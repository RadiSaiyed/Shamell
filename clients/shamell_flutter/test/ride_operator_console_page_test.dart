import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/dashboard_policy_scope.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_operator_console_page.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';

Widget _testApp(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

RideTrip _trip({
  required String rideId,
  required RideTripStatus status,
  required String pickup,
  required String destination,
  required String driverName,
  required String carPlate,
}) {
  return RideTrip(
    rideId: rideId,
    pickup: pickup,
    destination: destination,
    rideClass: 'economy',
    driverName: driverName,
    carPlate: carPlate,
    etaMinutes: 9,
    fareEstimateCents: 18500,
    status: status,
    createdAtIso: '2026-04-17T08:00:00Z',
    lastUpdatedAtIso: '2026-04-17T08:10:00Z',
  );
}

RideOperatorDriverRoster _driverRoster() {
  return const RideOperatorDriverRoster(
    generatedAtIso: '2026-04-17T10:30:00Z',
    drivers: <RideOperatorDriverRosterEntry>[
      RideOperatorDriverRosterEntry(
        driverAccountId: 'acct_driver_1',
        availabilityStatus: RideDriverAvailabilityStatus.online,
        lastSeenAtIso: '2026-04-17T10:29:50Z',
        updatedAtIso: '2026-04-17T10:29:50Z',
        location: null,
        driverName: 'Ahmad',
        carPlate: '123456',
        activeRideId: 'ride_active_1',
        activeTripStatus: RideTripStatus.driverAssigned,
        activePickup: 'Kafar Souseh',
        activeDestination: 'Bab Touma',
      ),
    ],
  );
}

RideOperatorDriverRoster _driverRosterWithIdleDriver() {
  return const RideOperatorDriverRoster(
    generatedAtIso: '2026-04-17T10:30:00Z',
    drivers: <RideOperatorDriverRosterEntry>[
      RideOperatorDriverRosterEntry(
        driverAccountId: 'acct_driver_1',
        availabilityStatus: RideDriverAvailabilityStatus.online,
        lastSeenAtIso: '2026-04-17T10:29:50Z',
        updatedAtIso: '2026-04-17T10:29:50Z',
        location: null,
        driverName: 'Ahmad',
        carPlate: '123456',
        activeRideId: 'ride_active_1',
        activeTripStatus: RideTripStatus.driverAssigned,
        activePickup: 'Kafar Souseh',
        activeDestination: 'Bab Touma',
      ),
      RideOperatorDriverRosterEntry(
        driverAccountId: 'acct_driver_2',
        availabilityStatus: RideDriverAvailabilityStatus.online,
        lastSeenAtIso: '2026-04-17T10:29:40Z',
        updatedAtIso: '2026-04-17T10:29:40Z',
        location: null,
        driverName: 'Lina',
        carPlate: '654321',
      ),
    ],
  );
}

RideOperatorDriverRoster _driverRosterForFleetSort() {
  return const RideOperatorDriverRoster(
    generatedAtIso: '2026-04-17T10:30:00Z',
    drivers: <RideOperatorDriverRosterEntry>[
      RideOperatorDriverRosterEntry(
        driverAccountId: 'acct_driver_zaid',
        availabilityStatus: RideDriverAvailabilityStatus.online,
        lastSeenAtIso: '2026-04-17T10:29:55Z',
        updatedAtIso: '2026-04-17T10:29:55Z',
        location: RideCoordinatePoint(lat: 33.5138, lon: 36.2765),
        driverName: 'Zaid',
        carPlate: '111111',
      ),
      RideOperatorDriverRosterEntry(
        driverAccountId: 'acct_driver_ahmad',
        availabilityStatus: RideDriverAvailabilityStatus.online,
        lastSeenAtIso: '2026-04-17T10:29:40Z',
        updatedAtIso: '2026-04-17T10:29:40Z',
        location: RideCoordinatePoint(lat: 33.5000, lon: 36.3000),
        driverName: 'Ahmad',
        carPlate: '222222',
      ),
    ],
  );
}

void main() {
  testWidgets('ride operator console consumes dashboard policy override',
      (tester) async {
    configureLargeViewport(tester);
    final board = RideOperatorLiveBoard(
      counts: const RideOperatorLiveCounts(
        openDispatches: 2,
        activeTrips: 1,
        enRouteTrips: 0,
        inProgressTrips: 1,
        paymentFailures: 0,
        onlineDrivers: 4,
      ),
      summary: const RideOperatorSummary(
        generatedAtIso: '2026-04-17T10:30:00Z',
        openDispatchValueMinorUnits: 41000,
        activeTripValueMinorUnits: 22000,
        completedTodayCount: 9,
        completedTodayValueMinorUnits: 126000,
        avgOpenEtaSeconds: 420,
        avgActiveEtaSeconds: 510,
        activeDriverCount: 1,
        idleOnlineDrivers: 3,
        driverUtilizationBps: 2500,
        capacityGapDispatches: 1,
        stalledDispatches: 0,
        overdueArrivals: 0,
        longRunningTrips: 0,
        silentTrackingTrips: 0,
        metadataGaps: 0,
        classBreakdown: <RideOperatorServiceClassSummary>[],
        alerts: <RideOperatorAlert>[],
      ),
      openDispatches: <RideTrip>[
        _trip(
          rideId: 'ride_open_policy',
          status: RideTripStatus.rideRequested,
          pickup: 'Mazzeh',
          destination: 'Abu Rummaneh',
          driverName: '',
          carPlate: '',
        ),
      ],
      activeTrips: <RideTrip>[
        _trip(
          rideId: 'ride_active_policy',
          status: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(
        RideOperatorConsolePage(
          baseUrl: 'https://api.example.com',
          bootstrapOnInit: false,
          dashboardPolicyOverride: const ShamellDashboardPolicy(
            baseUrl: 'https://api.example.com',
            privilegeSnapshot: AccountPrivilegeSnapshot(
              isSuperadmin: true,
            ),
            capabilities: ShamellCapabilities.conservativeDefaults,
          ),
          initialBoard: board,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Command desk'), findsOneWidget);
    expect(
      find.text(
          'This account is authorized for the live ride operations board.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'This account is not yet authorized. Grant a ride-operations role before using this console.',
      ),
      findsNothing,
    );
  });

  testWidgets('ride operator console surfaces command desk priorities',
      (tester) async {
    configureLargeViewport(tester);
    final board = RideOperatorLiveBoard(
      counts: const RideOperatorLiveCounts(
        openDispatches: 7,
        activeTrips: 4,
        enRouteTrips: 2,
        inProgressTrips: 2,
        paymentFailures: 3,
        onlineDrivers: 11,
      ),
      summary: const RideOperatorSummary(
        generatedAtIso: '2026-04-17T10:30:00Z',
        openDispatchValueMinorUnits: 125000,
        activeTripValueMinorUnits: 93000,
        completedTodayCount: 28,
        completedTodayValueMinorUnits: 481000,
        avgOpenEtaSeconds: 540,
        avgActiveEtaSeconds: 720,
        activeDriverCount: 4,
        idleOnlineDrivers: 7,
        driverUtilizationBps: 3600,
        capacityGapDispatches: 3,
        stalledDispatches: 2,
        overdueArrivals: 1,
        longRunningTrips: 1,
        silentTrackingTrips: 0,
        metadataGaps: 0,
        classBreakdown: <RideOperatorServiceClassSummary>[],
        alerts: <RideOperatorAlert>[],
      ),
      openDispatches: <RideTrip>[
        _trip(
          rideId: 'ride_open_1',
          status: RideTripStatus.rideRequested,
          pickup: 'Mazzeh',
          destination: 'Abu Rummaneh',
          driverName: '',
          carPlate: '',
        ),
      ],
      activeTrips: <RideTrip>[
        _trip(
          rideId: 'ride_active_1',
          status: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
        ),
      ],
    );
    final caseQueue = RideOperatorCaseQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorCaseQueueTotals(
        openCases: 6,
        criticalCases: 2,
        highCases: 3,
        financeCases: 2,
        supportCases: 2,
        complianceCases: 2,
      ),
      cases: const <RideOperatorCaseItem>[
        RideOperatorCaseItem(
          caseId: 'case_1',
          category: RideOperatorCaseCategory.finance,
          severity: RideOperatorAlertSeverity.critical,
          title: 'Payout dispute escalated',
          detail: 'Driver reports a blocked payout after a completed ride.',
          suggestedAction: 'Review finance hold and release manually.',
          rideId: 'ride_active_1',
          rideClass: 'economy',
          status: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
          fareEstimateMinorUnits: 18500,
          ageSeconds: 5100,
          createdAtIso: '2026-04-17T09:05:00Z',
          lastUpdatedAtIso: '2026-04-17T10:20:00Z',
        ),
      ],
    );
    final supportQueue = RideOperatorSupportQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorSupportQueueTotals(
        openTickets: 5,
        urgentTickets: 2,
      ),
      tickets: const <RideSupportTicket>[
        RideSupportTicket(
          ticketId: 'ticket_1',
          rideId: 'ride_active_1',
          riderAccountId: 'acct_rider_1',
          category: RideSupportTicketCategory.safety,
          subject: 'Driver did not follow requested route',
          body: 'Customer reported a detour and requested an urgent callback.',
          preferredContact: RideSupportTicketContactPreference.phone,
          status: RideSupportTicketStatus.open,
          resolutionNote: null,
          resolvedByAccountId: null,
          resolvedAtIso: null,
          rideClass: 'economy',
          tripStatus: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
          createdAtIso: '2026-04-17T09:45:00Z',
          updatedAtIso: '2026-04-17T10:15:00Z',
        ),
      ],
    );
    final documentQueue = RideOperatorDocumentQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorDocumentQueueTotals(
        pendingDocuments: 4,
        rejectedDocuments: 1,
        expiredDocuments: 2,
        blockedDrivers: 3,
      ),
      documents: const <RideDriverDocument>[
        RideDriverDocument(
          documentId: 'doc_1',
          driverAccountId: 'acct_driver_1',
          documentType: RideDriverDocumentType.insurance,
          documentNumberMasked: 'INS-***-921',
          issuingCountry: 'SY',
          status: RideDriverDocumentStatus.pending,
          submittedAtIso: '2026-04-17T08:40:00Z',
          reviewedAtIso: null,
          expiresAtIso: '2026-08-01T00:00:00Z',
          reviewNote: 'Needs manual validation before driver can go online.',
        ),
      ],
    );
    final financeQueue = RideOperatorFinanceQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      feeWalletId: 'wallet_fee_1',
      totals: const RideOperatorFinanceQueueTotals(
        pendingRequests: 4,
        pendingAmountMinorUnits: 91000,
        approvedRequests: 1,
        blockedRequests: 1,
        oldestPendingAgeSeconds: 4200,
        reservedFeeEvents: 2,
        releasedFeeEvents: 1,
        settledFeeEvents: 3,
      ),
      requests: const <RidePayoutRequest>[
        RidePayoutRequest(
          requestId: 'payout_1',
          fromWalletId: 'wallet_driver_1',
          toWalletId: 'wallet_bank_1',
          amountMinorUnits: 42000,
          currency: 'SYP',
          message: 'Daily payout',
          status: RidePayoutRequestStatus.pending,
          createdAtIso: '2026-04-17T09:20:00Z',
          ageSeconds: 4200,
        ),
      ],
      recentReserveEvents: const <RideDriverReserveEvent>[],
    );

    await tester.pumpWidget(
      _testApp(
        RideOperatorConsolePage(
          bootstrapOnInit: false,
          privilegeSnapshotOverride:
              const AccountPrivilegeSnapshot(isSuperadmin: true),
          initialBoard: board,
          initialCaseQueue: caseQueue,
          initialSupportQueue: supportQueue,
          initialDocumentQueue: documentQueue,
          initialFinanceQueue: financeQueue,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Command desk'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Dispatch capacity gap'), findsWidgets);
    expect(find.text('Trips slipping SLA'), findsOneWidget);
    expect(find.text('Critical case queue'), findsOneWidget);
    expect(find.text('Urgent customer tickets'), findsOneWidget);
    expect(find.text('Driver compliance blockers'), findsOneWidget);
    expect(find.text('Payout approvals waiting'), findsOneWidget);
    expect(find.text('Payment failures live'), findsOneWidget);
    expect(find.text('Pending payouts'), findsOneWidget);
    expect(find.text('Inspect dispatches'), findsOneWidget);
    expect(find.text('Review cases'), findsOneWidget);
    expect(find.text('Review support'), findsOneWidget);
    expect(find.text('Review documents'), findsOneWidget);
    expect(find.text('Check payouts'), findsOneWidget);
  });

  testWidgets('ride operator console filters workspace sections locally',
      (tester) async {
    configureLargeViewport(tester);
    final board = RideOperatorLiveBoard(
      counts: const RideOperatorLiveCounts(
        openDispatches: 7,
        activeTrips: 4,
        enRouteTrips: 2,
        inProgressTrips: 2,
        paymentFailures: 3,
        onlineDrivers: 11,
      ),
      summary: const RideOperatorSummary(
        generatedAtIso: '2026-04-17T10:30:00Z',
        openDispatchValueMinorUnits: 125000,
        activeTripValueMinorUnits: 93000,
        completedTodayCount: 28,
        completedTodayValueMinorUnits: 481000,
        avgOpenEtaSeconds: 540,
        avgActiveEtaSeconds: 720,
        activeDriverCount: 4,
        idleOnlineDrivers: 7,
        driverUtilizationBps: 3600,
        capacityGapDispatches: 3,
        stalledDispatches: 2,
        overdueArrivals: 1,
        longRunningTrips: 1,
        silentTrackingTrips: 0,
        metadataGaps: 0,
        classBreakdown: <RideOperatorServiceClassSummary>[],
        alerts: <RideOperatorAlert>[],
      ),
      openDispatches: <RideTrip>[
        _trip(
          rideId: 'ride_open_1',
          status: RideTripStatus.rideRequested,
          pickup: 'Mazzeh',
          destination: 'Abu Rummaneh',
          driverName: '',
          carPlate: '',
        ),
      ],
      activeTrips: <RideTrip>[
        _trip(
          rideId: 'ride_active_1',
          status: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
        ),
      ],
    );
    final caseQueue = RideOperatorCaseQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorCaseQueueTotals(
        openCases: 6,
        criticalCases: 2,
        highCases: 3,
        financeCases: 2,
        supportCases: 2,
        complianceCases: 2,
      ),
      cases: const <RideOperatorCaseItem>[
        RideOperatorCaseItem(
          caseId: 'case_1',
          category: RideOperatorCaseCategory.finance,
          severity: RideOperatorAlertSeverity.critical,
          title: 'Payout dispute escalated',
          detail: 'Driver reports a blocked payout after a completed ride.',
          suggestedAction: 'Review finance hold and release manually.',
          rideId: 'ride_active_1',
          rideClass: 'economy',
          status: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
          fareEstimateMinorUnits: 18500,
          ageSeconds: 5100,
          createdAtIso: '2026-04-17T09:05:00Z',
          lastUpdatedAtIso: '2026-04-17T10:20:00Z',
        ),
      ],
    );
    final supportQueue = RideOperatorSupportQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorSupportQueueTotals(
        openTickets: 5,
        urgentTickets: 2,
      ),
      tickets: const <RideSupportTicket>[
        RideSupportTicket(
          ticketId: 'ticket_1',
          rideId: 'ride_active_1',
          riderAccountId: 'acct_rider_1',
          category: RideSupportTicketCategory.safety,
          subject: 'Driver did not follow requested route',
          body: 'Customer reported a detour and requested an urgent callback.',
          preferredContact: RideSupportTicketContactPreference.phone,
          status: RideSupportTicketStatus.open,
          resolutionNote: null,
          resolvedByAccountId: null,
          resolvedAtIso: null,
          rideClass: 'economy',
          tripStatus: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
          createdAtIso: '2026-04-17T09:45:00Z',
          updatedAtIso: '2026-04-17T10:15:00Z',
        ),
      ],
    );
    final documentQueue = RideOperatorDocumentQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorDocumentQueueTotals(
        pendingDocuments: 4,
        rejectedDocuments: 1,
        expiredDocuments: 2,
        blockedDrivers: 3,
      ),
      documents: const <RideDriverDocument>[
        RideDriverDocument(
          documentId: 'doc_1',
          driverAccountId: 'acct_driver_1',
          documentType: RideDriverDocumentType.insurance,
          documentNumberMasked: 'INS-***-921',
          issuingCountry: 'SY',
          status: RideDriverDocumentStatus.pending,
          submittedAtIso: '2026-04-17T08:40:00Z',
          reviewedAtIso: null,
          expiresAtIso: '2026-08-01T00:00:00Z',
          reviewNote: 'Needs manual validation before driver can go online.',
        ),
      ],
    );
    final financeQueue = RideOperatorFinanceQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      feeWalletId: 'wallet_fee_1',
      totals: const RideOperatorFinanceQueueTotals(
        pendingRequests: 4,
        pendingAmountMinorUnits: 91000,
        approvedRequests: 1,
        blockedRequests: 1,
        oldestPendingAgeSeconds: 4200,
        reservedFeeEvents: 2,
        releasedFeeEvents: 1,
        settledFeeEvents: 3,
      ),
      requests: const <RidePayoutRequest>[
        RidePayoutRequest(
          requestId: 'payout_1',
          fromWalletId: 'wallet_driver_1',
          toWalletId: 'wallet_bank_1',
          amountMinorUnits: 42000,
          currency: 'SYP',
          message: 'Daily payout',
          status: RidePayoutRequestStatus.pending,
          createdAtIso: '2026-04-17T09:20:00Z',
          ageSeconds: 4200,
        ),
      ],
      recentReserveEvents: const <RideDriverReserveEvent>[],
    );

    Widget buildConsole([Key? pageKey]) {
      return _testApp(
        RideOperatorConsolePage(
          key: pageKey,
          bootstrapOnInit: false,
          privilegeSnapshotOverride:
              const AccountPrivilegeSnapshot(isSuperadmin: true),
          initialBoard: board,
          initialDriverRoster: _driverRoster(),
          initialCaseQueue: caseQueue,
          initialSupportQueue: supportQueue,
          initialDocumentQueue: documentQueue,
          initialFinanceQueue: financeQueue,
        ),
      );
    }

    await tester.pumpWidget(buildConsole());

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Workspace focus'), findsOneWidget);
    expect(find.text('Showing 6 of 6 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_fleet')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rideOpsWorkspace_cases')),
      500,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_cases')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rideOpsWorkspace_support')),
      500,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_support')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rideOpsWorkspace_documents')),
      500,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_documents')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rideOpsWorkspace_payouts')),
      500,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_payouts')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rideOpsWorkspace_dispatches')),
      500,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_dispatches')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      buildConsole(const ValueKey('rideOpsConsoleFilterReset')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final supportFocusFinder =
        find.byKey(const ValueKey('rideOpsWorkspaceFocus_support'));
    await tester.tap(supportFocusFinder);
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 6 workspaces'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rideOpsWorkspace_support')),
      500,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_dispatches')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_fleet')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_cases')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_documents')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_payouts')),
      findsNothing,
    );

    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();

    final allFocusFinder =
        find.byKey(const ValueKey('rideOpsWorkspaceFocus_all'));
    await tester.tap(allFocusFinder);
    await tester.pumpAndSettle();

    expect(find.text('Showing 6 of 6 workspaces'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rideOpsWorkspace_dispatches')),
      500,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_dispatches')),
      findsOneWidget,
    );
  });

  testWidgets('ride operator console sorts and remembers support desk locally',
      (tester) async {
    configureLargeViewport(tester);
    final supportQueue = RideOperatorSupportQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorSupportQueueTotals(
        openTickets: 2,
        urgentTickets: 1,
      ),
      tickets: const <RideSupportTicket>[
        RideSupportTicket(
          ticketId: 'ticket_general',
          rideId: 'ride_active_1',
          riderAccountId: 'acct_rider_1',
          category: RideSupportTicketCategory.bookingIssue,
          subject: 'General follow-up needed',
          body: 'Customer requested a routine booking callback.',
          preferredContact: RideSupportTicketContactPreference.phone,
          status: RideSupportTicketStatus.open,
          resolutionNote: null,
          resolvedByAccountId: null,
          resolvedAtIso: null,
          rideClass: 'economy',
          tripStatus: RideTripStatus.driverAssigned,
          pickup: 'Mazzeh',
          destination: 'Abu Rummaneh',
          driverName: 'Ahmad',
          carPlate: '123456',
          createdAtIso: '2026-04-17T09:50:00Z',
          updatedAtIso: '2026-04-17T10:20:00Z',
        ),
        RideSupportTicket(
          ticketId: 'ticket_safety',
          rideId: 'ride_active_2',
          riderAccountId: 'acct_rider_2',
          category: RideSupportTicketCategory.safety,
          subject: 'Safety callback escalated',
          body: 'Customer requested immediate safety review.',
          preferredContact: RideSupportTicketContactPreference.phone,
          status: RideSupportTicketStatus.open,
          resolutionNote: null,
          resolvedByAccountId: null,
          resolvedAtIso: null,
          rideClass: 'economy',
          tripStatus: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Lina',
          carPlate: '654321',
          createdAtIso: '2026-04-17T09:40:00Z',
          updatedAtIso: '2026-04-17T10:10:00Z',
        ),
      ],
    );
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return _testApp(
        PageStorage(
          bucket: bucket,
          child: RideOperatorConsolePage(
            key: const PageStorageKey<String>('rideOperatorConsoleSupportSort'),
            bootstrapOnInit: false,
            privilegeSnapshotOverride:
                const AccountPrivilegeSnapshot(isSuperadmin: true),
            initialSupportQueue: supportQueue,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSort_support_priority')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSort_support_latest')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsWorkspaceSort_support_priority')),
          )
          .selected,
      isTrue,
    );

    final prioritySafetyDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsSupportTicket_ticket_safety')))
        .dy;
    final priorityGeneralDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsSupportTicket_ticket_general')))
        .dy;
    expect(prioritySafetyDy, lessThan(priorityGeneralDy));

    await tester.tap(
      find.byKey(const ValueKey('rideOpsWorkspaceSort_support_latest')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsWorkspaceSort_support_latest')),
          )
          .selected,
      isTrue,
    );
    final latestGeneralDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsSupportTicket_ticket_general')))
        .dy;
    final latestSafetyDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsSupportTicket_ticket_safety')))
        .dy;
    expect(latestGeneralDy, lessThan(latestSafetyDy));

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsWorkspaceSort_support_latest')),
          )
          .selected,
      isTrue,
    );
    final restoredGeneralDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsSupportTicket_ticket_general')))
        .dy;
    final restoredSafetyDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsSupportTicket_ticket_safety')))
        .dy;
    expect(restoredGeneralDy, lessThan(restoredSafetyDy));
  });

  testWidgets('ride operator console sorts and remembers fleet desk locally',
      (tester) async {
    configureLargeViewport(tester);
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return _testApp(
        PageStorage(
          bucket: bucket,
          child: RideOperatorConsolePage(
            key: const PageStorageKey<String>('rideOperatorConsoleFleetSort'),
            bootstrapOnInit: false,
            privilegeSnapshotOverride:
                const AccountPrivilegeSnapshot(isSuperadmin: true),
            initialDriverRoster: _driverRosterForFleetSort(),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSort_fleet_attention')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSort_fleet_name')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsWorkspaceSort_fleet_attention')),
          )
          .selected,
      isTrue,
    );

    final defaultZaidDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsDriver_acct_driver_zaid')))
        .dy;
    final defaultAhmadDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsDriver_acct_driver_ahmad')))
        .dy;
    expect(defaultZaidDy, lessThan(defaultAhmadDy));

    await tester.tap(
      find.byKey(const ValueKey('rideOpsWorkspaceSort_fleet_name')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsWorkspaceSort_fleet_name')),
          )
          .selected,
      isTrue,
    );
    final nameAhmadDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsDriver_acct_driver_ahmad')))
        .dy;
    final nameZaidDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsDriver_acct_driver_zaid')))
        .dy;
    expect(nameAhmadDy, lessThan(nameZaidDy));

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsWorkspaceSort_fleet_name')),
          )
          .selected,
      isTrue,
    );
    final restoredAhmadDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsDriver_acct_driver_ahmad')))
        .dy;
    final restoredZaidDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('rideOpsDriver_acct_driver_zaid')))
        .dy;
    expect(restoredAhmadDy, lessThan(restoredZaidDy));
  });

  testWidgets('ride operator console remembers workspace focus',
      (tester) async {
    configureLargeViewport(tester);
    final supportQueue = RideOperatorSupportQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorSupportQueueTotals(
        openTickets: 2,
        urgentTickets: 1,
      ),
      tickets: const <RideSupportTicket>[
        RideSupportTicket(
          ticketId: 'ticket_1',
          rideId: 'ride_active_1',
          riderAccountId: 'acct_rider_1',
          category: RideSupportTicketCategory.safety,
          subject: 'Driver did not follow requested route',
          body: 'Customer reported a detour and requested an urgent callback.',
          preferredContact: RideSupportTicketContactPreference.phone,
          status: RideSupportTicketStatus.open,
          resolutionNote: null,
          resolvedByAccountId: null,
          resolvedAtIso: null,
          rideClass: 'economy',
          tripStatus: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
          createdAtIso: '2026-04-17T09:45:00Z',
          updatedAtIso: '2026-04-17T10:15:00Z',
        ),
      ],
    );
    final documentQueue = RideOperatorDocumentQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorDocumentQueueTotals(
        pendingDocuments: 1,
        rejectedDocuments: 0,
        expiredDocuments: 1,
        blockedDrivers: 1,
      ),
      documents: const <RideDriverDocument>[
        RideDriverDocument(
          documentId: 'doc_1',
          driverAccountId: 'acct_driver_1',
          documentType: RideDriverDocumentType.insurance,
          documentNumberMasked: 'INS-***-921',
          issuingCountry: 'SY',
          status: RideDriverDocumentStatus.pending,
          submittedAtIso: '2026-04-17T08:40:00Z',
          reviewedAtIso: null,
          expiresAtIso: '2026-08-01T00:00:00Z',
          reviewNote: 'Needs manual validation before driver can go online.',
        ),
      ],
    );
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return _testApp(
        PageStorage(
          bucket: bucket,
          child: RideOperatorConsolePage(
            key: const PageStorageKey<String>('rideOperatorConsolePage'),
            bootstrapOnInit: false,
            privilegeSnapshotOverride:
                const AccountPrivilegeSnapshot(isSuperadmin: true),
            initialSupportQueue: supportQueue,
            initialDocumentQueue: documentQueue,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_support_open')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_support_safety')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_documents')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_documents_pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_documents_blocked')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('rideOpsWorkspaceFocus_support')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_support_open')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_documents')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_documents_pending')),
      findsNothing,
    );

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspace_documents')),
      findsNothing,
    );
  });

  testWidgets('ride operator console collapses and expands visible workspaces',
      (tester) async {
    configureLargeViewport(tester);
    final supportQueue = RideOperatorSupportQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorSupportQueueTotals(
        openTickets: 2,
        urgentTickets: 1,
      ),
      tickets: const <RideSupportTicket>[
        RideSupportTicket(
          ticketId: 'ticket_1',
          rideId: 'ride_active_1',
          riderAccountId: 'acct_rider_1',
          category: RideSupportTicketCategory.safety,
          subject: 'Driver did not follow requested route',
          body: 'Customer reported a detour and requested an urgent callback.',
          preferredContact: RideSupportTicketContactPreference.phone,
          status: RideSupportTicketStatus.open,
          resolutionNote: null,
          resolvedByAccountId: null,
          resolvedAtIso: null,
          rideClass: 'economy',
          tripStatus: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
          createdAtIso: '2026-04-17T09:45:00Z',
          updatedAtIso: '2026-04-17T10:15:00Z',
        ),
      ],
    );
    final documentQueue = RideOperatorDocumentQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorDocumentQueueTotals(
        pendingDocuments: 1,
        rejectedDocuments: 0,
        expiredDocuments: 1,
        blockedDrivers: 1,
      ),
      documents: const <RideDriverDocument>[
        RideDriverDocument(
          documentId: 'doc_1',
          driverAccountId: 'acct_driver_1',
          documentType: RideDriverDocumentType.insurance,
          documentNumberMasked: 'INS-***-921',
          issuingCountry: 'SY',
          status: RideDriverDocumentStatus.pending,
          submittedAtIso: '2026-04-17T08:40:00Z',
          reviewedAtIso: null,
          expiresAtIso: '2026-08-01T00:00:00Z',
          reviewNote: 'Needs manual validation before driver can go online.',
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(
        RideOperatorConsolePage(
          bootstrapOnInit: false,
          privilegeSnapshotOverride:
              const AccountPrivilegeSnapshot(isSuperadmin: true),
          initialSupportQueue: supportQueue,
          initialDocumentQueue: documentQueue,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_documents')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('rideOpsWorkspaceToggle_support')));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 1 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_support')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceCollapsed_support')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('rideOpsCollapseVisible')));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 2 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_documents')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceCollapsed_documents')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('rideOpsExpandVisible')));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_documents')),
      findsOneWidget,
    );
  });

  testWidgets('ride operator console remembers collapsed workspaces',
      (tester) async {
    configureLargeViewport(tester);
    final supportQueue = RideOperatorSupportQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorSupportQueueTotals(
        openTickets: 2,
        urgentTickets: 1,
      ),
      tickets: const <RideSupportTicket>[
        RideSupportTicket(
          ticketId: 'ticket_1',
          rideId: 'ride_active_1',
          riderAccountId: 'acct_rider_1',
          category: RideSupportTicketCategory.safety,
          subject: 'Driver did not follow requested route',
          body: 'Customer reported a detour and requested an urgent callback.',
          preferredContact: RideSupportTicketContactPreference.phone,
          status: RideSupportTicketStatus.open,
          resolutionNote: null,
          resolvedByAccountId: null,
          resolvedAtIso: null,
          rideClass: 'economy',
          tripStatus: RideTripStatus.driverAssigned,
          pickup: 'Kafar Souseh',
          destination: 'Bab Touma',
          driverName: 'Ahmad',
          carPlate: '123456',
          createdAtIso: '2026-04-17T09:45:00Z',
          updatedAtIso: '2026-04-17T10:15:00Z',
        ),
      ],
    );
    final documentQueue = RideOperatorDocumentQueue(
      generatedAtIso: '2026-04-17T10:30:00Z',
      totals: const RideOperatorDocumentQueueTotals(
        pendingDocuments: 1,
        rejectedDocuments: 0,
        expiredDocuments: 1,
        blockedDrivers: 1,
      ),
      documents: const <RideDriverDocument>[
        RideDriverDocument(
          documentId: 'doc_1',
          driverAccountId: 'acct_driver_1',
          documentType: RideDriverDocumentType.insurance,
          documentNumberMasked: 'INS-***-921',
          issuingCountry: 'SY',
          status: RideDriverDocumentStatus.pending,
          submittedAtIso: '2026-04-17T08:40:00Z',
          reviewedAtIso: null,
          expiresAtIso: '2026-08-01T00:00:00Z',
          reviewNote: 'Needs manual validation before driver can go online.',
        ),
      ],
    );
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return _testApp(
        PageStorage(
          bucket: bucket,
          child: RideOperatorConsolePage(
            key: const PageStorageKey<String>(
              'rideOperatorConsoleCollapsedWorkspacesPage',
            ),
            bootstrapOnInit: false,
            privilegeSnapshotOverride:
                const AccountPrivilegeSnapshot(isSuperadmin: true),
            initialSupportQueue: supportQueue,
            initialDocumentQueue: documentQueue,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('rideOpsWorkspaceToggle_documents')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 1 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_documents')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceCollapsed_documents')),
      findsOneWidget,
    );

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 1 of 2 workspaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceBody_documents')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceCollapsed_documents')),
      findsOneWidget,
    );
  });

  testWidgets('ride operator console remembers fleet filter', (tester) async {
    configureLargeViewport(tester);
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return _testApp(
        PageStorage(
          bucket: bucket,
          child: RideOperatorConsolePage(
            key: const PageStorageKey<String>(
              'rideOperatorConsoleFleetFilterPage',
            ),
            bootstrapOnInit: false,
            privilegeSnapshotOverride:
                const AccountPrivilegeSnapshot(isSuperadmin: true),
            initialDriverRoster: _driverRosterWithIdleDriver(),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2 drivers in the current view.'),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_fleet_online')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_fleet_idle')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsFleetFilter_all')),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('rideOpsFleetFilter_idle')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 2 drivers in the current view.'),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('rideOpsWorkspaceSignal_fleet_stale')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsFleetFilter_idle')),
          )
          .selected,
      isTrue,
    );

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 2 drivers in the current view.'),
        findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('rideOpsFleetFilter_idle')),
          )
          .selected,
      isTrue,
    );
  });
}
