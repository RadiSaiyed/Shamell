import 'package:shared_preferences/shared_preferences.dart';

/// Persistent storage for the *auth* username (the one the user typed
/// at signup / signin), distinct from:
///   - the SyrChat-ID (a server-assigned 8-char handle used to discover
///     contacts cross-account), and
///   - the chat device-ID (transport-only identifier).
///
/// The auth username is the friendly handle that appears under the
/// display name on the Profile / Me hero — "logged in as @anna_m".
/// It is single-tenant per device install: on every successful login
/// we overwrite the stored value, and on "Logout & Forget Device" we
/// clear it (see `clearProfileUsername` callsite in logout_wipe.dart).
const String kProfileUsernamePrefKey = 'sa.profile_username.v1';

/// Save the auth username. Empty/whitespace input clears the stored
/// value — we never want a blank handle to flash on Profile.
Future<void> saveProfileUsername(
  String username, {
  SharedPreferences? sp,
}) async {
  final trimmed = username.trim();
  final prefs = sp ?? await SharedPreferences.getInstance();
  if (trimmed.isEmpty) {
    await prefs.remove(kProfileUsernamePrefKey);
    return;
  }
  await prefs.setString(kProfileUsernamePrefKey, trimmed);
}

/// Load the auth username, or `null` if none was persisted. Callers
/// should treat `null` as "fall back to the SyrChat-ID" so the UI
/// never shows a blank handle.
Future<String?> loadProfileUsername({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final raw = (prefs.getString(kProfileUsernamePrefKey) ?? '').trim();
    if (raw.isEmpty) return null;
    return raw;
  } catch (_) {
    return null;
  }
}

/// Remove the stored username — wired into the "Logout & Forget
/// Device" path so the next user on this device doesn't inherit the
/// previous handle.
Future<void> clearProfileUsername({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(kProfileUsernamePrefKey);
  } catch (_) {}
}
