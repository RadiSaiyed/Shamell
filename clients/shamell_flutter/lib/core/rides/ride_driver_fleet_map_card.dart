import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../config.dart';
import '../session_cookie_store.dart';
import 'ride_mobility_api.dart';
import 'ride_platform_contracts.dart';
import 'ride_trip_map_marker_images.dart';
import 'ride_trip_map_support.dart';

const Duration _rideDriverFleetMapProviderProbeTimeout = Duration(seconds: 4);

class RideDriverFleetMapCard extends StatefulWidget {
  final String? baseUrl;
  final RidePlatformBootstrap? bootstrap;
  final List<RideOperatorDriverRosterEntry> drivers;
  final bool isArabic;
  final double height;
  final bool allowFullscreen;
  final bool standalone;
  final bool showZoomControls;
  final String? fullscreenTitle;

  const RideDriverFleetMapCard({
    super.key,
    required this.baseUrl,
    required this.bootstrap,
    required this.drivers,
    required this.isArabic,
    this.height = 280,
    this.allowFullscreen = true,
    this.standalone = false,
    this.showZoomControls = true,
    this.fullscreenTitle,
  });

  @override
  State<RideDriverFleetMapCard> createState() => _RideDriverFleetMapCardState();
}

class _RideDriverFleetMapCardState extends State<RideDriverFleetMapCard> {
  maplibre.MapLibreMapController? _mapController;
  bool _mapStyleLoaded = false;
  bool _mapOverlaysApplied = false;
  bool _resolvingMapStyle = false;
  bool _usingTomTomMapStyle = false;
  bool _hasAttemptedTomTomMapProbe = false;
  String? _resolvedMapStyleString;
  double? _cameraZoom;

  List<RideDriverFleetMapMarker> get _markers =>
      rideDriverFleetMapMarkers(widget.drivers);

  int get _onlineCount =>
      widget.drivers.where((driver) => driver.isOnline).length;

  int get _trackedCount => _markers.length;

  int get _idleCount => _markers.where((marker) => marker.isIdleOnline).length;

  int get _activeCount => _trackedCount - _idleCount;

  int get _missingGpsCount => max(0, _onlineCount - _trackedCount);

  maplibre.LatLng get _initialTarget =>
      rideDriverFleetMapInitialTarget(_markers);

  double get _initialZoom => rideTripMapInitialZoom(
        snapshot: null,
        currentLocation: _markers.isEmpty
            ? null
            : RideGeoPoint(
                lat: _markers.first.point.latitude,
                lon: _markers.first.point.longitude,
              ),
      );

  @override
  void initState() {
    super.initState();
    _cameraZoom = _initialZoom;
    if (_canRenderMapLibre) {
      unawaited(_resolveMapStyle());
    }
  }

  @override
  void didUpdateWidget(covariant RideDriverFleetMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final baseUrlChanged = (oldWidget.baseUrl ?? '') != (widget.baseUrl ?? '');
    if (_canRenderMapLibre &&
        (baseUrlChanged || oldWidget.bootstrap != widget.bootstrap)) {
      _hasAttemptedTomTomMapProbe = false;
      unawaited(_resolveMapStyle());
    }
    if (oldWidget.drivers != widget.drivers) {
      _cameraZoom ??= _initialZoom;
      unawaited(_syncMapOverlays());
    }
  }

  bool get _canRenderMapLibre {
    if (!useMapLibreMaps) return false;
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    if (bindingType.contains('TestWidgetsFlutterBinding')) {
      return false;
    }
    return true;
  }

  String get _fallbackStyleString {
    final configuredStyle = kOsmStyleUrl.trim();
    if (configuredStyle.isNotEmpty) return configuredStyle;
    return maplibre.MapLibreStyles.openfreemapLiberty;
  }

  String get _styleString => _resolvedMapStyleString ?? _fallbackStyleString;

