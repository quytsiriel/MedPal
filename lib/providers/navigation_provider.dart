import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/map_service.dart';
import '../services/api_service.dart';

class NavigationState {
  final Hospital? currentHospital;
  final String currentAddress;
  final List<String> indoorSteps;
  final bool hasArrived;
  final bool isLoading;
  final double? lat;
  final double? lng;
  final String? targetDepartment;

  NavigationState({
    this.currentHospital,
    this.currentAddress = "Đang xác định vị trí...",
    this.indoorSteps = const [],
    this.hasArrived = false,
    this.isLoading = false,
    this.lat,
    this.lng,
    this.targetDepartment,
  });

  NavigationState copyWith({
    Hospital? currentHospital,
    String? currentAddress,
    List<String>? indoorSteps,
    bool? hasArrived,
    bool? isLoading,
    double? lat,
    double? lng,
    String? targetDepartment,
  }) {
    return NavigationState(
      currentHospital: currentHospital ?? this.currentHospital,
      currentAddress: currentAddress ?? this.currentAddress,
      indoorSteps: indoorSteps ?? this.indoorSteps,
      hasArrived: hasArrived ?? this.hasArrived,
      isLoading: isLoading ?? this.isLoading,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      targetDepartment: targetDepartment ?? this.targetDepartment,
    );
  }
}

class NavigationNotifier extends Notifier<NavigationState> {
  @override
  NavigationState build() {
    return NavigationState();
  }

  void setHospital(Hospital hospital, double? hospitalLat, double? hospitalLng, {String? targetDepartment}) {
    state = state.copyWith(
      currentHospital: hospital,
      lat: hospitalLat,
      lng: hospitalLng,
      hasArrived: false,
      indoorSteps: [],
      targetDepartment: targetDepartment,
    );
    if (hospitalLat != null && hospitalLng != null) {
      updateAddress(hospitalLat, hospitalLng);
    }
  }

  Future<void> updateAddress(double userLat, double userLng) async {
    state = state.copyWith(isLoading: true, lat: userLat, lng: userLng);
    final address = await mapService.getAddressFromLatLng(userLat, userLng);
    state = state.copyWith(currentAddress: address, isLoading: false);
  }

  void setArrived(bool arrived) {
    state = state.copyWith(hasArrived: arrived);
    if (arrived && state.indoorSteps.isEmpty) {
      fetchIndoorDirections();
    }
  }

  Future<void> fetchIndoorDirections() async {
    if (state.currentHospital == null) return;
    state = state.copyWith(isLoading: true);
    try {
      if (state.targetDepartment != null && state.targetDepartment!.isNotEmpty) {
        final res = await apiService.updateDepartment("session-id", state.targetDepartment!);
        state = state.copyWith(
          indoorSteps: List<String>.from(res['next_steps'] ?? []),
          isLoading: false,
        );
      } else {
        final res = await apiService.navigate("session-id", state.currentHospital!.name);
        state = state.copyWith(
          indoorSteps: List<String>.from(res['steps'] ?? []),
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void reset() {
    state = NavigationState();
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, NavigationState>(() {
  return NavigationNotifier();
});
