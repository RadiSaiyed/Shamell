/// Parses user-entered amount into cents.
/// Accepts either raw cents (e.g., "1250") or decimal major units (e.g., "12.50" or "12,50").
int parseCents(String s) {
  if (s.isEmpty) return 0;
  final hasComma = s.contains(',');
  final hasDot = s.contains('.');
  String x = s;
  if (hasComma && hasDot) {
    // Likely thousand separators + decimal dot: remove commas
    x = x.replaceAll(',', '');
  } else if (hasComma && !hasDot) {
    // Decimal separator is comma
    x = x.replaceAll(',', '.');
  }
  final hasDec = x.contains('.');
  final norm = x.replaceAll(RegExp(r'[^0-9\.]'), '');
  if (norm.isEmpty) return 0;
  if (hasDec) {
    final d = double.tryParse(norm);
    if (d == null) return int.tryParse(norm) ?? 0;
    final v = (d * 100).round();
    return v < 0 ? 0 : v;
  }
  return int.tryParse(norm) ?? 0;
}

/// Builds the target payload for a transfer.
/// - If input starts with '@', returns {to_alias: input}
/// - Else returns {to_wallet_id: resolvedWalletId ?? input}
Map<String, dynamic> buildTransferTarget(String input, {String? resolvedWalletId}) {
  final to = input.trim();
  if (to.startsWith('@')) return {'to_alias': to};
  if ((resolvedWalletId ?? '').isNotEmpty) return {'to_wallet_id': resolvedWalletId};
  return {'to_wallet_id': to};
}
