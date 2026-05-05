import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/directions_service.dart';
import '../services/map_service.dart'; // Use map_service.Hospital

class MapScreen extends StatefulWidget {
  final Hospital destination;
  final VoidCallback onArrived;
  
  const MapScreen({super.key, required this.destination, required this.onArrived});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _locationService   = LocationService();
  final _directionsService = DirectionsService();

  GoogleMapController? _mapController;
  RouteInfo?  _routeInfo;
  Position?   _userPosition;
  int         _currentStep = 0;
  bool        _isNavigating = false;
  StreamSubscription<Position>? _locationSub;

  Set<Polyline> get _polylines => _routeInfo == null ? {} : {
    Polyline(
      polylineId: const PolylineId('route'),
      points:     _routeInfo!.polylinePoints,
      width:      6,
      color:      const Color(0xFF1A73E8),
      endCap:     Cap.roundCap,
      startCap:   Cap.roundCap,
    ),
  };

  Set<Marker> get _markers => {
    if (_userPosition != null)
      AdvancedMarker(
        markerId: const MarkerId('user'),
        position: LatLng(_userPosition!.latitude, _userPosition!.longitude),
        icon: BitmapDescriptor.pinConfig(
          backgroundColor: Colors.blue,
          borderColor: Colors.blue,
          glyph: const CircleGlyph(color: Colors.white),
        ),
        infoWindow: const InfoWindow(title: 'Vị trí của bạn'),
      ),
    AdvancedMarker(
      markerId: const MarkerId('hospital'),
      position: LatLng(widget.destination.lat, widget.destination.lng),
      icon: BitmapDescriptor.pinConfig(
        backgroundColor: Colors.red,
        borderColor: Colors.red,
        glyph: const CircleGlyph(color: Colors.white),
      ),
      infoWindow: InfoWindow(title: widget.destination.name),
    ),
  };

  @override
  void initState() {
    super.initState();
    _initNavigation();
  }

  Future<void> _initNavigation() async {
    final position = await _locationService.getCurrentLocation();
    if (position == null || !mounted) return;

    setState(() => _userPosition = position);

    final origin = LatLng(position.latitude, position.longitude);
    final route = await _directionsService.getRoute(
      origin:             origin,
      destinationPlaceId: widget.destination.placeId,
      destinationLatLng:  LatLng(widget.destination.lat, widget.destination.lng),
    );
    if (route == null || !mounted) return;

    setState(() {
      _routeInfo    = route;
      _isNavigating = true;
    });

    _fitRouteBounds(route.polylinePoints);
    _startTracking();
  }

  void _startTracking() {
    _locationSub = _locationService.trackLocation().listen((position) {
      if (!mounted) return;
      setState(() => _userPosition = position);

      final userLatLng = LatLng(position.latitude, position.longitude);

      // Camera theo user
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target:  userLatLng,
            zoom:    17,
            bearing: position.heading, // xoay map theo hướng đi
            tilt:    45,
          ),
        ),
      );

      // Advance step nếu đến gần điểm cuối của step hiện tại
      if (_routeInfo != null && _currentStep < _routeInfo!.steps.length) {
        final stepEnd = _routeInfo!.steps[_currentStep].endLocation;
        final dist    = Geolocator.distanceBetween(
          userLatLng.latitude, userLatLng.longitude,
          stepEnd.latitude,    stepEnd.longitude,
        );

        if (dist < 30) { // trong vòng 30m thì chuyển step
          setState(() => _currentStep++);
        }
      }

      // Recalculate nếu lệch khỏi đường > 100m
      _checkOffRoute(userLatLng);
    });
  }

  void _checkOffRoute(LatLng userLatLng) {
    if (_routeInfo == null) return;
    double minDist = double.infinity;

    for (final point in _routeInfo!.polylinePoints) {
      final d = Geolocator.distanceBetween(
        userLatLng.latitude, userLatLng.longitude,
        point.latitude,      point.longitude,
      );
      if (d < minDist) minDist = d;
    }

    if (minDist > 100) _recalculateRoute(userLatLng);
  }

  Future<void> _recalculateRoute(LatLng from) async {
    final route = await _directionsService.getRoute(
      origin:             from,
      destinationPlaceId: widget.destination.placeId,
      destinationLatLng:  LatLng(widget.destination.lat, widget.destination.lng),
    );
    if (route != null && mounted) {
      setState(() {
        _routeInfo    = route;
        _currentStep  = 0;
      });
    }
  }

  void _fitRouteBounds(List<LatLng> points) {
    final bounds = points.fold<LatLngBounds>(
      LatLngBounds(southwest: points.first, northeast: points.first),
      (b, p) => LatLngBounds(
        southwest: LatLng(
          p.latitude  < b.southwest.latitude  ? p.latitude  : b.southwest.latitude,
          p.longitude < b.southwest.longitude ? p.longitude : b.southwest.longitude,
        ),
        northeast: LatLng(
          p.latitude  > b.northeast.latitude  ? p.latitude  : b.northeast.latitude,
          p.longitude > b.northeast.longitude ? p.longitude : b.northeast.longitude,
        ),
      ),
    );
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = (_routeInfo != null && _currentStep < _routeInfo!.steps.length)
        ? _routeInfo!.steps[_currentStep]
        : null;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _mapController = c,
            cloudMapId: 'a45c02f1baf69dd786bcac73',
            markerType: GoogleMapMarkerType.advancedMarker,
            initialCameraPosition: CameraPosition(
              target: _userPosition != null
                  ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
                  : LatLng(widget.destination.lat, widget.destination.lng),
              zoom: 14,
            ),
            myLocationEnabled:       true,
            myLocationButtonEnabled: false,
            polylines: _polylines,
            markers:   _markers,
            mapToolbarEnabled: false,
          ),

          // Instruction banner ở trên
          if (step != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.instruction,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Còn ${step.distanceMeters}m',
                        style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
            ),

          // Tổng thời gian ở dưới
          if (_routeInfo != null)
            Positioned(
              bottom: 32, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color:        Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.destination.name,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('~${(_routeInfo!.totalDurationSeconds / 60).ceil()} phút',
                              style: const TextStyle(color: Color(0xFF1A73E8))),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: widget.onArrived,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006B70),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('TÔI ĐÃ ĐẾN BỆNH VIỆN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            ),
          
          if (_routeInfo == null)
            Positioned(
              bottom: 32, left: 16, right: 16,
              child: ElevatedButton(
                onPressed: widget.onArrived,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006B70),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('TÔI ĐÃ ĐẾN BỆNH VIỆN', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}
