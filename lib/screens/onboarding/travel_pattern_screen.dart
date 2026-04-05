import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/destination.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/api_service.dart';
import '../../router/route_config.dart';

class TravelPatternScreen extends ConsumerStatefulWidget {
  const TravelPatternScreen({super.key});

  @override
  ConsumerState<TravelPatternScreen> createState() =>
      _TravelPatternScreenState();
}

class _TravelPatternScreenState extends ConsumerState<TravelPatternScreen> {
  final _formKey = GlobalKey<FormState>();

  final _homeController = TextEditingController();
  final _officeController = TextEditingController();

  TimeOfDay _departHomeTime = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay _arriveOfficeTime = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _departOfficeTime = const TimeOfDay(hour: 17, minute: 30);
  TimeOfDay _arriveHomeTime = const TimeOfDay(hour: 18, minute: 45);
  List<String> _workDays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday'
  ];

  final List<_DestEntry> _destinations = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _homeController.dispose();
    _officeController.dispose();
    super.dispose();
  }

  String _timeToString(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(
      TimeOfDay current, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_homeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your home address.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final homeLocation = LocationResult(
      address: _homeController.text.trim(),
      lat: 0.0,
      lng: 0.0,
    );
    final officeAddress = _officeController.text.trim();
    final officeLocation = officeAddress.isNotEmpty
        ? LocationResult(address: officeAddress, lat: 0.0, lng: 0.0)
        : null;

    final destinations = _destinations.asMap().entries.map((e) {
      final entry = e.value;
      return Destination(
        id: 'dest_${e.key}',
        label: entry.label,
        address: entry.address,
        lat: 0.0,
        lng: 0.0,
        type: entry.type,
        daysOfWeek: entry.days,
        frequencyPerWeek: entry.days.length,
        trips: const [],
      );
    }).toList();

    final payload = {
      'home_location': homeLocation.toJson(),
      if (officeLocation != null) 'office_location': officeLocation.toJson(),
      'destinations': destinations.map((d) => d.toJson()).toList(),
      'work_schedule': {
        'days': _workDays,
        'depart_home_time': _timeToString(_departHomeTime),
        'arrive_office_time': _timeToString(_arriveOfficeTime),
        'depart_office_time': _timeToString(_departOfficeTime),
        'arrive_home_time': _timeToString(_arriveHomeTime),
        'intermediate_stops': [],
      },
    };

    try {
      final api = ref.read(apiServiceProvider);
      await api.saveTravelPatterns(payload);

      final notifier = ref.read(onboardingProvider.notifier);
      notifier.setHomeLocation(homeLocation);
      if (officeLocation != null) notifier.setOfficeLocation(officeLocation);
      notifier.setDestinations(destinations);

      if (mounted) context.go(Routes.onboardingRoutes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addDestination() async {
    final entry = await showModalBottomSheet<_DestEntry>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddDestinationSheet(),
    );
    if (entry != null) {
      setState(() => _destinations.add(entry));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Movement Patterns'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(20),
          child: _StepIndicator(currentStep: 0, totalSteps: 3),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _SectionHeader(title: 'Primary Locations'),
            TextFormField(
              controller: _homeController,
              decoration: const InputDecoration(
                labelText: 'Home Address',
                prefixIcon: Icon(Icons.home_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _officeController,
              decoration: const InputDecoration(
                labelText: 'Office / Work Address (optional)',
                prefixIcon: Icon(Icons.business_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(title: 'Work Days'),
            _DaySelector(
              selected: _workDays,
              onChanged: (days) => setState(() => _workDays = days),
            ),
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Daily Schedule'),
            _TimeTile(
              label: 'Leave Home',
              time: _departHomeTime,
              onTap: () => _pickTime(
                  _departHomeTime, (t) => setState(() => _departHomeTime = t)),
            ),
            _TimeTile(
              label: 'Arrive Office',
              time: _arriveOfficeTime,
              onTap: () => _pickTime(_arriveOfficeTime,
                  (t) => setState(() => _arriveOfficeTime = t)),
            ),
            _TimeTile(
              label: 'Leave Office',
              time: _departOfficeTime,
              onTap: () => _pickTime(_departOfficeTime,
                  (t) => setState(() => _departOfficeTime = t)),
            ),
            _TimeTile(
              label: 'Arrive Home',
              time: _arriveHomeTime,
              onTap: () => _pickTime(
                  _arriveHomeTime, (t) => setState(() => _arriveHomeTime = t)),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(title: 'Other Destinations'),
            Text(
              'Add gyms, markets, places of worship, or anywhere you visit regularly.',
              style:
                  TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            ..._destinations.map(
              (d) => _DestinationCard(
                entry: d,
                onDelete: () => setState(() => _destinations.remove(d)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addDestination,
              icon: const Icon(Icons.add),
              label: const Text('Add Destination'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _submit,
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
                        'Continue',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Internal data class ──────────────────────────────────────────────────────

class _DestEntry {
  final String label;
  final String address;
  final String type;
  final List<String> days;
  const _DestEntry(
      {required this.label,
      required this.address,
      required this.type,
      required this.days});
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style:
            const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  const _TimeTile(
      {required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final formatted = time.format(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: TextButton(
        onPressed: onTap,
        child: Text(
          formatted,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _DaySelector({required this.selected, required this.onChanged});

  static const _days = [
    ('monday', 'Mon'),
    ('tuesday', 'Tue'),
    ('wednesday', 'Wed'),
    ('thursday', 'Thu'),
    ('friday', 'Fri'),
    ('saturday', 'Sat'),
    ('sunday', 'Sun'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _days.map((entry) {
        final (key, label) = entry;
        final isSelected = selected.contains(key);
        return ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (val) {
            final newDays = List<String>.from(selected);
            val ? newDays.add(key) : newDays.remove(key);
            onChanged(newDays);
          },
        );
      }).toList(),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final _DestEntry entry;
  final VoidCallback onDelete;
  const _DestinationCard({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.place_outlined),
        title: Text(entry.label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(entry.address),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

// ─── Add Destination Bottom Sheet ─────────────────────────────────────────────

class _AddDestinationSheet extends StatefulWidget {
  const _AddDestinationSheet();

  @override
  State<_AddDestinationSheet> createState() => _AddDestinationSheetState();
}

class _AddDestinationSheetState extends State<_AddDestinationSheet> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();
  String _type = 'leisure';
  final List<String> _days = ['saturday'];

  static const _types = [
    ('work_stop', 'Work Stop'),
    ('leisure', 'Leisure'),
    ('errand', 'Errand'),
  ];

  static const _allDays = [
    ('monday', 'Mon'),
    ('tuesday', 'Tue'),
    ('wednesday', 'Wed'),
    ('thursday', 'Thu'),
    ('friday', 'Fri'),
    ('saturday', 'Sat'),
    ('sunday', 'Sun'),
  ];

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Destination',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Name (e.g. Gym, Market)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: _types
                .map((e) => DropdownMenuItem(
                    value: e.$1, child: Text(e.$2)))
                .toList(),
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 12),
          const Text('Usual days:',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: _allDays.map((entry) {
              final (key, label) = entry;
              final isSelected = _days.contains(key);
              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    val ? _days.add(key) : _days.remove(key);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final label = _labelController.text.trim();
                final address = _addressController.text.trim();
                if (label.isEmpty || address.isEmpty) return;
                Navigator.pop(
                  context,
                  _DestEntry(
                    label: label,
                    address: address,
                    type: _type,
                    days: List.from(_days),
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }
}

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
