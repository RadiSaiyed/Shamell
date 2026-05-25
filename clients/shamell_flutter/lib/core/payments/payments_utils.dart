import 'package:flutter/foundation.dart' show kIsWeb;

/// Parses user-entered amount into cents.
/// Accepts either raw cents (e.g., "1250") or decimal major units (e.g., "12.50" or "12,50").
const String _maxI64ValueDecimal = '9223372036854775807';
const int _maxJsSafeIntegerValue = 9007199254740991;

int parseCents(String s) {
  final raw = s.trim();
  if (raw.isEmpty) return 0;

  // Fail closed on explicit signs/scientific notation instead of attempting to
  // salvage input (e.g. "-5" previously became "5").
  if (raw.startsWith('-') ||
      raw.startsWith('+') ||
      raw.contains(RegExp(r'[eE]'))) {
    return 0;
  }

  final compact = raw.replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return 0;

  String normalized;
  if (compact.contains(',') && compact.contains('.')) {
    // Allow grouped thousands with dot decimal only: 1,234.56
    if (!RegExp(r'^\d{1,3}(,\d{3})+(\.\d{1,2})?$').hasMatch(compact)) {
      return 0;
    }
    normalized = compact.replaceAll(',', '');
  } else if (compact.contains(',')) {
    // Allow comma decimal separator: 12,50
    if (!RegExp(r'^\d+(,\d{1,2})?$').hasMatch(compact)) {
      return 0;
    }
    normalized = compact.replaceFirst(',', '.');
  } else {
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(compact)) {
      return 0;
    }
    normalized = compact;
  }

  final dot = normalized.indexOf('.');
  if (dot < 0) {
    final cents = int.tryParse(normalized) ?? 0;
    return cents >= 0 ? cents : 0;
  }

  final wholeRaw = normalized.substring(0, dot);
  final fracRaw = normalized.substring(dot + 1);
  final whole = int.tryParse(wholeRaw);
  if (whole == null || whole < 0) return 0;

  final fracPadded = fracRaw.padRight(2, '0');
  final frac = int.tryParse(fracPadded);
  if (frac == null || frac < 0) return 0;

  final cents = whole * 100 + frac;
  final maxCents =
      kIsWeb ? _maxJsSafeIntegerValue : int.parse(_maxI64ValueDecimal);
  if (cents > maxCents) return 0;
  return cents;
}

Map<String, Object?> buildTransferTarget(
  String raw,
) {
  final v = raw.trim();
  if (v.isEmpty) return const <String, Object?>{};
  final isPhone = v.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(v);
  if (isPhone) {
    // Permanently disabled: never use phone numbers as payment routing identifiers.
    return const <String, Object?>{};
  }
  if (v.startsWith('@')) {
    return <String, Object?>{'to_alias': v};
  }
  return <String, Object?>{'to_wallet_id': v};
}
