// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/base_url.dart';

const String _paymentRecentsLegacyKey = 'pay_recents';
const String _paymentRecentsLegacySecureKey = 'payments.pay_recents.v1';
const String _paymentRecentsScopedKeyPrefix = 'payments.pay_recents.v2.';
const String _billTemplatesLegacyKey = 'bill_templates';
const String _billTemplatesLegacySecureKey = 'payments.bill_templates.v1';
const String _billTemplatesScopedKeyPrefix = 'payments.bill_templates.v2.';
const String _seenPaymentRequestsLegacyKey = 'seen_reqs';
const String _seenPaymentRequestsLegacySecureKey = 'payments.seen_reqs.v1';
const String _seenPaymentRequestsScopedKeyPrefix = 'payments.seen_reqs.v2.';
const String _paymentsLocalUnknownScope = 'unknown';
const String _paymentsLocalBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _paymentsLocalSecureStore = FlutterSecureStorage(
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

Future<List<String>> loadPaymentRecents({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _loadStringListWithMigration(
    legacyKey: _paymentRecentsLegacyKey,
    legacySecureKey: _paymentRecentsLegacySecureKey,
    scopedKeyPrefix: _paymentRecentsScopedKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<bool> savePaymentRecents(
  List<String> recents, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _saveStringList(
    values: recents,
    legacyKey: _paymentRecentsLegacyKey,
    legacySecureKey: _paymentRecentsLegacySecureKey,
    scopedKeyPrefix: _paymentRecentsScopedKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<List<String>> loadBillTemplateEntries({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _loadStringListWithMigration(
    legacyKey: _billTemplatesLegacyKey,
    legacySecureKey: _billTemplatesLegacySecureKey,
    scopedKeyPrefix: _billTemplatesScopedKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<bool> saveBillTemplateEntries(
  List<String> entries, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _saveStringList(
    values: entries,
    legacyKey: _billTemplatesLegacyKey,
    legacySecureKey: _billTemplatesLegacySecureKey,
    scopedKeyPrefix: _billTemplatesScopedKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> clearPaymentsLocalData() async {
  final sp = await SharedPreferences.getInstance();
  if (!kIsWeb) {
    await _clearAllScopedSecureKeys(
      prefixes: <String>[
        _paymentRecentsScopedKeyPrefix,
        _billTemplatesScopedKeyPrefix,
        _seenPaymentRequestsScopedKeyPrefix,
      ],
      legacySecureKeys: <String>[
        _paymentRecentsLegacySecureKey,
        _billTemplatesLegacySecureKey,
        _seenPaymentRequestsLegacySecureKey,
      ],
    );
  }
  await _clearAllScopedLegacyKeys(
    sp: sp,
    prefixes: <String>[
      _paymentRecentsScopedKeyPrefix,
      _billTemplatesScopedKeyPrefix,
      _seenPaymentRequestsScopedKeyPrefix,
    ],
    legacyKeys: <String>[
      _paymentRecentsLegacyKey,
      _billTemplatesLegacyKey,
      _seenPaymentRequestsLegacyKey,
    ],
  );
}

Future<List<String>> loadSeenPaymentRequestIds({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _loadStringListWithMigration(
    legacyKey: _seenPaymentRequestsLegacyKey,
    legacySecureKey: _seenPaymentRequestsLegacySecureKey,
    scopedKeyPrefix: _seenPaymentRequestsScopedKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<bool> saveSeenPaymentRequestIds(
  Iterable<String> requestIds, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  return _saveStringList(
    values: requestIds.toList(growable: false),
    legacyKey: _seenPaymentRequestsLegacyKey,
    legacySecureKey: _seenPaymentRequestsLegacySecureKey,
    scopedKeyPrefix: _seenPaymentRequestsScopedKeyPrefix,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<List<String>> _loadStringListWithMigration({
  required String legacyKey,
  required String legacySecureKey,
  required String scopedKeyPrefix,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentPaymentsLocalScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedPaymentsLocalKey(scopedKeyPrefix, scope);
  if (kIsWeb) {
    final scoped =
        _sanitizeStringList(prefs.getStringList(scopedKey) ?? const <String>[]);
    if (scoped.isNotEmpty) {
      await _removeLegacyStringList(legacyKey, sp: prefs);
      return scoped;
    }

    final legacy =
        _sanitizeStringList(prefs.getStringList(legacyKey) ?? const <String>[]);
    if (legacy.isEmpty) return const <String>[];
    await _removeLegacyStringList(legacyKey, sp: prefs);
    if (_isUnknownPaymentsLocalScope(scope)) {
      await prefs.setStringList(scopedKey, legacy);
      return legacy;
    }
    return const <String>[];
  }

  var secureReadFailed = false;
  final secureRead = await _secureRead(scopedKey);
  secureReadFailed = secureRead.failed;
  final secureRaw = secureRead.value;
  if (secureRaw != null) {
    await _clearLegacyStringList(
      legacyKey: legacyKey,
      legacySecureKey: legacySecureKey,
      sp: prefs,
    );
    return _decodeStringList(secureRaw);
  }

  final legacySecureRead = await _secureRead(legacySecureKey);
  secureReadFailed = secureReadFailed || legacySecureRead.failed;
  final legacySecureRaw = legacySecureRead.value;
  if (legacySecureRaw != null) {
    final legacySecure = _decodeStringList(legacySecureRaw);
    if (_isUnknownPaymentsLocalScope(scope) && legacySecure.isNotEmpty) {
      final migrated = await _secureWrite(scopedKey, jsonEncode(legacySecure));
      if (migrated) {
        await _clearLegacyStringList(
          legacyKey: legacyKey,
          legacySecureKey: legacySecureKey,
          sp: prefs,
        );
        return legacySecure;
      }
      await _secureDelete(scopedKey);
      if (secureReadFailed) {
        return legacySecure;
      }
    }
    await _clearLegacyStringList(
      legacyKey: legacyKey,
      legacySecureKey: legacySecureKey,
      sp: prefs,
    );
    return const <String>[];
  }

  // Fail closed by default: ignore mutable SharedPreferences payment state on
  // mobile unless fallback is explicitly enabled, or secure storage is
  // currently unavailable.
  if (!_allowLegacyPaymentsLocalFallback() && !secureReadFailed) {
    await _removeLegacyStringList(legacyKey, sp: prefs);
    return const <String>[];
  }

  final legacy =
      _sanitizeStringList(prefs.getStringList(legacyKey) ?? const <String>[]);
  if (legacy.isEmpty) return const <String>[];

  if (_isUnknownPaymentsLocalScope(scope)) {
    final migrated = await _secureWrite(scopedKey, jsonEncode(legacy));
    if (migrated) {
      await _clearLegacyStringList(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        sp: prefs,
      );
      return legacy;
    }
    await _secureDelete(scopedKey);
    if (secureReadFailed) {
      return legacy;
    }
  }
  await _clearLegacyStringList(
    legacyKey: legacyKey,
    legacySecureKey: legacySecureKey,
    sp: prefs,
  );
  return const <String>[];
}

Future<bool> _saveStringList({
  required List<String> values,
  required String legacyKey,
  required String legacySecureKey,
  required String scopedKeyPrefix,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scopedKey = _scopedPaymentsLocalKey(
    scopedKeyPrefix,
    _currentPaymentsLocalScope(prefs, baseUrlOverride: baseUrlOverride),
  );
  final cleaned = _sanitizeStringList(values);
  if (kIsWeb) {
    try {
      if (cleaned.isEmpty) {
        await prefs.remove(scopedKey);
      } else {
        await prefs.setStringList(scopedKey, cleaned);
      }
      await _removeLegacyStringList(legacyKey, sp: prefs);
      return true;
    } catch (_) {
      return false;
    }
  }

  if (cleaned.isEmpty) {
    await _secureDelete(scopedKey);
    await _clearLegacyStringList(
      legacyKey: legacyKey,
      legacySecureKey: legacySecureKey,
      sp: prefs,
    );
    return true;
  }

  final wrote = await _secureWrite(scopedKey, jsonEncode(cleaned));
  await _clearLegacyStringList(
    legacyKey: legacyKey,
    legacySecureKey: legacySecureKey,
    sp: prefs,
  );
  if (!wrote) {
    await _secureDelete(scopedKey);
    return false;
  }
  return true;
}

List<String> _decodeStringList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return _sanitizeStringList(decoded.map((e) => e.toString()));
  } catch (_) {
    return const <String>[];
  }
}

List<String> _sanitizeStringList(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

Future<void> _removeLegacyStringList(
  String key, {
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(key);
  } catch (_) {}
}

Future<_SecureReadResult> _secureRead(String key) async {
  try {
    final value = await _paymentsLocalSecureStore.read(key: key);
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
    await _paymentsLocalSecureStore.write(key: key, value: value);
    final roundTrip =
        (await _paymentsLocalSecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<bool> _secureDelete(String key) async {
  try {
    await _paymentsLocalSecureStore.delete(key: key);
    final roundTrip =
        (await _paymentsLocalSecureStore.read(key: key) ?? '').trim();
    return roundTrip.isEmpty;
  } catch (_) {
    return false;
  }
}

String _currentPaymentsLocalScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final rawBase =
      (baseUrlOverride ?? prefs.getString(_paymentsLocalBaseUrlPrefKey) ?? '')
          .trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _paymentsLocalUnknownScope;
}

bool _isUnknownPaymentsLocalScope(String scope) {
  return scope == _paymentsLocalUnknownScope;
}

bool _allowLegacyPaymentsLocalFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_PAYMENTS_LOCAL_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_PAYMENTS_LOCAL_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_PAYMENTS_LOCAL_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_PAYMENTS_LOCAL_FALLBACK',
    defaultValue: true,
  );
}

String _scopedPaymentsLocalKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<void> _clearLegacyStringList({
  required String legacyKey,
  required String legacySecureKey,
  required SharedPreferences sp,
}) async {
  await _secureDelete(legacySecureKey);
  await _removeLegacyStringList(legacyKey, sp: sp);
}

Future<void> _clearAllScopedSecureKeys({
  required List<String> prefixes,
  required List<String> legacySecureKeys,
}) async {
  try {
    final all = await _paymentsLocalSecureStore.readAll();
    for (final key in all.keys) {
      if (legacySecureKeys.contains(key) ||
          prefixes.any((prefix) => key.startsWith(prefix))) {
        try {
          await _paymentsLocalSecureStore.delete(key: key);
        } catch (_) {}
      }
    }
  } catch (_) {
    for (final key in legacySecureKeys) {
      await _secureDelete(key);
    }
  }
}

Future<void> _clearAllScopedLegacyKeys({
  required SharedPreferences sp,
  required List<String> prefixes,
  required List<String> legacyKeys,
}) async {
  try {
    final keys = sp
        .getKeys()
        .where((key) =>
            legacyKeys.contains(key) ||
            prefixes.any((prefix) => key.startsWith(prefix)))
        .toList(growable: false);
    for (final key in keys) {
      await sp.remove(key);
    }
  } catch (_) {}
}
