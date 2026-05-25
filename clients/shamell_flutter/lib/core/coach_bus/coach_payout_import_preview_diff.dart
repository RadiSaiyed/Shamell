import 'coach_mobility_api.dart';
import 'coach_payout_import_rework_validation.dart';

class CoachPayoutImportPreviewDiffSummary {
  final bool localDraftValid;
  final int localIssueCount;
  final int localAffectedRows;
  final int safeFixCount;
  final int safeHeaderFixCount;
  final int safeStatusFixCount;
  final int previewReadyRows;
  final int previewBlockedRows;
  final int backendFailureCount;
  final String? previewEchoChecksumSha256;
  final String? previewEchoRequestFingerprint;
  final String? previewEchoStatus;
  final String? previewEchoExpiresAtIso;
  final bool? previewEchoMatchesCurrentDraft;
  final bool? previewEchoUsableAtNow;
  final String headline;
  final String statusLine;
  final List<String> notes;

  const CoachPayoutImportPreviewDiffSummary({
    required this.localDraftValid,
    required this.localIssueCount,
    required this.localAffectedRows,
    required this.safeFixCount,
    required this.safeHeaderFixCount,
    required this.safeStatusFixCount,
    required this.previewReadyRows,
    required this.previewBlockedRows,
    required this.backendFailureCount,
    required this.previewEchoChecksumSha256,
    required this.previewEchoRequestFingerprint,
    required this.previewEchoStatus,
    required this.previewEchoExpiresAtIso,
    required this.previewEchoMatchesCurrentDraft,
    required this.previewEchoUsableAtNow,
    required this.headline,
    required this.statusLine,
    required this.notes,
  });
}

CoachPayoutImportPreviewDiffSummary buildCoachPayoutImportPreviewDiffSummary({
  required CoachPayoutImportDraftValidationSummary localValidation,
  required CoachPayoutImportDraftAutoFixResult autoFix,
  required CoachOperatorPayoutImportBatchMutationResult previewResult,
  CoachOperatorPayoutImportPreviewEcho? previewEcho,
  String? currentDraftChecksumSha256,
}) {
  final previewReadyRows = previewResult.batch.appliedRows;
  final previewBlockedRows = previewResult.batch.failedRows;
  final backendFailureCount = previewResult.failedRows.length;
  final localDraftValid = localValidation.isValid;
  final effectivePreviewEcho = previewEcho ?? previewResult.previewEcho;
  final previewEchoChecksumSha256 =
      effectivePreviewEcho?.reportChecksumSha256.trim().isEmpty ?? true
          ? null
          : effectivePreviewEcho!.reportChecksumSha256.trim();
  final previewEchoRequestFingerprint =
      effectivePreviewEcho?.requestFingerprint.trim().isEmpty ?? true
          ? null
          : effectivePreviewEcho!.requestFingerprint.trim();
  final previewEchoStatus =
      effectivePreviewEcho?.previewStatus.trim().isEmpty ?? true
          ? null
          : effectivePreviewEcho!.previewStatus.trim();
  final previewEchoExpiresAtIso =
      effectivePreviewEcho?.expiresAtIso.trim().isEmpty ?? true
          ? null
          : effectivePreviewEcho!.expiresAtIso.trim();
  final previewEchoMatchesCurrentDraft = previewEchoChecksumSha256 == null ||
          (currentDraftChecksumSha256 ?? '').isEmpty
      ? null
      : previewEchoChecksumSha256 == currentDraftChecksumSha256;
  final previewEchoUsableAtNow = effectivePreviewEcho == null
      ? null
      : effectivePreviewEcho.isUsableAt(DateTime.now().toUtc());

  late final String headline;
  if (!localDraftValid) {
    headline = 'Local draft still needs manual fixes';
  } else if (previewEchoMatchesCurrentDraft == false) {
    headline = 'Preview echo no longer matches the current draft';
  } else if (previewEchoUsableAtNow == false) {
    headline = 'Preview confirmation is no longer active';
  } else if (previewBlockedRows > 0 || backendFailureCount > 0) {
    headline = 'Backend preview still blocks some rows';
  } else {
    headline = 'Preview ready for apply';
  }

  final notes = <String>[];
  if (autoFix.hasChanges) {
    notes.add(
      'Safe fixes available: ${autoFix.headerFixCount} headers, ${autoFix.statusFixCount} statuses.',
    );
  } else {
    notes.add('No safe local auto-fixes are pending.');
  }
  if (!localDraftValid) {
    notes.add(
      'Apply stays blocked until ${localValidation.issueCount} local issues are resolved.',
    );
  } else {
    notes.add('Local draft is clean.');
  }
  if (backendFailureCount > 0) {
    final firstFailure = previewResult.failedRows.first;
    notes.add(
      'Backend blocked line ${firstFailure.lineNumber}: ${firstFailure.detail}',
    );
  } else if (previewBlockedRows > 0) {
    notes.add(
        'Backend preview still reports blocked rows without line-level details.');
  } else {
    notes.add('Backend preview did not report blocked rows.');
  }
  if (previewEchoChecksumSha256 != null) {
    notes.add('Server echo checksum: $previewEchoChecksumSha256');
  }
  if (previewEchoMatchesCurrentDraft != null) {
    notes.add(
      previewEchoMatchesCurrentDraft
          ? 'Server echo matches the current draft.'
          : 'Server echo no longer matches the current draft.',
    );
  }
  if (previewEchoStatus != null) {
    notes.add('Preview status: $previewEchoStatus');
  }
  if (previewEchoExpiresAtIso != null) {
    notes.add('Preview expires at: $previewEchoExpiresAtIso');
  }
  if (previewEchoUsableAtNow != null) {
    notes.add(
      previewEchoUsableAtNow
          ? 'Preview confirmation is currently active.'
          : 'Preview confirmation is no longer usable.',
    );
  }
  if (previewEchoRequestFingerprint != null) {
    notes.add('Preview fingerprint: $previewEchoRequestFingerprint');
  }
  notes.add('Next action: ${previewResult.nextAction}');

  return CoachPayoutImportPreviewDiffSummary(
    localDraftValid: localDraftValid,
    localIssueCount: localValidation.issueCount,
    localAffectedRows: localValidation.affectedRowCount,
    safeFixCount: autoFix.totalFixCount,
    safeHeaderFixCount: autoFix.headerFixCount,
    safeStatusFixCount: autoFix.statusFixCount,
    previewReadyRows: previewReadyRows,
    previewBlockedRows: previewBlockedRows,
    backendFailureCount: backendFailureCount,
    previewEchoChecksumSha256: previewEchoChecksumSha256,
    previewEchoRequestFingerprint: previewEchoRequestFingerprint,
    previewEchoStatus: previewEchoStatus,
    previewEchoExpiresAtIso: previewEchoExpiresAtIso,
    previewEchoMatchesCurrentDraft: previewEchoMatchesCurrentDraft,
    previewEchoUsableAtNow: previewEchoUsableAtNow,
    headline: headline,
    statusLine:
        'Local issues ${localValidation.issueCount} across ${localValidation.affectedRowCount} rows • safe fixes ${autoFix.totalFixCount} • preview ready $previewReadyRows • preview blocked $previewBlockedRows',
    notes: notes,
  );
}
