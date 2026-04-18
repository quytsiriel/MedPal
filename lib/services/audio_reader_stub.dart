import 'dart:typed_data';

/// Stub — sẽ không bao giờ được gọi nếu platform hợp lệ
Future<Uint8List> readRecordedAudio(String path) {
  throw UnsupportedError('readRecordedAudio: platform not supported');
}

Future<String> createRecordingPath() {
  throw UnsupportedError('createRecordingPath: platform not supported');
}
