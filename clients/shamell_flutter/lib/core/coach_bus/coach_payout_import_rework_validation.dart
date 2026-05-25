import 'coach_mobility_api.dart';

class CoachPayoutImportDraftValidationIssue {
  final int? lineNumber;
  final String fieldKey;
  final String message;
  final String? currentValue;
  final String? suggestion;

  const CoachPayoutImportDraftValidationIssue({
    required this.lineNumber,
    required this.fieldKey,
    required this.message,
    this.currentValue,
    this.suggestion,
  });
}

class CoachPayoutImportDraftValidationSummary {
  final int totalRows;
  final List<String> headerIssues;
  final List<CoachPayoutImportDraftValidationIssue> rowIssues;

  const CoachPayoutImportDraftValidationSummary({
    required this.totalRows,
    required this.headerIssues,
    required this.rowIssues,
  });

  bool get isValid => headerIssues.isEmpty && rowIssues.isEmpty;

  int get issueCount => headerIssues.length + rowIssues.length;

  int get affectedRowCount => rowIssues
      .where((issue) => issue.lineNumber != null)
      .map((issue) => issue.lineNumber!)
      .toSet()
      .length;

  List<CoachPayoutImportDraftValidationIssue> get correctionHints => rowIssues
      .where((issue) => (issue.suggestion ?? '').trim().isNotEmpty)
      .toList(growable: false);
}

class CoachPayoutImportDraftAutoFixResult {
  final String correctedBody;
  final int headerFixCount;
  final int statusFixCount;

  const CoachPayoutImportDraftAutoFixResult({
    required this.correctedBody,
    required this.headerFixCount,
    required this.statusFixCount,
  });

  bool get hasChanges => totalFixCount > 0;

  int get totalFixCount => headerFixCount + statusFixCount;
}

CoachPayoutImportDraftValidationSummary buildCoachPayoutImportDraftValidation({
  required CoachOperatorPayoutImportProfile profile,
  required String draftBody,
}) {
  final normalizedDraft = _normalizeCoachCsvBody(draftBody);
  if (normalizedDraft.isEmpty) {
    return const CoachPayoutImportDraftValidationSummary(
      totalRows: 0,
      headerIssues: <String>['CSV report body is empty.'],
      rowIssues: <CoachPayoutImportDraftValidationIssue>[],
    );
  }
  final lines = normalizedDraft.split('\n');
  final headerLine = lines.first;
  final delimiter =
      _detectCoachCsvDelimiter(headerLine, profile.supportedDelimiters);
  final headerCells = headerLine
      .split(delimiter)
      .map((value) => value.trim().toLowerCase())
      .toList(growable: false);
  final headerIssues = <String>[];
  final rowIssues = <CoachPayoutImportDraftValidationIssue>[];
  final fieldIndexByKey = <String, int?>{};

  for (final field in profile.fields) {
    fieldIndexByKey[field.key] = _findHeaderIndex(
      headerCells,
      _acceptedHeadersForField(profile, field.key),
    );
    if (field.required && fieldIndexByKey[field.key] == null) {
      headerIssues.add(
        'Missing required column for ${field.key}: ${field.acceptedHeaders.join(' / ')}',
      );
    }
  }

  final statusFieldIndex = _findHeaderIndex(
    headerCells,
    _acceptedHeadersForField(profile, 'external_status'),
  );
  final statusMappingByAcceptedValue =
      <String, CoachOperatorPayoutImportStatusMapping>{};
  for (final mapping in profile.statusMappings) {
    for (final acceptedValue in mapping.acceptedValues) {
      final normalizedValue = acceptedValue.trim().toLowerCase();
      if (normalizedValue.isNotEmpty) {
        statusMappingByAcceptedValue.putIfAbsent(
            normalizedValue, () => mapping);
      }
    }
  }

  final dataLines = lines
      .skip(1)
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (dataLines.isEmpty) {
    headerIssues.add('CSV report body must include at least one data row.');
  }

  for (var index = 0; index < dataLines.length; index++) {
    final line = dataLines[index];
    final lineNumber = index + 2;
    final cells = line
        .split(delimiter)
        .map((value) => value.trim())
        .toList(growable: false);
    for (final field in profile.fields.where((field) => field.required)) {
      final fieldIndex = fieldIndexByKey[field.key];
      if (fieldIndex == null) {
        continue;
      }
      final fieldValue =
          fieldIndex < cells.length ? cells[fieldIndex].trim() : '';
      if (fieldValue.isEmpty) {
        rowIssues.add(
          CoachPayoutImportDraftValidationIssue(
            lineNumber: lineNumber,
            fieldKey: field.key,
            message: '${field.key} is required.',
            currentValue: fieldValue.isEmpty ? null : fieldValue,
            suggestion: _buildMissingFieldSuggestion(
              field.key,
              statusValue: _statusValueForLine(
                cells: cells,
                statusFieldIndex: statusFieldIndex,
              ),
            ),
          ),
        );
      }
    }
    if (statusFieldIndex == null) {
      continue;
    }
    final statusValue =
        statusFieldIndex < cells.length ? cells[statusFieldIndex].trim() : '';
    if (statusValue.isEmpty) {
      rowIssues.add(
        CoachPayoutImportDraftValidationIssue(
          lineNumber: lineNumber,
          fieldKey: 'external_status',
          message: 'external_status is required.',
          suggestion:
              'Set external_status to one of: ${_collectAcceptedStatusValues(profile).join(', ')}.',
        ),
      );
      continue;
    }
    final statusMapping =
        statusMappingByAcceptedValue[statusValue.trim().toLowerCase()];
    if (statusMapping == null) {
      rowIssues.add(
        CoachPayoutImportDraftValidationIssue(
          lineNumber: lineNumber,
          fieldKey: 'external_status',
          message:
              'Unsupported status "$statusValue". Expected ${statusMappingByAcceptedValue.keys.join(', ')}.',
          currentValue: statusValue,
          suggestion:
              'Use one of: ${_collectAcceptedStatusValues(profile).join(', ')}.',
        ),
      );
      continue;
    }
    for (final requiredFieldKey in statusMapping.requiredFields) {
      final fieldIndex = _findHeaderIndex(
        headerCells,
        _acceptedHeadersForField(profile, requiredFieldKey),
      );
      final fieldValue = fieldIndex != null && fieldIndex < cells.length
          ? cells[fieldIndex].trim()
          : '';
      if (fieldValue.isEmpty) {
        rowIssues.add(
          CoachPayoutImportDraftValidationIssue(
            lineNumber: lineNumber,
            fieldKey: requiredFieldKey,
            message:
                '$requiredFieldKey is required when status maps to ${statusMapping.normalizedStatus}.',
            suggestion: _buildMissingFieldSuggestion(
              requiredFieldKey,
              statusValue: statusValue,
              normalizedStatus: statusMapping.normalizedStatus,
            ),
          ),
        );
      }
    }
  }

  return CoachPayoutImportDraftValidationSummary(
    totalRows: dataLines.length,
    headerIssues: headerIssues,
    rowIssues: rowIssues,
  );
}

