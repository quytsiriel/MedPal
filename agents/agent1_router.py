import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

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
from services.whisper import transcribe_audio_base64

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

# ── Model Config ───────────────────────────────────
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "puyangwang/medgemma-27b-it:q4_0")
OLLAMA_MODEL_2 = os.environ.get("OLLAMA_MODEL_2", "puyangwang/medgemma-27b-it:q4_0")

PROMPT_PATH = os.path.join(os.path.dirname(__file__), "agent1", "prompt.txt")
PROMPT_BRAIN2_PATH = os.path.join(os.path.dirname(__file__), "agent1", "prompt_brain2.txt")

# ── Dual-Brain Clients ─────────────────────────────
def create_brain1_client():
    """Brain 1 (Port 11434): RAG + Hội thoại + Tạo hồ sơ + Quyết định"""
    return OpenAI(
        base_url=os.environ.get("OLLAMA_BASE_URL", "http://124.197.18.208:11434/v1"),
        api_key="ollama"
    )

def create_brain2_client():
    """Brain 2 (Port 11435): Scoring + Phân loại câu hỏi + Giải thích"""
    return OpenAI(
        base_url=os.environ.get("OLLAMA_BASE_URL_2", "http://124.197.18.220:11435/v1"),
        api_key="ollama"
    )

# ── Helpers ────────────────────────────────────────
def get_next_task(task_scores, threshold=0.85, preferred_task=None):
    """Trả về task tiếp theo cần hỏi. Ưu tiên preferred_task nếu hợp lệ."""
    task_dict = dict(TASKS)
    # Ưu tiên task do Brain 2 đề xuất (đã được chọn theo information gain)
    if preferred_task and preferred_task in task_dict:
        if task_scores.get(preferred_task, 0.0) < threshold:
            return preferred_task, task_dict[preferred_task]
    # Fallback: quay về duyệt tuần tự
    for tid, desc in TASKS:
        if task_scores.get(tid, 0.0) < threshold:
            return tid, desc
    return None, None

def all_done(task_scores, threshold=0.85):
    return all(task_scores.get(tid, 0.0) >= threshold for tid, _ in TASKS)

def build_task_status(task_scores) -> str:
    lines = []
    for tid, desc in TASKS:
        score = task_scores.get(tid, 0.0)
        mark = "✓" if score >= 0.85 else ("~" if score >= 0.4 else "○")
        lines.append(f"  {mark} {tid} ({desc}): {score:.1f}")
    return "\n".join(lines)

def build_asked_topics(history: list) -> str:
    """Trích xuất danh sách các chủ đề AI đã hỏi để tránh lặp."""
    asked = []
    for msg in history:
        if msg["role"] == "assistant" and "?" in msg["content"]:
            # Lấy câu hỏi từ tin nhắn AI
            content = msg["content"]
            # Trích xuất câu chứa dấu ?
            for sentence in content.replace("\n", " ").split("."):
                if "?" in sentence:
                    asked.append(sentence.strip())
    return "\n".join(f"  - {q}" for q in asked[-10:])  # Giữ tối đa 10 câu gần nhất

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

# ── Brain 2 Functions ──────────────────────────────

# Các chuỗi đầu câu cho thấy AI đang viết chain-of-thought thay vì giải thích
_THINKING_PREFIXES = [
    "người dùng đang hỏi",
    "bệnh nhân đang hỏi",
    "bệnh nhân muốn biết",
    "người dùng muốn biết",
    "họ muốn hiểu",
    "họ chưa hiểu",
    "câu hỏi này đề cập",
    "người dùng cần",
    "bệnh nhân cần được",
    "thuật ngữ được hỏi",
]

def _strip_thinking(explanation: str) -> str:
    """Phát hiện và loại bỏ chain-of-thought trong explanation của Brain 2."""
    if not explanation:
        return explanation
    low = explanation.lower()
    # Nếu câu đầu tiên là suy nghĩ nội tâm, tìm câu thức sự sau đó
    for prefix in _THINKING_PREFIXES:
        if low.startswith(prefix):
            # Tìm dấu "." hoặc "\n" đầu tiên — phần sau đó mới là giải thích thật
            for sep in ["\n\n", "\n", ". "]:
                idx = explanation.find(sep)
                if idx != -1:
                    rest = explanation[idx:].lstrip(".\n ")
                    if len(rest) > 20:  # Có nội dung thủc sự
                        return rest
            return explanation  # Không tách được, giữ nguyên
    return explanation


