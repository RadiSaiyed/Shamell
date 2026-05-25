// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_snapshot_store.dart';
import 'base_url.dart';

const String _accountRolesLegacyKey = 'roles';
const String _accountIsSuperadminLegacyKey = 'is_superadmin';
const String _accountPhoneLegacyKey = 'phone';
const String _accountRolesLegacySecureKey = 'shamell.security.account.roles.v1';
const String _accountPrivilegeSnapshotScopedPrefix =
    'shamell.security.account.snapshot.v3.';
const String _accountRolesScopedSecurePrefix =
    'shamell.security.account.roles.v2.';
const String _accountOperatorIdsScopedSecurePrefix =
    'shamell.security.account.operator_ids.v1.';
const String _accountIsSuperadminLegacySecureKey =
    'shamell.security.account.is_superadmin.v1';
const String _accountIsSuperadminScopedSecurePrefix =
    'shamell.security.account.is_superadmin.v2.';
const String _accountPrivilegeUnknownScope = 'unknown';
const String _accountPrivilegeBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _accountPrivilegeSecureStore = FlutterSecureStorage(
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

class AccountPrivilegeSnapshot {
  final List<String> roles;
  final List<String> operatorIds;
  final List<String> permissions;
  final List<String> products;
  final List<String> officialAccountIds;
  final bool officialAccountWildcard;
  final bool hasPlatformScope;
  final bool isAdmin;
  final bool isSuperadmin;

  const AccountPrivilegeSnapshot({
    this.roles = const <String>[],
    this.operatorIds = const <String>[],
    this.permissions = const <String>[],
    this.products = const <String>[],
    this.officialAccountIds = const <String>[],
    this.officialAccountWildcard = false,
    this.hasPlatformScope = false,
    this.isAdmin = false,
    this.isSuperadmin = false,
  });

  static const empty = AccountPrivilegeSnapshot();

  AccountPrivilegeSnapshot copyWith({
    List<String>? roles,
    List<String>? operatorIds,
    List<String>? permissions,
    List<String>? products,
    List<String>? officialAccountIds,
    bool? officialAccountWildcard,
    bool? hasPlatformScope,
    bool? isAdmin,
    bool? isSuperadmin,
  }) {
    return AccountPrivilegeSnapshot(
      roles: roles ?? this.roles,
      operatorIds: operatorIds ?? this.operatorIds,
      permissions: permissions ?? this.permissions,
      products: products ?? this.products,
      officialAccountIds: officialAccountIds ?? this.officialAccountIds,
      officialAccountWildcard:
          officialAccountWildcard ?? this.officialAccountWildcard,
      hasPlatformScope: hasPlatformScope ?? this.hasPlatformScope,
      isAdmin: isAdmin ?? this.isAdmin,
      isSuperadmin: isSuperadmin ?? this.isSuperadmin,
    );
  }

  bool hasPermission(String permission) {
    final normalized = permission.trim();
    if (normalized.isEmpty) return false;
    return permissions.contains(normalized);
  }

  bool hasAnyPermission(Iterable<String> values) {
    for (final value in values) {
      if (hasPermission(value)) return true;
    }
    return false;
  }

  bool hasProductAccess(String product) {
    final normalized = product.trim();
    if (normalized.isEmpty) return false;
    return products.contains(normalized);
  }

  bool hasOperatorScope(
    String operatorId, {
    bool allowUnscoped = true,
  }) {
    final normalized = operatorId.trim();
    if (normalized.isEmpty) return false;
    if (isSuperadmin) return true;
    if (operatorIds.isEmpty) return allowUnscoped;
    return operatorIds.contains(normalized);
  }

  bool hasOfficialAccountScope(String officialAccountId) {
    final normalized = officialAccountId.trim();
    if (normalized.isEmpty) return false;
    if (isSuperadmin || officialAccountWildcard) return true;
    return officialAccountIds.contains(normalized);
  }

  bool can(
    String permission, {
    String? product,
    String? operatorId,
    String? officialAccountId,
  }) {
    if (!hasPermission(permission)) return false;
    if (product != null && !hasProductAccess(product)) return false;
    if (operatorId != null && !hasOperatorScope(operatorId)) return false;
    if (officialAccountId != null &&
        !hasOfficialAccountScope(officialAccountId)) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'roles': roles,
      'operator_ids': operatorIds,
      'permissions': permissions,
      'products': products,
      'official_account_ids': officialAccountIds,
      'official_account_wildcard': officialAccountWildcard,
      'has_platform_scope': hasPlatformScope,
      'is_admin': isAdmin,
      'is_superadmin': isSuperadmin,
    };
  }
}

