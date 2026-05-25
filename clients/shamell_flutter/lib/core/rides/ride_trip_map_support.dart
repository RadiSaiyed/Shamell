import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'ride_hailing_store.dart';
import 'ride_mobility_api.dart';
import 'ride_platform_contracts.dart';

const double rideTripMapCurrentLocationZoom = 14.5;
const double rideTripMapDefaultZoom = 10.0;
const double rideTripMapRouteZoom = 11.5;
const double rideTripMapMinZoom = 4.0;
const double rideTripMapMaxZoom = 18.5;
const double rideTripMapZoomStep = 1.0;
const maplibre.LatLng rideTripMapDefaultTarget =
    maplibre.LatLng(33.5138, 36.2765);

enum RideTripMapStage {
  pickup,
  destination,
}

enum RideTripMapMarkerVisual {
  driverTaxiActive,
  driverTaxiIdle,
  riderPerson,
  destinationFlag,
}

class RideTripMapSnapshot {
  final List<maplibre.LatLng> routePoints;
  final RideGeoPoint? driverLocation;
  final RideGeoPoint? pickupLocation;
  final RideGeoPoint? destinationLocation;

  const RideTripMapSnapshot({
    required this.routePoints,
    required this.driverLocation,
    required this.pickupLocation,
    required this.destinationLocation,
  });

  bool get hasRoute => routePoints.isNotEmpty;

  bool get hasAnyOverlay =>
      hasRoute ||
      driverLocation != null ||
      pickupLocation != null ||
      destinationLocation != null;
}

class RideDriverFleetMapMarker {
  final String driverAccountId;
  final maplibre.LatLng point;
  final bool isIdleOnline;
  final String? driverName;
  final String? carPlate;
  final String? activeRideId;
  final String? activePickup;
  final String? activeDestination;

  const RideDriverFleetMapMarker({
    required this.driverAccountId,
    required this.point,
    required this.isIdleOnline,
    required this.driverName,
    required this.carPlate,
    required this.activeRideId,
    required this.activePickup,
    required this.activeDestination,
  });

  bool get hasActiveRide => activeRideId != null;
}

String rideTripMapMarkerImageId(RideTripMapMarkerVisual visual) {
  switch (visual) {
    case RideTripMapMarkerVisual.driverTaxiActive:
      return 'shamell-driver-taxi-active';
    case RideTripMapMarkerVisual.driverTaxiIdle:
      return 'shamell-driver-taxi-idle';
    case RideTripMapMarkerVisual.riderPerson:
      return 'shamell-rider-person';
    case RideTripMapMarkerVisual.destinationFlag:
      return 'shamell-destination-flag';
  }
}

double rideTripMapMarkerIconSize(RideTripMapMarkerVisual visual) {
  switch (visual) {
    case RideTripMapMarkerVisual.driverTaxiActive:
    case RideTripMapMarkerVisual.driverTaxiIdle:
      return 0.72;
    case RideTripMapMarkerVisual.riderPerson:
      return 0.66;
    case RideTripMapMarkerVisual.destinationFlag:
      return 0.62;
  }
}

RideTripMapStage rideTripMapStageForStatus(RideTripStatus status) {
  switch (status) {
    case RideTripStatus.tripStarted:
    case RideTripStatus.tripInProgress:
    case RideTripStatus.paymentFailed:
    case RideTripStatus.tripCompleted:
      return RideTripMapStage.destination;
    default:
      return RideTripMapStage.pickup;
  }
}

bool rideTripStatusHasLiveDriverTracking(RideTripStatus status) {
  switch (status) {
    case RideTripStatus.driverAssigned:
    case RideTripStatus.driverArriving:
    case RideTripStatus.driverArrived:
    case RideTripStatus.tripStarted:
    case RideTripStatus.tripInProgress:
    case RideTripStatus.paymentFailed:
      return true;
    default:
      return false;
  }
}

RideGeoPoint? rideGeoPointFromCoordinatePoint(RideCoordinatePoint? point) {
  if (point == null) return null;
  return RideGeoPoint(lat: point.lat, lon: point.lon);
}

maplibre.LatLng? rideTripMapLatLngFromGeoPoint(RideGeoPoint? point) {
  if (point == null) return null;
  return maplibre.LatLng(point.lat, point.lon);
}

double rideTripMapClampZoom(double zoom) {
  return zoom.clamp(rideTripMapMinZoom, rideTripMapMaxZoom).toDouble();
}

String rideTripMapCoordinateLabel(RideGeoPoint point) {
  return '${point.lat.toStringAsFixed(5)}, ${point.lon.toStringAsFixed(5)}';
}

