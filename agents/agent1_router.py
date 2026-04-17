from fastapi import APIRouter, HTTPException, Depends, Header
from models.schemas import StartResponse, ChatRequest, ChatResponse
import uuid
from datetime import datetime, timezone
import json
import os
import re
from openai import OpenAI
from services.firebase import get_db
from agents.agent1.rag import search

router = APIRouter(prefix="/agent1", tags=["Agent 1"])

# ── Metadata ───────────────────────────────────────
TASKS = [
    ("t21", "thời điểm và cách khởi phát triệu chứng"),
    ("t22", "vị trí, tính chất, mức độ triệu chứng"),
    ("t23", "diễn biến theo thời gian"),
    ("t24", "triệu chứng kèm theo"),
    ("t25", "đã khám hoặc dùng thuốc gì chưa"),
    ("t26", "tình trạng ăn ngủ, cân nặng gần đây"),
    ("t31", "bệnh mãn tính hoặc bệnh cũ"),
    ("t32", "tiêm chủng gần đây"),
    ("t33", "phẫu thuật hoặc chấn thương"),
    ("t34", "truyền máu"),
    ("t35", "dị ứng thuốc hoặc thực phẩm"),
]

MEDICAL_KEYWORDS = [
    "thuốc", "uống thuốc", "paracetamol", "ibuprofen", "kháng sinh",
    "tiêm", "xét nghiệm", "siêu âm", "chụp x-quang", "nhập viện",
    "phẫu thuật", "bác sĩ kê", "đơn thuốc", "liều", "mg",
    "viên", "chai", "kem bôi", "nhỏ mắt", "truyền dịch"
]

EMERGENCY_KEYWORDS = [
    "đau ngực", "tức ngực", "khó thở", "thở không được", "ngất", "ngất xỉu",
    "tim đập nhanh", "tim đập mạnh", "hồi hộp dữ dội",
    "liệt", "tê liệt", "mất ý thức", "co giật", "đột quỵ",
    "méo miệng", "nói không được", "nói khó", "mắt mờ đột ngột",
    "đau đầu dữ dội", "đau đầu đột ngột",
    "chảy máu không cầm", "nôn ra máu", "đi ngoài ra máu", "tiểu ra máu",
    "tai nạn", "ngã từ cao", "chấn thương đầu",
    "sưng họng", "sưng lưỡi", "không nuốt được", "phát ban toàn thân",
    "sốt cao", "sốt 39", "sốt 40", "ớn lạnh run", "mê sảng", "lú lẫn",
    "đau bụng dữ dội", "đau bụng không chịu được", "bụng cứng",
    "muốn chết", "tự tử", "tự làm đau"
]

EMERGENCY_MESSAGE = (
    "⚠️ Tôi nhận thấy bạn đang mô tả triệu chứng có thể nghiêm trọng.\n"
    "Vui lòng gọi ngay cấp cứu 115 hoặc đến phòng cấp cứu gần nhất.\n"
    "Không nên chờ đợi."
)

OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "puyangwang/medgemma-27b-it:q6")
PROMPT_PATH = os.path.join(os.path.dirname(__file__), "agent1", "prompt.txt")

# ── Helpers ────────────────────────────────────────
def get_next_task(task_scores):
    for tid, desc in TASKS:
        if task_scores.get(tid, 0.0) < 0.85:
            return tid, desc
    return None, None

def all_done(task_scores):
    return all(task_scores.get(tid, 0.0) >= 0.85 for tid, _ in TASKS)

def build_task_status(task_scores) -> str:
    lines = []
    for tid, desc in TASKS:
        score = task_scores.get(tid, 0.0)
        mark = "✓" if score >= 0.85 else ("~" if score >= 0.4 else "○")
        lines.append(f"  {mark} {tid} ({desc}): {score:.1f}")
    return "\n".join(lines)

def detect_emergency(text: str) -> bool:
    text_lower = text.lower()
    return any(kw in text_lower for kw in EMERGENCY_KEYWORDS)

def validate_advice(advice: str) -> str:
    if not advice:
        return ""
    advice_lower = advice.lower()
    for kw in MEDICAL_KEYWORDS:
        if kw in advice_lower:
            return ""
    return advice

def create_client():
    return OpenAI(
        base_url=os.environ.get("OLLAMA_BASE_URL", "http://124.197.18.120:11434/v1"),
        api_key="ollama"
    )

