import 'coach_mobility_api.dart';

class CoachPayoutImportReworkDeltaSummary {
  final int seedRowCount;
  final int draftRowCount;
  final int originalFailedRows;
  final int remainingFailedRowsEstimate;
  final int additionalRows;
  final bool isModified;
  final List<String> affectedPayoutRunIds;

  const CoachPayoutImportReworkDeltaSummary({
    required this.seedRowCount,
    required this.draftRowCount,
    required this.originalFailedRows,
    required this.remainingFailedRowsEstimate,
    required this.additionalRows,
    required this.isModified,
    required this.affectedPayoutRunIds,
  });
}

CoachPayoutImportReworkDeltaSummary? buildCoachPayoutImportReworkDelta({
  required CoachOperatorPayoutImportBatch sourceBatch,
  required String seedBody,
  required String draftBody,
}) {
  final normalizedSeed = _normalizeCoachCsvBody(seedBody);
  final normalizedDraft = _normalizeCoachCsvBody(draftBody);
  if (normalizedSeed.isEmpty) {
    return null;
  }
  final seedLines = normalizedSeed.split('\n');
  final draftLines =
      normalizedDraft.isEmpty ? const <String>[] : normalizedDraft.split('\n');
  final seedRowCount = seedLines.length > 1 ? seedLines.length - 1 : 0;
  final draftRowCount = draftLines.length > 1 ? draftLines.length - 1 : 0;
  final originalFailedRows = sourceBatch.failedRows;
  final remainingFailedRowsEstimate = originalFailedRows > draftRowCount
      ? originalFailedRows - draftRowCount
      : 0;
  final additionalRows =
      draftRowCount > seedRowCount ? draftRowCount - seedRowCount : 0;
  return CoachPayoutImportReworkDeltaSummary(
    seedRowCount: seedRowCount,
    draftRowCount: draftRowCount,
    originalFailedRows: originalFailedRows,
    remainingFailedRowsEstimate: remainingFailedRowsEstimate,
    additionalRows: additionalRows,
    isModified: normalizedSeed != normalizedDraft,
    affectedPayoutRunIds: _extractCoachPayoutRunIdsFromCsv(normalizedDraft),
  );
}

String _normalizeCoachCsvBody(String body) {
  final lines = body
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trimRight())
      .toList();
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n').trim();
}

List<String> _extractCoachPayoutRunIdsFromCsv(String body) {
  if (body.isEmpty) {
    return const <String>[];
  }
  final lines = body.split('\n');
  if (lines.length < 2) {
    return const <String>[];
  }
  final delimiter = _detectCoachCsvDelimiter(lines.first);
  final header = lines.first
      .split(delimiter)
      .map((value) => value.trim().toLowerCase())
      .toList(growable: false);
  final payoutRunIdIndex = header.indexWhere(
    (value) => const <String>[
      'payout_run_id',
      'merchant_reference',
      'metadata_payout_run_id',
    ].contains(value),
  );
  if (payoutRunIdIndex < 0) {
    return const <String>[];
  }
  final payoutRunIds = <String>[];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) {
      continue;
    }
    final cells = line.split(delimiter);
    if (payoutRunIdIndex >= cells.length) {
      continue;
    }
    final payoutRunId = cells[payoutRunIdIndex].trim();
    if (payoutRunId.isNotEmpty && !payoutRunIds.contains(payoutRunId)) {
      payoutRunIds.add(payoutRunId);
    }
  }
  return payoutRunIds;
}

String _detectCoachCsvDelimiter(String headerLine) {
  const candidates = <String>[',', ';', '\t'];
  var selected = ',';
  var selectedCount = -1;
  for (final candidate in candidates) {
    final count = headerLine.split(candidate).length;
    if (count > selectedCount) {
      selected = candidate;
      selectedCount = count;
    }
  }
  return selected;
}
