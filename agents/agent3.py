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

HEALTH_ADVICE_PROMPT = """Ban la bac si tu van suc khoe. Dua tren ho so benh ly cua benh nhan duoi day, hay dua ra loi khuyen cham soc suc khoe CA NHAN HOA, CU THE cho tinh trang benh nay.

HO SO BENH NHAN:
{patient_context}

HAY TRA VE JSON DUNG DINH DANG SAU (KHONG giai thich them, CHI tra ve JSON):
{{
  "diagnosis_summary": "Tom tat ngan gon tinh trang benh cua benh nhan (1-2 cau)",
  "tips": [
    {{
      "category": "avoid",
      "icon": "block",
      "title": "Tieu de ngan (VD: Khong an do lanh)",
      "description": "Giai thich tai sao nen tranh (1-2 cau)"
    }},
    {{
      "category": "avoid",
      "icon": "block",
      "title": "Dieu nen tranh thu 2",
      "description": "Giai thich"
    }},
    {{
      "category": "do",
      "icon": "check_circle",
      "title": "Dieu nen lam (VD: Uong nuoc am)",
      "description": "Giai thich tai sao nen lam (1-2 cau)"
    }},
    {{
      "category": "do",
      "icon": "check_circle",
      "title": "Dieu nen lam thu 2",
      "description": "Giai thich"
    }},
    {{
      "category": "do",
      "icon": "check_circle",
      "title": "Dieu nen lam thu 3",
      "description": "Giai thich"
    }},
    {{
      "category": "warning",
      "icon": "warning",
      "title": "Khi nao can di kham ngay",
      "description": "Mo ta cac dau hieu nguy hiem can di kham gap"
    }}
  ]
}}

QUY TAC QUAN TRONG:
- Toi thieu 2 muc "avoid", 3 muc "do", 1 muc "warning"
- TUYET DOI KHONG ke don thuoc hoac de cap ten thuoc cu the
- Chi dua loi khuyen ve loi song, dinh duong, sinh hoat, ve sinh
- Phai CU THE cho loai benh nay, KHONG chung chung
- Tra loi bang tieng Viet co dau day du"""


@router.post("/health-advice")
def get_health_advice(request: HealthAdviceRequest):
    """Read session data from Firebase, feed to MedGemma, return personalized health tips."""
    
    # 1. Read session from Firestore
    db = get_db()
    doc = db.collection("sessions").document(request.session_id).get()
    
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Session not found in Firestore")
    
    session_data = doc.to_dict()
    
    # 2. Extract relevant medical context
    record = session_data.get("record", {})
    symptoms = session_data.get("symptoms_accumulated", [])
    decision = session_data.get("decision", "unknown")
    advice_from_agent1 = session_data.get("advice", "")
    recommended_dept = session_data.get("recommended_dept", "")
    
    # Build patient context string
    context_parts = []
    
    if record:
        if record.get("ly_do_kham"):
            context_parts.append(f"Ly do kham: {record['ly_do_kham']}")
        hpi = record.get("hpi", {})
        if hpi:
            if hpi.get("dac_diem_trieu_chung"):
                context_parts.append(f"Trieu chung chinh: {hpi['dac_diem_trieu_chung']}")
            if hpi.get("khoi_phat"):
                context_parts.append(f"Khoi phat: {hpi['khoi_phat']}")
            if hpi.get("dien_bien"):
                context_parts.append(f"Dien bien: {hpi['dien_bien']}")
            if hpi.get("trieu_chung_kem_theo"):
                context_parts.append(f"Trieu chung kem theo: {hpi['trieu_chung_kem_theo']}")
            if hpi.get("da_xu_ly"):
                context_parts.append(f"Da xu ly: {hpi['da_xu_ly']}")
        ph = record.get("ph", {})
        if ph:
            if ph.get("benh_cu") and ph["benh_cu"] != "[chua khai thac]":
                context_parts.append(f"Tien su benh: {ph['benh_cu']}")
            if ph.get("di_ung") and ph["di_ung"] != "[chua khai thac]":
                context_parts.append(f"Di ung: {ph['di_ung']}")
        khoa = record.get("khoa_de_nghi", {})
        if khoa and khoa.get("khoa_chinh"):
            context_parts.append(f"Chuyen khoa de xuat: {khoa['khoa_chinh']}")
    
    if symptoms:
        context_parts.append(f"Danh sach trieu chung: {', '.join(symptoms)}")
    
    if decision:
        context_parts.append(f"Ket luan: {'Can di kham bac si' if decision == 'visit' else 'Tu cham soc tai nha'}")
    
    if recommended_dept:
        context_parts.append(f"Khoa kham de xuat: {recommended_dept}")
    
    if advice_from_agent1:
        context_parts.append(f"Loi khuyen so bo tu Agent 1: {advice_from_agent1}")
    
    patient_context = "\n".join(context_parts)
    
    if not patient_context.strip():
        raise HTTPException(status_code=400, detail="Session khong co du lieu benh ly de phan tich")
    
    # 3. Call MedGemma at port 11436
    medgemma_client = OpenAI(
        base_url=os.environ.get("OLLAMA_BASE_URL_3", "http://124.197.18.227:11436/v1"),
        api_key="ollama",
    )
    
    prompt = HEALTH_ADVICE_PROMPT.format(patient_context=patient_context)
    
    try:
        response = medgemma_client.chat.completions.create(
            model=os.environ.get("OLLAMA_MODEL_3", "puyangwang/medgemma-27b-it:q4_0"),
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3,
        )
        
        raw_text = response.choices[0].message.content.strip()
        
        # Clean markdown wrappers
        if "```json" in raw_text:
            raw_text = raw_text.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_text:
            raw_text = raw_text.split("```")[1].split("```")[0].strip()
        
        data = json.loads(raw_text)
        
        # Save to Firestore
        doc_ref = db.collection("sessions").document(request.session_id)
        doc_ref.set({"health_advice": data}, merge=True)
        
        return data
        
    except json.JSONDecodeError as e:
        print(f"Agent 3 Health Advice JSON parse error: {e}")
        print(f"Raw response: {raw_text}")
        raise HTTPException(status_code=500, detail=f"MedGemma tra ve dinh dang khong hop le: {str(e)}")
    except Exception as e:
        print(f"Agent 3 Health Advice Error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
