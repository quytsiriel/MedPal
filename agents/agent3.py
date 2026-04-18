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
