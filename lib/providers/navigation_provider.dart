import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/map_service.dart';
import '../services/api_service.dart';

class NavigationState {
  final bool isLoading;
  final Hospital? currentHospital;
  final String? targetDepartment;
  final String? previousDepartment; // Last visited dept for cross-dept A* routing
  final bool hasArrived;
  final String currentAddress;
  final List<String> indoorSteps;

  // Real-time navigation fields
  final bool isNavigating;
  final List<({double lat, double lng})> routePoints;
  final List<dynamic> routeSteps;
  final String currentInstruction;
  final ({double lat, double lng})? userLocation;
  final double userBearing;

  NavigationState({
    this.isLoading = false,
    this.currentHospital,
    this.targetDepartment,
    this.previousDepartment,
    this.hasArrived = false,
    this.currentAddress = 'Đang lấy vị trí...',
    this.indoorSteps = const [],
    this.isNavigating = false,
    this.routePoints = const [],
    this.routeSteps = const [],
    this.currentInstruction = '',
    this.userLocation,
    this.userBearing = 0.0,
  });

  NavigationState copyWith({
    bool? isLoading,
    Hospital? currentHospital,
    String? targetDepartment,
    String? previousDepartment,
    bool clearPreviousDepartment = false,
    bool? hasArrived,
    String? currentAddress,
    List<String>? indoorSteps,
    bool? isNavigating,
    List<({double lat, double lng})>? routePoints,
    List<dynamic>? routeSteps,
    String? currentInstruction,
    ({double lat, double lng})? userLocation,
    double? userBearing,
  }) {
    return NavigationState(
      isLoading: isLoading ?? this.isLoading,
      currentHospital: currentHospital ?? this.currentHospital,
      targetDepartment: targetDepartment ?? this.targetDepartment,
      previousDepartment: clearPreviousDepartment ? null : (previousDepartment ?? this.previousDepartment),
      hasArrived: hasArrived ?? this.hasArrived,
      currentAddress: currentAddress ?? this.currentAddress,
      indoorSteps: indoorSteps ?? this.indoorSteps,
      isNavigating: isNavigating ?? this.isNavigating,
      routePoints: routePoints ?? this.routePoints,
      routeSteps: routeSteps ?? this.routeSteps,
      currentInstruction: currentInstruction ?? this.currentInstruction,
      userLocation: userLocation ?? this.userLocation,
      userBearing: userBearing ?? this.userBearing,
    );
  }
}

class NavigationNotifier extends Notifier<NavigationState> {
  @override
  NavigationState build() {
    return NavigationState();
  }

  Future<void> setHospital(
    Hospital targetHospital, 
    double? userLat, 
    double? userLng, 
    {String? targetDepartment}
  ) async {
    if (targetHospital.name.contains("Bệnh viện E")) {
      targetDepartment ??= "Khoa Khám bệnh";
    }

    if (targetDepartment != null && targetHospital.name.contains("Bệnh viện E")) {
      try {
        final buildingData = await apiService.getBuildingCoords(targetDepartment);
        if (buildingData.isNotEmpty && buildingData['lat'] != null) {
          targetHospital = Hospital(
            name: targetHospital.name,
            address: buildingData['building_name'] != null ? '${buildingData['building_name']}, ${targetHospital.address}' : targetHospital.address,
            openStatus: targetHospital.openStatus,
            lat: buildingData['lat'],
            lng: buildingData['lng'],
            photoUrl: targetHospital.photoUrl,
            placeId: targetHospital.placeId,
          );
        }
      } catch (e) {
        debugPrint('[setHospital] getBuildingCoords unavailable, skipping: $e');
      }
    }

    state = state.copyWith(
      isLoading: true,
      currentHospital: targetHospital,
      targetDepartment: targetDepartment,
      hasArrived: false,
    );

    double? lat = userLat;
    double? lng = userLng;

    // Use GPS to get current location if not provided
    if (lat == null || lng == null) {
      final loc = await mapService.getCurrentLocation();
      if (loc != null) {
        lat = loc.lat;
        lng = loc.lng;
      }
    }

    String address = 'Không xác định được vị trí';
    if (lat != null && lng != null) {
      address = await apiService.reverseGeocode(lat, lng);
    }

    state = state.copyWith(
      isLoading: false,
      currentAddress: address,
    );
  }

