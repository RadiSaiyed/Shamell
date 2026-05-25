// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'base_url.dart';
import 'shamell_webview_page.dart';

const Duration _superappApiRequestTimeout = Duration(seconds: 20);
const String _superappKvPrefix = 'superapp.kv.';
final RegExp _superappKvSegmentPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');
const String _superappKvTypeString = 'string';
const String _superappKvTypeInt = 'int';
const String _superappKvTypeBool = 'bool';
const String _superappKvTypeStringList = 'string_list';
const Set<String> _superappAllowedExternalSchemes = <String>{
  'http',
  'https',
  'mailto',
  'tel',
};

String _defaultSuperappApiBaseUrl() {
  return normalizeSecureApiBaseUrl(
        const String.fromEnvironment(
          'BASE_URL',
          defaultValue: 'https://api.shamell.online',
        ),
      ) ??
      'https://api.shamell.online';
}

bool _superappIsLocalhostHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

const FlutterSecureStorage _superappKvSecureStore = FlutterSecureStorage(
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

class _SecureKvReadResult<T> {
  final T? value;
  final bool failed;
  const _SecureKvReadResult({
    required this.value,
    required this.failed,
  });
}

class GeoPosition {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });
}

typedef EnsureOfficialFollowFn = Future<void> Function({
  required String officialId,
  required String chatPeerId,
});

typedef RecordModuleUseFn = Future<void> Function(String moduleId);

/// Host‑API surface that Mini‑Apps are allowed to depend on.
///
/// This will grow to include Payments, Chat, Location, Storage,
/// Analytics, FeatureFlags, etc. For now it exposes the minimal
/// primitives required to open built‑in Mini‑Apps without reaching
/// into `main.dart`.
class SuperappAPI {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String storageNamespace;
  final http.Client Function()? httpClientFactory;
  final void Function(String modId) openMod;
  final void Function(Widget page) pushPage;
  final EnsureOfficialFollowFn ensureServiceOfficialFollow;
  final RecordModuleUseFn recordModuleUse;

  const SuperappAPI({
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    this.storageNamespace = 'global',
    this.httpClientFactory,
    required this.openMod,
    required this.pushPage,
    required this.ensureServiceOfficialFollow,
    required this.recordModuleUse,
  });

  static Future<void> _noopEnsureOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {}

  static Future<void> _noopRecordModuleUse(String moduleId) async {}

  static void _noopOpenMod(String modId) {}

  static void _noopPushPage(Widget page) {}

  bool get _canPushPage => pushPage != _noopPushPage;

  factory SuperappAPI.light({
    required String baseUrl,
    String walletId = '',
    String deviceId = '',
    http.Client Function()? httpClientFactory,
    void Function(String modId)? openMod,
    void Function(Widget page)? pushPage,
    EnsureOfficialFollowFn? ensureServiceOfficialFollow,
    RecordModuleUseFn? recordModuleUse,
  }) {
    final effectiveBaseUrl = normalizeSecureApiBaseUrl(baseUrl.trim()) ??
        _defaultSuperappApiBaseUrl();
    return SuperappAPI(
      baseUrl: effectiveBaseUrl,
      walletId: walletId,
      deviceId: deviceId,
      httpClientFactory: httpClientFactory,
      openMod: openMod ?? _noopOpenMod,
      pushPage: pushPage ?? _noopPushPage,
      ensureServiceOfficialFollow:
          ensureServiceOfficialFollow ?? _noopEnsureOfficialFollow,
      recordModuleUse: recordModuleUse ?? _noopRecordModuleUse,
    );
  }

  String get _cleanBase => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  @visibleForTesting
  static Uri? normalizeSuperappLaunchUri(
    Uri uri, {
    Uri? baseUri,
  }) {
    var candidate = uri;
    if (baseUri != null && candidate.scheme.isEmpty) {
      try {
        candidate = baseUri.resolveUri(candidate);
      } catch (_) {}
    }
    final scheme = candidate.scheme.toLowerCase();
    if (!_superappAllowedExternalSchemes.contains(scheme)) {
      return null;
    }
    if (scheme == 'http' || scheme == 'https') {
      if (candidate.host.trim().isEmpty) return null;
      if (candidate.userInfo.isNotEmpty) return null;
      // Security hardening: never allow plaintext remote links. Keep HTTP
      // only for explicit localhost/dev tooling targets.
      if (scheme == 'http' && !_superappIsLocalhostHost(candidate.host)) {
        return null;
      }
      return candidate;
    }
    final target = candidate.path.trim();
    if (target.isEmpty) return null;
    return candidate;
  }

