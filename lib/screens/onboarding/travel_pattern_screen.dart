import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../models/destination.dart';
import '../../models/route_entry.dart';
import '../../services/api_service.dart';
import '../../router/route_config.dart';

// ─── Transport mode ───────────────────────────────────────────────────────────

enum _Transport {
  car(Icons.directions_car_rounded, 'Car'),
  bus(Icons.directions_bus_rounded, 'Bus'),
  train(Icons.train_rounded, 'Train'),
  walk(Icons.directions_walk_rounded, 'Walk'),
  bike(Icons.pedal_bike_rounded, 'Bike'),
  taxi(Icons.local_taxi_rounded, 'Taxi');

  const _Transport(this.icon, this.label);
  final IconData icon;
  final String label;
}

// Action presented when the user taps an already-set location button.
enum _LocationChoice { rename, change }

// ─── Stop entry ───────────────────────────────────────────────────────────────
// Each stop has a location, optional arrive time, and optional depart time.
// Very first stop of day → no arriveTime. Very last stop of day → no departTime.

class _StopEntry {
  LocationResult? location;
  String label = '';
  TimeOfDay? arriveTime;
  TimeOfDay? departTime;

  _StopEntry({this.arriveTime, this.departTime});
}

// ─── Segment routes ───────────────────────────────────────────────────────────

class _SegmentRoutes {
  List<RouteOption> routes = [];
  int selectedIndex = 0;
  bool isLoading = false;
  String? error;
}

// ─── Trip entry ───────────────────────────────────────────────────────────────

class _TripEntry {
  _Transport transport = _Transport.car;
  List<_StopEntry> stops = [];
  List<_SegmentRoutes> segmentRoutes = [];

  _TripEntry() {
    stops = [
      _StopEntry(departTime: const TimeOfDay(hour: 7, minute: 30)),
      _StopEntry(arriveTime: const TimeOfDay(hour: 8, minute: 0)),
    ];
    segmentRoutes = [_SegmentRoutes()];
  }

  _TripEntry.copy(_TripEntry src) {
    transport = src.transport;
    stops = src.stops.map((s) {
      final c = _StopEntry(arriveTime: s.arriveTime, departTime: s.departTime);
      c.location = s.location;
      c.label = s.label;
      return c;
    }).toList();
    segmentRoutes = src.segmentRoutes.map((sr) {
      final copy = _SegmentRoutes();
      copy.routes = List.from(sr.routes);
      copy.selectedIndex = sr.selectedIndex;
      return copy;
    }).toList();
  }

  int get segmentCount => stops.length - 1;

  bool segmentReady(int segIdx) =>
      stops[segIdx].location != null && stops[segIdx + 1].location != null;
}

// ─── Main screen ──────────────────────────────────────────────────────────────

class TravelPatternScreen extends ConsumerStatefulWidget {
  const TravelPatternScreen({super.key});

  @override
  ConsumerState<TravelPatternScreen> createState() =>
      _TravelPatternScreenState();
}

