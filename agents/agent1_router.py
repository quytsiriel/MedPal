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
    ("t1", "Lý do khám chính (Triệu chứng nổi bật nhất)"),
    ("t2", "Vị trí, tính chất và mức độ triệu chứng"),
    ("t3", "Thời điểm khởi phát và diễn biến theo thời gian"),
    ("t4", "Triệu chứng kèm theo hoặc không kèm theo"),
    ("t5", "Đã xử lý hoặc dùng thuốc gì chưa"),
    ("t6", "Tiền sử bệnh lý (bệnh mãn tính, dị ứng)"),
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
        if msg["role"] == "assistant":
            content = msg["content"].replace("\n", " ")
            # Tách thành các câu dựa trên dấu kết thúc câu
            sentences = [s.strip() for s in re.split(r'(?<=[.!?])\s+', content) if s.strip()]
            asked.extend(sentences)
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


def filter_user_input(user_input: str, last_assistant_msg: str) -> dict:
    """
    Brain 2 (Model 4B): Filter tin nhắn người dùng.
    Trả về JSON:
    {
      "category": "on_topic" | "off_topic",
      "status": "đủ" | "thiếu", 
      "medical_related": true/false,
      "reply": "câu trả lời nếu off_topic hoặc thiếu thông tin",
      "processed_input": "thông tin hữu ích trích xuất được (nếu có)"
    }
    """
    try:
        prompt_brain2 = "Bạn là chuyên gia y tế và hệ thống phân loại. Bạn am hiểu và CÓ THỂ giải thích chi tiết các thuật ngữ y khoa. Trả về JSON duy nhất."
        
        filter_prompt = f"""Tin nhắn của bác sĩ (vừa hỏi): "{last_assistant_msg}"
Tin nhắn của bệnh nhân: "{user_input}"

Nhiệm vụ:
1. Xác định tin nhắn của bệnh nhân là "on_topic" (đang trả lời thông tin bác sĩ cần) hay "off_topic" (hỏi linh tinh, HOẶC hỏi giải thích thuật ngữ, ví dụ "X là gì?", "Tại sao?").
2. Nếu "on_topic", xác định "status" là "đủ" hay "thiếu". LƯU Ý QUAN TRỌNG: Nếu bác sĩ hỏi 2 ý, nhưng bệnh nhân chỉ trả lời 1 ý, HÃY COI LÀ "đủ" (để hệ thống khác tự hỏi tiếp). CHỈ xếp vào "thiếu" khi bệnh nhân HOÀN TOÀN lảng tránh, không cung cấp bất kỳ thông tin nào.
3. Nếu "thiếu", hãy sinh ra một câu hỏi nhắc nhở (vào trường 'reply'). TUYỆT ĐỐI KHÔNG BÊ NGUYÊN câu hỏi cũ để hỏi lại, hãy hỏi một cách ngắn gọn, tập trung vào ý bị thiếu.
4. Nếu "off_topic": BẠN LÀ TỪ ĐIỂN Y KHOA. Nếu bệnh nhân hỏi "X là gì?", bạn TUYỆT ĐỐI KHÔNG ĐƯỢC hỏi vặn lại hay bắt bệnh nhân tự miêu tả. Bạn PHẢI TỰ ĐƯA RA ĐỊNH NGHĨA rõ ràng cho X. Sau khi giải thích xong, BẮT BUỘC PHẢI nhắc lại nội dung của "Tin nhắn của bác sĩ (vừa hỏi)" để dẫn dắt bệnh nhân tiếp tục trả lời vấn đề chính.
5. Trích xuất các thông tin triệu chứng hữu ích vào 'processed_input' (nếu có).

Chỉ trả về định dạng JSON:
{{
  "category": "on_topic" | "off_topic",
  "status": "đủ" | "thiếu",
  "medical_related": true | false,
  "reply": "câu trả lời/hỏi lại của bạn",
  "processed_input": "các triệu chứng bệnh nhân đã cung cấp"
}}"""

        response = create_brain2_client().chat.completions.create(
            model=OLLAMA_MODEL_2,
            messages=[
                {"role": "system", "content": prompt_brain2},
                {"role": "user", "content": filter_prompt}
            ],
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            return json.loads(match.group())
    except Exception as e:
        print(f"[WARN] Brain 2 filter failed: {e}")
    
    # Fallback: coi là đủ
    return {"category": "on_topic", "status": "đủ", "medical_related": True, "reply": "", "processed_input": user_input}

def extract_patient_info(history: list) -> dict:
    """Brain 1 (Model 27B): Trích xuất 9 sub-fields từ lịch sử hội thoại."""
    if not history:
        return {}
    
    main_history = [m for m in history if not m.get("is_off_topic", False)]
    conversation_text = "\n".join(
        f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}" 
        for m in main_history
    )
    
    extraction_prompt = f"""Đây là đoạn hội thoại giữa trợ lý y tế và bệnh nhân:

{conversation_text}

Hãy trích xuất các thông tin y tế bệnh nhân ĐÃ CUNG CẤP vào JSON theo đúng các trường sau. 
LƯU Ý ĐẶC BIỆT 1: Tuyệt đối KHÔNG trích xuất các từ khóa nếu bệnh nhân chỉ đang hỏi định nghĩa (ví dụ: "Đau quặn là gì?"). Chỉ trích xuất khi bệnh nhân XÁC NHẬN họ có triệu chứng đó.
LƯU Ý ĐẶC BIỆT 2: Nếu bệnh nhân trả lời là "Không có", "Không" (ví dụ không bị dị ứng), PHẢI trích xuất chữ "Không có". Tuyệt đối KHÔNG ĐƯỢC để null. 
Chỉ để null khi thông tin CHƯA ĐƯỢC HỎI hoặc bệnh nhân không trả lời vào trọng tâm.

{{
  "t1_ly_do": "Lý do khám chính",
  "t2_vi_tri": "Vị trí đau/triệu chứng",
  "t2_tinh_chat": "Tính chất (âm ỉ, quặn, rát...)",
  "t2_muc_do": "Mức độ (nhẹ, vừa, dữ dội...)",
  "t3_khoi_phat": "Bị từ bao giờ",
  "t3_dien_bien": "Tiến triển (tăng lên, giảm đi...)",
  "t4_kem_theo": "Các triệu chứng khác",
  "t5_da_xu_ly": "Đã xử lý/uống thuốc gì",
  "t6_tien_su": "Bệnh nền, dị ứng"
}}

Chỉ trả về định dạng JSON, không giải thích."""

    try:
        response = create_brain1_client().chat.completions.create(
            model=OLLAMA_MODEL,
            messages=[
                {"role": "system", "content": "Bạn là chuyên gia phân tích hồ sơ bệnh án."},
                {"role": "user", "content": extraction_prompt}
            ],
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            return json.loads(match.group())
    except Exception as e:
        print(f"[WARN] Brain 1 extraction failed: {e}")
    return {}

def calculate_scores_from_extracted_info(info: dict) -> dict:
    scores = {}
    
    def is_filled(val):
        if not val: return False
        v = str(val).lower().strip()
        if v in ["", "null", "none", "không rõ", "chưa rõ", "chưa khai thác", "không có thông tin"]: return False
        return True

    scores["t1"] = 1.0 if is_filled(info.get("t1_ly_do")) else 0.0
    
    t2_fields = [info.get("t2_vi_tri"), info.get("t2_tinh_chat"), info.get("t2_muc_do")]
    scores["t2"] = sum(1 for f in t2_fields if is_filled(f)) / 3.0
    
    t3_fields = [info.get("t3_khoi_phat"), info.get("t3_dien_bien")]
    scores["t3"] = sum(1 for f in t3_fields if is_filled(f)) / 2.0
    
    scores["t4"] = 1.0 if is_filled(info.get("t4_kem_theo")) else 0.0
    scores["t5"] = 1.0 if is_filled(info.get("t5_da_xu_ly")) else 0.0
    scores["t6"] = 1.0 if is_filled(info.get("t6_tien_su")) else 0.0

    return scores

# ── Brain 1 Functions ──────────────────────────────

def generate_final_report(history: list) -> dict:
    """
    Brain 1 (Model 27B): Hợp nhất tổng hợp hồ sơ và đánh giá đi khám vào 1 JSON duy nhất.
    """
    main_history = [m for m in history if not m.get("is_off_topic", False)]
    conversation_text = "\n".join(
        f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}" 
        for m in main_history
    )
    
    prompt = f"""Dựa trên đoạn hội thoại:

{conversation_text}

Nhiệm vụ 1: Tổng hợp hồ sơ tiền khám dựa trên thông tin bệnh nhân đã nói.
Nhiệm vụ 2: Đưa ra câu chốt lại (closing statement) khuyên bệnh nhân đi khám.
Yêu cầu cho câu chốt lại:
- KHÔNG ĐƯỢC chẩn đoán bệnh cụ thể (không được nói "bạn bị bệnh X").
- Chỉ đưa ra sự tương quan giữa triệu chứng/vị trí với các vùng/hệ cơ quan nhạy cảm nếu có.
- Yêu cầu bệnh nhân cần được bác sĩ thăm khám (có thể ngay lập tức hoặc sắp xếp thời gian, tuỳ mức độ) để loại trừ các tình trạng rủi ro.
Ví dụ: "Vị trí đau của bạn trùng khớp với khu vực ruột thừa. Do tính chất nhạy cảm của vùng này, bạn cần được bác sĩ kiểm tra ngay lập tức để loại trừ các tình trạng khẩn cấp."
- KHÔNG đưa ra lời khuyên chăm sóc tại nhà, kiêng cữ hay đơn thuốc.

Trả về kết quả DƯỚI DẠNG JSON duy nhất tuân thủ CHÍNH XÁC cấu trúc sau:
{{
  "visitDate": "serverTimestamp",
  "patientProfile": {{
    "patientInfo": {{ "age": null, "sex": null, "weightKg": null }},
    "chiefComplaint": "Lý do khám chính",
    "symptomSummary": {{
      "mainSymptom": "",
      "location": "",
      "duration": "",
      "severity": null,
      "description": "",
      "associatedSymptoms": ["triệu chứng 1", "triệu chứng 2"],
      "deniedSymptoms": ["triệu chứng phủ nhận 1"]
    }},
    "medicalBackground": {{
      "chronicDiseases": [],
      "allergies": [],
      "currentMedications": [],
      "previousSimilarSymptoms": ""
    }},
    "redFlags": {{
      "hasRedFlags": false,
      "details": []
    }}
  }},
  "closingStatement": {{
    "message": "Câu chốt lại theo yêu cầu trên",
    "disclaimer": "Lưu ý: Thông tin này chỉ mang tính tham khảo, không thay thế tư vấn, chẩn đoán y khoa chính thức từ bác sĩ."
  }}
}}
"""
    try:
        response = create_brain1_client().chat.completions.create(
            model=OLLAMA_MODEL, 
            messages=[{"role": "user", "content": prompt}], 
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            return json.loads(match.group())
    except Exception as e:
        print(f"[WARN] Brain 1 generate_final_report failed: {e}")
    
    # Fallback structure
    return {
      "visitDate": "serverTimestamp",
      "patientProfile": {"patientInfo": {"age": None, "sex": None, "weightKg": None}, "chiefComplaint": "Không rõ", "symptomSummary": {}, "medicalBackground": {}, "redFlags": {"hasRedFlags": False, "details": []}},
      "closingStatement": {"message": "Dựa trên các triệu chứng bạn cung cấp, bạn nên được bác sĩ kiểm tra để loại trừ các rủi ro sức khỏe.", "disclaimer": "Lưu ý: Thông tin này chỉ mang tính tham khảo, không thay thế tư vấn, chẩn đoán y khoa chính thức từ bác sĩ."}
    }

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
        "extracted_info": {},
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

    # ─── STEP 2: BRAIN 2 — FILTER USER INPUT ─────
    last_assistant_msg = ""
    for msg in reversed(history):
        if msg["role"] == "assistant":
            last_assistant_msg = msg["content"]
            break
    
    filter_result = filter_user_input(user_input, last_assistant_msg)
    category = filter_result.get("category", "on_topic")
    status = filter_result.get("status", "đủ")
    reply_msg = filter_result.get("reply", "Xin lỗi, tôi chưa rõ ý bạn. Bạn có thể nói rõ hơn không?")
    
    if category == "off_topic" or status == "thiếu":
        if status == "thiếu":
            missing_info_count = session.get("missing_info_count", 0) + 1
            if missing_info_count >= 3:
                # Đã hỏi 3 lần không được -> bỏ qua coi như đủ
                update_session(request.session_id, {"missing_info_count": 0})
            else:
                history.append({"role": "user", "content": user_input, "is_off_topic": True})
                history.append({"role": "assistant", "content": reply_msg, "is_off_topic": True})
                update_session(request.session_id, {
                    "conversation_history": history,
                    "missing_info_count": missing_info_count
                })
                return ChatResponse(reply=reply_msg, emergency=False, stage="clarifying", transcript=transcript)
        else:
            # Off topic
            history.append({"role": "user", "content": user_input, "is_off_topic": True})
            history.append({"role": "assistant", "content": reply_msg, "is_off_topic": True})
            update_session(request.session_id, {"conversation_history": history})
            return ChatResponse(reply=reply_msg, emergency=False, stage="clarifying", transcript=transcript)

    # ─── STEP 3: BRAIN 1 — SCORING ─────────────────
    update_session(request.session_id, {"missing_info_count": 0})
    processed_input = filter_result.get("processed_input", user_input)
    if processed_input and processed_input not in symptoms:
        symptoms.append(processed_input)
    
    history.append({"role": "user", "content": processed_input})

    extracted_info = session.get("extracted_info", {})
    turn_count = len(symptoms)
    
    if not is_first_turn:
        new_extracted = extract_patient_info(history)
        if new_extracted:
            for k, v in new_extracted.items():
                if v: extracted_info[k] = v
        
        scores = calculate_scores_from_extracted_info(extracted_info)
        for tid in task_scores:
            if tid in scores:
                task_scores[tid] = float(scores[tid])
        
    # Tính threshold linh hoạt theo số lượt đã trôi qua. Bắt đầu từ 0.7, giảm dần.
    dynamic_threshold = max(0.2, 0.7 - (turn_count * 0.05))
    
    # ─── STEP 4: CHECK ALL DONE ────────────────────
    if not is_first_turn and all_done(task_scores, dynamic_threshold):
        # Brain 1: Tổng hợp hồ sơ & Quyết định
        final_report = generate_final_report(history)
        
        statement = final_report.get("closingStatement", {})
        advice = f"{statement.get('message', 'Dựa trên các triệu chứng bạn cung cấp, bạn nên được bác sĩ kiểm tra để loại trừ các rủi ro sức khỏe.')}\n\n{statement.get('disclaimer', '')}".strip()
        
        decision = "visit"
        stage = "complete_visit"
        reply_msg = advice
        
        history.append({"role": "assistant", "content": reply_msg})
        
        update_session(request.session_id, {
            "conversation_history": history,
            "symptoms_accumulated": symptoms,
            "task_scores": task_scores,
            "extracted_info": extracted_info,
            "is_first_turn": False,
            "status": "completed",
            "decision": decision,
            "record": final_report,
            "advice": advice
        })
        
        return ChatResponse(
            reply=reply_msg, 
            emergency=False, 
            stage=stage,
            decision=decision,
            advice=advice,
            record=final_report,
            transcript=transcript
        )

    # ─── STEP 5: BRAIN 1 — GENERATE NEXT QUESTION ──
    current_task_id, current_task_desc = get_next_task(task_scores, dynamic_threshold, preferred_task=None)
    
    # Xây danh sách câu hỏi đã hỏi để chống trùng lặp
    asked_topics = build_asked_topics(history)
    
    if is_first_turn:
        instruction = "Đây là lượt đầu tiên. Hỏi ngắn gọn đúng một câu về khởi phát và tình trạng bệnh để khai thác tiếp."
    else:
        task_status = build_task_status(task_scores)
        anti_dup = ""
        if asked_topics:
            anti_dup = f"\n\nCÁC CÂU HỎI ĐÃ HỎI (TUYỆT ĐỐI KHÔNG HỎI LẠI Ý TƯƠNG TỰ):\n{asked_topics}"
        
        # Lấy thông tin đã biết để LLM không hỏi lại
        known_info = "\n".join(f"- {k}: {v}" for k, v in extracted_info.items() if v)
        if known_info:
            known_info = f"\nTHÔNG TIN ĐÃ BIẾT (TUYỆT ĐỐI KHÔNG HỎI LẠI CÁC Ý NÀY):\n{known_info}\n"
        
        instruction = (
            f"TRẠNG THÁI NHIỆM VỤ:\n"
            f"{task_status}\n\n"
            f"{known_info}"
            f"Nhiệm vụ: Hỏi thêm về '{current_task_desc}'.\n"
            f"YÊU CẦU BẮT BUỘC:\n"
            f"1. Chỉ hỏi ĐÚNG MỘT câu tự nhiên, ngắn gọn.\n"
            f"2. KHÔNG hỏi lại những thông tin đã biết.\n"
            f"3. KIỂM TRA KỸ DANH SÁCH ĐÃ HỎI. TUYỆT ĐỐI KHÔNG HỎI LẠI NHỮNG GÌ ĐÃ HỎI HOẶC TƯƠNG TỰ. Nếu đã hỏi rồi mà chưa có thông tin, bắt buộc phải hỏi sang khía cạnh khác của vấn đề."
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
        if not msg.get("is_off_topic", False):
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
        "extracted_info": extracted_info,
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
