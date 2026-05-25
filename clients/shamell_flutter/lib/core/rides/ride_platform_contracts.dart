import 'dart:convert';

import '../account_privilege_store.dart';
import 'ride_hailing_store.dart';

const _rideCurrencySyp = 'SYP';

bool _isRideCurrency(String currency) => currency == _rideCurrencySyp;

enum RideServiceClass {
  economy,
  xl,
  premium,
  delivery,
  corporate,
}

String rideServiceClassWireValue(RideServiceClass value) {
  switch (value) {
    case RideServiceClass.economy:
      return 'economy';
    case RideServiceClass.xl:
      return 'xl';
    case RideServiceClass.premium:
      return 'premium';
    case RideServiceClass.delivery:
      return 'delivery';
    case RideServiceClass.corporate:
      return 'corporate';
  }
}

enum RideWalletBucketType {
  cashBalance,
  promoCredit,
  refundCredit,
  corporateCredit,
}

String rideWalletBucketTypeWireValue(RideWalletBucketType value) {
  switch (value) {
    case RideWalletBucketType.cashBalance:
      return 'cash_balance';
    case RideWalletBucketType.promoCredit:
      return 'promo_credit';
    case RideWalletBucketType.refundCredit:
      return 'refund_credit';
    case RideWalletBucketType.corporateCredit:
      return 'corporate_credit';
  }
}

RideWalletBucketType? rideWalletBucketTypeFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'cash_balance':
      return RideWalletBucketType.cashBalance;
    case 'promo_credit':
      return RideWalletBucketType.promoCredit;
    case 'refund_credit':
      return RideWalletBucketType.refundCredit;
    case 'corporate_credit':
      return RideWalletBucketType.corporateCredit;
    default:
      return null;
  }
}

class RiderWalletBucket {
  final RideWalletBucketType type;
  final String currency;
  final int balanceMinorUnits;
  final String? expiresAtIso;

  const RiderWalletBucket({
    required this.type,
    required this.currency,
    required this.balanceMinorUnits,
    this.expiresAtIso,
  });

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': rideWalletBucketTypeWireValue(type),
      'currency': currency,
      'balance_minor_units': balanceMinorUnits,
      if ((expiresAtIso ?? '').trim().isNotEmpty) 'expires_at': expiresAtIso,
    };
  }

  static RiderWalletBucket? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type =
        rideWalletBucketTypeFromWire((raw['type'] ?? '').toString().trim());
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final balance = raw['balance_minor_units'];
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    if (type == null ||
        !_isRideCurrency(currency) ||
        balance is! int ||
        balance < 0) {
      return null;
    }
    return RiderWalletBucket(
      type: type,
      currency: currency,
      balanceMinorUnits: balance,
      expiresAtIso: expiresAtIso.isEmpty ? null : expiresAtIso,
    );
  }
}

class RiderWalletSnapshot {
  final String riderId;
  final List<RiderWalletBucket> buckets;

  const RiderWalletSnapshot({
    required this.riderId,
    required this.buckets,
  });

  bool hasStrictBucketSegregation() {
    final seen = <RideWalletBucketType>{};
    for (final bucket in buckets) {
      if (!seen.add(bucket.type)) return false;
    }
    return true;
  }

  int bucketBalance(RideWalletBucketType type) {
    for (final bucket in buckets) {
      if (bucket.type == type) return bucket.balanceMinorUnits;
    }
    return 0;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rider_id': riderId,
      'buckets':
          buckets.map((bucket) => bucket.toJson()).toList(growable: false),
    };
  }

  static RiderWalletSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final riderId = (raw['rider_id'] ?? '').toString().trim();
    final bucketsRaw = raw['buckets'];
    if (riderId.isEmpty || bucketsRaw is! List) return null;
    final buckets = bucketsRaw
        .map(RiderWalletBucket.fromJson)
        .whereType<RiderWalletBucket>()
        .toList();
    if (buckets.isEmpty) return null;
    final snapshot = RiderWalletSnapshot(
      riderId: riderId,
      buckets: buckets,
    );
    if (!snapshot.hasStrictBucketSegregation()) return null;
    return snapshot;
  }
}

class RidePricingPreview {
  final String rideClass;
  final String currency;
  final int distanceMeters;
  final int etaSeconds;
  final int trafficDelaySeconds;
  final int baseFareMinorUnits;
  final int distanceComponentMinorUnits;
  final int timeComponentMinorUnits;
  final int trafficSurchargeMinorUnits;
  final int bookingFeeMinorUnits;
  final int minimumFareLiftMinorUnits;
  final int totalFareMinorUnits;
  final int suggestedDriverPayoutMinorUnits;
  final int platformMarginMinorUnits;

  const RidePricingPreview({
    required this.rideClass,
    required this.currency,
    required this.distanceMeters,
    required this.etaSeconds,
    required this.trafficDelaySeconds,
    required this.baseFareMinorUnits,
    required this.distanceComponentMinorUnits,
    required this.timeComponentMinorUnits,
    required this.trafficSurchargeMinorUnits,
    required this.bookingFeeMinorUnits,
    required this.minimumFareLiftMinorUnits,
    required this.totalFareMinorUnits,
    required this.suggestedDriverPayoutMinorUnits,
    required this.platformMarginMinorUnits,
  });

  static RidePricingPreview? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final rideClass = (raw['ride_class'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final distanceMeters = raw['distance_m'];
    final etaSeconds = raw['eta_s'];
    final trafficDelaySeconds = raw['traffic_delay_s'];
    final breakdown = raw['breakdown'];
    final totalFareMinorUnits = raw['total_fare_minor_units'];
    final suggestedDriverPayoutMinorUnits =
        raw['suggested_driver_payout_minor_units'];
    final platformMarginMinorUnits = raw['platform_margin_minor_units'];
    if (rideClass.isEmpty ||
        !_isRideCurrency(currency) ||
        distanceMeters is! int ||
        etaSeconds is! int ||
        trafficDelaySeconds is! int ||
        breakdown is! Map ||
        totalFareMinorUnits is! int ||
        suggestedDriverPayoutMinorUnits is! int ||
        platformMarginMinorUnits is! int) {
      return null;
    }
    final baseFareMinorUnits = breakdown['base_fare_minor_units'];
    final distanceComponentMinorUnits =
        breakdown['distance_component_minor_units'];
    final timeComponentMinorUnits = breakdown['time_component_minor_units'];
    final trafficSurchargeMinorUnits =
        breakdown['traffic_surcharge_minor_units'];
    final bookingFeeMinorUnits = breakdown['booking_fee_minor_units'];
    final minimumFareLiftMinorUnits =
        breakdown['minimum_fare_lift_minor_units'];
    if (baseFareMinorUnits is! int ||
        distanceComponentMinorUnits is! int ||
        timeComponentMinorUnits is! int ||
        trafficSurchargeMinorUnits is! int ||
        bookingFeeMinorUnits is! int ||
        minimumFareLiftMinorUnits is! int) {
      return null;
    }
    return RidePricingPreview(
      rideClass: rideClass,
      currency: currency,
      distanceMeters: distanceMeters,
      etaSeconds: etaSeconds,
      trafficDelaySeconds: trafficDelaySeconds,
      baseFareMinorUnits: baseFareMinorUnits,
      distanceComponentMinorUnits: distanceComponentMinorUnits,
      timeComponentMinorUnits: timeComponentMinorUnits,
      trafficSurchargeMinorUnits: trafficSurchargeMinorUnits,
      bookingFeeMinorUnits: bookingFeeMinorUnits,
      minimumFareLiftMinorUnits: minimumFareLiftMinorUnits,
      totalFareMinorUnits: totalFareMinorUnits,
      suggestedDriverPayoutMinorUnits: suggestedDriverPayoutMinorUnits,
      platformMarginMinorUnits: platformMarginMinorUnits,
    );
  }
}

class RidePricingPolicy {
  final String rideClass;
  final int baseFareMinorUnits;
  final int perKmMinorUnits;
  final int perMinuteMinorUnits;
  final int trafficDelayPerMinuteMinorUnits;
  final int bookingFeeMinorUnits;
  final int minimumFareMinorUnits;
  final int driverShareBps;
  final String updatedAtIso;
  final String? updatedByAccountId;

  const RidePricingPolicy({
    required this.rideClass,
    required this.baseFareMinorUnits,
    required this.perKmMinorUnits,
    required this.perMinuteMinorUnits,
    required this.trafficDelayPerMinuteMinorUnits,
    required this.bookingFeeMinorUnits,
    required this.minimumFareMinorUnits,
    required this.driverShareBps,
    required this.updatedAtIso,
    required this.updatedByAccountId,
  });

  static RidePricingPolicy? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final rideClass = (raw['ride_class'] ?? '').toString().trim();
    final baseFareMinorUnits = raw['base_fare_minor_units'];
    final perKmMinorUnits = raw['per_km_minor_units'];
    final perMinuteMinorUnits = raw['per_minute_minor_units'];
    final trafficDelayPerMinuteMinorUnits =
        raw['traffic_delay_per_minute_minor_units'];
    final bookingFeeMinorUnits = raw['booking_fee_minor_units'];
    final minimumFareMinorUnits = raw['minimum_fare_minor_units'];
    final driverShareBps = raw['driver_share_bps'];
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    final updatedByAccountId =
        (raw['updated_by_account_id'] ?? '').toString().trim();
    if (rideClass.isEmpty ||
        baseFareMinorUnits is! int ||
        perKmMinorUnits is! int ||
        perMinuteMinorUnits is! int ||
        trafficDelayPerMinuteMinorUnits is! int ||
        bookingFeeMinorUnits is! int ||
        minimumFareMinorUnits is! int ||
        driverShareBps is! int ||
        updatedAtIso.isEmpty) {
      return null;
    }
    if (baseFareMinorUnits <= 0 ||
        perKmMinorUnits < 0 ||
        perMinuteMinorUnits < 0 ||
        trafficDelayPerMinuteMinorUnits < 0 ||
        bookingFeeMinorUnits < 0 ||
        minimumFareMinorUnits <= 0 ||
        driverShareBps < 1000 ||
        driverShareBps > 9900) {
      return null;
    }
    return RidePricingPolicy(
      rideClass: rideClass,
      baseFareMinorUnits: baseFareMinorUnits,
      perKmMinorUnits: perKmMinorUnits,
      perMinuteMinorUnits: perMinuteMinorUnits,
      trafficDelayPerMinuteMinorUnits: trafficDelayPerMinuteMinorUnits,
      bookingFeeMinorUnits: bookingFeeMinorUnits,
      minimumFareMinorUnits: minimumFareMinorUnits,
      driverShareBps: driverShareBps,
      updatedAtIso: updatedAtIso,
      updatedByAccountId:
          updatedByAccountId.isEmpty ? null : updatedByAccountId,
    );
  }
}

