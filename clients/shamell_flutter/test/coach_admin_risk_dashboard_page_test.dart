import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_admin_risk_dashboard_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeCoachAdminRiskApi extends CoachMobilityApi {
  _FakeCoachAdminRiskApi() : super(baseUrl: 'https://api.shamell.online');

  int riskDashboardCalls = 0;
  int riskActionCalls = 0;
  String? lastSnoozedUntilIso;
  String? lastSnoozeReason;
  String? lastSnoozeNote;
  String? lastActionRiskId;
  String? lastAction;

  CoachAdminRiskDashboardResponse _response = CoachAdminRiskDashboardResponse(
    generatedAtIso: '2026-04-13T11:05:00Z',
    summary: const CoachAdminRiskSummary(
      openRisks: 5,
      activeRisks: 3,
      acknowledgedRisks: 1,
      snoozedRisks: 1,
      ownedRisks: 2,
      criticalRisks: 2,
      overdueRisks: 1,
      dueSoonRisks: 1,
      financeAlerts: 2,
      supportAlerts: 1,
      partnerAlerts: 1,
      boardingAlerts: 1,
    ),
    risks: const <CoachAdminRiskItem>[
      CoachAdminRiskItem(
        riskId: 'risk_operator_rail_escalation_payout_run_1',
        category: 'finance',
        severity: 'critical',
        title: 'Repeated operator rail failures',
        status: 'failed',
        detectedAtIso: '2026-04-13T10:37:00Z',
        operatorId: 'op_demo_express',
        operatorName: 'Demo Express',
        bookingId: null,
        statementId: 'settlement_op_demo_express_2026w15',
        payoutRunId: 'payout_run_1',
        tripId: null,
        referenceLabel: 'Operator rail payout_run_1',
        currency: 'SYP',
        amountMinorUnits: 6460,
        nextAction:
            'Repeated downstream payout failures detected. Escalate to finance operations before another retry.',
        workflowStatus: 'active',
        ownerAccountId: null,
        ownerTeam: null,
        suggestedTeam: 'finance_ops',
        routingSource: 'shamell_pay_reconciliation',
        routingReason:
            'Repeated operator rail failures originated from SyrChat Pay downstream reconciliation.',
        slaDueAtIso: '2026-04-13T11:00:00Z',
        slaStatus: 'overdue',
        followUpTaskCode: 'finance_reconcile_operator_rail',
        followUpTaskLabel: 'Reconcile operator rail',
        followUpTaskDetail:
            'Repeated downstream payout failures detected. Escalate to finance operations before another retry.',
        snoozedUntilIso: null,
        snoozeReason: null,
        workflowUpdatedAtIso: null,
        workflowUpdatedByAccountId: null,
        workflowNote: null,
        detailLines: <String>[
          'Failed operator rail attempts 2',
          'Latest downstream status failed',
        ],
      ),
      CoachAdminRiskItem(
        riskId: 'risk_feed_op_border_runner_siri',
        category: 'partner_feed',
        severity: 'high',
        title: 'Realtime partner feed stale',
        status: 'degraded',
        detectedAtIso: '2026-04-13T10:40:00Z',
        operatorId: 'op_border_runner',
        operatorName: 'Border Runner',
        bookingId: null,
        statementId: null,
        payoutRunId: null,
        tripId: null,
        referenceLabel: 'Border Runner siri',
        currency: null,
        amountMinorUnits: null,
        nextAction: 'Verify partner realtime feed before boarding.',
        workflowStatus: 'acknowledged',
        ownerAccountId: 'acct_feed_ops',
        ownerTeam: 'partner_ops',
        suggestedTeam: 'partner_ops',
        routingSource: 'partner_feed_health',
        routingReason:
            'Feed freshness and realtime degradation should route to partner operations.',
        slaDueAtIso: '2026-04-13T12:00:00Z',
        slaStatus: 'due_soon',
        followUpTaskCode: 'partner_restore_feed',
        followUpTaskLabel: 'Restore partner feed',
        followUpTaskDetail: 'Verify partner realtime feed before boarding.',
        snoozedUntilIso: null,
        snoozeReason: null,
        workflowUpdatedAtIso: '2026-04-13T10:50:00Z',
        workflowUpdatedByAccountId: 'acct_feed_ops',
        workflowNote: 'Watching partner timeout behaviour.',
        detailLines: <String>[
          'Feed siri via siri',
          'Error: timeout on realtime pull',
        ],
      ),
      CoachAdminRiskItem(
        riskId: 'risk_payout_run_1',
        category: 'finance',
        severity: 'critical',
        title: 'Payout run failed',
        status: 'failed',
        detectedAtIso: '2026-04-13T10:35:00Z',
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
        workflowStatus: 'snoozed',
        ownerAccountId: 'acct_finance_ops',
        ownerTeam: 'finance_ops',
        suggestedTeam: 'finance_ops',
        routingSource: 'shamell_pay_reconciliation',
        routingReason:
            'Failed payout runs should stay with finance operations until the operator rail is confirmed.',
        slaDueAtIso: '2026-04-14T10:00:00Z',
        slaStatus: 'on_track',
        followUpTaskCode: 'finance_review_payout_run',
        followUpTaskLabel: 'Review payout run',
        followUpTaskDetail: 'Requeue payout after bank review.',
        snoozedUntilIso: '2026-04-14T10:00:00Z',
        snoozeReason: 'Waiting for bank callback window.',
        workflowUpdatedAtIso: '2026-04-13T10:55:00Z',
        workflowUpdatedByAccountId: 'acct_finance_ops',
        workflowNote: 'Waiting for bank callback window.',
        detailLines: <String>[
          'Statements settlement_op_demo_express_2026w15',
        ],
      ),
    ],
  );

  @override
  Future<CoachAdminRiskDashboardResponse> adminRiskDashboard({
    String? query,
    int limit = 20,
  }) async {
    riskDashboardCalls++;
    final normalizedQuery = query?.trim().toLowerCase() ?? '';
    final openRisks = _response.risks
        .where((risk) => risk.workflowStatus != 'resolved')
        .toList(growable: false);
    final risks = normalizedQuery.isEmpty
        ? openRisks
        : openRisks
            .where(
              (risk) =>
                  risk.title.toLowerCase().contains(normalizedQuery) ||
                  (risk.operatorName ?? '')
                      .toLowerCase()
                      .contains(normalizedQuery) ||
                  risk.workflowStatus.toLowerCase().contains(normalizedQuery),
            )
            .toList(growable: false);
    return CoachAdminRiskDashboardResponse(
      generatedAtIso: _response.generatedAtIso,
      summary: _summarize(risks),
      risks: risks.take(limit).toList(growable: false),
    );
  }

  @override
  Future<CoachAdminRiskMutationResult> adminRiskAction({
    required String riskId,
    required String action,
    String? ownerAccountId,
    String? ownerTeam,
    String? snoozedUntilIso,
    String? snoozeReason,
    String? note,
    String? idempotencyKey,
  }) async {
    riskActionCalls++;
    lastActionRiskId = riskId;
    lastAction = action;
    if (action == 'snooze') {
      lastSnoozedUntilIso = snoozedUntilIso;
      lastSnoozeReason = snoozeReason;
    } else {
      lastSnoozedUntilIso = null;
      lastSnoozeReason = null;
    }
    lastSnoozeNote = note;
    final risks = _response.risks.map((risk) {
      if (risk.riskId != riskId) {
        return risk;
      }
      final owner = ownerAccountId?.trim().isNotEmpty == true
          ? ownerAccountId!.trim()
          : (risk.ownerAccountId ?? 'acct_risk_admin');
      switch (action) {
        case 'claim':
          return CoachAdminRiskItem(
            riskId: risk.riskId,
            category: risk.category,
            severity: risk.severity,
            title: risk.title,
            status: risk.status,
            detectedAtIso: risk.detectedAtIso,
            operatorId: risk.operatorId,
            operatorName: risk.operatorName,
            bookingId: risk.bookingId,
            statementId: risk.statementId,
            payoutRunId: risk.payoutRunId,
            tripId: risk.tripId,
            referenceLabel: risk.referenceLabel,
            currency: risk.currency,
            amountMinorUnits: risk.amountMinorUnits,
            nextAction: risk.nextAction,
            workflowStatus: risk.workflowStatus,
            ownerAccountId: owner,
            ownerTeam: ownerTeam ?? risk.ownerTeam ?? risk.suggestedTeam,
            suggestedTeam: risk.suggestedTeam,
            routingSource: risk.routingSource,
            routingReason: risk.routingReason,
            slaDueAtIso: risk.slaDueAtIso,
            slaStatus: risk.slaStatus,
            followUpTaskCode: risk.followUpTaskCode,
            followUpTaskLabel: risk.followUpTaskLabel,
            followUpTaskDetail: risk.followUpTaskDetail,
            snoozedUntilIso: risk.snoozedUntilIso,
            snoozeReason: risk.snoozeReason,
            workflowUpdatedAtIso: '2026-04-13T11:08:00Z',
            workflowUpdatedByAccountId: 'acct_risk_admin',
            workflowNote: note ?? risk.workflowNote,
            detailLines: risk.detailLines,
          );
        case 'acknowledge':
          return CoachAdminRiskItem(
            riskId: risk.riskId,
            category: risk.category,
            severity: risk.severity,
            title: risk.title,
            status: risk.status,
            detectedAtIso: risk.detectedAtIso,
            operatorId: risk.operatorId,
            operatorName: risk.operatorName,
            bookingId: risk.bookingId,
            statementId: risk.statementId,
            payoutRunId: risk.payoutRunId,
            tripId: risk.tripId,
            referenceLabel: risk.referenceLabel,
            currency: risk.currency,
            amountMinorUnits: risk.amountMinorUnits,
            nextAction: risk.nextAction,
            workflowStatus: 'acknowledged',
            ownerAccountId: owner,
            ownerTeam: ownerTeam ?? risk.ownerTeam ?? risk.suggestedTeam,
            suggestedTeam: risk.suggestedTeam,
            routingSource: risk.routingSource,
            routingReason: risk.routingReason,
            slaDueAtIso: risk.slaDueAtIso,
            slaStatus: risk.slaStatus,
            followUpTaskCode: risk.followUpTaskCode,
            followUpTaskLabel: risk.followUpTaskLabel,
            followUpTaskDetail: risk.followUpTaskDetail,
            snoozedUntilIso: null,
            snoozeReason: null,
            workflowUpdatedAtIso: '2026-04-13T11:09:00Z',
            workflowUpdatedByAccountId: 'acct_risk_admin',
            workflowNote: note ?? risk.workflowNote,
            detailLines: risk.detailLines,
          );
        case 'snooze':
          return CoachAdminRiskItem(
            riskId: risk.riskId,
            category: risk.category,
            severity: risk.severity,
            title: risk.title,
            status: risk.status,
            detectedAtIso: risk.detectedAtIso,
            operatorId: risk.operatorId,
            operatorName: risk.operatorName,
            bookingId: risk.bookingId,
            statementId: risk.statementId,
            payoutRunId: risk.payoutRunId,
            tripId: risk.tripId,
            referenceLabel: risk.referenceLabel,
            currency: risk.currency,
            amountMinorUnits: risk.amountMinorUnits,
            nextAction: risk.nextAction,
            workflowStatus: 'snoozed',
            ownerAccountId: owner,
            ownerTeam: ownerTeam ?? risk.ownerTeam ?? risk.suggestedTeam,
            suggestedTeam: risk.suggestedTeam,
            routingSource: risk.routingSource,
            routingReason: risk.routingReason,
            slaDueAtIso: snoozedUntilIso ?? risk.slaDueAtIso,
            slaStatus: 'on_track',
            followUpTaskCode: risk.followUpTaskCode,
            followUpTaskLabel: risk.followUpTaskLabel,
            followUpTaskDetail: risk.followUpTaskDetail,
            snoozedUntilIso: snoozedUntilIso ?? '2026-04-14T11:09:00Z',
            snoozeReason:
                snoozeReason ?? 'Waiting for finance reconciliation window.',
            workflowUpdatedAtIso: '2026-04-13T11:10:00Z',
            workflowUpdatedByAccountId: 'acct_risk_admin',
            workflowNote: note ?? risk.workflowNote,
            detailLines: risk.detailLines,
          );
        case 'resolve':
          return CoachAdminRiskItem(
            riskId: risk.riskId,
            category: risk.category,
            severity: risk.severity,
            title: risk.title,
            status: risk.status,
            detectedAtIso: risk.detectedAtIso,
            operatorId: risk.operatorId,
            operatorName: risk.operatorName,
            bookingId: risk.bookingId,
            statementId: risk.statementId,
            payoutRunId: risk.payoutRunId,
            tripId: risk.tripId,
            referenceLabel: risk.referenceLabel,
            currency: risk.currency,
            amountMinorUnits: risk.amountMinorUnits,
            nextAction: risk.nextAction,
            workflowStatus: 'resolved',
            ownerAccountId: owner,
            ownerTeam: ownerTeam ?? risk.ownerTeam ?? risk.suggestedTeam,
            suggestedTeam: risk.suggestedTeam,
            routingSource: risk.routingSource,
            routingReason: risk.routingReason,
            slaDueAtIso: null,
            slaStatus: 'on_track',
            followUpTaskCode: risk.followUpTaskCode,
            followUpTaskLabel: risk.followUpTaskLabel,
            followUpTaskDetail: risk.followUpTaskDetail,
            autoCaseKind: null,
            autoCaseId: null,
            autoCaseStatus: null,
            autoCaseLabel: null,
            snoozedUntilIso: null,
            snoozeReason: null,
            workflowUpdatedAtIso: '2026-04-13T11:10:30Z',
            workflowUpdatedByAccountId: 'acct_risk_admin',
            workflowNote: note ?? 'Resolved in risk dashboard.',
            detailLines: risk.detailLines,
          );
        case 'reopen':
        default:
          return CoachAdminRiskItem(
            riskId: risk.riskId,
            category: risk.category,
            severity: risk.severity,
            title: risk.title,
            status: risk.status,
            detectedAtIso: risk.detectedAtIso,
            operatorId: risk.operatorId,
            operatorName: risk.operatorName,
            bookingId: risk.bookingId,
            statementId: risk.statementId,
            payoutRunId: risk.payoutRunId,
            tripId: risk.tripId,
            referenceLabel: risk.referenceLabel,
            currency: risk.currency,
            amountMinorUnits: risk.amountMinorUnits,
            nextAction: risk.nextAction,
            workflowStatus: 'active',
            ownerAccountId: risk.ownerAccountId,
            ownerTeam: risk.ownerTeam,
            suggestedTeam: risk.suggestedTeam,
            routingSource: risk.routingSource,
            routingReason: risk.routingReason,
            slaDueAtIso: risk.slaDueAtIso,
            slaStatus: risk.slaStatus,
            followUpTaskCode: risk.followUpTaskCode,
            followUpTaskLabel: risk.followUpTaskLabel,
            followUpTaskDetail: risk.followUpTaskDetail,
            snoozedUntilIso: null,
            snoozeReason: null,
            workflowUpdatedAtIso: '2026-04-13T11:11:00Z',
            workflowUpdatedByAccountId: 'acct_risk_admin',
            workflowNote: note ?? risk.workflowNote,
            detailLines: risk.detailLines,
          );
      }
    }).toList(growable: false);
    _response = CoachAdminRiskDashboardResponse(
      generatedAtIso: '2026-04-13T11:11:00Z',
      summary: _summarize(risks),
      risks: risks,
    );
    final updated = risks.firstWhere((risk) => risk.riskId == riskId);
    return CoachAdminRiskMutationResult(
      riskId: riskId,
      action: action,
      updatedAtIso: _response.generatedAtIso,
      risk: updated,
    );
  }

  CoachAdminRiskSummary _summarize(List<CoachAdminRiskItem> risks) {
    return CoachAdminRiskSummary(
      openRisks: risks.length,
      activeRisks:
          risks.where((risk) => risk.workflowStatus == 'active').length,
      acknowledgedRisks:
          risks.where((risk) => risk.workflowStatus == 'acknowledged').length,
      snoozedRisks:
          risks.where((risk) => risk.workflowStatus == 'snoozed').length,
      ownedRisks: risks.where((risk) => risk.ownerAccountId != null).length,
      criticalRisks: risks.where((risk) => risk.severity == 'critical').length,
      overdueRisks: risks.where((risk) => risk.slaStatus == 'overdue').length,
      dueSoonRisks: risks.where((risk) => risk.slaStatus == 'due_soon').length,
      financeAlerts: risks.where((risk) => risk.category == 'finance').length,
      supportAlerts: risks.where((risk) => risk.category == 'support').length,
      partnerAlerts:
          risks.where((risk) => risk.category == 'partner_feed').length,
      boardingAlerts: risks.where((risk) => risk.category == 'boarding').length,
    );
  }
}

