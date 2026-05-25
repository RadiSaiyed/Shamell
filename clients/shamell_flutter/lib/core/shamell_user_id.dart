import 'package:shared_preferences/shared_preferences.dart';

import 'account_identity_store.dart';

/// SyrChat user identifier (handle) distinct from chat device identity.
///
/// - SyrChat-ID: user handle (shareable; used for contact discovery)
/// - Chat-ID: device-scoped identifier used by the chat transport
const String kShamellUserIdPrefKey = 'sa.user_id';

final RegExp _kAllowed = RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$');

bool isValidShamellUserId(String v) {
  final s = v.trim().toUpperCase();
  return _kAllowed.hasMatch(s);
}

Future<String?> loadShamellUserId({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  try {
    final raw = (await loadStoredShamellUserId(
              sp: sp,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim();
    if (raw.isEmpty) return null;
    final normalized = raw.toUpperCase();
    if (!isValidShamellUserId(normalized)) {
      await clearStoredShamellUserId(
        sp: sp,
        baseUrlOverride: baseUrlOverride,
      );
      return null;
    }
    return normalized;
  } catch (_) {
    return null;
  }
}