bool accountPrivilegeSnapshotHasData(AccountPrivilegeSnapshot snapshot) {
  return snapshot.roles.isNotEmpty ||
      snapshot.permissions.isNotEmpty ||
      snapshot.products.isNotEmpty ||
      snapshot.operatorIds.isNotEmpty ||
      snapshot.officialAccountIds.isNotEmpty ||
      snapshot.officialAccountWildcard ||
      snapshot.hasPlatformScope ||
      snapshot.isAdmin ||
      snapshot.isSuperadmin;
}

AccountPrivilegeSnapshot accountPrivilegeSnapshotFromPayload(
  Object? decoded, {
  AccountPrivilegeSnapshot fallback = AccountPrivilegeSnapshot.empty,
}) {
  if (decoded is! Map) {
    return fallback;
  }
  return AccountPrivilegeSnapshot(
    roles: _jsonStringList(decoded['roles'], fallback: fallback.roles),
    operatorIds: _jsonStringList(decoded['operator_ids'],
        fallback: fallback.operatorIds),
    permissions:
        _jsonStringList(decoded['permissions'], fallback: fallback.permissions),
    products: _jsonStringList(decoded['products'], fallback: fallback.products),
    officialAccountIds: _jsonStringList(
      decoded['official_account_ids'],
      fallback: fallback.officialAccountIds,
    ),
    officialAccountWildcard: _jsonBool(
      decoded['official_account_wildcard'],
      fallback: fallback.officialAccountWildcard,
    ),
    hasPlatformScope: _jsonBool(
      decoded['has_platform_scope'],
      fallback: fallback.hasPlatformScope,
    ),
    isAdmin: _jsonBool(decoded['is_admin'], fallback: fallback.isAdmin),
    isSuperadmin: _jsonBool(
      decoded['is_superadmin'],
      fallback: fallback.isSuperadmin,
    ),
  );
}

