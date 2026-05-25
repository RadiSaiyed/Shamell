// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String kRequireBiometricsPrefKey = 'require_biometrics';
const String _requireBiometricsSecureKey = 'security.require_biometrics.v1';
const String _requireBiometricsScopedSecureKeyPrefix =
    'security.require_biometrics.v2.';
const String _requireBiometricsScopedPrefKeyPrefix = 'require_biometrics.v2.';
const String _biometricPreferenceBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _biometricPreferenceSecureStore =
    FlutterSecureStorage(
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

final Map<String, bool> _volatileRequireBiometricsByScope = <String, bool>{};

class _SecureBoolReadResult {
  final bool? value;
  final bool failed;
  const _SecureBoolReadResult({
    required this.value,
    required this.failed,
  });
}

Future<bool> loadRequireBiometricsPreference({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentBiometricPreferenceScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  if (_volatileRequireBiometricsByScope.containsKey(scope)) {
    return _volatileRequireBiometricsByScope[scope]!;
  }

  final scopedSecureKey = _scopedBiometricPreferenceKey(
    _requireBiometricsScopedSecureKeyPrefix,
    scope,
  );
  final scopedPrefKey = _scopedBiometricPreferenceKey(
    _requireBiometricsScopedPrefKeyPrefix,
    scope,
  );

  if (_canPersistSecureBiometricPreference()) {
    var secureReadFailed = false;
    final secureRead = await _readSecureRequireBiometrics(scopedSecureKey);
    secureReadFailed = secureRead.failed;
    final secure = secureRead.value;
    if (secure != null) {
      _volatileRequireBiometricsByScope[scope] = secure;
      await _removeLegacyRequireBiometrics(sp: prefs);
      return secure;
    }

    final legacySecureRead =
        await _readSecureRequireBiometrics(_requireBiometricsSecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = legacySecureRead.value;
    if (legacySecure != null) {
      await _removeLegacyRequireBiometrics(sp: prefs);
      if (_isUnknownBiometricPreferenceScope(scope)) {
        final migrated =
            await _writeSecureRequireBiometrics(scopedSecureKey, legacySecure);
        if (migrated) {
          _volatileRequireBiometricsByScope[scope] = legacySecure;
          return legacySecure;
        }
        await _deleteSecureRequireBiometrics(scopedSecureKey);
        if (secureReadFailed) {
          _volatileRequireBiometricsByScope[scope] = legacySecure;
          return legacySecure;
        }
      }
      return false;
    }

    // Fail closed by default: do not trust mutable SharedPreferences values
    // unless fallback is explicitly enabled or secure storage is unavailable.
    if (!_allowLegacyBiometricPreferenceFallback() && !secureReadFailed) {
      await _removeLegacyRequireBiometrics(sp: prefs);
      return false;
    }

    try {
      final legacy = prefs.getBool(kRequireBiometricsPrefKey);
      if (legacy == null) return false;
      await _removeLegacyRequireBiometrics(sp: prefs);
      if (_isUnknownBiometricPreferenceScope(scope)) {
        final migrated =
            await _writeSecureRequireBiometrics(scopedSecureKey, legacy);
        if (migrated) {
          _volatileRequireBiometricsByScope[scope] = legacy;
          return legacy;
        }
        await _deleteSecureRequireBiometrics(scopedSecureKey);
        if (secureReadFailed) {
          _volatileRequireBiometricsByScope[scope] = legacy;
          return legacy;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  try {
    final scoped = prefs.getBool(scopedPrefKey);
    if (scoped != null) {
      _volatileRequireBiometricsByScope[scope] = scoped;
      await _removeLegacyRequireBiometrics(sp: prefs);
      return scoped;
    }
    final legacy = prefs.getBool(kRequireBiometricsPrefKey);
    if (legacy == null) return false;
    await _removeLegacyRequireBiometrics(sp: prefs);
    if (_isUnknownBiometricPreferenceScope(scope)) {
      await prefs.setBool(scopedPrefKey, legacy);
      _volatileRequireBiometricsByScope[scope] = legacy;
      return legacy;
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<bool> saveRequireBiometricsPreference(
  bool value, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentBiometricPreferenceScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedSecureKey = _scopedBiometricPreferenceKey(
    _requireBiometricsScopedSecureKeyPrefix,
    scope,
  );
  final scopedPrefKey = _scopedBiometricPreferenceKey(
    _requireBiometricsScopedPrefKeyPrefix,
    scope,
  );
  _volatileRequireBiometricsByScope[scope] = value;
  if (_canPersistSecureBiometricPreference()) {
    final wrote = await _writeSecureRequireBiometrics(scopedSecureKey, value);
    await _removeLegacyRequireBiometrics(sp: prefs);
    if (!wrote) {
      await _deleteSecureRequireBiometrics(scopedSecureKey);
    }
    return wrote;
  }

  try {
    await prefs.setBool(scopedPrefKey, value);
    await _removeLegacyRequireBiometrics(sp: prefs);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> clearRequireBiometricsPreference({SharedPreferences? sp}) async {
  _volatileRequireBiometricsByScope.clear();
  final prefs = sp ?? await SharedPreferences.getInstance();
  if (_canPersistSecureBiometricPreference()) {
    await _clearAllScopedSecureBiometricPreferences();
  }
  await _clearAllScopedBiometricPrefs(prefs);
  await _removeLegacyRequireBiometrics(sp: prefs);
}

bool _canPersistSecureBiometricPreference() => !kIsWeb;

bool _allowLegacyBiometricPreferenceFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_BIOMETRIC_PREFERENCE_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_BIOMETRIC_PREFERENCE_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_BIOMETRIC_PREFERENCE_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_BIOMETRIC_PREFERENCE_FALLBACK',
    defaultValue: true,
  );
}

Future<void> _removeLegacyRequireBiometrics({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(kRequireBiometricsPrefKey);
    await _deleteSecureRequireBiometrics(_requireBiometricsSecureKey);
  } catch (_) {}
}

Future<_SecureBoolReadResult> _readSecureRequireBiometrics(String key) async {
  try {
    final raw = (await _biometricPreferenceSecureStore.read(
              key: key,
            ) ??
            '')
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

Future<bool> _writeSecureRequireBiometrics(String key, bool value) async {
  try {
    final encoded = value ? '1' : '0';
    await _biometricPreferenceSecureStore.write(
      key: key,
      value: encoded,
    );
    final roundTrip = (await _biometricPreferenceSecureStore.read(
              key: key,
            ) ??
            '')
        .trim();
    return roundTrip == encoded;
  } catch (_) {
    return false;
  }
}

Future<void> _deleteSecureRequireBiometrics(String key) async {
  try {
    await _biometricPreferenceSecureStore.delete(key: key);
  } catch (_) {}
}

Future<void> _clearAllScopedSecureBiometricPreferences() async {
  await _deleteSecureRequireBiometrics(_requireBiometricsSecureKey);
  try {
    final all = await _biometricPreferenceSecureStore.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_requireBiometricsScopedSecureKeyPrefix)) {
        await _deleteSecureRequireBiometrics(key);
      }
    }
  } catch (_) {}
}

Future<void> _clearAllScopedBiometricPrefs(SharedPreferences prefs) async {
  try {
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_requireBiometricsScopedPrefKeyPrefix)) {
        await prefs.remove(key);
      }
    }
  } catch (_) {}
}

String _currentBiometricPreferenceScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final raw = (baseUrlOverride ??
          prefs.getString(_biometricPreferenceBaseUrlPrefKey) ??
          '')
      .trim();
  final normalized = normalizeSecureApiBaseUrl(raw) ?? '';
  if (normalized.isEmpty) return 'unknown';
  return Uri.parse(normalized).origin;
}

bool _isUnknownBiometricPreferenceScope(String scope) => scope == 'unknown';

String _scopedBiometricPreferenceKey(String prefix, String scope) =>
    '$prefix$scope';

String currentRequireBiometricsScopedPrefKey({
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final scope = _currentBiometricPreferenceScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  return _scopedBiometricPreferenceKey(
    _requireBiometricsScopedPrefKeyPrefix,
    scope,
  );
}
