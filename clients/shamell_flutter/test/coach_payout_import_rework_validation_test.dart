import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_rework_validation.dart';

void main() {
  const bankProfile = CoachOperatorPayoutImportProfile(
    importSource: 'bank_report',
    title: 'Bank payout report',
    summary: 'Bank payout import profile',
    reportFormat: 'csv',
    supportedDelimiters: <String>['comma', 'semicolon'],
    statusMappings: <CoachOperatorPayoutImportStatusMapping>[
      CoachOperatorPayoutImportStatusMapping(
        normalizedStatus: 'pending',
        acceptedValues: <String>['pending', 'processing'],
        requiredFields: <String>[],
        description: 'Queued in bank rail.',
      ),
      CoachOperatorPayoutImportStatusMapping(
        normalizedStatus: 'executed',
        acceptedValues: <String>['executed', 'completed', 'paid'],
        requiredFields: <String>['payment_reference'],
        description: 'Paid in bank rail.',
      ),
      CoachOperatorPayoutImportStatusMapping(
        normalizedStatus: 'failed',
        acceptedValues: <String>['failed', 'rejected'],
        requiredFields: <String>[],
        description: 'Failed in bank rail.',
      ),
    ],
    sampleBody:
        'merchant_reference;bank_status;transfer_reference;bank_file_reference;executed_at;comment\n'
        'payoutrun_demo_express;executed;bank_import_payoutrun_demo_express;bank_file_2026w15;2026-04-14T10:06:00Z;executed import applied from coach ops console',
    fields: <CoachOperatorPayoutImportProfileField>[
      CoachOperatorPayoutImportProfileField(
        key: 'payout_run_id',
        required: true,
        acceptedHeaders: <String>[
          'payout_run_id',
          'merchant_reference',
          'metadata_payout_run_id',
        ],
        description: 'Internal payout run reference.',
      ),
      CoachOperatorPayoutImportProfileField(
        key: 'external_status',
        required: true,
        acceptedHeaders: <String>[
          'external_status',
          'bank_status',
          'payout_status',
          'status',
        ],
        description: 'Bank status.',
      ),
      CoachOperatorPayoutImportProfileField(
        key: 'payment_reference',
        required: false,
        acceptedHeaders: <String>[
          'payment_reference',
          'bank_payment_reference',
          'transfer_reference',
        ],
        description: 'Bank payment reference.',
      ),
      CoachOperatorPayoutImportProfileField(
        key: 'external_reference',
        required: false,
        acceptedHeaders: <String>[
          'external_reference',
          'bank_file_reference',
          'report_reference',
        ],
        description: 'External file reference.',
      ),
    ],
  );

  test('buildCoachPayoutImportDraftValidation accepts valid bank report rows',
      () {
    const draftBody =
        'merchant_reference;bank_status;transfer_reference;bank_file_reference\n'
        'payoutrun_demo_express;executed;bank_import_payoutrun_demo_express;bank_file_2026w15\n'
        'payoutrun_demo_retry;failed;;bank_file_2026w15';

    final summary = buildCoachPayoutImportDraftValidation(
      profile: bankProfile,
      draftBody: draftBody,
    );

    expect(summary.isValid, isTrue);
    expect(summary.totalRows, 2);
    expect(summary.issueCount, 0);
  });

  test(
      'buildCoachPayoutImportDraftValidation flags missing payment reference for executed rows',
      () {
    const draftBody =
        'merchant_reference;bank_status;transfer_reference;bank_file_reference\n'
        'payoutrun_demo_express;executed;;bank_file_2026w15';

    final summary = buildCoachPayoutImportDraftValidation(
      profile: bankProfile,
      draftBody: draftBody,
    );

    expect(summary.isValid, isFalse);
    expect(summary.issueCount, 1);
    expect(summary.rowIssues.single.lineNumber, 2);
    expect(summary.rowIssues.single.fieldKey, 'payment_reference');
    expect(summary.correctionHints.single.suggestion,
        contains('transfer or payout reference'));
  });

  test('buildCoachPayoutImportDraftValidation flags unsupported status values',
      () {
    const draftBody = 'merchant_reference;bank_status;transfer_reference\n'
        'payoutrun_demo_express;unknown;bank_import_payoutrun_demo_express';

    final summary = buildCoachPayoutImportDraftValidation(
      profile: bankProfile,
      draftBody: draftBody,
    );

    expect(summary.isValid, isFalse);
    expect(summary.issueCount, 1);
    expect(summary.rowIssues.single.lineNumber, 2);
    expect(summary.rowIssues.single.fieldKey, 'external_status');
    expect(summary.rowIssues.single.message, contains('Unsupported status'));
    expect(summary.rowIssues.single.currentValue, 'unknown');
    expect(summary.correctionHints.single.suggestion,
        contains('Use one of: pending, processing, executed, completed, paid'));
  });

  test(
      'buildCoachPayoutImportDraftAutoFix canonicalizes alias headers and accepted status synonyms',
      () {
    const draftBody =
        'merchant_reference;bank_status;transfer_reference;bank_file_reference;imported_at\n'
        'payoutrun_demo_express;completed;bank_import_payoutrun_demo_express;bank_file_2026w15;2026-04-14T10:06:00Z';

    final result = buildCoachPayoutImportDraftAutoFix(
      profile: bankProfile,
      draftBody: draftBody,
    );

    expect(result.hasChanges, isTrue);
    expect(result.headerFixCount, 4);
    expect(result.statusFixCount, 1);
    expect(
      result.correctedBody,
      startsWith(
        'payout_run_id;external_status;payment_reference;external_reference;imported_at',
      ),
    );
    expect(
      result.correctedBody,
      contains(
        'payoutrun_demo_express;executed;bank_import_payoutrun_demo_express;bank_file_2026w15;2026-04-14T10:06:00Z',
      ),
    );
  });

  test('buildCoachPayoutImportDraftAutoFix leaves canonical rows unchanged',
      () {
    const draftBody =
        'payout_run_id;external_status;payment_reference;external_reference\n'
        'payoutrun_demo_express;executed;bank_import_payoutrun_demo_express;bank_file_2026w15';

    final result = buildCoachPayoutImportDraftAutoFix(
      profile: bankProfile,
      draftBody: draftBody,
    );

    expect(result.hasChanges, isFalse);
    expect(result.totalFixCount, 0);
    expect(result.correctedBody, draftBody);
  });
}
