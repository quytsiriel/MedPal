import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/navigation_provider.dart';
import '../services/map_service.dart';
import '../services/places_service.dart';
import '../services/directions_service.dart';
import '../services/location_service.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});
  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  static const Color brand = Color(0xFF006B70);

  final _locationSvc   = LocationService();
  final _directionsSvc = DirectionsService();

  GoogleMapController? _mapCtrl;
  StreamSubscription<Position>? _posSub;

  bool _isLoadingRoute = false;
  bool _isNavigating   = false;
  RouteInfo? _route;
  int  _stepIdx = 0;
  LatLng? _userPos;
  List<Hospital> _nearby = [];

  @override
  void dispose() {
    _posSub?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  IconData _maneuverIcon(String m) {
    switch (m) {
      case 'turn-left':
      case 'sharp-left':
      case 'slight-left':  return Icons.turn_left_rounded;
      case 'turn-right':
      case 'sharp-right':
      case 'slight-right': return Icons.turn_right_rounded;
      case 'uturn-left':
      case 'uturn-right':  return Icons.u_turn_left_rounded;
      case 'roundabout-left':
      case 'roundabout-right': return Icons.roundabout_right_rounded;
      case 'merge':
      case 'ramp-left':
      case 'ramp-right':  return Icons.merge_rounded;
      default:            return Icons.straight_rounded;
    }
  }

  String _fmtDuration(int s) {
    if (s < 3600) return '${(s / 60).ceil()} phút';
    return '${s ~/ 3600}h ${(s % 3600) ~/ 60}p';
  }

  String _fmtDist(int m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '$m m';

  Future<void> _startNavigation(Hospital hospital) async {
    setState(() => _isLoadingRoute = true);
    final pos = await _locationSvc.getCurrentLocation();
    final origin = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : LatLng(hospital.lat, hospital.lng);
    setState(() => _userPos = origin);

    final route = await _directionsSvc.getRoute(
      origin: origin,
      destinationPlaceId: hospital.placeId,
      destinationLatLng: LatLng(hospital.lat, hospital.lng),
    );
    if (!mounted) return;

    if (route != null) {
      setState(() {
        _route = route;
        _stepIdx = 0;
        _isNavigating = true;
        _isLoadingRoute = false;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      _fitBounds(route.polylinePoints);
      _startTracking(hospital);
    } else {
      setState(() => _isLoadingRoute = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không lấy được lộ trình. Kiểm tra kết nối.')),
        );
      }
    }
  }

  void _startTracking(Hospital hospital) {
    _posSub?.cancel();
    _posSub = _locationSvc.trackLocation().listen((pos) {
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _userPos = loc);
      _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: loc, zoom: 17, bearing: pos.heading, tilt: 30),
      ));
      final steps = _route?.steps ?? [];
      if (steps.isNotEmpty && _stepIdx < steps.length) {
        final d = Geolocator.distanceBetween(
          loc.latitude, loc.longitude,
          steps[_stepIdx].endLocation.latitude,
          steps[_stepIdx].endLocation.longitude,
        );
        if (d < 30 && _stepIdx < steps.length - 1) setState(() => _stepIdx++);
      }
      final distToDest = Geolocator.distanceBetween(
        loc.latitude, loc.longitude, hospital.lat, hospital.lng,
      );
      if (distToDest < 50) {
        _showArrivalFollowUp();
      }
    });
  }

  void _fitBounds(List<LatLng> pts) {
    if (pts.isEmpty) return;
    var sw = pts.first, ne = pts.first;
    for (final p in pts) {
      sw = LatLng(p.latitude < sw.latitude ? p.latitude : sw.latitude,
                  p.longitude < sw.longitude ? p.longitude : sw.longitude);
      ne = LatLng(p.latitude > ne.latitude ? p.latitude : ne.latitude,
                  p.longitude > ne.longitude ? p.longitude : ne.longitude);
    }
    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 64),
    );
  }

  void _stopNavigation() {
    _posSub?.cancel();
    setState(() { _isNavigating = false; _route = null; _stepIdx = 0; });
  }

  /// Bottom sheet hỏi tên khoa → gọi setDepartmentFromFollowUp() đã có sẵn
  void _showArrivalFollowUp() {
    _posSub?.cancel();
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDE4E6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_hospital_rounded, color: brand, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bạn đã đến bệnh viện! 🎉',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                        SizedBox(height: 2),
                        Text('Nhập tên khoa để được chỉ đường trong bệnh viện',
                          style: TextStyle(fontSize: 12, color: Color(0xFF95A5A6))),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'VD: Khoa Nội, Khoa Cấp cứu...',
                    prefixIcon: const Icon(Icons.search_rounded, color: brand),
                    filled: true,
                    fillColor: const Color(0xFFF4FAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: brand, width: 1.5),
                    ),
                  ),
                  onSubmitted: (val) => _submitDepartment(ctx, ctrl),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _submitDepartment(ctx, ctrl),
                    icon: const Icon(Icons.near_me_rounded, color: Colors.white),
                    label: const Text('Chỉ đường vào trong',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Bỏ qua hỏi khoa, vào thẳng luồng mặc định
                      ref.read(navigationProvider.notifier).setArrived(true);
                    },
                    child: const Text('Bỏ qua, tôi tự tìm được',
                      style: TextStyle(color: Color(0xFF95A5A6), fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitDepartment(BuildContext ctx, TextEditingController ctrl) async {
    final dept = ctrl.text.trim();
    if (dept.isEmpty) return;
    Navigator.pop(ctx);
    final ok = await ref.read(navigationProvider.notifier).setDepartmentFromFollowUp(dept);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không tìm thấy khoa "$dept". Thử lại với tên khác nhé.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);
    final hospital = navState.currentHospital;
    if (hospital == null) return _buildNoHospital();
    if (navState.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4FAFA),
        body: Center(child: CircularProgressIndicator(color: brand)),
      );
    }
    if (navState.hasArrived) return _buildIndoorNav(navState);
    return _buildHospitalView(hospital);
  }

  Widget _buildHospitalView(Hospital hospital) {
    final step = (_isNavigating && _route != null && _stepIdx < _route!.steps.length)
        ? _route!.steps[_stepIdx] : null;
    final double progress = (_route != null && _route!.steps.isNotEmpty)
        ? _stepIdx / _route!.steps.length : 0.0;

    final markers = <Marker>{
      AdvancedMarker(
        markerId: const MarkerId('hospital'),
        position: LatLng(hospital.lat, hospital.lng),
        icon: BitmapDescriptor.pinConfig(
          backgroundColor: Colors.red,
          borderColor: Colors.red,
          glyph: const CircleGlyph(color: Colors.white),
        ),
        infoWindow: InfoWindow(title: hospital.name),
      ),
      if (_userPos != null)
        AdvancedMarker(
          markerId: const MarkerId('user'),
          position: _userPos!,
          icon: BitmapDescriptor.pinConfig(
            backgroundColor: Colors.blue,
            borderColor: Colors.blue,
            glyph: const CircleGlyph(color: Colors.white),
          ),
        ),
    };

    final polylines = _route == null ? <Polyline>{} : {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _route!.polylinePoints,
        width: 6,
        color: const Color(0xFF1A73E8),
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),

          // Map
          Container(
            height: 320, width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(children: [
              GoogleMap(
                onMapCreated: (c) => _mapCtrl = c,
                cloudMapId: 'a45c02f1baf69dd786bcac73',
                markerType: GoogleMapMarkerType.advancedMarker,
                initialCameraPosition: CameraPosition(target: LatLng(hospital.lat, hospital.lng), zoom: 15),
                markers: markers,
                polylines: polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),

              // Step banner
              if (step != null)
                Positioned(
                  top: 10, left: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: brand,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Row(children: [
                      Icon(_maneuverIcon(step.maneuver), color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(step.instruction,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(step.distanceText,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                ),

              // Loading overlay
              if (_isLoadingRoute)
                Container(
                  color: Colors.black45,
                  child: const Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text('Đang tính toán lộ trình...', style: TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  )),
                ),
            ]),
          ),

          const SizedBox(height: 16),

          // Info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFE8F5F5), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.local_hospital_rounded, color: brand, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(hospital.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                  const SizedBox(height: 3),
                  Text(hospital.address, style: const TextStyle(fontSize: 12, color: Color(0xFF95A5A6))),
                ])),
              ]),

              // ETA
              if (_route != null) ...[
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.access_time_rounded, color: brand, size: 18),
                  const SizedBox(width: 6),
                  Text(_fmtDuration(_route!.totalDurationSeconds),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: brand)),
                  const SizedBox(width: 16),
                  const Icon(Icons.straighten_rounded, color: Color(0xFF95A5A6), size: 18),
                  const SizedBox(width: 6),
                  Text(_fmtDist(_route!.totalDistanceMeters),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF95A5A6))),
                  const Spacer(),
                  Text('Bước ${_stepIdx + 1}/${_route!.steps.length}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF95A5A6))),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress, minHeight: 6,
                    backgroundColor: const Color(0xFFE0F2F2),
                    color: brand,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Buttons
              if (!_isNavigating)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoadingRoute ? null : () => _startNavigation(hospital),
                    icon: const Icon(Icons.directions_rounded, color: Colors.white),
                    label: const Text('Bắt đầu chỉ đường',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 3,
                    ),
                  ),
                )
              else
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _stopNavigation,
                      icon: const Icon(Icons.close_rounded, color: brand),
                      label: const Text('Dừng', style: TextStyle(color: brand)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: brand),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _showArrivalFollowUp,
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                      label: const Text('Tôi đã đến',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                    ),
                  ),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildNoHospital() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 120, height: 120,
              decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 20, offset: Offset(0, 10))],
              ),
              child: Center(child: Image.asset('assets/mascot.png', width: 80, height: 80, fit: BoxFit.contain)),
            ),
            const SizedBox(height: 32),
            const Text(
              'MedPal sẽ giúp bạn tìm đến bệnh viện/phòng khám gần nhất nhé!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: brand, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showHospitalDialog,
                icon: const Icon(Icons.search, size: 24, color: Colors.white),
                label: const Text('Tìm phòng khám gần tôi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: brand,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildIndoorNav(NavigationState navState) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [brand, Color(0xFF00888E)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Color(0x4D006B70), blurRadius: 15, offset: Offset(0, 8))],
            ),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Colors.white24,
                child: Icon(Icons.near_me_rounded, color: Colors.white)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Đang điều hướng', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text('Đến ${navState.targetDepartment ?? 'Khoa khám bệnh'}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
          const SizedBox(height: 24),
          const Row(children: [
            Icon(Icons.directions_walk, color: brand),
            SizedBox(width: 8),
            Text('Các bước di chuyển',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: brand)),
          ]),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: navState.indoorSteps.length,
            itemBuilder: (ctx, i) {
              final step = navState.indoorSteps[i];
              final isLast = i == navState.indoorSteps.length - 1;
              final icon  = _indoorStepIcon(step);
              final color = _indoorStepColor(step);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isLast ? const Color(0xFFB2DFDB) : const Color(0xFFE5F1F1)),
                  boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    radius: 20,
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(step,
                    style: TextStyle(
                      fontSize: 15, height: 1.4,
                      color: isLast ? const Color(0xFF006B70) : const Color(0xFF333333),
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                    ))),
                  if (!isLast)
                    Text('${i + 1}', style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 12)),
                ]),
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ref.read(navigationProvider.notifier).markCurrentDeptAsVisited();
                _showFollowUpDepartment(navState.targetDepartment);
              },
              icon: const Icon(Icons.check_circle, color: Colors.white, size: 28),
              label: Text(() {
                final dept = navState.targetDepartment ?? 'KHÁM';
                final up = dept.toUpperCase();
                return up.startsWith('KHOA') ? 'TÔI ĐÃ ĐẾN $up' : 'TÔI ĐÃ ĐẾN KHOA $up';
              }(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: brand,
                padding: const EdgeInsets.symmetric(vertical: 22),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 8,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  IconData _indoorStepIcon(String step) {
    final s = step.toLowerCase();
    if (s.contains('rẽ trái'))  return Icons.turn_left_rounded;
    if (s.contains('rẽ phải'))  return Icons.turn_right_rounded;
    if (s.contains('thang máy')) return Icons.elevator_rounded;
    if (s.contains('thang bộ'))  return Icons.stairs_rounded;
    if (s.contains('cổng') || s.contains('vào')) return Icons.door_front_door_rounded;
    if (s.contains('đến') && s.contains('khoa')) return Icons.local_hospital_rounded;
    if (s.contains('đi thẳng')) return Icons.straight_rounded;
    return Icons.directions_walk_rounded;
  }

  Color _indoorStepColor(String step) {
    final s = step.toLowerCase();
    if (s.contains('thang máy') || s.contains('thang bộ')) return const Color(0xFF7B1FA2);
    if (s.contains('khoa') && s.contains('đến'))           return brand;
    if (s.contains('rẽ'))                                   return const Color(0xFFE65100);
    return const Color(0xFF006B70);
  }

  void _showFollowUpDepartment(String? arrivedDept) {
    final ctrl = TextEditingController();
    final displayDept = arrivedDept ?? 'khoa vừa đến';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFDDE4E6), borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Bạn đã đến $displayDept ✅',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)))),
                ]),
              ),
              const SizedBox(height: 20),
              const Text('Bác sĩ còn yêu cầu bạn\nđến khoa nào nữa không?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50), height: 1.4)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'VD: Khoa Nội, Khoa Phẫu thuật...',
                  prefixIcon: const Icon(Icons.search_rounded, color: brand),
                  filled: true, fillColor: const Color(0xFFF4FAFA),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: brand, width: 1.5)),
                ),
                onSubmitted: (_) => _submitFollowUpDept(ctx, ctrl),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _submitFollowUpDept(ctx, ctrl),
                  icon: const Icon(Icons.near_me_rounded, color: Colors.white),
                  label: const Text('Chỉ đường tiếp',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brand,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ref.read(navigationProvider.notifier).setArrived(false);
                    context.go('/');
                  },
                  icon: const Icon(Icons.home_rounded, size: 18, color: Color(0xFF95A5A6)),
                  label: const Text('Không, kết thúc hành trình',
                    style: TextStyle(color: Color(0xFF95A5A6), fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitFollowUpDept(BuildContext ctx, TextEditingController ctrl) async {
    final dept = ctrl.text.trim();
    if (dept.isEmpty) return;
    Navigator.pop(ctx);
    final ok = await ref.read(navigationProvider.notifier).setDepartmentFromFollowUp(dept);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Không tìm thấy khoa "$dept". Thử lại với tên khác nhé.'),
        backgroundColor: Colors.orange.shade700,
      ));
    }
  }



  void _showHospitalDialog() async {
    // Luôn show dialog dù GPS/API có lỗi hay không
    try {
      if (_nearby.isEmpty) {
        final pos = await _locationSvc.getCurrentLocation();
        if (pos != null) {
          _nearby = await PlacesService().getNearbyHospitals(
            LatLng(pos.latitude, pos.longitude));
        }
      }
    } catch (e) {
      debugPrint('[Nav] Hospital search error: $e');
      // Tiếp tục show dialog với danh sách hardcoded
    }
    final list = <Hospital>[
      Hospital(
        name: 'Bệnh viện E',
        address: '89 Trần Cung, Nghĩa Tân, Cầu Giấy, Hà Nội',
        openStatus: 'Đang mở cửa',
        lat: 21.0463, lng: 105.7865,
        photoUrl: 'assets/benhvien_e.jpg',
        placeId: 'ChIJTz29XkOrNTERQ1d-5z72mB0',
      ),
    ];
    for (final h in _nearby) {
      if (list.length >= 3) break;
      if (!h.name.contains('Bệnh viện E')) list.add(h);
    }
    if (list.length < 3) {
      list.add(Hospital(
        name: 'Phòng khám Đa khoa Thu Cúc',
        address: '286 Thụy Khuê, Tây Hồ, Hà Nội',
        openStatus: 'Đang mở cửa',
        lat: 21.0375, lng: 105.8038,
        placeId: 'ChIJ172R7bqrNTER1-aL5-9jT5Q',
      ));
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        title: const Row(children: [
          Icon(Icons.location_on_rounded, color: brand),
          SizedBox(width: 8),
          Expanded(child: Text('Đề xuất cho bạn',
            style: TextStyle(fontSize: 18, color: brand, fontWeight: FontWeight.bold))),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: list.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _hospitalCard(ctx, h),
            )).toList(),
          ),
        ),
        actions: [TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Đóng', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
        )],
      ),
    );
  }

  Widget _hospitalCard(BuildContext ctx, Hospital h) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        setState(() { _isNavigating = false; _route = null; _stepIdx = 0; });
        ref.read(navigationProvider.notifier).setHospital(h, null, null);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))],
          border: Border.all(color: const Color(0xFFE5F1F1)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: const Color(0xFFF4FAFA), borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.hardEdge,
            child: h.photoUrl != null
              ? (h.photoUrl!.startsWith('http')
                ? Image.network(h.photoUrl!, fit: BoxFit.cover,
                    errorBuilder: (c,e,s) => const Icon(Icons.local_hospital_rounded, color: brand, size: 28))
                : Image.asset(h.photoUrl!, fit: BoxFit.cover,
                    errorBuilder: (c,e,s) => const Icon(Icons.local_hospital_rounded, color: brand, size: 28)))
              : const Icon(Icons.local_hospital_rounded, color: brand, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2C3E50))),
            const SizedBox(height: 4),
            Text(h.address, style: const TextStyle(color: Color(0xFF7F8C8D), fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(h.openStatus, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: brand),
        ]),
      ),
    );
  }
}
