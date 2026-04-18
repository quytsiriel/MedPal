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

@router.post("/prescription")
def scan_prescription(request: PrescriptionRequest):
    client = OpenAI(
        base_url=os.environ.get("OLLAMA_BASE_URL", "http://124.197.18.87:11434/v1"),
        api_key="ollama", 
    )
    
    # Chuẩn bị payload chuẩn Vision của OpenAI
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": [
                {
                    "type": "text", 
                    "text": "Hãy trích xuất thông tin phân tích đơn thuốc trong hình ảnh này và trả về định dạng JSON nghiêm ngặt."
                },
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{request.image_base64}"
                    }
                }
            ]
        }
    ]
    
    try:
        response = client.chat.completions.create(
            # Sử dụng model hỗ trợ vision tại server (ví dụ llava)
            model=os.environ.get("OLLAMA_VISION_MODEL", "llava"),
            messages=messages,
            temperature=0.0, # Nhiệt độ 0.0 để AI tập trung trích xuất độ trính xác cao
        )
        
        raw_text = response.choices[0].message.content
        
        # Dọn dẹp markdown rác (ví dụ: ```json ... ```) để parse thành python dict an toàn
        if "```json" in raw_text:
            raw_text = raw_text.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_text:
            raw_text = raw_text.split("```")[1].split("```")[0].strip()
            
        data = json.loads(raw_text)
        return data
        
    except Exception as e:
        print(f"Agent 3 Error: {str(e)}")
        # Ollama tắt hoặc có lỗi, ném HTTP 500 để ứng dụng báo lỗi thật
        raise HTTPException(status_code=500, detail=str(e))
