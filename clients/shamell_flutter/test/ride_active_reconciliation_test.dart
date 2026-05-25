import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_page.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';

RideTrip _persistedTrip({
  required String lastUpdatedAtIso,
  RideTripStatus status = RideTripStatus.matching,
}) {
  return RideTrip(
    rideId: 'ride_1',
    pickup: 'Bab Touma',
    destination: 'Malki',
    rideClass: 'economy',
    driverName: 'Driver pending',
    carPlate: '--',
    etaMinutes: 5,
    fareEstimateCents: 2630,
    status: status,
    createdAtIso: '2026-04-04T18:00:00Z',
    lastUpdatedAtIso: lastUpdatedAtIso,
  );
}

void main() {
  group('rideShouldDiscardPersistedActiveTrip', () {
    test('drops stale persisted trip after authoritative empty server result',
        () {
      final shouldDiscard = rideShouldDiscardPersistedActiveTrip(
        authoritativeNoActiveFromServer: true,
        trackingTrip: null,
        persistedTrip: _persistedTrip(
          lastUpdatedAtIso: '2026-04-04T18:00:00Z',
        ),
        now: DateTime.parse('2026-04-04T18:20:01Z'),
      );

      expect(shouldDiscard, isTrue);
    });

    test('keeps persisted trip when tracking still confirms it', () {
      final trip = _persistedTrip(lastUpdatedAtIso: '2026-04-04T18:00:00Z');
      final shouldDiscard = rideShouldDiscardPersistedActiveTrip(
        authoritativeNoActiveFromServer: true,
        trackingTrip: trip,
        persistedTrip: trip,
        now: DateTime.parse('2026-04-04T18:20:01Z'),
      );

      expect(shouldDiscard, isFalse);
    });

    test('keeps persisted trip when server result was not authoritative', () {
      final shouldDiscard = rideShouldDiscardPersistedActiveTrip(
        authoritativeNoActiveFromServer: false,
        trackingTrip: null,
        persistedTrip: _persistedTrip(
          lastUpdatedAtIso: '2026-04-04T18:00:00Z',
        ),
        now: DateTime.parse('2026-04-04T18:20:01Z'),
      );

      expect(shouldDiscard, isFalse);
    });
  });
}
