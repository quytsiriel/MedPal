import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/symptom_screen.dart';
import '../screens/navigation_screen.dart';
import '../screens/prescription_screen.dart';
import '../screens/scaffold_with_bottom_nav.dart';

// Global key for root navigator
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: _rootNavigatorKey,
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return ScaffoldWithBottomNav(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (context, state) {
            final followup = state.uri.queryParameters['followup'] == 'true';
            return HomeScreen(isFollowUp: followup);
          },
        ),
        GoRoute(
          path: '/symptoms',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (context, state) => const SymptomScreen(),
        ),
        GoRoute(
          path: '/navigation',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (context, state) => const NavigationScreen(),
        ),
        GoRoute(
          path: '/prescriptions',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (context, state) => const PrescriptionScreen(),
        ),
      ],
    ),
  ],
);