class RideOperatorPricingPolicyDashboard {
  final String generatedAtIso;
  final List<RidePricingPolicy> policies;

  const RideOperatorPricingPolicyDashboard({
    required this.generatedAtIso,
    required this.policies,
  });

  static RideOperatorPricingPolicyDashboard? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final policiesRaw = raw['policies'];
    if (generatedAtIso.isEmpty || policiesRaw is! List) {
      return null;
    }
    return RideOperatorPricingPolicyDashboard(
      generatedAtIso: generatedAtIso,
      policies: policiesRaw
          .map(RidePricingPolicy.fromJson)
          .whereType<RidePricingPolicy>()
          .toList(growable: false),
    );
  }
}

class DriverLedgerSnapshot {
  final String driverId;
  final int earningsAvailableMinorUnits;
  final int heldReserveMinorUnits;
  final int debtMinorUnits;
  final int payoutPendingMinorUnits;
  final int bonusesMinorUnits;
  final int cashCollectedMinorUnits;

  const DriverLedgerSnapshot({
    required this.driverId,
    required this.earningsAvailableMinorUnits,
    required this.heldReserveMinorUnits,
    required this.debtMinorUnits,
    required this.payoutPendingMinorUnits,
    required this.bonusesMinorUnits,
    required this.cashCollectedMinorUnits,
  });

  int get netAvailableForPayoutMinorUnits {
    return earningsAvailableMinorUnits +
        bonusesMinorUnits -
        heldReserveMinorUnits;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'driver_id': driverId,
      'earnings_available_minor_units': earningsAvailableMinorUnits,
      'held_reserve_minor_units': heldReserveMinorUnits,
      'debt_minor_units': debtMinorUnits,
      'payout_pending_minor_units': payoutPendingMinorUnits,
      'bonuses_minor_units': bonusesMinorUnits,
      'cash_collected_minor_units': cashCollectedMinorUnits,
    };
  }

  static DriverLedgerSnapshot? fromJson(
    Object? raw, {
    String? fallbackDriverId,
  }) {
    if (raw is! Map) return null;
    final driverId =
        ((raw['driver_id'] ?? fallbackDriverId) ?? '').toString().trim();
    final earnings = raw['earnings_available_minor_units'] ??
        raw['earnings_available_cents'];
    final reserve =
        raw['held_reserve_minor_units'] ?? raw['held_reserve_cents'];
    final debt = raw['debt_minor_units'] ?? raw['debt_cents'];
    final payoutPending =
        raw['payout_pending_minor_units'] ?? raw['payout_pending_cents'];
    final bonuses = raw['bonuses_minor_units'] ?? raw['bonuses_cents'];
    final cashCollected =
        raw['cash_collected_minor_units'] ?? raw['cash_collected_cents'];
    if (driverId.isEmpty ||
        earnings is! int ||
        reserve is! int ||
        debt is! int ||
        payoutPending is! int ||
        bonuses is! int ||
        cashCollected is! int) {
      return null;
    }
    if (earnings < 0 ||
        reserve < 0 ||
        debt < 0 ||
        payoutPending < 0 ||
        bonuses < 0 ||
        cashCollected < 0) {
      return null;
    }
    return DriverLedgerSnapshot(
      driverId: driverId,
      earningsAvailableMinorUnits: earnings,
      heldReserveMinorUnits: reserve,
      debtMinorUnits: debt,
      payoutPendingMinorUnits: payoutPending,
      bonusesMinorUnits: bonuses,
      cashCollectedMinorUnits: cashCollected,
    );
  }
}

class RideDriverReserveEvent {
  final String rideId;
  final String? walletId;
  final int amountMinorUnits;
  final String status;
  final String? createdAtIso;
  final String? updatedAtIso;
  final String? reservedAtIso;
  final String? releasedAtIso;
  final String? settledAtIso;

  const RideDriverReserveEvent({
    required this.rideId,
    required this.walletId,
    required this.amountMinorUnits,
    required this.status,
    required this.createdAtIso,
    required this.updatedAtIso,
    required this.reservedAtIso,
    required this.releasedAtIso,
    required this.settledAtIso,
  });

  static RideDriverReserveEvent? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final rideId = (raw['ride_id'] ?? '').toString().trim();
    final walletId = (raw['wallet_id'] ?? '').toString().trim();
    final amountMinorUnits = raw['amount_minor_units'] ?? raw['amount_cents'];
    final status = (raw['status'] ?? '').toString().trim().toLowerCase();
    if (rideId.isEmpty ||
        amountMinorUnits is! int ||
        amountMinorUnits <= 0 ||
        !const <String>{'reserved', 'released', 'settled'}.contains(status)) {
      return null;
    }
    String? readIso(String key) {
      final value = (raw[key] ?? '').toString().trim();
      return value.isEmpty ? null : value;
    }

    return RideDriverReserveEvent(
      rideId: rideId,
      walletId: walletId.isEmpty ? null : walletId,
      amountMinorUnits: amountMinorUnits,
      status: status,
      createdAtIso: readIso('created_at'),
      updatedAtIso: readIso('updated_at'),
      reservedAtIso: readIso('reserved_at'),
      releasedAtIso: readIso('released_at'),
      settledAtIso: readIso('settled_at'),
    );
  }
}

class RideCoordinatePoint {
  final double lat;
  final double lon;

  const RideCoordinatePoint({
    required this.lat,
    required this.lon,
  });

  static RideCoordinatePoint? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final lat = raw['lat'];
    final lon = raw['lon'];
    if (lat is! num || lon is! num) {
      return null;
    }
    return RideCoordinatePoint(
      lat: lat.toDouble(),
      lon: lon.toDouble(),
    );
  }
}

class RideDriverPresence {
  final String driverAccountId;
  final bool online;
  final String? lastSeenAtIso;
  final String? lastOnlineAtIso;
  final RideCoordinatePoint? location;
  final String? driverName;
  final String? carPlate;

  const RideDriverPresence({
    required this.driverAccountId,
    required this.online,
    required this.lastSeenAtIso,
    required this.lastOnlineAtIso,
    required this.location,
    required this.driverName,
    required this.carPlate,
  });

  static RideDriverPresence? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final driverAccountId = (raw['driver_account_id'] ?? '').toString().trim();
    final online = raw['online'];
    final lastSeenAtIso = (raw['last_seen_at'] ?? '').toString().trim();
    final lastOnlineAtIso = (raw['last_online_at'] ?? '').toString().trim();
    final driverName = (raw['driver_name'] ?? '').toString().trim();
    final carPlate = (raw['car_plate'] ?? '').toString().trim();
    if (driverAccountId.isEmpty || online is! bool) {
      return null;
    }
    return RideDriverPresence(
      driverAccountId: driverAccountId,
      online: online,
      lastSeenAtIso: lastSeenAtIso.isEmpty ? null : lastSeenAtIso,
      lastOnlineAtIso: lastOnlineAtIso.isEmpty ? null : lastOnlineAtIso,
      location: RideCoordinatePoint.fromJson(raw['location']),
      driverName: driverName.isEmpty ? null : driverName,
      carPlate: carPlate.isEmpty ? null : carPlate,
    );
  }
}

class RideDriverFinanceDashboard {
  final String generatedAtIso;
  final String walletId;
  final String? platformPayoutWalletId;
  final DriverLedgerSnapshot ledger;
  final int completedTodayCount;
  final int completedTodayValueMinorUnits;
  final int activeTripValueMinorUnits;
  final int netAvailableMinorUnits;
  final int recommendedReserveMinorUnits;
  final int recommendedPayoutMinorUnits;
  final int pendingSettlementMinorUnits;
  final int reserveCoverageBps;
  final bool payoutBlocked;
  final List<RideOperatorAlert> alerts;
  final List<RideTrip> recentCompletedTrips;
  final List<RideDriverReserveEvent> recentReserveEvents;

  const RideDriverFinanceDashboard({
    required this.generatedAtIso,
    required this.walletId,
    required this.platformPayoutWalletId,
    required this.ledger,
    required this.completedTodayCount,
    required this.completedTodayValueMinorUnits,
    required this.activeTripValueMinorUnits,
    required this.netAvailableMinorUnits,
    required this.recommendedReserveMinorUnits,
    required this.recommendedPayoutMinorUnits,
    required this.pendingSettlementMinorUnits,
    required this.reserveCoverageBps,
    required this.payoutBlocked,
    required this.alerts,
    required this.recentCompletedTrips,
    required this.recentReserveEvents,
  });

