import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api_client.dart';
import '../../router/route_config.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _requestPermission() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final status = await Permission.locationWhenInUse.request();

      if (!mounted) return;

      if (status.isGranted) {
        await _notifyBackend();
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _error =
              'Location permission is permanently denied. Please enable it in Settings.';
          _isLoading = false;
        });
        await openAppSettings();
      } else {
        setState(() {
          _error = 'Location permission is required to continue.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'An error occurred: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _notifyBackend() async {
    try {
      final response =
          await ApiClient.post('/onboarding/location-permission', {});

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _error = 'Server error (${response.statusCode}). Please try again.';
          _isLoading = false;
        });
        return;
      }

      // Use `next_step` from the POST response directly.
      // `home_location` is handled inside TravelPatternScreen, so map it
      // to travel_patterns here.
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      String? nextStep = body['next_step'] as String?;
      if (nextStep == 'home_location') nextStep = 'travel_patterns';

      if (nextStep != null) {
        if (!mounted) return;
        context.go(Routes.fromResumeStep(nextStep));
        return;
      }

      // Fallback: fetch onboarding state from /auth/me.
      final me = await ApiClient.fetchMe();
      if (!mounted) return;
      context.go(Routes.fromResumeStep(_resolveNextStep(me)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save progress: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Walks the `steps` list from /auth/me and returns the first step that is
  /// not yet completed, skipping email_verification when email is already
  /// verified in the step data (backend quirk: completed stays false).
  String? _resolveNextStep(Map<String, dynamic>? me) {
    final onboarding = me?['onboarding'] as Map<String, dynamic>?;
    if (onboarding == null) return null;
    final steps = onboarding['steps'] as List?;
    if (steps == null) return onboarding['resume_step'] as String?;
    for (final s in steps) {
      final m = s as Map<String, dynamic>;
      if (m['completed'] == true) continue;
      // Backend marks email_verification as completed=false even when the
      // email is actually verified — skip it in that case.
      if (m['step'] == 'email_verification') {
        final data = m['data'] as Map<String, dynamic>?;
        if (data?['email_verified'] == true) continue;
      }
      return m['step'] as String?;
    }
    return null; // all steps done → home
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Access'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                Icons.location_on_outlined,
                size: 80,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(height: 24),
              Text(
                'Enable Location',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'GuideME uses your location to provide real-time travel alerts '
                'and route monitoring along your daily trips.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              ElevatedButton(
                onPressed: _isLoading ? null : _requestPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Allow Location Access',
                        style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
