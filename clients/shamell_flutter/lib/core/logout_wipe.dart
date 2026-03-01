import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat/chat_service.dart';
import 'device_id.dart';
import 'session_cookie_store.dart';
import 'ui_prefs.dart';

// Best practice: on logout/switch-account, wipe all account-scoped local data
// to prevent cross-account leakage. Preserve only explicit device preferences.
const Set<String> _kPreservePrefsKeys = <String>{
  // Environment/device prefs.
  'base_url',
  'app_mode',
  kStableDeviceIdPrefKey,
  kUiLocaleKey,
  kUiTextScaleKey,
  kUiThemeModeKey,
  'require_biometrics',

  // Shamell "Plugins" toggles (device preference).
  'shamell.plugins.show_moments',
  'shamell.plugins.show_channels',
  'shamell.plugins.show_scan',
  'shamell.plugins.show_mini_programs',
  'shamell.plugins.show_cards_offers',

  // Notification preferences (device preference).
  'chat.notify.preview',
  'chat.notify.enabled',
  'chat.notify.sound',
  'chat.notify.vibrate',
  'chat.notify.dnd',
  'chat.notify.dnd_start',
  'chat.notify.dnd_end',
};

Map<String, Object> _snapshotPrefs(SharedPreferences sp, Set<String> keys) {
  final out = <String, Object>{};
  for (final k in keys) {
    final v = sp.get(k);
    if (v == null) continue;
    if (v is bool || v is int || v is double || v is String) {
      out[k] = v;
      continue;
    }
    if (v is List<String>) {
      out[k] = List<String>.from(v);
      continue;
    }
  }
  return out;
}

Future<void> _restorePrefs(
    SharedPreferences sp, Map<String, Object> snapshot) async {
  for (final e in snapshot.entries) {
    final k = e.key;
    final v = e.value;
    try {
      if (v is bool) {
        await sp.setBool(k, v);
      } else if (v is int) {
        await sp.setInt(k, v);
      } else if (v is double) {
        await sp.setDouble(k, v);
      } else if (v is String) {
        await sp.setString(k, v);
      } else if (v is List<String>) {
        await sp.setStringList(k, v);
      }
    } catch (_) {}
  }
}

const FlutterSecureStorage _shamellSecureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device),
);

const FlutterSecureStorage _chatSecureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: true,
    sharedPreferencesName: 'chat_secure_store',
  ),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device),
);

Future<void> _wipeSecureStoreAll(FlutterSecureStorage sec) async {
  try {
    await sec.deleteAll();
    return;
  } catch (_) {}

  // Fallback: enumerate keys and delete individually.
  try {
    final all = await sec.readAll();
    for (final k in all.keys) {
      try {
        await sec.delete(key: k);
      } catch (_) {}
    }
  } catch (_) {}
}

Future<void> wipeLocalAccountData({bool preserveDevicePrefs = true}) async {
  // 1) Clear session material.
  try {
    await clearSessionCookie();
  } catch (_) {}

  // 2) Clear chat/session secrets stored in secure storage.
  try {
    await ChatLocalStore().wipeSecrets();
  } catch (_) {}

  // 3) Clear SharedPreferences, preserving only device prefs.
  try {
    final sp = await SharedPreferences.getInstance();
    final preserved = preserveDevicePrefs
        ? _snapshotPrefs(sp, _kPreservePrefsKeys)
        : <String, Object>{};
    await sp.clear();
    if (preserved.isNotEmpty) {
      await _restorePrefs(sp, preserved);
    }
  } catch (_) {}
}

/// "Forget this device" local wipe:
/// - clears all SharedPreferences (including stable device id)
/// - wipes secure storage (biometric tokens, local password, session, chat secrets)
Future<void> wipeLocalForForgetDevice() async {
  await wipeLocalAccountData(preserveDevicePrefs: false);
  await _wipeSecureStoreAll(_shamellSecureStore);
  await _wipeSecureStoreAll(_chatSecureStore);
}