  static RideDriverFinanceDashboard? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final walletId = (raw['wallet_id'] ?? '').toString().trim();
    final platformPayoutWalletId =
        (raw['platform_payout_wallet_id'] ?? '').toString().trim();
    final ledger = DriverLedgerSnapshot.fromJson(raw['ledger']);
    final completedTodayCount = raw['completed_today_count'];
    final completedTodayValueMinorUnits =
        raw['completed_today_value_minor_units'];
    final activeTripValueMinorUnits = raw['active_trip_value_minor_units'];
    final netAvailableMinorUnits = raw['net_available_minor_units'];
    final recommendedReserveMinorUnits = raw['recommended_reserve_minor_units'];
    final recommendedPayoutMinorUnits = raw['recommended_payout_minor_units'];
    final pendingSettlementMinorUnits = raw['pending_settlement_minor_units'];
    final reserveCoverageBps = raw['reserve_coverage_bps'];
    final payoutBlocked = raw['payout_blocked'];
    final alertsRaw = raw['alerts'];
    final recentCompletedTripsRaw = raw['recent_completed_trips'];
    final recentReserveEventsRaw = raw['recent_reserve_events'];
    if (generatedAtIso.isEmpty ||
        walletId.isEmpty ||
        ledger == null ||
        completedTodayCount is! int ||
        completedTodayValueMinorUnits is! int ||
        activeTripValueMinorUnits is! int ||
        netAvailableMinorUnits is! int ||
        recommendedReserveMinorUnits is! int ||
        recommendedPayoutMinorUnits is! int ||
        pendingSettlementMinorUnits is! int ||
        reserveCoverageBps is! int ||
        payoutBlocked is! bool ||
        alertsRaw is! List ||
        recentCompletedTripsRaw is! List) {
      return null;
    }
    if (completedTodayCount < 0 ||
        completedTodayValueMinorUnits < 0 ||
        activeTripValueMinorUnits < 0 ||
        netAvailableMinorUnits < 0 ||
        recommendedReserveMinorUnits < 0 ||
        recommendedPayoutMinorUnits < 0 ||
        pendingSettlementMinorUnits < 0 ||
        reserveCoverageBps < 0) {
      return null;
    }
    return RideDriverFinanceDashboard(
      generatedAtIso: generatedAtIso,
      walletId: walletId,
      platformPayoutWalletId:
          platformPayoutWalletId.isEmpty ? null : platformPayoutWalletId,
      ledger: ledger,
      completedTodayCount: completedTodayCount,
      completedTodayValueMinorUnits: completedTodayValueMinorUnits,
      activeTripValueMinorUnits: activeTripValueMinorUnits,
      netAvailableMinorUnits: netAvailableMinorUnits,
      recommendedReserveMinorUnits: recommendedReserveMinorUnits,
      recommendedPayoutMinorUnits: recommendedPayoutMinorUnits,
      pendingSettlementMinorUnits: pendingSettlementMinorUnits,
      reserveCoverageBps: reserveCoverageBps,
      payoutBlocked: payoutBlocked,
      alerts: alertsRaw
          .map(RideOperatorAlert.fromJson)
          .whereType<RideOperatorAlert>()
          .toList(growable: false),
      recentCompletedTrips: recentCompletedTripsRaw
          .map(RideTrip.fromJson)
          .whereType<RideTrip>()
          .toList(growable: false),
      recentReserveEvents: recentReserveEventsRaw is! List
          ? const <RideDriverReserveEvent>[]
          : recentReserveEventsRaw
              .map(RideDriverReserveEvent.fromJson)
              .whereType<RideDriverReserveEvent>()
              .toList(growable: false),
    );
  }
}

class RideDriverShiftSummary {
  final String generatedAtIso;
  final bool online;
  final String? lastSeenAtIso;
  final String? lastOnlineAtIso;
  final int currentOnlineDurationSeconds;
  final int openDispatchesVisible;
  final int activeTripCount;
  final int completedTodayCount;
  final int completedTodayValueMinorUnits;
  final int paymentFailedCount;
  final int avgCompletedEtaSeconds;
  final String? lastCompletedAtIso;
  final List<RideOperatorAlert> alerts;

  const RideDriverShiftSummary({
    required this.generatedAtIso,
    required this.online,
    required this.lastSeenAtIso,
    required this.lastOnlineAtIso,
    required this.currentOnlineDurationSeconds,
    required this.openDispatchesVisible,
    required this.activeTripCount,
    required this.completedTodayCount,
    required this.completedTodayValueMinorUnits,
    required this.paymentFailedCount,
    required this.avgCompletedEtaSeconds,
    required this.lastCompletedAtIso,
    required this.alerts,
  });

  static RideDriverShiftSummary? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final online = raw['online'];
    final currentOnlineDurationSeconds = raw['current_online_duration_seconds'];
    final openDispatchesVisible = raw['open_dispatches_visible'];
    final activeTripCount = raw['active_trip_count'];
    final completedTodayCount = raw['completed_today_count'];
    final completedTodayValueMinorUnits =
        raw['completed_today_value_minor_units'];
    final paymentFailedCount = raw['payment_failed_count'];
    final avgCompletedEtaSeconds = raw['avg_completed_eta_seconds'];
    final alertsRaw = raw['alerts'];
    if (generatedAtIso.isEmpty ||
        online is! bool ||
        currentOnlineDurationSeconds is! int ||
        openDispatchesVisible is! int ||
        activeTripCount is! int ||
        completedTodayCount is! int ||
        completedTodayValueMinorUnits is! int ||
        paymentFailedCount is! int ||
        avgCompletedEtaSeconds is! int ||
        alertsRaw is! List) {
      return null;
    }
    if (currentOnlineDurationSeconds < 0 ||
        openDispatchesVisible < 0 ||
        activeTripCount < 0 ||
        completedTodayCount < 0 ||
        completedTodayValueMinorUnits < 0 ||
        paymentFailedCount < 0 ||
        avgCompletedEtaSeconds < 0) {
      return null;
    }
    final lastSeenAtIso = (raw['last_seen_at'] ?? '').toString().trim();
    final lastOnlineAtIso = (raw['last_online_at'] ?? '').toString().trim();
    final lastCompletedAtIso =
        (raw['last_completed_at'] ?? '').toString().trim();
    return RideDriverShiftSummary(
      generatedAtIso: generatedAtIso,
      online: online,
      lastSeenAtIso: lastSeenAtIso.isEmpty ? null : lastSeenAtIso,
      lastOnlineAtIso: lastOnlineAtIso.isEmpty ? null : lastOnlineAtIso,
      currentOnlineDurationSeconds: currentOnlineDurationSeconds,
      openDispatchesVisible: openDispatchesVisible,
      activeTripCount: activeTripCount,
      completedTodayCount: completedTodayCount,
      completedTodayValueMinorUnits: completedTodayValueMinorUnits,
      paymentFailedCount: paymentFailedCount,
      avgCompletedEtaSeconds: avgCompletedEtaSeconds,
      lastCompletedAtIso:
          lastCompletedAtIso.isEmpty ? null : lastCompletedAtIso,
      alerts: alertsRaw
          .map(RideOperatorAlert.fromJson)
          .whereType<RideOperatorAlert>()
          .toList(growable: false),
    );
  }
}

enum RidePayoutRequestStatus {
  pending,
  accepted,
  canceled,
  expired,
}

RidePayoutRequestStatus? ridePayoutRequestStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'pending':
      return RidePayoutRequestStatus.pending;
    case 'accepted':
      return RidePayoutRequestStatus.accepted;
    case 'canceled':
      return RidePayoutRequestStatus.canceled;
    case 'expired':
      return RidePayoutRequestStatus.expired;
    default:
      return null;
  }
}

class RidePayoutRequest {
  final String? requestId;
  final String? fromWalletId;
  final String? toWalletId;
  final int amountMinorUnits;
  final String currency;
  final String? message;
  final RidePayoutRequestStatus status;
  final String createdAtIso;
  final int ageSeconds;

  const RidePayoutRequest({
    required this.requestId,
    required this.fromWalletId,
    required this.toWalletId,
    required this.amountMinorUnits,
    required this.currency,
    required this.message,
    required this.status,
    required this.createdAtIso,
    required this.ageSeconds,
  });

  bool get isPending => status == RidePayoutRequestStatus.pending;

  static RidePayoutRequest? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final requestId =
        ((raw['request_id'] ?? raw['id']) ?? '').toString().trim();
    final fromWalletId = (raw['from_wallet_id'] ?? '').toString().trim();
    final toWalletId = (raw['to_wallet_id'] ?? '').toString().trim();
    final amountMinorUnits = raw['amount_minor_units'] ?? raw['amount_cents'];
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final messageRaw = (raw['message'] ?? '').toString().trim();
    final status =
        ridePayoutRequestStatusFromWire((raw['status'] ?? '').toString());
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final ageSecondsRaw = raw['age_seconds'];
    final ageSeconds = ageSecondsRaw is int ? ageSecondsRaw : 0;
    if (amountMinorUnits is! int ||
        amountMinorUnits <= 0 ||
        !_isRideCurrency(currency) ||
        status == null ||
        createdAtIso.isEmpty ||
        ageSeconds < 0) {
      return null;
    }
    return RidePayoutRequest(
      requestId: requestId.isEmpty ? null : requestId,
      fromWalletId: fromWalletId.isEmpty ? null : fromWalletId,
      toWalletId: toWalletId.isEmpty ? null : toWalletId,
      amountMinorUnits: amountMinorUnits,
      currency: currency,
      message: messageRaw.isEmpty ? null : messageRaw,
      status: status,
      createdAtIso: createdAtIso,
      ageSeconds: ageSeconds,
    );
  }
}

class RideOperatorFinanceQueueTotals {
  final int pendingRequests;
  final int pendingAmountMinorUnits;
  final int approvedRequests;
  final int blockedRequests;
  final int oldestPendingAgeSeconds;
  final int reservedFeeEvents;
  final int releasedFeeEvents;
  final int settledFeeEvents;

