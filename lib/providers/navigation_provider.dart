import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/map_service.dart';
import '../services/api_service.dart';

class NavigationState {
  final bool isLoading;
  final Hospital? currentHospital;
  final String? targetDepartment;
  final bool hasArrived;
  final String currentAddress;
  final List<String> indoorSteps;

  NavigationState({
    this.isLoading = false,
    this.currentHospital,
    this.targetDepartment,
    this.hasArrived = false,
    this.currentAddress = 'Đang lấy vị trí...',
    this.indoorSteps = const [],
  });

  NavigationState copyWith({
    bool? isLoading,
    Hospital? currentHospital,
    String? targetDepartment,
    bool? hasArrived,
    String? currentAddress,
    List<String>? indoorSteps,
  }) {
    return NavigationState(
      isLoading: isLoading ?? this.isLoading,
      currentHospital: currentHospital ?? this.currentHospital,
      targetDepartment: targetDepartment ?? this.targetDepartment,
      hasArrived: hasArrived ?? this.hasArrived,
      currentAddress: currentAddress ?? this.currentAddress,
      indoorSteps: indoorSteps ?? this.indoorSteps,
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
      final buildingData = await apiService.getBuildingCoords(targetDepartment);
      if (buildingData.isNotEmpty && buildingData['lat'] != null) {
        targetHospital = Hospital(
          name: targetHospital.name,
          address: buildingData['building_name'] != null ? '${buildingData['building_name']}, ${targetHospital.address}' : targetHospital.address,
          openStatus: targetHospital.openStatus,
          lat: buildingData['lat'],
          lng: buildingData['lng'],
          photoUrl: targetHospital.photoUrl,
        );
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
      // Fetch indoor steps from backend Agent 2
      final String sessionOrUserId = 'default_session'; // Update this to real session logic if needed
      
      Map<String, dynamic> response;
      if (state.targetDepartment != null) {
        response = await apiService.updateDepartment(sessionOrUserId, state.targetDepartment!);
      } else {
        response = await apiService.navigate(sessionOrUserId, state.currentHospital!.name);
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

  /// Sets a new department target during a follow-up phase and jumps directly to indoor navigation.
  /// Returns [true] if the department was found and state updated, [false] otherwise.
  Future<bool> setDepartmentFromFollowUp(String departmentName) async {
    state = state.copyWith(isLoading: true);

    try {
      // 1. Fetch building coordinates for the specific department in Hospital E
      final buildingData = await apiService.getBuildingCoords(departmentName);
      
      // Validation: If no data returned or lat is null, the department doesn't exist in our DB
      if (buildingData.isEmpty || buildingData['lat'] == null) {
        state = state.copyWith(isLoading: false);
        return false;
      }

      // Use canonical name from DB if available, otherwise fallback to what user typed
      final String canonicalDept = buildingData['department'] ?? departmentName;

      // 2. Update current hospital state with building info
      final currentHosp = state.currentHospital;
      if (currentHosp != null) {
        final updatedHospital = Hospital(
          name: currentHosp.name,
          address: buildingData['building_name'] != null ? '${buildingData['building_name']}, ${currentHosp.address.split(',').skip(1).join(',')}' : currentHosp.address,
          openStatus: currentHosp.openStatus,
          lat: buildingData['lat'],
          lng: buildingData['lng'],
          photoUrl: currentHosp.photoUrl,
        );
        state = state.copyWith(
          currentHospital: updatedHospital,
          targetDepartment: canonicalDept,
          hasArrived: true,
        );
      } else {
        // Fallback if currentHospital isn't set
        state = state.copyWith(
          targetDepartment: canonicalDept,
          hasArrived: true,
        );
      }

      // 3. Fetch indoor steps for this new canonical department
      final String sessionOrUserId = 'default_session';
      final response = await apiService.updateDepartment(sessionOrUserId, canonicalDept);
      
      final steps = (response['steps'] as List<dynamic>?)?.map((e) => e.toString()).toList()
                 ?? (response['next_steps'] as List<dynamic>?)?.map((e) => e.toString()).toList()
                 ?? [];

      state = state.copyWith(
        isLoading: false,
        indoorSteps: steps.isNotEmpty ? steps : ["Đi tới tòa nhà vừa cập nhật", "Hỏi lễ tân tại sảnh tòa nhà"],
      );
      
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, NavigationState>(NavigationNotifier.new);
