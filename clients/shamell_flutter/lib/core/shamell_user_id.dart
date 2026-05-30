import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Shamell user identifier (handle) distinct from chat device identity.
///
/// - Shamell-ID: user handle (shareable; used for contact discovery)
/// - Chat-ID: device-scoped identifier used by the chat transport
const String kShamellUserIdPrefKey = 'sa.user_id';

const String _kAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final RegExp _kAllowed = RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$');

String _randomId({int length = 8}) {
  final n = length.clamp(8, 32);
  Random r;
  try {
    r = Random.secure();
  } catch (_) {
    r = Random();
  }
  return List.generate(n, (_) => _kAlphabet[r.nextInt(_kAlphabet.length)])
      .join();
}

bool isValidShamellUserId(String v) {
  final s = v.trim().toUpperCase();
  return _kAllowed.hasMatch(s);
}

Future<String?> loadShamellUserId({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final raw = (prefs.getString(kShamellUserIdPrefKey) ?? '').trim();
    if (raw.isEmpty) return null;
    final normalized = raw.toUpperCase();
    if (!isValidShamellUserId(normalized)) return null;
    return normalized;
  } catch (_) {
    return null;
  }
}

Future<String> getOrCreateShamellUserId({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final existing = (prefs.getString(kShamellUserIdPrefKey) ?? '').trim();
    final normalized = existing.toUpperCase();
    if (isValidShamellUserId(normalized)) return normalized;
    final id = _randomId(length: 8);
    await prefs.setString(kShamellUserIdPrefKey, id);
    return id;
  } catch (_) {
    // Fall back to a best-effort in-memory ID.
    return _randomId(length: 8);
  }
}

