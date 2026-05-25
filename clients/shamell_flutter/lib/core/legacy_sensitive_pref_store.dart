// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String _legacyProfileNameKey = 'last_login_name';
const String _legacyProfilePhoneKey = 'last_login_phone';
const String _legacyProfileNameSecureKey = 'legacy.profile.name.v1';
const String _legacyProfilePhoneSecureKey = 'legacy.profile.phone.v1';
const String _legacyProfileNameScopedSecureKeyPrefix =
    'legacy.profile.name.v2.';
const String _legacyProfilePhoneScopedSecureKeyPrefix =
    'legacy.profile.phone.v2.';
const String _legacyDefaultOfficialAccountIdKey = 'official.default_account_id';
const String _legacyDefaultOfficialAccountNameKey =
    'official.default_account_name';
const String _legacyDefaultOfficialAccountIdSecureKey =
    'legacy.official.default_account.id.v1';
const String _legacyDefaultOfficialAccountNameSecureKey =
    'legacy.official.default_account.name.v1';
const String _legacyDefaultOfficialAccountIdScopedSecureKeyPrefix =
    'legacy.official.default_account.id.v2.';
const String _legacyDefaultOfficialAccountNameScopedSecureKeyPrefix =
    'legacy.official.default_account.name.v2.';
const String _legacyContactShortlistKey = 'contact_shortlist';
const String _legacyContactShortlistSecureKey = 'legacy.contact_shortlist.v1';
const String _legacyContactShortlistScopedSecureKeyPrefix =
    'legacy.contact_shortlist.v2.';
const String _legacyProfileNameScopedPrefKeyPrefix = 'last_login_name.v2.';
const String _legacyProfilePhoneScopedPrefKeyPrefix = 'last_login_phone.v2.';
const String _legacyDefaultOfficialAccountIdScopedPrefKeyPrefix =
    'official.default_account_id.v2.';
const String _legacyDefaultOfficialAccountNameScopedPrefKeyPrefix =
    'official.default_account_name.v2.';
const String _legacyContactShortlistScopedPrefKeyPrefix =
    'contact_shortlist.v2.';
const String _legacySensitiveBaseUrlPrefKey = 'base_url';
const String _legacySensitiveUnknownScope = 'unknown';

const FlutterSecureStorage _legacySensitivePrefSecureStore =
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

class _SecureReadResult {
  final String? value;
  final bool failed;
  const _SecureReadResult({
    required this.value,
    required this.failed,
  });
}

class LegacyProfileSummary {
  final String name;
  final String phone;

  const LegacyProfileSummary({
    required this.name,
    required this.phone,
  });
}

class LegacyDefaultOfficialAccountContext {
  final String accountId;
  final String accountName;

  const LegacyDefaultOfficialAccountContext({
    required this.accountId,
    required this.accountName,
  });
}

