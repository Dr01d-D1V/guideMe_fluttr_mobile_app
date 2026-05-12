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
    final encoded = json['polyline'] as String? ?? '';
    return RouteOption(
      encodedPolyline: encoded,
      points: _decodePolyline(encoded),
      // description is a slash-separated road name string, e.g. "Road A/Road B"
      roadNames: (json['description'] as String? ?? '')
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      // backend returns duration_seconds; convert to minutes
      durationMinutes:
          (((json['duration_seconds'] as num?) ?? 0) / 60).round(),
      summary: json['description'] as String? ?? '',
      // backend returns distance_meters; convert to km
      distanceKm:
          ((json['distance_meters'] as num?)?.toDouble() ?? 0.0) / 1000.0,
    );
  }
}

/// Decodes a Google-encoded polyline string into a list of lat/lng points.
List<Map<String, double>> _decodePolyline(String encoded) {
  final points = <Map<String, double>>[];
  int index = 0;
  int lat = 0;
  int lng = 0;

  while (index < encoded.length) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0; result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add({'lat': lat / 1e5, 'lng': lng / 1e5});
  }
  return points;
}
