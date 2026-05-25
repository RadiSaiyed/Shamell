import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';

void main() {
  test('realtime freshness budgets match transit SLA targets', () {
    expect(
      coachRealtimeFreshnessBudget(CoachRealtimeFeedKind.tripUpdates),
      const Duration(seconds: 90),
    );
    expect(
      coachRealtimeFreshnessBudget(CoachRealtimeFeedKind.vehiclePositions),
      const Duration(seconds: 90),
    );
    expect(
      coachRealtimeFreshnessBudget(CoachRealtimeFeedKind.serviceAlerts),
      const Duration(minutes: 10),
    );

    final now = DateTime.utc(2026, 4, 7, 12, 0, 0);
    expect(
      coachRealtimeFeedIsFresh(
        kind: CoachRealtimeFeedKind.tripUpdates,
        observedAt: now.subtract(const Duration(seconds: 89)),
        now: now,
      ),
      isTrue,
    );
    expect(
      coachRealtimeFeedIsFresh(
        kind: CoachRealtimeFeedKind.tripUpdates,
        observedAt: now.subtract(const Duration(seconds: 91)),
        now: now,
      ),
      isFalse,
    );
    expect(
      coachRealtimeFeedIsFresh(
        kind: CoachRealtimeFeedKind.serviceAlerts,
        observedAt: now.subtract(const Duration(minutes: 9, seconds: 59)),
        now: now,
      ),
      isTrue,
    );
    expect(
      coachRealtimeFeedIsFresh(
        kind: CoachRealtimeFeedKind.serviceAlerts,
        observedAt: now.subtract(const Duration(minutes: 10, seconds: 1)),
        now: now,
      ),
      isFalse,
    );
  });

  test('wallet snapshot enforces strict balance bucket segregation', () {
    final valid = CoachWalletSnapshot.fromJson(<String, Object?>{
      'customer_id': 'cust-1',
      'buckets': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'cash_balance',
          'currency': 'SYP',
          'balance_minor_units': 12000,
        },
        <String, Object?>{
          'type': 'promo_credit',
          'currency': 'SYP',
          'balance_minor_units': 2300,
        },
        <String, Object?>{
          'type': 'refund_credit',
          'currency': 'SYP',
          'balance_minor_units': 1800,
        },
        <String, Object?>{
          'type': 'gift_card_credit',
          'currency': 'SYP',
          'balance_minor_units': 500,
        },
      ],
    });

    expect(valid, isNotNull);
    expect(valid!.hasStrictBucketSegregation(), isTrue);
    expect(valid.bucketBalance(CoachWalletBucketType.cashBalance), 12000);
    expect(valid.bucketBalance(CoachWalletBucketType.giftCardCredit), 500);

    final duplicateBucket = CoachWalletSnapshot.fromJson(<String, Object?>{
      'customer_id': 'cust-1',
      'buckets': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'cash_balance',
          'currency': 'SYP',
          'balance_minor_units': 12000,
        },
        <String, Object?>{
          'type': 'cash_balance',
          'currency': 'SYP',
          'balance_minor_units': 100,
        },
      ],
    });

    expect(duplicateBucket, isNull);
  });

  test('offer and hold stay separate commercial records', () {
    final offer = CoachOffer.fromJson(<String, Object?>{
      'offer_id': 'offer-1',
      'operator_id': 'op-1',
      'itinerary_id': 'iti-1',
      'currency': 'SYP',
      'total_minor_units': 4590,
      'seats_requested': 2,
      'hold_supported': true,
      'changeable': true,
      'refundable': false,
      'expires_at': '2026-04-07T12:05:00Z',
    });
    final hold = CoachHold.fromJson(<String, Object?>{
      'hold_id': 'hold-1',
      'offer_id': 'offer-1',
      'operator_reference': 'op-hold-9',
      'expires_at': '2026-04-07T12:04:30Z',
      'status': 'active',
      'seat_assignments': <Map<String, Object?>>[
        <String, Object?>{
          'passenger_id': 'pax-1',
          'seat_number': '4A',
        },
      ],
    });

    expect(offer, isNotNull);
    expect(offer!.holdSupported, isTrue);
    expect(offer.isExpired(now: DateTime.utc(2026, 4, 7, 12, 4, 0)), isFalse);
    expect(hold, isNotNull);
    expect(hold!.offerId, offer.offerId);
    expect(hold.status, CoachHoldStatus.active);
    expect(hold.seatAssignments.single.seatNumber, '4A');
  });

  test('offer rejects non-SYP currency', () {
    final offer = CoachOffer.fromJson(<String, Object?>{
      'offer_id': 'offer-1',
      'operator_id': 'op-1',
      'itinerary_id': 'iti-1',
      'currency': 'EUR',
      'total_minor_units': 4590,
      'seats_requested': 2,
      'hold_supported': true,
      'changeable': true,
      'refundable': false,
      'expires_at': '2026-04-07T12:05:00Z',
    });

    expect(offer, isNull);
  });

  test('booking lifecycle blocks unsafe status jumps', () {
    expect(
      coachBookingLifecycleCanTransition(
        from: CoachBookingLifecycleState.offerCreated,
        to: CoachBookingLifecycleState.holdCreated,
      ),
      isTrue,
    );
    expect(
      coachBookingLifecycleCanTransition(
        from: CoachBookingLifecycleState.paymentAuthorized,
        to: CoachBookingLifecycleState.ticketed,
      ),
      isFalse,
    );
    expect(
      coachBookingLifecycleCanTransition(
        from: CoachBookingLifecycleState.ticketed,
        to: CoachBookingLifecycleState.boarded,
      ),
      isTrue,
    );
    expect(
      coachBookingLifecycleCanTransition(
        from: CoachBookingLifecycleState.boarded,
        to: CoachBookingLifecycleState.refundRequested,
      ),
      isFalse,
    );
  });

  test('passenger manifests parse rider categories and nationality', () {
    final manifest = CoachPassengerManifest.fromJson(<String, Object?>{
      'passenger_id': 'adult_1',
      'given_name': 'Lina',
      'family_name': 'Haddad',
      'rider_category': 'student',
      'nationality_code': 'sy',
    });

    expect(manifest, isNotNull);
    expect(manifest!.displayName, 'Lina Haddad');
    expect(manifest.riderCategory, CoachPassengerRiderCategory.student);
    expect(manifest.nationalityCode, 'SY');

    final invalid = CoachPassengerManifest.fromJson(<String, Object?>{
      'passenger_id': 'adult_1',
      'given_name': 'Lina',
      'family_name': 'Haddad',
      'rider_category': 'vip',
    });
    expect(invalid, isNull);
  });

  test('refund eligibility and request records parse strict payout options',
      () {
    final eligibility = CoachRefundEligibility.fromJson(<String, Object?>{
      'booking_id': 'booking_demo_express_direct',
      'booking_state': 'ticketed',
      'refundable': true,
      'currency': 'SYP',
      'refund_cutoff_at': '2026-04-08T06:00:00Z',
      'recommended_kind': 'refund_credit',
      'tickets_void_required': true,
      'options': <Map<String, Object?>>[
        <String, Object?>{
          'kind': 'refund_credit',
          'label': 'Travel credit',
          'currency': 'SYP',
          'refund_minor_units': 9180,
          'fee_minor_units': 0,
          'expires_at': '2027-04-08T00:00:00Z',
        },
        <String, Object?>{
          'kind': 'original_payment',
          'label': 'Original payment',
          'currency': 'SYP',
          'refund_minor_units': 8190,
          'fee_minor_units': 990,
        },
      ],
    });

    expect(eligibility, isNotNull);
    expect(eligibility!.recommendedKind, CoachRefundKind.refundCredit);
    expect(
      eligibility.optionForKind(CoachRefundKind.originalPayment)?.feeMinorUnits,
      990,
    );

    final request = CoachRefundRequestRecord.fromJson(<String, Object?>{
      'refund_request_id': 'refundreq_demo_1',
      'booking_id': 'booking_demo_express_direct',
      'status': 'requested',
      'selected_kind': 'refund_credit',
      'currency': 'SYP',
      'requested_minor_units': 9180,
      'fee_minor_units': 0,
      'ticket_ids': <String>['ticket_demo_express_direct_1'],
      'reason': 'customer_change_of_plans',
      'created_at': '2026-04-07T13:00:00Z',
    });

    expect(request, isNotNull);
    expect(request!.selectedKind, CoachRefundKind.refundCredit);
    expect(request.ticketIds.single, 'ticket_demo_express_direct_1');
  });

  test('change eligibility and request records parse rebook quotes', () {
    final eligibility = CoachChangeEligibility.fromJson(<String, Object?>{
      'booking_id': 'booking_demo_express_direct',
      'booking_state': 'ticketed',
      'changeable': true,
      'change_cutoff_at': '2026-04-08T06:30:00Z',
      'options': <Map<String, Object?>>[
        <String, Object?>{
          'target_offer_id': 'offer_demo_express_midday',
          'journey_id': 'journey_demo_express_midday',
          'departure_at': '2026-04-08T12:00:00Z',
          'arrival_at': '2026-04-08T16:30:00Z',
          'currency': 'SYP',
          'fare_difference_minor_units': 800,
          'change_fee_minor_units': 500,
          'total_due_minor_units': 1300,
          'seat_map_available': true,
          'expires_at': '2026-04-07T14:00:00Z',
        },
      ],
    });

    expect(eligibility, isNotNull);
    expect(eligibility!.options.single.totalDueMinorUnits, 1300);

    final request = CoachChangeRequestRecord.fromJson(<String, Object?>{
      'change_request_id': 'changereq_demo_1',
      'booking_id': 'booking_demo_express_direct',
      'status': 'requested',
      'target_offer_id': 'offer_demo_express_midday',
      'currency': 'SYP',
      'fare_difference_minor_units': 800,
      'change_fee_minor_units': 500,
      'total_due_minor_units': 1300,
      'reason': 'move to midday departure',
      'created_at': '2026-04-07T13:05:00Z',
    });

    expect(request, isNotNull);
    expect(request!.targetOfferId, 'offer_demo_express_midday');
    expect(request.totalDueMinorUnits, 1300);
  });

  test('ticket and boarding parse as separate operational records', () {
    final ticket = CoachTicketCoupon.fromJson(<String, Object?>{
      'ticket_id': 'ticket-1',
      'booking_id': 'booking-1',
      'coupon_id': 'coupon-1',
      'passenger_id': 'pax-1',
      'segment_ids': <String>['seg-1'],
      'status': 'active',
      'operator_ticket_reference': 'op-ticket-1',
      'qr_payload_ref': 's3://tickets/ticket-1-qr',
      'artifacts': <Map<String, Object?>>[
        <String, Object?>{
          'artifact_id': 'ticketartifact-qr-1',
          'ticket_id': 'ticket-1',
          'booking_id': 'booking-1',
          'artifact_kind': 'qr',
          'delivery_channel': 'qr',
          'file_name': 'ticket-1-qr.svg',
          'mime_type': 'image/svg+xml',
          'content_length_bytes': 2048,
          'download_path': '/downloads/coach/tickets/ticketartifact-qr-1.svg',
        },
        <String, Object?>{
          'artifact_id': 'ticketartifact-pdf-1',
          'ticket_id': 'ticket-1',
          'booking_id': 'booking-1',
          'artifact_kind': 'pdf',
          'delivery_channel': 'pdf',
          'file_name': 'ticket-1.pdf',
          'mime_type': 'application/pdf',
          'content_length_bytes': 32768,
          'download_path': '/downloads/coach/tickets/ticketartifact-pdf-1.pdf',
        },
      ],
      'issued_at': '2026-04-07T12:06:00Z',
    });
    final boarding = CoachBoardingEvent.fromJson(<String, Object?>{
      'boarding_event_id': 'board-1',
      'ticket_id': 'ticket-1',
      'trip_id': 'trip-9',
      'scan_status': 'scanned',
      'captured_at': '2026-04-07T13:10:00Z',
      'offline_captured': true,
      'device_id': 'crew-device-3',
      'note': 'duplicate scan at gate',
    });

    expect(ticket, isNotNull);
    expect(ticket!.status, CoachTicketStatus.active);
    expect(ticket.operatorTicketReference, 'op-ticket-1');
    expect(ticket.artifacts.length, 2);
    expect(ticket.artifactByKind('pdf')!.downloadPath, contains('.pdf'));
    expect(boarding, isNotNull);
    expect(boarding!.scanStatus, CoachBoardingScanStatus.scanned);
    expect(boarding.offlineCaptured, isTrue);
    expect(boarding.note, 'duplicate scan at gate');
    expect(
      coachManifestBoardingStateFromWire('duplicate_attempt'),
      CoachManifestBoardingState.duplicateAttempt,
    );
  });

  test('settlement lines validate arithmetic and settlement basis', () {
    final valid = CoachSettlementLine.fromJson(<String, Object?>{
      'settlement_id': 'set-1',
      'operator_id': 'op-1',
      'booking_id': 'booking-1',
      'basis': 'refund_window_closed',
      'currency': 'SYP',
      'gross_minor_units': 10000,
      'commission_minor_units': 1200,
      'refund_minor_units': 1000,
      'chargeback_reserve_minor_units': 300,
      'manual_adjustment_minor_units': -200,
      'net_payable_minor_units': 7300,
    });

    expect(valid, isNotNull);
    expect(valid!.basis, CoachSettlementBasis.refundWindowClosed);
    expect(valid.expectedNetPayableMinorUnits, 7300);

    final invalid = CoachSettlementLine.fromJson(<String, Object?>{
      'settlement_id': 'set-1',
      'operator_id': 'op-1',
      'booking_id': 'booking-1',
      'basis': 'ticketed',
      'currency': 'SYP',
      'gross_minor_units': 10000,
      'commission_minor_units': 1200,
      'refund_minor_units': 1000,
      'chargeback_reserve_minor_units': 300,
      'manual_adjustment_minor_units': -200,
      'net_payable_minor_units': 7000,
    });

    expect(invalid, isNull);
  });

  test('ops queue status and urgency parse strict review semantics', () {
    expect(
      coachOpsQueueStatusFromWire('pending_review'),
      CoachOpsQueueStatus.pendingReview,
    );
    expect(
      coachOpsQueueStatusWireValue(CoachOpsQueueStatus.approved),
      'approved',
    );
    expect(
      coachOpsRequestUrgencyFromWire('high'),
      CoachOpsRequestUrgency.high,
    );
    expect(
      coachOpsRequestUrgencyWireValue(CoachOpsRequestUrgency.critical),
      'critical',
    );
    expect(coachOpsQueueStatusFromWire('waiting'), isNull);
  });
}
