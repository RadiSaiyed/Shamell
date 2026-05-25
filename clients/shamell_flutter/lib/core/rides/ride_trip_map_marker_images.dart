import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'ride_trip_map_support.dart';

Future<Map<String, Uint8List>>? _rideTripMarkerImageCache;

Future<void> ensureRideTripMapMarkerImages(
  maplibre.MapLibreMapController controller,
) async {
  final images =
      await (_rideTripMarkerImageCache ??= _buildRideTripMapMarkerImages());
  for (final entry in images.entries) {
    try {
      await controller.addImage(entry.key, entry.value);
    } catch (_) {}
  }
}

Future<Map<String, Uint8List>> _buildRideTripMapMarkerImages() async {
  final visuals = RideTripMapMarkerVisual.values;
  final images = <String, Uint8List>{};
  for (final visual in visuals) {
    images[rideTripMapMarkerImageId(visual)] =
        await _buildRideTripMapMarkerImage(visual);
  }
  return Map<String, Uint8List>.unmodifiable(images);
}

Future<Uint8List> _buildRideTripMapMarkerImage(
  RideTripMapMarkerVisual visual,
) {
  switch (visual) {
    case RideTripMapMarkerVisual.driverTaxiActive:
      return _buildMarkerIconBytes(
        icon: Icons.local_taxi_rounded,
        backgroundColor: const Color(0xFF2563EB),
      );
    case RideTripMapMarkerVisual.driverTaxiIdle:
      return _buildMarkerIconBytes(
        icon: Icons.local_taxi_rounded,
        backgroundColor: const Color(0xFF22C55E),
      );
    case RideTripMapMarkerVisual.riderPerson:
      return _buildMarkerIconBytes(
        icon: Icons.person_pin_circle_rounded,
        backgroundColor: const Color(0xFF16A34A),
      );
    case RideTripMapMarkerVisual.destinationFlag:
      return _buildMarkerIconBytes(
        icon: Icons.flag_rounded,
        backgroundColor: const Color(0xFFF97316),
      );
  }
}

Future<Uint8List> _buildMarkerIconBytes({
  required IconData icon,
  required Color backgroundColor,
}) async {
  const markerSize = 112.0;
  const badgeRadius = 34.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = const Offset(markerSize / 2, markerSize / 2);
  final circleRect = Rect.fromCircle(center: center, radius: badgeRadius);
  final pointerPath = Path()
    ..moveTo(center.dx, markerSize - 14)
    ..lineTo(center.dx - 14, center.dy + 18)
    ..lineTo(center.dx + 14, center.dy + 18)
    ..close();
  final shapePath = Path()
    ..addOval(circleRect)
    ..addPath(pointerPath, Offset.zero);

  canvas.drawShadow(shapePath, Colors.black.withValues(alpha: .32), 10, true);
  final fillPaint = Paint()..color = backgroundColor;
  final borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5;
  canvas.drawPath(shapePath, fillPaint);
  canvas.drawPath(shapePath, borderPaint);

  final iconPainter = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: 44,
        color: Colors.white,
      ),
    ),
  )..layout();
  iconPainter.paint(
    canvas,
    Offset(
      center.dx - (iconPainter.width / 2),
      center.dy - 33,
    ),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(markerSize.toInt(), markerSize.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
