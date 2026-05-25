import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../config.dart';
import '../session_cookie_store.dart';
import 'ride_mobility_api.dart';
import 'ride_trip_map_marker_images.dart';
import 'ride_trip_map_support.dart';

const Duration _rideTripMapProviderProbeTimeout = Duration(seconds: 4);

class RideTripMapCard extends StatefulWidget {
  final String? baseUrl;
  final RidePlatformBootstrap? bootstrap;
  final RideTripMapSnapshot? snapshot;
  final RideGeoPoint? currentLocation;
  final double height;
  final String unavailableMessage;
  final String loadingMessage;
  final bool allowFullscreen;
  final bool standalone;
  final bool showZoomControls;
  final String? fullscreenTitle;
  final ValueChanged<RideGeoPoint>? onPointSelected;

  const RideTripMapCard({
    super.key,
    required this.baseUrl,
    required this.bootstrap,
    required this.snapshot,
    required this.currentLocation,
    required this.unavailableMessage,
    required this.loadingMessage,
    this.height = 220,
    this.allowFullscreen = true,
    this.standalone = false,
    this.showZoomControls = true,
    this.fullscreenTitle,
    this.onPointSelected,
  });

  @override
  State<RideTripMapCard> createState() => _RideTripMapCardState();
}

class _RideTripMapCardState extends State<RideTripMapCard> {
  maplibre.MapLibreMapController? _mapController;
  bool _mapStyleLoaded = false;
  bool _mapOverlaysApplied = false;
  bool _resolvingMapStyle = false;
  bool _usingTomTomMapStyle = false;
  bool _hasAttemptedTomTomMapProbe = false;
  String? _resolvedMapStyleString;
  double? _cameraZoom;

  maplibre.LatLng get _initialTarget => rideTripMapInitialTarget(
        snapshot: widget.snapshot,
        currentLocation: widget.currentLocation,
      );

  double get _initialZoom => rideTripMapInitialZoom(
        snapshot: widget.snapshot,
        currentLocation: widget.currentLocation,
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
  void didUpdateWidget(covariant RideTripMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final baseUrlChanged = (oldWidget.baseUrl ?? '') != (widget.baseUrl ?? '');
    if (_canRenderMapLibre &&
        (baseUrlChanged || oldWidget.bootstrap != widget.bootstrap)) {
      _hasAttemptedTomTomMapProbe = false;
      unawaited(_resolveMapStyle());
    }
    if (oldWidget.snapshot != widget.snapshot ||
        oldWidget.currentLocation != widget.currentLocation) {
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

  String _fullscreenTitle(BuildContext context) {
    final explicit = (widget.fullscreenTitle ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return 'Map';
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
            .timeout(_rideTripMapProviderProbeTimeout);
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
    final snapshot = widget.snapshot;
    try {
      if (snapshot == null || !snapshot.hasAnyOverlay) {
        if (_mapOverlaysApplied) {
          await controller.clearLines();
          await controller.clearSymbols();
          _mapOverlaysApplied = false;
        }
        return;
      }

      final routePoints =
          rideTripMapDedupeConsecutivePoints(snapshot.routePoints);
      final pickupMarker =
          rideTripMapLatLngFromGeoPoint(snapshot.pickupLocation);
      final destinationMarker =
          rideTripMapLatLngFromGeoPoint(snapshot.destinationLocation);
      final driverMarker =
          rideTripMapLatLngFromGeoPoint(snapshot.driverLocation);

      await controller.clearLines();
      await controller.clearSymbols();
      if (routePoints.length >= 2) {
        await controller.addLine(
          maplibre.LineOptions(
            geometry: routePoints,
            lineColor: '#0ea5e9',
            lineWidth: 4.0,
          ),
        );
      }
      if (pickupMarker != null) {
        await controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: pickupMarker,
            iconImage:
                rideTripMapMarkerImageId(RideTripMapMarkerVisual.riderPerson),
            iconSize:
                rideTripMapMarkerIconSize(RideTripMapMarkerVisual.riderPerson),
            iconAnchor: 'bottom',
          ),
        );
      }
      if (destinationMarker != null &&
          !_samePoint(destinationMarker, pickupMarker)) {
        await controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: destinationMarker,
            iconImage: rideTripMapMarkerImageId(
              RideTripMapMarkerVisual.destinationFlag,
            ),
            iconSize: rideTripMapMarkerIconSize(
              RideTripMapMarkerVisual.destinationFlag,
            ),
            iconAnchor: 'bottom',
          ),
        );
      }
      if (driverMarker != null) {
        await controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: driverMarker,
            iconImage: rideTripMapMarkerImageId(
              RideTripMapMarkerVisual.driverTaxiActive,
            ),
            iconSize: rideTripMapMarkerIconSize(
              RideTripMapMarkerVisual.driverTaxiActive,
            ),
            iconAnchor: 'bottom',
          ),
        );
      }
      _mapOverlaysApplied = true;

