import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/symptoms',
          builder: (context, state) => const SymptomScreen(),
        ),
        GoRoute(
          path: '/prescriptions',
          builder: (context, state) => const PrescriptionScreen(),
        ),
        GoRoute(
          path: '/navigation',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return NavigationScreen(
              targetHospital: extra?['hospital'] as Hospital?,
              userLat: extra?['userLat'] as double?,
              userLng: extra?['userLng'] as double?,
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
    return Scaffold(
      body: child,
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

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/navigation')) return 1;
    if (location.startsWith('/prescriptions')) return 2;
    return 0;
  }
}

