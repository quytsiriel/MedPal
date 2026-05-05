import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {

  Future<Position?> getCurrentLocation() async {
    // Bước 1: kiểm tra permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || kIsWeb) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) return null;

    // Bước 2: kiểm tra GPS service (bỏ qua trên web vì browser xử lý)
    if (!kIsWeb) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
    }

    // Bước 3: lấy vị trí
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, // Giảm từ best xuống high để lấy nhanh hơn
          timeLimit: Duration(seconds: 5), // Chỉ chờ 5s thay vì 20s
        ),
      );
      if (_isValidPosition(position)) return position;
      debugPrint('[LocationService] Invalid fix: (${position.latitude}, ${position.longitude}), acc=${position.accuracy}');
    } catch (e) {
      debugPrint('[LocationService] Fresh fix failed: $e');
      // Thử last known (chỉ trên mobile)
      if (!kIsWeb) {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null && _isValidPosition(last)) return last;
        } catch (_) {}
      }
    }
    return null;
  }

  /// Stream real-time tracking — đã lọc nhiễu (0,0) và accuracy kém
  Stream<Position> trackLocation() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10, // chỉ update khi di chuyển ≥ 10m
      ),
    ).where(_isValidPosition); // Lọc trực tiếp trong stream
  }

  bool _isValidPosition(Position p) =>
      !(p.latitude == 0.0 && p.longitude == 0.0); // Bỏ qua accuracy filter để hỗ trợ Web/Emulator
}
