import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';

void main() {
  test('rider wallet snapshot enforces strict bucket segregation', () {
    final valid = RiderWalletSnapshot.fromJson(<String, Object?>{
      'rider_id': 'rider-1',
      'buckets': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'cash_balance',
          'currency': 'SYP',
          'balance_minor_units': 120000,
        },
        <String, Object?>{
          'type': 'promo_credit',
          'currency': 'SYP',
          'balance_minor_units': 4000,
        },
        <String, Object?>{
          'type': 'refund_credit',
          'currency': 'SYP',
          'balance_minor_units': 2500,
        },
      ],
    });
    expect(valid, isNotNull);
    expect(valid!.hasStrictBucketSegregation(), isTrue);
    expect(valid.bucketBalance(RideWalletBucketType.cashBalance), 120000);
    expect(valid.bucketBalance(RideWalletBucketType.promoCredit), 4000);

    final duplicateBucket = RiderWalletSnapshot.fromJson(<String, Object?>{
      'rider_id': 'rider-1',
      'buckets': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'cash_balance',
          'currency': 'SYP',
          'balance_minor_units': 120000,
        },
        <String, Object?>{
          'type': 'cash_balance',
          'currency': 'SYP',
          'balance_minor_units': 3000,
        },
      ],
    });
    expect(duplicateBucket, isNull);
  });

  test('rider wallet snapshot rejects non-SYP currency', () {
    final invalid = RiderWalletSnapshot.fromJson(<String, Object?>{
      'rider_id': 'rider-1',
      'buckets': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'cash_balance',
          'currency': 'EUR',
          'balance_minor_units': 120000,
        },
      ],
    });

    expect(invalid, isNull);
  });

  test('driver ledger net payout excludes reserve', () {
    const snapshot = DriverLedgerSnapshot(
      driverId: 'drv-1',
      earningsAvailableMinorUnits: 150000,
      heldReserveMinorUnits: 25000,
      debtMinorUnits: 12000,
      payoutPendingMinorUnits: 5000,
      bonusesMinorUnits: 10000,
      cashCollectedMinorUnits: 30000,
    );
    expect(snapshot.netAvailableForPayoutMinorUnits, 135000);
  });

  test('role permissions include expected least-privilege grants', () {
    final support = rideDefaultPermissionsForRole(RideOperatorRole.supportL1);
    expect(support, <RideAdminPermission>{RideAdminPermission.manageTickets});

    final finance = rideDefaultPermissionsForRole(RideOperatorRole.finance);
    expect(finance.contains(RideAdminPermission.managePayouts), isTrue);
    expect(finance.contains(RideAdminPermission.issueRefunds), isTrue);
    expect(finance.contains(RideAdminPermission.configurePlatform), isFalse);
  });

  test('support access excludes marketing-only and read-only observer roles',
      () {
    expect(shamellHasRideSupportAccess(const <String>['support_l1']), isTrue);
    expect(
      shamellHasRideSupportAccess(const <String>['finance', 'marketing']),
      isTrue,
    );
    expect(
      shamellHasRideSupportAccess(const <String>[
        'marketing',
        'bi_audit_read_only',
      ]),
      isFalse,
    );
  });

  test(
      'sensitive finance and compliance access stay narrower than queue access',
      () {
    expect(
      shamellHasRideFinanceSensitiveAccess(const <String>['finance']),
      isTrue,
    );
    expect(
        shamellHasRideFinanceSensitiveAccess(const <String>['ops']), isFalse);
    expect(
      shamellHasRideComplianceSensitiveAccess(const <String>[
        'compliance_risk',
      ]),
      isTrue,
    );
    expect(
      shamellHasRideComplianceSensitiveAccess(const <String>['driver_ops']),
      isFalse,
    );
  });

  test('audit action requires normalized reason code', () {
    const ok = RideAuditAction(
      actorId: 'ops-1',
      actorRole: RideOperatorRole.supportL2,
      action: 'ticket_refund_issued',
      reasonCode: 'duplicate_charge',
      targetType: 'ride',
      targetId: 'ride_42',
      createdAtIso: '2026-03-31T12:00:00Z',
    );
    expect(ok.isWriteSafe, isTrue);

    const invalid = RideAuditAction(
      actorId: 'ops-1',
      actorRole: RideOperatorRole.supportL2,
      action: 'ticket_refund_issued',
      reasonCode: 'Duplicate-Charge',
      targetType: 'ride',
      targetId: 'ride_42',
      createdAtIso: '2026-03-31T12:00:00Z',
    );
    expect(invalid.isWriteSafe, isFalse);
  });

  test('driver finance dashboard accepts optional payout wallet id', () {
    final dashboard = RideDriverFinanceDashboard.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T12:20:00Z',
      'wallet_id': 'WALLET123',
      'platform_payout_wallet_id': 'FEE-WALLET-1',
      'ledger': <String, Object?>{
        'driver_id': 'driver-1',
        'earnings_available_minor_units': 25000,
        'held_reserve_minor_units': 4000,
        'debt_minor_units': 1500,
        'payout_pending_minor_units': 0,
        'bonuses_minor_units': 1200,
        'cash_collected_minor_units': 500,
      },
      'completed_today_count': 9,
      'completed_today_value_minor_units': 48200,
      'active_trip_value_minor_units': 6200,
      'net_available_minor_units': 22200,
      'recommended_reserve_minor_units': 4820,
      'recommended_payout_minor_units': 17880,
      'pending_settlement_minor_units': 4000,
      'reserve_coverage_bps': 8298,
      'payout_blocked': false,
      'alerts': const <Map<String, Object?>>[],
      'recent_completed_trips': const <Map<String, Object?>>[],
      'recent_reserve_events': <Map<String, Object?>>[
        <String, Object?>{
          'ride_id': 'ride-1',
          'wallet_id': 'WALLET123',
          'amount_minor_units': 4000,
          'status': 'reserved',
          'reserved_at': '2026-04-02T12:18:00Z',
          'updated_at': '2026-04-02T12:18:00Z',
        },
      ],
    });

    expect(dashboard, isNotNull);
    expect(dashboard!.platformPayoutWalletId, 'FEE-WALLET-1');
    expect(dashboard.recentReserveEvents.single.status, 'reserved');
  });

  test('driver shift summary parses online duration and alerts', () {
    final summary = RideDriverShiftSummary.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T12:40:00Z',
      'online': true,
      'last_seen_at': '2026-04-02T12:39:30Z',
      'last_online_at': '2026-04-02T10:10:00Z',
      'current_online_duration_seconds': 9000,
      'open_dispatches_visible': 4,
      'active_trip_count': 1,
      'completed_today_count': 6,
      'completed_today_value_minor_units': 28100,
      'payment_failed_count': 1,
      'avg_completed_eta_seconds': 780,
      'last_completed_at': '2026-04-02T12:15:00Z',
      'alerts': <Map<String, Object?>>[
        <String, Object?>{
          'code': 'driver_shift_payment_failures',
          'severity': 'high',
          'title': 'A completed fare still needs payment recovery',
          'detail':
              '1 rides are still blocked in payment_failed and may delay payout settlement.',
        },
      ],
    });

    expect(summary, isNotNull);
    expect(summary!.online, isTrue);
    expect(summary.currentOnlineDurationSeconds, 9000);
    expect(summary.openDispatchesVisible, 4);
    expect(summary.alerts.single.severity, RideOperatorAlertSeverity.high);
  });

  test('operator pricing policy dashboard parses editable rules', () {
    final dashboard =
        RideOperatorPricingPolicyDashboard.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T13:30:00Z',
      'policies': <Map<String, Object?>>[
        <String, Object?>{
          'ride_class': 'economy',
          'base_fare_minor_units': 700,
          'per_km_minor_units': 130,
          'per_minute_minor_units': 35,
          'traffic_delay_per_minute_minor_units': 18,
          'booking_fee_minor_units': 150,
          'minimum_fare_minor_units': 1100,
          'driver_share_bps': 8200,
          'updated_at': '2026-04-02T13:20:00Z',
          'updated_by_account_id': 'ops-1',
        },
      ],
    });

    expect(dashboard, isNotNull);
    expect(dashboard!.policies.single.rideClass, 'economy');
    expect(dashboard.policies.single.driverShareBps, 8200);
    expect(dashboard.policies.single.updatedByAccountId, 'ops-1');
  });

  test('operator live summary parses capacity metrics', () {
    final board = RideOperatorLiveBoard.fromJson(<String, Object?>{
      'counts': <String, Object?>{
        'open_dispatches': 3,
        'active_trips': 6,
        'en_route_trips': 2,
        'in_progress_trips': 2,
        'payment_failures': 1,
        'online_drivers': 5,
      },
      'summary': <String, Object?>{
        'generated_at': '2026-04-02T14:15:00Z',
        'open_dispatch_value_minor_units': 6300,
        'active_trip_value_minor_units': 18400,
        'completed_today_count': 12,
        'completed_today_value_minor_units': 44100,
        'avg_open_eta_seconds': 420,
        'avg_active_eta_seconds': 760,
        'active_driver_count': 4,
        'idle_online_drivers': 1,
        'driver_utilization_bps': 8000,
        'capacity_gap_dispatches': 2,
        'stalled_dispatches': 1,
        'overdue_arrivals': 0,
        'long_running_trips': 1,
        'silent_tracking_trips': 1,
        'metadata_gaps': 0,
        'class_breakdown': const <Map<String, Object?>>[],
        'alerts': const <Map<String, Object?>>[],
      },
      'open_dispatches': const <Map<String, Object?>>[],
      'active_trips': const <Map<String, Object?>>[],
    });

    expect(board, isNotNull);
    expect(board!.summary, isNotNull);
    expect(board.summary!.activeDriverCount, 4);
    expect(board.summary!.idleOnlineDrivers, 1);
    expect(board.summary!.driverUtilizationBps, 8000);
    expect(board.summary!.capacityGapDispatches, 2);
  });

  test('operator driver roster parses idle and active drivers', () {
    final roster = RideOperatorDriverRoster.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T14:20:00Z',
      'drivers': <Map<String, Object?>>[
        <String, Object?>{
          'driver_account_id': 'driver-1',
          'availability_status': 'online',
          'last_seen_at': '2026-04-02T14:19:30Z',
          'last_online_at': '2026-04-02T13:50:00Z',
          'updated_at': '2026-04-02T14:19:30Z',
          'driver_name': 'Maya',
          'car_plate': 'BA-1586',
          'active_ride_id': 'ride-1',
          'active_trip_status': 'trip_in_progress',
          'active_pickup': 'Mazzeh',
          'active_destination': 'Airport',
        },
        <String, Object?>{
          'driver_account_id': 'driver-2',
          'availability_status': 'offline',
          'last_seen_at': '2026-04-02T13:15:00Z',
          'updated_at': '2026-04-02T13:15:00Z',
        },
      ],
    });

    expect(roster, isNotNull);
    expect(roster!.drivers, hasLength(2));
    expect(roster.drivers.first.isOnline, isTrue);
    expect(roster.drivers.first.isIdleOnline, isFalse);
    expect(
        roster.drivers.first.activeTripStatus, RideTripStatus.tripInProgress);
    expect(roster.drivers.last.isOnline, isFalse);
  });

  test('operator finance queue parses payout requests and totals', () {
    final queue = RideOperatorFinanceQueue.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T12:25:00Z',
      'fee_wallet_id': 'FEE-WALLET-1',
      'totals': <String, Object?>{
        'pending_requests': 2,
        'pending_amount_minor_units': 54000,
        'approved_requests': 3,
        'blocked_requests': 1,
        'oldest_pending_age_seconds': 1800,
        'reserved_fee_events': 2,
        'released_fee_events': 1,
        'settled_fee_events': 3,
      },
      'requests': <Map<String, Object?>>[
        <String, Object?>{
          'request_id': 'req_1',
          'from_wallet_id': 'driver_wallet_1',
          'to_wallet_id': 'FEE-WALLET-1',
          'amount_minor_units': 12000,
          'currency': 'SYP',
          'message': 'ride_driver_payout',
          'status': 'pending',
          'created_at': '2026-04-02T12:00:00Z',
          'age_seconds': 600,
        },
      ],
      'recent_reserve_events': <Map<String, Object?>>[
        <String, Object?>{
          'ride_id': 'ride-1',
          'wallet_id': 'driver_wallet_1',
          'amount_minor_units': 1200,
          'status': 'settled',
          'settled_at': '2026-04-02T12:10:00Z',
        },
      ],
    });

    expect(queue, isNotNull);
    expect(queue!.totals.pendingRequests, 2);
    expect(queue.totals.settledFeeEvents, 3);
    expect(queue.requests.single.status, RidePayoutRequestStatus.pending);
    expect(queue.requests.single.isPending, isTrue);
    expect(queue.recentReserveEvents.single.status, 'settled');
  });

  test('operator finance queue parser accepts redacted identifiers', () {
    final queue = RideOperatorFinanceQueue.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T12:25:00Z',
      'fee_wallet_id': null,
      'totals': <String, Object?>{
        'pending_requests': 1,
        'pending_amount_minor_units': 12000,
        'approved_requests': 0,
        'blocked_requests': 0,
        'oldest_pending_age_seconds': 600,
        'reserved_fee_events': 1,
        'released_fee_events': 0,
        'settled_fee_events': 0,
      },
      'requests': <Map<String, Object?>>[
        <String, Object?>{
          'request_id': null,
          'from_wallet_id': null,
          'to_wallet_id': null,
          'amount_minor_units': 12000,
          'currency': 'SYP',
          'message': 'ride_driver_payout',
          'status': 'pending',
          'created_at': '2026-04-02T12:00:00Z',
          'age_seconds': 600,
        },
      ],
      'recent_reserve_events': <Map<String, Object?>>[
        <String, Object?>{
          'ride_id': 'ride-1',
          'wallet_id': null,
          'amount_minor_units': 1200,
          'status': 'reserved',
          'reserved_at': '2026-04-02T12:10:00Z',
        },
      ],
    });

    expect(queue, isNotNull);
    expect(queue!.feeWalletId, isNull);
    expect(queue.requests.single.requestId, isNull);
    expect(queue.requests.single.fromWalletId, isNull);
    expect(queue.recentReserveEvents.single.walletId, isNull);
  });

  test('support ticket and operator support queue parse open workflow', () {
    final queue = RideOperatorSupportQueue.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T14:10:00Z',
      'totals': <String, Object?>{
        'open_tickets': 3,
        'urgent_tickets': 1,
      },
      'tickets': <Map<String, Object?>>[
        <String, Object?>{
          'ticket_id': 'rst_123',
          'ride_id': 'RIDE-1',
          'rider_account_id': 'rider-1',
          'category': 'payment_issue',
          'subject': 'Payment issue · RIDE-1',
          'body': 'Driver charged cash after wallet preauth.',
          'preferred_contact': 'in_app',
          'status': 'open',
          'resolution_note': null,
          'resolved_by_account_id': null,
          'resolved_at': null,
          'ride_class': 'economy',
          'trip_status': 'payment_failed',
          'pickup': 'Umayyad Square',
          'destination': 'Bab Touma',
          'driver_name': 'Maya',
          'car_plate': 'BA-1586',
          'created_at': '2026-04-02T14:00:00Z',
          'updated_at': '2026-04-02T14:05:00Z',
        },
      ],
    });

    expect(queue, isNotNull);
    expect(queue!.totals.urgentTickets, 1);
    expect(
        queue.tickets.single.category, RideSupportTicketCategory.paymentIssue);
    expect(queue.tickets.single.status, RideSupportTicketStatus.open);
    expect(queue.tickets.single.preferredContact,
        RideSupportTicketContactPreference.inApp);
  });

  test('support ticket parser accepts redacted internal account identifiers',
      () {
    final ticket = RideSupportTicket.fromJson(<String, Object?>{
      'ticket_id': 'rst_456',
      'ride_id': 'RIDE-2',
      'category': 'safety',
      'subject': 'Safety follow-up',
      'body': 'Driver could not find the pickup point.',
      'preferred_contact': 'phone',
      'status': 'open',
      'resolved_at': null,
      'ride_class': 'economy',
      'trip_status': 'driver_arriving',
      'pickup': 'Abu Rummaneh',
      'destination': 'Malki',
      'driver_name': 'Maya',
      'car_plate': 'BA-1586',
      'created_at': '2026-04-02T14:00:00Z',
      'updated_at': '2026-04-02T14:05:00Z',
    });

    expect(ticket, isNotNull);
    expect(ticket!.riderAccountId, isNull);
    expect(ticket.resolvedByAccountId, isNull);
    expect(ticket.category, RideSupportTicketCategory.safety);
  });

  test('driver document dashboard parses blocking and readiness state', () {
    final dashboard = RideDriverDocumentDashboard.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T12:45:00Z',
      'driver_account_id': 'driver-1',
      'summary': <String, Object?>{
        'missing_documents': 1,
        'pending_documents': 1,
        'approved_documents': 1,
        'rejected_documents': 1,
        'expired_documents': 0,
        'blocking_issues': 3,
        'ready_to_drive': false,
      },
      'documents': <Map<String, Object?>>[
        <String, Object?>{
          'document_id': 'ride_doc_1',
          'driver_account_id': 'driver-1',
          'document_type': 'driver_license',
          'document_number_masked': '••••1234',
          'issuing_country': 'SY',
          'status': 'approved',
          'submitted_at': '2026-04-01T10:00:00Z',
          'reviewed_at': '2026-04-01T11:00:00Z',
          'expires_at': '2027-04-01T00:00:00Z',
          'review_note': '',
        },
        <String, Object?>{
          'document_id': null,
          'driver_account_id': 'driver-1',
          'document_type': 'insurance',
          'document_number_masked': null,
          'issuing_country': null,
          'status': 'missing',
          'submitted_at': null,
          'reviewed_at': null,
          'expires_at': null,
          'review_note': null,
        },
      ],
    });

    expect(dashboard, isNotNull);
    expect(dashboard!.summary.blockingIssues, 3);
    expect(dashboard.summary.readyToDrive, isFalse);
    expect(dashboard.documents.first.documentType,
        RideDriverDocumentType.driverLicense);
    expect(dashboard.documents.first.status, RideDriverDocumentStatus.approved);
    expect(dashboard.documents.last.isBlocking, isTrue);
  });

  test('driver document parser accepts redacted operator identity fields', () {
    final document = RideDriverDocument.fromJson(<String, Object?>{
      'document_id': 'ride_doc_2',
      'driver_account_id': null,
      'document_type': 'insurance',
      'document_number_masked': '••••7890',
      'issuing_country': 'SY',
      'status': 'pending',
      'submitted_at': '2026-04-02T09:00:00Z',
      'reviewed_at': null,
      'expires_at': '2027-01-01T00:00:00Z',
      'review_note': null,
    });

    expect(document, isNotNull);
    expect(document!.driverAccountId, isNull);
    expect(document.status, RideDriverDocumentStatus.pending);
  });

  test('operator document queue parses compliance workload', () {
    final queue = RideOperatorDocumentQueue.fromJson(<String, Object?>{
      'generated_at': '2026-04-02T12:50:00Z',
      'totals': <String, Object?>{
        'pending_documents': 4,
        'rejected_documents': 2,
        'expired_documents': 1,
        'blocked_drivers': 5,
      },
      'documents': <Map<String, Object?>>[
        <String, Object?>{
          'document_id': 'ride_doc_2',
          'driver_account_id': 'driver-2',
          'document_type': 'insurance',
          'document_number_masked': '••••7890',
          'issuing_country': 'SY',
          'status': 'pending',
          'submitted_at': '2026-04-02T09:00:00Z',
          'reviewed_at': null,
          'expires_at': '2027-01-01T00:00:00Z',
          'review_note': null,
        },
      ],
    });

    expect(queue, isNotNull);
    expect(queue!.totals.pendingDocuments, 4);
    expect(queue.totals.blockedDrivers, 5);
    expect(queue.documents.single.status, RideDriverDocumentStatus.pending);
  });

  test('ride role helpers enforce separated driver operator finance access',
      () {
    expect(shamellHasRideDriverAccess(const <String>['driver']), isTrue);
    expect(shamellHasRideDriverAccess(const <String>['support_l1']), isFalse);

    expect(shamellHasRideOperatorAccess(const <String>['support_l1']), isTrue);
    expect(shamellHasRideOperatorAccess(const <String>['driver']), isFalse);

    expect(shamellHasRideFinanceAccess(const <String>['finance']), isTrue);
    expect(shamellHasRideFinanceAccess(const <String>['support_l2']), isFalse);

    expect(shamellHasRideComplianceAccess(const <String>['compliance_risk']),
        isTrue);
    expect(shamellHasRideComplianceAccess(const <String>['finance']), isFalse);

    expect(shamellHasRidePricingAccess(const <String>['city_manager']), isTrue);
    expect(shamellHasRidePricingAccess(const <String>['finance']), isFalse);
  });

  test('ride snapshot helpers allow permission-only operator surfaces', () {
    const snapshot = AccountPrivilegeSnapshot(
      permissions: <String>[
        'rides.operator.read',
        'rides.support.read',
        'rides.finance.read',
      ],
      products: <String>['rides'],
    );

    expect(shamellHasRideOperatorSnapshotAccess(snapshot), isTrue);
    expect(shamellHasRideSupportSnapshotAccess(snapshot), isTrue);
    expect(shamellHasRideFinanceSnapshotAccess(snapshot), isTrue);
    expect(shamellHasRideDriverSnapshotAccess(snapshot), isFalse);
  });

  test('ride snapshot helpers allow permission-only driver accounts', () {
    const snapshot = AccountPrivilegeSnapshot(
      permissions: <String>['rides.driver.read'],
      products: <String>['rides'],
    );

    expect(shamellHasRideDriverSnapshotAccess(snapshot), isTrue);
    expect(shamellHasRideOperatorSnapshotAccess(snapshot), isFalse);
  });

  test('ride snapshot helpers fail closed for missing sensitive grants', () {
    const financeSnapshot = AccountPrivilegeSnapshot(
      roles: <String>['finance'],
      permissions: <String>['rides.finance.read'],
      products: <String>['rides'],
    );
    const complianceSnapshot = AccountPrivilegeSnapshot(
      roles: <String>['compliance_risk'],
      permissions: <String>['rides.compliance.read'],
      products: <String>['rides'],
    );

    expect(
      shamellHasRideFinanceSensitiveSnapshotAccess(financeSnapshot),
      isFalse,
    );
    expect(
      shamellHasRideComplianceSensitiveSnapshotAccess(complianceSnapshot),
      isFalse,
    );
    expect(shamellHasRideFinanceSnapshotAccess(financeSnapshot), isTrue);
    expect(shamellHasRideComplianceSnapshotAccess(complianceSnapshot), isTrue);
  });
}
