# MedPal - Trợ lý Sức khỏe Thông minh (AI-Powered Medical Assistant)

MedPal là một ứng dụng hỗ trợ y tế tích hợp AI, giúp người dùng theo dõi triệu chứng, nhận lời khuyên sức khỏe và tìm kiếm các cơ sở y tế gần nhất. Dự án sử dụng mô hình ngôn ngữ lớn (LLM) MedGemma thông qua Ollama để cung cấp các phản hồi chuyên sâu về y khoa.

## 🌟 Tính năng chính
- **Chẩn đoán triệu chứng:** Trò chuyện với AI để mô tả tình trạng sức khỏe và nhận phân tích sơ bộ.
- **Lời khuyên sức khỏe:** Nhận các gợi ý tự chăm sóc hoặc khuyến cáo khi nào cần gặp bác sĩ.
- **Tìm kiếm hiệu thuốc & bệnh viện:** Tích hợp Google Maps để tìm và chỉ đường đến các cơ sở y tế gần nhất.
- **Giao tiếp đa phương thức:** Hỗ trợ nhập liệu bằng văn bản và tích hợp nhận diện giọng nói.
- **Quản lý lịch sử:** Lưu trữ và quản lý các phiên tư vấn sức khỏe qua Firebase.

## 🛠 Công nghệ sử dụng
- **Frontend:** Flutter (Sử dụng Riverpod để quản lý state, GoRouter để điều hướng).
- **Backend:** Python (FastAPI, tích hợp với các AI Agents).
- **Cơ sở dữ liệu:** Firebase (Cloud Firestore để lưu data, Firebase Auth để xác thực).
- **Trí tuệ nhân tạo (AI):** 
  - **MedGemma:** Chạy thông qua Ollama trên FPT AI Factory để xử lý nghiệp vụ y tế.
  - **Whisper:** Xử lý chuyển đổi giọng nói thành văn bản.

## 🚀 Hướng dẫn cài đặt và chạy dự án

Để dự án hoạt động chính xác, bạn cần thiết lập các môi trường và file cấu hình sau:

### 1. Thiết lập biến môi trường (.env)
Dự án sử dụng file `.env` để quản lý các API Key và cấu hình server.
1. Tìm file `.env.example` trong thư mục gốc.
2. Tạo một file mới tên là `.env` và copy toàn bộ nội dung từ `.env.example` sang.
3. Điền các thông tin thực tế của bạn:
   - `OLLAMA_BASE_URL`: Link API của server Ollama (mặc định thường là `http://<ip>:11434/v1`).
   - `FIREBASE_PROJECT_ID`: ID dự án trên Firebase.
   - `MAPS_API_KEY`: API Key để sử dụng Google Maps SDK.

### 2. Cấu hình Firebase
1. Tải file `serviceAccountKey.json` (SDK Admin Key) từ Firebase Console.
2. Đặt file này vào thư mục gốc của project (đây là file dùng cho Backend Python kết nối tới Firestore).
3. Đảm bảo bạn cũng đã cài đặt `google-services.json` (cho Android) hoặc `GoogleService-Info.plist` (cho iOS) trong thư mục tương ứng nếu cần chạy mobile.

### 3. Chạy Backend (Python)
Đảm bảo bạn đã cài đặt Python 3.10 trở lên.
```powershell
# Tạo môi trường ảo (khuyến nghị)
python -m venv venv
.\venv\Scripts\activate

# Cài đặt dependencies
pip install -r requirements.txt

# Khởi chạy server
python main.py
```

### 4. Chạy Frontend (Flutter)
```powershell
# Tải các gói phụ thuộc
flutter pub get

# Chạy ứng dụng
flutter run
```

## 📂 Cấu trúc thư mục chính
- `lib/`: Chứa mã nguồn Flutter (UI, Services, Providers).
- `agents/`: Chứa logic của các AI Agent (Router, Diagnostic Agent).
- `main.py`: Điểm đầu entry point của backend FastAPI.
- `.env.example`: File mẫu chứa các biến môi trường cần thiết.

---
**Lưu ý:** Nếu bạn đang chạy local, hãy đảm bảo Backend và Flutter (nếu chạy trên máy ảo) có thể thông tin được với nhau qua địa chỉ IP phù hợp.
