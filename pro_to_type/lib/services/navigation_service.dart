import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/transit_models.dart';

class NavigationService {
  Map<String, StopNode> nodes = {};
  List<RouteEdge> edges = [];
  Map<String, dynamic> fareRules = {};
  Map<String, String> coopNames = {};
  final List<ItineraryLog> savedLogs = [];

  Future<void> initializeGraph() async {
    final jsonString = await rootBundle.loadString('assets/data/local.json');
    final Map<String, dynamic> data = jsonDecode(jsonString);

    final Map<String, StopNode> loadedNodes = {};
    for (var stop in data['stops']) {
      loadedNodes[stop['id']] = StopNode(
        id: stop['id'],
        name: stop['name'],
        position: LatLng(
          (stop['lat'] as num).toDouble(),
          (stop['lng'] as num).toDouble(),
        ),
      );
    }

    final List<RouteEdge> loadedEdges = [];
    for (var edge in data['edges']) {
      final List<LatLng> pts = [];
      if (edge['waypoints'] != null) {
        for (var pt in edge['waypoints']) {
          pts.add(LatLng((pt[0] as num).toDouble(), (pt[1] as num).toDouble()));
        }
      }
      loadedEdges.add(RouteEdge(
        fromId: edge['from'],
        toId: edge['to'],
        distanceKm: (edge['distance_km'] as num).toDouble(),
        mode: edge['mode'] ?? 'Jeepney',
        coopId: edge['coop_id'] ?? 'GENERIC',
        isOneWay: edge['is_one_way'] ?? false,
        waypoints: pts,
      ));
    }

    final Map<String, String> loadedCoops = {};
    if (data['cooperatives'] != null) {
      for (var c in data['cooperatives']) {
        loadedCoops[c['id']] = c['name'];
      }
    }

    nodes = loadedNodes;
    edges = loadedEdges;
    fareRules = data['fare_rules'] ?? {};
    coopNames = loadedCoops;
  }

  RouteCalculationResult calculateRoute({
    required StopNode origin,
    required StopNode destination,
    required bool isDiscounted,
  }) {
    if (origin.id == destination.id) {
      return RouteCalculationResult(
        pathCoordinates: [],
        totalDistanceKm: 0.0,
        estimatedFare: 0.0,
        operatorName: 'N/A',
      );
    }

    final Map<String, List<RouteEdge>> adjacency = {
      for (var k in nodes.keys) k: []
    };

    for (var edge in edges) {
      adjacency[edge.fromId]?.add(edge);
      if (!edge.isOneWay) {
        adjacency[edge.toId]?.add(RouteEdge(
          fromId: edge.toId,
          toId: edge.fromId,
          distanceKm: edge.distanceKm,
          mode: edge.mode,
          coopId: edge.coopId,
          isOneWay: edge.isOneWay,
          waypoints: edge.waypoints.reversed.toList(),
        ));
      }
    }

    final Map<String, double> gScore = {for (var k in nodes.keys) k: double.infinity};
    final Map<String, double> fScore = {for (var k in nodes.keys) k: double.infinity};
    final Map<String, String> cameFrom = {};
    final Map<String, RouteEdge> cameFromEdge = {};
    final Set<String> openSet = {origin.id};

    gScore[origin.id] = 0.0;
    fScore[origin.id] = _haversineHeuristic(origin.id, destination.id);

    while (openSet.isNotEmpty) {
      String current = openSet.reduce((a, b) => fScore[a]! < fScore[b]! ? a : b);

      if (current == destination.id) {
        return _buildResult(cameFrom, cameFromEdge, current, gScore[destination.id]!, isDiscounted);
      }

      openSet.remove(current);

      for (var edge in adjacency[current] ?? []) {
        double tentativeG = gScore[current]! + edge.distanceKm;

        if (tentativeG < (gScore[edge.toId] ?? double.infinity)) {
          cameFrom[edge.toId] = current;
          cameFromEdge[edge.toId] = edge;
          gScore[edge.toId] = tentativeG;
          fScore[edge.toId] = tentativeG + _haversineHeuristic(edge.toId, destination.id);
          openSet.add(edge.toId);
        }
      }
    }

    return RouteCalculationResult(
      pathCoordinates: [],
      totalDistanceKm: 0.0,
      estimatedFare: 0.0,
      operatorName: 'No Route',
    );
  }

  RouteCalculationResult _buildResult(
    Map<String, String> cameFrom,
    Map<String, RouteEdge> cameFromEdge,
    String current,
    double distance,
    bool isDiscounted,
  ) {
    List<RouteEdge> pathEdges = [];
    String detectedCoopId = cameFromEdge[current]?.coopId ?? 'GENERIC';

    while (cameFrom.containsKey(current)) {
      if (cameFromEdge.containsKey(current)) {
        pathEdges.insert(0, cameFromEdge[current]!);
      }
      current = cameFrom[current]!;
    }

    final List<LatLng> roadPolyline = [];
    for (var edge in pathEdges) {
      if (edge.waypoints.isNotEmpty) {
        roadPolyline.addAll(edge.waypoints);
      } else {
        roadPolyline.add(nodes[edge.fromId]!.position);
        roadPolyline.add(nodes[edge.toId]!.position);
      }
    }

    // Read bounds from JSON rules
    final double shortMinKm = (fareRules['short_distance_min_km'] as num?)?.toDouble() ?? 0.0;
    final double shortMaxKm = (fareRules['short_distance_km'] as num?)?.toDouble() ?? 3.0;
    final double shortFare = (fareRules['short_distance_fare'] as num?)?.toDouble() ?? 11.00;
    final double baseFare = (fareRules['base_fare'] as num?)?.toDouble() ?? 12.00;
    final double baseKm = (fareRules['base_km'] as num?)?.toDouble() ?? 4.0;
    final double surcharge = (fareRules['surcharge_per_km'] as num?)?.toDouble() ?? 1.80;

    double computedFare;
    bool allowDiscount = true;

    // Condition: Greater than 0 km AND less than or equal to 3.0 km
    if (distance > shortMinKm && distance <= shortMaxKm) {
      computedFare = shortFare; // ₱11.00
      allowDiscount = false;    // Restricted discount
    } else if (distance <= baseKm) {
      computedFare = baseFare;  // ₱12.00 for trips up to 4.0 km
      allowDiscount = false;    // Restricted discount
    } else {
      computedFare = baseFare + ((distance - baseKm) * surcharge);
      allowDiscount = true;     // Discount enabled for trips > 4.0 km
    }

    final double finalFare = (isDiscounted && allowDiscount)
        ? (computedFare * 0.80)
        : computedFare;

    return RouteCalculationResult(
      pathCoordinates: roadPolyline,
      totalDistanceKm: distance,
      estimatedFare: finalFare,
      operatorName: coopNames[detectedCoopId] ?? 'Legazpi Commuter Line',
    );
  }

  double _haversineHeuristic(String aId, String bId) {
    final posA = nodes[aId]!.position;
    final posB = nodes[bId]!.position;
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((posB.latitude - posA.latitude) * p) / 2 +
        cos(posA.latitude * p) *
            cos(posB.latitude * p) *
            (1 - cos((posB.longitude - posA.longitude) * p)) /
            2;
    return 12742 * asin(sqrt(a));
  }

  void saveLog(ItineraryLog log) {
    savedLogs.add(log);
  }

  void removeLog(int index) {
    savedLogs.removeAt(index);
  }

  void clearLogs() {
    savedLogs.clear();
  }
}