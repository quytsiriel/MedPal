// Barrel file: tự động chọn đúng implementation theo platform
export 'audio_reader_stub.dart'
    if (dart.library.io) 'audio_reader_io.dart'
    if (dart.library.html) 'audio_reader_web.dart';