def score_tasks_from_history(history: list, task_scores: dict):
    if not history:
        return
    conversation_text = "\n".join(f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}" for m in history)
    task_list = "\n".join(f"- {tid}: {desc}" for tid, desc in TASKS)
    scoring_prompt = f"""Đây là đoạn hội thoại giữa trợ lý y tế và bệnh nhân:

{conversation_text}

Đánh giá mức độ đã khai thác được thông tin cho từng mục sau. Chỉ trả về JSON, không giải thích.
Thang điểm:
- 1.0: có thông tin rõ ràng, đầy đủ
- 0.5: có đề cập nhưng chưa rõ hoặc chưa đủ
- 0.0: chưa được hỏi hoặc chưa có thông tin

Danh sách mục:
{task_list}

Trả về đúng định dạng chuẩn:
{{"t21": 0.0, "t22": 0.0, "t23": 0.0, "t24": 0.0, "t25": 0.0, "t26": 0.0, "t31": 0.0, "t32": 0.0, "t33": 0.0, "t34": 0.0, "t35": 0.0}}"""
    try:
        response = create_client().chat.completions.create(model=OLLAMA_MODEL, messages=[{"role": "user", "content": scoring_prompt}], temperature=0)
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            scores = json.loads(match.group())
            for tid in task_scores:
                if tid in scores:
                    task_scores[tid] = float(scores[tid])
    except Exception as e:
        print(f"[WARN] Scoring failed: {e}")

def generate_record(history: list) -> str:
    conversation_text = "\n".join(f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}" for m in history)
    record_prompt = f"""Dựa trên đoạn hội thoại:

{conversation_text}

Hãy tạo hồ sơ tiền khám hoàn chỉnh. Chỉ dùng thông tin bệnh nhân đã nói. Mục nào chưa có ghi [chưa khai thác]. Nhưng bắt buộc phải ghi tên Khoa chính.

---
HỒ SƠ TIỀN KHÁM
---

KHOA ĐỀ NGHỊ:
  - Khoa chính: [tự xác định trên nhóm bệnh]
  - Chuyên khoa phụ: [nếu có]

LÝ DO KHÁM (CC):
  [1–2 câu tóm tắt]

LỊCH SỬ BỆNH HIỆN TẠI (HPI):
  - Khởi phát: [...]
  - Đặc điểm triệu chứng: [...]
  - Diễn biến: [...]
  - Triệu chứng kèm theo: [...]
  - Đã xử lý: [...]
  - Tình trạng chung: [...]

TIỀN SỬ (PH):
  - Bệnh cũ: [...]
  - Tiêm chủng: [...]
  - Phẫu thuật / Chấn thương: [...]
  - Truyền máu: [...]
  - Dị ứng: [...]

LỜI KHUYÊN SỨC KHỎE:
  [Chỉ gồm: nghỉ ngơi, uống nước, dinh dưỡng, theo dõi triệu chứng]
  [TUYỆT ĐỐI KHÔNG đề cập thuốc hoặc bất kỳ can thiệp y tế nào]
"""
    try:
        response = create_client().chat.completions.create(model=OLLAMA_MODEL, messages=[{"role": "user", "content": record_prompt}], temperature=0)
        return response.choices[0].message.content.strip()
    except Exception as e:
        return ""

def parse_record_to_json(record_text: str) -> dict:
    parse_prompt = f"""Đây là hồ sơ tiền khám dạng text:

{record_text}

Trích xuất thông tin và trả về JSON theo cấu trúc sau. Chỉ trả về JSON.
Nếu một trường không có thông tin → điền "[chưa khai thác]".
QUY TẮC loi_khuyen_suc_khoe: Chỉ giữ nội dung về nghỉ ngơi, uống nước, dinh dưỡng. Nếu vi phạm → "".

{{
  "khoa_de_nghi": {{ "khoa_chinh": "", "chuyen_khoa_phu": "" }},
  "ly_do_kham": "",
  "hpi": {{ "khoi_phat": "", "dac_diem_trieu_chung": "", "dien_bien": "", "trieu_chung_kem_theo": "", "da_xu_ly": "", "tinh_trang_chung": "" }},
  "ph": {{ "benh_cu": "", "tiem_chung": "", "phau_thuat_chan_thuong": "", "truyen_mau": "", "di_ung": "" }},
  "loi_khuyen_suc_khoe": ""
}}"""
    try:
        response = create_client().chat.completions.create(model=OLLAMA_MODEL, messages=[{"role": "user", "content": parse_prompt}], temperature=0)
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            obj = json.loads(match.group())
            if "loi_khuyen_suc_khoe" in obj:
                obj["loi_khuyen_suc_khoe"] = validate_advice(obj["loi_khuyen_suc_khoe"])
            return obj
    except Exception as e:
        pass
    return {}

# ── Session Management ─────────────────────────────
def create_session(user_id: str) -> str:
    db = get_db()
    if not db: raise Exception("Firestore not initialized")
    session_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    initial_msg = "Xin chào, tôi là trợ lý y tế MedPal. Bạn đang có dấu hiệu mệt mỏi hay khó chịu ở đâu, hãy chia sẻ để tôi hỗ trợ nhé?"
    
    session_data = {
        "session_id": session_id,
        "user_id": user_id,
        "status": "collecting",
        "symptoms_accumulated": [],
        "task_scores": {tid: 0.0 for tid, _ in TASKS},
        "is_first_turn": True,
        "conversation_history": [{"role": "assistant", "content": initial_msg}],
        "recommended_dept": None,
        "record": None,
        "emergency": False,
        "created_at": now,
        "updated_at": now
    }
    db.collection("sessions").document(session_id).set(session_data)
    return session_id

def get_session(session_id: str) -> dict:
    db = get_db()
    doc = db.collection("sessions").document(session_id).get()
    return doc.to_dict() if doc.exists else None

