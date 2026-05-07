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
import 'dart:convert';
import 'package:record/record.dart';
import '../services/audio_reader.dart';
import '../services/api_service.dart';
import '../providers/session_provider.dart';

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

  bool _isPostExamPhase = false;
  int _mascotState = 0; // 0: none, 1: ask dept, 2: ask diagnosis
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String _mascotReply = "Bác sĩ có những chẩn đoán như thế nào?";
  bool _isProcessingMic = false;
  StateSetter? _modalSetState;
  final TextEditingController _deptController = TextEditingController();
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _conclusionController = TextEditingController();

  // Conclusion phase state
  bool _isSavingConclusion = false;

  void _updateMascotState(VoidCallback fn) {
    fn();
    if (mounted) setState(() {});
    if (_modalSetState != null) _modalSetState!(() {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _mapCtrl?.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _deptController.dispose();
    _diagnosisController.dispose();
    _conclusionController.dispose();
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
        _handleArrival();
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

  void _handleArrival() {
    _posSub?.cancel();
    ref.read(navigationProvider.notifier).setArrived(true);
    _isPostExamPhase = true;
    _showMascotModal("Bạn đã đến Khoa Khám bệnh.\nBác sĩ có yêu cầu bạn đến khoa nào nữa không?");
  }

  void _showMascotModal(String initialMsg) {
    _mascotState = 1;
    _mascotReply = initialMsg;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            _modalSetState = setModalState;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF4FAFA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                    _buildPostExamContent(),
                  ],
                ),
                ),  // SingleChildScrollView
              ),
            );
          }
        );
      }
    ).whenComplete(() {
      _modalSetState = null;
      _isPostExamPhase = false;
      _mascotState = 0;
    });
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

  Future<void> _submitDeptFromText() async {
    final dept = _deptController.text.trim();
    if (dept.isEmpty) return;
    _deptController.clear();
    _updateMascotState(() => _mascotReply = 'Đang tìm đường đến khoa...');
    final ok = await ref.read(navigationProvider.notifier).setDepartmentFromFollowUp(dept);
    if (ok) {
      _updateMascotState(() {
        _isPostExamPhase = false;
        _mascotState = 0;
      });
      if (mounted) Navigator.pop(context);
    } else {
      _updateMascotState(
        () => _mascotReply = 'Không tìm thấy khoa "$dept". Vui lòng nhập lại.',
      );
    }
  }

  Future<void> _submitDiagnosisFromText() async {
    final diagnosis = _diagnosisController.text.trim();
    if (diagnosis.isEmpty) return;
    _diagnosisController.clear();
    _updateMascotState(() => _mascotReply = 'Đang lưu chẩn đoán...');

    try {
      final sessionId = ref.read(sessionProvider).lastSessionId;
      if (sessionId != null) {
        await apiService.saveDiagnosis(sessionId, diagnosis);
      }
      if (mounted) {
        ref.read(navigationProvider.notifier).setArrived(false);
        _updateMascotState(() {
          _isPostExamPhase = false;
          _mascotState = 0;
        });
        Navigator.pop(context);
        context.go('/prescriptions');
      }
    } catch (e) {
      _updateMascotState(() => _mascotReply = 'Lỗi lưu chẩn đoán: $e');
    }
  }

  void _initConclusionChat() {
    _isSavingConclusion = false;
    _conclusionController.clear();
  }

  Future<void> _submitConclusionChat() async {
    final text = _conclusionController.text.trim();
    if (text.isEmpty || _isSavingConclusion) return;
    _conclusionController.clear();

    _updateMascotState(() {
      _isSavingConclusion = true;
      _mascotReply = '⏳ Đang lưu kết luận bác sĩ...';
    });

    try {
      final sessionId = ref.read(sessionProvider).lastSessionId;
      if (sessionId == null) {
        _updateMascotState(() {
          _isSavingConclusion = false;
          _mascotReply = '❌ Không tìm thấy phiên khám hiện tại.';
        });
        return;
      }

      // Save doctor's conclusion to Firebase via the combined endpoint.
      // This also triggers MedGemma 4B in the background, caching
      // the advice in Firebase for the prescriptions panel to pick up.
      await apiService.submitDoctorConclusion(sessionId, text);

      if (mounted) {
        // Invalidate advice cache so prescription_screen re-fetches
        // the newly generated health advice from Firebase.
        ref.read(sessionProvider.notifier).invalidateAdvice();

        // Navigate to prescriptions → Tab "Lời khuyên" which auto-fetches advice
        _navigateToPrescriptions();
      }
    } catch (e) {
      _updateMascotState(() {
        _isSavingConclusion = false;
        _mascotReply = '❌ Lỗi: $e';
      });
    }
  }

  void _navigateToPrescriptions() {
    ref.read(navigationProvider.notifier).setArrived(false);
    _updateMascotState(() {
      _isPostExamPhase = false;
      _mascotState = 0;
    });
    Navigator.pop(context);
    context.go('/prescriptions');
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
                      onPressed: _handleArrival,
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
                _isPostExamPhase = true;
                _showMascotModal("Bạn đã đến ${navState.targetDepartment ?? 'Khoa'}, Bác sĩ có yêu cầu bạn đến khoa nào nữa không?");
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
                    _initConclusionChat();
                    setState(() {
                      _isPostExamPhase = true;
                      _mascotState = 2;
                      _mascotReply = "Nhập kết luận bác sĩ";
                    });
                  },
                  icon: const Icon(Icons.medical_services_rounded, size: 18, color: brand),
                  label: const Text('Tôi đã khám xong toàn bộ',
                    style: TextStyle(color: brand, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ref.read(navigationProvider.notifier).setArrived(false);
                    context.go('/');
                  },
                  icon: const Icon(Icons.home_rounded, size: 18, color: Color(0xFF95A5A6)),
                  label: const Text('Không, quay về trang chủ',
                    style: TextStyle(color: Color(0xFF95A5A6), fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // POST-EXAM PHASE WIDGETS & LOGIC
  // ==========================================
  
  Widget _buildPostExamContent() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.0),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
            ),
            child: Text(
              _mascotReply,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: brand, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildRobotMascot(context),
        const SizedBox(height: 24),
        Text(
          _isRecording ? 'Nhấn lại trái tim để gửi' : 'Nhấn vào trái tim để bắt đầu nói',
          style: TextStyle(
            fontSize: 16,
            color: _isRecording ? Colors.red : const Color(0xFF6B7B80),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        if (_mascotState == 1) ...[
          // ── Text input for department (tab-1 style) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deptController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Nhập tên khoa...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE5F1F1), width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE5F1F1), width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: brand, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                    onSubmitted: (_) => _submitDeptFromText(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: const BoxDecoration(
                    color: brand,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.near_me_rounded, color: Colors.white),
                    onPressed: _submitDeptFromText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Skip to diagnosis (now opens chat) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _initConclusionChat();
                  _updateMascotState(() {
                    _mascotState = 2;
                    _mascotReply = "Nhập kết luận bác sĩ";
                  });
                },
                icon: const Icon(Icons.medical_services_rounded, color: brand),
                label: const Text('Tôi đã khám xong tất cả',
                    style: TextStyle(color: brand, fontSize: 16, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: brand, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ),
        ],
        if (_mascotState == 2) ...[
          // ── Doctor Conclusion Chat Interface ──
          _buildConclusionChatUI(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildConclusionChatUI() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          // ── Header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [brand, Color(0xFF00888E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(color: Color(0x33006B70), blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kết luận bác sĩ',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Nhập để MedGemma đưa ra lời khuyên',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.amber, size: 14),
                      SizedBox(width: 4),
                      Text('MedGemma', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Text Input Card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5F1F1), width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bác sĩ đã chẩn đoán gì cho bạn?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'VD: Viêm họng cấp, viêm amidan, thiếu máu nhẹ...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF95A5A6)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _conclusionController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 4,
                  minLines: 2,
                  enabled: !_isSavingConclusion,
                  decoration: InputDecoration(
                    hintText: 'Nhập kết luận của bác sĩ...',
                    hintStyle: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFFF8FCFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE5F1F1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE5F1F1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                  onSubmitted: (_) => _submitConclusionChat(),
                ),
                const SizedBox(height: 14),
                // ── Action buttons ──
                Row(
                  children: [
                    // Mic button
                    GestureDetector(
                      onTap: _isSavingConclusion ? null : _toggleRecordingForConclusion,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.red.withValues(alpha: 0.12) : const Color(0xFFF4FAFA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _isRecording ? Colors.red.withValues(alpha: 0.3) : const Color(0xFFE5F1F1),
                          ),
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                          color: _isRecording ? Colors.red : brand,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Send button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSavingConclusion ? null : _submitConclusionChat,
                        icon: _isSavingConclusion
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        label: Text(
                          _isSavingConclusion ? 'Đang gửi...' : 'Gửi & nhận lời khuyên',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSavingConclusion ? Colors.grey.shade400 : brand,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: _isSavingConclusion ? 0 : 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRecordingForConclusion() async {
    if (_isProcessingMic) return;
    _isProcessingMic = true;
    try {
      if (_isRecording) {
        await _stopRecordingForConclusion();
      } else {
        await _startRecording();
      }
    } finally {
      _isProcessingMic = false;
    }
  }

  Future<void> _stopRecordingForConclusion() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    _updateMascotState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
      _mascotReply = 'Đang nhận dạng giọng nói...';
    });

    if (path == null) return;

    try {
      final bytes = await readRecordedAudio(path);
      final base64Audio = base64Encode(bytes);
      final response = await apiService.transcribe(base64Audio);
      final transcript = response['transcript'] as String?;

      if (transcript != null && transcript.isNotEmpty) {
        _conclusionController.text = transcript;
        _updateMascotState(() => _mascotReply = 'Nhập kết luận bác sĩ');
      } else {
        _updateMascotState(() => _mascotReply = 'Không nghe rõ, bạn có thể nói lại không?');
      }
    } catch (e) {
      _updateMascotState(() => _mascotReply = 'Lỗi nhận dạng: $e');
    }
  }

  Widget _buildRobotMascot(BuildContext context) {

    // -------------------------------------------------------------
    // Tinh chỉnh kích thước và vị trí của trái tim tại đây:
    const double heartWidth = 350.0; // Chiều ngang của trái tim
    const double heartHeight = 350.0; // Chiều cao của trái tim
    const double heartBottomOffset = -5; // Độ xa tính từ mép dưới của nhân vật
    // -------------------------------------------------------------

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow Background
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF96F1FA).withOpacity(0.4),
                blurRadius: 60,
                spreadRadius: 20,
              ),
            ],
          ),
        ),
        // Mascot Image
        Image.asset(
          'assets/mascot.png',
          width: 320,
          height: 320,
          fit: BoxFit.contain,
        ),

        // 5. Nút Mic - Bắt sự kiện Nhấn nhả sử dụng ảnh Assets (Tắt viền trắng)
        Positioned(
          bottom: heartBottomOffset, // Vị trí trái tim lên xuống
          child: GestureDetector(
            onTap: _toggleRecording,
            child: SizedBox(
              width: heartWidth,
              height: heartHeight,
              child: AnimatedCrossFade(
                firstChild: Image.asset(
                  'assets/heart_normal.png',
                  fit: BoxFit.contain,
                  width: heartWidth,
                  height: heartHeight,
                ),
                secondChild: Image.asset(
                  'assets/heart_pressed.png',
                  fit: BoxFit.contain,
                  width: heartWidth,
                  height: heartHeight,
                ),
                crossFadeState: _isRecording
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 150),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleRecording() async {
    if (_isProcessingMic) return;
    _isProcessingMic = true;
    try {
      if (_isRecording) {
        await _stopRecordingAndSend();
      } else {
        await _startRecording();
      }
    } finally {
      _isProcessingMic = false;
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final filePath = await createRecordingPath();
        final config = const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        );
        await _audioRecorder.start(config, path: filePath);
        _recordTimer?.cancel();
        _updateMascotState(() {
          _isRecording = true;
          _recordDuration = Duration.zero;
          _mascotReply = '🎤 Đang ghi âm... Nhấn lại trái tim để gửi.';
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          final m = _recordDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
          final s = _recordDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
          _updateMascotState(() {
            _recordDuration += const Duration(seconds: 1);
            _mascotReply = '🎤 Đang ghi âm... $m:$s\nNhấn lại trái tim để gửi.';
          });
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần cấp quyền microphone để ghi âm.')));
        }
      }
    } catch (e) {
      _updateMascotState(() => _mascotReply = 'Lỗi ghi âm: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    _updateMascotState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
      _mascotReply = 'Đang nhận dạng giọng nói...';
    });

    if (path == null) return;

    try {
      final bytes = await readRecordedAudio(path);
      final base64Audio = base64Encode(bytes);

      final response = await apiService.transcribe(base64Audio);
      final transcript = response['transcript'] as String?;
      
      if (transcript != null && transcript.isNotEmpty) {
        if (_mascotState == 1) {
           _updateMascotState(() => _mascotReply = 'Đang tìm đường đến khoa...');
           final ok = await ref.read(navigationProvider.notifier).setDepartmentFromFollowUp(transcript);
           if (ok) {
               _updateMascotState(() {
                 _isPostExamPhase = false;
                 _mascotState = 0;
               });
               if (mounted) Navigator.pop(context); // Close the bottom sheet
           } else {
               _updateMascotState(() => _mascotReply = 'Không tìm thấy khoa "$transcript". Vui lòng nói lại.');
           }
        } else if (_mascotState == 2) {
          _updateMascotState(() {
            _mascotReply = 'Đang lưu chẩn đoán...';
          });
          
          final sessionId = ref.read(sessionProvider).lastSessionId;
          if (sessionId != null) {
            await apiService.saveDiagnosis(sessionId, transcript);
            if (mounted) {
               ref.read(navigationProvider.notifier).setArrived(false);
               _updateMascotState(() {
                 _isPostExamPhase = false;
                 _mascotState = 0;
               });
               Navigator.pop(context); // Close the bottom sheet
               context.go('/prescriptions');
            }
          } else {
            _updateMascotState(() {
               _mascotReply = 'Lỗi: Không tìm thấy phiên khám hiện tại.';
            });
          }
        }
      } else {
        _updateMascotState(() {
          _mascotReply = 'Không nghe rõ, bạn có thể nói lại không?';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mascotReply = 'Lỗi nhận dạng: $e';
        });
      }
    }
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
