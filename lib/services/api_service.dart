import 'dart:convert';
import 'package:flutter/foundation.dart'; // Dùng foundation thay cho dart:io để không gây crash trên Web
import 'package:http/http.dart' as http;

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  // ==========================================
  // AGENT 1: SYMPTOM COLLECTION
  // ==========================================

  /// [POST] /agent1/start
  /// Khởi tạo một session khám bệnh mới.
  Future<Map<String, dynamic>> startSession() async {
    final response = await http.post(
      Uri.parse('$baseUrl/agent1/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}), // Gửi body trống
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to start session: ${response.statusCode}');
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
    throw Exception('Chat failed: ${response.statusCode}');
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