def classify_user_input(user_input: str, last_assistant_msg: str) -> dict:
    """
    Brain 2: Phân loại tin nhắn người dùng.
    - "answer": Câu trả lời bình thường → chuyển cho Brain 1
    - "question": Câu hỏi ngoài lề → Brain 2 giải thích, trả stage="clarifying"
    """
    try:
        prompt_brain2 = ""
        try:
            with open(PROMPT_BRAIN2_PATH, "r", encoding="utf-8") as f:
                prompt_brain2 = f.read()
        except:
            prompt_brain2 = "Bạn là evaluator y tế. Phân loại tin nhắn người dùng."

        classify_prompt = f"""Tin nhắn cuối của trợ lý: "{last_assistant_msg}"

Tin nhắn người dùng: "{user_input}"

Nhiệm vụ: Phân loại tin nhắn người dùng và trả về JSON duy nhất.
Lưu ý quan trọ ng: Nếu là câu hỏi, trường 'explanation' phải là lời giải thích TRỰC TIẼP cho bệnh nhân.
KHÔNG được viết: 'Người dùng đang hỏi...' hay 'Bệnh nhân muốn biết...'"""

        response = create_brain2_client().chat.completions.create(
            model=OLLAMA_MODEL_2,
            messages=[
                {"role": "system", "content": prompt_brain2},
                {"role": "user", "content": classify_prompt}
            ],
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            result = json.loads(match.group())
            if "type" in result:
                # Lọc chain-of-thought nếu lỏ bị rò
                if result.get("type") == "question" and result.get("explanation"):
                    result["explanation"] = _strip_thinking(result["explanation"])
                return result
    except Exception as e:
        print(f"[WARN] Brain 2 classify failed: {e}")
    
    # Fallback: coi là câu trả lời bình thường
    return {"type": "answer", "processed_input": user_input}


def score_tasks_from_history(history: list, task_scores: dict) -> tuple:
    """Brain 2: Chấm điểm 11 tasks. Trả về (is_sufficient, next_best_task)."""
    if not history:
        return (False, None)
    
    conversation_text = "\n".join(
        f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}" 
        for m in history
    )
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
{{"t21": 0.0, "t22": 0.0, "t23": 0.0, "t24": 0.0, "t25": 0.0, "t26": 0.0, "t31": 0.0, "t32": 0.0, "t33": 0.0, "t34": 0.0, "t35": 0.0, "is_sufficient": false, "next_best_task": "t22"}}"""
    
    try:
        prompt_brain2 = ""
        try:
            with open(PROMPT_BRAIN2_PATH, "r", encoding="utf-8") as f:
                prompt_brain2 = f.read()
        except:
            prompt_brain2 = "Bạn là evaluator y tế."

        response = create_brain2_client().chat.completions.create(
            model=OLLAMA_MODEL_2,
            messages=[
                {"role": "system", "content": prompt_brain2},
                {"role": "user", "content": scoring_prompt}
            ],
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            scores = json.loads(match.group())
            for tid in task_scores:
                if tid in scores:
                    task_scores[tid] = float(scores[tid])
            is_sufficient = scores.get("is_sufficient", False)
            next_best = scores.get("next_best_task", None)
            return (is_sufficient, next_best)
    except Exception as e:
        print(f"[WARN] Brain 2 scoring failed: {e}")
    return (False, None)

# ── Brain 1 Functions ──────────────────────────────

def generate_record(history: list) -> str:
    """Brain 1: Tổng hợp hồ sơ tiền khám từ lịch sử hội thoại."""
    conversation_text = "\n".join(
        f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}" 
        for m in history
    )
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
        response = create_brain1_client().chat.completions.create(
            model=OLLAMA_MODEL, 
            messages=[{"role": "user", "content": record_prompt}], 
            temperature=0
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"[WARN] Brain 1 generate_record failed: {e}")
        return ""

def parse_record_to_json(record_text: str) -> dict:
    """Brain 1: Trích xuất JSON từ hồ sơ text."""
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
        response = create_brain1_client().chat.completions.create(
            model=OLLAMA_MODEL, 
            messages=[{"role": "user", "content": parse_prompt}], 
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            obj = json.loads(match.group())
            if "loi_khuyen_suc_khoe" in obj:
                obj["loi_khuyen_suc_khoe"] = validate_advice(obj["loi_khuyen_suc_khoe"])
            return obj
    except Exception as e:
        print(f"[WARN] Brain 1 parse_record failed: {e}")
    return {}

def decide_visit(record_json: dict, history: list) -> dict:
    """
    Brain 1: Quyết định bệnh nhân có nên đi khám hay không.
    Returns: { "decision": "visit"|"no_visit", "reason": "...", "department": "...", "advice": "...", "self_care_tips": {...} }
    """
    conversation_text = "\n".join(
        f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}" 
        for m in history
    )
    
    decision_prompt = f"""Dựa trên hồ sơ tiền khám JSON và hội thoại, hãy quyết định bệnh nhân có nên đi khám bác sĩ không.

