import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/navigation_provider.dart';
import '../services/map_service.dart';
import '../services/api_service.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  // Brand color
  static const Color brandColor = Color(0xFF006B70);
  
  List<Hospital> _nearbyHospitals = []; // State for dynamic hospitals

  Future<void> _openMap(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở bản đồ.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);
    final currentHospital = navState.currentHospital;

    // Feature 5: If no session/hospital selected yet
    if (currentHospital == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4FAFA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/mascot.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'MedPal sẽ giúp bạn tìm đến bệnh viện/phòng khám gần nhất nhé!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF006B70),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showHospitalRecommendationsDialog,
                    icon: const Icon(Icons.search, size: 24, color: Colors.white),
                    label: const Text(
                      'Tìm phòng khám gần tôi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006B70),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0xFF006B70).withOpacity(0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: navState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF006B70)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // --- UI Condition: Before arriving at Hospital ---
                  if (!navState.hasArrived) ...[
                    // Hospital Info Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          if (currentHospital.photoUrl != null)
                            Container(
                              height: 150,
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                image: DecorationImage(
                                  image: currentHospital.photoUrl!.startsWith('http')
                                      ? NetworkImage(currentHospital.photoUrl!) as ImageProvider
                                      : AssetImage(currentHospital.photoUrl!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.local_hospital, size: 64, color: brandColor),
                          const SizedBox(height: 12),
                          Text(
                            currentHospital.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C3E50),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentHospital.address,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          
                          // Map Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _openMap(currentHospital.lat, currentHospital.lng),
                                  icon: const Icon(Icons.map, color: Colors.white),
                                  label: const Text(
                                    'MỞ BẢN ĐỒ GOOGLE',
                                    style: TextStyle(
                                      color: Colors.white, 
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: brandColor,
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref.read(navigationProvider.notifier).setArrived(true);
                              },
                              icon: const Icon(Icons.check_circle_outline, color: brandColor),
                              label: const Text(
                                'TÔI ĐÃ ĐẾN BỆNH VIỆN',
                                style: TextStyle(
                                  color: brandColor, 
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                side: const BorderSide(color: brandColor, width: 3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // --- UI Condition: After reaching Hospital (Indoor Navigation) ---
                  if (navState.hasArrived) ...[
                    // Active Nav Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [brandColor, brandColor.withOpacity(0.8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: brandColor.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.near_me_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Đang điều hướng',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                Text(
                                  'Đến ${navState.targetDepartment ?? 'Khoa khám bệnh'}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Icon(Icons.directions_walk, color: brandColor),
                        SizedBox(width: 8),
                        Text(
                          'Các bước di chuyển',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: brandColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: navState.indoorSteps.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5F1F1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: brandColor,
                                radius: 14,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  navState.indoorSteps[index],
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                    color: Color(0xFF333333),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Clean up specifically the arrival status, keep the hospital for context
                          ref.read(navigationProvider.notifier).setArrived(false);
                          // Navigate back to Home screen with follow-up flag
                          context.go('/?followup=true');
                        },
                        icon: const Icon(Icons.check_circle, color: Colors.white, size: 28),
                        label: Text(
                          () {
                            final dept = navState.targetDepartment ?? "KHÁM";
                            final deptUpper = dept.toUpperCase();
                            if (deptUpper.startsWith("KHOA")) {
                              return 'TÔI ĐÃ ĐẾN $deptUpper';
                            }
                            return 'TÔI ĐÃ ĐẾN KHOA $deptUpper';
                          }(),
                          style: const TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.bold,
                            fontSize: 20, // Extra large for the final step
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandColor,
                          padding: const EdgeInsets.symmetric(vertical: 22), // Maximum padding
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 8,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  void _showHospitalRecommendationsDialog() async {
    // 1. Fetch real nearby hospitals if not already fetched
    if (_nearbyHospitals.isEmpty) {
      final loc = await mapService.getCurrentLocation();
      if (loc != null) {
        _nearbyHospitals = await apiService.getNearbyHospitals(loc.lat, loc.lng);
      }
    }

    // 2. Prepare the list: Bệnh viện E first, then 2 real nearest
    List<Hospital> displayList = [];
    
    // Hardcode BV E as primary choice for Demo
    displayList.add(Hospital(
      name: "Bệnh viện E",
      address: "89 Trần Cung, Nghĩa Tân, Cầu Giấy, Hà Nội",
      openStatus: "Đang mở cửa",
      lat: 21.0463,
      lng: 105.7865,
      photoUrl: "assets/benhvien_e.jpg",
    ));

    // Add up to 2 more from real API results (avoid duplicating BV E if it's there)
    for (var h in _nearbyHospitals) {
      if (displayList.length >= 3) break;
      if (!h.name.contains("Bệnh viện E")) {
        displayList.add(h);
      }
    }

    // Fallback if API results are thin
    if (displayList.length < 3) {
      displayList.add(Hospital(
        name: "Phòng khám Đa khoa Thu Cúc",
        address: "286 Thụy Khuê, Tây Hồ, Hà Nội",
        openStatus: "Đang mở cửa",
        lat: 21.0375,
        lng: 105.8038,
      ));
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        title: const Row(
          children: [
            Icon(Icons.location_on_rounded, color: Color(0xFF006B70)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Đề xuất cho bạn",
                style: TextStyle(
                  fontSize: 18,
                  color: Color(0xFF006B70),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: displayList.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildHospitalCard(
                ctx,
                h.name,
                "Cách đây ~1km", 
                h.openStatus,
                photoUrl: h.photoUrl,
                lat: h.lat,
                lng: h.lng,
                address: h.address,
              ),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Đóng",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalCard(
    BuildContext ctx,
    String name,
    String distance,
    String status, {
    bool isEmergency = false,
    String? photoUrl,
    double lat = 0.0,
    double lng = 0.0,
    String address = "",
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        final hospital = Hospital(
          name: name,
          address: address,
          openStatus: status,
          lat: lat,
          lng: lng,
          photoUrl: photoUrl,
        );
        ref.read(navigationProvider.notifier).setHospital(hospital, null, null);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isEmergency
                ? Colors.red.withOpacity(0.3)
                : const Color(0xFFE5F1F1),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFF4FAFA),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: photoUrl != null 
                ? (photoUrl.startsWith('http') 
                    ? Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.local_hospital_rounded, color: Color(0xFF006A71), size: 28))
                    : Image.asset(photoUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.local_hospital_rounded, color: Color(0xFF006A71), size: 28)))
                : const Icon(Icons.local_hospital_rounded, color: Color(0xFF006A71), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    distance,
                    style: const TextStyle(
                      color: Color(0xFF7F8C8D),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: TextStyle(
                      color: isEmergency ? Colors.red : Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.directions_rounded,
                color: Colors.blueAccent,
                size: 28,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                final hospital = Hospital(name: name, address: address, openStatus: status, lat: lat, lng: lng, photoUrl: photoUrl);
                ref.read(navigationProvider.notifier).setHospital(hospital, null, null);
              },
            ),
          ],
        ),
      ),
    );
  }
}
