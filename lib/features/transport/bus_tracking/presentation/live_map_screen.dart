import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveMapScreen extends StatefulWidget {
  final String busId;
  const LiveMapScreen({super.key, required this.busId});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  LatLng? busLocation;

  @override
  void initState() {
    super.initState();
    _subscribeToLocation();
  }

  void _subscribeToLocation() {
    Supabase.instance.client
        .from('bus_live_locations')
        .stream(primaryKey: ['bus_id'])
        .eq('bus_id', widget.busId)
        .listen((data) {
      if (data.isNotEmpty && mounted) {
        setState(() {
          busLocation = LatLng(data[0]['lat'], data[0]['lng']);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Bus Tracking')),
      body: FlutterMap(
        options: MapOptions(initialCenter: busLocation ?? LatLng(23.8103, 90.4125), initialZoom: 15),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          if (busLocation != null)
            MarkerLayer(markers: [Marker(point: busLocation!, child: const Icon(Icons.directions_bus, color: Colors.blue))]),
        ],
      ),
    );
  }
}
