import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_driver_page.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_page.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_mobility_api.dart';

RideTrip _trip(RideTripStatus status) {
  return RideTrip(
    rideId: 'ride-1',
    pickup: 'Bab Touma Damascus',
    destination: 'Malki Damascus',
    pickupLabel: 'Bab Touma Damascus',
    destinationLabel: 'Malki Damascus',
    pickupLat: 33.5138,
    pickupLon: 36.3138,
    destinationLat: 33.5152,
    destinationLon: 36.29637,
    rideClass: 'economy',
    driverName: 'Prod Driver',
    carPlate: 'SH001',
    etaMinutes: 5,
    fareEstimateCents: 230000,
    status: status,
    createdAtIso: '2026-04-04T14:00:00Z',
    lastUpdatedAtIso: '2026-04-04T14:00:05Z',
    assignedAtIso: '2026-04-04T14:00:05Z',
    arrivingAtIso: '2026-04-04T14:00:10Z',
    arrivedAtIso: '2026-04-04T14:01:00Z',
    startedAtIso: '2026-04-04T14:02:00Z',
    completedAtIso: null,
  );
}

RideLiveTrackingSnapshot _trackingSnapshot(RideTrip trip) {
  return RideLiveTrackingSnapshot(
    ride: trip,
    latestDriverLocation: RideTrackingEvent(
      eventId: 7,
      eventKind: 'driver_location',
      status: trip.status,
      actorAccountId:
          '677a2e41ad8218b1e39caf0a36292ac7b0dccedd76af983d363e405b95d67531',
      location: const RideGeoPoint(lat: 33.51405, lon: 36.3124),
      accuracyMeters: 8,
      speedKmh: 18,
      headingDegrees: 96,
      note: null,
      createdAtIso: '2026-04-04T14:03:00Z',
    ),
    timeline: <RideTrackingEvent>[
      RideTrackingEvent(
        eventId: 6,
        eventKind: 'status_changed',
        status: trip.status,
        actorAccountId:
            '677a2e41ad8218b1e39caf0a36292ac7b0dccedd76af983d363e405b95d67531',
        location: null,
        accuracyMeters: null,
        speedKmh: null,
        headingDegrees: null,
        note: null,
        createdAtIso: '2026-04-04T14:02:50Z',
      ),
    ],
  );
}

String? _fakeAgeLabel(String? iso, {required bool isArabic}) {
  if ((iso ?? '').isEmpty) return null;
  return isArabic ? 'الآن' : 'just now';
}

void main() {
  test('ride active trip semantics summary includes core rider fields', () {
    final trip = _trip(RideTripStatus.driverArriving);
    final summary = rideActiveTripSemanticsSummaryLabel(
      trip: trip,
      trackingSnapshot: _trackingSnapshot(trip),
      isArabic: false,
      trackingAgeLabel: _fakeAgeLabel,
    );

    expect(summary, isNotNull);
    expect(summary, contains('Current ride summary'));
    expect(summary, contains('Driver arriving'));
    expect(summary, contains('Prod Driver'));
    expect(summary, contains('S…01'));
    expect(summary, contains('Bab Touma Damascus -> Malki Damascus'));
    expect(summary, contains('Driver last update: just now'));
    expect(summary, contains('Approx. location 33.51, 36.31'));
    expect(summary, contains('Live tracking: 1 updates'));
  });

  test('driver active trip semantics summary includes route and tracking', () {
    final trip = _trip(RideTripStatus.tripStarted);
    final summary = rideDriverActiveTripSemanticsSummaryLabel(
      trip: trip,
      trackingQuote: RideTomTomQuote(
        pickup: const RideSearchPlace(
          displayName: 'Bab Touma Damascus',
          point: RideGeoPoint(lat: 33.5138, lon: 36.3138),
        ),
        destination: const RideSearchPlace(
          displayName: 'Malki Damascus',
          point: RideGeoPoint(lat: 33.5152, lon: 36.29637),
        ),
        route: const RideRouteQuote(
          distanceMeters: 4600,
          etaSeconds: 300,
          trafficDelaySeconds: 30,
          points: <RideGeoPoint>[],
        ),
      ),
      trackingSnapshot: _trackingSnapshot(trip),
      lastLocationPingAtIso: null,
      isArabic: false,
      trackingAgeLabel: _fakeAgeLabel,
    );

    expect(summary, isNotNull);
    expect(summary, contains('Active trip summary'));
    expect(summary, contains('Trip started'));
    expect(summary, contains('Navigation target destination'));
    expect(summary, contains('Trip route 4.6 km'));
    expect(summary, contains('Tracking last sent: just now'));
    expect(summary, contains('Approx. GPS 33.51, 36.31'));
  });
}
