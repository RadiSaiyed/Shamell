String shamellMaskIdentifier(
  String raw, {
  int prefix = 2,
  int suffix = 2,
}) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final safePrefix = prefix.clamp(1, value.length);
  final maxSuffix = (value.length - safePrefix).clamp(0, value.length);
  final safeSuffix = suffix.clamp(0, maxSuffix);
  if (safePrefix + safeSuffix >= value.length) {
    return value.length <= 2 ? '…' : '${value.substring(0, 1)}…';
  }
  return '${value.substring(0, safePrefix)}…${value.substring(value.length - safeSuffix)}';
}

String shamellMaskPhone(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final hasPlus = value.startsWith('+');
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.length <= 4) return hasPlus ? '+…' : '…';
  final prefixDigits = digits.length >= 11 ? 3 : 2;
  final suffixDigits = 2;
  final prefix = digits.substring(0, prefixDigits.clamp(0, digits.length));
  final suffix = digits.substring(digits.length - suffixDigits);
  return '${hasPlus ? '+' : ''}$prefix•••$suffix';
}

String shamellMaskVehiclePlate(String raw) {
  final compact = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return '';
  if (compact.length <= 3) return '…$compact';
  return '${compact.substring(0, 1)}…${compact.substring(compact.length - 2)}';
}

String shamellApproximateCoordinatePair({
  required double lat,
  required double lon,
  int decimals = 2,
}) {
  final precision = decimals.clamp(0, 6);
  return '${lat.toStringAsFixed(precision)}, ${lon.toStringAsFixed(precision)}';
}

String shamellPrivacySafePayloadSummary(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return 'empty';
  return 'present(${normalized.length} chars)';
}

String shamellPrivacySafeTextPreview(
  String raw, {
  int maxChars = 96,
}) {
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return '';
  final redactedPhones = collapsed.replaceAllMapped(
    RegExp(r'\+?\d[\d\-\s()]{6,}\d'),
    (match) => shamellMaskPhone(match.group(0) ?? ''),
  );
  if (redactedPhones.length <= maxChars) {
    return redactedPhones;
  }
  final safeLimit = maxChars.clamp(8, 280);
  return '${redactedPhones.substring(0, safeLimit - 1).trimRight()}…';
}

String shamellShortRideId(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (value.length <= 8) return value;
  return '${value.substring(0, 6)}…';
}