  const RideOperatorFinanceQueueTotals({
    required this.pendingRequests,
    required this.pendingAmountMinorUnits,
    required this.approvedRequests,
    required this.blockedRequests,
    required this.oldestPendingAgeSeconds,
    required this.reservedFeeEvents,
    required this.releasedFeeEvents,
    required this.settledFeeEvents,
  });

  static RideOperatorFinanceQueueTotals? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final pendingRequests = raw['pending_requests'];
    final pendingAmountMinorUnits = raw['pending_amount_minor_units'];
    final approvedRequests = raw['approved_requests'];
    final blockedRequests = raw['blocked_requests'];
    final oldestPendingAgeSeconds = raw['oldest_pending_age_seconds'];
    final reservedFeeEvents = raw['reserved_fee_events'];
    final releasedFeeEvents = raw['released_fee_events'];
    final settledFeeEvents = raw['settled_fee_events'];
    if (pendingRequests is! int ||
        pendingAmountMinorUnits is! int ||
        approvedRequests is! int ||
        blockedRequests is! int ||
        oldestPendingAgeSeconds is! int) {
      return null;
    }
    if (pendingRequests < 0 ||
        pendingAmountMinorUnits < 0 ||
        approvedRequests < 0 ||
        blockedRequests < 0 ||
        oldestPendingAgeSeconds < 0) {
      return null;
    }
    return RideOperatorFinanceQueueTotals(
      pendingRequests: pendingRequests,
      pendingAmountMinorUnits: pendingAmountMinorUnits,
      approvedRequests: approvedRequests,
      blockedRequests: blockedRequests,
      oldestPendingAgeSeconds: oldestPendingAgeSeconds,
      reservedFeeEvents: reservedFeeEvents is int ? reservedFeeEvents : 0,
      releasedFeeEvents: releasedFeeEvents is int ? releasedFeeEvents : 0,
      settledFeeEvents: settledFeeEvents is int ? settledFeeEvents : 0,
    );
  }
}

class RideOperatorFinanceQueue {
  final String generatedAtIso;
  final String? feeWalletId;
  final RideOperatorFinanceQueueTotals totals;
  final List<RidePayoutRequest> requests;
  final List<RideDriverReserveEvent> recentReserveEvents;

  const RideOperatorFinanceQueue({
    required this.generatedAtIso,
    required this.feeWalletId,
    required this.totals,
    required this.requests,
    required this.recentReserveEvents,
  });

  static RideOperatorFinanceQueue? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final feeWalletId = (raw['fee_wallet_id'] ?? '').toString().trim();
    final totals = RideOperatorFinanceQueueTotals.fromJson(raw['totals']);
    final requestsRaw = raw['requests'];
    final recentReserveEventsRaw = raw['recent_reserve_events'];
    if (generatedAtIso.isEmpty || totals == null || requestsRaw is! List) {
      return null;
    }
    return RideOperatorFinanceQueue(
      generatedAtIso: generatedAtIso,
      feeWalletId: feeWalletId.isEmpty ? null : feeWalletId,
      totals: totals,
      requests: requestsRaw
          .map(RidePayoutRequest.fromJson)
          .whereType<RidePayoutRequest>()
          .toList(growable: false),
      recentReserveEvents: recentReserveEventsRaw is! List
          ? const <RideDriverReserveEvent>[]
          : recentReserveEventsRaw
              .map(RideDriverReserveEvent.fromJson)
              .whereType<RideDriverReserveEvent>()
              .toList(growable: false),
    );
  }
}

enum RideDriverDocumentType {
  driverLicense,
  vehicleRegistration,
  insurance,
  identityCard,
}

RideDriverDocumentType? rideDriverDocumentTypeFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'driver_license':
      return RideDriverDocumentType.driverLicense;
    case 'vehicle_registration':
      return RideDriverDocumentType.vehicleRegistration;
    case 'insurance':
      return RideDriverDocumentType.insurance;
    case 'identity_card':
      return RideDriverDocumentType.identityCard;
    default:
      return null;
  }
}

String rideDriverDocumentTypeWireValue(RideDriverDocumentType value) {
  switch (value) {
    case RideDriverDocumentType.driverLicense:
      return 'driver_license';
    case RideDriverDocumentType.vehicleRegistration:
      return 'vehicle_registration';
    case RideDriverDocumentType.insurance:
      return 'insurance';
    case RideDriverDocumentType.identityCard:
      return 'identity_card';
  }
}

enum RideDriverDocumentStatus {
  missing,
  pending,
  approved,
  rejected,
  expired,
}

RideDriverDocumentStatus? rideDriverDocumentStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'missing':
      return RideDriverDocumentStatus.missing;
    case 'pending':
      return RideDriverDocumentStatus.pending;
    case 'approved':
      return RideDriverDocumentStatus.approved;
    case 'rejected':
      return RideDriverDocumentStatus.rejected;
    case 'expired':
      return RideDriverDocumentStatus.expired;
    default:
      return null;
  }
}

class RideDriverDocument {
  final String? documentId;
  final String? driverAccountId;
  final RideDriverDocumentType documentType;
  final String? documentNumberMasked;
  final String? issuingCountry;
  final RideDriverDocumentStatus status;
  final String? submittedAtIso;
  final String? reviewedAtIso;
  final String? expiresAtIso;
  final String? reviewNote;

  const RideDriverDocument({
    required this.documentId,
    required this.driverAccountId,
    required this.documentType,
    required this.documentNumberMasked,
    required this.issuingCountry,
    required this.status,
    required this.submittedAtIso,
    required this.reviewedAtIso,
    required this.expiresAtIso,
    required this.reviewNote,
  });

  bool get isBlocking {
    switch (status) {
      case RideDriverDocumentStatus.missing:
      case RideDriverDocumentStatus.pending:
      case RideDriverDocumentStatus.rejected:
      case RideDriverDocumentStatus.expired:
        return true;
      case RideDriverDocumentStatus.approved:
        return false;
    }
  }

  static RideDriverDocument? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final documentId = (raw['document_id'] ?? '').toString().trim();
    final driverAccountId = (raw['driver_account_id'] ?? '').toString().trim();
    final documentType = rideDriverDocumentTypeFromWire(
      (raw['document_type'] ?? '').toString(),
    );
    final documentNumberMasked =
        (raw['document_number_masked'] ?? '').toString().trim();
    final issuingCountry = (raw['issuing_country'] ?? '').toString().trim();
    final status = rideDriverDocumentStatusFromWire(
      (raw['status'] ?? '').toString(),
    );
    final submittedAtIso = (raw['submitted_at'] ?? '').toString().trim();
    final reviewedAtIso = (raw['reviewed_at'] ?? '').toString().trim();
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    final reviewNote = (raw['review_note'] ?? '').toString().trim();
    if (documentType == null || status == null) {
      return null;
    }
    return RideDriverDocument(
      documentId: documentId.isEmpty ? null : documentId,
      driverAccountId: driverAccountId.isEmpty ? null : driverAccountId,
      documentType: documentType,
      documentNumberMasked:
          documentNumberMasked.isEmpty ? null : documentNumberMasked,
      issuingCountry: issuingCountry.isEmpty ? null : issuingCountry,
      status: status,
      submittedAtIso: submittedAtIso.isEmpty ? null : submittedAtIso,
      reviewedAtIso: reviewedAtIso.isEmpty ? null : reviewedAtIso,
      expiresAtIso: expiresAtIso.isEmpty ? null : expiresAtIso,
      reviewNote: reviewNote.isEmpty ? null : reviewNote,
    );
  }
}

class RideDriverDocumentSummary {
  final int missingDocuments;
  final int pendingDocuments;
  final int approvedDocuments;
  final int rejectedDocuments;
  final int expiredDocuments;
  final int blockingIssues;
  final bool readyToDrive;

  const RideDriverDocumentSummary({
    required this.missingDocuments,
    required this.pendingDocuments,
    required this.approvedDocuments,
    required this.rejectedDocuments,
    required this.expiredDocuments,
    required this.blockingIssues,
    required this.readyToDrive,
  });

  static RideDriverDocumentSummary? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final missingDocuments = raw['missing_documents'];
    final pendingDocuments = raw['pending_documents'];
    final approvedDocuments = raw['approved_documents'];
    final rejectedDocuments = raw['rejected_documents'];
    final expiredDocuments = raw['expired_documents'];
    final blockingIssues = raw['blocking_issues'];
    final readyToDrive = raw['ready_to_drive'];
    if (missingDocuments is! int ||
        pendingDocuments is! int ||
        approvedDocuments is! int ||
        rejectedDocuments is! int ||
        expiredDocuments is! int ||
        blockingIssues is! int ||
        readyToDrive is! bool) {
      return null;
    }
    if (missingDocuments < 0 ||
        pendingDocuments < 0 ||
        approvedDocuments < 0 ||
        rejectedDocuments < 0 ||
        expiredDocuments < 0 ||
        blockingIssues < 0) {
      return null;
    }
    return RideDriverDocumentSummary(
      missingDocuments: missingDocuments,
      pendingDocuments: pendingDocuments,
      approvedDocuments: approvedDocuments,
      rejectedDocuments: rejectedDocuments,
      expiredDocuments: expiredDocuments,
      blockingIssues: blockingIssues,
      readyToDrive: readyToDrive,
    );
  }
}

class RideDriverDocumentDashboard {
  final String generatedAtIso;
  final String driverAccountId;
  final RideDriverDocumentSummary summary;
  final List<RideDriverDocument> documents;

  const RideDriverDocumentDashboard({
    required this.generatedAtIso,
    required this.driverAccountId,
    required this.summary,
    required this.documents,
  });

