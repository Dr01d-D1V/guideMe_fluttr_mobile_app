import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../router/route_config.dart';

class AlertPreferencesScreen extends ConsumerStatefulWidget {
  const AlertPreferencesScreen({super.key});

  @override
  ConsumerState<AlertPreferencesScreen> createState() =>
      _AlertPreferencesScreenState();
}

class _AlertPreferencesScreenState
    extends ConsumerState<AlertPreferencesScreen> {
  final Set<String> _selectedAlerts = {
    'traffic_congestion',
    'road_closure',
    'accident',
  };
  int _alertRadiusMeters = 2000;
  int _notifyBeforeMinutes = 30;
  bool _notifyEnRoute = true;
  bool _isLoading = false;

  static const _alertOptions = [
    _AlertOption(
      key: 'traffic_congestion',
      label: 'Traffic Congestion',
      description: 'Heavy or unusual traffic on your routes',
      icon: Icons.traffic,
      color: Color(0xFFF59E0B),
    ),
    _AlertOption(
      key: 'road_closure',
      label: 'Road Closures',
      description: 'Recently closed or blocked roads',
      icon: Icons.block,
      color: Color(0xFFEF4444),
    ),
    _AlertOption(
      key: 'accident',
      label: 'Accidents',
      description: 'Reported accidents ahead',
      icon: Icons.car_crash_outlined,
      color: Color(0xFFEF4444),
    ),
    _AlertOption(
      key: 'protest_riot',
      label: 'Protests & Riots',
      description: 'Civil unrest and crowd gatherings',
      icon: Icons.groups_outlined,
      color: Color(0xFFF97316),
    ),
    _AlertOption(
      key: 'terror_threat',
      label: 'Terror Threat Warnings',
      description: 'Intelligence or news warnings about attacks',
      icon: Icons.warning_amber_outlined,
      color: Color(0xFFDC2626),
    ),
    _AlertOption(
      key: 'security_deployment',
      label: 'Security Deployments',
      description: 'Police or military presence on routes',
      icon: Icons.local_police_outlined,
      color: Color(0xFF6366F1),
    ),
    _AlertOption(
      key: 'curfew',
      label: 'Curfews',
      description: 'Government-imposed movement restrictions',
      icon: Icons.nightlight_outlined,
      color: Color(0xFF8B5CF6),
    ),
    _AlertOption(
      key: 'flooding',
      label: 'Flooding',
      description: 'Flooded roads or waterlogged areas',
      icon: Icons.water_outlined,
      color: Color(0xFF0EA5E9),
    ),
    _AlertOption(
      key: 'road_construction',
      label: 'Road Construction',
      description: 'Active construction zones causing delays',
      icon: Icons.construction_outlined,
      color: Color(0xFFD97706),
    ),
    _AlertOption(
      key: 'vehicle_breakdown_obstruction',
      label: 'Broken-down Vehicles',
      description: 'Stalled vehicles blocking lanes',
      icon: Icons.car_repair_outlined,
      color: Color(0xFF64748B),
    ),
  ];

  Future<void> _finish() async {
    if (_selectedAlerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please select at least one alert type.'),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.saveAlertPreferences({
        'alert_traffic_congestion': _selectedAlerts.contains('traffic_congestion'),
        'alert_road_closures': _selectedAlerts.contains('road_closure'),
        'alert_accidents': _selectedAlerts.contains('accident'),
        'alert_construction': _selectedAlerts.contains('road_construction'),
        'alert_protests_riots': _selectedAlerts.contains('protest_riot'),
        'alert_terror_warnings': _selectedAlerts.contains('terror_threat'),
        'alert_police_deployment': _selectedAlerts.contains('security_deployment'),
        'alert_military_deployment': _selectedAlerts.contains('security_deployment'),
        'alert_curfew': _selectedAlerts.contains('curfew'),
        'alert_crime_reports': false,
        'alert_severe_weather': false,
        'alert_flooding': _selectedAlerts.contains('flooding'),
        'alert_poor_visibility': false,
        'alert_route_optimization': true,
        'notification_lead_time_minutes': _notifyBeforeMinutes,
        'quiet_hours_start': null,
        'quiet_hours_end': null,
      });
      if (mounted) context.go(Routes.home);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert Preferences'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(20),
          child: _StepIndicator(currentStep: 1, totalSteps: 2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'What do you want to be warned about?',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Your AI guard will alert you about these on your routes '
            'and around your destinations.',
            style: TextStyle(color: Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 20),
          ..._alertOptions.map(
            (opt) => _AlertToggleTile(
              option: opt,
              isSelected: _selectedAlerts.contains(opt.key),
              onToggle: (val) => setState(() {
                val
                    ? _selectedAlerts.add(opt.key)
                    : _selectedAlerts.remove(opt.key);
              }),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Text('Alert Radius',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Warn me about issues within '
            '${(_alertRadiusMeters / 1000).toStringAsFixed(1)} km of my route',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          Slider(
            value: _alertRadiusMeters.toDouble(),
            min: 500,
            max: 10000,
            divisions: 19,
            label: '${(_alertRadiusMeters / 1000).toStringAsFixed(1)} km',
            onChanged: (v) =>
                setState(() => _alertRadiusMeters = v.round()),
          ),
          const SizedBox(height: 16),
          const Text('Notify Me Before Departure',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '$_notifyBeforeMinutes minutes before each trip',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          Slider(
            value: _notifyBeforeMinutes.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            label: '$_notifyBeforeMinutes min',
            onChanged: (v) =>
                setState(() => _notifyBeforeMinutes = v.round()),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _notifyEnRoute,
            onChanged: (v) => setState(() => _notifyEnRoute = v),
            title: const Text('Alert me while travelling',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle:
                const Text('Get real-time alerts during your trip'),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: const Color(0xFF2563EB),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _finish,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Finish & Go to Home',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Data class ───────────────────────────────────────────────────────────────

class _AlertOption {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const _AlertOption({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

// ─── Toggle tile ──────────────────────────────────────────────────────────────

class _AlertToggleTile extends StatelessWidget {
  final _AlertOption option;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  const _AlertToggleTile({
    required this.option,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onToggle(!isSelected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? option.color.withValues(alpha: 0.07)
              : Colors.grey[50],
          border: Border.all(
            color: isSelected ? option.color : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
              color: option.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(option.icon, color: option.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    option.description,
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: isSelected,
              onChanged: (v) => onToggle(v ?? false),
              activeColor: option.color,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step indicator ──────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepIndicator(
      {required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: List.generate(totalSteps, (i) {
          final isActive = i <= currentStep;
          return Expanded(
            child: Padding(
              padding:
                  EdgeInsets.only(right: i < totalSteps - 1 ? 6 : 0),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF2563EB)
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
