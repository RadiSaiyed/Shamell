import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_mobility_api.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';
import 'package:shamell_flutter/core/rides/ride_trip_map_support.dart';

void main() {
  test('trip map stage targets pickup before the ride starts', () {
    expect(
      rideTripMapStageForStatus(RideTripStatus.driverAssigned),
      RideTripMapStage.pickup,
    );
    expect(
      rideTripMapStageForStatus(RideTripStatus.driverArriving),
      RideTripMapStage.pickup,
    );
    expect(
      rideTripMapStageForStatus(RideTripStatus.driverArrived),
      RideTripMapStage.pickup,
    );
  });

  test('trip map stage targets destination once the ride starts', () {
    expect(
      rideTripMapStageForStatus(RideTripStatus.tripStarted),
      RideTripMapStage.destination,
    );
    expect(
      rideTripMapStageForStatus(RideTripStatus.tripInProgress),
      RideTripMapStage.destination,
    );
    expect(
      rideTripMapStageForStatus(RideTripStatus.paymentFailed),
      RideTripMapStage.destination,
    );
  });

  test('trip map only exposes live driver tracking on assigned rides', () {
    expect(
      rideTripStatusHasLiveDriverTracking(RideTripStatus.matching),
      isFalse,
    );
    expect(
      rideTripStatusHasLiveDriverTracking(RideTripStatus.driverAssigned),
      isTrue,
    );
    expect(
      rideTripStatusHasLiveDriverTracking(RideTripStatus.tripInProgress),
      isTrue,
    );
    expect(
      rideTripStatusHasLiveDriverTracking(RideTripStatus.tripCompleted),
      isFalse,
    );
  });

  test(
      'trip map initial target prefers route then driver then current location',
      () {
    final routeSnapshot = RideTripMapSnapshot(
      routePoints: const <maplibre.LatLng>[
        maplibre.LatLng(33.5, 36.2),
        maplibre.LatLng(33.6, 36.3),
      ],
      driverLocation: const RideGeoPoint(lat: 40, lon: -74),
      pickupLocation: null,
      destinationLocation: null,
    );
    final routeTarget = rideTripMapInitialTarget(
      snapshot: routeSnapshot,
      currentLocation: const RideGeoPoint(lat: 41, lon: -73),
    );
    expect(routeTarget.latitude, closeTo(33.5, 1e-6));
    expect(routeTarget.longitude, closeTo(36.2, 1e-6));

    final driverSnapshot = RideTripMapSnapshot(
      routePoints: const <maplibre.LatLng>[],
      driverLocation: const RideGeoPoint(lat: 40.7128, lon: -74.0060),
      pickupLocation: null,
      destinationLocation: null,
    );
    final driverTarget = rideTripMapInitialTarget(
      snapshot: driverSnapshot,
      currentLocation: const RideGeoPoint(lat: 41, lon: -73),
    );
    expect(driverTarget.latitude, closeTo(40.7128, 1e-6));
    expect(driverTarget.longitude, closeTo(-74.0060, 1e-6));

    final currentLocationTarget = rideTripMapInitialTarget(
      snapshot: null,
      currentLocation: const RideGeoPoint(lat: 41, lon: -73),
    );
    expect(currentLocationTarget.latitude, closeTo(41, 1e-6));
    expect(currentLocationTarget.longitude, closeTo(-73, 1e-6));
  });

  test('trip map dedupes consecutive identical route points', () {
    final deduped = rideTripMapDedupeConsecutivePoints(
      const <maplibre.LatLng>[
        maplibre.LatLng(33.5, 36.2),
        maplibre.LatLng(33.5, 36.2),
        maplibre.LatLng(33.6, 36.3),
      ],
    );

    expect(deduped, hasLength(2));
    expect(deduped.first.latitude, closeTo(33.5, 1e-6));
    expect(deduped.last.longitude, closeTo(36.3, 1e-6));
  });

  test('driver fleet markers keep only online drivers with location', () {
    final markers = rideDriverFleetMapMarkers(
      const <RideOperatorDriverRosterEntry>[
        RideOperatorDriverRosterEntry(
          driverAccountId: 'driver-active',
          availabilityStatus: RideDriverAvailabilityStatus.online,
          lastSeenAtIso: '2026-04-03T08:00:00Z',
          updatedAtIso: '2026-04-03T08:00:00Z',
          location: RideCoordinatePoint(lat: 33.51, lon: 36.28),
          driverName: 'Active Driver',
          carPlate: 'SH001',
          activeRideId: 'ride-1',
          activePickup: 'Bab Touma',
          activeDestination: 'Malki',
        ),
        RideOperatorDriverRosterEntry(
          driverAccountId: 'driver-idle',
          availabilityStatus: RideDriverAvailabilityStatus.online,
          lastSeenAtIso: '2026-04-03T08:01:00Z',
          updatedAtIso: '2026-04-03T08:01:00Z',
          location: RideCoordinatePoint(lat: 33.52, lon: 36.29),
          driverName: 'Idle Driver',
          carPlate: 'SH002',
        ),
        RideOperatorDriverRosterEntry(
          driverAccountId: 'driver-no-gps',
          availabilityStatus: RideDriverAvailabilityStatus.online,
          lastSeenAtIso: '2026-04-03T08:02:00Z',
          updatedAtIso: '2026-04-03T08:02:00Z',
          driverName: 'No GPS',
          carPlate: 'SH003',
        ),
        RideOperatorDriverRosterEntry(
          driverAccountId: 'driver-offline',
          availabilityStatus: RideDriverAvailabilityStatus.offline,
          lastSeenAtIso: '2026-04-03T08:03:00Z',
          updatedAtIso: '2026-04-03T08:03:00Z',
          location: RideCoordinatePoint(lat: 33.53, lon: 36.30),
          driverName: 'Offline Driver',
          carPlate: 'SH004',
        ),
      ],
    );

    expect(markers, hasLength(2));
    expect(markers.first.driverAccountId, 'driver-active');
    expect(markers.first.hasActiveRide, isTrue);
    expect(markers.last.driverAccountId, 'driver-idle');
    expect(markers.last.isIdleOnline, isTrue);
  });

  test('driver fleet map target prefers the first tracked marker', () {
    final markers = rideDriverFleetMapMarkers(
      const <RideOperatorDriverRosterEntry>[
        RideOperatorDriverRosterEntry(
          driverAccountId: 'driver-idle',
          availabilityStatus: RideDriverAvailabilityStatus.online,
          lastSeenAtIso: '2026-04-03T08:00:00Z',
          updatedAtIso: '2026-04-03T08:00:00Z',
          location: RideCoordinatePoint(lat: 33.52, lon: 36.29),
          driverName: 'Idle Driver',
        ),
        RideOperatorDriverRosterEntry(
          driverAccountId: 'driver-active',
          availabilityStatus: RideDriverAvailabilityStatus.online,
          lastSeenAtIso: '2026-04-03T08:01:00Z',
          updatedAtIso: '2026-04-03T08:01:00Z',
          location: RideCoordinatePoint(lat: 33.51, lon: 36.28),
          driverName: 'Active Driver',
          activeRideId: 'ride-1',
        ),
      ],
    );

    final target = rideDriverFleetMapInitialTarget(markers);

    expect(target.latitude, closeTo(33.51, 1e-6));
    expect(target.longitude, closeTo(36.28, 1e-6));
    final fallback = rideDriverFleetMapInitialTarget(
      const <RideDriverFleetMapMarker>[],
    );
    expect(fallback.latitude, closeTo(rideTripMapDefaultTarget.latitude, 1e-6));
    expect(
      fallback.longitude,
      closeTo(rideTripMapDefaultTarget.longitude, 1e-6),
    );
  });

  test('trip map converts presence coordinates into ride geo points', () {
    const coordinate = RideCoordinatePoint(lat: 33.5138, lon: 36.2765);

    final point = rideGeoPointFromCoordinatePoint(coordinate);

    expect(point, isNotNull);
    expect(point!.lat, closeTo(33.5138, 1e-6));
    expect(point.lon, closeTo(36.2765, 1e-6));
  });

  test('trip map clamps zoom and formats coordinate labels', () {
    expect(rideTripMapClampZoom(2.0), closeTo(rideTripMapMinZoom, 1e-6));
    expect(rideTripMapClampZoom(25.0), closeTo(rideTripMapMaxZoom, 1e-6));
    expect(
      rideTripMapCoordinateLabel(
        const RideGeoPoint(lat: 33.513812, lon: 36.276512),
      ),
      '33.51381, 36.27651',
    );
  });

  test('trip map marker visuals resolve to stable image ids and sizes', () {
    expect(
      rideTripMapMarkerImageId(RideTripMapMarkerVisual.driverTaxiActive),
      'shamell-driver-taxi-active',
    );
    expect(
      rideTripMapMarkerImageId(RideTripMapMarkerVisual.riderPerson),
      'shamell-rider-person',
    );
    expect(
      rideTripMapMarkerIconSize(RideTripMapMarkerVisual.driverTaxiIdle),
      greaterThan(0.6),
    );
    expect(
      rideTripMapMarkerIconSize(RideTripMapMarkerVisual.destinationFlag),
      lessThan(
        rideTripMapMarkerIconSize(RideTripMapMarkerVisual.driverTaxiActive),
      ),
    );
  });
}