  static RideDriverDocumentDashboard? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final driverAccountId = (raw['driver_account_id'] ?? '').toString().trim();
    final summary = RideDriverDocumentSummary.fromJson(raw['summary']);
    final documentsRaw = raw['documents'];
    if (generatedAtIso.isEmpty ||
        driverAccountId.isEmpty ||
        summary == null ||
        documentsRaw is! List) {
      return null;
    }
    return RideDriverDocumentDashboard(
      generatedAtIso: generatedAtIso,
      driverAccountId: driverAccountId,
      summary: summary,
      documents: documentsRaw
          .map(RideDriverDocument.fromJson)
          .whereType<RideDriverDocument>()
          .toList(growable: false),
    );
  }
}

class RideOperatorDocumentQueueTotals {
  final int pendingDocuments;
  final int rejectedDocuments;
  final int expiredDocuments;
  final int blockedDrivers;

  const RideOperatorDocumentQueueTotals({
    required this.pendingDocuments,
    required this.rejectedDocuments,
    required this.expiredDocuments,
    required this.blockedDrivers,
  });

  static RideOperatorDocumentQueueTotals? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final pendingDocuments = raw['pending_documents'];
    final rejectedDocuments = raw['rejected_documents'];
    final expiredDocuments = raw['expired_documents'];
    final blockedDrivers = raw['blocked_drivers'];
    if (pendingDocuments is! int ||
        rejectedDocuments is! int ||
        expiredDocuments is! int ||
        blockedDrivers is! int) {
      return null;
    }
    if (pendingDocuments < 0 ||
        rejectedDocuments < 0 ||
        expiredDocuments < 0 ||
        blockedDrivers < 0) {
      return null;
    }
    return RideOperatorDocumentQueueTotals(
      pendingDocuments: pendingDocuments,
      rejectedDocuments: rejectedDocuments,
      expiredDocuments: expiredDocuments,
      blockedDrivers: blockedDrivers,
    );
  }
}

class RideOperatorDocumentQueue {
  final String generatedAtIso;
  final RideOperatorDocumentQueueTotals totals;
  final List<RideDriverDocument> documents;

  const RideOperatorDocumentQueue({
    required this.generatedAtIso,
    required this.totals,
    required this.documents,
  });

  static RideOperatorDocumentQueue? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final totals = RideOperatorDocumentQueueTotals.fromJson(raw['totals']);
    final documentsRaw = raw['documents'];
    if (generatedAtIso.isEmpty || totals == null || documentsRaw is! List) {
      return null;
    }
    return RideOperatorDocumentQueue(
      generatedAtIso: generatedAtIso,
      totals: totals,
      documents: documentsRaw
          .map(RideDriverDocument.fromJson)
          .whereType<RideDriverDocument>()
          .toList(growable: false),
    );
  }
}

const Set<String> shamellRideDispatchRoles = <String>{
  'driver',
  'ride_driver',
  'driver_ops',
  'city_manager',
  'support_l1',
  'support_l2',
  'finance',
  'compliance_risk',
  'marketing',
  'bi_audit_read_only',
  'admin',
  'superadmin',
  'ops',
  'seller',
};

const Set<String> shamellRideDriverRoles = <String>{
  'driver',
  'ride_driver',
  'driver_ops',
  'city_manager',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> shamellRideOperatorRoles = <String>{
  'driver_ops',
  'city_manager',
  'support_l1',
  'support_l2',
  'finance',
  'compliance_risk',
  'marketing',
  'bi_audit_read_only',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> shamellRideSupportRoles = <String>{
  'driver_ops',
  'city_manager',
  'support_l1',
  'support_l2',
  'finance',
  'compliance_risk',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> shamellRideFinanceRoles = <String>{
  'driver_ops',
  'city_manager',
  'finance',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> shamellRideComplianceRoles = <String>{
  'driver_ops',
  'city_manager',
  'compliance_risk',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> shamellRideFinanceSensitiveRoles = <String>{
  'finance',
  'admin',
  'superadmin',
};

const Set<String> shamellRideComplianceSensitiveRoles = <String>{
  'compliance_risk',
  'admin',
  'superadmin',
};

const Set<String> shamellRidePricingRoles = <String>{
  'city_manager',
  'admin',
  'superadmin',
  'ops',
};

bool shamellHasRideOperationsAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (role.isEmpty) {
      continue;
    }
    if (shamellRideDispatchRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideDriverAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRideDriverRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideOperatorAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRideOperatorRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideSupportAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRideSupportRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideFinanceAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRideFinanceRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideFinanceSensitiveAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRideFinanceSensitiveRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideComplianceAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRideComplianceRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideComplianceSensitiveAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRideComplianceSensitiveRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRidePricingAccess(List<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellRidePricingRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool _rideSnapshotHasPermission(
  AccountPrivilegeSnapshot snapshot,
  String permission,
) {
  return snapshot.can(permission, product: 'rides') ||
      snapshot.hasPermission(permission);
}

bool _rideSnapshotHasAnyPermission(
  AccountPrivilegeSnapshot snapshot,
  Iterable<String> permissions,
) {
  for (final permission in permissions) {
    if (_rideSnapshotHasPermission(snapshot, permission)) {
      return true;
    }
  }
  return false;
}

bool shamellHasRideDriverSnapshotAccess(AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasPermission(snapshot, 'rides.driver.read');
  }
  if (shamellHasRideDriverAccess(snapshot.roles)) {
    return true;
  }
  if (snapshot.isAdmin) {
    return true;
  }
  if (snapshot.products.isNotEmpty) {
    return snapshot.hasProductAccess('rides');
  }
  return false;
}

bool shamellHasRideOperatorSnapshotAccess(AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasPermission(snapshot, 'rides.operator.read');
  }
  if (shamellHasRideOperatorAccess(snapshot.roles)) {
    return true;
  }
  if (snapshot.isAdmin) {
    return true;
  }
  if (snapshot.products.isNotEmpty) {
    return snapshot.hasProductAccess('rides');
  }
  return false;
}

bool shamellHasRideSupportSnapshotAccess(AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasPermission(snapshot, 'rides.support.read');
  }
  if (shamellHasRideSupportAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasRideFinanceSnapshotAccess(AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasPermission(snapshot, 'rides.finance.read');
  }
  if (shamellHasRideFinanceAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasRideFinanceSensitiveSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasPermission(snapshot, 'rides.finance.sensitive.read');
  }
  if (shamellHasRideFinanceSensitiveAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasRideComplianceSnapshotAccess(AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasPermission(snapshot, 'rides.compliance.read');
  }
  if (shamellHasRideComplianceAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasRideComplianceSensitiveSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasAnyPermission(snapshot, const <String>[
      'rides.document.sensitive.read',
    ]);
  }
  if (shamellHasRideComplianceSensitiveAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasRidePricingSnapshotAccess(AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _rideSnapshotHasPermission(snapshot, 'rides.pricing.write');
  }
  if (shamellHasRidePricingAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

class RideOperatorLiveCounts {
  final int openDispatches;
  final int activeTrips;
  final int enRouteTrips;
  final int inProgressTrips;
  final int paymentFailures;
  final int onlineDrivers;

  const RideOperatorLiveCounts({
    required this.openDispatches,
    required this.activeTrips,
    required this.enRouteTrips,
    required this.inProgressTrips,
    required this.paymentFailures,
    required this.onlineDrivers,
  });

  static RideOperatorLiveCounts? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final openDispatches = raw['open_dispatches'];
    final activeTrips = raw['active_trips'];
    final enRouteTrips = raw['en_route_trips'];
    final inProgressTrips = raw['in_progress_trips'];
    final paymentFailures = raw['payment_failures'];
    final onlineDrivers = raw['online_drivers'];
    if (openDispatches is! int ||
        activeTrips is! int ||
        enRouteTrips is! int ||
        inProgressTrips is! int ||
        paymentFailures is! int ||
        onlineDrivers is! int) {
      return null;
    }
    return RideOperatorLiveCounts(
      openDispatches: openDispatches,
      activeTrips: activeTrips,
      enRouteTrips: enRouteTrips,
      inProgressTrips: inProgressTrips,
      paymentFailures: paymentFailures,
      onlineDrivers: onlineDrivers,
    );
  }
}

enum RideOperatorAlertSeverity {
  info,
  medium,
  high,
  critical,
}

RideOperatorAlertSeverity? rideOperatorAlertSeverityFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'info':
      return RideOperatorAlertSeverity.info;
    case 'medium':
      return RideOperatorAlertSeverity.medium;
    case 'high':
      return RideOperatorAlertSeverity.high;
    case 'critical':
      return RideOperatorAlertSeverity.critical;
    default:
      return null;
  }
}

class RideOperatorAlert {
  final String code;
  final RideOperatorAlertSeverity severity;
  final String title;
  final String detail;

  const RideOperatorAlert({
    required this.code,
    required this.severity,
    required this.title,
    required this.detail,
  });

  static RideOperatorAlert? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final code = (raw['code'] ?? '').toString().trim();
    final severity =
        rideOperatorAlertSeverityFromWire((raw['severity'] ?? '').toString());
    final title = (raw['title'] ?? '').toString().trim();
    final detail = (raw['detail'] ?? '').toString().trim();
    if (code.isEmpty || severity == null || title.isEmpty || detail.isEmpty) {
      return null;
    }
    return RideOperatorAlert(
      code: code,
      severity: severity,
      title: title,
      detail: detail,
    );
  }
}

enum RideOperatorCaseCategory {
  finance,
  support,
  compliance,
}

RideOperatorCaseCategory? rideOperatorCaseCategoryFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'finance':
      return RideOperatorCaseCategory.finance;
    case 'support':
      return RideOperatorCaseCategory.support;
    case 'compliance':
      return RideOperatorCaseCategory.compliance;
    default:
      return null;
  }
}

class RideOperatorCaseQueueTotals {
  final int openCases;
  final int criticalCases;
  final int highCases;
  final int financeCases;
  final int supportCases;
  final int complianceCases;

  const RideOperatorCaseQueueTotals({
    required this.openCases,
    required this.criticalCases,
    required this.highCases,
    required this.financeCases,
    required this.supportCases,
    required this.complianceCases,
  });

  static RideOperatorCaseQueueTotals? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final openCases = raw['open_cases'];
    final criticalCases = raw['critical_cases'];
    final highCases = raw['high_cases'];
    final financeCases = raw['finance_cases'];
    final supportCases = raw['support_cases'];
    final complianceCases = raw['compliance_cases'];
    if (openCases is! int ||
        criticalCases is! int ||
        highCases is! int ||
        financeCases is! int ||
        supportCases is! int ||
        complianceCases is! int) {
      return null;
    }
    return RideOperatorCaseQueueTotals(
      openCases: openCases,
      criticalCases: criticalCases,
      highCases: highCases,
      financeCases: financeCases,
      supportCases: supportCases,
      complianceCases: complianceCases,
    );
  }
}

class RideOperatorCaseItem {
  final String caseId;
  final RideOperatorCaseCategory category;
  final RideOperatorAlertSeverity severity;
  final String title;
  final String detail;
  final String suggestedAction;
  final String rideId;
  final String rideClass;
  final RideTripStatus status;
  final String pickup;
  final String destination;
  final String driverName;
  final String carPlate;
  final int fareEstimateMinorUnits;
  final int ageSeconds;
  final String createdAtIso;
  final String lastUpdatedAtIso;

  const RideOperatorCaseItem({
    required this.caseId,
    required this.category,
    required this.severity,
    required this.title,
    required this.detail,
    required this.suggestedAction,
    required this.rideId,
    required this.rideClass,
    required this.status,
    required this.pickup,
    required this.destination,
    required this.driverName,
    required this.carPlate,
    required this.fareEstimateMinorUnits,
    required this.ageSeconds,
    required this.createdAtIso,
    required this.lastUpdatedAtIso,
  });

  static RideOperatorCaseItem? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final caseId = (raw['case_id'] ?? '').toString().trim();
    final category =
        rideOperatorCaseCategoryFromWire((raw['category'] ?? '').toString());
    final severity =
        rideOperatorAlertSeverityFromWire((raw['severity'] ?? '').toString());
    final title = (raw['title'] ?? '').toString().trim();
    final detail = (raw['detail'] ?? '').toString().trim();
    final suggestedAction = (raw['suggested_action'] ?? '').toString().trim();
    final rideId = (raw['ride_id'] ?? '').toString().trim();
    final rideClass = (raw['ride_class'] ?? '').toString().trim();
    final status = rideTripStatusFromWire((raw['status'] ?? '').toString());
    final pickup = (raw['pickup'] ?? '').toString().trim();
    final destination = (raw['destination'] ?? '').toString().trim();
    final driverName = (raw['driver_name'] ?? '').toString().trim();
    final carPlate = (raw['car_plate'] ?? '').toString().trim();
    final fareEstimateMinorUnits = raw['fare_estimate_minor_units'];
    final ageSeconds = raw['age_seconds'];
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final lastUpdatedAtIso = (raw['last_updated_at'] ?? '').toString().trim();
    if (caseId.isEmpty ||
        category == null ||
        severity == null ||
        title.isEmpty ||
        detail.isEmpty ||
        suggestedAction.isEmpty ||
        rideId.isEmpty ||
        rideClass.isEmpty ||
        status == null ||
        pickup.isEmpty ||
        destination.isEmpty ||
        driverName.isEmpty ||
        carPlate.isEmpty ||
        fareEstimateMinorUnits is! int ||
        ageSeconds is! int ||
        createdAtIso.isEmpty ||
        lastUpdatedAtIso.isEmpty) {
      return null;
    }
    if (fareEstimateMinorUnits < 0 || ageSeconds < 0) {
      return null;
    }
    return RideOperatorCaseItem(
      caseId: caseId,
      category: category,
      severity: severity,
      title: title,
      detail: detail,
      suggestedAction: suggestedAction,
      rideId: rideId,
      rideClass: rideClass,
      status: status,
      pickup: pickup,
      destination: destination,
      driverName: driverName,
      carPlate: carPlate,
      fareEstimateMinorUnits: fareEstimateMinorUnits,
      ageSeconds: ageSeconds,
      createdAtIso: createdAtIso,
      lastUpdatedAtIso: lastUpdatedAtIso,
    );
  }
}

class RideOperatorCaseQueue {
  final String generatedAtIso;
  final RideOperatorCaseQueueTotals totals;
  final List<RideOperatorCaseItem> cases;

  const RideOperatorCaseQueue({
    required this.generatedAtIso,
    required this.totals,
    required this.cases,
  });

  static RideOperatorCaseQueue? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final totals = RideOperatorCaseQueueTotals.fromJson(raw['totals']);
    final casesRaw = raw['cases'];
    if (generatedAtIso.isEmpty || totals == null || casesRaw is! List) {
      return null;
    }
    return RideOperatorCaseQueue(
      generatedAtIso: generatedAtIso,
      totals: totals,
      cases: casesRaw
          .map(RideOperatorCaseItem.fromJson)
          .whereType<RideOperatorCaseItem>()
          .toList(growable: false),
    );
  }
}

