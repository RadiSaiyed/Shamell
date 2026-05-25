// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';
import 'hardware_attestation.dart';

/// Stable (non-secret) identifier for this app install.
///
/// This is used for device session binding / revocation on the backend.
const String kStableDeviceIdPrefKey = 'sa.device_id';
const String _stableDeviceIdSecureKey = 'device.install_id.v1';
const String _stableDeviceIdScopedSecureKeyPrefix = 'device.install_id.v2.';
const String _stableDeviceIdScopedPrefKeyPrefix = 'sa.device_id.v2.';
const String _stableDeviceIdBaseUrlPrefKey = 'base_url';
const String _stableDeviceIdUnknownScope = 'unknown';
const String _stableDeviceIdOverride = String.fromEnvironment(
  'SHAMELL_DEVICE_ID_OVERRIDE',
  defaultValue: '',
);
// Local debug anchor for the currently attached Android test handset. This
// must never be relied on for release security because the server-visible
// device_id is still client-controlled.
const Set<String> _trustedAndroidSecureIds = <String>{
  // `adb shell settings get secure android_id`
  '71a05a7e9af77a62',
  // App-visible ANDROID_ID on the attached debug-signed Android handset.
  'd28519355eec5c28',
};
const String _trustedAndroidStableDeviceId =
    'android-dev-trusted-71a05a7e9af77a62';
String? _stableDeviceIdOverrideResolved;

@visibleForTesting
bool shamellAllowSyntheticAndroidSecureIdProbe = false;