def update_session(session_id: str, data: dict):
    db = get_db()
    data["updated_at"] = datetime.now(timezone.utc)
    db.collection("sessions").document(session_id).update(data)

def get_user_id_from_token(authorization: str = Header(None)) -> str:
    if not authorization: return "mock_user_123"
    token = authorization.replace("Bearer ", "")
    return f"user_from_token_{token}"

# ── Endpoint Routes ────────────────────────────────
@router.post("/start", response_model=StartResponse)
def start_session(user_id: str = Depends(get_user_id_from_token)):
    try:
        session_id = create_session(user_id)
        initial_msg = "Xin chào, tôi là trợ lý y tế MedPal. Bạn đang có dấu hiệu mệt mỏi hay khó chịu ở đâu, hãy chia sẻ để tôi hỗ trợ nhé?"
        return {"session_id": session_id, "status": "ok", "message": initial_msg, "stage": "collecting"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/chat", response_model=ChatResponse)
def chat_with_agent1(request: ChatRequest):
    session = get_session(request.session_id)
    if not session: raise HTTPException(status_code=404, detail="Session not found")
    if session.get("status") == "completed" or session.get("emergency"):
        return ChatResponse(reply="Phiên khám này đã kết thúc.", emergency=session.get("emergency"), stage="complete")
        
    history = session.get("conversation_history", [])
    task_scores = session.get("task_scores", {tid: 0.0 for tid, _ in TASKS})
    symptoms = session.get("symptoms_accumulated", [])
    is_first_turn = session.get("is_first_turn", True)
    user_input = request.message.strip()
    
    # 1. EMERGENCY CHECK
    if detect_emergency(user_input):
        history.append({"role": "user", "content": user_input})
        history.append({"role": "assistant", "content": EMERGENCY_MESSAGE})
        update_session(request.session_id, {
            "conversation_history": history,
            "emergency": True,
            "status": "completed"
        })
        return ChatResponse(reply=EMERGENCY_MESSAGE, emergency=True, stage="complete")

    # 2. RAG & LLM
    symptoms.append(user_input)
    try:
        rag_query = " ".join(symptoms[-5:])
        context_lines = search(rag_query) if rag_query else []
        context = "\n".join(context_lines)
    except:
        context = "Chưa có dữ liệu nền."

    history.append({"role": "user", "content": user_input})

    if not is_first_turn:
        score_tasks_from_history(history, task_scores)
        
    # Check all_done
    if not is_first_turn and all_done(task_scores):
        record_text = generate_record(history)
        record_json = parse_record_to_json(record_text)
        dept = record_json.get("khoa_de_nghi", {}).get("khoa_chinh", "Đa khoa")
        
        reply_msg = f"Đã thu thập đủ thông tin. Hệ thống đề xuất chuyên khoa sơ bộ: {dept}."
        history.append({"role": "assistant", "content": reply_msg})
        
        update_session(request.session_id, {
            "conversation_history": history,
            "symptoms_accumulated": symptoms,
            "task_scores": task_scores,
            "is_first_turn": False,
            "status": "completed",
            "recommended_dept": dept,
            "record": record_json
        })
        return ChatResponse(reply=reply_msg, emergency=False, stage="complete")

    current_task_id, current_task_desc = get_next_task(task_scores)
    
    if is_first_turn:
        instruction = "Đây là lượt đầu tiên. Hỏi ngắn gọn đúng một câu về khởi phát và tình trạng bệnh để khai thác tiếp."
    else:
        task_status = build_task_status(task_scores)
        instruction = (
            f"TRẠNG THÁI NHIỆM VỤ:\n"
            f"{task_status}\n\n"
            f"Hỏi thêm về: '{current_task_desc}'. Chỉ hỏi ĐÚNG MỘT câu tự nhiên."
        )

    try:
        with open(PROMPT_PATH, "r", encoding="utf-8") as f:
            system_instruction = f.read()
    except:
        system_instruction = "Bạn là trợ lý y tế chuyên khai thác thông tin bệnh nhân."

    messages_to_send = [{"role": "system", "content": f"{system_instruction}\n\n---\nDỮ LIỆU THÔNG TIN Y KHOA (RAG TỪ TÀI LIỆU): \n{context}\n---"}]
    for msg in history[:-1]:  # Exclude last user input since we inject it with instruction
        messages_to_send.append({"role": msg["role"], "content": msg["content"]})
        
    messages_to_send.append({
        "role": "user",
        "content": f"{user_input}\n\n[LƯU Ý]\n{instruction}"
    })

    try:
        response = create_client().chat.completions.create(model=OLLAMA_MODEL, messages=messages_to_send, temperature=0.3)
        ai_reply = response.choices[0].message.content.strip()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    history.append({"role": "assistant", "content": ai_reply})
    
    update_session(request.session_id, {
        "conversation_history": history,
        "symptoms_accumulated": symptoms,
        "task_scores": task_scores,
        "is_first_turn": False
    })
    
    return ChatResponse(reply=ai_reply, emergency=False, stage="collecting")
