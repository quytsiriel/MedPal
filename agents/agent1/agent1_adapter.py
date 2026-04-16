from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
import sys
import os

# Ensure we can import from the agent1 directory
AGENT1_DIR = os.path.dirname(__file__)
if AGENT1_DIR not in sys.path:
    sys.path.append(AGENT1_DIR)

import agent1  # This is your original agent1.py

router = APIRouter(prefix="/agent1", tags=["Agent 1 - Symptom Collection"])

# --- Models ---

class ChatRequest(BaseModel):
    session_id: str
    message: Optional[str] = None
    voice_base64: Optional[str] = None

class ChatResponse(BaseModel):
    reply: str
    stage: str
    qr_code: Optional[str] = None

class StartResponse(BaseModel):
    session_id: str
    message: str
    stage: str

# --- Simple Session Manager (In-memory) ---
# NOTE: Your agent1.py uses global variables like `conversation_history`.
# For a real multi-user app, these should be moved into session objects.
# For the hackathon, we will use a single global session for simplicity OR 
# try to wrap it if possible without modifying your code.

sessions = {}

@router.post("/start", response_model=StartResponse)
async def start_session():
    session_id = str(uuid.uuid4())
    
    # Reset original agent1 globals for this "pretend" session
    agent1.conversation_history = []
    agent1.symptoms_accumulated = []
    agent1.task_scores = {tid: 0.0 for tid, _ in agent1.TASKS}
    agent1.is_first_turn = True
    
    return {
        "session_id": session_id,
        "message": "Chào bạn, tôi là bác sĩ trợ lý MedPal. Bạn vui lòng miêu tả triệu chứng nhé.",
        "stage": "init"
    }

@router.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    if not req.message:
        raise HTTPException(status_code=400, detail="Missing message")

    user_input = req.message.strip()
    
    # ── EMERGENCY CHECK ──────
    if agent1.detect_emergency(user_input):
        agent1.conversation_history.append({"role": "user", "content": user_input})
        agent1.conversation_history.append({"role": "assistant", "content": agent1.EMERGENCY_MESSAGE})
        return {
            "reply": agent1.EMERGENCY_MESSAGE,
            "stage": "emergency"
        }

    # ── Normal Flow (Minimal wrapper around your loop logic) ──
    agent1.symptoms_accumulated.append(user_input)
    rag_query = " ".join(agent1.symptoms_accumulated[-5:])
    context = "\n".join(agent1.search(rag_query))
    agent1.conversation_history.append({"role": "user", "content": user_input})

    if not agent1.is_first_turn:
        agent1.score_tasks_from_history(agent1.conversation_history)

    # Check if done
    if not agent1.is_first_turn and agent1.all_done():
        record_text = agent1.generate_record()
        # record_json = agent1.parse_record_to_json(record_text)
        # agent1.save_record(record_json, record_text, emergency=False)
        return {
            "reply": record_text,
            "stage": "completed"
        }

    # Generate next question
    current_task_id, current_task_desc = agent1.get_next_task()
    
    if agent1.is_first_turn:
        instruction = (
            "Đây là lượt đầu tiên. Chào bệnh nhân thật ngắn gọn (một câu), "
            "sau đó hỏi ngay về thời điểm và cách khởi phát của triệu chứng họ vừa mô tả."
        )
        agent1.is_first_turn = False
    else:
        task_status = agent1.build_task_status()
        instruction = (
            f"NHIỆM VỤ TIẾP THEO: hỏi về '{current_task_desc}'.\n"
            f"Chỉ hỏi đúng một câu tự nhiên, ngắn gọn."
        )

    messages_to_send = [
        {
            "role": "system",
            "content": f"{agent1.SYSTEM_PROMPT}\n\nContext:\n{context}"
        }
    ]
    for msg in agent1.conversation_history[:-1]:
        messages_to_send.append(msg)
    
    messages_to_send.append({
        "role": "user",
        "content": f"{user_input}\n\n[INSTRUCTION]\n{instruction}"
    })

    response = agent1.client.chat.completions.create(
        model=agent1.OLLAMA_MODEL,
        messages=messages_to_send
    )

    ai_reply = response.choices[0].message.content.strip()
    agent1.conversation_history.append({"role": "assistant", "content": ai_reply})

    return {
        "reply": ai_reply,
        "stage": "collecting"
    }
