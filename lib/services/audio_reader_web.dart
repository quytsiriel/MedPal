import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Web: đọc audio từ blob URL do record package trả về
Future<Uint8List> readRecordedAudio(String path) async {
  // Trên web, record package trả về blob URL (blob:http://...)
  // Dùng http.get để tải dữ liệu blob về dạng bytes
  final response = await http.get(Uri.parse(path));
  return response.bodyBytes;
}

/// Web: không cần đường dẫn thực, trả filename gợi ý cho record package
Future<String> createRecordingPath() async {
  return 'recording.webm';
}
