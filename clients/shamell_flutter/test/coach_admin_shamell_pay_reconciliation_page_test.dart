import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_admin_shamell_pay_reconciliation_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeCoachAdminShamellPayApi extends CoachMobilityApi {
  _FakeCoachAdminShamellPayApi() : super(baseUrl: 'https://api.shamell.online');

  int reconciliationCalls = 0;
  int previewImportCalls = 0;
  int applyImportCalls = 0;
  int releaseOperatorRailCalls = 0;
  int confirmOperatorRailCalls = 0;
  int failOperatorRailCalls = 0;
  String? lastExpectedPreviewToken;
  String downstreamStatus = 'not_reported';
  List<CoachOperatorPayoutImport> seededDownstreamAttempts =
      <CoachOperatorPayoutImport>[];
  List<CoachAdminShamellPayReconciliationRun> extraRuns =
      <CoachAdminShamellPayReconciliationRun>[];
  final List<CoachOperatorPayoutImport> _downstreamAttempts =
      <CoachOperatorPayoutImport>[];

  List<CoachOperatorPayoutImport> _syntheticDownstreamAttempts() {
    switch (downstreamStatus) {
      case 'pending':
        return const <CoachOperatorPayoutImport>[
          CoachOperatorPayoutImport(
            importId: 'import_manual_release_seed',
            importBatchId: null,
            payoutRunId: 'payout_run_1',
            importSource: 'manual_upload',
            externalStatus: 'pending',
            paymentReference: null,
            externalReference: 'railrelease_demo_seed',
            importedAtIso: '2026-04-13T11:04:00Z',
            importedByAccountId: 'acct_finance_demo',
            previousRunStatus: 'paid',
            appliedRunStatus: 'paid',
            note: 'Released from SyrChat Pay reconciliation.',
          ),
        ];
      case 'executed':
        return const <CoachOperatorPayoutImport>[
          CoachOperatorPayoutImport(
            importId: 'import_manual_confirm_seed',
            importBatchId: null,
            payoutRunId: 'payout_run_1',
            importSource: 'manual_upload',
            externalStatus: 'executed',
            paymentReference: 'operatorrail_demo_seed',
            externalReference: 'railconfirm_demo_seed',
            importedAtIso: '2026-04-13T11:06:00Z',
            importedByAccountId: 'acct_finance_demo',
            previousRunStatus: 'paid',
            appliedRunStatus: 'paid',
            note: 'Confirmed from SyrChat Pay reconciliation.',
          ),
        ];
      case 'failed':
        return const <CoachOperatorPayoutImport>[
          CoachOperatorPayoutImport(
            importId: 'import_manual_fail_seed',
            importBatchId: null,
            payoutRunId: 'payout_run_1',
            importSource: 'manual_upload',
            externalStatus: 'failed',
            paymentReference: null,
            externalReference: 'railfail_demo_seed',
            importedAtIso: '2026-04-13T11:05:00Z',
            importedByAccountId: 'acct_finance_demo',
            previousRunStatus: 'paid',
            appliedRunStatus: 'paid',
            note: 'Marked failed from SyrChat Pay reconciliation.',
          ),
        ];
      default:
        return const <CoachOperatorPayoutImport>[];
    }
  }

  List<CoachOperatorPayoutImport> get _effectiveDownstreamAttempts =>
      _downstreamAttempts.isNotEmpty
          ? List<CoachOperatorPayoutImport>.unmodifiable(_downstreamAttempts)
          : seededDownstreamAttempts.isNotEmpty
              ? List<CoachOperatorPayoutImport>.unmodifiable(
                  seededDownstreamAttempts,
                )
              : _syntheticDownstreamAttempts();

  CoachAdminShamellPayReconciliationSummary _buildSummary(
    List<CoachAdminShamellPayReconciliationRun> runs,
  ) {
    final currency = runs.isEmpty ? 'SYP' : runs.first.currency;
    final expectedNetPayableMinorUnits = runs.fold<int>(
      0,
      (sum, run) => sum + run.expectedNetPayableMinorUnits,
    );
    final reconciledNetPayableMinorUnits =
        runs.where((run) => run.reconciliationStatus == 'reconciled').fold<int>(
              0,
              (sum, run) => sum + run.expectedNetPayableMinorUnits,
            );
    final attentionNetPayableMinorUnits =
        runs.where((run) => run.needsAttention).fold<int>(
              0,
              (sum, run) => sum + run.expectedNetPayableMinorUnits,
            );
    final shamellPayClearingMinorUnits = runs
        .where(
          (run) =>
              run.shamellPayStatus == 'executed' ||
              run.shamellPayStatus == 'booked',
        )
        .fold<int>(
          0,
          (sum, run) => sum + run.expectedNetPayableMinorUnits,
        );
    final settlementInTransitMinorUnits = -runs
        .where(
          (run) =>
              run.reconciliationStatus != 'reconciled' &&
              (run.shamellPayStatus == 'executed' ||
                  run.shamellPayStatus == 'booked'),
        )
        .fold<int>(
          0,
          (sum, run) => sum + run.expectedNetPayableMinorUnits,
        );
    return CoachAdminShamellPayReconciliationSummary(
      currency: currency,
      totalRuns: runs.length,
      reconciledRuns:
          runs.where((run) => run.reconciliationStatus == 'reconciled').length,
      awaitingShamellPayRuns: runs
          .where(
            (run) =>
                run.reconciliationStatus == 'awaiting_shamell_pay' ||
                run.shamellPayStatus == 'not_reported',
          )
          .length,
      operatorRailPendingRuns: runs
          .where((run) => run.reconciliationStatus == 'operator_rail_pending')
          .length,
      failedRuns:
          runs.where((run) => run.reconciliationStatus == 'failed').length,
      statusMismatchRuns: runs
          .where((run) => run.reconciliationStatus == 'status_mismatch')
          .length,
      escalatedRuns: runs.where((run) => run.escalated).length,
      attentionRuns: runs.where((run) => run.needsAttention).length,
      expectedNetPayableMinorUnits: expectedNetPayableMinorUnits,
      reconciledNetPayableMinorUnits: reconciledNetPayableMinorUnits,
      attentionNetPayableMinorUnits: attentionNetPayableMinorUnits,
      shamellPayClearingMinorUnits: shamellPayClearingMinorUnits,
      settlementInTransitMinorUnits: settlementInTransitMinorUnits,
    );
  }

  CoachAdminShamellPayReconciliationResponse _buildReconciliationResponse() {
    const shamellPayAttempt = CoachOperatorPayoutImport(
      importId: 'import_psp_1',
      importBatchId: 'payoutbatch_shamell_pay_1',
      payoutRunId: 'payout_run_1',
      importSource: 'psp_report',
      externalStatus: 'executed',
      paymentReference: 'shpay_ref_1',
      externalReference: 'shpay_batch_2026w15',
      importedAtIso: '2026-04-13T11:02:00Z',
      importedByAccountId: 'acct_finance_demo',
      previousRunStatus: 'queued',
      appliedRunStatus: 'paid',
      note: 'Reported by SyrChat Pay.',
    );
    final downstreamAttempts = _effectiveDownstreamAttempts;
    final latestDownstreamAttempt =
        downstreamAttempts.isEmpty ? null : downstreamAttempts.first;
    final operatorRailConfirmed =
        latestDownstreamAttempt?.externalStatus == 'executed';
    final operatorRailFailed =
        latestDownstreamAttempt?.externalStatus == 'failed';
    final downstreamFailedAttemptCount = downstreamAttempts
        .where((attempt) => attempt.externalStatus == 'failed')
        .length;
    final escalated =
        !operatorRailConfirmed && downstreamFailedAttemptCount >= 2;
    final escalationSeverity =
        escalated ? (operatorRailFailed ? 'critical' : 'high') : null;
    final escalationReason = escalated
        ? 'Repeated operator rail failures detected after $downstreamFailedAttemptCount failed attempts.'
        : null;
    final runs = <CoachAdminShamellPayReconciliationRun>[
      CoachAdminShamellPayReconciliationRun(
        entryId: 'shamell_pay_reconciliation_payout_run_1',
        occurredAtIso: latestDownstreamAttempt?.importedAtIso ??
            shamellPayAttempt.importedAtIso,
        payoutRunId: 'payout_run_1',
        statementIds: const <String>['settlement_op_demo_express_2026w15'],
        operatorIds: const <String>['op_demo_express'],
        operatorNames: const <String>['Demo Express'],
        currency: 'SYP',
        runStatus: 'paid',
        shamellPayStatus: 'executed',
        downstreamStatus:
            latestDownstreamAttempt?.externalStatus ?? 'not_reported',
        reconciliationStatus: operatorRailConfirmed
            ? 'reconciled'
            : operatorRailFailed
                ? 'failed'
                : 'operator_rail_pending',
        latestShamellPayImportId: shamellPayAttempt.importId,
        latestDownstreamImportId: latestDownstreamAttempt?.importId,
        paymentReference: latestDownstreamAttempt?.paymentReference ??
            shamellPayAttempt.paymentReference,
        externalReference: latestDownstreamAttempt?.externalReference ??
            shamellPayAttempt.externalReference,
        shamellPayAttempts: const <CoachOperatorPayoutImport>[
          shamellPayAttempt,
        ],
        downstreamAttempts: downstreamAttempts,
        downstreamAttemptCount: downstreamAttempts.length,
        downstreamFailedAttemptCount: downstreamFailedAttemptCount,
        escalated: escalated,
        escalationSeverity: escalationSeverity,
        escalationReason: escalationReason,
        expectedNetPayableMinorUnits: 6460,
        needsAttention: !operatorRailConfirmed,
        nextAction: operatorRailConfirmed
            ? 'SyrChat Pay and the downstream payout rail are aligned.'
            : escalated
                ? latestDownstreamAttempt?.externalStatus == 'pending'
                    ? 'Repeated downstream payout failures detected. Escalate to finance operations while the current retry is still pending.'
                    : 'Repeated downstream payout failures detected. Escalate to finance operations before another retry.'
                : operatorRailFailed
                    ? 'Investigate the failed transfer and decide whether to requeue the payout.'
                    : 'Trigger or reconcile the downstream operator payout after SyrChat Pay execution.',
        detailLines: <String>[
          'Run status paid',
          'Statements settlement_op_demo_express_2026w15',
          'SyrChat Pay status executed',
          'Downstream payout status ${latestDownstreamAttempt?.externalStatus ?? 'not_reported'}',
          'Operator rail attempts ${downstreamAttempts.length}',
          if (downstreamFailedAttemptCount > 0)
            'Operator rail failed attempts $downstreamFailedAttemptCount',
          if (escalationReason != null) escalationReason,
        ],
      ),
      ...extraRuns,
    ];
    return CoachAdminShamellPayReconciliationResponse(
      generatedAtIso: '2026-04-13T11:00:00Z',
      summary: _buildSummary(runs),
      runs: runs,
    );
  }

  @override
  Future<CoachAdminShamellPayReconciliationResponse>
      adminShamellPayReconciliation({
    String? query,
    int limit = 20,
  }) async {
    reconciliationCalls++;
    return _buildReconciliationResponse();
  }

  @override
  Future<CoachOperatorPayoutImportBatchMutationResult>
      createAdminShamellPayReportImport({
    required String reportName,
    String reportFormat = 'csv',
    required String reportBody,
    String? expectedPreviewToken,
    bool dryRun = false,
    String? note,
    String? idempotencyKey,
  }) async {
    lastExpectedPreviewToken = expectedPreviewToken;
    if (dryRun) {
      previewImportCalls++;
      return const CoachOperatorPayoutImportBatchMutationResult(
        command: 'payout_import_batch_create',
        dryRun: true,
        mutationApplied: false,
        previewEcho: CoachOperatorPayoutImportPreviewEcho(
          importSource: 'psp_report',
          reportName: 'shamell_pay_report.csv',
          reportFormat: 'csv',
          reportChecksumSha256: 'sha256_preview_demo',
          requestFingerprint: 'preview_fp_demo',
          previewToken: 'previewtoken_shamell_pay_1',
          previewStatus: 'active',
          expiresAtIso: '2026-04-13T11:10:00Z',
          reworkOfBatchId: null,
        ),
        idempotency: CoachCommandIdempotencyMeta(
          key: 'idem_preview_shpay',
          scope: 'coach_operator_payout_import_batch_create',
          requestFingerprint: 'preview_fp_demo',
          replayed: false,
          derivedKeys: <String, String>{},
        ),
        batch: CoachOperatorPayoutImportBatch(
          batchId: 'payoutbatchpreview_shamell_pay_1',
          dryRun: true,
          importSource: 'psp_report',
          reportName: 'shamell_pay_report.csv',
          reportFormat: 'csv',
          reworkOfBatchId: null,
          reworkOriginBatchId: null,
          followUpBatchIds: <String>[],
          reportChecksumSha256: 'sha256_preview_demo',
          totalRows: 1,
          appliedRows: 0,
          failedRows: 0,
          payoutRunIds: <String>['payout_run_1'],
          failureMessages: <String>[],
          createdAtIso: '2026-04-13T11:00:00Z',
          createdByAccountId: 'acct_finance_demo',
          reportArtifact: null,
          reworkArtifact: null,
          note: 'preview',
        ),
        imports: <CoachOperatorPayoutImport>[],
        failedRows: <CoachOperatorPayoutImportBatchFailure>[],
        nextAction: 'apply_ready',
      );
    }
    applyImportCalls++;
    return const CoachOperatorPayoutImportBatchMutationResult(
      command: 'payout_import_batch_create',
      dryRun: false,
      mutationApplied: true,
      previewEcho: null,
      idempotency: CoachCommandIdempotencyMeta(
        key: 'idem_apply_shpay',
        scope: 'coach_operator_payout_import_batch_create',
        requestFingerprint: 'apply_fp_demo',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      batch: CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_shamell_pay_1',
        dryRun: false,
        importSource: 'psp_report',
        reportName: 'shamell_pay_report.csv',
        reportFormat: 'csv',
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_apply_demo',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payout_run_1'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-13T11:02:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'apply',
      ),
      imports: <CoachOperatorPayoutImport>[
        CoachOperatorPayoutImport(
          importId: 'import_psp_1',
          importBatchId: 'payoutbatch_shamell_pay_1',
          payoutRunId: 'payout_run_1',
          importSource: 'psp_report',
          externalStatus: 'booked',
          paymentReference: 'shpay_ref_1',
          externalReference: 'shpay_batch_2026w15',
          importedAtIso: '2026-04-13T11:02:00Z',
          importedByAccountId: 'acct_finance_demo',
          previousRunStatus: 'queued',
          appliedRunStatus: 'queued',
          note: 'apply',
        ),
      ],
      failedRows: <CoachOperatorPayoutImportBatchFailure>[],
      nextAction: 'reconciliation_updated',
    );
  }

  @override
  Future<CoachOperatorPayoutImportMutationResult>
      releaseAdminShamellPayOperatorRail({
    required String payoutRunId,
    String? note,
    String? externalReference,
    String? idempotencyKey,
  }) async {
    releaseOperatorRailCalls++;
    downstreamStatus = 'pending';
    final import = CoachOperatorPayoutImport(
      importId: 'import_manual_release_$releaseOperatorRailCalls',
      importBatchId: null,
      payoutRunId: 'payout_run_1',
      importSource: 'manual_upload',
      externalStatus: 'pending',
      paymentReference: null,
      externalReference: 'railrelease_demo_$releaseOperatorRailCalls',
      importedAtIso: '2026-04-13T11:0${3 + releaseOperatorRailCalls}:00Z',
      importedByAccountId: 'acct_finance_demo',
      previousRunStatus: 'paid',
      appliedRunStatus: 'paid',
      note: 'Released from SyrChat Pay reconciliation.',
    );
    _downstreamAttempts.insert(0, import);
    return CoachOperatorPayoutImportMutationResult(
      command: 'admin_shamell_pay_operator_rail_release',
      idempotency: CoachCommandIdempotencyMeta(
        key: 'idem_release_operator_rail',
        scope: 'coach_admin_shamell_pay_operator_rail_release',
        requestFingerprint: 'release_fp_demo',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      payoutImport: import,
      payoutRun: CoachOperatorPayoutRun(
        payoutRunId: 'payout_run_1',
        status: 'paid',
        currency: 'SYP',
        statementIds: <String>['settlement_op_demo_express_2026w15'],
        operatorIds: <String>['op_demo_express'],
        operatorNames: <String>['Demo Express'],
        statementCount: 1,
        grossMinorUnits: 6600,
        reserveMinorUnits: 140,
        netPayableMinorUnits: 6460,
        createdAtIso: '2026-04-13T09:30:00Z',
        paidAtIso: '2026-04-13T11:02:00Z',
        createdByAccountId: 'acct_finance_demo',
        paidByAccountId: 'acct_finance_demo',
        paymentReference: 'shpay_ref_1',
        note: null,
        availableExportFormats: <String>['csv'],
        exports: <CoachOperatorPayoutExport>[],
      ),
      nextAction: 'await_downstream_payout_confirmation',
    );
  }

  @override
  Future<CoachOperatorPayoutImportMutationResult>
      confirmAdminShamellPayOperatorRail({
    required String payoutRunId,
    String? paymentReference,
    String? externalReference,
    String? importedAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    confirmOperatorRailCalls++;
    downstreamStatus = 'executed';
    final import = CoachOperatorPayoutImport(
      importId: 'import_manual_confirm_$confirmOperatorRailCalls',
      importBatchId: null,
      payoutRunId: 'payout_run_1',
      importSource: 'manual_upload',
      externalStatus: 'executed',
      paymentReference: 'operatorrail_demo_$confirmOperatorRailCalls',
      externalReference: 'railconfirm_demo_$confirmOperatorRailCalls',
      importedAtIso: '2026-04-13T11:06:00Z',
      importedByAccountId: 'acct_finance_demo',
      previousRunStatus: 'paid',
      appliedRunStatus: 'paid',
      note: 'Confirmed from SyrChat Pay reconciliation.',
    );
    _downstreamAttempts.insert(0, import);
    return CoachOperatorPayoutImportMutationResult(
      command: 'admin_shamell_pay_operator_rail_confirm',
      idempotency: CoachCommandIdempotencyMeta(
        key: 'idem_confirm_operator_rail',
        scope: 'coach_admin_shamell_pay_operator_rail_confirm',
        requestFingerprint: 'confirm_fp_demo',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      payoutImport: import,
      payoutRun: CoachOperatorPayoutRun(
        payoutRunId: 'payout_run_1',
        status: 'paid',
        currency: 'SYP',
        statementIds: <String>['settlement_op_demo_express_2026w15'],
        operatorIds: <String>['op_demo_express'],
        operatorNames: <String>['Demo Express'],
        statementCount: 1,
        grossMinorUnits: 6600,
        reserveMinorUnits: 140,
        netPayableMinorUnits: 6460,
        createdAtIso: '2026-04-13T09:30:00Z',
        paidAtIso: '2026-04-13T11:02:00Z',
        createdByAccountId: 'acct_finance_demo',
        paidByAccountId: 'acct_finance_demo',
        paymentReference: 'shpay_ref_1',
        note: null,
        availableExportFormats: <String>['csv'],
        exports: <CoachOperatorPayoutExport>[],
      ),
      nextAction: 'reconciliation_closed',
    );
  }

  @override
  Future<CoachOperatorPayoutImportMutationResult>
      failAdminShamellPayOperatorRail({
    required String payoutRunId,
    String? externalReference,
    String? importedAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    failOperatorRailCalls++;
    downstreamStatus = 'failed';
    final import = CoachOperatorPayoutImport(
      importId: 'import_manual_fail_$failOperatorRailCalls',
      importBatchId: null,
      payoutRunId: 'payout_run_1',
      importSource: 'manual_upload',
      externalStatus: 'failed',
      paymentReference: null,
      externalReference: 'railfail_demo_$failOperatorRailCalls',
      importedAtIso: '2026-04-13T11:05:00Z',
      importedByAccountId: 'acct_finance_demo',
      previousRunStatus: 'paid',
      appliedRunStatus: 'paid',
      note: 'Marked failed from SyrChat Pay reconciliation.',
    );
    _downstreamAttempts.insert(0, import);
    return CoachOperatorPayoutImportMutationResult(
      command: 'admin_shamell_pay_operator_rail_fail',
      idempotency: CoachCommandIdempotencyMeta(
        key: 'idem_fail_operator_rail',
        scope: 'coach_admin_shamell_pay_operator_rail_fail',
        requestFingerprint: 'fail_fp_demo',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      payoutImport: import,
      payoutRun: CoachOperatorPayoutRun(
        payoutRunId: 'payout_run_1',
        status: 'paid',
        currency: 'SYP',
        statementIds: <String>['settlement_op_demo_express_2026w15'],
        operatorIds: <String>['op_demo_express'],
        operatorNames: <String>['Demo Express'],
        statementCount: 1,
        grossMinorUnits: 6600,
        reserveMinorUnits: 140,
        netPayableMinorUnits: 6460,
        createdAtIso: '2026-04-13T09:30:00Z',
        paidAtIso: '2026-04-13T11:02:00Z',
        createdByAccountId: 'acct_finance_demo',
        paidByAccountId: 'acct_finance_demo',
        paymentReference: 'shpay_ref_1',
        note: null,
        availableExportFormats: <String>['csv'],
        exports: <CoachOperatorPayoutExport>[],
      ),
      nextAction: 'retry_or_requeue_operator_rail',
    );
  }
}

void main() {
  testWidgets(
      'coach admin SyrChat Pay reconciliation page renders list and detail',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminShamellPayApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminShamellPayReconciliationPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.reconciliationCalls, 1);
    expect(find.text('SyrChat Pay reconciliation'), findsOneWidget);
    expect(find.text('SyrChat Pay command desk'), findsOneWidget);
    expect(find.text('Runs 1'), findsOneWidget);
    expect(find.text('Demo Express'), findsOneWidget);
    expect(find.text('Release operator rail'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('coachShamellPayRunCard_payout_run_1')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final bottomSheet = find.byType(BottomSheet);
    final sheetScrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Operator rail attempts'),
      200,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Operator rail attempts'), findsOneWidget);
    expect(
      find.text('No downstream operator rail attempts recorded yet.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.descendant(of: bottomSheet, matching: find.text('Next action')),
      300,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: bottomSheet, matching: find.text('Next action')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomSheet,
        matching: find.text(
          'Trigger or reconcile the downstream operator payout after SyrChat Pay execution.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach admin SyrChat Pay reconciliation page releases operator rail',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminShamellPayApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminShamellPayReconciliationPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Release operator rail'), findsOneWidget);

    await tester.ensureVisible(find.text('Release operator rail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Release operator rail'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.releaseOperatorRailCalls, 1);
    expect(api.reconciliationCalls, 2);
    expect(find.text('await_downstream_payout_confirmation'), findsOneWidget);
    expect(find.text('Release operator rail'), findsNothing);
    expect(find.text('Confirm operator rail'), findsOneWidget);
    expect(find.textContaining('1 rail attempt'), findsOneWidget);
  });

  testWidgets(
      'coach admin SyrChat Pay reconciliation page confirms operator rail',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminShamellPayApi()..downstreamStatus = 'pending';

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminShamellPayReconciliationPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Confirm operator rail'), findsOneWidget);

    await tester.ensureVisible(find.text('Confirm operator rail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm operator rail'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.confirmOperatorRailCalls, 1);
    expect(api.reconciliationCalls, 2);
    expect(find.text('reconciliation_closed'), findsOneWidget);
    expect(find.text('Confirm operator rail'), findsNothing);
    expect(find.text('Reconciled 1'), findsOneWidget);
  });

  testWidgets(
      'coach admin SyrChat Pay reconciliation page marks operator rail failed and allows retry',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminShamellPayApi()..downstreamStatus = 'pending';

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminShamellPayReconciliationPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Mark operator rail failed'), findsOneWidget);

    await tester.ensureVisible(find.text('Mark operator rail failed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark operator rail failed'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.failOperatorRailCalls, 1);
    expect(api.reconciliationCalls, 2);
    expect(find.text('Retry operator rail'), findsOneWidget);

    await tester.ensureVisible(find.text('Retry operator rail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry operator rail'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.releaseOperatorRailCalls, 1);
    expect(api.reconciliationCalls, 3);
    expect(find.text('Confirm operator rail'), findsOneWidget);
    expect(find.text('Retry operator rail'), findsNothing);
    expect(find.textContaining('2 rail attempts'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('coachShamellPayRunCard_payout_run_1')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final sheetScrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.textContaining('Import import_manual_release_1'),
      300,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Operator rail attempts'), findsOneWidget);
    expect(
        find.textContaining('Import import_manual_release_1'), findsOneWidget);
    expect(find.textContaining('Import import_manual_fail_1'), findsOneWidget);
  });

  testWidgets(
      'coach admin SyrChat Pay reconciliation page surfaces repeated rail failure escalation',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminShamellPayApi()
      ..seededDownstreamAttempts = const <CoachOperatorPayoutImport>[
        CoachOperatorPayoutImport(
          importId: 'import_manual_retry_2',
          importBatchId: null,
          payoutRunId: 'payout_run_1',
          importSource: 'manual_upload',
          externalStatus: 'pending',
          paymentReference: null,
          externalReference: 'railrelease_demo_2',
          importedAtIso: '2026-04-13T11:07:00Z',
          importedByAccountId: 'acct_finance_demo',
          previousRunStatus: 'paid',
          appliedRunStatus: 'paid',
          note: 'Second retry queued from SyrChat Pay reconciliation.',
        ),
        CoachOperatorPayoutImport(
          importId: 'import_manual_fail_2',
          importBatchId: null,
          payoutRunId: 'payout_run_1',
          importSource: 'manual_upload',
          externalStatus: 'failed',
          paymentReference: null,
          externalReference: 'railfail_demo_2',
          importedAtIso: '2026-04-13T11:06:00Z',
          importedByAccountId: 'acct_finance_demo',
          previousRunStatus: 'paid',
          appliedRunStatus: 'paid',
          note: 'Second rail failure.',
        ),
        CoachOperatorPayoutImport(
          importId: 'import_manual_fail_1',
          importBatchId: null,
          payoutRunId: 'payout_run_1',
          importSource: 'manual_upload',
          externalStatus: 'failed',
          paymentReference: null,
          externalReference: 'railfail_demo_1',
          importedAtIso: '2026-04-13T11:05:00Z',
          importedByAccountId: 'acct_finance_demo',
          previousRunStatus: 'paid',
          appliedRunStatus: 'paid',
          note: 'First rail failure.',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminShamellPayReconciliationPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.textContaining('Repeated operator rail failures detected'),
        findsOneWidget);
    expect(find.text('Escalated 1'), findsWidgets);
    expect(find.textContaining('Escalated'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey('coachShamellPayRunCard_payout_run_1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('coachShamellPayRunCard_payout_run_1')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final sheetScrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Escalation'),
      200,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Escalation'), findsOneWidget);
    expect(find.text('High severity'), findsOneWidget);
    expect(find.text('Failed attempts 2 of 3'), findsOneWidget);
  });

  testWidgets(
      'coach admin SyrChat Pay reconciliation page previews and applies report import',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminShamellPayApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminShamellPayReconciliationPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.reconciliationCalls, 1);

    await tester.tap(find.byTooltip('Import report'));
    await tester.pumpAndSettle();
    expect(find.text('Import SyrChat Pay report'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'CSV body'),
      'merchant_reference,psp_status,psp_reference,settlement_reference,booked_at,description\n'
      'payout_run_1,booked,shpay_ref_1,shpay_batch_2026w15,2026-04-13T11:00:00Z,booked in SyrChat App',
    );

    await tester.ensureVisible(find.text('Preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.previewImportCalls, 1);
    expect(find.text('Latest preview'), findsOneWidget);
    expect(find.text('Preview ready'), findsOneWidget);

    await tester.ensureVisible(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.applyImportCalls, 1);
    expect(api.lastExpectedPreviewToken, 'previewtoken_shamell_pay_1');
    expect(api.reconciliationCalls, 2);
    expect(find.text('Latest import'), findsOneWidget);
    expect(find.text('Import applied'), findsOneWidget);
  });

  testWidgets(
      'coach admin SyrChat Pay reconciliation page supports focus queues and latest activity sort',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminShamellPayApi()
      ..extraRuns = <CoachAdminShamellPayReconciliationRun>[
        const CoachAdminShamellPayReconciliationRun(
          entryId: 'shamell_pay_reconciliation_payout_run_2',
          occurredAtIso: '2026-04-13T11:20:00Z',
          payoutRunId: 'payout_run_2',
          statementIds: <String>['settlement_op_coastal_2026w15'],
          operatorIds: <String>['op_coastal'],
          operatorNames: <String>['Coastal Lines'],
          currency: 'SYP',
          runStatus: 'queued',
          shamellPayStatus: 'not_reported',
          downstreamStatus: 'not_reported',
          reconciliationStatus: 'awaiting_shamell_pay',
          latestShamellPayImportId: null,
          latestDownstreamImportId: null,
          paymentReference: null,
          externalReference: null,
          shamellPayAttempts: <CoachOperatorPayoutImport>[],
          downstreamAttempts: <CoachOperatorPayoutImport>[],
          downstreamAttemptCount: 0,
          downstreamFailedAttemptCount: 0,
          escalated: false,
          escalationSeverity: null,
          escalationReason: null,
          expectedNetPayableMinorUnits: 5800,
          needsAttention: true,
          nextAction:
              'Wait for the latest SyrChat Pay report before releasing the downstream payout rail.',
          detailLines: <String>[
            'Run is queued but still missing in the latest SyrChat Pay import.',
          ],
        ),
        CoachAdminShamellPayReconciliationRun(
          entryId: 'shamell_pay_reconciliation_payout_run_3',
          occurredAtIso: '2026-04-13T11:15:00Z',
          payoutRunId: 'payout_run_3',
          statementIds: const <String>['settlement_op_nightjet_2026w15'],
          operatorIds: const <String>['op_nightjet'],
          operatorNames: const <String>['NightJet Coaches'],
          currency: 'SYP',
          runStatus: 'paid',
          shamellPayStatus: 'executed',
          downstreamStatus: 'failed',
          reconciliationStatus: 'failed',
          latestShamellPayImportId: 'import_psp_3',
          latestDownstreamImportId: 'import_manual_fail_3',
          paymentReference: 'shpay_ref_3',
          externalReference: 'railfail_demo_3',
          shamellPayAttempts: const <CoachOperatorPayoutImport>[
            CoachOperatorPayoutImport(
              importId: 'import_psp_3',
              importBatchId: 'payoutbatch_shamell_pay_3',
              payoutRunId: 'payout_run_3',
              importSource: 'psp_report',
              externalStatus: 'executed',
              paymentReference: 'shpay_ref_3',
              externalReference: 'shpay_batch_2026w15b',
              importedAtIso: '2026-04-13T11:10:00Z',
              importedByAccountId: 'acct_finance_demo',
              previousRunStatus: 'queued',
              appliedRunStatus: 'paid',
              note: 'Reported by SyrChat Pay.',
            ),
          ],
          downstreamAttempts: const <CoachOperatorPayoutImport>[
            CoachOperatorPayoutImport(
              importId: 'import_manual_fail_3',
              importBatchId: null,
              payoutRunId: 'payout_run_3',
              importSource: 'manual_upload',
              externalStatus: 'failed',
              paymentReference: null,
              externalReference: 'railfail_demo_3',
              importedAtIso: '2026-04-13T11:15:00Z',
              importedByAccountId: 'acct_finance_demo',
              previousRunStatus: 'paid',
              appliedRunStatus: 'paid',
              note: 'Third downstream rail failure.',
            ),
            CoachOperatorPayoutImport(
              importId: 'import_manual_fail_2',
              importBatchId: null,
              payoutRunId: 'payout_run_3',
              importSource: 'manual_upload',
              externalStatus: 'failed',
              paymentReference: null,
              externalReference: 'railfail_demo_2',
              importedAtIso: '2026-04-13T11:12:00Z',
              importedByAccountId: 'acct_finance_demo',
              previousRunStatus: 'paid',
              appliedRunStatus: 'paid',
              note: 'Second downstream rail failure.',
            ),
            CoachOperatorPayoutImport(
              importId: 'import_manual_release_1',
              importBatchId: null,
              payoutRunId: 'payout_run_3',
              importSource: 'manual_upload',
              externalStatus: 'pending',
              paymentReference: null,
              externalReference: 'railrelease_demo_1',
              importedAtIso: '2026-04-13T11:11:00Z',
              importedByAccountId: 'acct_finance_demo',
              previousRunStatus: 'paid',
              appliedRunStatus: 'paid',
              note: 'Retry queued after earlier failure.',
            ),
          ],
          downstreamAttemptCount: 3,
          downstreamFailedAttemptCount: 2,
          escalated: true,
          escalationSeverity: 'high',
          escalationReason:
              'Repeated operator rail failures detected after 2 failed attempts.',
          expectedNetPayableMinorUnits: 8100,
          needsAttention: true,
          nextAction:
              'Escalate to finance operations before another downstream payout retry.',
          detailLines: <String>[
            'Repeated rail failure pattern detected.',
          ],
        ),
      ];
    final response = await api.adminShamellPayReconciliation();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminShamellPayReconciliationPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('SyrChat Pay command desk'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('coachShamellPayFocus_escalated')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 runs'), findsOneWidget);
    expect(find.text('NightJet Coaches'), findsOneWidget);
    expect(find.text('Coastal Lines'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Latest activity'));
    await tester.pumpAndSettle();

    final awaitingCard = find.byKey(
      const ValueKey('coachShamellPayRunCard_payout_run_2'),
    );
    final escalatedCard = find.byKey(
      const ValueKey('coachShamellPayRunCard_payout_run_3'),
    );

    expect(
      tester.getTopLeft(awaitingCard).dy,
      lessThan(tester.getTopLeft(escalatedCard).dy),
    );
    expect(find.text('Showing 3 of 3 runs'), findsOneWidget);
  });
}
