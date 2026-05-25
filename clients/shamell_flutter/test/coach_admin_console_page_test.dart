import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/coach_bus/coach_admin_console_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';
import 'package:shamell_flutter/core/dashboard_policy_scope.dart';

Future<void> _dragUntilTextVisible(
  WidgetTester tester,
  String text,
) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeCoachAdminApi extends CoachMobilityApi {
  _FakeCoachAdminApi() : super(baseUrl: 'https://api.shamell.online');

  int overviewCalls = 0;
  int financeJournalCalls = 0;
  int shamellPayReconciliationCalls = 0;
  int riskDashboardCalls = 0;
  int disruptionsCalls = 0;

  @override
  Future<CoachAdminOverviewResponse> adminOverview({int limit = 8}) async {
    overviewCalls++;
    return CoachAdminOverviewResponse(
      generatedAtIso: '2026-04-13T10:30:00Z',
      liveOpsSummary: const CoachAdminLiveOpsSummary(
        tripCount: 3,
        boardedPassengers: 18,
        pendingBoardingPassengers: 5,
        needsAttentionPassengers: 2,
      ),
      departures: const CoachCrewDepartureBoardResponse(
        generatedAtIso: '2026-04-13T10:30:00Z',
        departures: <CoachCrewTripSummary>[
          CoachCrewTripSummary(
            tripId: 'trip_demo_express_direct',
            journeyId: 'journey_demo_express_direct',
            bookingId: 'booking_demo_express_direct',
            operatorName: 'Demo Express',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: '2026-04-13T08:00:00Z',
            arrivalAtIso: '2026-04-13T12:30:00Z',
            boardingOpensAtIso: '2026-04-13T07:20:00Z',
            boardingClosesAtIso: '2026-04-13T07:55:00Z',
            gateLabel: 'Bay A4',
            vehicleLabel: 'Bus DX-402',
            manifestCount: 12,
            boardedCount: 8,
            deniedCount: 0,
            noShowCount: 1,
            pendingCount: 3,
          ),
        ],
      ),
      disruptionSummary: const CoachAdminDisruptionSummary(
        tripCount: 3,
        scheduledTrips: 1,
        monitoringTrips: 1,
        actionRequiredTrips: 1,
        resolvedTrips: 0,
        delayedTrips: 1,
        cancelledTrips: 1,
        criticalTrips: 1,
        affectedBookingCount: 3,
        eligibleReaccommodationCount: 2,
        queuedReaccommodationCount: 1,
      ),
      supportSummary: const CoachAdminSupportSummary(
        pendingReviewCount: 4,
        urgentRequestCount: 2,
        openRefundRequests: 3,
        openChangeRequests: 2,
      ),
      refundQueue: const CoachOperatorRefundQueueResponse(
        generatedAtIso: '2026-04-13T10:30:00Z',
        totals: CoachOperatorRefundQueueTotals(
          openRequests: 3,
          pendingReview: 2,
          approved: 1,
          rejected: 0,
          creditRequests: 2,
          cashRequests: 1,
        ),
        requests: <CoachOperatorRefundQueueEntry>[
          CoachOperatorRefundQueueEntry(
            refundRequestId: 'refund_1',
            bookingId: 'booking_demo_express_direct',
            journeyId: 'journey_demo_express_direct',
            operatorName: 'Demo Express',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: '2026-04-13T08:00:00Z',
            arrivalAtIso: '2026-04-13T12:30:00Z',
            bookingState: CoachBookingLifecycleState.ticketed,
            requestStatus: 'submitted',
            selectedKind: CoachRefundKind.refundCredit,
            currency: 'SYP',
            requestedMinorUnits: 9180,
            feeMinorUnits: 0,
            ticketIds: <String>['ticket_1'],
            reason: 'schedule issue',
            requestedAtIso: '2026-04-13T06:30:00Z',
            queueStatus: CoachOpsQueueStatus.pendingReview,
            urgency: CoachOpsRequestUrgency.high,
            suggestedAction: 'Review before departure',
            reviewedAtIso: null,
            reviewedByAccountId: null,
            reviewNote: null,
          ),
        ],
      ),
      changeQueue: const CoachOperatorChangeQueueResponse(
        generatedAtIso: '2026-04-13T10:30:00Z',
        totals: CoachOperatorChangeQueueTotals(
          openRequests: 2,
          pendingReview: 2,
          approved: 0,
          rejected: 0,
          collectionRequiredRequests: 1,
          zeroDueRequests: 1,
        ),
        requests: <CoachOperatorChangeQueueEntry>[
          CoachOperatorChangeQueueEntry(
            changeRequestId: 'change_1',
            bookingId: 'booking_demo_border_runner',
            journeyId: 'journey_demo_border_runner_morning',
            operatorName: 'Border Runner',
            from: 'Homs',
            to: 'Amman',
            departureAtIso: '2026-04-13T05:30:00Z',
            arrivalAtIso: '2026-04-13T12:15:00Z',
            bookingState: CoachBookingLifecycleState.ticketed,
            requestStatus: 'submitted',
            targetOfferId: 'offer_demo_border_runner_evening',
            targetJourneyId: 'journey_demo_border_runner_evening',
            currency: 'SYP',
            fareDifferenceMinorUnits: 800,
            changeFeeMinorUnits: 500,
            totalDueMinorUnits: 1300,
            reason: 'move to evening departure',
            requestedAtIso: '2026-04-13T03:20:00Z',
            queueStatus: CoachOpsQueueStatus.pendingReview,
            urgency: CoachOpsRequestUrgency.critical,
            suggestedAction: 'Escalate to operator desk',
            reviewedAtIso: null,
            reviewedByAccountId: null,
            reviewNote: null,
          ),
        ],
      ),
      financeSummary: const CoachAdminFinanceSummary(
        currency: 'SYP',
        statementCount: 2,
        queuedPayoutRuns: 1,
        failedPayoutRuns: 0,
        netPayableMinorUnits: 12750,
      ),
      reconciliation: const CoachOperatorReconciliationResponse(
        generatedAtIso: '2026-04-13T10:30:00Z',
        summary: CoachOperatorReconciliationSummary(
          currency: 'SYP',
          tripCount: 3,
          manifestPassengers: 23,
          boardedPassengers: 18,
          pendingBoardingPassengers: 5,
          needsAttentionPassengers: 2,
          pendingReviewRequests: 4,
          reviewedRequests: 1,
          approvedCreditRefundMinorUnits: 9180,
          approvedCashRefundMinorUnits: 0,
          approvedCollectionDueMinorUnits: 1300,
        ),
        tripSnapshots: <CoachOperatorReconciliationTripSnapshot>[],
        reviewHistory: <CoachOperatorReconciliationHistoryEntry>[],
      ),
      settlementStatements: const CoachOperatorSettlementStatementsResponse(
        generatedAtIso: '2026-04-13T10:30:00Z',
        statements: <CoachOperatorSettlementStatement>[
          CoachOperatorSettlementStatement(
            statementId: 'settlement_op_demo_express_2026w15',
            operatorId: 'op_demo_express',
            operatorName: 'Demo Express',
            currency: 'SYP',
            periodStartIso: '2026-04-07T00:00:00Z',
            periodEndIso: '2026-04-13T23:59:59Z',
            nextPayoutAtIso: '2026-04-14T10:00:00Z',
            status: 'ready_for_payout',
            downloadFormats: <String>['csv'],
            totals: CoachOperatorSettlementStatementTotals(
              lineCount: 2,
              grossMinorUnits: 18000,
              commissionMinorUnits: 2160,
              refundMinorUnits: 9180,
              chargebackReserveMinorUnits: 200,
              manualAdjustmentMinorUnits: 0,
              netPayableMinorUnits: 6460,
            ),
            lines: <CoachSettlementLine>[],
          ),
        ],
      ),
      payoutRuns: const CoachOperatorPayoutRunsResponse(
        generatedAtIso: '2026-04-13T10:30:00Z',
        summary: CoachOperatorPayoutRunSummary(
          currency: 'SYP',
          queuedRuns: 1,
          paidRuns: 0,
          failedRuns: 0,
          queuedStatementCount: 2,
          queuedNetPayableMinorUnits: 12750,
          paidNetPayableMinorUnits: 0,
        ),
        runs: <CoachOperatorPayoutRun>[
          CoachOperatorPayoutRun(
            payoutRunId: 'payout_run_1',
            status: 'queued',
            currency: 'SYP',
            statementIds: <String>['settlement_op_demo_express_2026w15'],
            operatorIds: <String>['op_demo_express'],
            operatorNames: <String>['Demo Express'],
            statementCount: 1,
            grossMinorUnits: 18000,
            reserveMinorUnits: 200,
            netPayableMinorUnits: 6460,
            createdAtIso: '2026-04-13T09:30:00Z',
            paidAtIso: null,
            createdByAccountId: 'acct_admin',
            paidByAccountId: null,
            paymentReference: null,
            note: 'weekly settlement',
            availableExportFormats: <String>['csv'],
            exports: <CoachOperatorPayoutExport>[],
          ),
        ],
      ),
      feedHealth: const CoachOperatorFeedHealthResponse(
        generatedAtIso: '2026-04-13T10:30:00Z',
        summary: CoachOperatorFeedHealthSummary(
          operatorsTotal: 2,
          healthyOperators: 1,
          degradedFeeds: 1,
          staleFeeds: 1,
        ),
        feeds: <CoachOperatorFeedHealth>[
          CoachOperatorFeedHealth(
            operatorId: 'op_demo_express',
            operatorName: 'Demo Express',
            operatorIntegrationMode: 'hybrid',
            feedKind: 'gtfs_rt_trip_updates',
            sourceKind: 'gtfs_rt',
            syncStatus: 'ok',
            freshnessStatus: 'fresh',
            lastAttemptedAtIso: '2026-04-13T10:25:00Z',
            lastSucceededAtIso: '2026-04-13T10:25:00Z',
            freshnessExpiresAtIso: '2026-04-13T10:26:30Z',
            recordsIngested: 4,
            errorMessage: null,
          ),
          CoachOperatorFeedHealth(
            operatorId: 'op_border_runner',
            operatorName: 'Border Runner',
            operatorIntegrationMode: 'api',
            feedKind: 'siri',
            sourceKind: 'siri',
            syncStatus: 'degraded',
            freshnessStatus: 'stale',
            lastAttemptedAtIso: '2026-04-13T10:10:00Z',
            lastSucceededAtIso: '2026-04-13T09:40:00Z',
            freshnessExpiresAtIso: '2026-04-13T09:41:30Z',
            recordsIngested: 0,
            errorMessage: 'timeout on realtime pull',
          ),
        ],
      ),
    );
  }

  @override
  Future<CoachAdminFinanceJournalResponse> adminFinanceJournal({
    String? query,
    int limit = 20,
  }) async {
    financeJournalCalls++;
    return const CoachAdminFinanceJournalResponse(
      generatedAtIso: '2026-04-13T10:45:00Z',
      summary: CoachAdminFinanceJournalSummary(
        currency: 'SYP',
        totalEntries: 2,
        attentionEntries: 0,
        accrualEntries: 1,
        adjustmentEntries: 0,
        payoutEntries: 1,
        pspClearingMinorUnits: 11540,
        operatorPayableMinorUnits: 0,
        platformRevenueMinorUnits: 2160,
        chargebackReserveMinorUnits: 200,
        travelCreditLiabilityMinorUnits: 0,
        cashRefundPayableMinorUnits: 0,
        customerReceivableMinorUnits: 0,
        settlementInTransitMinorUnits: 6460,
      ),
      entries: <CoachAdminFinanceJournalEntry>[
        CoachAdminFinanceJournalEntry(
          entryId: 'journal_payout_created_1',
          occurredAtIso: '2026-04-13T09:30:00Z',
          eventType: 'payout_run_created',
          title: 'Payout run created',
          status: 'queued',
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          bookingId: null,
          statementId: 'settlement_op_demo_express_2026w15',
          payoutRunId: 'payout_run_1',
          requestId: null,
          importId: null,
          referenceLabel: 'Payout run payout_run_1',
          currency: 'SYP',
          primaryAmountMinorUnits: 6460,
          needsAttention: false,
          nextAction: 'Funds are reserved for external payout execution.',
          detailLines: <String>[
            'Statements settlement_op_demo_express_2026w15',
          ],
          accountMovements: <CoachAdminFinanceAccountMovement>[
            CoachAdminFinanceAccountMovement(
              accountCode: 'operator_payable',
              accountLabel: 'Operator payable',
              direction: 'decrease',
              amountMinorUnits: 6460,
              signedMinorUnits: -6460,
            ),
            CoachAdminFinanceAccountMovement(
              accountCode: 'settlement_in_transit',
              accountLabel: 'Settlement in transit',
              direction: 'increase',
              amountMinorUnits: 6460,
              signedMinorUnits: 6460,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<CoachAdminShamellPayReconciliationResponse>
      adminShamellPayReconciliation({
    String? query,
    int limit = 20,
  }) async {
    shamellPayReconciliationCalls++;
    return const CoachAdminShamellPayReconciliationResponse(
      generatedAtIso: '2026-04-13T10:48:00Z',
      summary: CoachAdminShamellPayReconciliationSummary(
        currency: 'SYP',
        totalRuns: 2,
        reconciledRuns: 1,
        awaitingShamellPayRuns: 1,
        operatorRailPendingRuns: 0,
        failedRuns: 0,
        statusMismatchRuns: 0,
        escalatedRuns: 0,
        attentionRuns: 1,
        expectedNetPayableMinorUnits: 12750,
        reconciledNetPayableMinorUnits: 6290,
        attentionNetPayableMinorUnits: 6460,
        shamellPayClearingMinorUnits: 11540,
        settlementInTransitMinorUnits: 6460,
      ),
      runs: <CoachAdminShamellPayReconciliationRun>[
        CoachAdminShamellPayReconciliationRun(
          entryId: 'shamell_pay_reconciliation_payout_run_1',
          occurredAtIso: '2026-04-13T09:45:00Z',
          payoutRunId: 'payout_run_1',
          statementIds: <String>['settlement_op_demo_express_2026w15'],
          operatorIds: <String>['op_demo_express'],
          operatorNames: <String>['Demo Express'],
          currency: 'SYP',
          runStatus: 'queued',
          shamellPayStatus: 'missing_report',
          downstreamStatus: 'queued',
          reconciliationStatus: 'awaiting_shamell_pay',
          latestShamellPayImportId: null,
          latestDownstreamImportId: 'import_bank_1',
          paymentReference: 'shpay_batch_2026w15',
          externalReference: 'bank_file_2026w15',
          shamellPayAttempts: <CoachOperatorPayoutImport>[],
          downstreamAttempts: <CoachOperatorPayoutImport>[
            CoachOperatorPayoutImport(
              importId: 'import_bank_1',
              importBatchId: null,
              payoutRunId: 'payout_run_1',
              importSource: 'bank_report',
              externalStatus: 'queued',
              paymentReference: 'shpay_batch_2026w15',
              externalReference: 'bank_file_2026w15',
              importedAtIso: '2026-04-13T09:45:00Z',
              importedByAccountId: 'acct_finance_demo',
              previousRunStatus: 'queued',
              appliedRunStatus: 'queued',
              note: 'Operator rail still queued.',
            ),
          ],
          downstreamAttemptCount: 1,
          downstreamFailedAttemptCount: 0,
          escalated: false,
          escalationSeverity: null,
          escalationReason: null,
          expectedNetPayableMinorUnits: 6460,
          needsAttention: true,
          nextAction:
              'Import SyrChat Pay report before releasing operator rail.',
          detailLines: <String>[
            'No SyrChat Pay report attached for payout_run_1',
          ],
        ),
      ],
    );
  }

  @override
  Future<CoachAdminRiskDashboardResponse> adminRiskDashboard({
    String? query,
    int limit = 20,
  }) async {
    riskDashboardCalls++;
    return const CoachAdminRiskDashboardResponse(
      generatedAtIso: '2026-04-13T10:50:00Z',
      summary: CoachAdminRiskSummary(
        openRisks: 3,
        activeRisks: 2,
        acknowledgedRisks: 1,
        snoozedRisks: 0,
        ownedRisks: 1,
        criticalRisks: 1,
        financeAlerts: 1,
        supportAlerts: 1,
        partnerAlerts: 1,
        boardingAlerts: 0,
      ),
      risks: <CoachAdminRiskItem>[
        CoachAdminRiskItem(
          riskId: 'risk_payout_run_1',
          category: 'finance',
          severity: 'critical',
          title: 'Payout run failed',
          status: 'failed',
          detectedAtIso: '2026-04-13T10:40:00Z',
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          bookingId: null,
          statementId: 'settlement_op_demo_express_2026w15',
          payoutRunId: 'payout_run_1',
          tripId: null,
          referenceLabel: 'Payout run payout_run_1',
          currency: 'SYP',
          amountMinorUnits: 6460,
          nextAction: 'Requeue payout after bank review.',
          workflowStatus: 'active',
          ownerAccountId: null,
          ownerTeam: null,
          suggestedTeam: 'finance_ops',
          routingSource: 'shamell_pay_reconciliation',
          routingReason:
              'Failed payout runs should stay with finance operations until the operator rail is confirmed.',
          snoozedUntilIso: null,
          snoozeReason: null,
          workflowUpdatedAtIso: null,
          workflowUpdatedByAccountId: null,
          workflowNote: null,
          detailLines: <String>[
            'Statements settlement_op_demo_express_2026w15',
          ],
        ),
      ],
    );
  }

  @override
  Future<CoachAdminDisruptionsResponse> adminDisruptions({
    String? query,
    String? workflowStatus,
    String? disruptionKind,
    int limit = 20,
  }) async {
    disruptionsCalls++;
    return const CoachAdminDisruptionsResponse(
      generatedAtIso: '2026-04-13T10:55:00Z',
      summary: CoachAdminDisruptionSummary(
        tripCount: 1,
        scheduledTrips: 0,
        monitoringTrips: 0,
        actionRequiredTrips: 1,
        resolvedTrips: 0,
        delayedTrips: 0,
        cancelledTrips: 1,
        criticalTrips: 1,
        affectedBookingCount: 1,
        eligibleReaccommodationCount: 1,
        queuedReaccommodationCount: 1,
      ),
      trips: <CoachAdminDisruptionTrip>[
        CoachAdminDisruptionTrip(
          tripId: 'trip_demo_express_direct',
          journeyId: 'journey_demo_express_direct',
          bookingId: 'booking_demo_express_direct',
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          gateLabel: 'Bay A4',
          vehicleLabel: 'Bus DX-402',
          manifestCount: 12,
          boardedCount: 8,
          deniedCount: 0,
          noShowCount: 1,
          pendingCount: 3,
          workflowStatus: 'action_required',
          disruptionKind: 'cancelled',
          delayMinutes: null,
          severity: 'critical',
          affectedBookingCount: 1,
          eligibleReaccommodationCount: 1,
          queuedReaccommodationCount: 1,
          feedIssueCount: 1,
          lastAction: 'queue_reaccommodation',
          updatedAtIso: '2026-04-13T10:54:00Z',
          updatedByAccountId: 'acct_admin',
          reason: 'service was cancelled by operator',
          note: 'Queued change request for affected ticket.',
          blockers: <String>['timeout on realtime pull'],
          nextAction: 'Monitor the reissue queue and operator confirmation',
        ),
      ],
    );
  }
}

void main() {
  testWidgets('coach admin console consumes inherited dashboard policy',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellDashboardPolicyScope(
          policy: const ShamellDashboardPolicy(
            baseUrl: 'https://api.shamell.online',
            privilegeSnapshot: AccountPrivilegeSnapshot(
              permissions: <String>['coach.admin.read'],
              products: <String>['coach'],
            ),
            capabilities: ShamellCapabilities.conservativeDefaults,
          ),
          child: CoachAdminConsolePage(
            baseUrl: 'https://api.shamell.online',
            api: api,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Coach admin'), findsOneWidget);
    expect(
      find.text(
          'This account is not allowed to access the coach admin console.'),
      findsNothing,
    );
    expect(api.overviewCalls, 1);
  });

  testWidgets('coach admin console consumes dashboard policy override',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          dashboardPolicyOverride: const ShamellDashboardPolicy(
            baseUrl: 'https://api.shamell.online',
            privilegeSnapshot: AccountPrivilegeSnapshot(
              permissions: <String>['coach.admin.read'],
              products: <String>['coach'],
            ),
            capabilities: ShamellCapabilities.conservativeDefaults,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Coach admin'), findsOneWidget);
    expect(
      find.text(
          'This account is not allowed to access the coach admin console.'),
      findsNothing,
    );
    expect(api.overviewCalls, 1);
  });

  testWidgets('coach admin console renders overview sections', (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminApi();
    final overview = await api.adminOverview();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialOverview: overview,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
            operatorIds: <String>[],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.overviewCalls, greaterThanOrEqualTo(1));
    expect(find.text('Coach admin'), findsOneWidget);
    expect(find.text('Realtime board'), findsOneWidget);
    expect(find.text('Live ops'), findsOneWidget);
    expect(find.textContaining('Bay A4'), findsOneWidget);
    expect(find.textContaining('Reaccommodation 1'), findsOneWidget);
    expect(find.text('Support'), findsWidgets);
    expect(find.textContaining('Review before departure'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Disruptions');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disruptions'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.disruptionsCalls, 1);
    expect(find.text('Coach disruptions'), findsOneWidget);

    Navigator.of(tester.element(find.text('Coach disruptions'))).pop();
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Finance');
    expect(find.text('Finance'), findsWidgets);
    await _dragUntilTextVisible(tester, 'settlement_op_demo_express_2026w15');
    expect(find.textContaining('settlement_op_demo_express_2026w15'),
        findsOneWidget);
    await _dragUntilTextVisible(tester, 'SyrChat Pay reconciliation');
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'SyrChat Pay reconciliation'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'SyrChat Pay reconciliation'),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.shamellPayReconciliationCalls, 1);
    expect(find.text('SyrChat Pay reconciliation'), findsWidgets);

    Navigator.of(tester.element(find.text('SyrChat Pay reconciliation').first))
        .pop();
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Partner health');
    expect(find.text('Partner health'), findsWidgets);
    expect(find.textContaining('Border Runner • siri'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Finance journal');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Finance journal'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.financeJournalCalls, 1);
    expect(find.text('Coach finance'), findsOneWidget);

    Navigator.of(tester.element(find.text('Coach finance'))).pop();
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Risk & compliance');
    expect(find.text('Risk & compliance'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Risk dashboard');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Risk dashboard'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.riskDashboardCalls, 1);
    expect(find.text('Coach risk'), findsOneWidget);
  });

  testWidgets('coach admin console surfaces command desk priorities',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminApi();
    final overview = await api.adminOverview();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialOverview: overview,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
            operatorIds: <String>[],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Command desk'), findsOneWidget);
    expect(find.text('Coach admin control room'), findsOneWidget);
    expect(find.text('Priority lanes'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Trips need disruption handling'), findsOneWidget);
    expect(find.text('Urgent support queue'), findsOneWidget);
    expect(find.text('Queued payouts'), findsOneWidget);
    expect(find.text('Partner feeds degraded'), findsOneWidget);
    expect(find.text('Boarding attention'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminDeskLane_disruptions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminDeskLane_support')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminDeskLane_finance')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminDeskLane_shamell_pay')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('coachAdminDeskLane_risk')), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminDeskLane_partners')),
        findsOneWidget);
    expect(find.text('Open reconciliation desk'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('coachAdminDeskLane_shamell_pay')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.shamellPayReconciliationCalls, 1);
    expect(find.text('SyrChat Pay reconciliation'), findsWidgets);
  });

  testWidgets('coach admin console filters section desks locally',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminApi();
    final overview = await api.adminOverview();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialOverview: overview,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
            operatorIds: <String>[],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Desk focus'), findsOneWidget);
    expect(find.text('Showing 5 of 5 desks'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('coachAdminSectionFocus_support')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 5 desks'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSection_support')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('coachAdminSection_live_ops')), findsNothing);
    expect(
        find.byKey(const ValueKey('coachAdminSection_finance')), findsNothing);
    expect(find.byKey(const ValueKey('coachAdminSection_risk')), findsNothing);
    expect(
        find.byKey(const ValueKey('coachAdminSection_partners')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('coachAdminSectionFocus_all')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 5 of 5 desks'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSection_live_ops')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSection_support')),
        findsOneWidget);
  });

  testWidgets('coach admin console collapses and expands visible desks',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminApi();
    final overview = await api.adminOverview();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialOverview: overview,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
            operatorIds: <String>[],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSectionBody_live_ops')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('coachAdminSectionToggle_live_ops')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 1 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSectionBody_live_ops')),
        findsNothing);
    expect(find.textContaining('Bay A4'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('coachAdminCollapseVisible')));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 5 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSectionBody_support')),
        findsNothing);
    expect(find.byKey(const ValueKey('coachAdminSectionBody_finance')),
        findsNothing);

    await tester.tap(find.byKey(const ValueKey('coachAdminExpandVisible')));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSectionBody_live_ops')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSectionBody_support')),
        findsOneWidget);
  });

  testWidgets('coach admin console remembers focus and collapsed desks',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminApi();
    final overview = await api.adminOverview();
    final bucket = PageStorageBucket();

    Widget buildPage() {
      return PageStorage(
        bucket: bucket,
        child: MaterialApp(
          home: CoachAdminConsolePage(
            key: const PageStorageKey<String>('coachAdminConsolePage'),
            baseUrl: 'https://api.shamell.online',
            api: api,
            initialOverview: overview,
            privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
              roles: <String>['admin'],
              isSuperadmin: false,
              operatorIds: <String>[],
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('coachAdminSectionFocus_support')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('coachAdminSectionToggle_support')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 5 desks'), findsOneWidget);
    expect(find.text('Collapsed 1 of 1'), findsOneWidget);

    await tester.pumpWidget(
      PageStorage(
        bucket: bucket,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(buildPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 5 desks'), findsOneWidget);
    expect(find.text('Collapsed 1 of 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachAdminSection_support')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('coachAdminSection_live_ops')), findsNothing);
    expect(find.byKey(const ValueKey('coachAdminSectionBody_support')),
        findsNothing);
  });
}