class _TravelPatternScreenState extends ConsumerState<TravelPatternScreen>
    with TickerProviderStateMixin {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayFull = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];
  static const _dayKeys = [
    'monday', 'tuesday', 'wednesday', 'thursday',
    'friday', 'saturday', 'sunday'
  ];

  // Per-trip polyline colour palette (index 0 is reserved for the active trip).
  static const _tripPalette = [
    Color(0xFFEA580C), // orange
    Color(0xFF7C3AED), // purple
    Color(0xFF059669), // emerald
    Color(0xFFDB2777), // pink
    Color(0xFF0891B2), // cyan
    Color(0xFFD97706), // amber
  ];

  int _selectedDay = 0;
  int? _activeTripIdx;
  final Map<int, List<_TripEntry>> _tripsByDay = {
    for (int i = 0; i < 7; i++) i: [],
  };

  // Panel split fraction (0.12 = collapsed, 0.55 = default, 0.92 = expanded)
  double _panelFraction = 0.55;
  late final AnimationController _snapController;
  late Animation<double> _snapAnimation;
  final ScrollController _listScrollController = ScrollController();

  GoogleMapController? _mapController;
  LatLng _mapCenter = const LatLng(9.0579, 7.4951);
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isSubmitting = false;
  bool _locationPermGranted = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    // Keep _panelFraction in sync during snap animations
    _snapController.addListener(() {
      if (mounted) setState(() => _panelFraction = _snapAnimation.value);
    });
    _snapAnimation = Tween<double>(begin: 0.55, end: 0.55)
        .animate(_snapController);
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _snapController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _animatePanelTo(double target) {
    _snapAnimation = Tween<double>(
      begin: _panelFraction,
      end: target,
    ).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOut),
    );
    _snapController.forward(from: 0);
  }

  Future<void> _loadCurrentLocation() async {
    try {
      var status = await Geolocator.checkPermission();
      if (status == LocationPermission.denied) {
        status = await Geolocator.requestPermission();
      }
      final granted = status == LocationPermission.always ||
          status == LocationPermission.whileInUse;
      if (mounted) setState(() => _locationPermGranted = granted);

      if (granted) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        if (mounted) {
          setState(() => _mapCenter = LatLng(pos.latitude, pos.longitude));
          _mapController?.animateCamera(CameraUpdate.newLatLng(_mapCenter));
        }
      }
    } catch (_) {}
  }

  List<_TripEntry> get _currentTrips => _tripsByDay[_selectedDay]!;

  bool _isVeryFirstStop(int tripIdx, int stopIdx) =>
      tripIdx == 0 && stopIdx == 0;

  bool _isVeryLastStop(int tripIdx, int stopIdx) =>
      tripIdx == _currentTrips.length - 1 &&
      stopIdx == _currentTrips[tripIdx].stops.length - 1;

  // ─── Map overlays ─────────────────────────────────────────────────────────

  void _refreshMapOverlays() {
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    for (int t = 0; t < _currentTrips.length; t++) {
      final trip = _currentTrips[t];
      for (int s = 0; s < trip.stops.length; s++) {
        final stop = trip.stops[s];
        if (stop.location == null) continue;
        final pos = LatLng(stop.location!.lat, stop.location!.lng);
        final isFirst = s == 0;
        final isLast = s == trip.stops.length - 1;
        markers.add(Marker(
          markerId: MarkerId('stop_${_selectedDay}_${t}_$s'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isFirst
                ? BitmapDescriptor.hueGreen
                : isLast
                    ? BitmapDescriptor.hueRed
                    : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: stop.label.isNotEmpty ? stop.label : 'Stop ${s + 1}',
          ),
        ));
      }

      for (int seg = 0; seg < trip.segmentCount; seg++) {
        if (seg >= trip.segmentRoutes.length) continue;
        final sr = trip.segmentRoutes[seg];
        final fromStop = trip.stops[seg];
        final toStop = trip.stops[seg + 1];
        if (fromStop.location == null || toStop.location == null) continue;

        if (sr.routes.isNotEmpty && sr.selectedIndex < sr.routes.length) {
          final route = sr.routes[sr.selectedIndex];
          if (route.points.isNotEmpty) {
            // Each trip always gets its own palette colour.
            // When a specific trip is tapped, it gets the blue active colour
            // and others are dimmed; when nothing is selected every trip is
            // shown at full opacity in its own colour.
            final hasSelection = _activeTripIdx != null;
            final isSelected = _activeTripIdx == t;
            final paletteColor = _tripPalette[t % _tripPalette.length];
            final Color lineColor;
            final int lineWidth;
            final int lineZIndex;
            if (!hasSelection) {
              lineColor = paletteColor;
              lineWidth = 4;
              lineZIndex = 0;
            } else if (isSelected) {
              lineColor = const Color(0xFF2563EB);
              lineWidth = 5;
              lineZIndex = 1;
            } else {
              lineColor = paletteColor.withValues(alpha: 0.40);
              lineWidth = 3;
              lineZIndex = 0;
            }
            polylines.add(Polyline(
              polylineId: PolylineId('seg_${_selectedDay}_${t}_$seg'),
              color: lineColor,
              width: lineWidth,
              points: route.points
                  .map((p) => LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
                  .toList(),
              zIndex: lineZIndex,
            ));
          }
        }
      }
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  // ─── Route fetching ───────────────────────────────────────────────────────

  Future<void> _fetchSegment(int dayIdx, int tripIdx, int segIdx) async {
    final trip = _tripsByDay[dayIdx]![tripIdx];
    if (!trip.segmentReady(segIdx)) return;
    if (segIdx >= trip.segmentRoutes.length) return;

    setState(() {
      trip.segmentRoutes[segIdx].isLoading = true;
      trip.segmentRoutes[segIdx].error = null;
      trip.segmentRoutes[segIdx].routes = [];
    });

    try {
      final fromLoc = trip.stops[segIdx].location!;
      final toLoc = trip.stops[segIdx + 1].location!;
      final api = ref.read(apiServiceProvider);
      final routes = await api.fetchRouteOptions(
        fromLoc.lat, fromLoc.lng,
        toLoc.lat, toLoc.lng,
      );
      if (mounted) {
        setState(() {
          trip.segmentRoutes[segIdx].routes = routes;
          trip.segmentRoutes[segIdx].selectedIndex = 0;
          trip.segmentRoutes[segIdx].isLoading = false;
        });
        _refreshMapOverlays();
        _recalcArrivalTimes(dayIdx, tripIdx);
        // Fit the camera to the fetched route polyline
        if (routes.isNotEmpty && routes.first.points.isNotEmpty) {
          final pts = routes.first.points
              .map((p) => LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
              .toList();
          final lats = pts.map((p) => p.latitude);
          final lngs = pts.map((p) => p.longitude);
          final bounds = LatLngBounds(
            southwest: LatLng(lats.reduce((a, b) => a < b ? a : b),
                lngs.reduce((a, b) => a < b ? a : b)),
            northeast: LatLng(lats.reduce((a, b) => a > b ? a : b),
                lngs.reduce((a, b) => a > b ? a : b)),
          );
          _mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 60),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          trip.segmentRoutes[segIdx].isLoading = false;
          trip.segmentRoutes[segIdx].error = e.toString();
        });
      }
    }
  }

  // ─── Auto-calculate arrival times ─────────────────────────────────────────
  //
  // For each segment in a trip, arrival time at stop[seg+1] =
  // stop[seg].departTime + selectedRoute.durationMinutes.

  void _recalcArrivalTimes(int dayIdx, int tripIdx) {
    final trip = _tripsByDay[dayIdx]?[tripIdx];
    if (trip == null) return;
    for (int seg = 0; seg < trip.segmentCount; seg++) {
      final departTime = trip.stops[seg].departTime;
      if (departTime == null) continue;
      final durationMins = (seg < trip.segmentRoutes.length &&
              trip.segmentRoutes[seg].routes.isNotEmpty)
          ? trip.segmentRoutes[seg]
              .routes[trip.segmentRoutes[seg].selectedIndex]
              .durationMinutes
          : 0;
      final totalMins =
          departTime.hour * 60 + departTime.minute + durationMins;
      setState(() {
        trip.stops[seg + 1].arriveTime = TimeOfDay(
          hour: (totalMins ~/ 60) % 24,
          minute: totalMins % 60,
        );
      });
    }
  }

  // ─── Rename an existing stop label without re-picking coords ─────────────

  Future<void> _renameLocation(int tripIdx, int stopIdx) async {
    final stop = _currentTrips[tripIdx].stops[stopIdx];
    final ctrl = TextEditingController(text: stop.label);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename location'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(border: OutlineInputBorder()),
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
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newLabel != null && mounted) {
      setState(() =>
          _tripsByDay[_selectedDay]![tripIdx].stops[stopIdx].label = newLabel);
    }
  }

  // ─── Location picker ──────────────────────────────────────────────────────

  Future<void> _pickLocation(int tripIdx, int stopIdx) async {
    final stop = _currentTrips[tripIdx].stops[stopIdx];

    // Already has a location — offer rename or change
    if (stop.location != null) {
      final choice = await showModalBottomSheet<_LocationChoice>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: Color(0xFF2563EB)),
                title: const Text('Rename label'),
                subtitle: Text(stop.label,
                    style: TextStyle(color: Colors.grey[500])),
                onTap: () =>
                    Navigator.pop(context, _LocationChoice.rename),
              ),
              ListTile(
                leading: const Icon(Icons.place_outlined,
                    color: Color(0xFF2563EB)),
                title: const Text('Change location'),
                onTap: () =>
                    Navigator.pop(context, _LocationChoice.change),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == _LocationChoice.rename) {
        await _renameLocation(tripIdx, stopIdx);
        return;
      }
      // _LocationChoice.change falls through to the full picker below
    }

    final initial = stop.location != null
        ? LatLng(stop.location!.lat, stop.location!.lng)
        : _mapCenter;

    // Collect all previously pinned locations across all days (deduplicated).
    final seen = <String>{};
    final knownLocations = <LocationResult>[];
    for (final trips in _tripsByDay.values) {
      for (final trip in trips) {
        for (final s in trip.stops) {
          if (s.location == null) continue;
          final key = '${s.location!.lat},${s.location!.lng}';
          if (seen.add(key)) knownLocations.add(s.location!);
        }
      }
    }

    final result = await Navigator.of(context).push<LocationResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LocationPickerScreen(
          initialPosition: initial,
          knownLocations: knownLocations,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _tripsByDay[_selectedDay]![tripIdx].stops[stopIdx].location = result;
      _tripsByDay[_selectedDay]![tripIdx].stops[stopIdx].label = result.address;
    });
    _refreshMapOverlays();

    final trip = _tripsByDay[_selectedDay]![tripIdx];
    if (stopIdx > 0 && trip.segmentReady(stopIdx - 1)) {
      await _fetchSegment(_selectedDay, tripIdx, stopIdx - 1);
    }
    if (stopIdx < trip.segmentCount && trip.segmentReady(stopIdx)) {
      await _fetchSegment(_selectedDay, tripIdx, stopIdx);
    }
  }

  // ─── Add waypoint ─────────────────────────────────────────────────────────

  void _addWaypoint(int tripIdx) {
    final trip = _tripsByDay[_selectedDay]![tripIdx];
    final insertAt = trip.stops.length - 1;
    setState(() {
      trip.stops.insert(
        insertAt,
        _StopEntry(
          arriveTime: const TimeOfDay(hour: 12, minute: 0),
          departTime: const TimeOfDay(hour: 12, minute: 30),
        ),
      );
      trip.segmentRoutes.insert(insertAt, _SegmentRoutes());
      if (insertAt < trip.segmentRoutes.length) {
        trip.segmentRoutes[insertAt].routes = [];
        trip.segmentRoutes[insertAt].error = null;
      }
    });
  }

  // ─── Remove stop ──────────────────────────────────────────────────────────

  Future<void> _removeStop(int tripIdx, int stopIdx) async {
    final trip = _tripsByDay[_selectedDay]![tripIdx];
    if (trip.stops.length <= 2) return;

    // Middle stop removal: the surviving segment at segIdx will now span
    // prev→next and has stale route data — it needs to be cleared + re-fetched.
    final isMiddle = stopIdx > 0 && stopIdx < trip.stops.length - 1;
    final segIdx = stopIdx > 0 ? stopIdx - 1 : 0;

    setState(() {
      trip.stops.removeAt(stopIdx);
      if (segIdx < trip.segmentRoutes.length) {
        trip.segmentRoutes.removeAt(segIdx);
      }
      // Clear the now-merged segment's stale route data
      if (isMiddle && segIdx < trip.segmentRoutes.length) {
        trip.segmentRoutes[segIdx].routes = [];
        trip.segmentRoutes[segIdx].error = null;
      }
    });
    _refreshMapOverlays();

    // Re-fetch the merged segment if both endpoints are known
    if (isMiddle &&
        segIdx < trip.segmentRoutes.length &&
        trip.segmentReady(segIdx)) {
      await _fetchSegment(_selectedDay, tripIdx, segIdx);
    }
  }

  // ─── Time picker ──────────────────────────────────────────────────────────

  Future<void> _pickStopTime(int tripIdx, int stopIdx, bool isDeparture) async {
    final stop = _currentTrips[tripIdx].stops[stopIdx];
    final current = isDeparture
        ? (stop.departTime ?? const TimeOfDay(hour: 8, minute: 0))
        : (stop.arriveTime ?? const TimeOfDay(hour: 9, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !mounted) return;
    setState(() {
      if (isDeparture) {
        _tripsByDay[_selectedDay]![tripIdx].stops[stopIdx].departTime = picked;
      } else {
        _tripsByDay[_selectedDay]![tripIdx].stops[stopIdx].arriveTime = picked;
      }
    });
    // After changing departure time, recalculate downstream arrival times.
    if (isDeparture) _recalcArrivalTimes(_selectedDay, tripIdx);
  }

  // ─── Copy day sheet ───────────────────────────────────────────────────────

  Future<void> _showCopyDaySheet() async {
    if (_currentTrips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trips on this day to copy.')),
      );
      return;
    }

    final selected = List<bool>.generate(7, (_) => false);
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Copy trips to other days',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Copies all trips from ${_dayFull[_selectedDay]}. You can edit any day afterward.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (i) {
                      if (i == _selectedDay) {
                        return Chip(
                          label: Text(_dayFull[i]),
                          backgroundColor: const Color(0xFFEFF6FF),
                          labelStyle: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w600),
                          avatar: const Icon(Icons.check_circle,
                              size: 16, color: Color(0xFF2563EB)),
                        );
                      }
                      final isOn = selected[i];
                      return FilterChip(
                        label: Text(_dayFull[i]),
                        selected: isOn,
                        onSelected: (v) =>
                            setSheetState(() => selected[i] = v),
                        selectedColor: const Color(0xFFEFF6FF),
                        checkmarkColor: const Color(0xFF2563EB),
                        labelStyle: TextStyle(
                          color: isOn
                              ? const Color(0xFF2563EB)
                              : Colors.black87,
                          fontWeight:
                              isOn ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isOn
                              ? const Color(0xFF2563EB)
                              : Colors.grey[300]!,
                        ),
                      );
                    }),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errorMsg!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 12)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      final targets = List.generate(7, (i) => i)
                          .where((i) => selected[i])
                          .toList();
                      if (targets.isEmpty) {
                        setSheetState(
                            () => errorMsg = 'Select at least one day.');
                        return;
                      }
                      setState(() {
                        for (final day in targets) {
                          _tripsByDay[day] = _currentTrips
                              .map((t) => _TripEntry.copy(t))
                              .toList();
                        }
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Copied to ${targets.map((i) => _dayFull[i]).join(', ')}',
                          ),
                          backgroundColor: const Color(0xFF2563EB),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('Copy trips'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  /// Returns true if [label] looks like a home address.
  static bool _isHomeLabel(String label) {
    final l = label.toLowerCase().trim();
    return l == 'home' ||
        l == 'house' ||
        l == 'my home' ||
        l == 'my house' ||
        l.startsWith('home ') ||
        l.endsWith(' home');
  }

  Future<void> _submit() async {
    final allTrips = _tripsByDay.values
        .expand((list) => list)
        .where((t) => t.stops.every((s) => s.location != null))
        .toList();

    if (allTrips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please complete at least one trip with all locations set.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final tripPayloads = <Map<String, dynamic>>[];
      final routeSelections = <Map<String, dynamic>>[];
      LocationResult? homeLocation;

      for (int d = 0; d < 7; d++) {
        final trips = _tripsByDay[d]!;
        for (int ti = 0; ti < trips.length; ti++) {
          final trip = trips[ti];
          if (trip.stops.any((s) => s.location == null)) continue;

          final stopPayloads = trip.stops.asMap().entries.map((e) {
            final idx = e.key;
            final s = e.value;

            // Capture the first stop labelled "home" (or synonym).
            if (homeLocation == null && _isHomeLabel(s.label)) {
              homeLocation = s.location;
            }

            return {
              'location': s.location!.toJson(),
              'label': s.label,
              if (s.arriveTime != null)
                'arrive_time':
                    '${s.arriveTime!.hour.toString().padLeft(2, '0')}:'
                    '${s.arriveTime!.minute.toString().padLeft(2, '0')}',
              if (s.departTime != null)
                'depart_time':
                    '${s.departTime!.hour.toString().padLeft(2, '0')}:'
                    '${s.departTime!.minute.toString().padLeft(2, '0')}',
              'stop_index': idx,
            };
          }).toList();

          tripPayloads.add({
            'day': _dayKeys[d],
            'trip_index': ti,
            'transport': trip.transport.label.toLowerCase(),
            'stops': stopPayloads,
          });

          // Build route-selection entries for each segment that has a route chosen.
          for (int seg = 0; seg < trip.segmentCount; seg++) {
            if (seg >= trip.segmentRoutes.length) continue;
            final sr = trip.segmentRoutes[seg];
            if (sr.routes.isEmpty) continue;
            final sel = sr.routes[sr.selectedIndex];
            routeSelections.add({
              'day': _dayKeys[d],
              'trip_index': ti,
              'segment_index': seg,
              'from_label': trip.stops[seg].label,
              'to_label': trip.stops[seg + 1].label,
              'transport': trip.transport.label.toLowerCase(),
              'encoded_polyline': sel.encodedPolyline,
              'road_names': sel.roadNames,
              'duration_minutes': sel.durationMinutes,
              'distance_km': sel.distanceKm,
            });
          }
        }
      }

      final api = ref.read(apiServiceProvider);

      // Fire travel-pattern and route-selection in parallel.
      // Home-location only sent if a home stop was detected.
      final futures = <Future>[
        api.saveTravelPatterns({'trips': tripPayloads}),
        if (routeSelections.isNotEmpty)
          api.saveRouteSelection({'routes': routeSelections}),
        if (homeLocation != null)
          api.saveHomeLocation({
            'location': {
              'name': 'Home',
              'latitude': homeLocation!.lat,
              'longitude': homeLocation!.lng,
              'address': homeLocation!.address,
            },
          }),
      ];

      await Future.wait(futures);

      if (mounted) context.go(Routes.onboardingAlertPreferences);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Available body height = screen minus status bar minus AppBar (toolbar 56 + step-indicator 20).
    // Subtract 8 px so the handle always stays just below the AppBar and is reachable.
    final bodyHeight = screenHeight
        - MediaQuery.of(context).padding.top
        - kToolbarHeight
        - 20   // step-indicator PreferredSize height
        - 8;   // guaranteed gap
    final maxFraction = (bodyHeight / screenHeight).clamp(0.30, 0.95);
    // Clamp stored fraction on next frame if layout changed.
    if (_panelFraction > maxFraction) {
      SchedulerBinding.instance.addPostFrameCallback(
          (_) { if (mounted) setState(() => _panelFraction = maxFraction); });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Your Trips'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          Tooltip(
            message: 'Copy today\'s trips to other days',
            child: IconButton(
              icon: const Icon(Icons.copy_all_rounded),
              onPressed: _showCopyDaySheet,
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(20),
          child: _StepIndicator(currentStep: 0, totalSteps: 2),
        ),
      ),
      body: Stack(
        children: [
          // ── Full-screen map ────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              onMapCreated: (c) {
                _mapController = c;
                _mapController!
                    .animateCamera(CameraUpdate.newLatLng(_mapCenter));
              },
              initialCameraPosition:
                  CameraPosition(target: _mapCenter, zoom: 13),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: _locationPermGranted,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),
          ),
          // ── My-location FAB (floats above panel) ──────────────────────
          Positioned(
            bottom: screenHeight * _panelFraction + 8,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'map_location',
              backgroundColor: Colors.white,
              onPressed: () async {
                try {
                  final pos = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.medium,
                  );
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(
                        LatLng(pos.latitude, pos.longitude), 14),
                  );
                } catch (_) {}
              },
              child: const Icon(Icons.my_location,
                  color: Color(0xFF2563EB), size: 18),
            ),
          ),
          // ── Custom trip panel (handle-only resize) ────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: screenHeight * _panelFraction,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Handle — ONLY this area resizes the panel
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      final delta = -details.delta.dy / screenHeight;
                      setState(() {
                        _panelFraction =
                            (_panelFraction + delta).clamp(0.12, maxFraction);
                      });
                    },
                    onVerticalDragEnd: (details) {
                      final snapSizes = [0.12, 0.55, maxFraction];
                      final nearest = snapSizes.reduce((a, b) =>
                          (a - _panelFraction).abs() <
                                  (b - _panelFraction).abs()
                              ? a
                              : b);
                      _animatePanelTo(nearest);
                    },
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                    // Day selector (always visible)
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: List.generate(7, (i) {
                            final isSelected = _selectedDay == i;
                            final hasTrips = _tripsByDay[i]!.isNotEmpty;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _selectedDay = i);
                                _refreshMapOverlays();
                              },
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF2563EB)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF2563EB)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _dayNames[i],
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (hasTrips) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? Colors.white.withValues(
                                                  alpha: 0.8)
                                              : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    // Trip list (scrollable — independent from sheet drag)
                    Expanded(
                      child: ListView(
                        controller: _listScrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_currentTrips.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 24),
                              child: Column(
                                children: [
                                  Icon(Icons.add_road_outlined,
                                      size: 48,
                                      color: Colors.grey[300]),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No trips for ${_dayFull[_selectedDay]}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap below to add where you\'ll go and when.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        height: 1.5),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...List.generate(
                              _currentTrips.length,
                              (i) => GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () {
                                  if (_activeTripIdx != i) {
                                    setState(() => _activeTripIdx = i);
                                    _refreshMapOverlays();
                                  }
                                },
                                child: _TripCard(
                                  key: ValueKey('trip_${_selectedDay}_$i'),
                                  index: i,
                                  trip: _currentTrips[i],
                                  isFirstTrip: i == 0,
                                  isLastTrip:
                                      i == _currentTrips.length - 1,
                                  onPickLocation: (stopIdx) =>
                                      _pickLocation(i, stopIdx),
                                  onAddWaypoint: () => _addWaypoint(i),
                                  onRemoveStop: (stopIdx) =>
                                      _removeStop(i, stopIdx),
                                  onPickStopTime: (stopIdx, isDep) =>
                                      _pickStopTime(i, stopIdx, isDep),
                                  onTransportChanged: (t) => setState(() =>
                                      _tripsByDay[_selectedDay]![i]
                                          .transport = t),
                                  onSelectRoute: (segIdx, ri) {
                                    setState(() =>
                                        _tripsByDay[_selectedDay]![i]
                                            .segmentRoutes[segIdx]
                                            .selectedIndex = ri);
                                    _refreshMapOverlays();
                                    _recalcArrivalTimes(_selectedDay, i);
                                  },
                                  onDelete: () {
                                    setState(() {
                                      _tripsByDay[_selectedDay]!
                                          .removeAt(i);
                                      if (_activeTripIdx != null) {
                                        if (_activeTripIdx == i) {
                                          _activeTripIdx = null;
                                        } else if (_activeTripIdx! > i) {
                                          _activeTripIdx =
                                              _activeTripIdx! - 1;
                                        }
                                      }
                                    });
                                    _refreshMapOverlays();
                                  },
                                  onRetry: (segIdx) =>
                                      _fetchSegment(_selectedDay, i, segIdx),
                                  isVeryFirstStop: _isVeryFirstStop,
                                  isVeryLastStop: _isVeryLastStop,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                                () => _currentTrips.add(_TripEntry())),
                            icon: const Icon(Icons.add),
                            label: Text(
                                'Add trip for ${_dayFull[_selectedDay]}'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Text('Continue',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),   // Stack
    );       // Scaffold
  }
}

// ─── Trip card ────────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  final int index;
  final _TripEntry trip;
  final bool isFirstTrip;
  final bool isLastTrip;
  final ValueChanged<int> onPickLocation;
  final VoidCallback onAddWaypoint;
  final ValueChanged<int> onRemoveStop;
  final void Function(int stopIdx, bool isDeparture) onPickStopTime;
  final ValueChanged<_Transport> onTransportChanged;
  final void Function(int segIdx, int routeIdx) onSelectRoute;
  final VoidCallback onDelete;
  final ValueChanged<int> onRetry;
  final bool Function(int tripIdx, int stopIdx) isVeryFirstStop;
  final bool Function(int tripIdx, int stopIdx) isVeryLastStop;

  const _TripCard({
    super.key,
    required this.index,
    required this.trip,
    required this.isFirstTrip,
    required this.isLastTrip,
    required this.onPickLocation,
    required this.onAddWaypoint,
    required this.onRemoveStop,
    required this.onPickStopTime,
    required this.onTransportChanged,
    required this.onSelectRoute,
    required this.onDelete,
    required this.onRetry,
    required this.isVeryFirstStop,
    required this.isVeryLastStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Trip ${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.delete_outline,
                        color: Colors.red[400], size: 18),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Transport
            _TransportDropdown(
              value: trip.transport,
              onChanged: onTransportChanged,
            ),

            const SizedBox(height: 16),

            // Stops list with timeline
            ...List.generate(trip.stops.length, (si) {
              final stop = trip.stops[si];
              final isFirstOfDay = isFirstTrip && si == 0;
              final isLastOfDay = isLastTrip && si == trip.stops.length - 1;
              final isIntermediate = !isFirstOfDay && !isLastOfDay;
              final isLastStop = si == trip.stops.length - 1;
              final canRemove = trip.stops.length > 2;

              Color dotColor = const Color(0xFF2563EB);
              if (isFirstOfDay) dotColor = const Color(0xFF22C55E);
              if (isLastOfDay) dotColor = const Color(0xFFEF4444);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Arrival time chip (not on first stop of the day)
                  if (!isFirstOfDay && stop.arriveTime != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 24, bottom: 4),
                      child: _TimeChip(
                        label: 'Arrive',
                        time: stop.arriveTime!,
                        color: const Color(0xFFEF4444),
                        // Arrival time is auto-calculated — read-only (no onTap)
                      ),
                    ),

                  // Stop row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Timeline dot
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotColor,
                          border:
                              Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.35),
                              blurRadius: 6,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _LocationButton(
                          label: stop.label.isNotEmpty
                              ? stop.label
                              : (isFirstOfDay
                                  ? 'Set starting point'
                                  : isLastOfDay
                                      ? 'Set final destination'
                                      : 'Set waypoint $si'),
                          isEmpty: stop.label.isEmpty,
                          onTap: () => onPickLocation(si),
                        ),
                      ),
                      if (isIntermediate && canRemove) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => onRemoveStop(si),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(Icons.remove_circle_outline,
                                color: Colors.red[300], size: 16),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Departure time chip (not on last stop of the day)
                  if (!isLastOfDay && stop.departTime != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 24, top: 4),
                      child: _TimeChip(
                        label: 'Depart',
                        time: stop.departTime!,
                        color: const Color(0xFF22C55E),
                        onTap: () => onPickStopTime(si, true),
                      ),
                    ),

                  // Segment connector + route cards
                  if (!isLastStop)
                    _SegmentConnector(
                      segIdx: si,
                      sr: si < trip.segmentRoutes.length
                          ? trip.segmentRoutes[si]
                          : null,
                      onSelectRoute: onSelectRoute,
                      onRetry: onRetry,
                    ),
                ],
              );
            }),

            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onAddWaypoint,
              icon: const Icon(Icons.add_location_alt_outlined, size: 16),
              label: const Text('Add stop / waypoint',
                  style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Segment connector + inline route cards ───────────────────────────────────

class _SegmentConnector extends StatelessWidget {
  final int segIdx;
  final _SegmentRoutes? sr;
  final void Function(int, int) onSelectRoute;
  final ValueChanged<int> onRetry;

  const _SegmentConnector({
    required this.segIdx,
    required this.sr,
    required this.onSelectRoute,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dots(),
          if (sr != null && sr!.isLoading)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
              child: Row(
                children: [
                  const SizedBox(
                    height: 12,
                    width: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Finding routes...',
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ),
          if (sr != null && !sr!.isLoading && sr!.error != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.orange[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Routes unavailable',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => onRetry(segIdx),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('Retry',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          if (sr != null &&
              !sr!.isLoading &&
              sr!.error == null &&
              sr!.routes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Route options',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ...List.generate(sr!.routes.length, (ri) {
                    final route = sr!.routes[ri];
                    final isSelected = ri == sr!.selectedIndex;
                    final isBest = ri == 0;
                    return GestureDetector(
                      onTap: () => onSelectRoute(segIdx, ri),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFEFF6FF)
                              : Colors.grey[50],
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF2563EB)
                                : Colors.grey[200]!,
                            width: isSelected ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.route_outlined,
                              size: 16,
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : Colors.grey[400],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          route.summary.isNotEmpty
                                              ? route.summary
                                              : 'Route ${ri + 1}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: isSelected
                                                ? const Color(0xFF2563EB)
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      if (isBest) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 1),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF2563EB)
                                                : Colors.grey[300],
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'BEST',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '~${route.durationMinutes} min'
                                    '${route.distanceKm > 0 ? ' · ${route.distanceKm.toStringAsFixed(1)} km' : ''}',
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF2563EB), size: 16),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          _dots(),
        ],
      ),
    );
  }

  Widget _dots() => Column(
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            width: 2,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      );
}

