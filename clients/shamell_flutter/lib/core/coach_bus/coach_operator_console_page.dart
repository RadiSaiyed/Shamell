import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../account_privilege_store.dart';
import '../dashboard_policy_scope.dart';
import '../l10n.dart';
import '../safe_set_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_catalog_import_run_filter_store.dart';
import 'coach_operator_disruption_broadcast_page.dart';
import '../rides/operator_activity_page.dart';
import 'coach_payout_import_batch_filter_store.dart';
import 'coach_saved_view_pin_store.dart';
import 'coach_saved_view_usage_store.dart';
import 'coach_mobility_api.dart';
import 'coach_ops_feature_widgets.dart';
import 'coach_payout_import_preview_diff.dart';
import 'coach_payout_import_preview_history_filter_store.dart';
import 'coach_payout_import_rework_delta.dart';
import 'coach_payout_import_rework_validation.dart';
import 'coach_platform_contracts.dart';

String _coachFormatCatalogOperatorScope(List<String> operatorIds) {
  final normalized = operatorIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) {
    return 'all discovered operators';
  }
  if (normalized.length <= 3) {
    return normalized.join(', ');
  }
  return '${normalized.take(3).join(', ')} +${normalized.length - 3} more';
}

const String _catalogImportRunSavedViewUsageCollectionKey =
    'catalog_import_run';
const String _catalogImportRunIssueSavedViewUsageCollectionKey =
    'catalog_import_run_issue';
const String _payoutImportPreviewSavedViewUsageCollectionKey =
    'payout_import_preview';
const String _payoutImportBatchSavedViewUsageCollectionKey =
    'payout_import_batch';

enum _CoachCatalogImportMutationAction {
  saveConfig,
  uploadSource,
  triggerRun,
}

String _coachOpsMoney(String currency, int minorUnits) {
  final major = minorUnits ~/ 100;
  final cents = (minorUnits.abs() % 100).toString().padLeft(2, '0');
  return '$currency $major.$cents';
}

String _coachCatalogImportScopedSourceGuidanceText(bool isArabic) {
  return isArabic
      ? 'هذا الحساب مقيّد بنطاق المشغل. اختر مصدر GTFS ضمن النطاق أو ارفع أرشيفًا جديدًا لهذا المشغل.'
      : 'This account is restricted to operator-scoped sources. Select an in-scope GTFS source or upload a new archive for this operator.';
}

String _coachCatalogImportScopedSourceEmptyText(bool isArabic) {
  return isArabic
      ? 'لا توجد مصادر ضمن النطاق بعد. ارفع أرشيف GTFS جديدًا لهذا المشغل للمتابعة.'
      : 'No in-scope sources are available yet. Upload a GTFS archive for this operator to continue.';
}

String _coachCatalogImportTriggerGuidanceText(
  bool isArabic, {
  required bool ready,
  required bool scopedSourceRequired,
}) {
  if (!ready) {
    if (scopedSourceRequired) {
      return isArabic
          ? 'اختر مصدر GTFS ضمن النطاق أو ارفع أرشيفًا جديدًا لهذا المشغل قبل تشغيل الاستيراد اليدوي.'
          : 'Select an in-scope GTFS source or upload a new archive for this operator before running a manual import.';
    }
    return isArabic
        ? 'اضبط مصدر GTFS أولاً قبل تشغيل الاستيراد اليدوي.'
        : 'Configure a valid GTFS source before running a manual import.';
  }
  if (scopedSourceRequired) {
    return isArabic
        ? 'شغّل استيراد GTFS المحدد ضمن النطاق الآن لتحديث الكتالوج وسجل الصحة.'
        : 'Run the selected in-scope GTFS import now to refresh the catalog and feed health.';
  }
  return isArabic
      ? 'أعد تشغيل استيراد GTFS المهيأ على الخادم لتحديث الكتالوج وسجل الصحة.'
      : 'Run the configured GTFS import now to refresh the catalog and feed health.';
}

String _coachCatalogImportActionableErrorDetail(
  String detail, {
  required bool isArabic,
  required _CoachCatalogImportMutationAction action,
}) {
  final normalized = detail.trim().toLowerCase();
  if (normalized.isEmpty) {
    return detail;
  }
  final isOperatorScopeConflict =
      normalized.contains('restricted operator account') ||
          normalized.contains('operator scope unavailable') ||
          normalized.contains('exceeds operator privileges');
  if (!isOperatorScopeConflict) {
    return detail;
  }
  if (normalized.contains('replay import run')) {
    return isArabic
        ? 'افتح تشغيل استيراد ضمن نطاق هذا المشغل أو اختر مصدر GTFS ضمن النطاق.'
        : 'Open an in-scope import run or select an in-scope GTFS source for this operator.';
  }
  if (action == _CoachCatalogImportMutationAction.uploadSource) {
    return isArabic
        ? 'ملف GTFS ZIP المحدد خارج نطاق هذا المشغل. ارفع ملف GTFS ZIP لهذا المشغل أو اختر مصدرًا ضمن النطاق.'
        : 'This GTFS ZIP is outside the allowed operator scope. Upload a GTFS ZIP for this operator or select an in-scope source.';
  }
  return isArabic
      ? 'اختر مصدر GTFS ضمن النطاق أو ارفع ملف GTFS ZIP لهذا المشغل.'
      : 'Select an in-scope GTFS source or upload a GTFS ZIP for this operator.';
}

String? _coachCatalogImportUploadDisabledHintText(
  bool isArabic, {
  required bool hasSelectedArchive,
  required bool uploading,
  required bool loading,
}) {
  if (uploading || loading || hasSelectedArchive) {
    return null;
  }
  return isArabic
      ? 'اختر ملف GTFS ZIP لتفعيل الرفع.'
      : 'Select a GTFS ZIP to enable upload.';
}

String? _coachCatalogImportSaveDisabledHintText(
  bool isArabic, {
  required bool scopedSourceRequired,
  required bool hasScopedSourceDraft,
  required bool hasFeedLocatorDraft,
  required bool hasSelectedArchive,
  required bool saving,
  required bool loading,
}) {
  if (saving || loading) {
    return null;
  }
  if (scopedSourceRequired && !hasScopedSourceDraft) {
    if (hasSelectedArchive) {
      return isArabic
          ? 'ارفع ملف GTFS ZIP المحدد أو اختر مصدرًا ضمن النطاق لتفعيل هذا الإعداد.'
          : 'Upload the selected GTFS ZIP or choose an in-scope source to activate this configuration.';
    }
    return isArabic
        ? 'اختر مصدر GTFS ضمن النطاق أو ارفع ملف GTFS ZIP لهذا المشغل لتفعيل هذا الإعداد.'
        : 'Select an in-scope GTFS source or upload a GTFS ZIP for this operator to activate this configuration.';
  }
  if (!scopedSourceRequired && !hasFeedLocatorDraft) {
    return isArabic
        ? 'أدخل مسار التغذية أو اختر مصدرًا متاحًا لتفعيل الحفظ.'
        : 'Enter a feed locator or choose an available source to enable save.';
  }
  return null;
}

String? _coachCatalogImportTriggerDisabledHintText(
  bool isArabic, {
  required bool ready,
  required bool scopedSourceRequired,
  required bool running,
  required bool loading,
}) {
  if (running || loading || ready) {
    return null;
  }
  if (scopedSourceRequired) {
    return isArabic
        ? 'اختر مصدر GTFS ضمن النطاق أو ارفع ملف GTFS ZIP لهذا المشغل لتفعيل الاستيراد اليدوي.'
        : 'Select an in-scope GTFS source or upload a GTFS ZIP for this operator to enable manual import.';
  }
  return isArabic
      ? 'اضبط مصدر GTFS صالحًا لتفعيل الاستيراد اليدوي.'
      : 'Configure a valid GTFS source to enable manual import.';
}

String _coachCatalogImportReadOnlyConfigHintText(
  bool isArabic, {
  required bool scopedSourceRequired,
  required bool hasSourceArtifact,
}) {
  if (scopedSourceRequired && !hasSourceArtifact) {
    return isArabic
        ? 'هذا الحساب يملك صلاحية المراجعة فقط. يجب على مشغّل الكتالوج اختيار مصدر GTFS ضمن النطاق أو رفع ملف GTFS ZIP لهذا المشغل.'
        : 'This account is read-only for catalog imports. A catalog operator must select an in-scope GTFS source or upload a GTFS ZIP for this operator.';
  }
  if (hasSourceArtifact) {
    return isArabic
        ? 'هذا الحساب يملك صلاحية المراجعة فقط. راجع الأرشيف المرتبط أو اطلب من مشغّل الكتالوج تشغيل الاستيراد من هذا المصدر.'
        : 'This account is read-only for catalog imports. Review the linked artifact or ask a catalog operator to run the import from this source.';
  }
  return isArabic
      ? 'هذا الحساب يملك صلاحية المراجعة فقط. راجع التهيئة الحالية واطلب من مشغّل الكتالوج تحديث المصدر أو تشغيل الاستيراد.'
      : 'This account is read-only for catalog imports. Review the current configuration and ask a catalog operator to update the source or run the import.';
}

String _coachCatalogSourceArtifactReadOnlyHintText(bool isArabic) {
  return isArabic
      ? 'هذا الحساب يملك صلاحية المراجعة فقط. افتح التفاصيل أو اطلب من مشغّل الكتالوج تشغيل الاستيراد من هذا الأرشيف.'
      : 'This account is read-only for catalog imports. Open details or ask a catalog operator to run the import from this artifact.';
}

String _coachCatalogImportRunReadOnlyHintText(
  bool isArabic,
  CoachOperatorCatalogImportRun entry,
) {
  final needsAttention =
      entry.isFailed || entry.errorMessage != null || entry.issues.isNotEmpty;
  if (needsAttention) {
    return isArabic
        ? 'هذا الحساب يملك صلاحية المراجعة فقط. افتح التفاصيل لمراجعة المشاكل ثم اطلب من مشغّل الكتالوج إعادة تشغيل هذا الاستيراد أو إعادة التشغيل من المصدر المرتبط.'
        : 'This account is read-only for catalog imports. Open details to review issues, then ask a catalog operator to replay this run or rerun it from the linked source.';
  }
  if ((entry.replayedFromImportRunId ?? '').trim().isNotEmpty ||
      (entry.replayLineageSummary?.replayRunCount ?? 0) > 0) {
    return isArabic
        ? 'هذا الحساب يملك صلاحية المراجعة فقط. افتح التفاصيل لمراجعة سلسلة الإعادات أو اطلب من مشغّل الكتالوج متابعة replay أو rerun.'
        : 'This account is read-only for catalog imports. Open details to inspect replay lineage or ask a catalog operator to continue with replay or rerun actions.';
  }
  return isArabic
      ? 'هذا الحساب يملك صلاحية المراجعة فقط. افتح التفاصيل لمراجعة هذا التشغيل أو اطلب من مشغّل الكتالوج إعادة التشغيل من المصدر المرتبط.'
      : 'This account is read-only for catalog imports. Open details to review this run or ask a catalog operator to rerun it from the linked source.';
}

String _coachCatalogImportRunDetailReadOnlyHintText(
  bool isArabic,
  CoachOperatorCatalogImportRun entry,
) {
  final hasReplaySource =
      (entry.replayedFromImportRunId ?? '').trim().isNotEmpty;
  final hasSourceArtifact = (entry.sourceArtifactId ?? '').trim().isNotEmpty ||
      entry.sourceArtifact != null;
  final hasReplayRuns = (entry.replayLineageSummary?.replayRunCount ?? 0) > 0;
  final needsAttention =
      entry.isFailed || entry.errorMessage != null || entry.issues.isNotEmpty;
  if (needsAttention &&
      (hasReplaySource || hasSourceArtifact || hasReplayRuns)) {
    return isArabic
        ? 'هذا الحساب يملك صلاحية المراجعة فقط. راجع المشاكل وسلسلة الإعادات والمصدر المرتبط من هنا، ثم اطلب من مشغّل الكتالوج تنفيذ replay أو rerun لهذا التشغيل.'
        : 'This account is read-only for catalog imports. Review issues, replay lineage, and linked source details here, then ask a catalog operator to replay this run or rerun it from the source.';
  }
  if (needsAttention) {
    return isArabic
        ? 'هذا الحساب يملك صلاحية المراجعة فقط. راجع المشاكل من هنا، ثم اطلب من مشغّل الكتالوج إعادة تشغيل هذا الاستيراد أو إعادة تشغيله من المصدر.'
        : 'This account is read-only for catalog imports. Review issues here, then ask a catalog operator to replay this run or rerun it from the source.';
  }
  if (hasReplaySource || hasSourceArtifact || hasReplayRuns) {
    return isArabic
        ? 'هذا الحساب يملك صلاحية المراجعة فقط. راجع سلسلة الإعادات والمصدر المرتبط من هنا، ثم اطلب من مشغّل الكتالوج متابعة replay أو rerun.'
        : 'This account is read-only for catalog imports. Review replay lineage and linked source details here, then ask a catalog operator to continue with replay or rerun actions.';
  }
  return isArabic
      ? 'هذا الحساب يملك صلاحية المراجعة فقط. راجع هذا التشغيل من هنا، ثم اطلب من مشغّل الكتالوج إعادة التشغيل من المصدر المرتبط.'
      : 'This account is read-only for catalog imports. Review this run here, then ask a catalog operator to rerun it from the linked source.';
}

String _coachCatalogImportRunReplaySourceReadOnlyHintText(bool isArabic) {
  return isArabic
      ? 'يمكنك فتح مصدر الإعادة للمراجعة فقط. إذا احتاج هذا التشغيل إلى replay جديد، فاطلب من مشغّل الكتالوج تنفيذه.'
      : 'You can open the replay source for review. If this run needs another replay, ask a catalog operator to execute it.';
}

String _coachCatalogImportRunSourceArtifactReadOnlyHintText(bool isArabic) {
  return isArabic
      ? 'يمكنك فتح الأرشيف المرتبط للمراجعة فقط. إذا احتاج هذا التشغيل إلى rerun من هذا المصدر، فاطلب من مشغّل الكتالوج تنفيذه.'
      : 'You can open the linked source artifact for review. If this run needs a rerun from this source, ask a catalog operator to execute it.';
}

String _coachCatalogImportRunReplayEntryReadOnlyHintText(bool isArabic) {
  return isArabic
      ? 'يمكنك فتح تشغيل الإعادة للمراجعة فقط. إذا احتاجت هذه السلسلة إلى replay أو rerun إضافي، فاطلب من مشغّل الكتالوج تنفيذه.'
      : 'You can open this replay run for review. If this lineage needs another replay or rerun, ask a catalog operator to execute it.';
}

String _coachOpsQueueStatusLabel(CoachOpsQueueStatus status) {
  switch (status) {
    case CoachOpsQueueStatus.pendingReview:
      return 'Pending review';
    case CoachOpsQueueStatus.approved:
      return 'Approved';
    case CoachOpsQueueStatus.rejected:
      return 'Rejected';
  }
}

String _coachOpsUrgencyLabel(CoachOpsRequestUrgency urgency) {
  switch (urgency) {
    case CoachOpsRequestUrgency.medium:
      return 'Medium';
    case CoachOpsRequestUrgency.high:
      return 'High';
    case CoachOpsRequestUrgency.critical:
      return 'Critical';
  }
}

String _coachOpsRequestKindLabel(CoachOpsRequestKind kind) {
  switch (kind) {
    case CoachOpsRequestKind.refundRequest:
      return 'Refund';
    case CoachOpsRequestKind.changeRequest:
      return 'Change';
  }
}

String _coachBoardingScanStatusLabel(CoachBoardingScanStatus status) {
  switch (status) {
    case CoachBoardingScanStatus.scanned:
      return 'Scanned';
    case CoachBoardingScanStatus.duplicate:
      return 'Duplicate';
    case CoachBoardingScanStatus.denied:
      return 'Denied';
    case CoachBoardingScanStatus.revoked:
      return 'Revoked';
    case CoachBoardingScanStatus.noShow:
      return 'No-show';
  }
}

String _coachPayoutExportFormatLabel(String exportFormat) {
  switch (exportFormat.trim().toLowerCase()) {
    case 'datev_json':
      return 'DATEV JSON';
    case 'csv':
      return 'CSV';
    default:
      return exportFormat.toUpperCase();
  }
}

String _coachPayoutImportStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'pending':
      return 'Pending';
    case 'executed':
      return 'Executed';
    case 'failed':
      return 'Failed';
    default:
      return status;
  }
}

String _coachPayoutImportPreviewStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'active':
      return 'Active';
    case 'consumed':
      return 'Consumed';
    case 'expired':
      return 'Expired';
    case 'invalidated':
      return 'Invalidated';
    default:
      return status;
  }
}

String _coachCatalogImportConfigStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'ready':
      return 'Ready';
    case 'missing':
      return 'Missing';
    default:
      return status;
  }
}

String _coachCatalogImportSourceKindLabel(String sourceKind) {
  switch (sourceKind.trim().toLowerCase()) {
    case 'gtfs':
      return 'GTFS';
    case 'netex':
      return 'NeTEx';
    default:
      return sourceKind.toUpperCase();
  }
}

String _coachCatalogImportSourceOriginLabel(String sourceOrigin) {
  switch (sourceOrigin.trim().toLowerCase()) {
    case 'database_saved':
      return 'Saved';
    case 'environment_default':
      return 'Environment default';
    case 'environment_option':
      return 'Configured option';
    default:
      return sourceOrigin;
  }
}

String _coachCatalogImportRunStatusFilterLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'all':
      return 'All';
    case 'failed':
      return 'Failed';
    case 'running':
      return 'Running';
    case 'succeeded':
      return 'Succeeded';
    default:
      return value;
  }
}

String _coachCatalogImportRunReplayScopeFilterLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'all':
      return 'All';
    case 'replays_only':
      return 'Replay only';
    case 'with_replays':
      return 'Has replays';
    case 'attention':
      return 'Attention';
    default:
      return value;
  }
}

String _coachCatalogImportRunStatusFilterChipLabel(String value) {
  return 'Run status: ${_coachCatalogImportRunStatusFilterLabel(value)}';
}

String _coachCatalogImportRunReplayScopeFilterChipLabel(String value) {
  return 'Replay scope: ${_coachCatalogImportRunReplayScopeFilterLabel(value)}';
}

String _coachCatalogImportRunIssueSeverityFilterLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'all':
      return 'All';
    case 'error':
      return 'Error';
    case 'warning':
      return 'Warning';
    case 'info':
      return 'Info';
    default:
      return value;
  }
}

String _coachCatalogImportRunIssueSeverityFilterChipLabel(String value) {
  return 'Issue severity: ${_coachCatalogImportRunIssueSeverityFilterLabel(value)}';
}

String _coachCatalogImportRunIssueStageFilterLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.toLowerCase() == 'all') {
    return 'All';
  }
  return normalized;
}

String _coachCatalogImportRunIssueStageFilterChipLabel(String value) {
  return 'Issue stage: ${_coachCatalogImportRunIssueStageFilterLabel(value)}';
}

String _coachPayoutReconciliationStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'balanced':
      return 'Balanced';
    case 'awaiting_bank_execution':
      return 'Awaiting bank execution';
    case 'missing_payment_reference':
      return 'Missing payment reference';
    case 'missing_exports':
      return 'Missing exports';
    case 'partial_exports':
      return 'Partial exports';
    case 'payout_failed':
      return 'Payout failed';
    default:
      return status;
  }
}

String _defaultCoachPayoutImportBatchReportBody() {
  return [
    'payout_run_id,external_status,payment_reference,external_reference,imported_at,note',
    'payoutrun_2026w15_001,executed,bank_transfer_2026w15_001,bank_file_2026w15,2026-04-14T10:06:00Z,bank import applied from operator console',
    'payoutrun_2026w15_002,failed,,bank_file_2026w15,2026-04-14T10:07:00Z,bank import requires finance review',
  ].join('\n');
}

class CoachPickedPayoutImportFile {
  final String fileName;
  final Uint8List bytes;

  const CoachPickedPayoutImportFile({
    required this.fileName,
    required this.bytes,
  });
}

class CoachPickedCatalogImportFile {
  final String fileName;
  final Uint8List bytes;

  const CoachPickedCatalogImportFile({
    required this.fileName,
    required this.bytes,
  });
}

class CoachOperatorConsolePage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final ShamellDashboardPolicy? dashboardPolicyOverride;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;
  final CoachOperatorRefundQueueResponse? initialRefundQueue;
  final CoachOperatorChangeQueueResponse? initialChangeQueue;
  final CoachOperatorReconciliationResponse? initialReconciliation;
  final CoachOperatorSettlementStatementsResponse? initialSettlementStatements;
  final CoachOperatorPayoutRunsResponse? initialPayoutRuns;
  final CoachOperatorPayoutReconciliationResponse? initialPayoutReconciliation;
  final CoachOperatorFeedHealthResponse? initialOperatorFeedHealth;
  final CoachOperatorCatalogImportConfigResponse? initialCatalogImportConfig;
  final CoachOperatorCatalogImportSourcesResponse? initialCatalogImportSources;
  final CoachOperatorCatalogSourceArtifactsResponse?
      initialCatalogSourceArtifacts;
  final CoachOperatorCatalogImportRunsResponse? initialCatalogImportRuns;
  final CoachOperatorPayoutImportsResponse? initialPayoutImports;
  final CoachOperatorPayoutImportPreviewsResponse? initialPayoutImportPreviews;
  final CoachOperatorPayoutImportBatchesResponse? initialPayoutImportBatches;
  final CoachOperatorPayoutImportProfilesResponse? initialPayoutImportProfiles;
  final Future<CoachPickedPayoutImportFile?> Function()?
      pickPayoutImportFileOverride;
  final Future<CoachPickedCatalogImportFile?> Function()?
      pickCatalogImportFileOverride;
  final Future<CoachPayoutImportPreviewHistoryFilterPreferences> Function()?
      loadPreviewHistoryFilterPreferencesOverride;
  final Future<void> Function(
    CoachPayoutImportPreviewHistoryFilterPreferences preferences,
  )? savePreviewHistoryFilterPreferencesOverride;
  final Future<void> Function()? clearPreviewHistoryFilterPreferencesOverride;
  final Future<CoachPayoutImportBatchFilterPreferences> Function()?
      loadPayoutImportBatchFilterPreferencesOverride;
  final Future<void> Function(
    CoachPayoutImportBatchFilterPreferences preferences,
  )? savePayoutImportBatchFilterPreferencesOverride;
  final Future<void> Function()?
      clearPayoutImportBatchFilterPreferencesOverride;
  final Future<List<CoachPayoutImportBatchSavedView>> Function()?
      loadPayoutImportBatchSavedViewsOverride;
  final Future<List<CoachPayoutImportBatchSavedView>> Function(
    CoachPayoutImportBatchSavedView view,
  )? savePayoutImportBatchSavedViewOverride;
  final Future<List<CoachPayoutImportBatchSavedView>> Function(
    String viewId,
  )? deletePayoutImportBatchSavedViewOverride;
  final Future<CoachCatalogImportRunFilterPreferences> Function()?
      loadCatalogImportRunFilterPreferencesOverride;
  final Future<void> Function(
    CoachCatalogImportRunFilterPreferences preferences,
  )? saveCatalogImportRunFilterPreferencesOverride;
  final Future<void> Function()? clearCatalogImportRunFilterPreferencesOverride;
  final Future<CoachCatalogImportRunIssueFilterPreferences> Function()?
      loadCatalogImportRunIssueFilterPreferencesOverride;
  final Future<void> Function(
    CoachCatalogImportRunIssueFilterPreferences preferences,
  )? saveCatalogImportRunIssueFilterPreferencesOverride;
  final Future<void> Function()?
      clearCatalogImportRunIssueFilterPreferencesOverride;
  final Future<List<CoachCatalogImportRunIssueSavedView>> Function()?
      loadCatalogImportRunIssueSavedViewsOverride;
  final Future<List<CoachCatalogImportRunIssueSavedView>> Function(
    CoachCatalogImportRunIssueSavedView view,
  )? saveCatalogImportRunIssueSavedViewOverride;
  final Future<List<CoachCatalogImportRunIssueSavedView>> Function(
    String viewId,
  )? deleteCatalogImportRunIssueSavedViewOverride;
  final Future<List<CoachCatalogImportRunSavedView>> Function()?
      loadCatalogImportRunSavedViewsOverride;
  final Future<List<CoachCatalogImportRunSavedView>> Function(
    CoachCatalogImportRunSavedView view,
  )? saveCatalogImportRunSavedViewOverride;
  final Future<List<CoachCatalogImportRunSavedView>> Function(String viewId)?
      deleteCatalogImportRunSavedViewOverride;
  final Future<List<CoachPayoutImportPreviewHistorySavedView>> Function()?
      loadPreviewHistorySavedViewsOverride;
  final Future<List<CoachPayoutImportPreviewHistorySavedView>> Function(
    CoachPayoutImportPreviewHistorySavedView view,
  )? savePreviewHistorySavedViewOverride;
  final Future<List<CoachPayoutImportPreviewHistorySavedView>> Function(
    String viewId,
  )? deletePreviewHistorySavedViewOverride;
  final DateTime Function()? previewHistoryNowUtcOverride;

  const CoachOperatorConsolePage({
    super.key,
    required this.baseUrl,
    this.api,
    this.dashboardPolicyOverride,
    this.privilegeSnapshotOverride,
    this.initialRefundQueue,
    this.initialChangeQueue,
    this.initialReconciliation,
    this.initialSettlementStatements,
    this.initialPayoutRuns,
    this.initialPayoutReconciliation,
    this.initialOperatorFeedHealth,
    this.initialCatalogImportConfig,
    this.initialCatalogImportSources,
    this.initialCatalogSourceArtifacts,
    this.initialCatalogImportRuns,
    this.initialPayoutImports,
    this.initialPayoutImportPreviews,
    this.initialPayoutImportBatches,
    this.initialPayoutImportProfiles,
    this.pickPayoutImportFileOverride,
    this.pickCatalogImportFileOverride,
    this.loadPreviewHistoryFilterPreferencesOverride,
    this.savePreviewHistoryFilterPreferencesOverride,
    this.clearPreviewHistoryFilterPreferencesOverride,
    this.loadPayoutImportBatchFilterPreferencesOverride,
    this.savePayoutImportBatchFilterPreferencesOverride,
    this.clearPayoutImportBatchFilterPreferencesOverride,
    this.loadPayoutImportBatchSavedViewsOverride,
    this.savePayoutImportBatchSavedViewOverride,
    this.deletePayoutImportBatchSavedViewOverride,
    this.loadCatalogImportRunFilterPreferencesOverride,
    this.saveCatalogImportRunFilterPreferencesOverride,
    this.clearCatalogImportRunFilterPreferencesOverride,
    this.loadCatalogImportRunIssueFilterPreferencesOverride,
    this.saveCatalogImportRunIssueFilterPreferencesOverride,
    this.clearCatalogImportRunIssueFilterPreferencesOverride,
    this.loadCatalogImportRunIssueSavedViewsOverride,
    this.saveCatalogImportRunIssueSavedViewOverride,
    this.deleteCatalogImportRunIssueSavedViewOverride,
    this.loadCatalogImportRunSavedViewsOverride,
    this.saveCatalogImportRunSavedViewOverride,
    this.deleteCatalogImportRunSavedViewOverride,
    this.loadPreviewHistorySavedViewsOverride,
    this.savePreviewHistorySavedViewOverride,
    this.deletePreviewHistorySavedViewOverride,
    this.previewHistoryNowUtcOverride,
  });

  @override
  State<CoachOperatorConsolePage> createState() =>
      _CoachOperatorConsolePageState();
}

class _CoachOperatorConsolePageState extends State<CoachOperatorConsolePage>
    with SafeSetStateMixin<CoachOperatorConsolePage> {
  static const String _pageStorageStateIdentifier =
      'coach_operator_console_ui_state';
  static const String _workspaceAll = 'all';
  static const String _workspaceSupport = 'support';
  static const String _workspaceSettlements = 'settlements';
  static const String _workspacePayoutOps = 'payout_ops';
  static const String _workspaceSalesFeeds = 'sales_feeds';
  static const String _portalSectionToday = 'today';
  static const String _portalSectionTrips = 'trips';
  static const String _portalSectionSales = 'sales';
  static const String _portalSectionSettlements = 'settlements';
  static const String _portalSectionSupport = 'support';
  static const String _settlementsTrackAudit = 'audit';
  static const String _settlementsTrackExecution = 'execution';
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _refundSectionKey = GlobalKey(
    debugLabel: 'coachOpsRefundSection',
  );
  final GlobalKey _changeSectionKey = GlobalKey(
    debugLabel: 'coachOpsChangeSection',
  );
  final GlobalKey _settlementSectionKey = GlobalKey(
    debugLabel: 'coachOpsSettlementSection',
  );
  final GlobalKey _payoutRunsSectionKey = GlobalKey(
    debugLabel: 'coachOpsPayoutRunsSection',
  );
  final GlobalKey _payoutReconciliationSectionKey = GlobalKey(
    debugLabel: 'coachOpsPayoutReconciliationSection',
  );
  final GlobalKey _payoutImportsSectionKey = GlobalKey(
    debugLabel: 'coachOpsPayoutImportsSection',
  );
  final GlobalKey _feedHealthSectionKey = GlobalKey(
    debugLabel: 'coachOpsFeedHealthSection',
  );
  final GlobalKey _catalogImportSectionKey = GlobalKey(
    debugLabel: 'coachOpsCatalogImportSection',
  );
  final GlobalKey _payoutImportBatchesSectionKey = GlobalKey(
    debugLabel: 'coachOpsPayoutImportBatchesSection',
  );
  final GlobalKey _settlementsAuditSectionKey = GlobalKey(
    debugLabel: 'coachOpsSettlementsAuditSection',
  );
  final GlobalKey _settlementsExecutionSectionKey = GlobalKey(
    debugLabel: 'coachOpsSettlementsExecutionSection',
  );
  // Anchor for the "Today" portal home — first sliver of the console.
  // Used by the portal navigation rail/drawer to jump back to the top
  // of the long ListView without smuggling scroll-offset math through
  // every section's build.
  final GlobalKey _todaySectionKey = GlobalKey(
    debugLabel: 'coachOpsTodaySection',
  );

  bool _loadingPrivileges = true;
  bool _accessAllowed = false;
  bool _financeMutationsAllowed = false;
  bool _catalogImportMutationsAllowed = false;
  AccountPrivilegeSnapshot _privilegeSnapshot = AccountPrivilegeSnapshot.empty;
  bool _loadingQueues = false;
  String? _errorMessage;
  String? _refundGeneratedAtIso;
  String? _changeGeneratedAtIso;
  CoachOperatorReconciliationResponse? _reconciliation;
  CoachOperatorSettlementStatementsResponse? _settlementStatements;
  CoachOperatorPayoutRunsResponse? _payoutRuns;
  CoachOperatorPayoutReconciliationResponse? _payoutReconciliation;
  CoachOperatorFeedHealthResponse? _operatorFeedHealth;
  CoachOperatorCatalogImportConfigResponse? _catalogImportConfig;
  CoachOperatorCatalogImportSourcesResponse? _catalogImportSources;
  CoachOperatorCatalogSourceArtifactsResponse? _catalogSourceArtifacts;
  CoachOperatorCatalogImportRunsResponse? _catalogImportRuns;
  CoachOperatorPayoutImportsResponse? _payoutImports;
  CoachOperatorPayoutImportPreviewsResponse? _payoutImportPreviews;
  CoachOperatorPayoutImportPreviewsResponse? _payoutImportPreviewHistory;
  CoachOperatorPayoutImportBatchesResponse? _payoutImportBatches;
  CoachOperatorPayoutImportProfilesResponse? _payoutImportProfiles;
  List<CoachOperatorRefundQueueEntry> _refundRequests =
      const <CoachOperatorRefundQueueEntry>[];
  List<CoachOperatorChangeQueueEntry> _changeRequests =
      const <CoachOperatorChangeQueueEntry>[];
  final Set<String> _reviewingRefundIds = <String>{};
  final Set<String> _reviewingChangeIds = <String>{};
  final Set<String> _creatingPayoutStatementIds = <String>{};
  final Set<String> _markingPaidRunIds = <String>{};
  final Set<String> _creatingExportKeys = <String>{};
  final Set<String> _creatingImportKeys = <String>{};
  final Set<String> _invalidatingPreviewTokens = <String>{};
  CoachOperatorPayoutImportBatchMutationResult? _latestPayoutImportBatchResult;
  bool _loadingPayoutImportPreviewHistory = false;
  bool _loadingMorePayoutImportPreviewHistory = false;
  bool _loadingMoreSettlementStatements = false;
  bool _loadingMorePayoutRuns = false;
  bool _loadingMorePayoutReconciliation = false;
  bool _loadingMoreCatalogSourceArtifacts = false;
  bool _loadingMoreCatalogImportRuns = false;
  final Set<String> _loadingCatalogImportRunDetailIds = <String>{};
  final Set<String> _loadingCatalogSourceArtifactDetailIds = <String>{};
  bool _savingCatalogImportConfig = false;
  bool _uploadingCatalogImportSource = false;
  bool _runningCatalogImport = false;
  bool _loadingMorePayoutImports = false;
  bool _loadingMorePayoutImportBatches = false;
  String _selectedCatalogImportRunStatusFilter = 'all';
  String _selectedCatalogImportRunReplayScopeFilter = 'all';
  String _selectedCatalogImportRunIssueSeverityFilter = 'all';
  String _selectedCatalogImportRunIssueStageFilter = 'all';
  String? _payoutImportPreviewHistoryErrorMessage;
  final TextEditingController _catalogImportFeedLocatorController =
      TextEditingController();
  final TextEditingController _catalogImportRunSavedViewNameController =
      TextEditingController();
  String _catalogImportRunSavedViewVisibilityScope = 'personal';
  String _catalogImportRunSavedViewOperatorIdScope = 'all';
  String _catalogImportRunSavedViewsVisibilityFilter = 'all';
  String _catalogImportRunSavedViewsOwnerAccountIdFilter = 'all';
  String _catalogImportRunSavedViewsOperatorIdFilter = 'all';
  CoachPickedCatalogImportFile? _selectedCatalogImportFile;
  final TextEditingController _payoutImportReportNameController =
      TextEditingController(text: 'bank_report_2026w15.csv');
  final TextEditingController _payoutImportReportBodyController =
      TextEditingController(text: _defaultCoachPayoutImportBatchReportBody());
  final TextEditingController _payoutImportPreviewFromCreatedAtController =
      TextEditingController();
  final TextEditingController _payoutImportPreviewToCreatedAtController =
      TextEditingController();
  final TextEditingController _payoutImportPreviewSavedViewNameController =
      TextEditingController();
  final TextEditingController _payoutImportBatchSavedViewNameController =
      TextEditingController();
  String _payoutImportPreviewSavedViewVisibilityScope = 'personal';
  String _payoutImportBatchSavedViewVisibilityScope = 'personal';
  String _payoutImportPreviewSavedViewsVisibilityFilter = 'all';
  String _payoutImportBatchSavedViewsVisibilityFilter = 'all';
  String _payoutImportPreviewSavedViewsOwnerAccountIdFilter = 'all';
  String _payoutImportBatchSavedViewsOwnerAccountIdFilter = 'all';
  String _payoutImportPreviewSavedViewsOperatorIdFilter = 'all';
  String _payoutImportBatchSavedViewsOperatorIdFilter = 'all';
  CoachPickedPayoutImportFile? _selectedPayoutImportFile;
  bool _creatingImportBatch = false;
  bool _previewingImportBatch = false;
  bool _loadingReworkSeed = false;
  String? _loadedReworkSeedBody;
  String _selectedPayoutImportSource = 'bank_report';
  String? _selectedPayoutImportReworkOfBatchId;
  String _selectedPayoutImportPreviewStatusFilter = 'all';
  String _selectedPayoutImportPreviewOperatorIdFilter = 'all';
  String _selectedPayoutImportBatchOperatorIdFilter = 'all';
  List<CoachCatalogImportRunSavedView> _catalogImportRunSavedViews =
      const <CoachCatalogImportRunSavedView>[];
  Set<String> _catalogImportRunSavedViewPinnedIds = const <String>{};
  Map<String, String> _catalogImportRunSavedViewUsedAtById =
      const <String, String>{};
  Set<String> _catalogImportRunIssueSavedViewPinnedIds = const <String>{};
  Map<String, String> _catalogImportRunIssueSavedViewUsedAtById =
      const <String, String>{};
  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _catalogImportRunSavedViewOwners =
      const <CoachCatalogImportRunSavedViewOwnerSummary>[];
  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _catalogImportRunSavedViewOperators =
      const <CoachCatalogImportRunSavedViewOperatorSummary>[];
  List<CoachPayoutImportPreviewHistorySavedView>
      _payoutImportPreviewSavedViews =
      const <CoachPayoutImportPreviewHistorySavedView>[];
  Set<String> _payoutImportPreviewSavedViewPinnedIds = const <String>{};
  Map<String, String> _payoutImportPreviewSavedViewUsedAtById =
      const <String, String>{};
  List<CoachPayoutImportBatchSavedView> _payoutImportBatchSavedViews =
      const <CoachPayoutImportBatchSavedView>[];
  Set<String> _payoutImportBatchSavedViewPinnedIds = const <String>{};
  Map<String, String> _payoutImportBatchSavedViewUsedAtById =
      const <String, String>{};
  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _payoutImportPreviewSavedViewOwners =
      const <CoachCatalogImportRunSavedViewOwnerSummary>[];
  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _payoutImportBatchSavedViewOwners =
      const <CoachCatalogImportRunSavedViewOwnerSummary>[];
  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _payoutImportPreviewSavedViewOperators =
      const <CoachCatalogImportRunSavedViewOperatorSummary>[];
  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _payoutImportBatchSavedViewOperators =
      const <CoachCatalogImportRunSavedViewOperatorSummary>[];
  String? _appliedPayoutImportPreviewStatusFilter;
  String? _appliedPayoutImportPreviewFromCreatedAtIso;
  String? _appliedPayoutImportPreviewToCreatedAtIso;
  bool _savingCatalogImportRunSavedView = false;
  bool _savingPayoutImportPreviewSavedView = false;
  bool _savingPayoutImportBatchSavedView = false;
  final Set<String> _deletingCatalogImportRunSavedViewIds = <String>{};
  final Set<String> _updatingCatalogImportRunSavedViewDefaultIds = <String>{};
  final Set<String> _deletingPayoutImportPreviewSavedViewIds = <String>{};
  final Set<String> _updatingPayoutImportPreviewSavedViewDefaultIds =
      <String>{};
  final Set<String> _deletingPayoutImportBatchSavedViewIds = <String>{};
  final Set<String> _updatingPayoutImportBatchSavedViewDefaultIds = <String>{};
  bool _restoredStoredState = false;
  final Set<String> _collapsedWorkspaces = <String>{};
  String _selectedWorkspace = _workspaceAll;
  String _selectedPortalSection = _portalSectionToday;
  String _selectedSettlementsTrack = _settlementsTrackAudit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredStoredState) {
      return;
    }
    _restoredStoredState = true;
    final stored = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _pageStorageStateIdentifier);
    if (stored is! Map) {
      return;
    }
    final selectedWorkspace = stored['selectedWorkspace'];
    final selectedPortalSection = stored['selectedPortalSection'];
    final selectedSettlementsTrack = stored['selectedSettlementsTrack'];
    const knownWorkspaces = <String>{
      _workspaceAll,
      _workspaceSupport,
      _workspaceSettlements,
      _workspacePayoutOps,
      _workspaceSalesFeeds,
    };
    const knownPortalSections = <String>{
      _portalSectionToday,
      _portalSectionTrips,
      _portalSectionSales,
      _portalSectionSettlements,
      _portalSectionSupport,
    };
    const knownSettlementsTracks = <String>{
      _settlementsTrackAudit,
      _settlementsTrackExecution,
    };
    if (selectedWorkspace is String &&
        knownWorkspaces.contains(selectedWorkspace)) {
      _selectedWorkspace = selectedWorkspace;
    }
    if (selectedPortalSection is String &&
        knownPortalSections.contains(selectedPortalSection)) {
      _selectedPortalSection = selectedPortalSection;
    }
    if (selectedSettlementsTrack is String &&
        knownSettlementsTracks.contains(selectedSettlementsTrack)) {
      _selectedSettlementsTrack = selectedSettlementsTrack;
    }
    final collapsedWorkspaces = stored['collapsedWorkspaces'];
    if (collapsedWorkspaces is List) {
      _collapsedWorkspaces
        ..clear()
        ..addAll(
          collapsedWorkspaces
              .map((entry) => entry.toString().trim())
              .where((entry) => knownWorkspaces.contains(entry))
              .where((entry) => entry != _workspaceAll),
        );
    }
  }

  DateTime _previewHistoryNowUtc() {
    final override = widget.previewHistoryNowUtcOverride;
    if (override != null) {
      return override().toUtc();
    }
    return DateTime.now().toUtc();
  }

  Future<CoachPayoutImportPreviewHistoryFilterPreferences>
      _loadPersistedPayoutImportPreviewHistoryFilterPreferences() async {
    try {
      final override = widget.loadPreviewHistoryFilterPreferencesOverride;
      if (override != null) {
        return override();
      }
      return loadCoachPayoutImportPreviewHistoryFilterPreferences(
        baseUrl: widget.baseUrl,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => CoachPayoutImportPreviewHistoryFilterPreferences.empty,
      );
    } catch (_) {
      return CoachPayoutImportPreviewHistoryFilterPreferences.empty;
    }
  }

  Future<void> _savePersistedPayoutImportPreviewHistoryFilterPreferences(
    CoachPayoutImportPreviewHistoryFilterPreferences preferences,
  ) async {
    final override = widget.savePreviewHistoryFilterPreferencesOverride;
    if (override != null) {
      await override(preferences);
      return;
    }
    await saveCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: widget.baseUrl,
      preferences: preferences,
    );
  }

  Future<void>
      _clearPersistedPayoutImportPreviewHistoryFilterPreferences() async {
    final override = widget.clearPreviewHistoryFilterPreferencesOverride;
    if (override != null) {
      await override();
      return;
    }
    await clearCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: widget.baseUrl,
    );
  }

  Future<CoachPayoutImportBatchFilterPreferences>
      _loadPersistedPayoutImportBatchFilterPreferences() async {
    try {
      final override = widget.loadPayoutImportBatchFilterPreferencesOverride;
      if (override != null) {
        return override();
      }
      return loadCoachPayoutImportBatchFilterPreferences(
        baseUrl: widget.baseUrl,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => CoachPayoutImportBatchFilterPreferences.empty,
      );
    } catch (_) {
      return CoachPayoutImportBatchFilterPreferences.empty;
    }
  }

  Future<void> _savePersistedPayoutImportBatchFilterPreferences(
    CoachPayoutImportBatchFilterPreferences preferences,
  ) async {
    final override = widget.savePayoutImportBatchFilterPreferencesOverride;
    if (override != null) {
      await override(preferences);
      return;
    }
    await saveCoachPayoutImportBatchFilterPreferences(
      baseUrl: widget.baseUrl,
      preferences: preferences,
    );
  }

  Future<void> _clearPersistedPayoutImportBatchFilterPreferences() async {
    final override = widget.clearPayoutImportBatchFilterPreferencesOverride;
    if (override != null) {
      await override();
      return;
    }
    await clearCoachPayoutImportBatchFilterPreferences(
      baseUrl: widget.baseUrl,
    );
  }

  Future<Map<String, String>> _loadPersistedSavedViewUsage(
    String collectionKey,
  ) async {
    try {
      return loadCoachSavedViewUsageMap(
        baseUrl: widget.baseUrl,
        collectionKey: collectionKey,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => const <String, String>{},
      );
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<Set<String>> _loadPersistedSavedViewPins(
    String collectionKey,
  ) async {
    try {
      return loadCoachSavedViewPinnedIds(
        baseUrl: widget.baseUrl,
        collectionKey: collectionKey,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => const <String>{},
      );
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> _togglePersistedSavedViewPin({
    required String collectionKey,
    required String viewId,
    required bool pinned,
    required Set<String> currentPins,
    required void Function(Set<String> value) assign,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      return;
    }
    final nextPins = <String>{...currentPins};
    if (pinned) {
      nextPins.add(normalizedViewId);
    } else {
      nextPins.remove(normalizedViewId);
    }
    if (mounted) {
      setState(() {
        assign(nextPins);
      });
    }
    try {
      final persisted = await setCoachSavedViewPinned(
        baseUrl: widget.baseUrl,
        collectionKey: collectionKey,
        viewId: normalizedViewId,
        pinned: pinned,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => nextPins,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        assign(persisted);
      });
    } catch (_) {}
  }

  Future<void> _recordPersistedSavedViewUsage({
    required String collectionKey,
    required String viewId,
    required Map<String, String> currentUsage,
    required void Function(Map<String, String> value) assign,
    String? usedAtIso,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      return;
    }
    final normalizedUsedAtIso =
        usedAtIso ?? _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc());
    final nextUsage = <String, String>{
      ...currentUsage,
      normalizedViewId: normalizedUsedAtIso,
    };
    if (mounted) {
      setState(() {
        assign(nextUsage);
      });
    }
    try {
      final api = widget.api;
      if (api != null) {
        try {
          final remoteUsedAtIso = await (() {
            switch (collectionKey) {
              case _catalogImportRunSavedViewUsageCollectionKey:
                return _api.markOperatorCatalogImportRunSavedViewUsed(
                  normalizedViewId,
                  usedAtIso: normalizedUsedAtIso,
                );
              case _catalogImportRunIssueSavedViewUsageCollectionKey:
                return _api.markOperatorCatalogImportRunIssueSavedViewUsed(
                  normalizedViewId,
                  usedAtIso: normalizedUsedAtIso,
                );
              case _payoutImportPreviewSavedViewUsageCollectionKey:
                return _api.markOperatorPayoutImportPreviewSavedViewUsed(
                  normalizedViewId,
                  usedAtIso: normalizedUsedAtIso,
                );
              case _payoutImportBatchSavedViewUsageCollectionKey:
                return _api.markOperatorPayoutImportBatchSavedViewUsed(
                  normalizedViewId,
                  usedAtIso: normalizedUsedAtIso,
                );
              default:
                return Future<String?>.value(normalizedUsedAtIso);
            }
          }())
              .timeout(
            const Duration(milliseconds: 400),
            onTimeout: () => normalizedUsedAtIso,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            assign(<String, String>{
              ...nextUsage,
              normalizedViewId: (remoteUsedAtIso ?? '').trim().isEmpty
                  ? normalizedUsedAtIso
                  : remoteUsedAtIso!.trim(),
            });
          });
          return;
        } catch (_) {}
      }
      final persisted = await markCoachSavedViewUsed(
        baseUrl: widget.baseUrl,
        collectionKey: collectionKey,
        viewId: normalizedViewId,
        usedAtIso: normalizedUsedAtIso,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => nextUsage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        assign(persisted);
      });
    } catch (_) {}
  }

  Future<void> _toggleCatalogImportRunSavedViewFavorite({
    required String viewId,
    required bool favorite,
  }) async {
    if (widget.api != null) {
      try {
        final savedViews = await _api
            .toggleOperatorCatalogImportRunSavedViewFavorite(
              viewId,
              favorite: favorite,
            )
            .timeout(
              const Duration(milliseconds: 400),
              onTimeout: () => _catalogImportRunSavedViews,
            );
        if (!mounted) {
          return;
        }
        setState(() {
          _catalogImportRunSavedViews = savedViews;
          _catalogImportRunSavedViewPinnedIds =
              _catalogImportRunSavedViewFavoriteIds(savedViews);
          _catalogImportRunSavedViewUsedAtById =
              _catalogImportRunSavedViewUsageMap(savedViews);
        });
        return;
      } catch (_) {}
    }
    await _togglePersistedSavedViewPin(
      collectionKey: _catalogImportRunSavedViewUsageCollectionKey,
      viewId: viewId,
      pinned: favorite,
      currentPins: _catalogImportRunSavedViewPinnedIds,
      assign: (value) => _catalogImportRunSavedViewPinnedIds = value,
    );
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      _toggleCatalogImportRunIssueSavedViewFavorite({
    required List<CoachCatalogImportRunIssueSavedView> currentViews,
    required String viewId,
    required bool favorite,
  }) async {
    if (widget.api != null) {
      try {
        final savedViews = await _api
            .toggleOperatorCatalogImportRunIssueSavedViewFavorite(
              viewId,
              favorite: favorite,
            )
            .timeout(
              const Duration(milliseconds: 400),
              onTimeout: () => currentViews,
            );
        if (!mounted) {
          return savedViews;
        }
        setState(() {
          _catalogImportRunIssueSavedViewPinnedIds =
              _catalogImportRunIssueSavedViewFavoriteIds(savedViews);
          _catalogImportRunIssueSavedViewUsedAtById =
              _catalogImportRunIssueSavedViewUsageMap(savedViews);
        });
        return savedViews;
      } catch (_) {}
    }
    await _togglePersistedSavedViewPin(
      collectionKey: _catalogImportRunIssueSavedViewUsageCollectionKey,
      viewId: viewId,
      pinned: favorite,
      currentPins: _catalogImportRunIssueSavedViewPinnedIds,
      assign: (value) => _catalogImportRunIssueSavedViewPinnedIds = value,
    );
    return currentViews;
  }

  Future<void> _togglePayoutImportPreviewSavedViewFavorite({
    required String viewId,
    required bool favorite,
  }) async {
    if (widget.api != null) {
      try {
        final savedViews = await _api
            .toggleOperatorPayoutImportPreviewSavedViewFavorite(
              viewId,
              favorite: favorite,
            )
            .timeout(
              const Duration(milliseconds: 400),
              onTimeout: () => _payoutImportPreviewSavedViews,
            );
        if (!mounted) {
          return;
        }
        setState(() {
          _payoutImportPreviewSavedViews = savedViews;
          _payoutImportPreviewSavedViewPinnedIds =
              _payoutImportPreviewSavedViewFavoriteIds(savedViews);
          _payoutImportPreviewSavedViewUsedAtById =
              _payoutImportPreviewSavedViewUsageMap(savedViews);
        });
        return;
      } catch (_) {}
    }
    await _togglePersistedSavedViewPin(
      collectionKey: _payoutImportPreviewSavedViewUsageCollectionKey,
      viewId: viewId,
      pinned: favorite,
      currentPins: _payoutImportPreviewSavedViewPinnedIds,
      assign: (value) => _payoutImportPreviewSavedViewPinnedIds = value,
    );
  }

  Future<void> _togglePayoutImportBatchSavedViewFavorite({
    required String viewId,
    required bool favorite,
  }) async {
    if (widget.api != null) {
      try {
        final savedViews = await _api
            .toggleOperatorPayoutImportBatchSavedViewFavorite(
              viewId,
              favorite: favorite,
            )
            .timeout(
              const Duration(milliseconds: 400),
              onTimeout: () => _payoutImportBatchSavedViews,
            );
        if (!mounted) {
          return;
        }
        setState(() {
          _payoutImportBatchSavedViews = savedViews;
          _payoutImportBatchSavedViewPinnedIds =
              _payoutImportBatchSavedViewFavoriteIds(savedViews);
          _payoutImportBatchSavedViewUsedAtById =
              _payoutImportBatchSavedViewUsageMap(savedViews);
        });
        return;
      } catch (_) {}
    }
    await _togglePersistedSavedViewPin(
      collectionKey: _payoutImportBatchSavedViewUsageCollectionKey,
      viewId: viewId,
      pinned: favorite,
      currentPins: _payoutImportBatchSavedViewPinnedIds,
      assign: (value) => _payoutImportBatchSavedViewPinnedIds = value,
    );
  }

  Future<List<CoachPayoutImportBatchSavedView>>
      _loadPersistedPayoutImportBatchSavedViews() async {
    try {
      final override = widget.loadPayoutImportBatchSavedViewsOverride;
      if (override != null) {
        return override();
      }
      final api = widget.api;
      if (api != null) {
        try {
          return await api.operatorPayoutImportBatchSavedViews().timeout(
                const Duration(milliseconds: 400),
                onTimeout: () => const <CoachPayoutImportBatchSavedView>[],
              );
        } catch (_) {}
      }
      return loadCoachPayoutImportBatchSavedViews(
        baseUrl: widget.baseUrl,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => const <CoachPayoutImportBatchSavedView>[],
      );
    } catch (_) {
      return const <CoachPayoutImportBatchSavedView>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      _loadPersistedPayoutImportBatchSavedViewOwners() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api.operatorPayoutImportBatchSavedViewOwners().timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOwnerSummary>[],
            );
      }
      final sharedViews = await _loadPersistedPayoutImportBatchSavedViews();
      return _payoutImportBatchSavedViewOwnerSummariesFromViews(
        sharedViews
            .where((entry) => entry.visibilityScope == 'shared_ops')
            .toList(growable: false),
      );
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOwnerSummary>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      _loadPersistedPayoutImportBatchSavedViewOperators() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api
            .operatorPayoutImportBatchSavedViewOperators()
            .then(_filterCatalogSavedViewOperatorSummariesByPrivilegeScope)
            .timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOperatorSummary>[],
            );
      }
      final sharedViews = await _loadPersistedPayoutImportBatchSavedViews();
      return _payoutImportBatchSavedViewOperatorSummariesFromViews(
        sharedViews
            .where((entry) => entry.visibilityScope == 'shared_ops')
            .toList(growable: false),
      );
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOperatorSummary>[];
    }
  }

  Future<List<CoachPayoutImportBatchSavedView>>
      _savePersistedPayoutImportBatchSavedView(
    CoachPayoutImportBatchSavedView view,
  ) async {
    try {
      final override = widget.savePayoutImportBatchSavedViewOverride;
      if (override != null) {
        return override(view);
      }
      final api = widget.api;
      if (api != null) {
        try {
          return await api
              .upsertOperatorPayoutImportBatchSavedView(view)
              .timeout(
                const Duration(milliseconds: 400),
                onTimeout: () => _payoutImportBatchSavedViews,
              );
        } catch (_) {}
      }
      return upsertCoachPayoutImportBatchSavedView(
        baseUrl: widget.baseUrl,
        view: view,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => _payoutImportBatchSavedViews,
      );
    } catch (_) {
      return _payoutImportBatchSavedViews;
    }
  }

  Future<List<CoachPayoutImportBatchSavedView>>
      _deletePersistedPayoutImportBatchSavedView(
    String viewId,
  ) async {
    try {
      final override = widget.deletePayoutImportBatchSavedViewOverride;
      if (override != null) {
        return override(viewId);
      }
      final api = widget.api;
      if (api != null) {
        try {
          return await api
              .deleteOperatorPayoutImportBatchSavedView(viewId)
              .timeout(
                const Duration(milliseconds: 400),
                onTimeout: () => _payoutImportBatchSavedViews,
              );
        } catch (_) {}
      }
      return deleteCoachPayoutImportBatchSavedView(
        baseUrl: widget.baseUrl,
        viewId: viewId,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => _payoutImportBatchSavedViews,
      );
    } catch (_) {
      return _payoutImportBatchSavedViews;
    }
  }

  Future<CoachCatalogImportRunFilterPreferences>
      _loadPersistedCatalogImportRunFilterPreferences() async {
    try {
      final override = widget.loadCatalogImportRunFilterPreferencesOverride;
      if (override != null) {
        return override();
      }
      return loadCoachCatalogImportRunFilterPreferences(
        baseUrl: widget.baseUrl,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => CoachCatalogImportRunFilterPreferences.empty,
      );
    } catch (_) {
      return CoachCatalogImportRunFilterPreferences.empty;
    }
  }

  Future<void> _savePersistedCatalogImportRunFilterPreferences(
    CoachCatalogImportRunFilterPreferences preferences,
  ) async {
    final override = widget.saveCatalogImportRunFilterPreferencesOverride;
    if (override != null) {
      await override(preferences);
      return;
    }
    await saveCoachCatalogImportRunFilterPreferences(
      baseUrl: widget.baseUrl,
      preferences: preferences,
    ).timeout(
      const Duration(milliseconds: 250),
      onTimeout: () async {},
    );
  }

  Future<void> _clearPersistedCatalogImportRunFilterPreferences() async {
    final override = widget.clearCatalogImportRunFilterPreferencesOverride;
    if (override != null) {
      await override();
      return;
    }
    await clearCoachCatalogImportRunFilterPreferences(
      baseUrl: widget.baseUrl,
    ).timeout(
      const Duration(milliseconds: 250),
      onTimeout: () async {},
    );
  }

  Future<CoachCatalogImportRunIssueFilterPreferences>
      _loadPersistedCatalogImportRunIssueFilterPreferences() async {
    try {
      final override =
          widget.loadCatalogImportRunIssueFilterPreferencesOverride;
      final future = override != null
          ? override()
          : loadCoachCatalogImportRunIssueFilterPreferences(
              baseUrl: widget.baseUrl,
            );
      return future.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => CoachCatalogImportRunIssueFilterPreferences.empty,
      );
    } catch (_) {
      return CoachCatalogImportRunIssueFilterPreferences.empty;
    }
  }

  Future<void> _savePersistedCatalogImportRunIssueFilterPreferences(
    CoachCatalogImportRunIssueFilterPreferences preferences,
  ) async {
    final override = widget.saveCatalogImportRunIssueFilterPreferencesOverride;
    final future = override != null
        ? override(preferences)
        : saveCoachCatalogImportRunIssueFilterPreferences(
            baseUrl: widget.baseUrl,
            preferences: preferences,
          );
    await future.timeout(
      const Duration(milliseconds: 250),
      onTimeout: () async {},
    );
  }

  Future<void> _clearPersistedCatalogImportRunIssueFilterPreferences() async {
    final override = widget.clearCatalogImportRunIssueFilterPreferencesOverride;
    final future = override != null
        ? override()
        : clearCoachCatalogImportRunIssueFilterPreferences(
            baseUrl: widget.baseUrl,
          );
    await future.timeout(
      const Duration(milliseconds: 250),
      onTimeout: () async {},
    );
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      _loadPersistedCatalogImportRunIssueSavedViews({
    String visibilityScope = 'all',
    String ownerAccountId = 'all',
    String operatorId = 'all',
  }) async {
    try {
      final normalizedScope =
          _normalizeCatalogSavedViewVisibilityFilter(visibilityScope);
      final normalizedOwnerAccountId = normalizedScope == 'shared_ops'
          ? _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId)
          : 'all';
      final normalizedOperatorId = normalizedScope == 'shared_ops'
          ? _normalizeCatalogSavedViewOperatorIdFilter(operatorId)
          : 'all';
      final override = widget.loadCatalogImportRunIssueSavedViewsOverride;
      final future = override != null
          ? override().then(
              (views) =>
                  _filterCatalogImportRunIssueSavedViewsByPrivilegeOperatorScope(
                _filterCatalogImportRunIssueSavedViewsByOperatorId(
                  _filterCatalogImportRunIssueSavedViewsByOwnerAccountId(
                    _filterCatalogImportRunIssueSavedViewsByVisibilityScope(
                      views,
                      normalizedScope,
                    ),
                    normalizedOwnerAccountId,
                  ),
                  normalizedOperatorId,
                ),
              ),
            )
          : ((widget.api != null)
              ? _api
                  .operatorCatalogImportRunIssueSavedViews(
                    visibilityScope: normalizedScope,
                    ownerAccountId: normalizedOwnerAccountId == 'all'
                        ? null
                        : normalizedOwnerAccountId,
                    operatorId: normalizedOperatorId == 'all'
                        ? null
                        : normalizedOperatorId,
                  )
                  .then(
                    _filterCatalogImportRunIssueSavedViewsByPrivilegeOperatorScope,
                  )
              : loadCoachCatalogImportRunIssueSavedViews(
                  baseUrl: widget.baseUrl,
                ).then(
                  (views) =>
                      _filterCatalogImportRunIssueSavedViewsByPrivilegeOperatorScope(
                    _filterCatalogImportRunIssueSavedViewsByOperatorId(
                      _filterCatalogImportRunIssueSavedViewsByOwnerAccountId(
                        _filterCatalogImportRunIssueSavedViewsByVisibilityScope(
                          views,
                          normalizedScope,
                        ),
                        normalizedOwnerAccountId,
                      ),
                      normalizedOperatorId,
                    ),
                  ),
                ));
      return future.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => const <CoachCatalogImportRunIssueSavedView>[],
      );
    } catch (_) {
      return const <CoachCatalogImportRunIssueSavedView>[];
    }
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      _savePersistedCatalogImportRunIssueSavedView(
    CoachCatalogImportRunIssueSavedView view,
  ) async {
    try {
      final override = widget.saveCatalogImportRunIssueSavedViewOverride;
      final future = override != null
          ? override(view)
          : ((widget.api != null)
              ? _api.upsertOperatorCatalogImportRunIssueSavedView(view)
              : upsertCoachCatalogImportRunIssueSavedView(
                  baseUrl: widget.baseUrl,
                  view: view,
                ));
      return future.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => const <CoachCatalogImportRunIssueSavedView>[],
      );
    } catch (_) {
      return const <CoachCatalogImportRunIssueSavedView>[];
    }
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      _deletePersistedCatalogImportRunIssueSavedView(
    String viewId,
  ) async {
    try {
      final override = widget.deleteCatalogImportRunIssueSavedViewOverride;
      final future = override != null
          ? override(viewId)
          : ((widget.api != null)
              ? _api.deleteOperatorCatalogImportRunIssueSavedView(viewId)
              : deleteCoachCatalogImportRunIssueSavedView(
                  baseUrl: widget.baseUrl,
                  viewId: viewId,
                ));
      return future.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => const <CoachCatalogImportRunIssueSavedView>[],
      );
    } catch (_) {
      return const <CoachCatalogImportRunIssueSavedView>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedView>>
      _loadPersistedCatalogImportRunSavedViews({
    String visibilityScope = 'all',
    String ownerAccountId = 'all',
    String operatorId = 'all',
  }) async {
    try {
      final normalizedScope =
          _normalizeCatalogSavedViewVisibilityFilter(visibilityScope);
      final normalizedOwnerAccountId = normalizedScope == 'shared_ops'
          ? _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId)
          : 'all';
      final normalizedOperatorId = normalizedScope == 'shared_ops'
          ? _normalizeCatalogSavedViewOperatorIdFilter(operatorId)
          : 'all';
      final override = widget.loadCatalogImportRunSavedViewsOverride;
      if (override != null) {
        return override().then(
          (views) => _filterCatalogImportRunSavedViewsByPrivilegeOperatorScope(
            _filterCatalogImportRunSavedViewsByOperatorId(
              _filterCatalogImportRunSavedViewsByOwnerAccountId(
                _filterCatalogImportRunSavedViewsByVisibilityScope(
                  views,
                  normalizedScope,
                ),
                normalizedOwnerAccountId,
              ),
              normalizedOperatorId,
            ),
          ),
        );
      }
      final api = widget.api;
      if (api == null) {
        return const <CoachCatalogImportRunSavedView>[];
      }
      return api
          .operatorCatalogImportRunSavedViews(
            visibilityScope: normalizedScope,
            ownerAccountId: normalizedOwnerAccountId == 'all'
                ? null
                : normalizedOwnerAccountId,
            operatorId:
                normalizedOperatorId == 'all' ? null : normalizedOperatorId,
          )
          .then(_filterCatalogImportRunSavedViewsByPrivilegeOperatorScope)
          .timeout(
            const Duration(milliseconds: 250),
            onTimeout: () => const <CoachCatalogImportRunSavedView>[],
          );
    } catch (_) {
      return const <CoachCatalogImportRunSavedView>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      _loadPersistedCatalogImportRunSavedViewOwners() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api.operatorCatalogImportRunSavedViewOwners().timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOwnerSummary>[],
            );
      }
      final sharedViews = await _loadPersistedCatalogImportRunSavedViews(
        visibilityScope: 'shared_ops',
      );
      return _catalogImportRunSavedViewOwnerSummariesFromViews(sharedViews);
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOwnerSummary>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      _loadPersistedCatalogImportRunSavedViewOperators() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api
            .operatorCatalogImportRunSavedViewOperators()
            .then(_filterCatalogSavedViewOperatorSummariesByPrivilegeScope)
            .timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOperatorSummary>[],
            );
      }
      final sharedViews = await _loadPersistedCatalogImportRunSavedViews(
        visibilityScope: 'shared_ops',
      );
      return _catalogImportRunSavedViewOperatorSummariesFromViews(sharedViews);
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOperatorSummary>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      _loadPersistedCatalogImportRunIssueSavedViewOwners() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api.operatorCatalogImportRunIssueSavedViewOwners().timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOwnerSummary>[],
            );
      }
      final sharedViews = await _loadPersistedCatalogImportRunIssueSavedViews(
        visibilityScope: 'shared_ops',
      );
      return _catalogImportRunIssueSavedViewOwnerSummariesFromViews(
          sharedViews);
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOwnerSummary>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      _loadPersistedCatalogImportRunIssueSavedViewOperators() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api
            .operatorCatalogImportRunIssueSavedViewOperators()
            .then(_filterCatalogSavedViewOperatorSummariesByPrivilegeScope)
            .timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOperatorSummary>[],
            );
      }
      final sharedViews = await _loadPersistedCatalogImportRunIssueSavedViews(
        visibilityScope: 'shared_ops',
      );
      return _catalogImportRunIssueSavedViewOperatorSummariesFromViews(
        sharedViews,
      );
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOperatorSummary>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedView>>
      _savePersistedCatalogImportRunSavedView(
    CoachCatalogImportRunSavedView view,
  ) async {
    try {
      final override = widget.saveCatalogImportRunSavedViewOverride;
      if (override != null) {
        return override(view);
      }
      final api = widget.api;
      if (api == null) {
        return _catalogImportRunSavedViews;
      }
      return api.upsertOperatorCatalogImportRunSavedView(view).timeout(
            const Duration(milliseconds: 250),
            onTimeout: () => _catalogImportRunSavedViews,
          );
    } catch (_) {
      return _catalogImportRunSavedViews;
    }
  }

  Future<List<CoachCatalogImportRunSavedView>>
      _deletePersistedCatalogImportRunSavedView(
    String viewId,
  ) async {
    try {
      final override = widget.deleteCatalogImportRunSavedViewOverride;
      if (override != null) {
        return override(viewId);
      }
      final api = widget.api;
      if (api == null) {
        return _catalogImportRunSavedViews;
      }
      return api.deleteOperatorCatalogImportRunSavedView(viewId).timeout(
            const Duration(milliseconds: 250),
            onTimeout: () => _catalogImportRunSavedViews,
          );
    } catch (_) {
      return _catalogImportRunSavedViews;
    }
  }

  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      _loadPersistedPayoutImportPreviewHistorySavedViews() async {
    try {
      final override = widget.loadPreviewHistorySavedViewsOverride;
      if (override != null) {
        return override();
      }
      final api = widget.api;
      if (api != null) {
        try {
          return await api.operatorPayoutImportPreviewSavedViews().timeout(
                const Duration(milliseconds: 400),
                onTimeout: () =>
                    const <CoachPayoutImportPreviewHistorySavedView>[],
              );
        } catch (_) {}
      }
      return loadCoachPayoutImportPreviewHistorySavedViews(
        baseUrl: widget.baseUrl,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => const <CoachPayoutImportPreviewHistorySavedView>[],
      );
    } catch (_) {
      return const <CoachPayoutImportPreviewHistorySavedView>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      _loadPersistedPayoutImportPreviewSavedViewOwners() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api.operatorPayoutImportPreviewSavedViewOwners().timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOwnerSummary>[],
            );
      }
      final sharedViews =
          await _loadPersistedPayoutImportPreviewHistorySavedViews();
      return _payoutImportPreviewSavedViewOwnerSummariesFromViews(
        sharedViews
            .where((entry) => entry.visibilityScope == 'shared_ops')
            .toList(growable: false),
      );
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOwnerSummary>[];
    }
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      _loadPersistedPayoutImportPreviewSavedViewOperators() async {
    try {
      if (widget.api != null && !_hasRestrictedCoachOperatorScope) {
        return _api
            .operatorPayoutImportPreviewSavedViewOperators()
            .then(_filterCatalogSavedViewOperatorSummariesByPrivilegeScope)
            .timeout(
              const Duration(milliseconds: 250),
              onTimeout: () =>
                  const <CoachCatalogImportRunSavedViewOperatorSummary>[],
            );
      }
      final sharedViews =
          await _loadPersistedPayoutImportPreviewHistorySavedViews();
      return _payoutImportPreviewSavedViewOperatorSummariesFromViews(
        sharedViews
            .where((entry) => entry.visibilityScope == 'shared_ops')
            .toList(growable: false),
      );
    } catch (_) {
      return const <CoachCatalogImportRunSavedViewOperatorSummary>[];
    }
  }

  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      _savePersistedPayoutImportPreviewHistorySavedView(
    CoachPayoutImportPreviewHistorySavedView view,
  ) async {
    try {
      final override = widget.savePreviewHistorySavedViewOverride;
      if (override != null) {
        return override(view);
      }
      final api = widget.api;
      if (api != null) {
        try {
          return await api
              .upsertOperatorPayoutImportPreviewSavedView(view)
              .timeout(
                const Duration(milliseconds: 400),
                onTimeout: () => _payoutImportPreviewSavedViews,
              );
        } catch (_) {}
      }
      return upsertCoachPayoutImportPreviewHistorySavedView(
        baseUrl: widget.baseUrl,
        view: view,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => _payoutImportPreviewSavedViews,
      );
    } catch (_) {
      return _payoutImportPreviewSavedViews;
    }
  }

  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      _deletePersistedPayoutImportPreviewHistorySavedView(
    String viewId,
  ) async {
    try {
      final override = widget.deletePreviewHistorySavedViewOverride;
      if (override != null) {
        return override(viewId);
      }
      final api = widget.api;
      if (api != null) {
        try {
          return await api
              .deleteOperatorPayoutImportPreviewSavedView(viewId)
              .timeout(
                const Duration(milliseconds: 400),
                onTimeout: () => _payoutImportPreviewSavedViews,
              );
        } catch (_) {}
      }
      return deleteCoachPayoutImportPreviewHistorySavedView(
        baseUrl: widget.baseUrl,
        viewId: viewId,
      ).timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => _payoutImportPreviewSavedViews,
      );
    } catch (_) {
      return _payoutImportPreviewSavedViews;
    }
  }

  String _formatPreviewHistoryRfc3339Utc(DateTime value) {
    final utc = value.toUtc();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    String fourDigits(int part) => part.toString().padLeft(4, '0');
    return '${fourDigits(utc.year)}-${twoDigits(utc.month)}-${twoDigits(utc.day)}'
        'T${twoDigits(utc.hour)}:${twoDigits(utc.minute)}:${twoDigits(utc.second)}Z';
  }

  void _setPayoutImportPreviewDraftWindow({
    required DateTime fromCreatedAtUtc,
    required DateTime toCreatedAtUtc,
  }) {
    _payoutImportPreviewFromCreatedAtController.text =
        _formatPreviewHistoryRfc3339Utc(fromCreatedAtUtc);
    _payoutImportPreviewToCreatedAtController.text =
        _formatPreviewHistoryRfc3339Utc(toCreatedAtUtc);
  }

  void _applyPayoutImportPreviewHistoryTimePreset(String presetKey) {
    final nowUtc = _previewHistoryNowUtc();
    late final DateTime fromCreatedAtUtc;
    switch (presetKey.trim().toLowerCase()) {
      case 'today':
        fromCreatedAtUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
        break;
      case 'last_24h':
        fromCreatedAtUtc = nowUtc.subtract(const Duration(hours: 24));
        break;
      case 'last_7d':
        fromCreatedAtUtc = nowUtc.subtract(const Duration(days: 7));
        break;
      default:
        return;
    }
    setState(() {
      _setPayoutImportPreviewDraftWindow(
        fromCreatedAtUtc: fromCreatedAtUtc,
        toCreatedAtUtc: nowUtc,
      );
    });
  }

  void _applyPayoutImportPreviewHistoryCombinedPreset(String presetKey) {
    final normalized = presetKey.trim().toLowerCase();
    final nowUtc = _previewHistoryNowUtc();
    late final String status;
    late final DateTime fromCreatedAtUtc;
    switch (normalized) {
      case 'active_today':
        status = 'active';
        fromCreatedAtUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
        break;
      case 'invalidated_last_7d':
        status = 'invalidated';
        fromCreatedAtUtc = nowUtc.subtract(const Duration(days: 7));
        break;
      default:
        return;
    }
    setState(() {
      _selectedPayoutImportPreviewStatusFilter = status;
      _setPayoutImportPreviewDraftWindow(
        fromCreatedAtUtc: fromCreatedAtUtc,
        toCreatedAtUtc: nowUtc,
      );
    });
  }

  void _hydratePayoutImportPreviewHistoryDraftFromPreferences(
    CoachPayoutImportPreviewHistoryFilterPreferences preferences,
  ) {
    _selectedPayoutImportPreviewStatusFilter =
        preferences.status.trim().isEmpty ? 'all' : preferences.status.trim();
    _selectedPayoutImportPreviewOperatorIdFilter =
        _normalizePayoutImportOperatorIdFilterValue(preferences.operatorId);
    _payoutImportPreviewFromCreatedAtController.text =
        preferences.fromCreatedAtIso ?? '';
    _payoutImportPreviewToCreatedAtController.text =
        preferences.toCreatedAtIso ?? '';
    _appliedPayoutImportPreviewStatusFilter =
        preferences.status.trim().toLowerCase() == 'all'
            ? null
            : preferences.status.trim();
    _appliedPayoutImportPreviewFromCreatedAtIso = preferences.fromCreatedAtIso;
    _appliedPayoutImportPreviewToCreatedAtIso = preferences.toCreatedAtIso;
  }

  void _setPayoutImportPreviewHistoryDraftFromPreferences(
    CoachPayoutImportPreviewHistoryFilterPreferences preferences,
  ) {
    _selectedPayoutImportPreviewStatusFilter =
        preferences.status.trim().isEmpty ? 'all' : preferences.status.trim();
    _selectedPayoutImportPreviewOperatorIdFilter =
        _normalizePayoutImportOperatorIdFilterValue(preferences.operatorId);
    _payoutImportPreviewFromCreatedAtController.text =
        preferences.fromCreatedAtIso ?? '';
    _payoutImportPreviewToCreatedAtController.text =
        preferences.toCreatedAtIso ?? '';
  }

  void _hydratePayoutImportBatchFiltersFromPreferences(
    CoachPayoutImportBatchFilterPreferences preferences,
  ) {
    _selectedPayoutImportBatchOperatorIdFilter =
        _normalizePayoutImportOperatorIdFilterValue(preferences.operatorId);
  }

  void _syncCatalogImportConfigDraft(
    CoachOperatorCatalogImportConfigResponse? config,
  ) {
    final locator = config?.feedLocator?.trim() ?? '';
    if (_catalogImportFeedLocatorController.text != locator) {
      _catalogImportFeedLocatorController.text = locator;
    }
  }

  void _hydrateCatalogImportRunFiltersFromPreferences(
    CoachCatalogImportRunFilterPreferences preferences,
  ) {
    _selectedCatalogImportRunStatusFilter =
        preferences.status.trim().isEmpty ? 'all' : preferences.status.trim();
    _selectedCatalogImportRunReplayScopeFilter =
        preferences.replayScope.trim().isEmpty
            ? 'all'
            : preferences.replayScope.trim();
    _selectedCatalogImportRunIssueSeverityFilter =
        preferences.issueSeverity.trim().isEmpty
            ? 'all'
            : preferences.issueSeverity.trim();
    _selectedCatalogImportRunIssueStageFilter =
        preferences.issueStage.trim().isEmpty
            ? 'all'
            : preferences.issueStage.trim();
  }

  CoachCatalogImportRunFilterPreferences
      get _draftCatalogImportRunFilterPreferences {
    return CoachCatalogImportRunFilterPreferences(
      status: _selectedCatalogImportRunStatusFilter,
      replayScope: _selectedCatalogImportRunReplayScopeFilter,
      issueSeverity: _selectedCatalogImportRunIssueSeverityFilter,
      issueStage: _selectedCatalogImportRunIssueStageFilter,
    );
  }

  String _describeCatalogImportRunFilterPreferences(
    CoachCatalogImportRunFilterPreferences preferences,
  ) {
    return _coachCatalogImportRunStatusFilterChipLabel(preferences.status) +
        ' • ' +
        _coachCatalogImportRunReplayScopeFilterChipLabel(
          preferences.replayScope,
        ) +
        ' • ' +
        _coachCatalogImportRunIssueSeverityFilterChipLabel(
          preferences.issueSeverity,
        ) +
        ' • ' +
        _coachCatalogImportRunIssueStageFilterChipLabel(
          preferences.issueStage,
        );
  }

  List<String> _catalogImportRunSavedViewContentChipLabels(
    CoachCatalogImportRunFilterPreferences preferences,
  ) {
    return <String>[
      _coachCatalogImportRunStatusFilterChipLabel(preferences.status),
      _coachCatalogImportRunReplayScopeFilterChipLabel(
        preferences.replayScope,
      ),
      _coachCatalogImportRunIssueSeverityFilterChipLabel(
        preferences.issueSeverity,
      ),
      _coachCatalogImportRunIssueStageFilterChipLabel(
        preferences.issueStage,
      ),
    ];
  }

  List<String> _catalogImportRunIssueSavedViewContentChipLabels(
    CoachCatalogImportRunIssueFilterPreferences preferences,
  ) {
    return <String>[
      _coachCatalogImportRunIssueSeverityFilterChipLabel(
        preferences.severity,
      ),
      _coachCatalogImportRunIssueStageFilterChipLabel(
        preferences.stage,
      ),
    ];
  }

  String? _savedViewActiveScopeChipLabel(
    String selectedVisibilityScope,
    String viewVisibilityScope,
  ) {
    final normalizedSelected = _normalizeCatalogSavedViewVisibilityFilter(
      selectedVisibilityScope,
    );
    final normalizedView = viewVisibilityScope.trim().toLowerCase();
    if (normalizedSelected == 'all' ||
        normalizedView.isEmpty ||
        normalizedSelected != normalizedView) {
      return null;
    }
    return 'Active scope';
  }

  String? _savedViewActiveOwnerChipLabel(
    String viewVisibilityScope,
    String viewAccountId,
    String selectedVisibilityScope,
    String selectedOwnerAccountId,
  ) {
    if (!_catalogSavedViewMatchesOwnerFilter(
      viewVisibilityScope,
      viewAccountId,
      selectedVisibilityScope,
      selectedOwnerAccountId,
    )) {
      return null;
    }
    return 'Active owner';
  }

  String? _catalogSavedViewActiveOperatorChipLabel(
    List<String> operatorIds,
    String selectedVisibilityScope,
    String selectedOperatorId,
  ) {
    if (_normalizeCatalogSavedViewVisibilityFilter(selectedVisibilityScope) !=
        'shared_ops') {
      return null;
    }
    final normalizedSelected = _normalizeCatalogSavedViewOperatorIdFilter(
      selectedOperatorId,
    );
    if (normalizedSelected == 'all' ||
        !_catalogSavedViewMatchesOperatorFilter(
          operatorIds,
          normalizedSelected,
        )) {
      return null;
    }
    return 'Active operator';
  }

  String? _payoutSavedViewActiveOperatorChipLabel(
    String operatorId,
    String selectedVisibilityScope,
    String selectedOperatorId,
  ) {
    if (_normalizeCatalogSavedViewVisibilityFilter(selectedVisibilityScope) !=
        'shared_ops') {
      return null;
    }
    final normalizedSelected = _normalizePayoutImportOperatorIdFilterValue(
      selectedOperatorId,
    );
    final normalizedOperator = _normalizePayoutImportOperatorIdFilterValue(
      operatorId,
    );
    if (normalizedSelected == 'all' ||
        normalizedOperator == 'all' ||
        normalizedSelected != normalizedOperator) {
      return null;
    }
    return 'Active operator';
  }

  List<String> _catalogSavedViewActiveChipLabels({
    required String selectedVisibilityScope,
    required String viewVisibilityScope,
    required String viewAccountId,
    required String selectedOwnerAccountId,
    required List<String> operatorIds,
    required String selectedOperatorId,
  }) {
    return <String>[
      if (_savedViewActiveScopeChipLabel(
            selectedVisibilityScope,
            viewVisibilityScope,
          ) !=
          null)
        _savedViewActiveScopeChipLabel(
          selectedVisibilityScope,
          viewVisibilityScope,
        )!,
      if (_savedViewActiveOwnerChipLabel(
            viewVisibilityScope,
            viewAccountId,
            selectedVisibilityScope,
            selectedOwnerAccountId,
          ) !=
          null)
        _savedViewActiveOwnerChipLabel(
          viewVisibilityScope,
          viewAccountId,
          selectedVisibilityScope,
          selectedOwnerAccountId,
        )!,
      if (_catalogSavedViewActiveOperatorChipLabel(
            operatorIds,
            selectedVisibilityScope,
            selectedOperatorId,
          ) !=
          null)
        _catalogSavedViewActiveOperatorChipLabel(
          operatorIds,
          selectedVisibilityScope,
          selectedOperatorId,
        )!,
    ];
  }

  List<String> _payoutSavedViewActiveChipLabels({
    required String selectedVisibilityScope,
    required String viewVisibilityScope,
    required String viewAccountId,
    required String selectedOwnerAccountId,
    required String viewOperatorId,
    required String selectedOperatorId,
  }) {
    return <String>[
      if (_savedViewActiveScopeChipLabel(
            selectedVisibilityScope,
            viewVisibilityScope,
          ) !=
          null)
        _savedViewActiveScopeChipLabel(
          selectedVisibilityScope,
          viewVisibilityScope,
        )!,
      if (_savedViewActiveOwnerChipLabel(
            viewVisibilityScope,
            viewAccountId,
            selectedVisibilityScope,
            selectedOwnerAccountId,
          ) !=
          null)
        _savedViewActiveOwnerChipLabel(
          viewVisibilityScope,
          viewAccountId,
          selectedVisibilityScope,
          selectedOwnerAccountId,
        )!,
      if (_payoutSavedViewActiveOperatorChipLabel(
            viewOperatorId,
            selectedVisibilityScope,
            selectedOperatorId,
          ) !=
          null)
        _payoutSavedViewActiveOperatorChipLabel(
          viewOperatorId,
          selectedVisibilityScope,
          selectedOperatorId,
        )!,
    ];
  }

  String? _savedViewRecentlyUsedChipLabel(String? usedAtIso) {
    final normalized = (usedAtIso ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      return null;
    }
    final utc = parsed.toUtc();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    String fourDigits(int value) => value.toString().padLeft(4, '0');
    return 'Last used '
        '${fourDigits(utc.year)}-${twoDigits(utc.month)}-${twoDigits(utc.day)} '
        '${twoDigits(utc.hour)}:${twoDigits(utc.minute)}Z';
  }

  bool _savedViewIsPinned(Set<String> pinnedViewIds, String viewId) {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      return false;
    }
    return pinnedViewIds.contains(normalizedViewId);
  }

  Set<String> _catalogImportRunSavedViewFavoriteIds(
    List<CoachCatalogImportRunSavedView> views,
  ) {
    return views
        .where((entry) => entry.isFavorite)
        .map((entry) => entry.viewId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Set<String> _catalogImportRunIssueSavedViewFavoriteIds(
    List<CoachCatalogImportRunIssueSavedView> views,
  ) {
    return views
        .where((entry) => entry.isFavorite)
        .map((entry) => entry.viewId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Set<String> _payoutImportPreviewSavedViewFavoriteIds(
    List<CoachPayoutImportPreviewHistorySavedView> views,
  ) {
    return views
        .where((entry) => entry.isFavorite)
        .map((entry) => entry.viewId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Set<String> _payoutImportBatchSavedViewFavoriteIds(
    List<CoachPayoutImportBatchSavedView> views,
  ) {
    return views
        .where((entry) => entry.isFavorite)
        .map((entry) => entry.viewId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Map<String, String> _catalogImportRunSavedViewUsageMap(
    List<CoachCatalogImportRunSavedView> views,
  ) {
    return <String, String>{
      for (final entry in views)
        if (entry.viewId.trim().isNotEmpty &&
            (entry.lastUsedAtIso ?? '').trim().isNotEmpty)
          entry.viewId.trim(): entry.lastUsedAtIso!.trim(),
    };
  }

  Map<String, String> _catalogImportRunIssueSavedViewUsageMap(
    List<CoachCatalogImportRunIssueSavedView> views,
  ) {
    return <String, String>{
      for (final entry in views)
        if (entry.viewId.trim().isNotEmpty &&
            (entry.lastUsedAtIso ?? '').trim().isNotEmpty)
          entry.viewId.trim(): entry.lastUsedAtIso!.trim(),
    };
  }

  Map<String, String> _payoutImportPreviewSavedViewUsageMap(
    List<CoachPayoutImportPreviewHistorySavedView> views,
  ) {
    return <String, String>{
      for (final entry in views)
        if (entry.viewId.trim().isNotEmpty &&
            (entry.lastUsedAtIso ?? '').trim().isNotEmpty)
          entry.viewId.trim(): entry.lastUsedAtIso!.trim(),
    };
  }

  Map<String, String> _payoutImportBatchSavedViewUsageMap(
    List<CoachPayoutImportBatchSavedView> views,
  ) {
    return <String, String>{
      for (final entry in views)
        if (entry.viewId.trim().isNotEmpty &&
            (entry.lastUsedAtIso ?? '').trim().isNotEmpty)
          entry.viewId.trim(): entry.lastUsedAtIso!.trim(),
    };
  }

  bool _catalogImportRunFilterPreferencesEqual(
    CoachCatalogImportRunFilterPreferences left,
    CoachCatalogImportRunFilterPreferences right,
  ) {
    return left.status.trim().toLowerCase() ==
            right.status.trim().toLowerCase() &&
        left.replayScope.trim().toLowerCase() ==
            right.replayScope.trim().toLowerCase() &&
        left.issueSeverity.trim().toLowerCase() ==
            right.issueSeverity.trim().toLowerCase() &&
        left.issueStage.trim().toLowerCase() ==
            right.issueStage.trim().toLowerCase();
  }

  bool _catalogImportRunIssueFilterPreferencesEqual(
    CoachCatalogImportRunIssueFilterPreferences left,
    CoachCatalogImportRunIssueFilterPreferences right,
  ) {
    return left.severity.trim().toLowerCase() ==
            right.severity.trim().toLowerCase() &&
        left.stage.trim().toLowerCase() == right.stage.trim().toLowerCase();
  }

  bool _payoutImportPreviewHistoryFilterPreferencesEqual(
    CoachPayoutImportPreviewHistoryFilterPreferences left,
    CoachPayoutImportPreviewHistoryFilterPreferences right,
  ) {
    return left.status.trim().toLowerCase() ==
            right.status.trim().toLowerCase() &&
        (left.fromCreatedAtIso ?? '').trim() ==
            (right.fromCreatedAtIso ?? '').trim() &&
        (left.toCreatedAtIso ?? '').trim() ==
            (right.toCreatedAtIso ?? '').trim() &&
        _normalizePayoutImportOperatorIdFilterValue(left.operatorId) ==
            _normalizePayoutImportOperatorIdFilterValue(right.operatorId);
  }

  bool _payoutImportBatchFilterPreferencesEqual(
    CoachPayoutImportBatchFilterPreferences left,
    CoachPayoutImportBatchFilterPreferences right,
  ) {
    return _normalizePayoutImportOperatorIdFilterValue(left.operatorId) ==
        _normalizePayoutImportOperatorIdFilterValue(right.operatorId);
  }

  bool _catalogSavedViewMatchesExactOperatorSelection(
    List<String> operatorIds,
    String selectedVisibilityScope,
    String selectedOperatorId,
  ) {
    if (_normalizeCatalogSavedViewVisibilityFilter(selectedVisibilityScope) !=
        'shared_ops') {
      return true;
    }
    final normalizedSelected = _normalizeCatalogSavedViewOperatorIdFilter(
      selectedOperatorId,
    );
    if (operatorIds.isEmpty) {
      return normalizedSelected == 'all';
    }
    if (operatorIds.length != 1) {
      return false;
    }
    return normalizedSelected == operatorIds.single;
  }

  bool _payoutSavedViewMatchesExactOperatorSelection(
    String viewOperatorId,
    String selectedVisibilityScope,
    String selectedOperatorId,
  ) {
    if (_normalizeCatalogSavedViewVisibilityFilter(selectedVisibilityScope) !=
        'shared_ops') {
      return true;
    }
    return _normalizePayoutImportOperatorIdFilterValue(viewOperatorId) ==
        _normalizePayoutImportOperatorIdFilterValue(selectedOperatorId);
  }

  bool _catalogImportRunSavedViewIsCurrent(
    CoachCatalogImportRunSavedView view,
  ) {
    if (_savedViewActiveScopeChipLabel(
          _catalogImportRunSavedViewsVisibilityFilter,
          view.visibilityScope,
        ) ==
        null) {
      return false;
    }
    if (view.visibilityScope == 'shared_ops' &&
        _savedViewActiveOwnerChipLabel(
              view.visibilityScope,
              view.accountId,
              _catalogImportRunSavedViewsVisibilityFilter,
              _catalogImportRunSavedViewsOwnerAccountIdFilter,
            ) ==
            null) {
      return false;
    }
    if (!_catalogSavedViewMatchesExactOperatorSelection(
      view.operatorIds,
      _catalogImportRunSavedViewsVisibilityFilter,
      _catalogImportRunSavedViewsOperatorIdFilter,
    )) {
      return false;
    }
    return _catalogImportRunFilterPreferencesEqual(
      view.preferences,
      CoachCatalogImportRunFilterPreferences(
        status: _selectedCatalogImportRunStatusFilter,
        replayScope: _selectedCatalogImportRunReplayScopeFilter,
        issueSeverity: _selectedCatalogImportRunIssueSeverityFilter,
        issueStage: _selectedCatalogImportRunIssueStageFilter,
      ),
    );
  }

  bool _catalogImportRunIssueSavedViewIsCurrent({
    required CoachCatalogImportRunIssueSavedView view,
    required String selectedVisibilityScope,
    required String selectedOwnerAccountId,
    required String selectedOperatorId,
    required String issueSeverityFilter,
    required String issueStageFilter,
  }) {
    if (_savedViewActiveScopeChipLabel(
          selectedVisibilityScope,
          view.visibilityScope,
        ) ==
        null) {
      return false;
    }
    if (view.visibilityScope == 'shared_ops' &&
        _savedViewActiveOwnerChipLabel(
              view.visibilityScope,
              view.accountId,
              selectedVisibilityScope,
              selectedOwnerAccountId,
            ) ==
            null) {
      return false;
    }
    if (!_catalogSavedViewMatchesExactOperatorSelection(
      view.operatorIds,
      selectedVisibilityScope,
      selectedOperatorId,
    )) {
      return false;
    }
    return _catalogImportRunIssueFilterPreferencesEqual(
      view.preferences,
      CoachCatalogImportRunIssueFilterPreferences(
        severity: issueSeverityFilter,
        stage: issueStageFilter,
      ),
    );
  }

  bool _payoutImportPreviewSavedViewIsCurrent(
    CoachPayoutImportPreviewHistorySavedView view,
  ) {
    if (_savedViewActiveScopeChipLabel(
          _payoutImportPreviewSavedViewsVisibilityFilter,
          view.visibilityScope,
        ) ==
        null) {
      return false;
    }
    if (view.visibilityScope == 'shared_ops' &&
        _savedViewActiveOwnerChipLabel(
              view.visibilityScope,
              view.accountId,
              _payoutImportPreviewSavedViewsVisibilityFilter,
              _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
            ) ==
            null) {
      return false;
    }
    if (!_payoutSavedViewMatchesExactOperatorSelection(
      view.preferences.operatorId,
      _payoutImportPreviewSavedViewsVisibilityFilter,
      _payoutImportPreviewSavedViewsOperatorIdFilter,
    )) {
      return false;
    }
    return _payoutImportPreviewHistoryFilterPreferencesEqual(
      view.preferences,
      CoachPayoutImportPreviewHistoryFilterPreferences(
        status: _appliedPayoutImportPreviewStatusFilter ?? 'all',
        fromCreatedAtIso: _appliedPayoutImportPreviewFromCreatedAtIso,
        toCreatedAtIso: _appliedPayoutImportPreviewToCreatedAtIso,
        operatorId: _selectedPayoutImportPreviewOperatorIdFilter,
      ),
    );
  }

  bool _payoutImportBatchSavedViewIsCurrent(
    CoachPayoutImportBatchSavedView view,
  ) {
    if (_savedViewActiveScopeChipLabel(
          _payoutImportBatchSavedViewsVisibilityFilter,
          view.visibilityScope,
        ) ==
        null) {
      return false;
    }
    if (view.visibilityScope == 'shared_ops' &&
        _savedViewActiveOwnerChipLabel(
              view.visibilityScope,
              view.accountId,
              _payoutImportBatchSavedViewsVisibilityFilter,
              _payoutImportBatchSavedViewsOwnerAccountIdFilter,
            ) ==
            null) {
      return false;
    }
    if (!_payoutSavedViewMatchesExactOperatorSelection(
      view.preferences.operatorId,
      _payoutImportBatchSavedViewsVisibilityFilter,
      _payoutImportBatchSavedViewsOperatorIdFilter,
    )) {
      return false;
    }
    return _payoutImportBatchFilterPreferencesEqual(
      view.preferences,
      CoachPayoutImportBatchFilterPreferences(
        operatorId: _selectedPayoutImportBatchOperatorIdFilter,
      ),
    );
  }

  int? _savedViewUsageTimestampMicros(
    Map<String, String> usedAtById,
    String viewId,
  ) {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      return null;
    }
    final usedAtIso = usedAtById[normalizedViewId];
    if (usedAtIso == null) {
      return null;
    }
    return DateTime.tryParse(usedAtIso)?.toUtc().microsecondsSinceEpoch;
  }

  List<T> _prioritizeSavedViews<T>(
    Iterable<T> values, {
    required bool Function(T value) isCurrent,
    required bool Function(T value) isDefault,
    required String Function(T value) viewIdOf,
    Set<String> pinnedViewIds = const <String>{},
    Map<String, String> usedAtById = const <String, String>{},
  }) {
    final indexedValues = values.toList(growable: false).asMap().entries.toList(
          growable: false,
        );
    indexedValues.sort((left, right) {
      final leftCurrent = isCurrent(left.value);
      final rightCurrent = isCurrent(right.value);
      if (leftCurrent != rightCurrent) {
        return leftCurrent ? -1 : 1;
      }
      final leftPinned = _savedViewIsPinned(
        pinnedViewIds,
        viewIdOf(left.value),
      );
      final rightPinned = _savedViewIsPinned(
        pinnedViewIds,
        viewIdOf(right.value),
      );
      if (leftPinned != rightPinned) {
        return leftPinned ? -1 : 1;
      }
      final leftDefault = isDefault(left.value);
      final rightDefault = isDefault(right.value);
      if (leftDefault != rightDefault) {
        return leftDefault ? -1 : 1;
      }
      final leftUsedAt = _savedViewUsageTimestampMicros(
        usedAtById,
        viewIdOf(left.value),
      );
      final rightUsedAt = _savedViewUsageTimestampMicros(
        usedAtById,
        viewIdOf(right.value),
      );
      if (leftUsedAt != rightUsedAt) {
        if (leftUsedAt == null) {
          return 1;
        }
        if (rightUsedAt == null) {
          return -1;
        }
        return rightUsedAt.compareTo(leftUsedAt);
      }
      return left.key.compareTo(right.key);
    });
    return indexedValues.map((entry) => entry.value).toList(growable: false);
  }

  List<T> _recentlyUsedSavedViews<T>(
    Iterable<T> values, {
    required String Function(T value) viewIdOf,
    Map<String, String> usedAtById = const <String, String>{},
    int limit = 3,
  }) {
    final indexedValues = values
        .toList(growable: false)
        .asMap()
        .entries
        .where(
          (entry) =>
              _savedViewUsageTimestampMicros(
                usedAtById,
                viewIdOf(entry.value),
              ) !=
              null,
        )
        .toList(growable: false);
    indexedValues.sort((left, right) {
      final leftUsedAt = _savedViewUsageTimestampMicros(
        usedAtById,
        viewIdOf(left.value),
      );
      final rightUsedAt = _savedViewUsageTimestampMicros(
        usedAtById,
        viewIdOf(right.value),
      );
      if (leftUsedAt != rightUsedAt) {
        return (rightUsedAt ?? 0).compareTo(leftUsedAt ?? 0);
      }
      return left.key.compareTo(right.key);
    });
    return indexedValues
        .take(limit)
        .map((entry) => entry.value)
        .toList(growable: false);
  }

  String _catalogSavedViewVisibilityScopeLabel(String scope) {
    return switch (scope.trim().toLowerCase()) {
      'shared_ops' => 'Shared with ops',
      _ => 'Personal',
    };
  }

  String? _catalogSavedViewOwnerLabel(String scope, String accountId) {
    if (scope.trim().toLowerCase() != 'shared_ops') {
      return null;
    }
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty) {
      return null;
    }
    return 'Shared by $normalizedAccountId';
  }

  String? _catalogSavedViewReadOnlyLabel(String scope, bool canManage) {
    if (scope.trim().toLowerCase() != 'shared_ops' || canManage) {
      return null;
    }
    return 'Read-only shared view';
  }

  String? _payoutSavedViewOwnerChipLabel(String scope, String accountId) {
    final normalizedScope = scope.trim().toLowerCase();
    final normalizedAccountId = accountId.trim();
    if (normalizedScope != 'shared_ops' || normalizedAccountId.isEmpty) {
      return null;
    }
    return 'Owner $normalizedAccountId';
  }

  String? _payoutSavedViewOperatorChipLabel(
    String operatorId, {
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries =
        const <CoachCatalogImportRunSavedViewOperatorSummary>[],
  }) {
    final normalizedOperatorId =
        _normalizePayoutImportOperatorIdFilterValue(operatorId);
    if (normalizedOperatorId == 'all') {
      return 'All operators';
    }
    final operatorName =
        _catalogOperatorNameFromSummaries(summaries, normalizedOperatorId) ??
            _catalogOperatorName(normalizedOperatorId);
    if (operatorName == null || operatorName.trim().isEmpty) {
      return 'Operator $normalizedOperatorId';
    }
    return 'Operator $operatorName';
  }

  String? _payoutSavedViewReadOnlyChipLabel(String scope, bool canManage) {
    final normalizedScope = scope.trim().toLowerCase();
    if (normalizedScope != 'shared_ops' || canManage) {
      return null;
    }
    return 'Read-only';
  }

  String _compactIsoDateLabel(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized.length >= 10) {
      return normalized.substring(0, 10);
    }
    return normalized;
  }

  List<String> _payoutImportPreviewSavedViewContentChipLabels(
    CoachPayoutImportPreviewHistoryFilterPreferences preferences,
  ) {
    final labels = <String>[
      _coachPayoutImportPreviewStatusLabel(preferences.status),
    ];
    final fromDate = _compactIsoDateLabel(preferences.fromCreatedAtIso);
    if (fromDate.isNotEmpty) {
      labels.add('From $fromDate');
    }
    final toDate = _compactIsoDateLabel(preferences.toCreatedAtIso);
    if (toDate.isNotEmpty) {
      labels.add('To $toDate');
    }
    return labels;
  }

  String _payoutImportBatchSavedViewContentChipLabel(
    CoachPayoutImportBatchFilterPreferences preferences, {
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries =
        const <CoachCatalogImportRunSavedViewOperatorSummary>[],
  }) {
    final normalizedOperatorId =
        _normalizePayoutImportOperatorIdFilterValue(preferences.operatorId);
    if (normalizedOperatorId == 'all') {
      return 'All operators';
    }
    final operatorName =
        _catalogOperatorNameFromSummaries(summaries, normalizedOperatorId) ??
            _catalogOperatorName(normalizedOperatorId);
    if (operatorName == null || operatorName.trim().isEmpty) {
      return 'Filter $normalizedOperatorId';
    }
    return 'Filter $operatorName';
  }

  String _normalizeCatalogSavedViewVisibilityFilter(String scope) {
    return switch (scope.trim().toLowerCase()) {
      'personal' => 'personal',
      'shared_ops' => 'shared_ops',
      _ => 'all',
    };
  }

  String _normalizeCatalogSavedViewOwnerAccountIdFilter(String? accountId) {
    final normalized = accountId?.trim() ?? '';
    return normalized.isEmpty ? 'all' : normalized;
  }

  String _normalizeCatalogSavedViewOperatorIdFilter(String? operatorId) {
    final normalized = operatorId?.trim() ?? '';
    return normalized.isEmpty ? 'all' : normalized;
  }

  List<String> _privilegeScopedCoachOperatorIds() {
    if (_privilegeSnapshot.isSuperadmin) {
      return const <String>[];
    }
    final normalized = <String>[];
    final seen = <String>{};
    for (final operatorId in _privilegeSnapshot.operatorIds) {
      final value = operatorId.trim();
      if (value.isEmpty || !seen.add(value)) {
        continue;
      }
      normalized.add(value);
    }
    normalized.sort();
    return normalized;
  }

  bool get _hasRestrictedCoachOperatorScope =>
      _privilegeScopedCoachOperatorIds().isNotEmpty;

  List<String> _resolveSharedViewOperatorScopeIds(String selectedOperatorId) {
    final normalizedOperatorId =
        _normalizeCatalogSavedViewOperatorIdFilter(selectedOperatorId);
    if (normalizedOperatorId != 'all') {
      return <String>[normalizedOperatorId];
    }
    final allowedOperatorIds = _privilegeScopedCoachOperatorIds();
    if (allowedOperatorIds.isNotEmpty) {
      return allowedOperatorIds;
    }
    return const <String>[];
  }

  bool _sharedViewFallsWithinPrivilegeOperatorScope(List<String> operatorIds) {
    final allowedOperatorIds = _privilegeScopedCoachOperatorIds();
    if (allowedOperatorIds.isEmpty) {
      return true;
    }
    final normalizedOperatorIds = operatorIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedOperatorIds.isEmpty) {
      return false;
    }
    return normalizedOperatorIds.any(allowedOperatorIds.contains);
  }

  List<String> _catalogAvailableOperatorIds({
    List<CoachOperatorCatalogImportRun>? importRunsOverride,
    List<CoachOperatorCatalogSourceArtifact>? sourceArtifactsOverride,
  }) {
    final operatorIds = <String>{};
    for (final entry
        in _operatorFeedHealth?.feeds ?? const <CoachOperatorFeedHealth>[]) {
      final operatorId = entry.operatorId.trim();
      if (operatorId.isNotEmpty) {
        operatorIds.add(operatorId);
      }
    }
    for (final entry in importRunsOverride ??
        _catalogImportRuns?.importRuns ??
        const <CoachOperatorCatalogImportRun>[]) {
      operatorIds.addAll(
        entry.operatorIds
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    for (final entry in sourceArtifactsOverride ??
        _catalogSourceArtifacts?.artifacts ??
        const <CoachOperatorCatalogSourceArtifact>[]) {
      operatorIds.addAll(
        entry.operatorIds
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final configuredArtifact = _catalogImportConfig?.sourceArtifact;
    if (configuredArtifact != null) {
      operatorIds.addAll(
        configuredArtifact.operatorIds
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final allowedOperatorIds = _privilegeScopedCoachOperatorIds();
    if (allowedOperatorIds.isNotEmpty) {
      operatorIds.addAll(allowedOperatorIds);
    }
    final values = operatorIds.toList(growable: true)..sort();
    if (allowedOperatorIds.isNotEmpty) {
      return values
          .where((value) => allowedOperatorIds.contains(value))
          .toList(growable: false);
    }
    return values;
  }

  int _catalogSavedViewOperatorSharedViewCount(
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries,
    String operatorId,
  ) {
    final normalizedOperatorId = _normalizeCatalogSavedViewOperatorIdFilter(
      operatorId,
    );
    if (normalizedOperatorId == 'all') {
      return summaries.fold<int>(
        0,
        (sum, entry) => sum + entry.sharedViewCount,
      );
    }
    for (final summary in summaries) {
      if (summary.operatorId == normalizedOperatorId) {
        return summary.sharedViewCount;
      }
    }
    return 0;
  }

  int _catalogSavedViewScopedOperatorCount({
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries =
        const <CoachCatalogImportRunSavedViewOperatorSummary>[],
    List<CoachOperatorCatalogImportRun>? importRunsOverride,
    List<CoachOperatorCatalogSourceArtifact>? sourceArtifactsOverride,
  }) {
    final operatorIds = <String>{
      ..._catalogAvailableOperatorIds(
        importRunsOverride: importRunsOverride,
        sourceArtifactsOverride: sourceArtifactsOverride,
      ),
      ...summaries
          .map((entry) => entry.operatorId.trim())
          .where((value) => value.isNotEmpty),
    };
    return operatorIds.length;
  }

  String? _catalogOperatorName(String operatorId) {
    final normalizedOperatorId =
        _normalizeCatalogSavedViewOperatorIdFilter(operatorId);
    if (normalizedOperatorId == 'all') {
      return null;
    }
    for (final entry
        in _operatorFeedHealth?.feeds ?? const <CoachOperatorFeedHealth>[]) {
      if (entry.operatorId == normalizedOperatorId) {
        final normalizedOperatorName = entry.operatorName.trim();
        if (normalizedOperatorName.isNotEmpty) {
          return normalizedOperatorName;
        }
      }
    }
    return null;
  }

  String? _catalogOperatorNameFromSummaries(
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries,
    String operatorId,
  ) {
    final normalizedOperatorId =
        _normalizeCatalogSavedViewOperatorIdFilter(operatorId);
    if (normalizedOperatorId == 'all') {
      return null;
    }
    for (final summary in summaries) {
      if (summary.operatorId == normalizedOperatorId) {
        final normalizedOperatorName = summary.operatorName.trim();
        if (normalizedOperatorName.isNotEmpty) {
          return normalizedOperatorName;
        }
      }
    }
    return null;
  }

  String _catalogOperatorFilterOptionLabel(
    String operatorId, {
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries =
        const <CoachCatalogImportRunSavedViewOperatorSummary>[],
  }) {
    final normalizedOperatorId = _normalizeCatalogSavedViewOperatorIdFilter(
      operatorId,
    );
    if (normalizedOperatorId == 'all') {
      final operatorCount = _catalogSavedViewScopedOperatorCount(
        summaries: summaries,
      );
      return operatorCount == 0
          ? 'All operators'
          : 'All operators ($operatorCount)';
    }
    final operatorName =
        _catalogOperatorNameFromSummaries(summaries, normalizedOperatorId) ??
            _catalogOperatorName(normalizedOperatorId);
    final sharedViewCount = _catalogSavedViewOperatorSharedViewCount(
        summaries, normalizedOperatorId);
    final operatorLabel = operatorName ?? normalizedOperatorId;
    if (sharedViewCount > 0) {
      return '$operatorLabel ($sharedViewCount)';
    }
    return operatorLabel;
  }

  String _catalogOperatorFilterSummaryText(
    String operatorId, {
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries =
        const <CoachCatalogImportRunSavedViewOperatorSummary>[],
  }) {
    final normalizedOperatorId = _normalizeCatalogSavedViewOperatorIdFilter(
      operatorId,
    );
    if (summaries.isNotEmpty) {
      if (normalizedOperatorId == 'all') {
        final operatorCount = _catalogSavedViewScopedOperatorCount(
          summaries: summaries,
        );
        final scopedSharedViews = _catalogSavedViewOperatorSharedViewCount(
          summaries,
          'all',
        );
        final operatorLabel = operatorCount == 1
            ? '1 operator-scoped target'
            : '$operatorCount operator-scoped targets';
        final viewLabel = scopedSharedViews == 1
            ? '1 shared view'
            : '$scopedSharedViews shared views';
        return '$operatorLabel discovered across $viewLabel. All-operator views remain visible.';
      }
      final sharedViewCount = _catalogSavedViewOperatorSharedViewCount(
          summaries, normalizedOperatorId);
      if (sharedViewCount > 0) {
        final operatorName = _catalogOperatorNameFromSummaries(
                summaries, normalizedOperatorId) ??
            _catalogOperatorName(normalizedOperatorId);
        final operatorLabel = operatorName == null
            ? normalizedOperatorId
            : '$normalizedOperatorId · $operatorName';
        final viewLabel = sharedViewCount == 1
            ? '1 shared view'
            : '$sharedViewCount shared views';
        return '$operatorLabel scopes $viewLabel. All-operator views remain visible.';
      }
    }
    if (normalizedOperatorId == 'all') {
      final operatorCount = _catalogAvailableOperatorIds().length;
      if (operatorCount == 0) {
        return 'Shared views are not constrained to a specific operator yet.';
      }
      return operatorCount == 1
          ? 'Shared views can target 1 discovered operator or all operators.'
          : 'Shared views can target $operatorCount discovered operators or all operators.';
    }
    final operatorName =
        _catalogOperatorNameFromSummaries(summaries, normalizedOperatorId) ??
            _catalogOperatorName(normalizedOperatorId);
    final operatorLabel = operatorName == null
        ? normalizedOperatorId
        : '$normalizedOperatorId · $operatorName';
    return 'Shared views for $operatorLabel stay visible together with all-operator views.';
  }

  List<String> _catalogSavedViewOperatorIdOptions({
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries =
        const <CoachCatalogImportRunSavedViewOperatorSummary>[],
    List<CoachOperatorCatalogImportRun>? importRunsOverride,
    List<CoachOperatorCatalogSourceArtifact>? sourceArtifactsOverride,
    String? selectedOperatorId,
  }) {
    final values = <String>['all'];
    final seen = <String>{'all'};
    for (final operatorId in _catalogAvailableOperatorIds(
      importRunsOverride: importRunsOverride,
      sourceArtifactsOverride: sourceArtifactsOverride,
    )) {
      if (seen.add(operatorId)) {
        values.add(operatorId);
      }
    }
    for (final operatorId in summaries
        .map((entry) => entry.operatorId.trim())
        .where((value) => value.isNotEmpty)) {
      if (seen.add(operatorId)) {
        values.add(operatorId);
      }
    }
    final normalizedSelected = _normalizeCatalogSavedViewOperatorIdFilter(
      selectedOperatorId,
    );
    if (normalizedSelected != 'all' && !values.contains(normalizedSelected)) {
      values.add(normalizedSelected);
    }
    return values;
  }

  bool _catalogSavedViewMatchesOperatorFilter(
    List<String> operatorIds,
    String selectedOperatorId,
  ) {
    final normalizedOperatorId = _normalizeCatalogSavedViewOperatorIdFilter(
      selectedOperatorId,
    );
    if (normalizedOperatorId == 'all') {
      return operatorIds.isEmpty;
    }
    return operatorIds.contains(normalizedOperatorId);
  }

  int? _catalogSavedViewOwnerSharedViewCount(
    List<CoachCatalogImportRunSavedViewOwnerSummary> summaries,
    String ownerAccountId,
  ) {
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId == 'all') {
      return null;
    }
    for (final summary in summaries) {
      if (summary.accountId == normalizedOwnerAccountId) {
        return summary.sharedViewCount;
      }
    }
    return null;
  }

  String _catalogSavedViewOwnerFilterOptionLabel(
    String value,
    List<CoachCatalogImportRunSavedViewOwnerSummary> summaries,
  ) {
    final normalizedValue = _normalizeCatalogSavedViewOwnerAccountIdFilter(
      value,
    );
    if (normalizedValue == 'all') {
      return summaries.isEmpty
          ? 'All shared owners'
          : 'All shared owners (${summaries.length})';
    }
    final sharedViewCount = _catalogSavedViewOwnerSharedViewCount(
      summaries,
      normalizedValue,
    );
    if (sharedViewCount == null) {
      return normalizedValue;
    }
    return '$normalizedValue ($sharedViewCount)';
  }

  String _catalogSavedViewOwnerFilterSummaryText(
    List<CoachCatalogImportRunSavedViewOwnerSummary> summaries,
    String ownerAccountId,
  ) {
    if (summaries.isEmpty) {
      return 'No shared view owners discovered yet.';
    }
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId == 'all') {
      final totalSharedViews = summaries.fold<int>(
        0,
        (sum, entry) => sum + entry.sharedViewCount,
      );
      final ownerLabel = summaries.length == 1
          ? '1 shared owner'
          : '${summaries.length} shared owners';
      final viewLabel = totalSharedViews == 1
          ? '1 shared view'
          : '$totalSharedViews shared views';
      return '$ownerLabel discovered across $viewLabel.';
    }
    final sharedViewCount = _catalogSavedViewOwnerSharedViewCount(
      summaries,
      normalizedOwnerAccountId,
    );
    if (sharedViewCount == null) {
      return 'No shared views discovered for $normalizedOwnerAccountId.';
    }
    final viewLabel = sharedViewCount == 1
        ? '1 shared view'
        : '$sharedViewCount shared views';
    return '$normalizedOwnerAccountId exposes $viewLabel.';
  }

  bool _catalogSavedViewMatchesOwnerFilter(
    String visibilityScope,
    String ownerAccountId,
    String selectedVisibilityScope,
    String selectedOwnerAccountId,
  ) {
    return visibilityScope.trim().toLowerCase() == 'shared_ops' &&
        ownerAccountId.trim().isNotEmpty &&
        _normalizeCatalogSavedViewVisibilityFilter(selectedVisibilityScope) ==
            'shared_ops' &&
        _normalizeCatalogSavedViewOwnerAccountIdFilter(
                selectedOwnerAccountId) ==
            ownerAccountId.trim();
  }

  List<CoachCatalogImportRunSavedView>
      _filterCatalogImportRunSavedViewsByVisibilityScope(
    List<CoachCatalogImportRunSavedView> views,
    String visibilityScope,
  ) {
    final normalizedScope =
        _normalizeCatalogSavedViewVisibilityFilter(visibilityScope);
    if (normalizedScope == 'all') {
      return views;
    }
    return views
        .where((entry) => entry.visibilityScope == normalizedScope)
        .toList(growable: false);
  }

  List<CoachCatalogImportRunSavedView>
      _filterCatalogImportRunSavedViewsByOwnerAccountId(
    List<CoachCatalogImportRunSavedView> views,
    String ownerAccountId,
  ) {
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId == 'all') {
      return views;
    }
    return views
        .where((entry) => entry.accountId == normalizedOwnerAccountId)
        .toList(growable: false);
  }

  List<CoachCatalogImportRunSavedView>
      _filterCatalogImportRunSavedViewsByOperatorId(
    List<CoachCatalogImportRunSavedView> views,
    String operatorId,
  ) {
    final normalizedOperatorId =
        _normalizeCatalogSavedViewOperatorIdFilter(operatorId);
    if (normalizedOperatorId == 'all') {
      return views;
    }
    return views
        .where(
          (entry) =>
              entry.visibilityScope != 'shared_ops' ||
              entry.operatorIds.isEmpty ||
              entry.operatorIds.contains(normalizedOperatorId),
        )
        .toList(growable: false);
  }

  List<CoachCatalogImportRunSavedView>
      _filterCatalogImportRunSavedViewsByPrivilegeOperatorScope(
    List<CoachCatalogImportRunSavedView> views,
  ) {
    if (!_hasRestrictedCoachOperatorScope) {
      return views;
    }
    return views
        .where(
          (entry) =>
              entry.visibilityScope != 'shared_ops' ||
              _sharedViewFallsWithinPrivilegeOperatorScope(entry.operatorIds),
        )
        .toList(growable: false);
  }

  List<CoachCatalogImportRunIssueSavedView>
      _filterCatalogImportRunIssueSavedViewsByVisibilityScope(
    List<CoachCatalogImportRunIssueSavedView> views,
    String visibilityScope,
  ) {
    final normalizedScope =
        _normalizeCatalogSavedViewVisibilityFilter(visibilityScope);
    if (normalizedScope == 'all') {
      return views;
    }
    return views
        .where((entry) => entry.visibilityScope == normalizedScope)
        .toList(growable: false);
  }

  List<CoachCatalogImportRunIssueSavedView>
      _filterCatalogImportRunIssueSavedViewsByOwnerAccountId(
    List<CoachCatalogImportRunIssueSavedView> views,
    String ownerAccountId,
  ) {
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId == 'all') {
      return views;
    }
    return views
        .where((entry) => entry.accountId == normalizedOwnerAccountId)
        .toList(growable: false);
  }

  List<CoachCatalogImportRunIssueSavedView>
      _filterCatalogImportRunIssueSavedViewsByOperatorId(
    List<CoachCatalogImportRunIssueSavedView> views,
    String operatorId,
  ) {
    final normalizedOperatorId =
        _normalizeCatalogSavedViewOperatorIdFilter(operatorId);
    if (normalizedOperatorId == 'all') {
      return views;
    }
    return views
        .where(
          (entry) =>
              entry.visibilityScope != 'shared_ops' ||
              entry.operatorIds.isEmpty ||
              entry.operatorIds.contains(normalizedOperatorId),
        )
        .toList(growable: false);
  }

  List<CoachCatalogImportRunIssueSavedView>
      _filterCatalogImportRunIssueSavedViewsByPrivilegeOperatorScope(
    List<CoachCatalogImportRunIssueSavedView> views,
  ) {
    if (!_hasRestrictedCoachOperatorScope) {
      return views;
    }
    return views
        .where(
          (entry) =>
              entry.visibilityScope != 'shared_ops' ||
              _sharedViewFallsWithinPrivilegeOperatorScope(entry.operatorIds),
        )
        .toList(growable: false);
  }

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _catalogImportRunSavedViewOwnerSummariesFromViews(
    List<CoachCatalogImportRunSavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final summaries = counts.entries
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
    return summaries;
  }

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _catalogImportRunIssueSavedViewOwnerSummariesFromViews(
    List<CoachCatalogImportRunIssueSavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final summaries = counts.entries
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
    return summaries;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _catalogImportRunSavedViewOperatorSummariesFromViews(
    List<CoachCatalogImportRunSavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
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
    final summaries = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
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
    return summaries;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _catalogImportRunIssueSavedViewOperatorSummariesFromViews(
    List<CoachCatalogImportRunIssueSavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
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
    final summaries = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
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
    return summaries;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _filterCatalogSavedViewOperatorSummariesByPrivilegeScope(
    List<CoachCatalogImportRunSavedViewOperatorSummary> summaries,
  ) {
    final allowedOperatorIds = _privilegeScopedCoachOperatorIds();
    if (allowedOperatorIds.isEmpty) {
      return summaries;
    }
    return summaries
        .where((entry) => allowedOperatorIds.contains(entry.operatorId.trim()))
        .toList(growable: false);
  }

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _payoutImportPreviewSavedViewOwnerSummariesFromViews(
    List<CoachPayoutImportPreviewHistorySavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final summaries = counts.entries
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
    return summaries;
  }

  List<CoachCatalogImportRunSavedViewOwnerSummary>
      _payoutImportBatchSavedViewOwnerSummariesFromViews(
    List<CoachPayoutImportBatchSavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final accountId = entry.accountId.trim();
      if (accountId.isEmpty) {
        continue;
      }
      counts.update(accountId, (value) => value + 1, ifAbsent: () => 1);
    }
    final summaries = counts.entries
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
    return summaries;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _payoutImportPreviewSavedViewOperatorSummariesFromViews(
    List<CoachPayoutImportPreviewHistorySavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final operatorId = _normalizePayoutImportOperatorIdFilterValue(
        entry.preferences.operatorId,
      );
      if (operatorId == 'all') {
        continue;
      }
      counts.update(operatorId, (value) => value + 1, ifAbsent: () => 1);
    }
    final summaries = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
            operatorName: _catalogOperatorName(entry.key) ?? '',
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
    return summaries;
  }

  List<CoachCatalogImportRunSavedViewOperatorSummary>
      _payoutImportBatchSavedViewOperatorSummariesFromViews(
    List<CoachPayoutImportBatchSavedView> views,
  ) {
    final counts = <String, int>{};
    for (final entry in views) {
      if (entry.visibilityScope != 'shared_ops') {
        continue;
      }
      final operatorId = _normalizePayoutImportOperatorIdFilterValue(
        entry.preferences.operatorId,
      );
      if (operatorId == 'all') {
        continue;
      }
      counts.update(operatorId, (value) => value + 1, ifAbsent: () => 1);
    }
    final summaries = counts.entries
        .map(
          (entry) => CoachCatalogImportRunSavedViewOperatorSummary(
            operatorId: entry.key,
            operatorName: _catalogOperatorName(entry.key) ?? '',
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
    return summaries;
  }

  List<CoachPayoutImportPreviewHistorySavedView>
      _filterPayoutImportPreviewSavedViewsByOwnerAccountId(
    List<CoachPayoutImportPreviewHistorySavedView> views,
    String ownerAccountId,
  ) {
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId == 'all') {
      return views;
    }
    return views
        .where((entry) => entry.accountId == normalizedOwnerAccountId)
        .toList(growable: false);
  }

  List<CoachPayoutImportBatchSavedView>
      _filterPayoutImportBatchSavedViewsByOwnerAccountId(
    List<CoachPayoutImportBatchSavedView> views,
    String ownerAccountId,
  ) {
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId == 'all') {
      return views;
    }
    return views
        .where((entry) => entry.accountId == normalizedOwnerAccountId)
        .toList(growable: false);
  }

  List<CoachPayoutImportPreviewHistorySavedView>
      _filterPayoutImportPreviewSavedViewsByOperatorId(
    List<CoachPayoutImportPreviewHistorySavedView> views,
    String operatorId,
  ) {
    final normalizedOperatorId =
        _normalizePayoutImportOperatorIdFilterValue(operatorId);
    if (normalizedOperatorId == 'all') {
      return views;
    }
    return views.where((entry) {
      final entryOperatorId = _normalizePayoutImportOperatorIdFilterValue(
        entry.preferences.operatorId,
      );
      return entryOperatorId == 'all' ||
          entryOperatorId == normalizedOperatorId;
    }).toList(growable: false);
  }

  List<CoachPayoutImportBatchSavedView>
      _filterPayoutImportBatchSavedViewsByOperatorId(
    List<CoachPayoutImportBatchSavedView> views,
    String operatorId,
  ) {
    final normalizedOperatorId =
        _normalizePayoutImportOperatorIdFilterValue(operatorId);
    if (normalizedOperatorId == 'all') {
      return views;
    }
    return views.where((entry) {
      final entryOperatorId = _normalizePayoutImportOperatorIdFilterValue(
        entry.preferences.operatorId,
      );
      return entryOperatorId == 'all' ||
          entryOperatorId == normalizedOperatorId;
    }).toList(growable: false);
  }

  List<String> _catalogImportRunSavedViewOwnerAccountIdOptions(
    List<CoachCatalogImportRunSavedViewOwnerSummary> summaries,
    String ownerAccountId,
  ) {
    final options = summaries
        .map((entry) => entry.accountId.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: true);
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId != 'all' &&
        !options.contains(normalizedOwnerAccountId)) {
      options.insert(0, normalizedOwnerAccountId);
    }
    return <String>['all', ...options];
  }

  List<String> _catalogImportRunIssueSavedViewOwnerAccountIdOptions(
    List<CoachCatalogImportRunSavedViewOwnerSummary> summaries,
    String ownerAccountId,
  ) {
    final options = summaries
        .map((entry) => entry.accountId.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: true);
    final normalizedOwnerAccountId =
        _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId);
    if (normalizedOwnerAccountId != 'all' &&
        !options.contains(normalizedOwnerAccountId)) {
      options.insert(0, normalizedOwnerAccountId);
    }
    return <String>['all', ...options];
  }

  @override
  void initState() {
    super.initState();
    _payoutImportReportNameController
        .addListener(_handlePayoutImportDraftChanged);
    _payoutImportReportBodyController
        .addListener(_handlePayoutImportDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPrivilegesAndQueues();
    });
  }

  @override
  void dispose() {
    _payoutImportReportNameController
        .removeListener(_handlePayoutImportDraftChanged);
    _payoutImportReportBodyController
        .removeListener(_handlePayoutImportDraftChanged);
    _catalogImportFeedLocatorController.dispose();
    _catalogImportRunSavedViewNameController.dispose();
    _payoutImportReportNameController.dispose();
    _payoutImportReportBodyController.dispose();
    _payoutImportPreviewFromCreatedAtController.dispose();
    _payoutImportPreviewToCreatedAtController.dispose();
    _payoutImportPreviewSavedViewNameController.dispose();
    _payoutImportBatchSavedViewNameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToSection(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) {
      return;
    }
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
    );
  }

  void _persistConsoleUiState() {
    PageStorage.maybeOf(context)?.writeState(
      context,
      <String, Object?>{
        'selectedWorkspace': _selectedWorkspace,
        'selectedPortalSection': _selectedPortalSection,
        'selectedSettlementsTrack': _selectedSettlementsTrack,
        'collapsedWorkspaces': _collapsedWorkspaces.toList(growable: false),
      },
      identifier: _pageStorageStateIdentifier,
    );
  }

  List<String> _portalSectionWorkspaceIds(String sectionId) {
    switch (sectionId) {
      case _portalSectionTrips:
      case _portalSectionSales:
        return const <String>[_workspaceSalesFeeds];
      case _portalSectionSettlements:
        return const <String>[_workspaceSettlements, _workspacePayoutOps];
      case _portalSectionSupport:
        return const <String>[_workspaceSupport];
      case _portalSectionToday:
      default:
        return const <String>[
          _workspaceSupport,
          _workspaceSettlements,
          _workspacePayoutOps,
          _workspaceSalesFeeds,
        ];
    }
  }

  bool _portalSectionMatches(String descriptorSectionId) {
    return _selectedPortalSection == _portalSectionToday ||
        _selectedPortalSection == descriptorSectionId;
  }

  String _defaultPortalSectionForWorkspace(String workspaceId) {
    switch (workspaceId) {
      case _workspaceSupport:
        return _portalSectionSupport;
      case _workspaceSettlements:
      case _workspacePayoutOps:
        return _portalSectionSettlements;
      case _workspaceSalesFeeds:
        return _portalSectionSales;
      case _workspaceAll:
      default:
        return _portalSectionToday;
    }
  }

  String _defaultWorkspaceForPortalSection(String sectionId) {
    switch (sectionId) {
      case _portalSectionTrips:
      case _portalSectionSales:
        return _workspaceSalesFeeds;
      case _portalSectionSettlements:
        return _workspaceSettlements;
      case _portalSectionSupport:
        return _workspaceSupport;
      case _portalSectionToday:
      default:
        return _workspaceAll;
    }
  }

  List<String> _visibleWorkspaceIds(
    List<_CoachOpsWorkspaceDescriptor> workspaces,
  ) {
    if (_selectedWorkspace == _workspaceAll) {
      return workspaces
          .map((workspace) => workspace.id)
          .toList(growable: false);
    }
    return workspaces
        .where((workspace) => workspace.id == _selectedWorkspace)
        .map((workspace) => workspace.id)
        .toList(growable: false);
  }

  void _selectWorkspace(String workspaceId) {
    setState(() {
      _selectedWorkspace = workspaceId;
      if (workspaceId != _workspaceAll &&
          _selectedPortalSection != _portalSectionToday &&
          !_portalSectionWorkspaceIds(_selectedPortalSection)
              .contains(workspaceId)) {
        _selectedPortalSection = _defaultPortalSectionForWorkspace(workspaceId);
      }
      if (workspaceId != _workspaceAll) {
        _collapsedWorkspaces.remove(workspaceId);
      }
      _persistConsoleUiState();
    });
  }

  void _selectPortalSection(String sectionId) {
    setState(() {
      _selectedPortalSection = sectionId;
      if (sectionId == _portalSectionToday) {
        _selectedWorkspace = _workspaceAll;
      } else {
        final allowedWorkspaceIds = _portalSectionWorkspaceIds(sectionId);
        if (_selectedWorkspace == _workspaceAll ||
            !allowedWorkspaceIds.contains(_selectedWorkspace)) {
          _selectedWorkspace = _defaultWorkspaceForPortalSection(sectionId);
        }
        _collapsedWorkspaces.remove(_selectedWorkspace);
      }
      _persistConsoleUiState();
    });
  }

  void _toggleWorkspaceCollapsed(String workspaceId) {
    setState(() {
      if (_collapsedWorkspaces.contains(workspaceId)) {
        _collapsedWorkspaces.remove(workspaceId);
      } else {
        _collapsedWorkspaces.add(workspaceId);
      }
      _persistConsoleUiState();
    });
  }

  void _collapseVisibleWorkspaces(
      List<_CoachOpsWorkspaceDescriptor> workspaces) {
    setState(() {
      _collapsedWorkspaces.addAll(_visibleWorkspaceIds(workspaces));
      _persistConsoleUiState();
    });
  }

  void _expandVisibleWorkspaces(List<_CoachOpsWorkspaceDescriptor> workspaces) {
    setState(() {
      _collapsedWorkspaces.removeAll(_visibleWorkspaceIds(workspaces));
      _persistConsoleUiState();
    });
  }

  Future<void> _focusWorkspace(
    String workspaceId,
    GlobalKey targetKey,
  ) async {
    if (_selectedWorkspace != workspaceId ||
        _collapsedWorkspaces.contains(workspaceId) ||
        (_selectedPortalSection != _portalSectionToday &&
            !_portalSectionWorkspaceIds(_selectedPortalSection)
                .contains(workspaceId))) {
      setState(() {
        _selectedWorkspace = workspaceId;
        if (_selectedPortalSection != _portalSectionToday &&
            !_portalSectionWorkspaceIds(_selectedPortalSection)
                .contains(workspaceId)) {
          _selectedPortalSection =
              _defaultPortalSectionForWorkspace(workspaceId);
        }
        _collapsedWorkspaces.remove(workspaceId);
        _persistConsoleUiState();
      });
      await Future<void>.delayed(Duration.zero);
      if (!mounted) {
        return;
      }
    }
    await _scrollToSection(targetKey);
  }

  Future<void> _focusSettlementsTrack(
    String trackId,
    GlobalKey targetKey,
  ) async {
    final settlementsWorkspaceIds =
        _portalSectionWorkspaceIds(_portalSectionSettlements);
    final keepTodaySurface = _selectedPortalSection == _portalSectionToday;
    final nextPortalSection =
        keepTodaySurface ? _portalSectionToday : _portalSectionSettlements;
    final nextWorkspace = keepTodaySurface
        ? (_selectedWorkspace != _workspaceAll &&
                !settlementsWorkspaceIds.contains(_selectedWorkspace)
            ? _workspaceAll
            : _selectedWorkspace)
        : (_selectedPortalSection != _portalSectionSettlements
            ? (_selectedWorkspace == _workspaceAll ||
                    !settlementsWorkspaceIds.contains(_selectedWorkspace)
                ? _defaultWorkspaceForPortalSection(
                    _portalSectionSettlements,
                  )
                : _selectedWorkspace)
            : _selectedWorkspace);
    final nextCollapsedWorkspaces = <String>{..._collapsedWorkspaces};
    if (keepTodaySurface) {
      if (nextWorkspace == _workspaceAll) {
        nextCollapsedWorkspaces.removeAll(settlementsWorkspaceIds);
      } else if (settlementsWorkspaceIds.contains(nextWorkspace)) {
        nextCollapsedWorkspaces.remove(nextWorkspace);
      }
    } else if (nextWorkspace != _workspaceAll) {
      nextCollapsedWorkspaces.remove(nextWorkspace);
    }
    if (_selectedPortalSection != nextPortalSection ||
        _selectedSettlementsTrack != trackId ||
        _selectedWorkspace != nextWorkspace ||
        _collapsedWorkspaces.length != nextCollapsedWorkspaces.length ||
        !_collapsedWorkspaces.containsAll(nextCollapsedWorkspaces)) {
      setState(() {
        _selectedSettlementsTrack = trackId;
        _selectedPortalSection = nextPortalSection;
        _selectedWorkspace = nextWorkspace;
        _collapsedWorkspaces
          ..clear()
          ..addAll(nextCollapsedWorkspaces);
        _persistConsoleUiState();
      });
      await Future<void>.delayed(Duration.zero);
      if (!mounted) {
        return;
      }
    }
    if (keepTodaySurface) {
      return;
    }
    await _scrollToSection(targetKey);
  }

  // ---- Portal navigation surface --------------------------------------------
  //
  // The console body is a single 18k-line ListView with five logical "portal
  // sections" (Today / Trips / Sales / Settlements / Support). Without a
  // dedicated navigation surface, operators had to scroll back to the in-page
  // chip row at the top to switch sections. The rail (wide layout) and the
  // drawer (narrow layout) below let them jump directly to a section's
  // anchor key in one tap, while also updating `_selectedPortalSection`
  // so the existing per-section filtering logic still applies.

  List<_CoachOpsPortalNavItem> _portalNavItems(bool isArabic) {
    return <_CoachOpsPortalNavItem>[
      _CoachOpsPortalNavItem(
        portalSectionId: _portalSectionToday,
        icon: Icons.today_outlined,
        label: isArabic ? 'اليوم' : 'Today',
        badge: 0,
      ),
      _CoachOpsPortalNavItem(
        portalSectionId: _portalSectionTrips,
        icon: Icons.alt_route_outlined,
        label: isArabic ? 'الرحلات' : 'Trips',
        badge: _degradedFeedCount + _staleFeedCount,
      ),
      _CoachOpsPortalNavItem(
        portalSectionId: _portalSectionSales,
        icon: Icons.sell_outlined,
        label: isArabic ? 'المبيعات' : 'Sales',
        badge: _catalogImportRunCount,
      ),
      _CoachOpsPortalNavItem(
        portalSectionId: _portalSectionSettlements,
        icon: Icons.account_balance_wallet_outlined,
        label: isArabic ? 'التسويات' : 'Settlements',
        badge: _queuedPayoutRunCount +
            _payoutAttentionCount +
            _payoutImportCount +
            _activePayoutImportPreviewCount +
            _payoutImportBatchCount,
      ),
      _CoachOpsPortalNavItem(
        portalSectionId: _portalSectionSupport,
        icon: Icons.support_agent_outlined,
        label: isArabic ? 'الدعم' : 'Support',
        badge: _refundPendingCount + _changePendingCount,
      ),
    ];
  }

  Future<void> _navigateToPortalSection(String portalSectionId) async {
    if (_selectedPortalSection != portalSectionId) {
      setState(() {
        _selectedPortalSection = portalSectionId;
        _persistConsoleUiState();
      });
      // Yield so the next paint can mount/unmount section-conditional widgets
      // before `_scrollToSection` resolves the target key's context.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) {
        return;
      }
    }
    switch (portalSectionId) {
      case _portalSectionToday:
        await _scrollToSection(_todaySectionKey);
        break;
      case _portalSectionTrips:
        await _focusWorkspace(_workspaceSalesFeeds, _feedHealthSectionKey);
        break;
      case _portalSectionSales:
        await _focusWorkspace(_workspaceSalesFeeds, _catalogImportSectionKey);
        break;
      case _portalSectionSettlements:
        await _focusWorkspace(_workspaceSettlements, _settlementSectionKey);
        break;
      case _portalSectionSupport:
        await _focusWorkspace(_workspaceSupport, _refundSectionKey);
        break;
    }
  }

  Widget _buildPortalNavigationRail(
    BuildContext context,
    bool isArabic,
    bool extended,
  ) {
    final items = _portalNavItems(isArabic);
    final selectedIndex = items.indexWhere(
      (item) => item.portalSectionId == _selectedPortalSection,
    );
    return NavigationRail(
      selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
      extended: extended,
      labelType: extended ? null : NavigationRailLabelType.all,
      onDestinationSelected: (index) {
        unawaited(_navigateToPortalSection(items[index].portalSectionId));
      },
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: IconButton(
          tooltip: isArabic ? 'تحديث' : 'Refresh queues',
          onPressed: _loadingQueues ? null : _loadQueues,
          icon: const Icon(Icons.refresh),
        ),
      ),
      destinations: [
        for (final item in items)
          NavigationRailDestination(
            icon: _portalNavIcon(context, item, selected: false),
            selectedIcon: _portalNavIcon(context, item, selected: true),
            label: Text(item.label),
          ),
      ],
    );
  }

  Widget _portalNavIcon(
    BuildContext context,
    _CoachOpsPortalNavItem item, {
    required bool selected,
  }) {
    final icon = Icon(item.icon);
    if (item.badge <= 0) {
      return icon;
    }
    return Badge(
      // Cap the visible number so a runaway alert count doesn't overflow
      // the rail tile width. Real alert volume above 99 is already an
      // ops-incident signal that a numeric badge can't convey anyway.
      label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
      isLabelVisible: true,
      child: icon,
    );
  }

  Widget _buildPortalDrawer(BuildContext context, bool isArabic) {
    final items = _portalNavItems(isArabic);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Text(
                isArabic ? 'عمليات الحافلات' : 'Coach Ops',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const Divider(height: 1),
            for (final item in items)
              ListTile(
                leading: _portalNavIcon(
                  context,
                  item,
                  selected: item.portalSectionId == _selectedPortalSection,
                ),
                title: Text(item.label),
                selected: item.portalSectionId == _selectedPortalSection,
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(
                    _navigateToPortalSection(item.portalSectionId),
                  );
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(isArabic ? 'تحديث' : 'Refresh queues'),
              enabled: !_loadingQueues,
              onTap: _loadingQueues
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      unawaited(_loadQueues());
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceFocusSection(
    BuildContext context,
    bool isArabic,
    List<_CoachOpsWorkspaceDescriptor> workspaces,
  ) {
    final visibleWorkspaceIds = _visibleWorkspaceIds(workspaces);
    final visibleCount =
        _selectedWorkspace == _workspaceAll ? workspaces.length : 1;
    final collapsedVisibleCount = visibleWorkspaceIds
        .where((workspaceId) => _collapsedWorkspaces.contains(workspaceId))
        .length;
    final selectedDescriptor =
        workspaces.cast<_CoachOpsWorkspaceDescriptor?>().firstWhere(
              (workspace) => workspace?.id == _selectedWorkspace,
              orElse: () => null,
            );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD6E7DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'تركيز المكاتب' : 'Desk focus',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF17362B),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'بدل التمرير عبر البوابة كلها، اختر مكتب العمل الحالي وابقِ باقي التفاصيل خارج الطريق.'
                : 'Pick the operator desk you are working right now instead of scrolling the whole portal.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF50675E),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                key: const ValueKey('coachOpsWorkspaceFocus_all'),
                label: Text(
                  isArabic
                      ? 'كل المكاتب (${workspaces.length})'
                      : 'All desks (${workspaces.length})',
                ),
                selected: _selectedWorkspace == _workspaceAll,
                onSelected: (selected) {
                  if (!selected) {
                    return;
                  }
                  _selectWorkspace(_workspaceAll);
                },
              ),
              for (final workspace in workspaces)
                ChoiceChip(
                  key: ValueKey('coachOpsWorkspaceFocus_${workspace.id}'),
                  avatar: Icon(
                    workspace.icon,
                    size: 18,
                    color: workspace.color,
                  ),
                  label: Text('${workspace.label} (${workspace.signalCount})'),
                  selected: _selectedWorkspace == workspace.id,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    _selectWorkspace(workspace.id);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('coachOpsCollapseVisible'),
                onPressed: visibleWorkspaceIds.isEmpty
                    ? null
                    : () => _collapseVisibleWorkspaces(workspaces),
                icon: const Icon(Icons.unfold_less_outlined),
                label: Text(isArabic ? 'طي المعروض' : 'Collapse visible'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('coachOpsExpandVisible'),
                onPressed: visibleWorkspaceIds.isEmpty
                    ? null
                    : () => _expandVisibleWorkspaces(workspaces),
                icon: const Icon(Icons.unfold_more_outlined),
                label: Text(isArabic ? 'توسيع المعروض' : 'Expand visible'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isArabic
                ? 'يتم عرض $visibleCount من ${workspaces.length} مكاتب'
                : 'Showing $visibleCount of ${workspaces.length} desks',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF526176),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            isArabic
                ? 'مطوي $collapsedVisibleCount من $visibleCount'
                : 'Collapsed $collapsedVisibleCount of $visibleCount',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
          ),
          if (selectedDescriptor != null) ...[
            const SizedBox(height: 4),
            Text(
              selectedDescriptor.detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
            ),
          ],
        ],
      ),
    );
  }

  void _handlePayoutImportDraftChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      if (_latestPayoutImportBatchResult?.dryRun ?? false) {
        _latestPayoutImportBatchResult = null;
      }
    });
  }

  Future<void> _loadPrivilegesAndQueues() async {
    final policy = await shamellResolveDashboardPolicy(
      context,
      baseUrl: widget.baseUrl,
      policyOverride: widget.dashboardPolicyOverride,
      privilegeSnapshotOverride: widget.privilegeSnapshotOverride,
    );
    final snapshot = policy.privilegeSnapshot;
    _privilegeSnapshot = snapshot;
    final persistedPreviewHistoryFilters =
        await _loadPersistedPayoutImportPreviewHistoryFilterPreferences();
    final persistedPayoutImportBatchFilters =
        await _loadPersistedPayoutImportBatchFilterPreferences();
    final persistedCatalogImportRunFilters =
        await _loadPersistedCatalogImportRunFilterPreferences();
    final persistedCatalogImportRunSavedViews =
        await _loadPersistedCatalogImportRunSavedViews();
    final persistedCatalogImportRunSavedViewPins = widget.api != null
        ? _catalogImportRunSavedViewFavoriteIds(
            persistedCatalogImportRunSavedViews,
          )
        : await _loadPersistedSavedViewPins(
            _catalogImportRunSavedViewUsageCollectionKey,
          );
    final persistedCatalogImportRunSavedViewUsage =
        await _loadPersistedSavedViewUsage(
      _catalogImportRunSavedViewUsageCollectionKey,
    );
    final persistedCatalogImportRunIssueSavedViewPins =
        await _loadPersistedSavedViewPins(
      _catalogImportRunIssueSavedViewUsageCollectionKey,
    );
    final persistedCatalogImportRunIssueSavedViewUsage =
        await _loadPersistedSavedViewUsage(
      _catalogImportRunIssueSavedViewUsageCollectionKey,
    );
    final persistedCatalogImportRunSavedViewOwners =
        await _loadPersistedCatalogImportRunSavedViewOwners();
    final persistedCatalogImportRunSavedViewOperators =
        await _loadPersistedCatalogImportRunSavedViewOperators();
    final defaultCatalogImportRunSavedView =
        persistedCatalogImportRunFilters.hasActiveFilters
            ? null
            : persistedCatalogImportRunSavedViews
                .cast<CoachCatalogImportRunSavedView?>()
                .firstWhere(
                  (view) => view?.isDefault ?? false,
                  orElse: () => null,
                );
    final effectiveCatalogImportRunFilters =
        defaultCatalogImportRunSavedView?.preferences ??
            persistedCatalogImportRunFilters;
    final persistedPreviewHistorySavedViews =
        await _loadPersistedPayoutImportPreviewHistorySavedViews();
    final persistedPreviewHistorySavedViewPins = widget.api != null
        ? _payoutImportPreviewSavedViewFavoriteIds(
            persistedPreviewHistorySavedViews,
          )
        : await _loadPersistedSavedViewPins(
            _payoutImportPreviewSavedViewUsageCollectionKey,
          );
    final persistedPreviewHistorySavedViewUsage =
        await _loadPersistedSavedViewUsage(
      _payoutImportPreviewSavedViewUsageCollectionKey,
    );
    final persistedPreviewHistorySavedViewOwners =
        await _loadPersistedPayoutImportPreviewSavedViewOwners();
    final persistedPreviewHistorySavedViewOperators =
        await _loadPersistedPayoutImportPreviewSavedViewOperators();
    final defaultPreviewHistorySavedView =
        persistedPreviewHistoryFilters.hasActiveFilters
            ? null
            : persistedPreviewHistorySavedViews
                .cast<CoachPayoutImportPreviewHistorySavedView?>()
                .firstWhere(
                  (view) => view?.isDefault ?? false,
                  orElse: () => null,
                );
    final effectivePreviewHistoryFilters =
        defaultPreviewHistorySavedView?.preferences ??
            persistedPreviewHistoryFilters;
    final persistedPayoutImportBatchSavedViews =
        await _loadPersistedPayoutImportBatchSavedViews();
    final persistedPayoutImportBatchSavedViewPins = widget.api != null
        ? _payoutImportBatchSavedViewFavoriteIds(
            persistedPayoutImportBatchSavedViews,
          )
        : await _loadPersistedSavedViewPins(
            _payoutImportBatchSavedViewUsageCollectionKey,
          );
    final persistedPayoutImportBatchSavedViewUsage =
        await _loadPersistedSavedViewUsage(
      _payoutImportBatchSavedViewUsageCollectionKey,
    );
    final persistedPayoutImportBatchSavedViewOwners =
        await _loadPersistedPayoutImportBatchSavedViewOwners();
    final persistedPayoutImportBatchSavedViewOperators =
        await _loadPersistedPayoutImportBatchSavedViewOperators();
    final defaultPayoutImportBatchSavedView =
        persistedPayoutImportBatchFilters.hasActiveFilters
            ? null
            : persistedPayoutImportBatchSavedViews
                .cast<CoachPayoutImportBatchSavedView?>()
                .firstWhere(
                  (view) => view?.isDefault ?? false,
                  orElse: () => null,
                );
    final effectivePayoutImportBatchFilters =
        defaultPayoutImportBatchSavedView?.preferences ??
            persistedPayoutImportBatchFilters;
    if (!mounted) return;
    setState(() {
      _privilegeSnapshot = snapshot;
      _accessAllowed =
          shamellDashboardAllowsCoachOperatorConsoleSnapshot(snapshot);
      _financeMutationsAllowed =
          shamellDashboardAllowsCoachOperatorFinanceMutationsSnapshot(snapshot);
      _catalogImportMutationsAllowed =
          shamellDashboardAllowsCoachOperatorCatalogMutationsSnapshot(snapshot);
      _hydratePayoutImportPreviewHistoryDraftFromPreferences(
        effectivePreviewHistoryFilters,
      );
      _hydratePayoutImportBatchFiltersFromPreferences(
        effectivePayoutImportBatchFilters,
      );
      _hydrateCatalogImportRunFiltersFromPreferences(
        effectiveCatalogImportRunFilters,
      );
      _catalogImportRunSavedViews = persistedCatalogImportRunSavedViews;
      _catalogImportRunSavedViewPinnedIds =
          persistedCatalogImportRunSavedViewPins;
      _catalogImportRunSavedViewUsedAtById = widget.api != null
          ? _catalogImportRunSavedViewUsageMap(
              persistedCatalogImportRunSavedViews,
            )
          : persistedCatalogImportRunSavedViewUsage;
      _catalogImportRunIssueSavedViewPinnedIds =
          persistedCatalogImportRunIssueSavedViewPins;
      _catalogImportRunIssueSavedViewUsedAtById =
          persistedCatalogImportRunIssueSavedViewUsage;
      _catalogImportRunSavedViewOwners =
          persistedCatalogImportRunSavedViewOwners;
      _catalogImportRunSavedViewOperators =
          persistedCatalogImportRunSavedViewOperators;
      _payoutImportPreviewSavedViews = persistedPreviewHistorySavedViews;
      _payoutImportPreviewSavedViewPinnedIds =
          persistedPreviewHistorySavedViewPins;
      _payoutImportPreviewSavedViewUsedAtById = widget.api != null
          ? _payoutImportPreviewSavedViewUsageMap(
              persistedPreviewHistorySavedViews,
            )
          : persistedPreviewHistorySavedViewUsage;
      _payoutImportPreviewSavedViewOwners =
          persistedPreviewHistorySavedViewOwners;
      _payoutImportPreviewSavedViewOperators =
          persistedPreviewHistorySavedViewOperators;
      _payoutImportBatchSavedViews = persistedPayoutImportBatchSavedViews;
      _payoutImportBatchSavedViewPinnedIds =
          persistedPayoutImportBatchSavedViewPins;
      _payoutImportBatchSavedViewUsedAtById = widget.api != null
          ? _payoutImportBatchSavedViewUsageMap(
              persistedPayoutImportBatchSavedViews,
            )
          : persistedPayoutImportBatchSavedViewUsage;
      _payoutImportBatchSavedViewOwners =
          persistedPayoutImportBatchSavedViewOwners;
      _payoutImportBatchSavedViewOperators =
          persistedPayoutImportBatchSavedViewOperators;
      _loadingPrivileges = false;
    });
    if (_accessAllowed &&
        widget.initialRefundQueue != null &&
        widget.initialChangeQueue != null &&
        widget.initialReconciliation != null &&
        widget.initialSettlementStatements != null &&
        widget.initialPayoutRuns != null &&
        widget.initialPayoutReconciliation != null &&
        widget.initialPayoutImports != null &&
        widget.initialPayoutImportPreviews != null &&
        widget.initialPayoutImportBatches != null &&
        widget.initialPayoutImportProfiles != null) {
      setState(() {
        _refundGeneratedAtIso = widget.initialRefundQueue!.generatedAtIso;
        _changeGeneratedAtIso = widget.initialChangeQueue!.generatedAtIso;
        _reconciliation = widget.initialReconciliation!;
        _settlementStatements = widget.initialSettlementStatements!;
        _payoutRuns = widget.initialPayoutRuns!;
        _payoutReconciliation = widget.initialPayoutReconciliation!;
        _operatorFeedHealth = widget.initialOperatorFeedHealth;
        _catalogImportConfig = widget.initialCatalogImportConfig;
        _catalogImportSources = widget.initialCatalogImportSources;
        _catalogSourceArtifacts = widget.initialCatalogSourceArtifacts;
        _syncCatalogImportConfigDraft(widget.initialCatalogImportConfig);
        _catalogImportRuns = widget.initialCatalogImportRuns;
        _payoutImports = widget.initialPayoutImports!;
        _payoutImportPreviews = widget.initialPayoutImportPreviews!;
        _payoutImportPreviewHistory = widget.initialPayoutImportPreviews!;
        _payoutImportBatches = widget.initialPayoutImportBatches!;
        _payoutImportProfiles = widget.initialPayoutImportProfiles!;
        _payoutImportPreviewHistoryErrorMessage = null;
        _loadingPayoutImportPreviewHistory = false;
        _loadingMorePayoutImportPreviewHistory = false;
        _loadingMoreCatalogImportRuns = false;
        _loadingMorePayoutImports = false;
        _loadingMorePayoutImportBatches = false;
        _refundRequests = widget.initialRefundQueue!.requests;
        _changeRequests = widget.initialChangeQueue!.requests;
      });
      if (_hasActiveCatalogImportRunFilters) {
        await _reloadCatalogImportRuns();
      }
      if (_hasRemotePayoutImportPreviewHistoryFilters) {
        await _loadPayoutImportPreviewHistory(showBusy: false);
      }
      return;
    }
    if (_accessAllowed) {
      await _loadQueues();
    }
  }

  Future<void> _loadQueues() async {
    setState(() {
      _loadingQueues = true;
      _errorMessage = null;
      _loadingMoreSettlementStatements = false;
      _loadingMorePayoutRuns = false;
      _loadingMorePayoutReconciliation = false;
      if (_hasRemotePayoutImportPreviewHistoryFilters) {
        _loadingPayoutImportPreviewHistory = true;
        _loadingMorePayoutImportPreviewHistory = false;
        _loadingMoreCatalogSourceArtifacts = false;
        _loadingMoreCatalogImportRuns = false;
        _loadingMorePayoutImports = false;
        _loadingMorePayoutImportBatches = false;
        _payoutImportPreviewHistoryErrorMessage = null;
      }
    });
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        _api.operatorRefundQueue(limit: 16),
        _api.operatorChangeQueue(limit: 16),
        _api.operatorReconciliation(limit: 8),
        _api.operatorSettlementStatements(limit: 6),
        _api.operatorPayoutRuns(limit: 8),
        _api.operatorPayoutReconciliation(limit: 8),
        _api.operatorFeedHealth(),
        _api.operatorCatalogImportConfig(),
        _api.operatorCatalogImportSources(),
        _api.operatorCatalogSourceArtifacts(limit: 8),
        _api.operatorCatalogImportRuns(
          limit: 8,
          status: _catalogImportRunStatusFilter,
          replayScope: _catalogImportRunReplayScopeFilter,
          issueSeverity: _catalogImportRunIssueSeverityFilter,
          issueStage: _catalogImportRunIssueStageFilter,
        ),
        _api.operatorPayoutImports(limit: 8),
        _api.operatorPayoutImportPreviews(limit: 8),
        _api.operatorPayoutImportBatches(limit: 8),
        _api.operatorPayoutImportProfiles(),
      ]);
      if (!mounted) return;
      final refundQueue = results[0] as CoachOperatorRefundQueueResponse;
      final changeQueue = results[1] as CoachOperatorChangeQueueResponse;
      final reconciliation = results[2] as CoachOperatorReconciliationResponse;
      final settlementStatements =
          results[3] as CoachOperatorSettlementStatementsResponse;
      final payoutRuns = results[4] as CoachOperatorPayoutRunsResponse;
      final payoutReconciliation =
          results[5] as CoachOperatorPayoutReconciliationResponse;
      final operatorFeedHealth = results[6] as CoachOperatorFeedHealthResponse;
      final catalogImportConfig =
          results[7] as CoachOperatorCatalogImportConfigResponse;
      final catalogImportSources =
          results[8] as CoachOperatorCatalogImportSourcesResponse;
      final catalogSourceArtifacts =
          results[9] as CoachOperatorCatalogSourceArtifactsResponse;
      final catalogImportRuns =
          results[10] as CoachOperatorCatalogImportRunsResponse;
      final payoutImports = results[11] as CoachOperatorPayoutImportsResponse;
      final payoutImportPreviews =
          results[12] as CoachOperatorPayoutImportPreviewsResponse;
      final payoutImportBatches =
          results[13] as CoachOperatorPayoutImportBatchesResponse;
      final payoutImportProfiles =
          results[14] as CoachOperatorPayoutImportProfilesResponse;
      setState(() {
        _refundGeneratedAtIso = refundQueue.generatedAtIso;
        _changeGeneratedAtIso = changeQueue.generatedAtIso;
        _reconciliation = reconciliation;
        _settlementStatements = settlementStatements;
        _loadingMoreSettlementStatements = false;
        _payoutRuns = payoutRuns;
        _loadingMorePayoutRuns = false;
        _payoutReconciliation = payoutReconciliation;
        _loadingMorePayoutReconciliation = false;
        _operatorFeedHealth = operatorFeedHealth;
        _catalogImportConfig = catalogImportConfig;
        _catalogImportSources = catalogImportSources;
        _catalogSourceArtifacts = catalogSourceArtifacts;
        _syncCatalogImportConfigDraft(catalogImportConfig);
        _catalogImportRuns = catalogImportRuns;
        _loadingMoreCatalogSourceArtifacts = false;
        _loadingMoreCatalogImportRuns = false;
        _payoutImports = payoutImports;
        _loadingMorePayoutImports = false;
        _payoutImportPreviews = payoutImportPreviews;
        if (!_hasRemotePayoutImportPreviewHistoryFilters) {
          _payoutImportPreviewHistory = payoutImportPreviews;
          _payoutImportPreviewHistoryErrorMessage = null;
          _loadingPayoutImportPreviewHistory = false;
          _loadingMorePayoutImportPreviewHistory = false;
        }
        _payoutImportBatches = payoutImportBatches;
        _loadingMorePayoutImportBatches = false;
        _payoutImportProfiles = payoutImportProfiles;
        if (_selectedPayoutImportReworkOfBatchId != null &&
            !payoutImportBatches.batches.any(
              (batch) => batch.batchId == _selectedPayoutImportReworkOfBatchId,
            )) {
          _selectedPayoutImportReworkOfBatchId = null;
        }
        _refundRequests = refundQueue.requests;
        _changeRequests = changeQueue.requests;
        _loadingQueues = false;
      });
      if (_hasActiveCatalogImportRunFilters) {
        await _reloadCatalogImportRuns();
      }
      if (_hasRemotePayoutImportPreviewHistoryFilters) {
        await _loadPayoutImportPreviewHistory(showBusy: false);
      }
    } on CoachApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.detail;
        _loadingQueues = false;
        _loadingPayoutImportPreviewHistory = false;
        _loadingMorePayoutImportPreviewHistory = false;
        _loadingMoreSettlementStatements = false;
        _loadingMorePayoutRuns = false;
        _loadingMorePayoutReconciliation = false;
        _loadingMoreCatalogImportRuns = false;
        _loadingMorePayoutImports = false;
        _loadingMorePayoutImportBatches = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loadingQueues = false;
        _loadingPayoutImportPreviewHistory = false;
        _loadingMorePayoutImportPreviewHistory = false;
        _loadingMoreSettlementStatements = false;
        _loadingMorePayoutRuns = false;
        _loadingMorePayoutReconciliation = false;
        _loadingMoreCatalogImportRuns = false;
        _loadingMorePayoutImports = false;
        _loadingMorePayoutImportBatches = false;
      });
    }
  }

  Future<void> _reviewRefund(
    CoachOperatorRefundQueueEntry entry, {
    required bool approve,
  }) async {
    setState(() {
      _reviewingRefundIds.add(entry.refundRequestId);
    });
    try {
      final result = await _api.reviewRefundRequest(
        refundRequestId: entry.refundRequestId,
        approve: approve,
        note: approve
            ? 'approved in coach ops console'
            : 'rejected in coach ops console',
      );
      if (!mounted) return;
      setState(() {
        _refundRequests = _refundRequests
            .map(
              (value) => value.refundRequestId == result.request.refundRequestId
                  ? result.request
                  : value,
            )
            .toList(growable: false);
      });
      await _loadQueues();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Refund request approved.' : 'Refund request rejected.',
          ),
        ),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _reviewingRefundIds.remove(entry.refundRequestId);
        });
      }
    }
  }

  Future<void> _reviewChange(
    CoachOperatorChangeQueueEntry entry, {
    required bool approve,
  }) async {
    setState(() {
      _reviewingChangeIds.add(entry.changeRequestId);
    });
    try {
      final result = await _api.reviewChangeRequest(
        changeRequestId: entry.changeRequestId,
        approve: approve,
        note: approve
            ? 'approved in coach ops console'
            : 'rejected in coach ops console',
      );
      if (!mounted) return;
      setState(() {
        _changeRequests = _changeRequests
            .map(
              (value) => value.changeRequestId == result.request.changeRequestId
                  ? result.request
                  : value,
            )
            .toList(growable: false);
      });
      await _loadQueues();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve
              ? 'Change request approved.'
              : 'Change request rejected.'),
        ),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _reviewingChangeIds.remove(entry.changeRequestId);
        });
      }
    }
  }

  Future<void> _queuePayoutRun(
      CoachOperatorSettlementStatement statement) async {
    setState(() {
      _creatingPayoutStatementIds.add(statement.statementId);
    });
    try {
      await _api.createOperatorPayoutRun(
        statementIds: <String>[statement.statementId],
        note: 'queued from coach ops console',
      );
      await _loadQueues();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout run queued.')),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingPayoutStatementIds.remove(statement.statementId);
        });
      }
    }
  }

  Future<void> _markPayoutRunPaid(CoachOperatorPayoutRun run) async {
    setState(() {
      _markingPaidRunIds.add(run.payoutRunId);
    });
    try {
      await _api.markOperatorPayoutRunPaid(
        payoutRunId: run.payoutRunId,
        paymentReference: 'payout_batch_2026w15',
        note: 'paid from coach ops console',
      );
      await _loadQueues();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout marked as paid.')),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingPaidRunIds.remove(run.payoutRunId);
        });
      }
    }
  }

  String _payoutExportBusyKey(String payoutRunId, String exportFormat) =>
      '$payoutRunId::$exportFormat';

  Future<void> _createPayoutExport(
    CoachOperatorPayoutRun run,
    String exportFormat,
  ) async {
    final busyKey = _payoutExportBusyKey(run.payoutRunId, exportFormat);
    setState(() {
      _creatingExportKeys.add(busyKey);
    });
    try {
      await _api.createOperatorPayoutRunExport(
        payoutRunId: run.payoutRunId,
        exportFormat: exportFormat,
        note: 'prepared from coach ops console',
      );
      await _loadQueues();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$exportFormat export is ready.')),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingExportKeys.remove(busyKey);
        });
      }
    }
  }

  String _payoutImportBusyKey(String payoutRunId, String externalStatus) =>
      '$payoutRunId::$externalStatus';

  Future<void> _applyPayoutImport(
    CoachOperatorPayoutRun run,
    String externalStatus,
  ) async {
    final busyKey = _payoutImportBusyKey(run.payoutRunId, externalStatus);
    setState(() {
      _creatingImportKeys.add(busyKey);
    });
    try {
      await _api.createOperatorPayoutImport(
        payoutRunId: run.payoutRunId,
        importSource: 'bank_report',
        externalStatus: externalStatus,
        paymentReference: externalStatus == 'executed'
            ? 'bank_import_${run.payoutRunId}'
            : null,
        externalReference: 'bank_file_2026w15',
        note: externalStatus == 'executed'
            ? 'executed import applied from coach ops console'
            : 'failed import applied from coach ops console',
      );
      await _loadQueues();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout import applied.')),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingImportKeys.remove(busyKey);
        });
      }
    }
  }

  Future<void> _applyPayoutImportBatch({required bool dryRun}) async {
    final validation = _payoutImportDraftValidation;
    final previewEcho = !dryRun ? _latestFreshPayoutImportPreviewEcho : null;
    if (!dryRun && validation != null && !validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Resolve local CSV validation issues before applying the payout report.',
          ),
        ),
      );
      return;
    }
    if (!dryRun && previewEcho == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Run Preview report on the current draft before applying the payout report.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (dryRun) {
        _previewingImportBatch = true;
      } else {
        _creatingImportBatch = true;
      }
    });
    try {
      final selectedFile = _selectedPayoutImportFile;
      final result = selectedFile == null
          ? await _api.createOperatorPayoutImportBatch(
              importSource: _selectedPayoutImportSource,
              reportName: _payoutImportReportNameController.text.trim(),
              reportBody: _payoutImportReportBodyController.text,
              reworkOfBatchId: _selectedPayoutImportReworkOfBatchId,
              expectedPreviewToken: previewEcho?.previewToken,
              dryRun: dryRun,
              note: 'uploaded from coach ops console',
            )
          : await _api.uploadOperatorPayoutImportBatchFile(
              importSource: _selectedPayoutImportSource,
              reportName: _payoutImportReportNameController.text.trim(),
              fileName: selectedFile.fileName,
              fileBytes: selectedFile.bytes,
              reworkOfBatchId: _selectedPayoutImportReworkOfBatchId,
              expectedPreviewToken: previewEcho?.previewToken,
              dryRun: dryRun,
              note: 'uploaded from coach ops console',
            );
      if (!dryRun) {
        await _loadQueues();
      }
      if (!mounted) return;
      final summary = result.dryRun
          ? '${result.batch.appliedRows} ready, ${result.batch.failedRows} blocked.'
          : '${result.batch.appliedRows} applied, ${result.batch.failedRows} failed.';
      setState(() {
        _latestPayoutImportBatchResult = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.dryRun
                ? 'Payout import preview ready: $summary'
                : 'Payout import batch processed: $summary',
          ),
        ),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (dryRun) {
            _previewingImportBatch = false;
          } else {
            _creatingImportBatch = false;
          }
        });
      }
    }
  }

  Future<void> _invalidatePayoutImportPreview(String previewToken) async {
    final normalizedPreviewToken = previewToken.trim();
    if (normalizedPreviewToken.isEmpty) {
      return;
    }
    setState(() {
      _invalidatingPreviewTokens.add(normalizedPreviewToken);
    });
    try {
      final result = await _api.invalidateOperatorPayoutImportPreview(
        previewToken: normalizedPreviewToken,
      );
      await _loadQueues();
      if (!mounted) return;
      final latestPreviewToken =
          _latestPayoutImportBatchResult?.previewEcho?.previewToken.trim();
      setState(() {
        if (latestPreviewToken == normalizedPreviewToken) {
          _latestPayoutImportBatchResult = null;
        }
      });
      late final String message;
      switch (result.nextAction) {
        case 'preview_invalidated':
          message = 'Preview invalidated.';
          break;
        case 'preview_already_invalidated':
          message = 'Preview was already invalidated.';
          break;
        case 'preview_already_consumed':
          message = 'Preview was already consumed.';
          break;
        case 'preview_already_expired':
          message = 'Preview had already expired.';
          break;
        default:
          message = 'Preview state updated.';
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _invalidatingPreviewTokens.remove(normalizedPreviewToken);
        });
      }
    }
  }

  CoachOperatorPayoutImportProfile? get _selectedPayoutImportProfile {
    final profiles = _payoutImportProfiles?.profiles ??
        const <CoachOperatorPayoutImportProfile>[];
    for (final profile in profiles) {
      if (profile.importSource == _selectedPayoutImportSource) {
        return profile;
      }
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  void _setSelectedPayoutImportSource(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == _selectedPayoutImportSource) {
      return;
    }
    final fileStem = normalized.replaceAll('_report', '').replaceAll('_', '-');
    setState(() {
      _selectedPayoutImportSource = normalized;
      _selectedPayoutImportReworkOfBatchId = null;
      _loadingReworkSeed = false;
      _loadedReworkSeedBody = null;
      _payoutImportReportNameController.text = '${fileStem}_2026w15.csv';
      _latestPayoutImportBatchResult = null;
    });
    _loadSelectedPayoutImportProfileSample();
  }

  List<CoachOperatorPayoutImportBatch> get _eligibleReworkSourceBatches {
    final batches = _payoutImportBatches?.batches ??
        const <CoachOperatorPayoutImportBatch>[];
    return batches
        .where((batch) => batch.failedRows > 0 && batch.reworkArtifact != null)
        .toList(growable: false);
  }

  CoachOperatorPayoutImportBatch? get _selectedReworkSourceBatch {
    final selectedId = _selectedPayoutImportReworkOfBatchId;
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }
    for (final batch in _eligibleReworkSourceBatches) {
      if (batch.batchId == selectedId) {
        return batch;
      }
    }
    return null;
  }

  String _normalizePayoutImportOperatorIdFilterValue(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return 'all';
    }
    return normalized;
  }

  bool _matchesPayoutImportOperatorFilter(
    List<String> operatorIds,
    String operatorId,
  ) {
    final normalizedOperatorId = operatorId.trim();
    if (normalizedOperatorId.isEmpty || normalizedOperatorId == 'all') {
      return true;
    }
    return operatorIds.any((value) => value.trim() == normalizedOperatorId);
  }

  List<String> _payoutImportOperatorFilterOptionsFromScopes(
    Iterable<List<String>> operatorScopes,
    String selectedOperatorId,
  ) {
    final options = operatorScopes
        .expand((scope) => scope)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: true)
      ..sort();
    final normalizedSelected =
        _normalizePayoutImportOperatorIdFilterValue(selectedOperatorId);
    if (normalizedSelected != 'all' && !options.contains(normalizedSelected)) {
      options.insert(0, normalizedSelected);
    }
    return <String>['all', ...options];
  }

  List<String> get _payoutImportPreviewHistoryOperatorFilterOptions {
    final previews = _payoutImportPreviewHistory?.previews ??
        _payoutImportPreviews?.previews ??
        const <CoachOperatorPayoutImportPreview>[];
    return _payoutImportOperatorFilterOptionsFromScopes(
      previews.map((entry) => entry.operatorIds),
      _selectedPayoutImportPreviewOperatorIdFilter,
    );
  }

  List<String> get _payoutImportBatchOperatorFilterOptions {
    final batches = _payoutImportBatches?.batches ??
        const <CoachOperatorPayoutImportBatch>[];
    return _payoutImportOperatorFilterOptionsFromScopes(
      batches.map((entry) => entry.operatorIds),
      _selectedPayoutImportBatchOperatorIdFilter,
    );
  }

  String? get _payoutImportPreviewHistoryOperatorIdFilter {
    final normalized = _normalizePayoutImportOperatorIdFilterValue(
      _selectedPayoutImportPreviewOperatorIdFilter,
    );
    if (normalized == 'all') {
      return null;
    }
    return normalized;
  }

  String? get _payoutImportBatchOperatorIdFilter {
    final normalized = _normalizePayoutImportOperatorIdFilterValue(
      _selectedPayoutImportBatchOperatorIdFilter,
    );
    if (normalized == 'all') {
      return null;
    }
    return normalized;
  }

  List<CoachOperatorPayoutImportPreview>
      get _visiblePayoutImportPreviewHistory {
    final previews = _payoutImportPreviewHistory?.previews ??
        const <CoachOperatorPayoutImportPreview>[];
    final operatorId = _payoutImportPreviewHistoryOperatorIdFilter;
    if (operatorId == null) {
      return previews;
    }
    return previews
        .where(
          (entry) => _matchesPayoutImportOperatorFilter(
            entry.operatorIds,
            operatorId,
          ),
        )
        .toList(growable: false);
  }

  List<CoachOperatorPayoutImportBatch> get _visiblePayoutImportBatches {
    final batches = _payoutImportBatches?.batches ??
        const <CoachOperatorPayoutImportBatch>[];
    final operatorId = _payoutImportBatchOperatorIdFilter;
    if (operatorId == null) {
      return batches;
    }
    return batches
        .where(
          (entry) => _matchesPayoutImportOperatorFilter(
            entry.operatorIds,
            operatorId,
          ),
        )
        .toList(growable: false);
  }

  List<CoachPayoutImportPreviewHistorySavedView>
      get _visiblePayoutImportPreviewSavedViews {
    final visibilityScope = _normalizeCatalogSavedViewVisibilityFilter(
      _payoutImportPreviewSavedViewsVisibilityFilter,
    );
    final visibilityFiltered = visibilityScope == 'all'
        ? _payoutImportPreviewSavedViews
        : _payoutImportPreviewSavedViews
            .where((entry) => entry.visibilityScope == visibilityScope)
            .toList(growable: false);
    if (visibilityScope != 'shared_ops') {
      return _prioritizeSavedViews(
        visibilityFiltered,
        isCurrent: _payoutImportPreviewSavedViewIsCurrent,
        isDefault: (view) => view.isDefault,
        viewIdOf: (view) => view.viewId,
        pinnedViewIds: _payoutImportPreviewSavedViewPinnedIds,
        usedAtById: _payoutImportPreviewSavedViewUsedAtById,
      );
    }
    final ownerFiltered = _filterPayoutImportPreviewSavedViewsByOwnerAccountId(
      visibilityFiltered,
      _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
    );
    return _prioritizeSavedViews(
      _filterPayoutImportPreviewSavedViewsByOperatorId(
        ownerFiltered,
        _payoutImportPreviewSavedViewsOperatorIdFilter,
      ),
      isCurrent: _payoutImportPreviewSavedViewIsCurrent,
      isDefault: (view) => view.isDefault,
      viewIdOf: (view) => view.viewId,
      pinnedViewIds: _payoutImportPreviewSavedViewPinnedIds,
      usedAtById: _payoutImportPreviewSavedViewUsedAtById,
    );
  }

  List<CoachPayoutImportBatchSavedView>
      get _visiblePayoutImportBatchSavedViews {
    final visibilityScope = _normalizeCatalogSavedViewVisibilityFilter(
      _payoutImportBatchSavedViewsVisibilityFilter,
    );
    final visibilityFiltered = visibilityScope == 'all'
        ? _payoutImportBatchSavedViews
        : _payoutImportBatchSavedViews
            .where((entry) => entry.visibilityScope == visibilityScope)
            .toList(growable: false);
    if (visibilityScope != 'shared_ops') {
      return _prioritizeSavedViews(
        visibilityFiltered,
        isCurrent: _payoutImportBatchSavedViewIsCurrent,
        isDefault: (view) => view.isDefault,
        viewIdOf: (view) => view.viewId,
        pinnedViewIds: _payoutImportBatchSavedViewPinnedIds,
        usedAtById: _payoutImportBatchSavedViewUsedAtById,
      );
    }
    final ownerFiltered = _filterPayoutImportBatchSavedViewsByOwnerAccountId(
      visibilityFiltered,
      _payoutImportBatchSavedViewsOwnerAccountIdFilter,
    );
    return _prioritizeSavedViews(
      _filterPayoutImportBatchSavedViewsByOperatorId(
        ownerFiltered,
        _payoutImportBatchSavedViewsOperatorIdFilter,
      ),
      isCurrent: _payoutImportBatchSavedViewIsCurrent,
      isDefault: (view) => view.isDefault,
      viewIdOf: (view) => view.viewId,
      pinnedViewIds: _payoutImportBatchSavedViewPinnedIds,
      usedAtById: _payoutImportBatchSavedViewUsedAtById,
    );
  }

  Future<void> _setSelectedPayoutImportReworkSourceBatch(
      String? batchId) async {
    final normalized = batchId?.trim();
    final effectiveId =
        normalized == null || normalized.isEmpty ? null : normalized;
    CoachOperatorPayoutImportBatch? selectedBatch;
    if (effectiveId != null) {
      for (final batch in _eligibleReworkSourceBatches) {
        if (batch.batchId == effectiveId) {
          selectedBatch = batch;
          break;
        }
      }
    }
    final seedArtifact = selectedBatch?.reworkArtifact;
    setState(() {
      _selectedPayoutImportReworkOfBatchId = effectiveId;
      if (selectedBatch != null) {
        _selectedPayoutImportSource = selectedBatch.importSource;
        _payoutImportReportNameController.text = seedArtifact?.fileName ??
            'coach-payout-import-rework-${selectedBatch.batchId}.csv';
        _selectedPayoutImportFile = null;
      }
      _loadingReworkSeed = seedArtifact != null;
      _loadedReworkSeedBody = null;
      _latestPayoutImportBatchResult = null;
    });
    if (seedArtifact == null) {
      return;
    }
    try {
      final reportBody =
          await _api.fetchPayoutImportReportBody(seedArtifact.downloadPath);
      if (!mounted) return;
      if (_selectedPayoutImportReworkOfBatchId != effectiveId) {
        setState(() {
          _loadingReworkSeed = false;
        });
        return;
      }
      setState(() {
        _payoutImportReportBodyController.text = reportBody;
        _loadedReworkSeedBody = reportBody;
        _loadingReworkSeed = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (_selectedPayoutImportReworkOfBatchId == effectiveId) {
          _loadedReworkSeedBody = null;
          _loadingReworkSeed = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    }
  }

  void _loadSelectedPayoutImportProfileSample() {
    final profile = _selectedPayoutImportProfile;
    if (profile == null) return;
    setState(() {
      _loadedReworkSeedBody = null;
      _payoutImportReportBodyController.text = profile.sampleBody;
      _latestPayoutImportBatchResult = null;
    });
  }

  Future<CoachPickedPayoutImportFile?> _pickPayoutImportFile() async {
    if (widget.pickPayoutImportFileOverride != null) {
      return widget.pickPayoutImportFileOverride!();
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['csv', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const CoachApiException('selected payout import file is empty');
    }
    final fileName = file.name.trim().isEmpty
        ? 'payout_import_report.csv'
        : file.name.trim();
    return CoachPickedPayoutImportFile(fileName: fileName, bytes: bytes);
  }

  Future<CoachPickedCatalogImportFile?> _pickCatalogImportFile() async {
    if (widget.pickCatalogImportFileOverride != null) {
      return widget.pickCatalogImportFileOverride!();
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const CoachApiException('selected GTFS archive is empty');
    }
    final fileName =
        file.name.trim().isEmpty ? 'coach_gtfs_upload.zip' : file.name.trim();
    return CoachPickedCatalogImportFile(fileName: fileName, bytes: bytes);
  }

  Future<void> _selectPayoutImportFile() async {
    try {
      final picked = await _pickPayoutImportFile();
      if (!mounted || picked == null) return;
      setState(() {
        _selectedPayoutImportFile = picked;
        _loadedReworkSeedBody = null;
        _payoutImportReportNameController.text = picked.fileName;
        _latestPayoutImportBatchResult = null;
      });
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    }
  }

  Future<void> _selectCatalogImportFile() async {
    try {
      final picked = await _pickCatalogImportFile();
      if (!mounted || picked == null) return;
      setState(() {
        _selectedCatalogImportFile = picked;
      });
    } on CoachApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _clearSelectedPayoutImportFile() {
    setState(() {
      _selectedPayoutImportFile = null;
      _latestPayoutImportBatchResult = null;
    });
  }

  String get _activePayoutImportDraftBody {
    final selectedFile = _selectedPayoutImportFile;
    if (selectedFile == null) {
      return _payoutImportReportBodyController.text;
    }
    return utf8.decode(selectedFile.bytes, allowMalformed: true);
  }

  CoachPayoutImportReworkDeltaSummary? get _selectedReworkDraftDelta {
    final selectedBatch = _selectedReworkSourceBatch;
    final seedBody = _loadedReworkSeedBody;
    if (selectedBatch == null || seedBody == null) {
      return null;
    }
    return buildCoachPayoutImportReworkDelta(
      sourceBatch: selectedBatch,
      seedBody: seedBody,
      draftBody: _payoutImportReportBodyController.text,
    );
  }

  CoachPayoutImportDraftValidationSummary? get _payoutImportDraftValidation {
    final profile = _selectedPayoutImportProfile;
    if (profile == null) {
      return null;
    }
    return buildCoachPayoutImportDraftValidation(
      profile: profile,
      draftBody: _activePayoutImportDraftBody,
    );
  }

  bool get _hasBlockingPayoutImportValidationIssues =>
      (_payoutImportDraftValidation?.isValid ?? true) == false;

  CoachPayoutImportDraftAutoFixResult? get _payoutImportDraftAutoFix {
    final profile = _selectedPayoutImportProfile;
    if (profile == null) {
      return null;
    }
    return buildCoachPayoutImportDraftAutoFix(
      profile: profile,
      draftBody: _activePayoutImportDraftBody,
    );
  }

  String get _normalizedPayoutImportDraftBodyForChecksum {
    var normalized = _activePayoutImportDraftBody;
    if (normalized.startsWith('\u{feff}')) {
      normalized = normalized.substring(1);
    }
    return normalized.trim();
  }

  String get _currentPayoutImportDraftChecksumSha256 => crypto.sha256
      .convert(utf8.encode(_normalizedPayoutImportDraftBodyForChecksum))
      .toString();

  CoachOperatorPayoutImportPreviewEcho?
      get _latestFreshPayoutImportPreviewEcho {
    final result = _latestPayoutImportBatchResult;
    if (result == null || !result.dryRun) {
      return null;
    }
    final previewEcho = result.previewEcho;
    if (previewEcho == null) {
      return null;
    }
    if (previewEcho.reportChecksumSha256 !=
        _currentPayoutImportDraftChecksumSha256) {
      return null;
    }
    if (!previewEcho.isUsableAt(DateTime.now().toUtc())) {
      return null;
    }
    return previewEcho;
  }

  Future<void> _applySuggestedPayoutImportFixes() async {
    final autoFix = _payoutImportDraftAutoFix;
    if (autoFix == null || !autoFix.hasChanges) {
      return;
    }
    final movedFromFileUpload = _selectedPayoutImportFile != null;
    setState(() {
      _payoutImportReportBodyController.text = autoFix.correctedBody;
      _selectedPayoutImportFile = null;
      _latestPayoutImportBatchResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          movedFromFileUpload
              ? 'Applied ${autoFix.totalFixCount} safe fixes and moved the CSV into the editable draft.'
              : 'Applied ${autoFix.totalFixCount} safe fixes to the CSV draft.',
        ),
      ),
    );
  }

  String? get _draftPayoutImportPreviewStatusFilter {
    final normalized = _selectedPayoutImportPreviewStatusFilter.trim();
    if (normalized.isEmpty || normalized == 'all') {
      return null;
    }
    return normalized;
  }

  String? get _draftPayoutImportPreviewFromCreatedAtIso {
    final normalized = _payoutImportPreviewFromCreatedAtController.text.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? get _draftPayoutImportPreviewToCreatedAtIso {
    final normalized = _payoutImportPreviewToCreatedAtController.text.trim();
    return normalized.isEmpty ? null : normalized;
  }

  CoachPayoutImportPreviewHistoryFilterPreferences
      get _draftPayoutImportPreviewHistoryPreferences {
    return CoachPayoutImportPreviewHistoryFilterPreferences(
      status: _selectedPayoutImportPreviewStatusFilter,
      fromCreatedAtIso: _draftPayoutImportPreviewFromCreatedAtIso,
      toCreatedAtIso: _draftPayoutImportPreviewToCreatedAtIso,
      operatorId: _selectedPayoutImportPreviewOperatorIdFilter,
    );
  }

  bool get _hasRemotePayoutImportPreviewHistoryFilters {
    return _appliedPayoutImportPreviewStatusFilter != null ||
        _appliedPayoutImportPreviewFromCreatedAtIso != null ||
        _appliedPayoutImportPreviewToCreatedAtIso != null;
  }

  bool get _hasActivePayoutImportPreviewHistoryFilters {
    return _hasRemotePayoutImportPreviewHistoryFilters ||
        _payoutImportPreviewHistoryOperatorIdFilter != null;
  }

  bool get _hasDraftPayoutImportPreviewHistoryFilters {
    return _draftPayoutImportPreviewStatusFilter != null ||
        _draftPayoutImportPreviewFromCreatedAtIso != null ||
        _draftPayoutImportPreviewToCreatedAtIso != null ||
        _payoutImportPreviewHistoryOperatorIdFilter != null;
  }

  bool get _payoutImportPreviewHistoryFiltersDirty {
    return _draftPayoutImportPreviewStatusFilter !=
            _appliedPayoutImportPreviewStatusFilter ||
        _draftPayoutImportPreviewFromCreatedAtIso !=
            _appliedPayoutImportPreviewFromCreatedAtIso ||
        _draftPayoutImportPreviewToCreatedAtIso !=
            _appliedPayoutImportPreviewToCreatedAtIso;
  }

  String _describePayoutImportPreviewHistoryPreferences(
    CoachPayoutImportPreviewHistoryFilterPreferences preferences,
  ) {
    return '${preferences.status}'
        '${preferences.fromCreatedAtIso == null ? '' : ' • from ${preferences.fromCreatedAtIso}'}'
        '${preferences.toCreatedAtIso == null ? '' : ' • to ${preferences.toCreatedAtIso}'}'
        '${_normalizePayoutImportOperatorIdFilterValue(preferences.operatorId) == 'all' ? '' : ' • operator ${preferences.operatorId}'}';
  }

  CoachPayoutImportBatchFilterPreferences
      get _draftPayoutImportBatchFilterPreferences {
    return CoachPayoutImportBatchFilterPreferences(
      operatorId: _selectedPayoutImportBatchOperatorIdFilter,
    );
  }

  String _describePayoutImportBatchPreferences(
    CoachPayoutImportBatchFilterPreferences preferences,
  ) {
    return _normalizePayoutImportOperatorIdFilterValue(
                preferences.operatorId) ==
            'all'
        ? 'All operators'
        : 'operator ${preferences.operatorId}';
  }

  Future<void> _savePayoutImportPreviewHistorySavedView() async {
    final name = _payoutImportPreviewSavedViewNameController.text.trim();
    final preferences = _draftPayoutImportPreviewHistoryPreferences;
    final visibilityScope = _payoutImportPreviewSavedViewVisibilityScope;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a saved view name first.')),
      );
      return;
    }
    if (!preferences.hasActiveFilters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved views require at least one active preview history filter.',
          ),
        ),
      );
      return;
    }
    CoachPayoutImportPreviewHistorySavedView? existingView;
    for (final candidate in _payoutImportPreviewSavedViews) {
      if (candidate.name.trim().toLowerCase() == name.toLowerCase() &&
          candidate.visibilityScope == visibilityScope) {
        existingView = candidate;
        break;
      }
    }
    if (existingView != null && !existingView.canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Shared payout import preview views can only be managed by the owner account.',
          ),
        ),
      );
      return;
    }
    final nowIso = _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc());
    final view = CoachPayoutImportPreviewHistorySavedView(
      viewId: existingView?.viewId ??
          'previewhistoryview_${_previewHistoryNowUtc().microsecondsSinceEpoch}',
      accountId: existingView?.accountId ?? '',
      name: name,
      visibilityScope: visibilityScope,
      preferences: preferences,
      isDefault: visibilityScope == 'personal'
          ? (existingView?.isDefault ?? false)
          : false,
      isFavorite: existingView?.isFavorite ?? false,
      lastUsedAtIso: existingView?.lastUsedAtIso,
      canManage: existingView?.canManage ?? true,
      createdAtIso: existingView?.createdAtIso ?? nowIso,
      updatedAtIso: nowIso,
    );
    setState(() {
      _savingPayoutImportPreviewSavedView = true;
    });
    final updatedViews =
        await _savePersistedPayoutImportPreviewHistorySavedView(view);
    if (!mounted) {
      return;
    }
    setState(() {
      _payoutImportPreviewSavedViews = updatedViews;
      _payoutImportPreviewSavedViewPinnedIds =
          _payoutImportPreviewSavedViewFavoriteIds(updatedViews);
      _payoutImportPreviewSavedViewUsedAtById =
          _payoutImportPreviewSavedViewUsageMap(updatedViews);
      _payoutImportPreviewSavedViewOwners =
          _payoutImportPreviewSavedViewOwnerSummariesFromViews(updatedViews);
      _payoutImportPreviewSavedViewOperators =
          _payoutImportPreviewSavedViewOperatorSummariesFromViews(updatedViews);
      _savingPayoutImportPreviewSavedView = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingView == null
              ? (visibilityScope == 'shared_ops'
                  ? 'Saved shared preview history view.'
                  : 'Saved preview history view.')
              : (visibilityScope == 'shared_ops'
                  ? 'Updated shared preview history view.'
                  : 'Updated preview history view.'),
        ),
      ),
    );
  }

  Future<void> _applyPayoutImportPreviewHistorySavedView(
    CoachPayoutImportPreviewHistorySavedView view,
  ) async {
    setState(() {
      _payoutImportPreviewSavedViewNameController.text = view.name;
      _payoutImportPreviewSavedViewVisibilityScope = view.visibilityScope;
      _setPayoutImportPreviewHistoryDraftFromPreferences(view.preferences);
    });
    unawaited(
      _recordPersistedSavedViewUsage(
        collectionKey: _payoutImportPreviewSavedViewUsageCollectionKey,
        viewId: view.viewId,
        currentUsage: _payoutImportPreviewSavedViewUsedAtById,
        assign: (value) => _payoutImportPreviewSavedViewUsedAtById = value,
      ),
    );
    await _applyPayoutImportPreviewHistoryFilters();
  }

  Future<void> _deletePayoutImportPreviewHistorySavedView(
    CoachPayoutImportPreviewHistorySavedView view,
  ) async {
    final normalizedViewId = view.viewId.trim();
    if (normalizedViewId.isEmpty) {
      return;
    }
    if (!view.canManage) {
      return;
    }
    setState(() {
      _deletingPayoutImportPreviewSavedViewIds.add(normalizedViewId);
    });
    final updatedViews =
        await _deletePersistedPayoutImportPreviewHistorySavedView(
      normalizedViewId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _payoutImportPreviewSavedViews = updatedViews;
      _payoutImportPreviewSavedViewPinnedIds =
          _payoutImportPreviewSavedViewFavoriteIds(updatedViews);
      _payoutImportPreviewSavedViewUsedAtById =
          _payoutImportPreviewSavedViewUsageMap(updatedViews);
      _payoutImportPreviewSavedViewOwners =
          _payoutImportPreviewSavedViewOwnerSummariesFromViews(updatedViews);
      _payoutImportPreviewSavedViewOperators =
          _payoutImportPreviewSavedViewOperatorSummariesFromViews(updatedViews);
      _deletingPayoutImportPreviewSavedViewIds.remove(normalizedViewId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved preview history view deleted.')),
    );
  }

  Future<void> _togglePayoutImportPreviewHistorySavedViewDefault(
    CoachPayoutImportPreviewHistorySavedView view,
  ) async {
    final normalizedViewId = view.viewId.trim();
    if (normalizedViewId.isEmpty || view.visibilityScope != 'personal') {
      return;
    }
    setState(() {
      _updatingPayoutImportPreviewSavedViewDefaultIds.add(normalizedViewId);
    });
    final updatedViews =
        await _savePersistedPayoutImportPreviewHistorySavedView(
      CoachPayoutImportPreviewHistorySavedView(
        viewId: view.viewId,
        accountId: view.accountId,
        name: view.name,
        visibilityScope: view.visibilityScope,
        preferences: view.preferences,
        isDefault: !view.isDefault,
        isFavorite: view.isFavorite,
        lastUsedAtIso: view.lastUsedAtIso,
        canManage: view.canManage,
        createdAtIso: view.createdAtIso,
        updatedAtIso: _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc()),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _payoutImportPreviewSavedViews = updatedViews;
      _payoutImportPreviewSavedViewPinnedIds =
          _payoutImportPreviewSavedViewFavoriteIds(updatedViews);
      _payoutImportPreviewSavedViewUsedAtById =
          _payoutImportPreviewSavedViewUsageMap(updatedViews);
      _payoutImportPreviewSavedViewOwners =
          _payoutImportPreviewSavedViewOwnerSummariesFromViews(updatedViews);
      _payoutImportPreviewSavedViewOperators =
          _payoutImportPreviewSavedViewOperatorSummariesFromViews(updatedViews);
      _updatingPayoutImportPreviewSavedViewDefaultIds.remove(normalizedViewId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          view.isDefault
              ? 'Cleared default preview history view.'
              : 'Set default preview history view.',
        ),
      ),
    );
  }

  Future<void> _savePayoutImportBatchSavedView() async {
    final name = _payoutImportBatchSavedViewNameController.text.trim();
    final preferences = _draftPayoutImportBatchFilterPreferences;
    final visibilityScope = _payoutImportBatchSavedViewVisibilityScope;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a saved view name first.')),
      );
      return;
    }
    if (!preferences.hasActiveFilters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved views require at least one active payout import batch filter.',
          ),
        ),
      );
      return;
    }
    CoachPayoutImportBatchSavedView? existingView;
    for (final candidate in _payoutImportBatchSavedViews) {
      if (candidate.name.trim().toLowerCase() == name.toLowerCase() &&
          candidate.visibilityScope == visibilityScope) {
        existingView = candidate;
        break;
      }
    }
    if (existingView != null && !existingView.canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Shared payout import batch views can only be managed by the owner account.',
          ),
        ),
      );
      return;
    }
    final nowIso = _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc());
    final view = CoachPayoutImportBatchSavedView(
      viewId: existingView?.viewId ??
          'payoutimportbatchview_${_previewHistoryNowUtc().microsecondsSinceEpoch}',
      accountId: existingView?.accountId ?? '',
      name: name,
      visibilityScope: visibilityScope,
      preferences: preferences,
      isDefault: visibilityScope == 'personal'
          ? (existingView?.isDefault ?? false)
          : false,
      isFavorite: existingView?.isFavorite ?? false,
      lastUsedAtIso: existingView?.lastUsedAtIso,
      canManage: existingView?.canManage ?? true,
      createdAtIso: existingView?.createdAtIso ?? nowIso,
      updatedAtIso: nowIso,
    );
    setState(() {
      _savingPayoutImportBatchSavedView = true;
    });
    final updatedViews = await _savePersistedPayoutImportBatchSavedView(view);
    if (!mounted) {
      return;
    }
    setState(() {
      _payoutImportBatchSavedViews = updatedViews;
      _payoutImportBatchSavedViewPinnedIds =
          _payoutImportBatchSavedViewFavoriteIds(updatedViews);
      _payoutImportBatchSavedViewUsedAtById =
          _payoutImportBatchSavedViewUsageMap(updatedViews);
      _payoutImportBatchSavedViewOwners =
          _payoutImportBatchSavedViewOwnerSummariesFromViews(updatedViews);
      _payoutImportBatchSavedViewOperators =
          _payoutImportBatchSavedViewOperatorSummariesFromViews(updatedViews);
      _savingPayoutImportBatchSavedView = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingView == null
              ? (visibilityScope == 'shared_ops'
                  ? 'Saved shared payout import batch view.'
                  : 'Saved payout import batch view.')
              : (visibilityScope == 'shared_ops'
                  ? 'Updated shared payout import batch view.'
                  : 'Updated payout import batch view.'),
        ),
      ),
    );
  }

  Future<void> _applyPayoutImportBatchSavedView(
    CoachPayoutImportBatchSavedView view,
  ) async {
    final normalizedOperatorId = _normalizePayoutImportOperatorIdFilterValue(
      view.preferences.operatorId,
    );
    setState(() {
      _payoutImportBatchSavedViewNameController.text = view.name;
      _payoutImportBatchSavedViewVisibilityScope = view.visibilityScope;
      _selectedPayoutImportBatchOperatorIdFilter = normalizedOperatorId;
    });
    unawaited(
      _recordPersistedSavedViewUsage(
        collectionKey: _payoutImportBatchSavedViewUsageCollectionKey,
        viewId: view.viewId,
        currentUsage: _payoutImportBatchSavedViewUsedAtById,
        assign: (value) => _payoutImportBatchSavedViewUsedAtById = value,
      ),
    );
    await _persistPayoutImportBatchOperatorFilterSelection(
        normalizedOperatorId);
  }

  Future<void> _deletePayoutImportBatchSavedView(
    CoachPayoutImportBatchSavedView view,
  ) async {
    final normalizedViewId = view.viewId.trim();
    if (normalizedViewId.isEmpty) {
      return;
    }
    if (!view.canManage) {
      return;
    }
    setState(() {
      _deletingPayoutImportBatchSavedViewIds.add(normalizedViewId);
    });
    final updatedViews =
        await _deletePersistedPayoutImportBatchSavedView(normalizedViewId);
    if (!mounted) {
      return;
    }
    setState(() {
      _payoutImportBatchSavedViews = updatedViews;
      _payoutImportBatchSavedViewPinnedIds =
          _payoutImportBatchSavedViewFavoriteIds(updatedViews);
      _payoutImportBatchSavedViewUsedAtById =
          _payoutImportBatchSavedViewUsageMap(updatedViews);
      _payoutImportBatchSavedViewOwners =
          _payoutImportBatchSavedViewOwnerSummariesFromViews(updatedViews);
      _payoutImportBatchSavedViewOperators =
          _payoutImportBatchSavedViewOperatorSummariesFromViews(updatedViews);
      _deletingPayoutImportBatchSavedViewIds.remove(normalizedViewId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved payout import batch view deleted.')),
    );
  }

  Future<void> _togglePayoutImportBatchSavedViewDefault(
    CoachPayoutImportBatchSavedView view,
  ) async {
    final normalizedViewId = view.viewId.trim();
    if (normalizedViewId.isEmpty || view.visibilityScope != 'personal') {
      return;
    }
    setState(() {
      _updatingPayoutImportBatchSavedViewDefaultIds.add(normalizedViewId);
    });
    final updatedViews = await _savePersistedPayoutImportBatchSavedView(
      CoachPayoutImportBatchSavedView(
        viewId: view.viewId,
        accountId: view.accountId,
        name: view.name,
        visibilityScope: view.visibilityScope,
        preferences: view.preferences,
        isDefault: !view.isDefault,
        isFavorite: view.isFavorite,
        lastUsedAtIso: view.lastUsedAtIso,
        canManage: view.canManage,
        createdAtIso: view.createdAtIso,
        updatedAtIso: _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc()),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _payoutImportBatchSavedViews = updatedViews;
      _payoutImportBatchSavedViewPinnedIds =
          _payoutImportBatchSavedViewFavoriteIds(updatedViews);
      _payoutImportBatchSavedViewUsedAtById =
          _payoutImportBatchSavedViewUsageMap(updatedViews);
      _payoutImportBatchSavedViewOwners =
          _payoutImportBatchSavedViewOwnerSummariesFromViews(updatedViews);
      _payoutImportBatchSavedViewOperators =
          _payoutImportBatchSavedViewOperatorSummariesFromViews(updatedViews);
      _updatingPayoutImportBatchSavedViewDefaultIds.remove(normalizedViewId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          view.isDefault
              ? 'Cleared default payout import batch view.'
              : 'Set default payout import batch view.',
        ),
      ),
    );
  }

  Future<void> _loadPayoutImportPreviewHistory({
    bool showBusy = true,
  }) async {
    if (!_hasRemotePayoutImportPreviewHistoryFilters) {
      if (!mounted) {
        return;
      }
      setState(() {
        _payoutImportPreviewHistory = _payoutImportPreviews;
        _payoutImportPreviewHistoryErrorMessage = null;
        _loadingPayoutImportPreviewHistory = false;
        _loadingMorePayoutImportPreviewHistory = false;
      });
      return;
    }
    if (showBusy && mounted) {
      setState(() {
        _loadingPayoutImportPreviewHistory = true;
        _loadingMorePayoutImportPreviewHistory = false;
        _payoutImportPreviewHistoryErrorMessage = null;
      });
    }
    try {
      final response = await _api.operatorPayoutImportPreviews(
        limit: 8,
        status: _appliedPayoutImportPreviewStatusFilter,
        fromCreatedAtIso: _appliedPayoutImportPreviewFromCreatedAtIso,
        toCreatedAtIso: _appliedPayoutImportPreviewToCreatedAtIso,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _payoutImportPreviewHistory = response;
        _payoutImportPreviewHistoryErrorMessage = null;
        _loadingPayoutImportPreviewHistory = false;
        _loadingMorePayoutImportPreviewHistory = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _payoutImportPreviewHistoryErrorMessage = error.detail;
        _loadingPayoutImportPreviewHistory = false;
        _loadingMorePayoutImportPreviewHistory = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _payoutImportPreviewHistoryErrorMessage = error.toString();
        _loadingPayoutImportPreviewHistory = false;
        _loadingMorePayoutImportPreviewHistory = false;
      });
    }
  }

  Future<void> _loadMorePayoutImportPreviewHistory() async {
    final currentHistory = _payoutImportPreviewHistory;
    final cursor = currentHistory?.nextCursor?.trim();
    if (currentHistory == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMorePayoutImportPreviewHistory = true;
      _payoutImportPreviewHistoryErrorMessage = null;
    });
    try {
      final response = await _api.operatorPayoutImportPreviews(
        limit: 8,
        status: _appliedPayoutImportPreviewStatusFilter,
        fromCreatedAtIso: _appliedPayoutImportPreviewFromCreatedAtIso,
        toCreatedAtIso: _appliedPayoutImportPreviewToCreatedAtIso,
        cursor: cursor,
      );
      if (!mounted) {
        return;
      }
      final mergedPreviews = <CoachOperatorPayoutImportPreview>[
        ...currentHistory.previews,
      ];
      final seenPreviewTokens =
          mergedPreviews.map((entry) => entry.previewToken).toSet();
      for (final preview in response.previews) {
        if (seenPreviewTokens.add(preview.previewToken)) {
          mergedPreviews.add(preview);
        }
      }
      setState(() {
        _payoutImportPreviewHistory = CoachOperatorPayoutImportPreviewsResponse(
          generatedAtIso: response.generatedAtIso,
          summary: response.summary,
          previews: mergedPreviews,
          nextCursor: response.nextCursor,
        );
        _loadingMorePayoutImportPreviewHistory = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _payoutImportPreviewHistoryErrorMessage = error.detail;
        _loadingMorePayoutImportPreviewHistory = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _payoutImportPreviewHistoryErrorMessage = error.toString();
        _loadingMorePayoutImportPreviewHistory = false;
      });
    }
  }

  Future<void> _loadMorePayoutImports() async {
    final currentImports = _payoutImports;
    final cursor = currentImports?.nextCursor?.trim();
    if (currentImports == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMorePayoutImports = true;
    });
    try {
      final response =
          await _api.operatorPayoutImports(limit: 8, cursor: cursor);
      if (!mounted) {
        return;
      }
      final mergedImports = <CoachOperatorPayoutImport>[
        ...currentImports.imports
      ];
      final seenImportIds =
          mergedImports.map((entry) => entry.importId).toSet();
      for (final entry in response.imports) {
        if (seenImportIds.add(entry.importId)) {
          mergedImports.add(entry);
        }
      }
      setState(() {
        _payoutImports = CoachOperatorPayoutImportsResponse(
          generatedAtIso: response.generatedAtIso,
          summary: response.summary,
          imports: mergedImports,
          nextCursor: response.nextCursor,
        );
        _loadingMorePayoutImports = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutImports = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutImports = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _loadMoreCatalogImportRuns() async {
    final currentRuns = _catalogImportRuns;
    final cursor = _catalogImportRunsCursor;
    if (currentRuns == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMoreCatalogImportRuns = true;
    });
    try {
      final response = await _api.operatorCatalogImportRuns(
        limit: 8,
        cursor: cursor,
        status: _catalogImportRunStatusFilter,
        replayScope: _catalogImportRunReplayScopeFilter,
        issueSeverity: _catalogImportRunIssueSeverityFilter,
        issueStage: _catalogImportRunIssueStageFilter,
      );
      if (!mounted) {
        return;
      }
      final mergedRuns = <CoachOperatorCatalogImportRun>[
        ...currentRuns.importRuns,
      ];
      final seenRunIds = mergedRuns.map((entry) => entry.importRunId).toSet();
      for (final entry in response.importRuns) {
        if (seenRunIds.add(entry.importRunId)) {
          mergedRuns.add(entry);
        }
      }
      setState(() {
        _catalogImportRuns = CoachOperatorCatalogImportRunsResponse(
          generatedAtIso: response.generatedAtIso,
          summary: response.summary,
          importRuns: mergedRuns,
          nextCursor: response.nextCursor,
        );
        _loadingMoreCatalogImportRuns = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMoreCatalogImportRuns = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMoreCatalogImportRuns = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _reloadCatalogImportRuns() async {
    setState(() {
      _loadingQueues = true;
      _loadingMoreCatalogImportRuns = false;
      _errorMessage = null;
    });
    try {
      final response = await _api.operatorCatalogImportRuns(
        limit: 8,
        status: _catalogImportRunStatusFilter,
        replayScope: _catalogImportRunReplayScopeFilter,
        issueSeverity: _catalogImportRunIssueSeverityFilter,
        issueStage: _catalogImportRunIssueStageFilter,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogImportRuns = response;
        _loadingMoreCatalogImportRuns = false;
        _loadingQueues = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingQueues = false;
        _loadingMoreCatalogImportRuns = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingQueues = false;
        _loadingMoreCatalogImportRuns = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _updateCatalogImportRunFilters({
    String? statusFilter,
    String? replayScopeFilter,
    String? issueSeverityFilter,
    String? issueStageFilter,
  }) {
    final nextStatus =
        (statusFilter ?? _selectedCatalogImportRunStatusFilter).trim();
    final nextReplayScope =
        (replayScopeFilter ?? _selectedCatalogImportRunReplayScopeFilter)
            .trim();
    final nextIssueSeverity =
        (issueSeverityFilter ?? _selectedCatalogImportRunIssueSeverityFilter)
            .trim();
    final nextIssueStage =
        (issueStageFilter ?? _selectedCatalogImportRunIssueStageFilter).trim();
    if (nextStatus == _selectedCatalogImportRunStatusFilter &&
        nextReplayScope == _selectedCatalogImportRunReplayScopeFilter &&
        nextIssueSeverity == _selectedCatalogImportRunIssueSeverityFilter &&
        nextIssueStage == _selectedCatalogImportRunIssueStageFilter) {
      return;
    }
    setState(() {
      _selectedCatalogImportRunStatusFilter = nextStatus;
      _selectedCatalogImportRunReplayScopeFilter = nextReplayScope;
      _selectedCatalogImportRunIssueSeverityFilter = nextIssueSeverity;
      _selectedCatalogImportRunIssueStageFilter = nextIssueStage;
    });
    final preferences = CoachCatalogImportRunFilterPreferences(
      status: nextStatus,
      replayScope: nextReplayScope,
      issueSeverity: nextIssueSeverity,
      issueStage: nextIssueStage,
    );
    if (preferences.hasActiveFilters) {
      unawaited(
        _savePersistedCatalogImportRunFilterPreferences(preferences),
      );
    } else {
      unawaited(_clearPersistedCatalogImportRunFilterPreferences());
    }
    unawaited(_reloadCatalogImportRuns());
  }

  Future<void> _saveCatalogImportRunSavedView() async {
    final name = _catalogImportRunSavedViewNameController.text.trim();
    final preferences = _draftCatalogImportRunFilterPreferences;
    final visibilityScope = _catalogImportRunSavedViewVisibilityScope;
    final operatorIds = visibilityScope == 'shared_ops'
        ? _resolveSharedViewOperatorScopeIds(
            _catalogImportRunSavedViewOperatorIdScope,
          )
        : const <String>[];
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a saved view name first.')),
      );
      return;
    }
    if (!preferences.hasActiveFilters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved views require at least one active catalog import run filter.',
          ),
        ),
      );
      return;
    }
    CoachCatalogImportRunSavedView? existingView;
    for (final candidate in _catalogImportRunSavedViews) {
      if (candidate.name.trim().toLowerCase() == name.toLowerCase() &&
          candidate.visibilityScope == visibilityScope) {
        existingView = candidate;
        break;
      }
    }
    if (existingView != null && !existingView.canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Shared catalog import run views can only be managed by the owner account.',
          ),
        ),
      );
      return;
    }
    final nowIso = _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc());
    final view = CoachCatalogImportRunSavedView(
      viewId: existingView?.viewId ??
          'catalogimportrunsavedview_${_previewHistoryNowUtc().microsecondsSinceEpoch}',
      accountId: existingView?.accountId ?? '',
      name: name,
      visibilityScope: visibilityScope,
      operatorIds: operatorIds,
      preferences: preferences,
      isDefault: visibilityScope == 'personal'
          ? (existingView?.isDefault ?? false)
          : false,
      isFavorite: existingView?.isFavorite ?? false,
      lastUsedAtIso: existingView?.lastUsedAtIso,
      canManage: existingView?.canManage ?? true,
      createdAtIso: existingView?.createdAtIso ?? nowIso,
      updatedAtIso: nowIso,
    );
    setState(() {
      _savingCatalogImportRunSavedView = true;
    });
    final updatedViews = await _savePersistedCatalogImportRunSavedView(view);
    if (!mounted) {
      return;
    }
    final visibleUpdatedViews =
        _filterCatalogImportRunSavedViewsByPrivilegeOperatorScope(updatedViews);
    setState(() {
      _catalogImportRunSavedViews =
          _filterCatalogImportRunSavedViewsByOperatorId(
        _filterCatalogImportRunSavedViewsByOwnerAccountId(
          _filterCatalogImportRunSavedViewsByVisibilityScope(
            visibleUpdatedViews,
            _catalogImportRunSavedViewsVisibilityFilter,
          ),
          _catalogImportRunSavedViewsOwnerAccountIdFilter,
        ),
        _catalogImportRunSavedViewsOperatorIdFilter,
      );
      _catalogImportRunSavedViewOwners =
          _catalogImportRunSavedViewOwnerSummariesFromViews(
              visibleUpdatedViews);
      _catalogImportRunSavedViewOperators =
          _catalogImportRunSavedViewOperatorSummariesFromViews(
        visibleUpdatedViews,
      );
      _catalogImportRunSavedViewPinnedIds =
          _catalogImportRunSavedViewFavoriteIds(visibleUpdatedViews);
      _catalogImportRunSavedViewUsedAtById =
          _catalogImportRunSavedViewUsageMap(visibleUpdatedViews);
      _savingCatalogImportRunSavedView = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingView == null
              ? (visibilityScope == 'shared_ops'
                  ? 'Saved shared catalog import run view.'
                  : 'Saved catalog import run view.')
              : (visibilityScope == 'shared_ops'
                  ? 'Updated shared catalog import run view.'
                  : 'Updated catalog import run view.'),
        ),
      ),
    );
  }

  Future<void> _applyCatalogImportRunSavedView(
    CoachCatalogImportRunSavedView view,
  ) async {
    _catalogImportRunSavedViewNameController.text = view.name;
    setState(() {
      _catalogImportRunSavedViewVisibilityScope = view.visibilityScope;
      _catalogImportRunSavedViewOperatorIdScope =
          view.operatorIds.length == 1 ? view.operatorIds.first : 'all';
    });
    unawaited(
      _recordPersistedSavedViewUsage(
        collectionKey: _catalogImportRunSavedViewUsageCollectionKey,
        viewId: view.viewId,
        currentUsage: _catalogImportRunSavedViewUsedAtById,
        assign: (value) => _catalogImportRunSavedViewUsedAtById = value,
      ),
    );
    _updateCatalogImportRunFilters(
      statusFilter: view.preferences.status,
      replayScopeFilter: view.preferences.replayScope,
      issueSeverityFilter: view.preferences.issueSeverity,
      issueStageFilter: view.preferences.issueStage,
    );
  }

  Future<void> _reloadCatalogImportRunSavedViewsForFilters({
    required String visibilityScope,
    required String ownerAccountId,
    required String operatorId,
  }) async {
    final normalizedScope =
        _normalizeCatalogSavedViewVisibilityFilter(visibilityScope);
    final normalizedOwnerAccountId = normalizedScope == 'shared_ops'
        ? _normalizeCatalogSavedViewOwnerAccountIdFilter(ownerAccountId)
        : 'all';
    final normalizedOperatorId = normalizedScope == 'shared_ops'
        ? _normalizeCatalogSavedViewOperatorIdFilter(operatorId)
        : 'all';
    final savedViews = await _loadPersistedCatalogImportRunSavedViews(
      visibilityScope: normalizedScope,
      ownerAccountId: normalizedOwnerAccountId,
      operatorId: normalizedOperatorId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _catalogImportRunSavedViewsVisibilityFilter = normalizedScope;
      _catalogImportRunSavedViewsOwnerAccountIdFilter =
          normalizedOwnerAccountId;
      _catalogImportRunSavedViewsOperatorIdFilter = normalizedOperatorId;
      _catalogImportRunSavedViews = savedViews;
      _catalogImportRunSavedViewPinnedIds =
          _catalogImportRunSavedViewFavoriteIds(savedViews);
      _catalogImportRunSavedViewUsedAtById =
          _catalogImportRunSavedViewUsageMap(savedViews);
    });
  }

  Future<void> _deleteCatalogImportRunSavedView(
    CoachCatalogImportRunSavedView view,
  ) async {
    final normalizedViewId = view.viewId.trim();
    if (normalizedViewId.isEmpty) {
      return;
    }
    setState(() {
      _deletingCatalogImportRunSavedViewIds.add(normalizedViewId);
    });
    final updatedViews = await _deletePersistedCatalogImportRunSavedView(
      normalizedViewId,
    );
    if (!mounted) {
      return;
    }
    final visibleUpdatedViews =
        _filterCatalogImportRunSavedViewsByPrivilegeOperatorScope(updatedViews);
    setState(() {
      _catalogImportRunSavedViews =
          _filterCatalogImportRunSavedViewsByOperatorId(
        _filterCatalogImportRunSavedViewsByOwnerAccountId(
          _filterCatalogImportRunSavedViewsByVisibilityScope(
            visibleUpdatedViews,
            _catalogImportRunSavedViewsVisibilityFilter,
          ),
          _catalogImportRunSavedViewsOwnerAccountIdFilter,
        ),
        _catalogImportRunSavedViewsOperatorIdFilter,
      );
      _catalogImportRunSavedViewOwners =
          _catalogImportRunSavedViewOwnerSummariesFromViews(
              visibleUpdatedViews);
      _catalogImportRunSavedViewOperators =
          _catalogImportRunSavedViewOperatorSummariesFromViews(
        visibleUpdatedViews,
      );
      _catalogImportRunSavedViewPinnedIds =
          _catalogImportRunSavedViewFavoriteIds(visibleUpdatedViews);
      _catalogImportRunSavedViewUsedAtById =
          _catalogImportRunSavedViewUsageMap(visibleUpdatedViews);
      _deletingCatalogImportRunSavedViewIds.remove(normalizedViewId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Catalog import run saved view deleted.')),
    );
  }

  Future<void> _toggleCatalogImportRunSavedViewDefault(
    CoachCatalogImportRunSavedView view,
  ) async {
    if (view.visibilityScope != 'personal') {
      return;
    }
    final normalizedViewId = view.viewId.trim();
    if (normalizedViewId.isEmpty) {
      return;
    }
    setState(() {
      _updatingCatalogImportRunSavedViewDefaultIds.add(normalizedViewId);
    });
    final updatedViews = await _savePersistedCatalogImportRunSavedView(
      CoachCatalogImportRunSavedView(
        viewId: view.viewId,
        accountId: view.accountId,
        name: view.name,
        visibilityScope: view.visibilityScope,
        operatorIds: view.operatorIds,
        preferences: view.preferences,
        isDefault: !view.isDefault,
        isFavorite: view.isFavorite,
        lastUsedAtIso: view.lastUsedAtIso,
        canManage: view.canManage,
        createdAtIso: view.createdAtIso,
        updatedAtIso: _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc()),
      ),
    );
    if (!mounted) {
      return;
    }
    final visibleUpdatedViews =
        _filterCatalogImportRunSavedViewsByPrivilegeOperatorScope(updatedViews);
    setState(() {
      _catalogImportRunSavedViews =
          _filterCatalogImportRunSavedViewsByOperatorId(
        _filterCatalogImportRunSavedViewsByOwnerAccountId(
          _filterCatalogImportRunSavedViewsByVisibilityScope(
            visibleUpdatedViews,
            _catalogImportRunSavedViewsVisibilityFilter,
          ),
          _catalogImportRunSavedViewsOwnerAccountIdFilter,
        ),
        _catalogImportRunSavedViewsOperatorIdFilter,
      );
      _catalogImportRunSavedViewOwners =
          _catalogImportRunSavedViewOwnerSummariesFromViews(
              visibleUpdatedViews);
      _catalogImportRunSavedViewOperators =
          _catalogImportRunSavedViewOperatorSummariesFromViews(
        visibleUpdatedViews,
      );
      _catalogImportRunSavedViewPinnedIds =
          _catalogImportRunSavedViewFavoriteIds(visibleUpdatedViews);
      _catalogImportRunSavedViewUsedAtById =
          _catalogImportRunSavedViewUsageMap(visibleUpdatedViews);
      _updatingCatalogImportRunSavedViewDefaultIds.remove(normalizedViewId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          view.isDefault
              ? 'Cleared default catalog import run view.'
              : 'Set default catalog import run view.',
        ),
      ),
    );
  }

  Future<void> _loadMoreCatalogSourceArtifacts() async {
    final currentArtifacts = _catalogSourceArtifacts;
    final cursor = _catalogSourceArtifactsCursor;
    if (currentArtifacts == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMoreCatalogSourceArtifacts = true;
    });
    try {
      final response = await _api.operatorCatalogSourceArtifacts(
        limit: 8,
        cursor: cursor,
      );
      if (!mounted) {
        return;
      }
      final mergedArtifacts = <CoachOperatorCatalogSourceArtifact>[
        ...currentArtifacts.artifacts,
      ];
      final seenArtifactIds =
          mergedArtifacts.map((entry) => entry.artifactId).toSet();
      for (final entry in response.artifacts) {
        if (seenArtifactIds.add(entry.artifactId)) {
          mergedArtifacts.add(entry);
        }
      }
      setState(() {
        _catalogSourceArtifacts = CoachOperatorCatalogSourceArtifactsResponse(
          generatedAtIso: response.generatedAtIso,
          summary: response.summary,
          artifacts: mergedArtifacts,
          nextCursor: response.nextCursor,
        );
        _loadingMoreCatalogSourceArtifacts = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMoreCatalogSourceArtifacts = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMoreCatalogSourceArtifacts = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showCatalogSourceArtifactDetails(
    CoachOperatorCatalogSourceArtifact entry, {
    String? importRunId,
  }) async {
    const detailPageSize = 2;
    final artifactId = entry.artifactId.trim();
    CoachOperatorCatalogSourceArtifactDetailResponse detail =
        CoachOperatorCatalogSourceArtifactDetailResponse(
      generatedAtIso: DateTime.now().toUtc().toIso8601String(),
      sourceArtifact: entry,
      referencingImportRunsSummary:
          const CoachOperatorCatalogSourceArtifactReferencingRunsSummary(
        totalRuns: 0,
        failedRuns: 0,
        succeededRuns: 0,
        runningRuns: 0,
        latestStartedAtIso: null,
      ),
      referencingImportRunsNextCursor: null,
      referencingImportRuns: const <CoachOperatorCatalogImportRun>[],
    );
    if (artifactId.isNotEmpty) {
      setState(() {
        _loadingCatalogSourceArtifactDetailIds.add(artifactId);
      });
      try {
        detail = await _api.operatorCatalogSourceArtifact(
          artifactId,
          limit: detailPageSize,
        );
        final resolvedEntry = detail.sourceArtifact;
        final currentArtifacts = _catalogSourceArtifacts;
        if (currentArtifacts != null) {
          final mergedArtifacts = currentArtifacts.artifacts
              .map(
                (candidate) => candidate.artifactId == resolvedEntry.artifactId
                    ? resolvedEntry
                    : candidate,
              )
              .toList(growable: false);
          setState(() {
            _catalogSourceArtifacts =
                CoachOperatorCatalogSourceArtifactsResponse(
              generatedAtIso: currentArtifacts.generatedAtIso,
              summary: currentArtifacts.summary,
              artifacts: mergedArtifacts,
              nextCursor: currentArtifacts.nextCursor,
            );
          });
        }
      } on CoachApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.detail)),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _loadingCatalogSourceArtifactDetailIds.remove(artifactId);
          });
        }
      }
    }
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var loadingMoreReferencingImportRuns = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> loadMoreReferencingImportRuns() async {
              final nextCursor = detail.referencingImportRunsNextCursor?.trim();
              if (artifactId.isEmpty ||
                  loadingMoreReferencingImportRuns ||
                  nextCursor == null ||
                  nextCursor.isEmpty) {
                return;
              }
              setSheetState(() {
                loadingMoreReferencingImportRuns = true;
              });
              try {
                final nextPage = await _api.operatorCatalogSourceArtifact(
                  artifactId,
                  limit: detailPageSize,
                  cursor: nextCursor,
                );
                final mergedRuns = <CoachOperatorCatalogImportRun>[
                  ...detail.referencingImportRuns,
                  ...nextPage.referencingImportRuns.where(
                    (candidate) => !detail.referencingImportRuns.any(
                      (existing) =>
                          existing.importRunId == candidate.importRunId,
                    ),
                  ),
                ];
                setSheetState(() {
                  detail = CoachOperatorCatalogSourceArtifactDetailResponse(
                    generatedAtIso: nextPage.generatedAtIso,
                    sourceArtifact: nextPage.sourceArtifact,
                    referencingImportRunsSummary:
                        nextPage.referencingImportRunsSummary,
                    referencingImportRunsNextCursor:
                        nextPage.referencingImportRunsNextCursor,
                    referencingImportRuns: mergedRuns,
                  );
                  loadingMoreReferencingImportRuns = false;
                });
              } on CoachApiException catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.detail)),
                  );
                }
                setSheetState(() {
                  loadingMoreReferencingImportRuns = false;
                });
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
                setSheetState(() {
                  loadingMoreReferencingImportRuns = false;
                });
              }
            }

            final resolvedEntry = detail.sourceArtifact;
            final referencingImportRuns = detail.referencingImportRuns;
            final referencingSummary = detail.referencingImportRunsSummary;
            final hasMoreReferencingImportRuns =
                (detail.referencingImportRunsNextCursor ?? '')
                    .trim()
                    .isNotEmpty;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Source artifact details',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(resolvedEntry.sourceLabel,
                          style: Theme.of(sheetContext).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text('Artifact id: ${resolvedEntry.artifactId}'),
                      const SizedBox(height: 4),
                      Text('Feed kind: ${resolvedEntry.feedKind}'),
                      const SizedBox(height: 4),
                      Text('Source kind: ${resolvedEntry.sourceKind}'),
                      const SizedBox(height: 4),
                      Text(
                        'Operators: ${_coachFormatCatalogOperatorScope(resolvedEntry.operatorIds)}',
                      ),
                      const SizedBox(height: 4),
                      Text('File: ${resolvedEntry.fileName}'),
                      const SizedBox(height: 4),
                      Text('Feed locator: ${resolvedEntry.feedLocator}'),
                      const SizedBox(height: 4),
                      Text('Checksum: ${resolvedEntry.fileChecksumSha256}'),
                      const SizedBox(height: 4),
                      Text(
                        'Content length: ${resolvedEntry.contentLengthBytes} bytes',
                      ),
                      const SizedBox(height: 4),
                      Text(
                          'Extracted files: ${resolvedEntry.extractedFileCount}'),
                      const SizedBox(height: 4),
                      Text('Created by: ${resolvedEntry.createdByAccountId}'),
                      const SizedBox(height: 4),
                      Text('Created at: ${resolvedEntry.createdAtIso}'),
                      if (importRunId != null &&
                          importRunId.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Referenced by import run: ${importRunId.trim()}',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                      if (referencingSummary.totalRuns > 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Referencing import runs (${referencingSummary.totalRuns})',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Loaded ${referencingImportRuns.length} • '
                          'failed ${referencingSummary.failedRuns} • '
                          'succeeded ${referencingSummary.succeededRuns} • '
                          'running ${referencingSummary.runningRuns}',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        if (referencingSummary.latestStartedAtIso != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Latest started at: ${referencingSummary.latestStartedAtIso}',
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ],
                      ],
                      if (referencingImportRuns.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...referencingImportRuns.map(
                          (run) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${run.importRunId} • ${run.status} • ${run.triggerKind}',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  key: ValueKey(
                                    'coachOpsCatalogSourceArtifactViewImportRun_'
                                    '${resolvedEntry.artifactId}_${run.importRunId}',
                                  ),
                                  onPressed: () {
                                    Navigator.of(sheetContext).pop();
                                    _showCatalogImportRunDetails(run);
                                  },
                                  child: const Text('View run'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (hasMoreReferencingImportRuns) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsCatalogSourceArtifactLoadOlderRuns_'
                              '${resolvedEntry.artifactId}',
                            ),
                            onPressed: loadingMoreReferencingImportRuns
                                ? null
                                : loadMoreReferencingImportRuns,
                            icon: loadingMoreReferencingImportRuns
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.history_outlined),
                            label: Text(
                              loadingMoreReferencingImportRuns
                                  ? 'Loading older runs...'
                                  : 'Load older runs',
                            ),
                          ),
                        ),
                      ],
                      if (_catalogImportMutationsAllowed) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsCatalogSourceArtifactRunImportFromDetails_'
                              '${resolvedEntry.artifactId}',
                            ),
                            onPressed: _runningCatalogImport || _loadingQueues
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                    _triggerCatalogImportRun(
                                      sourceArtifactId:
                                          resolvedEntry.artifactId,
                                      sourceLabel: resolvedEntry.sourceLabel,
                                    );
                                  },
                            icon: _runningCatalogImport
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_outlined),
                            label: Text(
                              _runningCatalogImport
                                  ? 'Running import...'
                                  : 'Run import from this artifact',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  CoachOperatorCatalogImportRun _catalogImportRunEntryForDetail(
    String importRunId,
  ) {
    final normalizedImportRunId = importRunId.trim();
    for (final entry in _catalogImportRuns?.importRuns ?? const []) {
      if (entry.importRunId == normalizedImportRunId) {
        return entry;
      }
    }
    return CoachOperatorCatalogImportRun(
      importRunId: normalizedImportRunId,
      feedKind: 'static_catalog',
      sourceKind: 'gtfs',
      triggerKind: 'manual',
      feedLocator: null,
      operatorIds: const <String>[],
      replayedFromImportRunId: null,
      replayLineageSummary: null,
      sourceArtifactId: null,
      sourceArtifact: null,
      status: 'running',
      startedAtIso: DateTime.now().toUtc().toIso8601String(),
      finishedAtIso: null,
      counts: const CoachOperatorCatalogImportRunCounts(
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
      issues: const <CoachOperatorCatalogImportRunIssue>[],
    );
  }

  List<String> _catalogImportRunIssueSeverityOptions(
    Iterable<CoachOperatorCatalogImportRunIssue> issues,
  ) {
    final values = issues
        .map((issue) => issue.severity.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: true)
      ..sort((left, right) {
        final leftRank = switch (left.toLowerCase()) {
          'error' => 0,
          'warning' => 1,
          'info' => 2,
          _ => 3,
        };
        final rightRank = switch (right.toLowerCase()) {
          'error' => 0,
          'warning' => 1,
          'info' => 2,
          _ => 3,
        };
        final rankCompare = leftRank.compareTo(rightRank);
        if (rankCompare != 0) {
          return rankCompare;
        }
        return left.compareTo(right);
      });
    return values;
  }

  List<String> _catalogImportRunIssueStageOptions(
    Iterable<CoachOperatorCatalogImportRunIssue> issues,
  ) {
    final values = issues
        .map((issue) => issue.stage.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: true)
      ..sort();
    return values;
  }

  Future<void> _showCatalogImportRunDetails(
    CoachOperatorCatalogImportRun entry,
  ) async {
    const detailPageSize = 2;
    final importRunId = entry.importRunId.trim();
    final issueSavedViewNameController = TextEditingController();
    CoachOperatorCatalogImportRunLineageResponse? lineage;
    List<CoachCatalogImportRunIssueSavedView> persistedIssueSavedViews =
        const <CoachCatalogImportRunIssueSavedView>[];
    List<CoachCatalogImportRunSavedViewOwnerSummary>
        persistedIssueSavedViewOwners =
        const <CoachCatalogImportRunSavedViewOwnerSummary>[];
    List<CoachCatalogImportRunSavedViewOperatorSummary>
        persistedIssueSavedViewOperators =
        const <CoachCatalogImportRunSavedViewOperatorSummary>[];
    CoachOperatorCatalogImportRunDetailResponse detail =
        CoachOperatorCatalogImportRunDetailResponse(
      generatedAtIso: DateTime.now().toUtc().toIso8601String(),
      issuesSummary: CoachOperatorCatalogImportRunIssuesSummary(
        totalIssues: entry.issues.length,
        filteredIssues: entry.issues.length,
        errorIssues:
            entry.issues.where((issue) => issue.severity == 'error').length,
        warningIssues:
            entry.issues.where((issue) => issue.severity == 'warning').length,
      ),
      issuesFilters: CoachOperatorCatalogImportRunIssueFilters(
        severity: null,
        stage: null,
        availableSeverities: _catalogImportRunIssueSeverityOptions(
          entry.issues,
        ),
        availableStages: _catalogImportRunIssueStageOptions(entry.issues),
      ),
      issuesNextCursor: null,
      importRun: entry,
    );
    var persistedIssueFilters =
        CoachCatalogImportRunIssueFilterPreferences.empty;
    if (importRunId.isNotEmpty) {
      setState(() {
        _loadingCatalogImportRunDetailIds.add(importRunId);
      });
      try {
        detail = await _api.operatorCatalogImportRun(
          importRunId,
          limit: detailPageSize,
        );
        lineage = await _api.operatorCatalogImportRunLineage(
          importRunId,
          limit: detailPageSize,
        );
        persistedIssueFilters =
            await _loadPersistedCatalogImportRunIssueFilterPreferences();
        persistedIssueSavedViews =
            await _loadPersistedCatalogImportRunIssueSavedViews();
        persistedIssueSavedViewOwners =
            await _loadPersistedCatalogImportRunIssueSavedViewOwners();
        persistedIssueSavedViewOperators =
            await _loadPersistedCatalogImportRunIssueSavedViewOperators();
        final defaultIssueSavedView = persistedIssueFilters.hasActiveFilters
            ? null
            : persistedIssueSavedViews
                .cast<CoachCatalogImportRunIssueSavedView?>()
                .firstWhere(
                  (view) => view?.isDefault ?? false,
                  orElse: () => null,
                );
        final effectiveIssueFilters =
            defaultIssueSavedView?.preferences ?? persistedIssueFilters;
        if (effectiveIssueFilters.hasActiveFilters) {
          detail = await _api.operatorCatalogImportRun(
            importRunId,
            limit: detailPageSize,
            issueSeverity: effectiveIssueFilters.severity,
            issueStage: effectiveIssueFilters.stage,
          );
          persistedIssueFilters = effectiveIssueFilters;
        }
      } on CoachApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.detail)),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _loadingCatalogImportRunDetailIds.remove(importRunId);
          });
        }
      }
    }
    if (!mounted) {
      issueSavedViewNameController.dispose();
      return;
    }
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var loadingMoreIssues = false;
        var reloadingIssueFilters = false;
        var loadingMoreReplayRuns = false;
        var savedIssueViews = persistedIssueSavedViews;
        var issueSavedViewOwners = persistedIssueSavedViewOwners;
        var issueSavedViewOperators = persistedIssueSavedViewOperators;
        var savingIssueSavedView = false;
        var issueSavedViewVisibilityScope = 'personal';
        var issueSavedViewOperatorIdScope = 'all';
        var issueSavedViewsVisibilityFilter = 'all';
        var issueSavedViewsOwnerAccountIdFilter = 'all';
        var issueSavedViewsOperatorIdFilter = 'all';
        var issueSavedViewPinnedIds = Set<String>.from(
          widget.api != null
              ? _catalogImportRunIssueSavedViewFavoriteIds(savedIssueViews)
              : _catalogImportRunIssueSavedViewPinnedIds,
        );
        var issueSavedViewUsedAtById = Map<String, String>.from(
          widget.api != null
              ? _catalogImportRunIssueSavedViewUsageMap(savedIssueViews)
              : _catalogImportRunIssueSavedViewUsedAtById,
        );
        final deletingIssueSavedViewIds = <String>{};
        final updatingIssueSavedViewDefaultIds = <String>{};
        var issueSeverityFilter = persistedIssueFilters.hasActiveFilters
            ? persistedIssueFilters.severity
            : (detail.issuesFilters.severity ?? 'all');
        var issueStageFilter = persistedIssueFilters.hasActiveFilters
            ? persistedIssueFilters.stage
            : (detail.issuesFilters.stage ?? 'all');
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            CoachOperatorCatalogImportRunDetailResponse mergeIssueDetailPage(
              CoachOperatorCatalogImportRunDetailResponse nextPage, {
              List<CoachOperatorCatalogImportRunIssue>? issuesOverride,
            }) {
              return CoachOperatorCatalogImportRunDetailResponse(
                generatedAtIso: nextPage.generatedAtIso,
                issuesSummary: nextPage.issuesSummary,
                issuesFilters: nextPage.issuesFilters,
                issuesNextCursor: nextPage.issuesNextCursor,
                importRun: CoachOperatorCatalogImportRun(
                  importRunId: nextPage.importRun.importRunId,
                  feedKind: nextPage.importRun.feedKind,
                  sourceKind: nextPage.importRun.sourceKind,
                  triggerKind: nextPage.importRun.triggerKind,
                  feedLocator: nextPage.importRun.feedLocator,
                  operatorIds: nextPage.importRun.operatorIds,
                  replayedFromImportRunId:
                      nextPage.importRun.replayedFromImportRunId,
                  replayLineageSummary:
                      nextPage.importRun.replayLineageSummary ??
                          detail.importRun.replayLineageSummary,
                  sourceArtifactId: nextPage.importRun.sourceArtifactId,
                  sourceArtifact: nextPage.importRun.sourceArtifact,
                  status: nextPage.importRun.status,
                  startedAtIso: nextPage.importRun.startedAtIso,
                  finishedAtIso: nextPage.importRun.finishedAtIso,
                  counts: nextPage.importRun.counts,
                  errorMessage: nextPage.importRun.errorMessage,
                  issues: issuesOverride ?? nextPage.importRun.issues,
                ),
              );
            }

            Future<void> reloadIssueFilters({
              required String severity,
              required String stage,
            }) async {
              if (importRunId.isEmpty || reloadingIssueFilters) {
                return;
              }
              setSheetState(() {
                reloadingIssueFilters = true;
              });
              try {
                final nextPage = await _api.operatorCatalogImportRun(
                  importRunId,
                  limit: detailPageSize,
                  issueSeverity: severity,
                  issueStage: stage,
                );
                final persistedPreferences =
                    CoachCatalogImportRunIssueFilterPreferences(
                  severity: nextPage.issuesFilters.severity ?? 'all',
                  stage: nextPage.issuesFilters.stage ?? 'all',
                );
                if (persistedPreferences.hasActiveFilters) {
                  await _savePersistedCatalogImportRunIssueFilterPreferences(
                    persistedPreferences,
                  );
                } else {
                  await _clearPersistedCatalogImportRunIssueFilterPreferences();
                }
                setSheetState(() {
                  detail = mergeIssueDetailPage(nextPage);
                  issueSeverityFilter =
                      nextPage.issuesFilters.severity ?? 'all';
                  issueStageFilter = nextPage.issuesFilters.stage ?? 'all';
                  reloadingIssueFilters = false;
                });
              } on CoachApiException catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.detail)),
                  );
                }
                setSheetState(() {
                  reloadingIssueFilters = false;
                });
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
                setSheetState(() {
                  reloadingIssueFilters = false;
                });
              }
            }

            Future<void> reloadIssueSavedViewsForFilters({
              required String scope,
              required String ownerAccountId,
              required String operatorId,
            }) async {
              final normalizedScope =
                  _normalizeCatalogSavedViewVisibilityFilter(scope);
              final normalizedOwnerAccountId = normalizedScope == 'shared_ops'
                  ? _normalizeCatalogSavedViewOwnerAccountIdFilter(
                      ownerAccountId,
                    )
                  : 'all';
              final normalizedOperatorId = normalizedScope == 'shared_ops'
                  ? _normalizeCatalogSavedViewOperatorIdFilter(operatorId)
                  : 'all';
              setSheetState(() {
                issueSavedViewsVisibilityFilter = normalizedScope;
                issueSavedViewsOwnerAccountIdFilter = normalizedOwnerAccountId;
                issueSavedViewsOperatorIdFilter = normalizedOperatorId;
              });
              final updatedViews =
                  await _loadPersistedCatalogImportRunIssueSavedViews(
                visibilityScope: normalizedScope,
                ownerAccountId: normalizedOwnerAccountId,
                operatorId: normalizedOperatorId,
              );
              if (!mounted) {
                return;
              }
              setSheetState(() {
                savedIssueViews = updatedViews;
                issueSavedViewPinnedIds =
                    _catalogImportRunIssueSavedViewFavoriteIds(updatedViews);
                issueSavedViewUsedAtById =
                    _catalogImportRunIssueSavedViewUsageMap(updatedViews);
                _catalogImportRunIssueSavedViewUsedAtById =
                    issueSavedViewUsedAtById;
              });
            }

            Future<void> saveIssueSavedView() async {
              final name = issueSavedViewNameController.text.trim();
              final preferences = CoachCatalogImportRunIssueFilterPreferences(
                severity: issueSeverityFilter,
                stage: issueStageFilter,
              );
              final operatorIds = issueSavedViewVisibilityScope == 'shared_ops'
                  ? _resolveSharedViewOperatorScopeIds(
                      issueSavedViewOperatorIdScope,
                    )
                  : const <String>[];
              if (name.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter an issue saved view name first.'),
                    ),
                  );
                }
                return;
              }
              if (!preferences.hasActiveFilters) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Issue saved views require at least one active issue filter.',
                      ),
                    ),
                  );
                }
                return;
              }
              CoachCatalogImportRunIssueSavedView? existingView;
              for (final candidate in savedIssueViews) {
                if (candidate.name.trim().toLowerCase() == name.toLowerCase() &&
                    candidate.visibilityScope ==
                        issueSavedViewVisibilityScope) {
                  existingView = candidate;
                  break;
                }
              }
              if (existingView != null && !existingView.canManage) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Shared issue drilldown views can only be managed by the owner account.',
                    ),
                  ),
                );
                return;
              }
              final nowIso =
                  _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc());
              setSheetState(() {
                savingIssueSavedView = true;
              });
              final updatedViews =
                  await _savePersistedCatalogImportRunIssueSavedView(
                CoachCatalogImportRunIssueSavedView(
                  viewId: existingView?.viewId ??
                      'catalogimportrunissuesavedview_${_previewHistoryNowUtc().microsecondsSinceEpoch}',
                  accountId: existingView?.accountId ?? '',
                  name: name,
                  visibilityScope: issueSavedViewVisibilityScope,
                  operatorIds: operatorIds,
                  preferences: preferences,
                  isDefault: issueSavedViewVisibilityScope == 'personal'
                      ? (existingView?.isDefault ?? false)
                      : false,
                  isFavorite: existingView?.isFavorite ?? false,
                  lastUsedAtIso: existingView?.lastUsedAtIso,
                  canManage: existingView?.canManage ?? true,
                  createdAtIso: existingView?.createdAtIso ?? nowIso,
                  updatedAtIso: nowIso,
                ),
              );
              if (!mounted) {
                return;
              }
              final visibleUpdatedViews =
                  _filterCatalogImportRunIssueSavedViewsByPrivilegeOperatorScope(
                updatedViews,
              );
              setSheetState(() {
                savedIssueViews =
                    _filterCatalogImportRunIssueSavedViewsByOperatorId(
                  _filterCatalogImportRunIssueSavedViewsByOwnerAccountId(
                    _filterCatalogImportRunIssueSavedViewsByVisibilityScope(
                      visibleUpdatedViews,
                      issueSavedViewsVisibilityFilter,
                    ),
                    issueSavedViewsOwnerAccountIdFilter,
                  ),
                  issueSavedViewsOperatorIdFilter,
                );
                issueSavedViewOwners =
                    _catalogImportRunIssueSavedViewOwnerSummariesFromViews(
                  visibleUpdatedViews,
                );
                issueSavedViewOperators =
                    _catalogImportRunIssueSavedViewOperatorSummariesFromViews(
                  visibleUpdatedViews,
                );
                issueSavedViewPinnedIds =
                    _catalogImportRunIssueSavedViewFavoriteIds(
                  visibleUpdatedViews,
                );
                issueSavedViewUsedAtById =
                    _catalogImportRunIssueSavedViewUsageMap(
                  visibleUpdatedViews,
                );
                _catalogImportRunIssueSavedViewPinnedIds =
                    issueSavedViewPinnedIds;
                _catalogImportRunIssueSavedViewUsedAtById =
                    issueSavedViewUsedAtById;
                savingIssueSavedView = false;
              });
              issueSavedViewNameController.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    existingView == null
                        ? (issueSavedViewVisibilityScope == 'shared_ops'
                            ? 'Saved shared issue drilldown view.'
                            : 'Saved issue drilldown view.')
                        : (issueSavedViewVisibilityScope == 'shared_ops'
                            ? 'Updated shared issue drilldown view.'
                            : 'Updated issue drilldown view.'),
                  ),
                ),
              );
            }

            Future<void> applyIssueSavedView(
              CoachCatalogImportRunIssueSavedView view,
            ) async {
              final usedAtIso =
                  _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc());
              issueSavedViewNameController.text = view.name;
              setSheetState(() {
                issueSavedViewVisibilityScope = view.visibilityScope;
                issueSavedViewOperatorIdScope = view.operatorIds.length == 1
                    ? view.operatorIds.first
                    : 'all';
                issueSavedViewUsedAtById = <String, String>{
                  ...issueSavedViewUsedAtById,
                  view.viewId.trim(): usedAtIso,
                };
              });
              unawaited(
                _recordPersistedSavedViewUsage(
                  collectionKey:
                      _catalogImportRunIssueSavedViewUsageCollectionKey,
                  viewId: view.viewId,
                  currentUsage: _catalogImportRunIssueSavedViewUsedAtById,
                  assign: (value) =>
                      _catalogImportRunIssueSavedViewUsedAtById = value,
                  usedAtIso: usedAtIso,
                ),
              );
              await reloadIssueFilters(
                severity: view.preferences.severity,
                stage: view.preferences.stage,
              );
            }

            Future<void> deleteIssueSavedView(
              CoachCatalogImportRunIssueSavedView view,
            ) async {
              final normalizedViewId = view.viewId.trim();
              if (normalizedViewId.isEmpty) {
                return;
              }
              setSheetState(() {
                deletingIssueSavedViewIds.add(normalizedViewId);
              });
              final updatedViews =
                  await _deletePersistedCatalogImportRunIssueSavedView(
                normalizedViewId,
              );
              if (!mounted) {
                return;
              }
              final visibleUpdatedViews =
                  _filterCatalogImportRunIssueSavedViewsByPrivilegeOperatorScope(
                updatedViews,
              );
              setSheetState(() {
                savedIssueViews =
                    _filterCatalogImportRunIssueSavedViewsByOperatorId(
                  _filterCatalogImportRunIssueSavedViewsByOwnerAccountId(
                    _filterCatalogImportRunIssueSavedViewsByVisibilityScope(
                      visibleUpdatedViews,
                      issueSavedViewsVisibilityFilter,
                    ),
                    issueSavedViewsOwnerAccountIdFilter,
                  ),
                  issueSavedViewsOperatorIdFilter,
                );
                issueSavedViewOwners =
                    _catalogImportRunIssueSavedViewOwnerSummariesFromViews(
                  visibleUpdatedViews,
                );
                issueSavedViewOperators =
                    _catalogImportRunIssueSavedViewOperatorSummariesFromViews(
                  visibleUpdatedViews,
                );
                issueSavedViewPinnedIds =
                    _catalogImportRunIssueSavedViewFavoriteIds(
                  visibleUpdatedViews,
                );
                issueSavedViewUsedAtById =
                    _catalogImportRunIssueSavedViewUsageMap(
                  visibleUpdatedViews,
                );
                _catalogImportRunIssueSavedViewPinnedIds =
                    issueSavedViewPinnedIds;
                _catalogImportRunIssueSavedViewUsedAtById =
                    issueSavedViewUsedAtById;
                deletingIssueSavedViewIds.remove(normalizedViewId);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Issue drilldown saved view deleted.'),
                ),
              );
            }

            Future<void> toggleIssueSavedViewDefault(
              CoachCatalogImportRunIssueSavedView view,
            ) async {
              if (view.visibilityScope != 'personal') {
                return;
              }
              final normalizedViewId = view.viewId.trim();
              if (normalizedViewId.isEmpty) {
                return;
              }
              setSheetState(() {
                updatingIssueSavedViewDefaultIds.add(normalizedViewId);
              });
              final updatedViews =
                  await _savePersistedCatalogImportRunIssueSavedView(
                CoachCatalogImportRunIssueSavedView(
                  viewId: view.viewId,
                  accountId: view.accountId,
                  name: view.name,
                  visibilityScope: view.visibilityScope,
                  operatorIds: view.operatorIds,
                  preferences: view.preferences,
                  isDefault: !view.isDefault,
                  isFavorite: view.isFavorite,
                  lastUsedAtIso: view.lastUsedAtIso,
                  canManage: view.canManage,
                  createdAtIso: view.createdAtIso,
                  updatedAtIso:
                      _formatPreviewHistoryRfc3339Utc(_previewHistoryNowUtc()),
                ),
              );
              if (!mounted) {
                return;
              }
              final visibleUpdatedViews =
                  _filterCatalogImportRunIssueSavedViewsByPrivilegeOperatorScope(
                updatedViews,
              );
              setSheetState(() {
                savedIssueViews =
                    _filterCatalogImportRunIssueSavedViewsByOperatorId(
                  _filterCatalogImportRunIssueSavedViewsByOwnerAccountId(
                    _filterCatalogImportRunIssueSavedViewsByVisibilityScope(
                      visibleUpdatedViews,
                      issueSavedViewsVisibilityFilter,
                    ),
                    issueSavedViewsOwnerAccountIdFilter,
                  ),
                  issueSavedViewsOperatorIdFilter,
                );
                issueSavedViewOwners =
                    _catalogImportRunIssueSavedViewOwnerSummariesFromViews(
                  visibleUpdatedViews,
                );
                issueSavedViewOperators =
                    _catalogImportRunIssueSavedViewOperatorSummariesFromViews(
                  visibleUpdatedViews,
                );
                issueSavedViewPinnedIds =
                    _catalogImportRunIssueSavedViewFavoriteIds(
                  visibleUpdatedViews,
                );
                issueSavedViewUsedAtById =
                    _catalogImportRunIssueSavedViewUsageMap(
                  visibleUpdatedViews,
                );
                _catalogImportRunIssueSavedViewPinnedIds =
                    issueSavedViewPinnedIds;
                _catalogImportRunIssueSavedViewUsedAtById =
                    issueSavedViewUsedAtById;
                updatingIssueSavedViewDefaultIds.remove(normalizedViewId);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    view.isDefault
                        ? 'Cleared default issue drilldown view.'
                        : 'Set default issue drilldown view.',
                  ),
                ),
              );
            }

            Future<void> loadMoreIssues() async {
              final nextCursor = detail.issuesNextCursor?.trim();
              if (importRunId.isEmpty ||
                  loadingMoreIssues ||
                  nextCursor == null ||
                  nextCursor.isEmpty) {
                return;
              }
              setSheetState(() {
                loadingMoreIssues = true;
              });
              try {
                final nextPage = await _api.operatorCatalogImportRun(
                  importRunId,
                  limit: detailPageSize,
                  cursor: nextCursor,
                  issueSeverity: issueSeverityFilter,
                  issueStage: issueStageFilter,
                );
                final mergedIssues = <CoachOperatorCatalogImportRunIssue>[
                  ...detail.importRun.issues,
                  ...nextPage.importRun.issues.where(
                    (candidate) => !detail.importRun.issues.any(
                      (existing) => existing.issueId == candidate.issueId,
                    ),
                  ),
                ];
                setSheetState(() {
                  detail = mergeIssueDetailPage(
                    nextPage,
                    issuesOverride: mergedIssues,
                  );
                  issueSeverityFilter =
                      nextPage.issuesFilters.severity ?? 'all';
                  issueStageFilter = nextPage.issuesFilters.stage ?? 'all';
                  loadingMoreIssues = false;
                });
              } on CoachApiException catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.detail)),
                  );
                }
                setSheetState(() {
                  loadingMoreIssues = false;
                });
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
                setSheetState(() {
                  loadingMoreIssues = false;
                });
              }
            }

            Future<void> loadMoreReplayRuns() async {
              final nextCursor = lineage?.replayRunsNextCursor?.trim();
              if (importRunId.isEmpty ||
                  loadingMoreReplayRuns ||
                  nextCursor == null ||
                  nextCursor.isEmpty) {
                return;
              }
              setSheetState(() {
                loadingMoreReplayRuns = true;
              });
              try {
                final nextPage = await _api.operatorCatalogImportRunLineage(
                  importRunId,
                  limit: detailPageSize,
                  cursor: nextCursor,
                );
                final existingReplayRuns = lineage?.replayRuns ?? const [];
                final mergedReplayRuns = <CoachOperatorCatalogImportRun>[
                  ...existingReplayRuns,
                  ...nextPage.replayRuns.where(
                    (candidate) => !existingReplayRuns.any(
                      (existing) =>
                          existing.importRunId == candidate.importRunId,
                    ),
                  ),
                ];
                setSheetState(() {
                  lineage = CoachOperatorCatalogImportRunLineageResponse(
                    generatedAtIso: nextPage.generatedAtIso,
                    importRun: nextPage.importRun,
                    replayRunsSummary: nextPage.replayRunsSummary,
                    replayRunsNextCursor: nextPage.replayRunsNextCursor,
                    replayRuns: mergedReplayRuns,
                  );
                  loadingMoreReplayRuns = false;
                });
              } on CoachApiException catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.detail)),
                  );
                }
                setSheetState(() {
                  loadingMoreReplayRuns = false;
                });
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
                setSheetState(() {
                  loadingMoreReplayRuns = false;
                });
              }
            }

            final resolvedEntry = detail.importRun;
            final sourceArtifact = resolvedEntry.sourceArtifact;
            final issuesSummary = detail.issuesSummary;
            final issueFilters = detail.issuesFilters;
            final hasMoreIssues =
                (detail.issuesNextCursor ?? '').trim().isNotEmpty;
            final replayRunsSummary = lineage?.replayRunsSummary;
            final replayRuns =
                lineage?.replayRuns ?? const <CoachOperatorCatalogImportRun>[];
            final hasMoreReplayRuns =
                (lineage?.replayRunsNextCursor ?? '').trim().isNotEmpty;
            final isArabic = L10n.of(sheetContext).isArabic;
            final hasActiveIssueFilters =
                issueSeverityFilter != 'all' || issueStageFilter != 'all';
            final issueSummaryText = <String>[
              if (hasActiveIssueFilters)
                'Filtered ${issuesSummary.filteredIssues} of ${issuesSummary.totalIssues}',
              'Loaded ${resolvedEntry.issues.length}',
              'errors ${issuesSummary.errorIssues}',
              'warnings ${issuesSummary.warningIssues}',
            ].join(' • ');
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Catalog import run details',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(resolvedEntry.importRunId,
                          style: Theme.of(sheetContext).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text('Status: ${resolvedEntry.status}'),
                      const SizedBox(height: 4),
                      Text('Trigger: ${resolvedEntry.triggerKind}'),
                      const SizedBox(height: 4),
                      Text('Source kind: ${resolvedEntry.sourceKind}'),
                      const SizedBox(height: 4),
                      Text('Feed kind: ${resolvedEntry.feedKind}'),
                      const SizedBox(height: 4),
                      Text('Started at: ${resolvedEntry.startedAtIso}'),
                      if (resolvedEntry.finishedAtIso != null) ...[
                        const SizedBox(height: 4),
                        Text('Finished at: ${resolvedEntry.finishedAtIso}'),
                      ],
                      if (resolvedEntry.feedLocator != null) ...[
                        const SizedBox(height: 4),
                        Text('Feed locator: ${resolvedEntry.feedLocator}'),
                      ],
                      if ((resolvedEntry.sourceArtifactId ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                            'Source artifact id: ${resolvedEntry.sourceArtifactId}'),
                      ],
                      if ((resolvedEntry.replayedFromImportRunId ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Replayed from import run: ${resolvedEntry.replayedFromImportRunId}',
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsCatalogImportRunViewReplaySource_${resolvedEntry.importRunId}',
                            ),
                            onPressed: () {
                              final replaySourceImportRunId =
                                  resolvedEntry.replayedFromImportRunId?.trim();
                              if (replaySourceImportRunId == null ||
                                  replaySourceImportRunId.isEmpty) {
                                return;
                              }
                              Navigator.of(sheetContext).pop();
                              _showCatalogImportRunDetails(
                                _catalogImportRunEntryForDetail(
                                  replaySourceImportRunId,
                                ),
                              );
                            },
                            icon: const Icon(Icons.history_outlined),
                            label: const Text('View replay source'),
                          ),
                        ),
                        if (!_catalogImportMutationsAllowed) ...[
                          const SizedBox(height: 6),
                          Text(
                            _coachCatalogImportRunReplaySourceReadOnlyHintText(
                              isArabic,
                            ),
                            key: ValueKey(
                              'coachOpsCatalogImportRunViewReplaySourceReadOnlyHint_${resolvedEntry.importRunId}',
                            ),
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ],
                      ],
                      if (!_catalogImportMutationsAllowed) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _coachCatalogImportRunDetailReadOnlyHintText(
                              isArabic,
                              resolvedEntry,
                            ),
                            key: ValueKey(
                              'coachOpsCatalogImportRunDetailReadOnlyHint_${resolvedEntry.importRunId}',
                            ),
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Counts',
                        style: Theme.of(sheetContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text('Operators: ${resolvedEntry.counts.operators}'),
                      const SizedBox(height: 4),
                      Text(
                        'Operator scope: ${_coachFormatCatalogOperatorScope(resolvedEntry.operatorIds)}',
                      ),
                      const SizedBox(height: 4),
                      Text('Cities: ${resolvedEntry.counts.cities}'),
                      const SizedBox(height: 4),
                      Text(
                          'Stop clusters: ${resolvedEntry.counts.stopClusters}'),
                      const SizedBox(height: 4),
                      Text('Stops: ${resolvedEntry.counts.stops}'),
                      const SizedBox(height: 4),
                      Text('Lines: ${resolvedEntry.counts.lines}'),
                      const SizedBox(height: 4),
                      Text(
                          'Service calendars: ${resolvedEntry.counts.serviceCalendars}'),
                      const SizedBox(height: 4),
                      Text('Trips: ${resolvedEntry.counts.trips}'),
                      const SizedBox(height: 4),
                      Text(
                          'Fare products: ${resolvedEntry.counts.fareProducts}'),
                      const SizedBox(height: 4),
                      Text(
                          'Total records: ${resolvedEntry.counts.totalRecords}'),
                      if (sourceArtifact != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Source artifact',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(sourceArtifact.sourceLabel),
                        const SizedBox(height: 4),
                        Text(
                          '${sourceArtifact.artifactId} • ${sourceArtifact.contentLengthBytes} bytes',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsCatalogImportRunViewSourceArtifact_${resolvedEntry.importRunId}',
                            ),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _showCatalogSourceArtifactDetails(
                                sourceArtifact,
                                importRunId: resolvedEntry.importRunId,
                              );
                            },
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('View source artifact'),
                          ),
                        ),
                        if (!_catalogImportMutationsAllowed) ...[
                          const SizedBox(height: 6),
                          Text(
                            _coachCatalogImportRunSourceArtifactReadOnlyHintText(
                              isArabic,
                            ),
                            key: ValueKey(
                              'coachOpsCatalogImportRunViewSourceArtifactReadOnlyHint_${resolvedEntry.importRunId}',
                            ),
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ],
                      ],
                      if (_catalogImportMutationsAllowed &&
                          (resolvedEntry.importRunId.trim().isNotEmpty)) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsCatalogImportRunReplay_${resolvedEntry.importRunId}',
                            ),
                            onPressed: _runningCatalogImport || _loadingQueues
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                    _triggerCatalogImportRun(
                                      replayImportRunId:
                                          resolvedEntry.importRunId,
                                      sourceLabel:
                                          sourceArtifact?.sourceLabel ??
                                              resolvedEntry.feedLocator ??
                                              resolvedEntry.importRunId,
                                    );
                                  },
                            icon: _runningCatalogImport
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_outlined),
                            label: Text(
                              _runningCatalogImport
                                  ? 'Replaying import...'
                                  : 'Replay this run',
                            ),
                          ),
                        ),
                      ],
                      if (replayRunsSummary != null &&
                          replayRunsSummary.totalRuns > 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Replay runs (${replayRunsSummary.totalRuns})',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Loaded ${replayRuns.length} • '
                          'failed ${replayRunsSummary.failedRuns} • '
                          'succeeded ${replayRunsSummary.succeededRuns} • '
                          'running ${replayRunsSummary.runningRuns}',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        ...replayRuns.map(
                          (replayRun) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${replayRun.importRunId} • ${replayRun.status} • ${replayRun.triggerKind}',
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: ValueKey(
                                      'coachOpsCatalogImportRunViewReplayRun_${resolvedEntry.importRunId}_${replayRun.importRunId}',
                                    ),
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _showCatalogImportRunDetails(replayRun);
                                    },
                                    icon:
                                        const Icon(Icons.open_in_new_outlined),
                                    label: const Text('View run'),
                                  ),
                                ),
                                if (!_catalogImportMutationsAllowed) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _coachCatalogImportRunReplayEntryReadOnlyHintText(
                                      isArabic,
                                    ),
                                    key: ValueKey(
                                      'coachOpsCatalogImportRunViewReplayRunReadOnlyHint_${resolvedEntry.importRunId}_${replayRun.importRunId}',
                                    ),
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (hasMoreReplayRuns) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: ValueKey(
                                'coachOpsCatalogImportRunLoadOlderReplays_${resolvedEntry.importRunId}',
                              ),
                              onPressed: loadingMoreReplayRuns
                                  ? null
                                  : loadMoreReplayRuns,
                              icon: loadingMoreReplayRuns
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.history_outlined),
                              label: Text(
                                loadingMoreReplayRuns
                                    ? 'Loading older replay runs...'
                                    : 'Load older replay runs',
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (issuesSummary.totalIssues > 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Issues (${issuesSummary.totalIssues})',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          issueSummaryText,
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              key: ValueKey(
                                'coachOpsCatalogImportRunIssuePresetErrors_${resolvedEntry.importRunId}',
                              ),
                              onPressed: reloadingIssueFilters
                                  ? null
                                  : () => reloadIssueFilters(
                                        severity: 'error',
                                        stage: 'all',
                                      ),
                              child: const Text('Errors only'),
                            ),
                            if (issueFilters.availableSeverities
                                .map((value) => value.toLowerCase())
                                .contains('warning'))
                              OutlinedButton(
                                key: ValueKey(
                                  'coachOpsCatalogImportRunIssuePresetWarnings_${resolvedEntry.importRunId}',
                                ),
                                onPressed: reloadingIssueFilters
                                    ? null
                                    : () => reloadIssueFilters(
                                          severity: 'warning',
                                          stage: 'all',
                                        ),
                                child: const Text('Warnings only'),
                              ),
                            if (issueFilters.availableStages
                                .map((value) => value.toLowerCase())
                                .contains('load_feed'))
                              OutlinedButton(
                                key: ValueKey(
                                  'coachOpsCatalogImportRunIssuePresetLoadFeed_${resolvedEntry.importRunId}',
                                ),
                                onPressed: reloadingIssueFilters
                                    ? null
                                    : () => reloadIssueFilters(
                                          severity: 'all',
                                          stage: 'load_feed',
                                        ),
                                child: const Text('Load feed only'),
                              ),
                            if (hasActiveIssueFilters)
                              OutlinedButton(
                                key: ValueKey(
                                  'coachOpsCatalogImportRunIssuePresetClear_${resolvedEntry.importRunId}',
                                ),
                                onPressed: reloadingIssueFilters
                                    ? null
                                    : () => reloadIssueFilters(
                                          severity: 'all',
                                          stage: 'all',
                                        ),
                                child: const Text('Clear issue filters'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'coachOpsCatalogImportRunIssueSeverityFilterField_${resolvedEntry.importRunId}',
                          ),
                          initialValue: issueSeverityFilter,
                          decoration: const InputDecoration(
                            labelText: 'Issue severity',
                            isDense: true,
                          ),
                          items: <String>[
                            'all',
                            ...issueFilters.availableSeverities,
                          ]
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    value == 'all' ? 'All severities' : value,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: reloadingIssueFilters
                              ? null
                              : (value) {
                                  final nextSeverity = value ?? 'all';
                                  if (nextSeverity == issueSeverityFilter) {
                                    return;
                                  }
                                  reloadIssueFilters(
                                    severity: nextSeverity,
                                    stage: issueStageFilter,
                                  );
                                },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'coachOpsCatalogImportRunIssueStageFilterField_${resolvedEntry.importRunId}',
                          ),
                          initialValue: issueStageFilter,
                          decoration: const InputDecoration(
                            labelText: 'Issue stage',
                            isDense: true,
                          ),
                          items: <String>[
                            'all',
                            ...issueFilters.availableStages,
                          ]
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    value == 'all' ? 'All stages' : value,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: reloadingIssueFilters
                              ? null
                              : (value) {
                                  final nextStage = value ?? 'all';
                                  if (nextStage == issueStageFilter) {
                                    return;
                                  }
                                  reloadIssueFilters(
                                    severity: issueSeverityFilter,
                                    stage: nextStage,
                                  );
                                },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Issue saved views',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Personal views stay on your ops account. Shared views are visible to all coach ops accounts.',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'coachOpsCatalogImportRunIssueSavedViewsVisibilityFilterField_${resolvedEntry.importRunId}',
                          ),
                          initialValue: issueSavedViewsVisibilityFilter,
                          decoration: const InputDecoration(
                            labelText: 'Show saved views',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('All scopes'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'personal',
                              child: Text('Personal only'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'shared_ops',
                              child: Text('Shared with ops only'),
                            ),
                          ],
                          onChanged:
                              savingIssueSavedView || reloadingIssueFilters
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      unawaited(
                                        reloadIssueSavedViewsForFilters(
                                          scope: value,
                                          ownerAccountId: 'all',
                                          operatorId: 'all',
                                        ),
                                      );
                                    },
                        ),
                        if (issueSavedViewsVisibilityFilter ==
                            'shared_ops') ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'coachOpsCatalogImportRunIssueSavedViewsOwnerFilterField_${resolvedEntry.importRunId}',
                            ),
                            initialValue: issueSavedViewsOwnerAccountIdFilter,
                            decoration: const InputDecoration(
                              labelText: 'Shared view owner',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items:
                                _catalogImportRunIssueSavedViewOwnerAccountIdOptions(
                              issueSavedViewOwners,
                              issueSavedViewsOwnerAccountIdFilter,
                            ).map((value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  _catalogSavedViewOwnerFilterOptionLabel(
                                    value,
                                    issueSavedViewOwners,
                                  ),
                                ),
                              );
                            }).toList(growable: false),
                            onChanged: savingIssueSavedView ||
                                    reloadingIssueFilters
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    unawaited(
                                      reloadIssueSavedViewsForFilters(
                                        scope: issueSavedViewsVisibilityFilter,
                                        ownerAccountId: value,
                                        operatorId:
                                            issueSavedViewsOperatorIdFilter,
                                      ),
                                    );
                                  },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _catalogSavedViewOwnerFilterSummaryText(
                              issueSavedViewOwners,
                              issueSavedViewsOwnerAccountIdFilter,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'coachOpsCatalogImportRunIssueSavedViewsOperatorFilterField_${resolvedEntry.importRunId}',
                            ),
                            initialValue: issueSavedViewsOperatorIdFilter,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Shared operator scope',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _catalogSavedViewOperatorIdOptions(
                              summaries: issueSavedViewOperators,
                              selectedOperatorId:
                                  issueSavedViewsOperatorIdFilter,
                            ).map((value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  _catalogOperatorFilterOptionLabel(
                                    value,
                                    summaries: issueSavedViewOperators,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(growable: false),
                            onChanged: savingIssueSavedView ||
                                    reloadingIssueFilters
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    unawaited(
                                      reloadIssueSavedViewsForFilters(
                                        scope: issueSavedViewsVisibilityFilter,
                                        ownerAccountId:
                                            issueSavedViewsOwnerAccountIdFilter,
                                        operatorId: value,
                                      ),
                                    );
                                  },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _catalogOperatorFilterSummaryText(
                              issueSavedViewsOperatorIdFilter,
                              summaries: issueSavedViewOperators,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          key: ValueKey(
                            'coachOpsCatalogImportRunIssueSavedViewNameField_${resolvedEntry.importRunId}',
                          ),
                          controller: issueSavedViewNameController,
                          enabled:
                              !savingIssueSavedView && !reloadingIssueFilters,
                          decoration: const InputDecoration(
                            labelText: 'Saved issue view name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'coachOpsCatalogImportRunIssueSavedViewScopeField_${resolvedEntry.importRunId}',
                          ),
                          initialValue: issueSavedViewVisibilityScope,
                          decoration: const InputDecoration(
                            labelText: 'View scope',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: 'personal',
                              child: Text('Personal'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'shared_ops',
                              child: Text('Shared with ops'),
                            ),
                          ],
                          onChanged:
                              savingIssueSavedView || reloadingIssueFilters
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setSheetState(() {
                                        issueSavedViewVisibilityScope = value;
                                      });
                                    },
                        ),
                        if (issueSavedViewVisibilityScope == 'shared_ops') ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'coachOpsCatalogImportRunIssueSavedViewOperatorScopeField_${resolvedEntry.importRunId}',
                            ),
                            initialValue: issueSavedViewOperatorIdScope,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Shared operator scope',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _catalogSavedViewOperatorIdOptions(
                              summaries: issueSavedViewOperators,
                              selectedOperatorId: issueSavedViewOperatorIdScope,
                            ).map((value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  _catalogOperatorFilterOptionLabel(
                                    value,
                                    summaries: issueSavedViewOperators,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(growable: false),
                            onChanged:
                                savingIssueSavedView || reloadingIssueFilters
                                    ? null
                                    : (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setSheetState(() {
                                          issueSavedViewOperatorIdScope =
                                              _normalizeCatalogSavedViewOperatorIdFilter(
                                            value,
                                          );
                                        });
                                      },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _catalogOperatorFilterSummaryText(
                              issueSavedViewOperatorIdScope,
                              summaries: issueSavedViewOperators,
                            ),
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsCatalogImportRunIssueSaveView_${resolvedEntry.importRunId}',
                            ),
                            onPressed:
                                savingIssueSavedView || reloadingIssueFilters
                                    ? null
                                    : saveIssueSavedView,
                            icon: savingIssueSavedView
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.bookmark_add_outlined),
                            label: Text(
                              savingIssueSavedView
                                  ? 'Saving issue view...'
                                  : 'Save issue view',
                            ),
                          ),
                        ),
                        if (_recentlyUsedSavedViews(
                          savedIssueViews,
                          viewIdOf: (view) => view.viewId,
                          usedAtById: issueSavedViewUsedAtById,
                        ).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Recent views',
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _recentlyUsedSavedViews(
                              savedIssueViews,
                              viewIdOf: (view) => view.viewId,
                              usedAtById: issueSavedViewUsedAtById,
                            ).map((view) {
                              final isCurrent =
                                  _catalogImportRunIssueSavedViewIsCurrent(
                                view: view,
                                selectedVisibilityScope:
                                    issueSavedViewsVisibilityFilter,
                                selectedOwnerAccountId:
                                    issueSavedViewsOwnerAccountIdFilter,
                                selectedOperatorId:
                                    issueSavedViewsOperatorIdFilter,
                                issueSeverityFilter: issueSeverityFilter,
                                issueStageFilter: issueStageFilter,
                              );
                              return ActionChip(
                                key: ValueKey(
                                  'coachOpsCatalogImportRunIssueRecentSavedView_${resolvedEntry.importRunId}_${view.viewId}',
                                ),
                                avatar: const Icon(
                                  Icons.history,
                                  size: 18,
                                ),
                                label: Text(view.name),
                                onPressed: savingIssueSavedView ||
                                        reloadingIssueFilters ||
                                        isCurrent
                                    ? null
                                    : () => applyIssueSavedView(view),
                              );
                            }).toList(growable: false),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (savedIssueViews.isEmpty)
                          Text(
                            'No issue saved views yet.',
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _prioritizeSavedViews(
                              savedIssueViews,
                              isCurrent: (view) =>
                                  _catalogImportRunIssueSavedViewIsCurrent(
                                view: view,
                                selectedVisibilityScope:
                                    issueSavedViewsVisibilityFilter,
                                selectedOwnerAccountId:
                                    issueSavedViewsOwnerAccountIdFilter,
                                selectedOperatorId:
                                    issueSavedViewsOperatorIdFilter,
                                issueSeverityFilter: issueSeverityFilter,
                                issueStageFilter: issueStageFilter,
                              ),
                              isDefault: (view) => view.isDefault,
                              viewIdOf: (view) => view.viewId,
                              pinnedViewIds: issueSavedViewPinnedIds,
                              usedAtById: issueSavedViewUsedAtById,
                            ).map((view) {
                              final normalizedViewId = view.viewId.trim();
                              final deleting = deletingIssueSavedViewIds
                                  .contains(normalizedViewId);
                              final isPinnedView = _savedViewIsPinned(
                                issueSavedViewPinnedIds,
                                view.viewId,
                              );
                              final activeChipLabels =
                                  _catalogSavedViewActiveChipLabels(
                                selectedVisibilityScope:
                                    issueSavedViewsVisibilityFilter,
                                viewVisibilityScope: view.visibilityScope,
                                viewAccountId: view.accountId,
                                selectedOwnerAccountId:
                                    issueSavedViewsOwnerAccountIdFilter,
                                operatorIds: view.operatorIds,
                                selectedOperatorId:
                                    issueSavedViewsOperatorIdFilter,
                              );
                              final isCurrentView =
                                  _catalogImportRunIssueSavedViewIsCurrent(
                                view: view,
                                selectedVisibilityScope:
                                    issueSavedViewsVisibilityFilter,
                                selectedOwnerAccountId:
                                    issueSavedViewsOwnerAccountIdFilter,
                                selectedOperatorId:
                                    issueSavedViewsOperatorIdFilter,
                                issueSeverityFilter: issueSeverityFilter,
                                issueStageFilter: issueStageFilter,
                              );
                              final recentlyUsedLabel =
                                  _savedViewRecentlyUsedChipLabel(
                                issueSavedViewUsedAtById[view.viewId],
                              );
                              final showStateChips =
                                  activeChipLabels.isNotEmpty ||
                                      isCurrentView ||
                                      recentlyUsedLabel != null;
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(sheetContext)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      view.name,
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Chip(
                                      label: Text(
                                        _catalogSavedViewVisibilityScopeLabel(
                                          view.visibilityScope,
                                        ),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    if (view.isDefault) ...[
                                      const SizedBox(height: 4),
                                      Chip(
                                        label: const Text('Default view'),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ],
                                    if (isPinnedView) ...[
                                      const SizedBox(height: 4),
                                      Chip(
                                        label: const Text('Pinned'),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    if (_catalogSavedViewOwnerLabel(
                                          view.visibilityScope,
                                          view.accountId,
                                        ) !=
                                        null)
                                      Text(
                                        _catalogSavedViewOwnerLabel(
                                          view.visibilityScope,
                                          view.accountId,
                                        )!,
                                        style: Theme.of(sheetContext)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    if (_catalogSavedViewOwnerLabel(
                                          view.visibilityScope,
                                          view.accountId,
                                        ) !=
                                        null)
                                      const SizedBox(height: 4),
                                    if (_catalogSavedViewReadOnlyLabel(
                                          view.visibilityScope,
                                          view.canManage,
                                        ) !=
                                        null)
                                      Text(
                                        _catalogSavedViewReadOnlyLabel(
                                          view.visibilityScope,
                                          view.canManage,
                                        )!,
                                        style: Theme.of(sheetContext)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    if (_catalogSavedViewReadOnlyLabel(
                                          view.visibilityScope,
                                          view.canManage,
                                        ) !=
                                        null)
                                      const SizedBox(height: 4),
                                    if (view.visibilityScope == 'shared_ops')
                                      Text(
                                        'Operator scope: ${_coachFormatCatalogOperatorScope(view.operatorIds)}',
                                        style: Theme.of(sheetContext)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    if (view.visibilityScope == 'shared_ops')
                                      const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children:
                                          _catalogImportRunIssueSavedViewContentChipLabels(
                                        view.preferences,
                                      ).map((label) {
                                        return Chip(
                                          label: Text(label),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        );
                                      }).toList(growable: false),
                                    ),
                                    if (showStateChips)
                                      const SizedBox(height: 6),
                                    if (showStateChips)
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          ...activeChipLabels.map((label) {
                                            return Chip(
                                              label: Text(label),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            );
                                          }),
                                          if (isCurrentView)
                                            const Chip(
                                              label: Text('Using this view'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          if (recentlyUsedLabel != null)
                                            Chip(
                                              label: Text(recentlyUsedLabel),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                        ],
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Severity: ${view.preferences.severity} • Stage: ${view.preferences.stage}',
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton(
                                          key: ValueKey(
                                            'coachOpsCatalogImportRunIssueApplySavedView_${resolvedEntry.importRunId}_${view.viewId}',
                                          ),
                                          onPressed: reloadingIssueFilters ||
                                                  isCurrentView
                                              ? null
                                              : () => applyIssueSavedView(view),
                                          child: Text(
                                            isCurrentView
                                                ? 'View already active'
                                                : 'Apply',
                                          ),
                                        ),
                                        OutlinedButton(
                                          key: ValueKey(
                                            'coachOpsCatalogImportRunIssueTogglePinnedSavedView_${resolvedEntry.importRunId}_${view.viewId}',
                                          ),
                                          onPressed: reloadingIssueFilters ||
                                                  savingIssueSavedView
                                              ? null
                                              : () async {
                                                  final nextPinned =
                                                      !isPinnedView;
                                                  setSheetState(() {
                                                    issueSavedViewPinnedIds =
                                                        <String>{
                                                      ...issueSavedViewPinnedIds,
                                                    };
                                                    if (nextPinned) {
                                                      issueSavedViewPinnedIds
                                                          .add(
                                                        normalizedViewId,
                                                      );
                                                    } else {
                                                      issueSavedViewPinnedIds
                                                          .remove(
                                                        normalizedViewId,
                                                      );
                                                    }
                                                  });
                                                  final updatedIssueSavedViews =
                                                      await _toggleCatalogImportRunIssueSavedViewFavorite(
                                                    currentViews:
                                                        savedIssueViews,
                                                    viewId: view.viewId,
                                                    favorite: nextPinned,
                                                  );
                                                  if (!mounted) {
                                                    return;
                                                  }
                                                  setSheetState(() {
                                                    savedIssueViews =
                                                        updatedIssueSavedViews;
                                                    if (widget.api != null) {
                                                      issueSavedViewPinnedIds =
                                                          _catalogImportRunIssueSavedViewFavoriteIds(
                                                        updatedIssueSavedViews,
                                                      );
                                                    }
                                                  });
                                                },
                                          child: Text(
                                            isPinnedView
                                                ? 'Unpin view'
                                                : 'Pin view',
                                          ),
                                        ),
                                        OutlinedButton(
                                          key: ValueKey(
                                            'coachOpsCatalogImportRunIssueFilterByOwner_${resolvedEntry.importRunId}_${view.viewId}',
                                          ),
                                          onPressed: reloadingIssueFilters ||
                                                  view.visibilityScope !=
                                                      'shared_ops' ||
                                                  view.accountId
                                                      .trim()
                                                      .isEmpty ||
                                                  _catalogSavedViewMatchesOwnerFilter(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                    issueSavedViewsVisibilityFilter,
                                                    issueSavedViewsOwnerAccountIdFilter,
                                                  )
                                              ? null
                                              : () => unawaited(
                                                    reloadIssueSavedViewsForFilters(
                                                      scope: 'shared_ops',
                                                      ownerAccountId:
                                                          view.accountId,
                                                      operatorId:
                                                          issueSavedViewsOperatorIdFilter,
                                                    ),
                                                  ),
                                          child: const Text('Filter by owner'),
                                        ),
                                        OutlinedButton(
                                          key: ValueKey(
                                            'coachOpsCatalogImportRunIssueFilterByOperator_${resolvedEntry.importRunId}_${view.viewId}',
                                          ),
                                          onPressed: reloadingIssueFilters ||
                                                  view.visibilityScope !=
                                                      'shared_ops' ||
                                                  view.operatorIds.length !=
                                                      1 ||
                                                  _catalogSavedViewMatchesOperatorFilter(
                                                    view.operatorIds,
                                                    issueSavedViewsOperatorIdFilter,
                                                  )
                                              ? null
                                              : () => unawaited(
                                                    reloadIssueSavedViewsForFilters(
                                                      scope: 'shared_ops',
                                                      ownerAccountId:
                                                          issueSavedViewsOwnerAccountIdFilter,
                                                      operatorId: view
                                                          .operatorIds.single,
                                                    ),
                                                  ),
                                          child:
                                              const Text('Filter by operator'),
                                        ),
                                        OutlinedButton(
                                          key: ValueKey(
                                            'coachOpsCatalogImportRunIssueToggleDefaultSavedView_${resolvedEntry.importRunId}_${view.viewId}',
                                          ),
                                          onPressed: view.visibilityScope !=
                                                      'personal' ||
                                                  reloadingIssueFilters ||
                                                  updatingIssueSavedViewDefaultIds
                                                      .contains(view.viewId)
                                              ? null
                                              : () =>
                                                  toggleIssueSavedViewDefault(
                                                    view,
                                                  ),
                                          child: Text(
                                            view.isDefault
                                                ? 'Clear default'
                                                : 'Set default',
                                          ),
                                        ),
                                        OutlinedButton(
                                          key: ValueKey(
                                            'coachOpsCatalogImportRunIssueDeleteSavedView_${resolvedEntry.importRunId}_${view.viewId}',
                                          ),
                                          onPressed: deleting || !view.canManage
                                              ? null
                                              : () => deleteIssueSavedView(
                                                    view,
                                                  ),
                                          child: Text(
                                            deleting ? 'Deleting...' : 'Delete',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(growable: false),
                          ),
                      ],
                      if (resolvedEntry.issues.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...resolvedEntry.issues.map(
                          (issue) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${issue.severity.toUpperCase()} • ${issue.stage} • ${issue.code}',
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .bodySmall,
                                ),
                                const SizedBox(height: 2),
                                Text(issue.message),
                                if (issue.fileName != null &&
                                    issue.fileName!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'File: ${issue.fileName}',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                                if (issue.rowReference != null &&
                                    issue.rowReference!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Row: ${issue.rowReference}',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (hasMoreIssues) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsCatalogImportRunLoadOlderIssues_${resolvedEntry.importRunId}',
                            ),
                            onPressed:
                                loadingMoreIssues ? null : loadMoreIssues,
                            icon: loadingMoreIssues
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.history_outlined),
                            label: Text(
                              loadingMoreIssues
                                  ? 'Loading older issues...'
                                  : 'Load older issues',
                            ),
                          ),
                        ),
                      ],
                      if (resolvedEntry.errorMessage != null &&
                          resolvedEntry.errorMessage!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Error',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(resolvedEntry.errorMessage!),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      );
    } finally {
      issueSavedViewNameController.dispose();
    }
  }

  Future<void> _triggerCatalogImportRun({
    String? sourceArtifactId,
    String? replayImportRunId,
    String? sourceLabel,
  }) async {
    setState(() {
      _runningCatalogImport = true;
    });
    try {
      final mutation = await _api.triggerOperatorCatalogImportRun(
        sourceArtifactId: sourceArtifactId,
        replayImportRunId: replayImportRunId,
      );
      final refreshedConfig = await _api.operatorCatalogImportConfig();
      final refreshedFeedHealth = await _api.operatorFeedHealth();
      final refreshedArtifacts = await _api.operatorCatalogSourceArtifacts(
        limit: 8,
      );
      final refreshedRuns = await _api.operatorCatalogImportRuns(
        limit: 8,
        status: _catalogImportRunStatusFilter,
        replayScope: _catalogImportRunReplayScopeFilter,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogImportConfig = refreshedConfig;
        _operatorFeedHealth = refreshedFeedHealth;
        _catalogSourceArtifacts = refreshedArtifacts;
        _catalogImportRuns = refreshedRuns;
        _loadingMoreCatalogSourceArtifacts = false;
        _loadingMoreCatalogImportRuns = false;
        _runningCatalogImport = false;
      });
      final importRun = mutation.importRun;
      final replayLabel = replayImportRunId?.trim();
      final message = importRun.isSucceeded
          ? replayLabel != null && replayLabel.isNotEmpty
              ? 'Catalog import replay completed for $replayLabel.'
              : sourceLabel == null || sourceLabel.isEmpty
                  ? 'Catalog import completed.'
                  : 'Catalog import completed for $sourceLabel.'
          : replayLabel != null && replayLabel.isNotEmpty
              ? importRun.errorMessage == null ||
                      importRun.errorMessage!.isEmpty
                  ? 'Catalog import replay failed for $replayLabel.'
                  : 'Catalog import replay failed for $replayLabel: ${importRun.errorMessage}'
              : importRun.errorMessage == null ||
                      importRun.errorMessage!.isEmpty
                  ? 'Catalog import failed.'
                  : 'Catalog import failed: ${importRun.errorMessage}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _runningCatalogImport = false;
      });
      final isArabic = L10n.of(context).isArabic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _coachCatalogImportActionableErrorDetail(
              error.detail,
              isArabic: isArabic,
              action: _CoachCatalogImportMutationAction.triggerRun,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _runningCatalogImport = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _saveCatalogImportConfig() async {
    final feedLocator = _catalogImportFeedLocatorController.text.trim();
    if (feedLocator.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feed locator required.')),
      );
      return;
    }
    setState(() {
      _savingCatalogImportConfig = true;
    });
    try {
      final mutationFuture = _api.updateOperatorCatalogImportConfig(
        feedLocator: feedLocator,
      );
      final sourcesFuture = _api.operatorCatalogImportSources();
      final artifactsFuture = _api.operatorCatalogSourceArtifacts(limit: 8);
      final mutation = await mutationFuture;
      final sources = await sourcesFuture;
      final artifacts = await artifactsFuture;
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogImportConfig = mutation.config;
        _catalogImportSources = sources;
        _catalogSourceArtifacts = artifacts;
        _syncCatalogImportConfigDraft(mutation.config);
        _loadingMoreCatalogSourceArtifacts = false;
        _savingCatalogImportConfig = false;
      });
      final message = mutation.config.isReady
          ? 'Catalog import configuration saved.'
          : 'Catalog import configuration saved, but the feed source still needs verification.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savingCatalogImportConfig = false;
      });
      final isArabic = L10n.of(context).isArabic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _coachCatalogImportActionableErrorDetail(
              error.detail,
              isArabic: isArabic,
              action: _CoachCatalogImportMutationAction.saveConfig,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savingCatalogImportConfig = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _uploadCatalogImportSourceFile() async {
    final selectedFile = _selectedCatalogImportFile;
    if (selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a GTFS ZIP file first.')),
      );
      return;
    }
    setState(() {
      _uploadingCatalogImportSource = true;
    });
    try {
      final uploadFuture = _api.uploadOperatorCatalogImportSourceFile(
        fileName: selectedFile.fileName,
        fileBytes: selectedFile.bytes,
      );
      final sourcesFuture = _api.operatorCatalogImportSources();
      final artifactsFuture = _api.operatorCatalogSourceArtifacts(limit: 8);
      final upload = await uploadFuture;
      final sources = await sourcesFuture;
      final artifacts = await artifactsFuture;
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogImportConfig = upload.config;
        _catalogImportSources = sources;
        _catalogSourceArtifacts = artifacts;
        _syncCatalogImportConfigDraft(upload.config);
        _selectedCatalogImportFile = null;
        _loadingMoreCatalogSourceArtifacts = false;
        _uploadingCatalogImportSource = false;
      });
      final message = upload.config.isReady
          ? 'GTFS archive uploaded and activated.'
          : 'GTFS archive uploaded, but the extracted source still needs verification.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _uploadingCatalogImportSource = false;
      });
      final isArabic = L10n.of(context).isArabic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _coachCatalogImportActionableErrorDetail(
              error.detail,
              isArabic: isArabic,
              action: _CoachCatalogImportMutationAction.uploadSource,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _uploadingCatalogImportSource = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _loadMorePayoutRuns() async {
    final currentRuns = _payoutRuns;
    final cursor = currentRuns?.nextCursor?.trim();
    if (currentRuns == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMorePayoutRuns = true;
    });
    try {
      final response = await _api.operatorPayoutRuns(limit: 8, cursor: cursor);
      if (!mounted) {
        return;
      }
      final mergedRuns = <CoachOperatorPayoutRun>[...currentRuns.runs];
      final seenRunIds = mergedRuns.map((entry) => entry.payoutRunId).toSet();
      for (final run in response.runs) {
        if (seenRunIds.add(run.payoutRunId)) {
          mergedRuns.add(run);
        }
      }
      setState(() {
        _payoutRuns = CoachOperatorPayoutRunsResponse(
          generatedAtIso: response.generatedAtIso,
          summary: response.summary,
          runs: mergedRuns,
          nextCursor: response.nextCursor,
        );
        _loadingMorePayoutRuns = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutRuns = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutRuns = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _loadMoreSettlementStatements() async {
    final currentStatements = _settlementStatements;
    final cursor = currentStatements?.nextCursor?.trim();
    if (currentStatements == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMoreSettlementStatements = true;
    });
    try {
      final response =
          await _api.operatorSettlementStatements(limit: 6, cursor: cursor);
      if (!mounted) {
        return;
      }
      final mergedStatements = <CoachOperatorSettlementStatement>[
        ...currentStatements.statements,
      ];
      final seenStatementIds =
          mergedStatements.map((entry) => entry.statementId).toSet();
      for (final statement in response.statements) {
        if (seenStatementIds.add(statement.statementId)) {
          mergedStatements.add(statement);
        }
      }
      setState(() {
        _settlementStatements = CoachOperatorSettlementStatementsResponse(
          generatedAtIso: response.generatedAtIso,
          statements: mergedStatements,
          nextCursor: response.nextCursor,
        );
        _loadingMoreSettlementStatements = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMoreSettlementStatements = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMoreSettlementStatements = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _loadMorePayoutReconciliation() async {
    final currentReconciliation = _payoutReconciliation;
    final cursor = currentReconciliation?.nextCursor?.trim();
    if (currentReconciliation == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMorePayoutReconciliation = true;
    });
    try {
      final response =
          await _api.operatorPayoutReconciliation(limit: 8, cursor: cursor);
      if (!mounted) {
        return;
      }
      final mergedRuns = <CoachOperatorPayoutReconciliationRun>[
        ...currentReconciliation.runs,
      ];
      final seenRunIds = mergedRuns.map((entry) => entry.payoutRunId).toSet();
      for (final run in response.runs) {
        if (seenRunIds.add(run.payoutRunId)) {
          mergedRuns.add(run);
        }
      }
      setState(() {
        _payoutReconciliation = CoachOperatorPayoutReconciliationResponse(
          generatedAtIso: response.generatedAtIso,
          summary: response.summary,
          runs: mergedRuns,
          nextCursor: response.nextCursor,
        );
        _loadingMorePayoutReconciliation = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutReconciliation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutReconciliation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _loadMorePayoutImportBatches() async {
    final currentBatches = _payoutImportBatches;
    final cursor = _payoutImportBatchesCursor;
    if (currentBatches == null || cursor == null || cursor.isEmpty) {
      return;
    }
    setState(() {
      _loadingMorePayoutImportBatches = true;
    });
    try {
      final response = await _api.operatorPayoutImportBatches(
        limit: 8,
        cursor: cursor,
      );
      if (!mounted) {
        return;
      }
      final mergedBatches = <CoachOperatorPayoutImportBatch>[
        ...currentBatches.batches,
      ];
      final seenBatchIds = mergedBatches.map((entry) => entry.batchId).toSet();
      for (final batch in response.batches) {
        if (seenBatchIds.add(batch.batchId)) {
          mergedBatches.add(batch);
        }
      }
      setState(() {
        _payoutImportBatches = CoachOperatorPayoutImportBatchesResponse(
          generatedAtIso: response.generatedAtIso,
          summary: response.summary,
          batches: mergedBatches,
          nextCursor: response.nextCursor,
        );
        _loadingMorePayoutImportBatches = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutImportBatches = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMorePayoutImportBatches = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _applyPayoutImportPreviewHistoryFilters() async {
    setState(() {
      _appliedPayoutImportPreviewStatusFilter =
          _draftPayoutImportPreviewStatusFilter;
      _appliedPayoutImportPreviewFromCreatedAtIso =
          _draftPayoutImportPreviewFromCreatedAtIso;
      _appliedPayoutImportPreviewToCreatedAtIso =
          _draftPayoutImportPreviewToCreatedAtIso;
    });
    try {
      final preferences = CoachPayoutImportPreviewHistoryFilterPreferences(
        status: _appliedPayoutImportPreviewStatusFilter ?? 'all',
        fromCreatedAtIso: _appliedPayoutImportPreviewFromCreatedAtIso,
        toCreatedAtIso: _appliedPayoutImportPreviewToCreatedAtIso,
        operatorId: _selectedPayoutImportPreviewOperatorIdFilter,
      );
      if (preferences.hasActiveFilters) {
        await _savePersistedPayoutImportPreviewHistoryFilterPreferences(
          preferences,
        );
      } else {
        await _clearPersistedPayoutImportPreviewHistoryFilterPreferences();
      }
    } catch (_) {}
    await _loadPayoutImportPreviewHistory();
  }

  void _clearPayoutImportPreviewHistoryFilters() {
    unawaited(_clearPayoutImportPreviewHistoryFiltersPersisted());
  }

  Future<void> _clearPayoutImportPreviewHistoryFiltersPersisted() async {
    try {
      await _clearPersistedPayoutImportPreviewHistoryFilterPreferences();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPayoutImportPreviewStatusFilter = 'all';
      _selectedPayoutImportPreviewOperatorIdFilter = 'all';
      _payoutImportPreviewFromCreatedAtController.clear();
      _payoutImportPreviewToCreatedAtController.clear();
      _appliedPayoutImportPreviewStatusFilter = null;
      _appliedPayoutImportPreviewFromCreatedAtIso = null;
      _appliedPayoutImportPreviewToCreatedAtIso = null;
      _payoutImportPreviewHistory = _payoutImportPreviews;
      _payoutImportPreviewHistoryErrorMessage = null;
      _loadingPayoutImportPreviewHistory = false;
    });
  }

  Future<void> _persistPayoutImportPreviewHistoryOperatorFilterSelection(
    String operatorId,
  ) async {
    final normalizedOperatorId =
        _normalizePayoutImportOperatorIdFilterValue(operatorId);
    final preferences = CoachPayoutImportPreviewHistoryFilterPreferences(
      status: _appliedPayoutImportPreviewStatusFilter ?? 'all',
      fromCreatedAtIso: _appliedPayoutImportPreviewFromCreatedAtIso,
      toCreatedAtIso: _appliedPayoutImportPreviewToCreatedAtIso,
      operatorId: normalizedOperatorId,
    );
    try {
      if (preferences.hasActiveFilters) {
        await _savePersistedPayoutImportPreviewHistoryFilterPreferences(
          preferences,
        );
      } else {
        await _clearPersistedPayoutImportPreviewHistoryFilterPreferences();
      }
    } catch (_) {}
  }

  Future<void> _persistPayoutImportBatchOperatorFilterSelection(
    String operatorId,
  ) async {
    final normalizedOperatorId =
        _normalizePayoutImportOperatorIdFilterValue(operatorId);
    final preferences = CoachPayoutImportBatchFilterPreferences(
      operatorId: normalizedOperatorId,
    );
    try {
      if (preferences.hasActiveFilters) {
        await _savePersistedPayoutImportBatchFilterPreferences(preferences);
      } else {
        await _clearPersistedPayoutImportBatchFilterPreferences();
      }
    } catch (_) {}
  }

  String _resolvePayoutExportUrl(String downloadPath) {
    return _api.resolvePayoutExportUri(downloadPath)?.toString() ??
        downloadPath;
  }

  String _resolvePayoutImportReportUrl(String downloadPath) {
    return _api.resolvePayoutImportReportUri(downloadPath)?.toString() ??
        downloadPath;
  }

  int get _refundPendingCount => _refundRequests
      .where((entry) => entry.queueStatus == CoachOpsQueueStatus.pendingReview)
      .length;

  int get _changePendingCount => _changeRequests
      .where((entry) => entry.queueStatus == CoachOpsQueueStatus.pendingReview)
      .length;

  int get _settlementNetPayableMinorUnits =>
      (_settlementStatements?.statements ??
              const <CoachOperatorSettlementStatement>[])
          .fold<int>(
        0,
        (sum, statement) => sum + statement.totals.netPayableMinorUnits,
      );

  int get _queuedPayoutRunCount =>
      _payoutRuns?.summary.queuedRuns ??
      (_payoutRuns?.runs.where((run) => run.isQueued).length ?? 0);

  int get _payoutAttentionCount =>
      _payoutReconciliation?.summary.attentionRuns ?? 0;

  int get _degradedFeedCount => _operatorFeedHealth?.summary.degradedFeeds ?? 0;

  int get _staleFeedCount => _operatorFeedHealth?.summary.staleFeeds ?? 0;

  int get _catalogImportRunCount => _catalogImportRuns?.summary.totalRuns ?? 0;

  int get _catalogSourceArtifactCount =>
      _catalogSourceArtifacts?.summary.totalArtifacts ?? 0;

  bool get _catalogImportConfigReady => _catalogImportConfig?.isReady ?? false;

  bool get _catalogImportConfigRequiresScopedSource =>
      (_catalogImportConfig?.configOrigin ?? '').trim() == 'operator_scope';

  bool get _hasCatalogImportFeedLocatorDraft =>
      _catalogImportFeedLocatorController.text.trim().isNotEmpty;

  bool get _hasCatalogImportScopedSourceDraft =>
      (_selectedCatalogImportSourceLocator ?? '').trim().isNotEmpty;

  String? get _selectedCatalogImportSourceLocator {
    final locator = _catalogImportFeedLocatorController.text.trim();
    if (locator.isEmpty) {
      return null;
    }
    final sources = _catalogImportSources?.sources ?? const [];
    if (!sources.any((entry) => entry.feedLocator == locator)) {
      return null;
    }
    return locator;
  }

  CoachOperatorCatalogImportSourceOption? get _selectedCatalogImportSource {
    final locator = _selectedCatalogImportSourceLocator;
    if (locator == null) {
      return null;
    }
    for (final source in _catalogImportSources?.sources ?? const []) {
      if (source.feedLocator == locator) {
        return source;
      }
    }
    return null;
  }

  String? get _catalogSourceArtifactsCursor {
    final artifacts = _catalogSourceArtifacts;
    if (artifacts == null) {
      return null;
    }
    final nextCursor = artifacts.nextCursor?.trim();
    if (nextCursor != null && nextCursor.isNotEmpty) {
      return nextCursor;
    }
    if (artifacts.summary.totalArtifacts <= artifacts.artifacts.length ||
        artifacts.artifacts.isEmpty) {
      return null;
    }
    final lastArtifact = artifacts.artifacts.last;
    return '${lastArtifact.createdAtIso}|${lastArtifact.artifactId}';
  }

  String? get _catalogImportRunsCursor {
    final runs = _catalogImportRuns;
    if (runs == null) {
      return null;
    }
    final nextCursor = runs.nextCursor?.trim();
    if (nextCursor != null && nextCursor.isNotEmpty) {
      return nextCursor;
    }
    if (runs.summary.totalRuns <= runs.importRuns.length ||
        runs.importRuns.isEmpty) {
      return null;
    }
    final lastRun = runs.importRuns.last;
    return '${lastRun.startedAtIso}|${lastRun.importRunId}';
  }

  List<String> get _catalogImportRunSeverityFilterOptions {
    final values = _catalogImportRunIssueSeverityOptions(
      _catalogImportRuns?.importRuns.expand((entry) => entry.issues) ??
          const <CoachOperatorCatalogImportRunIssue>[],
    ).toList(growable: true);
    final selected = _selectedCatalogImportRunIssueSeverityFilter.trim();
    if (selected.isNotEmpty &&
        selected != 'all' &&
        !values.any((value) => value == selected)) {
      values.insert(0, selected);
    }
    return <String>['all', ...values];
  }

  List<String> get _catalogImportRunStageFilterOptions {
    final values = _catalogImportRunIssueStageOptions(
      _catalogImportRuns?.importRuns.expand((entry) => entry.issues) ??
          const <CoachOperatorCatalogImportRunIssue>[],
    ).toList(growable: true);
    final selected = _selectedCatalogImportRunIssueStageFilter.trim();
    if (selected.isNotEmpty &&
        selected != 'all' &&
        !values.any((value) => value == selected)) {
      values.insert(0, selected);
    }
    return <String>['all', ...values];
  }

  bool get _catalogImportRunIssuePresetErrorsAvailable =>
      _catalogImportRunSeverityFilterOptions.any(
        (value) => value.trim().toLowerCase() == 'error',
      );

  bool get _catalogImportRunIssuePresetWarningsAvailable =>
      _catalogImportRunSeverityFilterOptions.any(
        (value) => value.trim().toLowerCase() == 'warning',
      );

  bool get _catalogImportRunIssuePresetLoadFeedAvailable =>
      _catalogImportRunStageFilterOptions.any(
        (value) => value.trim().toLowerCase() == 'load_feed',
      );

  String? get _catalogImportRunStatusFilter {
    final normalized = _selectedCatalogImportRunStatusFilter.trim();
    if (normalized.isEmpty || normalized == 'all') {
      return null;
    }
    return normalized;
  }

  String? get _catalogImportRunReplayScopeFilter {
    final normalized = _selectedCatalogImportRunReplayScopeFilter.trim();
    if (normalized.isEmpty || normalized == 'all') {
      return null;
    }
    return normalized;
  }

  String? get _catalogImportRunIssueSeverityFilter {
    final normalized = _selectedCatalogImportRunIssueSeverityFilter.trim();
    if (normalized.isEmpty || normalized == 'all') {
      return null;
    }
    return normalized;
  }

  String? get _catalogImportRunIssueStageFilter {
    final normalized = _selectedCatalogImportRunIssueStageFilter.trim();
    if (normalized.isEmpty || normalized == 'all') {
      return null;
    }
    return normalized;
  }

  bool get _hasActiveCatalogImportRunFilters =>
      _catalogImportRunStatusFilter != null ||
      _catalogImportRunReplayScopeFilter != null ||
      _catalogImportRunIssueSeverityFilter != null ||
      _catalogImportRunIssueStageFilter != null;

  bool get _hasActiveCatalogImportRunIssueFilters =>
      _catalogImportRunIssueSeverityFilter != null ||
      _catalogImportRunIssueStageFilter != null;

  int get _payoutImportCount => _payoutImports?.summary.totalImports ?? 0;

  int get _activePayoutImportPreviewCount =>
      _payoutImportPreviews?.summary.activePreviews ?? 0;

  int get _payoutImportBatchCount =>
      _payoutImportBatches?.summary.totalBatches ?? 0;

  String? get _payoutImportBatchesCursor {
    final batches = _payoutImportBatches;
    if (batches == null) {
      return null;
    }
    final nextCursor = batches.nextCursor?.trim();
    if (nextCursor != null && nextCursor.isNotEmpty) {
      return nextCursor;
    }
    if (batches.summary.totalBatches <= batches.batches.length ||
        batches.batches.isEmpty) {
      return null;
    }
    final lastBatch = batches.batches.last;
    return '${lastBatch.createdAtIso}|${lastBatch.batchId}';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final rankedCatalogImportRunSavedViews = _prioritizeSavedViews(
      _catalogImportRunSavedViews,
      isCurrent: _catalogImportRunSavedViewIsCurrent,
      isDefault: (view) => view.isDefault,
      viewIdOf: (view) => view.viewId,
      pinnedViewIds: _catalogImportRunSavedViewPinnedIds,
      usedAtById: _catalogImportRunSavedViewUsedAtById,
    );
    final recentCatalogImportRunSavedViews = _recentlyUsedSavedViews(
      rankedCatalogImportRunSavedViews,
      viewIdOf: (view) => view.viewId,
      usedAtById: _catalogImportRunSavedViewUsedAtById,
    );
    final visiblePayoutImportPreviewHistory =
        _visiblePayoutImportPreviewHistory;
    final visiblePayoutImportBatches = _visiblePayoutImportBatches;
    final visiblePayoutImportPreviewSavedViews =
        _visiblePayoutImportPreviewSavedViews;
    final recentPayoutImportPreviewSavedViews = _recentlyUsedSavedViews(
      visiblePayoutImportPreviewSavedViews,
      viewIdOf: (view) => view.viewId,
      usedAtById: _payoutImportPreviewSavedViewUsedAtById,
    );
    final visiblePayoutImportBatchSavedViews =
        _visiblePayoutImportBatchSavedViews;
    final recentPayoutImportBatchSavedViews = _recentlyUsedSavedViews(
      visiblePayoutImportBatchSavedViews,
      viewIdOf: (view) => view.viewId,
      usedAtById: _payoutImportBatchSavedViewUsedAtById,
    );
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: Text(isArabic ? 'عمليات الحافلات' : 'Coach Ops')),
        body: const ShamellSkeletonList(itemCount: 6),
      );
    }
    if (!_accessAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(isArabic ? 'عمليات الحافلات' : 'Coach Ops')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isArabic
                  ? 'هذا الحساب غير مخوّل لإدارة طلبات الحافلات.'
                  : 'This account is not allowed to manage coach requests.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final scopeLabel = _hasRestrictedCoachOperatorScope
        ? _coachFormatCatalogOperatorScope(_privilegeSnapshot.operatorIds)
        : 'all assigned operators';
    final financeModeLabel = _financeMutationsAllowed
        ? 'Settlement and payout actions enabled'
        : 'Read-only finance and payouts';
    final catalogModeLabel = _catalogImportMutationsAllowed
        ? (_catalogImportConfigReady
            ? 'Catalog source is ready for operator updates'
            : 'Catalog source still needs setup')
        : 'Catalog configuration is visible in read-only mode';
    final workspaces = <_CoachOpsWorkspaceDescriptor>[
      _CoachOpsWorkspaceDescriptor(
        id: _workspaceSupport,
        label: isArabic ? 'مكتب الدعم' : 'Support desk',
        detail: isArabic
            ? 'طلبات الاسترداد والتغيير التي تحتاج قرارًا من فريق التشغيل.'
            : 'Refund and change requests that still need an operator decision.',
        icon: Icons.support_agent_outlined,
        color: const Color(0xFF1D4ED8),
        signalCount: _refundPendingCount + _changePendingCount,
      ),
      _CoachOpsWorkspaceDescriptor(
        id: _workspaceSettlements,
        label: isArabic ? 'التسويات' : 'Settlements',
        detail: isArabic
            ? 'المطابقة، تشغيلات الدفع، وكشوفات التسوية الخاصة بالمشغل.'
            : 'Reconciliation, payout runs, and settlement statements for the operator.',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF0F766E),
        signalCount: _queuedPayoutRunCount + _payoutAttentionCount,
      ),
      _CoachOpsWorkspaceDescriptor(
        id: _workspacePayoutOps,
        label: isArabic ? 'عمليات الدفع' : 'Payout ops',
        detail: isArabic
            ? 'سجل الاستيراد، المعاينات، والدفعات المجمعة قبل إرسالها.'
            : 'Import history, preview confirmations, and import batches before release.',
        icon: Icons.receipt_long_outlined,
        color: const Color(0xFFB45309),
        signalCount: _payoutImportCount +
            _activePayoutImportPreviewCount +
            _payoutImportBatchCount,
      ),
      _CoachOpsWorkspaceDescriptor(
        id: _workspaceSalesFeeds,
        label: isArabic ? 'المبيعات والتغذيات' : 'Sales & feeds',
        detail: isArabic
            ? 'صحة التغذيات واستيراد الكتالوج الذي يغذي المبيعات وتوفر الرحلات.'
            : 'Feed health and catalog imports that drive sales and trip availability.',
        icon: Icons.hub_outlined,
        color: const Color(0xFF7C3AED),
        signalCount:
            _catalogImportRunCount + _degradedFeedCount + _staleFeedCount,
      ),
    ];
    final supportWorkspace = workspaces.firstWhere(
      (workspace) => workspace.id == _workspaceSupport,
    );
    final settlementsWorkspace = workspaces.firstWhere(
      (workspace) => workspace.id == _workspaceSettlements,
    );
    final payoutOpsWorkspace = workspaces.firstWhere(
      (workspace) => workspace.id == _workspacePayoutOps,
    );
    final salesFeedsWorkspace = workspaces.firstWhere(
      (workspace) => workspace.id == _workspaceSalesFeeds,
    );
    final visibleWorkspaceIds = _visibleWorkspaceIds(workspaces).toSet();
    final selectedWorkspaceDescriptor =
        workspaces.cast<_CoachOpsWorkspaceDescriptor?>().firstWhere(
              (workspace) => workspace?.id == _selectedWorkspace,
              orElse: () => null,
            );
    final portalSections = <_CoachOpsPortalSectionDescriptor>[
      _CoachOpsPortalSectionDescriptor(
        id: _portalSectionToday,
        label: 'Today',
        detail:
            'Cross-desk start page for the current shift with the signals that need action now.',
        icon: Icons.today_outlined,
        color: const Color(0xFF165B45),
        signalCount: workspaces.fold<int>(
          0,
          (sum, workspace) => sum + workspace.signalCount,
        ),
      ),
      _CoachOpsPortalSectionDescriptor(
        id: _portalSectionTrips,
        label: 'Trips',
        detail:
            'Availability risk from degraded or stale operator feeds that can block live trip coverage.',
        icon: Icons.alt_route_outlined,
        color: const Color(0xFF7C3AED),
        signalCount: _degradedFeedCount + _staleFeedCount,
      ),
      _CoachOpsPortalSectionDescriptor(
        id: _portalSectionSales,
        label: 'Sales',
        detail:
            'Catalog imports and source readiness that shape sellable inventory for coach operators.',
        icon: Icons.sell_outlined,
        color: const Color(0xFF2563EB),
        signalCount: _catalogImportRunCount + _catalogSourceArtifactCount,
      ),
      _CoachOpsPortalSectionDescriptor(
        id: _portalSectionSettlements,
        label: 'Settlements',
        detail:
            'Statements, payout runs, reconciliation, and payout intake for finance operations.',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF0F766E),
        signalCount: _queuedPayoutRunCount +
            _payoutAttentionCount +
            _payoutImportCount +
            _activePayoutImportPreviewCount +
            _payoutImportBatchCount,
      ),
      _CoachOpsPortalSectionDescriptor(
        id: _portalSectionSupport,
        label: 'Support',
        detail:
            'Refund and change queues waiting on an operator decision before the customer can move on.',
        icon: Icons.support_agent_outlined,
        color: const Color(0xFF1D4ED8),
        signalCount: _refundPendingCount + _changePendingCount,
      ),
    ];
    final selectedPortalSectionDescriptor =
        portalSections.cast<_CoachOpsPortalSectionDescriptor?>().firstWhere(
              (section) => section?.id == _selectedPortalSection,
              orElse: () => null,
            );
    final tripsPortalSection = portalSections.firstWhere(
      (section) => section.id == _portalSectionTrips,
    );
    final salesPortalSection = portalSections.firstWhere(
      (section) => section.id == _portalSectionSales,
    );
    final settlementsPortalSection = portalSections.firstWhere(
      (section) => section.id == _portalSectionSettlements,
    );
    final supportPortalSection = portalSections.firstWhere(
      (section) => section.id == _portalSectionSupport,
    );
    final portalJumpChips = <_CoachOpsPortalJumpDescriptor>[
      _CoachOpsPortalJumpDescriptor(
        id: 'support_queue',
        portalSectionId: _portalSectionSupport,
        icon: Icons.support_agent_outlined,
        label: 'Support queue',
        workspaceId: _workspaceSupport,
        targetKey: _refundSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'support_changes',
        portalSectionId: _portalSectionSupport,
        icon: Icons.swap_horiz_outlined,
        label: 'Changes',
        workspaceId: _workspaceSupport,
        targetKey: _changeSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'settlements',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackExecution,
        icon: Icons.receipt_long_outlined,
        label: 'Settlements',
        workspaceId: _workspaceSettlements,
        targetKey: _settlementSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'payouts',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackExecution,
        icon: Icons.account_balance_wallet_outlined,
        label: 'Payouts',
        workspaceId: _workspaceSettlements,
        targetKey: _payoutRunsSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'reconciliation',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackAudit,
        icon: Icons.balance_outlined,
        label: 'Reconciliation',
        workspaceId: _workspaceSettlements,
        targetKey: _payoutReconciliationSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'payout_imports',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackAudit,
        icon: Icons.file_download_outlined,
        label: 'Payout imports',
        workspaceId: _workspacePayoutOps,
        targetKey: _payoutImportsSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'import_batches',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackExecution,
        icon: Icons.dataset_outlined,
        label: 'Import batches',
        workspaceId: _workspacePayoutOps,
        targetKey: _payoutImportBatchesSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'feed_health',
        portalSectionId: _portalSectionTrips,
        icon: Icons.hub_outlined,
        label: 'Feed health',
        workspaceId: _workspaceSalesFeeds,
        targetKey: _feedHealthSectionKey,
      ),
      _CoachOpsPortalJumpDescriptor(
        id: 'sales_imports',
        portalSectionId: _portalSectionSales,
        icon: Icons.inventory_2_outlined,
        label: 'Sales & imports',
        workspaceId: _workspaceSalesFeeds,
        targetKey: _catalogImportSectionKey,
      ),
    ];
    final visiblePortalJumpChips = portalJumpChips
        .where(
          (jumpChip) =>
              _portalSectionMatches(jumpChip.portalSectionId) &&
              visibleWorkspaceIds.contains(jumpChip.workspaceId) &&
              ((_selectedPortalSection != _portalSectionToday &&
                      _selectedPortalSection != _portalSectionSettlements) ||
                  jumpChip.portalSectionId != _portalSectionSettlements ||
                  jumpChip.settlementsTrackId == null ||
                  jumpChip.settlementsTrackId == _selectedSettlementsTrack),
        )
        .toList(growable: false);
    final todayCards = <_CoachOpsPortalSummaryCardDescriptor>[
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'support_refunds',
        portalSectionId: _portalSectionSupport,
        workspaceId: _workspaceSupport,
        title: isArabic ? 'طلبات الاسترداد' : 'Refund queue',
        value: '${_refundRequests.length}',
        subtitle:
            '${isArabic ? 'بانتظار المراجعة' : 'Pending review'}: $_refundPendingCount',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'support_changes',
        portalSectionId: _portalSectionSupport,
        workspaceId: _workspaceSupport,
        title: isArabic ? 'طلبات التغيير' : 'Change queue',
        value: '${_changeRequests.length}',
        subtitle:
            '${isArabic ? 'بانتظار المراجعة' : 'Pending review'}: $_changePendingCount',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'settlements_net',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackExecution,
        workspaceId: _workspaceSettlements,
        title: isArabic ? 'صافي التسوية' : 'Net settlement',
        value: _settlementStatements == null
            ? '-'
            : _coachOpsMoney(
                _settlementStatements!.statements.isEmpty
                    ? 'SYP'
                    : _settlementStatements!.statements.first.currency,
                _settlementNetPayableMinorUnits,
              ),
        subtitle: _settlementStatements == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'البيانات' : 'Statements'}: ${_settlementStatements!.statements.length}',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'settlements_payout_runs',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackExecution,
        workspaceId: _workspaceSettlements,
        title: isArabic ? 'دفعات قيد التنفيذ' : 'Payout runs',
        value: '$_queuedPayoutRunCount',
        subtitle: _payoutReconciliation == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'يتطلب انتباه' : 'Needs attention'}: $_payoutAttentionCount',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'settlements_reconciliation',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackAudit,
        workspaceId: _workspaceSettlements,
        title: isArabic ? 'مطابقة الدفعات' : 'Payout reconciliation',
        value: _payoutReconciliation == null
            ? '-'
            : '${_payoutReconciliation!.summary.balancedRuns}',
        subtitle: _payoutReconciliation == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'مدفوع' : 'Paid'}: ${_coachOpsMoney(_payoutReconciliation!.summary.currency, _payoutReconciliation!.summary.paidNetPayableMinorUnits)}',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'sales_feeds_feed_health',
        portalSectionId: _portalSectionTrips,
        workspaceId: _workspaceSalesFeeds,
        title: isArabic ? 'صحة التغذيات' : 'Feed health',
        value: _operatorFeedHealth == null
            ? '-'
            : '${_operatorFeedHealth!.summary.healthyOperators}',
        subtitle: _operatorFeedHealth == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'متدهور' : 'Degraded'}: $_degradedFeedCount • '
                '${isArabic ? 'قديم' : 'Stale'}: $_staleFeedCount',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'sales_feeds_catalog_imports',
        portalSectionId: _portalSectionSales,
        workspaceId: _workspaceSalesFeeds,
        title: isArabic ? 'استيراد الكتالوج' : 'Catalog imports',
        value: '$_catalogImportRunCount',
        subtitle: _catalogImportRuns == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'فشل' : 'Failed'}: ${_catalogImportRuns!.summary.failedRuns} • '
                '${isArabic ? 'الأرشيفات' : 'Artifacts'}: $_catalogSourceArtifactCount',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'payout_ops_imports',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackAudit,
        workspaceId: _workspacePayoutOps,
        title: isArabic ? 'استيراد الدفعات' : 'Payout imports',
        value: '$_payoutImportCount',
        subtitle: _payoutImports == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'فشل' : 'Failed'}: ${_payoutImports!.summary.failedImports}',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'payout_ops_previews',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackAudit,
        workspaceId: _workspacePayoutOps,
        title: isArabic ? 'معاينات الدفع' : 'Preview confirmations',
        value: '$_activePayoutImportPreviewCount',
        subtitle: _payoutImportPreviews == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'منتهي' : 'Expired'}: ${_payoutImportPreviews!.summary.expiredPreviews} • '
                '${isArabic ? 'مبطل' : 'Invalidated'}: ${_payoutImportPreviews!.summary.invalidatedPreviews}',
      ),
      _CoachOpsPortalSummaryCardDescriptor(
        id: 'payout_ops_batches',
        portalSectionId: _portalSectionSettlements,
        settlementsTrackId: _settlementsTrackExecution,
        workspaceId: _workspacePayoutOps,
        title: isArabic ? 'دفعات مجمعة' : 'Import batches',
        value: '$_payoutImportBatchCount',
        subtitle: _payoutImportBatches == null
            ? (isArabic ? 'غير متاح' : 'Unavailable')
            : '${isArabic ? 'صفوف فاشلة' : 'Failed rows'}: ${_payoutImportBatches!.summary.failedRows}',
      ),
    ];
    final visibleTodayCards = todayCards
        .where(
          (card) =>
              _portalSectionMatches(card.portalSectionId) &&
              visibleWorkspaceIds.contains(card.workspaceId) &&
              ((_selectedPortalSection != _portalSectionToday &&
                      _selectedPortalSection != _portalSectionSettlements) ||
                  card.portalSectionId != _portalSectionSettlements ||
                  card.settlementsTrackId == null ||
                  card.settlementsTrackId == _selectedSettlementsTrack),
        )
        .toList(growable: false);
    final portalSummaryTitle = _selectedPortalSection == _portalSectionToday ||
            selectedPortalSectionDescriptor == null
        ? 'Today'
        : selectedPortalSectionDescriptor.label;
    final settlementsTrackSummaryCopy = _selectedSettlementsTrack ==
            _settlementsTrackAudit
        ? 'Audit view keeps reconciliation, payout intake, and preview review in focus before finance execution.'
        : 'Execution view keeps settlement statements, payout runs, and import batches in focus for finance operations.';
    final todaySummaryCopy = _selectedPortalSection == _portalSectionToday
        ? (_selectedWorkspace == _workspaceAll ||
                selectedWorkspaceDescriptor == null
            ? 'Start with what needs action now, then drill into the detailed operator queues below.'
            : 'Showing live signals for ${selectedWorkspaceDescriptor.label}. Drill into the desk below for the full operator queue.')
        : (_selectedPortalSection == _portalSectionSettlements
            ? (_selectedWorkspace == _workspaceAll ||
                    selectedWorkspaceDescriptor == null
                ? settlementsTrackSummaryCopy
                : '$settlementsTrackSummaryCopy Desk focus is ${selectedWorkspaceDescriptor.label}.')
            : (_selectedWorkspace == _workspaceAll ||
                    selectedWorkspaceDescriptor == null ||
                    selectedPortalSectionDescriptor == null
                ? (selectedPortalSectionDescriptor?.detail ??
                    'Start with what needs action now, then drill into the detailed operator queues below.')
                : '${selectedPortalSectionDescriptor.detail} Desk focus is ${selectedWorkspaceDescriptor.label}.'));
    final showSettlementsTracks =
        _selectedPortalSection == _portalSectionToday ||
            _selectedPortalSection == _portalSectionSettlements;
    final showSettlementsAuditSection =
        _selectedPortalSection != _portalSectionSettlements ||
            _selectedSettlementsTrack == _settlementsTrackAudit;
    final showSettlementsExecutionSection =
        _selectedPortalSection != _portalSectionSettlements ||
            _selectedSettlementsTrack == _settlementsTrackExecution;

    Widget partnerBadge({
      required IconData icon,
      required String label,
      Color color = const Color(0xFF165B45),
    }) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: .18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget jumpChip({
      required String id,
      required IconData icon,
      required String label,
      required String workspaceId,
      required GlobalKey targetKey,
    }) {
      return OutlinedButton.icon(
        key: ValueKey('coachOpsJump_$id'),
        onPressed: () => _focusWorkspace(workspaceId, targetKey),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    Widget settlementsTrackChip({
      required String id,
      required IconData icon,
      required String label,
      required int signalCount,
      required String subtitle,
      required GlobalKey targetKey,
    }) {
      final selected = _selectedSettlementsTrack == id;
      const selectedColor = Color(0xFF0F766E);
      const defaultColor = Color(0xFF526176);
      final color = selected ? selectedColor : defaultColor;
      return ChoiceChip(
        key: ValueKey('coachOpsSettlementsTrackFocus_$id'),
        avatar: Icon(icon, size: 16, color: color),
        label: Text('$label ($signalCount)'),
        selected: selected,
        selectedColor: selectedColor.withValues(alpha: .14),
        side: BorderSide(
          color: selected
              ? selectedColor.withValues(alpha: .28)
              : const Color(0xFFD6E7DF),
        ),
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
        tooltip: subtitle,
        onSelected: (_) => unawaited(
          _focusSettlementsTrack(id, targetKey),
        ),
      );
    }

    List<Widget> portalSection({
      required _CoachOpsPortalSectionDescriptor section,
      String? segmentId,
      String? subtitle,
      Iterable<String> alsoVisibleFor = const <String>[],
      GlobalKey? sectionKey,
      required List<Widget> children,
    }) {
      final visibleSectionIds = <String>{section.id, ...alsoVisibleFor};
      if ((_selectedPortalSection != _portalSectionToday &&
              !visibleSectionIds.contains(_selectedPortalSection)) ||
          children.isEmpty) {
        return const <Widget>[];
      }
      final keySuffix =
          segmentId == null ? section.id : '${section.id}_$segmentId';
      return <Widget>[
        KeyedSubtree(
          key: sectionKey,
          child: _CoachOpsPortalSectionShell(
            key: ValueKey('coachOpsPortalSection_$keySuffix'),
            bodyKey: ValueKey('coachOpsPortalSectionBody_$keySuffix'),
            icon: section.icon,
            title: section.label,
            subtitle: subtitle ?? section.detail,
            accentColor: section.color,
            signalCount: section.signalCount,
            children: children,
          ),
        ),
      ];
    }

    List<Widget> workspaceDesk({
      required _CoachOpsWorkspaceDescriptor workspace,
      String? segmentId,
      bool showHeader = true,
      required List<Widget> children,
    }) {
      if (_selectedWorkspace != _workspaceAll &&
          _selectedWorkspace != workspace.id) {
        return const <Widget>[];
      }
      final collapsed = _collapsedWorkspaces.contains(workspace.id);
      if (!showHeader) {
        if (collapsed) {
          return const <Widget>[];
        }
        return <Widget>[
          KeyedSubtree(
            key: ValueKey(
              'coachOpsWorkspaceSegment_${workspace.id}_${segmentId ?? 'body'}',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ];
      }
      return <Widget>[
        Container(
          key: ValueKey('coachOpsWorkspace_${workspace.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              workspace.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: ValueKey(
                              'coachOpsWorkspaceToggle_${workspace.id}',
                            ),
                            onPressed: () =>
                                _toggleWorkspaceCollapsed(workspace.id),
                            icon: Icon(
                              collapsed
                                  ? Icons.unfold_more_outlined
                                  : Icons.unfold_less_outlined,
                            ),
                            label: Text(
                              isArabic
                                  ? (collapsed ? 'توسيع' : 'طي')
                                  : (collapsed ? 'Expand' : 'Collapse'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        workspace.detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF526176),
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: workspace.color.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: workspace.color.withValues(alpha: .18),
                              ),
                            ),
                            child: Text(
                              isArabic
                                  ? 'إشارات مفتوحة ${workspace.signalCount}'
                                  : 'Open signals ${workspace.signalCount}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: workspace.color,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (collapsed)
                Container(
                  key: ValueKey('coachOpsWorkspaceCollapsed_${workspace.id}'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    isArabic
                        ? 'هذا المكتب مطوي الآن. افتحه لمتابعة التفاصيل.'
                        : 'This desk is collapsed right now. Expand it to continue.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                KeyedSubtree(
                  key: ValueKey('coachOpsWorkspaceBody_${workspace.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
            ],
          ),
        ),
      ];
    }

    void openSimpleDesk(String workspaceId, GlobalKey targetKey) {
      unawaited(_focusWorkspace(workspaceId, targetKey));
    }

    Widget simpleOpsActionCard({
      required String id,
      required IconData icon,
      required String title,
      required String value,
      required String detail,
      required Color color,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 230,
        child: Material(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: .46),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey('coachOpsSimpleAction_$id'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 20),
                      const Spacer(),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .70),
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildSimpleOpsStartSection() {
      final supportSignals = _refundPendingCount + _changePendingCount;
      final settlementSignals = _queuedPayoutRunCount + _payoutAttentionCount;
      final payoutIntakeSignals = _payoutImportCount +
          _activePayoutImportPreviewCount +
          _payoutImportBatchCount;
      final feedSignals = _degradedFeedCount + _staleFeedCount;
      final salesSignals = _catalogImportRunCount + _catalogSourceArtifactCount;
      final totalSignals = supportSignals +
          settlementSignals +
          payoutIntakeSignals +
          feedSignals +
          salesSignals;

      late final IconData primaryIcon;
      late final String primaryLabel;
      late final String primaryDetail;
      late final VoidCallback primaryAction;
      if (supportSignals > 0) {
        primaryIcon = Icons.support_agent_outlined;
        primaryLabel = isArabic ? 'افتح الدعم' : 'Open support';
        primaryDetail = isArabic
            ? '$supportSignals طلبات استرداد أو تغيير تنتظر القرار.'
            : '$supportSignals refund or change requests need a decision.';
        primaryAction =
            () => openSimpleDesk(_workspaceSupport, _refundSectionKey);
      } else if (settlementSignals > 0) {
        primaryIcon = Icons.account_balance_wallet_outlined;
        primaryLabel = isArabic ? 'افتح الدفعات' : 'Open payouts';
        primaryDetail = isArabic
            ? '$settlementSignals دفعات أو تسويات تحتاج متابعة.'
            : '$settlementSignals payout or settlement items need follow-up.';
        primaryAction =
            () => openSimpleDesk(_workspaceSettlements, _payoutRunsSectionKey);
      } else if (payoutIntakeSignals > 0) {
        primaryIcon = Icons.receipt_long_outlined;
        primaryLabel = isArabic ? 'افتح استيراد الدفعات' : 'Open payout intake';
        primaryDetail = isArabic
            ? '$payoutIntakeSignals معاينات أو دفعات مستوردة تحتاج مراجعة.'
            : '$payoutIntakeSignals previews or import batches need review.';
        primaryAction =
            () => openSimpleDesk(_workspacePayoutOps, _payoutImportsSectionKey);
      } else if (feedSignals > 0) {
        primaryIcon = Icons.hub_outlined;
        primaryLabel = isArabic ? 'افتح التغذيات' : 'Open feed health';
        primaryDetail = isArabic
            ? '$feedSignals تغذيات مشغلين متدهورة أو قديمة.'
            : '$feedSignals operator feeds are degraded or stale.';
        primaryAction =
            () => openSimpleDesk(_workspaceSalesFeeds, _feedHealthSectionKey);
      } else {
        primaryIcon = Icons.check_circle_outline;
        primaryLabel = isArabic ? 'كل شيء هادئ' : 'All clear';
        primaryDetail = isArabic
            ? 'لا توجد إشارات عاجلة الآن. حدّث عند بداية الوردية.'
            : 'No urgent signals right now. Refresh at the start of the shift.';
        primaryAction = _loadQueues;
      }

      return Container(
        key: const ValueKey('coachOpsSimpleHome'),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'مكتب عمليات الشركاء' : 'Partner operations desk',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'النسخة البسيطة تعرض مهام الوردية فقط. المكاتب التفصيلية ما زالت أسفل الصفحة عند الحاجة.'
                  : 'The simple coach desk shows shift tasks first. Detailed desks stay below when you need them.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .70),
                  ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('coachOpsSimplePrimaryAction'),
              onPressed: _loadingQueues ? null : primaryAction,
              icon: Icon(primaryIcon),
              label: Text(primaryLabel),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '$primaryDetail ${isArabic ? 'الإشارات المفتوحة' : 'Open signals'}: $totalSignals',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .68),
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isArabic ? 'انتقل إلى' : 'Jump to',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                simpleOpsActionCard(
                  id: 'support',
                  icon: Icons.support_agent_outlined,
                  title: isArabic ? 'قائمة الدعم' : 'Support queue',
                  value: '$supportSignals',
                  detail: isArabic
                      ? 'استرداد وتغييرات العملاء'
                      : 'Refunds and customer changes',
                  color: const Color(0xFF1D4ED8),
                  onTap: () =>
                      openSimpleDesk(_workspaceSupport, _refundSectionKey),
                ),
                simpleOpsActionCard(
                  id: 'settlements',
                  icon: Icons.account_balance_wallet_outlined,
                  title: isArabic ? 'التسويات' : 'Settlements',
                  value: '$settlementSignals',
                  detail: isArabic
                      ? 'كشوفات ودفعات جاهزة'
                      : 'Statements and payout runs',
                  color: const Color(0xFF0F766E),
                  onTap: () => openSimpleDesk(
                    _workspaceSettlements,
                    _payoutRunsSectionKey,
                  ),
                ),
                simpleOpsActionCard(
                  id: 'payout_intake',
                  icon: Icons.receipt_long_outlined,
                  title: isArabic ? 'استيراد الدفعات' : 'Payout intake',
                  value: '$payoutIntakeSignals',
                  detail: isArabic
                      ? 'معاينات ودفعات مجمعة'
                      : 'Previews and import batches',
                  color: const Color(0xFFB45309),
                  onTap: () => openSimpleDesk(
                    _workspacePayoutOps,
                    _payoutImportsSectionKey,
                  ),
                ),
                simpleOpsActionCard(
                  id: 'feeds',
                  icon: Icons.hub_outlined,
                  title: isArabic ? 'التغذيات' : 'Feeds',
                  value: '$feedSignals',
                  detail: isArabic
                      ? 'صحة المشغلين والتوفر'
                      : 'Operator health and availability',
                  color: const Color(0xFF7C3AED),
                  onTap: () => openSimpleDesk(
                    _workspaceSalesFeeds,
                    _feedHealthSectionKey,
                  ),
                ),
                simpleOpsActionCard(
                  id: 'sales',
                  icon: Icons.inventory_2_outlined,
                  title: isArabic ? 'المبيعات والاستيراد' : 'Sales & imports',
                  value: '$salesSignals',
                  detail: isArabic
                      ? 'استيراد الكتالوج والمصادر'
                      : 'Catalog imports and sources',
                  color: const Color(0xFF2563EB),
                  onTap: () => openSimpleDesk(
                    _workspaceSalesFeeds,
                    _catalogImportSectionKey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('coachOpsSimpleFinance_payNow'),
                    onPressed: () => openSimpleDesk(
                      _workspaceSettlements,
                      _payoutRunsSectionKey,
                    ),
                    icon: const Icon(Icons.playlist_add_check_outlined),
                    label: Text(isArabic ? 'ادفع الآن' : 'Pay now'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('coachOpsSimpleFinance_reviewFailed'),
                    onPressed: () => openSimpleDesk(
                      _workspaceSettlements,
                      _payoutReconciliationSectionKey,
                    ),
                    icon: const Icon(Icons.error_outline),
                    label: Text(isArabic ? 'راجع الفشل' : 'Review failed'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('coachOpsSimpleFinance_export'),
                    onPressed: () => openSimpleDesk(
                      _workspaceSettlements,
                      _payoutRunsSectionKey,
                    ),
                    icon: const Icon(Icons.file_download_outlined),
                    label: Text(isArabic ? 'تصدير' : 'Export'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('coachOpsSimpleFinance_markPaid'),
                    onPressed: () => openSimpleDesk(
                      _workspaceSettlements,
                      _payoutRunsSectionKey,
                    ),
                    icon: const Icon(Icons.price_check_outlined),
                    label: Text(isArabic ? 'علّم كمدفوع' : 'Mark paid'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('coachOpsSimpleFinance_reconcile'),
                    onPressed: () => openSimpleDesk(
                      _workspaceSettlements,
                      _payoutReconciliationSectionKey,
                    ),
                    icon: const Icon(Icons.balance_outlined),
                    label: Text(isArabic ? 'طابق' : 'Reconcile'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Layout breakpoints: keep the wide rail for tablets / desktop where
    // operators typically run the console, fall back to a slide-in drawer
    // on phones where horizontal space is at a premium. 720 dp matches
    // the threshold used elsewhere in the app for two-pane operator UIs.
    return LayoutBuilder(builder: (layoutCtx, constraints) {
      final wideLayout = constraints.maxWidth >= 720;
      final extendedRail = constraints.maxWidth >= 1100;
      final mainBody = SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadQueues,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // Anchor for the "Today" portal navigation destination so
              // tapping it from the rail/drawer always returns to the
              // top-of-console signals overview.
              SizedBox(key: _todaySectionKey, height: 0),
              if (_errorMessage != null) ...[
                StatusBanner.error(_errorMessage!),
                const SizedBox(height: 12),
              ],
              if (_loadingQueues)
                const ShamellSkeletonList(itemCount: 6)
              else ...[
                buildSimpleOpsStartSection(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFFF7FBF8),
                        Color(0xFFE9F4EE),
                        Color(0xFFDDECE4),
                      ],
                    ),
                    border: Border.all(color: const Color(0xFFD5E7DD)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x12081F17),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .78),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFD6E6DE)),
                        ),
                        child: Text(
                          'Coach operator portal',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: const Color(0xFF165B45),
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Operator portal details',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: const Color(0xFF16362B),
                              fontWeight: FontWeight.w900,
                              height: .96,
                            ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Text(
                          'Run today’s coach business from one place: support queues, settlements, payouts, feed health, and sales imports. This home is for operator work, not platform superadmin tasks.',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: const Color(0xFF50675E),
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          partnerBadge(
                            icon: Icons.storefront_outlined,
                            label: 'Scope: $scopeLabel',
                          ),
                          partnerBadge(
                            icon: _financeMutationsAllowed
                                ? Icons.payments_outlined
                                : Icons.visibility_outlined,
                            label: financeModeLabel,
                            color: _financeMutationsAllowed
                                ? const Color(0xFF0F766E)
                                : const Color(0xFF64748B),
                          ),
                          partnerBadge(
                            icon: Icons.hub_outlined,
                            label: catalogModeLabel,
                            color: _catalogImportMutationsAllowed
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF64748B),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Portal lanes',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF214739),
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: portalSections
                            .map(
                              (section) => ChoiceChip(
                                key: ValueKey(
                                  'coachOpsPortalSectionFocus_${section.id}',
                                ),
                                avatar: Icon(
                                  section.icon,
                                  size: 16,
                                  color: _selectedPortalSection == section.id
                                      ? section.color
                                      : const Color(0xFF526176),
                                ),
                                label: Text(
                                  '${section.label} (${section.signalCount})',
                                ),
                                selected: _selectedPortalSection == section.id,
                                selectedColor:
                                    section.color.withValues(alpha: .14),
                                side: BorderSide(
                                  color: _selectedPortalSection == section.id
                                      ? section.color.withValues(alpha: .28)
                                      : const Color(0xFFD6E7DF),
                                ),
                                labelStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color:
                                          _selectedPortalSection == section.id
                                              ? section.color
                                              : const Color(0xFF214739),
                                      fontWeight: FontWeight.w700,
                                    ),
                                onSelected: (_) =>
                                    _selectPortalSection(section.id),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      if (selectedPortalSectionDescriptor != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          selectedPortalSectionDescriptor.detail,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF526176),
                                  ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Jump to',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF214739),
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: visiblePortalJumpChips
                            .map(
                              (jump) => jumpChip(
                                id: jump.id,
                                icon: jump.icon,
                                label: jump.label,
                                workspaceId: jump.workspaceId,
                                targetKey: jump.targetKey,
                              ),
                            )
                            .toList(growable: false),
                      ),
                      if (showSettlementsTracks) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Settlement tracks',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF214739),
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedPortalSection == _portalSectionToday
                              ? 'Filter Today to settlement audit or execution work without leaving the cross-desk view.'
                              : 'Move between preflight audit work and execution queues inside the settlements lane.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF526176),
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            settlementsTrackChip(
                              id: _settlementsTrackAudit,
                              icon: Icons.fact_check_outlined,
                              label: 'Audit',
                              signalCount: _payoutAttentionCount +
                                  _payoutImportCount +
                                  _activePayoutImportPreviewCount,
                              subtitle:
                                  'Reconciliation, payout intake, and preview review before execution.',
                              targetKey: _settlementsAuditSectionKey,
                            ),
                            settlementsTrackChip(
                              id: _settlementsTrackExecution,
                              icon: Icons.playlist_add_check_circle_outlined,
                              label: 'Execution',
                              signalCount: _queuedPayoutRunCount +
                                  _payoutImportBatchCount,
                              subtitle:
                                  'Import batches, payout runs, and settlement statements ready for finance execution.',
                              targetKey: _settlementsExecutionSectionKey,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildWorkspaceFocusSection(context, isArabic, workspaces),
                const SizedBox(height: 16),
                Text(
                  portalSummaryTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  todaySummaryCopy,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .72),
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: visibleTodayCards
                      .map(
                        (card) => _CoachOpsSummaryCard(
                          key: ValueKey('coachOpsTodayCard_${card.id}'),
                          title: card.title,
                          value: card.value,
                          subtitle: card.subtitle,
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 16),
                if (showSettlementsAuditSection)
                  ...portalSection(
                    section: settlementsPortalSection,
                    segmentId: 'audit',
                    subtitle:
                        'Reconciliation, review history, payout imports, and preview history before finance execution.',
                    sectionKey: _settlementsAuditSectionKey,
                    children: [
                      ...workspaceDesk(
                        workspace: settlementsWorkspace,
                        children: [
                          Container(
                            key: _payoutReconciliationSectionKey,
                            child: Text(
                              isArabic
                                  ? 'مطابقة الدفعات'
                                  : 'Payout reconciliation',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_payoutReconciliation != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_payoutReconciliation!.generatedAtIso}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (_payoutReconciliation == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'تعذر تحميل مطابقة الدفعات.'
                                    : 'Payout reconciliation is unavailable.',
                              ),
                            )
                          else if (_payoutReconciliation!.runs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'لا توجد دفعات لمطابقتها بعد.'
                                    : 'No payout runs to reconcile yet.',
                              ),
                            )
                          else ...[
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _CoachOpsSummaryCard(
                                  title: isArabic ? 'مطابق' : 'Balanced',
                                  value:
                                      '${_payoutReconciliation!.summary.balancedRuns}',
                                  subtitle:
                                      '${isArabic ? 'المجموع' : 'Runs'}: ${_payoutReconciliation!.summary.runCount}',
                                ),
                                _CoachOpsSummaryCard(
                                  title: isArabic
                                      ? 'يتطلب انتباه'
                                      : 'Needs attention',
                                  value:
                                      '${_payoutReconciliation!.summary.attentionRuns}',
                                  subtitle:
                                      '${isArabic ? 'مرجع ناقص' : 'Missing reference'}: ${_payoutReconciliation!.summary.missingPaymentReferenceRuns}',
                                ),
                                _CoachOpsSummaryCard(
                                  title: isArabic
                                      ? 'صافي بحاجة لمتابعة'
                                      : 'Attention net',
                                  value: _coachOpsMoney(
                                    _payoutReconciliation!.summary.currency,
                                    _payoutReconciliation!
                                        .summary.attentionNetPayableMinorUnits,
                                  ),
                                  subtitle:
                                      '${isArabic ? 'صادرات جزئية' : 'Partial exports'}: ${_payoutReconciliation!.summary.partialExportRuns}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._payoutReconciliation!.runs.map(
                              (run) =>
                                  _CoachOpsPayoutReconciliationCard(run: run),
                            ),
                            if ((_payoutReconciliation!.nextCursor
                                    ?.trim()
                                    .isNotEmpty ??
                                false))
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'coachOpsPayoutReconciliationLoadOlderButton',
                                    ),
                                    onPressed:
                                        _loadingMorePayoutReconciliation ||
                                                _loadingQueues
                                            ? null
                                            : _loadMorePayoutReconciliation,
                                    icon: _loadingMorePayoutReconciliation
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.unfold_more_outlined),
                                    label: Text(
                                      _loadingMorePayoutReconciliation
                                          ? 'Loading older payout reconciliation...'
                                          : 'Load older payout reconciliation',
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            isArabic
                                ? 'لقطة المطابقة التشغيلية'
                                : 'Reconciliation snapshot',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_reconciliation != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_reconciliation!.generatedAtIso}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (_reconciliation == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'تعذر تحميل لقطة المطابقة التشغيلية.'
                                    : 'Reconciliation snapshot is unavailable.',
                              ),
                            )
                          else ...[
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _CoachOpsSummaryCard(
                                  title: isArabic
                                      ? 'الرحلات المتابعة'
                                      : 'Trips in scope',
                                  value:
                                      '${_reconciliation!.summary.tripCount}',
                                  subtitle:
                                      '${isArabic ? 'الصعود المكتمل' : 'Boarded'}: ${_reconciliation!.summary.boardedPassengers}',
                                ),
                                _CoachOpsSummaryCard(
                                  title: isArabic
                                      ? 'الصعود المعلق'
                                      : 'Pending boarding',
                                  value:
                                      '${_reconciliation!.summary.pendingBoardingPassengers}',
                                  subtitle:
                                      '${isArabic ? 'بحاجة لانتباه' : 'Needs attention'}: ${_reconciliation!.summary.needsAttentionPassengers}',
                                ),
                                _CoachOpsSummaryCard(
                                  title: isArabic
                                      ? 'طلبات تمت مراجعتها'
                                      : 'Reviewed requests',
                                  value:
                                      '${_reconciliation!.summary.reviewedRequests}',
                                  subtitle:
                                      '${isArabic ? 'قيد الانتظار' : 'Pending review'}: ${_reconciliation!.summary.pendingReviewRequests}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._reconciliation!.tripSnapshots.map(
                              (snapshot) => _CoachOpsTripReconciliationCard(
                                snapshot: snapshot,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isArabic ? 'سجل القرارات' : 'Review history',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (_reconciliation!.reviewHistory.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  isArabic
                                      ? 'لا توجد قرارات مراجعة محفوظة بعد.'
                                      : 'No reviewed requests yet.',
                                ),
                              )
                            else
                              ..._reconciliation!.reviewHistory.map(
                                (entry) =>
                                    _CoachOpsReviewHistoryCard(entry: entry),
                              ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                      ...workspaceDesk(
                        workspace: payoutOpsWorkspace,
                        children: [
                          Container(
                            key: _payoutImportsSectionKey,
                            child: Text(
                              isArabic
                                  ? 'سجل استيراد الدفعات'
                                  : 'Payout imports',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_payoutImports != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_payoutImports!.generatedAtIso}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (_payoutImports == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'تعذر تحميل سجل استيراد الدفعات.'
                                    : 'Payout imports are unavailable.',
                              ),
                            )
                          else if (_payoutImports!.imports.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'لا توجد عمليات استيراد دفعات بعد.'
                                    : 'No payout imports yet.',
                              ),
                            )
                          else ...[
                            ..._payoutImports!.imports.map(
                              (entry) =>
                                  _CoachOpsPayoutImportCard(entry: entry),
                            ),
                            if ((_payoutImports!.nextCursor ?? '')
                                .trim()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'coachOpsPayoutImportsLoadOlderButton',
                                    ),
                                    onPressed: _loadingMorePayoutImports ||
                                            _loadingQueues
                                        ? null
                                        : _loadMorePayoutImports,
                                    icon: _loadingMorePayoutImports
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.unfold_more_outlined),
                                    label: Text(
                                      _loadingMorePayoutImports
                                          ? 'Loading older imports...'
                                          : 'Load older imports',
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            isArabic ? 'سجل المعاينات' : 'Preview history',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_payoutImportPreviewHistory != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_payoutImportPreviewHistory!.generatedAtIso}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isArabic
                                        ? 'مرشحات سجل المعاينات'
                                        : 'Preview history filters',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsPreviewHistoryStatusDropdown',
                                    ),
                                    initialValue:
                                        _selectedPayoutImportPreviewStatusFilter,
                                    decoration: const InputDecoration(
                                      labelText: 'Status',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'all',
                                        child: Text('All statuses'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'active',
                                        child: Text('Active'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'consumed',
                                        child: Text('Consumed'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'expired',
                                        child: Text('Expired'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'invalidated',
                                        child: Text('Invalidated'),
                                      ),
                                    ],
                                    onChanged:
                                        _loadingPayoutImportPreviewHistory ||
                                                _loadingQueues
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _selectedPayoutImportPreviewStatusFilter =
                                                      value;
                                                });
                                              },
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsPreviewHistoryOperatorFilterField',
                                    ),
                                    initialValue:
                                        _selectedPayoutImportPreviewOperatorIdFilter,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Operator scope',
                                      border: OutlineInputBorder(),
                                    ),
                                    items:
                                        _payoutImportPreviewHistoryOperatorFilterOptions
                                            .map(
                                              (operatorId) =>
                                                  DropdownMenuItem<String>(
                                                value: operatorId,
                                                child: Text(
                                                  operatorId == 'all'
                                                      ? 'All operators'
                                                      : operatorId,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                    onChanged:
                                        _loadingPayoutImportPreviewHistory ||
                                                _loadingQueues
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                final normalizedValue =
                                                    _normalizePayoutImportOperatorIdFilterValue(
                                                  value,
                                                );
                                                setState(() {
                                                  _selectedPayoutImportPreviewOperatorIdFilter =
                                                      normalizedValue;
                                                });
                                                unawaited(
                                                  _persistPayoutImportPreviewHistoryOperatorFilterSelection(
                                                    normalizedValue,
                                                  ),
                                                );
                                              },
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller:
                                        _payoutImportPreviewFromCreatedAtController,
                                    enabled:
                                        !_loadingPayoutImportPreviewHistory &&
                                            !_loadingQueues,
                                    decoration: const InputDecoration(
                                      labelText: 'From created_at (RFC3339)',
                                      hintText: '2026-04-14T00:00:00Z',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistoryPresetToday',
                                        ),
                                        onPressed:
                                            _loadingPayoutImportPreviewHistory ||
                                                    _loadingQueues
                                                ? null
                                                : () =>
                                                    _applyPayoutImportPreviewHistoryTimePreset(
                                                      'today',
                                                    ),
                                        child: const Text('Today'),
                                      ),
                                      OutlinedButton(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistoryPresetLast24h',
                                        ),
                                        onPressed:
                                            _loadingPayoutImportPreviewHistory ||
                                                    _loadingQueues
                                                ? null
                                                : () =>
                                                    _applyPayoutImportPreviewHistoryTimePreset(
                                                      'last_24h',
                                                    ),
                                        child: const Text('Last 24h'),
                                      ),
                                      OutlinedButton(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistoryPresetLast7d',
                                        ),
                                        onPressed:
                                            _loadingPayoutImportPreviewHistory ||
                                                    _loadingQueues
                                                ? null
                                                : () =>
                                                    _applyPayoutImportPreviewHistoryTimePreset(
                                                      'last_7d',
                                                    ),
                                        child: const Text('Last 7d'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistoryCombinedPresetActiveToday',
                                        ),
                                        onPressed:
                                            _loadingPayoutImportPreviewHistory ||
                                                    _loadingQueues
                                                ? null
                                                : () =>
                                                    _applyPayoutImportPreviewHistoryCombinedPreset(
                                                      'active_today',
                                                    ),
                                        child: const Text('Active today'),
                                      ),
                                      OutlinedButton(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistoryCombinedPresetInvalidatedLast7d',
                                        ),
                                        onPressed:
                                            _loadingPayoutImportPreviewHistory ||
                                                    _loadingQueues
                                                ? null
                                                : () =>
                                                    _applyPayoutImportPreviewHistoryCombinedPreset(
                                                      'invalidated_last_7d',
                                                    ),
                                        child:
                                            const Text('Invalidated last 7d'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller:
                                        _payoutImportPreviewToCreatedAtController,
                                    enabled:
                                        !_loadingPayoutImportPreviewHistory &&
                                            !_loadingQueues,
                                    decoration: const InputDecoration(
                                      labelText: 'To created_at (RFC3339)',
                                      hintText: '2026-04-15T23:59:59Z',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Filters affect preview history only. Use RFC3339 timestamps for the created_at window. Presets use UTC and populate the draft window.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistoryApplyFiltersButton',
                                        ),
                                        onPressed:
                                            _loadingPayoutImportPreviewHistory ||
                                                    _loadingQueues
                                                ? null
                                                : _applyPayoutImportPreviewHistoryFilters,
                                        icon: _loadingPayoutImportPreviewHistory
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.filter_alt_outlined),
                                        label: Text(
                                          _loadingPayoutImportPreviewHistory
                                              ? 'Loading...'
                                              : 'Apply filters',
                                        ),
                                      ),
                                      TextButton(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistoryClearFiltersButton',
                                        ),
                                        onPressed: _loadingPayoutImportPreviewHistory ||
                                                _loadingQueues ||
                                                (!_hasActivePayoutImportPreviewHistoryFilters &&
                                                    !_hasDraftPayoutImportPreviewHistoryFilters)
                                            ? null
                                            : _clearPayoutImportPreviewHistoryFilters,
                                        child: const Text('Clear filters'),
                                      ),
                                    ],
                                  ),
                                  if (_hasActivePayoutImportPreviewHistoryFilters) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Active filters: '
                                      '${_appliedPayoutImportPreviewStatusFilter ?? 'all'}'
                                      '${_appliedPayoutImportPreviewFromCreatedAtIso == null ? '' : ' • from ${_appliedPayoutImportPreviewFromCreatedAtIso}'}'
                                      '${_appliedPayoutImportPreviewToCreatedAtIso == null ? '' : ' • to ${_appliedPayoutImportPreviewToCreatedAtIso}'}'
                                      '${_payoutImportPreviewHistoryOperatorIdFilter == null ? '' : ' • operator ${_payoutImportPreviewHistoryOperatorIdFilter}'}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  if (_payoutImportPreviewHistory != null &&
                                      (_payoutImportPreviewHistoryOperatorIdFilter !=
                                              null ||
                                          _payoutImportPreviewHistory!
                                                  .previews.length !=
                                              visiblePayoutImportPreviewHistory
                                                  .length)) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        Chip(
                                          key: const ValueKey(
                                            'coachOpsPreviewHistoryFilteredCountChip',
                                          ),
                                          avatar: const Icon(
                                            Icons.filter_alt_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            isArabic
                                                ? 'المعروض: ${visiblePayoutImportPreviewHistory.length} من ${_payoutImportPreviewHistory!.previews.length}'
                                                : 'Shown: ${visiblePayoutImportPreviewHistory.length} of ${_payoutImportPreviewHistory!.previews.length}',
                                          ),
                                        ),
                                        if (_payoutImportPreviewHistoryOperatorIdFilter !=
                                            null)
                                          InputChip(
                                            key: const ValueKey(
                                              'coachOpsPreviewHistoryOperatorFilterChip',
                                            ),
                                            label: Text(
                                              'Operator: ${_payoutImportPreviewHistoryOperatorIdFilter!}',
                                            ),
                                            onDeleted:
                                                _loadingPayoutImportPreviewHistory ||
                                                        _loadingQueues
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _selectedPayoutImportPreviewOperatorIdFilter =
                                                              'all';
                                                        });
                                                        unawaited(
                                                          _persistPayoutImportPreviewHistoryOperatorFilterSelection(
                                                            'all',
                                                          ),
                                                        );
                                                      },
                                          ),
                                      ],
                                    ),
                                  ],
                                  if (_payoutImportPreviewHistoryFiltersDirty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Draft filters changed. Apply filters to refresh preview history.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Saved views',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Personal views stay on your finance account. Shared views are visible to all coach ops accounts when the API is available.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsPreviewHistorySavedViewsVisibilityFilterField',
                                    ),
                                    initialValue:
                                        _payoutImportPreviewSavedViewsVisibilityFilter,
                                    decoration: const InputDecoration(
                                      labelText: 'Show saved views',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'all',
                                        child: Text('All scopes'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'personal',
                                        child: Text('Personal only'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'shared_ops',
                                        child: Text('Shared with ops only'),
                                      ),
                                    ],
                                    onChanged:
                                        _savingPayoutImportPreviewSavedView ||
                                                _loadingPayoutImportPreviewHistory ||
                                                _loadingQueues
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _payoutImportPreviewSavedViewsVisibilityFilter =
                                                      _normalizeCatalogSavedViewVisibilityFilter(
                                                    value,
                                                  );
                                                });
                                              },
                                  ),
                                  if (_payoutImportPreviewSavedViewsVisibilityFilter ==
                                      'shared_ops') ...[
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'coachOpsPreviewHistorySavedViewsOwnerFilterField',
                                      ),
                                      initialValue:
                                          _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                      decoration: const InputDecoration(
                                        labelText: 'Shared view owner',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items:
                                          _catalogImportRunSavedViewOwnerAccountIdOptions(
                                        _payoutImportPreviewSavedViewOwners,
                                        _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                      ).map((value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _catalogSavedViewOwnerFilterOptionLabel(
                                              value,
                                              _payoutImportPreviewSavedViewOwners,
                                            ),
                                          ),
                                        );
                                      }).toList(growable: false),
                                      onChanged:
                                          _savingPayoutImportPreviewSavedView ||
                                                  _loadingPayoutImportPreviewHistory ||
                                                  _loadingQueues
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _payoutImportPreviewSavedViewsOwnerAccountIdFilter =
                                                        _normalizeCatalogSavedViewOwnerAccountIdFilter(
                                                      value,
                                                    );
                                                  });
                                                },
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _catalogSavedViewOwnerFilterSummaryText(
                                        _payoutImportPreviewSavedViewOwners,
                                        _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'coachOpsPreviewHistorySavedViewsOperatorFilterField',
                                      ),
                                      initialValue:
                                          _payoutImportPreviewSavedViewsOperatorIdFilter,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Shared operator scope',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: _catalogSavedViewOperatorIdOptions(
                                        summaries:
                                            _payoutImportPreviewSavedViewOperators,
                                        selectedOperatorId:
                                            _payoutImportPreviewSavedViewsOperatorIdFilter,
                                      ).map((value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _catalogOperatorFilterOptionLabel(
                                              value,
                                              summaries:
                                                  _payoutImportPreviewSavedViewOperators,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(growable: false),
                                      onChanged:
                                          _savingPayoutImportPreviewSavedView ||
                                                  _loadingPayoutImportPreviewHistory ||
                                                  _loadingQueues
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _payoutImportPreviewSavedViewsOperatorIdFilter =
                                                        _normalizePayoutImportOperatorIdFilterValue(
                                                      value,
                                                    );
                                                  });
                                                },
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _catalogOperatorFilterSummaryText(
                                        _payoutImportPreviewSavedViewsOperatorIdFilter,
                                        summaries:
                                            _payoutImportPreviewSavedViewOperators,
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  if (_payoutImportPreviewSavedViewsVisibilityFilter !=
                                          'all' ||
                                      _payoutImportPreviewSavedViews.length !=
                                          visiblePayoutImportPreviewSavedViews
                                              .length) ...[
                                    const SizedBox(height: 8),
                                    Chip(
                                      key: const ValueKey(
                                        'coachOpsPreviewHistorySavedViewsFilteredCountChip',
                                      ),
                                      avatar: const Icon(
                                        Icons.filter_alt_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'Shown: ${visiblePayoutImportPreviewSavedViews.length} of ${_payoutImportPreviewSavedViews.length}',
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller:
                                        _payoutImportPreviewSavedViewNameController,
                                    enabled:
                                        !_savingPayoutImportPreviewSavedView &&
                                            !_loadingPayoutImportPreviewHistory &&
                                            !_loadingQueues,
                                    decoration: const InputDecoration(
                                      labelText: 'Saved view name',
                                      hintText: 'Invalidated last 7d',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsPreviewHistorySavedViewScopeField',
                                    ),
                                    initialValue:
                                        _payoutImportPreviewSavedViewVisibilityScope,
                                    decoration: const InputDecoration(
                                      labelText: 'View scope',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'personal',
                                        child: Text('Personal'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'shared_ops',
                                        child: Text('Shared with ops'),
                                      ),
                                    ],
                                    onChanged:
                                        _savingPayoutImportPreviewSavedView ||
                                                _loadingPayoutImportPreviewHistory ||
                                                _loadingQueues
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _payoutImportPreviewSavedViewVisibilityScope =
                                                      value;
                                                });
                                              },
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'coachOpsPreviewHistorySaveViewButton',
                                        ),
                                        onPressed: _savingPayoutImportPreviewSavedView ||
                                                _loadingPayoutImportPreviewHistory ||
                                                _loadingQueues
                                            ? null
                                            : _savePayoutImportPreviewHistorySavedView,
                                        icon:
                                            _savingPayoutImportPreviewSavedView
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(Icons
                                                    .bookmark_add_outlined),
                                        label: Text(
                                          _savingPayoutImportPreviewSavedView
                                              ? 'Saving view...'
                                              : 'Save view',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (recentPayoutImportPreviewSavedViews
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Recent views',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          recentPayoutImportPreviewSavedViews
                                              .map((
                                        view,
                                      ) {
                                        final isCurrent =
                                            _payoutImportPreviewSavedViewIsCurrent(
                                                view);
                                        return ActionChip(
                                          key: ValueKey(
                                            'coachOpsPreviewHistoryRecentSavedView_${view.viewId}',
                                          ),
                                          avatar: const Icon(
                                            Icons.history,
                                            size: 18,
                                          ),
                                          label: Text(view.name),
                                          onPressed:
                                              _loadingPayoutImportPreviewHistory ||
                                                      _loadingQueues ||
                                                      isCurrent
                                                  ? null
                                                  : () =>
                                                      _applyPayoutImportPreviewHistorySavedView(
                                                        view,
                                                      ),
                                        );
                                      }).toList(growable: false),
                                    ),
                                  ],
                                  if (visiblePayoutImportPreviewSavedViews
                                      .isEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _payoutImportPreviewSavedViews.isEmpty
                                          ? 'No saved views yet.'
                                          : (_payoutImportPreviewSavedViewsVisibilityFilter ==
                                                      'shared_ops' &&
                                                  (_normalizeCatalogSavedViewOwnerAccountIdFilter(
                                                            _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                                          ) !=
                                                          'all' ||
                                                      _normalizePayoutImportOperatorIdFilterValue(
                                                            _payoutImportPreviewSavedViewsOperatorIdFilter,
                                                          ) !=
                                                          'all'))
                                              ? 'No saved views match the active scope and owner filters.'
                                              : 'No saved views match the active scope filter.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 10),
                                    ...visiblePayoutImportPreviewSavedViews.map(
                                      (view) {
                                        final isPinnedView = _savedViewIsPinned(
                                          _payoutImportPreviewSavedViewPinnedIds,
                                          view.viewId,
                                        );
                                        return Container(
                                          width: double.infinity,
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    view.name,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                  Chip(
                                                    label: Text(
                                                      _catalogSavedViewVisibilityScopeLabel(
                                                        view.visibilityScope,
                                                      ),
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  if (view.isDefault)
                                                    Chip(
                                                      label: const Text(
                                                          'Default view'),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                  if (isPinnedView)
                                                    Chip(
                                                      label:
                                                          const Text('Pinned'),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                ],
                                              ),
                                              if (view.visibilityScope ==
                                                  'shared_ops') ...[
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    if (_payoutSavedViewOwnerChipLabel(
                                                          view.visibilityScope,
                                                          view.accountId,
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _payoutSavedViewOwnerChipLabel(
                                                            view.visibilityScope,
                                                            view.accountId,
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    if (_payoutSavedViewOperatorChipLabel(
                                                          view.preferences
                                                              .operatorId,
                                                          summaries:
                                                              _payoutImportPreviewSavedViewOperators,
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _payoutSavedViewOperatorChipLabel(
                                                            view.preferences
                                                                .operatorId,
                                                            summaries:
                                                                _payoutImportPreviewSavedViewOperators,
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    if (_payoutSavedViewReadOnlyChipLabel(
                                                          view.visibilityScope,
                                                          view.canManage,
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _payoutSavedViewReadOnlyChipLabel(
                                                            view.visibilityScope,
                                                            view.canManage,
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                  ],
                                                ),
                                              ],
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children:
                                                    _payoutImportPreviewSavedViewContentChipLabels(
                                                  view.preferences,
                                                ).map((label) {
                                                  return Chip(
                                                    label: Text(label),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  );
                                                }).toList(growable: false),
                                              ),
                                              if (_payoutSavedViewActiveChipLabels(
                                                    selectedVisibilityScope:
                                                        _payoutImportPreviewSavedViewsVisibilityFilter,
                                                    viewVisibilityScope:
                                                        view.visibilityScope,
                                                    viewAccountId:
                                                        view.accountId,
                                                    selectedOwnerAccountId:
                                                        _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                                    viewOperatorId: view
                                                        .preferences.operatorId,
                                                    selectedOperatorId:
                                                        _payoutImportPreviewSavedViewsOperatorIdFilter,
                                                  ).isNotEmpty ||
                                                  _payoutImportPreviewSavedViewIsCurrent(
                                                    view,
                                                  ) ||
                                                  _savedViewRecentlyUsedChipLabel(
                                                        _payoutImportPreviewSavedViewUsedAtById[
                                                            view.viewId],
                                                      ) !=
                                                      null)
                                                const SizedBox(height: 6),
                                              if (_payoutSavedViewActiveChipLabels(
                                                    selectedVisibilityScope:
                                                        _payoutImportPreviewSavedViewsVisibilityFilter,
                                                    viewVisibilityScope:
                                                        view.visibilityScope,
                                                    viewAccountId:
                                                        view.accountId,
                                                    selectedOwnerAccountId:
                                                        _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                                    viewOperatorId: view
                                                        .preferences.operatorId,
                                                    selectedOperatorId:
                                                        _payoutImportPreviewSavedViewsOperatorIdFilter,
                                                  ).isNotEmpty ||
                                                  _payoutImportPreviewSavedViewIsCurrent(
                                                    view,
                                                  ) ||
                                                  _savedViewRecentlyUsedChipLabel(
                                                        _payoutImportPreviewSavedViewUsedAtById[
                                                            view.viewId],
                                                      ) !=
                                                      null)
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    ..._payoutSavedViewActiveChipLabels(
                                                      selectedVisibilityScope:
                                                          _payoutImportPreviewSavedViewsVisibilityFilter,
                                                      viewVisibilityScope:
                                                          view.visibilityScope,
                                                      viewAccountId:
                                                          view.accountId,
                                                      selectedOwnerAccountId:
                                                          _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                                      viewOperatorId: view
                                                          .preferences
                                                          .operatorId,
                                                      selectedOperatorId:
                                                          _payoutImportPreviewSavedViewsOperatorIdFilter,
                                                    ).map((label) {
                                                      return Chip(
                                                        label: Text(label),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      );
                                                    }),
                                                    if (_payoutImportPreviewSavedViewIsCurrent(
                                                      view,
                                                    ))
                                                      const Chip(
                                                        label: Text(
                                                            'Using this view'),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    if (_savedViewRecentlyUsedChipLabel(
                                                          _payoutImportPreviewSavedViewUsedAtById[
                                                              view.viewId],
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _savedViewRecentlyUsedChipLabel(
                                                            _payoutImportPreviewSavedViewUsedAtById[
                                                                view.viewId],
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                  ],
                                                ),
                                              const SizedBox(height: 4),
                                              if (_catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  ) !=
                                                  null)
                                                Text(
                                                  _catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  )!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              if (_catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  ) !=
                                                  null)
                                                const SizedBox(height: 4),
                                              if (_catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  ) !=
                                                  null)
                                                Text(
                                                  _catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  )!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              if (_catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  ) !=
                                                  null)
                                                const SizedBox(height: 4),
                                              const SizedBox(height: 4),
                                              Text(
                                                _describePayoutImportPreviewHistoryPreferences(
                                                  view.preferences,
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Updated ${view.updatedAtIso}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 8,
                                                children: [
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPreviewHistoryApplySavedView_${view.viewId}',
                                                    ),
                                                    onPressed:
                                                        _loadingPayoutImportPreviewHistory ||
                                                                _loadingQueues ||
                                                                _payoutImportPreviewSavedViewIsCurrent(
                                                                  view,
                                                                )
                                                            ? null
                                                            : () =>
                                                                _applyPayoutImportPreviewHistorySavedView(
                                                                  view,
                                                                ),
                                                    icon: const Icon(
                                                      Icons
                                                          .bookmark_added_outlined,
                                                    ),
                                                    label: Text(
                                                      _payoutImportPreviewSavedViewIsCurrent(
                                                        view,
                                                      )
                                                          ? 'View already active'
                                                          : 'Apply view',
                                                    ),
                                                  ),
                                                  OutlinedButton(
                                                    key: ValueKey(
                                                      'coachOpsPreviewHistoryTogglePinnedSavedView_${view.viewId}',
                                                    ),
                                                    onPressed:
                                                        _loadingPayoutImportPreviewHistory ||
                                                                _loadingQueues
                                                            ? null
                                                            : () =>
                                                                _togglePayoutImportPreviewSavedViewFavorite(
                                                                  viewId: view
                                                                      .viewId,
                                                                  favorite:
                                                                      !isPinnedView,
                                                                ),
                                                    child: Text(
                                                      isPinnedView
                                                          ? 'Unpin view'
                                                          : 'Pin view',
                                                    ),
                                                  ),
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPreviewHistoryFilterByOwner_${view.viewId}',
                                                    ),
                                                    onPressed:
                                                        _loadingPayoutImportPreviewHistory ||
                                                                _loadingQueues ||
                                                                view.visibilityScope !=
                                                                    'shared_ops' ||
                                                                view.accountId
                                                                    .trim()
                                                                    .isEmpty ||
                                                                _catalogSavedViewMatchesOwnerFilter(
                                                                  view.visibilityScope,
                                                                  view.accountId,
                                                                  _payoutImportPreviewSavedViewsVisibilityFilter,
                                                                  _payoutImportPreviewSavedViewsOwnerAccountIdFilter,
                                                                )
                                                            ? null
                                                            : () {
                                                                setState(() {
                                                                  _payoutImportPreviewSavedViewsVisibilityFilter =
                                                                      'shared_ops';
                                                                  _payoutImportPreviewSavedViewsOwnerAccountIdFilter =
                                                                      _normalizeCatalogSavedViewOwnerAccountIdFilter(
                                                                    view.accountId,
                                                                  );
                                                                });
                                                              },
                                                    icon: const Icon(
                                                      Icons.filter_alt_outlined,
                                                    ),
                                                    label: const Text(
                                                        'Filter by owner'),
                                                  ),
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPreviewHistoryFilterByOperator_${view.viewId}',
                                                    ),
                                                    onPressed:
                                                        _loadingPayoutImportPreviewHistory ||
                                                                _loadingQueues ||
                                                                view.visibilityScope !=
                                                                    'shared_ops' ||
                                                                _normalizePayoutImportOperatorIdFilterValue(
                                                                      view.preferences
                                                                          .operatorId,
                                                                    ) ==
                                                                    'all' ||
                                                                _normalizePayoutImportOperatorIdFilterValue(
                                                                      view.preferences
                                                                          .operatorId,
                                                                    ) ==
                                                                    _payoutImportPreviewSavedViewsOperatorIdFilter
                                                            ? null
                                                            : () {
                                                                setState(() {
                                                                  _payoutImportPreviewSavedViewsVisibilityFilter =
                                                                      'shared_ops';
                                                                  _payoutImportPreviewSavedViewsOperatorIdFilter =
                                                                      _normalizePayoutImportOperatorIdFilterValue(
                                                                    view.preferences
                                                                        .operatorId,
                                                                  );
                                                                });
                                                              },
                                                    icon: const Icon(
                                                      Icons
                                                          .directions_bus_outlined,
                                                    ),
                                                    label: const Text(
                                                        'Filter by operator'),
                                                  ),
                                                  OutlinedButton(
                                                    key: ValueKey(
                                                      'coachOpsPreviewHistoryToggleDefaultSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: view.visibilityScope !=
                                                                'personal' ||
                                                            _loadingPayoutImportPreviewHistory ||
                                                            _loadingQueues ||
                                                            _updatingPayoutImportPreviewSavedViewDefaultIds
                                                                .contains(
                                                                    view.viewId)
                                                        ? null
                                                        : () =>
                                                            _togglePayoutImportPreviewHistorySavedViewDefault(
                                                              view,
                                                            ),
                                                    child: Text(
                                                      view.isDefault
                                                          ? 'Clear default'
                                                          : 'Set default',
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPreviewHistoryDeleteSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: _deletingPayoutImportPreviewSavedViewIds
                                                                .contains(view
                                                                    .viewId) ||
                                                            !view.canManage ||
                                                            _loadingPayoutImportPreviewHistory ||
                                                            _loadingQueues
                                                        ? null
                                                        : () =>
                                                            _deletePayoutImportPreviewHistorySavedView(
                                                              view,
                                                            ),
                                                    icon:
                                                        _deletingPayoutImportPreviewSavedViewIds
                                                                .contains(
                                                                    view.viewId)
                                                            ? const SizedBox(
                                                                width: 14,
                                                                height: 14,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                              )
                                                            : const Icon(
                                                                Icons
                                                                    .delete_outline,
                                                              ),
                                                    label: Text(
                                                      _deletingPayoutImportPreviewSavedViewIds
                                                              .contains(
                                                                  view.viewId)
                                                          ? 'Deleting...'
                                                          : 'Delete view',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (_payoutImportPreviewHistoryErrorMessage !=
                              null) ...[
                            StatusBanner.error(
                                _payoutImportPreviewHistoryErrorMessage!),
                            const SizedBox(height: 12),
                          ],
                          if (_loadingPayoutImportPreviewHistory &&
                              !_loadingQueues)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: ShamellSkeletonList(itemCount: 3),
                            )
                          else if (_payoutImportPreviewHistory == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'تعذر تحميل سجل المعاينات.'
                                    : 'Preview history is unavailable.',
                              ),
                            )
                          else if (_payoutImportPreviewHistory!
                              .previews.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                _hasActivePayoutImportPreviewHistoryFilters
                                    ? (isArabic
                                        ? 'لا توجد معاينات تطابق المرشحات الحالية.'
                                        : 'No previews match the current filters.')
                                    : (isArabic
                                        ? 'لا توجد معاينات دفعات بعد.'
                                        : 'No payout import previews yet.'),
                              ),
                            )
                          else if (visiblePayoutImportPreviewHistory.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'لا توجد معاينات تطابق عامل التصفية الحالي للمشغل.'
                                    : 'No previews match the current operator filter.',
                              ),
                            )
                          else ...[
                            ...visiblePayoutImportPreviewHistory.map(
                              (entry) => _CoachOpsPayoutImportPreviewCard(
                                entry: entry,
                                financeMutationsAllowed:
                                    _financeMutationsAllowed,
                                busy: _invalidatingPreviewTokens
                                    .contains(entry.previewToken),
                                onInvalidate: entry.usableNow
                                    ? () => _invalidatePayoutImportPreview(
                                        entry.previewToken)
                                    : null,
                              ),
                            ),
                            if ((_payoutImportPreviewHistory!.nextCursor ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  key: const ValueKey(
                                    'coachOpsPreviewHistoryLoadOlderButton',
                                  ),
                                  onPressed:
                                      _loadingMorePayoutImportPreviewHistory ||
                                              _loadingPayoutImportPreviewHistory ||
                                              _loadingQueues
                                          ? null
                                          : _loadMorePayoutImportPreviewHistory,
                                  icon: _loadingMorePayoutImportPreviewHistory
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.unfold_more_outlined),
                                  label: Text(
                                    _loadingMorePayoutImportPreviewHistory
                                        ? 'Loading older previews...'
                                        : 'Load older previews',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ],
                  ),
                ...portalSection(
                  section: tripsPortalSection,
                  segmentId: 'feed_health',
                  subtitle:
                      'Feed health, degraded operators, and stale inputs that threaten live trip coverage.',
                  children: [
                    ...workspaceDesk(
                      workspace: salesFeedsWorkspace,
                      segmentId: 'trips',
                      showHeader: _selectedPortalSection != _portalSectionSales,
                      children: [
                        Container(
                          key: _feedHealthSectionKey,
                          child: Text(
                            isArabic
                                ? 'صحة تغذيات الشركاء'
                                : 'Operator feed health',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_operatorFeedHealth != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_operatorFeedHealth!.generatedAtIso}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (_operatorFeedHealth == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              isArabic
                                  ? 'تعذر تحميل صحة التغذيات.'
                                  : 'Operator feed health is unavailable.',
                            ),
                          )
                        else if (_operatorFeedHealth!.feeds.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              isArabic
                                  ? 'لا توجد تغذيات شركاء بعد.'
                                  : 'No operator feeds yet.',
                            ),
                          )
                        else ...[
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _CoachOpsSummaryCard(
                                title: isArabic ? 'المشغّلون' : 'Operators',
                                value:
                                    '${_operatorFeedHealth!.summary.operatorsTotal}',
                                subtitle:
                                    '${isArabic ? 'سليم' : 'Healthy'}: ${_operatorFeedHealth!.summary.healthyOperators}',
                              ),
                              _CoachOpsSummaryCard(
                                title: isArabic ? 'متدهور' : 'Degraded',
                                value:
                                    '${_operatorFeedHealth!.summary.degradedFeeds}',
                                subtitle:
                                    '${isArabic ? 'قديم' : 'Stale'}: ${_operatorFeedHealth!.summary.staleFeeds}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._operatorFeedHealth!.feeds.map(
                            (entry) => _CoachOpsFeedHealthCard(entry: entry),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ],
                ),
                ...portalSection(
                  section: salesPortalSection,
                  segmentId: 'market',
                  subtitle:
                      'Catalog imports, source artifacts, and import runs that shape sellable coach inventory.',
                  children: [
                    ...workspaceDesk(
                      workspace: salesFeedsWorkspace,
                      segmentId: 'sales',
                      showHeader: _selectedPortalSection == _portalSectionSales,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              key: _catalogImportSectionKey,
                              child: Text(
                                isArabic
                                    ? 'تهيئة استيراد الكتالوج'
                                    : 'Catalog import configuration',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (_catalogImportConfig != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 8),
                                child: Text(
                                  '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_catalogImportConfig!.generatedAtIso}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            if (_catalogImportConfig == null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  isArabic
                                      ? 'تعذر تحميل تهيئة استيراد الكتالوج.'
                                      : 'Catalog import configuration is unavailable.',
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${isArabic ? 'الحالة' : 'Status'}: ${_coachCatalogImportConfigStatusLabel(_catalogImportConfig!.status)}',
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${isArabic ? 'المصدر' : 'Source'}: ${_coachCatalogImportSourceKindLabel(_catalogImportConfig!.sourceKind)}',
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${isArabic ? 'الأصل' : 'Origin'}: ${_catalogImportConfig!.configOrigin}',
                                    ),
                                    if ((_catalogImportConfig!.feedLocator ??
                                            '')
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${isArabic ? 'المسار' : 'Feed locator'}: ${_catalogImportConfig!.feedLocator}',
                                      ),
                                    ],
                                    if (_catalogImportConfig!.sourceArtifact !=
                                        null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${isArabic ? 'الأرشيف' : 'Artifact'}: ${_catalogImportConfig!.sourceArtifact!.sourceLabel}',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${isArabic ? 'المعرّف' : 'Artifact id'}: ${_catalogImportConfig!.sourceArtifact!.artifactId}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${isArabic ? 'الحجم' : 'Size'}: ${_catalogImportConfig!.sourceArtifact!.contentLengthBytes} bytes • '
                                        '${isArabic ? 'ملفات مستخرجة' : 'Extracted files'}: ${_catalogImportConfig!.sourceArtifact!.extractedFileCount}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      '${isArabic ? 'التفاصيل' : 'Detail'}: ${_catalogImportConfig!.detail}',
                                    ),
                                    if (_catalogImportConfigRequiresScopedSource) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          (_catalogImportSources
                                                      ?.sources.isNotEmpty ??
                                                  false)
                                              ? _coachCatalogImportScopedSourceGuidanceText(
                                                  isArabic,
                                                )
                                              : _coachCatalogImportScopedSourceEmptyText(
                                                  isArabic,
                                                ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ],
                                    if ((_catalogImportConfig!
                                                .updatedByAccountId ??
                                            '')
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${isArabic ? 'آخر تحديث بواسطة' : 'Updated by'}: ${_catalogImportConfig!.updatedByAccountId}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    if ((_catalogImportConfig!.updatedAtIso ??
                                            '')
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${isArabic ? 'وقت آخر تحديث' : 'Updated at'}: ${_catalogImportConfig!.updatedAtIso}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    if (_catalogImportConfig!.latestImportRun !=
                                        null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '${isArabic ? 'آخر تشغيل' : 'Latest run'}: '
                                        '${_catalogImportConfig!.latestImportRun!.importRunId} • '
                                        '${_catalogImportConfig!.latestImportRun!.status}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    if (!_catalogImportMutationsAllowed) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          _coachCatalogImportReadOnlyConfigHintText(
                                            isArabic,
                                            scopedSourceRequired:
                                                _catalogImportConfigRequiresScopedSource,
                                            hasSourceArtifact:
                                                _catalogImportConfig!
                                                        .sourceArtifact !=
                                                    null,
                                          ),
                                          key: const ValueKey(
                                            'coachOpsCatalogImportConfigReadOnlyHint',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ],
                                    if (_catalogImportMutationsAllowed) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: [
                                          OutlinedButton.icon(
                                            key: const ValueKey(
                                              'coachOpsCatalogImportFileSelectButton',
                                            ),
                                            onPressed:
                                                _uploadingCatalogImportSource ||
                                                        _loadingQueues
                                                    ? null
                                                    : _selectCatalogImportFile,
                                            icon: const Icon(
                                                Icons.archive_outlined),
                                            label: Text(
                                              _selectedCatalogImportFile == null
                                                  ? 'Select GTFS ZIP'
                                                  : 'Replace GTFS ZIP',
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            key: const ValueKey(
                                              'coachOpsCatalogImportFileUploadButton',
                                            ),
                                            onPressed: _uploadingCatalogImportSource ||
                                                    _loadingQueues ||
                                                    _selectedCatalogImportFile ==
                                                        null
                                                ? null
                                                : _uploadCatalogImportSourceFile,
                                            icon: _uploadingCatalogImportSource
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.upload_file_outlined,
                                                  ),
                                            label: Text(
                                              _uploadingCatalogImportSource
                                                  ? 'Uploading GTFS ZIP...'
                                                  : 'Upload GTFS ZIP',
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_selectedCatalogImportFile !=
                                          null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Selected archive: ${_selectedCatalogImportFile!.fileName} (${_selectedCatalogImportFile!.bytes.length} bytes)',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _coachCatalogImportUploadDisabledHintText(
                                                isArabic,
                                                hasSelectedArchive:
                                                    _selectedCatalogImportFile !=
                                                        null,
                                                uploading:
                                                    _uploadingCatalogImportSource,
                                                loading: _loadingQueues,
                                              ) ??
                                              '',
                                          key: const ValueKey(
                                            'coachOpsCatalogImportUploadDisabledHint',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      if ((_catalogImportSources
                                                  ?.sources.length ??
                                              0) >
                                          0) ...[
                                        DropdownButtonFormField<String>(
                                          key: const ValueKey(
                                            'coachOpsCatalogImportSourceDropdown',
                                          ),
                                          initialValue:
                                              _selectedCatalogImportSourceLocator,
                                          decoration: const InputDecoration(
                                            labelText: 'Available source',
                                            border: OutlineInputBorder(),
                                          ),
                                          items: (_catalogImportSources
                                                      ?.sources ??
                                                  const <CoachOperatorCatalogImportSourceOption>[])
                                              .map(
                                                (source) =>
                                                    DropdownMenuItem<String>(
                                                  value: source.feedLocator,
                                                  child: Text(
                                                    '${source.sourceLabel} • ${_coachCatalogImportConfigStatusLabel(source.status)}',
                                                  ),
                                                ),
                                              )
                                              .toList(growable: false),
                                          onChanged:
                                              _savingCatalogImportConfig ||
                                                      _loadingQueues
                                                  ? null
                                                  : (value) {
                                                      if (value == null) {
                                                        return;
                                                      }
                                                      setState(() {
                                                        _catalogImportFeedLocatorController
                                                            .text = value;
                                                      });
                                                    },
                                        ),
                                        if (_selectedCatalogImportSource !=
                                            null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            '${isArabic ? 'المصدر المحدد' : 'Selected source'}: '
                                            '${_coachCatalogImportSourceOriginLabel(_selectedCatalogImportSource!.sourceOrigin)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _selectedCatalogImportSource!
                                                .detail,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${isArabic ? 'المسار المحدد' : 'Selected locator'}: ${_selectedCatalogImportSource!.feedLocator}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                      ],
                                      if (!_catalogImportConfigRequiresScopedSource) ...[
                                        TextField(
                                          key: const ValueKey(
                                            'coachOpsCatalogImportFeedLocatorField',
                                          ),
                                          controller:
                                              _catalogImportFeedLocatorController,
                                          enabled:
                                              !_savingCatalogImportConfig &&
                                                  !_loadingQueues,
                                          decoration: const InputDecoration(
                                            labelText: 'Feed locator',
                                            hintText: '/srv/feeds/operator_a',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          key: const ValueKey(
                                            'coachOpsCatalogImportConfigSaveButton',
                                          ),
                                          onPressed: _savingCatalogImportConfig ||
                                                  _loadingQueues ||
                                                  (_catalogImportConfigRequiresScopedSource
                                                      ? !_hasCatalogImportScopedSourceDraft
                                                      : !_hasCatalogImportFeedLocatorDraft)
                                              ? null
                                              : _saveCatalogImportConfig,
                                          icon: _savingCatalogImportConfig
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(Icons.save_outlined),
                                          label: Text(
                                            _savingCatalogImportConfig
                                                ? 'Saving configuration...'
                                                : _catalogImportConfigRequiresScopedSource
                                                    ? 'Activate selected source'
                                                    : 'Save import configuration',
                                          ),
                                        ),
                                      ),
                                      if ((_coachCatalogImportSaveDisabledHintText(
                                                isArabic,
                                                scopedSourceRequired:
                                                    _catalogImportConfigRequiresScopedSource,
                                                hasScopedSourceDraft:
                                                    _hasCatalogImportScopedSourceDraft,
                                                hasFeedLocatorDraft:
                                                    _hasCatalogImportFeedLocatorDraft,
                                                hasSelectedArchive:
                                                    _selectedCatalogImportFile !=
                                                        null,
                                                saving:
                                                    _savingCatalogImportConfig,
                                                loading: _loadingQueues,
                                              ) ??
                                              '')
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          _coachCatalogImportSaveDisabledHintText(
                                            isArabic,
                                            scopedSourceRequired:
                                                _catalogImportConfigRequiresScopedSource,
                                            hasScopedSourceDraft:
                                                _hasCatalogImportScopedSourceDraft,
                                            hasFeedLocatorDraft:
                                                _hasCatalogImportFeedLocatorDraft,
                                            hasSelectedArchive:
                                                _selectedCatalogImportFile !=
                                                    null,
                                            saving: _savingCatalogImportConfig,
                                            loading: _loadingQueues,
                                          )!,
                                          key: const ValueKey(
                                            'coachOpsCatalogImportConfigSaveDisabledHint',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                        Text(
                          isArabic
                              ? 'أرشيفات مصادر الكتالوج'
                              : 'Catalog source artifacts',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_catalogSourceArtifacts != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_catalogSourceArtifacts!.generatedAtIso}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (_catalogSourceArtifacts == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              isArabic
                                  ? 'تعذر تحميل أرشيفات المصادر.'
                                  : 'Catalog source artifacts are unavailable.',
                            ),
                          )
                        else if (_catalogSourceArtifacts!.artifacts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              isArabic
                                  ? 'لا توجد أرشيفات GTFS مرفوعة بعد.'
                                  : 'No uploaded GTFS source artifacts yet.',
                            ),
                          )
                        else ...[
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _CoachOpsSummaryCard(
                                title: isArabic ? 'الأرشيفات' : 'Artifacts',
                                value:
                                    '${_catalogSourceArtifacts!.summary.totalArtifacts}',
                                subtitle: isArabic
                                    ? 'إجمالي الرفع: ${_catalogSourceArtifacts!.summary.uploadedBytesTotal} بايت'
                                    : 'Uploaded total: ${_catalogSourceArtifacts!.summary.uploadedBytesTotal} bytes',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._catalogSourceArtifacts!.artifacts.map(
                            (entry) => _CoachOpsCatalogSourceArtifactCard(
                              entry: entry,
                              viewingDetails:
                                  _loadingCatalogSourceArtifactDetailIds
                                      .contains(entry.artifactId),
                              runningImport: _runningCatalogImport,
                              catalogMutationsAllowed:
                                  _catalogImportMutationsAllowed,
                              readOnlyHintText: _catalogImportMutationsAllowed
                                  ? null
                                  : _coachCatalogSourceArtifactReadOnlyHintText(
                                      isArabic,
                                    ),
                              onViewDetails: () =>
                                  _showCatalogSourceArtifactDetails(entry),
                              onRunImport: !_catalogImportMutationsAllowed ||
                                      _runningCatalogImport ||
                                      _loadingQueues
                                  ? null
                                  : () => _triggerCatalogImportRun(
                                        sourceArtifactId: entry.artifactId,
                                        sourceLabel: entry.sourceLabel,
                                      ),
                            ),
                          ),
                          if ((_catalogSourceArtifactsCursor ?? '')
                              .trim()
                              .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  key: const ValueKey(
                                    'coachOpsCatalogSourceArtifactsLoadOlderButton',
                                  ),
                                  onPressed:
                                      _loadingMoreCatalogSourceArtifacts ||
                                              _loadingQueues
                                          ? null
                                          : _loadMoreCatalogSourceArtifacts,
                                  icon: _loadingMoreCatalogSourceArtifacts
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.unfold_more_outlined),
                                  label: Text(
                                    _loadingMoreCatalogSourceArtifacts
                                        ? 'Loading older artifacts...'
                                        : 'Load older artifacts',
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          isArabic
                              ? 'سجل استيراد الكتالوج'
                              : 'Catalog import runs',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_catalogImportRuns != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_catalogImportRuns!.generatedAtIso}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: 180,
                                child: DropdownButtonFormField<String>(
                                  key: const ValueKey(
                                    'coachOpsCatalogImportRunsStatusFilterField',
                                  ),
                                  initialValue:
                                      _selectedCatalogImportRunStatusFilter,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Run status',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: const <String>[
                                    'all',
                                    'failed',
                                    'running',
                                    'succeeded',
                                  ]
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _coachCatalogImportRunStatusFilterLabel(
                                              value,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _loadingQueues
                                      ? null
                                      : (value) {
                                          _updateCatalogImportRunFilters(
                                            statusFilter:
                                                (value ?? 'all').trim(),
                                          );
                                        },
                                ),
                              ),
                              SizedBox(
                                width: 180,
                                child: DropdownButtonFormField<String>(
                                  key: const ValueKey(
                                    'coachOpsCatalogImportRunsReplayScopeFilterField',
                                  ),
                                  initialValue:
                                      _selectedCatalogImportRunReplayScopeFilter,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Replay scope',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: const <String>[
                                    'all',
                                    'attention',
                                    'with_replays',
                                    'replays_only',
                                  ]
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _coachCatalogImportRunReplayScopeFilterLabel(
                                              value,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _loadingQueues
                                      ? null
                                      : (value) {
                                          _updateCatalogImportRunFilters(
                                            replayScopeFilter:
                                                (value ?? 'all').trim(),
                                          );
                                        },
                                ),
                              ),
                              SizedBox(
                                width: 180,
                                child: DropdownButtonFormField<String>(
                                  key: const ValueKey(
                                    'coachOpsCatalogImportRunsIssueSeverityFilterField',
                                  ),
                                  initialValue:
                                      _selectedCatalogImportRunIssueSeverityFilter,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Issue severity',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: _catalogImportRunSeverityFilterOptions
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _coachCatalogImportRunIssueSeverityFilterLabel(
                                              value,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _loadingQueues
                                      ? null
                                      : (value) {
                                          _updateCatalogImportRunFilters(
                                            issueSeverityFilter:
                                                (value ?? 'all').trim(),
                                          );
                                        },
                                ),
                              ),
                              SizedBox(
                                width: 180,
                                child: DropdownButtonFormField<String>(
                                  key: const ValueKey(
                                    'coachOpsCatalogImportRunsIssueStageFilterField',
                                  ),
                                  initialValue:
                                      _selectedCatalogImportRunIssueStageFilter,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Issue stage',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: _catalogImportRunStageFilterOptions
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _coachCatalogImportRunIssueStageFilterLabel(
                                              value,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _loadingQueues
                                      ? null
                                      : (value) {
                                          _updateCatalogImportRunFilters(
                                            issueStageFilter:
                                                (value ?? 'all').trim(),
                                          );
                                        },
                                ),
                              ),
                              if (_hasActiveCatalogImportRunFilters)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsClearFiltersButton',
                                    ),
                                    onPressed: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              statusFilter: 'all',
                                              replayScopeFilter: 'all',
                                              issueSeverityFilter: 'all',
                                              issueStageFilter: 'all',
                                            ),
                                    icon: const Icon(
                                        Icons.filter_alt_off_outlined),
                                    label: const Text('Clear filters'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_catalogImportRunIssuePresetErrorsAvailable ||
                            _catalogImportRunIssuePresetWarningsAvailable ||
                            _catalogImportRunIssuePresetLoadFeedAvailable ||
                            _hasActiveCatalogImportRunIssueFilters)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_catalogImportRunIssuePresetErrorsAvailable)
                                  OutlinedButton(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsIssuePresetErrorsButton',
                                    ),
                                    onPressed: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              issueSeverityFilter: 'error',
                                              issueStageFilter: 'all',
                                            ),
                                    child: const Text('Errors only'),
                                  ),
                                if (_catalogImportRunIssuePresetWarningsAvailable)
                                  OutlinedButton(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsIssuePresetWarningsButton',
                                    ),
                                    onPressed: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              issueSeverityFilter: 'warning',
                                              issueStageFilter: 'all',
                                            ),
                                    child: const Text('Warnings only'),
                                  ),
                                if (_catalogImportRunIssuePresetLoadFeedAvailable)
                                  OutlinedButton(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsIssuePresetLoadFeedButton',
                                    ),
                                    onPressed: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              issueSeverityFilter: 'all',
                                              issueStageFilter: 'load_feed',
                                            ),
                                    child: const Text('Load feed only'),
                                  ),
                                if (_hasActiveCatalogImportRunIssueFilters)
                                  OutlinedButton(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsClearIssueFiltersButton',
                                    ),
                                    onPressed: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              issueSeverityFilter: 'all',
                                              issueStageFilter: 'all',
                                            ),
                                    child: const Text('Clear issue filters'),
                                  ),
                              ],
                            ),
                          ),
                        if (_hasActiveCatalogImportRunFilters &&
                            _catalogImportRuns != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  key: const ValueKey(
                                    'coachOpsCatalogImportRunsFilteredCountChip',
                                  ),
                                  avatar: const Icon(
                                    Icons.filter_alt_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    isArabic
                                        ? 'النتائج المفلترة: ${_catalogImportRuns!.summary.totalRuns}'
                                        : 'Filtered runs: ${_catalogImportRuns!.summary.totalRuns}',
                                  ),
                                ),
                                if (_catalogImportRunStatusFilter != null)
                                  InputChip(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsStatusFilterChip',
                                    ),
                                    label: Text(
                                      _coachCatalogImportRunStatusFilterChipLabel(
                                        _selectedCatalogImportRunStatusFilter,
                                      ),
                                    ),
                                    onDeleted: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              statusFilter: 'all',
                                            ),
                                  ),
                                if (_catalogImportRunReplayScopeFilter != null)
                                  InputChip(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsReplayScopeFilterChip',
                                    ),
                                    label: Text(
                                      _coachCatalogImportRunReplayScopeFilterChipLabel(
                                        _selectedCatalogImportRunReplayScopeFilter,
                                      ),
                                    ),
                                    onDeleted: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              replayScopeFilter: 'all',
                                            ),
                                  ),
                                if (_catalogImportRunIssueSeverityFilter !=
                                    null)
                                  InputChip(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsIssueSeverityFilterChip',
                                    ),
                                    label: Text(
                                      _coachCatalogImportRunIssueSeverityFilterChipLabel(
                                        _selectedCatalogImportRunIssueSeverityFilter,
                                      ),
                                    ),
                                    onDeleted: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              issueSeverityFilter: 'all',
                                            ),
                                  ),
                                if (_catalogImportRunIssueStageFilter != null)
                                  InputChip(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsIssueStageFilterChip',
                                    ),
                                    label: Text(
                                      _coachCatalogImportRunIssueStageFilterChipLabel(
                                        _selectedCatalogImportRunIssueStageFilter,
                                      ),
                                    ),
                                    onDeleted: _loadingQueues
                                        ? null
                                        : () => _updateCatalogImportRunFilters(
                                              issueStageFilter: 'all',
                                            ),
                                  ),
                              ],
                            ),
                          ),
                        if (_catalogImportMutationsAllowed) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              _coachCatalogImportTriggerGuidanceText(
                                isArabic,
                                ready: _catalogImportConfigReady,
                                scopedSourceRequired:
                                    _catalogImportConfigRequiresScopedSource,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                key: const ValueKey(
                                    'coachOpsCatalogImportTriggerButton'),
                                onPressed: _runningCatalogImport ||
                                        _loadingQueues ||
                                        !_catalogImportConfigReady
                                    ? null
                                    : _triggerCatalogImportRun,
                                icon: _runningCatalogImport
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.sync_outlined),
                                label: Text(
                                  _runningCatalogImport
                                      ? 'Running configured GTFS import...'
                                      : 'Run configured GTFS import',
                                ),
                              ),
                            ),
                          ),
                          if ((_coachCatalogImportTriggerDisabledHintText(
                                    isArabic,
                                    ready: _catalogImportConfigReady,
                                    scopedSourceRequired:
                                        _catalogImportConfigRequiresScopedSource,
                                    running: _runningCatalogImport,
                                    loading: _loadingQueues,
                                  ) ??
                                  '')
                              .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _coachCatalogImportTriggerDisabledHintText(
                                  isArabic,
                                  ready: _catalogImportConfigReady,
                                  scopedSourceRequired:
                                      _catalogImportConfigRequiresScopedSource,
                                  running: _runningCatalogImport,
                                  loading: _loadingQueues,
                                )!,
                                key: const ValueKey(
                                  'coachOpsCatalogImportTriggerDisabledHint',
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                        if (_catalogImportRuns == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              isArabic
                                  ? 'تعذر تحميل سجل استيراد الكتالوج.'
                                  : 'Catalog import runs are unavailable.',
                            ),
                          )
                        else if (_catalogImportRuns!.importRuns.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              isArabic
                                  ? 'لا توجد عمليات استيراد كتالوج بعد.'
                                  : 'No catalog import runs yet.',
                            ),
                          )
                        else ...[
                          ..._catalogImportRuns!.importRuns.map(
                            (entry) => _CoachOpsCatalogImportRunCard(
                              entry: entry,
                              viewingDetails:
                                  _loadingCatalogImportRunDetailIds.contains(
                                entry.importRunId,
                              ),
                              readOnlyHintText: _catalogImportMutationsAllowed
                                  ? null
                                  : _coachCatalogImportRunReadOnlyHintText(
                                      isArabic,
                                      entry,
                                    ),
                              onViewDetails: () =>
                                  _showCatalogImportRunDetails(entry),
                            ),
                          ),
                          if ((_catalogImportRunsCursor ?? '')
                              .trim()
                              .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  key: const ValueKey(
                                    'coachOpsCatalogImportRunsLoadOlderButton',
                                  ),
                                  onPressed: _loadingMoreCatalogImportRuns ||
                                          _loadingQueues
                                      ? null
                                      : _loadMoreCatalogImportRuns,
                                  icon: _loadingMoreCatalogImportRuns
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.unfold_more_outlined),
                                  label: Text(
                                    _loadingMoreCatalogImportRuns
                                        ? 'Loading older catalog imports...'
                                        : 'Load older catalog imports',
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Saved views',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Personal views stay on your ops account. Shared views are visible to all coach ops accounts.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsSavedViewsVisibilityFilterField',
                                    ),
                                    initialValue:
                                        _catalogImportRunSavedViewsVisibilityFilter,
                                    decoration: const InputDecoration(
                                      labelText: 'Show saved views',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'all',
                                        child: Text('All scopes'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'personal',
                                        child: Text('Personal only'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'shared_ops',
                                        child: Text('Shared with ops only'),
                                      ),
                                    ],
                                    onChanged:
                                        _savingCatalogImportRunSavedView ||
                                                _loadingQueues
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                unawaited(
                                                  _reloadCatalogImportRunSavedViewsForFilters(
                                                    visibilityScope: value,
                                                    ownerAccountId: 'all',
                                                    operatorId: 'all',
                                                  ),
                                                );
                                              },
                                  ),
                                  if (_catalogImportRunSavedViewsVisibilityFilter ==
                                      'shared_ops') ...[
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'coachOpsCatalogImportRunsSavedViewsOwnerFilterField',
                                      ),
                                      initialValue:
                                          _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                      decoration: const InputDecoration(
                                        labelText: 'Shared view owner',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items:
                                          _catalogImportRunSavedViewOwnerAccountIdOptions(
                                        _catalogImportRunSavedViewOwners,
                                        _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                      ).map((value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _catalogSavedViewOwnerFilterOptionLabel(
                                              value,
                                              _catalogImportRunSavedViewOwners,
                                            ),
                                          ),
                                        );
                                      }).toList(growable: false),
                                      onChanged:
                                          _savingCatalogImportRunSavedView ||
                                                  _loadingQueues
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  unawaited(
                                                    _reloadCatalogImportRunSavedViewsForFilters(
                                                      visibilityScope:
                                                          _catalogImportRunSavedViewsVisibilityFilter,
                                                      ownerAccountId: value,
                                                      operatorId:
                                                          _catalogImportRunSavedViewsOperatorIdFilter,
                                                    ),
                                                  );
                                                },
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _catalogSavedViewOwnerFilterSummaryText(
                                        _catalogImportRunSavedViewOwners,
                                        _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'coachOpsCatalogImportRunsSavedViewsOperatorFilterField',
                                      ),
                                      initialValue:
                                          _catalogImportRunSavedViewsOperatorIdFilter,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Shared operator scope',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: _catalogSavedViewOperatorIdOptions(
                                        summaries:
                                            _catalogImportRunSavedViewOperators,
                                        selectedOperatorId:
                                            _catalogImportRunSavedViewsOperatorIdFilter,
                                      ).map((value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _catalogOperatorFilterOptionLabel(
                                              value,
                                              summaries:
                                                  _catalogImportRunSavedViewOperators,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(growable: false),
                                      onChanged:
                                          _savingCatalogImportRunSavedView ||
                                                  _loadingQueues
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  unawaited(
                                                    _reloadCatalogImportRunSavedViewsForFilters(
                                                      visibilityScope:
                                                          _catalogImportRunSavedViewsVisibilityFilter,
                                                      ownerAccountId:
                                                          _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                                      operatorId: value,
                                                    ),
                                                  );
                                                },
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _catalogOperatorFilterSummaryText(
                                        _catalogImportRunSavedViewsOperatorIdFilter,
                                        summaries:
                                            _catalogImportRunSavedViewOperators,
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  TextField(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsSavedViewNameField',
                                    ),
                                    controller:
                                        _catalogImportRunSavedViewNameController,
                                    enabled:
                                        !_savingCatalogImportRunSavedView &&
                                            !_loadingQueues,
                                    decoration: const InputDecoration(
                                      labelText: 'Saved view name',
                                      hintText:
                                          'Failed replays needing attention',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsCatalogImportRunsSavedViewScopeField',
                                    ),
                                    initialValue:
                                        _catalogImportRunSavedViewVisibilityScope,
                                    decoration: const InputDecoration(
                                      labelText: 'View scope',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'personal',
                                        child: Text('Personal'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'shared_ops',
                                        child: Text('Shared with ops'),
                                      ),
                                    ],
                                    onChanged:
                                        _savingCatalogImportRunSavedView ||
                                                _loadingQueues
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _catalogImportRunSavedViewVisibilityScope =
                                                      value;
                                                });
                                              },
                                  ),
                                  if (_catalogImportRunSavedViewVisibilityScope ==
                                      'shared_ops') ...[
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'coachOpsCatalogImportRunsSavedViewOperatorScopeField',
                                      ),
                                      initialValue:
                                          _catalogImportRunSavedViewOperatorIdScope,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Shared operator scope',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: _catalogSavedViewOperatorIdOptions(
                                        summaries:
                                            _catalogImportRunSavedViewOperators,
                                        selectedOperatorId:
                                            _catalogImportRunSavedViewOperatorIdScope,
                                      ).map((value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _catalogOperatorFilterOptionLabel(
                                              value,
                                              summaries:
                                                  _catalogImportRunSavedViewOperators,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(growable: false),
                                      onChanged:
                                          _savingCatalogImportRunSavedView ||
                                                  _loadingQueues
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _catalogImportRunSavedViewOperatorIdScope =
                                                        _normalizeCatalogSavedViewOperatorIdFilter(
                                                      value,
                                                    );
                                                  });
                                                },
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _catalogOperatorFilterSummaryText(
                                        _catalogImportRunSavedViewOperatorIdScope,
                                        summaries:
                                            _catalogImportRunSavedViewOperators,
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'coachOpsCatalogImportRunsSaveViewButton',
                                        ),
                                        onPressed:
                                            _savingCatalogImportRunSavedView ||
                                                    _loadingQueues
                                                ? null
                                                : _saveCatalogImportRunSavedView,
                                        icon: _savingCatalogImportRunSavedView
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.bookmark_add_outlined),
                                        label: Text(
                                          _savingCatalogImportRunSavedView
                                              ? 'Saving view...'
                                              : 'Save view',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (recentCatalogImportRunSavedViews
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Recent views',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          recentCatalogImportRunSavedViews.map((
                                        view,
                                      ) {
                                        final isCurrent =
                                            _catalogImportRunSavedViewIsCurrent(
                                                view);
                                        return ActionChip(
                                          key: ValueKey(
                                            'coachOpsCatalogImportRunsRecentSavedView_${view.viewId}',
                                          ),
                                          avatar: const Icon(
                                            Icons.history,
                                            size: 18,
                                          ),
                                          label: Text(view.name),
                                          onPressed: _loadingQueues || isCurrent
                                              ? null
                                              : () =>
                                                  _applyCatalogImportRunSavedView(
                                                      view),
                                        );
                                      }).toList(growable: false),
                                    ),
                                  ],
                                  if (_catalogImportRunSavedViews.isEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'No saved views yet.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 10),
                                    ...rankedCatalogImportRunSavedViews.map(
                                      (view) {
                                        final isPinnedView = _savedViewIsPinned(
                                          _catalogImportRunSavedViewPinnedIds,
                                          view.viewId,
                                        );
                                        return Container(
                                          width: double.infinity,
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    view.name,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                  Chip(
                                                    label: Text(
                                                      _catalogSavedViewVisibilityScopeLabel(
                                                        view.visibilityScope,
                                                      ),
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  if (view.isDefault)
                                                    Chip(
                                                      label: const Text(
                                                          'Default view'),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                  if (isPinnedView)
                                                    Chip(
                                                      label:
                                                          const Text('Pinned'),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              if (_catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  ) !=
                                                  null)
                                                Text(
                                                  _catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  )!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              if (_catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  ) !=
                                                  null)
                                                const SizedBox(height: 4),
                                              if (_catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  ) !=
                                                  null)
                                                Text(
                                                  _catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  )!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              if (_catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  ) !=
                                                  null)
                                                const SizedBox(height: 4),
                                              if (view.visibilityScope ==
                                                  'shared_ops')
                                                Text(
                                                  'Operator scope: ${_coachFormatCatalogOperatorScope(view.operatorIds)}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              if (view.visibilityScope ==
                                                  'shared_ops')
                                                const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children:
                                                    _catalogImportRunSavedViewContentChipLabels(
                                                  view.preferences,
                                                ).map((label) {
                                                  return Chip(
                                                    label: Text(label),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  );
                                                }).toList(growable: false),
                                              ),
                                              if (_catalogSavedViewActiveChipLabels(
                                                    selectedVisibilityScope:
                                                        _catalogImportRunSavedViewsVisibilityFilter,
                                                    viewVisibilityScope:
                                                        view.visibilityScope,
                                                    viewAccountId:
                                                        view.accountId,
                                                    selectedOwnerAccountId:
                                                        _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                                    operatorIds:
                                                        view.operatorIds,
                                                    selectedOperatorId:
                                                        _catalogImportRunSavedViewsOperatorIdFilter,
                                                  ).isNotEmpty ||
                                                  _catalogImportRunSavedViewIsCurrent(
                                                    view,
                                                  ) ||
                                                  _savedViewRecentlyUsedChipLabel(
                                                        _catalogImportRunSavedViewUsedAtById[
                                                            view.viewId],
                                                      ) !=
                                                      null)
                                                const SizedBox(height: 6),
                                              if (_catalogSavedViewActiveChipLabels(
                                                    selectedVisibilityScope:
                                                        _catalogImportRunSavedViewsVisibilityFilter,
                                                    viewVisibilityScope:
                                                        view.visibilityScope,
                                                    viewAccountId:
                                                        view.accountId,
                                                    selectedOwnerAccountId:
                                                        _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                                    operatorIds:
                                                        view.operatorIds,
                                                    selectedOperatorId:
                                                        _catalogImportRunSavedViewsOperatorIdFilter,
                                                  ).isNotEmpty ||
                                                  _catalogImportRunSavedViewIsCurrent(
                                                    view,
                                                  ) ||
                                                  _savedViewRecentlyUsedChipLabel(
                                                        _catalogImportRunSavedViewUsedAtById[
                                                            view.viewId],
                                                      ) !=
                                                      null)
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    ..._catalogSavedViewActiveChipLabels(
                                                      selectedVisibilityScope:
                                                          _catalogImportRunSavedViewsVisibilityFilter,
                                                      viewVisibilityScope:
                                                          view.visibilityScope,
                                                      viewAccountId:
                                                          view.accountId,
                                                      selectedOwnerAccountId:
                                                          _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                                      operatorIds:
                                                          view.operatorIds,
                                                      selectedOperatorId:
                                                          _catalogImportRunSavedViewsOperatorIdFilter,
                                                    ).map((label) {
                                                      return Chip(
                                                        label: Text(label),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      );
                                                    }),
                                                    if (_catalogImportRunSavedViewIsCurrent(
                                                      view,
                                                    ))
                                                      const Chip(
                                                        label: Text(
                                                            'Using this view'),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    if (_savedViewRecentlyUsedChipLabel(
                                                          _catalogImportRunSavedViewUsedAtById[
                                                              view.viewId],
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _savedViewRecentlyUsedChipLabel(
                                                            _catalogImportRunSavedViewUsedAtById[
                                                                view.viewId],
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                  ],
                                                ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _describeCatalogImportRunFilterPreferences(
                                                  view.preferences,
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Updated ${view.updatedAtIso}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 8,
                                                children: [
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsCatalogImportRunsApplySavedView_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues ||
                                                            _catalogImportRunSavedViewIsCurrent(
                                                              view,
                                                            )
                                                        ? null
                                                        : () =>
                                                            _applyCatalogImportRunSavedView(
                                                              view,
                                                            ),
                                                    icon: const Icon(
                                                      Icons
                                                          .bookmark_added_outlined,
                                                    ),
                                                    label: Text(
                                                      _catalogImportRunSavedViewIsCurrent(
                                                        view,
                                                      )
                                                          ? 'View already active'
                                                          : 'Apply view',
                                                    ),
                                                  ),
                                                  OutlinedButton(
                                                    key: ValueKey(
                                                      'coachOpsCatalogImportRunsTogglePinnedSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues
                                                        ? null
                                                        : () =>
                                                            _toggleCatalogImportRunSavedViewFavorite(
                                                              viewId:
                                                                  view.viewId,
                                                              favorite:
                                                                  !isPinnedView,
                                                            ),
                                                    child: Text(
                                                      isPinnedView
                                                          ? 'Unpin view'
                                                          : 'Pin view',
                                                    ),
                                                  ),
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsCatalogImportRunsFilterByOwner_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues ||
                                                            view.visibilityScope !=
                                                                'shared_ops' ||
                                                            view.accountId
                                                                .trim()
                                                                .isEmpty ||
                                                            _catalogSavedViewMatchesOwnerFilter(
                                                              view.visibilityScope,
                                                              view.accountId,
                                                              _catalogImportRunSavedViewsVisibilityFilter,
                                                              _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                                            )
                                                        ? null
                                                        : () => unawaited(
                                                              _reloadCatalogImportRunSavedViewsForFilters(
                                                                visibilityScope:
                                                                    'shared_ops',
                                                                ownerAccountId:
                                                                    view.accountId,
                                                                operatorId:
                                                                    _catalogImportRunSavedViewsOperatorIdFilter,
                                                              ),
                                                            ),
                                                    icon: const Icon(Icons
                                                        .filter_alt_outlined),
                                                    label: const Text(
                                                        'Filter by owner'),
                                                  ),
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsCatalogImportRunsFilterByOperator_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues ||
                                                            view.visibilityScope !=
                                                                'shared_ops' ||
                                                            view.operatorIds
                                                                    .length !=
                                                                1 ||
                                                            _catalogSavedViewMatchesOperatorFilter(
                                                              view.operatorIds,
                                                              _catalogImportRunSavedViewsOperatorIdFilter,
                                                            )
                                                        ? null
                                                        : () => unawaited(
                                                              _reloadCatalogImportRunSavedViewsForFilters(
                                                                visibilityScope:
                                                                    'shared_ops',
                                                                ownerAccountId:
                                                                    _catalogImportRunSavedViewsOwnerAccountIdFilter,
                                                                operatorId: view
                                                                    .operatorIds
                                                                    .single,
                                                              ),
                                                            ),
                                                    icon: const Icon(
                                                      Icons
                                                          .directions_bus_outlined,
                                                    ),
                                                    label: const Text(
                                                        'Filter by operator'),
                                                  ),
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsCatalogImportRunsToggleDefaultSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: view.visibilityScope !=
                                                                'personal' ||
                                                            _loadingQueues ||
                                                            _updatingCatalogImportRunSavedViewDefaultIds
                                                                .contains(
                                                                    view.viewId)
                                                        ? null
                                                        : () =>
                                                            _toggleCatalogImportRunSavedViewDefault(
                                                              view,
                                                            ),
                                                    icon:
                                                        _updatingCatalogImportRunSavedViewDefaultIds
                                                                .contains(
                                                                    view.viewId)
                                                            ? const SizedBox(
                                                                width: 14,
                                                                height: 14,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                              )
                                                            : Icon(
                                                                view.isDefault
                                                                    ? Icons
                                                                        .bookmark_remove_outlined
                                                                    : Icons
                                                                        .bookmark_border,
                                                              ),
                                                    label: Text(
                                                      view.isDefault
                                                          ? 'Clear default'
                                                          : 'Set default',
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsCatalogImportRunsDeleteSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: !view
                                                                .canManage ||
                                                            _deletingCatalogImportRunSavedViewIds
                                                                .contains(view
                                                                    .viewId) ||
                                                            _loadingQueues
                                                        ? null
                                                        : () =>
                                                            _deleteCatalogImportRunSavedView(
                                                              view,
                                                            ),
                                                    icon:
                                                        _deletingCatalogImportRunSavedViewIds
                                                                .contains(
                                                                    view.viewId)
                                                            ? const SizedBox(
                                                                width: 14,
                                                                height: 14,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                              )
                                                            : const Icon(
                                                                Icons
                                                                    .delete_outline,
                                                              ),
                                                    label: const Text(
                                                        'Delete view'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (showSettlementsExecutionSection)
                  ...portalSection(
                    section: settlementsPortalSection,
                    segmentId: 'execution',
                    subtitle:
                        'Batch execution, settlement statements, and payout run handling after audit is complete.',
                    sectionKey: _settlementsExecutionSectionKey,
                    children: [
                      ...workspaceDesk(
                        workspace: payoutOpsWorkspace,
                        segmentId: 'batches',
                        showHeader: false,
                        children: [
                          Container(
                            key: _payoutImportBatchesSectionKey,
                            child: Text(
                              isArabic
                                  ? 'دفعات مجمعة'
                                  : 'Payout import batches',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_payoutImportBatches != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_payoutImportBatches!.generatedAtIso}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isArabic
                                        ? 'تحميل تقرير دفعات CSV'
                                        : 'Upload CSV payout report',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        (_payoutImportProfiles?.profiles.any(
                                                  (profile) =>
                                                      profile.importSource ==
                                                      _selectedPayoutImportSource,
                                                ) ??
                                                false)
                                            ? _selectedPayoutImportSource
                                            : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Import source',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: (_payoutImportProfiles?.profiles ??
                                            const <CoachOperatorPayoutImportProfile>[])
                                        .map(
                                          (profile) => DropdownMenuItem<String>(
                                            value: profile.importSource,
                                            child: Text(profile.title),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: _creatingImportBatch
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              _setSelectedPayoutImportSource(
                                                  value);
                                            }
                                          },
                                  ),
                                  if (_selectedPayoutImportProfile != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _selectedPayoutImportProfile!.summary,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (_selectedPayoutImportProfile!
                                        .supportedDelimiters.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Supported delimiters: ${_selectedPayoutImportProfile!.supportedDelimiters.join(', ')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    if (_selectedPayoutImportProfile!
                                        .statusMappings.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      ..._selectedPayoutImportProfile!
                                          .statusMappings
                                          .map(
                                        (mapping) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            mapping.requiredFields.isEmpty
                                                ? '${_coachPayoutImportStatusLabel(mapping.normalizedStatus)}: ${mapping.acceptedValues.join(' / ')}'
                                                : '${_coachPayoutImportStatusLabel(mapping.normalizedStatus)}: ${mapping.acceptedValues.join(' / ')} • requires ${mapping.requiredFields.join(', ')}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          _selectedPayoutImportProfile!.fields
                                              .map(
                                                (field) => Chip(
                                                  label: Text(
                                                    '${field.key}${field.required ? ' *' : ''}: ${field.acceptedHeaders.join(' / ')}',
                                                  ),
                                                ),
                                              )
                                              .toList(growable: false),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: _creatingImportBatch ||
                                                _loadingReworkSeed
                                            ? null
                                            : _loadSelectedPayoutImportProfileSample,
                                        icon: const Icon(
                                            Icons.auto_fix_high_outlined),
                                        label: const Text('Load CSV template'),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller:
                                        _payoutImportReportNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Report name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  if (_eligibleReworkSourceBatches
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String?>(
                                      key: const ValueKey(
                                        'coachOpsPayoutImportReworkSourceDropdown',
                                      ),
                                      initialValue:
                                          _selectedPayoutImportReworkOfBatchId,
                                      decoration: const InputDecoration(
                                        labelText: 'Rework source batch',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: <DropdownMenuItem<String?>>[
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child:
                                              Text('No linked rework source'),
                                        ),
                                        ..._eligibleReworkSourceBatches.map(
                                          (batch) => DropdownMenuItem<String?>(
                                            value: batch.batchId,
                                            child: Text(
                                              '${batch.batchId} • ${batch.failedRows} failed',
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: !_financeMutationsAllowed ||
                                              _creatingImportBatch ||
                                              _previewingImportBatch ||
                                              _loadingReworkSeed
                                          ? null
                                          : (value) {
                                              unawaited(
                                                _setSelectedPayoutImportReworkSourceBatch(
                                                  value,
                                                ),
                                              );
                                            },
                                    ),
                                    if (_selectedReworkSourceBatch != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Linked rework source: ${_selectedReworkSourceBatch!.batchId}'
                                        ' • ${_selectedReworkSourceBatch!.reportName}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      if (_selectedReworkDraftDelta !=
                                          null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _selectedReworkDraftDelta!.isModified
                                              ? 'Draft differs from seeded rework CSV.'
                                              : 'Draft matches the seeded rework CSV.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Seed rows: ${_selectedReworkDraftDelta!.seedRowCount} • '
                                          'Draft rows: ${_selectedReworkDraftDelta!.draftRowCount} • '
                                          'Original failed rows: ${_selectedReworkDraftDelta!.originalFailedRows}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        if (_selectedReworkDraftDelta!
                                                .remainingFailedRowsEstimate >
                                            0) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Remaining gap to original failures: ${_selectedReworkDraftDelta!.remainingFailedRowsEstimate}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                        if (_selectedReworkDraftDelta!
                                                .additionalRows >
                                            0) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Additional rows beyond seed: ${_selectedReworkDraftDelta!.additionalRows}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                        if (_selectedReworkDraftDelta!
                                            .affectedPayoutRunIds
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Affected payout runs: ${_selectedReworkDraftDelta!.affectedPayoutRunIds.join(', ')}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ],
                                      if (_selectedReworkSourceBatch!
                                          .followUpBatchIds.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Existing follow-ups: ${_selectedReworkSourceBatch!.followUpBatchIds.join(' -> ')}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                      if (_loadingReworkSeed) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Loading linked rework CSV...',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ],
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: !_financeMutationsAllowed ||
                                                _creatingImportBatch ||
                                                _previewingImportBatch ||
                                                _loadingReworkSeed
                                            ? null
                                            : _selectPayoutImportFile,
                                        icon: const Icon(
                                            Icons.attach_file_outlined),
                                        label: Text(
                                          _selectedPayoutImportFile == null
                                              ? 'Select CSV file'
                                              : 'Replace CSV file',
                                        ),
                                      ),
                                      if (_selectedPayoutImportFile != null)
                                        TextButton.icon(
                                          onPressed: _creatingImportBatch ||
                                                  _previewingImportBatch ||
                                                  _loadingReworkSeed
                                              ? null
                                              : _clearSelectedPayoutImportFile,
                                          icon:
                                              const Icon(Icons.clear_outlined),
                                          label: const Text('Clear file'),
                                        ),
                                    ],
                                  ),
                                  if (_selectedPayoutImportFile != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Selected file: ${_selectedPayoutImportFile!.fileName} (${_selectedPayoutImportFile!.bytes.length} bytes)',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller:
                                        _payoutImportReportBodyController,
                                    minLines: 5,
                                    maxLines: 8,
                                    decoration: InputDecoration(
                                      labelText: 'CSV report body',
                                      helperText: _selectedPayoutImportFile ==
                                              null
                                          ? 'Paste the CSV body from the selected bank, PSP or normalized finance report.'
                                          : 'A selected file will be uploaded. Clear the file to use the pasted CSV body instead.',
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                  if (_payoutImportDraftValidation != null) ...[
                                    const SizedBox(height: 12),
                                    if (_payoutImportDraftValidation!.isValid)
                                      StatusBanner.success(
                                        'Validation ready: ${_payoutImportDraftValidation!.totalRows} rows parsed with no local issues.',
                                        dense: true,
                                      )
                                    else
                                      StatusBanner.warning(
                                        'Validation issues: ${_payoutImportDraftValidation!.issueCount} across ${_payoutImportDraftValidation!.affectedRowCount} rows.',
                                        dense: true,
                                      ),
                                    if (_payoutImportDraftValidation!
                                        .headerIssues.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      ..._payoutImportDraftValidation!
                                          .headerIssues
                                          .take(3)
                                          .map(
                                            (issue) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 2),
                                              child: Text(
                                                'Header: $issue',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ),
                                          ),
                                    ],
                                    if (_payoutImportDraftValidation!
                                        .rowIssues.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      ..._payoutImportDraftValidation!.rowIssues
                                          .take(5)
                                          .map(
                                            (issue) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 2),
                                              child: Text(
                                                issue.lineNumber == null
                                                    ? issue.message
                                                    : 'Line ${issue.lineNumber}: ${issue.message}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ),
                                          ),
                                    ],
                                    if ((_payoutImportDraftAutoFix
                                            ?.hasChanges ??
                                        false)) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _creatingImportBatch ||
                                                    _previewingImportBatch ||
                                                    _loadingReworkSeed
                                                ? null
                                                : _applySuggestedPayoutImportFixes,
                                            icon: const Icon(
                                                Icons.auto_fix_high_outlined),
                                            label: const Text(
                                                'Apply suggested fixes'),
                                          ),
                                          Text(
                                            '${_payoutImportDraftAutoFix!.headerFixCount} header fixes • ${_payoutImportDraftAutoFix!.statusFixCount} status fixes',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (_payoutImportDraftValidation!
                                        .correctionHints.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        'Correction help',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 6),
                                      ..._payoutImportDraftValidation!
                                          .correctionHints
                                          .take(3)
                                          .map(
                                            (issue) => Container(
                                              width: double.infinity,
                                              margin: const EdgeInsets.only(
                                                  bottom: 8),
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    issue.lineNumber == null
                                                        ? issue.fieldKey
                                                        : 'Line ${issue.lineNumber} • ${issue.fieldKey}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    issue.message,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                                  if ((issue.currentValue ?? '')
                                                      .trim()
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Current value: ${issue.currentValue}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall,
                                                    ),
                                                  ],
                                                  if ((issue.suggestion ?? '')
                                                      .trim()
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Suggested fix: ${issue.suggestion}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                    ],
                                    if (!_payoutImportDraftValidation!
                                        .isValid) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Preview can still run, but Apply stays blocked until local issues are resolved.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: !_financeMutationsAllowed ||
                                                _creatingImportBatch ||
                                                _previewingImportBatch ||
                                                _loadingReworkSeed
                                            ? null
                                            : () => _applyPayoutImportBatch(
                                                dryRun: true),
                                        icon: _previewingImportBatch
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(
                                                Icons.visibility_outlined),
                                        label: Text(
                                          _previewingImportBatch
                                              ? 'Previewing report...'
                                              : 'Preview report',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: !_financeMutationsAllowed ||
                                                _creatingImportBatch ||
                                                _previewingImportBatch ||
                                                _loadingReworkSeed ||
                                                _hasBlockingPayoutImportValidationIssues ||
                                                _latestFreshPayoutImportPreviewEcho ==
                                                    null
                                            ? null
                                            : () => _applyPayoutImportBatch(
                                                dryRun: false),
                                        icon: _creatingImportBatch
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(
                                                Icons.upload_file_outlined),
                                        label: Text(
                                          _creatingImportBatch
                                              ? 'Processing report...'
                                              : 'Apply payout report',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_latestFreshPayoutImportPreviewEcho ==
                                      null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Run Preview report on the current draft before Apply is enabled.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  if (_latestPayoutImportBatchResult !=
                                      null) ...[
                                    const SizedBox(height: 12),
                                    _CoachOpsPayoutImportBatchResultCard(
                                      result: _latestPayoutImportBatchResult!,
                                      localValidation:
                                          _payoutImportDraftValidation,
                                      localAutoFix: _payoutImportDraftAutoFix,
                                      currentDraftChecksumSha256:
                                          _currentPayoutImportDraftChecksumSha256,
                                      resolveReportUrl:
                                          _resolvePayoutImportReportUrl,
                                      financeMutationsAllowed:
                                          _financeMutationsAllowed,
                                      invalidatingPreview:
                                          _latestPayoutImportBatchResult!
                                                      .previewEcho?.previewToken
                                                      .trim()
                                                      .isNotEmpty ==
                                                  true &&
                                              _invalidatingPreviewTokens
                                                  .contains(
                                                _latestPayoutImportBatchResult!
                                                    .previewEcho!.previewToken,
                                              ),
                                      onInvalidatePreview:
                                          _latestPayoutImportBatchResult!
                                                          .previewEcho ==
                                                      null ||
                                                  !_latestPayoutImportBatchResult!
                                                      .previewEcho!
                                                      .isUsableAt(DateTime.now()
                                                          .toUtc())
                                              ? null
                                              : () =>
                                                  _invalidatePayoutImportPreview(
                                                    _latestPayoutImportBatchResult!
                                                        .previewEcho!
                                                        .previewToken,
                                                  ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (_payoutImportBatches != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      SizedBox(
                                        width: 220,
                                        child: DropdownButtonFormField<String>(
                                          key: const ValueKey(
                                            'coachOpsPayoutImportBatchesOperatorFilterField',
                                          ),
                                          initialValue:
                                              _selectedPayoutImportBatchOperatorIdFilter,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Operator scope',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items:
                                              _payoutImportBatchOperatorFilterOptions
                                                  .map(
                                                    (operatorId) =>
                                                        DropdownMenuItem<
                                                            String>(
                                                      value: operatorId,
                                                      child: Text(
                                                        operatorId == 'all'
                                                            ? 'All operators'
                                                            : operatorId,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(growable: false),
                                          onChanged: _loadingQueues ||
                                                  _loadingMorePayoutImportBatches
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  final normalizedValue =
                                                      _normalizePayoutImportOperatorIdFilterValue(
                                                    value,
                                                  );
                                                  setState(() {
                                                    _selectedPayoutImportBatchOperatorIdFilter =
                                                        normalizedValue;
                                                  });
                                                  unawaited(
                                                    _persistPayoutImportBatchOperatorFilterSelection(
                                                      normalizedValue,
                                                    ),
                                                  );
                                                },
                                        ),
                                      ),
                                      if (_payoutImportBatchOperatorIdFilter !=
                                              null ||
                                          _payoutImportBatches!
                                                  .batches.length !=
                                              visiblePayoutImportBatches.length)
                                        Chip(
                                          key: const ValueKey(
                                            'coachOpsPayoutImportBatchesFilteredCountChip',
                                          ),
                                          avatar: const Icon(
                                            Icons.filter_alt_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            isArabic
                                                ? 'المعروض: ${visiblePayoutImportBatches.length} من ${_payoutImportBatches!.batches.length}'
                                                : 'Shown: ${visiblePayoutImportBatches.length} of ${_payoutImportBatches!.batches.length}',
                                          ),
                                        ),
                                      if (_payoutImportBatchOperatorIdFilter !=
                                          null)
                                        InputChip(
                                          key: const ValueKey(
                                            'coachOpsPayoutImportBatchesOperatorFilterChip',
                                          ),
                                          label: Text(
                                            'Operator: ${_payoutImportBatchOperatorIdFilter!}',
                                          ),
                                          onDeleted: _loadingQueues ||
                                                  _loadingMorePayoutImportBatches
                                              ? null
                                              : () {
                                                  setState(() {
                                                    _selectedPayoutImportBatchOperatorIdFilter =
                                                        'all';
                                                  });
                                                  unawaited(
                                                    _persistPayoutImportBatchOperatorFilterSelection(
                                                      'all',
                                                    ),
                                                  );
                                                },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Saved views',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Personal views stay on your finance account. Shared views are visible to all coach ops accounts when the API is available.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsPayoutImportBatchesSavedViewsVisibilityFilterField',
                                    ),
                                    initialValue:
                                        _payoutImportBatchSavedViewsVisibilityFilter,
                                    decoration: const InputDecoration(
                                      labelText: 'Show saved views',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'all',
                                        child: Text('All scopes'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'personal',
                                        child: Text('Personal only'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'shared_ops',
                                        child: Text('Shared with ops only'),
                                      ),
                                    ],
                                    onChanged:
                                        _savingPayoutImportBatchSavedView ||
                                                _loadingQueues ||
                                                _loadingMorePayoutImportBatches
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _payoutImportBatchSavedViewsVisibilityFilter =
                                                      _normalizeCatalogSavedViewVisibilityFilter(
                                                    value,
                                                  );
                                                });
                                              },
                                  ),
                                  if (_payoutImportBatchSavedViewsVisibilityFilter ==
                                      'shared_ops') ...[
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'coachOpsPayoutImportBatchesSavedViewsOwnerFilterField',
                                      ),
                                      initialValue:
                                          _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                      decoration: const InputDecoration(
                                        labelText: 'Shared view owner',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items:
                                          _catalogImportRunSavedViewOwnerAccountIdOptions(
                                        _payoutImportBatchSavedViewOwners,
                                        _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                      ).map((value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _catalogSavedViewOwnerFilterOptionLabel(
                                              value,
                                              _payoutImportBatchSavedViewOwners,
                                            ),
                                          ),
                                        );
                                      }).toList(growable: false),
                                      onChanged:
                                          _savingPayoutImportBatchSavedView ||
                                                  _loadingQueues ||
                                                  _loadingMorePayoutImportBatches
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _payoutImportBatchSavedViewsOwnerAccountIdFilter =
                                                        _normalizeCatalogSavedViewOwnerAccountIdFilter(
                                                      value,
                                                    );
                                                  });
                                                },
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _catalogSavedViewOwnerFilterSummaryText(
                                        _payoutImportBatchSavedViewOwners,
                                        _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'coachOpsPayoutImportBatchesSavedViewsOperatorFilterField',
                                      ),
                                      initialValue:
                                          _payoutImportBatchSavedViewsOperatorIdFilter,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Shared operator scope',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: _catalogSavedViewOperatorIdOptions(
                                        summaries:
                                            _payoutImportBatchSavedViewOperators,
                                        selectedOperatorId:
                                            _payoutImportBatchSavedViewsOperatorIdFilter,
                                      ).map((value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            _catalogOperatorFilterOptionLabel(
                                              value,
                                              summaries:
                                                  _payoutImportBatchSavedViewOperators,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(growable: false),
                                      onChanged:
                                          _savingPayoutImportBatchSavedView ||
                                                  _loadingQueues ||
                                                  _loadingMorePayoutImportBatches
                                              ? null
                                              : (value) {
                                                  if (value == null) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _payoutImportBatchSavedViewsOperatorIdFilter =
                                                        _normalizePayoutImportOperatorIdFilterValue(
                                                      value,
                                                    );
                                                  });
                                                },
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _catalogOperatorFilterSummaryText(
                                        _payoutImportBatchSavedViewsOperatorIdFilter,
                                        summaries:
                                            _payoutImportBatchSavedViewOperators,
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  if (_payoutImportBatchSavedViewsVisibilityFilter !=
                                          'all' ||
                                      _payoutImportBatchSavedViews.length !=
                                          visiblePayoutImportBatchSavedViews
                                              .length) ...[
                                    const SizedBox(height: 8),
                                    Chip(
                                      key: const ValueKey(
                                        'coachOpsPayoutImportBatchesSavedViewsFilteredCountChip',
                                      ),
                                      avatar: const Icon(
                                        Icons.filter_alt_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'Shown: ${visiblePayoutImportBatchSavedViews.length} of ${_payoutImportBatchSavedViews.length}',
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  TextField(
                                    key: const ValueKey(
                                      'coachOpsPayoutImportBatchesSavedViewNameField',
                                    ),
                                    controller:
                                        _payoutImportBatchSavedViewNameController,
                                    enabled:
                                        !_savingPayoutImportBatchSavedView &&
                                            !_loadingQueues &&
                                            !_loadingMorePayoutImportBatches,
                                    decoration: const InputDecoration(
                                      labelText: 'Saved view name',
                                      hintText: 'April payout batches',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: const ValueKey(
                                      'coachOpsPayoutImportBatchesSavedViewScopeField',
                                    ),
                                    initialValue:
                                        _payoutImportBatchSavedViewVisibilityScope,
                                    decoration: const InputDecoration(
                                      labelText: 'View scope',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'personal',
                                        child: Text('Personal'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'shared_ops',
                                        child: Text('Shared with ops'),
                                      ),
                                    ],
                                    onChanged:
                                        _savingPayoutImportBatchSavedView ||
                                                _loadingQueues ||
                                                _loadingMorePayoutImportBatches
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _payoutImportBatchSavedViewVisibilityScope =
                                                      value;
                                                });
                                              },
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'coachOpsPayoutImportBatchesSaveViewButton',
                                        ),
                                        onPressed:
                                            _savingPayoutImportBatchSavedView ||
                                                    _loadingQueues ||
                                                    _loadingMorePayoutImportBatches
                                                ? null
                                                : _savePayoutImportBatchSavedView,
                                        icon: _savingPayoutImportBatchSavedView
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.bookmark_add_outlined),
                                        label: Text(
                                          _savingPayoutImportBatchSavedView
                                              ? 'Saving view...'
                                              : 'Save view',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (recentPayoutImportBatchSavedViews
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Recent views',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          recentPayoutImportBatchSavedViews
                                              .map((
                                        view,
                                      ) {
                                        final isCurrent =
                                            _payoutImportBatchSavedViewIsCurrent(
                                                view);
                                        return ActionChip(
                                          key: ValueKey(
                                            'coachOpsPayoutImportBatchesRecentSavedView_${view.viewId}',
                                          ),
                                          avatar: const Icon(
                                            Icons.history,
                                            size: 18,
                                          ),
                                          label: Text(view.name),
                                          onPressed: _loadingQueues ||
                                                  _loadingMorePayoutImportBatches ||
                                                  isCurrent
                                              ? null
                                              : () =>
                                                  _applyPayoutImportBatchSavedView(
                                                      view),
                                        );
                                      }).toList(growable: false),
                                    ),
                                  ],
                                  if (visiblePayoutImportBatchSavedViews
                                      .isEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _payoutImportBatchSavedViews.isEmpty
                                          ? 'No saved views yet.'
                                          : (_payoutImportBatchSavedViewsVisibilityFilter ==
                                                      'shared_ops' &&
                                                  (_normalizeCatalogSavedViewOwnerAccountIdFilter(
                                                            _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                                          ) !=
                                                          'all' ||
                                                      _normalizePayoutImportOperatorIdFilterValue(
                                                            _payoutImportBatchSavedViewsOperatorIdFilter,
                                                          ) !=
                                                          'all'))
                                              ? 'No saved views match the active scope and owner filters.'
                                              : 'No saved views match the active scope filter.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 10),
                                    ...visiblePayoutImportBatchSavedViews.map(
                                      (view) {
                                        final isPinnedView = _savedViewIsPinned(
                                          _payoutImportBatchSavedViewPinnedIds,
                                          view.viewId,
                                        );
                                        return Container(
                                          width: double.infinity,
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    view.name,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                  Chip(
                                                    label: Text(
                                                      _catalogSavedViewVisibilityScopeLabel(
                                                        view.visibilityScope,
                                                      ),
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  if (view.isDefault)
                                                    Chip(
                                                      label: const Text(
                                                          'Default view'),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                  if (isPinnedView)
                                                    Chip(
                                                      label:
                                                          const Text('Pinned'),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                ],
                                              ),
                                              if (view.visibilityScope ==
                                                  'shared_ops') ...[
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    if (_payoutSavedViewOwnerChipLabel(
                                                          view.visibilityScope,
                                                          view.accountId,
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _payoutSavedViewOwnerChipLabel(
                                                            view.visibilityScope,
                                                            view.accountId,
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    if (_payoutSavedViewOperatorChipLabel(
                                                          view.preferences
                                                              .operatorId,
                                                          summaries:
                                                              _payoutImportBatchSavedViewOperators,
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _payoutSavedViewOperatorChipLabel(
                                                            view.preferences
                                                                .operatorId,
                                                            summaries:
                                                                _payoutImportBatchSavedViewOperators,
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    if (_payoutSavedViewReadOnlyChipLabel(
                                                          view.visibilityScope,
                                                          view.canManage,
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _payoutSavedViewReadOnlyChipLabel(
                                                            view.visibilityScope,
                                                            view.canManage,
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                  ],
                                                ),
                                              ],
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: [
                                                  Chip(
                                                    label: Text(
                                                      _payoutImportBatchSavedViewContentChipLabel(
                                                        view.preferences,
                                                        summaries:
                                                            _payoutImportBatchSavedViewOperators,
                                                      ),
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                ],
                                              ),
                                              if (_payoutSavedViewActiveChipLabels(
                                                    selectedVisibilityScope:
                                                        _payoutImportBatchSavedViewsVisibilityFilter,
                                                    viewVisibilityScope:
                                                        view.visibilityScope,
                                                    viewAccountId:
                                                        view.accountId,
                                                    selectedOwnerAccountId:
                                                        _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                                    viewOperatorId: view
                                                        .preferences.operatorId,
                                                    selectedOperatorId:
                                                        _payoutImportBatchSavedViewsOperatorIdFilter,
                                                  ).isNotEmpty ||
                                                  _payoutImportBatchSavedViewIsCurrent(
                                                    view,
                                                  ) ||
                                                  _savedViewRecentlyUsedChipLabel(
                                                        _payoutImportBatchSavedViewUsedAtById[
                                                            view.viewId],
                                                      ) !=
                                                      null)
                                                const SizedBox(height: 6),
                                              if (_payoutSavedViewActiveChipLabels(
                                                    selectedVisibilityScope:
                                                        _payoutImportBatchSavedViewsVisibilityFilter,
                                                    viewVisibilityScope:
                                                        view.visibilityScope,
                                                    viewAccountId:
                                                        view.accountId,
                                                    selectedOwnerAccountId:
                                                        _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                                    viewOperatorId: view
                                                        .preferences.operatorId,
                                                    selectedOperatorId:
                                                        _payoutImportBatchSavedViewsOperatorIdFilter,
                                                  ).isNotEmpty ||
                                                  _payoutImportBatchSavedViewIsCurrent(
                                                    view,
                                                  ) ||
                                                  _savedViewRecentlyUsedChipLabel(
                                                        _payoutImportBatchSavedViewUsedAtById[
                                                            view.viewId],
                                                      ) !=
                                                      null)
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    ..._payoutSavedViewActiveChipLabels(
                                                      selectedVisibilityScope:
                                                          _payoutImportBatchSavedViewsVisibilityFilter,
                                                      viewVisibilityScope:
                                                          view.visibilityScope,
                                                      viewAccountId:
                                                          view.accountId,
                                                      selectedOwnerAccountId:
                                                          _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                                      viewOperatorId: view
                                                          .preferences
                                                          .operatorId,
                                                      selectedOperatorId:
                                                          _payoutImportBatchSavedViewsOperatorIdFilter,
                                                    ).map((label) {
                                                      return Chip(
                                                        label: Text(label),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      );
                                                    }),
                                                    if (_payoutImportBatchSavedViewIsCurrent(
                                                      view,
                                                    ))
                                                      const Chip(
                                                        label: Text(
                                                            'Using this view'),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    if (_savedViewRecentlyUsedChipLabel(
                                                          _payoutImportBatchSavedViewUsedAtById[
                                                              view.viewId],
                                                        ) !=
                                                        null)
                                                      Chip(
                                                        label: Text(
                                                          _savedViewRecentlyUsedChipLabel(
                                                            _payoutImportBatchSavedViewUsedAtById[
                                                                view.viewId],
                                                          )!,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                  ],
                                                ),
                                              const SizedBox(height: 4),
                                              if (_catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  ) !=
                                                  null)
                                                Text(
                                                  _catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  )!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              if (_catalogSavedViewOwnerLabel(
                                                    view.visibilityScope,
                                                    view.accountId,
                                                  ) !=
                                                  null)
                                                const SizedBox(height: 4),
                                              if (_catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  ) !=
                                                  null)
                                                Text(
                                                  _catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  )!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              if (_catalogSavedViewReadOnlyLabel(
                                                    view.visibilityScope,
                                                    view.canManage,
                                                  ) !=
                                                  null)
                                                const SizedBox(height: 4),
                                              const SizedBox(height: 4),
                                              Text(
                                                _describePayoutImportBatchPreferences(
                                                  view.preferences,
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Updated ${view.updatedAtIso}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 8,
                                                children: [
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPayoutImportBatchesApplySavedView_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues ||
                                                            _loadingMorePayoutImportBatches ||
                                                            _payoutImportBatchSavedViewIsCurrent(
                                                              view,
                                                            )
                                                        ? null
                                                        : () =>
                                                            _applyPayoutImportBatchSavedView(
                                                              view,
                                                            ),
                                                    icon: const Icon(
                                                      Icons
                                                          .bookmark_added_outlined,
                                                    ),
                                                    label: Text(
                                                      _payoutImportBatchSavedViewIsCurrent(
                                                        view,
                                                      )
                                                          ? 'View already active'
                                                          : 'Apply view',
                                                    ),
                                                  ),
                                                  OutlinedButton(
                                                    key: ValueKey(
                                                      'coachOpsPayoutImportBatchesTogglePinnedSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues ||
                                                            _loadingMorePayoutImportBatches
                                                        ? null
                                                        : () =>
                                                            _togglePayoutImportBatchSavedViewFavorite(
                                                              viewId:
                                                                  view.viewId,
                                                              favorite:
                                                                  !isPinnedView,
                                                            ),
                                                    child: Text(
                                                      isPinnedView
                                                          ? 'Unpin view'
                                                          : 'Pin view',
                                                    ),
                                                  ),
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPayoutImportBatchesFilterByOwner_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues ||
                                                            _loadingMorePayoutImportBatches ||
                                                            view.visibilityScope !=
                                                                'shared_ops' ||
                                                            view.accountId
                                                                .trim()
                                                                .isEmpty ||
                                                            _catalogSavedViewMatchesOwnerFilter(
                                                              view.visibilityScope,
                                                              view.accountId,
                                                              _payoutImportBatchSavedViewsVisibilityFilter,
                                                              _payoutImportBatchSavedViewsOwnerAccountIdFilter,
                                                            )
                                                        ? null
                                                        : () {
                                                            setState(() {
                                                              _payoutImportBatchSavedViewsVisibilityFilter =
                                                                  'shared_ops';
                                                              _payoutImportBatchSavedViewsOwnerAccountIdFilter =
                                                                  _normalizeCatalogSavedViewOwnerAccountIdFilter(
                                                                view.accountId,
                                                              );
                                                            });
                                                          },
                                                    icon: const Icon(
                                                      Icons.filter_alt_outlined,
                                                    ),
                                                    label: const Text(
                                                        'Filter by owner'),
                                                  ),
                                                  OutlinedButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPayoutImportBatchesFilterByOperator_${view.viewId}',
                                                    ),
                                                    onPressed: _loadingQueues ||
                                                            _loadingMorePayoutImportBatches ||
                                                            view.visibilityScope !=
                                                                'shared_ops' ||
                                                            _normalizePayoutImportOperatorIdFilterValue(
                                                                  view.preferences
                                                                      .operatorId,
                                                                ) ==
                                                                'all' ||
                                                            _normalizePayoutImportOperatorIdFilterValue(
                                                                  view.preferences
                                                                      .operatorId,
                                                                ) ==
                                                                _payoutImportBatchSavedViewsOperatorIdFilter
                                                        ? null
                                                        : () {
                                                            setState(() {
                                                              _payoutImportBatchSavedViewsVisibilityFilter =
                                                                  'shared_ops';
                                                              _payoutImportBatchSavedViewsOperatorIdFilter =
                                                                  _normalizePayoutImportOperatorIdFilterValue(
                                                                view.preferences
                                                                    .operatorId,
                                                              );
                                                            });
                                                          },
                                                    icon: const Icon(
                                                      Icons
                                                          .directions_bus_outlined,
                                                    ),
                                                    label: const Text(
                                                        'Filter by operator'),
                                                  ),
                                                  OutlinedButton(
                                                    key: ValueKey(
                                                      'coachOpsPayoutImportBatchesToggleDefaultSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: view.visibilityScope !=
                                                                'personal' ||
                                                            _loadingQueues ||
                                                            _loadingMorePayoutImportBatches ||
                                                            _updatingPayoutImportBatchSavedViewDefaultIds
                                                                .contains(
                                                                    view.viewId)
                                                        ? null
                                                        : () =>
                                                            _togglePayoutImportBatchSavedViewDefault(
                                                              view,
                                                            ),
                                                    child: Text(
                                                      view.isDefault
                                                          ? 'Clear default'
                                                          : 'Set default',
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    key: ValueKey(
                                                      'coachOpsPayoutImportBatchesDeleteSavedView_${view.viewId}',
                                                    ),
                                                    onPressed: _deletingPayoutImportBatchSavedViewIds
                                                                .contains(view
                                                                    .viewId) ||
                                                            !view.canManage ||
                                                            _loadingQueues ||
                                                            _loadingMorePayoutImportBatches
                                                        ? null
                                                        : () =>
                                                            _deletePayoutImportBatchSavedView(
                                                              view,
                                                            ),
                                                    icon:
                                                        _deletingPayoutImportBatchSavedViewIds
                                                                .contains(
                                                                    view.viewId)
                                                            ? const SizedBox(
                                                                width: 14,
                                                                height: 14,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                              )
                                                            : const Icon(
                                                                Icons
                                                                    .delete_outline,
                                                              ),
                                                    label: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (_payoutImportBatches == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'تعذر تحميل دفعات الاستيراد المجمعة.'
                                    : 'Payout import batches are unavailable.',
                              ),
                            )
                          else if (_payoutImportBatches!.batches.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'لا توجد دفعات استيراد مجمعة بعد.'
                                    : 'No payout import batches yet.',
                              ),
                            )
                          else if (visiblePayoutImportBatches.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'لا توجد دفعات تطابق عامل التصفية الحالي للمشغل.'
                                    : 'No payout import batches match the current operator filter.',
                              ),
                            )
                          else ...[
                            if ((_payoutImportBatchesCursor ?? '')
                                .trim()
                                .isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'coachOpsPayoutImportBatchesLoadOlderButton',
                                    ),
                                    onPressed:
                                        _loadingMorePayoutImportBatches ||
                                                _loadingQueues
                                            ? null
                                            : _loadMorePayoutImportBatches,
                                    icon: _loadingMorePayoutImportBatches
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.unfold_more_outlined),
                                    label: Text(
                                      _loadingMorePayoutImportBatches
                                          ? 'Loading older batches...'
                                          : 'Load older batches',
                                    ),
                                  ),
                                ),
                              ),
                            ...visiblePayoutImportBatches.map(
                              (batch) => _CoachOpsPayoutImportBatchCard(
                                batch: batch,
                                resolveReportUrl: _resolvePayoutImportReportUrl,
                                onUseAsReworkSource: _financeMutationsAllowed &&
                                        batch.failedRows > 0 &&
                                        batch.reworkArtifact != null
                                    ? () => unawaited(
                                          _setSelectedPayoutImportReworkSourceBatch(
                                            batch.batchId,
                                          ),
                                        )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                      ...workspaceDesk(
                        workspace: settlementsWorkspace,
                        segmentId: 'finance',
                        showHeader: false,
                        children: [
                          Container(
                            key: _payoutRunsSectionKey,
                            child: Text(
                              isArabic ? 'تشغيل الدفعات' : 'Payout runs',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_payoutRuns != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_payoutRuns!.generatedAtIso}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (_payoutRuns == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'تعذر تحميل تشغيل الدفعات.'
                                    : 'Payout runs are unavailable.',
                              ),
                            )
                          else if (_payoutRuns!.runs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'لا توجد دفعات مجدولة بعد.'
                                    : 'No payout runs queued yet.',
                              ),
                            )
                          else ...[
                            if ((_payoutRuns!.nextCursor?.trim().isNotEmpty ??
                                false))
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'coachOpsPayoutRunsLoadOlderButton',
                                    ),
                                    onPressed:
                                        _loadingMorePayoutRuns || _loadingQueues
                                            ? null
                                            : _loadMorePayoutRuns,
                                    icon: _loadingMorePayoutRuns
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.unfold_more_outlined),
                                    label: Text(
                                      _loadingMorePayoutRuns
                                          ? 'Loading older payout runs...'
                                          : 'Load older payout runs',
                                    ),
                                  ),
                                ),
                              ),
                            ..._payoutRuns!.runs.map(
                              (run) => _CoachOpsPayoutRunCard(
                                run: run,
                                busy: _markingPaidRunIds
                                    .contains(run.payoutRunId),
                                creatingExportKeys: _creatingExportKeys,
                                allowMarkPaid:
                                    _financeMutationsAllowed && run.isQueued,
                                allowCreateExports: _financeMutationsAllowed,
                                allowImportActions:
                                    _financeMutationsAllowed && run.isQueued,
                                importingExecuted: _creatingImportKeys
                                    .contains(_payoutImportBusyKey(
                                  run.payoutRunId,
                                  'executed',
                                )),
                                importingFailed: _creatingImportKeys
                                    .contains(_payoutImportBusyKey(
                                  run.payoutRunId,
                                  'failed',
                                )),
                                resolveExportUrl: _resolvePayoutExportUrl,
                                onMarkPaid: run.isQueued
                                    ? () => _markPayoutRunPaid(run)
                                    : null,
                                onImportExecuted: run.isQueued
                                    ? () => _applyPayoutImport(run, 'executed')
                                    : null,
                                onImportFailed: run.isQueued
                                    ? () => _applyPayoutImport(run, 'failed')
                                    : null,
                                onCreateExport: (exportFormat) =>
                                    _createPayoutExport(run, exportFormat),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Container(
                            key: _settlementSectionKey,
                            child: Text(
                              isArabic
                                  ? 'كشوفات التسوية'
                                  : 'Settlement statements',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_settlementStatements != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                '${isArabic ? 'آخر مزامنة' : 'Generated'}: ${_settlementStatements!.generatedAtIso}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (_settlementStatements == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'تعذر تحميل كشف التسوية.'
                                    : 'Settlement statements are unavailable.',
                              ),
                            )
                          else if (_settlementStatements!.statements.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isArabic
                                    ? 'لا توجد كشوفات تسوية متاحة.'
                                    : 'No settlement statements available.',
                              ),
                            )
                          else ...[
                            ..._settlementStatements!.statements.map(
                              (statement) => _CoachOpsSettlementStatementCard(
                                statement: statement,
                                busy: _creatingPayoutStatementIds
                                    .contains(statement.statementId),
                                allowQueuePayout: _financeMutationsAllowed &&
                                    statement.status == 'ready_for_payout',
                                onQueuePayout:
                                    statement.status == 'ready_for_payout'
                                        ? () => _queuePayoutRun(statement)
                                        : null,
                              ),
                            ),
                            if ((_settlementStatements!.nextCursor
                                    ?.trim()
                                    .isNotEmpty ??
                                false))
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'coachOpsSettlementStatementsLoadOlderButton',
                                    ),
                                    onPressed:
                                        _loadingMoreSettlementStatements ||
                                                _loadingQueues
                                            ? null
                                            : _loadMoreSettlementStatements,
                                    icon: _loadingMoreSettlementStatements
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.unfold_more_outlined),
                                    label: Text(
                                      _loadingMoreSettlementStatements
                                          ? 'Loading older statements...'
                                          : 'Load older statements',
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ],
                  ),
                ...portalSection(
                  section: supportPortalSection,
                  children: [
                    ...workspaceDesk(
                      workspace: supportWorkspace,
                      children: [
                        Container(
                          key: _refundSectionKey,
                          child: Text(
                            isArabic ? 'طلبات الاسترداد' : 'Refund requests',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_refundGeneratedAtIso != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              '${isArabic ? 'آخر مزامنة' : 'Generated'}: $_refundGeneratedAtIso',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (_refundRequests.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              isArabic
                                  ? 'لا توجد طلبات استرداد مفتوحة.'
                                  : 'No open refund requests.',
                            ),
                          ),
                        ..._refundRequests.map(
                          (entry) => _CoachRefundRequestCard(
                            entry: entry,
                            busy: _reviewingRefundIds
                                .contains(entry.refundRequestId),
                            onApprove: entry.isPendingReview
                                ? () => _reviewRefund(entry, approve: true)
                                : null,
                            onReject: entry.isPendingReview
                                ? () => _reviewRefund(entry, approve: false)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          key: _changeSectionKey,
                          child: Text(
                            isArabic ? 'طلبات التغيير' : 'Change requests',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_changeGeneratedAtIso != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              '${isArabic ? 'آخر مزامنة' : 'Generated'}: $_changeGeneratedAtIso',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (_changeRequests.isEmpty)
                          Text(
                            isArabic
                                ? 'لا توجد طلبات تغيير مفتوحة.'
                                : 'No open change requests.',
                          ),
                        ..._changeRequests.map(
                          (entry) => _CoachChangeRequestCard(
                            entry: entry,
                            busy: _reviewingChangeIds
                                .contains(entry.changeRequestId),
                            onApprove: entry.isPendingReview
                                ? () => _reviewChange(entry, approve: true)
                                : null,
                            onReject: entry.isPendingReview
                                ? () => _reviewChange(entry, approve: false)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CoachApprovalQueuePanel(
                  items: <CoachApprovalQueueItem>[
                    if (_refundPendingCount > 0)
                      CoachApprovalQueueItem(
                        title: 'Refund approval',
                        detail:
                            '$_refundPendingCount refund request(s) need operator review.',
                        riskLabel: 'Customer money',
                        icon: Icons.request_quote_outlined,
                      ),
                    if (_changePendingCount > 0)
                      CoachApprovalQueueItem(
                        title: 'Change approval',
                        detail:
                            '$_changePendingCount change request(s) need a decision.',
                        riskLabel: 'Seat inventory',
                        icon: Icons.alt_route_outlined,
                      ),
                    if (_payoutAttentionCount > 0)
                      CoachApprovalQueueItem(
                        title: 'Payout exception',
                        detail:
                            '$_payoutAttentionCount payout item(s) need finance review.',
                        riskLabel: 'Settlement',
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                CoachPartnerPerformancePanel(
                  partnerLabel: scopeLabel,
                  metrics: <CoachPerformanceMetric>[
                    CoachPerformanceMetric(
                      label: 'Support load',
                      value:
                          '${_refundRequests.length + _changeRequests.length}',
                      detail: 'Open refund and change requests',
                      icon: Icons.support_agent_outlined,
                      color: const Color(0xFF2563EB),
                    ),
                    CoachPerformanceMetric(
                      label: 'Feed issues',
                      value: '${_degradedFeedCount + _staleFeedCount}',
                      detail: 'Degraded or stale feeds',
                      icon: Icons.hub_outlined,
                      color: const Color(0xFFB45309),
                    ),
                    CoachPerformanceMetric(
                      label: 'Queued payouts',
                      value: '$_queuedPayoutRunCount',
                      detail: 'Runs ready for payment',
                      icon: Icons.account_balance_wallet_outlined,
                      color: const Color(0xFF0F766E),
                    ),
                    CoachPerformanceMetric(
                      label: 'Catalog runs',
                      value: '$_catalogImportRunCount',
                      detail: 'Import runs in scope',
                      icon: Icons.inventory_2_outlined,
                      color: const Color(0xFF7C3AED),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CoachRecoveryFlowPanel(
                  routeLabel: _refundRequests.isNotEmpty
                      ? '${_refundRequests.first.from} -> ${_refundRequests.first.to}'
                      : _changeRequests.isNotEmpty
                          ? '${_changeRequests.first.from} -> ${_changeRequests.first.to}'
                          : 'Operator support queue',
                  impactedPassengers:
                      _refundRequests.length + _changeRequests.length,
                  rebookingOptions: const <String>[
                    'Same operator next departure',
                    'Partner standby inventory',
                    'Refund to SyrChat wallet',
                  ],
                  compensationLabel: 'Operator voucher or refund credit',
                ),
                const SizedBox(height: 16),
                CoachNotificationsInboxPanel(
                  items: <CoachNotificationInboxItem>[
                    CoachNotificationInboxItem(
                      title: 'Refund status update',
                      audience: '${_refundRequests.length} request(s)',
                      status: _refundRequests.isEmpty ? 'Delivered' : 'Pending',
                      timeLabel: _refundGeneratedAtIso ?? '-',
                      icon: Icons.request_quote_outlined,
                    ),
                    CoachNotificationInboxItem(
                      title: 'Change request update',
                      audience: '${_changeRequests.length} request(s)',
                      status: _changeRequests.isEmpty ? 'Delivered' : 'Pending',
                      timeLabel: _changeGeneratedAtIso ?? '-',
                      icon: Icons.alt_route_outlined,
                    ),
                    CoachNotificationInboxItem(
                      title: 'Payout run notice',
                      audience: '$_queuedPayoutRunCount queued run(s)',
                      status:
                          _payoutAttentionCount > 0 ? 'Failed' : 'Delivered',
                      timeLabel: _payoutRuns?.generatedAtIso ?? '-',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
      return Scaffold(
        appBar: AppBar(
          title: Text(isArabic ? 'عمليات الحافلات' : 'Coach Ops'),
          actions: [
            // Cycle 262 — Disruption Broadcast composer entry. Lets
            // an operator quickly publish a journey-level notice
            // (delay/route change/weather) without navigating into a
            // specific queue first.
            IconButton(
              tooltip: isArabic
                  ? 'بلاغات التعطّل'
                  : 'Disruption broadcasts',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CoachOperatorDisruptionBroadcastPage(
                      baseUrl: widget.baseUrl,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.campaign_outlined),
            ),
            // Activity log (operator-console-inventory module 8). Same
            // flavor-agnostic page the Taxi operator already uses; lands
            // the admin on /admin/user-activity without leaving the bus
            // console.
            IconButton(
              tooltip: isArabic ? 'سجل النشاط' : 'Activity log',
              icon: const Icon(Icons.history_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OperatorActivityPage(
                      baseUrl: widget.baseUrl,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: isArabic ? 'تحديث' : 'Refresh queues',
              onPressed: _loadingQueues ? null : _loadQueues,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        // Narrow layout → slide-in drawer; wide layout uses the rail in
        // the body Row instead so the drawer trigger doesn't compete with
        // it for screen real estate.
        drawer: wideLayout ? null : _buildPortalDrawer(layoutCtx, isArabic),
        body: wideLayout
            ? Row(
                children: [
                  _buildPortalNavigationRail(
                    layoutCtx,
                    isArabic,
                    extendedRail,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: mainBody),
                ],
              )
            : mainBody,
      );
    });
  }
}

class _CoachOpsWorkspaceDescriptor {
  final String id;
  final String label;
  final String detail;
  final IconData icon;
  final Color color;
  final int signalCount;

  const _CoachOpsWorkspaceDescriptor({
    required this.id,
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
    required this.signalCount,
  });
}

class _CoachOpsPortalJumpDescriptor {
  final String id;
  final String portalSectionId;
  final String? settlementsTrackId;
  final IconData icon;
  final String label;
  final String workspaceId;
  final GlobalKey targetKey;

  const _CoachOpsPortalJumpDescriptor({
    required this.id,
    required this.portalSectionId,
    this.settlementsTrackId,
    required this.icon,
    required this.label,
    required this.workspaceId,
    required this.targetKey,
  });
}

class _CoachOpsPortalSectionDescriptor {
  final String id;
  final String label;
  final String detail;
  final IconData icon;
  final Color color;
  final int signalCount;

  const _CoachOpsPortalSectionDescriptor({
    required this.id,
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
    required this.signalCount,
  });
}

class _CoachOpsPortalNavItem {
  final String portalSectionId;
  final IconData icon;
  final String label;
  final int badge;

  const _CoachOpsPortalNavItem({
    required this.portalSectionId,
    required this.icon,
    required this.label,
    required this.badge,
  });
}

class _CoachOpsPortalSummaryCardDescriptor {
  final String id;
  final String portalSectionId;
  final String? settlementsTrackId;
  final String workspaceId;
  final String title;
  final String value;
  final String subtitle;

  const _CoachOpsPortalSummaryCardDescriptor({
    required this.id,
    required this.portalSectionId,
    this.settlementsTrackId,
    required this.workspaceId,
    required this.title,
    required this.value,
    required this.subtitle,
  });
}

class _CoachOpsPortalSectionShell extends StatelessWidget {
  final Key bodyKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final int signalCount;
  final List<Widget> children;

  const _CoachOpsPortalSectionShell({
    super.key,
    required this.bodyKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.signalCount,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: .18)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0C081F17),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Portal lane',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .2,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF16362B),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF526176),
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accentColor.withValues(alpha: .16)),
                ),
                child: Text(
                  'Open signals $signalCount',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: bodyKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachOpsSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _CoachOpsSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachOpsSettlementStatementCard extends StatelessWidget {
  final CoachOperatorSettlementStatement statement;
  final bool busy;
  final bool allowQueuePayout;
  final VoidCallback? onQueuePayout;

  const _CoachOpsSettlementStatementCard({
    required this.statement,
    this.busy = false,
    this.allowQueuePayout = false,
    this.onQueuePayout,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${statement.operatorName} • ${statement.status}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${statement.periodStartIso} → ${statement.periodEndIso}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Net payable ${_coachOpsMoney(statement.currency, statement.totals.netPayableMinorUnits)} • lines ${statement.totals.lineCount}',
            ),
            const SizedBox(height: 4),
            Text(
              'Gross ${_coachOpsMoney(statement.currency, statement.totals.grossMinorUnits)} • refunds ${_coachOpsMoney(statement.currency, statement.totals.refundMinorUnits)}',
            ),
            const SizedBox(height: 4),
            Text(
              'SyrChat app fee ${_coachOpsMoney(statement.currency, statement.totals.commissionMinorUnits)} • reserve ${_coachOpsMoney(statement.currency, statement.totals.chargebackReserveMinorUnits)}',
            ),
            const SizedBox(height: 4),
            Text('Formats: ${statement.downloadFormats.join(', ')}'),
            const SizedBox(height: 4),
            Text('Next payout: ${statement.nextPayoutAtIso}'),
            if (allowQueuePayout) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onQueuePayout,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.account_balance_wallet_outlined),
                  label: Text(
                    busy ? 'Queueing payout...' : 'Queue payout',
                  ),
                ),
              ),
            ],
            if (statement.lines.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...statement.lines.take(2).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${line.bookingId} • ${coachSettlementBasisWireValue(line.basis)} • ${_coachOpsMoney(line.currency, line.netPayableMinorUnits)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsPayoutReconciliationCard extends StatelessWidget {
  final CoachOperatorPayoutReconciliationRun run;

  const _CoachOpsPayoutReconciliationCard({required this.run});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${run.operatorNames.join(', ')} • ${_coachPayoutReconciliationStatusLabel(run.reconciliationStatus)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${run.payoutRunId} • ${run.runStatus} • created ${run.createdAtIso}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Net payable ${_coachOpsMoney(run.currency, run.netPayableMinorUnits)}',
            ),
            const SizedBox(height: 4),
            Text('Statements: ${run.statementIds.join(', ')}'),
            if (run.paymentReference != null) ...[
              const SizedBox(height: 4),
              Text('Reference: ${run.paymentReference}'),
            ],
            if (run.readyExportFormats.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ready exports: ${run.readyExportFormats.map(_coachPayoutExportFormatLabel).join(', ')}',
              ),
            ],
            if (run.missingExportFormats.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Missing exports: ${run.missingExportFormats.map(_coachPayoutExportFormatLabel).join(', ')}',
              ),
            ],
            const SizedBox(height: 4),
            Text('Next: ${run.nextAction}'),
            if (run.needsAttention && run.attentionReasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...run.attentionReasons.map(
                (reason) => Text(
                  'Attention: $reason',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsPayoutImportCard extends StatelessWidget {
  final CoachOperatorPayoutImport entry;

  const _CoachOpsPayoutImportCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.importSource} • ${entry.externalStatus}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.importId} • run ${entry.payoutRunId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Applied ${entry.previousRunStatus} → ${entry.appliedRunStatus}',
            ),
            const SizedBox(height: 4),
            Text('Imported at: ${entry.importedAtIso}'),
            if (entry.paymentReference != null) ...[
              const SizedBox(height: 4),
              Text('Reference: ${entry.paymentReference}'),
            ],
            if (entry.externalReference != null) ...[
              const SizedBox(height: 4),
              Text('External ref: ${entry.externalReference}'),
            ],
            if (entry.note != null) ...[
              const SizedBox(height: 4),
              Text('Note: ${entry.note}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsCatalogSourceArtifactCard extends StatelessWidget {
  final CoachOperatorCatalogSourceArtifact entry;
  final bool viewingDetails;
  final bool runningImport;
  final bool catalogMutationsAllowed;
  final String? readOnlyHintText;
  final VoidCallback onViewDetails;
  final VoidCallback? onRunImport;

  const _CoachOpsCatalogSourceArtifactCard({
    required this.entry,
    this.viewingDetails = false,
    required this.runningImport,
    required this.catalogMutationsAllowed,
    this.readOnlyHintText,
    required this.onViewDetails,
    required this.onRunImport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.sourceLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.artifactId} • ${entry.contentLengthBytes} bytes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Operators: ${_coachFormatCatalogOperatorScope(entry.operatorIds)}',
            ),
            const SizedBox(height: 4),
            Text('File: ${entry.fileName}'),
            const SizedBox(height: 4),
            Text('Feed: ${entry.feedLocator}'),
            const SizedBox(height: 4),
            Text(
              'Extracted files: ${entry.extractedFileCount} • Created at: ${entry.createdAtIso}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Checksum: ${entry.fileChecksumSha256}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if ((readOnlyHintText ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                readOnlyHintText!,
                key: ValueKey(
                  'coachOpsCatalogSourceArtifactReadOnlyHint_${entry.artifactId}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  key: ValueKey(
                    'coachOpsCatalogSourceArtifactViewDetails_${entry.artifactId}',
                  ),
                  onPressed: viewingDetails ? null : onViewDetails,
                  icon: viewingDetails
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new_outlined),
                  label: Text(
                    viewingDetails ? 'Loading details...' : 'View details',
                  ),
                ),
                if (catalogMutationsAllowed)
                  OutlinedButton.icon(
                    key: ValueKey(
                      'coachOpsCatalogSourceArtifactRunImport_${entry.artifactId}',
                    ),
                    onPressed: onRunImport,
                    icon: runningImport
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_outlined),
                    label: Text(
                      runningImport
                          ? 'Running import...'
                          : 'Run import from this artifact',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachOpsCatalogImportRunCard extends StatelessWidget {
  final CoachOperatorCatalogImportRun entry;
  final bool viewingDetails;
  final String? readOnlyHintText;
  final VoidCallback onViewDetails;

  const _CoachOpsCatalogImportRunCard({
    required this.entry,
    this.viewingDetails = false,
    this.readOnlyHintText,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.sourceKind} • ${entry.status}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.importRunId} • ${entry.triggerKind}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text('Started at: ${entry.startedAtIso}'),
            if (entry.finishedAtIso != null) ...[
              const SizedBox(height: 4),
              Text('Finished at: ${entry.finishedAtIso}'),
            ],
            if (entry.feedLocator != null) ...[
              const SizedBox(height: 4),
              Text('Feed: ${entry.feedLocator}'),
            ],
            const SizedBox(height: 4),
            Text(
              'Operator scope: ${_coachFormatCatalogOperatorScope(entry.operatorIds)}',
            ),
            if ((entry.replayedFromImportRunId ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Replay of: ${entry.replayedFromImportRunId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if ((entry.replayLineageSummary?.replayRunCount ?? 0) > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Replay runs: ${entry.replayLineageSummary!.replayRunCount}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if ((entry.replayLineageSummary?.latestReplayRunId ?? '')
                  .trim()
                  .isNotEmpty)
                Text(
                  'Latest replay: ${entry.replayLineageSummary!.latestReplayRunId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if ((entry.replayLineageSummary?.latestReplayStartedAtIso ?? '')
                  .trim()
                  .isNotEmpty)
                Text(
                  'Latest replay at: ${entry.replayLineageSummary!.latestReplayStartedAtIso}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (entry.sourceArtifact != null) ...[
              const SizedBox(height: 4),
              Text('Artifact: ${entry.sourceArtifact!.sourceLabel}'),
              const SizedBox(height: 4),
              Text(
                '${entry.sourceArtifact!.artifactId} • ${entry.sourceArtifact!.contentLengthBytes} bytes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if ((entry.sourceArtifactId ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Artifact id: ${entry.sourceArtifactId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Records: ${entry.counts.totalRecords} • trips ${entry.counts.trips} • fares ${entry.counts.fareProducts}',
            ),
            if (entry.issues.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Issues: ${entry.issues.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              ...entry.issues.take(3).map(
                    (issue) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${issue.severity.toUpperCase()} • ${issue.stage} • ${issue.code}'
                            '${issue.fileName == null ? '' : ' • ${issue.fileName}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            issue.message,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (issue.rowReference != null)
                            Text(
                              'Row: ${issue.rowReference}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
            if (entry.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                'Error: ${entry.errorMessage}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if ((readOnlyHintText ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                readOnlyHintText!,
                key: ValueKey(
                  'coachOpsCatalogImportRunReadOnlyHint_${entry.importRunId}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: ValueKey(
                  'coachOpsCatalogImportRunViewDetails_${entry.importRunId}',
                ),
                onPressed: viewingDetails ? null : onViewDetails,
                icon: viewingDetails
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_new_outlined),
                label: Text(
                  viewingDetails ? 'Loading details...' : 'View details',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachOpsFeedHealthCard extends StatelessWidget {
  final CoachOperatorFeedHealth entry;

  const _CoachOpsFeedHealthCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final statusLine =
        '${entry.operatorName} • ${entry.feedKind} • ${entry.syncStatus}/${entry.freshnessStatus}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusLine,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.operatorId} • ${entry.operatorIntegrationMode} • ${entry.sourceKind}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (entry.lastAttemptedAtIso != null) ...[
              const SizedBox(height: 4),
              Text('Last attempted: ${entry.lastAttemptedAtIso}'),
            ],
            if (entry.lastSucceededAtIso != null) ...[
              const SizedBox(height: 4),
              Text('Last succeeded: ${entry.lastSucceededAtIso}'),
            ],
            if (entry.freshnessExpiresAtIso != null) ...[
              const SizedBox(height: 4),
              Text('Fresh until: ${entry.freshnessExpiresAtIso}'),
            ],
            const SizedBox(height: 4),
            Text('Records ingested: ${entry.recordsIngested}'),
            if (entry.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                'Error: ${entry.errorMessage}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsPayoutImportPreviewCard extends StatelessWidget {
  final CoachOperatorPayoutImportPreview entry;
  final bool financeMutationsAllowed;
  final bool busy;
  final VoidCallback? onInvalidate;

  const _CoachOpsPayoutImportPreviewCard({
    required this.entry,
    this.financeMutationsAllowed = false,
    this.busy = false,
    this.onInvalidate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.importSource} • ${_coachPayoutImportPreviewStatusLabel(entry.previewStatus)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.previewToken} • ${entry.reportName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text('Created at: ${entry.createdAtIso}'),
            const SizedBox(height: 4),
            Text('Expires at: ${entry.expiresAtIso}'),
            if (entry.consumedAtIso != null) ...[
              const SizedBox(height: 4),
              Text('Consumed at: ${entry.consumedAtIso}'),
            ],
            if (entry.invalidatedAtIso != null) ...[
              const SizedBox(height: 4),
              Text('Invalidated at: ${entry.invalidatedAtIso}'),
            ],
            if (entry.reworkOfBatchId != null) ...[
              const SizedBox(height: 4),
              Text('Rework of: ${entry.reworkOfBatchId}'),
            ],
            const SizedBox(height: 4),
            Text(
              'Operator scope: ${_coachFormatCatalogOperatorScope(entry.operatorIds)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              entry.usableNow ? 'Usable now: yes' : 'Usable now: no',
            ),
            if (financeMutationsAllowed && onInvalidate != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onInvalidate,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cancel_outlined),
                  label: Text(
                    busy ? 'Invalidating...' : 'Invalidate preview',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsPayoutImportBatchCard extends StatelessWidget {
  final CoachOperatorPayoutImportBatch batch;
  final String Function(String downloadPath) resolveReportUrl;
  final VoidCallback? onUseAsReworkSource;

  const _CoachOpsPayoutImportBatchCard({
    required this.batch,
    required this.resolveReportUrl,
    required this.onUseAsReworkSource,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${batch.reportName} • ${batch.importSource}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${batch.batchId} • ${batch.reportFormat.toUpperCase()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Rows ${batch.totalRows} • applied ${batch.appliedRows} • failed ${batch.failedRows}',
            ),
            if (batch.payoutRunIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Runs: ${batch.payoutRunIds.join(', ')}'),
            ],
            const SizedBox(height: 4),
            Text(
              'Operator scope: ${_coachFormatCatalogOperatorScope(batch.operatorIds)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text('Created at: ${batch.createdAtIso}'),
            const SizedBox(height: 4),
            Text('Checksum: ${batch.reportChecksumSha256}'),
            if (batch.reworkOfBatchId != null) ...[
              const SizedBox(height: 4),
              Text('Rework of: ${batch.reworkOfBatchId}'),
            ],
            if (batch.reworkOriginBatchId != null &&
                batch.reworkOriginBatchId != batch.reworkOfBatchId) ...[
              const SizedBox(height: 4),
              Text('Origin batch: ${batch.reworkOriginBatchId}'),
            ],
            if (batch.followUpBatchIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Follow-ups: ${batch.followUpBatchIds.join(' -> ')}'),
            ],
            if (batch.reportArtifact != null) ...[
              const SizedBox(height: 4),
              Text(
                'Report download: ${resolveReportUrl(batch.reportArtifact!.downloadPath)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Report scope: ${_coachFormatCatalogOperatorScope(batch.reportArtifact!.operatorIds)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (batch.reworkArtifact != null) ...[
              const SizedBox(height: 4),
              Text(
                'Rework download: ${resolveReportUrl(batch.reworkArtifact!.downloadPath)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Rework scope: ${_coachFormatCatalogOperatorScope(batch.reworkArtifact!.operatorIds)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (batch.note != null) ...[
              const SizedBox(height: 4),
              Text('Note: ${batch.note}'),
            ],
            if (onUseAsReworkSource != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onUseAsReworkSource,
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('Use failed rows as rework source'),
                ),
              ),
            ],
            if (batch.failureMessages.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...batch.failureMessages.take(3).map(
                    (message) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('Attention: $message'),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsPayoutImportBatchResultCard extends StatelessWidget {
  final CoachOperatorPayoutImportBatchMutationResult result;
  final CoachPayoutImportDraftValidationSummary? localValidation;
  final CoachPayoutImportDraftAutoFixResult? localAutoFix;
  final String currentDraftChecksumSha256;
  final String Function(String downloadPath) resolveReportUrl;
  final bool financeMutationsAllowed;
  final bool invalidatingPreview;
  final VoidCallback? onInvalidatePreview;

  const _CoachOpsPayoutImportBatchResultCard({
    required this.result,
    required this.localValidation,
    required this.localAutoFix,
    required this.currentDraftChecksumSha256,
    required this.resolveReportUrl,
    this.financeMutationsAllowed = false,
    this.invalidatingPreview = false,
    this.onInvalidatePreview,
  });

  @override
  Widget build(BuildContext context) {
    final batch = result.batch;
    final headline = result.dryRun ? 'Preview ready' : 'Last applied batch';
    final statusLine = result.dryRun
        ? 'No payout runs or audit rows were mutated yet.'
        : 'Payout runs and import audit rows were updated.';
    final previewDiffSummary =
        result.dryRun && localValidation != null && localAutoFix != null
            ? buildCoachPayoutImportPreviewDiffSummary(
                localValidation: localValidation!,
                autoFix: localAutoFix!,
                previewResult: result,
                previewEcho: result.previewEcho,
                currentDraftChecksumSha256: currentDraftChecksumSha256,
              )
            : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$headline • ${batch.reportName}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Rows ${batch.totalRows} • ready ${batch.appliedRows} • blocked ${batch.failedRows}',
            ),
            const SizedBox(height: 4),
            Text(statusLine),
            const SizedBox(height: 4),
            Text('Next: ${result.nextAction}'),
            if (financeMutationsAllowed &&
                result.dryRun &&
                onInvalidatePreview != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: invalidatingPreview ? null : onInvalidatePreview,
                  icon: invalidatingPreview
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cancel_outlined),
                  label: Text(
                    invalidatingPreview
                        ? 'Invalidating preview...'
                        : 'Invalidate preview',
                  ),
                ),
              ),
            ],
            if (previewDiffSummary != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dry-run diff • ${previewDiffSummary.headline}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      previewDiffSummary.statusLine,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    ...previewDiffSummary.notes.take(3).map(
                          (note) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              note,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
            if (batch.reworkOfBatchId != null) ...[
              const SizedBox(height: 4),
              Text('Rework of: ${batch.reworkOfBatchId}'),
            ],
            if (batch.reworkOriginBatchId != null &&
                batch.reworkOriginBatchId != batch.reworkOfBatchId) ...[
              const SizedBox(height: 4),
              Text('Origin batch: ${batch.reworkOriginBatchId}'),
            ],
            if (batch.followUpBatchIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Follow-ups: ${batch.followUpBatchIds.join(' -> ')}'),
            ],
            const SizedBox(height: 4),
            Text(
              'Operator scope: ${_coachFormatCatalogOperatorScope(batch.operatorIds)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (batch.reportArtifact != null) ...[
              const SizedBox(height: 4),
              Text(
                'Report download: ${resolveReportUrl(batch.reportArtifact!.downloadPath)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Report scope: ${_coachFormatCatalogOperatorScope(batch.reportArtifact!.operatorIds)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (batch.reworkArtifact != null) ...[
              const SizedBox(height: 4),
              Text(
                'Rework download: ${resolveReportUrl(batch.reworkArtifact!.downloadPath)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Rework scope: ${_coachFormatCatalogOperatorScope(batch.reworkArtifact!.operatorIds)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (batch.payoutRunIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Runs: ${batch.payoutRunIds.join(', ')}'),
            ],
            if (result.imports.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.imports.take(3).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${entry.payoutRunId}: ${entry.previousRunStatus} -> ${entry.appliedRunStatus}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
            ],
            if (result.failedRows.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.failedRows.take(3).map(
                    (failure) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'Attention: line ${failure.lineNumber}: ${failure.detail}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsPayoutRunCard extends StatelessWidget {
  final CoachOperatorPayoutRun run;
  final bool busy;
  final Set<String> creatingExportKeys;
  final bool allowMarkPaid;
  final bool allowCreateExports;
  final bool allowImportActions;
  final bool importingExecuted;
  final bool importingFailed;
  final String Function(String downloadPath)? resolveExportUrl;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onImportExecuted;
  final VoidCallback? onImportFailed;
  final ValueChanged<String>? onCreateExport;

  const _CoachOpsPayoutRunCard({
    required this.run,
    this.busy = false,
    this.creatingExportKeys = const <String>{},
    this.allowMarkPaid = false,
    this.allowCreateExports = false,
    this.allowImportActions = false,
    this.importingExecuted = false,
    this.importingFailed = false,
    this.resolveExportUrl,
    this.onMarkPaid,
    this.onImportExecuted,
    this.onImportFailed,
    this.onCreateExport,
  });

  @override
  Widget build(BuildContext context) {
    final existingFormats = run.exports
        .map((export) => export.exportFormat.trim().toLowerCase())
        .toSet();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${run.operatorNames.join(', ')} • ${run.status}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${run.payoutRunId} • statements ${run.statementCount} • created ${run.createdAtIso}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Net payable ${_coachOpsMoney(run.currency, run.netPayableMinorUnits)} • reserve ${_coachOpsMoney(run.currency, run.reserveMinorUnits)}',
            ),
            const SizedBox(height: 4),
            Text('Statements: ${run.statementIds.join(', ')}'),
            if (run.paymentReference != null) ...[
              const SizedBox(height: 4),
              Text('Reference: ${run.paymentReference}'),
            ],
            if (run.paidAtIso != null) ...[
              const SizedBox(height: 4),
              Text('Paid at: ${run.paidAtIso}'),
            ],
            if (run.note != null) ...[
              const SizedBox(height: 4),
              Text('Note: ${run.note}'),
            ],
            if (run.availableExportFormats.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Export formats: ${run.availableExportFormats.map(_coachPayoutExportFormatLabel).join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (allowCreateExports) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: run.availableExportFormats
                    .where(
                  (format) =>
                      !existingFormats.contains(format.trim().toLowerCase()),
                )
                    .map((format) {
                  final busyKey = '${run.payoutRunId}::$format';
                  final exportBusy = creatingExportKeys.contains(busyKey);
                  return OutlinedButton.icon(
                    onPressed:
                        exportBusy ? null : () => onCreateExport?.call(format),
                    icon: exportBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined),
                    label: Text(
                      exportBusy
                          ? 'Preparing ${_coachPayoutExportFormatLabel(format)}...'
                          : 'Prepare ${_coachPayoutExportFormatLabel(format)}',
                    ),
                  );
                }).toList(growable: false),
              ),
            ],
            if (run.exports.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Exports',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              ...run.exports.map(
                (export) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${_coachPayoutExportFormatLabel(export.exportFormat)} • ${export.status} • ${export.fileName}\n${resolveExportUrl?.call(export.downloadPath) ?? export.downloadPath}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (allowImportActions) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: importingExecuted ? null : onImportExecuted,
                    icon: importingExecuted
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_balance_outlined),
                    label: Text(
                      importingExecuted
                          ? 'Importing executed...'
                          : 'Import executed',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: importingFailed ? null : onImportFailed,
                    icon: importingFailed
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.error_outline),
                    label: Text(
                      importingFailed ? 'Importing failed...' : 'Import failed',
                    ),
                  ),
                ],
              ),
            ],
            if (allowMarkPaid) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: busy ? null : onMarkPaid,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all),
                  label: Text(busy ? 'Saving payout...' : 'Mark paid'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsTripReconciliationCard extends StatelessWidget {
  final CoachOperatorReconciliationTripSnapshot snapshot;

  const _CoachOpsTripReconciliationCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final trip = snapshot.trip;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${trip.operatorName} • ${trip.from} → ${trip.to}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${trip.tripId} • boarded ${trip.boardedCount}/${trip.manifestCount} • pending ${trip.pendingCount}',
            ),
            const SizedBox(height: 4),
            Text(
              'Denied ${trip.deniedCount} • no-show ${trip.noShowCount} • needs attention ${snapshot.needsAttentionCount}',
            ),
            if (snapshot.pendingTicketIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Pending tickets: ${snapshot.pendingTicketIds.join(', ')}'),
            ],
            if (snapshot.recentEvents.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Recent scans',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              ...snapshot.recentEvents.take(3).map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${_coachBoardingScanStatusLabel(event.scanStatus)} • ${event.ticketId} • ${event.capturedAtIso}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachOpsReviewHistoryCard extends StatelessWidget {
  final CoachOperatorReconciliationHistoryEntry entry;

  const _CoachOpsReviewHistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final settlementEffect = entry.settlementEffect;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_coachOpsRequestKindLabel(entry.requestKind)} • ${entry.operatorName} • ${entry.from} → ${entry.to}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.requestId} • ${_coachOpsQueueStatusLabel(entry.queueStatus)} • ${_coachOpsUrgencyLabel(entry.urgency)}',
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.subjectLabel} • ${_coachOpsMoney(entry.currency, entry.amountMinorUnits)}',
            ),
            const SizedBox(height: 4),
            Text('Action: ${entry.suggestedAction}'),
            const SizedBox(height: 4),
            Text('Next: ${entry.nextAction}'),
            if (settlementEffect != null) ...[
              const SizedBox(height: 4),
              Text(
                'Settlement: ${settlementEffect.kind} • ${_coachOpsMoney(settlementEffect.currency, settlementEffect.amountMinorUnits)}',
              ),
            ],
            if (entry.reviewNote != null) ...[
              const SizedBox(height: 4),
              Text('Review note: ${entry.reviewNote}'),
            ],
            if (entry.reviewedAtIso != null) ...[
              const SizedBox(height: 4),
              Text(
                'Reviewed: ${entry.reviewedAtIso} • ${entry.reviewedByAccountId ?? '-'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachRefundRequestCard extends StatelessWidget {
  final CoachOperatorRefundQueueEntry entry;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _CoachRefundRequestCard({
    required this.entry,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.operatorName} • ${entry.from} → ${entry.to}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.refundRequestId} • ${_coachOpsQueueStatusLabel(entry.queueStatus)} • ${_coachOpsUrgencyLabel(entry.urgency)}',
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.selectedKind.name} • ${_coachOpsMoney(entry.currency, entry.requestedMinorUnits)}',
            ),
            const SizedBox(height: 4),
            Text('Tickets: ${entry.ticketIds.join(', ')}'),
            if (entry.reason != null) ...[
              const SizedBox(height: 4),
              Text('Reason: ${entry.reason}'),
            ],
            const SizedBox(height: 4),
            Text('Action: ${entry.suggestedAction}'),
            if (entry.reviewNote != null) ...[
              const SizedBox(height: 4),
              Text('Review note: ${entry.reviewNote}'),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: Text(busy ? 'Working...' : 'Approve refund'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('Reject refund'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachChangeRequestCard extends StatelessWidget {
  final CoachOperatorChangeQueueEntry entry;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _CoachChangeRequestCard({
    required this.entry,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.operatorName} • ${entry.from} → ${entry.to}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.changeRequestId} • ${_coachOpsQueueStatusLabel(entry.queueStatus)} • ${_coachOpsUrgencyLabel(entry.urgency)}',
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.targetOfferId} • due ${_coachOpsMoney(entry.currency, entry.totalDueMinorUnits)}',
            ),
            if (entry.reason != null) ...[
              const SizedBox(height: 4),
              Text('Reason: ${entry.reason}'),
            ],
            const SizedBox(height: 4),
            Text('Action: ${entry.suggestedAction}'),
            if (entry.reviewNote != null) ...[
              const SizedBox(height: 4),
              Text('Review note: ${entry.reviewNote}'),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: Text(busy ? 'Working...' : 'Approve change'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('Reject change'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
