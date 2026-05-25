import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_preview_diff.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_rework_validation.dart';

void main() {
  const localInvalidSummary = CoachPayoutImportDraftValidationSummary(
    totalRows: 2,
    headerIssues: <String>[],
    rowIssues: <CoachPayoutImportDraftValidationIssue>[
      CoachPayoutImportDraftValidationIssue(
        lineNumber: 2,
        fieldKey: 'payment_reference',
        message: 'payment_reference is required when status maps to executed.',
        suggestion: 'Add the transfer reference.',
      ),
    ],
  );

  const localAutoFix = CoachPayoutImportDraftAutoFixResult(
    correctedBody: 'payout_run_id,external_status',
    headerFixCount: 2,
    statusFixCount: 1,
  );

  const previewResult = CoachOperatorPayoutImportBatchMutationResult(
    command: 'payout_import_batch_create',
    dryRun: true,
    mutationApplied: false,
    previewEcho: CoachOperatorPayoutImportPreviewEcho(
      importSource: 'bank_report',
      reportName: 'bank_report_2026w15.csv',
      reportFormat: 'csv',
      reportChecksumSha256: 'sha256_demo_preview',
      requestFingerprint: 'fp_preview_diff_test',
      previewToken: 'previewtoken_demo',
      previewStatus: 'active',
      expiresAtIso: '2027-04-14T10:18:00Z',
      reworkOfBatchId: null,
    ),
    idempotency: CoachCommandIdempotencyMeta(
      key: 'preview-diff-test',
      scope: 'coach_operator_payout_import_batch_create',
      requestFingerprint: 'fp_preview_diff_test',
      replayed: false,
      derivedKeys: <String, String>{},
    ),
    batch: CoachOperatorPayoutImportBatch(
      batchId: 'payoutbatchpreview_demo_1',
      dryRun: true,
      importSource: 'bank_report',
      reportName: 'bank_report_2026w15.csv',
      reportFormat: 'csv',
      reworkOfBatchId: null,
      reworkOriginBatchId: null,
      followUpBatchIds: <String>[],
      reportChecksumSha256: 'sha256_demo_preview',
      totalRows: 2,
      appliedRows: 1,
      failedRows: 1,
      payoutRunIds: <String>['payoutrun_demo_express'],
      failureMessages: <String>['line 3 (payoutrun_demo_failed): not found'],
      createdAtIso: '2026-04-14T10:08:00Z',
      createdByAccountId: 'acct_finance_demo',
      reportArtifact: null,
      reworkArtifact: null,
      note: 'preview',
    ),
    imports: <CoachOperatorPayoutImport>[],
    failedRows: <CoachOperatorPayoutImportBatchFailure>[
      CoachOperatorPayoutImportBatchFailure(
        lineNumber: 3,
        payoutRunId: 'payoutrun_demo_failed',
        detail: 'not found',
      ),
    ],
    nextAction: 'review_failed_rows',
  );

  test('buildCoachPayoutImportPreviewDiffSummary flags local blockers first',
      () {
    final summary = buildCoachPayoutImportPreviewDiffSummary(
      localValidation: localInvalidSummary,
      autoFix: localAutoFix,
      previewResult: previewResult,
    );

    expect(summary.headline, 'Local draft still needs manual fixes');
    expect(summary.localIssueCount, 1);
    expect(summary.safeFixCount, 3);
    expect(summary.previewReadyRows, 1);
    expect(summary.previewBlockedRows, 1);
    expect(
      summary.notes,
      contains('Apply stays blocked until 1 local issues are resolved.'),
    );
    expect(
      summary.notes,
      contains('Backend blocked line 3: not found'),
    );
    expect(
      summary.notes,
      contains('Server echo checksum: sha256_demo_preview'),
    );
    expect(
      summary.notes,
      contains('Preview fingerprint: fp_preview_diff_test'),
    );
  });

  test('buildCoachPayoutImportPreviewDiffSummary reports clean local draft',
      () {
    const localValidSummary = CoachPayoutImportDraftValidationSummary(
      totalRows: 2,
      headerIssues: <String>[],
      rowIssues: <CoachPayoutImportDraftValidationIssue>[],
    );
    const noFixes = CoachPayoutImportDraftAutoFixResult(
      correctedBody:
          'payout_run_id,external_status,payment_reference\npayoutrun_demo_express,executed,bank_import_payoutrun_demo_express',
      headerFixCount: 0,
      statusFixCount: 0,
    );

    final summary = buildCoachPayoutImportPreviewDiffSummary(
      localValidation: localValidSummary,
      autoFix: noFixes,
      previewResult: previewResult,
    );

    expect(summary.headline, 'Backend preview still blocks some rows');
    expect(summary.notes, contains('No safe local auto-fixes are pending.'));
    expect(summary.notes, contains('Local draft is clean.'));
  });

  test(
      'buildCoachPayoutImportPreviewDiffSummary flags stale preview echo when draft changed',
      () {
    const localValidSummary = CoachPayoutImportDraftValidationSummary(
      totalRows: 2,
      headerIssues: <String>[],
      rowIssues: <CoachPayoutImportDraftValidationIssue>[],
    );
    const noFixes = CoachPayoutImportDraftAutoFixResult(
      correctedBody:
          'payout_run_id,external_status,payment_reference\npayoutrun_demo_express,executed,bank_import_payoutrun_demo_express',
      headerFixCount: 0,
      statusFixCount: 0,
    );

    final summary = buildCoachPayoutImportPreviewDiffSummary(
      localValidation: localValidSummary,
      autoFix: noFixes,
      previewResult: previewResult,
      currentDraftChecksumSha256: 'sha256_changed_draft',
    );

    expect(
      summary.headline,
      'Preview echo no longer matches the current draft',
    );
    expect(summary.previewEchoMatchesCurrentDraft, isFalse);
    expect(
      summary.notes,
      contains('Server echo no longer matches the current draft.'),
    );
  });
}
