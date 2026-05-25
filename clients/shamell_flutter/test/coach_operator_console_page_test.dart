import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_batch_filter_store.dart';
import 'package:shamell_flutter/core/coach_bus/coach_catalog_import_run_filter_store.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_operator_console_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_preview_history_filter_store.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';
import 'package:shamell_flutter/core/dashboard_policy_scope.dart';

Future<void> _dragUntilTextVisible(
  WidgetTester tester,
  String text,
) async {
  await _dragUntilFinderVisible(tester, find.text(text));
}

Future<void> _pumpUntilFinderVisible(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 10,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(step);
  }
}

Future<void> _dragUntilFinderVisible(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 40,
  double dragDy = -320,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      continue;
    }
    await tester.drag(scrollables.first, Offset(0, dragDy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1400, 3200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeCoachOperatorApi extends CoachMobilityApi {
  _FakeCoachOperatorApi() : super(baseUrl: 'https://api.shamell.online');

  int refundQueueCalls = 0;
  int changeQueueCalls = 0;
  int reconciliationCalls = 0;
  int settlementStatementsCalls = 0;
  int payoutRunsCalls = 0;
  int payoutReconciliationCalls = 0;
  int operatorFeedHealthCalls = 0;
  int operatorCatalogImportConfigCalls = 0;
  int operatorCatalogImportSourcesCalls = 0;
  int operatorCatalogSourceArtifactsCalls = 0;
  int catalogSourceArtifactDetailCalls = 0;
  int catalogImportConfigUpdateCalls = 0;
  int catalogImportSourceUploadCalls = 0;
  int catalogImportRunsCalls = 0;
  int catalogImportRunDetailCalls = 0;
  int catalogImportRunLineageCalls = 0;
  int catalogImportRunTriggerCalls = 0;
  int catalogImportRunSavedViewsCalls = 0;
  int catalogImportRunSavedViewOwnersCalls = 0;
  int catalogImportRunSavedViewOperatorsCalls = 0;
  int catalogImportRunSavedViewUpsertCalls = 0;
  int catalogImportRunSavedViewDeleteCalls = 0;
  int catalogImportRunIssueSavedViewsCalls = 0;
  int catalogImportRunIssueSavedViewOwnersCalls = 0;
  int catalogImportRunIssueSavedViewOperatorsCalls = 0;
  int catalogImportRunIssueSavedViewUpsertCalls = 0;
  int catalogImportRunIssueSavedViewDeleteCalls = 0;
  CoachApiException? catalogImportConfigUpdateError;
  CoachApiException? catalogImportSourceUploadError;
  CoachApiException? catalogImportRunTriggerError;
  String? lastCatalogImportRunSavedViewsVisibilityScope;
  String? lastCatalogImportRunSavedViewsOwnerAccountId;
  String? lastCatalogImportRunSavedViewsOperatorId;
  String? lastCatalogImportRunIssueSavedViewsVisibilityScope;
  String? lastCatalogImportRunIssueSavedViewsOwnerAccountId;
  String? lastCatalogImportRunIssueSavedViewsOperatorId;
  int payoutImportsCalls = 0;
  int payoutImportPreviewsCalls = 0;
  int payoutImportPreviewSavedViewsCalls = 0;
  int payoutImportPreviewSavedViewOwnersCalls = 0;
  int payoutImportPreviewSavedViewOperatorsCalls = 0;
  int payoutImportPreviewSavedViewUpsertCalls = 0;
  int payoutImportPreviewSavedViewDeleteCalls = 0;
  int payoutImportBatchesCalls = 0;
  int payoutImportBatchSavedViewsCalls = 0;
  int payoutImportBatchSavedViewOwnersCalls = 0;
  int payoutImportBatchSavedViewOperatorsCalls = 0;
  int payoutImportBatchSavedViewUpsertCalls = 0;
  int payoutImportBatchSavedViewDeleteCalls = 0;
  int payoutImportProfilesCalls = 0;
  int refundReviewCalls = 0;
  int changeReviewCalls = 0;
  int payoutCreateCalls = 0;
  int payoutMarkPaidCalls = 0;
  int payoutImportCreateCalls = 0;
  int payoutImportBatchCreateCalls = 0;
  int payoutImportBatchPreviewCalls = 0;
  int payoutImportBatchUploadCalls = 0;
  int payoutImportBatchUploadPreviewCalls = 0;
  int payoutImportPreviewInvalidateCalls = 0;
  int payoutImportReportFetchCalls = 0;
  int payoutExportCreateCalls = 0;
  bool refundApproved = false;
  bool changeRejected = false;
  bool payoutQueued = false;
  bool payoutMarkedPaid = false;
  bool payoutFailed = false;
  String? payoutImportedPaymentReference;
  final Set<String> preparedExportFormats = <String>{};
  final List<CoachOperatorSettlementStatement> settlementStatementEvents =
      <CoachOperatorSettlementStatement>[];
  final List<CoachOperatorPayoutRun> payoutRunEvents =
      <CoachOperatorPayoutRun>[];
  final List<CoachOperatorPayoutImport> payoutImportEvents =
      <CoachOperatorPayoutImport>[];
  final List<CoachOperatorCatalogImportRun> catalogImportRunEvents =
      <CoachOperatorCatalogImportRun>[];
  List<CoachPayoutImportPreviewHistorySavedView> payoutImportPreviewSavedViews =
      <CoachPayoutImportPreviewHistorySavedView>[];
  List<CoachPayoutImportBatchSavedView> payoutImportBatchSavedViews =
      <CoachPayoutImportBatchSavedView>[];
  List<CoachCatalogImportRunSavedView> catalogImportRunSavedViews =
      <CoachCatalogImportRunSavedView>[];
  List<CoachCatalogImportRunIssueSavedView> catalogImportRunIssueSavedViews =
      <CoachCatalogImportRunIssueSavedView>[];

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _catalogImportRunSavedViewOwnersSnapshot() {
    final counts = <String, int>{};
    for (final entry in catalogImportRunSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOwnerSummary(
            accountId: entry.key,
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.accountId.compareTo(right.accountId);
      });
    return out;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _catalogImportRunSavedViewOperatorsSnapshot() {
    final counts = <String, int>{};
    for (final entry in catalogImportRunSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      for (final operatorId in entry.operatorIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()) {
        counts.update(operatorId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
            operatorName: _operatorNameForId(entry.key),
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.operatorId.compareTo(right.operatorId);
      });
    return out;
  }

  String _operatorNameForId(String operatorId) {
    return switch (operatorId.trim()) {
      'op_demo_express' => 'Demo Express',
      'op_border_runner' => 'Border Runner',
      'op_northern_connector' => 'Northern Connector',
      _ => '',
    };
  }

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _catalogImportRunIssueSavedViewOwnersSnapshot() {
    final counts = <String, int>{};
    for (final entry in catalogImportRunIssueSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOwnerSummary(
            accountId: entry.key,
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.accountId.compareTo(right.accountId);
      });
    return out;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _catalogImportRunIssueSavedViewOperatorsSnapshot() {
    final counts = <String, int>{};
    for (final entry in catalogImportRunIssueSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      for (final operatorId in entry.operatorIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()) {
        counts.update(operatorId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
            operatorName: _operatorNameForId(entry.key),
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.operatorId.compareTo(right.operatorId);
      });
    return out;
  }

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _payoutImportPreviewSavedViewOwnersSnapshot() {
    final counts = <String, int>{};
    for (final entry in payoutImportPreviewSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOwnerSummary(
            accountId: entry.key,
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.accountId.compareTo(right.accountId);
      });
    return out;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _payoutImportPreviewSavedViewOperatorsSnapshot() {
    final counts = <String, int>{};
    for (final entry in payoutImportPreviewSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final operatorId = entry.preferences.operatorId.trim();
      if (operatorId.isEmpty || operatorId == 'all') {
        continue;
      }
      counts.update(operatorId, (value) => value + 1, ifAbsent: () => 1);
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
            operatorName: _operatorNameForId(entry.key),
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.operatorId.compareTo(right.operatorId);
      });
    return out;
  }

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _payoutImportBatchSavedViewOwnersSnapshot() {
    final counts = <String, int>{};
    for (final entry in payoutImportBatchSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOwnerSummary(
            accountId: entry.key,
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.accountId.compareTo(right.accountId);
      });
    return out;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _payoutImportBatchSavedViewOperatorsSnapshot() {
    final counts = <String, int>{};
    for (final entry in payoutImportBatchSavedViews) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final operatorId = entry.preferences.operatorId.trim();
      if (operatorId.isEmpty || operatorId == 'all') {
        continue;
      }
      counts.update(operatorId, (value) => value + 1, ifAbsent: () => 1);
    }
    final out = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
            operatorName: _operatorNameForId(entry.key),
            sharedViewCount: entry.value,
          ),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final countCompare =
            right.sharedViewCount.compareTo(left.sharedViewCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.operatorId.compareTo(right.operatorId);
      });
    return out;
  }

  final List<CoachOperatorPayoutImportPreview> payoutImportPreviewEvents =
      <CoachOperatorPayoutImportPreview>[];
  final List<CoachOperatorPayoutImportBatch> payoutImportBatchEvents =
      <CoachOperatorPayoutImportBatch>[];
  final Map<String, String> payoutImportReportBodies = <String, String>{};
  String? lastUploadedPayoutImportFileName;
  String? lastUploadedPayoutImportBody;
  String? lastPayoutImportBatchReworkOfBatchId;
  String? lastExpectedPreviewToken;
  String? lastFetchedPayoutImportReportPath;
  String? lastPayoutImportPreviewStatusFilter;
  String? lastPayoutImportPreviewFromCreatedAtIso;
  String? lastPayoutImportPreviewToCreatedAtIso;
  String? lastSettlementStatementCursor;
  String? lastPayoutRunCursor;
  String? lastPayoutReconciliationCursor;
  String? lastCatalogImportRunCursor;
  String? lastCatalogImportRunStatusFilter;
  String? lastCatalogImportRunReplayScopeFilter;
  String? lastCatalogImportRunIssueSeverityFilter;
  String? lastCatalogImportRunIssueStageFilter;
  String? lastCatalogImportRunDetailId;
  String? lastCatalogImportRunDetailCursor;
  String? lastCatalogImportRunDetailSeverity;
  String? lastCatalogImportRunDetailStage;
  String? lastCatalogImportRunLineageId;
  String? lastCatalogImportRunLineageCursor;
  String? lastCatalogSourceArtifactCursor;
  String? lastCatalogSourceArtifactDetailId;
  String? lastCatalogImportFeedLocator;
  String? lastTriggeredCatalogImportSourceArtifactId;
  String? lastTriggeredCatalogReplayImportRunId;
  String? lastUploadedCatalogImportFileName;
  int? lastUploadedCatalogImportFileBytesLength;
  String? lastPayoutImportCursor;
  String? lastPayoutImportPreviewCursor;
  String? lastPayoutImportBatchCursor;
  String currentCatalogImportFeedLocator = '/srv/feeds/operator_a';
  bool currentCatalogImportConfigReady = true;
  CoachOperatorCatalogSourceArtifact? currentCatalogImportSourceArtifact;

  CoachOperatorCatalogSourceArtifact _catalogImportSourceArtifactSnapshot({
    required String artifactId,
    required String sourceLabel,
    required String fileName,
    required int contentLengthBytes,
    required int extractedFileCount,
    required String feedLocator,
    String createdAtIso = '2026-04-15T10:13:00Z',
  }) {
    return CoachOperatorCatalogSourceArtifact(
      artifactId: artifactId,
      feedKind: 'static_catalog',
      sourceKind: 'gtfs',
      sourceLabel: sourceLabel,
      fileName: fileName,
      fileChecksumSha256: 'a' * 64,
      contentLengthBytes: contentLengthBytes,
      extractedFileCount: extractedFileCount,
      feedLocator: feedLocator,
      createdByAccountId: 'acct_ops_demo',
      createdAtIso: createdAtIso,
    );
  }

  List<String> _followUpBatchIdsFor(
    String batchId,
    List<CoachOperatorPayoutImportBatch> batches,
  ) {
    final followUpBatchIds = <String>[];
    final seen = <String>{};

    void walk(String currentBatchId) {
      final children = batches
          .where((batch) => batch.reworkOfBatchId == currentBatchId)
          .toList(growable: false)
        ..sort(
          (left, right) => left.createdAtIso.compareTo(right.createdAtIso),
        );
      for (final child in children) {
        if (!seen.add(child.batchId)) {
          continue;
        }
        followUpBatchIds.add(child.batchId);
        walk(child.batchId);
      }
    }

    walk(batchId);
    return followUpBatchIds;
  }

  CoachOperatorPayoutImportBatchMutationResult _buildPayoutImportBatchResult({
    required int sequence,
    required String importSource,
    required String reportName,
    required String reportFormat,
    required String reportBody,
    required bool dryRun,
    String? reworkOfBatchId,
    String? note,
  }) {
    final reportChecksumSha256 =
        crypto.sha256.convert(utf8.encode(reportBody.trim())).toString();
    final imports = <CoachOperatorPayoutImport>[
      CoachOperatorPayoutImport(
        importId: 'payoutimport_batch_${sequence}_1',
        importBatchId: 'payoutbatch_demo_$sequence',
        payoutRunId: 'payoutrun_demo_express',
        importSource: importSource,
        externalStatus: 'executed',
        paymentReference: 'bank_import_payoutrun_demo_express',
        externalReference: 'bank_file_2026w15',
        importedAtIso: '2026-04-14T10:06:00Z',
        importedByAccountId: 'acct_finance_demo',
        previousRunStatus: 'queued',
        appliedRunStatus: 'paid',
        note: 'executed import applied from coach ops console',
      ),
    ];
    payoutImportEvents.insertAll(0, imports);
    final batchId = dryRun
        ? 'payoutbatchpreview_demo_$sequence'
        : 'payoutbatch_demo_$sequence';
    final batch = CoachOperatorPayoutImportBatch(
      batchId: batchId,
      dryRun: dryRun,
      importSource: importSource,
      reportName: reportName,
      reportFormat: reportFormat,
      operatorIds: const <String>['op_demo_express'],
      reworkOfBatchId: reworkOfBatchId,
      reworkOriginBatchId: reworkOfBatchId,
      followUpBatchIds: const <String>[],
      reportChecksumSha256: reportChecksumSha256,
      totalRows: 2,
      appliedRows: 1,
      failedRows: 1,
      payoutRunIds: const <String>['payoutrun_demo_express'],
      failureMessages: const <String>[
        'line 3 (payoutrun_demo_failed): not found',
      ],
      createdAtIso: '2026-04-14T10:08:00Z',
      createdByAccountId: 'acct_finance_demo',
      reportArtifact: dryRun
          ? null
          : CoachOperatorPayoutImportReportArtifact(
              artifactId: 'payoutreport_demo_$sequence',
              batchId: 'payoutbatch_demo_$sequence',
              artifactKind: 'source_report',
              importSource: importSource,
              reportName: reportName,
              reportFormat: reportFormat,
              operatorIds: const <String>['op_demo_express'],
              fileName: 'coach-payout-import-payoutbatch_demo_$sequence.csv',
              mimeType: 'text/csv; charset=utf-8',
              downloadPath:
                  '/downloads/coach/payout_import_reports/payoutreport_demo_$sequence.csv',
              checksumSha256: reportChecksumSha256,
              contentLengthBytes: 182,
              createdAtIso: '2026-04-14T10:08:00Z',
              createdByAccountId: 'acct_finance_demo',
              note: 'uploaded from coach ops console',
            ),
      reworkArtifact: dryRun
          ? null
          : CoachOperatorPayoutImportReportArtifact(
              artifactId: 'payoutrework_demo_$sequence',
              batchId: 'payoutbatch_demo_$sequence',
              artifactKind: 'failed_row_rework',
              importSource: importSource,
              reportName: '$reportName (failed row rework)',
              reportFormat: reportFormat,
              operatorIds: const <String>['op_demo_express'],
              fileName:
                  'coach-payout-import-rework-payoutbatch_demo_$sequence.csv',
              mimeType: 'text/csv; charset=utf-8',
              downloadPath:
                  '/downloads/coach/payout_import_reports/payoutrework_demo_$sequence.csv',
              checksumSha256: 'sha256_demo_rework',
              contentLengthBytes: 224,
              createdAtIso: '2026-04-14T10:08:00Z',
              createdByAccountId: 'acct_finance_demo',
              note: 'failed row rework export',
            ),
      note: note,
    );
    if (!dryRun) {
      payoutImportBatchEvents.insert(0, batch);
      payoutQueued = true;
      payoutMarkedPaid = true;
      payoutFailed = false;
      payoutImportedPaymentReference = 'bank_import_payoutrun_demo_express';
    }
    final previewEcho = dryRun
        ? CoachOperatorPayoutImportPreviewEcho(
            importSource: importSource,
            reportName: reportName,
            reportFormat: reportFormat,
            reportChecksumSha256: reportChecksumSha256,
            requestFingerprint: 'fp_ops_payout_import_batch_preview_$sequence',
            previewToken:
                'previewtoken_ops_payout_import_batch_preview_$sequence',
            previewStatus: 'active',
            expiresAtIso: '2027-04-14T10:18:00Z',
            reworkOfBatchId: reworkOfBatchId,
          )
        : null;
    if (previewEcho != null) {
      payoutImportPreviewEvents.insert(
        0,
        CoachOperatorPayoutImportPreview(
          previewToken: previewEcho.previewToken,
          accountId: 'acct_finance_demo',
          importSource: previewEcho.importSource,
          reportName: previewEcho.reportName,
          reportFormat: previewEcho.reportFormat,
          operatorIds: const <String>['op_demo_express'],
          reportChecksumSha256: previewEcho.reportChecksumSha256,
          requestFingerprint: previewEcho.requestFingerprint,
          previewStatus: previewEcho.previewStatus,
          createdAtIso: '2026-04-14T10:08:00Z',
          expiresAtIso: previewEcho.expiresAtIso,
          usableNow: true,
          reworkOfBatchId: previewEcho.reworkOfBatchId,
          consumedAtIso: null,
          invalidatedAtIso: null,
        ),
      );
    }
    return CoachOperatorPayoutImportBatchMutationResult(
      command: 'payout_import_batch_create',
      dryRun: dryRun,
      mutationApplied: !dryRun,
      previewEcho: previewEcho,
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-payout-import-batch-test-1',
        scope: 'coach_operator_payout_import_batch_create',
        requestFingerprint: 'fp_ops_payout_import_batch_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      batch: batch,
      imports: imports,
      failedRows: const <CoachOperatorPayoutImportBatchFailure>[
        CoachOperatorPayoutImportBatchFailure(
          lineNumber: 3,
          payoutRunId: 'payoutrun_demo_failed',
          detail: 'not found',
        ),
      ],
      nextAction: 'review_failed_rows',
    );
  }

  CoachOperatorRefundQueueResponse refundQueueSnapshot() {
    return CoachOperatorRefundQueueResponse(
      generatedAtIso: '2026-04-07T14:10:00Z',
      totals: const CoachOperatorRefundQueueTotals(
        openRequests: 1,
        pendingReview: 1,
        approved: 0,
        rejected: 0,
        creditRequests: 1,
        cashRequests: 0,
      ),
      requests: <CoachOperatorRefundQueueEntry>[
        CoachOperatorRefundQueueEntry(
          refundRequestId: 'refundreq_demo_credit',
          bookingId: 'booking_demo_express_direct',
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-08T08:00:00Z',
          arrivalAtIso: '2026-04-08T12:30:00Z',
          bookingState: CoachBookingLifecycleState.refundRequested,
          requestStatus: 'requested',
          selectedKind: CoachRefundKind.refundCredit,
          currency: 'SYP',
          requestedMinorUnits: 9180,
          feeMinorUnits: 0,
          ticketIds: const <String>['ticket_demo_1', 'ticket_demo_2'],
          reason: 'customer changed plans',
          requestedAtIso: '2026-04-07T13:00:00Z',
          queueStatus: refundApproved
              ? CoachOpsQueueStatus.approved
              : CoachOpsQueueStatus.pendingReview,
          urgency: CoachOpsRequestUrgency.medium,
          suggestedAction: refundApproved
              ? 'Customer notification is queued.'
              : 'Travel credit can be approved immediately.',
          reviewedAtIso: refundApproved ? '2026-04-07T14:15:00Z' : null,
          reviewedByAccountId: refundApproved ? 'acct_ops_demo' : null,
          reviewNote: refundApproved ? 'approved in coach ops console' : null,
        ),
      ],
    );
  }

  CoachOperatorChangeQueueResponse changeQueueSnapshot() {
    return CoachOperatorChangeQueueResponse(
      generatedAtIso: '2026-04-07T14:10:00Z',
      totals: const CoachOperatorChangeQueueTotals(
        openRequests: 1,
        pendingReview: 1,
        approved: 0,
        rejected: 0,
        collectionRequiredRequests: 1,
        zeroDueRequests: 0,
      ),
      requests: <CoachOperatorChangeQueueEntry>[
        CoachOperatorChangeQueueEntry(
          changeRequestId: 'changereq_demo_midday',
          bookingId: 'booking_demo_express_direct',
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-08T08:00:00Z',
          arrivalAtIso: '2026-04-08T12:30:00Z',
          bookingState: CoachBookingLifecycleState.ticketed,
          requestStatus: 'requested',
          targetOfferId: 'offer_demo_express_midday',
          targetJourneyId: 'journey_demo_express_midday',
          currency: 'SYP',
          fareDifferenceMinorUnits: 800,
          changeFeeMinorUnits: 500,
          totalDueMinorUnits: 1300,
          reason: 'move to midday departure',
          requestedAtIso: '2026-04-07T13:05:00Z',
          queueStatus: changeRejected
              ? CoachOpsQueueStatus.rejected
              : CoachOpsQueueStatus.pendingReview,
          urgency: CoachOpsRequestUrgency.high,
          suggestedAction: changeRejected
              ? 'Keep the original ticket active and notify support.'
              : 'Collect the fare difference before reissuing tickets.',
          reviewedAtIso: changeRejected ? '2026-04-07T14:20:00Z' : null,
          reviewedByAccountId: changeRejected ? 'acct_ops_demo' : null,
          reviewNote: changeRejected ? 'rejected in coach ops console' : null,
        ),
      ],
    );
  }

  CoachOperatorReconciliationResponse reconciliationSnapshot() {
    return CoachOperatorReconciliationResponse(
      generatedAtIso: '2026-04-07T15:20:00Z',
      summary: CoachOperatorReconciliationSummary(
        currency: 'SYP',
        tripCount: 1,
        manifestPassengers: 2,
        boardedPassengers: 1,
        pendingBoardingPassengers: 1,
        needsAttentionPassengers: 1,
        pendingReviewRequests: 2,
        reviewedRequests: refundApproved || changeRejected ? 1 : 0,
        approvedCreditRefundMinorUnits: refundApproved ? 9180 : 0,
        approvedCashRefundMinorUnits: 0,
        approvedCollectionDueMinorUnits: 0,
      ),
      tripSnapshots: <CoachOperatorReconciliationTripSnapshot>[
        CoachOperatorReconciliationTripSnapshot(
          trip: const CoachCrewTripSummary(
            tripId: 'trip_demo_express_direct',
            journeyId: 'journey_demo_express_direct',
            bookingId: 'booking_demo_express_direct',
            operatorName: 'Demo Express',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: '2026-04-08T08:00:00Z',
            arrivalAtIso: '2026-04-08T12:30:00Z',
            boardingOpensAtIso: '2026-04-08T07:20:00Z',
            boardingClosesAtIso: '2026-04-08T07:55:00Z',
            gateLabel: 'Bay A4',
            vehicleLabel: 'Bus DX-402',
            manifestCount: 2,
            boardedCount: 1,
            deniedCount: 0,
            noShowCount: 0,
            pendingCount: 1,
          ),
          recentEvents: const <CoachBoardingEvent>[
            CoachBoardingEvent(
              boardingEventId: 'boardevt_demo_scan',
              ticketId: 'ticket_demo_1',
              tripId: 'trip_demo_express_direct',
              scanStatus: CoachBoardingScanStatus.duplicate,
              capturedAtIso: '2026-04-08T07:42:30Z',
              offlineCaptured: false,
              deviceId: 'crew_device_demo',
              note: 'duplicate scan at gate',
            ),
          ],
          pendingTicketIds: const <String>['ticket_demo_2'],
          needsAttentionCount: 1,
        ),
      ],
      reviewHistory: refundApproved
          ? <CoachOperatorReconciliationHistoryEntry>[
              const CoachOperatorReconciliationHistoryEntry(
                requestKind: CoachOpsRequestKind.refundRequest,
                requestId: 'refundreq_demo_credit',
                bookingId: 'booking_demo_express_direct',
                journeyId: 'journey_demo_express_direct',
                operatorName: 'Demo Express',
                from: 'Damascus',
                to: 'Aleppo',
                departureAtIso: '2026-04-08T08:00:00Z',
                queueStatus: CoachOpsQueueStatus.approved,
                urgency: CoachOpsRequestUrgency.medium,
                subjectLabel: 'Travel credit',
                currency: 'SYP',
                amountMinorUnits: 9180,
                suggestedAction: 'Customer notification is queued.',
                reviewedAtIso: '2026-04-07T14:15:00Z',
                reviewedByAccountId: 'acct_ops_demo',
                reviewNote: 'approved in coach ops console',
                settlementEffect: CoachOperatorSettlementEffect(
                  kind: 'travel_credit_liability',
                  currency: 'SYP',
                  amountMinorUnits: 9180,
                ),
                nextAction: 'customer_notification_queued',
              ),
            ]
          : const <CoachOperatorReconciliationHistoryEntry>[],
    );
  }

  CoachOperatorSettlementStatementsResponse settlementStatementsSnapshot({
    int limit = 8,
    String? cursor,
  }) {
    final seededStatements = settlementStatementEvents.isNotEmpty
        ? settlementStatementEvents
        : <CoachOperatorSettlementStatement>[
            CoachOperatorSettlementStatement(
              statementId: 'settlement_op_demo_express_2026w15',
              operatorId: 'op_demo_express',
              operatorName: 'Demo Express',
              currency: 'SYP',
              periodStartIso: '2026-04-07T00:00:00Z',
              periodEndIso: '2026-04-13T23:59:59Z',
              nextPayoutAtIso: '2026-04-14T10:00:00Z',
              status: payoutMarkedPaid
                  ? 'paid_out'
                  : payoutFailed
                      ? 'ready_for_payout'
                      : payoutQueued
                          ? 'payout_in_progress'
                          : 'ready_for_payout',
              downloadFormats: <String>['csv', 'datev_json'],
              totals: const CoachOperatorSettlementStatementTotals(
                lineCount: 1,
                grossMinorUnits: 9180,
                commissionMinorUnits: 1180,
                refundMinorUnits: 0,
                chargebackReserveMinorUnits: 200,
                manualAdjustmentMinorUnits: 0,
                netPayableMinorUnits: 7800,
              ),
              lines: <CoachSettlementLine>[
                CoachSettlementLine(
                  settlementId: 'settlement_op_demo_express_2026w15',
                  operatorId: 'op_demo_express',
                  bookingId: 'booking_demo_express_direct',
                  basis: CoachSettlementBasis.boarded,
                  currency: 'SYP',
                  grossMinorUnits: 9180,
                  commissionMinorUnits: 1180,
                  refundMinorUnits: 0,
                  chargebackReserveMinorUnits: 200,
                  manualAdjustmentMinorUnits: 0,
                  netPayableMinorUnits: 7800,
                ),
              ],
            ),
          ];
    final allStatements = seededStatements.toList(growable: false)
      ..sort((left, right) {
        final periodEndCompare =
            right.periodEndIso.compareTo(left.periodEndIso);
        if (periodEndCompare != 0) {
          return periodEndCompare;
        }
        return right.statementId.compareTo(left.statementId);
      });
    DateTime? cursorPeriodEnd;
    String? cursorStatementId;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorPeriodEnd = DateTime.parse(parts.first).toUtc();
        cursorStatementId = parts.last;
      }
    }
    final filteredStatements = allStatements.where((entry) {
      if (cursorPeriodEnd != null && cursorStatementId != null) {
        final periodEnd = DateTime.parse(entry.periodEndIso).toUtc();
        if (periodEnd.isAfter(cursorPeriodEnd!)) {
          return false;
        }
        if (periodEnd.isAtSameMomentAs(cursorPeriodEnd!) &&
            entry.statementId.compareTo(cursorStatementId!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    final pageStatements =
        filteredStatements.take(limit).toList(growable: false);
    final nextCursor = filteredStatements.length > limit &&
            pageStatements.isNotEmpty
        ? '${pageStatements.last.periodEndIso}|${pageStatements.last.statementId}'
        : null;
    return CoachOperatorSettlementStatementsResponse(
      generatedAtIso: '2026-04-07T15:35:00Z',
      statements: pageStatements,
      nextCursor: nextCursor,
    );
  }

  CoachOperatorPayoutRunsResponse payoutRunsSnapshot({
    int limit = 8,
    String? cursor,
  }) {
    final seededRuns = payoutRunEvents.isNotEmpty
        ? payoutRunEvents
        : (payoutQueued
            ? <CoachOperatorPayoutRun>[
                CoachOperatorPayoutRun(
                  payoutRunId: 'payoutrun_demo_express',
                  status: payoutMarkedPaid
                      ? 'paid'
                      : payoutFailed
                          ? 'failed'
                          : 'queued',
                  currency: 'SYP',
                  statementIds: const <String>[
                    'settlement_op_demo_express_2026w15',
                  ],
                  operatorIds: const <String>['op_demo_express'],
                  operatorNames: const <String>['Demo Express'],
                  statementCount: 1,
                  grossMinorUnits: 9180,
                  reserveMinorUnits: 200,
                  netPayableMinorUnits: 7800,
                  createdAtIso: '2026-04-07T15:50:00Z',
                  paidAtIso: payoutMarkedPaid ? '2026-04-14T10:05:00Z' : null,
                  createdByAccountId: 'acct_finance_demo',
                  paidByAccountId:
                      payoutMarkedPaid ? 'acct_finance_demo' : null,
                  paymentReference: payoutMarkedPaid
                      ? (payoutImportedPaymentReference ??
                          'payout_batch_2026w15')
                      : payoutImportedPaymentReference,
                  note: payoutMarkedPaid
                      ? 'paid from coach ops console'
                      : payoutFailed
                          ? 'failed import applied from coach ops console'
                          : 'queued from coach ops console',
                  availableExportFormats: const <String>[
                    'csv',
                    'datev_json',
                  ],
                  exports: preparedExportFormats
                      .map(
                        (format) => CoachOperatorPayoutExport(
                          exportId:
                              'export_payoutrun_demo_express_${format.replaceAll('_', '')}',
                          payoutRunId: 'payoutrun_demo_express',
                          exportFormat: format,
                          status: 'ready',
                          fileName: format == 'csv'
                              ? 'coach-settlement-payoutrun_demo_express.csv'
                              : 'coach-settlement-payoutrun_demo_express.datev.json',
                          mimeType: format == 'csv'
                              ? 'text/csv; charset=utf-8'
                              : 'application/json',
                          downloadPath: format == 'csv'
                              ? '/downloads/coach/settlement_exports/export_payoutrun_demo_express_csv.csv'
                              : '/downloads/coach/settlement_exports/export_payoutrun_demo_express_datevjson.json',
                          checksumSha256: 'sha256_demo_$format',
                          contentLengthBytes: format == 'csv' ? 182 : 624,
                          createdAtIso: '2026-04-14T10:15:00Z',
                          createdByAccountId: 'acct_finance_demo',
                          statementIds: const <String>[
                            'settlement_op_demo_express_2026w15',
                          ],
                          operatorIds: const <String>['op_demo_express'],
                          note: 'prepared from coach ops console',
                        ),
                      )
                      .toList(growable: false),
                ),
              ]
            : const <CoachOperatorPayoutRun>[]);
    final allRuns = seededRuns.toList(growable: false)
      ..sort((left, right) {
        final createdAtCompare =
            right.createdAtIso.compareTo(left.createdAtIso);
        if (createdAtCompare != 0) {
          return createdAtCompare;
        }
        return right.payoutRunId.compareTo(left.payoutRunId);
      });
    DateTime? cursorCreatedAt;
    String? cursorRunId;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorCreatedAt = DateTime.parse(parts.first).toUtc();
        cursorRunId = parts.last;
      }
    }
    final filteredRuns = allRuns.where((entry) {
      if (cursorCreatedAt != null && cursorRunId != null) {
        final createdAt = DateTime.parse(entry.createdAtIso).toUtc();
        if (createdAt.isAfter(cursorCreatedAt!)) {
          return false;
        }
        if (createdAt.isAtSameMomentAs(cursorCreatedAt!) &&
            entry.payoutRunId.compareTo(cursorRunId!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    final pageRuns = filteredRuns.take(limit).toList(growable: false);
    final nextCursor = filteredRuns.length > limit && pageRuns.isNotEmpty
        ? '${pageRuns.last.createdAtIso}|${pageRuns.last.payoutRunId}'
        : null;
    return CoachOperatorPayoutRunsResponse(
      generatedAtIso: '2026-04-07T15:45:00Z',
      summary: CoachOperatorPayoutRunSummary(
        currency: 'SYP',
        queuedRuns: allRuns.where((run) => run.status == 'queued').length,
        paidRuns: allRuns.where((run) => run.status == 'paid').length,
        failedRuns: allRuns.where((run) => run.status == 'failed').length,
        queuedStatementCount: allRuns
            .where((run) => run.status == 'queued')
            .fold<int>(0, (sum, run) => sum + run.statementCount),
        queuedNetPayableMinorUnits: allRuns
            .where((run) => run.status == 'queued')
            .fold<int>(0, (sum, run) => sum + run.netPayableMinorUnits),
        paidNetPayableMinorUnits: allRuns
            .where((run) => run.status == 'paid')
            .fold<int>(0, (sum, run) => sum + run.netPayableMinorUnits),
      ),
      runs: pageRuns,
      nextCursor: nextCursor,
    );
  }

  CoachOperatorPayoutImportsResponse payoutImportsSnapshot({
    int limit = 8,
    String? cursor,
  }) {
    final allImports = payoutImportEvents.toList(growable: false)
      ..sort((left, right) {
        final importedAtCompare =
            right.importedAtIso.compareTo(left.importedAtIso);
        if (importedAtCompare != 0) {
          return importedAtCompare;
        }
        return right.importId.compareTo(left.importId);
      });
    DateTime? cursorImportedAt;
    String? cursorImportId;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorImportedAt = DateTime.parse(parts.first).toUtc();
        cursorImportId = parts.last;
      }
    }
    final filteredImports = allImports.where((entry) {
      if (cursorImportedAt != null && cursorImportId != null) {
        final importedAt = DateTime.parse(entry.importedAtIso).toUtc();
        if (importedAt.isAfter(cursorImportedAt!)) {
          return false;
        }
        if (importedAt.isAtSameMomentAs(cursorImportedAt!) &&
            entry.importId.compareTo(cursorImportId!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    final pageImports = filteredImports.take(limit).toList(growable: false);
    final nextCursor = filteredImports.length > limit && pageImports.isNotEmpty
        ? '${pageImports.last.importedAtIso}|${pageImports.last.importId}'
        : null;
    return CoachOperatorPayoutImportsResponse(
      generatedAtIso: allImports.isEmpty
          ? '2026-04-07T16:10:00Z'
          : allImports.first.importedAtIso,
      summary: CoachOperatorPayoutImportsSummary(
        totalImports: allImports.length,
        executedImports: allImports
            .where((value) => value.externalStatus == 'executed')
            .length,
        failedImports: allImports
            .where((value) => value.externalStatus == 'failed')
            .length,
        pendingImports: allImports
            .where((value) => value.externalStatus == 'pending')
            .length,
      ),
      imports: pageImports,
      nextCursor: nextCursor,
    );
  }

  List<CoachCatalogImportRunSavedView> _sortedCatalogImportRunSavedViews(
    List<CoachCatalogImportRunSavedView> views,
  ) {
    final sorted = views.toList(growable: false)
      ..sort((left, right) {
        if (left.isDefault != right.isDefault) {
          return left.isDefault ? -1 : 1;
        }
        final scopeOrder =
            left.visibilityScope.compareTo(right.visibilityScope);
        if (scopeOrder != 0) {
          return scopeOrder;
        }
        return right.updatedAtIso.compareTo(left.updatedAtIso);
      });
    return sorted;
  }

  List<CoachCatalogImportRunIssueSavedView>
      _sortedCatalogImportRunIssueSavedViews(
    List<CoachCatalogImportRunIssueSavedView> views,
  ) {
    final sorted = views.toList(growable: false)
      ..sort((left, right) {
        if (left.isDefault != right.isDefault) {
          return left.isDefault ? -1 : 1;
        }
        final scopeOrder =
            left.visibilityScope.compareTo(right.visibilityScope);
        if (scopeOrder != 0) {
          return scopeOrder;
        }
        return right.updatedAtIso.compareTo(left.updatedAtIso);
      });
    return sorted;
  }

  bool _matchesSavedViewOperatorScope(
    List<String> operatorIds,
    String operatorId,
  ) {
    final normalizedOperatorId = operatorId.trim();
    if (normalizedOperatorId.isEmpty) {
      return true;
    }
    if (operatorIds.isEmpty) {
      return true;
    }
    return operatorIds.any((value) => value.trim() == normalizedOperatorId);
  }

  CoachOperatorPayoutImportBatchesResponse payoutImportBatchesSnapshot({
    int limit = 8,
    String? cursor,
  }) {
    final allBatches = payoutImportBatchEvents
        .map(
          (batch) => CoachOperatorPayoutImportBatch(
            batchId: batch.batchId,
            dryRun: batch.dryRun,
            importSource: batch.importSource,
            reportName: batch.reportName,
            reportFormat: batch.reportFormat,
            operatorIds: batch.operatorIds,
            reworkOfBatchId: batch.reworkOfBatchId,
            reworkOriginBatchId: batch.reworkOriginBatchId,
            followUpBatchIds:
                _followUpBatchIdsFor(batch.batchId, payoutImportBatchEvents),
            reportChecksumSha256: batch.reportChecksumSha256,
            totalRows: batch.totalRows,
            appliedRows: batch.appliedRows,
            failedRows: batch.failedRows,
            payoutRunIds: batch.payoutRunIds,
            failureMessages: batch.failureMessages,
            createdAtIso: batch.createdAtIso,
            createdByAccountId: batch.createdByAccountId,
            reportArtifact: batch.reportArtifact,
            reworkArtifact: batch.reworkArtifact,
            note: batch.note,
          ),
        )
        .toList(growable: false)
      ..sort((left, right) {
        final createdAtCompare =
            right.createdAtIso.compareTo(left.createdAtIso);
        if (createdAtCompare != 0) {
          return createdAtCompare;
        }
        return right.batchId.compareTo(left.batchId);
      });
    DateTime? cursorCreatedAt;
    String? cursorBatchId;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorCreatedAt = DateTime.parse(parts.first).toUtc();
        cursorBatchId = parts.last;
      }
    }
    final filteredBatches = allBatches.where((entry) {
      if (cursorCreatedAt != null && cursorBatchId != null) {
        final createdAt = DateTime.parse(entry.createdAtIso).toUtc();
        if (createdAt.isAfter(cursorCreatedAt!)) {
          return false;
        }
        if (createdAt.isAtSameMomentAs(cursorCreatedAt!) &&
            entry.batchId.compareTo(cursorBatchId!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    final pageBatches = filteredBatches.take(limit).toList(growable: false);
    final nextCursor = filteredBatches.length > limit && pageBatches.isNotEmpty
        ? '${pageBatches.last.createdAtIso}|${pageBatches.last.batchId}'
        : null;
    return CoachOperatorPayoutImportBatchesResponse(
      generatedAtIso: allBatches.isEmpty
          ? '2026-04-07T16:12:00Z'
          : allBatches.first.createdAtIso,
      summary: CoachOperatorPayoutImportBatchesSummary(
        totalBatches: allBatches.length,
        totalRows:
            allBatches.fold<int>(0, (sum, value) => sum + value.totalRows),
        appliedRows:
            allBatches.fold<int>(0, (sum, value) => sum + value.appliedRows),
        failedRows:
            allBatches.fold<int>(0, (sum, value) => sum + value.failedRows),
      ),
      batches: pageBatches,
      nextCursor: nextCursor,
    );
  }

  CoachOperatorPayoutImportProfilesResponse payoutImportProfilesSnapshot() {
    return CoachOperatorPayoutImportProfilesResponse(
      generatedAtIso: '2026-04-07T16:11:00Z',
      profiles: <CoachOperatorPayoutImportProfile>[
        CoachOperatorPayoutImportProfile(
          importSource: 'bank_report',
          title: 'Bank payout report',
          summary:
              'Use this for bank execution files where SyrChat payout runs are carried as merchant references.',
          reportFormat: 'csv',
          supportedDelimiters: <String>['comma', 'semicolon'],
          statusMappings: <CoachOperatorPayoutImportStatusMapping>[
            CoachOperatorPayoutImportStatusMapping(
              normalizedStatus: 'pending',
              acceptedValues: <String>['pending', 'processing', 'queued'],
              requiredFields: const <String>[],
              description:
                  'Keeps the payout run queued until the bank execution is final.',
            ),
            CoachOperatorPayoutImportStatusMapping(
              normalizedStatus: 'executed',
              acceptedValues: <String>['executed', 'completed', 'paid'],
              requiredFields: const <String>['payment_reference'],
              description:
                  'Marks the payout run as paid after bank execution is confirmed.',
            ),
            CoachOperatorPayoutImportStatusMapping(
              normalizedStatus: 'failed',
              acceptedValues: <String>['failed', 'rejected'],
              requiredFields: const <String>[],
              description:
                  'Keeps the payout run blocked when the bank rejects or fails the transfer.',
            ),
          ],
          sampleBody:
              'merchant_reference;bank_status;transfer_reference;bank_file_reference;executed_at;comment\npayoutrun_demo_express;executed;bank_import_payoutrun_demo_express;bank_file_2026w15;2026-04-14T10:06:00Z;executed import applied from coach ops console',
          fields: <CoachOperatorPayoutImportProfileField>[
            CoachOperatorPayoutImportProfileField(
              key: 'payout_run_id',
              required: true,
              acceptedHeaders: <String>[
                'payout_run_id',
                'merchant_reference',
                'metadata_payout_run_id',
              ],
              description:
                  'Internal SyrChat payout run reference attached to the bank transfer.',
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
              description: 'Bank payout status.',
            ),
            CoachOperatorPayoutImportProfileField(
              key: 'payment_reference',
              required: false,
              acceptedHeaders: <String>[
                'payment_reference',
                'bank_payment_reference',
                'transfer_reference',
              ],
              description: 'Bank transfer reference.',
            ),
            CoachOperatorPayoutImportProfileField(
              key: 'external_reference',
              required: false,
              acceptedHeaders: <String>[
                'external_reference',
                'bank_file_reference',
                'report_reference',
              ],
              description: 'Bank file or report reference.',
            ),
          ],
        ),
        CoachOperatorPayoutImportProfile(
          importSource: 'psp_report',
          title: 'PSP payout report',
          summary:
              'Use this for Stripe Connect, Adyen or other marketplace payout exports.',
          reportFormat: 'csv',
          supportedDelimiters: <String>['comma', 'semicolon', 'tab'],
          statusMappings: <CoachOperatorPayoutImportStatusMapping>[
            CoachOperatorPayoutImportStatusMapping(
              normalizedStatus: 'pending',
              acceptedValues: <String>['pending', 'processing', 'in_transit'],
              requiredFields: const <String>[],
              description:
                  'Keeps the payout run queued while the PSP transfer is still in flight.',
            ),
            CoachOperatorPayoutImportStatusMapping(
              normalizedStatus: 'executed',
              acceptedValues: <String>['booked', 'settled', 'succeeded'],
              requiredFields: const <String>[
                'payment_reference',
                'external_reference',
              ],
              description:
                  'Marks the payout run as paid once the PSP rail reports a successful transfer.',
            ),
          ],
          sampleBody:
              'merchant_reference,psp_status,psp_reference,settlement_reference,booked_at,description\npayoutrun_demo_express,booked,psp_transfer_payoutrun_demo_express,psp_batch_2026w15,2026-04-14T10:06:00Z,booked by PSP payout rail',
          fields: <CoachOperatorPayoutImportProfileField>[
            CoachOperatorPayoutImportProfileField(
              key: 'external_status',
              required: true,
              acceptedHeaders: <String>[
                'external_status',
                'psp_status',
                'transfer_status',
                'status',
              ],
              description: 'Payout status from the PSP or marketplace rail.',
            ),
          ],
        ),
        CoachOperatorPayoutImportProfile(
          importSource: 'manual_upload',
          title: 'Manual normalized upload',
          summary:
              'Use this when finance prepares a normalized CSV manually or from ad hoc reconciliation work.',
          reportFormat: 'csv',
          supportedDelimiters: <String>['comma', 'semicolon'],
          statusMappings: <CoachOperatorPayoutImportStatusMapping>[
            CoachOperatorPayoutImportStatusMapping(
              normalizedStatus: 'pending',
              acceptedValues: <String>['pending'],
              requiredFields: const <String>[],
              description: 'Keeps the payout run queued.',
            ),
            CoachOperatorPayoutImportStatusMapping(
              normalizedStatus: 'executed',
              acceptedValues: <String>['executed'],
              requiredFields: const <String>['payment_reference'],
              description: 'Marks the payout run as paid.',
            ),
          ],
          sampleBody:
              'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\npayoutrun_demo_express,executed,bank_import_payoutrun_demo_express,manual_batch_2026w15,2026-04-14T10:06:00Z,manual finance import',
          fields: <CoachOperatorPayoutImportProfileField>[
            CoachOperatorPayoutImportProfileField(
              key: 'payout_run_id',
              required: true,
              acceptedHeaders: <String>['payout_run_id'],
              description: 'Internal SyrChat payout run reference.',
            ),
          ],
        ),
      ],
    );
  }

  List<CoachOperatorPayoutImportPreview> _filteredPayoutImportPreviews({
    String? status,
    String? fromCreatedAtIso,
    String? toCreatedAtIso,
    String? cursor,
  }) {
    final rawPreviews = <CoachOperatorPayoutImportPreview>[
      ...payoutImportPreviewEvents,
      const CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_demo_consumed',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_2026w14.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_demo_express'],
        reportChecksumSha256: 'sha256_demo_consumed',
        requestFingerprint: 'fp_preview_consumed_demo',
        previewStatus: 'consumed',
        createdAtIso: '2026-04-14T09:08:00Z',
        expiresAtIso: '2026-04-14T09:18:00Z',
        usableNow: false,
        reworkOfBatchId: null,
        consumedAtIso: '2026-04-14T09:09:00Z',
        invalidatedAtIso: null,
      ),
      const CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_demo_expired',
        accountId: 'acct_finance_demo',
        importSource: 'psp_report',
        reportName: 'psp_report_2026w13.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_border_runner'],
        reportChecksumSha256: 'sha256_demo_expired',
        requestFingerprint: 'fp_preview_expired_demo',
        previewStatus: 'expired',
        createdAtIso: '2026-04-01T09:08:00Z',
        expiresAtIso: '2026-04-01T09:18:00Z',
        usableNow: false,
        reworkOfBatchId: null,
        consumedAtIso: null,
        invalidatedAtIso: null,
      ),
    ];
    rawPreviews.sort((left, right) {
      final createdAtCompare = right.createdAtIso.compareTo(left.createdAtIso);
      if (createdAtCompare != 0) {
        return createdAtCompare;
      }
      return right.previewToken.compareTo(left.previewToken);
    });
    final normalizedStatus = status?.trim().toLowerCase();
    final fromCreatedAt =
        fromCreatedAtIso == null || fromCreatedAtIso.trim().isEmpty
            ? null
            : DateTime.parse(fromCreatedAtIso).toUtc();
    final toCreatedAt = toCreatedAtIso == null || toCreatedAtIso.trim().isEmpty
        ? null
        : DateTime.parse(toCreatedAtIso).toUtc();
    DateTime? cursorCreatedAt;
    String? cursorPreviewToken;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorCreatedAt = DateTime.parse(parts.first).toUtc();
        cursorPreviewToken = parts.last;
      }
    }
    return rawPreviews.where((entry) {
      if (normalizedStatus != null &&
          normalizedStatus.isNotEmpty &&
          entry.previewStatus.toLowerCase() != normalizedStatus) {
        return false;
      }
      final createdAt = DateTime.parse(entry.createdAtIso).toUtc();
      if (fromCreatedAt != null && createdAt.isBefore(fromCreatedAt)) {
        return false;
      }
      if (toCreatedAt != null && createdAt.isAfter(toCreatedAt)) {
        return false;
      }
      if (cursorCreatedAt != null && cursorPreviewToken != null) {
        if (createdAt.isAfter(cursorCreatedAt!)) {
          return false;
        }
        if (createdAt.isAtSameMomentAs(cursorCreatedAt!) &&
            entry.previewToken.compareTo(cursorPreviewToken!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
  }

  CoachOperatorPayoutImportPreviewsResponse payoutImportPreviewsSnapshot({
    int limit = 8,
    String? status,
    String? fromCreatedAtIso,
    String? toCreatedAtIso,
    String? cursor,
  }) {
    final allFilteredPreviews = _filteredPayoutImportPreviews(
      status: status,
      fromCreatedAtIso: fromCreatedAtIso,
      toCreatedAtIso: toCreatedAtIso,
    );
    final filteredPreviews = _filteredPayoutImportPreviews(
      status: status,
      fromCreatedAtIso: fromCreatedAtIso,
      toCreatedAtIso: toCreatedAtIso,
      cursor: cursor,
    );
    final pagePreviews = filteredPreviews.take(limit).toList(growable: false);
    final nextCursor = filteredPreviews.length > limit &&
            pagePreviews.isNotEmpty
        ? '${pagePreviews.last.createdAtIso}|${pagePreviews.last.previewToken}'
        : null;
    return CoachOperatorPayoutImportPreviewsResponse(
      generatedAtIso: allFilteredPreviews.isEmpty
          ? '2026-04-07T16:11:00Z'
          : allFilteredPreviews.first.createdAtIso,
      summary: CoachOperatorPayoutImportPreviewsSummary(
        totalPreviews: allFilteredPreviews.length,
        activePreviews: allFilteredPreviews
            .where((entry) => entry.previewStatus == 'active')
            .length,
        consumedPreviews: allFilteredPreviews
            .where((entry) => entry.previewStatus == 'consumed')
            .length,
        expiredPreviews: allFilteredPreviews
            .where((entry) => entry.previewStatus == 'expired')
            .length,
        invalidatedPreviews: allFilteredPreviews
            .where((entry) => entry.previewStatus == 'invalidated')
            .length,
      ),
      previews: pagePreviews,
      nextCursor: nextCursor,
    );
  }

  CoachOperatorCatalogImportRunsResponse catalogImportRunsSnapshot({
    int limit = 8,
    String? cursor,
    String? status,
    String? replayScope,
    String? issueSeverity,
    String? issueStage,
  }) {
    final allRuns = <CoachOperatorCatalogImportRun>[
      ...catalogImportRunEvents,
      const CoachOperatorCatalogImportRun(
        importRunId: 'catalogimportrun_demo_failed',
        feedKind: 'static_catalog',
        sourceKind: 'gtfs',
        triggerKind: 'startup',
        feedLocator: '/srv/feeds/operator_a',
        replayedFromImportRunId: 'catalogimportrun_demo_failed_old_2',
        replayLineageSummary: CoachOperatorCatalogImportRunReplayLineageSummary(
          replayRunCount: 3,
          latestReplayRunId: 'catalogimportrun_demo_failed_replay_2',
          latestReplayStartedAtIso: '2026-04-15T10:10:00Z',
        ),
        sourceArtifactId: 'catalogsourceartifact_demo_failed',
        sourceArtifact: CoachOperatorCatalogSourceArtifact(
          artifactId: 'catalogsourceartifact_demo_failed',
          feedKind: 'static_catalog',
          sourceKind: 'gtfs',
          sourceLabel: 'operator_a_feed_failed.zip',
          fileName: 'operator_a_feed_failed.zip',
          fileChecksumSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          contentLengthBytes: 768,
          extractedFileCount: 6,
          feedLocator: '/srv/feeds/operator_a',
          createdByAccountId: 'acct_ops_demo',
          createdAtIso: '2026-04-14T10:07:00Z',
        ),
        status: 'failed',
        startedAtIso: '2026-04-14T10:08:00Z',
        finishedAtIso: '2026-04-14T10:09:00Z',
        counts: CoachOperatorCatalogImportRunCounts(
          operators: 0,
          cities: 0,
          stopClusters: 0,
          stops: 0,
          lines: 0,
          serviceCalendars: 0,
          trips: 0,
          fareProducts: 0,
          totalRecords: 0,
          ready: false,
        ),
        errorMessage: 'required GTFS file missing: stops.txt',
        issues: <CoachOperatorCatalogImportRunIssue>[
          CoachOperatorCatalogImportRunIssue(
            issueId: 'catalogimportissue_demo_failed_1',
            severity: 'error',
            stage: 'load_feed',
            code: 'required_file_missing',
            message: 'required GTFS file missing: stops.txt',
            fileName: 'stops.txt',
            rowReference: null,
          ),
        ],
      ),
      const CoachOperatorCatalogImportRun(
        importRunId: 'catalogimportrun_demo_ok',
        feedKind: 'static_catalog',
        sourceKind: 'gtfs',
        triggerKind: 'scheduled',
        feedLocator: '/srv/feeds/operator_a',
        sourceArtifact: null,
        status: 'succeeded',
        startedAtIso: '2026-04-13T10:08:00Z',
        finishedAtIso: '2026-04-13T10:08:30Z',
        counts: CoachOperatorCatalogImportRunCounts(
          operators: 1,
          cities: 2,
          stopClusters: 2,
          stops: 4,
          lines: 1,
          serviceCalendars: 1,
          trips: 2,
          fareProducts: 2,
          totalRecords: 15,
          ready: true,
        ),
        errorMessage: null,
        issues: <CoachOperatorCatalogImportRunIssue>[],
      ),
      const CoachOperatorCatalogImportRun(
        importRunId: 'catalogimportrun_demo_old',
        feedKind: 'static_catalog',
        sourceKind: 'gtfs',
        triggerKind: 'startup',
        feedLocator: '/srv/feeds/operator_a_v1',
        sourceArtifact: null,
        status: 'succeeded',
        startedAtIso: '2026-04-12T10:08:00Z',
        finishedAtIso: '2026-04-12T10:08:20Z',
        counts: CoachOperatorCatalogImportRunCounts(
          operators: 1,
          cities: 1,
          stopClusters: 1,
          stops: 2,
          lines: 1,
          serviceCalendars: 1,
          trips: 1,
          fareProducts: 1,
          totalRecords: 9,
          ready: true,
        ),
        errorMessage: null,
        issues: <CoachOperatorCatalogImportRunIssue>[],
      ),
      const CoachOperatorCatalogImportRun(
        importRunId: 'catalogimportrun_demo_failed_old_2',
        feedKind: 'static_catalog',
        sourceKind: 'gtfs',
        triggerKind: 'scheduled',
        feedLocator: '/srv/feeds/operator_a_v2',
        sourceArtifactId: 'catalogsourceartifact_demo_failed',
        sourceArtifact: null,
        status: 'succeeded',
        startedAtIso: '2026-04-11T10:08:00Z',
        finishedAtIso: '2026-04-11T10:08:20Z',
        counts: CoachOperatorCatalogImportRunCounts(
          operators: 1,
          cities: 1,
          stopClusters: 1,
          stops: 2,
          lines: 1,
          serviceCalendars: 1,
          trips: 1,
          fareProducts: 1,
          totalRecords: 9,
          ready: true,
        ),
        errorMessage: null,
        issues: <CoachOperatorCatalogImportRunIssue>[],
      ),
      const CoachOperatorCatalogImportRun(
        importRunId: 'catalogimportrun_demo_failed_old_1',
        feedKind: 'static_catalog',
        sourceKind: 'gtfs',
        triggerKind: 'startup',
        feedLocator: '/srv/feeds/operator_a_v1',
        sourceArtifactId: 'catalogsourceartifact_demo_failed',
        sourceArtifact: null,
        status: 'failed',
        startedAtIso: '2026-04-10T10:08:00Z',
        finishedAtIso: '2026-04-10T10:08:15Z',
        counts: CoachOperatorCatalogImportRunCounts(
          operators: 0,
          cities: 0,
          stopClusters: 0,
          stops: 0,
          lines: 0,
          serviceCalendars: 0,
          trips: 0,
          fareProducts: 0,
          totalRecords: 0,
          ready: false,
        ),
        errorMessage: 'operator_a historical feed failed',
        issues: <CoachOperatorCatalogImportRunIssue>[],
      ),
    ];
    allRuns.sort((left, right) {
      final startedAtCompare = right.startedAtIso.compareTo(left.startedAtIso);
      if (startedAtCompare != 0) {
        return startedAtCompare;
      }
      return right.importRunId.compareTo(left.importRunId);
    });
    final normalizedStatus = status?.trim();
    final normalizedReplayScope = replayScope?.trim();
    final normalizedIssueSeverity = issueSeverity?.trim();
    final normalizedIssueStage = issueStage?.trim();
    final allFilteredRuns = allRuns.where((entry) {
      if (normalizedStatus != null &&
          normalizedStatus.isNotEmpty &&
          normalizedStatus != 'all' &&
          entry.status != normalizedStatus) {
        return false;
      }
      if (normalizedReplayScope != null &&
          normalizedReplayScope.isNotEmpty &&
          normalizedReplayScope != 'all') {
        final hasReplays = allRuns.any(
          (candidate) => candidate.replayedFromImportRunId == entry.importRunId,
        );
        final needsAttention =
            (entry.replayedFromImportRunId?.isNotEmpty ?? false) &&
                    entry.isFailed ||
                allRuns.any(
                  (candidate) =>
                      candidate.replayedFromImportRunId == entry.importRunId &&
                      candidate.isFailed,
                );
        switch (normalizedReplayScope) {
          case 'replays_only':
            if ((entry.replayedFromImportRunId?.isNotEmpty ?? false) == false) {
              return false;
            }
            break;
          case 'with_replays':
            if (!hasReplays) {
              return false;
            }
            break;
          case 'attention':
            if (!needsAttention) {
              return false;
            }
            break;
        }
      }
      if ((normalizedIssueSeverity != null &&
              normalizedIssueSeverity.isNotEmpty &&
              normalizedIssueSeverity != 'all') ||
          (normalizedIssueStage != null &&
              normalizedIssueStage.isNotEmpty &&
              normalizedIssueStage != 'all')) {
        final matchesIssueFilters = entry.issues.any((issue) {
          if (normalizedIssueSeverity != null &&
              normalizedIssueSeverity.isNotEmpty &&
              normalizedIssueSeverity != 'all' &&
              issue.severity.toLowerCase() != normalizedIssueSeverity) {
            return false;
          }
          if (normalizedIssueStage != null &&
              normalizedIssueStage.isNotEmpty &&
              normalizedIssueStage != 'all' &&
              issue.stage.toLowerCase() != normalizedIssueStage) {
            return false;
          }
          return true;
        });
        if (!matchesIssueFilters) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    DateTime? cursorStartedAt;
    String? cursorRunId;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorStartedAt = DateTime.parse(parts.first).toUtc();
        cursorRunId = parts.last;
      }
    }
    final filteredRuns = allFilteredRuns.where((entry) {
      if (cursorStartedAt != null && cursorRunId != null) {
        final startedAt = DateTime.parse(entry.startedAtIso).toUtc();
        if (startedAt.isAfter(cursorStartedAt!)) {
          return false;
        }
        if (startedAt.isAtSameMomentAs(cursorStartedAt!) &&
            entry.importRunId.compareTo(cursorRunId!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    final pageRuns = filteredRuns.take(limit).toList(growable: false);
    final nextCursor = filteredRuns.length > limit && pageRuns.isNotEmpty
        ? '${pageRuns.last.startedAtIso}|${pageRuns.last.importRunId}'
        : null;
    String? latestSucceededAtIso;
    for (final entry in allFilteredRuns) {
      if (entry.isSucceeded) {
        latestSucceededAtIso = entry.finishedAtIso;
        break;
      }
    }
    return CoachOperatorCatalogImportRunsResponse(
      generatedAtIso:
          (allFilteredRuns.isNotEmpty ? allFilteredRuns.first : allRuns.first)
              .startedAtIso,
      summary: CoachOperatorCatalogImportRunsSummary(
        totalRuns: allFilteredRuns.length,
        succeededRuns:
            allFilteredRuns.where((entry) => entry.isSucceeded).length,
        failedRuns: allFilteredRuns.where((entry) => entry.isFailed).length,
        runningRuns: allFilteredRuns.where((entry) => entry.isRunning).length,
        importedRecordsTotal: allFilteredRuns
            .where((entry) => entry.isSucceeded)
            .fold<int>(0, (sum, entry) => sum + entry.counts.totalRecords),
        latestSucceededAtIso: latestSucceededAtIso,
      ),
      importRuns: pageRuns,
      nextCursor: nextCursor,
    );
  }

  CoachOperatorCatalogImportRunDetailResponse catalogImportRunDetailSnapshot(
    String importRunId, {
    int limit = 8,
    String? cursor,
    String? issueSeverity,
    String? issueStage,
  }) {
    final normalizedImportRunId = importRunId.trim();
    final existing = catalogImportRunsSnapshot(limit: 20).importRuns.firstWhere(
          (entry) => entry.importRunId == normalizedImportRunId,
          orElse: () => const CoachOperatorCatalogImportRun(
            importRunId: 'catalogimportrun_detail_missing',
            feedKind: 'static_catalog',
            sourceKind: 'gtfs',
            triggerKind: 'manual',
            feedLocator: '/srv/feeds/operator_a',
            replayedFromImportRunId: null,
            sourceArtifactId: null,
            sourceArtifact: null,
            status: 'failed',
            startedAtIso: '2026-04-14T10:08:00Z',
            finishedAtIso: '2026-04-14T10:09:00Z',
            counts: CoachOperatorCatalogImportRunCounts(
              operators: 0,
              cities: 0,
              stopClusters: 0,
              stops: 0,
              lines: 0,
              serviceCalendars: 0,
              trips: 0,
              fareProducts: 0,
              totalRecords: 0,
              ready: false,
            ),
            errorMessage: 'missing',
            issues: <CoachOperatorCatalogImportRunIssue>[],
          ),
        );
    final allIssues = existing.importRunId == 'catalogimportrun_demo_failed'
        ? const <CoachOperatorCatalogImportRunIssue>[
            CoachOperatorCatalogImportRunIssue(
              issueId: 'catalogimportissue_demo_failed_1',
              severity: 'error',
              stage: 'load_feed',
              code: 'required_file_missing',
              message: 'required GTFS file missing: stops.txt',
              fileName: 'stops.txt',
              rowReference: null,
            ),
            CoachOperatorCatalogImportRunIssue(
              issueId: 'catalogimportissue_demo_failed_2',
              severity: 'error',
              stage: 'parse_stop_times',
              code: 'invalid_time_value',
              message: 'stop_times.txt contains invalid departure_time',
              fileName: 'stop_times.txt',
              rowReference: 'row:42',
            ),
            CoachOperatorCatalogImportRunIssue(
              issueId: 'catalogimportissue_demo_failed_3',
              severity: 'warning',
              stage: 'hydrate_trip',
              code: 'partial_trip_skip',
              message: 'trip skipped because terminal stop was missing',
              fileName: 'trips.txt',
              rowReference: 'trip:42',
            ),
          ]
        : existing.issues;
    final normalizedSeverity = issueSeverity?.trim().toLowerCase();
    final normalizedStage = issueStage?.trim().toLowerCase();
    final allFilteredIssues = allIssues.where((entry) {
      if (normalizedSeverity != null &&
          normalizedSeverity.isNotEmpty &&
          normalizedSeverity != 'all' &&
          entry.severity.toLowerCase() != normalizedSeverity) {
        return false;
      }
      if (normalizedStage != null &&
          normalizedStage.isNotEmpty &&
          normalizedStage != 'all' &&
          entry.stage.toLowerCase() != normalizedStage) {
        return false;
      }
      return true;
    }).toList(growable: false);
    final normalizedCursor = cursor?.trim();
    final filteredIssues = allFilteredIssues.where((entry) {
      if (normalizedCursor == null || normalizedCursor.isEmpty) {
        return true;
      }
      return entry.issueId.compareTo(normalizedCursor) > 0;
    }).toList(growable: false);
    filteredIssues.sort((left, right) => left.issueId.compareTo(right.issueId));
    final pageIssues = filteredIssues.take(limit).toList(growable: false);
    final nextCursor = filteredIssues.length > limit && pageIssues.isNotEmpty
        ? pageIssues.last.issueId
        : null;
    final errorIssues =
        allFilteredIssues.where((entry) => entry.severity == 'error').length;
    final warningIssues =
        allFilteredIssues.where((entry) => entry.severity == 'warning').length;
    return CoachOperatorCatalogImportRunDetailResponse(
      generatedAtIso: existing.startedAtIso,
      issuesSummary: CoachOperatorCatalogImportRunIssuesSummary(
        totalIssues: allIssues.length,
        filteredIssues: allFilteredIssues.length,
        errorIssues: errorIssues,
        warningIssues: warningIssues,
      ),
      issuesFilters: CoachOperatorCatalogImportRunIssueFilters(
        severity: normalizedSeverity == null ||
                normalizedSeverity.isEmpty ||
                normalizedSeverity == 'all'
            ? null
            : normalizedSeverity,
        stage: normalizedStage == null ||
                normalizedStage.isEmpty ||
                normalizedStage == 'all'
            ? null
            : normalizedStage,
        availableSeverities: allIssues
            .map((entry) => entry.severity)
            .toSet()
            .toList(growable: true)
          ..sort(),
        availableStages:
            allIssues.map((entry) => entry.stage).toSet().toList(growable: true)
              ..sort(),
      ),
      issuesNextCursor: nextCursor,
      importRun: CoachOperatorCatalogImportRun(
        importRunId: existing.importRunId,
        feedKind: existing.feedKind,
        sourceKind: existing.sourceKind,
        triggerKind: existing.triggerKind,
        feedLocator: existing.feedLocator,
        replayedFromImportRunId: existing.replayedFromImportRunId,
        replayLineageSummary: existing.replayLineageSummary,
        sourceArtifactId: existing.sourceArtifactId,
        sourceArtifact: existing.sourceArtifact,
        status: existing.status,
        startedAtIso: existing.startedAtIso,
        finishedAtIso: existing.finishedAtIso,
        counts: existing.counts,
        errorMessage: existing.errorMessage,
        issues: pageIssues,
      ),
    );
  }

  CoachOperatorCatalogImportRunLineageResponse catalogImportRunLineageSnapshot(
    String importRunId, {
    int limit = 8,
    String? cursor,
  }) {
    final normalizedImportRunId = importRunId.trim();
    final importRun = catalogImportRunDetailSnapshot(
      normalizedImportRunId,
      limit: 20,
    ).importRun;
    final allReplayRuns =
        normalizedImportRunId == 'catalogimportrun_demo_failed'
            ? const <CoachOperatorCatalogImportRun>[
                CoachOperatorCatalogImportRun(
                  importRunId: 'catalogimportrun_demo_failed_replay_2',
                  feedKind: 'static_catalog',
                  sourceKind: 'gtfs',
                  triggerKind: 'manual',
                  feedLocator: '/srv/feeds/operator_a_replay_2',
                  replayedFromImportRunId: 'catalogimportrun_demo_failed',
                  sourceArtifactId: 'catalogsourceartifact_demo_failed',
                  sourceArtifact: null,
                  status: 'succeeded',
                  startedAtIso: '2026-04-15T10:10:00Z',
                  finishedAtIso: '2026-04-15T10:10:30Z',
                  counts: CoachOperatorCatalogImportRunCounts(
                    operators: 1,
                    cities: 2,
                    stopClusters: 2,
                    stops: 4,
                    lines: 1,
                    serviceCalendars: 1,
                    trips: 2,
                    fareProducts: 2,
                    totalRecords: 15,
                    ready: true,
                  ),
                  errorMessage: null,
                  issues: <CoachOperatorCatalogImportRunIssue>[],
                ),
                CoachOperatorCatalogImportRun(
                  importRunId: 'catalogimportrun_demo_failed_replay_1',
                  feedKind: 'static_catalog',
                  sourceKind: 'gtfs',
                  triggerKind: 'manual',
                  feedLocator: '/srv/feeds/operator_a_replay_1',
                  replayedFromImportRunId: 'catalogimportrun_demo_failed',
                  sourceArtifactId: 'catalogsourceartifact_demo_failed',
                  sourceArtifact: null,
                  status: 'failed',
                  startedAtIso: '2026-04-14T10:10:00Z',
                  finishedAtIso: '2026-04-14T10:10:15Z',
                  counts: CoachOperatorCatalogImportRunCounts(
                    operators: 0,
                    cities: 0,
                    stopClusters: 0,
                    stops: 0,
                    lines: 0,
                    serviceCalendars: 0,
                    trips: 0,
                    fareProducts: 0,
                    totalRecords: 0,
                    ready: false,
                  ),
                  errorMessage: 'replay failed',
                  issues: <CoachOperatorCatalogImportRunIssue>[],
                ),
                CoachOperatorCatalogImportRun(
                  importRunId: 'catalogimportrun_demo_failed_replay_0',
                  feedKind: 'static_catalog',
                  sourceKind: 'gtfs',
                  triggerKind: 'manual',
                  feedLocator: '/srv/feeds/operator_a_replay_0',
                  replayedFromImportRunId: 'catalogimportrun_demo_failed',
                  sourceArtifactId: 'catalogsourceartifact_demo_failed',
                  sourceArtifact: null,
                  status: 'running',
                  startedAtIso: '2026-04-13T10:10:00Z',
                  finishedAtIso: null,
                  counts: CoachOperatorCatalogImportRunCounts(
                    operators: 0,
                    cities: 0,
                    stopClusters: 0,
                    stops: 0,
                    lines: 0,
                    serviceCalendars: 0,
                    trips: 0,
                    fareProducts: 0,
                    totalRecords: 0,
                    ready: false,
                  ),
                  errorMessage: null,
                  issues: <CoachOperatorCatalogImportRunIssue>[],
                ),
              ]
            : const <CoachOperatorCatalogImportRun>[];
    final normalizedCursor = cursor?.trim();
    DateTime? cursorStartedAt;
    String? cursorRunId;
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorStartedAt = DateTime.parse(parts.first).toUtc();
        cursorRunId = parts.last;
      }
    }
    final filteredRuns = allReplayRuns.where((entry) {
      if (cursorStartedAt != null && cursorRunId != null) {
        final startedAt = DateTime.parse(entry.startedAtIso).toUtc();
        if (startedAt.isAfter(cursorStartedAt!)) {
          return false;
        }
        if (startedAt.isAtSameMomentAs(cursorStartedAt!) &&
            entry.importRunId.compareTo(cursorRunId!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    final pageRuns = filteredRuns.take(limit).toList(growable: false);
    final nextCursor = filteredRuns.length > limit && pageRuns.isNotEmpty
        ? '${pageRuns.last.startedAtIso}|${pageRuns.last.importRunId}'
        : null;
    return CoachOperatorCatalogImportRunLineageResponse(
      generatedAtIso: importRun.startedAtIso,
      importRun: importRun,
      replayRunsSummary: CoachOperatorCatalogImportRunReplayRunsSummary(
        totalRuns: allReplayRuns.length,
        failedRuns: allReplayRuns.where((entry) => entry.isFailed).length,
        succeededRuns: allReplayRuns.where((entry) => entry.isSucceeded).length,
        runningRuns: allReplayRuns.where((entry) => entry.isRunning).length,
        latestStartedAtIso:
            allReplayRuns.isEmpty ? null : allReplayRuns.first.startedAtIso,
      ),
      replayRunsNextCursor: nextCursor,
      replayRuns: pageRuns,
    );
  }

  CoachOperatorFeedHealthResponse operatorFeedHealthSnapshot() {
    return const CoachOperatorFeedHealthResponse(
      generatedAtIso: '2026-04-15T10:06:00Z',
      summary: CoachOperatorFeedHealthSummary(
        operatorsTotal: 2,
        healthyOperators: 1,
        degradedFeeds: 1,
        staleFeeds: 1,
      ),
      feeds: <CoachOperatorFeedHealth>[
        CoachOperatorFeedHealth(
          operatorId: 'op_demo_b',
          operatorName: 'Demo B',
          operatorIntegrationMode: 'hybrid',
          feedKind: 'gtfs_rt_trip_updates',
          sourceKind: 'gtfs_rt',
          syncStatus: 'error',
          freshnessStatus: 'stale',
          lastAttemptedAtIso: '2026-04-15T10:05:00Z',
          lastSucceededAtIso: null,
          freshnessExpiresAtIso: null,
          recordsIngested: 0,
          errorMessage: 'upstream timeout',
        ),
        CoachOperatorFeedHealth(
          operatorId: 'op_demo_a',
          operatorName: 'Demo A',
          operatorIntegrationMode: 'feed',
          feedKind: 'static_catalog',
          sourceKind: 'gtfs',
          syncStatus: 'ok',
          freshnessStatus: 'fresh',
          lastAttemptedAtIso: '2026-04-15T10:04:00Z',
          lastSucceededAtIso: '2026-04-15T10:04:00Z',
          freshnessExpiresAtIso: '2026-04-16T10:04:00Z',
          recordsIngested: 12,
          errorMessage: null,
        ),
      ],
    );
  }

  CoachOperatorCatalogImportConfigResponse catalogImportConfigSnapshot({
    bool ready = true,
    bool? configured,
    String? feedLocator,
    String? detail,
    String configOrigin = 'database',
    CoachOperatorCatalogSourceArtifact? sourceArtifactOverride,
    CoachOperatorCatalogImportRun? latestImportRunOverride,
  }) {
    final latestRunSnapshot = catalogImportRunsSnapshot(limit: 1).importRuns;
    final effectiveReady = ready && currentCatalogImportConfigReady;
    final effectiveFeedLocator = feedLocator ??
        (ready ? currentCatalogImportFeedLocator : '/srv/feeds/missing');
    final sourceArtifact = sourceArtifactOverride ??
        (currentCatalogImportSourceArtifact?.feedLocator == effectiveFeedLocator
            ? currentCatalogImportSourceArtifact
            : null);
    return CoachOperatorCatalogImportConfigResponse(
      generatedAtIso: '2026-04-15T10:07:00Z',
      sourceKind: 'gtfs',
      configured: configured ?? true,
      feedLocator: effectiveFeedLocator,
      status: effectiveReady ? 'ready' : 'missing',
      detail: detail ??
          (effectiveReady
              ? 'GTFS feed directory is configured.'
              : 'Configured GTFS feed directory does not exist.'),
      configOrigin: configOrigin,
      sourceArtifact: sourceArtifact,
      updatedAtIso: '2026-04-15T10:07:00Z',
      updatedByAccountId: 'acct_ops_demo',
      latestImportRun: latestImportRunOverride ??
          (latestRunSnapshot.isEmpty ? null : latestRunSnapshot.first),
    );
  }

  CoachOperatorCatalogImportSourcesResponse catalogImportSourcesSnapshot() {
    final currentLocator = currentCatalogImportFeedLocator;
    final savedSourceArtifact =
        currentCatalogImportSourceArtifact?.feedLocator == currentLocator
            ? currentCatalogImportSourceArtifact
            : null;
    final sources = <CoachOperatorCatalogImportSourceOption>[
      CoachOperatorCatalogImportSourceOption(
        sourceKind: 'gtfs',
        feedLocator: currentLocator,
        sourceOrigin: 'database_saved',
        sourceLabel: savedSourceArtifact?.sourceLabel ?? 'Saved feed locator',
        status: currentCatalogImportConfigReady ? 'ready' : 'missing',
        detail: currentCatalogImportConfigReady
            ? 'GTFS feed directory is configured.'
            : 'Configured GTFS feed directory does not exist.',
        selected: true,
      ),
      const CoachOperatorCatalogImportSourceOption(
        sourceKind: 'gtfs',
        feedLocator: '/srv/feeds/operator_env_default',
        sourceOrigin: 'environment_default',
        sourceLabel: 'Environment default',
        status: 'ready',
        detail: 'GTFS feed directory is configured.',
        selected: false,
      ),
      const CoachOperatorCatalogImportSourceOption(
        sourceKind: 'gtfs',
        feedLocator: '/srv/feeds/operator_option_b',
        sourceOrigin: 'environment_option',
        sourceLabel: 'Configured source 1',
        status: 'missing',
        detail: 'Configured GTFS feed directory does not exist.',
        selected: false,
      ),
    ];
    final seenLocators = <String>{};
    return CoachOperatorCatalogImportSourcesResponse(
      generatedAtIso: '2026-04-15T10:07:10Z',
      sources: sources.where((entry) {
        final locator = entry.feedLocator.trim();
        if (locator.isEmpty || !seenLocators.add(locator)) {
          return false;
        }
        return true;
      }).toList(growable: false),
    );
  }

  CoachOperatorCatalogSourceArtifactsResponse catalogSourceArtifactsSnapshot({
    int limit = 8,
    String? cursor,
  }) {
    final allArtifacts = <CoachOperatorCatalogSourceArtifact>[
      currentCatalogImportSourceArtifact ??
          _catalogImportSourceArtifactSnapshot(
            artifactId: 'catalogsourceartifact_demo_current',
            sourceLabel: 'operator_a_feed.zip',
            fileName: 'operator_a_feed.zip',
            contentLengthBytes: 1024,
            extractedFileCount: 7,
            feedLocator: currentCatalogImportFeedLocator,
          ),
      _catalogImportSourceArtifactSnapshot(
        artifactId: 'catalogsourceartifact_demo_previous',
        sourceLabel: 'operator_a_feed_v1.zip',
        fileName: 'operator_a_feed_v1.zip',
        contentLengthBytes: 864,
        extractedFileCount: 7,
        feedLocator: '/srv/feeds/operator_a_v1',
        createdAtIso: '2026-04-14T08:00:00Z',
      ),
      _catalogImportSourceArtifactSnapshot(
        artifactId: 'catalogsourceartifact_demo_oldest',
        sourceLabel: 'operator_a_feed_v0.zip',
        fileName: 'operator_a_feed_v0.zip',
        contentLengthBytes: 640,
        extractedFileCount: 7,
        feedLocator: '/srv/feeds/operator_a_v0',
        createdAtIso: '2026-04-13T08:00:00Z',
      ),
    ];
    allArtifacts.sort((left, right) {
      final createdAtCompare = right.createdAtIso.compareTo(left.createdAtIso);
      if (createdAtCompare != 0) {
        return createdAtCompare;
      }
      return right.artifactId.compareTo(left.artifactId);
    });
    DateTime? cursorCreatedAt;
    String? cursorArtifactId;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorCreatedAt = DateTime.parse(parts.first).toUtc();
        cursorArtifactId = parts.last;
      }
    }
    final filteredArtifacts = allArtifacts.where((entry) {
      if (cursorCreatedAt != null && cursorArtifactId != null) {
        final createdAt = DateTime.parse(entry.createdAtIso).toUtc();
        if (createdAt.isAfter(cursorCreatedAt!)) {
          return false;
        }
        if (createdAt.isAtSameMomentAs(cursorCreatedAt!) &&
            entry.artifactId.compareTo(cursorArtifactId!) >= 0) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    final pageArtifacts = filteredArtifacts.take(limit).toList(growable: false);
    final nextCursor = filteredArtifacts.length > limit &&
            pageArtifacts.isNotEmpty
        ? '${pageArtifacts.last.createdAtIso}|${pageArtifacts.last.artifactId}'
        : null;
    return CoachOperatorCatalogSourceArtifactsResponse(
      generatedAtIso: allArtifacts.first.createdAtIso,
      summary: CoachOperatorCatalogSourceArtifactsSummary(
        totalArtifacts: allArtifacts.length,
        uploadedBytesTotal: allArtifacts.fold<int>(
          0,
          (sum, entry) => sum + entry.contentLengthBytes,
        ),
        latestCreatedAtIso: allArtifacts.first.createdAtIso,
      ),
      artifacts: pageArtifacts,
      nextCursor: nextCursor,
    );
  }

  CoachOperatorCatalogSourceArtifactDetailResponse
      catalogSourceArtifactDetailSnapshot(
    String artifactId, {
    int limit = 8,
    String? cursor,
  }) {
    final normalizedArtifactId = artifactId.trim();
    final artifact =
        catalogSourceArtifactsSnapshot(limit: 20).artifacts.firstWhere(
              (entry) => entry.artifactId == normalizedArtifactId,
              orElse: () => _catalogImportSourceArtifactSnapshot(
                artifactId: normalizedArtifactId.isEmpty
                    ? 'catalogsourceartifact_detail_missing'
                    : normalizedArtifactId,
                sourceLabel: 'Missing artifact',
                fileName: 'missing_artifact.zip',
                contentLengthBytes: 0,
                extractedFileCount: 0,
                feedLocator: '/srv/feeds/missing',
              ),
            );
    final referencingImportRuns = catalogImportRunsSnapshot(limit: 20)
        .importRuns
        .where(
          (entry) =>
              entry.sourceArtifactId == artifact.artifactId ||
              entry.sourceArtifact?.artifactId == artifact.artifactId,
        )
        .toList(growable: false);
    DateTime? cursorStartedAt;
    String? cursorImportRunId;
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      final parts = normalizedCursor.split('|');
      if (parts.length == 2) {
        cursorStartedAt = DateTime.parse(parts.first).toUtc();
        cursorImportRunId = parts.last;
      }
    }
    final filteredImportRuns = referencingImportRuns.where((entry) {
      if (cursorStartedAt == null || cursorImportRunId == null) {
        return true;
      }
      final startedAt = DateTime.parse(entry.startedAtIso).toUtc();
      if (startedAt.isAfter(cursorStartedAt!)) {
        return false;
      }
      if (startedAt.isAtSameMomentAs(cursorStartedAt!) &&
          entry.importRunId.compareTo(cursorImportRunId!) >= 0) {
        return false;
      }
      return true;
    }).toList(growable: false);
    final pageImportRuns =
        filteredImportRuns.take(limit).toList(growable: false);
    final nextCursor = filteredImportRuns.length > limit &&
            pageImportRuns.isNotEmpty
        ? '${pageImportRuns.last.startedAtIso}|${pageImportRuns.last.importRunId}'
        : null;
    return CoachOperatorCatalogSourceArtifactDetailResponse(
      generatedAtIso: '2026-04-15T10:18:00Z',
      sourceArtifact: artifact,
      referencingImportRunsSummary:
          CoachOperatorCatalogSourceArtifactReferencingRunsSummary(
        totalRuns: referencingImportRuns.length,
        failedRuns: referencingImportRuns
            .where((entry) => entry.status == 'failed')
            .length,
        succeededRuns: referencingImportRuns
            .where((entry) => entry.status == 'succeeded')
            .length,
        runningRuns: referencingImportRuns
            .where((entry) => entry.status == 'running')
            .length,
        latestStartedAtIso: referencingImportRuns.isEmpty
            ? null
            : referencingImportRuns.first.startedAtIso,
      ),
      referencingImportRunsNextCursor: nextCursor,
      referencingImportRuns: pageImportRuns,
    );
  }

  CoachOperatorPayoutReconciliationResponse payoutReconciliationSnapshot({
    int limit = 8,
    String? cursor,
  }) {
    CoachOperatorPayoutReconciliationRun buildReconciliationRun(
      CoachOperatorPayoutRun run,
    ) {
      final readyExportFormats = run.exports
          .where((value) => value.isReady)
          .map((value) => value.exportFormat)
          .toList(growable: false);
      final readyKeys =
          readyExportFormats.map((value) => value.trim().toLowerCase()).toSet();
      final missingExportFormats = run.availableExportFormats
          .where((value) => !readyKeys.contains(value.trim().toLowerCase()))
          .toList(growable: false);
      late final String reconciliationStatus;
      late final bool needsAttention;
      late final List<String> attentionReasons;
      late final String nextAction;
      if (run.status == 'failed') {
        reconciliationStatus = 'payout_failed';
        needsAttention = true;
        attentionReasons = const <String>[
          'Payout execution failed in the banking rail.',
        ];
        nextAction = 'Requeue the payout or escalate the failed bank transfer.';
      } else if (run.isQueued) {
        reconciliationStatus = 'awaiting_bank_execution';
        needsAttention = false;
        attentionReasons = const <String>[];
        nextAction = 'Wait for the external payout rail to confirm execution.';
      } else if ((run.paymentReference ?? '').isEmpty) {
        reconciliationStatus = 'missing_payment_reference';
        needsAttention = true;
        attentionReasons = const <String>[
          'Bank payment reference is missing for this paid run.',
        ];
        nextAction =
            'Attach the bank payout reference before closing reconciliation.';
      } else if (readyExportFormats.isEmpty &&
          run.availableExportFormats.isNotEmpty) {
        reconciliationStatus = 'missing_exports';
        needsAttention = true;
        attentionReasons = const <String>[
          'No settlement export artifact has been generated yet.',
        ];
        nextAction =
            'Generate the required settlement export artifacts for finance.';
      } else if (missingExportFormats.isNotEmpty) {
        reconciliationStatus = 'partial_exports';
        needsAttention = true;
        attentionReasons = <String>[
          'Missing export artifacts: ${missingExportFormats.join(', ')}.',
        ];
        nextAction =
            'Generate the missing export formats before publishing the statement pack.';
      } else {
        reconciliationStatus = 'balanced';
        needsAttention = false;
        attentionReasons = const <String>[];
        nextAction = 'No further reconciliation action required.';
      }
      return CoachOperatorPayoutReconciliationRun(
        payoutRunId: run.payoutRunId,
        runStatus: run.status,
        reconciliationStatus: reconciliationStatus,
        currency: run.currency,
        operatorNames: run.operatorNames,
        statementIds: run.statementIds,
        paymentReference: run.paymentReference,
        netPayableMinorUnits: run.netPayableMinorUnits,
        availableExportFormats: run.availableExportFormats,
        readyExportFormats: readyExportFormats,
        missingExportFormats: missingExportFormats,
        createdAtIso: run.createdAtIso,
        paidAtIso: run.paidAtIso,
        needsAttention: needsAttention,
        attentionReasons: attentionReasons,
        nextAction: nextAction,
      );
    }

    final allRuns = payoutRunsSnapshot(limit: 100, cursor: null)
        .runs
        .map(buildReconciliationRun)
        .toList(growable: false);
    final runs = payoutRunsSnapshot(limit: limit, cursor: cursor)
        .runs
        .map(buildReconciliationRun)
        .toList(growable: false);
    return CoachOperatorPayoutReconciliationResponse(
      generatedAtIso: '2026-04-07T16:05:00Z',
      summary: CoachOperatorPayoutReconciliationSummary(
        currency: 'SYP',
        runCount: allRuns.length,
        balancedRuns: allRuns
            .where((value) => value.reconciliationStatus == 'balanced')
            .length,
        attentionRuns: allRuns.where((value) => value.needsAttention).length,
        queuedRuns:
            allRuns.where((value) => value.runStatus == 'queued').length,
        failedRuns:
            allRuns.where((value) => value.runStatus == 'failed').length,
        missingPaymentReferenceRuns: allRuns
            .where(
              (value) =>
                  value.reconciliationStatus == 'missing_payment_reference',
            )
            .length,
        missingExportsRuns: allRuns
            .where((value) => value.reconciliationStatus == 'missing_exports')
            .length,
        partialExportRuns: allRuns
            .where((value) => value.reconciliationStatus == 'partial_exports')
            .length,
        paidNetPayableMinorUnits:
            allRuns.where((value) => value.runStatus == 'paid').fold<int>(
                  0,
                  (sum, value) => sum + value.netPayableMinorUnits,
                ),
        attentionNetPayableMinorUnits:
            allRuns.where((value) => value.needsAttention).fold<int>(
                  0,
                  (sum, value) => sum + value.netPayableMinorUnits,
                ),
      ),
      runs: runs,
      nextCursor: payoutRunsSnapshot(limit: limit, cursor: cursor).nextCursor,
    );
  }

  @override
  Future<CoachOperatorRefundQueueResponse> operatorRefundQueue({
    int limit = 20,
  }) async {
    refundQueueCalls++;
    return refundQueueSnapshot();
  }

  @override
  Future<CoachOperatorChangeQueueResponse> operatorChangeQueue({
    int limit = 20,
  }) async {
    changeQueueCalls++;
    return changeQueueSnapshot();
  }

  @override
  Future<CoachOperatorReconciliationResponse> operatorReconciliation({
    int limit = 12,
  }) async {
    reconciliationCalls++;
    return reconciliationSnapshot();
  }

  @override
  Future<CoachOperatorSettlementStatementsResponse>
      operatorSettlementStatements({
    int limit = 8,
    String? cursor,
  }) async {
    settlementStatementsCalls++;
    lastSettlementStatementCursor = cursor?.trim();
    return settlementStatementsSnapshot(limit: limit, cursor: cursor);
  }

  @override
  Future<CoachOperatorPayoutRunsResponse> operatorPayoutRuns({
    int limit = 8,
    String? cursor,
  }) async {
    payoutRunsCalls++;
    lastPayoutRunCursor = cursor?.trim();
    return payoutRunsSnapshot(limit: limit, cursor: cursor);
  }

  @override
  Future<CoachOperatorPayoutReconciliationResponse>
      operatorPayoutReconciliation({
    int limit = 8,
    String? cursor,
  }) async {
    payoutReconciliationCalls++;
    lastPayoutReconciliationCursor = cursor?.trim();
    return payoutReconciliationSnapshot(limit: limit, cursor: cursor);
  }

  @override
  Future<CoachOperatorFeedHealthResponse> operatorFeedHealth() async {
    operatorFeedHealthCalls++;
    return operatorFeedHealthSnapshot();
  }

  @override
  Future<CoachOperatorCatalogImportConfigResponse>
      operatorCatalogImportConfig() async {
    operatorCatalogImportConfigCalls++;
    return catalogImportConfigSnapshot();
  }

  @override
  Future<CoachOperatorCatalogImportSourcesResponse>
      operatorCatalogImportSources() async {
    operatorCatalogImportSourcesCalls++;
    return catalogImportSourcesSnapshot();
  }

  @override
  Future<CoachOperatorCatalogSourceArtifactsResponse>
      operatorCatalogSourceArtifacts({
    int limit = 8,
    String? cursor,
  }) async {
    operatorCatalogSourceArtifactsCalls++;
    lastCatalogSourceArtifactCursor = cursor?.trim();
    return catalogSourceArtifactsSnapshot(limit: limit, cursor: cursor);
  }

  @override
  Future<CoachOperatorCatalogSourceArtifactDetailResponse>
      operatorCatalogSourceArtifact(
    String artifactId, {
    int limit = 8,
    String? cursor,
  }) async {
    catalogSourceArtifactDetailCalls++;
    lastCatalogSourceArtifactDetailId = artifactId.trim();
    return catalogSourceArtifactDetailSnapshot(
      artifactId,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<CoachOperatorCatalogImportConfigMutationResult>
      updateOperatorCatalogImportConfig({
    required String feedLocator,
    String? idempotencyKey,
  }) async {
    catalogImportConfigUpdateCalls++;
    lastCatalogImportFeedLocator = feedLocator.trim();
    final configuredError = catalogImportConfigUpdateError;
    if (configuredError != null) {
      throw configuredError;
    }
    currentCatalogImportFeedLocator = feedLocator.trim();
    currentCatalogImportConfigReady =
        !currentCatalogImportFeedLocator.toLowerCase().contains('missing');
    if (currentCatalogImportSourceArtifact?.feedLocator !=
        currentCatalogImportFeedLocator) {
      currentCatalogImportSourceArtifact = null;
    }
    return CoachOperatorCatalogImportConfigMutationResult(
      command: 'catalog_import_config_update',
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-ops-catalog-import-config-test-1',
        scope: 'coach_operator_catalog_import_config_update',
        requestFingerprint: 'fp_coach_catalog_import_config_1',
        replayed: false,
        derivedKeys: const <String, String>{},
      ),
      config: catalogImportConfigSnapshot(),
      nextAction: currentCatalogImportConfigReady
          ? 'catalog_import_ready'
          : 'verify_catalog_import_source',
    );
  }

  @override
  Future<CoachOperatorCatalogImportSourceUploadResult>
      uploadOperatorCatalogImportSourceFile({
    String sourceKind = 'gtfs',
    required Uint8List fileBytes,
    required String fileName,
    String? idempotencyKey,
  }) async {
    catalogImportSourceUploadCalls++;
    lastUploadedCatalogImportFileName = fileName.trim();
    lastUploadedCatalogImportFileBytesLength = fileBytes.length;
    final configuredError = catalogImportSourceUploadError;
    if (configuredError != null) {
      throw configuredError;
    }
    final normalizedFileName =
        fileName.trim().isEmpty ? 'coach_gtfs_upload.zip' : fileName.trim();
    final extractedStem = normalizedFileName.toLowerCase().endsWith('.zip')
        ? normalizedFileName.substring(0, normalizedFileName.length - 4)
        : normalizedFileName;
    currentCatalogImportFeedLocator =
        '/tmp/shamell_coach_gtfs_uploads/${extractedStem.replaceAll(' ', '_')}_uploaded';
    currentCatalogImportConfigReady = true;
    currentCatalogImportSourceArtifact = _catalogImportSourceArtifactSnapshot(
      artifactId: 'catalog_source_artifact_operator_b_feed_zip',
      sourceLabel: normalizedFileName,
      fileName: normalizedFileName,
      contentLengthBytes: fileBytes.length,
      extractedFileCount: 7,
      feedLocator: currentCatalogImportFeedLocator,
    );
    return CoachOperatorCatalogImportSourceUploadResult(
      command: 'catalog_import_source_upload',
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-ops-catalog-import-source-upload-test-1',
        scope: 'coach_operator_catalog_import_source_upload',
        requestFingerprint: 'fp_coach_catalog_import_source_upload_1',
        replayed: false,
        derivedKeys: const <String, String>{},
      ),
      uploadedSource: CoachOperatorCatalogImportUploadedSource(
        sourceArtifactId: currentCatalogImportSourceArtifact!.artifactId,
        sourceKind: sourceKind.trim().isEmpty ? 'gtfs' : sourceKind.trim(),
        sourceLabel: normalizedFileName,
        fileName: normalizedFileName,
        fileChecksumSha256: 'a' * 64,
        contentLengthBytes: fileBytes.length,
        feedLocator: currentCatalogImportFeedLocator,
        extractedFileCount: 7,
      ),
      config: catalogImportConfigSnapshot(),
      nextAction: 'catalog_import_ready',
    );
  }

  @override
  Future<CoachOperatorCatalogImportRunsResponse> operatorCatalogImportRuns({
    int limit = 8,
    String? cursor,
    String? status,
    String? replayScope,
    String? issueSeverity,
    String? issueStage,
  }) async {
    catalogImportRunsCalls++;
    lastCatalogImportRunCursor = cursor?.trim();
    lastCatalogImportRunStatusFilter = status?.trim();
    lastCatalogImportRunReplayScopeFilter = replayScope?.trim();
    lastCatalogImportRunIssueSeverityFilter = issueSeverity?.trim();
    lastCatalogImportRunIssueStageFilter = issueStage?.trim();
    return catalogImportRunsSnapshot(
      limit: limit,
      cursor: cursor,
      status: status,
      replayScope: replayScope,
      issueSeverity: issueSeverity,
      issueStage: issueStage,
    );
  }

  @override
  Future<List<CoachCatalogImportRunSavedView>>
      operatorCatalogImportRunSavedViews({
    String visibilityScope = 'all',
    String? ownerAccountId,
    String? operatorId,
  }) async {
    catalogImportRunSavedViewsCalls++;
    lastCatalogImportRunSavedViewsVisibilityScope = visibilityScope.trim();
    lastCatalogImportRunSavedViewsOwnerAccountId = ownerAccountId?.trim();
    lastCatalogImportRunSavedViewsOperatorId = operatorId?.trim();
    final normalizedScope = visibilityScope.trim().toLowerCase();
    final normalizedOwnerAccountId = switch ((ownerAccountId ?? '').trim()) {
      '' => '',
      'all' => '',
      final value => value,
    };
    final normalizedOperatorId = switch ((operatorId ?? '').trim()) {
      '' => '',
      'all' => '',
      final value => value,
    };
    final views = normalizedScope == 'all'
        ? catalogImportRunSavedViews
        : catalogImportRunSavedViews
            .where((entry) => entry.visibilityScope == normalizedScope)
            .toList(growable: false);
    final ownerFilteredViews =
        normalizedScope == 'shared_ops' && normalizedOwnerAccountId.isNotEmpty
            ? views
                .where((entry) => entry.accountId == normalizedOwnerAccountId)
                .toList(growable: false)
            : views;
    final filteredViews =
        normalizedScope == 'shared_ops' && normalizedOperatorId.isNotEmpty
            ? ownerFilteredViews
                .where(
                  (entry) =>
                      entry.visibilityScope != 'shared_ops' ||
                      _matchesSavedViewOperatorScope(
                        entry.operatorIds,
                        normalizedOperatorId,
                      ),
                )
                .toList(growable: false)
            : ownerFilteredViews;
    return _sortedCatalogImportRunSavedViews(filteredViews);
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorCatalogImportRunSavedViewOwners() async {
    catalogImportRunSavedViewOwnersCalls++;
    return _catalogImportRunSavedViewOwnersSnapshot();
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorCatalogImportRunSavedViewOperators() async {
    catalogImportRunSavedViewOperatorsCalls++;
    return _catalogImportRunSavedViewOperatorsSnapshot();
  }

  @override
  Future<List<CoachCatalogImportRunSavedView>>
      upsertOperatorCatalogImportRunSavedView(
    CoachCatalogImportRunSavedView view, {
    String? idempotencyKey,
  }) async {
    catalogImportRunSavedViewUpsertCalls++;
    final normalizedName = view.name.trim().toLowerCase();
    final normalizedScope = view.visibilityScope.trim().toLowerCase();
    final isDefault = view.isDefault && normalizedScope == 'personal';
    CoachCatalogImportRunSavedView? existingView;
    for (final candidate in catalogImportRunSavedViews) {
      if (candidate.viewId == view.viewId ||
          (candidate.name.trim().toLowerCase() == normalizedName &&
              candidate.visibilityScope.trim().toLowerCase() ==
                  normalizedScope)) {
        existingView = candidate;
        break;
      }
    }
    final persistedView = CoachCatalogImportRunSavedView(
      viewId: existingView?.viewId ?? view.viewId,
      accountId: existingView?.accountId ??
          (view.accountId.trim().isNotEmpty
              ? view.accountId
              : (normalizedScope == 'shared_ops'
                  ? 'acct_ops_shared'
                  : 'acct_ops_test')),
      name: view.name,
      visibilityScope: normalizedScope,
      operatorIds:
          normalizedScope == 'shared_ops' ? view.operatorIds : const <String>[],
      preferences: view.preferences,
      isDefault: isDefault,
      isFavorite: existingView?.isFavorite ?? view.isFavorite,
      lastUsedAtIso: existingView?.lastUsedAtIso ?? view.lastUsedAtIso,
      canManage: existingView?.canManage ?? view.canManage,
      createdAtIso: existingView?.createdAtIso ?? view.createdAtIso,
      updatedAtIso: view.updatedAtIso,
    );
    catalogImportRunSavedViews = _sortedCatalogImportRunSavedViews(
      <CoachCatalogImportRunSavedView>[
        persistedView,
        ...catalogImportRunSavedViews
            .where(
              (entry) =>
                  entry.viewId != persistedView.viewId &&
                  !(entry.name.trim().toLowerCase() == normalizedName &&
                      entry.visibilityScope.trim().toLowerCase() ==
                          normalizedScope),
            )
            .map(
              (entry) => persistedView.isDefault &&
                      entry.isDefault &&
                      entry.visibilityScope.trim().toLowerCase() == 'personal'
                  ? CoachCatalogImportRunSavedView(
                      viewId: entry.viewId,
                      accountId: entry.accountId,
                      name: entry.name,
                      visibilityScope: entry.visibilityScope,
                      operatorIds: entry.operatorIds,
                      preferences: entry.preferences,
                      isDefault: false,
                      isFavorite: entry.isFavorite,
                      lastUsedAtIso: entry.lastUsedAtIso,
                      canManage: entry.canManage,
                      createdAtIso: entry.createdAtIso,
                      updatedAtIso: entry.updatedAtIso,
                    )
                  : entry,
            ),
      ],
    );
    return catalogImportRunSavedViews;
  }

  @override
  Future<List<CoachCatalogImportRunSavedView>>
      deleteOperatorCatalogImportRunSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    catalogImportRunSavedViewDeleteCalls++;
    final normalizedViewId = viewId.trim();
    catalogImportRunSavedViews = _sortedCatalogImportRunSavedViews(
      catalogImportRunSavedViews
          .where((entry) => entry.viewId != normalizedViewId)
          .toList(growable: false),
    );
    return catalogImportRunSavedViews;
  }

  @override
  Future<List<CoachCatalogImportRunSavedView>>
      toggleOperatorCatalogImportRunSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    catalogImportRunSavedViews = _sortedCatalogImportRunSavedViews(
      catalogImportRunSavedViews
          .map(
            (entry) => entry.viewId == normalizedViewId
                ? CoachCatalogImportRunSavedView(
                    viewId: entry.viewId,
                    accountId: entry.accountId,
                    name: entry.name,
                    visibilityScope: entry.visibilityScope,
                    operatorIds: entry.operatorIds,
                    preferences: entry.preferences,
                    isDefault: entry.isDefault,
                    isFavorite: favorite,
                    lastUsedAtIso: entry.lastUsedAtIso,
                    canManage: entry.canManage,
                    createdAtIso: entry.createdAtIso,
                    updatedAtIso: entry.updatedAtIso,
                  )
                : entry,
          )
          .toList(growable: false),
    );
    return catalogImportRunSavedViews;
  }

  @override
  Future<String?> markOperatorCatalogImportRunSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    final normalizedUsedAtIso = (usedAtIso ?? '2026-04-16T10:00:00Z').trim();
    catalogImportRunSavedViews = _sortedCatalogImportRunSavedViews(
      catalogImportRunSavedViews
          .map(
            (entry) => entry.viewId == normalizedViewId
                ? CoachCatalogImportRunSavedView(
                    viewId: entry.viewId,
                    accountId: entry.accountId,
                    name: entry.name,
                    visibilityScope: entry.visibilityScope,
                    operatorIds: entry.operatorIds,
                    preferences: entry.preferences,
                    isDefault: entry.isDefault,
                    isFavorite: entry.isFavorite,
                    lastUsedAtIso: normalizedUsedAtIso,
                    canManage: entry.canManage,
                    createdAtIso: entry.createdAtIso,
                    updatedAtIso: entry.updatedAtIso,
                  )
                : entry,
          )
          .toList(growable: false),
    );
    return normalizedUsedAtIso;
  }

  @override
  Future<List<CoachCatalogImportRunIssueSavedView>>
      operatorCatalogImportRunIssueSavedViews({
    String visibilityScope = 'all',
    String? ownerAccountId,
    String? operatorId,
  }) async {
    catalogImportRunIssueSavedViewsCalls++;
    lastCatalogImportRunIssueSavedViewsVisibilityScope = visibilityScope.trim();
    lastCatalogImportRunIssueSavedViewsOwnerAccountId = ownerAccountId?.trim();
    lastCatalogImportRunIssueSavedViewsOperatorId = operatorId?.trim();
    final normalizedScope = visibilityScope.trim().toLowerCase();
    final normalizedOwnerAccountId = switch ((ownerAccountId ?? '').trim()) {
      '' => '',
      'all' => '',
      final value => value,
    };
    final normalizedOperatorId = switch ((operatorId ?? '').trim()) {
      '' => '',
      'all' => '',
      final value => value,
    };
    final views = normalizedScope == 'all'
        ? catalogImportRunIssueSavedViews
        : catalogImportRunIssueSavedViews
            .where((entry) => entry.visibilityScope == normalizedScope)
            .toList(growable: false);
    final ownerFilteredViews =
        normalizedScope == 'shared_ops' && normalizedOwnerAccountId.isNotEmpty
            ? views
                .where((entry) => entry.accountId == normalizedOwnerAccountId)
                .toList(growable: false)
            : views;
    final filteredViews =
        normalizedScope == 'shared_ops' && normalizedOperatorId.isNotEmpty
            ? ownerFilteredViews
                .where(
                  (entry) =>
                      entry.visibilityScope != 'shared_ops' ||
                      _matchesSavedViewOperatorScope(
                        entry.operatorIds,
                        normalizedOperatorId,
                      ),
                )
                .toList(growable: false)
            : ownerFilteredViews;
    return _sortedCatalogImportRunIssueSavedViews(filteredViews);
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorCatalogImportRunIssueSavedViewOwners() async {
    catalogImportRunIssueSavedViewOwnersCalls++;
    return _catalogImportRunIssueSavedViewOwnersSnapshot();
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorCatalogImportRunIssueSavedViewOperators() async {
    catalogImportRunIssueSavedViewOperatorsCalls++;
    return _catalogImportRunIssueSavedViewOperatorsSnapshot();
  }

  @override
  Future<List<CoachCatalogImportRunIssueSavedView>>
      upsertOperatorCatalogImportRunIssueSavedView(
    CoachCatalogImportRunIssueSavedView view, {
    String? idempotencyKey,
  }) async {
    catalogImportRunIssueSavedViewUpsertCalls++;
    final normalizedName = view.name.trim().toLowerCase();
    final normalizedScope = view.visibilityScope.trim().toLowerCase();
    final isDefault = view.isDefault && normalizedScope == 'personal';
    CoachCatalogImportRunIssueSavedView? existingView;
    for (final candidate in catalogImportRunIssueSavedViews) {
      if (candidate.viewId == view.viewId ||
          (candidate.name.trim().toLowerCase() == normalizedName &&
              candidate.visibilityScope.trim().toLowerCase() ==
                  normalizedScope)) {
        existingView = candidate;
        break;
      }
    }
    final persistedView = CoachCatalogImportRunIssueSavedView(
      viewId: existingView?.viewId ?? view.viewId,
      accountId: existingView?.accountId ??
          (view.accountId.trim().isNotEmpty
              ? view.accountId
              : (normalizedScope == 'shared_ops'
                  ? 'acct_ops_shared'
                  : 'acct_ops_test')),
      name: view.name,
      visibilityScope: normalizedScope,
      operatorIds:
          normalizedScope == 'shared_ops' ? view.operatorIds : const <String>[],
      preferences: view.preferences,
      isDefault: isDefault,
      isFavorite: existingView?.isFavorite ?? view.isFavorite,
      lastUsedAtIso: existingView?.lastUsedAtIso ?? view.lastUsedAtIso,
      canManage: existingView?.canManage ?? view.canManage,
      createdAtIso: existingView?.createdAtIso ?? view.createdAtIso,
      updatedAtIso: view.updatedAtIso,
    );
    catalogImportRunIssueSavedViews = _sortedCatalogImportRunIssueSavedViews(
      <CoachCatalogImportRunIssueSavedView>[
        persistedView,
        ...catalogImportRunIssueSavedViews
            .where(
              (entry) =>
                  entry.viewId != persistedView.viewId &&
                  !(entry.name.trim().toLowerCase() == normalizedName &&
                      entry.visibilityScope.trim().toLowerCase() ==
                          normalizedScope),
            )
            .map(
              (entry) => persistedView.isDefault &&
                      entry.isDefault &&
                      entry.visibilityScope.trim().toLowerCase() == 'personal'
                  ? CoachCatalogImportRunIssueSavedView(
                      viewId: entry.viewId,
                      accountId: entry.accountId,
                      name: entry.name,
                      visibilityScope: entry.visibilityScope,
                      operatorIds: entry.operatorIds,
                      preferences: entry.preferences,
                      isDefault: false,
                      isFavorite: entry.isFavorite,
                      lastUsedAtIso: entry.lastUsedAtIso,
                      canManage: entry.canManage,
                      createdAtIso: entry.createdAtIso,
                      updatedAtIso: entry.updatedAtIso,
                    )
                  : entry,
            ),
      ],
    );
    return catalogImportRunIssueSavedViews;
  }

  @override
  Future<List<CoachCatalogImportRunIssueSavedView>>
      deleteOperatorCatalogImportRunIssueSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    catalogImportRunIssueSavedViewDeleteCalls++;
    final normalizedViewId = viewId.trim();
    catalogImportRunIssueSavedViews = _sortedCatalogImportRunIssueSavedViews(
      catalogImportRunIssueSavedViews
          .where((entry) => entry.viewId != normalizedViewId)
          .toList(growable: false),
    );
    return catalogImportRunIssueSavedViews;
  }

  @override
  Future<List<CoachCatalogImportRunIssueSavedView>>
      toggleOperatorCatalogImportRunIssueSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    catalogImportRunIssueSavedViews = _sortedCatalogImportRunIssueSavedViews(
      catalogImportRunIssueSavedViews
          .map(
            (entry) => entry.viewId == normalizedViewId
                ? CoachCatalogImportRunIssueSavedView(
                    viewId: entry.viewId,
                    accountId: entry.accountId,
                    name: entry.name,
                    visibilityScope: entry.visibilityScope,
                    operatorIds: entry.operatorIds,
                    preferences: entry.preferences,
                    isDefault: entry.isDefault,
                    isFavorite: favorite,
                    lastUsedAtIso: entry.lastUsedAtIso,
                    canManage: entry.canManage,
                    createdAtIso: entry.createdAtIso,
                    updatedAtIso: entry.updatedAtIso,
                  )
                : entry,
          )
          .toList(growable: false),
    );
    return catalogImportRunIssueSavedViews;
  }

  @override
  Future<String?> markOperatorCatalogImportRunIssueSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    final normalizedUsedAtIso = (usedAtIso ?? '2026-04-16T10:00:00Z').trim();
    catalogImportRunIssueSavedViews = _sortedCatalogImportRunIssueSavedViews(
      catalogImportRunIssueSavedViews
          .map(
            (entry) => entry.viewId == normalizedViewId
                ? CoachCatalogImportRunIssueSavedView(
                    viewId: entry.viewId,
                    accountId: entry.accountId,
                    name: entry.name,
                    visibilityScope: entry.visibilityScope,
                    operatorIds: entry.operatorIds,
                    preferences: entry.preferences,
                    isDefault: entry.isDefault,
                    isFavorite: entry.isFavorite,
                    lastUsedAtIso: normalizedUsedAtIso,
                    canManage: entry.canManage,
                    createdAtIso: entry.createdAtIso,
                    updatedAtIso: entry.updatedAtIso,
                  )
                : entry,
          )
          .toList(growable: false),
    );
    return normalizedUsedAtIso;
  }

  @override
  Future<CoachOperatorCatalogImportRunDetailResponse> operatorCatalogImportRun(
    String importRunId, {
    int limit = 8,
    String? cursor,
    String? issueSeverity,
    String? issueStage,
  }) async {
    catalogImportRunDetailCalls++;
    lastCatalogImportRunDetailId = importRunId.trim();
    lastCatalogImportRunDetailCursor = cursor?.trim();
    lastCatalogImportRunDetailSeverity = issueSeverity?.trim();
    lastCatalogImportRunDetailStage = issueStage?.trim();
    return catalogImportRunDetailSnapshot(
      importRunId,
      limit: limit,
      cursor: cursor,
      issueSeverity: issueSeverity,
      issueStage: issueStage,
    );
  }

  @override
  Future<CoachOperatorCatalogImportRunLineageResponse>
      operatorCatalogImportRunLineage(
    String importRunId, {
    int limit = 8,
    String? cursor,
  }) async {
    catalogImportRunLineageCalls++;
    lastCatalogImportRunLineageId = importRunId.trim();
    lastCatalogImportRunLineageCursor = cursor?.trim();
    return catalogImportRunLineageSnapshot(
      importRunId,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<CoachOperatorCatalogImportRunMutationResult>
      triggerOperatorCatalogImportRun({
    String? sourceArtifactId,
    String? replayImportRunId,
    String? idempotencyKey,
  }) async {
    catalogImportRunTriggerCalls++;
    lastTriggeredCatalogImportSourceArtifactId = sourceArtifactId?.trim();
    lastTriggeredCatalogReplayImportRunId = replayImportRunId?.trim();
    final configuredError = catalogImportRunTriggerError;
    if (configuredError != null) {
      throw configuredError;
    }
    final replayedRun =
        replayImportRunId == null || replayImportRunId.trim().isEmpty
            ? null
            : catalogImportRunDetailSnapshot(replayImportRunId, limit: 20)
                .importRun;
    final selectedArtifact =
        sourceArtifactId == null || sourceArtifactId.trim().isEmpty
            ? currentCatalogImportSourceArtifact ?? replayedRun?.sourceArtifact
            : catalogSourceArtifactsSnapshot(limit: 20).artifacts.firstWhere(
                  (entry) => entry.artifactId == sourceArtifactId.trim(),
                  orElse: () =>
                      currentCatalogImportSourceArtifact ??
                      replayedRun?.sourceArtifact ??
                      _catalogImportSourceArtifactSnapshot(
                        artifactId: sourceArtifactId.trim(),
                        sourceLabel: 'Selected artifact',
                        fileName: 'selected_artifact.zip',
                        contentLengthBytes: 512,
                        extractedFileCount: 7,
                        feedLocator: currentCatalogImportFeedLocator,
                      ),
                );
    final run = CoachOperatorCatalogImportRun(
      importRunId: 'catalogimportrun_demo_manual_$catalogImportRunTriggerCalls',
      feedKind: 'static_catalog',
      sourceKind: 'gtfs',
      triggerKind: 'manual',
      feedLocator: selectedArtifact?.feedLocator ??
          replayedRun?.feedLocator ??
          currentCatalogImportFeedLocator,
      replayedFromImportRunId: replayedRun?.importRunId,
      replayLineageSummary: null,
      sourceArtifactId: selectedArtifact?.artifactId,
      sourceArtifact: selectedArtifact,
      status: 'succeeded',
      startedAtIso: '2026-04-15T10:09:00Z',
      finishedAtIso: '2026-04-15T10:09:20Z',
      counts: const CoachOperatorCatalogImportRunCounts(
        operators: 1,
        cities: 2,
        stopClusters: 2,
        stops: 4,
        lines: 1,
        serviceCalendars: 1,
        trips: 2,
        fareProducts: 2,
        totalRecords: 15,
        ready: true,
      ),
      errorMessage: null,
      issues: const <CoachOperatorCatalogImportRunIssue>[],
    );
    catalogImportRunEvents.insert(0, run);
    return CoachOperatorCatalogImportRunMutationResult(
      command: 'catalog_import_run_trigger',
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-ops-catalog-import-test-1',
        scope: 'coach_operator_catalog_import_run_trigger',
        requestFingerprint: 'fp_coach_catalog_import_manual_1',
        replayed: false,
        derivedKeys: const <String, String>{},
      ),
      importRun: run,
      nextAction: 'catalog_search_ready',
    );
  }

  @override
  Future<CoachOperatorPayoutImportsResponse> operatorPayoutImports({
    int limit = 8,
    String? cursor,
  }) async {
    payoutImportsCalls++;
    lastPayoutImportCursor = cursor?.trim();
    return payoutImportsSnapshot(limit: limit, cursor: cursor);
  }

  @override
  Future<CoachOperatorPayoutImportPreviewsResponse>
      operatorPayoutImportPreviews({
    int limit = 8,
    String? status,
    String? fromCreatedAtIso,
    String? toCreatedAtIso,
    String? cursor,
  }) async {
    payoutImportPreviewsCalls++;
    lastPayoutImportPreviewStatusFilter = status?.trim();
    lastPayoutImportPreviewFromCreatedAtIso = fromCreatedAtIso?.trim();
    lastPayoutImportPreviewToCreatedAtIso = toCreatedAtIso?.trim();
    lastPayoutImportPreviewCursor = cursor?.trim();
    final snapshot = payoutImportPreviewsSnapshot(
      limit: limit,
      status: status,
      fromCreatedAtIso: fromCreatedAtIso,
      toCreatedAtIso: toCreatedAtIso,
      cursor: cursor,
    );
    return CoachOperatorPayoutImportPreviewsResponse(
      generatedAtIso: snapshot.generatedAtIso,
      summary: snapshot.summary,
      previews: snapshot.previews.take(limit).toList(growable: false),
      nextCursor: snapshot.nextCursor,
    );
  }

  @override
  Future<CoachOperatorPayoutImportPreviewMutationResult>
      invalidateOperatorPayoutImportPreview({
    required String previewToken,
    String? idempotencyKey,
  }) async {
    payoutImportPreviewInvalidateCalls++;
    final index = payoutImportPreviewEvents.indexWhere(
      (entry) => entry.previewToken == previewToken,
    );
    late final CoachOperatorPayoutImportPreview preview;
    if (index >= 0) {
      final current = payoutImportPreviewEvents[index];
      preview = CoachOperatorPayoutImportPreview(
        previewToken: current.previewToken,
        accountId: current.accountId,
        importSource: current.importSource,
        reportName: current.reportName,
        reportFormat: current.reportFormat,
        operatorIds: current.operatorIds,
        reportChecksumSha256: current.reportChecksumSha256,
        requestFingerprint: current.requestFingerprint,
        previewStatus:
            current.usableNow ? 'invalidated' : current.previewStatus,
        createdAtIso: current.createdAtIso,
        expiresAtIso: current.expiresAtIso,
        usableNow: false,
        reworkOfBatchId: current.reworkOfBatchId,
        consumedAtIso: current.consumedAtIso,
        invalidatedAtIso: current.usableNow
            ? '2026-04-14T10:09:00Z'
            : current.invalidatedAtIso,
      );
      payoutImportPreviewEvents[index] = preview;
    } else {
      preview = const CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_missing',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_2026w15.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_demo_express'],
        reportChecksumSha256: 'sha256_demo_missing',
        requestFingerprint: 'fp_preview_missing_demo',
        previewStatus: 'expired',
        createdAtIso: '2026-04-14T10:08:00Z',
        expiresAtIso: '2026-04-14T10:18:00Z',
        usableNow: false,
        reworkOfBatchId: null,
        consumedAtIso: null,
        invalidatedAtIso: null,
      );
    }
    return CoachOperatorPayoutImportPreviewMutationResult(
      command: 'payout_import_preview_invalidate',
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-payout-preview-invalidate-test-1',
        scope: 'coach_operator_payout_import_preview_invalidate',
        requestFingerprint: 'fp_ops_payout_preview_invalidate_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      preview: preview,
      nextAction: preview.previewStatus == 'invalidated'
          ? 'preview_invalidated'
          : 'preview_already_expired',
    );
  }

  @override
  Future<CoachOperatorPayoutImportBatchesResponse> operatorPayoutImportBatches({
    int limit = 8,
    String? cursor,
  }) async {
    payoutImportBatchesCalls++;
    lastPayoutImportBatchCursor = cursor?.trim();
    return payoutImportBatchesSnapshot(limit: limit, cursor: cursor);
  }

  @override
  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      operatorPayoutImportPreviewSavedViews() async {
    payoutImportPreviewSavedViewsCalls++;
    return payoutImportPreviewSavedViews;
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorPayoutImportPreviewSavedViewOwners() async {
    payoutImportPreviewSavedViewOwnersCalls++;
    return _payoutImportPreviewSavedViewOwnersSnapshot();
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorPayoutImportPreviewSavedViewOperators() async {
    payoutImportPreviewSavedViewOperatorsCalls++;
    return _payoutImportPreviewSavedViewOperatorsSnapshot();
  }

  @override
  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      upsertOperatorPayoutImportPreviewSavedView(
    CoachPayoutImportPreviewHistorySavedView view, {
    String? idempotencyKey,
  }) async {
    payoutImportPreviewSavedViewUpsertCalls++;
    final normalizedName = view.name.trim().toLowerCase();
    final normalizedScope = view.visibilityScope;
    final normalizedView = CoachPayoutImportPreviewHistorySavedView(
      viewId: view.viewId,
      accountId: view.accountId,
      name: view.name,
      visibilityScope: normalizedScope,
      preferences: view.preferences,
      isDefault: normalizedScope == 'personal' && view.isDefault,
      isFavorite: view.isFavorite,
      lastUsedAtIso: view.lastUsedAtIso,
      canManage: view.canManage,
      createdAtIso: view.createdAtIso,
      updatedAtIso: view.updatedAtIso,
    );
    payoutImportPreviewSavedViews = <CoachPayoutImportPreviewHistorySavedView>[
      normalizedView,
      ...payoutImportPreviewSavedViews.where(
        (entry) =>
            entry.viewId != normalizedView.viewId &&
            !(entry.visibilityScope == normalizedScope &&
                entry.name.trim().toLowerCase() == normalizedName),
      ),
    ].map((entry) {
      if (normalizedView.isDefault &&
          entry.viewId != normalizedView.viewId &&
          entry.visibilityScope == 'personal') {
        return CoachPayoutImportPreviewHistorySavedView(
          viewId: entry.viewId,
          accountId: entry.accountId,
          name: entry.name,
          visibilityScope: entry.visibilityScope,
          preferences: entry.preferences,
          isDefault: false,
          isFavorite: entry.isFavorite,
          lastUsedAtIso: entry.lastUsedAtIso,
          canManage: entry.canManage,
          createdAtIso: entry.createdAtIso,
          updatedAtIso: entry.updatedAtIso,
        );
      }
      return entry;
    }).toList(growable: false)
      ..sort((left, right) {
        final defaultCompare =
            (right.isDefault ? 1 : 0).compareTo(left.isDefault ? 1 : 0);
        if (defaultCompare != 0) {
          return defaultCompare;
        }
        return right.updatedAtIso.compareTo(left.updatedAtIso);
      });
    return payoutImportPreviewSavedViews;
  }

  @override
  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      deleteOperatorPayoutImportPreviewSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    payoutImportPreviewSavedViewDeleteCalls++;
    payoutImportPreviewSavedViews = payoutImportPreviewSavedViews
        .where((entry) => entry.viewId != viewId)
        .toList(growable: false);
    return payoutImportPreviewSavedViews;
  }

  @override
  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      toggleOperatorPayoutImportPreviewSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    payoutImportPreviewSavedViews = payoutImportPreviewSavedViews
        .map((entry) => entry.viewId == viewId
            ? CoachPayoutImportPreviewHistorySavedView(
                viewId: entry.viewId,
                accountId: entry.accountId,
                name: entry.name,
                visibilityScope: entry.visibilityScope,
                preferences: entry.preferences,
                isDefault: entry.isDefault,
                isFavorite: favorite,
                lastUsedAtIso: entry.lastUsedAtIso,
                canManage: entry.canManage,
                createdAtIso: entry.createdAtIso,
                updatedAtIso: entry.updatedAtIso,
              )
            : entry)
        .toList(growable: false);
    return payoutImportPreviewSavedViews;
  }

  @override
  Future<String?> markOperatorPayoutImportPreviewSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    final normalizedUsedAtIso = (usedAtIso ?? '2026-04-16T10:00:00Z').trim();
    payoutImportPreviewSavedViews = payoutImportPreviewSavedViews
        .map((entry) => entry.viewId == normalizedViewId
            ? CoachPayoutImportPreviewHistorySavedView(
                viewId: entry.viewId,
                accountId: entry.accountId,
                name: entry.name,
                visibilityScope: entry.visibilityScope,
                preferences: entry.preferences,
                isDefault: entry.isDefault,
                isFavorite: entry.isFavorite,
                lastUsedAtIso: normalizedUsedAtIso,
                canManage: entry.canManage,
                createdAtIso: entry.createdAtIso,
                updatedAtIso: entry.updatedAtIso,
              )
            : entry)
        .toList(growable: false);
    return normalizedUsedAtIso;
  }

  @override
  Future<List<CoachPayoutImportBatchSavedView>>
      operatorPayoutImportBatchSavedViews() async {
    payoutImportBatchSavedViewsCalls++;
    return payoutImportBatchSavedViews;
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorPayoutImportBatchSavedViewOwners() async {
    payoutImportBatchSavedViewOwnersCalls++;
    return _payoutImportBatchSavedViewOwnersSnapshot();
  }

  @override
  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorPayoutImportBatchSavedViewOperators() async {
    payoutImportBatchSavedViewOperatorsCalls++;
    return _payoutImportBatchSavedViewOperatorsSnapshot();
  }

  @override
  Future<List<CoachPayoutImportBatchSavedView>>
      upsertOperatorPayoutImportBatchSavedView(
    CoachPayoutImportBatchSavedView view, {
    String? idempotencyKey,
  }) async {
    payoutImportBatchSavedViewUpsertCalls++;
    final normalizedName = view.name.trim().toLowerCase();
    final normalizedScope = view.visibilityScope;
    final normalizedView = CoachPayoutImportBatchSavedView(
      viewId: view.viewId,
      accountId: view.accountId,
      name: view.name,
      visibilityScope: normalizedScope,
      preferences: view.preferences,
      isDefault: normalizedScope == 'personal' && view.isDefault,
      isFavorite: view.isFavorite,
      lastUsedAtIso: view.lastUsedAtIso,
      canManage: view.canManage,
      createdAtIso: view.createdAtIso,
      updatedAtIso: view.updatedAtIso,
    );
    payoutImportBatchSavedViews = <CoachPayoutImportBatchSavedView>[
      normalizedView,
      ...payoutImportBatchSavedViews.where(
        (entry) =>
            entry.viewId != normalizedView.viewId &&
            !(entry.visibilityScope == normalizedScope &&
                entry.name.trim().toLowerCase() == normalizedName),
      ),
    ].map((entry) {
      if (normalizedView.isDefault &&
          entry.viewId != normalizedView.viewId &&
          entry.visibilityScope == 'personal') {
        return CoachPayoutImportBatchSavedView(
          viewId: entry.viewId,
          accountId: entry.accountId,
          name: entry.name,
          visibilityScope: entry.visibilityScope,
          preferences: entry.preferences,
          isDefault: false,
          isFavorite: entry.isFavorite,
          lastUsedAtIso: entry.lastUsedAtIso,
          canManage: entry.canManage,
          createdAtIso: entry.createdAtIso,
          updatedAtIso: entry.updatedAtIso,
        );
      }
      return entry;
    }).toList(growable: false)
      ..sort((left, right) {
        final defaultCompare =
            (right.isDefault ? 1 : 0).compareTo(left.isDefault ? 1 : 0);
        if (defaultCompare != 0) {
          return defaultCompare;
        }
        return right.updatedAtIso.compareTo(left.updatedAtIso);
      });
    return payoutImportBatchSavedViews;
  }

  @override
  Future<List<CoachPayoutImportBatchSavedView>>
      deleteOperatorPayoutImportBatchSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    payoutImportBatchSavedViewDeleteCalls++;
    payoutImportBatchSavedViews = payoutImportBatchSavedViews
        .where((entry) => entry.viewId != viewId.trim())
        .toList(growable: false);
    return payoutImportBatchSavedViews;
  }

  @override
  Future<List<CoachPayoutImportBatchSavedView>>
      toggleOperatorPayoutImportBatchSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    payoutImportBatchSavedViews = payoutImportBatchSavedViews
        .map((entry) => entry.viewId == viewId
            ? CoachPayoutImportBatchSavedView(
                viewId: entry.viewId,
                accountId: entry.accountId,
                name: entry.name,
                visibilityScope: entry.visibilityScope,
                preferences: entry.preferences,
                isDefault: entry.isDefault,
                isFavorite: favorite,
                lastUsedAtIso: entry.lastUsedAtIso,
                canManage: entry.canManage,
                createdAtIso: entry.createdAtIso,
                updatedAtIso: entry.updatedAtIso,
              )
            : entry)
        .toList(growable: false);
    return payoutImportBatchSavedViews;
  }

  @override
  Future<String?> markOperatorPayoutImportBatchSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    final normalizedUsedAtIso = (usedAtIso ?? '2026-04-16T10:00:00Z').trim();
    payoutImportBatchSavedViews = payoutImportBatchSavedViews
        .map((entry) => entry.viewId == normalizedViewId
            ? CoachPayoutImportBatchSavedView(
                viewId: entry.viewId,
                accountId: entry.accountId,
                name: entry.name,
                visibilityScope: entry.visibilityScope,
                preferences: entry.preferences,
                isDefault: entry.isDefault,
                isFavorite: entry.isFavorite,
                lastUsedAtIso: normalizedUsedAtIso,
                canManage: entry.canManage,
                createdAtIso: entry.createdAtIso,
                updatedAtIso: entry.updatedAtIso,
              )
            : entry)
        .toList(growable: false);
    return normalizedUsedAtIso;
  }

  @override
  Future<CoachOperatorPayoutImportProfilesResponse>
      operatorPayoutImportProfiles() async {
    payoutImportProfilesCalls++;
    return payoutImportProfilesSnapshot();
  }

  @override
  Future<CoachOperatorRefundReviewResult> reviewRefundRequest({
    required String refundRequestId,
    required bool approve,
    String? note,
    String? idempotencyKey,
  }) async {
    refundReviewCalls++;
    refundApproved = approve;
    return CoachOperatorRefundReviewResult(
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-refund-review-test-1',
        scope: 'coach_operator_refund_review',
        requestFingerprint: 'fp_ops_refund_review_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      request: (await operatorRefundQueue()).requests.single,
      settlementEffect: const CoachOperatorSettlementEffect(
        kind: 'travel_credit_liability',
        currency: 'SYP',
        amountMinorUnits: 9180,
      ),
      nextAction: 'customer_notification_queued',
    );
  }

  @override
  Future<CoachOperatorChangeReviewResult> reviewChangeRequest({
    required String changeRequestId,
    required bool approve,
    String? note,
    String? idempotencyKey,
  }) async {
    changeReviewCalls++;
    changeRejected = !approve;
    return CoachOperatorChangeReviewResult(
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-change-review-test-1',
        scope: 'coach_operator_change_review',
        requestFingerprint: 'fp_ops_change_review_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      request: (await operatorChangeQueue()).requests.single,
      settlementEffect: null,
      nextAction: 'keep_original_booking',
    );
  }

  @override
  Future<CoachOperatorPayoutRunMutationResult> createOperatorPayoutRun({
    required List<String> statementIds,
    String? note,
    String? idempotencyKey,
  }) async {
    payoutCreateCalls++;
    payoutQueued = true;
    return CoachOperatorPayoutRunMutationResult(
      command: 'payout_run_create',
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-payout-run-test-1',
        scope: 'coach_operator_payout_run_create',
        requestFingerprint: 'fp_ops_payout_run_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      payoutRun: payoutRunsSnapshot().runs.single,
      nextAction: 'await_external_payout_execution',
    );
  }

  @override
  Future<CoachOperatorPayoutRunMutationResult> markOperatorPayoutRunPaid({
    required String payoutRunId,
    String? paymentReference,
    String? note,
    String? idempotencyKey,
  }) async {
    payoutMarkPaidCalls++;
    payoutQueued = true;
    payoutMarkedPaid = true;
    payoutFailed = false;
    payoutImportedPaymentReference = paymentReference;
    return CoachOperatorPayoutRunMutationResult(
      command: 'payout_run_mark_paid',
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-payout-run-paid-test-1',
        scope: 'coach_operator_payout_run_mark_paid',
        requestFingerprint: 'fp_ops_payout_run_paid_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      payoutRun: payoutRunsSnapshot().runs.single,
      nextAction: 'statement_exports_ready',
    );
  }

  @override
  Future<CoachOperatorPayoutImportMutationResult> createOperatorPayoutImport({
    required String payoutRunId,
    required String importSource,
    required String externalStatus,
    String? paymentReference,
    String? externalReference,
    String? importedAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    payoutImportCreateCalls++;
    payoutQueued = true;
    payoutMarkedPaid = externalStatus == 'executed';
    payoutFailed = externalStatus == 'failed';
    payoutImportedPaymentReference = paymentReference;
    final importedAt = importedAtIso ?? '2026-04-14T10:06:00Z';
    final entry = CoachOperatorPayoutImport(
      importId: 'payoutimport_demo_${payoutImportCreateCalls}',
      importBatchId: null,
      payoutRunId: payoutRunId,
      importSource: importSource,
      externalStatus: externalStatus,
      paymentReference: paymentReference,
      externalReference: externalReference,
      importedAtIso: importedAt,
      importedByAccountId: 'acct_finance_demo',
      previousRunStatus: 'queued',
      appliedRunStatus: externalStatus == 'executed' ? 'paid' : 'failed',
      note: note,
    );
    payoutImportEvents.insert(0, entry);
    return CoachOperatorPayoutImportMutationResult(
      command: 'payout_import_create',
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-payout-import-test-1',
        scope: 'coach_operator_payout_import_create',
        requestFingerprint: 'fp_ops_payout_import_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      payoutImport: entry,
      payoutRun: payoutRunsSnapshot().runs.single,
      nextAction: externalStatus == 'executed'
          ? 'reconciliation_updated'
          : 'retry_or_requeue_payout',
    );
  }

  @override
  Future<CoachOperatorPayoutImportBatchMutationResult>
      createOperatorPayoutImportBatch({
    required String importSource,
    required String reportName,
    String reportFormat = 'csv',
    required String reportBody,
    String? reworkOfBatchId,
    String? expectedPreviewToken,
    bool dryRun = false,
    String? note,
    String? idempotencyKey,
  }) async {
    payoutImportBatchCreateCalls++;
    if (dryRun) {
      payoutImportBatchPreviewCalls++;
    }
    if (!dryRun && expectedPreviewToken != null) {
      final index = payoutImportPreviewEvents.indexWhere(
        (entry) => entry.previewToken == expectedPreviewToken,
      );
      if (index >= 0) {
        final preview = payoutImportPreviewEvents[index];
        payoutImportPreviewEvents[index] = CoachOperatorPayoutImportPreview(
          previewToken: preview.previewToken,
          accountId: preview.accountId,
          importSource: preview.importSource,
          reportName: preview.reportName,
          reportFormat: preview.reportFormat,
          operatorIds: preview.operatorIds,
          reportChecksumSha256: preview.reportChecksumSha256,
          requestFingerprint: preview.requestFingerprint,
          previewStatus: 'consumed',
          createdAtIso: preview.createdAtIso,
          expiresAtIso: preview.expiresAtIso,
          usableNow: false,
          reworkOfBatchId: preview.reworkOfBatchId,
          consumedAtIso: '2026-04-14T10:09:00Z',
          invalidatedAtIso: null,
        );
      }
    }
    lastPayoutImportBatchReworkOfBatchId = reworkOfBatchId;
    lastExpectedPreviewToken = expectedPreviewToken;
    return _buildPayoutImportBatchResult(
      sequence: payoutImportBatchCreateCalls,
      importSource: importSource,
      reportName: reportName,
      reportFormat: reportFormat,
      reportBody: reportBody,
      dryRun: dryRun,
      reworkOfBatchId: reworkOfBatchId,
      note: note,
    );
  }

  @override
  Future<CoachOperatorPayoutImportBatchMutationResult>
      uploadOperatorPayoutImportBatchFile({
    required String importSource,
    String? reportName,
    String reportFormat = 'csv',
    required Uint8List fileBytes,
    required String fileName,
    String? reworkOfBatchId,
    String? expectedPreviewToken,
    bool dryRun = false,
    String? note,
    String? idempotencyKey,
  }) async {
    payoutImportBatchUploadCalls++;
    if (dryRun) {
      payoutImportBatchUploadPreviewCalls++;
    }
    if (!dryRun && expectedPreviewToken != null) {
      final index = payoutImportPreviewEvents.indexWhere(
        (entry) => entry.previewToken == expectedPreviewToken,
      );
      if (index >= 0) {
        final preview = payoutImportPreviewEvents[index];
        payoutImportPreviewEvents[index] = CoachOperatorPayoutImportPreview(
          previewToken: preview.previewToken,
          accountId: preview.accountId,
          importSource: preview.importSource,
          reportName: preview.reportName,
          reportFormat: preview.reportFormat,
          operatorIds: preview.operatorIds,
          reportChecksumSha256: preview.reportChecksumSha256,
          requestFingerprint: preview.requestFingerprint,
          previewStatus: 'consumed',
          createdAtIso: preview.createdAtIso,
          expiresAtIso: preview.expiresAtIso,
          usableNow: false,
          reworkOfBatchId: preview.reworkOfBatchId,
          consumedAtIso: '2026-04-14T10:09:00Z',
          invalidatedAtIso: null,
        );
      }
    }
    lastUploadedPayoutImportFileName = fileName;
    lastUploadedPayoutImportBody = utf8.decode(fileBytes);
    lastPayoutImportBatchReworkOfBatchId = reworkOfBatchId;
    lastExpectedPreviewToken = expectedPreviewToken;
    return _buildPayoutImportBatchResult(
      sequence: payoutImportBatchUploadCalls,
      importSource: importSource,
      reportName: (reportName ?? '').trim().isEmpty ? fileName : reportName!,
      reportFormat: reportFormat,
      reportBody: utf8.decode(fileBytes),
      dryRun: dryRun,
      reworkOfBatchId: reworkOfBatchId,
      note: note,
    );
  }

  @override
  Future<CoachOperatorPayoutExportMutationResult>
      createOperatorPayoutRunExport({
    required String payoutRunId,
    required String exportFormat,
    String? note,
    String? idempotencyKey,
  }) async {
    payoutExportCreateCalls++;
    payoutQueued = true;
    preparedExportFormats.add(exportFormat);
    final export = payoutRunsSnapshot().runs.single.exports.firstWhere(
          (value) => value.exportFormat == exportFormat,
        );
    return CoachOperatorPayoutExportMutationResult(
      command: 'payout_run_export_create',
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-ops-payout-run-export-test-1',
        scope: 'coach_operator_payout_run_export_create',
        requestFingerprint: 'fp_ops_payout_run_export_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      export: export,
      nextAction: 'download_ready',
    );
  }

  @override
  Future<String> fetchPayoutImportReportBody(String downloadPath) async {
    payoutImportReportFetchCalls++;
    lastFetchedPayoutImportReportPath = downloadPath;
    return payoutImportReportBodies[downloadPath] ??
        'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
            'payoutrun_demo_failed,executed,bank_import_payoutrun_demo_failed,bank_file_2026w15,2026-04-14T11:06:00Z,rework import prepared from coach ops console';
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('coach operator console consumes inherited dashboard policy',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellDashboardPolicyScope(
          policy: const ShamellDashboardPolicy(
            baseUrl: 'https://api.shamell.online',
            privilegeSnapshot: AccountPrivilegeSnapshot(
              permissions: <String>['coach.operator.read'],
              products: <String>['coach'],
            ),
            capabilities: ShamellCapabilities.conservativeDefaults,
          ),
          child: CoachOperatorConsolePage(
            baseUrl: 'https://api.shamell.online',
            api: api,
            initialRefundQueue: api.refundQueueSnapshot(),
            initialChangeQueue: api.changeQueueSnapshot(),
            initialReconciliation: api.reconciliationSnapshot(),
            initialSettlementStatements: api.settlementStatementsSnapshot(),
            initialPayoutRuns: api.payoutRunsSnapshot(),
            initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
            initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
            initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
            initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
            initialPayoutImports: api.payoutImportsSnapshot(),
            initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
            initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
            initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
            saveCatalogImportRunFilterPreferencesOverride: (_) async {},
            clearCatalogImportRunFilterPreferencesOverride: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Partner operations desk'), findsOneWidget);
    expect(
      find.text('This account is not allowed to manage coach requests.'),
      findsNothing,
    );
  });

  testWidgets('coach operator console renders queue sections for ops users',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Partner operations desk'), findsOneWidget);
    expect(find.text('Jump to'), findsOneWidget);
    expect(find.text('Support queue'), findsOneWidget);
    expect(find.text('Sales & imports'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Today');
    expect(find.text('Today'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Payout reconciliation');
    expect(find.text('Payout reconciliation'), findsWidgets);
    await _dragUntilTextVisible(tester, 'Catalog import runs');
    expect(find.text('Catalog import runs'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Payout import batches');
    expect(find.text('Payout import batches'), findsOneWidget);
    expect(find.text('This account is not allowed to manage coach requests.'),
        findsNothing);
    expect(api.reconciliationCalls, 0);
    expect(api.settlementStatementsCalls, 0);
    expect(api.payoutRunsCalls, 0);
    expect(api.payoutReconciliationCalls, 0);
    expect(api.operatorFeedHealthCalls, 0);
    expect(api.operatorCatalogImportConfigCalls, 0);
    expect(api.catalogImportRunsCalls, 0);
    expect(api.payoutImportsCalls, 0);
    expect(api.payoutImportBatchesCalls, 0);
    expect(api.payoutImportProfilesCalls, 0);
    expect(api.refundReviewCalls, 0);
    expect(api.changeReviewCalls, 0);
    expect(api.payoutCreateCalls, 0);
    expect(api.payoutMarkPaidCalls, 0);
    expect(api.payoutImportCreateCalls, 0);
    expect(api.payoutImportBatchCreateCalls, 0);
    expect(api.payoutImportBatchPreviewCalls, 0);
    expect(api.payoutImportBatchUploadCalls, 0);
    expect(api.payoutImportBatchUploadPreviewCalls, 0);
    expect(api.payoutExportCreateCalls, 0);
  });

  testWidgets('coach operator console filters desk sections locally',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    Widget buildConsole([Key? pageKey]) {
      return MaterialApp(
        home: CoachOperatorConsolePage(
          key: pageKey,
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pumpAndSettle();

    expect(find.text('Showing 4 of 4 desks'), findsOneWidget);
    expect(find.text('Collapsed 0 of 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_settlements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_payout_ops')),
      findsOneWidget,
    );
    await _dragUntilFinderVisible(
      tester,
      find.byKey(const ValueKey('coachOpsWorkspace_sales_feeds')),
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_sales_feeds')),
      findsOneWidget,
    );
    await _dragUntilFinderVisible(
      tester,
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      buildConsole(const ValueKey('coachOpsConsoleFilterReset')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('coachOpsWorkspaceFocus_support')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 4 desks'), findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_settlements')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_payout_ops')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_sales_feeds')),
      findsNothing,
    );

    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('coachOpsWorkspaceFocus_all')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 4 of 4 desks'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_settlements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_payout_ops')),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console filters portal shortcuts and today cards',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coachOpsJump_support_queue')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsJump_reconciliation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_payout_imports')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_settlements')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_payouts')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_import_batches')),
      findsNothing,
    );
    expect(
        find.byKey(const ValueKey('coachOpsJump_feed_health')), findsOneWidget);
    expect(find.byKey(const ValueKey('coachOpsTodayCard_support_refunds')),
        findsOneWidget);
    expect(
      find.byKey(
          const ValueKey('coachOpsTodayCard_settlements_reconciliation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_imports')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_previews')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_net')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_payout_runs')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_batches')),
      findsNothing,
    );
    expect(
      find.byKey(
          const ValueKey('coachOpsTodayCard_sales_feeds_catalog_imports')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
      find.byType(Scrollable).first,
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsPortalSectionFocus_today'),
            ),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsSettlementsTrackFocus_execution'),
            ),
          )
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('coachOpsJump_support_queue')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsJump_settlements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_payouts')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_import_batches')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_reconciliation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_payout_imports')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_net')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_payout_runs')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_batches')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const ValueKey('coachOpsTodayCard_settlements_reconciliation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_imports')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_previews')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsWorkspaceFocus_support')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coachOpsJump_support_queue')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachOpsJump_support_changes')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('coachOpsJump_settlements')), findsNothing);
    expect(
      find.byKey(const ValueKey('coachOpsJump_feed_health')),
      findsNothing,
    );
    expect(find.textContaining('Showing live signals for Support desk.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachOpsTodayCard_support_refunds')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachOpsTodayCard_support_changes')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_net')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_imports')),
      findsNothing,
    );
    expect(
      find.byKey(
          const ValueKey('coachOpsTodayCard_sales_feeds_catalog_imports')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsWorkspaceFocus_sales_feeds')),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('coachOpsJump_support_queue')), findsNothing);
    expect(
        find.byKey(const ValueKey('coachOpsJump_feed_health')), findsOneWidget);
    expect(find.textContaining('Showing live signals for Sales & feeds.'),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_support_refunds')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_sales_feeds_feed_health')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const ValueKey('coachOpsTodayCard_sales_feeds_catalog_imports')),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console portal lanes sync header shortcuts and desk focus',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsPortalSectionFocus_today'),
            ),
          )
          .selected,
      isTrue,
    );
    expect(find.text('Today'), findsWidgets);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_all')),
          )
          .selected,
      isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_support')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsPortalSectionFocus_support')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_support')),
          )
          .selected,
      isTrue,
    );
    expect(find.textContaining('Desk focus is Support desk.'), findsOneWidget);
    expect(find.text('Support'), findsWidgets);
    expect(find.byKey(const ValueKey('coachOpsJump_support_queue')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachOpsJump_support_changes')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsJump_reconciliation')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('coachOpsTodayCard_support_refunds')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('coachOpsTodayCard_support_changes')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_net')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_settlements')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsPortalSectionFocus_settlements'),
            ),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_settlements')),
          )
          .selected,
      isTrue,
    );
    expect(find.textContaining('Desk focus is Settlements.'), findsOneWidget);
    expect(find.text('Settlements'), findsWidgets);
    expect(
      find.byKey(const ValueKey('coachOpsJump_reconciliation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_payouts')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_support_queue')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsTodayCard_settlements_reconciliation'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_net')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsWorkspaceFocus_payout_ops')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_payout_ops')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_settlements_net')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_imports')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_batches')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_payout_imports')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_import_batches')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
      find.byType(Scrollable).first,
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsSettlementsTrackFocus_execution'),
            ),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_payout_imports')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_import_batches')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_imports')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_payout_ops_batches')),
      findsOneWidget,
    );

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_today')),
      find.byType(Scrollable).first,
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_today')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsPortalSectionFocus_today')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_all')),
          )
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('coachOpsJump_support_queue')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsJump_feed_health')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('coachOpsTodayCard_support_refunds')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsTodayCard_sales_feeds_feed_health')),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console portal lanes shape detail sections',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final scrollable = find.byType(Scrollable).first;
    final settlementsAuditBody = find.byKey(
      const ValueKey('coachOpsPortalSectionBody_settlements_audit'),
    );
    final settlementsExecutionBody = find.byKey(
      const ValueKey('coachOpsPortalSectionBody_settlements_execution'),
    );

    Future<void> scrollToKey(String key) async {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        600,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
    }

    Future<void> revealKeyAbove(String key) async {
      await tester.dragUntilVisible(
        find.byKey(ValueKey(key)),
        scrollable,
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_audit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_audit')),
          )
          .selected,
      isTrue,
    );

    await scrollToKey('coachOpsPortalSection_settlements_audit');
    expect(
      find.descendant(
        of: settlementsAuditBody,
        matching: find.text('Reconciliation snapshot'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: settlementsAuditBody,
        matching: find.text('Review history'),
      ),
      findsOneWidget,
    );
    await scrollToKey('coachOpsPortalSection_trips_feed_health');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_trips_feed_health')),
      findsOneWidget,
    );
    await scrollToKey('coachOpsPortalSection_sales_market');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_sales_market')),
      findsOneWidget,
    );
    await scrollToKey('coachOpsPortalSection_settlements_execution');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_execution')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: settlementsExecutionBody,
        matching: find.text('Settlement statements'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: settlementsExecutionBody,
        matching: find.text('Reconciliation snapshot'),
      ),
      findsNothing,
    );
    await scrollToKey('coachOpsPortalSection_support');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_support')),
      findsOneWidget,
    );

    await revealKeyAbove('coachOpsSettlementsTrackFocus_execution');
    await tester.tap(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsPortalSectionFocus_today'),
            ),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsSettlementsTrackFocus_execution'),
            ),
          )
          .selected,
      isTrue,
    );

    await revealKeyAbove('coachOpsPortalSectionFocus_trips');
    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_trips')),
    );
    await tester.pumpAndSettle();

    await scrollToKey('coachOpsPortalSection_trips_feed_health');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_trips_feed_health')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_audit')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_support')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_sales_market')),
      findsNothing,
    );

    await revealKeyAbove('coachOpsPortalSectionFocus_sales');
    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_sales')),
    );
    await tester.pumpAndSettle();

    await scrollToKey('coachOpsPortalSection_sales_market');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_sales_market')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_trips_feed_health')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_audit')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_support')),
      findsNothing,
    );

    await revealKeyAbove('coachOpsPortalSectionFocus_settlements');
    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_settlements')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_audit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsSettlementsTrackFocus_execution'),
            ),
          )
          .selected,
      isTrue,
    );
    await scrollToKey('coachOpsPortalSection_settlements_execution');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_execution')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_audit')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_audit')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsSettlementsTrackFocus_audit'),
            ),
          )
          .selected,
      isTrue,
    );
    await scrollToKey('coachOpsPortalSection_settlements_audit');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_audit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_execution')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: settlementsAuditBody,
        matching: find.text('Reconciliation snapshot'),
      ),
      findsOneWidget,
    );

    await revealKeyAbove('coachOpsSettlementsTrackFocus_audit');
    await tester.tap(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('coachOpsSettlementsTrackFocus_execution'),
            ),
          )
          .selected,
      isTrue,
    );
    await scrollToKey('coachOpsPortalSection_settlements_execution');
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_execution')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_audit')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_sales_market')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_trips_feed_health')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_support')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: settlementsExecutionBody,
        matching: find.text('Reconciliation snapshot'),
      ),
      findsNothing,
    );

    await revealKeyAbove('coachOpsPortalSectionFocus_support');
    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_support')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_sales_market')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_trips_feed_health')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_audit')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsPortalSection_settlements_execution')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_audit')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsSettlementsTrackFocus_execution')),
      findsNothing,
    );
  });

  testWidgets('coach operator console remembers portal lane', (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: CoachOperatorConsolePage(
            key: const PageStorageKey<String>('coachOperatorConsolePortalPage'),
            baseUrl: 'https://api.shamell.online',
            api: api,
            privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
              roles: <String>['admin'],
              isSuperadmin: false,
            ),
            initialRefundQueue: api.refundQueueSnapshot(),
            initialChangeQueue: api.changeQueueSnapshot(),
            initialReconciliation: api.reconciliationSnapshot(),
            initialSettlementStatements: api.settlementStatementsSnapshot(),
            initialPayoutRuns: api.payoutRunsSnapshot(),
            initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
            initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
            initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
            initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
            initialPayoutImports: api.payoutImportsSnapshot(),
            initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
            initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
            initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
            saveCatalogImportRunFilterPreferencesOverride: (_) async {},
            clearCatalogImportRunFilterPreferencesOverride: () async {},
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('coachOpsPortalSectionFocus_sales')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsPortalSectionFocus_sales')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_sales_feeds')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsTodayCard_sales_feeds_catalog_imports'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_sales_imports')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_support_queue')),
      findsNothing,
    );

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsPortalSectionFocus_sales')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_sales_feeds')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsTodayCard_sales_feeds_catalog_imports'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_sales_imports')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsJump_support_queue')),
      findsNothing,
    );
  });

  testWidgets('coach operator console collapses and expands visible desks',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_settlements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_payout_ops')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_payout_ops')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('coachOpsWorkspaceToggle_payout_ops')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 1 of 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_payout_ops')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceCollapsed_payout_ops')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('coachOpsCollapseVisible')));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 4 of 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_settlements')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceCollapsed_settlements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceCollapsed_payout_ops')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('coachOpsExpandVisible')));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_settlements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_payout_ops')),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console remembers collapsed desks',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: CoachOperatorConsolePage(
            key: const PageStorageKey<String>(
              'coachOperatorConsoleCollapsedDesksPage',
            ),
            baseUrl: 'https://api.shamell.online',
            api: api,
            privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
              roles: <String>['admin'],
              isSuperadmin: false,
            ),
            initialRefundQueue: api.refundQueueSnapshot(),
            initialChangeQueue: api.changeQueueSnapshot(),
            initialReconciliation: api.reconciliationSnapshot(),
            initialSettlementStatements: api.settlementStatementsSnapshot(),
            initialPayoutRuns: api.payoutRunsSnapshot(),
            initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
            initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
            initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
            initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
            initialPayoutImports: api.payoutImportsSnapshot(),
            initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
            initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
            initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
            saveCatalogImportRunFilterPreferencesOverride: (_) async {},
            clearCatalogImportRunFilterPreferencesOverride: () async {},
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('coachOpsWorkspaceToggle_payout_ops')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 1 of 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_payout_ops')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceCollapsed_payout_ops')),
      findsOneWidget,
    );

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 1 of 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_settlements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceBody_payout_ops')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspaceCollapsed_payout_ops')),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console remembers desk focus', (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final bucket = PageStorageBucket();

    Widget buildConsole() {
      return MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: CoachOperatorConsolePage(
            key: const PageStorageKey<String>('coachOperatorConsolePage'),
            baseUrl: 'https://api.shamell.online',
            api: api,
            privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
              roles: <String>['admin'],
              isSuperadmin: false,
            ),
            initialRefundQueue: api.refundQueueSnapshot(),
            initialChangeQueue: api.changeQueueSnapshot(),
            initialReconciliation: api.reconciliationSnapshot(),
            initialSettlementStatements: api.settlementStatementsSnapshot(),
            initialPayoutRuns: api.payoutRunsSnapshot(),
            initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
            initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
            initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
            initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
            initialPayoutImports: api.payoutImportsSnapshot(),
            initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
            initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
            initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
            saveCatalogImportRunFilterPreferencesOverride: (_) async {},
            clearCatalogImportRunFilterPreferencesOverride: () async {},
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await tester.pumpAndSettle();

    expect(find.text('Desk focus'), findsOneWidget);
    expect(find.text('Showing 4 of 4 desks'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('coachOpsWorkspaceFocus_support')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 4 desks'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_support')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_all')),
          )
          .selected,
      isFalse,
    );
    await _dragUntilFinderVisible(
      tester,
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_payout_ops')),
      findsNothing,
    );

    await tester.pumpWidget(buildConsole());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 4 desks'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_support')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('coachOpsWorkspaceFocus_all')),
          )
          .selected,
      isFalse,
    );
    await _dragUntilFinderVisible(
      tester,
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_support')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsWorkspace_sales_feeds')),
      findsNothing,
    );
  });

  testWidgets('coach operator console shows partner scope and read-only mode',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            permissions: <String>['coach.operator.read'],
            products: <String>['coach'],
            operatorIds: <String>['op_demo_express'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Partner operations desk'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Scope: op_demo_express');
    expect(find.textContaining('Scope: op_demo_express'), findsOneWidget);
    expect(find.text('Read-only finance and payouts'), findsOneWidget);
    expect(
      find.text('Catalog configuration is visible in read-only mode'),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console renders catalog import run history',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    expect(find.text('Catalog import runs'), findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
        ),
      ),
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    await _dragUntilFinderVisible(
      tester,
      find.text('required GTFS file missing: stops.txt'),
    );
    expect(find.text('Replay runs: 3'), findsOneWidget);
    expect(
      find.text('Latest replay: catalogimportrun_demo_failed_replay_2'),
      findsOneWidget,
    );
    expect(find.textContaining('Issues: 1'), findsOneWidget);
    expect(
      find.text('required GTFS file missing: stops.txt'),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console filters catalog import runs by replay attention',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final replayScopeDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsReplayScopeFilterField'),
    );
    expect(replayScopeDropdown, findsOneWidget);

    tester
        .widget<DropdownButtonFormField<String>>(replayScopeDropdown)
        .onChanged!
        .call('attention');
    await tester.pumpAndSettle();

    expect(api.catalogImportRunsCalls, 1);
    expect(api.lastCatalogImportRunReplayScopeFilter, 'attention');
    expect(api.lastCatalogImportRunStatusFilter, isNull);
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
        ),
      ),
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed_old_2',
        ),
      ),
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed_old_2',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_ok',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console shows read-only catalog import run guidance for support users',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['support_l1'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final readOnlyHint = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunReadOnlyHint_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, readOnlyHint);
    expect(readOnlyHint, findsOneWidget);
    expect(
      find.text(
        'This account is read-only for catalog imports. Open details to review issues, then ask a catalog operator to replay this run or rerun it from the linked source.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console shows read-only catalog import run detail guidance for support users',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['support_l1'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final readOnlyHint = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunDetailReadOnlyHint_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, readOnlyHint);
    expect(readOnlyHint, findsOneWidget);
    expect(
      find.text(
        'This account is read-only for catalog imports. Review issues, replay lineage, and linked source details here, then ask a catalog operator to replay this run or rerun it from the source.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewReplaySource_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewReplaySourceReadOnlyHint_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'You can open the replay source for review. If this run needs another replay, ask a catalog operator to execute it.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewSourceArtifact_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewSourceArtifactReadOnlyHint_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'You can open the linked source artifact for review. If this run needs a rerun from this source, ask a catalog operator to execute it.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewReplayRunReadOnlyHint_catalogimportrun_demo_failed_catalogimportrun_demo_failed_replay_2',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunReplay_catalogimportrun_demo_failed',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console shows active import run filter chips and clears them individually',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final statusDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsStatusFilterField'),
    );
    final replayScopeDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsReplayScopeFilterField'),
    );
    expect(statusDropdown, findsOneWidget);
    expect(replayScopeDropdown, findsOneWidget);

    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!
        .call('failed');
    await tester.pumpAndSettle();

    tester
        .widget<DropdownButtonFormField<String>>(replayScopeDropdown)
        .onChanged!
        .call('attention');
    await tester.pumpAndSettle();

    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsFilteredCountChip'),
      ),
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsFilteredCountChip'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsStatusFilterChip'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsReplayScopeFilterChip'),
      ),
      findsOneWidget,
    );
    expect(api.catalogImportRunsCalls, 2);
    expect(api.lastCatalogImportRunStatusFilter, 'failed');
    expect(api.lastCatalogImportRunReplayScopeFilter, 'attention');

    tester
        .widget<InputChip>(
          find.byKey(
            const ValueKey('coachOpsCatalogImportRunsStatusFilterChip'),
          ),
        )
        .onDeleted!
        .call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunsCalls, 3);
    expect(api.lastCatalogImportRunStatusFilter, isNull);
    expect(api.lastCatalogImportRunReplayScopeFilter, 'attention');
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsStatusFilterChip'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsReplayScopeFilterChip'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsFilteredCountChip'),
      ),
      findsOneWidget,
    );
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed_old_2',
        ),
      ),
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed_old_2',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console filters catalog import runs by issue severity and clears the severity chip',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final issueSeverityDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterField'),
    );
    expect(issueSeverityDropdown, findsOneWidget);

    tester
        .widget<DropdownButtonFormField<String>>(issueSeverityDropdown)
        .onChanged!
        .call('error');
    await tester.pumpAndSettle();

    expect(api.catalogImportRunsCalls, 1);
    expect(api.lastCatalogImportRunIssueSeverityFilter, 'error');
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterChip'),
      ),
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterChip'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsFilteredCountChip'),
      ),
      findsOneWidget,
    );

    tester
        .widget<InputChip>(
          find.byKey(
            const ValueKey(
              'coachOpsCatalogImportRunsIssueSeverityFilterChip',
            ),
          ),
        )
        .onDeleted!
        .call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunsCalls, 2);
    expect(api.lastCatalogImportRunIssueSeverityFilter, isNull);
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterChip'),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console applies catalog import run issue preset buttons',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final errorsOnlyButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsIssuePresetErrorsButton'),
      skipOffstage: false,
    );
    final loadFeedOnlyButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsIssuePresetLoadFeedButton'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, errorsOnlyButton, dragDy: 260);
    expect(errorsOnlyButton, findsOneWidget);
    expect(loadFeedOnlyButton, findsOneWidget);

    tester.widget<OutlinedButton>(errorsOnlyButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunsCalls, 1);
    expect(api.lastCatalogImportRunIssueSeverityFilter, 'error');
    expect(api.lastCatalogImportRunIssueStageFilter, isNull);
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterChip'),
      ),
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterChip'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsFilteredCountChip'),
      ),
      findsOneWidget,
    );

    await _dragUntilFinderVisible(tester, loadFeedOnlyButton, dragDy: 260);
    tester.widget<OutlinedButton>(loadFeedOnlyButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunsCalls, 2);
    expect(api.lastCatalogImportRunIssueSeverityFilter, isNull);
    expect(api.lastCatalogImportRunIssueStageFilter, 'load_feed');
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterChip'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueStageFilterChip'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console clears only issue filters from issue preset button',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          clearCatalogImportRunFilterPreferencesOverride: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final statusDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsStatusFilterField'),
    );
    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!
        .call('failed');
    await tester.pumpAndSettle();

    final errorsOnlyButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsIssuePresetErrorsButton'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, errorsOnlyButton, dragDy: 260);
    tester.widget<OutlinedButton>(errorsOnlyButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunStatusFilter, 'failed');
    expect(api.lastCatalogImportRunIssueSeverityFilter, 'error');

    final clearIssueFiltersButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsClearIssueFiltersButton'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      clearIssueFiltersButton,
      dragDy: 260,
    );
    tester.widget<OutlinedButton>(clearIssueFiltersButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunStatusFilter, 'failed');
    expect(api.lastCatalogImportRunIssueSeverityFilter, isNull);
    expect(api.lastCatalogImportRunIssueStageFilter, isNull);
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsStatusFilterChip'),
      ),
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsStatusFilterChip'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterChip'),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console restores persisted catalog import run filters on load',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    var loadCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          loadCatalogImportRunFilterPreferencesOverride: () async {
            loadCalls += 1;
            return const CoachCatalogImportRunFilterPreferences(
              status: 'failed',
              replayScope: 'attention',
              issueSeverity: 'error',
              issueStage: 'load_feed',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCalls, 1);
    expect(api.lastCatalogImportRunStatusFilter, 'failed');
    expect(api.lastCatalogImportRunReplayScopeFilter, 'attention');
    expect(api.lastCatalogImportRunIssueSeverityFilter, 'error');
    expect(api.lastCatalogImportRunIssueStageFilter, 'load_feed');
    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final statusDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsStatusFilterField'),
      ),
    );
    final replayScopeDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsReplayScopeFilterField'),
      ),
    );
    final issueSeverityDropdown =
        tester.widget<DropdownButtonFormField<String>>(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterField'),
      ),
    );
    final issueStageDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsIssueStageFilterField'),
      ),
    );
    expect(statusDropdown.initialValue, 'failed');
    expect(replayScopeDropdown.initialValue, 'attention');
    expect(issueSeverityDropdown.initialValue, 'error');
    expect(issueStageDropdown.initialValue, 'load_feed');
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsFilteredCountChip'),
      ),
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportRunsFilteredCountChip'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console persists catalog import run filters and clears persisted scope',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    CoachCatalogImportRunFilterPreferences? savedPreferences;
    var clearCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (preferences) async {
            savedPreferences = preferences;
          },
          clearCatalogImportRunFilterPreferencesOverride: () async {
            clearCalls += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final statusDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsStatusFilterField'),
    );
    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!
        .call('failed');
    await tester.pumpAndSettle();

    expect(savedPreferences?.status, 'failed');
    expect(savedPreferences?.replayScope, 'all');
    expect(savedPreferences?.issueSeverity, 'all');
    expect(savedPreferences?.issueStage, 'all');
    expect(clearCalls, 0);

    final clearFiltersButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsClearFiltersButton'),
    );
    await _dragUntilFinderVisible(tester, clearFiltersButton);
    tester.widget<OutlinedButton>(clearFiltersButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(clearCalls, 1);
    expect(api.lastCatalogImportRunStatusFilter, isNull);
    expect(api.lastCatalogImportRunReplayScopeFilter, isNull);
    expect(api.lastCatalogImportRunIssueSeverityFilter, isNull);
    expect(api.lastCatalogImportRunIssueStageFilter, isNull);
  });

  testWidgets(
      'coach operator console saves and applies catalog import run saved views',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    var savedViews = <CoachCatalogImportRunSavedView>[];

    Future<List<CoachCatalogImportRunSavedView>> saveView(
      CoachCatalogImportRunSavedView view,
    ) async {
      savedViews = <CoachCatalogImportRunSavedView>[
        view,
        ...savedViews.where((entry) => entry.viewId != view.viewId),
      ];
      return savedViews;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          loadCatalogImportRunSavedViewsOverride: () async => savedViews,
          saveCatalogImportRunSavedViewOverride: saveView,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final statusDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsStatusFilterField'),
    );
    final replayScopeDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsReplayScopeFilterField'),
    );
    final issueSeverityDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsIssueSeverityFilterField'),
    );
    final issueStageDropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsIssueStageFilterField'),
    );
    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!
        .call('failed');
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<String>>(replayScopeDropdown)
        .onChanged!
        .call('attention');
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<String>>(issueSeverityDropdown)
        .onChanged!
        .call('error');
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<String>>(issueStageDropdown)
        .onChanged!
        .call('load_feed');
    await tester.pumpAndSettle();
    final savedViewNameField = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsSavedViewNameField'),
    );
    await _dragUntilFinderVisible(tester, savedViewNameField);
    await tester.enterText(
      savedViewNameField,
      'Failed attention',
    );
    final saveViewButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsSaveViewButton'),
    );
    await _dragUntilFinderVisible(tester, saveViewButton);
    tester.widget<OutlinedButton>(saveViewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(savedViews, hasLength(1));
    expect(savedViews.first.name, 'Failed attention');
    expect(savedViews.first.preferences.status, 'failed');
    expect(savedViews.first.preferences.replayScope, 'attention');
    expect(savedViews.first.preferences.issueSeverity, 'error');
    expect(savedViews.first.preferences.issueStage, 'load_feed');
    expect(find.text('Failed attention'), findsWidgets);

    await _dragUntilFinderVisible(tester, statusDropdown, dragDy: 320);
    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!
        .call('running');
    await tester.pump();
    await _dragUntilFinderVisible(tester, replayScopeDropdown, dragDy: 320);
    tester
        .widget<DropdownButtonFormField<String>>(replayScopeDropdown)
        .onChanged!
        .call('all');
    await tester.pump();
    await _dragUntilFinderVisible(tester, issueSeverityDropdown, dragDy: 320);
    tester
        .widget<DropdownButtonFormField<String>>(issueSeverityDropdown)
        .onChanged!
        .call('all');
    await tester.pump();
    await _dragUntilFinderVisible(tester, issueStageDropdown, dragDy: 320);
    tester
        .widget<DropdownButtonFormField<String>>(issueStageDropdown)
        .onChanged!
        .call('all');
    await tester.pumpAndSettle();

    final applySavedViewButton = find.byKey(
      ValueKey(
        'coachOpsCatalogImportRunsApplySavedView_${savedViews.first.viewId}',
      ),
    );
    await _dragUntilFinderVisible(tester, applySavedViewButton);
    tester.widget<OutlinedButton>(applySavedViewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunStatusFilter, 'failed');
    expect(api.lastCatalogImportRunReplayScopeFilter, 'attention');
    expect(api.lastCatalogImportRunIssueSeverityFilter, 'error');
    expect(api.lastCatalogImportRunIssueStageFilter, 'load_feed');
  });

  testWidgets(
      'coach operator console saves shared catalog import run saved views without default toggle',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    var savedViews = <CoachCatalogImportRunSavedView>[];

    Future<List<CoachCatalogImportRunSavedView>> saveView(
      CoachCatalogImportRunSavedView view,
    ) async {
      savedViews = <CoachCatalogImportRunSavedView>[
        view,
        ...savedViews.where(
          (entry) =>
              entry.viewId != view.viewId ||
              entry.visibilityScope != view.visibilityScope,
        ),
      ];
      return savedViews;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          saveCatalogImportRunFilterPreferencesOverride: (_) async {},
          loadCatalogImportRunSavedViewsOverride: () async => savedViews,
          saveCatalogImportRunSavedViewOverride: saveView,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(
            const ValueKey('coachOpsCatalogImportRunsStatusFilterField'),
          ),
        )
        .onChanged!
        .call('failed');
    await tester.pump();
    final savedViewNameField = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsSavedViewNameField'),
    );
    await _dragUntilFinderVisible(tester, savedViewNameField);
    await tester.enterText(
      savedViewNameField,
      'Shared failures',
    );
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(
            const ValueKey('coachOpsCatalogImportRunsSavedViewScopeField'),
          ),
        )
        .onChanged!
        .call('shared_ops');
    await tester.pump();

    final saveViewButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsSaveViewButton'),
    );
    await _dragUntilFinderVisible(tester, saveViewButton);
    tester.widget<OutlinedButton>(saveViewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(savedViews, hasLength(1));
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.isDefault, isFalse);
    expect(find.text('Shared with ops'), findsWidgets);

    final setDefaultButton = find.byKey(
      ValueKey(
        'coachOpsCatalogImportRunsToggleDefaultSavedView_${savedViews.single.viewId}',
      ),
    );
    await _dragUntilFinderVisible(tester, setDefaultButton);
    expect(
      tester.widget<OutlinedButton>(setDefaultButton).onPressed,
      isNull,
    );
  });

  testWidgets(
      'coach operator console filters catalog import run saved views by scope',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_personal_failed',
          name: 'Personal failed',
          visibilityScope: 'personal',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:00:00Z',
          updatedAtIso: '2026-04-16T08:01:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_failed',
          accountId: 'acct_ops_shared',
          name: 'Shared failed',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_demo_express'],
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final scopeFilter = find.byKey(
      const ValueKey(
          'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField'),
    );
    await _dragUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunSavedViewsVisibilityScope, 'shared_ops');
    expect(api.catalogImportRunSavedViewOperatorsCalls, 1);
    expect(find.text('All shared owners (1)'), findsOneWidget);
    expect(
      find.text('1 shared owner discovered across 1 shared view.'),
      findsOneWidget,
    );
    expect(find.text('All operators (1)'), findsOneWidget);
    expect(
      find.text(
        '1 operator-scoped target discovered across 1 shared view. All-operator views remain visible.',
      ),
      findsOneWidget,
    );
    expect(find.text('Shared failed'), findsOneWidget);
    expect(find.text('Shared by acct_ops_shared'), findsOneWidget);
    expect(find.text('Personal failed'), findsNothing);
  });

  testWidgets(
      'coach operator console restricts shared catalog import run saved views to privilege operators',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_express',
          accountId: 'acct_ops_shared',
          name: 'Shared express',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_demo_express'],
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_border',
          accountId: 'acct_ops_other',
          name: 'Shared border',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_border_runner'],
          preferences:
              CoachCatalogImportRunFilterPreferences(status: 'running'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_broad',
          accountId: 'acct_ops_global',
          name: 'Shared broad',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'all'),
          createdAtIso: '2026-04-16T08:06:00Z',
          updatedAtIso: '2026-04-16T08:07:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
            operatorIds: <String>['op_demo_express'],
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final scopeFilter = find.byKey(
      const ValueKey(
          'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField'),
    );
    await _dragUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunSavedViewsVisibilityScope, 'shared_ops');
    expect(find.text('Shared express'), findsOneWidget);
    expect(find.text('Shared border'), findsNothing);
    expect(find.text('Shared broad'), findsNothing);
    expect(find.text('All operators (1)'), findsOneWidget);
    expect(
      find.text(
        '1 operator-scoped target discovered across 1 shared view. All-operator views remain visible.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console filters shared catalog import run saved views by owner',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_a',
          accountId: 'acct_ops_shared',
          name: 'Shared failed A',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_b',
          accountId: 'acct_ops_other',
          name: 'Shared failed B',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField',
      ),
    );
    await _dragUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    final ownerFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsSavedViewsOwnerFilterField',
      ),
    );
    await _dragUntilFinderVisible(tester, ownerFilter);
    tester.widget<DropdownButtonFormField<String>>(ownerFilter).onChanged!.call(
          'acct_ops_other',
        );
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunSavedViewsVisibilityScope, 'shared_ops');
    expect(api.lastCatalogImportRunSavedViewsOwnerAccountId, 'acct_ops_other');
    expect(find.text('acct_ops_other (1)'), findsOneWidget);
    expect(
      find.text('acct_ops_other exposes 1 shared view.'),
      findsOneWidget,
    );
    expect(find.text('Shared failed B'), findsOneWidget);
    expect(find.text('Shared by acct_ops_other'), findsOneWidget);
    expect(find.text('Shared failed A'), findsNothing);
  });

  testWidgets(
      'coach operator console can filter catalog import run saved views by owner from saved view card',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_a',
          accountId: 'acct_ops_shared',
          name: 'Shared failed A',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_b',
          accountId: 'acct_ops_other',
          name: 'Shared failed B',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final filterByOwnerButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsFilterByOwner_catalogview_shared_b',
      ),
    );
    await _dragUntilFinderVisible(tester, filterByOwnerButton);
    tester.widget<OutlinedButton>(filterByOwnerButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunSavedViewsVisibilityScope, 'shared_ops');
    expect(api.lastCatalogImportRunSavedViewsOwnerAccountId, 'acct_ops_other');
    expect(find.text('Shared failed B'), findsOneWidget);
    expect(find.text('Shared failed A'), findsNothing);
  });

  testWidgets(
      'coach operator console can filter catalog import run saved views by operator from saved view card',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_a',
          accountId: 'acct_ops_shared',
          name: 'Shared failed A',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_demo_express'],
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_b',
          accountId: 'acct_ops_other',
          name: 'Shared failed B',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_border_runner'],
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField',
      ),
    );
    await _dragUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    final filterByOperatorButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsFilterByOperator_catalogview_shared_b',
      ),
    );
    await _dragUntilFinderVisible(tester, filterByOperatorButton);
    tester.widget<OutlinedButton>(filterByOperatorButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.lastCatalogImportRunSavedViewsVisibilityScope, 'shared_ops');
    expect(api.lastCatalogImportRunSavedViewsOperatorId, 'op_border_runner');
    expect(find.text('Shared failed B'), findsOneWidget);
    expect(find.text('Shared failed A'), findsNothing);
  });

  testWidgets(
      'coach operator console renders non-owned shared catalog import run saved views as read only',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_read_only',
          accountId: 'acct_ops_other',
          name: 'Shared failed B',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          canManage: false,
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    await _dragUntilTextVisible(tester, 'Read-only shared view');
    expect(find.text('Read-only shared view'), findsOneWidget);
    final deleteButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsDeleteSavedView_catalogview_shared_read_only',
      ),
    );
    await _dragUntilFinderVisible(tester, deleteButton);
    expect(tester.widget<TextButton>(deleteButton).onPressed, isNull);
  });

  testWidgets(
      'coach operator console shows catalog import run saved view content chips',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_content',
          accountId: 'acct_ops_other',
          name: 'Shared failed attention',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunFilterPreferences(
            status: 'failed',
            replayScope: 'attention',
            issueSeverity: 'warning',
            issueStage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    await _dragUntilTextVisible(tester, 'Shared failed attention');
    expect(
        find.text('Run status: Failed', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Replay scope: Attention', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Issue severity: Warning', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Issue stage: load_feed', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console shows active filter chips on catalog import run saved view cards',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_shared_active',
          accountId: 'acct_ops_other',
          name: 'Shared failed active',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_border_runner'],
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    await _dragUntilTextVisible(tester, 'Shared failed active');

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsApplySavedView_catalogview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, applyButton);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    final filterByOwnerButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsFilterByOwner_catalogview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, filterByOwnerButton);
    tester.widget<OutlinedButton>(filterByOwnerButton).onPressed!.call();
    await tester.pumpAndSettle();

    final filterByOperatorButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsFilterByOperator_catalogview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, filterByOperatorButton);
    tester.widget<OutlinedButton>(filterByOperatorButton).onPressed!.call();
    await tester.pumpAndSettle();

    final pinButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsTogglePinnedSavedView_catalogview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, pinButton);
    tester.widget<OutlinedButton>(pinButton).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Active scope', skipOffstage: false), findsOneWidget);
    expect(find.text('Active owner', skipOffstage: false), findsOneWidget);
    expect(find.text('Active operator', skipOffstage: false), findsOneWidget);
    expect(find.text('Using this view', skipOffstage: false), findsOneWidget);
    expect(find.text('Pinned', skipOffstage: false), findsOneWidget);
    expect(find.text('Unpin view', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('Last used ', skipOffstage: false),
      findsOneWidget,
    );
    await _dragUntilTextVisible(tester, 'Recent views');
    final recentChip = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsRecentSavedView_catalogview_shared_active',
      ),
      skipOffstage: false,
    );
    expect(recentChip, findsOneWidget);
    expect(tester.widget<ActionChip>(recentChip).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(applyButton).onPressed, isNull);
    expect(
      find.text('View already active', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console sorts current catalog import run saved view first',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_personal_a',
          name: 'Personal running A',
          visibilityScope: 'personal',
          preferences:
              CoachCatalogImportRunFilterPreferences(status: 'running'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_personal_b',
          name: 'Personal failed B',
          visibilityScope: 'personal',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'personal',
        );
    await tester.pumpAndSettle();

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsApplySavedView_catalogview_personal_b',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, applyButton);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'View already active');
    await _dragUntilTextVisible(tester, 'Personal running A');
    await _dragUntilTextVisible(tester, 'Recent views');
    final recentChip = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsRecentSavedView_catalogview_personal_b',
      ),
      skipOffstage: false,
    );
    expect(recentChip, findsOneWidget);
    expect(tester.widget<ActionChip>(recentChip).onPressed, isNull);
    final activeOffset = tester.getTopLeft(
      find.text('View already active', skipOffstage: false),
    );
    final otherOffset = tester.getTopLeft(
      find.text('Personal running A', skipOffstage: false),
    );
    expect(activeOffset.dy, lessThan(otherOffset.dy));
  });

  testWidgets(
      'coach operator console sorts recently used catalog import run saved view ahead of stale views',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_personal_b',
          name: 'Personal failed B',
          visibilityScope: 'personal',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_personal_a',
          name: 'Personal running A',
          visibilityScope: 'personal',
          preferences:
              CoachCatalogImportRunFilterPreferences(status: 'running'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'personal',
        );
    await tester.pumpAndSettle();

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsApplySavedView_catalogview_personal_a',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, applyButton);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    final statusFilter = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsStatusFilterField'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, statusFilter);
    tester
        .widget<DropdownButtonFormField<String>>(statusFilter)
        .onChanged!('all');
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Personal failed B');
    final recentApplyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsApplySavedView_catalogview_personal_a',
      ),
      skipOffstage: false,
    );
    final staleApplyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsApplySavedView_catalogview_personal_b',
      ),
      skipOffstage: false,
    );
    expect(recentApplyButton, findsOneWidget);
    expect(staleApplyButton, findsOneWidget);
    final recentOffset = tester.getTopLeft(
      recentApplyButton,
    );
    final staleOffset = tester.getTopLeft(
      staleApplyButton,
    );
    expect(recentOffset.dy, lessThan(staleOffset.dy));
  });

  testWidgets(
      'coach operator console applies default catalog import run saved view when no persisted filters exist',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_failed_attention',
          name: 'Failed attention',
          preferences: CoachCatalogImportRunFilterPreferences(
            status: 'failed',
            replayScope: 'attention',
            issueSeverity: 'error',
            issueStage: 'load_feed',
          ),
          isDefault: true,
          createdAtIso: '2026-04-16T07:58:00Z',
          updatedAtIso: '2026-04-16T07:59:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.catalogImportRunSavedViewsCalls, 1);
    expect(api.lastCatalogImportRunStatusFilter, 'failed');
    expect(api.lastCatalogImportRunReplayScopeFilter, 'attention');
    expect(api.lastCatalogImportRunIssueSeverityFilter, 'error');
    expect(api.lastCatalogImportRunIssueStageFilter, 'load_feed');
  });

  testWidgets(
      'coach operator console can set catalog import run saved view as default',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_failed_attention',
          name: 'Failed attention',
          preferences: CoachCatalogImportRunFilterPreferences(
            status: 'failed',
            replayScope: 'attention',
            issueSeverity: 'error',
            issueStage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T07:58:00Z',
          updatedAtIso: '2026-04-16T07:59:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final setDefaultButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsToggleDefaultSavedView_catalogview_failed_attention',
      ),
    );
    await _dragUntilFinderVisible(tester, setDefaultButton);
    tester.widget<OutlinedButton>(setDefaultButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunSavedViewUpsertCalls, 1);
    expect(api.catalogImportRunSavedViews.single.isDefault, isTrue);
    expect(find.text('Default view'), findsOneWidget);
  });

  testWidgets(
      'coach operator console opens catalog import run details and linked source artifact',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.ensureVisible(detailsButton);
    await tester.pumpAndSettle();
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    expect(api.catalogImportRunDetailCalls, 1);
    expect(api.lastCatalogImportRunDetailId, 'catalogimportrun_demo_failed');
    expect(api.catalogImportRunLineageCalls, 1);
    expect(api.lastCatalogImportRunLineageId, 'catalogimportrun_demo_failed');
    expect(find.text('Catalog import run details'), findsOneWidget);
    expect(find.text('Source artifact id: catalogsourceartifact_demo_failed'),
        findsOneWidget);
    expect(
      find.text(
        'Replayed from import run: catalogimportrun_demo_failed_old_2',
      ),
      findsOneWidget,
    );
    expect(find.text('Issues (3)'), findsOneWidget);
    expect(find.text('Loaded 2 • errors 2 • warnings 1'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunIssuePresetErrors_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunIssuePresetWarnings_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunIssuePresetLoadFeed_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunIssueSeverityFilterField_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunIssueStageFilterField_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Row: row:42'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunLoadOlderIssues_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunReplay_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunViewReplaySource_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Replay runs (3)'), findsOneWidget);
    expect(
      find.text('Loaded 2 • failed 1 • succeeded 1 • running 1'),
      findsOneWidget,
    );
    expect(
      find.text(
        'catalogimportrun_demo_failed_replay_2 • succeeded • manual',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunLoadOlderReplays_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );

    final viewSourceArtifactButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewSourceArtifact_catalogimportrun_demo_failed',
      ),
    );
    expect(viewSourceArtifactButton, findsOneWidget);
    await tester.ensureVisible(viewSourceArtifactButton);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(viewSourceArtifactButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Source artifact details'), findsOneWidget);
    expect(api.catalogSourceArtifactDetailCalls, 1);
    expect(
      api.lastCatalogSourceArtifactDetailId,
      'catalogsourceartifact_demo_failed',
    );
    expect(find.text('Artifact id: catalogsourceartifact_demo_failed'),
        findsOneWidget);
    expect(
      find.text(
        'Referenced by import run: catalogimportrun_demo_failed',
      ),
      findsOneWidget,
    );
    expect(find.text('Referencing import runs (3)'), findsOneWidget);
    expect(
      find.text('Loaded 2 • failed 2 • succeeded 1 • running 0'),
      findsOneWidget,
    );
    expect(
      find.text('catalogimportrun_demo_failed • failed • startup'),
      findsOneWidget,
    );
    expect(
      find.text('catalogimportrun_demo_failed_old_2 • succeeded • scheduled'),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogSourceArtifactLoadOlderRuns_catalogsourceartifact_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogSourceArtifactViewImportRun_catalogsourceartifact_demo_failed_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogSourceArtifactRunImportFromDetails_catalogsourceartifact_demo_failed',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console filters catalog import run issues',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    expect(detailsButton, findsOneWidget);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final severityFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSeverityFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, severityFilter);
    expect(severityFilter, findsOneWidget);
    tester
        .widget<DropdownButtonFormField<String>>(severityFilter)
        .onChanged!
        .call('warning');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.catalogImportRunDetailCalls, 2);
    expect(api.lastCatalogImportRunDetailSeverity, 'warning');
    expect(api.lastCatalogImportRunDetailStage, 'all');
    expect(
      find.text('Filtered 1 of 3 • Loaded 1 • errors 0 • warnings 1'),
      findsOneWidget,
    );
    expect(
      find.text('WARNING • hydrate_trip • partial_trip_skip'),
      findsOneWidget,
    );
    expect(
      find.text('ERROR • load_feed • required_file_missing'),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console restores persisted catalog import run issue filters on open',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          loadCatalogImportRunIssueFilterPreferencesOverride: () async =>
              const CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'load_feed',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    expect(detailsButton, findsOneWidget);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.catalogImportRunDetailCalls, 2);
    expect(api.lastCatalogImportRunDetailSeverity, 'error');
    expect(api.lastCatalogImportRunDetailStage, 'load_feed');
    expect(
      find.text('Filtered 1 of 3 • Loaded 1 • errors 1 • warnings 0'),
      findsOneWidget,
    );
    expect(
      find.text('ERROR • load_feed • required_file_missing'),
      findsOneWidget,
    );
    expect(
      find.text('ERROR • parse_stop_times • invalid_time_value'),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console applies catalog import run issue error preset',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final errorsOnlyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssuePresetErrors_catalogimportrun_demo_failed',
      ),
    );
    expect(errorsOnlyButton, findsOneWidget);
    await _dragUntilFinderVisible(tester, errorsOnlyButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(errorsOnlyButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.catalogImportRunDetailCalls, 2);
    expect(api.lastCatalogImportRunDetailSeverity, 'error');
    expect(api.lastCatalogImportRunDetailStage, 'all');
    expect(
      find.text('Filtered 2 of 3 • Loaded 2 • errors 2 • warnings 0'),
      findsOneWidget,
    );
    expect(
      find.text('ERROR • load_feed • required_file_missing'),
      findsOneWidget,
    );
    expect(
      find.text('WARNING • hydrate_trip • partial_trip_skip'),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunIssuePresetClear_catalogimportrun_demo_failed',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console applies catalog import run load feed preset',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final loadFeedOnlyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssuePresetLoadFeed_catalogimportrun_demo_failed',
      ),
    );
    expect(loadFeedOnlyButton, findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      loadFeedOnlyButton,
      maxAttempts: 20,
    );
    tester.widget<OutlinedButton>(loadFeedOnlyButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.catalogImportRunDetailCalls, 2);
    expect(api.lastCatalogImportRunDetailSeverity, 'all');
    expect(api.lastCatalogImportRunDetailStage, 'load_feed');
    expect(
      find.text('Filtered 1 of 3 • Loaded 1 • errors 1 • warnings 0'),
      findsOneWidget,
    );
    expect(
      find.text('ERROR • load_feed • required_file_missing'),
      findsOneWidget,
    );
    expect(
      find.text('ERROR • parse_stop_times • invalid_time_value'),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console saves and applies catalog import run issue saved views',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    var savedIssueViews = <CoachCatalogImportRunIssueSavedView>[];

    Future<List<CoachCatalogImportRunIssueSavedView>> saveIssueSavedView(
      CoachCatalogImportRunIssueSavedView view,
    ) async {
      savedIssueViews = <CoachCatalogImportRunIssueSavedView>[
        view,
        ...savedIssueViews.where(
          (entry) =>
              entry.viewId != view.viewId &&
              entry.name.trim().toLowerCase() != view.name.trim().toLowerCase(),
        ),
      ];
      return savedIssueViews;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          loadCatalogImportRunIssueSavedViewsOverride: () async =>
              savedIssueViews,
          saveCatalogImportRunIssueSavedViewOverride: saveIssueSavedView,
          deleteCatalogImportRunIssueSavedViewOverride: (viewId) async {
            savedIssueViews = savedIssueViews
                .where((entry) => entry.viewId != viewId.trim())
                .toList(growable: false);
            return savedIssueViews;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    expect(detailsButton, findsOneWidget);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final severityFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSeverityFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, severityFilter);
    expect(severityFilter, findsOneWidget);
    tester
        .widget<DropdownButtonFormField<String>>(severityFilter)
        .onChanged!
        .call('warning');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final savedViewNameField = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewNameField_catalogimportrun_demo_failed',
      ),
    );
    await tester.enterText(savedViewNameField, 'Warnings drilldown');
    await tester.pump();
    final saveViewButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSaveView_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, saveViewButton, dragDy: -200);
    expect(saveViewButton, findsOneWidget);
    tester.widget<OutlinedButton>(saveViewButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(savedIssueViews, hasLength(1));
    expect(savedIssueViews.first.preferences.severity, 'warning');
    expect(savedIssueViews.first.preferences.stage, 'all');
    expect(find.text('Warnings drilldown'), findsOneWidget);

    final clearPresetButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssuePresetClear_catalogimportrun_demo_failed',
      ),
    );
    await tester.tap(clearPresetButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final applySavedViewButton = find.byKey(
      ValueKey(
        'coachOpsCatalogImportRunIssueApplySavedView_catalogimportrun_demo_failed_${savedIssueViews.first.viewId}',
      ),
    );
    await _dragUntilFinderVisible(tester, applySavedViewButton, dragDy: -200);
    expect(applySavedViewButton, findsOneWidget);
    tester.widget<OutlinedButton>(applySavedViewButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.catalogImportRunDetailCalls, 4);
    expect(api.lastCatalogImportRunDetailSeverity, 'warning');
    expect(api.lastCatalogImportRunDetailStage, 'all');
    expect(
      find.text('Filtered 1 of 3 • Loaded 1 • errors 0 • warnings 1'),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console saves shared catalog import run issue saved views without default toggle',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    var savedIssueViews = <CoachCatalogImportRunIssueSavedView>[];

    Future<List<CoachCatalogImportRunIssueSavedView>> saveIssueSavedView(
      CoachCatalogImportRunIssueSavedView view,
    ) async {
      savedIssueViews = <CoachCatalogImportRunIssueSavedView>[
        view,
        ...savedIssueViews.where(
          (entry) =>
              entry.viewId != view.viewId ||
              entry.visibilityScope != view.visibilityScope,
        ),
      ];
      return savedIssueViews;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          loadCatalogImportRunIssueSavedViewsOverride: () async =>
              savedIssueViews,
          saveCatalogImportRunIssueSavedViewOverride: saveIssueSavedView,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final severityFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSeverityFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, severityFilter);
    tester
        .widget<DropdownButtonFormField<String>>(severityFilter)
        .onChanged!
        .call('error');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final savedViewNameField = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewNameField_catalogimportrun_demo_failed',
      ),
    );
    await tester.enterText(savedViewNameField, 'Shared errors');
    await tester.pump();

    final scopeField = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewScopeField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, scopeField);
    tester
        .widget<DropdownButtonFormField<String>>(scopeField)
        .onChanged!
        .call('shared_ops');
    await tester.pump();

    final saveViewButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSaveView_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, saveViewButton, dragDy: -200);
    tester.widget<OutlinedButton>(saveViewButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(savedIssueViews, hasLength(1));
    expect(savedIssueViews.single.visibilityScope, 'shared_ops');
    expect(savedIssueViews.single.isDefault, isFalse);
    expect(find.text('Shared with ops'), findsWidgets);

    final setDefaultButton = find.byKey(
      ValueKey(
        'coachOpsCatalogImportRunIssueToggleDefaultSavedView_catalogimportrun_demo_failed_${savedIssueViews.single.viewId}',
      ),
    );
    await _pumpUntilFinderVisible(tester, setDefaultButton);
    expect(
      tester.widget<OutlinedButton>(setDefaultButton).onPressed,
      isNull,
    );
  });

  testWidgets(
      'coach operator console filters issue saved views by scope in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_personal',
          name: 'Personal errors',
          visibilityScope: 'personal',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'all',
          ),
          createdAtIso: '2026-04-16T08:00:00Z',
          updatedAtIso: '2026-04-16T08:01:00Z',
        ),
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared',
          accountId: 'acct_ops_shared',
          name: 'Shared errors',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_demo_express'],
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewsVisibilityFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        api.lastCatalogImportRunIssueSavedViewsVisibilityScope, 'shared_ops');
    expect(api.catalogImportRunIssueSavedViewOperatorsCalls, 1);
    expect(find.text('All shared owners (1)'), findsOneWidget);
    expect(
      find.text('1 shared owner discovered across 1 shared view.'),
      findsOneWidget,
    );
    expect(find.text('All operators (1)'), findsOneWidget);
    expect(
      find.text(
        '1 operator-scoped target discovered across 1 shared view. All-operator views remain visible.',
      ),
      findsOneWidget,
    );
    expect(find.text('Shared errors'), findsOneWidget);
    expect(find.text('Shared by acct_ops_shared'), findsOneWidget);
    expect(find.text('Personal errors'), findsNothing);
  });

  testWidgets(
      'coach operator console restricts shared issue saved views to privilege operators in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_express',
          accountId: 'acct_ops_shared',
          name: 'Shared express errors',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_demo_express'],
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_border',
          accountId: 'acct_ops_other',
          name: 'Shared border errors',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_border_runner'],
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_broad',
          accountId: 'acct_ops_global',
          name: 'Shared broad errors',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'all',
          ),
          createdAtIso: '2026-04-16T08:06:00Z',
          updatedAtIso: '2026-04-16T08:07:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
            operatorIds: <String>['op_demo_express'],
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewsVisibilityFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Shared express errors'), findsOneWidget);
    expect(find.text('Shared border errors'), findsNothing);
    expect(find.text('Shared broad errors'), findsNothing);
    expect(find.text('All operators (1)'), findsOneWidget);
  });

  testWidgets(
      'coach operator console filters shared issue saved views by owner in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_a',
          accountId: 'acct_ops_shared',
          name: 'Shared errors A',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_b',
          accountId: 'acct_ops_other',
          name: 'Shared errors B',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewsVisibilityFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final ownerFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewsOwnerFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, ownerFilter);
    tester.widget<DropdownButtonFormField<String>>(ownerFilter).onChanged!.call(
          'acct_ops_other',
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      api.lastCatalogImportRunIssueSavedViewsVisibilityScope,
      'shared_ops',
    );
    expect(
      api.lastCatalogImportRunIssueSavedViewsOwnerAccountId,
      'acct_ops_other',
    );
    expect(find.text('acct_ops_other (1)'), findsOneWidget);
    expect(
      find.text('acct_ops_other exposes 1 shared view.'),
      findsOneWidget,
    );
    expect(find.text('Shared errors B'), findsOneWidget);
    expect(find.text('Shared by acct_ops_other'), findsOneWidget);
    expect(find.text('Shared errors A'), findsNothing);
  });

  testWidgets(
      'coach operator console can filter issue saved views by owner from saved view card',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_a',
          accountId: 'acct_ops_shared',
          name: 'Shared errors A',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_b',
          accountId: 'acct_ops_other',
          name: 'Shared errors B',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final filterByOwnerButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueFilterByOwner_catalogimportrun_demo_failed_catalogissueview_shared_b',
      ),
    );
    await _pumpUntilFinderVisible(tester, filterByOwnerButton);
    tester.widget<OutlinedButton>(filterByOwnerButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      api.lastCatalogImportRunIssueSavedViewsVisibilityScope,
      'shared_ops',
    );
    expect(
      api.lastCatalogImportRunIssueSavedViewsOwnerAccountId,
      'acct_ops_other',
    );
    expect(find.text('Shared errors B'), findsOneWidget);
    expect(find.text('Shared errors A'), findsNothing);
  });

  testWidgets(
      'coach operator console can filter issue saved views by operator from saved view card',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_a',
          accountId: 'acct_ops_shared',
          name: 'Shared errors A',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_demo_express'],
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_b',
          accountId: 'acct_ops_other',
          name: 'Shared errors B',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_border_runner'],
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewsVisibilityFilterField_catalogimportrun_demo_failed',
      ),
    );
    await _pumpUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final filterByOperatorButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueFilterByOperator_catalogimportrun_demo_failed_catalogissueview_shared_b',
      ),
    );
    await _pumpUntilFinderVisible(tester, filterByOperatorButton);
    tester.widget<OutlinedButton>(filterByOperatorButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      api.lastCatalogImportRunIssueSavedViewsVisibilityScope,
      'shared_ops',
    );
    expect(
      api.lastCatalogImportRunIssueSavedViewsOperatorId,
      'op_border_runner',
    );
    expect(find.text('Shared errors B'), findsOneWidget);
    expect(find.text('Shared errors A'), findsNothing);
  });

  testWidgets(
      'coach operator console renders non-owned shared issue saved views as read only',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_read_only',
          accountId: 'acct_ops_other',
          name: 'Shared errors B',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'load_feed',
          ),
          canManage: false,
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final readOnlyLabel = find.text('Read-only shared view');
    await _pumpUntilFinderVisible(tester, readOnlyLabel);
    expect(readOnlyLabel, findsOneWidget);
    final deleteButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueDeleteSavedView_catalogimportrun_demo_failed_catalogissueview_shared_read_only',
      ),
    );
    await _pumpUntilFinderVisible(tester, deleteButton);
    expect(tester.widget<OutlinedButton>(deleteButton).onPressed, isNull);
  });

  testWidgets(
      'coach operator console shows issue saved view content chips in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_content',
          accountId: 'acct_ops_other',
          name: 'Shared warnings',
          visibilityScope: 'shared_ops',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _pumpUntilFinderVisible(tester, find.text('Shared warnings'));
    expect(find.text('Issue severity: Warning'), findsWidgets);
    expect(find.text('Issue stage: load_feed'), findsWidgets);
  });

  testWidgets(
      'coach operator console shows active filter chips on issue saved view cards in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_shared_active',
          accountId: 'acct_ops_other',
          name: 'Shared warnings active',
          visibilityScope: 'shared_ops',
          operatorIds: <String>['op_border_runner'],
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'load_feed',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueApplySavedView_catalogimportrun_demo_failed_catalogissueview_shared_active',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, applyButton);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final filterByOwnerButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueFilterByOwner_catalogimportrun_demo_failed_catalogissueview_shared_active',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, filterByOwnerButton);
    tester.widget<OutlinedButton>(filterByOwnerButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final filterByOperatorButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueFilterByOperator_catalogimportrun_demo_failed_catalogissueview_shared_active',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, filterByOperatorButton);
    tester.widget<OutlinedButton>(filterByOperatorButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final pinButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueTogglePinnedSavedView_catalogimportrun_demo_failed_catalogissueview_shared_active',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, pinButton);
    tester.widget<OutlinedButton>(pinButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Active scope', skipOffstage: false), findsOneWidget);
    expect(find.text('Active owner', skipOffstage: false), findsOneWidget);
    expect(find.text('Active operator', skipOffstage: false), findsOneWidget);
    expect(find.text('Using this view', skipOffstage: false), findsOneWidget);
    expect(find.text('Pinned', skipOffstage: false), findsOneWidget);
    expect(find.text('Unpin view', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('Last used ', skipOffstage: false),
      findsOneWidget,
    );
    await _dragUntilTextVisible(tester, 'Recent views');
    final recentChip = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueRecentSavedView_catalogimportrun_demo_failed_catalogissueview_shared_active',
      ),
      skipOffstage: false,
    );
    expect(recentChip, findsOneWidget);
    expect(tester.widget<ActionChip>(recentChip).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(applyButton).onPressed, isNull);
    expect(
      find.text('View already active', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console sorts recently used issue saved view ahead of stale views in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_personal_b',
          name: 'Warnings B',
          visibilityScope: 'personal',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'warning',
            stage: 'all',
          ),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_personal_a',
          name: 'Errors A',
          visibilityScope: 'personal',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'all',
          ),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final savedViewsFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSavedViewsVisibilityFilterField_catalogimportrun_demo_failed',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, savedViewsFilter);
    tester
        .widget<DropdownButtonFormField<String>>(savedViewsFilter)
        .onChanged!('personal');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueApplySavedView_catalogimportrun_demo_failed_catalogissueview_personal_a',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, applyButton);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _dragUntilTextVisible(tester, 'Recent views');
    final recentChip = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueRecentSavedView_catalogimportrun_demo_failed_catalogissueview_personal_a',
      ),
      skipOffstage: false,
    );
    expect(recentChip, findsOneWidget);
    expect(tester.widget<ActionChip>(recentChip).onPressed, isNull);

    final severityField = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueSeverityFilterField_catalogimportrun_demo_failed',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, severityField);
    tester
        .widget<DropdownButtonFormField<String>>(severityField)
        .onChanged!('all');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final recentApplyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueApplySavedView_catalogimportrun_demo_failed_catalogissueview_personal_a',
      ),
      skipOffstage: false,
    );
    final staleApplyButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueApplySavedView_catalogimportrun_demo_failed_catalogissueview_personal_b',
      ),
      skipOffstage: false,
    );
    await _pumpUntilFinderVisible(tester, recentApplyButton);
    await _pumpUntilFinderVisible(tester, staleApplyButton);
    final recentOffset = tester.getTopLeft(
      recentApplyButton,
    );
    final staleOffset = tester.getTopLeft(
      staleApplyButton,
    );
    expect(recentOffset.dy, lessThan(staleOffset.dy));
  });

  testWidgets(
      'coach operator console applies default catalog import run issue saved view on open',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_errors',
          name: 'Errors only',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'all',
          ),
          isDefault: true,
          createdAtIso: '2026-04-16T08:00:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.catalogImportRunIssueSavedViewsCalls, 1);
    expect(api.lastCatalogImportRunDetailSeverity, 'error');
    expect(api.lastCatalogImportRunDetailStage, 'all');
    expect(find.text('Default view'), findsOneWidget);
  });

  testWidgets(
      'coach operator console can set catalog import run issue saved view as default',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunIssueSavedViews = <CoachCatalogImportRunIssueSavedView>[
        const CoachCatalogImportRunIssueSavedView(
          viewId: 'catalogissueview_errors',
          name: 'Errors only',
          preferences: CoachCatalogImportRunIssueFilterPreferences(
            severity: 'error',
            stage: 'all',
          ),
          createdAtIso: '2026-04-16T08:00:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final setDefaultButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunIssueToggleDefaultSavedView_catalogimportrun_demo_failed_catalogissueview_errors',
      ),
    );
    await _pumpUntilFinderVisible(tester, setDefaultButton);
    tester.widget<OutlinedButton>(setDefaultButton).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.catalogImportRunIssueSavedViewUpsertCalls, 1);
    expect(api.catalogImportRunIssueSavedViews.single.isDefault, isTrue);
    expect(find.text('Default view'), findsOneWidget);
  });

  testWidgets('coach operator console loads older replay runs in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunLineageCalls, 1);
    expect(api.lastCatalogImportRunLineageCursor, isNull);
    expect(
      find.text('catalogimportrun_demo_failed_replay_0 • running • manual'),
      findsNothing,
    );

    final loadOlderReplayRunsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunLoadOlderReplays_catalogimportrun_demo_failed',
      ),
    );
    expect(loadOlderReplayRunsButton, findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      loadOlderReplayRunsButton,
      maxAttempts: 20,
    );
    tester.widget<OutlinedButton>(loadOlderReplayRunsButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunLineageCalls, 2);
    expect(
      api.lastCatalogImportRunLineageCursor,
      '2026-04-14T10:10:00Z|catalogimportrun_demo_failed_replay_1',
    );
    expect(
      find.text('catalogimportrun_demo_failed_replay_0 • running • manual'),
      findsOneWidget,
    );
    expect(find.text('Loaded 3 • failed 1 • succeeded 1 • running 1'),
        findsOneWidget);
    expect(loadOlderReplayRunsButton, findsNothing);
  });

  testWidgets(
      'coach operator console opens replay source import run from run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final replaySourceButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewReplaySource_catalogimportrun_demo_failed',
      ),
    );
    expect(replaySourceButton, findsOneWidget);
    await _dragUntilFinderVisible(tester, replaySourceButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(replaySourceButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunDetailCalls, 2);
    expect(
      api.lastCatalogImportRunDetailId,
      'catalogimportrun_demo_failed_old_2',
    );
    expect(find.text('Catalog import run details'), findsOneWidget);
    expect(
      find.text('catalogimportrun_demo_failed_old_2'),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console loads older import run issues in run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunDetailCalls, 1);
    expect(api.lastCatalogImportRunDetailCursor, isNull);
    expect(
      find.text('trip skipped because terminal stop was missing'),
      findsNothing,
    );

    final loadOlderIssuesButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunLoadOlderIssues_catalogimportrun_demo_failed',
      ),
    );
    expect(loadOlderIssuesButton, findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      loadOlderIssuesButton,
      maxAttempts: 20,
    );
    tester.widget<OutlinedButton>(loadOlderIssuesButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunDetailCalls, 2);
    expect(
      api.lastCatalogImportRunDetailCursor,
      'catalogimportissue_demo_failed_2',
    );
    expect(
      find.text('trip skipped because terminal stop was missing'),
      findsOneWidget,
    );
    expect(find.text('Loaded 3 • errors 2 • warnings 1'), findsOneWidget);
    expect(loadOlderIssuesButton, findsNothing);
  });

  testWidgets(
      'coach operator console can replay import directly from run details',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final replayButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunReplay_catalogimportrun_demo_failed',
      ),
    );
    expect(replayButton, findsOneWidget);
    await _dragUntilFinderVisible(tester, replayButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(replayButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunTriggerCalls, 1);
    expect(api.lastTriggeredCatalogReplayImportRunId,
        'catalogimportrun_demo_failed');
    expect(api.lastTriggeredCatalogImportSourceArtifactId, isNull);
    expect(
        find.text(
            'Catalog import replay completed for catalogimportrun_demo_failed.'),
        findsOneWidget);
  });

  testWidgets(
      'coach operator console loads older referencing import runs in source artifact details',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final viewSourceArtifactButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewSourceArtifact_catalogimportrun_demo_failed',
      ),
    );
    tester.widget<OutlinedButton>(viewSourceArtifactButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      find.text('catalogimportrun_demo_failed_old_1 • failed • startup'),
      findsNothing,
    );
    final loadOlderRunsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogSourceArtifactLoadOlderRuns_catalogsourceartifact_demo_failed',
      ),
    );
    expect(loadOlderRunsButton, findsOneWidget);
    await _dragUntilFinderVisible(tester, loadOlderRunsButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(loadOlderRunsButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogSourceArtifactDetailCalls, 2);
    expect(
      find.text('catalogimportrun_demo_failed_old_1 • failed • startup'),
      findsOneWidget,
    );
    expect(loadOlderRunsButton, findsNothing);
  });

  testWidgets(
      'coach operator console can reopen referenced import run from source artifact details',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final viewSourceArtifactButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewSourceArtifact_catalogimportrun_demo_failed',
      ),
    );
    tester.widget<OutlinedButton>(viewSourceArtifactButton).onPressed!.call();
    await tester.pumpAndSettle();

    final reopenRunButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogSourceArtifactViewImportRun_catalogsourceartifact_demo_failed_catalogimportrun_demo_failed',
      ),
    );
    expect(reopenRunButton, findsOneWidget);
    await _dragUntilFinderVisible(tester, reopenRunButton, maxAttempts: 20);
    tester.widget<TextButton>(reopenRunButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunDetailCalls, 2);
    expect(api.lastCatalogImportRunDetailId, 'catalogimportrun_demo_failed');
    expect(find.text('Catalog import run details'), findsOneWidget);
  });

  testWidgets(
      'coach operator console can rerun import directly from source artifact details',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final detailsButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewDetails_catalogimportrun_demo_failed',
      ),
    );
    await _dragUntilFinderVisible(tester, detailsButton, maxAttempts: 40);
    await tester.pumpAndSettle();
    tester.widget<OutlinedButton>(detailsButton).onPressed!.call();
    await tester.pumpAndSettle();

    final viewSourceArtifactButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunViewSourceArtifact_catalogimportrun_demo_failed',
      ),
    );
    tester.widget<OutlinedButton>(viewSourceArtifactButton).onPressed!.call();
    await tester.pumpAndSettle();

    final rerunButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogSourceArtifactRunImportFromDetails_catalogsourceartifact_demo_failed',
      ),
    );
    expect(rerunButton, findsOneWidget);
    await _dragUntilFinderVisible(tester, rerunButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(rerunButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunTriggerCalls, 1);
    expect(
      api.lastTriggeredCatalogImportSourceArtifactId,
      'catalogsourceartifact_demo_failed',
    );
    expect(api.catalogImportRunEvents, hasLength(1));
    expect(api.catalogImportRunEvents.single.importRunId,
        'catalogimportrun_demo_manual_1');
  });

  testWidgets('coach operator console loads older catalog import runs',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    expect(find.textContaining('catalogimportrun_demo_old'), findsNothing);

    final loadOlderButton = find.byKey(
      const ValueKey('coachOpsCatalogImportRunsLoadOlderButton'),
    );
    await tester.dragUntilVisible(
      loadOlderButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(loadOlderButton, findsOneWidget);
    tester.widget<OutlinedButton>(loadOlderButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      api.lastCatalogImportRunCursor,
      '2026-04-13T10:08:00Z|catalogimportrun_demo_ok',
    );
    expect(find.textContaining('catalogimportrun_demo_old'), findsOneWidget);
  });

  testWidgets('coach operator console triggers configured catalog import',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import runs');
    final triggerButton = find.byKey(
      const ValueKey('coachOpsCatalogImportTriggerButton'),
    );
    await tester.dragUntilVisible(
      triggerButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(triggerButton, findsOneWidget);

    tester.widget<OutlinedButton>(triggerButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunTriggerCalls, 1);
    expect(api.operatorCatalogImportConfigCalls, 1);
    expect(api.operatorFeedHealthCalls, 1);
    expect(api.operatorCatalogSourceArtifactsCalls, 1);
    expect(api.catalogImportRunsCalls, 1);
    await _dragUntilFinderVisible(
      tester,
      find.textContaining('catalogimportrun_demo_manual_1'),
    );
    expect(
      find.textContaining('catalogimportrun_demo_manual_1'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Catalog import completed.'), findsOneWidget);
  });

  testWidgets('coach operator console renders operator feed health',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Operator feed health');
    expect(find.text('Operator feed health'), findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      find.textContaining('Demo B • gtfs_rt_trip_updates • error/stale'),
    );
    expect(find.textContaining('Demo B • gtfs_rt_trip_updates • error/stale'),
        findsOneWidget);
    expect(find.textContaining('Error: upstream timeout'), findsOneWidget);
  });

  testWidgets(
      'coach operator console disables catalog import trigger without ready config',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(
            ready: false,
          ),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    expect(find.text('Catalog import configuration'), findsOneWidget);
    expect(find.textContaining('Status: Missing'), findsOneWidget);
    expect(
      find.textContaining('Configured GTFS feed directory does not exist.'),
      findsOneWidget,
    );

    final triggerButton = find.byKey(
      const ValueKey('coachOpsCatalogImportTriggerButton'),
    );
    await tester.dragUntilVisible(
      triggerButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(triggerButton, findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(triggerButton).onPressed,
      isNull,
    );
    await _dragUntilFinderVisible(
      tester,
      find.byKey(
        const ValueKey('coachOpsCatalogImportTriggerDisabledHint'),
        skipOffstage: false,
      ),
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportTriggerDisabledHint'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Configure a valid GTFS source to enable manual import.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console shows read-only catalog import config guidance for support users',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['support_l1'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(
            ready: false,
            configured: false,
            feedLocator: null,
            detail:
                'Scoped source artifact required for this operator account.',
            configOrigin: 'operator_scope',
            sourceArtifactOverride: null,
            latestImportRunOverride: null,
          ),
          initialCatalogImportSources:
              const CoachOperatorCatalogImportSourcesResponse(
            generatedAtIso: '2026-04-15T10:07:10Z',
            sources: <CoachOperatorCatalogImportSourceOption>[],
          ),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    expect(
      find.byKey(const ValueKey('coachOpsCatalogImportConfigReadOnlyHint')),
      findsOneWidget,
    );
    expect(
      find.text(
        'This account is read-only for catalog imports. A catalog operator must select an in-scope GTFS source or upload a GTFS ZIP for this operator.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsCatalogImportConfigSaveButton')),
      findsNothing,
    );
  });

  testWidgets('coach operator console saves catalog import configuration',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    final field = find.byKey(
      const ValueKey('coachOpsCatalogImportFeedLocatorField'),
    );
    await tester.dragUntilVisible(
      field,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(field, findsOneWidget);

    await tester.enterText(field, '/srv/feeds/operator_b');
    await tester.pumpAndSettle();

    final saveButton = find.byKey(
      const ValueKey('coachOpsCatalogImportConfigSaveButton'),
    );
    expect(saveButton, findsOneWidget);
    tester.widget<OutlinedButton>(saveButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportConfigUpdateCalls, 1);
    expect(api.lastCatalogImportFeedLocator, '/srv/feeds/operator_b');
    expect(
      find.textContaining('Feed locator: /srv/feeds/operator_b'),
      findsOneWidget,
    );
    expect(find.text('Catalog import configuration saved.'), findsOneWidget);
  });

  testWidgets(
      'coach operator console guides operator-scoped import config without free locator field',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(
            ready: false,
            configured: false,
            feedLocator: null,
            detail:
                'Scoped source artifact required for this operator account.',
            configOrigin: 'operator_scope',
            sourceArtifactOverride: null,
            latestImportRunOverride: null,
          ),
          initialCatalogImportSources:
              const CoachOperatorCatalogImportSourcesResponse(
            generatedAtIso: '2026-04-15T10:07:10Z',
            sources: <CoachOperatorCatalogImportSourceOption>[],
          ),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    expect(
      find.text(
        'No in-scope sources are available yet. Upload a GTFS archive for this operator to continue.',
      ),
      findsOneWidget,
    );
    await _dragUntilTextVisible(
      tester,
      'Select an in-scope GTFS source or upload a new archive for this operator before running a manual import.',
    );
    expect(
      find.text(
        'Select an in-scope GTFS source or upload a new archive for this operator before running a manual import.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('coachOpsCatalogImportFeedLocatorField')),
      findsNothing,
    );

    final saveButton = find.byKey(
      const ValueKey('coachOpsCatalogImportConfigSaveButton'),
    );
    await _dragUntilFinderVisible(tester, saveButton);
    expect(find.text('Activate selected source'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(saveButton).onPressed, isNull);
    expect(
      find.byKey(
        const ValueKey('coachOpsCatalogImportConfigSaveDisabledHint'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Select an in-scope GTFS source or upload a GTFS ZIP for this operator to activate this configuration.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console activates selected operator-scoped source',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(
            ready: false,
            configured: false,
            feedLocator: null,
            detail:
                'Scoped source artifact required for this operator account.',
            configOrigin: 'operator_scope',
            sourceArtifactOverride: null,
            latestImportRunOverride: null,
          ),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    expect(
      find.byKey(const ValueKey('coachOpsCatalogImportFeedLocatorField')),
      findsNothing,
    );

    final dropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportSourceDropdown'),
    );
    await _dragUntilFinderVisible(tester, dropdown);
    tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged!.call(
          '/srv/feeds/operator_env_default',
        );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Selected locator: /srv/feeds/operator_env_default',
      ),
      findsOneWidget,
    );

    final saveButton = find.byKey(
      const ValueKey('coachOpsCatalogImportConfigSaveButton'),
    );
    expect(find.text('Activate selected source'), findsOneWidget);
    tester.widget<OutlinedButton>(saveButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportConfigUpdateCalls, 1);
    expect(api.lastCatalogImportFeedLocator, '/srv/feeds/operator_env_default');
    expect(find.text('Catalog import configuration saved.'), findsOneWidget);
  });

  testWidgets(
      'coach operator console maps scoped config conflicts to actionable snackbar text',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..catalogImportConfigUpdateError = const CoachApiException(
        'coach catalog feed locator requires scoped source artifact for restricted operator account',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(
            ready: false,
            configured: false,
            feedLocator: null,
            detail:
                'Scoped source artifact required for this operator account.',
            configOrigin: 'operator_scope',
            sourceArtifactOverride: null,
            latestImportRunOverride: null,
          ),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    final dropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportSourceDropdown'),
    );
    await _dragUntilFinderVisible(tester, dropdown);
    tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged!.call(
          '/srv/feeds/operator_env_default',
        );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(
      const ValueKey('coachOpsCatalogImportConfigSaveButton'),
    );
    tester.widget<OutlinedButton>(saveButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportConfigUpdateCalls, 1);
    expect(
      find.text(
        'Select an in-scope GTFS source or upload a GTFS ZIP for this operator.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console selects available catalog import source into draft',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    final dropdown = find.byKey(
      const ValueKey('coachOpsCatalogImportSourceDropdown'),
    );
    await tester.dragUntilVisible(
      dropdown,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(dropdown, findsOneWidget);

    tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged!.call(
          '/srv/feeds/operator_env_default',
        );
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey('coachOpsCatalogImportFeedLocatorField'),
    );
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      '/srv/feeds/operator_env_default',
    );
    expect(find.textContaining('Selected source: Environment default'),
        findsOneWidget);
  });

  testWidgets(
      'coach operator console renders and loads older catalog source artifacts',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogSourceArtifacts:
              api.catalogSourceArtifactsSnapshot(limit: 2),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog source artifacts');
    expect(find.text('Catalog source artifacts'), findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      find.text('operator_a_feed.zip'),
    );
    expect(find.text('operator_a_feed.zip'), findsOneWidget);
    expect(find.textContaining('operator_a_feed_v0.zip'), findsNothing);

    final loadOlderButton = find.byKey(
      const ValueKey('coachOpsCatalogSourceArtifactsLoadOlderButton'),
    );
    await tester.dragUntilVisible(
      loadOlderButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(loadOlderButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      api.lastCatalogSourceArtifactCursor,
      '2026-04-14T08:00:00Z|catalogsourceartifact_demo_previous',
    );
    await _dragUntilFinderVisible(
      tester,
      find.text('operator_a_feed_v0.zip'),
    );
    expect(find.text('operator_a_feed_v0.zip'), findsOneWidget);
  });

  testWidgets(
      'coach operator console shows read-only catalog source artifact guidance for support users',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['support_l1'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogSourceArtifacts:
              api.catalogSourceArtifactsSnapshot(limit: 2),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog source artifacts');
    final readOnlyHint = find.byKey(
      const ValueKey(
        'coachOpsCatalogSourceArtifactReadOnlyHint_catalogsourceartifact_demo_current',
      ),
    );
    await _dragUntilFinderVisible(tester, readOnlyHint);
    expect(readOnlyHint, findsOneWidget);
    expect(
      find.text(
        'This account is read-only for catalog imports. Open details or ask a catalog operator to run the import from this artifact.',
      ),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogSourceArtifactRunImport_catalogsourceartifact_demo_current',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'coach operator console triggers import from selected source artifact',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogSourceArtifacts:
              api.catalogSourceArtifactsSnapshot(limit: 2),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog source artifacts');
    final runButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogSourceArtifactRunImport_catalogsourceartifact_demo_current',
      ),
    );
    await tester.dragUntilVisible(
      runButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(runButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunTriggerCalls, 1);
    expect(
      api.lastTriggeredCatalogImportSourceArtifactId,
      'catalogsourceartifact_demo_current',
    );
    expect(find.text('Catalog import completed for operator_a_feed.zip.'),
        findsOneWidget);
    await _dragUntilFinderVisible(
      tester,
      find.textContaining('catalogimportrun_demo_manual_1'),
    );
    expect(
      find.textContaining('catalogimportrun_demo_manual_1'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets(
      'coach operator console maps scoped trigger conflicts to actionable snackbar text',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..catalogImportRunTriggerError = const CoachApiException(
        'coach catalog import trigger requires scoped source artifact for restricted operator account',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    final triggerButton = find.byKey(
      const ValueKey('coachOpsCatalogImportTriggerButton'),
    );
    await _dragUntilFinderVisible(tester, triggerButton);
    tester.widget<OutlinedButton>(triggerButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportRunTriggerCalls, 1);
    expect(
      find.text(
        'Select an in-scope GTFS source or upload a GTFS ZIP for this operator.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console uploads GTFS ZIP source', (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          pickCatalogImportFileOverride: () async =>
              CoachPickedCatalogImportFile(
            fileName: 'operator_b_feed.zip',
            bytes: Uint8List.fromList(const <int>[1, 2, 3, 4, 5]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    final selectButton = find.byKey(
      const ValueKey('coachOpsCatalogImportFileSelectButton'),
    );
    await tester.dragUntilVisible(
      selectButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(selectButton, findsOneWidget);

    tester.widget<OutlinedButton>(selectButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected archive: operator_b_feed.zip'),
        findsOneWidget);

    final uploadButton = find.byKey(
      const ValueKey('coachOpsCatalogImportFileUploadButton'),
    );
    expect(uploadButton, findsOneWidget);
    tester.widget<OutlinedButton>(uploadButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportSourceUploadCalls, 1);
    expect(api.lastUploadedCatalogImportFileName, 'operator_b_feed.zip');
    expect(api.lastUploadedCatalogImportFileBytesLength, 5);
    expect(api.operatorCatalogImportSourcesCalls, greaterThanOrEqualTo(1));
    expect(
      find.textContaining(
        'Feed locator: /tmp/shamell_coach_gtfs_uploads/operator_b_feed_uploaded',
      ),
      findsOneWidget,
    );
    expect(
        find.textContaining('Artifact: operator_b_feed.zip'), findsOneWidget);
    expect(find.text('GTFS archive uploaded and activated.'), findsOneWidget);
    expect(find.textContaining('Selected archive:'), findsNothing);
  });

  testWidgets(
      'coach operator console shows inline upload guidance before GTFS ZIP is selected',
      (tester) async {
    final api = _FakeCoachOperatorApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    expect(
      find.byKey(const ValueKey('coachOpsCatalogImportUploadDisabledHint')),
      findsOneWidget,
    );
    expect(
      find.text('Select a GTFS ZIP to enable upload.'),
      findsOneWidget,
    );
    final uploadButton = find.byKey(
      const ValueKey('coachOpsCatalogImportFileUploadButton'),
    );
    await _dragUntilFinderVisible(tester, uploadButton);
    expect(tester.widget<OutlinedButton>(uploadButton).onPressed, isNull);
  });

  testWidgets(
      'coach operator console maps scoped upload conflicts to actionable snackbar text',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..catalogImportSourceUploadError = const CoachApiException(
        'coach catalog source artifact exceeds operator privileges',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          pickCatalogImportFileOverride: () async =>
              CoachPickedCatalogImportFile(
            fileName: 'operator_b_feed.zip',
            bytes: Uint8List.fromList(const <int>[1, 2, 3, 4, 5]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Catalog import configuration');
    final selectButton = find.byKey(
      const ValueKey('coachOpsCatalogImportFileSelectButton'),
    );
    await _dragUntilFinderVisible(tester, selectButton);
    tester.widget<OutlinedButton>(selectButton).onPressed!.call();
    await tester.pumpAndSettle();

    final uploadButton = find.byKey(
      const ValueKey('coachOpsCatalogImportFileUploadButton'),
    );
    tester.widget<OutlinedButton>(uploadButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.catalogImportSourceUploadCalls, 1);
    expect(
      find.text(
        'This GTFS ZIP is outside the allowed operator scope. Upload a GTFS ZIP for this operator or select an in-scope source.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console renders payout import history',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportEvents.add(
      const CoachOperatorPayoutImport(
        importId: 'payoutimport_demo_executed',
        importBatchId: 'payoutbatch_demo_1',
        payoutRunId: 'payoutrun_demo_express',
        importSource: 'bank_report',
        externalStatus: 'executed',
        paymentReference: 'bank_import_payoutrun_demo_express',
        externalReference: 'bank_file_2026w15',
        importedAtIso: '2026-04-14T10:06:00Z',
        importedByAccountId: 'acct_finance_demo',
        previousRunStatus: 'queued',
        appliedRunStatus: 'paid',
        note: 'executed import applied from coach ops console',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview confirmations');
    expect(find.text('Preview confirmations'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Payout imports');
    expect(find.text('Payout imports'), findsWidgets);
    await _dragUntilTextVisible(tester, 'Preview history');
    expect(find.text('Preview history'), findsOneWidget);
    expect(find.text('This account is not allowed to manage coach requests.'),
        findsNothing);
  });

  testWidgets('coach operator console loads older payout import pages',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportEvents.addAll(
      List<CoachOperatorPayoutImport>.generate(9, (index) {
        final page = index + 1;
        final day = (16 - page).toString().padLeft(2, '0');
        return CoachOperatorPayoutImport(
          importId: 'payoutimport_demo_page_$page',
          importBatchId: 'payoutbatch_demo_page_$page',
          payoutRunId: 'payoutrun_demo_page_$page',
          importSource: 'bank_report',
          externalStatus: page == 2 ? 'failed' : 'executed',
          paymentReference:
              page == 2 ? null : 'bank_import_payoutrun_demo_page_$page',
          externalReference: 'bank_file_2026w$page',
          importedAtIso: '2026-04-${day}T10:08:00Z',
          importedByAccountId: 'acct_finance_demo',
          previousRunStatus: 'queued',
          appliedRunStatus: page == 2 ? 'failed' : 'paid',
          note: 'page $page import',
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout imports');
    expect(find.textContaining('payoutimport_demo_page_9'), findsNothing);

    final loadOlderButton = find.byKey(
      const ValueKey('coachOpsPayoutImportsLoadOlderButton'),
    );
    final listView = find.byType(ListView).first;
    for (var attempt = 0; attempt < 20; attempt++) {
      if (loadOlderButton.evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(listView, const Offset(0, -320));
      await tester.pumpAndSettle();
    }
    expect(loadOlderButton, findsOneWidget);
    tester.widget<OutlinedButton>(loadOlderButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      api.lastPayoutImportCursor,
      '2026-04-08T10:08:00Z|payoutimport_demo_page_8',
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      if (find
          .textContaining('payoutimport_demo_page_9')
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.drag(listView, const Offset(0, -320));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('payoutimport_demo_page_9'), findsOneWidget);
  });

  test('coach operator console paginates payout run pages by cursor', () async {
    final api = _FakeCoachOperatorApi();
    api.payoutRunEvents.addAll(
      List<CoachOperatorPayoutRun>.generate(9, (index) {
        final page = index + 1;
        final day = (16 - page).toString().padLeft(2, '0');
        return CoachOperatorPayoutRun(
          payoutRunId: 'payoutrun_demo_page_$page',
          status: page == 2 ? 'paid' : 'queued',
          currency: 'SYP',
          statementIds: <String>['settlement_demo_page_$page'],
          operatorIds: <String>['op_demo_page_$page'],
          operatorNames: <String>['Demo Page $page'],
          statementCount: 1,
          grossMinorUnits: 5000 + page,
          reserveMinorUnits: 100,
          netPayableMinorUnits: 4900 + page,
          createdAtIso: '2026-04-${day}T10:08:00Z',
          paidAtIso: page == 2 ? '2026-04-${day}T12:08:00Z' : null,
          createdByAccountId: 'acct_finance_demo',
          paidByAccountId: page == 2 ? 'acct_finance_demo' : null,
          paymentReference: page == 2 ? 'bank_page_$page' : null,
          note: 'page $page payout run',
          availableExportFormats: const <String>['csv', 'datev_json'],
          exports: const <CoachOperatorPayoutExport>[],
        );
      }),
    );

    final firstPage = api.payoutRunsSnapshot(limit: 8);
    expect(firstPage.runs, hasLength(8));
    expect(
        firstPage.runs.any((run) => run.payoutRunId == 'payoutrun_demo_page_9'),
        isFalse);
    expect(firstPage.nextCursor, '2026-04-08T10:08:00Z|payoutrun_demo_page_8');

    final secondPage = await api.operatorPayoutRuns(
      limit: 8,
      cursor: firstPage.nextCursor,
    );

    expect(
      api.lastPayoutRunCursor,
      '2026-04-08T10:08:00Z|payoutrun_demo_page_8',
    );
    expect(secondPage.runs, hasLength(1));
    expect(secondPage.runs.single.payoutRunId, 'payoutrun_demo_page_9');
    expect(secondPage.nextCursor, isNull);
  });

  testWidgets('coach operator console loads older payout reconciliation pages',
      (tester) async {
    final api = _FakeCoachOperatorApi();
    api.payoutRunEvents.addAll(
      List<CoachOperatorPayoutRun>.generate(9, (index) {
        final page = index + 1;
        final day = (16 - page).toString().padLeft(2, '0');
        return CoachOperatorPayoutRun(
          payoutRunId: 'payoutrun_demo_page_$page',
          status: page == 2 ? 'paid' : 'queued',
          currency: 'SYP',
          statementIds: <String>['settlement_demo_page_$page'],
          operatorIds: <String>['op_demo_page_$page'],
          operatorNames: <String>['Demo Page $page'],
          statementCount: 1,
          grossMinorUnits: 5000 + page,
          reserveMinorUnits: 100,
          netPayableMinorUnits: 4900 + page,
          createdAtIso: '2026-04-${day}T10:08:00Z',
          paidAtIso: page == 2 ? '2026-04-${day}T12:08:00Z' : null,
          createdByAccountId: 'acct_finance_demo',
          paidByAccountId: page == 2 ? 'acct_finance_demo' : null,
          paymentReference: page == 2 ? 'bank_page_$page' : null,
          note: 'page $page payout run',
          availableExportFormats: const <String>['csv', 'datev_json'],
          exports: const <CoachOperatorPayoutExport>[],
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 8),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout reconciliation');
    expect(find.textContaining('payoutrun_demo_page_9'), findsNothing);

    final loadOlderButton = find.byKey(
      const ValueKey('coachOpsPayoutReconciliationLoadOlderButton'),
      skipOffstage: false,
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(loadOlderButton, 320,
        scrollable: scrollable);
    expect(loadOlderButton, findsOneWidget);
    tester.widget<OutlinedButton>(loadOlderButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      api.lastPayoutReconciliationCursor,
      '2026-04-08T10:08:00Z|payoutrun_demo_page_8',
    );
    final listView = find.byType(ListView).first;
    for (var attempt = 0; attempt < 8; attempt++) {
      if (find.textContaining('payoutrun_demo_page_9').evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(listView, const Offset(0, -320));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('payoutrun_demo_page_9'), findsOneWidget);
  });

  testWidgets('coach operator console loads older settlement statement pages',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachOperatorApi();
    api.settlementStatementEvents.addAll(
      List<CoachOperatorSettlementStatement>.generate(7, (index) {
        final page = index + 1;
        final day = (14 - page).toString().padLeft(2, '0');
        return CoachOperatorSettlementStatement(
          statementId: 'settlement_demo_page_$page',
          operatorId: 'op_demo_page_$page',
          operatorName: 'Demo Page $page',
          currency: 'SYP',
          periodStartIso: '2026-04-0${page}T00:00:00Z',
          periodEndIso: '2026-04-${day}T23:59:59Z',
          nextPayoutAtIso: '2026-04-15T10:00:00Z',
          status: page == 2 ? 'paid_out' : 'ready_for_payout',
          downloadFormats: const <String>['csv', 'datev_json'],
          totals: CoachOperatorSettlementStatementTotals(
            lineCount: 1,
            grossMinorUnits: 4000 + page,
            commissionMinorUnits: 500,
            refundMinorUnits: 0,
            chargebackReserveMinorUnits: 100,
            manualAdjustmentMinorUnits: 0,
            netPayableMinorUnits: 3400 + page,
          ),
          lines: <CoachSettlementLine>[
            CoachSettlementLine(
              settlementId: 'settlement_demo_page_$page',
              operatorId: 'op_demo_page_$page',
              bookingId: 'booking_demo_page_$page',
              basis: CoachSettlementBasis.ticketed,
              currency: 'SYP',
              grossMinorUnits: 4000 + page,
              commissionMinorUnits: 500,
              refundMinorUnits: 0,
              chargebackReserveMinorUnits: 100,
              manualAdjustmentMinorUnits: 0,
              netPayableMinorUnits: 3400 + page,
            ),
          ],
        );
      }),
    );
    final initialSettlementStatements =
        api.settlementStatementsSnapshot(limit: 6);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements:
              CoachOperatorSettlementStatementsResponse(
            generatedAtIso: initialSettlementStatements.generatedAtIso,
            statements: initialSettlementStatements.statements,
            nextCursor: '2026-04-08T23:59:59Z|settlement_demo_page_6',
          ),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialOperatorFeedHealth: api.operatorFeedHealthSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportSources: api.catalogImportSourcesSnapshot(),
          initialCatalogSourceArtifacts: api.catalogSourceArtifactsSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Settlement statements');
    expect(find.textContaining('Demo Page 7'), findsNothing);
    final demoPageSixFinder = find.textContaining(
      'Demo Page 6',
      skipOffstage: false,
    );
    final loadOlderButtonOffstageFinder = find.byKey(
      const ValueKey('coachOpsSettlementStatementsLoadOlderButton'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      demoPageSixFinder,
      maxAttempts: 40,
    );
    expect(demoPageSixFinder, findsOneWidget);

    await _dragUntilFinderVisible(
      tester,
      loadOlderButtonOffstageFinder,
      maxAttempts: 40,
    );
    expect(loadOlderButtonOffstageFinder, findsOneWidget);
    tester
        .widget<OutlinedButton>(loadOlderButtonOffstageFinder)
        .onPressed!
        .call();
    await tester.pumpAndSettle();

    expect(
      api.lastSettlementStatementCursor,
      '2026-04-08T23:59:59Z|settlement_demo_page_6',
    );
    await _dragUntilFinderVisible(
      tester,
      find.textContaining('Demo Page 7'),
      maxAttempts: 20,
    );
    expect(find.textContaining('Demo Page 7'), findsOneWidget);
  });

  testWidgets('coach operator console loads older preview history pages',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportPreviewEvents
        .addAll(const <CoachOperatorPayoutImportPreview>[
      CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_demo_page_1',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_page_1.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_demo_express'],
        reportChecksumSha256: 'sha256_demo_page_1',
        requestFingerprint: 'fp_preview_page_1_demo',
        previewStatus: 'active',
        createdAtIso: '2026-04-15T10:08:00Z',
        expiresAtIso: '2026-04-15T10:18:00Z',
        usableNow: true,
        reworkOfBatchId: null,
        consumedAtIso: null,
        invalidatedAtIso: null,
      ),
      CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_demo_page_2',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_page_2.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_demo_express'],
        reportChecksumSha256: 'sha256_demo_page_2',
        requestFingerprint: 'fp_preview_page_2_demo',
        previewStatus: 'consumed',
        createdAtIso: '2026-04-14T11:08:00Z',
        expiresAtIso: '2026-04-14T11:18:00Z',
        usableNow: false,
        reworkOfBatchId: null,
        consumedAtIso: '2026-04-14T11:09:00Z',
        invalidatedAtIso: null,
      ),
      CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_demo_page_3',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_page_3.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_border_runner'],
        reportChecksumSha256: 'sha256_demo_page_3',
        requestFingerprint: 'fp_preview_page_3_demo',
        previewStatus: 'invalidated',
        createdAtIso: '2026-04-13T11:08:00Z',
        expiresAtIso: '2026-04-13T11:18:00Z',
        usableNow: false,
        reworkOfBatchId: null,
        consumedAtIso: null,
        invalidatedAtIso: '2026-04-13T11:09:00Z',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews:
              api.payoutImportPreviewsSnapshot(limit: 2),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(
      tester,
      'previewtoken_demo_page_1 • bank_report_page_1.csv',
    );
    expect(find.textContaining('previewtoken_demo_page_1'), findsOneWidget);
    await _dragUntilTextVisible(
      tester,
      'previewtoken_demo_page_2 • bank_report_page_2.csv',
    );
    expect(find.textContaining('previewtoken_demo_page_2'), findsOneWidget);
    expect(find.text('Operator scope: op_demo_express'), findsWidgets);
    expect(find.textContaining('previewtoken_demo_page_3'), findsNothing);

    final loadOlderButton = find.byKey(
      const ValueKey('coachOpsPreviewHistoryLoadOlderButton'),
    );
    await tester.dragUntilVisible(
      loadOlderButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(loadOlderButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      api.lastPayoutImportPreviewCursor,
      '2026-04-14T11:08:00Z|previewtoken_demo_page_2',
    );
    await _dragUntilTextVisible(
      tester,
      'previewtoken_demo_page_3 • bank_report_page_3.csv',
    );
    expect(find.textContaining('previewtoken_demo_page_3'), findsOneWidget);
  });

  test('coach operator console loads older payout import batch pages',
      () async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportBatchEvents.addAll(
      List<CoachOperatorPayoutImportBatch>.generate(9, (index) {
        final page = index + 1;
        final day = (16 - page).toString().padLeft(2, '0');
        return CoachOperatorPayoutImportBatch(
          batchId: 'payoutbatch_demo_page_$page',
          dryRun: false,
          importSource: 'bank_report',
          reportName: 'bank_report_page_$page.csv',
          reportFormat: 'csv',
          reworkOfBatchId: null,
          reworkOriginBatchId: null,
          followUpBatchIds: const <String>[],
          reportChecksumSha256: 'sha256_demo_page_$page',
          totalRows: 2,
          appliedRows: 2,
          failedRows: 0,
          payoutRunIds: <String>['payoutrun_demo_page_$page'],
          failureMessages: const <String>[],
          createdAtIso: '2026-04-${day}T10:08:00Z',
          createdByAccountId: 'acct_finance_demo',
          reportArtifact: null,
          reworkArtifact: null,
          note: 'page $page batch',
        );
      }),
    );

    final firstPage = api.payoutImportBatchesSnapshot(limit: 8);

    expect(firstPage.batches, hasLength(8));
    expect(
        firstPage.nextCursor, '2026-04-08T10:08:00Z|payoutbatch_demo_page_8');
    expect(
      firstPage.batches
          .any((entry) => entry.reportName == 'bank_report_page_9.csv'),
      isFalse,
    );

    final secondPage = await api.operatorPayoutImportBatches(
      limit: 8,
      cursor: firstPage.nextCursor,
    );

    expect(api.lastPayoutImportBatchCursor, firstPage.nextCursor);
    expect(secondPage.batches, hasLength(1));
    expect(secondPage.batches.single.reportName, 'bank_report_page_9.csv');
    expect(secondPage.nextCursor, isNull);
  });

  testWidgets('coach operator console renders payout import rework follow-ups',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportBatchEvents.addAll(const <CoachOperatorPayoutImportBatch>[
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_demo_1',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_2026w15.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_demo_express'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_demo_report',
        totalRows: 2,
        appliedRows: 1,
        failedRows: 1,
        payoutRunIds: <String>['payoutrun_demo_express'],
        failureMessages: <String>['line 3 (payoutrun_demo_failed): not found'],
        createdAtIso: '2026-04-14T10:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: CoachOperatorPayoutImportReportArtifact(
          artifactId: 'payoutreport_demo_1',
          batchId: 'payoutbatch_demo_1',
          artifactKind: 'source_report',
          importSource: 'bank_report',
          reportName: 'bank_report_2026w15.csv',
          reportFormat: 'csv',
          operatorIds: <String>['op_demo_express'],
          fileName: 'coach-payout-import-payoutbatch_demo_1.csv',
          mimeType: 'text/csv; charset=utf-8',
          downloadPath:
              '/downloads/coach/payout_import_reports/payoutreport_demo_1.csv',
          checksumSha256: 'sha256_demo_report',
          contentLengthBytes: 182,
          createdAtIso: '2026-04-14T10:08:00Z',
          createdByAccountId: 'acct_finance_demo',
          note: 'uploaded from coach ops console',
        ),
        reworkArtifact: CoachOperatorPayoutImportReportArtifact(
          artifactId: 'payoutrework_demo_1',
          batchId: 'payoutbatch_demo_1',
          artifactKind: 'failed_row_rework',
          importSource: 'bank_report',
          reportName: 'bank_report_2026w15.csv (failed row rework)',
          reportFormat: 'csv',
          operatorIds: <String>['op_demo_express'],
          fileName: 'coach-payout-import-rework-payoutbatch_demo_1.csv',
          mimeType: 'text/csv; charset=utf-8',
          downloadPath:
              '/downloads/coach/payout_import_reports/payoutrework_demo_1.csv',
          checksumSha256: 'sha256_demo_rework',
          contentLengthBytes: 224,
          createdAtIso: '2026-04-14T10:08:00Z',
          createdByAccountId: 'acct_finance_demo',
          note: 'failed row rework export',
        ),
        note: 'uploaded from coach ops console',
      ),
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_demo_2',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'coach-payout-import-rework-payoutbatch_demo_1.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_demo_express'],
        reworkOfBatchId: 'payoutbatch_demo_1',
        reworkOriginBatchId: 'payoutbatch_demo_1',
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_demo_rework',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_demo_failed'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T11:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: CoachOperatorPayoutImportReportArtifact(
          artifactId: 'payoutreport_demo_2',
          batchId: 'payoutbatch_demo_2',
          artifactKind: 'source_report',
          importSource: 'bank_report',
          reportName: 'coach-payout-import-rework-payoutbatch_demo_1.csv',
          reportFormat: 'csv',
          operatorIds: <String>['op_demo_express'],
          fileName: 'coach-payout-import-payoutbatch_demo_2.csv',
          mimeType: 'text/csv; charset=utf-8',
          downloadPath:
              '/downloads/coach/payout_import_reports/payoutreport_demo_2.csv',
          checksumSha256: 'sha256_demo_rework',
          contentLengthBytes: 144,
          createdAtIso: '2026-04-14T11:08:00Z',
          createdByAccountId: 'acct_finance_demo',
          note: 'rework upload',
        ),
        reworkArtifact: null,
        note: 'rework upload',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      api
          .payoutImportBatchesSnapshot()
          .batches
          .singleWhere((batch) => batch.batchId == 'payoutbatch_demo_1')
          .followUpBatchIds,
      <String>['payoutbatch_demo_2'],
    );
    await _dragUntilTextVisible(tester, 'Payout import batches');
    expect(find.text('Payout import batches'), findsOneWidget);
  });

  testWidgets(
      'coach operator console filters payout import batches by operator scope locally',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportBatchEvents.addAll(const <CoachOperatorPayoutImportBatch>[
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_scope_demo_a',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_scope_a.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_a'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_scope_batch_a',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_scope_demo_a'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T12:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'scope demo a',
      ),
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_scope_demo_b',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_scope_b.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_b'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_scope_batch_b',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_scope_demo_b'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T11:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'scope demo b',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    final operatorFilter = find.byKey(
      const ValueKey('coachOpsPayoutImportBatchesOperatorFilterField'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      operatorFilter,
      maxAttempts: 40,
      dragDy: -220,
    );
    tester
        .widget<DropdownButtonFormField<String>>(operatorFilter)
        .onChanged!('op_scope_b');
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('coachOpsPayoutImportBatchesOperatorFilterChip'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsPayoutImportBatchesFilteredCountChip'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Shown: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console restores and persists payout import batch operator filter',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportBatchEvents.addAll(const <CoachOperatorPayoutImportBatch>[
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_scope_restore_a',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_scope_restore_a.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_a'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_scope_restore_a',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_scope_restore_a'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T13:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'scope restore a',
      ),
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_scope_restore_b',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_scope_restore_b.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_b'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_scope_restore_b',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_scope_restore_b'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T12:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'scope restore b',
      ),
    ]);
    CoachPayoutImportBatchFilterPreferences? savedPreferences;
    var clearCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          loadPayoutImportBatchFilterPreferencesOverride: () async =>
              const CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_scope_b',
          ),
          savePayoutImportBatchFilterPreferencesOverride: (preferences) async {
            savedPreferences = preferences;
          },
          clearPayoutImportBatchFilterPreferencesOverride: () async {
            clearCalls += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    final operatorFilter = find.byKey(
      const ValueKey('coachOpsPayoutImportBatchesOperatorFilterField'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      operatorFilter,
      maxAttempts: 40,
      dragDy: -220,
    );
    final operatorDropdown =
        tester.widget<DropdownButtonFormField<String>>(operatorFilter);
    expect(operatorDropdown.initialValue, 'op_scope_b');
    expect(
      find.textContaining('Shown: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );

    operatorDropdown.onChanged!('op_scope_a');
    await tester.pumpAndSettle();
    expect(savedPreferences?.operatorId, 'op_scope_a');
    expect(
      find.text('Operator: op_scope_a', skipOffstage: false),
      findsOneWidget,
    );

    final filterChip = find.byKey(
      const ValueKey('coachOpsPayoutImportBatchesOperatorFilterChip'),
      skipOffstage: false,
    );
    tester.widget<InputChip>(filterChip).onDeleted!.call();
    await tester.pumpAndSettle();
    expect(clearCalls, 1);
  });

  testWidgets(
      'coach operator console loads payout import batch saved views from API when available',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
      CoachPayoutImportBatchSavedView(
        viewId: 'payoutimportbatchview_demo_express',
        name: 'Demo Express batches',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_demo_express',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T09:55:00Z',
        updatedAtIso: '2026-04-15T10:01:00Z',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.payoutImportBatchSavedViewsCalls, 1);
    await _dragUntilFinderVisible(
      tester,
      find.text('Demo Express batches', skipOffstage: false),
      maxAttempts: 40,
      dragDy: -220,
    );
    expect(
      find.text('Demo Express batches', skipOffstage: false),
      findsWidgets,
    );
    expect(find.text('Default view', skipOffstage: false), findsWidgets);
  });

  testWidgets(
      'coach operator console filters payout import batch saved views by scope',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_personal',
          name: 'Personal batches',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T10:01:00Z',
        ),
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared',
          accountId: 'acct_finance_shared',
          name: 'Shared batches',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Personal batches');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesSavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    expect(find.text('Shared batches', skipOffstage: false), findsOneWidget);
    expect(find.text('Personal batches', skipOffstage: false), findsNothing);
    expect(
      find.byKey(
        const ValueKey(
            'coachOpsPayoutImportBatchesSavedViewsFilteredCountChip'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Shown: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console renders non-owned shared payout import batch saved views as read only',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_read_only',
          accountId: 'acct_finance_other',
          name: 'Shared express batches',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          canManage: false,
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T10:01:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Shared express batches');
    expect(find.text('Shared with ops', skipOffstage: false), findsWidgets);
    expect(
      find.text('Shared by acct_finance_other', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Read-only shared view', skipOffstage: false),
      findsOneWidget,
    );

    final setDefaultButton = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesToggleDefaultSavedView_payoutimportbatchview_shared_read_only',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, setDefaultButton);
    expect(
      tester.widget<OutlinedButton>(setDefaultButton).onPressed,
      isNull,
    );

    final deleteButton = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesDeleteSavedView_payoutimportbatchview_shared_read_only',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, deleteButton);
    expect(
      tester.widget<TextButton>(deleteButton).onPressed,
      isNull,
    );
  });

  testWidgets(
      'coach operator console filters payout import batch saved views by owner',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_personal',
          name: 'Personal batches',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T10:01:00Z',
        ),
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared batches A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared batches B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Personal batches');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesSavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    final ownerFilter = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesSavedViewsOwnerFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, ownerFilter, maxAttempts: 20);
    tester.widget<DropdownButtonFormField<String>>(ownerFilter).onChanged!.call(
          'acct_finance_other',
        );
    await tester.pumpAndSettle();

    expect(api.payoutImportBatchSavedViewOwnersCalls, 1);
    expect(find.text('Shared batches B', skipOffstage: false), findsOneWidget);
    expect(find.text('Shared batches A', skipOffstage: false), findsNothing);
    expect(
      find.text('acct_finance_other exposes 1 shared view.',
          skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console filters payout import batch saved views by operator',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_personal',
          name: 'Personal batches',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T10:01:00Z',
        ),
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared batches A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared batches B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Personal batches');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesSavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    final operatorFilter = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesSavedViewsOperatorFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, operatorFilter, maxAttempts: 20);
    tester
        .widget<DropdownButtonFormField<String>>(operatorFilter)
        .onChanged!
        .call('op_border_runner');
    await tester.pumpAndSettle();

    expect(api.payoutImportBatchSavedViewOperatorsCalls, 1);
    expect(find.text('Shared batches B', skipOffstage: false), findsOneWidget);
    expect(find.text('Shared batches A', skipOffstage: false), findsNothing);
    expect(
      find.textContaining('Border Runner', skipOffstage: false),
      findsWidgets,
    );
  });

  testWidgets(
      'coach operator console filters payout import batch saved views from card action by operator',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared batches A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared batches B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Shared batches B');
    final button = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesFilterByOperator_payoutimportbatchview_shared_b',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, button, maxAttempts: 20);
    tester.widget<OutlinedButton>(button).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      find.text('Shared batches B', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Shared batches A', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.textContaining('Shown: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console filters payout import batch saved views from card action by owner',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared batches A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared batches B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Shared batches B');
    final button = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesFilterByOwner_payoutimportbatchview_shared_b',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, button, maxAttempts: 20);
    tester.widget<OutlinedButton>(button).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      find.text('Shared batches B', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Shared batches A', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.textContaining('acct_finance_other exposes 1 shared view.',
          skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console shows payout import batch saved view triage chips',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_read_only',
          accountId: 'acct_finance_other',
          name: 'Shared batches B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_border_runner',
          ),
          canManage: false,
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Shared batches B');
    expect(find.text('Owner acct_finance_other', skipOffstage: false),
        findsOneWidget);
    expect(find.text('Operator Border Runner', skipOffstage: false),
        findsOneWidget);
    expect(find.text('Read-only', skipOffstage: false), findsOneWidget);
    expect(
        find.text('Filter Border Runner', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
      'coach operator console shows active filter chips on payout import batch saved view cards',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
        CoachPayoutImportBatchSavedView(
          viewId: 'payoutimportbatchview_shared_active',
          accountId: 'acct_finance_other',
          name: 'Shared batches active',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Shared batches active');

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesApplySavedView_payoutimportbatchview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, applyButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    final filterByOwnerButton = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesFilterByOwner_payoutimportbatchview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, filterByOwnerButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(filterByOwnerButton).onPressed!.call();
    await tester.pumpAndSettle();

    final filterByOperatorButton = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesFilterByOperator_payoutimportbatchview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      filterByOperatorButton,
      maxAttempts: 20,
    );
    tester.widget<OutlinedButton>(filterByOperatorButton).onPressed!.call();
    await tester.pumpAndSettle();

    final pinButton = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesTogglePinnedSavedView_payoutimportbatchview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, pinButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(pinButton).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Active scope', skipOffstage: false), findsOneWidget);
    expect(find.text('Active owner', skipOffstage: false), findsOneWidget);
    expect(find.text('Active operator', skipOffstage: false), findsOneWidget);
    expect(find.text('Using this view', skipOffstage: false), findsOneWidget);
    expect(find.text('Pinned', skipOffstage: false), findsOneWidget);
    expect(find.text('Unpin view', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('Last used ', skipOffstage: false),
      findsOneWidget,
    );
    await _dragUntilTextVisible(tester, 'Recent views');
    final recentChip = find.byKey(
      const ValueKey(
        'coachOpsPayoutImportBatchesRecentSavedView_payoutimportbatchview_shared_active',
      ),
      skipOffstage: false,
    );
    expect(recentChip, findsOneWidget);
    expect(tester.widget<ActionChip>(recentChip).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(applyButton).onPressed, isNull);
    expect(
      find.text('View already active', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console applies default payout import batch saved view on load',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportBatchEvents.addAll(const <CoachOperatorPayoutImportBatch>[
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_default_a',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_default_a.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_a'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_default_a',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_default_a'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T13:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'default a',
      ),
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_default_b',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_default_b.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_b'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_default_b',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_default_b'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T12:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'default b',
      ),
    ]);
    api.payoutImportBatchSavedViews = const <CoachPayoutImportBatchSavedView>[
      CoachPayoutImportBatchSavedView(
        viewId: 'payoutimportbatchview_scope_b',
        name: 'Scope B batches',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_scope_b',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T09:55:00Z',
        updatedAtIso: '2026-04-15T10:01:00Z',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    final operatorFilter = find.byKey(
      const ValueKey('coachOpsPayoutImportBatchesOperatorFilterField'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      operatorFilter,
      maxAttempts: 40,
      dragDy: -220,
    );
    final operatorDropdown =
        tester.widget<DropdownButtonFormField<String>>(operatorFilter);
    expect(operatorDropdown.initialValue, 'op_scope_b');
    expect(
      find.textContaining('Shown: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Operator: op_scope_b', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console saves applies and deletes payout import batch saved views',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    api.payoutImportBatchEvents.addAll(const <CoachOperatorPayoutImportBatch>[
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_saved_view_a',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_saved_view_a.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_a'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_saved_view_a',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_saved_view_a'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T13:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'saved view a',
      ),
      CoachOperatorPayoutImportBatch(
        batchId: 'payoutbatch_saved_view_b',
        dryRun: false,
        importSource: 'bank_report',
        reportName: 'bank_report_saved_view_b.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_b'],
        reworkOfBatchId: null,
        reworkOriginBatchId: null,
        followUpBatchIds: <String>[],
        reportChecksumSha256: 'sha256_saved_view_b',
        totalRows: 1,
        appliedRows: 1,
        failedRows: 0,
        payoutRunIds: <String>['payoutrun_saved_view_b'],
        failureMessages: <String>[],
        createdAtIso: '2026-04-14T12:08:00Z',
        createdByAccountId: 'acct_finance_demo',
        reportArtifact: null,
        reworkArtifact: null,
        note: 'saved view b',
      ),
    ]);
    var savedViews = <CoachPayoutImportBatchSavedView>[];

    Future<List<CoachPayoutImportBatchSavedView>> saveView(
      CoachPayoutImportBatchSavedView view,
    ) async {
      savedViews = <CoachPayoutImportBatchSavedView>[
        view,
        ...savedViews.where((entry) => entry.viewId != view.viewId),
      ];
      return savedViews;
    }

    Future<List<CoachPayoutImportBatchSavedView>> deleteView(
      String viewId,
    ) async {
      savedViews = savedViews
          .where((entry) => entry.viewId != viewId)
          .toList(growable: false);
      return savedViews;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          loadPayoutImportBatchSavedViewsOverride: () async => savedViews,
          savePayoutImportBatchSavedViewOverride: saveView,
          deletePayoutImportBatchSavedViewOverride: deleteView,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    final operatorFilter = find.byKey(
      const ValueKey('coachOpsPayoutImportBatchesOperatorFilterField'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      operatorFilter,
      maxAttempts: 40,
      dragDy: -220,
    );
    tester
        .widget<DropdownButtonFormField<String>>(operatorFilter)
        .onChanged!('op_scope_b');
    await tester.pumpAndSettle();

    final nameField = find.byKey(
      const ValueKey('coachOpsPayoutImportBatchesSavedViewNameField'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      nameField,
      maxAttempts: 40,
      dragDy: -220,
    );
    await tester.enterText(nameField, 'Scope B batches');
    await tester.pumpAndSettle();

    final saveButton = find.byKey(
      const ValueKey('coachOpsPayoutImportBatchesSaveViewButton'),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      saveButton,
      maxAttempts: 40,
      dragDy: -220,
    );
    tester.widget<OutlinedButton>(saveButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(savedViews, hasLength(1));
    expect(savedViews.first.preferences.operatorId, 'op_scope_b');
    expect(find.text('Scope B batches'), findsWidgets);

    tester
        .widget<DropdownButtonFormField<String>>(operatorFilter)
        .onChanged!('op_scope_a');
    await tester.pumpAndSettle();
    expect(
      find.text('Operator: op_scope_a', skipOffstage: false),
      findsOneWidget,
    );

    final applySavedViewButton = find.byKey(
      ValueKey(
        'coachOpsPayoutImportBatchesApplySavedView_${savedViews.first.viewId}',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      applySavedViewButton,
      maxAttempts: 40,
      dragDy: -220,
    );
    tester.widget<OutlinedButton>(applySavedViewButton).onPressed!.call();
    await tester.pumpAndSettle();
    expect(
      find.text('Operator: op_scope_b', skipOffstage: false),
      findsOneWidget,
    );

    final deleteSavedViewButton = find.byKey(
      ValueKey(
        'coachOpsPayoutImportBatchesDeleteSavedView_${savedViews.first.viewId}',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      deleteSavedViewButton,
      maxAttempts: 40,
      dragDy: -220,
    );
    tester.widget<TextButton>(deleteSavedViewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(savedViews, isEmpty);
    expect(
      find.text('No saved views yet.', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console applies payout import batch',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final reportBody =
        'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
        'payoutrun_demo_express,executed,bank_import_payoutrun_demo_express,bank_file_2026w15,2026-04-14T10:06:00Z,executed import applied from coach ops console\n'
        'payoutrun_demo_failed,failed,,bank_file_2026w15,2026-04-14T10:07:00Z,failed import applied from coach ops console';
    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Report name');
    await tester.enterText(
      find.widgetWithText(TextField, 'Report name'),
      'bank_report_2026w15.csv',
    );
    await _dragUntilTextVisible(tester, 'CSV report body');
    await tester.enterText(
      find.widgetWithText(TextField, 'CSV report body'),
      reportBody,
    );
    final applyButton =
        find.widgetWithText(OutlinedButton, 'Apply payout report');
    final previewButton = find.widgetWithText(OutlinedButton, 'Preview report');
    await tester.dragUntilVisible(
      applyButton,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    expect(
      tester.widget<OutlinedButton>(applyButton).onPressed,
      isNull,
    );
    tester.widget<OutlinedButton>(previewButton).onPressed!.call();
    await tester.pumpAndSettle();
    expect(
      tester.widget<OutlinedButton>(applyButton).onPressed,
      isNotNull,
    );
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.payoutImportBatchCreateCalls, 2);
    expect(api.payoutImportBatchPreviewCalls, 1);
    expect(
      api.lastExpectedPreviewToken,
      'previewtoken_ops_payout_import_batch_preview_1',
    );
    await tester.dragUntilVisible(
      find.textContaining('Last applied batch'),
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    expect(find.textContaining('Last applied batch'), findsOneWidget);
    expect(find.textContaining('Rework download:'), findsWidgets);
  });

  testWidgets('coach operator console previews payout import batch',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Report name');
    await tester.enterText(
      find.widgetWithText(TextField, 'Report name'),
      'bank_report_2026w15.csv',
    );
    await _dragUntilTextVisible(tester, 'CSV report body');
    await tester.enterText(
      find.widgetWithText(TextField, 'CSV report body'),
      'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
      'payoutrun_demo_express,executed,bank_import_payoutrun_demo_express,bank_file_2026w15,2026-04-14T10:06:00Z,executed import applied from coach ops console\n'
      'payoutrun_demo_failed,failed,,bank_file_2026w15,2026-04-14T10:07:00Z,failed import applied from coach ops console',
    );
    final previewButton = find.widgetWithText(OutlinedButton, 'Preview report');
    await tester.dragUntilVisible(
      previewButton,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    tester.widget<OutlinedButton>(previewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.payoutImportBatchCreateCalls, 1);
    expect(api.payoutImportBatchPreviewCalls, 1);
    expect(find.textContaining('Payout import preview ready'), findsOneWidget);
    expect(
        find.text('Preview ready • bank_report_2026w15.csv'), findsOneWidget);
    expect(
      find.text('No payout runs or audit rows were mutated yet.'),
      findsOneWidget,
    );
  });

  testWidgets('coach operator console invalidates active payout import preview',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    await _dragUntilTextVisible(tester, 'Report name');
    await tester.enterText(
      find.widgetWithText(TextField, 'Report name'),
      'bank_report_2026w15.csv',
    );
    await _dragUntilTextVisible(tester, 'CSV report body');
    await tester.enterText(
      find.widgetWithText(TextField, 'CSV report body'),
      'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
      'payoutrun_demo_express,executed,bank_import_payoutrun_demo_express,bank_file_2026w15,2026-04-14T10:06:00Z,executed import applied from coach ops console\n'
      'payoutrun_demo_failed,failed,,bank_file_2026w15,2026-04-14T10:07:00Z,failed import applied from coach ops console',
    );
    final previewButton = find.widgetWithText(OutlinedButton, 'Preview report');
    await tester.dragUntilVisible(
      previewButton,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    tester.widget<OutlinedButton>(previewButton).onPressed!.call();
    await tester.pumpAndSettle();

    final applyButton =
        find.widgetWithText(OutlinedButton, 'Apply payout report');
    expect(tester.widget<OutlinedButton>(applyButton).onPressed, isNotNull);

    final invalidateButton =
        find.widgetWithText(OutlinedButton, 'Invalidate preview').first;
    tester.widget<OutlinedButton>(invalidateButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.payoutImportPreviewInvalidateCalls, 1);
    expect(api.payoutImportPreviewsSnapshot().summary.invalidatedPreviews, 1);
    await _dragUntilTextVisible(tester, 'Apply payout report');
    expect(tester.widget<OutlinedButton>(applyButton).onPressed, isNull);
  });

  testWidgets(
      'coach operator console filters preview history by status and date',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    CoachPayoutImportPreviewHistoryFilterPreferences? savedPreferences;
    api.payoutImportPreviewEvents
        .addAll(const <CoachOperatorPayoutImportPreview>[
      CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_demo_active_window',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_2026w15.csv',
        reportFormat: 'csv',
        reportChecksumSha256: 'sha256_demo_active_window',
        requestFingerprint: 'fp_preview_active_window_demo',
        previewStatus: 'active',
        createdAtIso: '2026-04-14T11:08:00Z',
        expiresAtIso: '2026-04-14T11:18:00Z',
        usableNow: true,
        reworkOfBatchId: null,
        consumedAtIso: null,
        invalidatedAtIso: null,
      ),
      CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_demo_invalidated_window',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_2026w15.csv',
        reportFormat: 'csv',
        reportChecksumSha256: 'sha256_demo_invalidated_window',
        requestFingerprint: 'fp_preview_invalidated_window_demo',
        previewStatus: 'invalidated',
        createdAtIso: '2026-04-14T10:08:00Z',
        expiresAtIso: '2026-04-14T10:18:00Z',
        usableNow: false,
        reworkOfBatchId: 'payoutbatch_demo_1',
        consumedAtIso: null,
        invalidatedAtIso: '2026-04-14T10:09:00Z',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          savePreviewHistoryFilterPreferencesOverride: (preferences) async {
            savedPreferences = preferences;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    final statusDropdown =
        find.byKey(const ValueKey('coachOpsPreviewHistoryStatusDropdown'));
    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!('invalidated');
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'From created_at (RFC3339)'),
      '2026-04-14T00:00:00Z',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'To created_at (RFC3339)'),
      '2026-04-14T23:59:59Z',
    );
    final applyFiltersButton = find.byKey(
      const ValueKey('coachOpsPreviewHistoryApplyFiltersButton'),
    );
    await tester.dragUntilVisible(
      applyFiltersButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(applyFiltersButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.lastPayoutImportPreviewStatusFilter, 'invalidated');
    expect(api.lastPayoutImportPreviewFromCreatedAtIso, '2026-04-14T00:00:00Z');
    expect(api.lastPayoutImportPreviewToCreatedAtIso, '2026-04-14T23:59:59Z');
    expect(savedPreferences?.status, 'invalidated');
    expect(savedPreferences?.fromCreatedAtIso, '2026-04-14T00:00:00Z');
    expect(savedPreferences?.toCreatedAtIso, '2026-04-14T23:59:59Z');
    await _dragUntilTextVisible(
      tester,
      'previewtoken_demo_invalidated_window • bank_report_2026w15.csv',
    );
    expect(
      find.textContaining('previewtoken_demo_invalidated_window'),
      findsOneWidget,
    );
    expect(
        find.textContaining('previewtoken_demo_active_window'), findsNothing);
  });

  testWidgets(
      'coach operator console filters preview history by operator scope locally',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    CoachPayoutImportPreviewHistoryFilterPreferences? savedPreferences;
    api.payoutImportPreviewEvents
        .addAll(const <CoachOperatorPayoutImportPreview>[
      CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_scope_demo_a',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_scope_a.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_a'],
        reportChecksumSha256: 'sha256_scope_a',
        requestFingerprint: 'fp_preview_scope_a_demo',
        previewStatus: 'active',
        createdAtIso: '2026-04-14T12:08:00Z',
        expiresAtIso: '2026-04-14T12:18:00Z',
        usableNow: true,
        reworkOfBatchId: null,
        consumedAtIso: null,
        invalidatedAtIso: null,
      ),
      CoachOperatorPayoutImportPreview(
        previewToken: 'previewtoken_scope_demo_b',
        accountId: 'acct_finance_demo',
        importSource: 'bank_report',
        reportName: 'bank_report_scope_b.csv',
        reportFormat: 'csv',
        operatorIds: <String>['op_scope_b'],
        reportChecksumSha256: 'sha256_scope_b',
        requestFingerprint: 'fp_preview_scope_b_demo',
        previewStatus: 'active',
        createdAtIso: '2026-04-14T11:08:00Z',
        expiresAtIso: '2026-04-14T11:18:00Z',
        usableNow: true,
        reworkOfBatchId: null,
        consumedAtIso: null,
        invalidatedAtIso: null,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          savePreviewHistoryFilterPreferencesOverride: (preferences) async {
            savedPreferences = preferences;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    final operatorFilter = find.byKey(
      const ValueKey('coachOpsPreviewHistoryOperatorFilterField'),
    );
    await tester.dragUntilVisible(
      operatorFilter,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester
        .widget<DropdownButtonFormField<String>>(operatorFilter)
        .onChanged!('op_scope_b');
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('coachOpsPreviewHistoryOperatorFilterChip'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await _dragUntilTextVisible(
      tester,
      'previewtoken_scope_demo_b • bank_report_scope_b.csv',
    );
    expect(find.textContaining('previewtoken_scope_demo_b'), findsOneWidget);
    expect(find.textContaining('previewtoken_scope_demo_a'), findsNothing);
    expect(api.lastPayoutImportPreviewStatusFilter, isNull);
    expect(savedPreferences?.operatorId, 'op_scope_b');
    expect(savedPreferences?.status, 'all');
  });

  testWidgets(
      'coach operator console restores persisted preview history filters on load',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    var loadCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          loadPreviewHistoryFilterPreferencesOverride: () async {
            loadCalls += 1;
            return const CoachPayoutImportPreviewHistoryFilterPreferences(
              status: 'invalidated',
              fromCreatedAtIso: '2026-04-14T00:00:00Z',
              toCreatedAtIso: '2026-04-14T23:59:59Z',
              operatorId: 'op_demo_express',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCalls, 1);
    expect(api.lastPayoutImportPreviewStatusFilter, 'invalidated');
    expect(api.lastPayoutImportPreviewFromCreatedAtIso, '2026-04-14T00:00:00Z');
    expect(api.lastPayoutImportPreviewToCreatedAtIso, '2026-04-14T23:59:59Z');
    await _dragUntilTextVisible(tester, 'Preview history');
    final statusDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('coachOpsPreviewHistoryStatusDropdown')),
    );
    final operatorDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('coachOpsPreviewHistoryOperatorFilterField')),
    );
    final fromField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'From created_at (RFC3339)'),
    );
    final toField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'To created_at (RFC3339)'),
    );
    expect(statusDropdown.initialValue, 'invalidated');
    expect(operatorDropdown.initialValue, 'op_demo_express');
    expect(fromField.controller!.text, '2026-04-14T00:00:00Z');
    expect(toField.controller!.text, '2026-04-14T23:59:59Z');
  });

  testWidgets(
      'coach operator console preview history presets populate UTC draft window',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final fixedNowUtc = DateTime.utc(2026, 4, 14, 18, 30, 45);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          previewHistoryNowUtcOverride: () => fixedNowUtc,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    final last24hPreset = find.byKey(
      const ValueKey('coachOpsPreviewHistoryPresetLast24h'),
    );
    await tester.dragUntilVisible(
      last24hPreset,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(last24hPreset).onPressed!.call();
    await tester.pumpAndSettle();

    final fromField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'From created_at (RFC3339)'),
    );
    final toField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'To created_at (RFC3339)'),
    );
    expect(fromField.controller!.text, '2026-04-13T18:30:45Z');
    expect(toField.controller!.text, '2026-04-14T18:30:45Z');
  });

  testWidgets(
      'coach operator console combined preview history presets populate status and UTC draft window',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final fixedNowUtc = DateTime.utc(2026, 4, 14, 18, 30, 45);

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          previewHistoryNowUtcOverride: () => fixedNowUtc,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    final combinedPreset = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryCombinedPresetInvalidatedLast7d',
      ),
    );
    await tester.dragUntilVisible(
      combinedPreset,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(combinedPreset).onPressed!.call();
    await tester.pumpAndSettle();

    final statusDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('coachOpsPreviewHistoryStatusDropdown')),
    );
    final fromField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'From created_at (RFC3339)'),
    );
    final toField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'To created_at (RFC3339)'),
    );
    expect(statusDropdown.initialValue, 'invalidated');
    expect(fromField.controller!.text, '2026-04-07T18:30:45Z');
    expect(toField.controller!.text, '2026-04-14T18:30:45Z');
  });

  testWidgets(
      'coach operator console saves and applies preview history saved views',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    var savedViews = <CoachPayoutImportPreviewHistorySavedView>[];

    Future<List<CoachPayoutImportPreviewHistorySavedView>> saveView(
      CoachPayoutImportPreviewHistorySavedView view,
    ) async {
      savedViews = <CoachPayoutImportPreviewHistorySavedView>[
        view,
        ...savedViews.where((entry) => entry.viewId != view.viewId),
      ];
      return savedViews;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          savePreviewHistoryFilterPreferencesOverride: (_) async {},
          loadPreviewHistorySavedViewsOverride: () async => savedViews,
          savePreviewHistorySavedViewOverride: saveView,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    final statusDropdown =
        find.byKey(const ValueKey('coachOpsPreviewHistoryStatusDropdown'));
    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!('invalidated');
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'From created_at (RFC3339)'),
      '2026-04-14T00:00:00Z',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'To created_at (RFC3339)'),
      '2026-04-14T23:59:59Z',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Saved view name'),
      'Invalidated day',
    );
    final saveViewButton = find.byKey(
      const ValueKey('coachOpsPreviewHistorySaveViewButton'),
    );
    await tester.dragUntilVisible(
      saveViewButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(saveViewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(savedViews, hasLength(1));
    expect(savedViews.first.name, 'Invalidated day');
    expect(find.text('Invalidated day'), findsWidgets);

    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!('active');
    await tester.pump();
    final applySavedViewButton = find.byKey(
      ValueKey(
        'coachOpsPreviewHistoryApplySavedView_${savedViews.first.viewId}',
      ),
    );
    await tester.dragUntilVisible(
      applySavedViewButton,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    tester.widget<OutlinedButton>(applySavedViewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.lastPayoutImportPreviewStatusFilter, 'invalidated');
    expect(api.lastPayoutImportPreviewFromCreatedAtIso, '2026-04-14T00:00:00Z');
    expect(api.lastPayoutImportPreviewToCreatedAtIso, '2026-04-14T23:59:59Z');
  });

  testWidgets(
      'coach operator console loads preview history saved views from API when available',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_demo_invalidated',
          name: 'Invalidated day',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-14T00:00:00Z',
            toCreatedAtIso: '2026-04-14T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          isDefault: true,
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T09:56:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');

    expect(api.payoutImportPreviewSavedViewsCalls, 1);
    expect(find.text('Invalidated day'), findsWidgets);
    expect(find.textContaining('invalidated'), findsWidgets);
    expect(find.text('Default view'), findsWidgets);
  });

  testWidgets(
      'coach operator console filters preview history saved views by scope',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_personal',
          name: 'Personal invalidated day',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-14T00:00:00Z',
            toCreatedAtIso: '2026-04-14T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T09:56:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared',
          accountId: 'acct_finance_shared',
          name: 'Shared invalidated day',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-13T00:00:00Z',
            toCreatedAtIso: '2026-04-13T23:59:59Z',
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Personal invalidated day');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistorySavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    expect(
      find.text('Shared invalidated day', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Personal invalidated day', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('coachOpsPreviewHistorySavedViewsFilteredCountChip'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Shown: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console renders non-owned shared preview history saved views as read only',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_read_only',
          accountId: 'acct_finance_other',
          name: 'Shared invalidated day',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-14T00:00:00Z',
            toCreatedAtIso: '2026-04-14T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          canManage: false,
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T09:56:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Shared invalidated day');
    expect(find.text('Shared with ops', skipOffstage: false), findsWidgets);
    expect(
      find.text('Shared by acct_finance_other', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Read-only shared view', skipOffstage: false),
      findsOneWidget,
    );

    final setDefaultButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryToggleDefaultSavedView_previewhistoryview_shared_read_only',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, setDefaultButton);
    expect(
      tester.widget<OutlinedButton>(setDefaultButton).onPressed,
      isNull,
    );

    final deleteButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryDeleteSavedView_previewhistoryview_shared_read_only',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, deleteButton);
    expect(
      tester.widget<TextButton>(deleteButton).onPressed,
      isNull,
    );
  });

  testWidgets(
      'coach operator console filters preview history saved views by owner',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_personal',
          name: 'Personal invalidated day',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-14T00:00:00Z',
            toCreatedAtIso: '2026-04-14T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T09:56:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared invalidated day A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-13T00:00:00Z',
            toCreatedAtIso: '2026-04-13T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared invalidated day B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Personal invalidated day');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistorySavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    final ownerFilter = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistorySavedViewsOwnerFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, ownerFilter, maxAttempts: 20);
    tester.widget<DropdownButtonFormField<String>>(ownerFilter).onChanged!.call(
          'acct_finance_other',
        );
    await tester.pumpAndSettle();

    expect(api.payoutImportPreviewSavedViewOwnersCalls, 1);
    expect(
      find.text('Shared invalidated day B', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Shared invalidated day A', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.text('acct_finance_other exposes 1 shared view.',
          skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console filters preview history saved views by operator',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_personal',
          name: 'Personal invalidated day',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-14T00:00:00Z',
            toCreatedAtIso: '2026-04-14T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T09:56:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared invalidated day A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-13T00:00:00Z',
            toCreatedAtIso: '2026-04-13T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared invalidated day B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Personal invalidated day');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistorySavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'shared_ops',
        );
    await tester.pumpAndSettle();

    final operatorFilter = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistorySavedViewsOperatorFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, operatorFilter, maxAttempts: 20);
    tester
        .widget<DropdownButtonFormField<String>>(operatorFilter)
        .onChanged!
        .call('op_border_runner');
    await tester.pumpAndSettle();

    expect(api.payoutImportPreviewSavedViewOperatorsCalls, 1);
    expect(
      find.text('Shared invalidated day B', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Shared invalidated day A', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.textContaining('Border Runner', skipOffstage: false),
      findsWidgets,
    );
  });

  testWidgets(
      'coach operator console filters preview history saved views from card action by operator',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared invalidated day A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-13T00:00:00Z',
            toCreatedAtIso: '2026-04-13T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared invalidated day B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Shared invalidated day B');
    final button = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryFilterByOperator_previewhistoryview_shared_b',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, button, maxAttempts: 20);
    tester.widget<OutlinedButton>(button).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      find.text('Shared invalidated day B', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Shared invalidated day A', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.textContaining('Shown: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console filters preview history saved views from card action by owner',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_a',
          accountId: 'acct_finance_shared',
          name: 'Shared invalidated day A',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-13T00:00:00Z',
            toCreatedAtIso: '2026-04-13T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_b',
          accountId: 'acct_finance_other',
          name: 'Shared invalidated day B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Shared invalidated day B');
    final button = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryFilterByOwner_previewhistoryview_shared_b',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, button, maxAttempts: 20);
    tester.widget<OutlinedButton>(button).onPressed!.call();
    await tester.pumpAndSettle();

    expect(
      find.text('Shared invalidated day B', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Shared invalidated day A', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.textContaining('acct_finance_other exposes 1 shared view.',
          skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console shows preview history saved view triage chips',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_read_only',
          accountId: 'acct_finance_other',
          name: 'Shared invalidated day B',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
            operatorId: 'op_border_runner',
          ),
          canManage: false,
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Shared invalidated day B');
    expect(find.text('Owner acct_finance_other', skipOffstage: false),
        findsOneWidget);
    expect(find.text('Operator Border Runner', skipOffstage: false),
        findsOneWidget);
    expect(find.text('Read-only', skipOffstage: false), findsOneWidget);
    expect(find.text('Invalidated', skipOffstage: false), findsWidgets);
    expect(find.text('From 2026-04-12', skipOffstage: false), findsOneWidget);
    expect(find.text('To 2026-04-12', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
      'coach operator console shows active filter chips on preview history saved view cards',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_shared_active',
          accountId: 'acct_finance_other',
          name: 'Shared invalidated day active',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
            operatorId: 'op_border_runner',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    await _dragUntilTextVisible(tester, 'Shared invalidated day active');

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryApplySavedView_previewhistoryview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, applyButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    final filterByOwnerButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryFilterByOwner_previewhistoryview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, filterByOwnerButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(filterByOwnerButton).onPressed!.call();
    await tester.pumpAndSettle();

    final filterByOperatorButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryFilterByOperator_previewhistoryview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(
      tester,
      filterByOperatorButton,
      maxAttempts: 20,
    );
    tester.widget<OutlinedButton>(filterByOperatorButton).onPressed!.call();
    await tester.pumpAndSettle();

    final pinButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryTogglePinnedSavedView_previewhistoryview_shared_active',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, pinButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(pinButton).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Active scope', skipOffstage: false), findsOneWidget);
    expect(find.text('Active owner', skipOffstage: false), findsOneWidget);
    expect(find.text('Active operator', skipOffstage: false), findsOneWidget);
    expect(find.text('Using this view', skipOffstage: false), findsOneWidget);
    expect(find.text('Pinned', skipOffstage: false), findsOneWidget);
    expect(find.text('Unpin view', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('Last used ', skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(applyButton).onPressed, isNull);
    expect(
      find.text('View already active', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach operator console sorts current preview history saved view first',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_personal_a',
          name: 'Personal active day A',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'active',
            fromCreatedAtIso: '2026-04-13T00:00:00Z',
            toCreatedAtIso: '2026-04-13T23:59:59Z',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_personal_b',
          name: 'Personal invalidated day B',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistorySavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'personal',
        );
    await tester.pumpAndSettle();

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryApplySavedView_previewhistoryview_personal_b',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, applyButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'View already active');
    await _dragUntilTextVisible(tester, 'Personal active day A');
    await _dragUntilTextVisible(tester, 'Recent views');
    final recentChip = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryRecentSavedView_previewhistoryview_personal_b',
      ),
      skipOffstage: false,
    );
    expect(recentChip, findsOneWidget);
    expect(tester.widget<ActionChip>(recentChip).onPressed, isNull);
    final activeOffset = tester.getTopLeft(
      find.text('View already active', skipOffstage: false),
    );
    final otherOffset = tester.getTopLeft(
      find.text('Personal active day A', skipOffstage: false),
    );
    expect(activeOffset.dy, lessThan(otherOffset.dy));
  });

  testWidgets(
      'coach operator console sorts pinned catalog import run saved view ahead of unpinned views',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..catalogImportRunSavedViews = <CoachCatalogImportRunSavedView>[
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_personal_b',
          name: 'Personal failed B',
          visibilityScope: 'personal',
          preferences: CoachCatalogImportRunFilterPreferences(status: 'failed'),
          createdAtIso: '2026-04-16T08:04:00Z',
          updatedAtIso: '2026-04-16T08:05:00Z',
        ),
        const CoachCatalogImportRunSavedView(
          viewId: 'catalogview_personal_a',
          name: 'Personal running A',
          visibilityScope: 'personal',
          preferences:
              CoachCatalogImportRunFilterPreferences(status: 'running'),
          createdAtIso: '2026-04-16T08:02:00Z',
          updatedAtIso: '2026-04-16T08:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['admin'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialCatalogImportConfig: api.catalogImportConfigSnapshot(),
          initialCatalogImportRuns: api.catalogImportRunsSnapshot(limit: 2),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Saved views');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'personal',
        );
    await tester.pumpAndSettle();

    final pinButton = find.byKey(
      const ValueKey(
        'coachOpsCatalogImportRunsTogglePinnedSavedView_catalogview_personal_a',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, pinButton);
    tester.widget<OutlinedButton>(pinButton).onPressed!.call();
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Pinned');
    final pinnedOffset = tester.getTopLeft(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunsTogglePinnedSavedView_catalogview_personal_a',
        ),
        skipOffstage: false,
      ),
    );
    final otherOffset = tester.getTopLeft(
      find.byKey(
        const ValueKey(
          'coachOpsCatalogImportRunsTogglePinnedSavedView_catalogview_personal_b',
        ),
        skipOffstage: false,
      ),
    );
    expect(pinnedOffset.dy, lessThan(otherOffset.dy));
  });

  testWidgets(
      'coach operator console sorts recently used preview history saved view ahead of stale views',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_personal_b',
          name: 'Personal invalidated day B',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-12T00:00:00Z',
            toCreatedAtIso: '2026-04-12T23:59:59Z',
          ),
          createdAtIso: '2026-04-15T09:58:00Z',
          updatedAtIso: '2026-04-15T10:04:00Z',
        ),
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_personal_a',
          name: 'Personal active day A',
          visibilityScope: 'personal',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'active',
            fromCreatedAtIso: '2026-04-13T00:00:00Z',
            toCreatedAtIso: '2026-04-13T23:59:59Z',
          ),
          createdAtIso: '2026-04-15T09:57:00Z',
          updatedAtIso: '2026-04-15T10:03:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Preview history');
    final scopeFilter = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistorySavedViewsVisibilityFilterField',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, scopeFilter, maxAttempts: 40);
    tester.widget<DropdownButtonFormField<String>>(scopeFilter).onChanged!.call(
          'personal',
        );
    await tester.pumpAndSettle();

    final applyButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryApplySavedView_previewhistoryview_personal_a',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, applyButton, maxAttempts: 20);
    tester.widget<OutlinedButton>(applyButton).onPressed!.call();
    await tester.pumpAndSettle();

    final statusDropdown =
        find.byKey(const ValueKey('coachOpsPreviewHistoryStatusDropdown'));
    await _dragUntilFinderVisible(tester, statusDropdown, maxAttempts: 20);
    tester
        .widget<DropdownButtonFormField<String>>(statusDropdown)
        .onChanged!('all');
    await tester.pump();
    final applyFiltersButton = find.byKey(
      const ValueKey('coachOpsPreviewHistoryApplyFiltersButton'),
    );
    await _dragUntilFinderVisible(
      tester,
      applyFiltersButton,
      maxAttempts: 20,
    );
    tester.widget<OutlinedButton>(applyFiltersButton).onPressed!.call();
    await tester.pumpAndSettle();

    final recentApplyButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryApplySavedView_previewhistoryview_personal_a',
      ),
      skipOffstage: false,
    );
    final staleApplyButton = find.byKey(
      const ValueKey(
        'coachOpsPreviewHistoryApplySavedView_previewhistoryview_personal_b',
      ),
      skipOffstage: false,
    );
    await _dragUntilFinderVisible(tester, recentApplyButton, maxAttempts: 20);
    await _dragUntilFinderVisible(tester, staleApplyButton, maxAttempts: 20);
    final recentOffset = tester.getTopLeft(
      recentApplyButton,
    );
    final staleOffset = tester.getTopLeft(
      staleApplyButton,
    );
    expect(recentOffset.dy, lessThan(staleOffset.dy));
  });

  testWidgets(
      'coach operator console applies default preview history saved view on load',
      (tester) async {
    final api = _FakeCoachOperatorApi()
      ..payoutQueued = true
      ..payoutImportPreviewSavedViews =
          const <CoachPayoutImportPreviewHistorySavedView>[
        CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewhistoryview_demo_invalidated',
          name: 'Invalidated day',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-14T00:00:00Z',
            toCreatedAtIso: '2026-04-14T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          isDefault: true,
          createdAtIso: '2026-04-15T09:55:00Z',
          updatedAtIso: '2026-04-15T09:56:00Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.lastPayoutImportPreviewStatusFilter, 'invalidated');
    expect(api.lastPayoutImportPreviewFromCreatedAtIso, '2026-04-14T00:00:00Z');
    expect(api.lastPayoutImportPreviewToCreatedAtIso, '2026-04-14T23:59:59Z');
  });

  testWidgets('coach operator console uploads selected payout import file',
      (tester) async {
    final api = _FakeCoachOperatorApi()..payoutQueued = true;
    final uploadBody =
        'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
        'payoutrun_demo_express,executed,bank_import_payoutrun_demo_express,bank_file_2026w15,2026-04-14T10:06:00Z,executed import applied from uploaded csv\n';

    await tester.pumpWidget(
      MaterialApp(
        home: CoachOperatorConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['finance'],
            isSuperadmin: false,
          ),
          initialRefundQueue: api.refundQueueSnapshot(),
          initialChangeQueue: api.changeQueueSnapshot(),
          initialReconciliation: api.reconciliationSnapshot(),
          initialSettlementStatements: api.settlementStatementsSnapshot(),
          initialPayoutRuns: api.payoutRunsSnapshot(),
          initialPayoutReconciliation: api.payoutReconciliationSnapshot(),
          initialPayoutImports: api.payoutImportsSnapshot(),
          initialPayoutImportPreviews: api.payoutImportPreviewsSnapshot(),
          initialPayoutImportBatches: api.payoutImportBatchesSnapshot(),
          initialPayoutImportProfiles: api.payoutImportProfilesSnapshot(),
          pickPayoutImportFileOverride: () async => CoachPickedPayoutImportFile(
            fileName: 'bank_report_uploaded.csv',
            bytes: Uint8List.fromList(utf8.encode(uploadBody)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Payout import batches');
    final selectFileButton =
        find.widgetWithText(OutlinedButton, 'Select CSV file');
    await tester.dragUntilVisible(
      selectFileButton,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    tester.widget<OutlinedButton>(selectFileButton).onPressed!.call();
    await tester.pumpAndSettle();
    await _dragUntilTextVisible(
      tester,
      'Selected file: bank_report_uploaded.csv',
    );
    expect(
      find.textContaining('Selected file: bank_report_uploaded.csv'),
      findsOneWidget,
    );

    final previewButton = find.widgetWithText(OutlinedButton, 'Preview report');
    await tester.dragUntilVisible(
      previewButton,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    tester.widget<OutlinedButton>(previewButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(api.payoutImportBatchCreateCalls, 0);
    expect(api.payoutImportBatchPreviewCalls, 0);
    expect(api.payoutImportBatchUploadCalls, 1);
    expect(api.payoutImportBatchUploadPreviewCalls, 1);
    expect(api.lastUploadedPayoutImportFileName, 'bank_report_uploaded.csv');
    expect(api.lastUploadedPayoutImportBody, uploadBody);
    expect(find.textContaining('Payout import preview ready'), findsOneWidget);
  });
}
