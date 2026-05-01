import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Stable (non-secret) identifier for this app install.
///
/// This is used for device session binding / revocation on the backend.
const String kStableDeviceIdPrefKey = 'sa.device_id';

String _randomHexId({int length = 16}) {
  const chars = 'abcdef0123456789';
  Random r;
  try {
    r = Random.secure();
  } catch (_) {
    r = Random();
  }
  final n = length.clamp(8, 64);
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

Future<String?> loadStableDeviceId() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = (sp.getString(kStableDeviceIdPrefKey) ?? '').trim();
    if (raw.isEmpty) return null;
    return raw;
  } catch (_) {
    return null;
  }
}

Future<String> getOrCreateStableDeviceId() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = (sp.getString(kStableDeviceIdPrefKey) ?? '').trim();
    if (raw.isNotEmpty) return raw;
    final id = _randomHexId();
    await sp.setString(kStableDeviceIdPrefKey, id);
    return id;
  } catch (_) {
    // Fall back to a best-effort in-memory ID.
    return _randomHexId();
  }
}

