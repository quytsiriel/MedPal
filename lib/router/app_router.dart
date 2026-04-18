import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/home_screen.dart';
import '../screens/symptom_screen.dart';
import '../screens/prescription_screen.dart';
import '../screens/navigation_screen.dart';
import '../services/map_service.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: _rootNavigatorKey,
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return ScaffoldWithNavBar(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/symptoms',
          builder: (context, state) => const SymptomScreen(),
        ),
        GoRoute(
          path: '/prescriptions',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PrescriptionScreen(),
          ),
        ),
        GoRoute(
          path: '/navigation',
          pageBuilder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return NoTransitionPage(
              child: NavigationScreen(
                targetHospital: extra?['hospital'] as Hospital?,
                userLat: extra?['userLat'] as double?,
                userLng: extra?['userLng'] as double?,
                targetDepartment: extra?['department'] as String?,
              ),
            );
          },
        ),
      ],
    ),
  ],
);

class ScaffoldWithNavBar extends StatelessWidget {
  final Widget child;
  const ScaffoldWithNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    // Show header only for the 3 main tabs
    final bool showHeader = location == '/' || 
                             location == '/navigation' || 
                             location == '/prescriptions';

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: SafeArea(
        child: Column(
          children: [
            if (showHeader) _buildPersistentHeader(context),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _calculateSelectedIndex(context),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF006B70),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/navigation');
              break;
            case 2:
              context.go('/prescriptions');
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.medical_services_rounded),
            label: 'Khám bệnh',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_rounded),
            label: 'Điều hướng',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Đơn thuốc',
          ),
        ],
      ),
    );
  }

  Widget _buildPersistentHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Row(
        children: [
          Image.asset('assets/mascot.png', width: 44, height: 44),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MedPal',
                style: GoogleFonts.lexend(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold, 
                  color: const Color(0xFF006B70),
                  height: 1.1,
                ),
              ),
              Text(
                'Người bạn đồng hành y tế của bạn',
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/navigation')) return 1;
    if (location.startsWith('/prescriptions')) return 2;
    return 0;
  }
}

