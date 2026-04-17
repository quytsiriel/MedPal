from pydantic import BaseModel
from typing import Optional, List, Dict

class StartResponse(BaseModel):
    session_id: str
    status: str
    message: Optional[str] = "Xin chào, tôi là trợ lý y tế số MedPal. Bạn đang gặp vấn đề gì về sức khỏe?"
    stage: str = "collecting"

class ChatRequest(BaseModel):
    session_id: str
    message: str

class ChatResponse(BaseModel):
    reply: str
    emergency: Optional[bool] = False
    stage: str  # "collecting" | "clarifying" | "complete_visit" | "complete_no_visit"
    decision: Optional[str] = None  # "visit" | "no_visit"
    advice: Optional[str] = None  # Lời khuyên khi no_visit
    record: Optional[Dict] = None  # Hồ sơ JSON khi complete
    recommended_dept: Optional[str] = None  # Khoa đề nghị khi visit
    qr_code: Optional[str] = None
