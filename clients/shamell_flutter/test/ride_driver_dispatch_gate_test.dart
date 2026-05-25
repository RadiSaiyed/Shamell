import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_driver_page.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';

RideTrip _tripWithFare(int fareEstimateCents) {
  return RideTrip(
    rideId: 'ride_1',
    pickup: 'Bab Touma',
    destination: 'Malki',
    rideClass: 'standard',
    driverName: 'Prod Driver',
    carPlate: 'SH001',
    etaMinutes: 5,
    fareEstimateCents: fareEstimateCents,
    status: RideTripStatus.matching,
    createdAtIso: '2026-04-04T00:00:00Z',
    lastUpdatedAtIso: '2026-04-04T00:00:00Z',
  );
}

DriverLedgerSnapshot _ledger({
  required int earningsAvailableMinorUnits,
  required int heldReserveMinorUnits,
  int bonusesMinorUnits = 0,
}) {
  return DriverLedgerSnapshot(
    driverId: 'driver_1',
    earningsAvailableMinorUnits: earningsAvailableMinorUnits,
    heldReserveMinorUnits: heldReserveMinorUnits,
    debtMinorUnits: 0,
    payoutPendingMinorUnits: 0,
    bonusesMinorUnits: bonusesMinorUnits,
    cashCollectedMinorUnits: 0,
  );
}

RideDriverFinanceDashboard _finance({
  required int netAvailableMinorUnits,
  DriverLedgerSnapshot? ledger,
}) {
  return RideDriverFinanceDashboard(
    generatedAtIso: '2026-04-04T00:00:00Z',
    walletId: 'wallet_1',
    platformPayoutWalletId: 'wallet_fee',
    ledger: ledger ??
        _ledger(earningsAvailableMinorUnits: 0, heldReserveMinorUnits: 0),
    completedTodayCount: 0,
    completedTodayValueMinorUnits: 0,
    activeTripValueMinorUnits: 0,
    netAvailableMinorUnits: netAvailableMinorUnits,
    recommendedReserveMinorUnits: 0,
    recommendedPayoutMinorUnits: 0,
    pendingSettlementMinorUnits: 0,
    reserveCoverageBps: 0,
    payoutBlocked: false,
    alerts: const [],
    recentCompletedTrips: const [],
    recentReserveEvents: const [],
  );
}

void main() {
  group('rideDriverRequiredReserveMinorUnits', () {
    test('uses rounded-up 10 percent reserve', () {
      expect(rideDriverRequiredReserveMinorUnits(2000), 200);
      expect(rideDriverRequiredReserveMinorUnits(1999), 200);
      expect(rideDriverRequiredReserveMinorUnits(1), 1);
      expect(rideDriverRequiredReserveMinorUnits(0), 0);
    });
  });

  group('rideDriverHasEnoughReserveForTrip', () {
    test('blocks accept when finance dashboard net available is too low', () {
      expect(
        rideDriverHasEnoughReserveForTrip(
          trip: _tripWithFare(2000),
          financeDashboard: _finance(netAvailableMinorUnits: 199),
          ledger: null,
        ),
        isFalse,
      );
    });

    test('allows accept when available reserve covers the hold', () {
      expect(
        rideDriverHasEnoughReserveForTrip(
          trip: _tripWithFare(2000),
          financeDashboard: _finance(netAvailableMinorUnits: 200),
          ledger: null,
        ),
        isTrue,
      );
    });

    test('does not pre-block when finance data is unavailable', () {
      expect(
        rideDriverHasEnoughReserveForTrip(
          trip: _tripWithFare(2000),
          financeDashboard: null,
          ledger: null,
        ),
        isTrue,
      );
    });
  });
}
