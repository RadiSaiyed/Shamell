// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';
import 'notification_tap_target.dart';

const String kPendingNotificationPayloadLegacyKey =
    'ui.pending_notification_payload';
const String _pendingNotificationPayloadLegacySecureKey =
    'ui.pending_notification_payload.v1';
const String _pendingNotificationPayloadScopedKeyPrefix =
    'ui.pending_notification_payload.v2.';
const String _pendingNotificationUnknownScope = 'unknown';
const String _pendingNotificationBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _pendingNotificationSecureStore =
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

class _SecurePendingPayloadReadResult {
  final String? value;
  final bool failed;
  const _SecurePendingPayloadReadResult({
    required this.value,
    required this.failed,
  });
}

Future<bool> _savePendingNotificationPayload(
  String payload, {
  String? baseUrlOverride,
}) async {
  final raw = payload.trim();
  if (raw.isEmpty) {
    await clearPendingNotificationPayload(baseUrlOverride: baseUrlOverride);
    return true;
  }
  final normalized = canonicalizePendingNotificationPayload(raw);
  if (normalized == null) {
    await clearPendingNotificationPayload(baseUrlOverride: baseUrlOverride);
    return false;
  }

  final sp = await SharedPreferences.getInstance();
  final scopedKey = _scopedPendingNotificationKey(
    _currentPendingNotificationScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    ),
  );

  if (kIsWeb) {
    try {
      await sp.setString(scopedKey, normalized);
      await _removeLegacyPendingNotificationPayload(sp: sp);
      return true;
    } catch (_) {
      return false;
    }
  }

  try {
    await _pendingNotificationSecureStore.write(
      key: scopedKey,
      value: normalized,
    );
    final roundTrip = (await _pendingNotificationSecureStore.read(
              key: scopedKey,
            ) ??
            '')
        .trim();
    if (roundTrip != normalized) {
      await clearPendingNotificationPayload(baseUrlOverride: baseUrlOverride);
      return false;
    }
    await _clearLegacyPendingNotificationPayload(sp: sp);
    return true;
  } catch (_) {
    await clearPendingNotificationPayload(baseUrlOverride: baseUrlOverride);
    return false;
  }
}