// ─── Time chip ────────────────────────────────────────────────────────────────

class _TimeChip extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final Color color;
  final VoidCallback? onTap;

  const _TimeChip({
    required this.label,
    required this.time,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final readOnly = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: readOnly ? 0.75 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                readOnly
                    ? Icons.access_time_rounded
                    : label == 'Arrive'
                        ? Icons.login_rounded
                        : Icons.logout_rounded,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                '$label \u00b7 ${time.format(context)}',
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600),
              ),
              if (readOnly) ...[const SizedBox(width: 4), Icon(Icons.lock_outline_rounded, size: 9, color: color)],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Location button ──────────────────────────────────────────────────────────

class _LocationButton extends StatelessWidget {
  final String label;
  final bool isEmpty;
  final VoidCallback onTap;

  const _LocationButton({
    required this.label,
    required this.isEmpty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isEmpty ? Colors.grey[50] : Colors.white,
          border: Border.all(
            color: isEmpty ? Colors.grey[300]! : Colors.grey[200]!,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isEmpty ? Colors.grey[400] : Colors.black87,
                  fontSize: 13,
                  fontWeight:
                      isEmpty ? FontWeight.normal : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

// ─── Transport dropdown ───────────────────────────────────────────────────────

class _TransportDropdown extends StatelessWidget {
  final _Transport value;
  final ValueChanged<_Transport> onChanged;

  const _TransportDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_Transport>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 16),
          items: _Transport.values
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon,
                            size: 16, color: const Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        Text(t.label,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (t) => onChanged(t!),
        ),
      ),
    );
  }
}