const FlutterSecureStorage _stableDeviceIdSecureStore = FlutterSecureStorage(
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
const Duration _stableDeviceSecureStoreIoTimeout = Duration(seconds: 3);

final Map<String, String> _volatileStableDeviceIdByScope = <String, String>{};

class _SecureStringReadResult {
  final String? value;
  final bool failed;
  const _SecureStringReadResult({
    required this.value,
    required this.failed,
  });
}

String? _stableDeviceIdOverrideValue() {
  final cached = _stableDeviceIdOverrideResolved;
  if (cached != null && cached.isNotEmpty) return cached;
  final raw = _stableDeviceIdOverride.trim();
  if (raw.isEmpty) return null;
  if (raw.toLowerCase() == 'auto') {
    final generated = 'debug-auto-${_randomHexId(length: 24)}';
    _stableDeviceIdOverrideResolved = generated;
    return generated;
  }
  final ok = RegExp(r'^[a-zA-Z0-9._:-]{8,128}$').hasMatch(raw);
  if (!ok) return null;
  _stableDeviceIdOverrideResolved = raw;
  return raw;
}

Future<String?> _runtimePinnedStableDeviceIdOverride() async {
  if (kReleaseMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  if (!Platform.isAndroid && !shamellAllowSyntheticAndroidSecureIdProbe) {
    return null;
  }
  final secureId = (await HardwareAttestation.tryGetAndroidSecureId(
    platformIsAndroid: true,
  ))
      ?.trim()
      .toLowerCase();
  if (kDebugMode) {
    debugPrint(
      'StableDeviceId runtime pin secureId_present=${secureId != null && secureId.isNotEmpty} '
      'trusted=${_trustedAndroidSecureIds.contains(secureId)}',
    );
  }
  if (_trustedAndroidSecureIds.contains(secureId)) {
    if (kDebugMode) {
      debugPrint('StableDeviceId runtime pin override=enabled');
    }
    return _trustedAndroidStableDeviceId;
  }
  return null;
}

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

Future<String?> loadStableDeviceId({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final override = _stableDeviceIdOverrideValue();
  if (override != null) {
    return override;
  }
  final runtimePinnedOverride = await _runtimePinnedStableDeviceIdOverride();
  if (runtimePinnedOverride != null) {
    if (kDebugMode) {
      debugPrint('StableDeviceId getOrCreate returning runtime pin');
    }
    return runtimePinnedOverride;
  }
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentStableDeviceIdScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final volatile = (_volatileStableDeviceIdByScope[scope] ?? '').trim();
  if (volatile.isNotEmpty) return volatile;

  if (_canPersistSecureStableDeviceId()) {
    final scopedSecureKey = _scopedStableDeviceIdKey(
      _stableDeviceIdScopedSecureKeyPrefix,
      scope,
    );
    var secureReadFailed = false;
    final secureRead = await _readSecureStableDeviceId(scopedSecureKey);
    secureReadFailed = secureRead.failed;
    final secure = secureRead.value;
    if (secure != null) {
      _volatileStableDeviceIdByScope[scope] = secure;
      await _removeLegacyStableDeviceId(sp: prefs);
      return secure;
    }

    final legacySecureRead =
        await _readSecureStableDeviceId(_stableDeviceIdSecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = legacySecureRead.value;
    if (legacySecure != null) {
      await _removeLegacyStableDeviceId(sp: prefs);
      if (_isUnknownStableDeviceIdScope(scope)) {
        final migrated =
            await _writeSecureStableDeviceId(scopedSecureKey, legacySecure);
        if (migrated) {
          _volatileStableDeviceIdByScope[scope] = legacySecure;
          return legacySecure;
        }
        await _deleteSecureStableDeviceId(scopedSecureKey);
        if (secureReadFailed) {
          _volatileStableDeviceIdByScope[scope] = legacySecure;
          return legacySecure;
        }
      }
      return null;
    }

    // Fail closed by default: do not trust mutable SharedPreferences values
    // unless fallback is explicitly enabled or secure storage is unavailable.
    if (!_allowLegacyStableDeviceIdFallback() && !secureReadFailed) {
      await _removeLegacyStableDeviceId(sp: prefs);
      return null;
    }

    try {
      final legacy = (prefs.getString(kStableDeviceIdPrefKey) ?? '').trim();
      if (legacy.isEmpty) return null;
      await _removeLegacyStableDeviceId(sp: prefs);
      if (_isUnknownStableDeviceIdScope(scope)) {
        final migrated =
            await _writeSecureStableDeviceId(scopedSecureKey, legacy);
        if (migrated) {
          _volatileStableDeviceIdByScope[scope] = legacy;
          return legacy;
        }
        await _deleteSecureStableDeviceId(scopedSecureKey);
        if (secureReadFailed) {
          _volatileStableDeviceIdByScope[scope] = legacy;
          return legacy;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  try {
    final scopedPrefKey = _scopedStableDeviceIdKey(
      _stableDeviceIdScopedPrefKeyPrefix,
      scope,
    );
    final scoped = (prefs.getString(scopedPrefKey) ?? '').trim();
    if (scoped.isNotEmpty) {
      _volatileStableDeviceIdByScope[scope] = scoped;
      await _removeLegacyStableDeviceId(sp: prefs);
      return scoped;
    }
    final legacy = (prefs.getString(kStableDeviceIdPrefKey) ?? '').trim();
    if (legacy.isEmpty) return null;
    await _removeLegacyStableDeviceId(sp: prefs);
    if (_isUnknownStableDeviceIdScope(scope)) {
      await prefs.setString(scopedPrefKey, legacy);
      _volatileStableDeviceIdByScope[scope] = legacy;
      return legacy;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<bool> saveStableDeviceId(
  String deviceId, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final override = _stableDeviceIdOverrideValue();
  if (override != null) {
    return deviceId.trim() == override;
  }
  final runtimePinnedOverride = await _runtimePinnedStableDeviceIdOverride();
  if (runtimePinnedOverride != null) {
    return deviceId.trim() == runtimePinnedOverride;
  }
  final normalized = deviceId.trim();
  if (normalized.isEmpty) {
    await clearStableDeviceId(sp: sp);
    return true;
  }

  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentStableDeviceIdScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  _volatileStableDeviceIdByScope[scope] = normalized;
  if (_canPersistSecureStableDeviceId()) {
    final scopedSecureKey = _scopedStableDeviceIdKey(
      _stableDeviceIdScopedSecureKeyPrefix,
      scope,
    );
    final wrote = await _writeSecureStableDeviceId(scopedSecureKey, normalized);
    await _removeLegacyStableDeviceId(sp: prefs);
    if (!wrote) {
      await _deleteSecureStableDeviceId(scopedSecureKey);
    }
    return wrote;
  }

  try {
    final scopedPrefKey = _scopedStableDeviceIdKey(
      _stableDeviceIdScopedPrefKeyPrefix,
      scope,
    );
    await prefs.setString(scopedPrefKey, normalized);
    await _removeLegacyStableDeviceId(sp: prefs);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> clearStableDeviceId({SharedPreferences? sp}) async {
  _volatileStableDeviceIdByScope.clear();
  final prefs = sp ?? await SharedPreferences.getInstance();
  if (_canPersistSecureStableDeviceId()) {
    await _clearAllScopedSecureStableDeviceIds();
  }
  await _clearAllScopedStableDevicePrefs(prefs);
  await _removeLegacyStableDeviceId(sp: prefs);
}

Future<String> getOrCreateStableDeviceId({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final override = _stableDeviceIdOverrideValue();
  if (override != null) {
    return override;
  }
  final runtimePinnedOverride = await _runtimePinnedStableDeviceIdOverride();
  if (runtimePinnedOverride != null) {
    return runtimePinnedOverride;
  }
  final existing = await loadStableDeviceId(
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
  if ((existing ?? '').trim().isNotEmpty) {
    return existing!.trim();
  }

  final id = _randomHexId();
  final precomputedScope = (baseUrlOverride ?? '').trim().isEmpty
      ? null
      : _stableDeviceIdScopeFromRawBaseUrl(baseUrlOverride!);
  if (precomputedScope != null) {
    _volatileStableDeviceIdByScope[precomputedScope] = id;
  }
  unawaited(saveStableDeviceId(
    id,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  ));
  if (precomputedScope == null) {
    final prefs = sp ?? await SharedPreferences.getInstance();
    _volatileStableDeviceIdByScope[_currentStableDeviceIdScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    )] = id;
  }
  return id;
}

bool _canPersistSecureStableDeviceId() => !kIsWeb;

bool _allowLegacyStableDeviceIdFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_STABLE_DEVICE_ID_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_STABLE_DEVICE_ID_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_STABLE_DEVICE_ID_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_STABLE_DEVICE_ID_FALLBACK',
    defaultValue: true,
  );
}

Future<void> _removeLegacyStableDeviceId({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(kStableDeviceIdPrefKey);
    await _deleteSecureStableDeviceId(_stableDeviceIdSecureKey);
  } catch (_) {}
}

Future<_SecureStringReadResult> _readSecureStableDeviceId(String key) async {
  try {
    final value = (await _stableDeviceIdSecureStore
                .read(key: key)
                .timeout(_stableDeviceSecureStoreIoTimeout) ??
            '')
        .trim();
    if (value.isEmpty) {
      return const _SecureStringReadResult(value: null, failed: false);
    }
    return _SecureStringReadResult(value: value, failed: false);
  } catch (_) {
    return const _SecureStringReadResult(value: null, failed: true);
  }
}

Future<bool> _writeSecureStableDeviceId(String key, String value) async {
  try {
    await _stableDeviceIdSecureStore
        .write(
          key: key,
          value: value,
        )
        .timeout(_stableDeviceSecureStoreIoTimeout);
    final roundTrip = (await _stableDeviceIdSecureStore
                .read(
                  key: key,
                )
                .timeout(_stableDeviceSecureStoreIoTimeout) ??
            '')
        .trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<void> _deleteSecureStableDeviceId(String key) async {
  try {
    await _stableDeviceIdSecureStore
        .delete(key: key)
        .timeout(_stableDeviceSecureStoreIoTimeout);
  } catch (_) {}
}

Future<void> _clearAllScopedSecureStableDeviceIds() async {
  await _deleteSecureStableDeviceId(_stableDeviceIdSecureKey);
  try {
    final all = await _stableDeviceIdSecureStore
        .readAll()
        .timeout(_stableDeviceSecureStoreIoTimeout);
    for (final key in all.keys) {
      if (key.startsWith(_stableDeviceIdScopedSecureKeyPrefix)) {
        await _deleteSecureStableDeviceId(key);
      }
    }
  } catch (_) {}
}

Future<void> _clearAllScopedStableDevicePrefs(SharedPreferences prefs) async {
  try {
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_stableDeviceIdScopedPrefKeyPrefix)) {
        await prefs.remove(key);
      }
    }
  } catch (_) {}
}

String _currentStableDeviceIdScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final raw =
      (baseUrlOverride ?? prefs.getString(_stableDeviceIdBaseUrlPrefKey) ?? '')
          .trim();
  return _stableDeviceIdScopeFromRawBaseUrl(raw);
}

String _stableDeviceIdScopeFromRawBaseUrl(String rawBaseUrl) {
  final raw = rawBaseUrl.trim();
  final normalized = normalizeSecureApiBaseUrl(raw) ?? '';
  if (normalized.isEmpty) return _stableDeviceIdUnknownScope;
  return Uri.parse(normalized).origin;
}

bool _isUnknownStableDeviceIdScope(String scope) =>
    scope == _stableDeviceIdUnknownScope;

String _scopedStableDeviceIdKey(String prefix, String scope) => '$prefix$scope';

String currentStableDeviceIdScopedPrefKey({
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final scope = _currentStableDeviceIdScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  return _scopedStableDeviceIdKey(_stableDeviceIdScopedPrefKeyPrefix, scope);
}