Future<bool> savePendingNotificationTapTarget(
  NotificationTapTarget tapTarget, {
  String? baseUrlOverride,
}) async {
  final payload = payloadForNotificationTapTarget(tapTarget);
  if (payload == null || payload.isEmpty) {
    await clearPendingNotificationPayload(baseUrlOverride: baseUrlOverride);
    return false;
  }
  return _savePendingNotificationPayload(
    payload,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<String?> _takePendingNotificationPayload({
  String? baseUrlOverride,
}) async {
  final sp = await SharedPreferences.getInstance();
  final scope = _currentPendingNotificationScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedPendingNotificationKey(scope);
  if (kIsWeb) {
    try {
      final scoped = canonicalizePendingNotificationPayload(
          (sp.getString(scopedKey) ?? ''));
      if (scoped != null) {
        await sp.remove(scopedKey);
        await _removeLegacyPendingNotificationPayload(sp: sp);
        return scoped;
      }
      await sp.remove(scopedKey);
      final payload = canonicalizePendingNotificationPayload(
          sp.getString(kPendingNotificationPayloadLegacyKey) ?? '');
      if (payload == null) {
        await _removeLegacyPendingNotificationPayload(sp: sp);
        return null;
      }
      await _removeLegacyPendingNotificationPayload(sp: sp);
      if (_isUnknownPendingNotificationScope(scope)) {
        return payload;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  var secureReadFailed = false;
  final secureRead = await _readSecurePendingNotificationPayload(scopedKey);
  secureReadFailed = secureRead.failed;
  final secure = secureRead.value;
  if (secure != null) {
    try {
      await _pendingNotificationSecureStore.delete(key: scopedKey);
    } catch (_) {}
    await _clearLegacyPendingNotificationPayload(sp: sp);
    return secure;
  }
  try {
    await _pendingNotificationSecureStore.delete(key: scopedKey);
  } catch (_) {}

  final legacySecureRead = await _readSecurePendingNotificationPayload(
    _pendingNotificationPayloadLegacySecureKey,
  );
  secureReadFailed = secureReadFailed || legacySecureRead.failed;
  final legacySecure = legacySecureRead.value;
  if (legacySecure != null) {
    await _clearLegacyPendingNotificationPayload(sp: sp);
    if (_isUnknownPendingNotificationScope(scope)) {
      return legacySecure;
    }
    return null;
  }

  // Fail closed by default: do not trust mutable SharedPreferences payloads
  // unless fallback is explicitly enabled or secure storage is unavailable.
  if (!_allowLegacyPendingNotificationFallback() && !secureReadFailed) {
    await _clearLegacyPendingNotificationPayload(sp: sp);
    return null;
  }

  try {
    final legacy = canonicalizePendingNotificationPayload(
      (sp.getString(kPendingNotificationPayloadLegacyKey) ?? '').trim(),
    );
    await _clearLegacyPendingNotificationPayload(sp: sp);
    if (legacy == null) return null;
    if (_isUnknownPendingNotificationScope(scope)) {
      return legacy;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<NotificationTapTarget?> takePendingNotificationTapTarget({
  String? baseUrlOverride,
}) async {
  final payload = await _takePendingNotificationPayload(
    baseUrlOverride: baseUrlOverride,
  );
  return parseNotificationTapTargetPayload(payload);
}

Future<void> clearPendingNotificationPayload({
  String? baseUrlOverride,
}) async {
  final sp = await SharedPreferences.getInstance();
  final normalizedOverride = normalizeSecureApiBaseUrl(
    (baseUrlOverride ?? '').trim(),
  );
  if (normalizedOverride != null && normalizedOverride.isNotEmpty) {
    final scopedKey = _scopedPendingNotificationKey(normalizedOverride);
    if (!kIsWeb) {
      try {
        await _pendingNotificationSecureStore.delete(key: scopedKey);
      } catch (_) {}
    }
    try {
      await sp.remove(scopedKey);
    } catch (_) {}
    await _clearLegacyPendingNotificationPayload(sp: sp);
    return;
  }
  if (!kIsWeb) {
    await _clearAllPendingNotificationSecureKeys();
  }
  await _clearAllPendingNotificationPrefs(sp: sp);
}

Future<void> _removeLegacyPendingNotificationPayload({
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(kPendingNotificationPayloadLegacyKey);
  } catch (_) {}
}

String _currentPendingNotificationScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final rawBase = (baseUrlOverride ??
          prefs.getString(_pendingNotificationBaseUrlPrefKey) ??
          '')
      .trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _pendingNotificationUnknownScope;
}

bool _isUnknownPendingNotificationScope(String scope) {
  return scope == _pendingNotificationUnknownScope;
}

bool _allowLegacyPendingNotificationFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_PENDING_NOTIFICATION_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_PENDING_NOTIFICATION_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_PENDING_NOTIFICATION_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_PENDING_NOTIFICATION_FALLBACK',
    defaultValue: true,
  );
}

String _scopedPendingNotificationKey(String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_pendingNotificationPayloadScopedKeyPrefix$suffix';
}

Future<_SecurePendingPayloadReadResult> _readSecurePendingNotificationPayload(
  String key,
) async {
  try {
    final value = canonicalizePendingNotificationPayload(
      (await _pendingNotificationSecureStore.read(key: key) ?? '').trim(),
    );
    return _SecurePendingPayloadReadResult(value: value, failed: false);
  } catch (_) {
    return const _SecurePendingPayloadReadResult(value: null, failed: true);
  }
}

Future<void> _clearLegacyPendingNotificationPayload({
  required SharedPreferences sp,
}) async {
  try {
    await _pendingNotificationSecureStore.delete(
      key: _pendingNotificationPayloadLegacySecureKey,
    );
  } catch (_) {}
  await _removeLegacyPendingNotificationPayload(sp: sp);
}

Future<void> _clearAllPendingNotificationSecureKeys() async {
  try {
    final all = await _pendingNotificationSecureStore.readAll();
    for (final key in all.keys) {
      if (key == _pendingNotificationPayloadLegacySecureKey ||
          key.startsWith(_pendingNotificationPayloadScopedKeyPrefix)) {
        try {
          await _pendingNotificationSecureStore.delete(key: key);
        } catch (_) {}
      }
    }
  } catch (_) {
    try {
      await _pendingNotificationSecureStore.delete(
        key: _pendingNotificationPayloadLegacySecureKey,
      );
    } catch (_) {}
  }
}

Future<void> _clearAllPendingNotificationPrefs({
  required SharedPreferences sp,
}) async {
  try {
    final keys = sp
        .getKeys()
        .where((key) =>
            key == kPendingNotificationPayloadLegacyKey ||
            key.startsWith(_pendingNotificationPayloadScopedKeyPrefix))
        .toList(growable: false);
    for (final key in keys) {
      await sp.remove(key);
    }
  } catch (_) {}
}
