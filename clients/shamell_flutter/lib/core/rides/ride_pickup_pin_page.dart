import 'package:flutter/material.dart';

import 'ride_mobility_api.dart';
import 'ride_trip_map_card.dart';
import 'ride_trip_map_support.dart';

class RideLocationPinPage extends StatefulWidget {
  final String? baseUrl;
  final RidePlatformBootstrap? bootstrap;
  final RideGeoPoint? currentLocation;
  final RideGeoPoint? initialPinnedLocation;
  final RideGeoPoint? pickupLocation;
  final RideGeoPoint? destinationLocation;
  final bool isArabic;
  final bool pinningDestination;

  const RideLocationPinPage({
    super.key,
    required this.baseUrl,
    required this.bootstrap,
    required this.currentLocation,
    required this.initialPinnedLocation,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.isArabic,
    required this.pinningDestination,
  });

  @override
  State<RideLocationPinPage> createState() => _RideLocationPinPageState();
}

class _RideLocationPinPageState extends State<RideLocationPinPage> {
  RideGeoPoint? _selectedPoint;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialPinnedLocation ?? widget.currentLocation;
  }

  RideTripMapSnapshot _mapSnapshot() {
    return RideTripMapSnapshot(
      routePoints: const [],
      driverLocation: null,
      pickupLocation:
          widget.pinningDestination ? widget.pickupLocation : _selectedPoint,
      destinationLocation: widget.pinningDestination
          ? _selectedPoint
          : widget.destinationLocation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final coordinateLabel = _selectedPoint == null
        ? (widget.isArabic
            ? 'اضغط على الخريطة لتحديد نقطة الانطلاق.'
            : 'Tap the map to place your pickup pin.')
        : rideTripMapCoordinateLabel(_selectedPoint!);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pinningDestination
              ? (widget.isArabic ? 'تثبيت الوجهة' : 'Pin destination')
              : (widget.isArabic ? 'تثبيت نقطة الانطلاق' : 'Pin pickup'),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _selectedPoint == null
              ? null
              : () => Navigator.of(context).pop(_selectedPoint),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(
            widget.pinningDestination
                ? (widget.isArabic
                    ? 'استخدم هذه الوجهة'
                    : 'Use this destination')
                : (widget.isArabic ? 'استخدم هذا الموقع' : 'Use this pickup'),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.pinningDestination
                    ? (widget.isArabic
                        ? 'اضغط على الخريطة لتثبيت الوجهة. يمكنك التحريك والتكبير قبل التأكيد.'
                        : 'Tap the map to pin the destination. You can pan and zoom before confirming.')
                    : (widget.isArabic
                        ? 'اضغط على الخريطة لتثبيت نقطة الانطلاق. يمكنك التحريك والتكبير قبل التأكيد.'
                        : 'Tap the map to pin the pickup. You can pan and zoom before confirming.'),
              ),
              const SizedBox(height: 8),
              Text(
                coordinateLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .72),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: RideTripMapCard(
                  baseUrl: widget.baseUrl,
                  bootstrap: widget.bootstrap,
                  snapshot: _mapSnapshot(),
                  currentLocation: widget.currentLocation,
                  fullscreenTitle: widget.pinningDestination
                      ? (widget.isArabic ? 'خريطة الوجهة' : 'Destination map')
                      : (widget.isArabic
                          ? 'خريطة نقطة الانطلاق'
                          : 'Pickup map'),
                  unavailableMessage: widget.isArabic
                      ? 'عرض الخريطة عبر MapLibre غير متاح في هذا البناء.'
                      : 'MapLibre map is not available in this build.',
                  loadingMessage: widget.isArabic
                      ? (widget.pinningDestination
                          ? 'جاري تهيئة خريطة الوجهة…'
                          : 'جاري تهيئة خريطة نقطة الانطلاق…')
                      : (widget.pinningDestination
                          ? 'Preparing destination map…'
                          : 'Preparing pickup map…'),
                  allowFullscreen: false,
                  standalone: true,
                  onPointSelected: (point) {
                    setState(() {
                      _selectedPoint = point;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