      final focusPoints = <maplibre.LatLng>[
        ...routePoints,
        if (pickupMarker != null) pickupMarker,
        if (destinationMarker != null) destinationMarker,
        if (driverMarker != null) driverMarker,
      ];
      if (focusPoints.isEmpty) {
        return;
      }
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

  bool _samePoint(maplibre.LatLng? a, maplibre.LatLng? b) {
    if (a == null || b == null) return false;
    return (a.latitude - b.latitude).abs() < 1e-7 &&
        (a.longitude - b.longitude).abs() < 1e-7;
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
        builder: (context) => _RideTripMapFullscreenPage(
          title: _fullscreenTitle(context),
          child: RideTripMapCard(
            baseUrl: widget.baseUrl,
            bootstrap: widget.bootstrap,
            snapshot: widget.snapshot,
            currentLocation: widget.currentLocation,
            unavailableMessage: widget.unavailableMessage,
            loadingMessage: widget.loadingMessage,
            allowFullscreen: false,
            standalone: true,
            showZoomControls: widget.showZoomControls,
            fullscreenTitle: widget.fullscreenTitle,
            onPointSelected: widget.onPointSelected,
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
                  tooltip: 'Fullscreen',
                ),
                const SizedBox(height: 8),
              ],
              if (widget.showZoomControls) ...[
                _buildControlButton(
                  icon: Icons.add_rounded,
                  onPressed: () => unawaited(_adjustZoom(rideTripMapZoomStep)),
                  tooltip: 'Zoom in',
                ),
                const SizedBox(height: 8),
                _buildControlButton(
                  icon: Icons.remove_rounded,
                  onPressed: () => unawaited(_adjustZoom(-rideTripMapZoomStep)),
                  tooltip: 'Zoom out',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailableSurface() {
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Center(child: Text(widget.unavailableMessage)),
    );
    if (widget.standalone) {
      return SizedBox.expand(child: content);
    }
    return Card(child: content);
  }

  Widget _buildLoadingSurface() {
    final content = Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(widget.loadingMessage),
        ],
      ),
    );
    if (widget.standalone) {
      return SizedBox.expand(child: content);
    }
    return Card(
      child: SizedBox(
        height: widget.height,
        child: content,
      ),
    );
  }

  Widget _buildMapSurface() {
    final styleString = _styleString;
    return _buildMapChrome(
      child: maplibre.MapLibreMap(
        key: ValueKey<String>('ride-trip-map-$styleString'),
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
        onMapClick: widget.onPointSelected == null
            ? null
            : (_, latLng) {
                widget.onPointSelected!(
                  RideGeoPoint(
                    lat: latLng.latitude,
                    lon: latLng.longitude,
                  ),
                );
              },
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

  @override
  Widget build(BuildContext context) {
    if (!_canRenderMapLibre) {
      return _buildUnavailableSurface();
    }
    if (_resolvingMapStyle && _resolvedMapStyleString == null) {
      return _buildLoadingSurface();
    }
    if (widget.standalone) {
      return SizedBox.expand(child: _buildMapSurface());
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: widget.height,
        child: _buildMapSurface(),
      ),
    );
  }
}

class _RideTripMapFullscreenPage extends StatelessWidget {
  final String title;
  final Widget child;

  const _RideTripMapFullscreenPage({
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
