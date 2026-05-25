// ignore_for_file: deprecated_member_use

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';
import 'local_password_hash.dart';

const FlutterSecureStorage _passwordHashSecureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
  ),
);

const String _kPasswordHashKey = 'shamell.security.password_hash.v1';
const String _kPasswordHashScopedKeyPrefix =
    'shamell.security.password_hash.v2.';
const String _passwordHashBaseUrlPrefKey = 'base_url';
const String _passwordHashUnknownScope = 'unknown';

Future<String?> loadStoredLocalPasswordHash({
  SharedPreferences? sp,
  String? baseUrlOverride,
  FlutterSecureStorage storage = _passwordHashSecureStore,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentPasswordHashScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedPasswordHashKey(scope);

  final scoped =
      await _readStoredLocalPasswordHash(scopedKey, storage: storage);
  if ((scoped ?? '').trim().isNotEmpty) {
    final scopedHash = scoped!.trim();
    if (!isSupportedLocalPasswordHash(scopedHash)) {
      await _deleteStoredLocalPasswordHash(scopedKey, storage: storage);
    } else {
      await _deleteStoredLocalPasswordHash(_kPasswordHashKey, storage: storage);
      return scopedHash;
    }
  }

  final legacy = await _readStoredLocalPasswordHash(
    _kPasswordHashKey,
    storage: storage,
  );
  if ((legacy ?? '').trim().isEmpty) return null;

  final legacyHash = legacy!.trim();
  if (!isSupportedLocalPasswordHash(legacyHash)) {
    await _deleteStoredLocalPasswordHash(_kPasswordHashKey, storage: storage);
    return null;
  }

  await _deleteStoredLocalPasswordHash(_kPasswordHashKey, storage: storage);
  if (_isUnknownPasswordHashScope(scope)) {
    final migrated = await _writeStoredLocalPasswordHash(
      scopedKey,
      legacyHash,
      storage: storage,
    );
    if (migrated) return legacyHash;
    await _deleteStoredLocalPasswordHash(scopedKey, storage: storage);
  }
  return null;
}

Future<bool> saveStoredLocalPasswordHash(
  String hash, {
  SharedPreferences? sp,
  String? baseUrlOverride,
  FlutterSecureStorage storage = _passwordHashSecureStore,
}) async {
  final normalized = hash.trim();
  if (normalized.isEmpty) {
    await clearStoredLocalPasswordHashForCurrentScope(
      sp: sp,
      baseUrlOverride: baseUrlOverride,
      storage: storage,
    );
    return true;
  }

  final prefs = sp ?? await SharedPreferences.getInstance();
  final scopedKey = _scopedPasswordHashKey(
    _currentPasswordHashScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    ),
  );
  final wrote = await _writeStoredLocalPasswordHash(
    scopedKey,
    normalized,
    storage: storage,
  );
  await _deleteStoredLocalPasswordHash(_kPasswordHashKey, storage: storage);
  if (!wrote) {
    await _deleteStoredLocalPasswordHash(scopedKey, storage: storage);
  }
  return wrote;
}

Future<void> clearStoredLocalPasswordHash({
  SharedPreferences? sp,
  FlutterSecureStorage storage = _passwordHashSecureStore,
}) async {
  await _deleteStoredLocalPasswordHash(_kPasswordHashKey, storage: storage);
  try {
    final all = await storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_kPasswordHashScopedKeyPrefix)) {
        await _deleteStoredLocalPasswordHash(key, storage: storage);
      }
    }
  } catch (_) {}
}

Future<void> clearStoredLocalPasswordHashForCurrentScope({
  SharedPreferences? sp,
  String? baseUrlOverride,
  FlutterSecureStorage storage = _passwordHashSecureStore,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  await _deleteStoredLocalPasswordHash(_kPasswordHashKey, storage: storage);
  await _deleteStoredLocalPasswordHash(
    _scopedPasswordHashKey(
      _currentPasswordHashScope(
        prefs,
        baseUrlOverride: baseUrlOverride,
      ),
    ),
    storage: storage,
  );
}

Future<String?> _readStoredLocalPasswordHash(
  String key, {
  required FlutterSecureStorage storage,
}) async {
  try {
    final raw = (await storage.read(key: key) ?? '').trim();
    if (raw.isEmpty) return null;
    return raw;
  } catch (_) {
    return null;
  }
}

Future<bool> _writeStoredLocalPasswordHash(
  String key,
  String value, {
  required FlutterSecureStorage storage,
}) async {
  try {
    await storage.write(key: key, value: value);
    final roundTrip = (await storage.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<void> _deleteStoredLocalPasswordHash(
  String key, {
  required FlutterSecureStorage storage,
}) async {
  try {
    await storage.delete(key: key);
  } catch (_) {}
}

String _currentPasswordHashScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final raw =
      (baseUrlOverride ?? prefs.getString(_passwordHashBaseUrlPrefKey) ?? '')
          .trim();
  final normalized = normalizeSecureApiBaseUrl(raw) ?? '';
  if (normalized.isEmpty) return _passwordHashUnknownScope;
  return Uri.parse(normalized).origin;
}

bool _isUnknownPasswordHashScope(String scope) =>
    scope == _passwordHashUnknownScope;

String _scopedPasswordHashKey(String scope) =>
    '$_kPasswordHashScopedKeyPrefix$scope';