  @visibleForTesting
  static Uri? normalizeSuperappRequestUri(
    Uri uri, {
    Uri? baseUri,
  }) {
    if (baseUri == null) return null;
    var candidate = uri;
    if (candidate.scheme.isEmpty) {
      try {
        candidate = baseUri.resolveUri(candidate);
      } catch (_) {
        return null;
      }
    }
    final scheme = candidate.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (candidate.host.trim().isEmpty) return null;
    if (candidate.userInfo.isNotEmpty) return null;

    final baseScheme = baseUri.scheme.toLowerCase();
    final baseHost = baseUri.host.toLowerCase();
    final basePort =
        baseUri.hasPort ? baseUri.port : (baseScheme == 'https' ? 443 : 80);
    final candidatePort =
        candidate.hasPort ? candidate.port : (scheme == 'https' ? 443 : 80);
    final sameOrigin = baseScheme == scheme &&
        baseHost == candidate.host.toLowerCase() &&
        basePort == candidatePort;
    if (!sameOrigin) return null;
    return candidate;
  }

  Uri uri(String path, {Map<String, String>? query}) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$_cleanBase/$p')
        .replace(queryParameters: query?.isEmpty == true ? null : query);
  }

  Future<Map<String, String>> sessionHeaders({
    required Uri uri,
    bool json = false,
    Map<String, String>? extra,
  }) async {
    _normalizeRequestUriOrThrow(uri);
    return shamellSessionHeadersForBaseUrl(
      baseUrl,
      json: json,
      extra: extra,
    );
  }

  Future<http.Response> getUri(Uri uri, {Map<String, String>? headers}) async {
    final normalized = _normalizeRequestUriOrThrow(uri);
    return _sendWithHttpClient(
      (client) => client.get(normalized, headers: headers),
    );
  }

  Future<http.Response> postUri(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final normalized = _normalizeRequestUriOrThrow(uri);
    return _sendWithHttpClient(
      (client) => client.post(
        normalized,
        headers: headers,
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> patchUri(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final normalized = _normalizeRequestUriOrThrow(uri);
    return _sendWithHttpClient(
      (client) => client.patch(
        normalized,
        headers: headers,
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> deleteUri(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final normalized = _normalizeRequestUriOrThrow(uri);
    return _sendWithHttpClient(
      (client) => client.delete(
        normalized,
        headers: headers,
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<String?> kvGetString(String key) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return null;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        var secureReadFailed = false;
        final secureRead = await _readSecureKvString(scopedKey);
        secureReadFailed = secureRead.failed;
        final secure = secureRead.value;
        if (secure != null) {
          await sp.remove(scopedKey);
          return secure;
        }

        // Fail closed by default: do not trust mutable SharedPreferences
        // values unless fallback is explicitly enabled or secure storage is
        // unavailable.
        if (!_allowLegacySuperappKvFallback() && !secureReadFailed) {
          await sp.remove(scopedKey);
          return null;
        }

        final legacy = sp.getString(scopedKey);
        if (legacy == null) return null;
        try {
          await _writeSecureKvValue(
            scopedKey,
            type: _superappKvTypeString,
            value: legacy,
          );
        } catch (_) {
          if (secureReadFailed) {
            return legacy;
          }
          await sp.remove(scopedKey);
          return null;
        }
        await sp.remove(scopedKey);
        return legacy;
      }
      return sp.getString(scopedKey);
    } catch (_) {
      return null;
    }
  }

  Future<int?> kvGetInt(String key) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return null;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        var secureReadFailed = false;
        final secureRead = await _readSecureKvInt(scopedKey);
        secureReadFailed = secureRead.failed;
        final secure = secureRead.value;
        if (secure != null) {
          await sp.remove(scopedKey);
          return secure;
        }

        // Fail closed by default: do not trust mutable SharedPreferences
        // values unless fallback is explicitly enabled or secure storage is
        // unavailable.
        if (!_allowLegacySuperappKvFallback() && !secureReadFailed) {
          await sp.remove(scopedKey);
          return null;
        }

        final legacy = sp.getInt(scopedKey);
        if (legacy == null) return null;
        try {
          await _writeSecureKvValue(
            scopedKey,
            type: _superappKvTypeInt,
            value: legacy,
          );
        } catch (_) {
          if (secureReadFailed) {
            return legacy;
          }
          await sp.remove(scopedKey);
          return null;
        }
        await sp.remove(scopedKey);
        return legacy;
      }
      return sp.getInt(scopedKey);
    } catch (_) {
      return null;
    }
  }

  Future<bool?> kvGetBool(String key) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return null;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        var secureReadFailed = false;
        final secureRead = await _readSecureKvBool(scopedKey);
        secureReadFailed = secureRead.failed;
        final secure = secureRead.value;
        if (secure != null) {
          await sp.remove(scopedKey);
          return secure;
        }

        // Fail closed by default: do not trust mutable SharedPreferences
        // values unless fallback is explicitly enabled or secure storage is
        // unavailable.
        if (!_allowLegacySuperappKvFallback() && !secureReadFailed) {
          await sp.remove(scopedKey);
          return null;
        }

        final legacy = sp.getBool(scopedKey);
        if (legacy == null) return null;
        try {
          await _writeSecureKvValue(
            scopedKey,
            type: _superappKvTypeBool,
            value: legacy,
          );
        } catch (_) {
          if (secureReadFailed) {
            return legacy;
          }
          await sp.remove(scopedKey);
          return null;
        }
        await sp.remove(scopedKey);
        return legacy;
      }
      return sp.getBool(scopedKey);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>?> kvGetStringList(String key) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return null;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        var secureReadFailed = false;
        final secureRead = await _readSecureKvStringList(scopedKey);
        secureReadFailed = secureRead.failed;
        final secure = secureRead.value;
        if (secure != null) {
          await sp.remove(scopedKey);
          return secure;
        }

        // Fail closed by default: do not trust mutable SharedPreferences
        // values unless fallback is explicitly enabled or secure storage is
        // unavailable.
        if (!_allowLegacySuperappKvFallback() && !secureReadFailed) {
          await sp.remove(scopedKey);
          return null;
        }

        final legacy = sp.getStringList(scopedKey);
        if (legacy == null) return null;
        try {
          await _writeSecureKvValue(
            scopedKey,
            type: _superappKvTypeStringList,
            value: legacy,
          );
        } catch (_) {
          if (secureReadFailed) {
            return legacy;
          }
          await sp.remove(scopedKey);
          return null;
        }
        await sp.remove(scopedKey);
        return legacy;
      }
      return sp.getStringList(scopedKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> kvSetString(String key, String value) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        await _writeSecureKvValue(
          scopedKey,
          type: _superappKvTypeString,
          value: value,
        );
        await sp.remove(scopedKey);
        return;
      }
      await sp.setString(scopedKey, value);
    } catch (_) {}
  }

  Future<void> kvSetInt(String key, int value) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        await _writeSecureKvValue(
          scopedKey,
          type: _superappKvTypeInt,
          value: value,
        );
        await sp.remove(scopedKey);
        return;
      }
      await sp.setInt(scopedKey, value);
    } catch (_) {}
  }

  Future<void> kvSetBool(String key, bool value) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        await _writeSecureKvValue(
          scopedKey,
          type: _superappKvTypeBool,
          value: value,
        );
        await sp.remove(scopedKey);
        return;
      }
      await sp.setBool(scopedKey, value);
    } catch (_) {}
  }

  Future<void> kvSetStringList(String key, List<String> value) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        await _writeSecureKvValue(
          scopedKey,
          type: _superappKvTypeStringList,
          value: value,
        );
        await sp.remove(scopedKey);
        return;
      }
      await sp.setStringList(scopedKey, value);
    } catch (_) {}
  }

  Future<void> kvRemove(String key) async {
    try {
      final scopedKey = _scopedKvKey(key);
      if (scopedKey == null) return;
      final sp = await SharedPreferences.getInstance();
      if (_useSecureKvStore()) {
        try {
          await _superappKvSecureStore.delete(key: scopedKey);
        } catch (_) {}
      }
      await sp.remove(scopedKey);
    } catch (_) {}
  }

  static Future<void> clearPersistedState({SharedPreferences? sp}) async {
    try {
      if (_useSecureKvStore()) {
        try {
          final all = await _superappKvSecureStore.readAll();
          for (final key in all.keys) {
            if (!key.startsWith(_superappKvPrefix)) continue;
            try {
              await _superappKvSecureStore.delete(key: key);
            } catch (_) {}
          }
        } catch (_) {}
      }
      final prefs = sp ?? await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith(_superappKvPrefix))
          .toList(growable: false);
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  String? _scopedKvKey(String key) {
    final scope = _storageScopeSegment();
    final namespace = _normalizeKvSegment(storageNamespace);
    final normalizedKey = _normalizeKvSegment(key);
    if (scope == null || namespace == null || normalizedKey == null) {
      return null;
    }
    return '$_superappKvPrefix$scope.$namespace.$normalizedKey';
  }

  String? _normalizeKvSegment(String raw) {
    final normalized = raw.trim();
    if (!_superappKvSegmentPattern.hasMatch(normalized)) return null;
    return normalized;
  }

  String? _storageScopeSegment() {
    final normalizedBase = normalizeSecureApiBaseUrl(baseUrl.trim());
    if (normalizedBase == null || normalizedBase.isEmpty) return null;
    final origin = Uri.parse(normalizedBase).origin;
    final normalizedWallet = walletId.trim();
    final scopePayload =
        normalizedWallet.isEmpty ? origin : '$origin|$normalizedWallet';
    return base64Url.encode(utf8.encode(scopePayload)).replaceAll('=', '');
  }

  Future<void> shareText(
    String text, {
    String? subject,
  }) async {
    try {
      await Share.share(text, subject: subject);
    } catch (_) {}
  }

  Future<bool> openUrl(
    Uri uri, {
    bool external = false,
  }) async {
    try {
      final baseUri = Uri.tryParse(_cleanBase);
      final normalized = normalizeSuperappLaunchUri(uri, baseUri: baseUri);
      if (normalized == null) return false;
      uri = normalized;
      if (!external) {
        final scheme = uri.scheme.toLowerCase();
        if ((scheme == 'http' || scheme == 'https') && _canPushPage) {
          // Best practice: keep embedded WebViews first-party and same-origin.
          if (baseUri != null) {
            final sameScheme = baseUri.scheme.toLowerCase() == scheme;
            final sameHost =
                baseUri.host.toLowerCase() == uri.host.toLowerCase();
            final basePort =
                baseUri.hasPort ? baseUri.port : (scheme == 'https' ? 443 : 80);
            final uriPort =
                uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
            final sameOrigin = sameScheme && sameHost && basePort == uriPort;
            if (sameOrigin) {
              pushPage(
                ShamellWebViewPage(
                  initialUri: uri,
                  baseUri: baseUri,
                ),
              );
              return true;
            }
          }
          // Non-same-origin: open externally to reduce phishing surface.
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return await launchUrl(
        uri,
        mode: external || uri.scheme == 'mailto' || uri.scheme == 'tel'
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> openUrlString(
    String url, {
    bool external = false,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return openUrl(uri, external: external);
  }

  Future<GeoPosition?> getCurrentLocation({bool best = true}) async {
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: best ? LocationAccuracy.best : LocationAccuracy.high,
      );
      return GeoPosition(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
      );
    } catch (_) {
      return null;
    }
  }

  Uri _normalizeRequestUriOrThrow(Uri uri) {
    final baseUri = Uri.tryParse(_cleanBase);
    final normalized = normalizeSuperappRequestUri(uri, baseUri: baseUri);
    if (normalized == null) {
      throw ArgumentError(
        'Superapp API only allows same-origin http(s) requests.',
      );
    }
    return normalized;
  }

  Future<http.Response> _sendWithHttpClient(
    Future<http.Response> Function(http.Client client) send,
  ) async {
    final client = (httpClientFactory ?? shamellHttpClient)();
    try {
      return await send(client).timeout(_superappApiRequestTimeout);
    } finally {
      client.close();
    }
  }

  static bool _useSecureKvStore() => !kIsWeb;

  static bool _allowLegacySuperappKvFallback() {
    if (kIsWeb) return false;
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      if (kReleaseMode) {
        return const bool.fromEnvironment(
          'ALLOW_LEGACY_SUPERAPP_KV_FALLBACK_ON_MOBILE_IN_RELEASE',
          defaultValue: false,
        );
      }
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_SUPERAPP_KV_FALLBACK_ON_MOBILE',
        defaultValue: false,
      );
    }
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_SUPERAPP_KV_FALLBACK_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_SUPERAPP_KV_FALLBACK',
      defaultValue: true,
    );
  }

  static Future<void> _writeSecureKvValue(
    String key, {
    required String type,
    required Object value,
  }) async {
    await _superappKvSecureStore.write(
      key: key,
      value: jsonEncode(<String, Object?>{
        't': type,
        'v': value,
      }),
    );
  }

  static Future<_SecureKvReadResult<String>> _readSecureKvString(
    String key,
  ) async {
    final value = await _readSecureKvValue(
      key,
      expectedType: _superappKvTypeString,
    );
    return _SecureKvReadResult<String>(
      value: value.value is String ? value.value as String : null,
      failed: value.failed,
    );
  }

  static Future<_SecureKvReadResult<int>> _readSecureKvInt(String key) async {
    final value = await _readSecureKvValue(
      key,
      expectedType: _superappKvTypeInt,
    );
    return _SecureKvReadResult<int>(
      value: value.value is int ? value.value as int : null,
      failed: value.failed,
    );
  }

  static Future<_SecureKvReadResult<bool>> _readSecureKvBool(
    String key,
  ) async {
    final value = await _readSecureKvValue(
      key,
      expectedType: _superappKvTypeBool,
    );
    return _SecureKvReadResult<bool>(
      value: value.value is bool ? value.value as bool : null,
      failed: value.failed,
    );
  }

  static Future<_SecureKvReadResult<List<String>>> _readSecureKvStringList(
    String key,
  ) async {
    final value = await _readSecureKvValue(
      key,
      expectedType: _superappKvTypeStringList,
    );
    return _SecureKvReadResult<List<String>>(
      value: value.value is List<String> ? value.value as List<String> : null,
      failed: value.failed,
    );
  }

  static Future<_SecureKvReadResult<Object>> _readSecureKvValue(
    String key, {
    required String expectedType,
  }) async {
    try {
      final raw = (await _superappKvSecureStore.read(key: key) ?? '').trim();
      if (raw.isEmpty) {
        return const _SecureKvReadResult<Object>(value: null, failed: false);
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const _SecureKvReadResult<Object>(value: null, failed: false);
      }
      final type = decoded['t']?.toString().trim() ?? '';
      if (type != expectedType) {
        return const _SecureKvReadResult<Object>(value: null, failed: false);
      }
      final value = decoded['v'];
      switch (expectedType) {
        case _superappKvTypeString:
          return _SecureKvReadResult<Object>(
            value: value is String ? value : null,
            failed: false,
          );
        case _superappKvTypeInt:
          return _SecureKvReadResult<Object>(
            value: value is int ? value : null,
            failed: false,
          );
        case _superappKvTypeBool:
          return _SecureKvReadResult<Object>(
            value: value is bool ? value : null,
            failed: false,
          );
        case _superappKvTypeStringList:
          if (value is! List || value.any((entry) => entry is! String)) {
            return const _SecureKvReadResult<Object>(
              value: null,
              failed: false,
            );
          }
          return _SecureKvReadResult<Object>(
            value: List<String>.from(value),
            failed: false,
          );
      }
    } catch (_) {
      return const _SecureKvReadResult<Object>(value: null, failed: true);
    }
    return const _SecureKvReadResult<Object>(value: null, failed: false);
  }
}
