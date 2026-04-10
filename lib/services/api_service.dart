import 'dart:convert';
import 'package:http/http.dart' as http; // Sẵn sàng để thế chỗ Call API thật

class ApiService {
  // Thay the URL backend bang link Cloud Run/ngrok thuc te
  static const String baseUrl = 'https://api.medpal-backend.xyz'; 

  // ==========================================
  // AGENT 1: SYMPTOM COLLECTION
  // ==========================================

  /// [POST] /agent1/start
  /// Khởi tạo một session khám bệnh mới.
  Future<Map<String, dynamic>> startSession() async {
    // TODO: Bỏ comment khi thực đấu với BE
    /*
    final response = await http.post(Uri.parse('$baseUrl/agent1/start'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to start session');
    */

    // --- MOCK TẠM CỦA CODE KIẾN TRÚC ---
    await Future.delayed(const Duration(seconds: 1));
    return {
      "session_id": "mock-uuid-888-999",
      "message": "Chào bạn, tôi là bác sĩ trợ lý MedPal. Bạn vui lòng miêu tả triệu chứng nhé.",
      "stage": "init"
    };
  }

  /// [POST] /agent1/chat
  /// Gửi tin nhắn (text hoặc voice) trong luồng chẩn đoán
  Future<Map<String, dynamic>> chatSymptom({
    required String sessionId,
    String? message,
    String? voiceBase64,
  }) async {
    if (message == null && voiceBase64 == null) {
      throw Exception('Missing both message and voice_base64');
    }

    // TODO: Bỏ comment khi thực đấu với BE
    /*
    final response = await http.post(
      Uri.parse('$baseUrl/agent1/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "session_id": sessionId,
        if (message != null) "message": message,
        if (voiceBase64 != null) "voice_base64": voiceBase64,
      })
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Chat failed');
    */

    // --- MOCK TẠM CỦA CODE KIẾN TRÚC ---
    await Future.delayed(const Duration(seconds: 2));
    
    // Xử lý fake: Nếu user chát chữ "xong", giả màu bắt tín hiệu kết thúc
    if (message != null && message.toLowerCase().contains('xong')) {
       return {
        "reply": "Cảm ơn bạn. Đây là mã QR dùng để quét tại quầy đăng ký bệnh viện.",
        "stage": "completed",
        // Một đoạn baseb4 mãnh liệt tạo thành ảnh hình vuông bé tí
        "qr_code": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mNk+M9Qz0AEYBxVSF+FAAhKDveksOjmAAAAAElFTkSuQmCC"
      };
    }

    // Default flow
    return {
      "reply": "Dạ vâng, tôi đã ghi chú. Bạn có bị ho rát họng hay sốt đi kèm không ạ?",
      "stage": "collecting"
    };
  }


  // ==========================================
  // AGENT 2: NAVIGATION & ROUTING
  // ==========================================

  /// [POST] /agent2/navigate
  Future<Map<String, dynamic>> navigate(String sessionId, String hospitalName) async {
    await Future.delayed(const Duration(seconds: 1));
    return {
      "steps": [
        "Đi thẳng 50m đến tiền sảnh",
        "Rẽ trái ở quầy lễ tân A",
        "Lên thang máy số 3 tới phòng 204"
      ],
      "map_image_url": "https://maps.fake/hospital_map.png"
    };
  }


  // ==========================================
  // AGENT 3: PRESCRIPTION OCR
  // ==========================================

  /// [POST] /agent3/prescription
  Future<Map<String, dynamic>> scanPrescription(String sessionId, String imageBase64) async {
    await Future.delayed(const Duration(seconds: 2));
    return {
      "medications": [
        {
          "name": "Paracetamol 500mg",
          "dosage": "1 viên/lần",
          "instructions": "Uống sau khi ăn sáng, khi sốt trên 38.5 độ."
        }
      ],
      "schedule_synced": true,
      "summary": "Đơn thuốc bạn có 1 loại kháng viêm hạ sốt và 1 kháng sinh mạnh."
    };
  }
}

// Global instance 
final apiService = ApiService();
