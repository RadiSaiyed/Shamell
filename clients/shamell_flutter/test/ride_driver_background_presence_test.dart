import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_driver_page.dart';
import 'package:shamell_flutter/core/rides/ride_mobility_api.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';

void main() {
  group('rideDriverShouldSubmitLivePresence', () {
    final origin = RideGeoPoint(lat: 33.51380, lon: 36.27650);
    final movedFar = RideGeoPoint(lat: 33.51410, lon: 36.27650);
    final movedNear = RideGeoPoint(lat: 33.51381, lon: 36.27650);
    final now = DateTime.utc(2026, 4, 4, 12);

    test('sends the first live position immediately', () {
      expect(
        rideDriverShouldSubmitLivePresence(
          lastSubmittedAt: null,
          lastSubmittedPoint: null,
          now: now,
          nextPoint: origin,
        ),
        isTrue,
      );
    });

    test('suppresses tiny movement inside the live interval window', () {
      expect(
        rideDriverShouldSubmitLivePresence(
          lastSubmittedAt: now.subtract(const Duration(seconds: 3)),
          lastSubmittedPoint: origin,
          now: now,
          nextPoint: movedNear,
        ),
        isFalse,
      );
    });

    test('allows a send once the minimum interval elapsed', () {
      expect(
        rideDriverShouldSubmitLivePresence(
          lastSubmittedAt: now.subtract(const Duration(seconds: 8)),
          lastSubmittedPoint: origin,
          now: now,
          nextPoint: movedNear,
        ),
        isTrue,
      );
    });

    test('allows a send early when the driver moved meaningfully', () {
      expect(
        rideDriverShouldSubmitLivePresence(
          lastSubmittedAt: now.subtract(const Duration(seconds: 3)),
          lastSubmittedPoint: origin,
          now: now,
          nextPoint: movedFar,
        ),
        isTrue,
      );
    });
  });

  group('rideDriverPresenceNeedsPollingHeartbeat', () {
    final now = DateTime.utc(2026, 4, 5, 15, 54, 9);

    RideDriverPresence buildPresence({
      required bool online,
      String? lastSeenAtIso,
    }) {
      return RideDriverPresence(
        driverAccountId: 'driver-1',
        online: online,
        lastSeenAtIso: lastSeenAtIso,
        lastOnlineAtIso: lastSeenAtIso,
        location: null,
        driverName: 'Driver',
        carPlate: 'ABC123',
      );
    }

    test('requires a heartbeat when presence is missing', () {
      expect(
        rideDriverPresenceNeedsPollingHeartbeat(
          presence: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('requires a heartbeat when last seen is stale', () {
      expect(
        rideDriverPresenceNeedsPollingHeartbeat(
          presence: buildPresence(
            online: true,
            lastSeenAtIso: '2026-04-05T15:45:03.536402Z',
          ),
          now: now,
        ),
        isTrue,
      );
    });

    test('skips the polling heartbeat while presence is fresh', () {
      expect(
        rideDriverPresenceNeedsPollingHeartbeat(
          presence: buildPresence(
            online: true,
            lastSeenAtIso: '2026-04-05T15:53:54.000000Z',
          ),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
