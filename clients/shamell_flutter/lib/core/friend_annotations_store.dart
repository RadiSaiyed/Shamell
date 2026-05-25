// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const String _legacyFriendAliasesKey = 'friends.aliases';
const String _legacyFriendTagsKey = 'friends.tags';
const String _legacyFriendCloseKey = 'friends.close';
const String _legacySecureFriendAliasesKey = 'friends.aliases.v1';
const String _legacySecureFriendTagsKey = 'friends.tags.v1';
const String _legacySecureFriendCloseKey = 'friends.close.v1';
const String _scopedFriendAliasesKeyPrefix = 'friends.aliases.v2.';
const String _scopedFriendTagsKeyPrefix = 'friends.tags.v2.';
const String _scopedFriendCloseKeyPrefix = 'friends.close.v2.';
const String _friendAnnotationsUnknownScope = 'unknown';
const String _friendAnnotationsBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _friendAnnotationsSecureStore = FlutterSecureStorage(
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

class FriendAnnotationsSnapshot {
  final Map<String, String> aliases;
  final Map<String, String> tags;
  final Set<String> closeFriendIds;

  const FriendAnnotationsSnapshot({
    this.aliases = const <String, String>{},
    this.tags = const <String, String>{},
    this.closeFriendIds = const <String>{},
  });
}

Future<FriendAnnotationsSnapshot> loadFriendAnnotations({
  String? baseUrlOverride,
}) async {
  final aliases = await loadFriendAliases(baseUrlOverride: baseUrlOverride);
  final tags = await loadFriendTags(baseUrlOverride: baseUrlOverride);
  final closeFriendIds =
      await loadCloseFriendIds(baseUrlOverride: baseUrlOverride);
  return FriendAnnotationsSnapshot(
    aliases: aliases,
    tags: tags,
    closeFriendIds: closeFriendIds,
  );
}

Future<Map<String, String>> loadFriendAliases({
  String? baseUrlOverride,
}) async {
  return _loadStringMap(
    scopedKeyPrefix: _scopedFriendAliasesKeyPrefix,
    legacySecureKey: _legacySecureFriendAliasesKey,
    legacyKey: _legacyFriendAliasesKey,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<Map<String, String>> loadFriendTags({
  String? baseUrlOverride,
  http.Client? httpClient,
}) async {
  final local = await _loadStringMap(
    scopedKeyPrefix: _scopedFriendTagsKeyPrefix,
    legacySecureKey: _legacySecureFriendTagsKey,
    legacyKey: _legacyFriendTagsKey,
    baseUrlOverride: baseUrlOverride,
  );
  final server = await _loadServerFriendTags(
    baseUrlOverride: baseUrlOverride,
    httpClient: httpClient,
  );
  if (server.isEmpty) return local;
  final merged = <String, String>{...local, ...server};
  if (!_stringMapEquals(local, merged)) {
    await _saveStringMap(
      scopedKeyPrefix: _scopedFriendTagsKeyPrefix,
      legacySecureKey: _legacySecureFriendTagsKey,
      legacyKey: _legacyFriendTagsKey,
      values: merged,
      baseUrlOverride: baseUrlOverride,
    );
  }
  return merged;
}

Future<void> saveFriendAliases(
  Map<String, String> aliases, {
  String? baseUrlOverride,
}) async {
  await _saveStringMap(
    scopedKeyPrefix: _scopedFriendAliasesKeyPrefix,
    legacySecureKey: _legacySecureFriendAliasesKey,
    legacyKey: _legacyFriendAliasesKey,
    values: aliases,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> saveFriendTags(
  Map<String, String> tags, {
  String? baseUrlOverride,
  http.Client? httpClient,
}) async {
  await _saveStringMap(
    scopedKeyPrefix: _scopedFriendTagsKeyPrefix,
    legacySecureKey: _legacySecureFriendTagsKey,
    legacyKey: _legacyFriendTagsKey,
    values: tags,
    baseUrlOverride: baseUrlOverride,
  );
  await _syncServerFriendTags(
    tags,
    baseUrlOverride: baseUrlOverride,
    httpClient: httpClient,
  );
}

Future<void> saveFriendAnnotationsSnapshot({
  required Map<String, String> aliases,
  required Map<String, String> tags,
  String? baseUrlOverride,
  http.Client? httpClient,
}) async {
  await Future.wait<void>(<Future<void>>[
    saveFriendAliases(aliases, baseUrlOverride: baseUrlOverride),
    saveFriendTags(
      tags,
      baseUrlOverride: baseUrlOverride,
      httpClient: httpClient,
    ),
  ]);
}

Future<void> saveFriendAliasAndTagsForPeer({
  required String peerId,
  required String alias,
  required String tags,
  String? baseUrlOverride,
  http.Client? httpClient,
}) async {
  final normalizedPeerId = peerId.trim();
  if (normalizedPeerId.isEmpty) return;
  final nextAlias = alias.trim();
  final nextTags = tags.trim();
  final results = await Future.wait<Object>(<Future<Object>>[
    loadFriendAliases(baseUrlOverride: baseUrlOverride),
    loadFriendTags(
      baseUrlOverride: baseUrlOverride,
      httpClient: httpClient,
    ),
  ]);
  final aliases = Map<String, String>.from(results[0] as Map<String, String>);
  final tagsByPeer =
      Map<String, String>.from(results[1] as Map<String, String>);
  _applyFriendAnnotationValue(aliases, normalizedPeerId, nextAlias);
  _applyFriendAnnotationValue(tagsByPeer, normalizedPeerId, nextTags);
  await saveFriendAnnotationsSnapshot(
    aliases: aliases,
    tags: tagsByPeer,
    baseUrlOverride: baseUrlOverride,
    httpClient: httpClient,
  );
  if (nextTags.isEmpty) {
    await _syncServerFriendTagsForPeer(
      normalizedPeerId,
      const <String>[],
      baseUrlOverride: baseUrlOverride,
      httpClient: httpClient,
    );
  }
}

Future<Set<String>> loadCloseFriendIds({
  String? baseUrlOverride,
}) async {
  return _loadStringSet(
    scopedKeyPrefix: _scopedFriendCloseKeyPrefix,
    legacySecureKey: _legacySecureFriendCloseKey,
    legacyKey: _legacyFriendCloseKey,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> saveCloseFriendIds(
  Iterable<String> ids, {
  String? baseUrlOverride,
}) async {
  await _saveStringSet(
    scopedKeyPrefix: _scopedFriendCloseKeyPrefix,
    legacySecureKey: _legacySecureFriendCloseKey,
    legacyKey: _legacyFriendCloseKey,
    values: ids,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> saveCloseFriendForPeer({
  required String peerId,
  required bool isClose,
  String? baseUrlOverride,
}) async {
  final normalizedPeerId = peerId.trim();
  if (normalizedPeerId.isEmpty) return;
  final closeFriendIds = <String>{
    ...await loadCloseFriendIds(baseUrlOverride: baseUrlOverride),
  };
  if (isClose) {
    closeFriendIds.add(normalizedPeerId);
  } else {
    closeFriendIds.remove(normalizedPeerId);
  }
  await saveCloseFriendIds(
    closeFriendIds,
    baseUrlOverride: baseUrlOverride,
  );
}

Future<void> clearFriendAnnotations() async {
  final prefs = await SharedPreferences.getInstance();
  if (_useSecureStore()) {
    await _clearAllFriendAnnotationSecureKeys();
  }
  await _clearAllFriendAnnotationPrefs(prefs);
}

bool _useSecureStore() => !kIsWeb;

bool _allowLegacyFriendAnnotationsFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_FRIEND_ANNOTATIONS_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_FRIEND_ANNOTATIONS_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_FRIEND_ANNOTATIONS_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_FRIEND_ANNOTATIONS_FALLBACK',
    defaultValue: true,
  );
}

Future<Map<String, String>> _loadStringMap({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  String? baseUrlOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final scope = _currentFriendAnnotationsScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedFriendAnnotationKey(scopedKeyPrefix, scope);
  if (_useSecureStore()) {
    var secureReadFailed = false;
    final scopedSecureRead = await _secureReadValue(scopedKey);
    secureReadFailed = scopedSecureRead.failed;
    final scopedSecure = (scopedSecureRead.value ?? '').trim();
    if (scopedSecure.isNotEmpty) {
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return _decodeStringMap(scopedSecure);
    }

    final legacySecureRead = await _secureReadValue(legacySecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = (legacySecureRead.value ?? '').trim();
    if (legacySecure.isNotEmpty) {
      final decodedLegacySecure = _decodeStringMap(legacySecure);
      if (_isUnknownFriendAnnotationsScope(scope) &&
          decodedLegacySecure.isNotEmpty) {
        final migrated = await _secureWriteValue(
          scopedKey,
          jsonEncode(decodedLegacySecure),
        );
        if (migrated) {
          await _clearLegacyFriendAnnotationValue(
            legacyKey: legacyKey,
            legacySecureKey: legacySecureKey,
            prefs: prefs,
          );
          return decodedLegacySecure;
        }
        await _secureDeleteValue(scopedKey);
        if (secureReadFailed) {
          return decodedLegacySecure;
        }
      }
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return const <String, String>{};
    }

    // Fail closed by default: do not trust mutable SharedPreferences values
    // unless fallback is explicitly enabled or secure storage is unavailable.
    if (!_allowLegacyFriendAnnotationsFallback() && !secureReadFailed) {
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return const <String, String>{};
    }

    final legacy = (prefs.getString(legacyKey) ?? '').trim();
    if (legacy.isEmpty) return const <String, String>{};
    final decoded = _decodeStringMap(legacy);
    if (decoded.isEmpty) {
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return const <String, String>{};
    }
    if (_isUnknownFriendAnnotationsScope(scope)) {
      final migrated = await _secureWriteValue(
        scopedKey,
        jsonEncode(decoded),
      );
      if (migrated) {
        await _clearLegacyFriendAnnotationValue(
          legacyKey: legacyKey,
          legacySecureKey: legacySecureKey,
          prefs: prefs,
        );
        return decoded;
      }
      await _secureDeleteValue(scopedKey);
      if (secureReadFailed) {
        return decoded;
      }
    }
    await _clearLegacyFriendAnnotationValue(
      legacyKey: legacyKey,
      legacySecureKey: legacySecureKey,
      prefs: prefs,
    );
    return const <String, String>{};
  }

  final legacy = (prefs.getString(legacyKey) ?? '').trim();
  if (legacy.isEmpty) return const <String, String>{};
  final decoded = _decodeStringMap(legacy);
  await _clearLegacyFriendAnnotationValue(
    legacyKey: legacyKey,
    legacySecureKey: legacySecureKey,
    prefs: prefs,
  );
  if (decoded.isEmpty) return const <String, String>{};

  if (_isUnknownFriendAnnotationsScope(scope)) {
    try {
      await prefs.setString(scopedKey, jsonEncode(decoded));
      return decoded;
    } catch (_) {
      return const <String, String>{};
    }
  }
  return const <String, String>{};
}

Future<void> _saveStringMap({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  required Map<String, String> values,
  String? baseUrlOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = _scopedFriendAnnotationKey(
    scopedKeyPrefix,
    _currentFriendAnnotationsScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    ),
  );
  final normalized = _normalizeStringMap(values);
  if (_useSecureStore()) {
    try {
      if (normalized.isEmpty) {
        await _friendAnnotationsSecureStore.delete(key: scopedKey);
      } else {
        await _friendAnnotationsSecureStore.write(
          key: scopedKey,
          value: jsonEncode(normalized),
        );
      }
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return;
    } catch (_) {
      return;
    }
  }

  if (normalized.isEmpty) {
    await prefs.remove(scopedKey);
    await _removeLegacyKey(legacyKey, prefs: prefs);
    return;
  }
  await prefs.setString(scopedKey, jsonEncode(normalized));
  await _removeLegacyKey(legacyKey, prefs: prefs);
}

Future<Map<String, String>> _loadServerFriendTags({
  String? baseUrlOverride,
  http.Client? httpClient,
}) async {
  final baseUrl = normalizeSecureApiBaseUrl((baseUrlOverride ?? '').trim());
  if (baseUrl == null || baseUrl.isEmpty) return const <String, String>{};
  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    final uri = Uri.parse('$baseUrl/me/friends/tags');
    final resp = await client
        .get(uri, headers: await shamellSessionHeadersForBaseUrl(baseUrl))
        .timeout(const Duration(seconds: 4));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return const <String, String>{};
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map || decoded['items'] is! List) {
      return const <String, String>{};
    }
    final out = <String, String>{};
    for (final item in decoded['items'] as List) {
      if (item is! Map) continue;
      final friendId = (item['friend_account_id'] ?? '').toString().trim();
      if (!_isServerFriendAccountId(friendId)) continue;
      final tagsRaw = item['tags'];
      if (tagsRaw is! List) continue;
      final tags = tagsRaw
          .map((e) => _serverSafeFriendTag((e ?? '').toString()))
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
      if (tags.isNotEmpty) {
        out[friendId] = tags.join(', ');
      }
    }
    return out;
  } catch (_) {
    return const <String, String>{};
  } finally {
    if (ownsClient) client.close();
  }
}

Future<void> _syncServerFriendTags(
  Map<String, String> tags, {
  String? baseUrlOverride,
  http.Client? httpClient,
}) async {
  final baseUrl = normalizeSecureApiBaseUrl((baseUrlOverride ?? '').trim());
  if (baseUrl == null || baseUrl.isEmpty) return;
  final serverEntries = tags.entries
      .where((entry) => _isServerFriendAccountId(entry.key.trim()))
      .toList(growable: false);
  if (serverEntries.isEmpty) return;
  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    final headers = await shamellSessionHeadersForBaseUrl(baseUrl, json: true);
    for (final entry in serverEntries) {
      final friendId = entry.key.trim();
      final payloadTags = _splitServerSafeFriendTags(entry.value);
      await _postServerFriendTags(
        client: client,
        baseUrl: baseUrl,
        headers: headers,
        friendAccountId: friendId,
        tags: payloadTags,
      );
    }
  } catch (_) {
  } finally {
    if (ownsClient) client.close();
  }
}

Future<void> _syncServerFriendTagsForPeer(
  String peerId,
  List<String> tags, {
  String? baseUrlOverride,
  http.Client? httpClient,
}) async {
  final friendId = peerId.trim();
  if (!_isServerFriendAccountId(friendId)) return;
  final baseUrl = normalizeSecureApiBaseUrl((baseUrlOverride ?? '').trim());
  if (baseUrl == null || baseUrl.isEmpty) return;
  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    await _postServerFriendTags(
      client: client,
      baseUrl: baseUrl,
      headers: await shamellSessionHeadersForBaseUrl(baseUrl, json: true),
      friendAccountId: friendId,
      tags: tags,
    );
  } catch (_) {
  } finally {
    if (ownsClient) client.close();
  }
}

Future<void> _postServerFriendTags({
  required http.Client client,
  required String baseUrl,
  required Map<String, String> headers,
  required String friendAccountId,
  required List<String> tags,
}) async {
  final encodedId = Uri.encodeComponent(friendAccountId.trim());
  final uri = Uri.parse('$baseUrl/me/friends/$encodedId/tags');
  await client
      .post(
        uri,
        headers: headers,
        body: jsonEncode(<String, Object?>{'tags': tags}),
      )
      .timeout(const Duration(seconds: 4));
}

List<String> _splitServerSafeFriendTags(String raw) {
  final out = <String>{};
  for (final part in raw.split(RegExp(r'[,،;]+'))) {
    final normalized = _serverSafeFriendTag(part);
    if (normalized != null) out.add(normalized);
  }
  final list = out.toList()..sort();
  return list;
}

String? _serverSafeFriendTag(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  value = value.replaceAll(RegExp(r'[^a-z0-9_.-]+'), '_');
  value = value.replaceAll(RegExp(r'_+'), '_');
  value = value.replaceAll(RegExp(r'^[_\-.]+|[_\-.]+$'), '');
  if (value.isEmpty) return null;
  if (value.length > 64) {
    value = value.substring(0, 64);
    value = value.replaceAll(RegExp(r'[_\-.]+$'), '');
  }
  if (value.isEmpty) return null;
  if (!RegExp(r'^[a-z0-9][a-z0-9_.-]{0,63}$').hasMatch(value)) {
    return null;
  }
  return value;
}

bool _isServerFriendAccountId(String raw) {
  return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(raw.trim());
}

bool _stringMapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

Future<Set<String>> _loadStringSet({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  String? baseUrlOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final scope = _currentFriendAnnotationsScope(
    prefs,
    baseUrlOverride: baseUrlOverride,
  );
  final scopedKey = _scopedFriendAnnotationKey(scopedKeyPrefix, scope);
  if (_useSecureStore()) {
    var secureReadFailed = false;
    final scopedSecureRead = await _secureReadValue(scopedKey);
    secureReadFailed = scopedSecureRead.failed;
    final scopedSecure = (scopedSecureRead.value ?? '').trim();
    if (scopedSecure.isNotEmpty) {
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return _decodeStringSet(scopedSecure);
    }

    final legacySecureRead = await _secureReadValue(legacySecureKey);
    secureReadFailed = secureReadFailed || legacySecureRead.failed;
    final legacySecure = (legacySecureRead.value ?? '').trim();
    if (legacySecure.isNotEmpty) {
      final decodedLegacySecure = _decodeStringSet(legacySecure);
      if (_isUnknownFriendAnnotationsScope(scope) &&
          decodedLegacySecure.isNotEmpty) {
        final migrated = await _secureWriteValue(
          scopedKey,
          jsonEncode(decodedLegacySecure.toList(growable: false)),
        );
        if (migrated) {
          await _clearLegacyFriendAnnotationValue(
            legacyKey: legacyKey,
            legacySecureKey: legacySecureKey,
            prefs: prefs,
          );
          return decodedLegacySecure;
        }
        await _secureDeleteValue(scopedKey);
        if (secureReadFailed) {
          return decodedLegacySecure;
        }
      }
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return const <String>{};
    }

    // Fail closed by default: do not trust mutable SharedPreferences values
    // unless fallback is explicitly enabled or secure storage is unavailable.
    if (!_allowLegacyFriendAnnotationsFallback() && !secureReadFailed) {
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return const <String>{};
    }

    final legacy = (prefs.getString(legacyKey) ?? '').trim();
    if (legacy.isEmpty) return const <String>{};
    final decoded = _decodeStringSet(legacy);
    if (decoded.isEmpty) {
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return const <String>{};
    }
    if (_isUnknownFriendAnnotationsScope(scope)) {
      final migrated = await _secureWriteValue(
        scopedKey,
        jsonEncode(decoded.toList(growable: false)),
      );
      if (migrated) {
        await _clearLegacyFriendAnnotationValue(
          legacyKey: legacyKey,
          legacySecureKey: legacySecureKey,
          prefs: prefs,
        );
        return decoded;
      }
      await _secureDeleteValue(scopedKey);
      if (secureReadFailed) {
        return decoded;
      }
    }
    await _clearLegacyFriendAnnotationValue(
      legacyKey: legacyKey,
      legacySecureKey: legacySecureKey,
      prefs: prefs,
    );
    return const <String>{};
  }

  final legacy = (prefs.getString(legacyKey) ?? '').trim();
  if (legacy.isEmpty) return const <String>{};
  final decoded = _decodeStringSet(legacy);
  await _clearLegacyFriendAnnotationValue(
    legacyKey: legacyKey,
    legacySecureKey: legacySecureKey,
    prefs: prefs,
  );
  if (decoded.isEmpty) return const <String>{};

  if (_isUnknownFriendAnnotationsScope(scope)) {
    await prefs.setString(
      scopedKey,
      jsonEncode(decoded.toList(growable: false)),
    );
    return decoded;
  }
  return const <String>{};
}

Future<void> _saveStringSet({
  required String scopedKeyPrefix,
  required String legacySecureKey,
  required String legacyKey,
  required Iterable<String> values,
  String? baseUrlOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = _scopedFriendAnnotationKey(
    scopedKeyPrefix,
    _currentFriendAnnotationsScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    ),
  );
  final normalized = _normalizeStringSet(values);
  if (_useSecureStore()) {
    try {
      if (normalized.isEmpty) {
        await _friendAnnotationsSecureStore.delete(key: scopedKey);
      } else {
        await _friendAnnotationsSecureStore.write(
          key: scopedKey,
          value: jsonEncode(normalized.toList(growable: false)),
        );
      }
      await _clearLegacyFriendAnnotationValue(
        legacyKey: legacyKey,
        legacySecureKey: legacySecureKey,
        prefs: prefs,
      );
      return;
    } catch (_) {
      return;
    }
  }

  if (normalized.isEmpty) {
    await prefs.remove(scopedKey);
    await _removeLegacyKey(legacyKey, prefs: prefs);
    return;
  }
  await prefs.setString(
    scopedKey,
    jsonEncode(<String, bool>{for (final id in normalized) id: true}),
  );
  await _removeLegacyKey(legacyKey, prefs: prefs);
}

Map<String, String> _decodeStringMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return _normalizeStringMap(decoded);
    }
  } catch (_) {}
  return const <String, String>{};
}

void _applyFriendAnnotationValue(
  Map<String, String> values,
  String peerId,
  String nextValue,
) {
  if (nextValue.isEmpty) {
    values.remove(peerId);
  } else {
    values[peerId] = nextValue;
  }
}

Map<String, String> _normalizeStringMap(Map<dynamic, dynamic> values) {
  final out = <String, String>{};
  values.forEach((k, v) {
    final key = (k ?? '').toString().trim();
    final value = (v ?? '').toString().trim();
    if (key.isEmpty || value.isEmpty) return;
    out[key] = value;
  });
  return out;
}

Set<String> _decodeStringSet(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return _normalizeStringSet(decoded);
    }
    if (decoded is Map) {
      final out = <String>{};
      decoded.forEach((k, v) {
        final key = (k ?? '').toString().trim();
        final boolVal = v is bool
            ? v
            : (v != null && v.toString().trim().toLowerCase() == 'true');
        if (key.isEmpty || !boolVal) return;
        out.add(key);
      });
      return out;
    }
  } catch (_) {}
  return const <String>{};
}

Set<String> _normalizeStringSet(Iterable<dynamic> values) {
  final out = <String>{};
  for (final value in values) {
    final normalized = (value ?? '').toString().trim();
    if (normalized.isEmpty) continue;
    out.add(normalized);
  }
  return out;
}

Future<_SecureReadResult> _secureReadValue(String key) async {
  if (!_useSecureStore()) {
    return const _SecureReadResult(value: null, failed: false);
  }
  try {
    final value = await _friendAnnotationsSecureStore.read(key: key);
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return const _SecureReadResult(value: null, failed: false);
    }
    return _SecureReadResult(value: value, failed: false);
  } catch (_) {
    return const _SecureReadResult(value: null, failed: true);
  }
}

