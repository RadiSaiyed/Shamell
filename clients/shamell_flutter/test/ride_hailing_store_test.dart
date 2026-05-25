import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';

RideTrip _trip({
  required String rideId,
  required RideTripStatus status,
}) {
  return RideTrip(
    rideId: rideId,
    pickup: 'Downtown',
    destination: 'Airport',
    rideClass: 'economy',
    driverName: 'Ayman',
    carPlate: 'AB-1234',
    etaMinutes: 8,
    fareEstimateCents: 4200,
    status: status,
    createdAtIso: '2026-03-30T00:00:00Z',
    lastUpdatedAtIso: '2026-03-30T00:00:00Z',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('ride history and active trip stay isolated per base-url scope',
      () async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';

    final t1 = _trip(rideId: 'ride_1', status: RideTripStatus.driverAssigned);
    await saveRideHailingHistory(
      <RideTrip>[t1],
      baseUrlOverride: originOne,
    );
    await saveActiveRideHailingTrip(
      t1,
      baseUrlOverride: originOne,
    );

    expect(
      await loadRideHailingHistory(baseUrlOverride: originOne),
      hasLength(1),
    );
    expect(
      (await loadActiveRideHailingTrip(baseUrlOverride: originOne))?.rideId,
      'ride_1',
    );
    expect(
      await loadRideHailingHistory(baseUrlOverride: originTwo),
      isEmpty,
    );
    expect(
      await loadActiveRideHailingTrip(baseUrlOverride: originTwo),
      isNull,
    );
  });

  test('upsert keeps latest ride state and deduplicates ride id', () async {
    const origin = 'https://api.example.com';
    final assigned = _trip(
      rideId: 'ride_42',
      status: RideTripStatus.driverAssigned,
    );
    final arrived = assigned.copyWith(
      status: RideTripStatus.driverArriving,
      lastUpdatedAtIso: '2026-03-30T00:04:00Z',
      etaMinutes: 3,
    );

    await upsertRideHailingHistoryTrip(
      assigned,
      baseUrlOverride: origin,
    );
    await upsertRideHailingHistoryTrip(
      _trip(rideId: 'ride_43', status: RideTripStatus.tripCompleted),
      baseUrlOverride: origin,
    );
    await upsertRideHailingHistoryTrip(
      arrived,
      baseUrlOverride: origin,
    );

    final history = await loadRideHailingHistory(baseUrlOverride: origin);
    expect(history, hasLength(2));
    expect(history.first.rideId, 'ride_42');
    expect(history.first.status, RideTripStatus.driverArriving);
  });

  test('malformed stored payload fails closed', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'base_url': 'https://api.example.com',
      'ride_hailing.history.v1.https://api.example.com': '{bad-json',
      'ride_hailing.active.v1.https://api.example.com': 'not-json',
    });

    expect(
      await loadRideHailingHistory(),
      isEmpty,
    );
    expect(
      await loadActiveRideHailingTrip(),
      isNull,
    );
  });

  test('ride status parser keeps backward compatibility for legacy wires', () {
    expect(rideTripStatusFromWire('searching'), RideTripStatus.matching);
    expect(
        rideTripStatusFromWire('in_progress'), RideTripStatus.tripInProgress);
    expect(rideTripStatusFromWire('completed'), RideTripStatus.tripCompleted);
    expect(rideTripStatusFromWire('cancelled'), RideTripStatus.canceled);
  });

  test('ride state machine allows only valid lifecycle transitions', () {
    expect(
      rideTripStatusCanTransition(
        from: RideTripStatus.quoteShown,
        to: RideTripStatus.rideRequested,
      ),
      isTrue,
    );
    expect(
      rideTripStatusCanTransition(
        from: RideTripStatus.rideRequested,
        to: RideTripStatus.driverAssigned,
      ),
      isFalse,
    );
    expect(
      rideTripStatusCanTransition(
        from: RideTripStatus.tripInProgress,
        to: RideTripStatus.paymentFailed,
      ),
      isTrue,
    );
    expect(
      rideTripStatusCanTransition(
        from: RideTripStatus.tripCompleted,
        to: RideTripStatus.driverAssigned,
      ),
      isFalse,
    );
  });

  test('rider cancellation window excludes driver and payment-only phases', () {
    expect(rideTripStatusRiderCanCancel(RideTripStatus.rideRequested), isTrue);
    expect(rideTripStatusRiderCanCancel(RideTripStatus.matching), isTrue);
    expect(rideTripStatusRiderCanCancel(RideTripStatus.driverAssigned), isTrue);
    expect(rideTripStatusRiderCanCancel(RideTripStatus.tripStarted), isTrue);
    expect(
        rideTripStatusRiderCanCancel(RideTripStatus.tripInProgress), isFalse);
    expect(rideTripStatusRiderCanCancel(RideTripStatus.paymentFailed), isFalse);
    expect(rideTripStatusRiderCanCancel(RideTripStatus.tripCompleted), isFalse);
  });

  test('RideTrip preserves extended trip metadata through json', () {
    final trip = RideTrip(
      rideId: 'ride_meta_1',
      offerId: 'offer_123',
      pickup: 'Old Town',
      destination: 'Bab Touma',
      pickupLabel: 'Old Town, Damascus',
      destinationLabel: 'Bab Touma, Damascus',
      pickupLat: 33.5138,
      pickupLon: 36.2765,
      destinationLat: 33.5149,
      destinationLon: 36.3015,
      rideClass: 'economy',
      driverName: 'Maya',
      carPlate: 'BA-1586',
      etaMinutes: 6,
      fareEstimateCents: 1880,
      status: RideTripStatus.driverAssigned,
      cancelReasonCode: 'rider_cancelled',
      createdAtIso: '2026-04-04T08:00:00Z',
      lastUpdatedAtIso: '2026-04-04T08:05:00Z',
      assignedAtIso: '2026-04-04T08:03:00Z',
      arrivingAtIso: '2026-04-04T08:04:00Z',
      arrivedAtIso: '2026-04-04T08:05:00Z',
      startedAtIso: '2026-04-04T08:06:00Z',
      completedAtIso: '2026-04-04T08:12:00Z',
    );

    final parsed = RideTrip.fromJson(trip.toJson());
    expect(parsed, isNotNull);
    expect(parsed!.offerId, 'offer_123');
    expect(parsed.pickupLabel, 'Old Town, Damascus');
    expect(parsed.destinationLabel, 'Bab Touma, Damascus');
    expect(parsed.pickupLat, 33.5138);
    expect(parsed.destinationLon, 36.3015);
    expect(parsed.cancelReasonCode, 'rider_cancelled');
    expect(parsed.assignedAtIso, '2026-04-04T08:03:00Z');
    expect(parsed.completedAtIso, '2026-04-04T08:12:00Z');
  });
}
