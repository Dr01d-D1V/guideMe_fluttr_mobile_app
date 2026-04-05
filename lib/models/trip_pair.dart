class TripPair {
  final String fromId;
  final String toId;
  final String fromLabel;
  final String toLabel;
  final String label;
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;

  const TripPair({
    required this.fromId,
    required this.toId,
    required this.fromLabel,
    required this.toLabel,
    required this.label,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
  });
}
