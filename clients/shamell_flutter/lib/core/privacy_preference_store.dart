// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String kPrivacyFriendVerificationPrefKey =
    'shamell.privacy.friend_verification';
// Deprecated compatibility-only keys. The active product privacy surface no
// longer exposes local Moments/Status toggles, but old installs may still
// carry persisted values that should be cleared.
const String kPrivacyMomentsAllowStrangersTenPostsPrefKey =
    'shamell.privacy.moments.allow_strangers_ten_posts';
const String kPrivacyMomentsUpdateRemindersPrefKey =
    'shamell.privacy.moments.update_reminders';
const String kPrivacyStatusVisibleToOthersPrefKey =
    'shamell.privacy.status.visible_to_others';

const FlutterSecureStorage _privacyPreferenceSecureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  mOptions:
      MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
);

class _SecureBoolReadResult {
  final bool? value;
  final bool failed;
  const _SecureBoolReadResult({
    required this.value,
    required this.failed,
  });
}

const String _privacyPreferencesUnknownScope = 'unknown';
const String _privacyPreferencesBaseUrlPrefKey = 'base_url';
const Set<String> _deprecatedPrivacyLegacyPrefKeys = <String>{
  'shamell.privacy.search_by_id',
  'shamell.privacy.add_me.by_id',
  'shamell.privacy.add_me.by_qr',
  'shamell.privacy.add_me.by_group',
  'shamell.privacy.add_me.by_card',
  kPrivacyMomentsAllowStrangersTenPostsPrefKey,
  kPrivacyMomentsUpdateRemindersPrefKey,
  kPrivacyStatusVisibleToOthersPrefKey,
};
const Set<String> _deprecatedPrivacyLegacySecureKeys = <String>{
  'privacy.add_me.by_id.v1',
  'privacy.add_me.by_qr.v1',
  'privacy.add_me.by_group.v1',
  'privacy.add_me.by_card.v1',
  'privacy.moments.allow_strangers_ten_posts.v1',
  'privacy.moments.update_reminders.v1',
  'privacy.status.visible_to_others.v1',
};
const Set<String> _deprecatedPrivacyScopedKeyPrefixes = <String>{
  'privacy.add_me.by_id.v2.',
  'privacy.add_me.by_qr.v2.',
  'privacy.add_me.by_group.v2.',
  'privacy.add_me.by_card.v2.',
  'privacy.moments.allow_strangers_ten_posts.v2.',
  'privacy.moments.update_reminders.v2.',
  'privacy.status.visible_to_others.v2.',
};

const Map<String, _PrivacyPreferenceSpec> _privacyPreferenceSpecs =
    <String, _PrivacyPreferenceSpec>{
  kPrivacyFriendVerificationPrefKey: _PrivacyPreferenceSpec(
    legacySecureKey: 'privacy.friend_verification.v1',
    scopedKeyPrefix: 'privacy.friend_verification.v2.',
  ),
};

Future<bool> loadPrivacyPreferenceValue(
  String key, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final spec = _privacyPreferenceSpecs[key];
  if (spec == null) return false;
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentPrivacyPreferencesScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedPrivacyPreferenceKey(spec.scopedKeyPrefix, scope);

  if (_canPersistSecurePrivacyPreferences()) {
    var secureReadFailed = false;
    final secureRead = await _readSecurePrivacyPreference(scopedKey);
    secureReadFailed = secureRead.failed;
    final secure = secureRead.value;
    if (secure != null) {
      await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
      return secure;
    }

    final legacySecureRead =
        await _readSecurePrivacyPreference(spec.legacySecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = legacySecureRead.value;
    if (legacySecure != null) {
      if (_isUnknownPrivacyPreferencesScope(scope)) {
        final migrated =
            await _writeSecurePrivacyPreference(scopedKey, legacySecure);
        if (migrated) {
          await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
          return legacySecure;
        }
        await _deleteSecurePrivacyPreference(scopedKey);
        if (secureReadFailed) {
          return legacySecure;
        }
      }
      await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
      return true;
    }

    // Fail closed by default: do not trust mutable SharedPreferences values
    // unless fallback is explicitly enabled or secure storage is unavailable.
    if (!_allowLegacyPrivacyPreferenceFallback() && !secureReadFailed) {
      await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
      return true;
    }

    try {
      for (final legacyKey in <String>[key]) {
        final legacy = prefs.getBool(legacyKey);
        if (legacy == null) continue;
        if (_isUnknownPrivacyPreferencesScope(scope)) {
          final migrated =
              await _writeSecurePrivacyPreference(scopedKey, legacy);
          if (migrated) {
            await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
            return legacy;
          }
          await _deleteSecurePrivacyPreference(scopedKey);
          if (secureReadFailed) {
            return legacy;
          }
        }
        await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
        return true;
      }
    } catch (_) {}

    return true;
  }

  try {
    final scoped = prefs.getBool(scopedKey);
    if (scoped != null) {
      await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
      return scoped;
    }
    for (final legacyKey in <String>[key]) {
      final value = prefs.getBool(legacyKey);
      if (value != null) {
        await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
        if (_isUnknownPrivacyPreferencesScope(scope)) {
          await prefs.setBool(scopedKey, value);
          return value;
        }
        return true;
      }
    }
  } catch (_) {}

  return true;
}

Future<bool> savePrivacyPreferenceValue(
  String key,
  bool value, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final spec = _privacyPreferenceSpecs[key];
  if (spec == null) return false;
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scopedKey = _scopedPrivacyPreferenceKey(
    spec.scopedKeyPrefix,
    _currentPrivacyPreferencesScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    ),
  );

  if (_canPersistSecurePrivacyPreferences()) {
    final wrote = await _writeSecurePrivacyPreference(scopedKey, value);
    await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
    if (!wrote) {
      await _deleteSecurePrivacyPreference(scopedKey);
    }
    return wrote;
  }

  try {
    await prefs.setBool(scopedKey, value);
    await _removeLegacyPrivacyPreference(key, spec, sp: prefs);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> clearPrivacyPreferenceState({SharedPreferences? sp}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  if (_canPersistSecurePrivacyPreferences()) {
    await _clearAllPrivacyPreferenceSecureKeys();
  }

  try {
    await _clearAllPrivacyPreferencePrefs(prefs);
  } catch (_) {}
}

bool _canPersistSecurePrivacyPreferences() => !kIsWeb;

bool _allowLegacyPrivacyPreferenceFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_PRIVACY_PREFERENCE_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_PRIVACY_PREFERENCE_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_PRIVACY_PREFERENCE_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_PRIVACY_PREFERENCE_FALLBACK',
    defaultValue: true,
  );
}

