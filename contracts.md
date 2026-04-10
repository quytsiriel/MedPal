# API Contracts (MedPal)

Tài liệu này định nghĩa các API endpoints để Flutter app giao tiếp với backend FastAPI.

## 1. Agent 1: Symptom Collection & Setup

### 1.1 Start Session
Khởi tạo một session khám bệnh mới.
- **URL**: `/agent1/start`
- **Method**: `POST`
- **Request Body**:
  ```json
  {}
  ```
  *(Có thể bổ sung user_id nếu có auth sau này)*
- **Response Schema** (200 OK):
  ```json
  {
    "session_id": "string (UUID)",
    "message": "string (Greeting message from AI)",
    "stage": "string (e.g., 'init')"
  }
  ```
- **Error Cases**:
  - `500 Internal Server Error`: Lỗi kết nối Firebase/Database.

### 1.2 Chat (Symptom Collection)
Gửi tin nhắn (text hoặc voice) tiếp theo trong luồng chẩn đoán/câu hỏi.
- **URL**: `/agent1/chat`
- **Method**: `POST`
- **Request Body**:
  ```json
  {
    "session_id": "string",
    "message": "string (optional if voice is provided)",
    "voice_base64": "string (optional)"
  }
  ```
- **Response Schema** (200 OK):
  ```json
  {
    "reply": "string (AI's next question or instruction)",
    "stage": "string (e.g., 'collecting', 'completed')",
    "qr_code": "string (base64 or URL, optional, only when stage is 'completed')"
  }
  ```
- **Error Cases**:
  - `400 Bad Request`: `session_id` bị thiếu hoặc cả `message` và `voice_base64` đều trống.
  - `404 Not Found`: Không tìm thấy session.
  - `500 Internal Server Error`: Lỗi parse voice hoặc kết nối Gemini.

---

## 2. Agent 2: Navigation & Routing

### 2.1 Navigate
Nhận chỉ dẫn từ cổng vào bệnh viện cụ thể.
- **URL**: `/agent2/navigate`
- **Method**: `POST`
- **Request Body**:
  ```json
  {
    "session_id": "string",
    "hospital_name": "string"
  }
  ```
- **Response Schema** (200 OK):
  ```json
  {
    "steps": [
      "Đi thẳng 50m",
      "Rẽ trái ở quầy lễ tân",
      "Thang máy số 3 lên tầng 2"
    ],
    "map_image_url": "string (URL to map image, optional)"
  }
  ```
- **Error Cases**:
  - `400 Bad Request`: `session_id` hoặc `hospital_name` trống.
  - `404 Not Found`: Không tìm thấy dữ liệu bản đồ cho bệnh viện này.

### 2.2 Update Department
Cập nhật khoa khám bệnh trong quá trình di chuyển (nếu có thay đổi hoặc đến chốt trung gian).
- **URL**: `/agent2/update-dept`
- **Method**: `POST`
- **Request Body**:
  ```json
  {
    "session_id": "string",
    "department": "string"
  }
  ```
- **Response Schema** (200 OK):
  ```json
  {
    "status": "string (e.g., 'updated')",
    "next_steps": [
      "string (Updated routing instructions)"
    ]
  }
  ```
- **Error Cases**:
  - `400 Bad Request`: Thiếu tham số.
  - `404 Not Found`: Session không tồn tại.

---

## 3. Agent 3: Prescription OCR

### 3.1 Scan Prescription
Gửi ảnh đơn thuốc để trích xuất thông tin nhắc nhở.
- **URL**: `/agent3/prescription`
- **Method**: `POST`
- **Request Body**:
  ```json
  {
    "session_id": "string",
    "image_base64": "string"
  }
  ```
- **Response Schema** (200 OK):
  ```json
  {
    "medications": [
      {
        "name": "string",
        "dosage": "string",
        "instructions": "string (e.g., 'Uống sau ăn sáng')"
      }
    ],
    "schedule_synced": "boolean (true if added to notification scheduler)",
    "summary": "string (AI summary of the prescription)"
  }
  ```
- **Error Cases**:
  - `400 Bad Request`: `image_base64` rỗng hoặc định dạng không hợp lệ.
  - `422 Unprocessable Entity`: Không nhận diện được chữ trong ảnh/ảnh mờ.
  - `500 Internal Server Error`: Lỗi xử lý OCR/Gemini.
