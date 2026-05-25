String? sanitizeDeviceLoginLabel(
  String? raw, {
  int maxChars = 64,
}) {
  if (maxChars <= 0) return null;
  final input = (raw ?? '').trim();
  if (input.isEmpty) return null;
  final out = StringBuffer();
  var count = 0;
  var prevWasSpace = false;
  for (final rune in input.runes) {
    if (_isBlockedDeviceLoginLabelRune(rune)) continue;
    final ch = String.fromCharCode(rune);
    final isSpace = ch.trim().isEmpty;
    if (isSpace) {
      if (out.isEmpty || prevWasSpace) continue;
      out.write(' ');
      prevWasSpace = true;
      count += 1;
      if (count >= maxChars) break;
      continue;
    }
    out.write(ch);
    prevWasSpace = false;
    count += 1;
    if (count >= maxChars) break;
  }
  final normalized = out.toString().trim();
  if (normalized.isEmpty) return null;
  return normalized;
}

bool _isBlockedDeviceLoginLabelRune(int rune) {
  // C0/C1 controls
  if (rune <= 0x001f || (rune >= 0x007f && rune <= 0x009f)) return true;
  // Arabic letter mark + classic bidi override/isolate controls.
  if (rune == 0x061c) return true;
  if ((rune >= 0x200e && rune <= 0x200f) ||
      (rune >= 0x202a && rune <= 0x202e) ||
      (rune >= 0x2066 && rune <= 0x2069)) {
    return true;
  }
  return false;
}
