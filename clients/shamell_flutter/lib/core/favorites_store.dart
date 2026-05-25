// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const String _favoritesLegacyKey = 'favorites_items';
const String _favoritesLegacySecureKey = 'favorites.items.v1';
const String _favoritesScopedKeyPrefix = 'favorites.items.v2.';
const String _favoritesUnknownScope = 'unknown';
const String _favoritesBaseUrlPrefKey = 'base_url';

const FlutterSecureStorage _favoritesSecureStore = FlutterSecureStorage(
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

Future<List<Map<String, dynamic>>> loadFavoriteItems({
  String? baseUrlOverride,
}) async {
  final raw = await loadFavoriteItemsRaw(baseUrlOverride: baseUrlOverride);
  var local = const <Map<String, dynamic>>[];
  var localCanonicalized = false;
  try {
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final decodedItems = decoded
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
        local = decodedItems
            .map(_canonicalFavoriteItem)
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        localCanonicalized = !_favoriteItemListsEqual(decodedItems, local);
      }
    }
  } catch (_) {
    local = const <Map<String, dynamic>>[];
  }
  final server = await _loadServerFavoriteItems(
    baseUrlOverride: baseUrlOverride,
  );
  if (server.isEmpty) {
    if (localCanonicalized) {
      await saveFavoriteItems(local, baseUrlOverride: baseUrlOverride);
    }
    return local;
  }
  final merged = _mergeFavoriteItems(server, local);
  if (localCanonicalized || !_favoriteItemListsEqual(local, merged)) {
    await saveFavoriteItems(merged, baseUrlOverride: baseUrlOverride);
  }
  return merged;
}

Future<String?> loadFavoriteItemsRaw({String? baseUrlOverride}) async {
  final sp = await SharedPreferences.getInstance();
  final scope = _currentFavoritesScope(sp, baseUrlOverride: baseUrlOverride);
  final scopedKey = _scopedFavoritesKey(scope);
  if (kIsWeb) {
    final scoped = (sp.getString(scopedKey) ?? '').trim();
    if (scoped.isNotEmpty) {
      await _removeLegacyFavorites(sp: sp);
      return scoped;
    }

    final legacy = (sp.getString(_favoritesLegacyKey) ?? '').trim();
    if (legacy.isEmpty) return null;
    await _removeLegacyFavorites(sp: sp);
    if (_isUnknownFavoritesScope(scope)) {
      await sp.setString(scopedKey, legacy);
      return legacy;
    }
    return null;
  }

  var secureReadFailed = false;
  final secureRead = await _secureReadResult(scopedKey);
  secureReadFailed = secureRead.failed;
  final secure = secureRead.value;
  if (secure != null) {
    await _clearLegacyFavorites(sp: sp);
    return secure;
  }

  final legacySecureRead = await _secureReadResult(_favoritesLegacySecureKey);
  secureReadFailed = secureReadFailed || legacySecureRead.failed;
  final legacySecure = legacySecureRead.value;
  if (legacySecure != null) {
    if (_isUnknownFavoritesScope(scope)) {
      final migrated = await _secureWrite(scopedKey, legacySecure);
      if (migrated) {
        await _clearLegacyFavorites(sp: sp);
        return legacySecure;
      }
      await _secureDelete(scopedKey);
      if (secureReadFailed) {
        return legacySecure;
      }
    }
    await _clearLegacyFavorites(sp: sp);
    return null;
  }

  // Fail closed by default: do not trust mutable SharedPreferences values
  // unless fallback is explicitly enabled or secure storage is unavailable.
  if (!_allowLegacyFavoritesFallback() && !secureReadFailed) {
    await _clearLegacyFavorites(sp: sp);
    return null;
  }

  final legacy = (sp.getString(_favoritesLegacyKey) ?? '').trim();
  if (legacy.isEmpty) return null;
  if (_isUnknownFavoritesScope(scope)) {
    final migrated = await _secureWrite(scopedKey, legacy);
    if (migrated) {
      await _clearLegacyFavorites(sp: sp);
      return legacy;
    }
    await _secureDelete(scopedKey);
    if (secureReadFailed) {
      return legacy;
    }
    await _clearLegacyFavorites(sp: sp);
    return null;
  }
  await _clearLegacyFavorites(sp: sp);
  return null;
}

