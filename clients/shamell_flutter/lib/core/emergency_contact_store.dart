// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String _emergencyContactNameLegacyKey =
    'shamell.security.emergency_contact.name';
const String _emergencyContactPhoneLegacyKey =
    'shamell.security.emergency_contact.phone';
const String _emergencyContactNameSecureKey =
    'shamell.security.emergency_contact.name.v1';
const String _emergencyContactPhoneSecureKey =
    'shamell.security.emergency_contact.phone.v1';
const String _emergencyContactNameScopedSecureKeyPrefix =
    'shamell.security.emergency_contact.name.v2.';
const String _emergencyContactPhoneScopedSecureKeyPrefix =
    'shamell.security.emergency_contact.phone.v2.';
const String _emergencyContactUnknownScope = 'unknown';
const String _emergencyContactBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _emergencyContactSecureStore = FlutterSecureStorage(
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

class EmergencyContactRecord {
  final String name;
  final String phone;

  const EmergencyContactRecord({
    required this.name,
    required this.phone,
  });
}

Future<EmergencyContactRecord> loadEmergencyContactRecord({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentEmergencyContactScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  var secureReadFailed = false;
  final secureNameRead = await _secureRead(
    _scopedEmergencyContactSecureKey(
      _emergencyContactNameScopedSecureKeyPrefix,
      scope,
    ),
  );
  secureReadFailed = secureNameRead.failed;
  final securePhoneRead = await _secureRead(
    _scopedEmergencyContactSecureKey(
      _emergencyContactPhoneScopedSecureKeyPrefix,
      scope,
    ),
  );
  secureReadFailed = secureReadFailed || securePhoneRead.failed;
  final secureName = secureNameRead.value;
  final securePhone = securePhoneRead.value;
  if (secureName != null || securePhone != null) {
    await _removeLegacyEmergencyContact(sp: prefs);
    await _deleteLegacyEmergencyContactSecureKeys();
    return EmergencyContactRecord(
      name: secureName ?? '',
      phone: securePhone ?? '',
    );
  }

  final legacySecureNameRead =
      await _secureRead(_emergencyContactNameSecureKey);
  secureReadFailed = secureReadFailed || legacySecureNameRead.failed;
  final legacySecurePhoneRead =
      await _secureRead(_emergencyContactPhoneSecureKey);
  secureReadFailed = secureReadFailed || legacySecurePhoneRead.failed;
  final legacySecureName = legacySecureNameRead.value;
  final legacySecurePhone = legacySecurePhoneRead.value;
  if (legacySecureName != null || legacySecurePhone != null) {
    final normalizedLegacySecureName = (legacySecureName ?? '').trim();
    final normalizedLegacySecurePhone = (legacySecurePhone ?? '').trim();
    if (_isUnknownEmergencyContactScope(scope)) {
      final migrated = await _writeScopedEmergencyContactRecord(
        scope: scope,
        name: normalizedLegacySecureName,
        phone: normalizedLegacySecurePhone,
      );
      if (migrated) {
        await _removeLegacyEmergencyContact(sp: prefs);
        await _deleteLegacyEmergencyContactSecureKeys();
        return EmergencyContactRecord(
          name: normalizedLegacySecureName,
          phone: normalizedLegacySecurePhone,
        );
      }
      await _deleteScopedEmergencyContactSecureKey(
        _emergencyContactNameScopedSecureKeyPrefix,
        scope,
      );
      await _deleteScopedEmergencyContactSecureKey(
        _emergencyContactPhoneScopedSecureKeyPrefix,
        scope,
      );
      if (secureReadFailed) {
        return EmergencyContactRecord(
          name: normalizedLegacySecureName,
          phone: normalizedLegacySecurePhone,
        );
      }
    }
    await _removeLegacyEmergencyContact(sp: prefs);
    await _deleteLegacyEmergencyContactSecureKeys();
    return const EmergencyContactRecord(name: '', phone: '');
  }

  // Fail closed by default: do not trust mutable SharedPreferences values
  // unless fallback is explicitly enabled or secure storage is unavailable.
  if (!_allowLegacyEmergencyContactFallback() && !secureReadFailed) {
    await _removeLegacyEmergencyContact(sp: prefs);
    return const EmergencyContactRecord(name: '', phone: '');
  }

  final legacyName =
      (prefs.getString(_emergencyContactNameLegacyKey) ?? '').trim();
  final legacyPhone =
      (prefs.getString(_emergencyContactPhoneLegacyKey) ?? '').trim();
  if (legacyName.isEmpty && legacyPhone.isEmpty) {
    return const EmergencyContactRecord(name: '', phone: '');
  }

  if (_isUnknownEmergencyContactScope(scope)) {
    final migrated = await _writeScopedEmergencyContactRecord(
      scope: scope,
      name: legacyName,
      phone: legacyPhone,
    );
    if (migrated) {
      await _removeLegacyEmergencyContact(sp: prefs);
      return EmergencyContactRecord(name: legacyName, phone: legacyPhone);
    }
    await _deleteScopedEmergencyContactSecureKey(
      _emergencyContactNameScopedSecureKeyPrefix,
      scope,
    );
    await _deleteScopedEmergencyContactSecureKey(
      _emergencyContactPhoneScopedSecureKeyPrefix,
      scope,
    );
    if (secureReadFailed) {
      return EmergencyContactRecord(name: legacyName, phone: legacyPhone);
    }
  }
  await _removeLegacyEmergencyContact(sp: prefs);
  return const EmergencyContactRecord(name: '', phone: '');
}

Future<bool> saveEmergencyContactRecord({
  required String name,
  required String phone,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final normalizedName = name.trim();
  final normalizedPhone = phone.trim();
  if (normalizedName.isEmpty && normalizedPhone.isEmpty) {
    await clearEmergencyContactRecord(
      sp: sp,
      baseUrlOverride: baseUrlOverride,
    );
    return true;
  }

  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currentEmergencyContactScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final saved = await _writeScopedEmergencyContactRecord(
    scope: scope,
    name: normalizedName,
    phone: normalizedPhone,
  );
  await _removeLegacyEmergencyContact(sp: prefs);
  await _deleteLegacyEmergencyContactSecureKeys();
  if (!saved) {
    await clearEmergencyContactRecord(
      sp: prefs,
      baseUrlOverride: baseUrlOverride,
    );
    return false;
  }
  return true;
}

Future<void> clearEmergencyContactRecord({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  if ((baseUrlOverride ?? '').trim().isNotEmpty) {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final scope = _currentEmergencyContactScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    );
    await _deleteScopedEmergencyContactSecureKey(
      _emergencyContactNameScopedSecureKeyPrefix,
      scope,
    );
    await _deleteScopedEmergencyContactSecureKey(
      _emergencyContactPhoneScopedSecureKeyPrefix,
      scope,
    );
    await _removeLegacyEmergencyContact(sp: prefs);
    await _deleteLegacyEmergencyContactSecureKeys();
    return;
  }
  await _clearAllEmergencyContactSecureKeys();
  await _removeLegacyEmergencyContact(sp: sp);
}

Future<void> _removeLegacyEmergencyContact({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(_emergencyContactNameLegacyKey);
    await prefs.remove(_emergencyContactPhoneLegacyKey);
  } catch (_) {}
}

Future<bool> _writeScopedEmergencyContactRecord({
  required String scope,
  required String name,
  required String phone,
}) async {
  final nameOk = await _writeScopedEmergencyContactField(
    keyPrefix: _emergencyContactNameScopedSecureKeyPrefix,
    scope: scope,
    value: name,
  );
  final phoneOk = await _writeScopedEmergencyContactField(
    keyPrefix: _emergencyContactPhoneScopedSecureKeyPrefix,
    scope: scope,
    value: phone,
  );
  return nameOk && phoneOk;
}

Future<bool> _writeScopedEmergencyContactField({
  required String keyPrefix,
  required String scope,
  required String value,
}) async {
  final normalized = value.trim();
  final key = _scopedEmergencyContactSecureKey(keyPrefix, scope);
  if (normalized.isEmpty) {
    await _deleteScopedEmergencyContactSecureKey(keyPrefix, scope);
    return true;
  }
  return _secureWrite(key, normalized);
}

Future<void> _deleteScopedEmergencyContactSecureKey(
  String keyPrefix,
  String scope,
) async {
  try {
    await _emergencyContactSecureStore.delete(
      key: _scopedEmergencyContactSecureKey(keyPrefix, scope),
    );
  } catch (_) {}
}

Future<void> _deleteLegacyEmergencyContactSecureKeys() async {
  try {
    await _emergencyContactSecureStore.delete(
        key: _emergencyContactNameSecureKey);
  } catch (_) {}
  try {
    await _emergencyContactSecureStore.delete(
      key: _emergencyContactPhoneSecureKey,
    );
  } catch (_) {}
}

Future<void> _clearAllEmergencyContactSecureKeys() async {
  await _deleteLegacyEmergencyContactSecureKeys();
  try {
    final all = await _emergencyContactSecureStore.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_emergencyContactNameScopedSecureKeyPrefix) ||
          key.startsWith(_emergencyContactPhoneScopedSecureKeyPrefix)) {
        try {
          await _emergencyContactSecureStore.delete(key: key);
        } catch (_) {}
      }
    }
  } catch (_) {}
}

Future<_SecureReadResult> _secureRead(String key) async {
  if (kIsWeb) return const _SecureReadResult(value: null, failed: false);
  try {
    final value = await _emergencyContactSecureStore.read(key: key);
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
  if (kIsWeb) return false;
  try {
    await _emergencyContactSecureStore.write(key: key, value: value);
    final roundTrip =
        (await _emergencyContactSecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

bool _allowLegacyEmergencyContactFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_EMERGENCY_CONTACT_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_EMERGENCY_CONTACT_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_EMERGENCY_CONTACT_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_EMERGENCY_CONTACT_FALLBACK',
    defaultValue: true,
  );
}

String _currentEmergencyContactScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final raw = (baseUrlOverride ??
          prefs.getString(_emergencyContactBaseUrlPrefKey) ??
          '')
      .trim();
  final normalized = normalizeSecureApiBaseUrl(raw) ?? '';
  if (normalized.isEmpty) return _emergencyContactUnknownScope;
  return Uri.parse(normalized).origin;
}

bool _isUnknownEmergencyContactScope(String scope) =>
    scope == _emergencyContactUnknownScope;

String _scopedEmergencyContactSecureKey(String keyPrefix, String scope) =>
    '$keyPrefix$scope';