CoachPayoutImportDraftAutoFixResult buildCoachPayoutImportDraftAutoFix({
  required CoachOperatorPayoutImportProfile profile,
  required String draftBody,
}) {
  final normalizedDraft = _normalizeCoachCsvBody(draftBody);
  if (normalizedDraft.isEmpty) {
    return const CoachPayoutImportDraftAutoFixResult(
      correctedBody: '',
      headerFixCount: 0,
      statusFixCount: 0,
    );
  }
  final lines = normalizedDraft.split('\n');
  final delimiter =
      _detectCoachCsvDelimiter(lines.first, profile.supportedDelimiters);
  final canonicalizedHeader = _canonicalizeHeaderCells(
    profile: profile,
    headerCells: lines.first.split(delimiter),
  );
  var statusFixCount = 0;
  final statusIndex = _findHeaderIndex(
    canonicalizedHeader.canonicalCells
        .map((value) => value.trim().toLowerCase())
        .toList(growable: false),
    _acceptedHeadersForField(profile, 'external_status'),
  );
  final normalizedRows = lines.skip(1).map((line) {
    final cells = line.split(delimiter).map((value) => value.trim()).toList();
    if (statusIndex != null && statusIndex < cells.length) {
      final statusValue = cells[statusIndex].trim();
      final normalizedStatus =
          _normalizedStatusForAcceptedValue(profile, statusValue);
      if (normalizedStatus != null && normalizedStatus != statusValue) {
        cells[statusIndex] = normalizedStatus;
        statusFixCount += 1;
      }
    }
    return cells.join(delimiter);
  }).toList(growable: false);
  return CoachPayoutImportDraftAutoFixResult(
    correctedBody: <String>[
      canonicalizedHeader.canonicalCells.join(delimiter),
      ...normalizedRows,
    ].join('\n'),
    headerFixCount: canonicalizedHeader.fixCount,
    statusFixCount: statusFixCount,
  );
}

String _statusValueForLine({
  required List<String> cells,
  required int? statusFieldIndex,
}) {
  if (statusFieldIndex == null || statusFieldIndex >= cells.length) {
    return '';
  }
  return cells[statusFieldIndex].trim();
}