Future<void> saveFavoriteItems(
  List<Map<String, dynamic>> items, {
  String? baseUrlOverride,
}) async {
  final cleaned = items
      .map(_canonicalFavoriteItem)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (cleaned.isEmpty) {
    await clearFavoriteItems(baseUrlOverride: baseUrlOverride);
    return;
  }

  final raw = jsonEncode(cleaned);
  if (kIsWeb) {
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedFavoritesKey(
      _currentFavoritesScope(sp, baseUrlOverride: baseUrlOverride),
    );
    await sp.setString(scopedKey, raw);
    await _removeLegacyFavorites(sp: sp);
    return;
  }

  final sp = await SharedPreferences.getInstance();
  final scopedKey = _scopedFavoritesKey(
    _currentFavoritesScope(sp, baseUrlOverride: baseUrlOverride),
  );
  final wrote = await _secureWrite(scopedKey, raw);
  await _clearLegacyFavorites(sp: sp);
  if (!wrote) {
    await _secureDelete(scopedKey);
  }
}

Future<void> appendFavoriteItem(
  Map<String, dynamic> item, {
  String? baseUrlOverride,
}) async {
  final entry = _canonicalFavoriteItem(item);
  if (entry.isEmpty) return;
  _ensureServerFavoriteId(entry);
  final items =
      (await loadFavoriteItems(baseUrlOverride: baseUrlOverride)).toList();
  items.insert(0, entry);
  await saveFavoriteItems(
    items,
    baseUrlOverride: baseUrlOverride,
  );
  await _upsertServerFavoriteItem(entry, baseUrlOverride: baseUrlOverride);
}

Future<void> insertFavoriteItemAt(
  int index,
  Map<String, dynamic> item, {
  String? baseUrlOverride,
}) async {
  final entry = _canonicalFavoriteItem(item);
  if (entry.isEmpty) return;
  _ensureServerFavoriteId(entry);
  final items =
      (await loadFavoriteItems(baseUrlOverride: baseUrlOverride)).toList();
  final normalizedIndex =
      index < 0 ? 0 : (index > items.length ? items.length : index);
  items.insert(normalizedIndex, entry);
  await saveFavoriteItems(
    items,
    baseUrlOverride: baseUrlOverride,
  );
  await _upsertServerFavoriteItem(entry, baseUrlOverride: baseUrlOverride);
}

Future<void> removeFavoriteItemEntry(
  Map<String, dynamic> item, {
  String? baseUrlOverride,
}) async {
  final target = _canonicalFavoriteItem(item);
  if (target.isEmpty) return;
  final targetKey = _favoriteItemIdentity(target);
  final items =
      (await loadFavoriteItems(baseUrlOverride: baseUrlOverride)).toList();
  final index = items.indexWhere(
    (entry) =>
        mapEquals(Map<String, dynamic>.from(entry), target) ||
        _favoriteItemIdentity(Map<String, dynamic>.from(entry)) == targetKey,
  );
  if (index < 0) return;
  final removed = Map<String, dynamic>.from(items.removeAt(index));
  await saveFavoriteItems(
    items,
    baseUrlOverride: baseUrlOverride,
  );
  await _deleteServerFavoriteItem(removed, baseUrlOverride: baseUrlOverride);
}

Future<void> removeFavoriteItemsByMessageId(
  String messageId, {
  String? baseUrlOverride,
}) async {
  final normalizedMessageId = messageId.trim();
  if (normalizedMessageId.isEmpty) return;
  final decoded = await loadFavoriteItems(baseUrlOverride: baseUrlOverride);
  if (decoded.isEmpty) return;
  final kept = <Map<String, dynamic>>[];
  final removed = <Map<String, dynamic>>[];
  var changed = false;
  for (final entry in decoded) {
    final item = Map<String, dynamic>.from(entry);
    final currentMessageId = (item['msgId'] ?? '').toString().trim();
    if (currentMessageId == normalizedMessageId) {
      changed = true;
      removed.add(item);
      continue;
    }
    kept.add(item);
  }
  if (!changed) return;
  await saveFavoriteItems(
    kept,
    baseUrlOverride: baseUrlOverride,
  );
  for (final item in removed) {
    await _deleteServerFavoriteItem(item, baseUrlOverride: baseUrlOverride);
  }
}

