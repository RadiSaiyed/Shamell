import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_admin_finance_journal_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';

Future<void> _dragUntilTextVisible(
  WidgetTester tester,
  String text,
) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -280));
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

class _FakeCoachAdminFinanceApi extends CoachMobilityApi {
  _FakeCoachAdminFinanceApi() : super(baseUrl: 'https://api.shamell.online');

  int journalCalls = 0;

  @override
  Future<CoachAdminFinanceJournalResponse> adminFinanceJournal({
    String? query,
    int limit = 20,
  }) async {
    journalCalls++;
    return const CoachAdminFinanceJournalResponse(
      generatedAtIso: '2026-04-13T12:00:00Z',
      summary: CoachAdminFinanceJournalSummary(
        currency: 'SYP',
        totalEntries: 3,
        attentionEntries: 2,
        accrualEntries: 1,
        adjustmentEntries: 1,
        payoutEntries: 0,
        pspClearingMinorUnits: 9180,
        operatorPayableMinorUnits: -9180,
        platformRevenueMinorUnits: 1180,
        chargebackReserveMinorUnits: 200,
        travelCreditLiabilityMinorUnits: 9180,
        cashRefundPayableMinorUnits: 0,
        customerReceivableMinorUnits: 0,
        settlementInTransitMinorUnits: 0,
      ),
      entries: <CoachAdminFinanceJournalEntry>[
        CoachAdminFinanceJournalEntry(
          entryId: 'journal_adjustment_refundreq_demo_1',
          occurredAtIso: '2026-04-13T07:15:00Z',
          eventType: 'travel_credit_refund_approved',
          title: 'Refund approved as travel credit',
          status: 'approved',
          operatorId: null,
          operatorName: 'Demo Express',
          bookingId: 'booking_demo_express_direct',
          statementId: null,
          payoutRunId: null,
          requestId: 'refundreq_demo_1',
          importId: null,
          referenceLabel: 'Request refundreq_demo_1',
          currency: 'SYP',
          primaryAmountMinorUnits: 9180,
          needsAttention: true,
          nextAction: 'customer_notification_queued',
          detailLines: <String>[
            'Refund requested by support',
            'Booking booking_demo_express_direct',
          ],
          accountMovements: <CoachAdminFinanceAccountMovement>[
            CoachAdminFinanceAccountMovement(
              accountCode: 'operator_payable',
              accountLabel: 'Operator payable',
              direction: 'decrease',
              amountMinorUnits: 9180,
              signedMinorUnits: -9180,
            ),
            CoachAdminFinanceAccountMovement(
              accountCode: 'travel_credit_liability',
              accountLabel: 'Travel credit liability',
              direction: 'increase',
              amountMinorUnits: 9180,
              signedMinorUnits: 9180,
            ),
          ],
        ),
        CoachAdminFinanceJournalEntry(
          entryId: 'fincase_risk_payout_run_1_1234567890',
          occurredAtIso: '2026-04-13T10:35:00Z',
          eventType: 'risk_follow_up_auto_case',
          title: 'Finance follow-up auto-case',
          status: 'open',
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          bookingId: 'booking_demo_express_direct',
          statementId: 'settlement_op_demo_express_2026w15',
          payoutRunId: 'payout_run_1',
          requestId: 'risk_payout_run_1',
          importId: null,
          referenceLabel: 'Payout run payout_run_1',
          currency: 'SYP',
          primaryAmountMinorUnits: 6460,
          needsAttention: true,
          nextAction: 'Requeue payout after bank review.',
          detailLines: <String>[
            'Auto-created from overdue finance risk.',
            'Risk risk_payout_run_1',
          ],
          accountMovements: <CoachAdminFinanceAccountMovement>[],
        ),
        CoachAdminFinanceJournalEntry(
          entryId: 'journal_accrual_settlement_demo',
          occurredAtIso: '2026-04-13T06:59:59Z',
          eventType: 'operator_payable_accrued',
          title: 'Operator payable accrued',
          status: 'ready_for_payout',
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          bookingId: 'booking_demo_express_direct',
          statementId: 'settlement_op_demo_express_2026w15',
          payoutRunId: null,
          requestId: null,
          importId: null,
          referenceLabel: 'Booking booking_demo_express_direct',
          currency: 'SYP',
          primaryAmountMinorUnits: 7800,
          needsAttention: false,
          nextAction: 'Settlement line is ready for finance review.',
          detailLines: <String>[
            'Statement settlement_op_demo_express_2026w15',
            'Gross 9180 SYP',
          ],
          accountMovements: <CoachAdminFinanceAccountMovement>[
            CoachAdminFinanceAccountMovement(
              accountCode: 'psp_clearing',
              accountLabel: 'SyrChat Pay clearing',
              direction: 'increase',
              amountMinorUnits: 9180,
              signedMinorUnits: 9180,
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  testWidgets('coach admin finance journal page renders list and detail',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminFinanceApi();
    final response = await api.adminFinanceJournal();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminFinanceJournalPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.journalCalls, greaterThanOrEqualTo(1));
    expect(find.text('Coach finance'), findsOneWidget);
    expect(find.text('Finance command desk'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Finance follow-up auto-case');
    expect(find.textContaining('Finance follow-up auto-case'), findsOneWidget);
    expect(find.textContaining('Refund approved as travel credit'),
        findsOneWidget);
    expect(find.text('Operator payable -91.80 SYP'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'coachFinanceEntryCard_fincase_risk_payout_run_1_1234567890',
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('References'), findsOneWidget);
    expect(find.text('Account movements'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Next action');
    expect(find.text('Next action'), findsOneWidget);
    await _dragUntilTextVisible(
        tester, 'Auto-created from overdue finance risk.');
    expect(
        find.text('Auto-created from overdue finance risk.'), findsOneWidget);
  });

  testWidgets('coach admin finance journal page filters local queues',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminFinanceApi();
    final response = await api.adminFinanceJournal();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminFinanceJournalPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Showing 3 of 3 entries'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Risk (1)'));
    await tester.pumpAndSettle();
    await _dragUntilTextVisible(tester, 'Finance follow-up auto-case');

    expect(find.text('Showing 1 of 3 entries'), findsOneWidget);
    expect(find.textContaining('Finance follow-up auto-case'), findsOneWidget);
    expect(
        find.textContaining('Refund approved as travel credit'), findsNothing);
    expect(find.textContaining('Operator payable accrued'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Accruals (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 entries'), findsOneWidget);
    expect(find.textContaining('Operator payable accrued'), findsOneWidget);
    expect(find.textContaining('Finance follow-up auto-case'), findsNothing);
  });

  testWidgets(
      'coach admin finance journal page supports focus queues and latest activity sort',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminFinanceApi();
    final response = await api.adminFinanceJournal();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminFinanceJournalPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Finance command desk'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coachFinanceFocus_risk')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 entries'), findsOneWidget);
    expect(find.textContaining('Finance follow-up auto-case'), findsOneWidget);
    expect(
      find.textContaining('Refund approved as travel credit'),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Latest activity'));
    await tester.pumpAndSettle();

    final riskCard = find.byKey(
      const ValueKey(
          'coachFinanceEntryCard_fincase_risk_payout_run_1_1234567890'),
    );
    final refundCard = find.byKey(
      const ValueKey(
          'coachFinanceEntryCard_journal_adjustment_refundreq_demo_1'),
    );

    expect(
      tester.getTopLeft(riskCard).dy,
      lessThan(tester.getTopLeft(refundCard).dy),
    );
    expect(find.text('Showing 3 of 3 entries'), findsOneWidget);
  });
}