Future<LegacyProfileSummary> loadLegacyProfileSummary({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final values = await _loadLegacyStringPair(
    firstSecureKey: _legacyProfileNameSecureKey,
    firstLegacyKey: _legacyProfileNameKey,
    secondSecureKey: _legacyProfilePhoneSecureKey,
    secondLegacyKey: _legacyProfilePhoneKey,
    firstScopedSecureKeyPrefix: _legacyProfileNameScopedSecureKeyPrefix,
    firstScopedPrefKeyPrefix: _legacyProfileNameScopedPrefKeyPrefix,
    secondScopedSecureKeyPrefix: _legacyProfilePhoneScopedSecureKeyPrefix,
    secondScopedPrefKeyPrefix: _legacyProfilePhoneScopedPrefKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
  return LegacyProfileSummary(
    name: values.$1,
    phone: values.$2,
  );
}

Future<LegacyDefaultOfficialAccountContext>
    loadLegacyDefaultOfficialAccountContext({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final values = await _loadLegacyStringPair(
    firstSecureKey: _legacyDefaultOfficialAccountIdSecureKey,
    firstLegacyKey: _legacyDefaultOfficialAccountIdKey,
    secondSecureKey: _legacyDefaultOfficialAccountNameSecureKey,
    secondLegacyKey: _legacyDefaultOfficialAccountNameKey,
    firstScopedSecureKeyPrefix:
        _legacyDefaultOfficialAccountIdScopedSecureKeyPrefix,
    firstScopedPrefKeyPrefix:
        _legacyDefaultOfficialAccountIdScopedPrefKeyPrefix,
    secondScopedSecureKeyPrefix:
        _legacyDefaultOfficialAccountNameScopedSecureKeyPrefix,
    secondScopedPrefKeyPrefix:
        _legacyDefaultOfficialAccountNameScopedPrefKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
  return LegacyDefaultOfficialAccountContext(
    accountId: values.$1,
    accountName: values.$2,
  );
}

Future<void> saveLegacyDefaultOfficialAccountContext({
  required String accountId,
  required String accountName,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final id = accountId.trim();
  final name = accountName.trim();
  final normalizedBase = (baseUrlOverride ?? '').trim();
  if (normalizedBase.isNotEmpty) {
    await prefs.setString(_legacySensitiveBaseUrlPrefKey, normalizedBase);
  }
  final scope = _currentLegacySensitiveScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedSecureIdKey = _scopedLegacySensitiveKey(
    _legacyDefaultOfficialAccountIdScopedSecureKeyPrefix,
    scope,
  );
  final scopedSecureNameKey = _scopedLegacySensitiveKey(
    _legacyDefaultOfficialAccountNameScopedSecureKeyPrefix,
    scope,
  );
  final scopedPrefIdKey = _scopedLegacySensitiveKey(
    _legacyDefaultOfficialAccountIdScopedPrefKeyPrefix,
    scope,
  );
  final scopedPrefNameKey = _scopedLegacySensitiveKey(
    _legacyDefaultOfficialAccountNameScopedPrefKeyPrefix,
    scope,
  );

  await _secureDelete(_legacyDefaultOfficialAccountIdSecureKey);
  await _secureDelete(_legacyDefaultOfficialAccountNameSecureKey);
  await _removeLegacyStringKeys(
    <String>[
      _legacyDefaultOfficialAccountIdKey,
      _legacyDefaultOfficialAccountNameKey,
    ],
    sp: prefs,
  );

  if (_canPersistLegacySensitivePrefs()) {
    var storedSecurely = true;
    if (id.isEmpty) {
      await _secureDelete(scopedSecureIdKey);
    } else {
      storedSecurely =
          await _secureWrite(scopedSecureIdKey, id) && storedSecurely;
    }
    if (name.isEmpty) {
      await _secureDelete(scopedSecureNameKey);
    } else {
      storedSecurely =
          await _secureWrite(scopedSecureNameKey, name) && storedSecurely;
    }
    if (storedSecurely) {
      await _removeLegacyScopedPrefKeys(
        <String>[scopedPrefIdKey, scopedPrefNameKey],
        sp: prefs,
      );
      return;
    }
    await _secureDelete(scopedSecureIdKey);
    await _secureDelete(scopedSecureNameKey);
  }

  if (id.isEmpty) {
    await prefs.remove(scopedPrefIdKey);
  } else {
    await prefs.setString(scopedPrefIdKey, id);
  }
  if (name.isEmpty) {
    await prefs.remove(scopedPrefNameKey);
  } else {
    await prefs.setString(scopedPrefNameKey, name);
  }
}

Future<List<String>> loadLegacyContactShortlistEntries({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentLegacySensitiveScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedSecureKey = _scopedLegacySensitiveKey(
    _legacyContactShortlistScopedSecureKeyPrefix,
    scope,
  );
  final scopedPrefKey = _scopedLegacySensitiveKey(
    _legacyContactShortlistScopedPrefKeyPrefix,
    scope,
  );
  if (!_canPersistLegacySensitivePrefs()) {
    try {
      final scoped = List<String>.from(
        prefs.getStringList(scopedPrefKey) ?? const <String>[],
      );
      if (scoped.isNotEmpty) {
        await _removeLegacyContactShortlist(sp: prefs);
        return scoped;
      }
      final legacy = List<String>.from(
        prefs.getStringList(_legacyContactShortlistKey) ?? const <String>[],
      );
      final cleaned = legacy
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (cleaned.isEmpty) return const <String>[];
      await _removeLegacyContactShortlist(sp: prefs);
      if (_isUnknownLegacySensitiveScope(scope)) {
        await prefs.setStringList(scopedPrefKey, cleaned);
        return cleaned;
      }
      return const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  var secureReadFailed = false;
  final scopedSecureRead = await _secureRead(scopedSecureKey);
  secureReadFailed = scopedSecureRead.failed;
  final scopedSecure = scopedSecureRead.value;
  if (scopedSecure != null && scopedSecure.isNotEmpty) {
    await _removeLegacyContactShortlist(sp: prefs);
    await _removeLegacyScopedPrefKeys(<String>[scopedPrefKey], sp: prefs);
    await _secureDelete(_legacyContactShortlistSecureKey);
    return _decodeStringList(scopedSecure);
  }

  final secureRead = await _secureRead(_legacyContactShortlistSecureKey);
  secureReadFailed = secureReadFailed || secureRead.failed;
  final secure = secureRead.value;
  if (secure != null && secure.isNotEmpty) {
    final decoded = _decodeStringList(secure);
    if (decoded.isEmpty) {
      await _secureDelete(_legacyContactShortlistSecureKey);
      await _removeLegacyContactShortlist(sp: prefs);
      await _removeLegacyScopedPrefKeys(<String>[scopedPrefKey], sp: prefs);
      return const <String>[];
    }
    if (_isUnknownLegacySensitiveScope(scope)) {
      final migrated = await _secureWrite(
        scopedSecureKey,
        jsonEncode(decoded),
      );
      if (migrated) {
        await _secureDelete(_legacyContactShortlistSecureKey);
        await _removeLegacyContactShortlist(sp: prefs);
        await _removeLegacyScopedPrefKeys(<String>[scopedPrefKey], sp: prefs);
        return decoded;
      }
      await _secureDelete(scopedSecureKey);
      if (secureReadFailed) {
        return decoded;
      }
    }
    await _secureDelete(_legacyContactShortlistSecureKey);
    await _removeLegacyContactShortlist(sp: prefs);
    await _removeLegacyScopedPrefKeys(<String>[scopedPrefKey], sp: prefs);
    return const <String>[];
  }

  // Fail closed by default: do not trust mutable SharedPreferences values
  // unless fallback is explicitly enabled or secure storage is unavailable.
  if (!_allowLegacySensitiveFallback() && !secureReadFailed) {
    await _removeLegacyContactShortlist(sp: prefs);
    await _removeLegacyScopedPrefKeys(<String>[scopedPrefKey], sp: prefs);
    return const <String>[];
  }

  try {
    final legacy = List<String>.from(
      prefs.getStringList(_legacyContactShortlistKey) ?? const <String>[],
    );
    final cleaned = legacy
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return const <String>[];
    if (_isUnknownLegacySensitiveScope(scope)) {
      final migrated = await _secureWrite(
        scopedSecureKey,
        jsonEncode(cleaned),
      );
      if (migrated) {
        await _removeLegacyContactShortlist(sp: prefs);
        await _removeLegacyScopedPrefKeys(<String>[scopedPrefKey], sp: prefs);
        return cleaned;
      }
      await _secureDelete(scopedSecureKey);
      if (secureReadFailed) {
        return cleaned;
      }
    }
    await _removeLegacyContactShortlist(sp: prefs);
    await _removeLegacyScopedPrefKeys(<String>[scopedPrefKey], sp: prefs);
    return const <String>[];
  } catch (_) {
    return const <String>[];
  }
}

Future<void> clearLegacySensitivePrefState({SharedPreferences? sp}) async {
  for (final key in <String>[
    _legacyProfileNameSecureKey,
    _legacyProfilePhoneSecureKey,
    _legacyDefaultOfficialAccountIdSecureKey,
    _legacyDefaultOfficialAccountNameSecureKey,
    _legacyContactShortlistSecureKey,
  ]) {
    try {
      await _legacySensitivePrefSecureStore.delete(key: key);
    } catch (_) {}
  }
  await _removeLegacyStringKeys(
    <String>[
      _legacyProfileNameKey,
      _legacyProfilePhoneKey,
      _legacyDefaultOfficialAccountIdKey,
      _legacyDefaultOfficialAccountNameKey,
      _legacyContactShortlistKey,
    ],
    sp: sp,
  );
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final scopedPrefKeys = prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith(_legacyProfileNameScopedPrefKeyPrefix) ||
              key.startsWith(_legacyProfilePhoneScopedPrefKeyPrefix) ||
              key.startsWith(
                  _legacyDefaultOfficialAccountIdScopedPrefKeyPrefix) ||
              key.startsWith(
                _legacyDefaultOfficialAccountNameScopedPrefKeyPrefix,
              ) ||
              key.startsWith(_legacyContactShortlistScopedPrefKeyPrefix),
        )
        .toList(growable: false);
    for (final key in scopedPrefKeys) {
      await prefs.remove(key);
    }
  } catch (_) {}
  if (_canPersistLegacySensitivePrefs()) {
    try {
      final all = await _legacySensitivePrefSecureStore.readAll();
      final scopedSecureKeys = all.keys
          .where(
            (key) =>
                key.startsWith(_legacyProfileNameScopedSecureKeyPrefix) ||
                key.startsWith(_legacyProfilePhoneScopedSecureKeyPrefix) ||
                key.startsWith(
                  _legacyDefaultOfficialAccountIdScopedSecureKeyPrefix,
                ) ||
                key.startsWith(
                  _legacyDefaultOfficialAccountNameScopedSecureKeyPrefix,
                ) ||
                key.startsWith(_legacyContactShortlistScopedSecureKeyPrefix),
          )
          .toList(growable: false);
      for (final key in scopedSecureKeys) {
        await _legacySensitivePrefSecureStore.delete(key: key);
      }
    } catch (_) {}
  }
}

Future<(String, String)> _loadLegacyStringPair({
  required String firstSecureKey,
  required String firstLegacyKey,
  required String secondSecureKey,
  required String secondLegacyKey,
  required String firstScopedSecureKeyPrefix,
  required String firstScopedPrefKeyPrefix,
  required String secondScopedSecureKeyPrefix,
  required String secondScopedPrefKeyPrefix,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentLegacySensitiveScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final firstScopedSecureKey =
      _scopedLegacySensitiveKey(firstScopedSecureKeyPrefix, scope);
  final secondScopedSecureKey =
      _scopedLegacySensitiveKey(secondScopedSecureKeyPrefix, scope);
  final firstScopedPrefKey =
      _scopedLegacySensitiveKey(firstScopedPrefKeyPrefix, scope);
  final secondScopedPrefKey =
      _scopedLegacySensitiveKey(secondScopedPrefKeyPrefix, scope);

  if (!_canPersistLegacySensitivePrefs()) {
    try {
      final scopedFirst = (prefs.getString(firstScopedPrefKey) ?? '').trim();
      final scopedSecond = (prefs.getString(secondScopedPrefKey) ?? '').trim();
      if (scopedFirst.isNotEmpty || scopedSecond.isNotEmpty) {
        await _removeLegacyStringKeys(
          <String>[firstLegacyKey, secondLegacyKey],
          sp: prefs,
        );
        return (scopedFirst, scopedSecond);
      }

      final first = (prefs.getString(firstLegacyKey) ?? '').trim();
      final second = (prefs.getString(secondLegacyKey) ?? '').trim();
      if (first.isEmpty && second.isEmpty) return ('', '');
      await _removeLegacyStringKeys(
        <String>[firstLegacyKey, secondLegacyKey],
        sp: prefs,
      );
      if (_isUnknownLegacySensitiveScope(scope)) {
        if (first.isNotEmpty) {
          await prefs.setString(firstScopedPrefKey, first);
        }
        if (second.isNotEmpty) {
          await prefs.setString(secondScopedPrefKey, second);
        }
        return (first, second);
      }
      return ('', '');
    } catch (_) {
      return ('', '');
    }
  }

  var secureReadFailed = false;
  final scopedSecureFirstRead = await _secureRead(firstScopedSecureKey);
  secureReadFailed = scopedSecureFirstRead.failed;
  final scopedSecureSecondRead = await _secureRead(secondScopedSecureKey);
  secureReadFailed = secureReadFailed || scopedSecureSecondRead.failed;
  final scopedSecureFirst = scopedSecureFirstRead.value;
  final scopedSecureSecond = scopedSecureSecondRead.value;
  if (scopedSecureFirst != null || scopedSecureSecond != null) {
    await _removeLegacyStringKeys(
      <String>[firstLegacyKey, secondLegacyKey],
      sp: prefs,
    );
    await _removeLegacyScopedPrefKeys(
      <String>[firstScopedPrefKey, secondScopedPrefKey],
      sp: prefs,
    );
    await _secureDelete(firstSecureKey);
    await _secureDelete(secondSecureKey);
    return (
      (scopedSecureFirst ?? '').trim(),
      (scopedSecureSecond ?? '').trim(),
    );
  }

  final secureFirstRead = await _secureRead(firstSecureKey);
  secureReadFailed = secureReadFailed || secureFirstRead.failed;
  final secureSecondRead = await _secureRead(secondSecureKey);
  secureReadFailed = secureReadFailed || secureSecondRead.failed;
  final secureFirst = secureFirstRead.value;
  final secureSecond = secureSecondRead.value;
  if (secureFirst != null || secureSecond != null) {
    final normalizedFirst = (secureFirst ?? '').trim();
    final normalizedSecond = (secureSecond ?? '').trim();
    if (_isUnknownLegacySensitiveScope(scope)) {
      var migrated = true;
      if (normalizedFirst.isNotEmpty) {
        migrated = await _secureWrite(firstScopedSecureKey, normalizedFirst) &&
            migrated;
      }
      if (normalizedSecond.isNotEmpty) {
        migrated =
            await _secureWrite(secondScopedSecureKey, normalizedSecond) &&
                migrated;
      }
      if (migrated) {
        await _secureDelete(firstSecureKey);
        await _secureDelete(secondSecureKey);
        await _removeLegacyStringKeys(
          <String>[firstLegacyKey, secondLegacyKey],
          sp: prefs,
        );
        await _removeLegacyScopedPrefKeys(
          <String>[firstScopedPrefKey, secondScopedPrefKey],
          sp: prefs,
        );
        return (normalizedFirst, normalizedSecond);
      }
      await _secureDelete(firstScopedSecureKey);
      await _secureDelete(secondScopedSecureKey);
      if (secureReadFailed) {
        return (normalizedFirst, normalizedSecond);
      }
    }
    await _secureDelete(firstSecureKey);
    await _secureDelete(secondSecureKey);
    await _removeLegacyStringKeys(
      <String>[firstLegacyKey, secondLegacyKey],
      sp: prefs,
    );
    await _removeLegacyScopedPrefKeys(
      <String>[firstScopedPrefKey, secondScopedPrefKey],
      sp: prefs,
    );
    return ('', '');
  }

  // Fail closed by default: do not trust mutable SharedPreferences values
  // unless fallback is explicitly enabled or secure storage is unavailable.
  if (!_allowLegacySensitiveFallback() && !secureReadFailed) {
    await _removeLegacyStringKeys(
      <String>[firstLegacyKey, secondLegacyKey],
      sp: prefs,
    );
    await _removeLegacyScopedPrefKeys(
      <String>[firstScopedPrefKey, secondScopedPrefKey],
      sp: prefs,
    );
    return ('', '');
  }

  try {
    final first = (prefs.getString(firstLegacyKey) ?? '').trim();
    final second = (prefs.getString(secondLegacyKey) ?? '').trim();
    if (first.isEmpty && second.isEmpty) return ('', '');
    if (_isUnknownLegacySensitiveScope(scope)) {
      var migrated = true;
      if (first.isNotEmpty) {
        migrated = await _secureWrite(firstScopedSecureKey, first) && migrated;
      }
      if (second.isNotEmpty) {
        migrated =
            await _secureWrite(secondScopedSecureKey, second) && migrated;
      }
      if (migrated) {
        await _removeLegacyStringKeys(
          <String>[firstLegacyKey, secondLegacyKey],
          sp: prefs,
        );
        await _removeLegacyScopedPrefKeys(
          <String>[firstScopedPrefKey, secondScopedPrefKey],
          sp: prefs,
        );
        return (first, second);
      }
      await _secureDelete(firstScopedSecureKey);
      await _secureDelete(secondScopedSecureKey);
      if (secureReadFailed) {
        return (first, second);
      }
    }
    await _removeLegacyStringKeys(
      <String>[firstLegacyKey, secondLegacyKey],
      sp: prefs,
    );
    await _removeLegacyScopedPrefKeys(
      <String>[firstScopedPrefKey, secondScopedPrefKey],
      sp: prefs,
    );
    return ('', '');
  } catch (_) {
    return ('', '');
  }
}

Future<void> _removeLegacyContactShortlist({SharedPreferences? sp}) async {
  await _removeLegacyStringKeys(<String>[_legacyContactShortlistKey], sp: sp);
}

Future<void> _removeLegacyStringKeys(
  List<String> keys, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    for (final key in keys) {
      await prefs.remove(key);
    }
  } catch (_) {}
}

bool _canPersistLegacySensitivePrefs() => !kIsWeb;

bool _allowLegacySensitiveFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_SENSITIVE_PREF_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_SENSITIVE_PREF_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_SENSITIVE_PREF_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_SENSITIVE_PREF_FALLBACK',
    defaultValue: true,
  );
}

String _currentLegacySensitiveScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final rawBase =
      (baseUrlOverride ?? prefs.getString(_legacySensitiveBaseUrlPrefKey) ?? '')
          .trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _legacySensitiveUnknownScope;
}

bool _isUnknownLegacySensitiveScope(String scope) {
  return scope == _legacySensitiveUnknownScope;
}

String _scopedLegacySensitiveKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<_SecureReadResult> _secureRead(String key) async {
  try {
    final value = await _legacySensitivePrefSecureStore.read(key: key);
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
    await _legacySensitivePrefSecureStore.write(key: key, value: value);
    final roundTrip =
        (await _legacySensitivePrefSecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {}
  return false;
}

Future<void> _secureDelete(String key) async {
  try {
    await _legacySensitivePrefSecureStore.delete(key: key);
  } catch (_) {}
}

Future<void> _removeLegacyScopedPrefKeys(
  List<String> keys, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    for (final key in keys) {
      await prefs.remove(key);
    }
  } catch (_) {}
}

List<String> _decodeStringList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
  } catch (_) {
    return const <String>[];
  }
}
