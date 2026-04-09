import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/destination.dart';
import '../../models/route_entry.dart';
import '../../providers/onboarding_provider.dart';
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
    segmentRoutes = src.segmentRoutes.map((_) => _SegmentRoutes()).toList();
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

class _TravelPatternScreenState extends ConsumerState<TravelPatternScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayFull = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];
  static const _dayKeys = [
    'monday', 'tuesday', 'wednesday', 'thursday',
    'friday', 'saturday', 'sunday'
  ];

  int _selectedDay = 0;
  final Map<int, List<_TripEntry>> _tripsByDay = {
    for (int i = 0; i < 7; i++) i: [],
  };

  GoogleMapController? _mapController;
  LatLng _mapCenter = const LatLng(9.0579, 7.4951);
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() => _mapCenter = LatLng(pos.latitude, pos.longitude));
        _mapController?.animateCamera(CameraUpdate.newLatLng(_mapCenter));
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
            polylines.add(Polyline(
              polylineId: PolylineId('seg_${_selectedDay}_${t}_$seg'),
              color: const Color(0xFF2563EB),
              width: 4,
              points: route.points
                  .map((p) => LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
                  .toList(),
            ));
            continue;
          }
        }
        polylines.add(Polyline(
          polylineId: PolylineId('seg_${_selectedDay}_${t}_$seg'),
          color: const Color(0xFF2563EB),
          width: 3,
          patterns: [PatternItem.dash(12), PatternItem.gap(8)],
          points: [
            LatLng(fromStop.location!.lat, fromStop.location!.lng),
            LatLng(toStop.location!.lat, toStop.location!.lng),
          ],
        ));
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

  // ─── Location picker ──────────────────────────────────────────────────────

  Future<void> _pickLocation(int tripIdx, int stopIdx) async {
    final stop = _currentTrips[tripIdx].stops[stopIdx];
    final initial = stop.location != null
        ? LatLng(stop.location!.lat, stop.location!.lng)
        : _mapCenter;

    final result = await Navigator.of(context).push<LocationResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LocationPickerScreen(initialPosition: initial),
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

  void _removeStop(int tripIdx, int stopIdx) {
    final trip = _tripsByDay[_selectedDay]![tripIdx];
    if (trip.stops.length <= 2) return;
    setState(() {
      trip.stops.removeAt(stopIdx);
      final segIdx = stopIdx > 0 ? stopIdx - 1 : 0;
      if (segIdx < trip.segmentRoutes.length) {
        trip.segmentRoutes.removeAt(segIdx);
      }
    });
    _refreshMapOverlays();
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
      final routeEntries = <RouteEntry>[];

      for (int d = 0; d < 7; d++) {
        final trips = _tripsByDay[d]!;
        for (int ti = 0; ti < trips.length; ti++) {
          final trip = trips[ti];
          if (trip.stops.any((s) => s.location == null)) continue;

          final stopPayloads = trip.stops.asMap().entries.map((e) {
            final idx = e.key;
            final s = e.value;
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

          for (int seg = 0; seg < trip.segmentCount; seg++) {
            if (seg >= trip.segmentRoutes.length) continue;
            final sr = trip.segmentRoutes[seg];
            if (sr.routes.isEmpty) continue;
            final sel = sr.routes[sr.selectedIndex];
            routeEntries.add(RouteEntry(
              tripLabel:
                  '${trip.stops[seg].label} -> ${trip.stops[seg + 1].label} '
                  '(${_dayFull[d]}, trip ${ti + 1}, seg ${seg + 1})',
              fromDestinationId: trip.stops[seg].label,
              toDestinationId: trip.stops[seg + 1].label,
              estimatedDurationMinutes: sel.durationMinutes,
              roadNames: sel.roadNames,
              preferred: true,
            ));
          }
        }
      }

      final api = ref.read(apiServiceProvider);
      await api.saveTravelPatterns({'trips': tripPayloads});

      if (routeEntries.isNotEmpty) {
        await api.saveRoutes(
            {'routes': routeEntries.map((r) => r.toJson()).toList()});
      }

      ref.read(onboardingProvider.notifier).setRoutes(routeEntries);

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
      body: Column(
        children: [
          // ── Map preview ────────────────────────────────────────────────
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.30,
            child: Stack(
              children: [
                GoogleMap(
                  onMapCreated: (c) {
                    _mapController = c;
                    _mapController!
                        .animateCamera(CameraUpdate.newLatLng(_mapCenter));
                  },
                  initialCameraPosition:
                      CameraPosition(target: _mapCenter, zoom: 13),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'map_location',
                    backgroundColor: Colors.white,
                    onPressed: () async {
                      try {
                        final pos =
                            await Geolocator.getCurrentPosition(
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
              ],
            ),
          ),

          // ── Day selector ───────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      duration: const Duration(milliseconds: 180),
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
                                    ? Colors.white.withValues(alpha: 0.8)
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

          // ── Trip list ──────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_currentTrips.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.add_road_outlined,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'No trips for ${_dayFull[_selectedDay]}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap below to add where you\'ll go and when.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey[500], height: 1.5),
                        ),
                      ],
                    ),
                  )
                else
                  ...List.generate(
                    _currentTrips.length,
                    (i) => _TripCard(
                      key: ValueKey('trip_${_selectedDay}_$i'),
                      index: i,
                      trip: _currentTrips[i],
                      isFirstTrip: i == 0,
                      isLastTrip: i == _currentTrips.length - 1,
                      onPickLocation: (stopIdx) => _pickLocation(i, stopIdx),
                      onAddWaypoint: () => _addWaypoint(i),
                      onRemoveStop: (stopIdx) => _removeStop(i, stopIdx),
                      onPickStopTime: (stopIdx, isDep) =>
                          _pickStopTime(i, stopIdx, isDep),
                      onTransportChanged: (t) => setState(
                          () => _tripsByDay[_selectedDay]![i].transport = t),
                      onSelectRoute: (segIdx, ri) {
                        setState(() => _tripsByDay[_selectedDay]![i]
                            .segmentRoutes[segIdx]
                            .selectedIndex = ri);
                        _refreshMapOverlays();
                      },
                      onDelete: () {
                        setState(
                            () => _tripsByDay[_selectedDay]!.removeAt(i));
                        _refreshMapOverlays();
                      },
                      onRetry: (segIdx) =>
                          _fetchSegment(_selectedDay, i, segIdx),
                      isVeryFirstStop: _isVeryFirstStop,
                      isVeryLastStop: _isVeryLastStop,
                    ),
                  ),

                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _currentTrips.add(_TripEntry())),
                  icon: const Icon(Icons.add),
                  label: Text('Add trip for ${_dayFull[_selectedDay]}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continue',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
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
                        onTap: () => onPickStopTime(si, false),
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
  final VoidCallback onTap;

  const _TimeChip({
    required this.label,
    required this.time,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              label == 'Arrive'
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
          ],
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
  const _LocationPickerScreen({required this.initialPosition});

  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  late LatLng _center;
  GoogleMapController? _ctrl;
  final _labelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _center = widget.initialPosition;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    _labelCtrl.clear();
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
          lat: _center.latitude,
          lng: _center.longitude,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _ctrl = c,
            initialCameraPosition:
                CameraPosition(target: widget.initialPosition, zoom: 15),
            onCameraMove: (pos) => _center = pos.target,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          const Center(
            child: Icon(
              Icons.add,
              size: 44,
              color: Color(0xFF2563EB),
              shadows: [Shadow(blurRadius: 8, color: Colors.white)],
            ),
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
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
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app_outlined,
                              size: 16, color: Color(0xFF2563EB)),
                          SizedBox(width: 8),
                          Text(
                            'Pan to your location, then confirm',
                            style: TextStyle(
                                fontSize: 13, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                  _ctrl?.animateCamera(
                    CameraUpdate.newLatLngZoom(
                        LatLng(pos.latitude, pos.longitude), 16),
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
              onPressed: _confirm,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirm Location',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
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