HỒ SƠ JSON:
{json.dumps(record_json, ensure_ascii=False, indent=2)}

HỘI THOẠI:
{conversation_text}

QUY TẮC:
- NÊN ĐI KHÁM nếu có BẤT KỲ dấu hiệu: triệu chứng kéo dài >7 ngày, đau dữ dội, sốt cao >3 ngày, triệu chứng thần kinh, khó thở, có bệnh nền, ảnh hưởng nghiêm trọng sinh hoạt
- KHÔNG CẦN ĐI KHÁM nếu TẤT CẢ: triệu chứng nhẹ <3 ngày, không sốt/sốt nhẹ, sinh hoạt bình thường, không bệnh nền, triệu chứng phổ biến tự giới hạn

Nếu quyết định là "no_visit", hãy tạo self_care_tips chi tiết, cụ thể cho BệNH NÀY (không chung chung).
Ví dụ nếu bị ho: avoid gồm "Uống đồ lạnh và đá", "Ăn đồ chiên xào nhiều dầu mỡ"...
TUYỆT ĐỐI KHÔNG đề cập thuốc trong bất kỳ trường nào.

Trả về JSON duy nhất (không giải thích thêm):
{{
  "decision": "visit hoặc no_visit",
  "reason": "lý do ngắn gọn",
  "department": "tên khoa nếu visit, rỗng nếu no_visit",
  "advice": "tóm tắt lời khuyên 1-2 câu nếu no_visit, rỗng nếu visit",
  "self_care_tips": {{
    "avoid": ["Điều nên kiêng 1", "Điều nên kiêng 2", "Điều nên kiêng 3"],
    "do": ["Nên làm 1", "Nên làm 2", "Nên làm 3"],
    "when_to_see_doctor": "Mô tả dấu hiệu cụ thể khi nào cần đi khám ngay"
  }}
}}
Nếu quyết định là "visit", để self_care_tips là null."""
    
    try:
        response = create_brain1_client().chat.completions.create(
            model=OLLAMA_MODEL, 
            messages=[{"role": "user", "content": decision_prompt}], 
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            result = json.loads(match.group())
            # Validate advice (không chứa thuốc)
            if result.get("advice"):
                result["advice"] = validate_advice(result["advice"])
            # Validate self_care_tips items
            if result.get("self_care_tips"):
                tips = result["self_care_tips"]
                tips["avoid"] = [validate_advice(x) or x for x in tips.get("avoid", []) if x]
                tips["do"] = [validate_advice(x) or x for x in tips.get("do", []) if x]
            return result
    except Exception as e:
        print(f"[WARN] Brain 1 decide_visit failed: {e}")
    
    # Fallback: an toàn → khuyen đi khám
    dept = record_json.get("khoa_de_nghi", {}).get("khoa_chinh", "Đa khoa")
    return {"decision": "visit", "reason": "Không thể đánh giá tự động", "department": dept, "advice": "", "self_care_tips": None}

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
        "decision": None,
        "advice": None,
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
    if not session: 
        raise HTTPException(status_code=404, detail="Session not found")
    if session.get("status") == "completed" or session.get("emergency"):
        return ChatResponse(
            reply="Phiên khám này đã kết thúc.", 
            emergency=session.get("emergency"), 
            stage="complete_visit" if session.get("decision") == "visit" else "complete_no_visit"
        )
        
    history = session.get("conversation_history", [])
    task_scores = session.get("task_scores", {tid: 0.0 for tid, _ in TASKS})
    symptoms = session.get("symptoms_accumulated", [])
    is_first_turn = session.get("is_first_turn", True)
    
    # ─── VOICE INPUT: Speech-to-Text ────────────────
    transcript = None
    if request.voice_base64:
        try:
            print(f"[STT] Received voice_base64, length: {len(request.voice_base64)}")
            transcript = transcribe_audio_base64(request.voice_base64)
            user_input = transcript
            print(f"[STT] Transcription successful: {transcript}")
        except Exception as e:
            print(f"[STT] Transcription failed: {e}")
            return ChatResponse(
                reply=f"Không thể nhận dạng giọng nói. Vui lòng thử lại hoặc nhập bằng văn bản.\n\n(Chi tiết: {e})",
                emergency=False,
                stage="collecting",
                transcript=None
            )
    elif request.message:
        user_input = request.message.strip()
    else:
        raise HTTPException(status_code=400, detail="Thiếu message hoặc voice_base64")
    
    # ─── STEP 1: EMERGENCY CHECK ────────────────────
    if detect_emergency(user_input):
        history.append({"role": "user", "content": user_input})
        history.append({"role": "assistant", "content": EMERGENCY_MESSAGE})
        update_session(request.session_id, {
            "conversation_history": history,
            "emergency": True,
            "status": "completed"
        })
        return ChatResponse(reply=EMERGENCY_MESSAGE, emergency=True, stage="complete_visit", transcript=transcript)

    # ─── STEP 2: BRAIN 2 — CLASSIFY USER INPUT ─────
    last_assistant_msg = ""
    for msg in reversed(history):
        if msg["role"] == "assistant":
            last_assistant_msg = msg["content"]
            break
    
    classification = classify_user_input(user_input, last_assistant_msg)
    
    if classification.get("type") == "question":
        # Người dùng hỏi ngoài lề (vd: "chuột rút bụng là gì?")
        explanation = classification.get("explanation", "Xin lỗi, tôi chưa thể giải thích rõ.")
        follow_up = classification.get("follow_up", "")
        
        clarify_reply = explanation
        if follow_up:
            clarify_reply += f"\n\n{follow_up}"
        
        history.append({"role": "user", "content": user_input})
        history.append({"role": "assistant", "content": clarify_reply})
        
        update_session(request.session_id, {
            "conversation_history": history,
        })
        return ChatResponse(reply=clarify_reply, emergency=False, stage="clarifying", transcript=transcript)

    # ─── STEP 3: BRAIN 2 — SCORING ─────────────────
    # Lấy processed_input từ Brain 2 (có thể đã được xử lý/rút gọn)
    processed_input = classification.get("processed_input", user_input)
    
    # Trích xuất facts rời rạc từ Brain 2 (xử lý câu trả lời lan man)
    extracted_facts = classification.get("extracted_facts", [])
    if extracted_facts:
        # Thêm từng fact riêng lẻ vào symptoms để RAG và scoring chính xác hơn
        for fact in extracted_facts:
            if fact and fact not in symptoms:
                symptoms.append(fact)
        print(f"[INFO] Extracted facts: {extracted_facts}")
    else:
        symptoms.append(processed_input)
    
    history.append({"role": "user", "content": processed_input})

    is_sufficient = False
    next_best_task = None
    turn_count = len(symptoms)
    
    if not is_first_turn:
        is_sufficient, next_best_task = score_tasks_from_history(history, task_scores)
        
    # Tính threshold linh hoạt theo số lượt đã trôi qua
    # Mỗi lượt giảm 0.08 điểm -> dễ thỏa mãn hơn. Vd: lượt 5 threshold chỉ còn ~0.45
    dynamic_threshold = max(0.3, 0.85 - (turn_count * 0.08))
    
    # Hard stop: Nếu đã hỏi tới câu thứ 8 (coi như quá dài), ép buộc chốt luôn
    if turn_count >= 8:
        is_sufficient = True
        dynamic_threshold = 0.0
        
    # ─── STEP 4: CHECK ALL DONE ────────────────────
    if not is_first_turn and (is_sufficient or all_done(task_scores, dynamic_threshold)):
        # Brain 1: Tổng hợp hồ sơ
        record_text = generate_record(history)
        record_json = parse_record_to_json(record_text)
        
        # Brain 1: Quyết định đi khám
        visit_decision = decide_visit(record_json, history)
        decision = visit_decision.get("decision", "visit")
        dept = visit_decision.get("department", record_json.get("khoa_de_nghi", {}).get("khoa_chinh", "Đa khoa"))
        advice = visit_decision.get("advice", "")
        reason = visit_decision.get("reason", "")
        self_care_tips = visit_decision.get("self_care_tips", None)
        
        if decision == "visit":
            reply_msg = (
                f"Đã thu thập đủ thông tin. Dựa trên các triệu chứng của bạn, "
                f"tôi khuyến nghị bạn nên đi khám bác sĩ.\n\n"
                f"📋 Lý do: {reason}\n"
                f"🏥 Chuyên khoa đề xuất: {dept}\n\n"
                f"Hệ thống sẽ giúp bạn tìm bệnh viện phù hợp gần nhất."
            )
            stage = "complete_visit"
        else:
            reply_msg = (
                f"Đã thu thập đủ thông tin. Dựa trên các triệu chứng hiện tại, "
                f"bạn có thể tự chăm sóc tại nhà.\n\n"
                f"📋 Đánh giá: {reason}\n\n"
                f"💡 Lời khuyên:\n{advice if advice else 'Nghỉ ngơi đầy đủ, uống nhiều nước, theo dõi triệu chứng.'}\n\n"
                f"⚠️ Nếu triệu chứng nặng hơn, hãy đến gặp bác sĩ ngay."
            )
            stage = "complete_no_visit"
        
        history.append({"role": "assistant", "content": reply_msg})
        
        update_session(request.session_id, {
            "conversation_history": history,
            "symptoms_accumulated": symptoms,
            "task_scores": task_scores,
            "is_first_turn": False,
            "status": "completed",
            "decision": decision,
            "recommended_dept": dept if decision == "visit" else None,
            "record": record_json,
            "advice": advice if decision == "no_visit" else None,
            "self_care_tips": self_care_tips if decision == "no_visit" else None
        })
        
        return ChatResponse(
            reply=reply_msg, 
            emergency=False, 
            stage=stage,
            decision=decision,
            advice=advice if decision == "no_visit" else None,
            self_care_tips=self_care_tips if decision == "no_visit" else None,
            record=record_json,
            recommended_dept=dept if decision == "visit" else None,
            transcript=transcript
        )

    # ─── STEP 5: BRAIN 1 — GENERATE NEXT QUESTION ──
    current_task_id, current_task_desc = get_next_task(task_scores, dynamic_threshold, preferred_task=next_best_task)
    
    # Xây danh sách câu hỏi đã hỏi để chống trùng lặp
    asked_topics = build_asked_topics(history)
    
    if is_first_turn:
        instruction = "Đây là lượt đầu tiên. Hỏi ngắn gọn đúng một câu về khởi phát và tình trạng bệnh để khai thác tiếp."
    else:
        task_status = build_task_status(task_scores)
        anti_dup = ""
        if asked_topics:
            anti_dup = f"\n\nCÁC CÂU HỎI ĐÃ HỎI (TUYỆT ĐỐI KHÔNG HỎI LẠI Ý TƯƠNG TỰ):\n{asked_topics}"
        
        instruction = (
            f"TRẠNG THÁI NHIỆM VỤ:\n"
            f"{task_status}\n\n"
            f"Hỏi thêm về: '{current_task_desc}'. "
            f"Chỉ hỏi ĐÚNG MỘT câu tự nhiên, ngắn gọn.\n"
            f"TUYỆT ĐỐI KHÔNG hỏi lại thông tin bệnh nhân đã cung cấp."
            f"{anti_dup}"
        )

    # RAG Search
    try:
        rag_query = " ".join(symptoms[-5:])
        context_lines = search(rag_query) if rag_query else []
        context = "\n".join(context_lines)
    except:
        context = "Chưa có dữ liệu nền."

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
        "content": f"{processed_input}\n\n[LƯU Ý]\n{instruction}"
    })

    try:
        response = create_brain1_client().chat.completions.create(
            model=OLLAMA_MODEL,
            messages=messages_to_send, 
            temperature=0.3
        )
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
    
    return ChatResponse(reply=ai_reply, emergency=False, stage="collecting", transcript=transcript)

@router.post("/transcribe")
def transcribe_only(request: ChatRequest):
    if not request.voice_base64:
        raise HTTPException(status_code=400, detail="Missing voice_base64")
    try:
        transcript = transcribe_audio_base64(request.voice_base64)
        return {"transcript": transcript}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    print("✅ Module agents.agent1_router loaded successfully!")
    print("💡 To run the API server, please use the command: python -m uvicorn main:app --reload")
