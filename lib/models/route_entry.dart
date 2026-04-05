class RouteEntry {
  final String tripLabel;
  final String fromDestinationId;
  final String toDestinationId;
  final String? polyline;
  final List<Map<String, double>> waypoints;
  final List<String> roadNames;
  final int estimatedDurationMinutes;
  final bool preferred;

  const RouteEntry({
    required this.tripLabel,
    required this.fromDestinationId,
    required this.toDestinationId,
    this.polyline,
    this.waypoints = const [],
    this.roadNames = const [],
    required this.estimatedDurationMinutes,
    this.preferred = true,
  });

  Map<String, dynamic> toJson() => {
        'trip_label': tripLabel,
        'from_destination_id': fromDestinationId,
        'to_destination_id': toDestinationId,
        if (polyline != null) 'polyline': polyline,
        'waypoints': waypoints,
        'road_names': roadNames,
        'estimated_duration_minutes': estimatedDurationMinutes,
        'preferred': preferred,
      };
}

class RouteOption {
  final String encodedPolyline;
  final List<Map<String, double>> points;
  final List<String> roadNames;
  final int durationMinutes;
  final String summary;
  final double distanceKm;

  const RouteOption({
    required this.encodedPolyline,
    required this.points,
    required this.roadNames,
    required this.durationMinutes,
    required this.summary,
    required this.distanceKm,
  });

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    return RouteOption(
      encodedPolyline: json['polyline'] as String? ?? '',
      points: (json['points'] as List<dynamic>? ?? [])
          .map((p) => {'lat': (p['lat'] as num).toDouble(), 'lng': (p['lng'] as num).toDouble()})
          .toList(),
      roadNames: (json['road_names'] as List<dynamic>? ?? []).cast<String>(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      summary: json['summary'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
