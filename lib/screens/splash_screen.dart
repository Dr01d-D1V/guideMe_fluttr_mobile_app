import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../router/route_config.dart';

/// Shown briefly on launch while the app checks login/intro state,
/// then immediately redirects to the appropriate screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so the UI thread is not blocked.
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
  }

  Future<void> _navigate() async {
    try {
      final loggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;

    if (loggedIn) {
      context.go(Routes.home);
      return;
    }

      final seenIntro = await AuthService.hasSeenIntro();
      if (!mounted) return;

      context.go(seenIntro ? Routes.signup : Routes.intro);
    } catch (_) {
      // Fallback: if SharedPreferences fails, send to signup.
      if (mounted) context.go(Routes.signup);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
