import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_service.dart';

class PlacesService {
  static const _apiKey = 'AIzaSyAnzgVLFFHAIF-mS8sHWI_kAKNJo4btE98';
  static const _baseUrl = 'https://maps.googleapis.com/maps/api';

  /// Trả về URL qua corsproxy.io khi chạy web để tránh CORS
  String _proxied(String rawUrl) {
    if (kIsWeb) {
      return 'https://corsproxy.io/?${Uri.encodeComponent(rawUrl)}';
    }
    return rawUrl;
  }

  Future<List<Hospital>> getNearbyHospitals(LatLng userLocation) async {
    final rawUrl = '$_baseUrl/place/nearbysearch/json'
        '?location=${userLocation.latitude},${userLocation.longitude}'
        '&radius=5000'
        '&type=hospital'
        '&language=vi'
        '&key=$_apiKey';

    try {
      final response = await http
          .get(Uri.parse(_proxied(rawUrl)))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK') {
        debugPrint('[PlacesService] API status: ${data['status']}');
        return [];
      }

      return (data['results'] as List).map((place) {
        final loc = place['geometry']['location'];
        return Hospital(
          name:       place['name'] ?? 'Bệnh viện',
          address:    place['vicinity'] ?? 'Không rõ địa chỉ',
          openStatus: place['opening_hours']?['open_now'] == true
              ? 'Đang mở cửa'
              : 'Mở cửa 24/7',
          lat:      loc['lat'],
          lng:      loc['lng'],
          placeId:  place['place_id'],
          photoUrl: place['photos'] != null && (place['photos'] as List).isNotEmpty
              ? '$_baseUrl/place/photo?maxwidth=400'
                '&photo_reference=${place['photos'][0]['photo_reference']}'
                '&key=$_apiKey'
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('[PlacesService] getNearbyHospitals error: $e');
      return [];
    }
  }
}
