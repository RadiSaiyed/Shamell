import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'config.dart';

class ShamellMapWidget extends StatelessWidget {
  final LatLng center;
  final double initialZoom;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final bool myLocationEnabled;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<Object>? onMapCreated;

  const ShamellMapWidget({
    super.key,
    required this.center,
    this.initialZoom = 13,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.myLocationEnabled = true,
    this.onTap,
    this.onMapCreated,
  });

  @override
  Widget build(BuildContext context) {
    final String baseTileUrl = kTomTomMapKey.isNotEmpty
        ? 'https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key=$kTomTomMapKey'
        : kOsmTileUrl;

    final ptsPolylines = <fm.Polyline>[];
    for (final p in polylines) {
      if (p.points.isEmpty) continue;
      ptsPolylines.add(
        fm.Polyline(
          points: p.points
              .map((pt) => ll.LatLng(pt.latitude, pt.longitude))
              .toList(),
          color: p.color,
          strokeWidth: p.width.toDouble(),
        ),
      );
    }

    final markerWidgets = <fm.Marker>[];
    for (final m in markers) {
      markerWidgets.add(
        fm.Marker(
          width: 40,
          height: 40,
          point: ll.LatLng(m.position.latitude, m.position.longitude),
          child: const Icon(Icons.location_pin, color: Colors.red, size: 32),
        ),
      );
    }

    return fm.FlutterMap(
      options: fm.MapOptions(
        initialCenter: ll.LatLng(center.latitude, center.longitude),
        initialZoom: initialZoom,
        onTap: (tapPos, latlng) =>
            onTap?.call(LatLng(latlng.latitude, latlng.longitude)),
      ),
      children: [
        fm.TileLayer(
          urlTemplate: baseTileUrl,
          userAgentPackageName: 'shamell.app',
          subdomains: const ['a', 'b', 'c'],
          tileProvider: CancellableNetworkTileProvider(),
        ),
        if (kOsmTrafficTileUrl.isNotEmpty)
          fm.TileLayer(
            urlTemplate: kOsmTrafficTileUrl,
            userAgentPackageName: 'shamell.app',
            subdomains: const ['a', 'b', 'c'],
            tileProvider: CancellableNetworkTileProvider(),
          ),
        if (ptsPolylines.isNotEmpty) fm.PolylineLayer(polylines: ptsPolylines),
        if (markerWidgets.isNotEmpty) fm.MarkerLayer(markers: markerWidgets),
      ],
    );
  }
}
