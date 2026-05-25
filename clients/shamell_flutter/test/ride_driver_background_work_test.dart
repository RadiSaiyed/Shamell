import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_driver_background_service.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';

RideTrip _trip({
  required String rideId,
  required RideTripStatus status,
}) {
  return RideTrip(
    rideId: rideId,
    pickup: 'Bab Touma',
    destination: 'Malki',
    rideClass: 'standard',
    driverName: 'Prod Driver',
    carPlate: 'SH001',
    etaMinutes: 5,
    fareEstimateCents: 2000,
    status: status,
    createdAtIso: '2026-04-05T00:00:00Z',
    lastUpdatedAtIso: '2026-04-05T00:00:00Z',
  );
}

void main() {
  group('rideDriverBackgroundShouldSchedule', () {
    test('requires online state, secure base url, driver name, and car plate',
        () {
      expect(
        rideDriverBackgroundShouldSchedule(
          online: true,
          baseUrl: 'https://api.shamell.online',
          driverName: 'Prod Driver',
          carPlate: 'SH001',
        ),
        isTrue,
      );

      expect(
        rideDriverBackgroundShouldSchedule(
          online: false,
          baseUrl: 'https://api.shamell.online',
          driverName: 'Prod Driver',
          carPlate: 'SH001',
        ),
        isFalse,
      );

      expect(
        rideDriverBackgroundShouldSchedule(
          online: true,
          baseUrl: 'ftp://api.shamell.online',
          driverName: 'Prod Driver',
          carPlate: 'SH001',
        ),
        isFalse,
      );

      expect(
        rideDriverBackgroundShouldSchedule(
          online: true,
          baseUrl: 'https://api.shamell.online',
          driverName: '',
          carPlate: 'SH001',
        ),
        isFalse,
      );
    });
  });

  group('rideDriverBackgroundShouldNotifyQueueGrowth', () {
    test('notifies only when the queue count increases after a baseline exists',
        () {
      expect(
        rideDriverBackgroundShouldNotifyQueueGrowth(
          previousQueueCount: null,
          nextQueueCount: 1,
        ),
        isFalse,
      );
      expect(
        rideDriverBackgroundShouldNotifyQueueGrowth(
          previousQueueCount: 1,
          nextQueueCount: 1,
        ),
        isFalse,
      );
      expect(
        rideDriverBackgroundShouldNotifyQueueGrowth(
          previousQueueCount: 1,
          nextQueueCount: 2,
        ),
        isTrue,
      );
    });
  });

  group('rideDriverBackgroundShouldNotifyTripTransition', () {
    test('notifies only when the same active ride changes status', () {
      final assigned = _trip(
        rideId: 'ride_1',
        status: RideTripStatus.driverAssigned,
      );
      final arriving = assigned.copyWith(
        status: RideTripStatus.driverArriving,
      );
      final otherRide = _trip(
        rideId: 'ride_2',
        status: RideTripStatus.driverArriving,
      );

      expect(
        rideDriverBackgroundShouldNotifyTripTransition(
          previousRideId: null,
          previousStatus: RideTripStatus.driverAssigned,
          nextTrip: arriving,
        ),
        isFalse,
      );

      expect(
        rideDriverBackgroundShouldNotifyTripTransition(
          previousRideId: assigned.rideId,
          previousStatus: RideTripStatus.driverAssigned,
          nextTrip: assigned,
        ),
        isFalse,
      );

      expect(
        rideDriverBackgroundShouldNotifyTripTransition(
          previousRideId: assigned.rideId,
          previousStatus: RideTripStatus.driverAssigned,
          nextTrip: otherRide,
        ),
        isFalse,
      );

      expect(
        rideDriverBackgroundShouldNotifyTripTransition(
          previousRideId: assigned.rideId,
          previousStatus: RideTripStatus.driverAssigned,
          nextTrip: arriving,
        ),
        isTrue,
      );
    });
  });

  group('rideDriverBackgroundShouldKickForPushType', () {
    test('kicks only for driver ride push types', () {
      expect(
        rideDriverBackgroundShouldKickForPushType('ride_driver_dispatch'),
        isTrue,
      );
      expect(
        rideDriverBackgroundShouldKickForPushType('ride_driver_update'),
        isTrue,
      );
      expect(
        rideDriverBackgroundShouldKickForPushType('ride_rider_update'),
        isFalse,
      );
      expect(
        rideDriverBackgroundShouldKickForPushType('ride_operator_alert'),
        isFalse,
      );
      expect(
        rideDriverBackgroundShouldKickForPushType(''),
        isFalse,
      );
    });
  });
}