  Future<void> setArrived(bool arrived) async {
    state = state.copyWith(hasArrived: arrived, isLoading: arrived);

    if (arrived && state.currentHospital != null) {
      final String sessionId = 'default_session';

      Map<String, dynamic> response;
      if (state.targetDepartment != null) {
        response = await apiService.updateDepartment(
          sessionId,
          state.targetDepartment!,
          fromDepartment: state.previousDepartment,
        );
      } else {
        response = await apiService.navigate(sessionId, state.currentHospital!.name);
      }

      final steps = (response['steps'] as List<dynamic>?)?.map((e) => e.toString()).toList()
                 ?? (response['next_steps'] as List<dynamic>?)?.map((e) => e.toString()).toList()
                 ?? [];

      state = state.copyWith(
        isLoading: false,
        indoorSteps: steps.isNotEmpty ? steps : ["Đi vào cửa chính", "Hỏi lễ tân"],
      );
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Called when user taps "Tôi đã đến Khoa X" — records current dept as previous
  /// so the next follow-up can route FROM this dept.
  void markCurrentDeptAsVisited() {
    final curr = state.targetDepartment;
    if (curr != null) {
      state = state.copyWith(previousDepartment: curr);
    }
  }

  /// Sets a new department target during follow-up. Routes FROM the previous dept.
  /// Returns [true] if found and state updated, [false] otherwise.
  Future<bool> setDepartmentFromFollowUp(String departmentName) async {
    // Snapshot the current dept as the routing origin before we overwrite it
    final fromDept = state.targetDepartment;
    state = state.copyWith(isLoading: true);

    try {
      // 1. Validate: fetch building coords for the new dept
      final buildingData = await apiService.getBuildingCoords(departmentName);
      if (buildingData.isEmpty || buildingData['lat'] == null) {
        state = state.copyWith(isLoading: false);
        return false;
      }

      final String canonicalDept = buildingData['department'] ?? departmentName;

      // 2. Update hospital target to the new building
      final currentHosp = state.currentHospital;
      if (currentHosp != null) {
        final updatedHospital = Hospital(
          name: currentHosp.name,
          address: buildingData['building_name'] != null
              ? '${buildingData['building_name']}, ${currentHosp.address.split(',').skip(1).join(',')}'
              : currentHosp.address,
          openStatus: currentHosp.openStatus,
          lat: buildingData['lat'],
          lng: buildingData['lng'],
          photoUrl: currentHosp.photoUrl,
          placeId: currentHosp.placeId,
        );
        state = state.copyWith(
          currentHospital: updatedHospital,
          previousDepartment: fromDept,   // store old dept as routing origin
          targetDepartment: canonicalDept,
          hasArrived: true,
        );
      } else {
        state = state.copyWith(
          previousDepartment: fromDept,
          targetDepartment: canonicalDept,
          hasArrived: true,
        );
      }

      // 3. Fetch hierarchical A* steps: fromDept → canonicalDept
      const sessionId = 'default_session';
      final response = await apiService.updateDepartment(
        sessionId,
        canonicalDept,
        fromDepartment: fromDept,  // pass routing origin
      );

      final steps = (response['steps'] as List<dynamic>?)?.map((e) => e.toString()).toList()
                 ?? (response['next_steps'] as List<dynamic>?)?.map((e) => e.toString()).toList()
                 ?? [];

      state = state.copyWith(
        isLoading: false,
        indoorSteps: steps.isNotEmpty
            ? steps
            : ['Đi tới tòa nhà vừa cập nhật', 'Hỏi lễ tân tại sảnh tòa nhà'],
      );

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  // Starts the real-time Google Maps route
  Future<void> startRealtimeRoute() async {
    final hosp = state.currentHospital;
    if (hosp == null || hosp.placeId == null) return;

    state = state.copyWith(isLoading: true);
    
    final loc = await mapService.getCurrentLocation();
    if (loc != null) {
      final dir = await mapService.getDirections(loc.lat, loc.lng, hosp.placeId!);
      if (dir != null) {
        state = state.copyWith(
          isNavigating: true,
          routePoints: dir['points'],
          routeSteps: dir['steps'],
          userLocation: loc,
          currentInstruction: dir['steps'].isNotEmpty ? _parseHtmlString(dir['steps'][0]['html_instructions']) : 'Đang đi theo lộ trình',
          isLoading: false,
        );
        return;
      }
    }
    state = state.copyWith(isLoading: false);
  }

  void updateUserLocation(({double lat, double lng}) loc, double bearing) {
    state = state.copyWith(userLocation: loc, userBearing: bearing);
    // Auto-advancing logic can be refined here by calculating distance to step end
  }
  
  void updateInstruction(String htmlString) {
    state = state.copyWith(currentInstruction: _parseHtmlString(htmlString));
  }

  String _parseHtmlString(String htmlString) {
    final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, ' ').replaceAll('  ', ' ').trim();
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, NavigationState>(NavigationNotifier.new);
