class Destination {
  final String id;
  final String label;
  final String address;
  final double lat;
  final double lng;
  final String type; // 'work_stop' | 'leisure' | 'errand'
  final List<String> daysOfWeek;
  final int frequencyPerWeek;
  final List<TripSchedule> trips;

  const Destination({
    required this.id,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    required this.type,
    required this.daysOfWeek,
    required this.frequencyPerWeek,
    required this.trips,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'lat': lat,
        'lng': lng,
        'type': type,
        'days_of_week': daysOfWeek,
        'frequency_per_week': frequencyPerWeek,
        'trips': trips.map((t) => t.toJson()).toList(),
      };
}

class TripSchedule {
  final String fromDestinationId;
  final String toDestinationId;
  final String departTime;
  final String arriveTime;

  const TripSchedule({
    required this.fromDestinationId,
    required this.toDestinationId,
    required this.departTime,
    required this.arriveTime,
  });

  Map<String, dynamic> toJson() => {
        'from_destination_id': fromDestinationId,
        'to_destination_id': toDestinationId,
        'depart_time': departTime,
        'arrive_time': arriveTime,
      };
}

class LocationResult {
  final String address;
  final double lat;
  final double lng;

  const LocationResult({
    required this.address,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {
        'address': address,
        'lat': lat,
        'lng': lng,
      };
}