enum RideSupportTicketCategory {
  bookingIssue,
  driverBehavior,
  safety,
  paymentIssue,
  lostItem,
  other,
}

RideSupportTicketCategory? rideSupportTicketCategoryFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'booking_issue':
      return RideSupportTicketCategory.bookingIssue;
    case 'driver_behavior':
      return RideSupportTicketCategory.driverBehavior;
    case 'safety':
      return RideSupportTicketCategory.safety;
    case 'payment_issue':
      return RideSupportTicketCategory.paymentIssue;
    case 'lost_item':
      return RideSupportTicketCategory.lostItem;
    case 'other':
      return RideSupportTicketCategory.other;
    default:
      return null;
  }
}

String rideSupportTicketCategoryWireValue(RideSupportTicketCategory value) {
  switch (value) {
    case RideSupportTicketCategory.bookingIssue:
      return 'booking_issue';
    case RideSupportTicketCategory.driverBehavior:
      return 'driver_behavior';
    case RideSupportTicketCategory.safety:
      return 'safety';
    case RideSupportTicketCategory.paymentIssue:
      return 'payment_issue';
    case RideSupportTicketCategory.lostItem:
      return 'lost_item';
    case RideSupportTicketCategory.other:
      return 'other';
  }
}

enum RideSupportTicketContactPreference {
  inApp,
  email,
  phone,
}

RideSupportTicketContactPreference? rideSupportTicketContactPreferenceFromWire(
  String raw,
) {
  switch (raw.trim().toLowerCase()) {
    case 'in_app':
      return RideSupportTicketContactPreference.inApp;
    case 'email':
      return RideSupportTicketContactPreference.email;
    case 'phone':
      return RideSupportTicketContactPreference.phone;
    default:
      return null;
  }
}

String rideSupportTicketContactPreferenceWireValue(
  RideSupportTicketContactPreference value,
) {
  switch (value) {
    case RideSupportTicketContactPreference.inApp:
      return 'in_app';
    case RideSupportTicketContactPreference.email:
      return 'email';
    case RideSupportTicketContactPreference.phone:
      return 'phone';
  }
}

enum RideSupportTicketStatus {
  open,
  resolved,
}

RideSupportTicketStatus? rideSupportTicketStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'open':
      return RideSupportTicketStatus.open;
    case 'resolved':
      return RideSupportTicketStatus.resolved;
    default:
      return null;
  }
}

class RideSupportTicket {
  final String ticketId;
  final String? rideId;
  final String? riderAccountId;
  final RideSupportTicketCategory category;
  final String subject;
  final String body;
  final RideSupportTicketContactPreference preferredContact;
  final RideSupportTicketStatus status;
  final String? resolutionNote;
  final String? resolvedByAccountId;
  final String? resolvedAtIso;
  final String? rideClass;
  final RideTripStatus? tripStatus;
  final String? pickup;
  final String? destination;
  final String? driverName;
  final String? carPlate;
  final String createdAtIso;
  final String updatedAtIso;

  const RideSupportTicket({
    required this.ticketId,
    required this.rideId,
    required this.riderAccountId,
    required this.category,
    required this.subject,
    required this.body,
    required this.preferredContact,
    required this.status,
    required this.resolutionNote,
    required this.resolvedByAccountId,
    required this.resolvedAtIso,
    required this.rideClass,
    required this.tripStatus,
    required this.pickup,
    required this.destination,
    required this.driverName,
    required this.carPlate,
    required this.createdAtIso,
    required this.updatedAtIso,
  });

  bool get isOpen => status == RideSupportTicketStatus.open;