  String _fullscreenTitle() {
    final explicit = (widget.fullscreenTitle ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return widget.isArabic ? 'خريطة السائقين' : 'Driver map';
  }

  String? _mapTileHeaderFilterPattern() {
    final probeUri = buildTomTomMapProbeTileUri(widget.baseUrl ?? '');
    if (probeUri == null) return null;
    final prefix =
        '${probeUri.scheme}://${probeUri.authority}/me/rides/map_tiles/';
    return '^${RegExp.escape(prefix)}.*\$';
  }

  Future<void> _configureMapRequestHeaders(
    maplibre.MapLibreMapController controller,
    String styleString,
  ) async {
    final filterPattern = _mapTileHeaderFilterPattern();
    if (filterPattern == null) return;
    final cookie =
        (await getSessionCookieHeader(widget.baseUrl ?? '') ?? '').trim();
    final headers = <String, String>{
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
    try {
      await controller.setCustomHeaders(headers, <String>[filterPattern]);
      if (_usingTomTomMapStyle) {
        await controller.setStyle(styleString);
      }
    } catch (_) {}
  }

  bool _shouldPreferTomTomMap() {
    if (useTomTomMapDisplayPrimary) return true;
    final stack = (widget.bootstrap?.mapDisplayStack ?? '').toLowerCase();
    return stack.contains('tomtom');
  }

  Future<void> _resolveMapStyle() async {
    final fallback = _fallbackStyleString;
    if (!_shouldPreferTomTomMap()) {
      if (!mounted) return;
      if (_resolvedMapStyleString == fallback &&
          !_resolvingMapStyle &&
          !_usingTomTomMapStyle) {
        return;
      }
      setState(() {
        _resolvedMapStyleString = fallback;
        _resolvingMapStyle = false;
        _usingTomTomMapStyle = false;
        _hasAttemptedTomTomMapProbe = false;
      });
      return;
    }

    if (_hasAttemptedTomTomMapProbe && _resolvedMapStyleString != null) {
      return;
    }

    final probeUri = buildTomTomMapProbeTileUri(widget.baseUrl ?? '');
    if (probeUri == null) {
      if (!mounted) return;
      setState(() {
        _resolvedMapStyleString = fallback;
        _resolvingMapStyle = false;
        _usingTomTomMapStyle = false;
        _hasAttemptedTomTomMapProbe = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _resolvingMapStyle = true;
    });
    _hasAttemptedTomTomMapProbe = true;

    var useTomTomDisplay = false;
    final client = http.Client();
    try {
      final headers =
          await shamellSessionHeadersForBaseUrl(widget.baseUrl ?? '');
      if ((headers['cookie'] ?? '').trim().isEmpty) {
        useTomTomDisplay = false;
      } else {
        final resp = await client
            .get(probeUri, headers: headers)
            .timeout(_rideDriverFleetMapProviderProbeTimeout);
        useTomTomDisplay = resp.statusCode >= 200 && resp.statusCode < 300;
      }
    } catch (_) {
      useTomTomDisplay = false;
    } finally {
      client.close();
    }

    final resolvedStyle = useTomTomDisplay
        ? buildTomTomMapLibreRasterStyleJson(widget.baseUrl ?? '')
        : fallback;
    if (!mounted) return;
    setState(() {
      _resolvedMapStyleString = resolvedStyle;
      _resolvingMapStyle = false;
      _usingTomTomMapStyle = useTomTomDisplay;
    });
  }

  Future<void> _syncMapOverlays() async {
    final controller = _mapController;
    if (controller == null || !_mapStyleLoaded) return;
    final markers = _markers;
    try {
      if (markers.isEmpty) {
        if (_mapOverlaysApplied) {
          await controller.clearSymbols();
          _mapOverlaysApplied = false;
        }
        return;
      }

      await controller.clearSymbols();
      for (final marker in markers) {
        final visual = marker.isIdleOnline
            ? RideTripMapMarkerVisual.driverTaxiIdle
            : RideTripMapMarkerVisual.driverTaxiActive;
        await controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: marker.point,
            iconImage: rideTripMapMarkerImageId(visual),
            iconSize: rideTripMapMarkerIconSize(visual),
            iconAnchor: 'bottom',
          ),
        );
      }
      _mapOverlaysApplied = true;

      final focusPoints =
          markers.map((marker) => marker.point).toList(growable: false);
      if (focusPoints.length == 1) {
        await controller.animateCamera(
          maplibre.CameraUpdate.newLatLngZoom(
            focusPoints.first,
            rideTripMapCurrentLocationZoom,
          ),
        );
        return;
      }
      final bounds = rideTripMapBoundsForPoints(focusPoints);
      if (bounds != null) {
        await controller.animateCamera(
          maplibre.CameraUpdate.newLatLngBounds(
            bounds,
            left: 48,
            right: 48,
            top: 56,
            bottom: 56,
          ),
        );
      }
    } catch (_) {}
  }

  String _summaryLabel() {
    if (widget.isArabic) {
      return 'يعرض $_trackedCount من أصل $_onlineCount سائقين متصلين على الخريطة'
          ' • متاح $_idleCount • في رحلة $_activeCount';
    }
    return 'Tracking $_trackedCount of $_onlineCount online drivers'
        ' • Idle $_idleCount • On trip $_activeCount';
  }

  String _gpsNoteLabel() {
    if (_onlineCount == 0) {
      return widget.isArabic
          ? 'لا يوجد سائقون متصلون حالياً.'
          : 'No online drivers right now.';
    }
    if (_trackedCount == 0) {
      return widget.isArabic
          ? 'السائقون المتصلون لم يرسلوا إحداثيات GPS بعد.'
          : 'Online drivers have not published GPS yet.';
    }
    if (_missingGpsCount <= 0) {
      return widget.isArabic
          ? 'كل السائقين المتصلين يرسلون مواقعهم الآن.'
          : 'All online drivers are publishing location.';
    }
    return widget.isArabic
        ? 'بانتظار إحداثيات GPS من $_missingGpsCount سائقين.'
        : 'Waiting for GPS from $_missingGpsCount drivers.';
  }

  Widget _legendChip({
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _rememberCameraPosition() async {
    final controller = _mapController;
    if (controller == null) return;
    maplibre.CameraPosition? position = controller.cameraPosition;
    position ??= await controller.queryCameraPosition();
    if (!mounted || position == null) return;
    setState(() {
      _cameraZoom = position!.zoom;
    });
  }

  Future<void> _adjustZoom(double delta) async {
    final controller = _mapController;
    if (controller == null) return;
    var position = controller.cameraPosition;
    position ??= await controller.queryCameraPosition();
    final target = position?.target ?? _initialTarget;
    final nextZoom = rideTripMapClampZoom(
        (position?.zoom ?? _cameraZoom ?? _initialZoom) + delta);
    try {
      await controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(target, nextZoom),
      );
      if (!mounted) return;
      setState(() {
        _cameraZoom = nextZoom;
      });
    } catch (_) {}
  }

  Future<void> _openFullscreen() async {
    if (!widget.allowFullscreen || widget.standalone) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _RideDriverFleetMapFullscreenPage(
          title: _fullscreenTitle(),
          child: RideDriverFleetMapCard(
            baseUrl: widget.baseUrl,
            bootstrap: widget.bootstrap,
            drivers: widget.drivers,
            isArabic: widget.isArabic,
            allowFullscreen: false,
            standalone: true,
            showZoomControls: widget.showZoomControls,
            fullscreenTitle: widget.fullscreenTitle,
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: .92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip ?? '',
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }

  Widget _buildMapChrome({required Widget child}) {
    final showControls = widget.showZoomControls ||
        (widget.allowFullscreen && !widget.standalone);
    if (!showControls) return child;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              if (widget.allowFullscreen && !widget.standalone) ...[
                _buildControlButton(
                  icon: Icons.open_in_full_rounded,
                  onPressed: _openFullscreen,
                  tooltip: widget.isArabic ? 'ملء الشاشة' : 'Fullscreen',
                ),
                const SizedBox(height: 8),
              ],
              if (widget.showZoomControls) ...[
                _buildControlButton(
                  icon: Icons.add_rounded,
                  onPressed: () => unawaited(_adjustZoom(rideTripMapZoomStep)),
                  tooltip: widget.isArabic ? 'تكبير' : 'Zoom in',
                ),
                const SizedBox(height: 8),
                _buildControlButton(
                  icon: Icons.remove_rounded,
                  onPressed: () => unawaited(_adjustZoom(-rideTripMapZoomStep)),
                  tooltip: widget.isArabic ? 'تصغير' : 'Zoom out',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapBody() {
    if (!_canRenderMapLibre) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.isArabic
                ? 'عرض الخريطة عبر MapLibre غير متاح في هذا البناء.'
                : 'MapLibre live driver map is not available in this build.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_resolvingMapStyle && _resolvedMapStyleString == null) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              widget.isArabic
                  ? 'جاري تهيئة خريطة السائقين…'
                  : 'Preparing live driver map…',
            ),
          ],
        ),
      );
    }
    if (_markers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _gpsNoteLabel(),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final styleString = _styleString;
    return _buildMapChrome(
      child: maplibre.MapLibreMap(
        key: ValueKey<String>('ride-driver-fleet-map-$styleString'),
        styleString: styleString,
        initialCameraPosition: maplibre.CameraPosition(
          target: _initialTarget,
          zoom: _cameraZoom ?? _initialZoom,
        ),
        compassEnabled: false,
        attributionButtonMargins: const Point<double>(8, 8),
        myLocationEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        trackCameraPosition: true,
        onMapCreated: (controller) {
          _mapController = controller;
          _mapStyleLoaded = false;
          unawaited(_configureMapRequestHeaders(controller, styleString));
        },
        onStyleLoadedCallback: () {
          _mapStyleLoaded = true;
          unawaited(() async {
            await ensureRideTripMapMarkerImages(_mapController!);
            await _syncMapOverlays();
          }());
        },
        onCameraIdle: () {
          unawaited(_rememberCameraPosition());
        },
      ),
    );
  }

  Widget _buildStandaloneBodyContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isArabic ? 'خريطة السائقين الحية' : 'Live driver map',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(_summaryLabel()),
        const SizedBox(height: 6),
        Text(_gpsNoteLabel()),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _legendChip(
              color: const Color(0xFF22C55E),
              label: widget.isArabic ? 'متاح' : 'Idle',
            ),
            _legendChip(
              color: const Color(0xFF2563EB),
              label: widget.isArabic ? 'في رحلة' : 'On trip',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.standalone ? 16 : 12),
            child: SizedBox.expand(child: _buildMapBody()),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.standalone) {
      return SizedBox.expand(child: _buildStandaloneBodyContent());
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isArabic ? 'خريطة السائقين الحية' : 'Live driver map',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(_summaryLabel()),
            const SizedBox(height: 6),
            Text(_gpsNoteLabel()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _legendChip(
                  color: const Color(0xFF22C55E),
                  label: widget.isArabic ? 'متاح' : 'Idle',
                ),
                _legendChip(
                  color: const Color(0xFF2563EB),
                  label: widget.isArabic ? 'في رحلة' : 'On trip',
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: widget.height,
                child: _buildMapBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideDriverFleetMapFullscreenPage extends StatelessWidget {
  final String title;
  final Widget child;

  const _RideDriverFleetMapFullscreenPage({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }
}