Future<void> _removeLegacyPrivacyPreference(
  String key,
  _PrivacyPreferenceSpec spec, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(key);
    if (_canPersistSecurePrivacyPreferences()) {
      await _deleteSecurePrivacyPreference(spec.legacySecureKey);
    }
  } catch (_) {}
}

Future<_SecureBoolReadResult> _readSecurePrivacyPreference(String key) async {
  try {
    final raw = (await _privacyPreferenceSecureStore.read(key: key) ?? '')
        .trim()
        .toLowerCase();
    if (raw.isEmpty) {
      return const _SecureBoolReadResult(value: null, failed: false);
    }
    if (raw == '1' || raw == 'true') {
      return const _SecureBoolReadResult(value: true, failed: false);
    }
    if (raw == '0' || raw == 'false') {
      return const _SecureBoolReadResult(value: false, failed: false);
    }
    return const _SecureBoolReadResult(value: null, failed: false);
  } catch (_) {
    return const _SecureBoolReadResult(value: null, failed: true);
  }
}

Future<bool> _writeSecurePrivacyPreference(String key, bool value) async {
  try {
    final encoded = value ? '1' : '0';
    await _privacyPreferenceSecureStore.write(key: key, value: encoded);
    final roundTrip =
        (await _privacyPreferenceSecureStore.read(key: key) ?? '').trim();
    return roundTrip == encoded;
  } catch (_) {
    return false;
  }
}

Future<bool> _deleteSecurePrivacyPreference(String key) async {
  try {
    await _privacyPreferenceSecureStore.delete(key: key);
    final roundTrip =
        (await _privacyPreferenceSecureStore.read(key: key) ?? '').trim();
    return roundTrip.isEmpty;
  } catch (_) {
    return false;
  }
}

String _currentPrivacyPreferencesScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final rawBase = (baseUrlOverride ??
          prefs.getString(_privacyPreferencesBaseUrlPrefKey) ??
          '')
      .trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _privacyPreferencesUnknownScope;
}

bool _isUnknownPrivacyPreferencesScope(String scope) {
  return scope == _privacyPreferencesUnknownScope;
}

String _scopedPrivacyPreferenceKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<void> _clearAllPrivacyPreferenceSecureKeys() async {
  try {
    final all = await _privacyPreferenceSecureStore.readAll();
    for (final key in all.keys) {
      if (_privacyPreferenceSpecs.values.any(
            (spec) =>
                key == spec.legacySecureKey ||
                key.startsWith(spec.scopedKeyPrefix),
          ) ||
          _deprecatedPrivacyLegacySecureKeys.contains(key) ||
          _deprecatedPrivacyScopedKeyPrefixes.any(key.startsWith)) {
        try {
          await _privacyPreferenceSecureStore.delete(key: key);
        } catch (_) {}
      }
    }
  } catch (_) {
    for (final spec in _privacyPreferenceSpecs.values) {
      await _deleteSecurePrivacyPreference(spec.legacySecureKey);
    }
    for (final key in _deprecatedPrivacyLegacySecureKeys) {
      await _deleteSecurePrivacyPreference(key);
    }
  }
}

Future<void> _clearAllPrivacyPreferencePrefs(SharedPreferences prefs) async {
  for (final entry in _privacyPreferenceSpecs.entries) {
    await prefs.remove(entry.key);
  }
  for (final key in _deprecatedPrivacyLegacyPrefKeys) {
    await prefs.remove(key);
  }
  final scopedPrefixes = _privacyPreferenceSpecs.values
      .map((spec) => spec.scopedKeyPrefix)
      .toSet()
    ..addAll(_deprecatedPrivacyScopedKeyPrefixes);
  final scopedKeys = prefs
      .getKeys()
      .where((key) => scopedPrefixes.any((prefix) => key.startsWith(prefix)))
      .toList(growable: false);
  for (final key in scopedKeys) {
    await prefs.remove(key);
  }
}

class _PrivacyPreferenceSpec {
  final String legacySecureKey;
  final String scopedKeyPrefix;

  const _PrivacyPreferenceSpec({
    required this.legacySecureKey,
    required this.scopedKeyPrefix,
  });
}
