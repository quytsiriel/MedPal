import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

/// Lightweight data class for a hospital result
class Hospital {
  final String name;
  final String address;
  final String openStatus;
  final double lat;
  final double lng;
  final String? photoUrl;

  const Hospital({
    required this.name,
    required this.address,
    required this.openStatus,
    required this.lat,
    required this.lng,
    this.photoUrl,
  });
}

class MapService {
  final String _apiKey = "AIzaSyAnzgVLFFHAIF-mS8sHWI_kAKNJo4btE98";

  // 1. Get current GPS position (optimized for APK & Laptop)
  Future<({double lat, double lng})?> getCurrentLocation() async {
    // On Web, we often need to request permission directly to trigger the prompt
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (kIsWeb || permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        debugPrint('[MapService] Location permission denied.');
        return null;
      }
    }

    // Check if hardware service is enabled (on Web this is usually handled by the prompt)
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
      debugPrint('[MapService] Location service disabled.');
      return null;
    }

    // Use high accuracy for APK. Web medium is faster and often more reliable for browsers.
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: kIsWeb 
          ? const LocationSettings(accuracy: LocationAccuracy.medium)
          : const LocationSettings(accuracy: LocationAccuracy.high)
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('[MapService] GPS fixed: ${position.latitude}, ${position.longitude}');
      return (lat: position.latitude, lng: position.longitude);
    } catch (e) {
      debugPrint('[MapService] Fresh fix failed: $e');
      if (!kIsWeb) {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) return (lat: last.latitude, lng: last.longitude);
        } catch (e2) {
          debugPrint('[MapService] getLastKnownPosition failed: $e2');
        }
      }
    }
    
    return null;
  }

  // 2. Clearer Proxy Handling
  String _getProxiedUrl(String url) {
    if (kIsWeb) {
      // Use corsproxy.io as it is reliable for both JSON and Images
      return "https://corsproxy.io/?${Uri.encodeComponent(url)}";
    }
    return url;
  }

  // 3. Fallback Hospital Search (if Agent 2 is unavailable)
  Future<List<Hospital>> getNearbyHospitals(double lat, double lng) async {
    final String urlStr =
        "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
        "?location=$lat,$lng"
        "&radius=5000"
        "&type=hospital"
        "&language=vi"
        "&key=$_apiKey";

    final targetUrl = _getProxiedUrl(urlStr);

    try {
      final response = await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['status'] == 'OK') {
          final results = (body['results'] as List).take(5);
          return results.map((p) {
            final geo = p['geometry']['location'];
            String? photoUrl;
            if (p['photos'] != null && p['photos'].isNotEmpty) {
              final ref = p['photos'][0]['photo_reference'];
              photoUrl = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=$ref&key=$_apiKey";
            }
            return Hospital(
              name: p['name'] ?? 'Bệnh viện',
              address: p['vicinity'] ?? 'Hà Nội',
              openStatus: p['opening_hours']?['open_now'] == true ? 'Đang mở cửa' : 'Mở cửa 24/7',
              lat: geo['lat'],
              lng: geo['lng'],
              photoUrl: photoUrl,
            );
          }).toList();
        }
      }
    } catch (_) {}
    
    return _fallback(lat, lng);
  }

  Future<String> getAddressFromLatLng(double lat, double lng) async {
    // We use the Backend (ApiService) to perform geocoding. 
    // This avoids all CORS/Proxy issues on the browser.
    return await apiService.reverseGeocode(lat, lng);
  }

  List<Hospital> _fallback(double userLat, double userLng) {
    return [
      Hospital(name: 'Bệnh viện Bạch Mai', address: '78 Giải Phóng, Hà Nội', openStatus: 'Mở cửa 24/7', lat: 21.0063, lng: 105.8427),
      Hospital(name: 'Bệnh viện Việt Đức', address: '40 Tràng Thi, Hà Nội', openStatus: 'Mở cửa 24/7', lat: 21.0287, lng: 105.8471),
    ];
  }
}

final mapService = MapService();
