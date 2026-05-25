// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String _homeSnapshotLegacyKey = 'home_snapshot';
const String _homeSnapshotLegacySecureKey = 'account.snapshot.home.v1';
const String _homeSnapshotScopedSecurePrefix = 'account.snapshot.home.v2.';
const String _walletSnapshotLegacyPrefix = 'wallet_snapshot_';
const String _walletSnapshotLegacySecurePrefix = 'account.snapshot.wallet.v1.';
const String _walletSnapshotScopedSecurePrefix = 'account.snapshot.wallet.v2.';
const String _walletLinkedCardsLegacyKey = 'wallet_linked_cards';
const String _walletLinkedCardsLegacySecureKey =
    'account.wallet.linked_cards.v1';
const String _walletLinkedCardsScopedSecurePrefix =
    'account.wallet.linked_cards.v2.';
const String _accountSnapshotUnknownScope = 'unknown';
const String _accountSnapshotBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _accountSnapshotSecureStore = FlutterSecureStorage(
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

Future<String?> loadCachedHomeSnapshotRaw({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _loadScopedSnapshot(
    scopedSecureKeyPrefix: _homeSnapshotScopedSecurePrefix,
    legacySecureKey: _homeSnapshotLegacySecureKey,
    legacyPrefKey: _homeSnapshotLegacyKey,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> saveCachedHomeSnapshotRaw(
  String raw, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  await _saveScopedSnapshot(
    scopedSecureKeyPrefix: _homeSnapshotScopedSecurePrefix,
    legacySecureKey: _homeSnapshotLegacySecureKey,
    legacyPrefKey: _homeSnapshotLegacyKey,
    raw: raw,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<String?> loadCachedWalletSnapshotRaw(
  String walletId, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final normalized = walletId.trim();
  if (normalized.isEmpty) return null;
  return _loadScopedSnapshot(
    scopedSecureKeyPrefix: _walletSnapshotScopedPrefixForWallet(normalized),
    legacySecureKey: _walletSnapshotLegacySecureKey(normalized),
    legacyPrefKey: _walletSnapshotLegacyKey(normalized),
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> saveCachedWalletSnapshotRaw(
  String walletId,
  String raw, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final normalized = walletId.trim();
  if (normalized.isEmpty) return;
  await _saveScopedSnapshot(
    scopedSecureKeyPrefix: _walletSnapshotScopedPrefixForWallet(normalized),
    legacySecureKey: _walletSnapshotLegacySecureKey(normalized),
    legacyPrefKey: _walletSnapshotLegacyKey(normalized),
    raw: raw,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<List<String>> loadCachedWalletLinkedCardsRawList({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentAccountSnapshotScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedAccountSnapshotKey(
    _walletLinkedCardsScopedSecurePrefix,
    scope,
  );

  if (_canPersistSecureSnapshots()) {
    var secureReadFailed = false;
    final secureRead = await _secureReadResult(scopedKey);
    secureReadFailed = secureRead.failed;
    final secure = secureRead.value;
    if (secure != null && secure.isNotEmpty) {
      await _clearLegacyAccountSnapshot(
        legacySecureKey: _walletLinkedCardsLegacySecureKey,
        legacyPrefKey: _walletLinkedCardsLegacyKey,
        sp: prefs,
      );
      return _decodeRawList(secure);
    }

    final legacySecureRead =
        await _secureReadResult(_walletLinkedCardsLegacySecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = legacySecureRead.value;
    if (legacySecure != null && legacySecure.isNotEmpty) {
      await _clearLegacyAccountSnapshot(
        legacySecureKey: _walletLinkedCardsLegacySecureKey,
        legacyPrefKey: _walletLinkedCardsLegacyKey,
        sp: prefs,
      );
      if (_isUnknownAccountSnapshotScope(scope)) {
        final migrated = await _secureWrite(scopedKey, legacySecure);
        if (migrated) return _decodeRawList(legacySecure);
        await _secureDelete(scopedKey);
        if (secureReadFailed) {
          return _decodeRawList(legacySecure);
        }
      }
      return const <String>[];
    }

    // Fail closed by default: do not trust mutable SharedPreferences snapshot
    // state unless fallback is explicitly enabled or secure storage is
    // unavailable.
    if (!_allowLegacyAccountSnapshotFallback() && !secureReadFailed) {
      await _clearLegacyAccountSnapshot(
        legacySecureKey: _walletLinkedCardsLegacySecureKey,
        legacyPrefKey: _walletLinkedCardsLegacyKey,
        sp: prefs,
      );
      return const <String>[];
    }

    final legacy = await _readLegacyStringListSnapshot(
      _walletLinkedCardsLegacyKey,
      sp: prefs,
    );
    if (legacy.isEmpty) return const <String>[];

    await _clearLegacyAccountSnapshot(
      legacySecureKey: _walletLinkedCardsLegacySecureKey,
      legacyPrefKey: _walletLinkedCardsLegacyKey,
      sp: prefs,
    );
    if (_isUnknownAccountSnapshotScope(scope)) {
      final migrated = await _secureWrite(scopedKey, jsonEncode(legacy));
      if (migrated) return legacy;
      await _secureDelete(scopedKey);
      if (secureReadFailed) {
        return legacy;
      }
      return const <String>[];
    }
    return const <String>[];
  } else {
    try {
      final scoped = prefs.getStringList(scopedKey) ?? const <String>[];
      if (scoped.isNotEmpty) {
        await _removeLegacySnapshot(_walletLinkedCardsLegacyKey, sp: prefs);
        return scoped
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    final legacy = await _readLegacyStringListSnapshot(
      _walletLinkedCardsLegacyKey,
      sp: prefs,
    );
    if (legacy.isEmpty) return const <String>[];
    if (_isUnknownAccountSnapshotScope(scope)) {
      try {
        await prefs.setStringList(scopedKey, legacy);
        return legacy;
      } catch (_) {
        return const <String>[];
      }
    }
    return const <String>[];
  }
}

Future<void> saveCachedWalletLinkedCardsRawList(
  List<String> values, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final cleaned = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scopedKey = _scopedAccountSnapshotKey(
    _walletLinkedCardsScopedSecurePrefix,
    _currentAccountSnapshotScope(prefs, baseUrlOverride: baseUrlOverride),
  );
  if (cleaned.isEmpty) {
    await _saveScopedSnapshot(
      scopedSecureKeyPrefix: _walletLinkedCardsScopedSecurePrefix,
      legacySecureKey: _walletLinkedCardsLegacySecureKey,
      legacyPrefKey: _walletLinkedCardsLegacyKey,
      raw: '',
      sp: prefs,
      baseUrlOverride: baseUrlOverride,
    );
    return;
  }

  if (_canPersistSecureSnapshots()) {
    final wrote = await _secureWrite(scopedKey, jsonEncode(cleaned));
    await _clearLegacyAccountSnapshot(
      legacySecureKey: _walletLinkedCardsLegacySecureKey,
      legacyPrefKey: _walletLinkedCardsLegacyKey,
      sp: prefs,
    );
    if (!wrote) {
      await _secureDelete(scopedKey);
    }
    return;
  }

  try {
    await prefs.setStringList(scopedKey, cleaned);
    await _removeLegacySnapshot(_walletLinkedCardsLegacyKey, sp: prefs);
  } catch (_) {}
}

Future<void> wipeCachedAccountSnapshots({SharedPreferences? sp}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  if (_canPersistSecureSnapshots()) {
    try {
      final all = await _accountSnapshotSecureStore.readAll();
      for (final key in all.keys) {
        if (key == _homeSnapshotLegacySecureKey ||
            key == _walletLinkedCardsLegacySecureKey ||
            key.startsWith(_homeSnapshotScopedSecurePrefix) ||
            key.startsWith(_walletSnapshotLegacySecurePrefix) ||
            key.startsWith(_walletSnapshotScopedSecurePrefix) ||
            key.startsWith(_walletLinkedCardsScopedSecurePrefix)) {
          try {
            await _accountSnapshotSecureStore.delete(key: key);
          } catch (_) {}
        }
      }
    } catch (_) {
      await _secureDelete(_homeSnapshotLegacySecureKey);
      await _secureDelete(_walletLinkedCardsLegacySecureKey);
    }
  }

  try {
    await prefs.remove(_homeSnapshotLegacyKey);
    await prefs.remove(_walletLinkedCardsLegacyKey);
    final snapshotKeys = prefs
        .getKeys()
        .where((key) =>
            key.startsWith(_walletSnapshotLegacyPrefix) ||
            key.startsWith(_homeSnapshotScopedSecurePrefix) ||
            key.startsWith(_walletSnapshotScopedSecurePrefix) ||
            key.startsWith(_walletLinkedCardsScopedSecurePrefix))
        .toList(growable: false);
    for (final key in snapshotKeys) {
      await prefs.remove(key);
    }
  } catch (_) {}
}

String _walletSnapshotLegacySecureKey(String walletId) =>
    '$_walletSnapshotLegacySecurePrefix$walletId';

String _walletSnapshotLegacyKey(String walletId) =>
    '$_walletSnapshotLegacyPrefix$walletId';

String _walletSnapshotScopedPrefixForWallet(String walletId) =>
    '$_walletSnapshotScopedSecurePrefix$walletId.';

bool _canPersistSecureSnapshots() => !kIsWeb;

bool _allowLegacyAccountSnapshotFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_ACCOUNT_SNAPSHOT_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_ACCOUNT_SNAPSHOT_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_ACCOUNT_SNAPSHOT_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_ACCOUNT_SNAPSHOT_FALLBACK',
    defaultValue: true,
  );
}

Future<String?> _loadScopedSnapshot({
  required String scopedSecureKeyPrefix,
  required String legacySecureKey,
  required String legacyPrefKey,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentAccountSnapshotScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedAccountSnapshotKey(scopedSecureKeyPrefix, scope);

  if (_canPersistSecureSnapshots()) {
    var secureReadFailed = false;
    final secureRead = await _secureReadResult(scopedKey);
    secureReadFailed = secureRead.failed;
    final secure = secureRead.value;
    if (secure != null) {
      await _clearLegacyAccountSnapshot(
        legacySecureKey: legacySecureKey,
        legacyPrefKey: legacyPrefKey,
        sp: prefs,
      );
      return secure;
    }

    final legacySecureRead = await _secureReadResult(legacySecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = legacySecureRead.value;
    if (legacySecure != null) {
      await _clearLegacyAccountSnapshot(
        legacySecureKey: legacySecureKey,
        legacyPrefKey: legacyPrefKey,
        sp: prefs,
      );
      if (_isUnknownAccountSnapshotScope(scope)) {
        final migrated = await _secureWrite(scopedKey, legacySecure);
        if (migrated) return legacySecure;
        await _secureDelete(scopedKey);
        if (secureReadFailed) {
          return legacySecure;
        }
      }
      return null;
    }

    // Fail closed by default: do not trust mutable SharedPreferences snapshot
    // state unless fallback is explicitly enabled or secure storage is
    // unavailable.
    if (!_allowLegacyAccountSnapshotFallback() && !secureReadFailed) {
      await _clearLegacyAccountSnapshot(
        legacySecureKey: legacySecureKey,
        legacyPrefKey: legacyPrefKey,
        sp: prefs,
      );
      return null;
    }

    final legacy = await _readLegacySnapshot(legacyPrefKey, sp: prefs);
    if (legacy == null) return null;

    await _clearLegacyAccountSnapshot(
      legacySecureKey: legacySecureKey,
      legacyPrefKey: legacyPrefKey,
      sp: prefs,
    );
    if (_isUnknownAccountSnapshotScope(scope)) {
      final migrated = await _secureWrite(scopedKey, legacy);
      if (migrated) return legacy;
      await _secureDelete(scopedKey);
      if (secureReadFailed) {
        return legacy;
      }
      return null;
    }
    return null;
  } else {
    try {
      final scoped = (prefs.getString(scopedKey) ?? '').trim();
      if (scoped.isNotEmpty) {
        await _removeLegacySnapshot(legacyPrefKey, sp: prefs);
        return scoped;
      }
    } catch (_) {}

    final legacy = await _readLegacySnapshot(legacyPrefKey, sp: prefs);
    if (legacy == null) return null;
    if (_isUnknownAccountSnapshotScope(scope)) {
      try {
        await prefs.setString(scopedKey, legacy);
        return legacy;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

Future<void> _saveScopedSnapshot({
  required String scopedSecureKeyPrefix,
  required String legacySecureKey,
  required String legacyPrefKey,
  required String raw,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scopedKey = _scopedAccountSnapshotKey(
    scopedSecureKeyPrefix,
    _currentAccountSnapshotScope(prefs, baseUrlOverride: baseUrlOverride),
  );
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    if (_canPersistSecureSnapshots()) {
      await _secureDelete(scopedKey);
      await _secureDelete(legacySecureKey);
    } else {
      try {
        await prefs.remove(scopedKey);
      } catch (_) {}
    }
    await _removeLegacySnapshot(legacyPrefKey, sp: prefs);
    return;
  }

  if (_canPersistSecureSnapshots()) {
    final wrote = await _secureWrite(scopedKey, raw);
    await _clearLegacyAccountSnapshot(
      legacySecureKey: legacySecureKey,
      legacyPrefKey: legacyPrefKey,
      sp: prefs,
    );
    if (!wrote) {
      await _secureDelete(scopedKey);
    }
    return;
  }

  try {
    await prefs.setString(scopedKey, raw);
    await _removeLegacySnapshot(legacyPrefKey, sp: prefs);
  } catch (_) {}
}

String _currentAccountSnapshotScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final rawBase =
      (baseUrlOverride ?? prefs.getString(_accountSnapshotBaseUrlPrefKey) ?? '')
          .trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _accountSnapshotUnknownScope;
}

bool _isUnknownAccountSnapshotScope(String scope) {
  return scope == _accountSnapshotUnknownScope;
}

String _scopedAccountSnapshotKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<void> _clearLegacyAccountSnapshot({
  required String legacySecureKey,
  required String legacyPrefKey,
  required SharedPreferences sp,
}) async {
  if (_canPersistSecureSnapshots()) {
    await _secureDelete(legacySecureKey);
  }
  await _removeLegacySnapshot(legacyPrefKey, sp: sp);
}

Future<_SecureReadResult> _secureReadResult(String key) async {
  if (!_canPersistSecureSnapshots()) {
    return const _SecureReadResult(value: null, failed: false);
  }
  try {
    final value = await _accountSnapshotSecureStore.read(key: key);
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
  if (!_canPersistSecureSnapshots()) return false;
  try {
    await _accountSnapshotSecureStore.write(key: key, value: value);
    final roundTrip =
        (await _accountSnapshotSecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<bool> _secureDelete(String key) async {
  if (!_canPersistSecureSnapshots()) return false;
  try {
    await _accountSnapshotSecureStore.delete(key: key);
    final roundTrip =
        (await _accountSnapshotSecureStore.read(key: key) ?? '').trim();
    return roundTrip.isEmpty;
  } catch (_) {
    return false;
  }
}

Future<String?> _readLegacySnapshot(
  String key, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final value = (prefs.getString(key) ?? '').trim();
    if (value.isEmpty) return null;
    return value;
  } catch (_) {
    return null;
  }
}

Future<List<String>> _readLegacyStringListSnapshot(
  String key, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final values = prefs.getStringList(key) ?? const <String>[];
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  } catch (_) {
    return const <String>[];
  }
}

List<String> _decodeRawList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded.map((item) => item.toString()).toList();
  } catch (_) {
    return const <String>[];
  }
}

Future<void> _removeLegacySnapshot(
  String key, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(key);
  } catch (_) {}
}
