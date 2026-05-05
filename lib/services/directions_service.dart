import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class RouteInfo {
  final List<LatLng> polylinePoints;
  final List<NavStep> steps;
  final int totalDistanceMeters;
  final int totalDurationSeconds;

  RouteInfo({
    required this.polylinePoints,
    required this.steps,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
  });
}

class NavStep {
  final String instruction;
  final int distanceMeters;
  final String distanceText;
  final LatLng endLocation;
  final String maneuver; // 'turn-left', 'turn-right', 'straight', 'roundabout-right', etc.

  NavStep({
    required this.instruction,
    required this.distanceMeters,
    required this.distanceText,
    required this.endLocation,
    this.maneuver = '',
  });
}

class DirectionsService {
  static const _apiKey = 'AIzaSyAnzgVLFFHAIF-mS8sHWI_kAKNJo4btE98';

  /// Trả về URL qua corsproxy.io khi chạy trên web để tránh CORS
  String _proxied(String rawUrl) {
    if (kIsWeb) {
      return 'https://corsproxy.io/?${Uri.encodeComponent(rawUrl)}';
    }
    return rawUrl;
  }

  Future<RouteInfo?> getRoute({
    required LatLng origin,
    String? destinationPlaceId,
    LatLng? destinationLatLng,
  }) async {
    assert(
      destinationPlaceId != null || destinationLatLng != null,
      'Phải cung cấp destinationPlaceId hoặc destinationLatLng',
    );

    RouteInfo? route;

    // Ưu tiên dùng LatLng để đảm bảo đường line xanh luôn khớp chính xác với vị trí red marker
    if (destinationLatLng != null) {
      route = await _fetchRoute(
        origin, 
        '${destinationLatLng.latitude},${destinationLatLng.longitude}'
      );
    }

    // Fallback sang Place ID nếu LatLng lỗi hoặc không có
    if (route == null && destinationPlaceId != null && destinationPlaceId.isNotEmpty) {
      debugPrint('[DirectionsService] Falling back to Place ID routing...');
      route = await _fetchRoute(origin, 'place_id:$destinationPlaceId');
    }

    return route;
  }

  Future<RouteInfo?> _fetchRoute(LatLng origin, String destParam) async {
    final rawUrl =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=$destParam'
        '&mode=driving'
        '&language=vi'
        '&key=$_apiKey';

    try {
      final response = await http
          .get(Uri.parse(_proxied(rawUrl)))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[DirectionsService] HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK') {
        debugPrint('[DirectionsService] API status: ${data['status']}');
        return null;
      }

      final route = data['routes'][0];
      final leg   = route['legs'][0];

      final polyPoints = PolylinePoints.decodePolyline(route['overview_polyline']['points'] as String);
      final points = polyPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

      final steps = (leg['steps'] as List).map((s) {
        final loc = s['end_location'];
        return NavStep(
          instruction:    _stripHtml(s['html_instructions'] as String),
          distanceMeters: s['distance']['value'] as int,
          distanceText:   s['distance']['text'] as String,
          endLocation:    LatLng(loc['lat'], loc['lng']),
          maneuver:       (s['maneuver'] as String?) ?? '',
        );
      }).toList();

      return RouteInfo(
        polylinePoints:       points,
        steps:                steps,
        totalDistanceMeters:  leg['distance']['value'] as int,
        totalDurationSeconds: leg['duration']['value'] as int,
      );
    } catch (e) {
      debugPrint('[DirectionsService] getRoute error: $e');
      return null;
    }
  }

  /// Bỏ các thẻ HTML trong instruction
  String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('  ', ' ').trim();

}
