import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/dashboard/dashboard_shell.dart';

GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
      GoRoute(
          path: '/register',
          builder: (_, __) => const AuthScreen(startOnSignUp: true)),
      GoRoute(path: '/home', builder: (_, __) => const DashboardShell()),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final s = auth.status;
      if (s == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }
      final loggedIn = s == AuthStatus.authenticated;
      if (loggedIn) {
        if (loc == '/login' || loc == '/register' || loc == '/splash') {
          return '/home';
        }
        return null;
      } else {
        if (loc.startsWith('/home')) return '/login';
        return null;
      }
    },
  );
}