  static RideSupportTicket? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final ticketId = (raw['ticket_id'] ?? '').toString().trim();
    final rideId = (raw['ride_id'] ?? '').toString().trim();
    final riderAccountId = (raw['rider_account_id'] ?? '').toString().trim();
    final category = rideSupportTicketCategoryFromWire(
      (raw['category'] ?? '').toString(),
    );
    final subject = (raw['subject'] ?? '').toString().trim();
    final body = (raw['body'] ?? '').toString().trim();
    final preferredContact = rideSupportTicketContactPreferenceFromWire(
      (raw['preferred_contact'] ?? '').toString(),
    );
    final status = rideSupportTicketStatusFromWire(
      (raw['status'] ?? '').toString(),
    );
    final resolutionNote = (raw['resolution_note'] ?? '').toString().trim();
    final resolvedByAccountId =
        (raw['resolved_by_account_id'] ?? '').toString().trim();
    final resolvedAtIso = (raw['resolved_at'] ?? '').toString().trim();
    final rideClass = (raw['ride_class'] ?? '').toString().trim();
    final tripStatus = rideTripStatusFromWire(
      (raw['trip_status'] ?? '').toString(),
    );
    final pickup = (raw['pickup'] ?? '').toString().trim();
    final destination = (raw['destination'] ?? '').toString().trim();
    final driverName = (raw['driver_name'] ?? '').toString().trim();
    final carPlate = (raw['car_plate'] ?? '').toString().trim();
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    if (ticketId.isEmpty ||
        category == null ||
        subject.isEmpty ||
        body.isEmpty ||
        preferredContact == null ||
        status == null ||
        createdAtIso.isEmpty ||
        updatedAtIso.isEmpty) {
      return null;
    }
    return RideSupportTicket(
      ticketId: ticketId,
      rideId: rideId.isEmpty ? null : rideId,
      riderAccountId: riderAccountId.isEmpty ? null : riderAccountId,
      category: category,
      subject: subject,
      body: body,
      preferredContact: preferredContact,
      status: status,
      resolutionNote: resolutionNote.isEmpty ? null : resolutionNote,
      resolvedByAccountId:
          resolvedByAccountId.isEmpty ? null : resolvedByAccountId,
      resolvedAtIso: resolvedAtIso.isEmpty ? null : resolvedAtIso,
      rideClass: rideClass.isEmpty ? null : rideClass,
      tripStatus: tripStatus,
      pickup: pickup.isEmpty ? null : pickup,
      destination: destination.isEmpty ? null : destination,
      driverName: driverName.isEmpty ? null : driverName,
      carPlate: carPlate.isEmpty ? null : carPlate,
      createdAtIso: createdAtIso,
      updatedAtIso: updatedAtIso,
    );
  }
}

class RideSupportTicketList {
  final String generatedAtIso;
  final List<RideSupportTicket> tickets;

  const RideSupportTicketList({
    required this.generatedAtIso,
    required this.tickets,
  });

  static RideSupportTicketList? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final ticketsRaw = raw['tickets'];
    if (generatedAtIso.isEmpty || ticketsRaw is! List) {
      return null;
    }
    return RideSupportTicketList(
      generatedAtIso: generatedAtIso,
      tickets: ticketsRaw
          .map(RideSupportTicket.fromJson)
          .whereType<RideSupportTicket>()
          .toList(growable: false),
    );
  }
}

class RideOperatorSupportQueueTotals {
  final int openTickets;
  final int urgentTickets;

  const RideOperatorSupportQueueTotals({
    required this.openTickets,
    required this.urgentTickets,
  });

  static RideOperatorSupportQueueTotals? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final openTickets = raw['open_tickets'];
    final urgentTickets = raw['urgent_tickets'];
    if (openTickets is! int || urgentTickets is! int) {
      return null;
    }
    return RideOperatorSupportQueueTotals(
      openTickets: openTickets,
      urgentTickets: urgentTickets,
    );
  }
}

class RideOperatorSupportQueue {
  final String generatedAtIso;
  final RideOperatorSupportQueueTotals totals;
  final List<RideSupportTicket> tickets;

  const RideOperatorSupportQueue({
    required this.generatedAtIso,
    required this.totals,
    required this.tickets,
  });

  static RideOperatorSupportQueue? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final totals = RideOperatorSupportQueueTotals.fromJson(raw['totals']);
    final ticketsRaw = raw['tickets'];
    if (generatedAtIso.isEmpty || totals == null || ticketsRaw is! List) {
      return null;
    }
    return RideOperatorSupportQueue(
      generatedAtIso: generatedAtIso,
      totals: totals,
      tickets: ticketsRaw
          .map(RideSupportTicket.fromJson)
          .whereType<RideSupportTicket>()
          .toList(growable: false),
    );
  }
}

class RideOperatorServiceClassSummary {
  final String rideClass;
  final int openDispatches;
  final int activeTrips;
  final int completedTodayCount;
  final int openDispatchValueMinorUnits;
  final int activeTripValueMinorUnits;
  final int completedTodayValueMinorUnits;

  const RideOperatorServiceClassSummary({
    required this.rideClass,
    required this.openDispatches,
    required this.activeTrips,
    required this.completedTodayCount,
    required this.openDispatchValueMinorUnits,
    required this.activeTripValueMinorUnits,
    required this.completedTodayValueMinorUnits,
  });

  static RideOperatorServiceClassSummary? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final rideClass = (raw['ride_class'] ?? '').toString().trim();
    final openDispatches = raw['open_dispatches'];
    final activeTrips = raw['active_trips'];
    final completedTodayCount = raw['completed_today_count'];
    final openDispatchValueMinorUnits = raw['open_dispatch_value_minor_units'];
    final activeTripValueMinorUnits = raw['active_trip_value_minor_units'];
    final completedTodayValueMinorUnits =
        raw['completed_today_value_minor_units'];
    if (rideClass.isEmpty ||
        openDispatches is! int ||
        activeTrips is! int ||
        completedTodayCount is! int ||
        openDispatchValueMinorUnits is! int ||
        activeTripValueMinorUnits is! int ||
        completedTodayValueMinorUnits is! int) {
      return null;
    }
    return RideOperatorServiceClassSummary(
      rideClass: rideClass,
      openDispatches: openDispatches,
      activeTrips: activeTrips,
      completedTodayCount: completedTodayCount,
      openDispatchValueMinorUnits: openDispatchValueMinorUnits,
      activeTripValueMinorUnits: activeTripValueMinorUnits,
      completedTodayValueMinorUnits: completedTodayValueMinorUnits,
    );
  }
}

class RideOperatorSummary {
  final String generatedAtIso;
  final int openDispatchValueMinorUnits;
  final int activeTripValueMinorUnits;
  final int completedTodayCount;
  final int completedTodayValueMinorUnits;
  final int avgOpenEtaSeconds;
  final int avgActiveEtaSeconds;
  final int activeDriverCount;
  final int idleOnlineDrivers;
  final int driverUtilizationBps;
  final int capacityGapDispatches;
  final int stalledDispatches;
  final int overdueArrivals;
  final int longRunningTrips;
  final int silentTrackingTrips;
  final int metadataGaps;
  final List<RideOperatorServiceClassSummary> classBreakdown;
  final List<RideOperatorAlert> alerts;

  const RideOperatorSummary({
    required this.generatedAtIso,
    required this.openDispatchValueMinorUnits,
    required this.activeTripValueMinorUnits,
    required this.completedTodayCount,
    required this.completedTodayValueMinorUnits,
    required this.avgOpenEtaSeconds,
    required this.avgActiveEtaSeconds,
    required this.activeDriverCount,
    required this.idleOnlineDrivers,
    required this.driverUtilizationBps,
    required this.capacityGapDispatches,
    required this.stalledDispatches,
    required this.overdueArrivals,
    required this.longRunningTrips,
    required this.silentTrackingTrips,
    required this.metadataGaps,
    required this.classBreakdown,
    required this.alerts,
  });

  static RideOperatorSummary? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final openDispatchValueMinorUnits = raw['open_dispatch_value_minor_units'];
    final activeTripValueMinorUnits = raw['active_trip_value_minor_units'];
    final completedTodayCount = raw['completed_today_count'];
    final completedTodayValueMinorUnits =
        raw['completed_today_value_minor_units'];
    final avgOpenEtaSeconds = raw['avg_open_eta_seconds'];
    final avgActiveEtaSeconds = raw['avg_active_eta_seconds'];
    final activeDriverCount = raw['active_driver_count'];
    final idleOnlineDrivers = raw['idle_online_drivers'];
    final driverUtilizationBps = raw['driver_utilization_bps'];
    final capacityGapDispatches = raw['capacity_gap_dispatches'];
    final stalledDispatches = raw['stalled_dispatches'];
    final overdueArrivals = raw['overdue_arrivals'];
    final longRunningTrips = raw['long_running_trips'];
    final silentTrackingTrips = raw['silent_tracking_trips'];
    final metadataGaps = raw['metadata_gaps'];
    final classBreakdownRaw = raw['class_breakdown'];
    final alertsRaw = raw['alerts'];
    if (generatedAtIso.isEmpty ||
        openDispatchValueMinorUnits is! int ||
        activeTripValueMinorUnits is! int ||
        completedTodayCount is! int ||
        completedTodayValueMinorUnits is! int ||
        avgOpenEtaSeconds is! int ||
        avgActiveEtaSeconds is! int ||
        stalledDispatches is! int ||
        overdueArrivals is! int ||
        longRunningTrips is! int ||
        silentTrackingTrips is! int ||
        metadataGaps is! int ||
        classBreakdownRaw is! List ||
        alertsRaw is! List) {
      return null;
    }
    return RideOperatorSummary(
      generatedAtIso: generatedAtIso,
      openDispatchValueMinorUnits: openDispatchValueMinorUnits,
      activeTripValueMinorUnits: activeTripValueMinorUnits,
      completedTodayCount: completedTodayCount,
      completedTodayValueMinorUnits: completedTodayValueMinorUnits,
      avgOpenEtaSeconds: avgOpenEtaSeconds,
      avgActiveEtaSeconds: avgActiveEtaSeconds,
      activeDriverCount: activeDriverCount is int ? activeDriverCount : 0,
      idleOnlineDrivers: idleOnlineDrivers is int ? idleOnlineDrivers : 0,
      driverUtilizationBps:
          driverUtilizationBps is int ? driverUtilizationBps : 0,
      capacityGapDispatches:
          capacityGapDispatches is int ? capacityGapDispatches : 0,
      stalledDispatches: stalledDispatches,
      overdueArrivals: overdueArrivals,
      longRunningTrips: longRunningTrips,
      silentTrackingTrips: silentTrackingTrips,
      metadataGaps: metadataGaps,
      classBreakdown: classBreakdownRaw
          .map(RideOperatorServiceClassSummary.fromJson)
          .whereType<RideOperatorServiceClassSummary>()
          .toList(growable: false),
      alerts: alertsRaw
          .map(RideOperatorAlert.fromJson)
          .whereType<RideOperatorAlert>()
          .toList(growable: false),
    );
  }
}

