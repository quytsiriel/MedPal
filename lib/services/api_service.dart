import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'map_service.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      // Browsers prefer 'localhost' for local development CORS
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 is the special alias for the host machine in Android Emulator
      return 'http://10.0.2.2:8000';
    }
    // Fallback for iOS simulator or other desktop platforms
    return 'http://localhost:8000';
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
      return jsonDecode(utf8.decode(response.bodyBytes));
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
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    
    // Trích xuất detail từ backend error response
    String detail = '';
    try {
      final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
      detail = errorBody['detail'] ?? response.body;
    } catch (_) {
      detail = response.body;
    }
    throw Exception('Chat failed (${response.statusCode}): $detail');
  }

  // ==========================================
  // AGENT 2: NAVIGATION & ROUTING (REAL GPS)
  // ==========================================

  Future<List<Hospital>> getNearbyHospitals(double lat, double lng) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agent2/hospitals'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "lat": lat,
          "lng": lng,
          "radius": 5000,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data.map((json) {
          String? photoUrl = json['photo_url'];
          if (photoUrl != null && kIsWeb) {
             photoUrl = "https://corsproxy.io/?${Uri.encodeComponent(photoUrl)}";
          }
          return Hospital(
            name: json['name'],
            address: json['address'],
            openStatus: json['open_status'],
            lat: json['lat'],
            lng: json['lng'],
            photoUrl: photoUrl,
          );
        }).toList();
      }
    } catch (e) {
      print('ApiService Error (getNearbyHospitals): $e');
    }

    // Final fallback to MapService if Agent 2 Cloud is down
    return mapService.getNearbyHospitals(lat, lng);
  }

  Future<Map<String, dynamic>> navigate(String sessionId, String hospitalName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agent2/navigate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "session_id": sessionId,
          "hospital_name": hospitalName,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}

    return {
      "steps": ["Đi thẳng vào cổng chính", "Hỏi quầy lễ tân để được hướng dẫn thêm"],
    };
  }

  Future<Map<String, dynamic>> updateDepartment(String sessionId, String department) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agent2/update-dept'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "session_id": sessionId,
          "department": department,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}

    return {"status": "default", "next_steps": ["Theo sau biển chỉ dẫn"]};
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/agent2/geocoding?lat=$lat&lng=$lng'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['address'] ?? "Không xác định được vị trí";
      }
    } catch (e) {
      print('ApiService Error (reverseGeocode): $e');
    }
    return "Không xác định được vị trí";
  }

  Future<Map<String, dynamic>> getBuildingCoords(String department) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/agent2/building-coords?department=${Uri.encodeComponent(department)}'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      print('ApiService Error (getBuildingCoords): $e');
    }
    return {};
  }

  // ==========================================
  // AGENT 3: PRESCRIPTION OCR
  // ==========================================

  Future<Map<String, dynamic>> scanPrescription(String sessionId, String imageBase64) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agent3/prescription'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "session_id": sessionId,
          "image_base64": imageBase64,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}

    return {
      "medications": [],
      "summary": "Hiện tại không thể phân tích đơn thuốc. Vui lòng thử lại sau."
    };
  }
}

// Global instance 
final apiService = ApiService();
