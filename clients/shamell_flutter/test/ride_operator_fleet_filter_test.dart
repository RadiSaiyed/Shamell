import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_operator_console_page.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';

RideTrip _trip({
  String rideId = 'ride_1',
  required RideTripStatus status,
}) {
  return RideTrip(
    rideId: rideId,
    pickup: 'Bab Touma',
    destination: 'Malki',
    rideClass: 'economy',
    driverName: 'Prod Driver',
    carPlate: 'SH001',
    etaMinutes: 3,
    fareEstimateCents: 1250,
    status: status,
    createdAtIso: '2026-04-05T00:00:00Z',
    lastUpdatedAtIso: '2026-04-05T00:00:00Z',
  );
}

RideOperatorDriverRosterEntry _driver({
  required String lastSeenAtIso,
  RideCoordinatePoint? location,
  String? activeRideId,
}) {
  return RideOperatorDriverRosterEntry(
    driverAccountId: 'driver_1',
    availabilityStatus: RideDriverAvailabilityStatus.online,
    lastSeenAtIso: lastSeenAtIso,
    updatedAtIso: lastSeenAtIso,
    location: location,
    driverName: 'Prod Driver',
    carPlate: 'SH001',
    activeRideId: activeRideId,
    activeTripStatus:
        activeRideId == null ? null : RideTripStatus.driverAssigned,
    activePickup: activeRideId == null ? null : 'Bab Touma',
    activeDestination: activeRideId == null ? null : 'Malki',
  );
}

