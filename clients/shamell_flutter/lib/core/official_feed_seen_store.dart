// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String kOfficialFeedSeenLegacyKey = 'official.feed_seen';
const String _officialFeedSeenLegacySecureKey = 'official.feed_seen.v1';
const String _officialFeedSeenScopedSecurePrefix = 'official.feed_seen.v2.';
const String _officialFeedSeenUnknownScope = 'unknown';
const String _officialFeedSeenBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _officialFeedSeenSecureStore = FlutterSecureStorage(
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

class _SecureSeenReadResult {
  final Map<String, String> value;
  final bool failed;
  const _SecureSeenReadResult({
    required this.value,
    required this.failed,
  });
}

Future<Map<String, String>> loadOfficialFeedSeenMap({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentOfficialFeedSeenScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedOfficialFeedSeenKey(scope);

  if (!kIsWeb) {
    var secureReadFailed = false;
    final secureRead = await _readSecureOfficialFeedSeenResult(scopedKey);
    secureReadFailed = secureRead.failed;
    final secure = secureRead.value;
    if (secure.isNotEmpty) {
      await _clearLegacyOfficialFeedSeen(sp: prefs);
      return secure;
    }

    final legacySecureRead = await _readSecureOfficialFeedSeenResult(
      _officialFeedSeenLegacySecureKey,
    );
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = legacySecureRead.value;
    if (legacySecure.isNotEmpty) {
      if (_isUnknownOfficialFeedSeenScope(scope)) {
        final wrote =
            await _writeSecureOfficialFeedSeen(scopedKey, legacySecure);
        if (wrote) {
          await _clearLegacyOfficialFeedSeen(sp: prefs);
          return legacySecure;
        }
        await _deleteSecureOfficialFeedSeen(scopedKey);
        if (secureReadFailed) {
          return legacySecure;
        }
      }
      await _clearLegacyOfficialFeedSeen(sp: prefs);
      return const <String, String>{};
    }

    // Fail closed by default: do not trust mutable SharedPreferences values
    // unless fallback is explicitly enabled or secure storage is unavailable.
    if (!_allowLegacyOfficialFeedSeenFallback() && !secureReadFailed) {
      await _clearLegacyOfficialFeedSeen(sp: prefs);
      return const <String, String>{};
    }

    final legacy = await _readLegacyOfficialFeedSeen(sp: prefs);
    if (legacy.isEmpty) return const <String, String>{};

    if (_isUnknownOfficialFeedSeenScope(scope)) {
      final wrote = await _writeSecureOfficialFeedSeen(scopedKey, legacy);
      if (wrote) {
        await _clearLegacyOfficialFeedSeen(sp: prefs);
        return legacy;
      }
      await _deleteSecureOfficialFeedSeen(scopedKey);
      if (secureReadFailed) {
        return legacy;
      }
    }
    await _clearLegacyOfficialFeedSeen(sp: prefs);
    return const <String, String>{};
  }

  try {
    final scoped = (prefs.getString(scopedKey) ?? '').trim();
    if (scoped.isNotEmpty) {
      await _removeLegacyOfficialFeedSeen(sp: prefs);
      return _decodeOfficialFeedSeen(scoped);
    }
  } catch (_) {}

  final legacy = await _readLegacyOfficialFeedSeen(sp: prefs);
  if (legacy.isEmpty) return const <String, String>{};

  await _removeLegacyOfficialFeedSeen(sp: prefs);
  if (_isUnknownOfficialFeedSeenScope(scope)) {
    try {
      await prefs.setString(scopedKey, jsonEncode(legacy));
      return legacy;
    } catch (_) {
      return const <String, String>{};
    }
  }
  return const <String, String>{};
}

Future<void> clearOfficialFeedSeenMap({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final normalizedOverride = normalizeSecureApiBaseUrl(
    (baseUrlOverride ?? '').trim(),
  );
  if (normalizedOverride != null && normalizedOverride.isNotEmpty) {
    final scopedKey = _scopedOfficialFeedSeenKey(normalizedOverride);
    if (!kIsWeb) {
      await _deleteSecureOfficialFeedSeen(scopedKey);
    }
    try {
      await prefs.remove(scopedKey);
    } catch (_) {}
    await _clearLegacyOfficialFeedSeen(sp: prefs);
    return;
  }
  if (!kIsWeb) {
    try {
      final all = await _officialFeedSeenSecureStore.readAll();
      for (final key in all.keys) {
        if (key == _officialFeedSeenLegacySecureKey ||
            key.startsWith(_officialFeedSeenScopedSecurePrefix)) {
          try {
            await _officialFeedSeenSecureStore.delete(key: key);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
  try {
    final keys = prefs
        .getKeys()
        .where((key) =>
            key == kOfficialFeedSeenLegacyKey ||
            key.startsWith(_officialFeedSeenScopedSecurePrefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  } catch (_) {}
}

Future<_SecureSeenReadResult> _readSecureOfficialFeedSeenResult(
  String key,
) async {
  try {
    final raw =
        (await _officialFeedSeenSecureStore.read(key: key) ?? '').trim();
    if (raw.isEmpty) {
      return const _SecureSeenReadResult(
        value: <String, String>{},
        failed: false,
      );
    }
    return _SecureSeenReadResult(
      value: _decodeOfficialFeedSeen(raw),
      failed: false,
    );
  } catch (_) {
    return const _SecureSeenReadResult(
      value: <String, String>{},
      failed: true,
    );
  }
}

bool _allowLegacyOfficialFeedSeenFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_OFFICIAL_FEED_SEEN_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_OFFICIAL_FEED_SEEN_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_OFFICIAL_FEED_SEEN_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_OFFICIAL_FEED_SEEN_FALLBACK',
    defaultValue: true,
  );
}

Future<Map<String, String>> _readLegacyOfficialFeedSeen({
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final raw = (prefs.getString(kOfficialFeedSeenLegacyKey) ?? '').trim();
    if (raw.isEmpty) return const <String, String>{};
    return _decodeOfficialFeedSeen(raw);
  } catch (_) {
    return const <String, String>{};
  }
}

Future<bool> _writeSecureOfficialFeedSeen(
  String key,
  Map<String, String> values,
) async {
  if (values.isEmpty) {
    try {
      await _officialFeedSeenSecureStore.delete(key: key);
      return true;
    } catch (_) {
      return false;
    }
  }

  try {
    final encoded = jsonEncode(values);
    await _officialFeedSeenSecureStore.write(
      key: key,
      value: encoded,
    );
    final roundTrip = (await _officialFeedSeenSecureStore.read(
              key: key,
            ) ??
            '')
        .trim();
    return roundTrip == encoded;
  } catch (_) {
    return false;
  }
}

Future<bool> _deleteSecureOfficialFeedSeen(String key) async {
  try {
    await _officialFeedSeenSecureStore.delete(key: key);
    final roundTrip =
        (await _officialFeedSeenSecureStore.read(key: key) ?? '').trim();
    return roundTrip.isEmpty;
  } catch (_) {
    return false;
  }
}

String _currentOfficialFeedSeenScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final rawBase = (baseUrlOverride ??
          prefs.getString(_officialFeedSeenBaseUrlPrefKey) ??
          '')
      .trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _officialFeedSeenUnknownScope;
}

bool _isUnknownOfficialFeedSeenScope(String scope) {
  return scope == _officialFeedSeenUnknownScope;
}

String _scopedOfficialFeedSeenKey(String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_officialFeedSeenScopedSecurePrefix$suffix';
}

Future<void> _clearLegacyOfficialFeedSeen({
  SharedPreferences? sp,
}) async {
  await _deleteSecureOfficialFeedSeen(_officialFeedSeenLegacySecureKey);
  await _removeLegacyOfficialFeedSeen(sp: sp);
}

Future<void> _removeLegacyOfficialFeedSeen({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(kOfficialFeedSeenLegacyKey);
  } catch (_) {}
}

Map<String, String> _decodeOfficialFeedSeen(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const <String, String>{};
    final out = <String, String>{};
    decoded.forEach((key, value) {
      final normalizedKey = key.toString().trim();
      final normalizedValue = value.toString().trim();
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) return;
      out[normalizedKey] = normalizedValue;
    });
    return out;
  } catch (_) {
    return const <String, String>{};
  }
}