class RideOperatorLiveBoard {
  final RideOperatorLiveCounts counts;
  final RideOperatorSummary? summary;
  final List<RideTrip> openDispatches;
  final List<RideTrip> activeTrips;

  const RideOperatorLiveBoard({
    required this.counts,
    this.summary,
    required this.openDispatches,
    required this.activeTrips,
  });

  static RideOperatorLiveBoard? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final counts = RideOperatorLiveCounts.fromJson(raw['counts']);
    final openDispatchesRaw = raw['open_dispatches'];
    final activeTripsRaw = raw['active_trips'];
    if (counts == null ||
        openDispatchesRaw is! List ||
        activeTripsRaw is! List) {
      return null;
    }
    return RideOperatorLiveBoard(
      counts: counts,
      summary: RideOperatorSummary.fromJson(raw['summary']),
      openDispatches: openDispatchesRaw
          .map(RideTrip.fromJson)
          .whereType<RideTrip>()
          .toList(),
      activeTrips:
          activeTripsRaw.map(RideTrip.fromJson).whereType<RideTrip>().toList(),
    );
  }
}

enum RideDriverAvailabilityStatus {
  online,
  offline,
}

RideDriverAvailabilityStatus? rideDriverAvailabilityStatusFromWire(
  String raw,
) {
  switch (raw.trim().toLowerCase()) {
    case 'online':
      return RideDriverAvailabilityStatus.online;
    case 'offline':
      return RideDriverAvailabilityStatus.offline;
    default:
      return null;
  }
}

class RideOperatorDriverRosterEntry {
  final String driverAccountId;
  final RideDriverAvailabilityStatus availabilityStatus;
  final String lastSeenAtIso;
  final String? lastOnlineAtIso;
  final String updatedAtIso;
  final RideCoordinatePoint? location;
  final String? driverName;
  final String? carPlate;
  final String? activeRideId;
  final RideTripStatus? activeTripStatus;
  final String? activePickup;
  final String? activeDestination;
  // Cycle 138 — post-trip rating roll-up surfaced alongside each
  // driver so operators can balance load with quality. Count == 0
  // means the driver has never been rated; the UI shows "—".
  final int ratingCount;
  final double? averageStars;

  const RideOperatorDriverRosterEntry({
    required this.driverAccountId,
    required this.availabilityStatus,
    required this.lastSeenAtIso,
    this.lastOnlineAtIso,
    required this.updatedAtIso,
    this.location,
    this.driverName,
    this.carPlate,
    this.activeRideId,
    this.activeTripStatus,
    this.activePickup,
    this.activeDestination,
    this.ratingCount = 0,
    this.averageStars,
  });

  bool get isOnline =>
      availabilityStatus == RideDriverAvailabilityStatus.online;

  bool get isIdleOnline => isOnline && activeRideId == null;

  bool get hasRatings => ratingCount > 0 && averageStars != null;

  static RideOperatorDriverRosterEntry? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final driverAccountId = (raw['driver_account_id'] ?? '').toString().trim();
    final availabilityStatus = rideDriverAvailabilityStatusFromWire(
      (raw['availability_status'] ?? '').toString(),
    );
    final lastSeenAtIso = (raw['last_seen_at'] ?? '').toString().trim();
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    if (driverAccountId.isEmpty ||
        availabilityStatus == null ||
        lastSeenAtIso.isEmpty ||
        updatedAtIso.isEmpty) {
      return null;
    }
    final lastOnlineAtIso = (raw['last_online_at'] ?? '').toString().trim();
    final driverName = (raw['driver_name'] ?? '').toString().trim();
    final carPlate = (raw['car_plate'] ?? '').toString().trim();
    final activeRideId = (raw['active_ride_id'] ?? '').toString().trim();
    final activePickup = (raw['active_pickup'] ?? '').toString().trim();
    final activeDestination =
        (raw['active_destination'] ?? '').toString().trim();
    // Cycle 138 — tolerate missing/typed-as-string rating fields so
    // an older BFF (pre-aggregate JOIN) still parses cleanly.
    final ratingCountRaw = raw['rating_count'];
    final int ratingCount = ratingCountRaw is int
        ? ratingCountRaw
        : ratingCountRaw is num
            ? ratingCountRaw.toInt()
            : int.tryParse('${ratingCountRaw ?? 0}') ?? 0;
    final avgRaw = raw['average_stars'];
    final double? averageStars = avgRaw is num
        ? avgRaw.toDouble()
        : avgRaw is String
            ? double.tryParse(avgRaw)
            : null;
    return RideOperatorDriverRosterEntry(
      driverAccountId: driverAccountId,
      availabilityStatus: availabilityStatus,
      lastSeenAtIso: lastSeenAtIso,
      lastOnlineAtIso: lastOnlineAtIso.isEmpty ? null : lastOnlineAtIso,
      updatedAtIso: updatedAtIso,
      location: RideCoordinatePoint.fromJson(raw['location']),
      driverName: driverName.isEmpty ? null : driverName,
      carPlate: carPlate.isEmpty ? null : carPlate,
      activeRideId: activeRideId.isEmpty ? null : activeRideId,
      activeTripStatus:
          rideTripStatusFromWire((raw['active_trip_status'] ?? '').toString()),
      activePickup: activePickup.isEmpty ? null : activePickup,
      activeDestination: activeDestination.isEmpty ? null : activeDestination,
      ratingCount: ratingCount,
      averageStars: averageStars,
    );
  }
}

class RideOperatorDriverRoster {
  final String generatedAtIso;
  final List<RideOperatorDriverRosterEntry> drivers;

  const RideOperatorDriverRoster({
    required this.generatedAtIso,
    required this.drivers,
  });

  static RideOperatorDriverRoster? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final driversRaw = raw['drivers'];
    if (generatedAtIso.isEmpty || driversRaw is! List) {
      return null;
    }
    return RideOperatorDriverRoster(
      generatedAtIso: generatedAtIso,
      drivers: driversRaw
          .map(RideOperatorDriverRosterEntry.fromJson)
          .whereType<RideOperatorDriverRosterEntry>()
          .toList(growable: false),
    );
  }
}

enum RideOperatorRole {
  superAdmin,
  cityManager,
  supportL1,
  supportL2,
  driverOps,
  finance,
  complianceRisk,
  marketing,
  biAuditReadOnly,
}

enum RideAdminPermission {
  configurePlatform,
  configureCityPricing,
  operateLiveMap,
  manageDriverOnboarding,
  manageTickets,
  issueRefunds,
  managePayouts,
  reviewRiskCases,
  managePromotions,
  viewAuditLogs,
}

Set<RideAdminPermission> rideDefaultPermissionsForRole(RideOperatorRole role) {
  switch (role) {
    case RideOperatorRole.superAdmin:
      return Set<RideAdminPermission>.from(RideAdminPermission.values);
    case RideOperatorRole.cityManager:
      return <RideAdminPermission>{
        RideAdminPermission.configureCityPricing,
        RideAdminPermission.operateLiveMap,
        RideAdminPermission.manageDriverOnboarding,
        RideAdminPermission.manageTickets,
        RideAdminPermission.viewAuditLogs,
      };
    case RideOperatorRole.supportL1:
      return <RideAdminPermission>{
        RideAdminPermission.manageTickets,
      };
    case RideOperatorRole.supportL2:
      return <RideAdminPermission>{
        RideAdminPermission.manageTickets,
        RideAdminPermission.issueRefunds,
      };
    case RideOperatorRole.driverOps:
      return <RideAdminPermission>{
        RideAdminPermission.manageDriverOnboarding,
        RideAdminPermission.operateLiveMap,
      };
    case RideOperatorRole.finance:
      return <RideAdminPermission>{
        RideAdminPermission.managePayouts,
        RideAdminPermission.issueRefunds,
        RideAdminPermission.viewAuditLogs,
      };
    case RideOperatorRole.complianceRisk:
      return <RideAdminPermission>{
        RideAdminPermission.reviewRiskCases,
        RideAdminPermission.viewAuditLogs,
      };
    case RideOperatorRole.marketing:
      return <RideAdminPermission>{
        RideAdminPermission.managePromotions,
      };
    case RideOperatorRole.biAuditReadOnly:
      return <RideAdminPermission>{
        RideAdminPermission.viewAuditLogs,
      };
  }
}

bool rideReasonCodeIsValid(String reasonCode) {
  final value = reasonCode.trim();
  if (value.isEmpty || value.length > 64) return false;
  final allowed = RegExp(r'^[a-z0-9_]+$');
  return allowed.hasMatch(value);
}

class RideAuditAction {
  final String actorId;
  final RideOperatorRole actorRole;
  final String action;
  final String reasonCode;
  final String targetType;
  final String targetId;
  final String createdAtIso;

  const RideAuditAction({
    required this.actorId,
    required this.actorRole,
    required this.action,
    required this.reasonCode,
    required this.targetType,
    required this.targetId,
    required this.createdAtIso,
  });

  bool get isWriteSafe {
    return actorId.trim().isNotEmpty &&
        action.trim().isNotEmpty &&
        targetType.trim().isNotEmpty &&
        targetId.trim().isNotEmpty &&
        rideReasonCodeIsValid(reasonCode);
  }

  String toWireJson() => jsonEncode(<String, Object?>{
        'actor_id': actorId,
        'actor_role': actorRole.name,
        'action': action,
        'reason_code': reasonCode,
        'target_type': targetType,
        'target_id': targetId,
        'created_at': createdAtIso,
      });
}
