import 'dart:io';
import 'dart:typed_data';

/// Mobile/Desktop: đọc file audio từ đường dẫn trên disk
Future<Uint8List> readRecordedAudio(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  // Dọn file tạm
  try {
    await file.delete();
  } catch (_) {}
  return bytes;
}

/// Mobile/Desktop: tạo đường dẫn file tạm cho bản ghi âm
Future<String> createRecordingPath() async {
  final dir = await Directory.systemTemp.createTemp('medpal_audio');
  return '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
}
