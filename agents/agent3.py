from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import os
import json
from openai import OpenAI

router = APIRouter(prefix="/agent3", tags=["Agent 3"])

class PrescriptionRequest(BaseModel):
    session_id: str
    image_base64: str

# Giữ nguyên System Prompt đã thống nhất ở trên để parse dữ liệu
SYSTEM_PROMPT = """
Bạn là một trợ lý Y khoa AI (Agent 3) chuyên phân tích thông tin từ văn bản đơn thuốc (OCR). 
Nhiệm vụ của bạn là đọc các dòng text hoặc ảnh chụp đơn thuốc, trích xuất chính xác tên thuốc, liều lượng, và ĐẶC BIỆT LÀ LỊCH UỐNG THUỐC cụ thể, sau đó trả về dữ liệu dưới định dạng JSON nguyên chuẩn để ứng dụng điện thoại có thể hiển thị lên Giao diện (UI) và thiết lập thông báo tự động (Reminders).

### YÊU CẦU TRÍCH XUẤT TỪ CHUYÊN GIA:
1. **name**: Tên thuốc (Ghi kèm hàm lượng nếu có trên đơn, ví dụ: "Paracetamol 500mg").
2. **dosage**: Liều lượng cho MỘT lần uống (ví dụ: "1 viên / lần", "10ml / lần").
3. **schedule**: Mảng các mốc giờ uống thuốc trong ngày theo định dạng 24h chuẩn `"HH:mm"`. 
   - Nếu text ghi cụ thể giờ (VD: 8h, 20h) -> Xài giờ đó: `["08:00", "20:00"]`.
   - Nếu text chỉ ghi buổi "Sáng, Trưa, Chiều, Tối", BẮT BUỘC tự động quy đổi ra mốc giờ mặc định: Sáng -> `"08:00"`, Trưa -> `"12:00"`, Chiều -> `"17:00"`, Tối -> `"20:00"`.
4. **icon**: Phân tích dạng thuốc để UI hiển thị icon phù hợp (Chỉ được chọn 1 trong các giá trị: `pill`, `capsule`, `effervescent`, `syrup`, `injection`). Mặc định là `pill`.
5. **note**: Các lưu ý đặc biệt bác sĩ dặn.

### ĐỊNH DẠNG ĐẦU RA (JSON BẮT BUỘC):
Chỉ trả về duy nhất một đối tượng JSON hợp lệ như sau:
{
  "summary": "Tóm tắt ngắn gọn",
  "medications": [
    {
      "name": "Amoxicillin 250mg",
      "dosage": "2 viên / lần",
      "icon": "capsule",
      "schedule": ["08:00", "13:00", "20:00"],
      "note": "Uống sau khi ăn no"
    }
  ]
}
"""

from services.firebase import get_db
import google.generativeai as genai
import base64

