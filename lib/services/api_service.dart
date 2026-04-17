import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'map_service.dart';

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

  Future<Map<String, dynamic>> startSession() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agent1/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      print('ApiService Error (startSession): $e');
    }

    // Fallback if backend is not reachable
    return {
      "session_id": "temp-session",
      "message": "Chào bạn, tôi là bác sĩ trợ lý MedPal. Hiện tại tôi đang mất kết nối với máy chủ, nhưng bạn vẫn có thể mô tả triệu chứng.",
      "stage": "init"
    };
  }

  Future<Map<String, dynamic>> chatSymptom({
    required String sessionId,
    String? message,
    String? voiceBase64,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agent1/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "session_id": sessionId,
          if (message != null) "message": message,
          if (voiceBase64 != null) "voice_base64": voiceBase64,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}

    return {
      "reply": "Dạ vâng, tôi đã ghi nhận. Xin mời bạn nói thêm...",
      "stage": "collecting"
    };
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
