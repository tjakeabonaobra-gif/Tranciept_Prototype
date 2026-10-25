import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/transit_models.dart';
import '../services/navigation_service.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final NavigationService _navService = NavigationService();
  final MapController _mapController = MapController();

  StopNode? selectedOrigin;
  StopNode? selectedDestination;

  List<LatLng> calculatedPath = [];
  double totalDistanceKm = 0.0;
  double estimatedFare = 0.0;
  String assignedCoop = 'Standard Line';
  bool isDiscounted = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _navService.initializeGraph();
    setState(() {
      if (_navService.nodes.length >= 2) {
        selectedOrigin = _navService.nodes.values.first;
        selectedDestination = _navService.nodes.values.elementAt(2);
      }
      isLoading = false;
    });
    _updateRoute();
  }

  void _updateRoute() {
    if (selectedOrigin == null || selectedDestination == null) return;

    final result = _navService.calculateRoute(
      origin: selectedOrigin!,
      destination: selectedDestination!,
      isDiscounted: isDiscounted,
    );

    setState(() {
      calculatedPath = result.pathCoordinates;
      totalDistanceKm = result.totalDistanceKm;
      estimatedFare = result.estimatedFare;
      assignedCoop = result.operatorName;
    });

    if (calculatedPath.isNotEmpty) {
      _mapController.move(calculatedPath.first, 14.0);
    }
  }

  void _handleSaveLog() {
    if (selectedOrigin == null || selectedDestination == null) return;

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final log = ItineraryLog(
      id: now.millisecondsSinceEpoch.toString(),
      timestamp: timeStr,
      origin: selectedOrigin!.name,
      destination: selectedDestination!.name,
      distanceKm: totalDistanceKm.toStringAsFixed(2),
      fare: estimatedFare.toStringAsFixed(2),
      operatorName: assignedCoop,
      isDiscounted: isDiscounted,
    );

    _navService.saveLog(log);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Itinerary saved! Total logs: ${_navService.savedLogs.length}'),
        action: SnackBarAction(
          label: 'VIEW LOGS',
          onPressed: _showSavedLogsDialog,
        ),
      ),
    );
  }

  void _showSavedLogsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Saved Itineraries (${_navService.savedLogs.length})'),
                  if (_navService.savedLogs.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _navService.clearLogs());
                        setModalState(() {});
                      },
                      icon: const Icon(Icons.delete_sweep, color: Colors.red),
                      label: const Text('Clear All', style: TextStyle(color: Colors.red)),
                    ),
                ],
              ),
              content: SizedBox(
                width: 520,
                height: 380,
                child: _navService.savedLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'No saved itineraries yet.\nClick "Save Itinerary" to add route logs.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _navService.savedLogs.length,
                        itemBuilder: (context, index) {
                          final item = _navService.savedLogs[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8.0),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.indigo.shade100,
                                child: Text('${index + 1}',
                                    style: TextStyle(color: Colors.indigo.shade900)),
                              ),
                              title: Text('${item.origin} ➔ ${item.destination}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(
                                'Operator: ${item.operatorName}\nDistance: ${item.distanceKm} km | Time: ${item.timestamp}${item.isDiscounted ? ' (20% Off)' : ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₱${item.fare}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                                    onPressed: () {
                                      setState(() => _navService.removeLog(index));
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSearchableAutocomplete({
    required String label,
    required StopNode? initialValue,
    required ValueChanged<StopNode?> onSelected,
  }) {
    return Autocomplete<StopNode>(
      initialValue: TextEditingValue(text: initialValue?.name ?? ''),
      displayStringForOption: (node) => node.name,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _navService.nodes.values;
        }
        return _navService.nodes.values.where((node) =>
            node.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onEditingComplete: onEditingComplete,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.search),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TranCeipt Prototype — Legazpi Nav'),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: _showSavedLogsDialog,
              icon: const Icon(Icons.bookmarks, size: 18),
              label: Text('Saved Logs (${_navService.savedLogs.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 360,
            color: Colors.grey.shade50,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEARCH & ROUTE SELECTION',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                _buildSearchableAutocomplete(
                  label: 'Origin (Type to Search)',
                  initialValue: selectedOrigin,
                  onSelected: (node) {
                    selectedOrigin = node;
                    _updateRoute();
                  },
                ),
                const SizedBox(height: 12),
                _buildSearchableAutocomplete(
                  label: 'Destination (Type to Search)',
                  initialValue: selectedDestination,
                  onSelected: (node) {
                    selectedDestination = node;
                    _updateRoute();
                  },
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('20% Discount (Senior/Student/PWD)', style: TextStyle(fontSize: 13)),
                  value: isDiscounted,
                  onChanged: (val) {
                    isDiscounted = val ?? false;
                    _updateRoute();
                  },
                ),
                const Divider(height: 28),
                const Text(
                  'ITINERARY RECEIPT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Card(
                  elevation: 0,
                  color: Colors.indigo.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Distance: ${totalDistanceKm.toStringAsFixed(2)} km'),
                        const SizedBox(height: 4),
                        Text('Operator: $assignedCoop',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        const Text('Mode: Jeepney'),
                        const SizedBox(height: 8),
                        Text(
                          'Estimated Fare: PHP ${estimatedFare.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleSaveLog,
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Save Itinerary'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showSavedLogsDialog,
                    icon: const Icon(Icons.list_alt),
                    label: Text('View Saved Logs (${_navService.savedLogs.length})'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _navService.nodes.isNotEmpty
                    ? _navService.nodes.values.first.position
                    : const LatLng(13.1391, 123.7438),
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tranceipt.app',
                ),
                if (calculatedPath.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: calculatedPath,
                        strokeWidth: 5.5,
                        color: Colors.indigo.shade700,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: _navService.nodes.values.map((node) {
                    final isOrigin = node.id == selectedOrigin?.id;
                    final isDest = node.id == selectedDestination?.id;
                    Color markerColor = Colors.blue.shade400;
                    if (isOrigin) markerColor = Colors.green;
                    if (isDest) markerColor = Colors.red;

                    return Marker(
                      point: node.position,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.location_on, color: markerColor, size: isOrigin || isDest ? 36 : 24),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}