Future<void> clearFavoriteItems({String? baseUrlOverride}) async {
  final serverItems = await _loadServerFavoriteItems(
    baseUrlOverride: baseUrlOverride,
  );
  for (final item in serverItems) {
    await _deleteServerFavoriteItem(item, baseUrlOverride: baseUrlOverride);
  }
  final sp = await SharedPreferences.getInstance();
  final overriddenScope = (baseUrlOverride ?? '').trim();
  if (overriddenScope.isNotEmpty) {
    final scopedKey = _scopedFavoritesKey(
      _currentFavoritesScope(sp, baseUrlOverride: baseUrlOverride),
    );
    if (kIsWeb) {
      await sp.remove(scopedKey);
      await _removeLegacyFavorites(sp: sp);
      return;
    }
    await _secureDelete(scopedKey);
    await _clearLegacyFavorites(sp: sp);
    return;
  }
  if (!kIsWeb) {
    await _clearAllFavoritesSecureKeys();
  }
  await _clearAllFavoritesPrefs(sp: sp);
}

Future<int> favoriteItemsStorageBytes({String? baseUrlOverride}) async {
  final raw = await loadFavoriteItemsRaw(baseUrlOverride: baseUrlOverride);
  return utf8.encode(raw ?? '').length;
}

Future<String?> _favoritesApiBaseUrl({String? baseUrlOverride}) async {
  final overridden = normalizeSecureApiBaseUrl((baseUrlOverride ?? '').trim());
  if (overridden != null && overridden.isNotEmpty) return overridden;
  try {
    final sp = await SharedPreferences.getInstance();
    final stored = normalizeSecureApiBaseUrl(
        (sp.getString(_favoritesBaseUrlPrefKey) ?? '').trim());
    if (stored != null && stored.isNotEmpty) return stored;
  } catch (_) {}
  return null;
}

Future<List<Map<String, dynamic>>> _loadServerFavoriteItems({
  String? baseUrlOverride,
}) async {
  final baseUrl = await _favoritesApiBaseUrl(baseUrlOverride: baseUrlOverride);
  if (baseUrl == null || baseUrl.isEmpty) return const <Map<String, dynamic>>[];
  try {
    final uri = Uri.parse('$baseUrl/me/favorites').replace(
      queryParameters: const <String, String>{'limit': '200'},
    );
    final resp = await http
        .get(uri, headers: await shamellSessionHeadersForBaseUrl(baseUrl))
        .timeout(const Duration(seconds: 4));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return const <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map || decoded['items'] is! List) {
      return const <Map<String, dynamic>>[];
    }
    return (decoded['items'] as List)
        .whereType<Map>()
        .map(_serverFavoriteItemToLocal)
        .map(_canonicalFavoriteItem)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
}

Future<void> _upsertServerFavoriteItem(
  Map<String, dynamic> item, {
  String? baseUrlOverride,
}) async {
  final baseUrl = await _favoritesApiBaseUrl(baseUrlOverride: baseUrlOverride);
  if (baseUrl == null || baseUrl.isEmpty) return;
  final entry = Map<String, dynamic>.from(item);
  _ensureServerFavoriteId(entry);
  try {
    final body = <String, Object?>{
      'id': entry['id'],
      'kind': _favoriteItemServerKind(entry),
      'title': _favoriteItemTitle(entry),
      'text': (entry['text'] ?? '').toString(),
      'payload': _favoriteItemPayload(entry),
      'source_module': _favoriteItemSourceModule(entry),
      'source_id': _favoriteItemSourceId(entry),
    }..removeWhere((_, value) => value == null);
    await http
        .post(
          Uri.parse('$baseUrl/me/favorites'),
          headers: await shamellSessionHeadersForBaseUrl(baseUrl, json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 4));
  } catch (_) {}
}

Future<void> _deleteServerFavoriteItem(
  Map<String, dynamic> item, {
  String? baseUrlOverride,
}) async {
  final id = (item['id'] ?? '').toString().trim().toLowerCase();
  if (!_isServerFavoriteId(id)) return;
  final baseUrl = await _favoritesApiBaseUrl(baseUrlOverride: baseUrlOverride);
  if (baseUrl == null || baseUrl.isEmpty) return;
  try {
    await http
        .delete(
          Uri.parse('$baseUrl/me/favorites/${Uri.encodeComponent(id)}'),
          headers: await shamellSessionHeadersForBaseUrl(baseUrl),
        )
        .timeout(const Duration(seconds: 4));
  } catch (_) {}
}

