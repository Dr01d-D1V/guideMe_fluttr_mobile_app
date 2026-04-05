import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/destination.dart';
import '../models/route_entry.dart';
import '../models/trip_pair.dart';

class OnboardingState {
  final LocationResult? homeLocation;
  final LocationResult? officeLocation;
  final List<Destination> destinations;
  final List<RouteEntry> routes;
  final List<String> alertPreferences;

  const OnboardingState({
    this.homeLocation,
    this.officeLocation,
    this.destinations = const [],
    this.routes = const [],
    this.alertPreferences = const [],
  });

  /// Builds all A→B trip pairs from stored home/office/destinations.
  List<TripPair> buildTripPairs() {
    final pairs = <TripPair>[];

    if (homeLocation != null && officeLocation != null) {
      pairs.add(TripPair(
        fromId: 'home',
        toId: 'office',
        fromLabel: 'Home',
        toLabel: 'Office',
        label: 'Home → Office',
        originLat: homeLocation!.lat,
        originLng: homeLocation!.lng,
        destinationLat: officeLocation!.lat,
        destinationLng: officeLocation!.lng,
      ));
      pairs.add(TripPair(
        fromId: 'office',
        toId: 'home',
        fromLabel: 'Office',
        toLabel: 'Home',
        label: 'Office → Home',
        originLat: officeLocation!.lat,
        originLng: officeLocation!.lng,
        destinationLat: homeLocation!.lat,
        destinationLng: homeLocation!.lng,
      ));
    }

    for (final dest in destinations) {
      if (homeLocation != null) {
        pairs.add(TripPair(
          fromId: 'home',
          toId: dest.id,
          fromLabel: 'Home',
          toLabel: dest.label,
          label: 'Home → ${dest.label}',
          originLat: homeLocation!.lat,
          originLng: homeLocation!.lng,
          destinationLat: dest.lat,
          destinationLng: dest.lng,
        ));
        pairs.add(TripPair(
          fromId: dest.id,
          toId: 'home',
          fromLabel: dest.label,
          toLabel: 'Home',
          label: '${dest.label} → Home',
          originLat: dest.lat,
          originLng: dest.lng,
          destinationLat: homeLocation!.lat,
          destinationLng: homeLocation!.lng,
        ));
      }
    }

    return pairs;
  }

  OnboardingState copyWith({
    LocationResult? homeLocation,
    LocationResult? officeLocation,
    List<Destination>? destinations,
    List<RouteEntry>? routes,
    List<String>? alertPreferences,
  }) {
    return OnboardingState(
      homeLocation: homeLocation ?? this.homeLocation,
      officeLocation: officeLocation ?? this.officeLocation,
      destinations: destinations ?? this.destinations,
      routes: routes ?? this.routes,
      alertPreferences: alertPreferences ?? this.alertPreferences,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(const OnboardingState());

  void setHomeLocation(LocationResult loc) =>
      state = state.copyWith(homeLocation: loc);

  void setOfficeLocation(LocationResult loc) =>
      state = state.copyWith(officeLocation: loc);

  void setDestinations(List<Destination> dests) =>
      state = state.copyWith(destinations: dests);

  void setRoutes(List<RouteEntry> routes) =>
      state = state.copyWith(routes: routes);

  void setAlertPreferences(List<String> prefs) =>
      state = state.copyWith(alertPreferences: prefs);
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
  (ref) => OnboardingNotifier(),
);
