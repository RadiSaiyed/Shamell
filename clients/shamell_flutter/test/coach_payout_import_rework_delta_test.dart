import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_rework_delta.dart';

void main() {
  const sourceBatch = CoachOperatorPayoutImportBatch(
    batchId: 'payoutbatch_demo_1',
    dryRun: false,
    importSource: 'bank_report',
    reportName: 'bank_report_2026w15.csv',
    reportFormat: 'csv',
    reworkOfBatchId: null,
    reworkOriginBatchId: null,
    followUpBatchIds: <String>[],
    reportChecksumSha256: 'sha256_demo_report',
    totalRows: 2,
    appliedRows: 1,
    failedRows: 2,
    payoutRunIds: <String>['payoutrun_demo_express'],
    failureMessages: <String>['line 3 (payoutrun_demo_failed): not found'],
    createdAtIso: '2026-04-14T10:08:00Z',
    createdByAccountId: 'acct_finance_demo',
    reportArtifact: null,
    reworkArtifact: null,
    note: 'uploaded from coach ops console',
  );

  test('buildCoachPayoutImportReworkDelta reports unchanged seeded draft', () {
    const seedBody =
        'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
        'payoutrun_demo_failed,executed,bank_import_payoutrun_demo_failed,bank_file_2026w15,2026-04-14T11:06:00Z,rework import prepared from coach ops console\n'
        'payoutrun_demo_retry,failed,,bank_file_2026w15,2026-04-14T11:07:00Z,needs another retry';

    final delta = buildCoachPayoutImportReworkDelta(
      sourceBatch: sourceBatch,
      seedBody: seedBody,
      draftBody: seedBody,
    );

    expect(delta, isNotNull);
    expect(delta!.isModified, isFalse);
    expect(delta.seedRowCount, 2);
    expect(delta.draftRowCount, 2);
    expect(delta.originalFailedRows, 2);
    expect(delta.remainingFailedRowsEstimate, 0);
    expect(delta.additionalRows, 0);
    expect(delta.affectedPayoutRunIds, <String>[
      'payoutrun_demo_failed',
      'payoutrun_demo_retry',
    ]);
  });

  test('buildCoachPayoutImportReworkDelta reports edits and extra rows', () {
    const seedBody = 'merchant_reference;bank_status;transfer_reference\n'
        'payoutrun_demo_failed;executed;bank_import_payoutrun_demo_failed';
    const draftBody = 'merchant_reference;bank_status;transfer_reference\n'
        'payoutrun_demo_failed;executed;bank_import_payoutrun_demo_failed\n'
        'payoutrun_demo_extra;pending;';

    final delta = buildCoachPayoutImportReworkDelta(
      sourceBatch: sourceBatch,
      seedBody: seedBody,
      draftBody: draftBody,
    );

    expect(delta, isNotNull);
    expect(delta!.isModified, isTrue);
    expect(delta.seedRowCount, 1);
    expect(delta.draftRowCount, 2);
    expect(delta.originalFailedRows, 2);
    expect(delta.remainingFailedRowsEstimate, 0);
    expect(delta.additionalRows, 1);
    expect(delta.affectedPayoutRunIds, <String>[
      'payoutrun_demo_failed',
      'payoutrun_demo_extra',
    ]);
  });
}