void main() {
  testWidgets('coach admin risk dashboard page renders list and detail',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.riskDashboardCalls, 1);
    expect(find.text('Coach risk'), findsOneWidget);
    expect(find.text('Open 3'), findsOneWidget);
    expect(find.text('Active 1'), findsOneWidget);
    expect(find.text('Ack 1'), findsOneWidget);
    expect(find.text('Snoozed 1'), findsOneWidget);
    expect(find.text('Owned 2'), findsOneWidget);
    expect(find.text('Overdue 1'), findsWidgets);
    expect(find.text('Due soon 1'), findsOneWidget);
    expect(find.text('Repeated operator rail failures'), findsOneWidget);
    expect(find.text('Reconcile operator rail'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Border Runner'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Border Runner'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Payout run failed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Payout run failed'), findsOneWidget);

    await tester.tap(find.text('Payout run failed'));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Next action'),
      120,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('Snoozed'), findsWidgets);
    expect(find.text('Owner acct_finance_ops'), findsWidgets);
    expect(find.text('Team Finance ops'), findsOneWidget);
    expect(find.text('Routing'), findsOneWidget);
    expect(find.text('Source SyrChat Pay reconciliation'), findsOneWidget);
    expect(find.text('SLA'), findsOneWidget);
    expect(find.text('On track'), findsWidgets);
    expect(find.text('Task Review payout run'), findsOneWidget);
    expect(find.text('Next action'), findsOneWidget);
    expect(find.text('Requeue payout after bank review.'), findsWidgets);
  });

  testWidgets('coach admin risk dashboard page performs workflow actions',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Claim').first);
    await tester.tap(find.text('Claim').first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.fling(
        find.byType(Scrollable).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(api.riskActionCalls, 1);
    expect(find.text('Owner acct_risk_admin'), findsOneWidget);
    expect(find.text('Owned 3'), findsOneWidget);
    expect(find.text('Finance ops'), findsWidgets);
    expect(find.text('Snooze'), findsWidgets);

    expect(find.text('Acknowledge'), findsWidgets);
    expect(find.text('Reopen'), findsWidgets);
  });

  testWidgets('coach admin risk dashboard page filters local queues',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();
    final response = await api.adminRiskDashboard();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Showing 3 of 3 risks'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue (1)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Showing 1 of 3 risks'), findsOneWidget);
    expect(find.text('Repeated operator rail failures'), findsOneWidget);
    expect(find.textContaining('Border Runner'), findsNothing);
    expect(find.text('Payout run failed'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Owned (2)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Payout run failed'),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('Showing 2 of 3 risks'), findsOneWidget);
    expect(find.textContaining('Border Runner'), findsOneWidget);
    expect(find.text('Payout run failed'), findsOneWidget);
    expect(find.text('Repeated operator rail failures'), findsNothing);
  });

  testWidgets(
      'coach admin risk dashboard page exposes unowned queue and newest sort',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 4200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeCoachAdminRiskApi();
    final response = await api.adminRiskDashboard();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Risk command desk'), findsOneWidget);
    expect(find.text('Unowned (1)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coachRiskFocus_unowned')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Showing 1 of 3 risks'), findsOneWidget);
    expect(find.text('Repeated operator rail failures'), findsOneWidget);
    expect(find.textContaining('Border Runner'), findsNothing);
    expect(find.text('Payout run failed'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Newest'));
    await tester.pumpAndSettle();

    final newestCard = find.byKey(
      const ValueKey('coachRiskCard_risk_feed_op_border_runner_siri'),
    );
    final olderCard = find.byKey(
      const ValueKey(
        'coachRiskCard_risk_operator_rail_escalation_payout_run_1',
      ),
    );

    expect(
        tester.getTopLeft(newestCard).dy,
        lessThan(tester
            .getTopLeft(
              olderCard,
            )
            .dy));
    expect(find.textContaining('Showing 3 of 3 risks'), findsOneWidget);
  });

  testWidgets(
      'coach admin risk dashboard page bulk-claims selected risks via select visible',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();
    final response = await api.adminRiskDashboard();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coachRiskBulkClaim')), findsNothing);

    final selectVisibleToggle =
        find.byKey(const ValueKey('coachRiskSelectVisibleToggle'));
    await tester.scrollUntilVisible(
      selectVisibleToggle,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(selectVisibleToggle);
    await tester.pumpAndSettle();

    expect(find.text('3 risks selected'), findsOneWidget);
    expect(find.text('Clear visible'), findsOneWidget);

    final bulkClaim = find.byKey(const ValueKey('coachRiskBulkClaim'));
    await tester.scrollUntilVisible(
      bulkClaim,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(bulkClaim);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.riskActionCalls, 3);
    expect(find.byKey(const ValueKey('coachRiskBulkClaim')), findsNothing);
    expect(find.text('3 risks claimed'), findsOneWidget);
  });

  testWidgets(
      'coach admin risk dashboard page bulk-resolves selected risks and drops them from queue',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();
    final response = await api.adminRiskDashboard();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final firstCheckbox = find.byKey(
      const ValueKey(
        'coachRiskSelect_risk_operator_rail_escalation_payout_run_1',
      ),
    );
    await tester.scrollUntilVisible(
      firstCheckbox,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(firstCheckbox);
    await tester.pumpAndSettle();

    final secondCheckbox = find.byKey(
      const ValueKey('coachRiskSelect_risk_payout_run_1'),
    );
    await tester.scrollUntilVisible(
      secondCheckbox,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(secondCheckbox);
    await tester.pumpAndSettle();

    expect(find.text('2 risks selected'), findsOneWidget);

    final bulkResolve = find.byKey(const ValueKey('coachRiskBulkResolve'));
    await tester.scrollUntilVisible(
      bulkResolve,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(bulkResolve);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.riskActionCalls, 2);
    expect(find.text('Repeated operator rail failures'), findsNothing);
    expect(find.text('Payout run failed'), findsNothing);
    expect(find.textContaining('Border Runner'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachRiskBulkResolve')), findsNothing);
  });

  testWidgets(
      'coach admin risk dashboard page bulk-clear resets selection without action',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();
    final response = await api.adminRiskDashboard();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final selectVisibleToggle =
        find.byKey(const ValueKey('coachRiskSelectVisibleToggle'));
    await tester.scrollUntilVisible(
      selectVisibleToggle,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(selectVisibleToggle);
    await tester.pumpAndSettle();

    expect(find.text('3 risks selected'), findsOneWidget);

    final bulkClear = find.byKey(const ValueKey('coachRiskBulkClear'));
    await tester.scrollUntilVisible(
      bulkClear,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(bulkClear);
    await tester.pumpAndSettle();

    expect(api.riskActionCalls, 0);
    expect(find.byKey(const ValueKey('coachRiskBulkClaim')), findsNothing);
    expect(find.text('Select visible'), findsOneWidget);
  });

  testWidgets(
      'coach admin risk dashboard page opens snooze sheet and submits custom reason and note',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final snoozeButton = find.byKey(
      const ValueKey(
        'coachRiskSnooze_risk_operator_rail_escalation_payout_run_1',
      ),
    );
    await tester.scrollUntilVisible(
      snoozeButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(snoozeButton);
    await tester.pumpAndSettle();

    expect(find.text('Snooze risk'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachRiskSnoozeDuration_24h')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachRiskSnoozeDuration_4h')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachRiskSnoozeDuration_4h')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('coachRiskSnoozeReasonField')),
      'Need vendor confirmation',
    );
    await tester.enterText(
      find.byKey(const ValueKey('coachRiskSnoozeNoteField')),
      'Vendor email pending',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('coachRiskSnoozeSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.riskActionCalls, 1);
    expect(api.lastAction, 'snooze');
    expect(
      api.lastActionRiskId,
      'risk_operator_rail_escalation_payout_run_1',
    );
    expect(api.lastSnoozeReason, 'Need vendor confirmation');
    expect(api.lastSnoozeNote, 'Vendor email pending');
    expect(api.lastSnoozedUntilIso, isNotNull);
    expect(find.byKey(const ValueKey('coachRiskSnoozeSubmit')), findsNothing);
  });

  testWidgets(
      'coach admin risk dashboard page bulk-snoozes selected risks with sheet reason',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();
    final response = await api.adminRiskDashboard();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final firstCheckbox = find.byKey(
      const ValueKey(
        'coachRiskSelect_risk_operator_rail_escalation_payout_run_1',
      ),
    );
    await tester.scrollUntilVisible(
      firstCheckbox,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(firstCheckbox);
    await tester.pumpAndSettle();

    final secondCheckbox = find.byKey(
      const ValueKey('coachRiskSelect_risk_feed_op_border_runner_siri'),
    );
    await tester.scrollUntilVisible(
      secondCheckbox,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(secondCheckbox);
    await tester.pumpAndSettle();

    expect(find.text('2 risks selected'), findsOneWidget);

    final bulkSnooze = find.byKey(const ValueKey('coachRiskBulkSnooze'));
    await tester.scrollUntilVisible(
      bulkSnooze,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(bulkSnooze);
    await tester.pumpAndSettle();

    expect(find.text('Snooze 2 risks'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('coachRiskSnoozeReasonField')),
      'Coordinated follow-up window',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('coachRiskSnoozeSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.riskActionCalls, 2);
    expect(api.lastAction, 'snooze');
    expect(api.lastSnoozeReason, 'Coordinated follow-up window');
    expect(api.lastSnoozedUntilIso, isNotNull);
    expect(find.byKey(const ValueKey('coachRiskSnoozeSubmit')), findsNothing);
  });

  testWidgets(
      'coach admin risk dashboard page disables snooze submit when reason is empty',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final snoozeButton = find.byKey(
      const ValueKey(
        'coachRiskSnooze_risk_operator_rail_escalation_payout_run_1',
      ),
    );
    await tester.scrollUntilVisible(
      snoozeButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(snoozeButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('coachRiskSnoozeReasonField')),
      '',
    );
    await tester.pumpAndSettle();

    final FilledButton submit = tester.widget(
      find.byKey(const ValueKey('coachRiskSnoozeSubmit')),
    );
    expect(submit.onPressed, isNull);
    expect(api.riskActionCalls, 0);
  });

  testWidgets(
      'coach admin risk dashboard page resolves risk and removes it from open list',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminRiskApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminRiskDashboardPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final riskCard = find.ancestor(
      of: find.text('Repeated operator rail failures'),
      matching: find.byType(Card),
    );
    final resolveButton = find.descendant(
      of: riskCard.first,
      matching: find.text('Resolve'),
    );
    await tester.ensureVisible(resolveButton);
    await tester.pumpAndSettle();
    await tester.tap(resolveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.riskActionCalls, 1);
    expect(
      api._response.risks
          .where((risk) => risk.workflowStatus == 'resolved')
          .length,
      1,
    );
    expect(find.text('Repeated operator rail failures'), findsNothing);
    expect(find.text('Payout run failed'), findsOneWidget);
  });
}
