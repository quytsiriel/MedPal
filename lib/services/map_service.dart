import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'api_service.dart';

/// Lightweight data class for a hospital result
class Hospital {
  final String name;
  final String address;
  final String openStatus;
  final double lat;
  final double lng;
  final String? photoUrl;
  final String? placeId;

  const Hospital({
    required this.name,
    required this.address,
    required this.openStatus,
    required this.lat,
    required this.lng,
    this.photoUrl,
    this.placeId,
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

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        )
      );
      
      if (position.latitude != 0.0 && position.longitude != 0.0) {
        debugPrint('[MapService] GPS fixed: ${position.latitude}, ${position.longitude}, acc: ${position.accuracy}');
        return (lat: position.latitude, lng: position.longitude);
      } else {
        debugPrint('[MapService] GPS fixed but (0,0)');
      }
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
              placeId: p['place_id'],
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
      Hospital(name: 'Bệnh viện Bạch Mai', address: '78 Giải Phóng, Hà Nội', openStatus: 'Mở cửa 24/7', lat: 21.0063, lng: 105.8427, placeId: 'ChIJT6p98rOrNTERE0yU2L5E28o'),
      Hospital(name: 'Bệnh viện Việt Đức', address: '40 Tràng Thi, Hà Nội', openStatus: 'Mở cửa 24/7', lat: 21.0287, lng: 105.8471, placeId: 'ChIJj7O-rF2pNTERxR_U8iXv1Uo'),
    ];
  }

  // 4. Get Directions using Google Maps Directions API
  Future<Map<String, dynamic>?> getDirections(double originLat, double originLng, String destinationPlaceId) async {
    final String urlStr =
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=$originLat,$originLng"
        "&destination=place_id:$destinationPlaceId"
        "&mode=driving"
        "&language=vi"
        "&key=$_apiKey";

    final targetUrl = _getProxiedUrl(urlStr);

    try {
      final response = await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        if (body['status'] == 'OK' && (body['routes'] as List).isNotEmpty) {
          final route = body['routes'][0];
          final polylineStr = route['overview_polyline']['points'];
          final leg = route['legs'][0];
          final steps = leg['steps'];
          
          List<({double lat, double lng})> points = _decodePolyline(polylineStr);
          
          return {
            'points': points,
            'steps': steps,
            'distance': leg['distance']['text'],
            'duration': leg['duration']['text'],
            'end_address': leg['end_address'],
          };
        }
      }
    } catch (e) {
      debugPrint('[MapService] getDirections error: $e');
    }
    return null;
  }

  // Polyline decoding algorithm using robust package
  List<({double lat, double lng})> _decodePolyline(String encoded) {
    final points = PolylinePoints.decodePolyline(encoded);
    return points.map((p) => (lat: p.latitude, lng: p.longitude)).toList();
  }
}

final mapService = MapService();