Map<String, dynamic> _serverFavoriteItemToLocal(Map raw) {
  final payloadRaw = raw['payload'];
  final out = <String, dynamic>{};
  if (payloadRaw is Map) {
    for (final entry in payloadRaw.entries) {
      final key = entry.key.toString();
      if (key.trim().isEmpty) continue;
      out[key] = entry.value;
    }
  }
  final id = (raw['id'] ?? '').toString().trim().toLowerCase();
  if (_isServerFavoriteId(id)) out['id'] = id;
  final kind =
      _normalizeFavoriteKind((raw['kind'] ?? out['kind'] ?? '').toString());
  if (kind.isNotEmpty) out['kind'] = kind;
  final title = (raw['title'] ?? '').toString().trim();
  if (title.isNotEmpty) out['title'] = title;
  final text = (raw['text'] ?? '').toString();
  if (text.trim().isNotEmpty) out['text'] = text;
  final ts = (out['ts'] ??
          raw['updated_at'] ??
          raw['created_at'] ??
          DateTime.now().toIso8601String())
      .toString();
  out['ts'] = ts;
  final sourceModule = (raw['source_module'] ?? '').toString().trim();
  if (sourceModule.isNotEmpty) out['sourceModule'] = sourceModule;
  final sourceId = (raw['source_id'] ?? '').toString().trim();
  if (sourceId.isNotEmpty) out['sourceId'] = sourceId;
  return out;
}

List<Map<String, dynamic>> _mergeFavoriteItems(
  List<Map<String, dynamic>> primary,
  List<Map<String, dynamic>> secondary,
) {
  final out = <Map<String, dynamic>>[];
  final indexes = <String, int>{};
  for (final source in <List<Map<String, dynamic>>>[primary, secondary]) {
    for (final raw in source) {
      final item = _canonicalFavoriteItem(raw);
      if (item.isEmpty) continue;
      final key = _favoriteItemIdentity(item);
      final existingIndex = indexes[key];
      if (existingIndex == null) {
        indexes[key] = out.length;
        out.add(item);
      } else {
        out[existingIndex] = <String, dynamic>{
          ...item,
          ...out[existingIndex],
        };
      }
    }
  }
  return out;
}

