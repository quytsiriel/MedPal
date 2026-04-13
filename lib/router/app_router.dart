import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/symptom_screen.dart';
import '../screens/navigation_screen.dart';
import '../screens/prescription_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
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
      path: '/navigation',
      builder: (context, state) => const NavigationScreen(),
    ),
    GoRoute(
      path: '/prescriptions',
      builder: (context, state) => const PrescriptionScreen(),
    ),
  ],
);
