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

// ─── Trip data model ──────────────────────────────────────────────────────────

class _TripEntry {
  LocationResult? from;
  String fromLabel = '';
  LocationResult? to;
  String toLabel = '';
  _Transport transport = _Transport.car;
  TimeOfDay departTime = const TimeOfDay(hour: 7, minute: 30);
  List<RouteOption> routes = [];
  int selectedRouteIndex = 0;
  bool isLoadingRoutes = false;
  String? routeError;
}

// ─── Main screen ──────────────────────────────────────────────────────────────

class TravelPatternScreen extends ConsumerStatefulWidget {
  const TravelPatternScreen({super.key});

  @override
  ConsumerState<TravelPatternScreen> createState() =>
      _TravelPatternScreenState();
}

class _TravelPatternScreenState extends ConsumerState<TravelPatternScreen> {
  static const _dayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];
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
  LatLng _mapCenter = const LatLng(9.0579, 7.4951); // Abuja fallback
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

  // ─── Map overlays ────────────────────────────────────────────────────────────

  void _refreshMapOverlays() {
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    for (final (i, trip) in _currentTrips.indexed) {
      if (trip.from != null) {
        markers.add(Marker(
          markerId: MarkerId('from_${_selectedDay}_$i'),
          position: LatLng(trip.from!.lat, trip.from!.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
              title:
                  trip.fromLabel.isNotEmpty ? trip.fromLabel : 'Start'),
        ));
      }
      if (trip.to != null) {
        markers.add(Marker(
          markerId: MarkerId('to_${_selectedDay}_$i'),
          position: LatLng(trip.to!.lat, trip.to!.lng),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
              title: trip.toLabel.isNotEmpty ? trip.toLabel : 'End'),
        ));
      }
      if (trip.routes.isNotEmpty &&
          trip.selectedRouteIndex < trip.routes.length) {
        final route = trip.routes[trip.selectedRouteIndex];
        if (route.points.isNotEmpty) {
          polylines.add(Polyline(
            polylineId: PolylineId('route_${_selectedDay}_$i'),
            color: const Color(0xFF2563EB),
            width: 4,
            points: route.points
                .map((p) =>
                    LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
                .toList(),
          ));
        } else if (trip.from != null && trip.to != null) {
          // Draw straight line if no polyline data returned
          polylines.add(Polyline(
            polylineId: PolylineId('route_${_selectedDay}_$i'),
            color: const Color(0xFF2563EB),
            width: 3,
            patterns: [PatternItem.dash(12), PatternItem.gap(8)],
            points: [
              LatLng(trip.from!.lat, trip.from!.lng),
              LatLng(trip.to!.lat, trip.to!.lng),
            ],
          ));
        }
      }
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  // ─── Route fetching ──────────────────────────────────────────────────────────

  Future<void> _fetchRoutes(int dayIdx, int tripIdx) async {
    final trip = _tripsByDay[dayIdx]![tripIdx];
    if (trip.from == null || trip.to == null) return;

    setState(() {
      _tripsByDay[dayIdx]![tripIdx].isLoadingRoutes = true;
      _tripsByDay[dayIdx]![tripIdx].routeError = null;
      _tripsByDay[dayIdx]![tripIdx].routes = [];
    });

    try {
      final api = ref.read(apiServiceProvider);
      final routes = await api.fetchRouteOptions(
        trip.from!.lat,
        trip.from!.lng,
        trip.to!.lat,
        trip.to!.lng,
      );
      if (mounted) {
        setState(() {
          _tripsByDay[dayIdx]![tripIdx].routes = routes;
          _tripsByDay[dayIdx]![tripIdx].selectedRouteIndex = 0;
          _tripsByDay[dayIdx]![tripIdx].isLoadingRoutes = false;
        });
        _refreshMapOverlays();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _tripsByDay[dayIdx]![tripIdx].isLoadingRoutes = false;
          _tripsByDay[dayIdx]![tripIdx].routeError = e.toString();
        });
      }
    }
  }

  // ─── Location picker ─────────────────────────────────────────────────────────

  Future<void> _pickLocation(int tripIdx, bool isFrom) async {
    final trip = _currentTrips[tripIdx];
    final existing = isFrom ? trip.from : trip.to;
    final initial = existing != null
        ? LatLng(existing.lat, existing.lng)
        : _mapCenter;

    final result = await Navigator.of(context).push<LocationResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LocationPickerScreen(initialPosition: initial),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      if (isFrom) {
        _tripsByDay[_selectedDay]![tripIdx].from = result;
        _tripsByDay[_selectedDay]![tripIdx].fromLabel = result.address;
      } else {
        _tripsByDay[_selectedDay]![tripIdx].to = result;
        _tripsByDay[_selectedDay]![tripIdx].toLabel = result.address;
      }
    });

    _refreshMapOverlays();

    // Auto-fetch routes when both ends are set
    final updatedTrip = _tripsByDay[_selectedDay]![tripIdx];
    if (updatedTrip.from != null && updatedTrip.to != null) {
      await _fetchRoutes(_selectedDay, tripIdx);
    }
  }

  // ─── Time picker ─────────────────────────────────────────────────────────────

  Future<void> _pickTime(int tripIdx) async {
    final current = _currentTrips[tripIdx].departTime;
    final picked =
        await showTimePicker(context: context, initialTime: current);
    if (picked != null && mounted) {
      setState(
          () => _tripsByDay[_selectedDay]![tripIdx].departTime = picked);
    }
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final allTrips = _tripsByDay.values
        .expand((list) => list)
        .where((t) => t.from != null && t.to != null)
        .toList();

    if (allTrips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please add at least one complete trip (from → to).')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final tripPayloads = <Map<String, dynamic>>[];
      final routeEntries = <RouteEntry>[];

      for (int d = 0; d < 7; d++) {
        for (final trip in _tripsByDay[d]!) {
          if (trip.from == null || trip.to == null) continue;
          tripPayloads.add({
            'day': _dayKeys[d],
            'from': trip.from!.toJson(),
            'from_label': trip.fromLabel,
            'to': trip.to!.toJson(),
            'to_label': trip.toLabel,
            'transport': trip.transport.label.toLowerCase(),
            'depart_time':
                '${trip.departTime.hour.toString().padLeft(2, '0')}:'
                '${trip.departTime.minute.toString().padLeft(2, '0')}',
          });

          if (trip.routes.isNotEmpty) {
            final sel = trip.routes[trip.selectedRouteIndex];
            routeEntries.add(RouteEntry(
              tripLabel:
                  '${trip.fromLabel} → ${trip.toLabel} (${_dayFull[d]})',
              fromDestinationId: trip.fromLabel,
              toDestinationId: trip.toLabel,
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

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Your Trips'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(20),
          child: _StepIndicator(currentStep: 0, totalSteps: 2),
        ),
      ),
      body: Column(
        children: [
          // ── Map preview ─────────────────────────────────────────────────
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.33,
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
                // My location FAB
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

          // ── Day selector ─────────────────────────────────────────────────
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
                                    ? Colors.white
                                        .withValues(alpha: 0.8)
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

          // ── Trip list ─────────────────────────────────────────────────────
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
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap below to add where you\'ll go\nand when.',
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
                      onPickFrom: () => _pickLocation(i, true),
                      onPickTo: () => _pickLocation(i, false),
                      onPickTime: () => _pickTime(i),
                      onTransportChanged: (t) => setState(
                          () => _tripsByDay[_selectedDay]![i].transport =
                              t),
                      onSelectRoute: (ri) {
                        setState(() =>
                            _tripsByDay[_selectedDay]![i]
                                .selectedRouteIndex = ri);
                        _refreshMapOverlays();
                      },
                      onDelete: () {
                        setState(
                            () => _tripsByDay[_selectedDay]!.removeAt(i));
                        _refreshMapOverlays();
                      },
                      onRetry: () => _fetchRoutes(_selectedDay, i),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
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
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onPickTime;
  final ValueChanged<_Transport> onTransportChanged;
  final ValueChanged<int> onSelectRoute;
  final VoidCallback onDelete;
  final VoidCallback onRetry;

  const _TripCard({
    super.key,
    required this.index,
    required this.trip,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onPickTime,
    required this.onTransportChanged,
    required this.onSelectRoute,
    required this.onDelete,
    required this.onRetry,
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
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

            // From / To with dotted connector
            _LocationButton(
              icon: Icons.circle,
              iconColor: const Color(0xFF22C55E),
              label: trip.fromLabel.isNotEmpty
                  ? trip.fromLabel
                  : 'Set starting point',
              isEmpty: trip.fromLabel.isEmpty,
              onTap: onPickFrom,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 11, top: 4, bottom: 4),
              child: Column(
                children: List.generate(
                  3,
                  (_) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    width: 2,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
            _LocationButton(
              icon: Icons.location_on_rounded,
              iconColor: const Color(0xFF2563EB),
              label:
                  trip.toLabel.isNotEmpty ? trip.toLabel : 'Set destination',
              isEmpty: trip.toLabel.isEmpty,
              onTap: onPickTo,
            ),

            const SizedBox(height: 14),
            Divider(color: Colors.grey[100]),
            const SizedBox(height: 10),

            // Transport + departure time row
            Row(
              children: [
                Expanded(
                  child: _TransportDropdown(
                    value: trip.transport,
                    onChanged: onTransportChanged,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onPickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 15, color: Color(0xFF2563EB)),
                        const SizedBox(width: 6),
                        Text(
                          trip.departTime.format(context),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Routes section (only shown when both ends pinned)
            if (trip.from != null && trip.to != null) ...[
              const SizedBox(height: 14),
              Divider(color: Colors.grey[100]),
              const SizedBox(height: 12),

              if (trip.isLoadingRoutes)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Finding best routes…',
                        style: TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else if (trip.routeError != null)
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: Colors.orange[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Routes unavailable',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      child: const Text('Retry',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                )
              else if (trip.routes.isEmpty)
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text(
                      'No routes returned from server',
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    const Text('Suggested Routes',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${trip.routes.length} route${trip.routes.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...List.generate(trip.routes.length, (ri) {
                  final route = trip.routes[ri];
                  final isSelected = ri == trip.selectedRouteIndex;
                  final isBest = ri == 0;
                  return GestureDetector(
                    onTap: () => onSelectRoute(ri),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.route_outlined,
                            size: 18,
                            color: isSelected
                                ? const Color(0xFF2563EB)
                                : Colors.grey[400],
                          ),
                          const SizedBox(width: 10),
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
                                          fontSize: 13,
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
                                const SizedBox(height: 2),
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
                                color: Color(0xFF2563EB), size: 18),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Location button ──────────────────────────────────────────────────────────

class _LocationButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isEmpty;
  final VoidCallback onTap;

  const _LocationButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isEmpty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isEmpty ? Colors.grey[50] : Colors.white,
          border: Border.all(
            color: isEmpty ? Colors.grey[300]! : Colors.grey[200]!,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color:
                      isEmpty ? Colors.grey[400] : Colors.black87,
                  fontSize: 13,
                  fontWeight:
                      isEmpty ? FontWeight.normal : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

// ─── Transport dropdown ────────────────────────────────────────────────────────

class _TransportDropdown extends StatelessWidget {
  final _Transport value;
  final ValueChanged<_Transport> onChanged;

  const _TransportDropdown(
      {required this.value, required this.onChanged});

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
                            size: 16,
                            color: const Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        Text(t.label,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
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
  State<_LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
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
          // Map
          GoogleMap(
            onMapCreated: (c) => _ctrl = c,
            initialCameraPosition:
                CameraPosition(target: widget.initialPosition, zoom: 15),
            onCameraMove: (pos) => _center = pos.target,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Crosshair
          const Center(
            child: Icon(
              Icons.add,
              size: 44,
              color: Color(0xFF2563EB),
              shadows: [Shadow(blurRadius: 8, color: Colors.white)],
            ),
          ),

          // Top bar
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

          // My location button
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

          // Confirm button
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

// ─── Step indicator ────────────────────────────────────────────────────────────

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

