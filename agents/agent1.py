from fastapi import APIRouter, HTTPException, Depends, Header
from models.schemas import StartResponse, ChatRequest, ChatResponse
import uuid
from datetime import datetime, timezone
import json
import os
from openai import OpenAI
from services.firebase import get_db

router = APIRouter(prefix="/agent1", tags=["Agent 1"]) # tạo router cho agent 1, cho tiền tố /agent1

# Các hàm dùng chung để quản lý session trên Firestore
def create_session(user_id: str) -> str:
    db = get_db()
    if not db:
        raise Exception("Firestore not initialized")
    
    session_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    
    session_data = {
        "session_id": session_id,
        "user_id": user_id,
        "status": "collecting",
        "symptoms": [],
        "conversation_history": [],
        "recommended_dept": None,
        "created_at": now,
        "updated_at": now
    }
    
    db.collection("sessions").document(session_id).set(session_data)
    return session_id

def get_session(session_id: str) -> dict:
    db = get_db()
    if not db:
        raise Exception("Firestore not initialized")
        
    doc = db.collection("sessions").document(session_id).get()
    if doc.exists:
        return doc.to_dict()
    return None

def update_session(session_id: str, data: dict):
    db = get_db()
    if not db:
        raise Exception("Firestore not initialized")
        
    data["updated_at"] = datetime.now(timezone.utc)
    db.collection("sessions").document(session_id).update(data)


# Hàm phụ trợ để giả lập việc kiểm tra token cho mục đích test
def get_user_id_from_token(authorization: str = Header(None)) -> str:
    if not authorization:
        # Cấp user_id mặc định nếu không truyền token khi test
        return "mock_user_123"
    
    # Thực tế sẽ dùng firebase_admin.auth.verify_id_token(token) để xác thực
    # Tạm thời trả về đoạn token giả làm user_id.
    token = authorization.replace("Bearer ", "")
    # Trả về một user_id mô phỏng dựa vào token truyền lên
    return f"user_from_token_{token}"

@router.post("/start", response_model=StartResponse)
def start_session(user_id: str = Depends(get_user_id_from_token)):
    try:
        session_id = create_session(user_id)
        return {"session_id": session_id, "status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/chat", response_model=ChatResponse)
def chat_with_agent1(request: ChatRequest):
    # 1. Load session từ Firestore
    session = get_session(request.session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # Nạp nội dung system prompt từ file
    prompt_path = os.path.join(os.path.dirname(__file__), "prompts", "agent1_system.txt")
    with open(prompt_path, "r", encoding="utf-8") as f:
        system_instruction = f.read()
        
    # Tạo nội dung gửi lên: Lịch sử trò chuyện + tin nhắn mới từ user
    history = session.get("conversation_history", [])
    messages = [{"role": "system", "content": system_instruction}]
    for item in history:
        messages.append({"role": item["role"], "content": item["content"]})
    messages.append({"role": "user", "content": request.message})
    
    # 2. Gọi Ollama qua chuẩn OpenAI-compatible API
    client = OpenAI(
        base_url=os.environ.get("OLLAMA_BASE_URL", "http://124.197.18.87:11434/v1"),
        api_key="ollama",  # Ollama không yêu cầu API key thật
    )
    try:
        response = client.chat.completions.create(
            model=os.environ.get("OLLAMA_MODEL", "puyangwang/medgemma-27b-it:q4_0"),
            messages=messages,
            temperature=0.3,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"LLM API error: {str(e)}")
        
    # 3. Parse JSON từ response của model
    raw_text = response.choices[0].message.content
    try:
        ai_data = json.loads(raw_text)
    except json.JSONDecodeError:
        # Nếu model không trả về JSON đúng chuẩn, wrap lại thành JSON hợp lệ
        ai_data = {"reply": raw_text, "emergency": False, "stage": "collecting"}
        
    reply_text = ai_data.get("reply", "Xin lỗi, tôi không hiểu bạn nói gì.")
    is_emergency = ai_data.get("emergency", False)
    stage = ai_data.get("stage", "collecting")
    recommended_dept = ai_data.get("recommended_dept")
    
    # Cập nhật lịch sử ở RAM (Memory)
    history.append({"role": "user", "content": request.message})
    history.append({"role": "assistant", "content": reply_text})
    
    # 4. Lưu trạng thái session mới nhất để đẩy lên DB
    update_data = {
        "conversation_history": history
    }
    
    if is_emergency:
        # Nếu là ca cấp cứu
        # (Ở đây có thể gọi hàm bắn thông báo, SMS, hoặc flag khẩn cấp trên hệ thống)
        update_data["emergency"] = True
        
    if stage == "complete":
        update_data["status"] = "completed"
        update_data["recommended_dept"] = recommended_dept
        
    # 5. Lưu lại xuống Firestore Database
    update_session(request.session_id, update_data)
    
    return ChatResponse(
        reply=reply_text,
        emergency=is_emergency,
        stage=stage
    )


