// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String _walletIdLegacyKey = 'wallet_id';
const String _walletIdLegacySecureKey = 'account.identity.wallet_id.v1';
const String _walletIdScopedKeyPrefix = 'account.identity.wallet_id.v2.';
const String _shamellUserIdLegacyKey = 'sa.user_id';
const String _shamellUserIdLegacySecureKey =
    'account.identity.shamell_user_id.v1';
const String _shamellUserIdScopedKeyPrefix =
    'account.identity.shamell_user_id.v2.';
const String _accountIdentityUnknownScope = 'unknown';
const String _accountIdentityBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _accountIdentitySecureStore = FlutterSecureStorage(
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

class _SecureReadResult {
  final String? value;
  final bool failed;
  const _SecureReadResult({
    required this.value,
    required this.failed,
  });
}

Future<String?> loadStoredWalletId({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _loadStoredIdentity(
    scopedKeyPrefix: _walletIdScopedKeyPrefix,
    legacySecureKey: _walletIdLegacySecureKey,
    legacyKey: _walletIdLegacyKey,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<bool> saveStoredWalletId(
  String walletId, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _saveStoredIdentity(
    scopedKeyPrefix: _walletIdScopedKeyPrefix,
    legacySecureKey: _walletIdLegacySecureKey,
    legacyKey: _walletIdLegacyKey,
    value: walletId,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> clearStoredWalletId({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  await _clearStoredIdentity(
    scopedKeyPrefix: _walletIdScopedKeyPrefix,
    legacySecureKey: _walletIdLegacySecureKey,
    legacyKey: _walletIdLegacyKey,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<String?> loadStoredShamellUserId({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _loadStoredIdentity(
    scopedKeyPrefix: _shamellUserIdScopedKeyPrefix,
    legacySecureKey: _shamellUserIdLegacySecureKey,
    legacyKey: _shamellUserIdLegacyKey,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<bool> saveStoredShamellUserId(
  String shamellUserId, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _saveStoredIdentity(
    scopedKeyPrefix: _shamellUserIdScopedKeyPrefix,
    legacySecureKey: _shamellUserIdLegacySecureKey,
    legacyKey: _shamellUserIdLegacyKey,
    value: shamellUserId,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> clearStoredShamellUserId({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  await _clearStoredIdentity(
    scopedKeyPrefix: _shamellUserIdScopedKeyPrefix,
    legacySecureKey: _shamellUserIdLegacySecureKey,
    legacyKey: _shamellUserIdLegacyKey,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> clearStoredAccountIdentity({SharedPreferences? sp}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  await _clearAllStoredIdentity(
    scopedKeyPrefix: _walletIdScopedKeyPrefix,
    legacySecureKey: _walletIdLegacySecureKey,
    legacyKey: _walletIdLegacyKey,
    sp: prefs,
  );
  await _clearAllStoredIdentity(
    scopedKeyPrefix: _shamellUserIdScopedKeyPrefix,
    legacySecureKey: _shamellUserIdLegacySecureKey,
    legacyKey: _shamellUserIdLegacyKey,
    sp: prefs,
  );
}

Future<String?> _loadStoredIdentity({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentAccountIdentityScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedAccountIdentityKey(scopedKeyPrefix, scope);
  if (_canPersistSecureAccountIdentity()) {
    var secureReadFailed = false;
    final secureRead = await _secureRead(scopedKey);
    secureReadFailed = secureRead.failed;
    final secure = secureRead.value;
    if (secure != null) {
      await _clearLegacyGlobalIdentity(
        legacySecureKey: legacySecureKey,
        legacyKey: legacyKey,
        sp: prefs,
      );
      return secure;
    }

    final legacySecureRead = await _secureRead(legacySecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = legacySecureRead.value;
    if (legacySecure != null) {
      if (_isUnknownAccountIdentityScope(scope)) {
        final migrated = await _secureWrite(scopedKey, legacySecure);
        if (migrated) {
          await _clearLegacyGlobalIdentity(
            legacySecureKey: legacySecureKey,
            legacyKey: legacyKey,
            sp: prefs,
          );
          return legacySecure;
        }
        await _secureDelete(scopedKey);
        if (secureReadFailed) {
          return legacySecure;
        }
      }
      await _clearLegacyGlobalIdentity(
        legacySecureKey: legacySecureKey,
        legacyKey: legacyKey,
        sp: prefs,
      );
      return null;
    }

    // Fail closed by default: ignore mutable SharedPreferences identity on
    // mobile unless fallback is explicitly enabled, or secure storage is
    // currently unavailable.
    if (!_allowLegacyAccountIdentityFallback() && !secureReadFailed) {
      await _removeLegacyIdentity(legacyKey, sp: prefs);
      return null;
    }

    final legacy = (prefs.getString(legacyKey) ?? '').trim();
    if (legacy.isEmpty) return null;

    if (_isUnknownAccountIdentityScope(scope)) {
      final migrated = await _secureWrite(scopedKey, legacy);
      if (migrated) {
        await _clearLegacyGlobalIdentity(
          legacySecureKey: legacySecureKey,
          legacyKey: legacyKey,
          sp: prefs,
        );
        return legacy;
      }
      await _secureDelete(scopedKey);
      if (secureReadFailed) {
        return legacy;
      }
    }
    await _clearLegacyGlobalIdentity(
      legacySecureKey: legacySecureKey,
      legacyKey: legacyKey,
      sp: prefs,
    );
    return null;
  }

  final scoped = (prefs.getString(scopedKey) ?? '').trim();
  if (scoped.isNotEmpty) {
    await _removeLegacyIdentity(legacyKey, sp: prefs);
    return scoped;
  }

  final legacy = (prefs.getString(legacyKey) ?? '').trim();
  if (legacy.isEmpty) return null;
  await _removeLegacyIdentity(legacyKey, sp: prefs);
  if (_isUnknownAccountIdentityScope(scope)) {
    await prefs.setString(scopedKey, legacy);
    return legacy;
  }
  return null;
}

Future<bool> _saveStoredIdentity({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  required String value,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scopedKey = _scopedAccountIdentityKey(
    scopedKeyPrefix,
    _currentAccountIdentityScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    ),
  );
  final normalized = value.trim();
  if (normalized.isEmpty) {
    await _clearStoredIdentity(
      scopedKeyPrefix: scopedKeyPrefix,
      legacySecureKey: legacySecureKey,
      legacyKey: legacyKey,
      sp: prefs,
      baseUrlOverride: baseUrlOverride,
    );
    return true;
  }

  if (_canPersistSecureAccountIdentity()) {
    final wrote = await _secureWrite(scopedKey, normalized);
    await _clearLegacyGlobalIdentity(
      legacySecureKey: legacySecureKey,
      legacyKey: legacyKey,
      sp: prefs,
    );
    if (!wrote) {
      await _secureDelete(scopedKey);
      return false;
    }
    return true;
  }

  try {
    await prefs.setString(scopedKey, normalized);
    await _removeLegacyIdentity(legacyKey, sp: prefs);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _clearStoredIdentity({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scopedKey = _scopedAccountIdentityKey(
    scopedKeyPrefix,
    _currentAccountIdentityScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    ),
  );
  if (_canPersistSecureAccountIdentity()) {
    await _secureDelete(scopedKey);
    await _secureDelete(legacySecureKey);
  }
  try {
    await prefs.remove(scopedKey);
  } catch (_) {}
  await _removeLegacyIdentity(legacyKey, sp: prefs);
}

Future<void> _clearAllStoredIdentity({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  required SharedPreferences sp,
}) async {
  if (_canPersistSecureAccountIdentity()) {
    try {
      final all = await _accountIdentitySecureStore.readAll();
      for (final key in all.keys) {
        if (key == legacySecureKey || key.startsWith(scopedKeyPrefix)) {
          try {
            await _accountIdentitySecureStore.delete(key: key);
          } catch (_) {}
        }
      }
    } catch (_) {
      await _secureDelete(legacySecureKey);
    }
  }
  try {
    final keys = sp
        .getKeys()
        .where((key) => key == legacyKey || key.startsWith(scopedKeyPrefix))
        .toList(growable: false);
    for (final key in keys) {
      await sp.remove(key);
    }
  } catch (_) {}
}

Future<void> _removeLegacyIdentity(
  String key, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(key);
  } catch (_) {}
}

bool _canPersistSecureAccountIdentity() => !kIsWeb;

bool _allowLegacyAccountIdentityFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_ACCOUNT_IDENTITY_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_ACCOUNT_IDENTITY_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_ACCOUNT_IDENTITY_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_ACCOUNT_IDENTITY_FALLBACK',
    defaultValue: true,
  );
}

String _currentAccountIdentityScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final rawBase =
      (baseUrlOverride ?? prefs.getString(_accountIdentityBaseUrlPrefKey) ?? '')
          .trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _accountIdentityUnknownScope;
}

bool _isUnknownAccountIdentityScope(String scope) {
  return scope == _accountIdentityUnknownScope;
}

String _scopedAccountIdentityKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<_SecureReadResult> _secureRead(String key) async {
  try {
    final value = await _accountIdentitySecureStore.read(key: key);
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return const _SecureReadResult(value: null, failed: false);
    }
    return _SecureReadResult(value: value, failed: false);
  } catch (_) {
    return const _SecureReadResult(value: null, failed: true);
  }
}

Future<bool> _secureWrite(String key, String value) async {
  try {
    await _accountIdentitySecureStore.write(key: key, value: value);
    final roundTrip =
        (await _accountIdentitySecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<bool> _secureDelete(String key) async {
  try {
    await _accountIdentitySecureStore.delete(key: key);
    final roundTrip =
        (await _accountIdentitySecureStore.read(key: key) ?? '').trim();
    return roundTrip.isEmpty;
  } catch (_) {
    return false;
  }
}

Future<void> _clearLegacyGlobalIdentity({
  required String legacySecureKey,
  required String legacyKey,
  required SharedPreferences sp,
}) async {
  await _secureDelete(legacySecureKey);
  await _removeLegacyIdentity(legacyKey, sp: sp);
}
