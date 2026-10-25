import 'package:latlong2/latlong.dart';

class StopNode {
  final String id;
  final String name;
  final LatLng position;

  StopNode({
    required this.id,
    required this.name,
    required this.position,
  });
}

class RouteEdge {
  final String fromId;
  final String toId;
  final double distanceKm;
  final String mode;
  final String coopId;
  final bool isOneWay;
  final List<LatLng> waypoints;

  RouteEdge({
    required this.fromId,
    required this.toId,
    required this.distanceKm,
    required this.mode,
    required this.coopId,
    required this.isOneWay,
    required this.waypoints,
  });
}

class RouteCalculationResult {
  final List<LatLng> pathCoordinates;
  final double totalDistanceKm;
  final double estimatedFare;
  final String operatorName;

  RouteCalculationResult({
    required this.pathCoordinates,
    required this.totalDistanceKm,
    required this.estimatedFare,
    required this.operatorName,
  });
}

class ItineraryLog {
  final String id;
  final String timestamp;
  final String origin;
  final String destination;
  final String distanceKm;
  final String fare;
  final String operatorName;
  final bool isDiscounted;

  ItineraryLog({
    required this.id,
    required this.timestamp,
    required this.origin,
    required this.destination,
    required this.distanceKm,
    required this.fare,
    required this.operatorName,
    required this.isDiscounted,
  });
}