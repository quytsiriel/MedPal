import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/map_service.dart';
import '../services/api_service.dart';
import '../providers/navigation_provider.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  final Hospital? targetHospital;
  final double? userLat;
  final double? userLng;

  const NavigationScreen({
    super.key,
    this.targetHospital,
    this.userLat,
    this.userLng,
  });

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.targetHospital != null) {
        ref.read(navigationProvider.notifier).setHospital(
          widget.targetHospital!, 
          widget.userLat, 
          widget.userLng
        );
      }
    });
  }

  Future<void> _openMapsDirections() async {
    final navState = ref.read(navigationProvider);
    if (navState.currentHospital == null) return;

    final destLat = navState.currentHospital!.lat;
    final destLng = navState.currentHospital!.lng;

    final googleMapsUrl = Uri.parse(
      "https://www.google.com/maps/dir/?api=1"
      "&destination=$destLat,$destLng"
      "&travelmode=driving"
    );

    final appleMapsUrl = Uri.parse(
      "https://maps.apple.com/?daddr=$destLat,$destLng"
      "&dirflg=d"
      "&t=m"
    );

    final googleMapsAppUrl = Uri.parse(
      "comgooglemaps://?daddr=$destLat,$destLng"
      "&directionsmode=driving"
    );

    if (!kIsWeb && await canLaunchUrl(googleMapsAppUrl)) {
      await launchUrl(googleMapsAppUrl);
    } else if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(appleMapsUrl)) {
      await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Không mở được ứng dụng bản đồ.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);
    final currentHospital = navState.currentHospital;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: navState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF006A71)),
            )
          : currentHospital == null
              ? const Center(
                  child: Text(
                    'Hãy chọn một cơ sở y tế ở trang Khám Y Tế',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : navState.hasArrived
                  ? _buildIndoorNavigation(navState)
                  : _buildOutdoorNavigation(navState),
    );
  }

  Widget _buildFallbackPhoto() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE5F1F1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Icon(Icons.local_hospital_rounded, size: 80, color: Color(0xFF006A71)),
      ),
    );
  }

  Widget _buildOutdoorNavigation(NavigationState navState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Premium Frame Holder for Hospital Image
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 4),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: navState.currentHospital?.photoUrl != null
                    ? Image.network(
                        navState.currentHospital!.photoUrl!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, _, __) => _buildFallbackPhoto(),
                      )
                    : _buildFallbackPhoto(),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(color: const Color(0xFFE5F1F1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.my_location_rounded, color: Colors.blue, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Bạn đang ở: ${navState.currentAddress}",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF2C3E50)),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 23, top: 4, bottom: 4),
                  child: SizedBox(
                    height: 20,
                    child: VerticalDivider(color: Color(0xFFE5F1F1), thickness: 2),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.local_hospital_rounded, color: Colors.red, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Cơ sở y tế hướng đến:\n${navState.currentHospital?.name}",
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF006A71)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            icon: const Icon(Icons.map_rounded, color: Colors.white, size: 28),
            label: const Text("Mở Bản đồ",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006A71),
              padding: const EdgeInsets.symmetric(vertical: 18),
              elevation: 4,
              shadowColor: const Color(0xFF006A71).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _openMapsDirections,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.login_rounded, color: Color(0xFF006A71), size: 28),
            label: const Text("Tôi đã đến tòa nhà cơ sở y tế",
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF006A71), fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF006A71), width: 2),
              ),
            ),
            onPressed: () {
              ref.read(navigationProvider.notifier).setArrived(true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIndoorNavigation(NavigationState navState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.directions_walk_rounded, size: 64, color: Color(0xFF006B70)),
          const SizedBox(height: 16),
          Text(
            'Hướng dẫn trong tòa nhà\n${navState.currentHospital?.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (navState.indoorSteps.isEmpty)
            const Text('Đang tải chỉ dẫn...', style: TextStyle(color: Colors.grey))
          else
            ...navState.indoorSteps.asMap().entries.map((entry) {
              int idx = entry.key;
              String step = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5F1F1)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF006B70),
                      child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Text(step, style: const TextStyle(fontSize: 16))),
                  ],
                ),
              );
            }),
          const SizedBox(height: 32),
          TextButton.icon(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF006A71)),
            label: const Text("Quay lại ngoài trời", style: TextStyle(color: Color(0xFF006A71), fontSize: 16)),
            onPressed: () {
              ref.read(navigationProvider.notifier).setArrived(false);
            },
          )
        ],
      ),
    );
  }
}
