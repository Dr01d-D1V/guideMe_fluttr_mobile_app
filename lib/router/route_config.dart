import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/intro_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/email_verification_screen.dart';
import '../screens/otp_verification_screen.dart';
import '../screens/onboarding/email_verified_screen.dart';
import '../screens/onboarding/agent_intro_screen.dart';
import '../screens/onboarding/location_permission_screen.dart';
import '../screens/onboarding/home_location_screen.dart';
import '../screens/onboarding/travel_pattern_screen.dart';
import '../screens/onboarding/route_selection_screen.dart';
import '../screens/onboarding/alert_preferences_screen.dart';

/// Named route path constants used throughout the app.
class Routes {
  static const splash = '/';
  static const intro = '/intro';
  static const signup = '/signup';
  static const login = '/login';
  static const home = '/home';
  static const emailVerification = '/email-verification';
  static const otpVerification = '/otp-verification';
  static const onboardingVerified = '/onboarding/verified';
  static const onboardingIntro = '/onboarding/intro';
  static const locationPermission = '/onboarding/location-permission';
  static const homeLocation = '/onboarding/home-location';
  static const onboardingTravelPatterns = '/onboarding/travel-patterns';
  static const onboardingRoutes = '/onboarding/routes';
  static const onboardingAlertPreferences = '/onboarding/alert-preferences';

  /// Maps a `resume_step` string from GET /auth/me to the corresponding route.
  /// `home_location` is collected inside TravelPatternScreen, so it maps
  /// directly to travel-patterns.
  static String fromResumeStep(String? step) {
    switch (step) {
      case 'email_verification':
        return emailVerification;
      case 'location_permission':
        return locationPermission;
      case 'home_location': // home location is captured in travel_patterns
      case 'travel_patterns':
        return onboardingTravelPatterns;
      case 'alert_preferences':
        return onboardingAlertPreferences;
      default:
        return home;
    }
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: Routes.splash,
  routes: [
    GoRoute(
      path: Routes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: Routes.intro,
      builder: (context, state) => const IntroScreen(),
    ),
    GoRoute(
      path: Routes.signup,
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: Routes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: Routes.emailVerification,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return EmailVerificationScreen(
          email: extra['email'] as String? ?? '',
          user: extra['user'] as Map<String, dynamic>?,
        );
      },
    ),
    GoRoute(
      path: Routes.otpVerification,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return OtpVerificationScreen(
          contact: extra['contact'] as String,
          deviceId: extra['deviceId'] as String,
          preAuthSessionId: extra['preAuthSessionId'] as String,
        );
      },
    ),
    GoRoute(
      path: Routes.onboardingVerified,
      builder: (context, state) => const EmailVerifiedScreen(),
    ),
    GoRoute(
      path: Routes.onboardingIntro,
      builder: (context, state) => const AgentIntroScreen(),
    ),
    GoRoute(
      path: Routes.locationPermission,
      builder: (context, state) => const LocationPermissionScreen(),
    ),
    GoRoute(
      path: Routes.homeLocation,
      builder: (context, state) => const HomeLocationScreen(),
    ),
    GoRoute(
      path: Routes.onboardingTravelPatterns,
      builder: (context, state) => const TravelPatternScreen(),
    ),
    GoRoute(
      path: Routes.onboardingRoutes,
      builder: (context, state) => const RouteSelectionScreen(),
    ),
    GoRoute(
      path: Routes.onboardingAlertPreferences,
      builder: (context, state) => const AlertPreferencesScreen(),
    ),
  ],
);
