import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/symptom_screen.dart';
import '../screens/navigation_screen.dart';
import '../screens/prescription_screen.dart';
import '../screens/scaffold_with_bottom_nav.dart';

// Global key for root navigator
final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: _rootNavigatorKey,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ScaffoldWithBottomNav(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) {
                final followup = state.uri.queryParameters['followup'] == 'true';
                return HomeScreen(isFollowUp: followup);
              },
            ),
            GoRoute(
              path: '/symptoms',
              builder: (context, state) => const SymptomScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/navigation',
              builder: (context, state) => const NavigationScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/prescriptions',
              builder: (context, state) => const PrescriptionScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