void main() {
  group('rideOperatorDriverIsStale', () {
    test('marks old heartbeat as stale', () {
      expect(
        rideOperatorDriverIsStale(
          _driver(
            lastSeenAtIso: '2026-04-04T18:00:00Z',
            location: const RideCoordinatePoint(lat: 33.5, lon: 36.3),
          ),
          now: DateTime.parse('2026-04-04T18:00:31Z'),
        ),
        isTrue,
      );
    });
  });

  group('rideOperatorDriverMatchesFleetFilter', () {
    test('matches no_gps only for online drivers without location', () {
      expect(
        rideOperatorDriverMatchesFleetFilter(
          driver: _driver(
            lastSeenAtIso: '2026-04-04T18:00:00Z',
            location: null,
          ),
          filterWireValue: 'no_gps',
          now: DateTime.parse('2026-04-04T18:00:10Z'),
        ),
        isTrue,
      );
    });

    test('matches on_trip only for online drivers with active ride', () {
      expect(
        rideOperatorDriverMatchesFleetFilter(
          driver: _driver(
            lastSeenAtIso: '2026-04-04T18:00:00Z',
            location: const RideCoordinatePoint(lat: 33.5, lon: 36.3),
            activeRideId: 'ride_1',
          ),
          filterWireValue: 'on_trip',
          now: DateTime.parse('2026-04-04T18:00:10Z'),
        ),
        isTrue,
      );
    });
  });

  group('rideOperatorShouldNotifyFocusTripTransition', () {
    test('notifies when the same ride changes status', () {
      expect(
        rideOperatorShouldNotifyFocusTripTransition(
          previousTrip: _trip(status: RideTripStatus.matching),
          nextTrip: _trip(status: RideTripStatus.driverAssigned),
        ),
        isTrue,
      );
    });

    test('does not notify for initial baseline', () {
      expect(
        rideOperatorShouldNotifyFocusTripTransition(
          previousTrip: null,
          nextTrip: _trip(status: RideTripStatus.matching),
        ),
        isFalse,
      );
    });

    test('does not notify when the focused ride changes entirely', () {
      expect(
        rideOperatorShouldNotifyFocusTripTransition(
          previousTrip: _trip(
            rideId: 'ride_1',
            status: RideTripStatus.matching,
          ),
          nextTrip: _trip(
            rideId: 'ride_2',
            status: RideTripStatus.driverAssigned,
          ),
        ),
        isFalse,
      );
    });
  });

  group('rideOperatorSensitiveRevealStillValid', () {
    test('returns false when no unlock is present', () {
      expect(rideOperatorSensitiveRevealStillValid(null), isFalse);
    });

    test('returns true only before the unlock window expires', () {
      final unlockedUntil = DateTime.parse('2026-04-05T10:02:00Z');

      expect(
        rideOperatorSensitiveRevealStillValid(
          unlockedUntil,
          now: DateTime.parse('2026-04-05T10:01:59Z'),
        ),
        isTrue,
      );
      expect(
        rideOperatorSensitiveRevealStillValid(
          unlockedUntil,
          now: DateTime.parse('2026-04-05T10:02:00Z'),
        ),
        isFalse,
      );
    });
  });

  group('rideOperatorPlatformRequiresSensitiveLocalAuth', () {
    test('requires local auth on mobile and Apple desktop surfaces', () {
      expect(
        rideOperatorPlatformRequiresSensitiveLocalAuth(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        rideOperatorPlatformRequiresSensitiveLocalAuth(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        rideOperatorPlatformRequiresSensitiveLocalAuth(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
    });

    test('skips local auth on web and unsupported desktop platforms', () {
      expect(
        rideOperatorPlatformRequiresSensitiveLocalAuth(isWeb: true),
        isFalse,
      );
      expect(
        rideOperatorPlatformRequiresSensitiveLocalAuth(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
      expect(
        rideOperatorPlatformRequiresSensitiveLocalAuth(
          isWeb: false,
          platform: TargetPlatform.linux,
        ),
        isFalse,
      );
    });
  });

  group('rideOperatorPrivacySafeTripTransitionBody', () {
    test('uses short ride id without route details', () {
      final body = rideOperatorPrivacySafeTripTransitionBody(
        nextTrip: _trip(
          rideId: 'L17XG2SBRMIEQTBPPRF7284UUM',
          status: RideTripStatus.driverAssigned,
        ),
        isArabic: false,
        statusLabel: 'Assigned',
      );

      expect(body, 'Ride L17XG2…: now Assigned.');
      expect(body, isNot(contains('Bab Touma')));
      expect(body, isNot(contains('Malki')));
    });
  });

  group('rideOperatorTripIdLabel', () {
    test('uses short ride id for operator-facing lightweight surfaces', () {
      expect(
        rideOperatorTripIdLabel(
          'L17XG2SBRMIEQTBPPRF7284UUM',
          isArabic: false,
        ),
        'Ride ID L17XG2…',
      );
    });
  });

  group('rideOperatorActiveRideLabel', () {
    test('uses short ride id without route details', () {
      expect(
        rideOperatorActiveRideLabel(
          'L17XG2SBRMIEQTBPPRF7284UUM',
          isArabic: false,
        ),
        'Active trip L17XG2…',
      );
    });
  });

  group('rideOperatorFindTripById', () {
    test('finds trips across active and dispatch lists', () {
      final board = RideOperatorLiveBoard(
        counts: const RideOperatorLiveCounts(
          openDispatches: 1,
          activeTrips: 1,
          enRouteTrips: 0,
          inProgressTrips: 0,
          paymentFailures: 0,
          onlineDrivers: 1,
        ),
        openDispatches: <RideTrip>[
          _trip(rideId: 'ride_dispatch', status: RideTripStatus.matching),
        ],
        activeTrips: <RideTrip>[
          _trip(rideId: 'ride_active', status: RideTripStatus.driverAssigned),
        ],
      );

      expect(
        rideOperatorFindTripById(board: board, rideId: 'ride_active')?.rideId,
        'ride_active',
      );
      expect(
        rideOperatorFindTripById(board: board, rideId: 'ride_dispatch')?.rideId,
        'ride_dispatch',
      );
      expect(
        rideOperatorFindTripById(board: board, rideId: 'ride_missing'),
        isNull,
      );
    });
  });
}