@router.post("/prescription")
def scan_prescription(request: PrescriptionRequest):
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Thiếu cấu hình GEMINI_API_KEY")
        
    genai.configure(api_key=api_key)
    
    # Cấu hình để luôn trả về JSON nếu muốn an toàn (Gemini 1.5 hỗ trợ cấu hình response_mime_type)
    generation_config = genai.types.GenerationConfig(
        temperature=0.0,
        response_mime_type="application/json"
    )
    
    model = genai.GenerativeModel('gemini-2.5-flash', generation_config=generation_config)
    
    # Định dạng ảnh truyền từ frontend
    image_dict = {
        "mime_type": "image/jpeg",
        "data": request.image_base64
    }
    
    try:
        # Gọi Gemini xử lý ảnh với System Prompt
        response = model.generate_content([image_dict, SYSTEM_PROMPT])
        
        raw_text = response.text
        
        # Dọn dẹp markdown rác nếu model đôi khi vẫn kẹp thêm (phòng hờ)
        if "```json" in raw_text:
            raw_text = raw_text.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_text:
            raw_text = raw_text.split("```")[1].split("```")[0].strip()
            
        data = json.loads(raw_text)
        
        # Lưu vào Firestore vào session hiện tại để các Agent khác có thể tham khảo
        db = get_db()
        doc_ref = db.collection("sessions").document(request.session_id)
        if doc_ref.get().exists:
            doc_ref.set({"prescription": data}, merge=True)
            
        return data
        
    except Exception as e:
        print(f"Agent 3 Error (Gemini API): {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# ── HEALTH ADVICE FEATURE ──────────────────────────

class HealthAdviceRequest(BaseModel):
    session_id: str

HEALTH_ADVICE_PROMPT = """Benh nhan co trieu chung: {symptoms}

Hay dua ra 6 loi khuyen cham soc suc khoe tai nha dang JSON. CHI tra ve JSON, KHONG giai thich them:
{{"diagnosis_summary":"Tom tat 1 cau","tips":[{{"category":"avoid","title":"..","description":".."}},{{"category":"avoid","title":"..","description":".."}},{{"category":"do","title":"..","description":".."}},{{"category":"do","title":"..","description":".."}},{{"category":"warning","title":"..","description":".."}}]}}

Quy tac: 2 muc avoid (nen tranh), 3 muc do (nen lam), 1 muc warning. KHONG ke thuoc. Tieng Viet co dau."""

def _extract_patient_summary(session_data: dict) -> str:
    parts = []
    record = session_data.get("record", {})
    
    # Format 1 (new)
    if record.get("presenting_complaint"):
        parts.append(record["presenting_complaint"])
        
    if record.get("symptoms") and isinstance(record["symptoms"], list):
        for s in record["symptoms"][:5]:
            if isinstance(s, dict):
                name = s.get("symptom") or s.get("type", "")
                if name: parts.append(name)
            elif isinstance(s, str):
                parts.append(s)
                
    # Format 2 (old)
    if record.get("ly_do_kham"):
        parts.append(record["ly_do_kham"])
        
    hpi = record.get("hpi", {})
    if isinstance(hpi, dict):
        for key in ["dac_diem_trieu_chung", "trieu_chung_kem_theo"]:
            val = hpi.get(key)
            if val and val != "[chua khai thac]":
                parts.append(val)
                
    # Fallback
    acc = session_data.get("symptoms_accumulated", [])
    if acc and isinstance(acc, list):
        parts.extend([str(s) for s in acc[:5]])
        
    seen = set()
    unique = []
    for p in parts:
        p_clean = str(p).strip()
        if p_clean and p_clean.lower() not in seen:
            seen.add(p_clean.lower())
            unique.append(p_clean)
            
    return ", ".join(unique[:8])


@router.post("/health-advice")
def get_health_advice(request: HealthAdviceRequest):
    """Read session data from Firebase, extract minimal symptoms, call MedGemma ONLY."""
    db = get_db()
    doc = db.collection("sessions").document(request.session_id).get()
    
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Khong tim thay session tren Firebase")
    session_data = doc.to_dict()
    
    # [FIX] If advice is already generated (MedGemma finished it in the background), return it instantly!
    if session_data.get("health_advice"):
        print("[Agent 3] Returning cached health advice instantly from Firebase")
        return session_data["health_advice"]
        
    # Chắt lọc thông tin tối đa để prompt cực nhẹ
    patient_summary = _extract_patient_summary(session_data)
    
    if not patient_summary.strip():
        raise HTTPException(status_code=400, detail="Thieu thong tin trieu chung de phan tich")
        
    print(f"[Agent 3] Extracted symptoms: {patient_summary}")
    
    # Chỉ gọi MedGemma (không Google API)
    medgemma_client = OpenAI(
        base_url=os.environ.get("OLLAMA_BASE_URL_3", "http://124.197.18.227:11436/v1"),
        api_key="ollama",
        timeout=180.0, # Timeout 3 phút cho MedGemma
    )
    
    prompt = HEALTH_ADVICE_PROMPT.format(symptoms=patient_summary)
    
    try:
        response = medgemma_client.chat.completions.create(
            model=os.environ.get("OLLAMA_MODEL_3", "puyangwang/medgemma-27b-it:q4_0"),
            messages=[{"role": "user", "content": prompt}],
            temperature=0.1, # JSON predictable
        )
        raw_text = response.choices[0].message.content.strip()
        
        if "```json" in raw_text:
            raw_text = raw_text.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_text:
            raw_text = raw_text.split("```")[1].split("```")[0].strip()
            
        data = json.loads(raw_text)
        
        # Cập nhật Firebase
        db.collection("sessions").document(request.session_id).set({"health_advice": data}, merge=True)
        return data
        
    except json.JSONDecodeError as e:
        print(f"JSON Error: {raw_text}")
        raise HTTPException(status_code=500, detail=f"MedGemma loi JSON: {str(e)}")
    except Exception as e:
        print(f"MedGemma Error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"MedGemma timeout hoac loi: {str(e)}")