Future<AccountPrivilegeSnapshot>
    loadAccountPrivilegeSnapshotFromCachedHomeSnapshot({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final raw = await loadCachedHomeSnapshotRaw(
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
  if (raw == null || raw.trim().isEmpty) {
    return AccountPrivilegeSnapshot.empty;
  }
  try {
    final decoded = jsonDecode(raw);
    return accountPrivilegeSnapshotFromPayload(decoded);
  } catch (_) {
    return AccountPrivilegeSnapshot.empty;
  }
}

class _SecureReadResult {
  final String? value;
  final bool failed;
  const _SecureReadResult({
    required this.value,
    required this.failed,
  });
}

Future<AccountPrivilegeSnapshot> loadAccountPrivilegeSnapshot({
  SharedPreferences? sp,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  return _loadAccountPrivilegeSnapshotForScope(
    _currentAccountPrivilegeScope(prefs),
    prefs: prefs,
  );
}

Future<AccountPrivilegeSnapshot> loadAccountPrivilegeSnapshotForBaseUrl(
  String baseUrl, {
  SharedPreferences? sp,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  return _loadAccountPrivilegeSnapshotForScope(
    _accountPrivilegeScopeForBaseUrl(baseUrl),
    prefs: prefs,
  );
}

Future<AccountPrivilegeSnapshot> _loadAccountPrivilegeSnapshotForScope(
  String scope, {
  required SharedPreferences prefs,
}) async {
  final scopedSnapshotKey = _scopedAccountPrivilegeKey(
    _accountPrivilegeSnapshotScopedPrefix,
    scope,
  );
  final scopedRolesKey = _scopedAccountPrivilegeKey(
    _accountRolesScopedSecurePrefix,
    scope,
  );
  final scopedOperatorIdsKey = _scopedAccountPrivilegeKey(
    _accountOperatorIdsScopedSecurePrefix,
    scope,
  );
  final scopedIsSuperadminKey = _scopedAccountPrivilegeKey(
    _accountIsSuperadminScopedSecurePrefix,
    scope,
  );

  if (kIsWeb) {
    try {
      final scopedSnapshotRaw = prefs.getString(scopedSnapshotKey);
      if ((scopedSnapshotRaw ?? '').trim().isNotEmpty) {
        final snapshot = _decodeAccountPrivilegeSnapshot(scopedSnapshotRaw);
        if (!_isEmptyAccountPrivilegeSnapshot(snapshot)) {
          await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
          return snapshot;
        }
      }
      final scopedRoles = prefs.getStringList(scopedRolesKey);
      final scopedOperatorIds = prefs.getStringList(scopedOperatorIdsKey);
      final scopedIsSuperadmin = prefs.getBool(scopedIsSuperadminKey);
      if (scopedRoles != null ||
          scopedOperatorIds != null ||
          scopedIsSuperadmin != null) {
        await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
        return AccountPrivilegeSnapshot(
          roles: _normalizeRoles(scopedRoles ?? const <String>[]),
          isSuperadmin: scopedIsSuperadmin ?? false,
          operatorIds: _normalizeOperatorIds(
            scopedOperatorIds ?? const <String>[],
          ),
        );
      }
    } catch (_) {}

    final legacySnapshot = await _loadLegacyAccountPrivilegeSnapshot(sp: prefs);
    final hadLegacyPhone = await _hasLegacyAccountPhone(sp: prefs);
    if (_isEmptyAccountPrivilegeSnapshot(legacySnapshot)) {
      if (hadLegacyPhone) {
        await _removeLegacyAccountPhone(sp: prefs);
      }
      return AccountPrivilegeSnapshot.empty;
    }

    await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
    if (_isUnknownAccountPrivilegeScope(scope)) {
      final migrated = await saveAccountPrivilegeSnapshot(
        roles: legacySnapshot.roles,
        isSuperadmin: legacySnapshot.isSuperadmin,
        operatorIds: legacySnapshot.operatorIds,
        sp: prefs,
        baseUrlOverride: scope,
      );
      if (!migrated) return AccountPrivilegeSnapshot.empty;
      return legacySnapshot;
    }
    return AccountPrivilegeSnapshot.empty;
  }

  var secureReadFailed = false;
  final secureSnapshotRead = await _secureReadResult(scopedSnapshotKey);
  final secureRolesRead = await _secureReadResult(scopedRolesKey);
  final secureOperatorIdsRead = await _secureReadResult(scopedOperatorIdsKey);
  final secureIsSuperadminRead = await _secureReadResult(scopedIsSuperadminKey);
  secureReadFailed = secureSnapshotRead.failed ||
      secureRolesRead.failed ||
      secureOperatorIdsRead.failed ||
      secureIsSuperadminRead.failed;
  final secureSnapshotRaw = secureSnapshotRead.value;
  final secureRolesRaw = secureRolesRead.value;
  final secureOperatorIdsRaw = secureOperatorIdsRead.value;
  final secureIsSuperadminRaw = secureIsSuperadminRead.value;
  if ((secureSnapshotRaw ?? '').trim().isNotEmpty) {
    final snapshot = _decodeAccountPrivilegeSnapshot(secureSnapshotRaw);
    if (!_isEmptyAccountPrivilegeSnapshot(snapshot)) {
      await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
      return snapshot;
    }
  }
  if (secureRolesRaw != null ||
      secureOperatorIdsRaw != null ||
      secureIsSuperadminRaw != null) {
    await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
    return AccountPrivilegeSnapshot(
      roles: _decodeRoles(secureRolesRaw),
      isSuperadmin: _decodeIsSuperadmin(secureIsSuperadminRaw),
      operatorIds: _decodeOperatorIds(secureOperatorIdsRaw),
    );
  }

  final legacySecureRolesRead =
      await _secureReadResult(_accountRolesLegacySecureKey);
  final legacySecureIsSuperadminRead =
      await _secureReadResult(_accountIsSuperadminLegacySecureKey);
  secureReadFailed = secureReadFailed ||
      legacySecureRolesRead.failed ||
      legacySecureIsSuperadminRead.failed;
  final legacySecureSnapshot = AccountPrivilegeSnapshot(
    roles: _decodeRoles(legacySecureRolesRead.value),
    isSuperadmin: _decodeIsSuperadmin(legacySecureIsSuperadminRead.value),
    operatorIds: const <String>[],
  );
  if (!_isEmptyAccountPrivilegeSnapshot(legacySecureSnapshot)) {
    await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
    if (_isUnknownAccountPrivilegeScope(scope)) {
      final migrated = await saveAccountPrivilegeSnapshot(
        roles: legacySecureSnapshot.roles,
        isSuperadmin: legacySecureSnapshot.isSuperadmin,
        operatorIds: legacySecureSnapshot.operatorIds,
        sp: prefs,
        baseUrlOverride: scope,
      );
      if (!migrated) {
        if (secureReadFailed) {
          return legacySecureSnapshot;
        }
        return AccountPrivilegeSnapshot.empty;
      }
      return legacySecureSnapshot;
    }
    return AccountPrivilegeSnapshot.empty;
  }

  // Fail closed by default: do not trust mutable SharedPreferences role state
  // unless fallback is explicitly enabled or secure storage is unavailable.
  if (!_allowLegacyAccountPrivilegeFallback() && !secureReadFailed) {
    await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
    return AccountPrivilegeSnapshot.empty;
  }

  final legacySnapshot = await _loadLegacyAccountPrivilegeSnapshot(sp: prefs);
  final hadLegacyPhone = await _hasLegacyAccountPhone(sp: prefs);
  if (legacySnapshot.roles.isEmpty && !legacySnapshot.isSuperadmin) {
    if (hadLegacyPhone) {
      await _removeLegacyAccountPhone(sp: prefs);
    }
    return AccountPrivilegeSnapshot.empty;
  }

  await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
  if (_isUnknownAccountPrivilegeScope(scope)) {
    final migrated = await saveAccountPrivilegeSnapshot(
      roles: legacySnapshot.roles,
      isSuperadmin: legacySnapshot.isSuperadmin,
      operatorIds: legacySnapshot.operatorIds,
      sp: prefs,
      baseUrlOverride: scope,
    );
    if (!migrated) {
      if (secureReadFailed) {
        return legacySnapshot;
      }
      return AccountPrivilegeSnapshot.empty;
    }
    return legacySnapshot;
  }
  return AccountPrivilegeSnapshot.empty;
}

Future<bool> saveAccountPrivilegeSnapshot({
  required List<String> roles,
  required bool isSuperadmin,
  List<String> operatorIds = const <String>[],
  List<String> permissions = const <String>[],
  List<String> products = const <String>[],
  List<String> officialAccountIds = const <String>[],
  bool officialAccountWildcard = false,
  bool hasPlatformScope = false,
  bool isAdmin = false,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final snapshot = AccountPrivilegeSnapshot(
    roles: _normalizeRoles(roles),
    operatorIds: _normalizeOperatorIds(operatorIds),
    permissions: _normalizeStringValues(permissions),
    products: _normalizeStringValues(products),
    officialAccountIds: _normalizeStringValues(officialAccountIds),
    officialAccountWildcard: officialAccountWildcard,
    hasPlatformScope: hasPlatformScope,
    isAdmin: isAdmin,
    isSuperadmin: isSuperadmin,
  );
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope =
      _currentAccountPrivilegeScope(prefs, baseUrlOverride: baseUrlOverride);
  final scopedSnapshotKey = _scopedAccountPrivilegeKey(
    _accountPrivilegeSnapshotScopedPrefix,
    scope,
  );
  final scopedRolesKey = _scopedAccountPrivilegeKey(
    _accountRolesScopedSecurePrefix,
    scope,
  );
  final scopedOperatorIdsKey = _scopedAccountPrivilegeKey(
    _accountOperatorIdsScopedSecurePrefix,
    scope,
  );
  final scopedIsSuperadminKey = _scopedAccountPrivilegeKey(
    _accountIsSuperadminScopedSecurePrefix,
    scope,
  );

  if (kIsWeb) {
    try {
      if (_isEmptyAccountPrivilegeSnapshot(snapshot)) {
        await prefs.remove(scopedSnapshotKey);
      } else {
        await prefs.setString(scopedSnapshotKey, jsonEncode(snapshot.toJson()));
      }
      await prefs.remove(scopedRolesKey);
      await prefs.remove(scopedOperatorIdsKey);
      await prefs.remove(scopedIsSuperadminKey);
      await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
      return true;
    } catch (_) {
      return false;
    }
  }

  final snapshotOk = _isEmptyAccountPrivilegeSnapshot(snapshot)
      ? await _secureDelete(scopedSnapshotKey)
      : await _secureWrite(scopedSnapshotKey, jsonEncode(snapshot.toJson()));
  final rolesOk = await _secureDelete(scopedRolesKey);
  final operatorIdsOk = await _secureDelete(scopedOperatorIdsKey);
  final isSuperadminOk = await _secureDelete(scopedIsSuperadminKey);
  await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
  if (!snapshotOk || !rolesOk || !operatorIdsOk || !isSuperadminOk) {
    await clearAccountPrivilegeSnapshot(
      sp: prefs,
      baseUrlOverride: baseUrlOverride,
    );
    return false;
  }
  return true;
}

Future<void> clearAccountPrivilegeSnapshot({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  if ((baseUrlOverride ?? '').trim().isNotEmpty) {
    final scope =
        _currentAccountPrivilegeScope(prefs, baseUrlOverride: baseUrlOverride);
    final scopedSnapshotKey = _scopedAccountPrivilegeKey(
      _accountPrivilegeSnapshotScopedPrefix,
      scope,
    );
    if (!kIsWeb) {
      await _secureDelete(scopedSnapshotKey);
      await _secureDelete(
        _scopedAccountPrivilegeKey(_accountRolesScopedSecurePrefix, scope),
      );
      await _secureDelete(
        _scopedAccountPrivilegeKey(
          _accountOperatorIdsScopedSecurePrefix,
          scope,
        ),
      );
      await _secureDelete(
        _scopedAccountPrivilegeKey(
          _accountIsSuperadminScopedSecurePrefix,
          scope,
        ),
      );
    }
    try {
      await prefs.remove(scopedSnapshotKey);
      await prefs.remove(
        _scopedAccountPrivilegeKey(_accountRolesScopedSecurePrefix, scope),
      );
      await prefs.remove(
        _scopedAccountPrivilegeKey(
          _accountOperatorIdsScopedSecurePrefix,
          scope,
        ),
      );
      await prefs.remove(
        _scopedAccountPrivilegeKey(
          _accountIsSuperadminScopedSecurePrefix,
          scope,
        ),
      );
      await prefs.remove(_accountPhoneLegacyKey);
    } catch (_) {}
    await _clearLegacyAccountPrivilegeGlobalState(sp: prefs);
    return;
  }
  if (!kIsWeb) {
    try {
      final all = await _accountPrivilegeSecureStore.readAll();
      for (final key in all.keys) {
        if (key == _accountRolesLegacySecureKey ||
            key == _accountIsSuperadminLegacySecureKey ||
            key.startsWith(_accountPrivilegeSnapshotScopedPrefix) ||
            key.startsWith(_accountRolesScopedSecurePrefix) ||
            key.startsWith(_accountOperatorIdsScopedSecurePrefix) ||
            key.startsWith(_accountIsSuperadminScopedSecurePrefix)) {
          try {
            await _accountPrivilegeSecureStore.delete(key: key);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
  try {
    final keys = prefs
        .getKeys()
        .where((key) =>
            key == _accountRolesLegacyKey ||
            key == _accountIsSuperadminLegacyKey ||
            key == _accountPhoneLegacyKey ||
            key.startsWith(_accountPrivilegeSnapshotScopedPrefix) ||
            key.startsWith(_accountRolesScopedSecurePrefix) ||
            key.startsWith(_accountOperatorIdsScopedSecurePrefix) ||
            key.startsWith(_accountIsSuperadminScopedSecurePrefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  } catch (_) {}
}

Future<AccountPrivilegeSnapshot> _loadLegacyAccountPrivilegeSnapshot({
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    return AccountPrivilegeSnapshot(
      roles: _normalizeRoles(
        prefs.getStringList(_accountRolesLegacyKey) ?? const <String>[],
      ),
      isSuperadmin: prefs.getBool(_accountIsSuperadminLegacyKey) ?? false,
      operatorIds: const <String>[],
    );
  } catch (_) {
    return AccountPrivilegeSnapshot.empty;
  }
}

List<String> _decodeRoles(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return _normalizeRoles(decoded.map((e) => e.toString()));
  } catch (_) {
    return const <String>[];
  }
}

List<String> _decodeOperatorIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return _normalizeOperatorIds(decoded.map((e) => e.toString()));
  } catch (_) {
    return const <String>[];
  }
}

bool _decodeIsSuperadmin(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

AccountPrivilegeSnapshot _decodeAccountPrivilegeSnapshot(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return AccountPrivilegeSnapshot.empty;
  }
  try {
    return accountPrivilegeSnapshotFromPayload(jsonDecode(raw));
  } catch (_) {
    return AccountPrivilegeSnapshot.empty;
  }
}

List<String> _normalizeRoles(Iterable<String> roles) {
  return _normalizeStringValues(roles);
}

List<String> _normalizeOperatorIds(Iterable<String> operatorIds) {
  return _normalizeStringValues(operatorIds);
}

List<String> _normalizeStringValues(Iterable<String> values) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty || !seen.add(value)) continue;
    normalized.add(value);
  }
  return normalized;
}

List<String> _jsonStringList(
  Object? raw, {
  List<String> fallback = const <String>[],
}) {
  if (raw is! List) {
    return fallback;
  }
  return _normalizeStringValues(raw.map((item) => item.toString()));
}

bool _jsonBool(Object? raw, {bool fallback = false}) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final normalized = (raw ?? '').toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return fallback;
}

bool _isEmptyAccountPrivilegeSnapshot(AccountPrivilegeSnapshot snapshot) {
  return !accountPrivilegeSnapshotHasData(snapshot);
}

String _currentAccountPrivilegeScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) =>
    _accountPrivilegeScopeForBaseUrl(
      (baseUrlOverride ??
              prefs.getString(_accountPrivilegeBaseUrlPrefKey) ??
              '')
          .trim(),
    );

String _accountPrivilegeScopeForBaseUrl(String rawBase) {
  return normalizeSecureApiBaseUrl(rawBase.trim()) ??
      _accountPrivilegeUnknownScope;
}

bool _isUnknownAccountPrivilegeScope(String scope) {
  return scope == _accountPrivilegeUnknownScope;
}

bool _allowLegacyAccountPrivilegeFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_ACCOUNT_PRIVILEGE_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_ACCOUNT_PRIVILEGE_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_ACCOUNT_PRIVILEGE_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_ACCOUNT_PRIVILEGE_FALLBACK',
    defaultValue: true,
  );
}

String _scopedAccountPrivilegeKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<void> _clearLegacyAccountPrivilegeGlobalState({
  required SharedPreferences sp,
}) async {
  if (!kIsWeb) {
    await _secureDelete(_accountRolesLegacySecureKey);
    await _secureDelete(_accountIsSuperadminLegacySecureKey);
  }
  await _removeLegacyAccountPrivilegePrefs(sp: sp);
}

Future<void> _removeLegacyAccountPrivilegePrefs({
  SharedPreferences? sp,
}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(_accountRolesLegacyKey);
    await prefs.remove(_accountIsSuperadminLegacyKey);
    await prefs.remove(_accountPhoneLegacyKey);
  } catch (_) {}
}

Future<void> _removeLegacyAccountPhone({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(_accountPhoneLegacyKey);
  } catch (_) {}
}

Future<bool> _hasLegacyAccountPhone({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    return (prefs.getString(_accountPhoneLegacyKey) ?? '').trim().isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<_SecureReadResult> _secureReadResult(String key) async {
  try {
    final value = await _accountPrivilegeSecureStore.read(key: key);
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
    await _accountPrivilegeSecureStore.write(key: key, value: value);
    final roundTrip =
        (await _accountPrivilegeSecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<bool> _secureDelete(String key) async {
  try {
    await _accountPrivilegeSecureStore.delete(key: key);
    final roundTrip =
        (await _accountPrivilegeSecureStore.read(key: key) ?? '').trim();
    return roundTrip.isEmpty;
  } catch (_) {
    return false;
  }
}