String _buildMissingFieldSuggestion(
  String fieldKey, {
  String? statusValue,
  String? normalizedStatus,
}) {
  switch (fieldKey) {
    case 'payment_reference':
      if ((normalizedStatus ?? '').trim().isNotEmpty) {
        return 'Add the transfer or payout reference before applying this ${normalizedStatus!.trim()} row.';
      }
      return 'Add the bank or PSP transfer reference for this row.';
    case 'external_reference':
      return 'Add the external file, settlement, or report reference from the payout rail.';
    case 'external_status':
      return 'Set the payout status using a value accepted by the selected import profile.';
    case 'payout_run_id':
      return 'Fill the SyrChat payout run id or the mapped merchant reference column.';
    default:
      final trimmedStatus = statusValue?.trim() ?? '';
      if (trimmedStatus.isNotEmpty) {
        return 'Fill $fieldKey for the row with status "$trimmedStatus".';
      }
      return 'Fill the missing $fieldKey value in this CSV row.';
  }
}

List<String> _collectAcceptedStatusValues(
  CoachOperatorPayoutImportProfile profile,
) {
  final values = <String>[];
  final seen = <String>{};
  for (final mapping in profile.statusMappings) {
    for (final acceptedValue in mapping.acceptedValues) {
      final trimmed = acceptedValue.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        values.add(trimmed);
      }
    }
  }
  return values;
}

String? _normalizedStatusForAcceptedValue(
  CoachOperatorPayoutImportProfile profile,
  String rawStatusValue,
) {
  final normalizedRawStatusValue = rawStatusValue.trim().toLowerCase();
  if (normalizedRawStatusValue.isEmpty) {
    return null;
  }
  for (final mapping in profile.statusMappings) {
    for (final acceptedValue in mapping.acceptedValues) {
      if (acceptedValue.trim().toLowerCase() == normalizedRawStatusValue) {
        return mapping.normalizedStatus;
      }
    }
  }
  return null;
}

class _CoachCanonicalizedHeaderCells {
  final List<String> canonicalCells;
  final int fixCount;

  const _CoachCanonicalizedHeaderCells({
    required this.canonicalCells,
    required this.fixCount,
  });
}

_CoachCanonicalizedHeaderCells _canonicalizeHeaderCells({
  required CoachOperatorPayoutImportProfile profile,
  required List<String> headerCells,
}) {
  final trimmedHeaderCells =
      headerCells.map((value) => value.trim()).toList(growable: false);
  final targetKeysByIndex = <int, String?>{};
  final targetKeyCounts = <String, int>{};
  for (var index = 0; index < trimmedHeaderCells.length; index++) {
    final targetKey =
        _canonicalFieldKeyForHeader(profile, trimmedHeaderCells[index]);
    targetKeysByIndex[index] = targetKey;
    if (targetKey != null) {
      targetKeyCounts[targetKey] = (targetKeyCounts[targetKey] ?? 0) + 1;
    }
  }
  var fixCount = 0;
  final canonicalCells = <String>[];
  for (var index = 0; index < trimmedHeaderCells.length; index++) {
    final currentHeader = trimmedHeaderCells[index];
    final normalizedCurrentHeader = currentHeader.toLowerCase();
    final targetKey = targetKeysByIndex[index];
    if (targetKey == null ||
        normalizedCurrentHeader == targetKey ||
        (targetKeyCounts[targetKey] ?? 0) > 1) {
      canonicalCells.add(currentHeader);
      continue;
    }
    canonicalCells.add(targetKey);
    fixCount += 1;
  }
  return _CoachCanonicalizedHeaderCells(
    canonicalCells: canonicalCells,
    fixCount: fixCount,
  );
}

String? _canonicalFieldKeyForHeader(
  CoachOperatorPayoutImportProfile profile,
  String rawHeader,
) {
  final normalizedHeader = rawHeader.trim().toLowerCase();
  if (normalizedHeader.isEmpty) {
    return null;
  }
  for (final field in profile.fields) {
    if (field.key.trim().toLowerCase() == normalizedHeader) {
      return field.key;
    }
    for (final acceptedHeader in field.acceptedHeaders) {
      if (acceptedHeader.trim().toLowerCase() == normalizedHeader) {
        return field.key;
      }
    }
  }
  return null;
}

int? _findHeaderIndex(List<String> headerCells, List<String> acceptedHeaders) {
  for (final acceptedHeader in acceptedHeaders) {
    final normalized = acceptedHeader.trim().toLowerCase();
    if (normalized.isEmpty) {
      continue;
    }
    final index = headerCells.indexOf(normalized);
    if (index >= 0) {
      return index;
    }
  }
  return null;
}

List<String> _acceptedHeadersForField(
  CoachOperatorPayoutImportProfile profile,
  String fieldKey,
) {
  for (final field in profile.fields) {
    if (field.key == fieldKey && field.acceptedHeaders.isNotEmpty) {
      return field.acceptedHeaders;
    }
  }
  return <String>[fieldKey];
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

String _detectCoachCsvDelimiter(
    String headerLine, List<String> supportedLabels) {
  final candidates = {
    for (final label in supportedLabels)
      switch (label.trim().toLowerCase()) {
        'semicolon' => ';',
        'tab' => '\t',
        _ => ',',
      },
  }.toList(growable: false);
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