Map<String, dynamic> _canonicalFavoriteItem(Map<String, dynamic> raw) {
  final item = Map<String, dynamic>.from(raw);
  if (item.isEmpty) return item;
  final explicitKind =
      _normalizeFavoriteKind((item['kind'] ?? item['type'] ?? '').toString());
  final kind =
      explicitKind.isNotEmpty ? explicitKind : _favoriteItemServerKind(item);
  if (explicitKind.isNotEmpty || kind == 'mini_program') item['kind'] = kind;
  if (kind == 'mini_program') {
    final appId = _favoriteItemMiniProgramId(item);
    if (appId.isNotEmpty) {
      item['appId'] = appId;
      item['sourceId'] = _favoriteItemSourceId(item) ?? appId;
    }
    final sourceModule = (item['sourceModule'] ?? item['source_module'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (sourceModule.isEmpty ||
        sourceModule == 'mini_app' ||
        sourceModule == 'mini_apps') {
      item['sourceModule'] = 'mini_programs';
    }
  }
  return item;
}

bool _favoriteItemListsEqual(
  List<Map<String, dynamic>> a,
  List<Map<String, dynamic>> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (jsonEncode(a[i]) != jsonEncode(b[i])) return false;
  }
  return true;
}

String _favoriteItemIdentity(Map<String, dynamic> item) {
  final id = (item['id'] ?? '').toString().trim().toLowerCase();
  if (_isServerFavoriteId(id)) return 'id:$id';
  final sourceModule = (item['sourceModule'] ?? item['source_module'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final sourceId =
      (item['sourceId'] ?? item['source_id'] ?? '').toString().trim();
  if (sourceModule.isNotEmpty && sourceId.isNotEmpty) {
    return 'source:${sourceModule.toLowerCase()}:$sourceId';
  }
  final chatId = (item['chatId'] ?? '').toString().trim();
  final msgId = (item['msgId'] ?? '').toString().trim();
  if (chatId.isNotEmpty && msgId.isNotEmpty) return 'message:$chatId:$msgId';
  final lat = item['lat'];
  final lon = item['lon'];
  if (lat is num && lon is num) {
    return 'location:${lat.toStringAsFixed(6)}:${lon.toStringAsFixed(6)}';
  }
  final text = (item['text'] ?? '').toString().trim();
  return 'text:${_favoriteItemServerKind(item)}:$text';
}

void _ensureServerFavoriteId(Map<String, dynamic> item) {
  final current = (item['id'] ?? '').toString().trim().toLowerCase();
  if (_isServerFavoriteId(current)) {
    item['id'] = current;
    return;
  }
  item['id'] = _newServerFavoriteId(item);
}

String _newServerFavoriteId(Map<String, dynamic> item) {
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final hash = item.entries
      .map((entry) => '${entry.key}:${entry.value}')
      .join('|')
      .hashCode
      .abs()
      .toRadixString(36);
  return 'fav_${micros}_$hash';
}

bool _isServerFavoriteId(String raw) {
  return RegExp(r'^[a-z0-9][a-z0-9_.-]{0,63}$').hasMatch(raw.trim());
}

String _favoriteItemServerKind(Map<String, dynamic> item) {
  final raw =
      _normalizeFavoriteKind((item['kind'] ?? item['type'] ?? '').toString());
  if (raw.isNotEmpty) return raw;
  if (item['lat'] is num && item['lon'] is num) return 'location';
  if ((item['msgId'] ?? '').toString().trim().isNotEmpty) return 'message';
  final text = (item['text'] ?? '').toString();
  if (_looksLikeWebLink(text)) return 'link';
  if ((item['officialId'] ?? item['official_account_id'] ?? '')
      .toString()
      .trim()
      .isNotEmpty) {
    return 'official';
  }
  if ((item['momentId'] ?? item['moment_id'] ?? '')
      .toString()
      .trim()
      .isNotEmpty) {
    return 'moment';
  }
  if ((item['channelId'] ?? item['channel_id'] ?? '')
      .toString()
      .trim()
      .isNotEmpty) {
    return 'channel';
  }
  if ((item['appId'] ?? item['app_id'] ?? '').toString().trim().isNotEmpty) {
    return 'mini_program';
  }
  if (_favoriteItemMiniProgramId(item).isNotEmpty) return 'mini_program';
  return 'note';
}

String _normalizeFavoriteKind(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'chat':
    case 'message':
      return 'message';
    case 'url':
    case 'link':
      return 'link';
    case 'place':
    case 'geo':
    case 'location':
      return 'location';
    case 'official_account':
    case 'official':
      return 'official';
    case 'moments':
    case 'moment':
      return 'moment';
    case 'channels':
    case 'channel':
      return 'channel';
    case 'mini':
    case 'mini_app':
    case 'mini-program':
    case 'mini_program':
      return 'mini_program';
    case 'pay':
    case 'wallet':
    case 'payment':
      return 'payment';
    case 'note':
    case 'text':
      return 'note';
  }
  return '';
}

String? _favoriteItemTitle(Map<String, dynamic> item) {
  final title = (item['title'] ?? item['label'] ?? '').toString().trim();
  if (title.isEmpty) return null;
  return title.length > 220 ? title.substring(0, 220) : title;
}

String? _favoriteItemSourceModule(Map<String, dynamic> item) {
  final explicit =
      (item['sourceModule'] ?? item['source_module'] ?? '').toString().trim();
  if (explicit.isNotEmpty) return explicit.toLowerCase();
  if ((item['msgId'] ?? '').toString().trim().isNotEmpty) return 'chat';
  if ((item['officialId'] ?? item['official_account_id'] ?? '')
      .toString()
      .trim()
      .isNotEmpty) {
    return 'official_accounts';
  }
  if ((item['momentId'] ?? item['moment_id'] ?? '')
      .toString()
      .trim()
      .isNotEmpty) {
    return 'moments';
  }
  if ((item['channelId'] ?? item['channel_id'] ?? '')
      .toString()
      .trim()
      .isNotEmpty) {
    return 'channels';
  }
  if (_favoriteItemMiniProgramId(item).isNotEmpty) {
    return 'mini_programs';
  }
  return null;
}

String? _favoriteItemSourceId(Map<String, dynamic> item) {
  final explicit =
      (item['sourceId'] ?? item['source_id'] ?? '').toString().trim();
  if (explicit.isNotEmpty) return explicit;
  final chatId = (item['chatId'] ?? '').toString().trim();
  final msgId = (item['msgId'] ?? '').toString().trim();
  if (chatId.isNotEmpty && msgId.isNotEmpty) return '$chatId:$msgId';
  for (final key in const <String>[
    'officialId',
    'official_account_id',
    'momentId',
    'moment_id',
    'channelId',
    'channel_id',
    'miniProgramId',
    'mini_program_id',
    'miniAppId',
    'mini_app_id',
    'appId',
    'app_id',
  ]) {
    final value = (item[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

String _favoriteItemMiniProgramId(Map<String, dynamic> item) {
  for (final key in const <String>[
    'miniProgramId',
    'mini_program_id',
    'miniAppId',
    'mini_app_id',
    'appId',
    'app_id',
  ]) {
    final value = (item[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  final sourceModule = (item['sourceModule'] ?? item['source_module'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final sourceId =
      (item['sourceId'] ?? item['source_id'] ?? '').toString().trim();
  if ((sourceModule == 'mini_app' ||
          sourceModule == 'mini_apps' ||
          sourceModule == 'mini_program' ||
          sourceModule == 'mini_programs') &&
      sourceId.isNotEmpty) {
    return sourceId;
  }
  return '';
}

Map<String, Object?> _favoriteItemPayload(Map<String, dynamic> item) {
  final payload = <String, Object?>{};
  for (final entry in item.entries) {
    final key = entry.key.trim();
    if (key.isEmpty ||
        key == 'id' ||
        key == 'text' ||
        key == 'title' ||
        key == 'sourceModule' ||
        key == 'sourceId') {
      continue;
    }
    payload[key] = _jsonSafeFavoriteValue(entry.value);
  }
  return payload;
}

Object? _jsonSafeFavoriteValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map(_jsonSafeFavoriteValue).toList(growable: false);
  }
  if (value is Map) {
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      out[entry.key.toString()] = _jsonSafeFavoriteValue(entry.value);
    }
    return out;
  }
  return value.toString();
}

bool _looksLikeWebLink(String text) {
  return RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)', caseSensitive: false)
      .hasMatch(text);
}

Future<void> _removeLegacyFavorites({SharedPreferences? sp}) async {
  try {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(_favoritesLegacyKey);
  } catch (_) {}
}

Future<_SecureReadResult> _secureReadResult(String key) async {
  try {
    final value = await _favoritesSecureStore.read(key: key);
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
    await _favoritesSecureStore.write(key: key, value: value);
    final roundTrip = (await _favoritesSecureStore.read(key: key) ?? '').trim();
    return roundTrip == value.trim();
  } catch (_) {
    return false;
  }
}

Future<bool> _secureDelete(String key) async {
  try {
    await _favoritesSecureStore.delete(key: key);
    final roundTrip = (await _favoritesSecureStore.read(key: key) ?? '').trim();
    return roundTrip.isEmpty;
  } catch (_) {
    return false;
  }
}

String _currentFavoritesScope(
  SharedPreferences prefs, {
  String? baseUrlOverride,
}) {
  final overridden = (baseUrlOverride ?? '').trim();
  if (overridden.isNotEmpty) {
    return normalizeSecureApiBaseUrl(overridden) ?? _favoritesUnknownScope;
  }
  final rawBase = (prefs.getString(_favoritesBaseUrlPrefKey) ?? '').trim();
  return normalizeSecureApiBaseUrl(rawBase) ?? _favoritesUnknownScope;
}

bool _isUnknownFavoritesScope(String scope) {
  return scope == _favoritesUnknownScope;
}

bool _allowLegacyFavoritesFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_FAVORITES_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_FAVORITES_FALLBACK_ON_MOBILE',
      defaultValue: false,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_FAVORITES_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_FAVORITES_FALLBACK',
    defaultValue: true,
  );
}

String _scopedFavoritesKey(String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_favoritesScopedKeyPrefix$suffix';
}

Future<void> _clearLegacyFavorites({required SharedPreferences sp}) async {
  await _secureDelete(_favoritesLegacySecureKey);
  await _removeLegacyFavorites(sp: sp);
}

Future<void> _clearAllFavoritesSecureKeys() async {
  try {
    final all = await _favoritesSecureStore.readAll();
    for (final key in all.keys) {
      if (key == _favoritesLegacySecureKey ||
          key.startsWith(_favoritesScopedKeyPrefix)) {
        try {
          await _favoritesSecureStore.delete(key: key);
        } catch (_) {}
      }
    }
  } catch (_) {
    await _secureDelete(_favoritesLegacySecureKey);
  }
}

Future<void> _clearAllFavoritesPrefs({required SharedPreferences sp}) async {
  try {
    final keys = sp
        .getKeys()
        .where((key) =>
            key == _favoritesLegacyKey ||
            key.startsWith(_favoritesScopedKeyPrefix))
        .toList(growable: false);
    for (final key in keys) {
      await sp.remove(key);
    }
  } catch (_) {}
}