Future<bool> _secureWriteValue(String key, String value) async {
  if (!_useSecureStore()) return false;
  try {
    await _friendAnnotationsSecureStore.write(key: key, value: value);
    final roundTrip =
        (await _friendAnnotationsSecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<void> _secureDeleteValue(String key) async {
  if (!_useSecureStore()) return;
  try {
    await _friendAnnotationsSecureStore.delete(key: key);
  } catch (_) {}
}

Future<void> _removeLegacyKey(
  String key, {
  SharedPreferences? prefs,
}) async {
  try {
    final instance = prefs ?? await SharedPreferences.getInstance();
    await instance.remove(key);
  } catch (_) {}
}

String _currentFriendAnnotationsScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final overridden = (baseUrlOverride ?? '').trim();
  if (overridden.isNotEmpty) {
    return normalizeSecureApiBaseUrl(overridden) ??
        _friendAnnotationsUnknownScope;
  }
  final rawBase =
      (prefs.getString(_friendAnnotationsBaseUrlPrefKey) ?? '').trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _friendAnnotationsUnknownScope;
}

bool _isUnknownFriendAnnotationsScope(String scope) {
  return scope == _friendAnnotationsUnknownScope;
}

String _scopedFriendAnnotationKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<void> _clearLegacyFriendAnnotationValue({
  required String legacyKey,
  required String legacySecureKey,
  required SharedPreferences prefs,
}) async {
  try {
    await _friendAnnotationsSecureStore.delete(key: legacySecureKey);
  } catch (_) {}
  await _removeLegacyKey(legacyKey, prefs: prefs);
}

Future<void> _clearAllFriendAnnotationSecureKeys() async {
  try {
    final all = await _friendAnnotationsSecureStore.readAll();
    for (final key in all.keys) {
      if (key == _legacySecureFriendAliasesKey ||
          key == _legacySecureFriendTagsKey ||
          key == _legacySecureFriendCloseKey ||
          key.startsWith(_scopedFriendAliasesKeyPrefix) ||
          key.startsWith(_scopedFriendTagsKeyPrefix) ||
          key.startsWith(_scopedFriendCloseKeyPrefix)) {
        try {
          await _friendAnnotationsSecureStore.delete(key: key);
        } catch (_) {}
      }
    }
  } catch (_) {
    try {
      await _friendAnnotationsSecureStore.delete(
          key: _legacySecureFriendAliasesKey);
    } catch (_) {}
    try {
      await _friendAnnotationsSecureStore.delete(
          key: _legacySecureFriendTagsKey);
    } catch (_) {}
    try {
      await _friendAnnotationsSecureStore.delete(
          key: _legacySecureFriendCloseKey);
    } catch (_) {}
  }
}

Future<void> _clearAllFriendAnnotationPrefs(SharedPreferences prefs) async {
  try {
    final keys = prefs
        .getKeys()
        .where((key) =>
            key == _legacyFriendAliasesKey ||
            key == _legacyFriendTagsKey ||
            key == _legacyFriendCloseKey ||
            key.startsWith(_scopedFriendAliasesKeyPrefix) ||
            key.startsWith(_scopedFriendTagsKeyPrefix) ||
            key.startsWith(_scopedFriendCloseKeyPrefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  } catch (_) {}
}
