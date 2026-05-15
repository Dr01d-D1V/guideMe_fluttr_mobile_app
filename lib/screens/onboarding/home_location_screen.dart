import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/api_client.dart';
import '../../router/route_config.dart';

class HomeLocationScreen extends StatefulWidget {
  const HomeLocationScreen({super.key});

  @override
  State<HomeLocationScreen> createState() => _HomeLocationScreenState();
}

class _HomeLocationScreenState extends State<HomeLocationScreen> {
  static const _defaultPosition = LatLng(33.6844, 73.0479); // Islamabad

  GoogleMapController? _ctrl;
  final _labelCtrl = TextEditingController();

  LatLng? _tappedLocation;
  String? _suggestedAddress;
  bool _locationPermGranted = false;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    setState(() {
      _locationPermGranted = status == LocationPermission.always ||
          status == LocationPermission.whileInUse;
    });
  }

  Future<void> _onLongPress(LatLng latLng) async {
    setState(() {
      _tappedLocation = latLng;
      _suggestedAddress = null;
      _error = null;
    });
    final address = await _reverseGeocode(latLng);
    if (address != null && mounted) {
      setState(() => _suggestedAddress = address);
    }
  }

  Future<String?> _reverseGeocode(LatLng pos) async {
    try {
      final key = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      if (key.isEmpty) return null;

      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}&key=$key',
      );
      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] == 'OK') {
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          return (results.first as Map)['formatted_address'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  String? _resolveNextStep(Map<String, dynamic>? me) {
    final onboarding = me?['onboarding'] as Map<String, dynamic>?;
    if (onboarding == null) return null;
    final steps = onboarding['steps'] as List?;
    if (steps == null) return onboarding['resume_step'] as String?;
    for (final s in steps) {
      final m = s as Map<String, dynamic>;
      if (m['completed'] == true) continue;
      if (m['step'] == 'email_verification') {
        final data = m['data'] as Map<String, dynamic>?;
        if (data?['email_verified'] == true) continue;
      }
      return m['step'] as String?;
    }
    return null;
  }

  Future<void> _confirmLocation() async {
    if (_tappedLocation == null) return;

    _labelCtrl.text = _suggestedAddress ?? '';
    final address = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm home address'),
        content: TextField(
          controller: _labelCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. 5 Main Street, Islamabad',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = _labelCtrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (address == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiClient.post('/onboarding/home-location', {
        'location': {
          'name': 'Home',
          'latitude': _tappedLocation!.latitude,
          'longitude': _tappedLocation!.longitude,
          'address': address,
        },
      });

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _error = 'Server error (${response.statusCode}). Please try again.';
          _isLoading = false;
        });
        return;
      }

      // Use `next_step` from the POST response directly.
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final nextStep = body['next_step'] as String?;

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
          _error = 'Failed to save: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = _tappedLocation != null;
    final marker = hasPin
        ? {
            Marker(
              markerId: const MarkerId('home'),
              position: _tappedLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueViolet),
              infoWindow: const InfoWindow(title: 'Home'),
            ),
          }
        : <Marker>{};

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _ctrl = c,
            initialCameraPosition: const CameraPosition(
              target: _defaultPosition,
              zoom: 14,
            ),
            onLongPress: _onLongPress,
            markers: marker,
            myLocationEnabled: _locationPermGranted,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          // Top hint bar
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => context.pop(),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.arrow_back, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                hasPin
                                    ? Icons.home
                                    : Icons.touch_app_outlined,
                                size: 16,
                                color: const Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  hasPin
                                      ? (_suggestedAddress ?? 'Location selected')
                                      : 'Long-press to pin your home location',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: hasPin
                                        ? Colors.black87
                                        : Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Confirm button at bottom
          if (hasPin)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
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
                    : const Text('Set as Home Location',
                        style: TextStyle(fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }
}