List<maplibre.LatLng> rideTripMapPointsFromRoute(List<RideGeoPoint> points) {
  if (points.isEmpty) {
    return const <maplibre.LatLng>[];
  }
  final mapped = points
      .map((point) => maplibre.LatLng(point.lat, point.lon))
      .toList(growable: false);
  return rideTripMapDedupeConsecutivePoints(mapped);
}

List<maplibre.LatLng> rideTripMapDedupeConsecutivePoints(
  List<maplibre.LatLng> raw,
) {
  if (raw.length < 2) return raw;
  final normalized = <maplibre.LatLng>[raw.first];
  for (var i = 1; i < raw.length; i++) {
    final current = raw[i];
    final previous = normalized.last;
    final sameLatitude = (current.latitude - previous.latitude).abs() < 1e-7;
    final sameLongitude = (current.longitude - previous.longitude).abs() < 1e-7;
    if (sameLatitude && sameLongitude) continue;
    normalized.add(current);
  }
  return normalized;
}

maplibre.LatLngBounds? rideTripMapBoundsForPoints(
    List<maplibre.LatLng> points) {
  if (points.isEmpty) return null;
  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLon = points.first.longitude;
  var maxLon = points.first.longitude;
  for (final point in points.skip(1)) {
    if (point.latitude < minLat) minLat = point.latitude;
    if (point.latitude > maxLat) maxLat = point.latitude;
    if (point.longitude < minLon) minLon = point.longitude;
    if (point.longitude > maxLon) maxLon = point.longitude;
  }
  return maplibre.LatLngBounds(
    southwest: maplibre.LatLng(minLat, minLon),
    northeast: maplibre.LatLng(maxLat, maxLon),
  );
}

List<RideDriverFleetMapMarker> rideDriverFleetMapMarkers(
  Iterable<RideOperatorDriverRosterEntry> drivers,
) {
  final markers = <RideDriverFleetMapMarker>[];
  for (final driver in drivers) {
    final location = driver.location;
    if (!driver.isOnline || location == null) {
      continue;
    }
    markers.add(
      RideDriverFleetMapMarker(
        driverAccountId: driver.driverAccountId,
        point: maplibre.LatLng(location.lat, location.lon),
        isIdleOnline: driver.isIdleOnline,
        driverName: driver.driverName,
        carPlate: driver.carPlate,
        activeRideId: driver.activeRideId,
        activePickup: driver.activePickup,
        activeDestination: driver.activeDestination,
      ),
    );
  }
  markers.sort((a, b) {
    if (a.isIdleOnline != b.isIdleOnline) {
      return a.isIdleOnline ? 1 : -1;
    }
    final aLabel = (a.driverName ?? a.driverAccountId).toLowerCase();
    final bLabel = (b.driverName ?? b.driverAccountId).toLowerCase();
    return aLabel.compareTo(bLabel);
  });
  return List<RideDriverFleetMapMarker>.unmodifiable(markers);
}

maplibre.LatLng rideDriverFleetMapInitialTarget(
  List<RideDriverFleetMapMarker> markers,
) {
  if (markers.isNotEmpty) {
    return markers.first.point;
  }
  return rideTripMapDefaultTarget;
}

maplibre.LatLng rideTripMapInitialTarget({
  required RideTripMapSnapshot? snapshot,
  RideGeoPoint? currentLocation,
}) {
  if (snapshot != null && snapshot.routePoints.isNotEmpty) {
    return snapshot.routePoints.first;
  }
  final driverTarget = rideTripMapLatLngFromGeoPoint(snapshot?.driverLocation);
  if (driverTarget != null) return driverTarget;
  final pickupTarget = rideTripMapLatLngFromGeoPoint(snapshot?.pickupLocation);
  if (pickupTarget != null) return pickupTarget;
  final destinationTarget =
      rideTripMapLatLngFromGeoPoint(snapshot?.destinationLocation);
  if (destinationTarget != null) return destinationTarget;
  if (currentLocation != null) {
    return maplibre.LatLng(currentLocation.lat, currentLocation.lon);
  }
  return rideTripMapDefaultTarget;
}

double rideTripMapInitialZoom({
  required RideTripMapSnapshot? snapshot,
  RideGeoPoint? currentLocation,
}) {
  if (snapshot != null && snapshot.routePoints.isNotEmpty) {
    return rideTripMapRouteZoom;
  }
  if ((snapshot?.driverLocation) != null ||
      (snapshot?.pickupLocation) != null ||
      (snapshot?.destinationLocation) != null ||
      currentLocation != null) {
    return rideTripMapCurrentLocationZoom;
  }
  return rideTripMapDefaultZoom;
}