// ─── Full-screen location picker ──────────────────────────────────────────────

class _LocationPickerScreen extends StatefulWidget {
  final LatLng initialPosition;
  final List<LocationResult> knownLocations;
  const _LocationPickerScreen({
    required this.initialPosition,
    this.knownLocations = const [],
  });

  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  GoogleMapController? _ctrl;
  final _labelCtrl = TextEditingController();
  LatLng? _tappedLocation;
  bool _locationPermGranted = false;
  String? _suggestedName;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
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

  @override
  void dispose() {
    _labelCtrl.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _onLongPress(LatLng latLng) async {
    setState(() {
      _tappedLocation = latLng;
      _suggestedName = null;
    });
    // Reverse-geocode to pre-fill the label dialog with the place name
    final name = await _reverseGeocode(latLng);
    if (name != null && mounted) setState(() => _suggestedName = name);
  }

  /// Calls Google Geocoding API with the existing Maps API key — no backend needed.
  /// First tries to get a named establishment (business/landmark), then falls
  /// back to the formatted address so we always get a human-readable name.
  Future<String?> _reverseGeocode(LatLng pos) async {
    try {
      final key = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      if (key.isEmpty) return null;

      // 1) Try establishment / point_of_interest first for POI names.
      final estResp = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}'
        '&result_type=establishment%7Cpoint_of_interest&key=$key',
      ));
      final estData = jsonDecode(estResp.body) as Map<String, dynamic>;
      if (estData['status'] == 'OK') {
        final results = estData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map;
          // Extract the establishment name from address_components or formatted_address.
          final comps = first['address_components'] as List? ?? [];
          for (final c in comps) {
            final types = (c['types'] as List? ?? []).cast<String>();
            if (types.contains('establishment') ||
                types.contains('point_of_interest')) {
              return c['long_name'] as String?;
            }
          }
          // Fallback within the result: use the first part before a comma.
          final addr = first['formatted_address'] as String? ?? '';
          if (addr.isNotEmpty) return addr.split(',').first.trim();
        }
      }

      // 2) Regular geocode fallback.
      final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}&key=$key',
      ));
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

  Future<void> _confirm() async {
    if (_tappedLocation == null) return;
    _labelCtrl.text = _suggestedName ?? '';
    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Name this location'),
        content: TextField(
          controller: _labelCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Home, Office, Gym',
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
                backgroundColor: const Color(0xFF2563EB)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (label != null && mounted) {
      Navigator.pop(
        context,
        LocationResult(
          address: label,
          lat: _tappedLocation!.latitude,
          lng: _tappedLocation!.longitude,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final marker = _tappedLocation == null
        ? <Marker>{}
        : {
            Marker(
              markerId: const MarkerId('selected'),
              position: _tappedLocation!,
              infoWindow: const InfoWindow(title: 'Selected location'),
            ),
          };

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _ctrl = c,
            initialCameraPosition:
                CameraPosition(target: widget.initialPosition, zoom: 15),
            onLongPress: _onLongPress,
            markers: marker,
            myLocationEnabled: _locationPermGranted,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button + hint bar
                  Row(
                    children: [
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(context),
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
                                _tappedLocation == null
                                    ? Icons.touch_app_outlined
                                    : Icons.location_on,
                                size: 16,
                                color: const Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _tappedLocation == null
                                    ? 'Long-press to pin \u00b7 tap for place info'
                                    : 'Pinned \u2014 confirm or long-press to move',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Previously marked locations chip strip
                  if (widget.knownLocations.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.knownLocations.map((loc) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context, loc);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.history_rounded,
                                        size: 12,
                                        color: Color(0xFF2563EB)),
                                    const SizedBox(width: 5),
                                    Text(
                                      loc.address,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'picker_location',
              backgroundColor: Colors.white,
              elevation: 2,
              onPressed: () async {
                try {
                  final pos = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.medium,
                  );
                  final myLoc = LatLng(pos.latitude, pos.longitude);
                  _ctrl?.animateCamera(
                    CameraUpdate.newLatLngZoom(myLoc, 16),
                  );
                } catch (_) {}
              },
              child: const Icon(Icons.my_location,
                  color: Color(0xFF2563EB), size: 18),
            ),
          ),
          Positioned(
            bottom: 36,
            left: 32,
            right: 32,
            child: FilledButton.icon(
              onPressed: _tappedLocation != null ? _confirm : null,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirm Location',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: Colors.grey[300],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step indicator ───────────────────────────────────────────────────────────

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
