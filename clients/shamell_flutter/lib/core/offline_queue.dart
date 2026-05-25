// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/device_binding_guard.dart';
import 'package:shamell_flutter/core/runtime_base_scope.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const Duration _offlineQueueRequestTimeout = Duration(seconds: 10);
const String _offlineQueueLegacyKey = 'offline_queue_v1';
const String _offlineQueueSecureKey = 'offline.queue.v2';
const String _offlineQueueBaseUrlPrefKey = 'base_url';
const String _offlineQueueUnknownScope = 'unknown';

const FlutterSecureStorage _offlineQueueSecureStore = FlutterSecureStorage(
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

// Never persist authentication material in SharedPreferences.
const Set<String> _offlineSensitiveHeaders = <String>{
  'cookie',
  'authorization',
  'set-cookie',
  'x-chat-device-token',
  'x-internal-secret',
  'x-legacy-internal-secret',
  'x-role-auth',
  'x-auth-roles',
  'x-internal-service-id',
  'x-internal-audience',
  'x-internal-identity-ts',
  'x-internal-identity-nonce',
  'x-internal-identity-sig',
  'x-internal-identity-sig-v2',
  'x-shamell-payment-attestation-challenge',
  'x-shamell-payment-play-integrity',
  'x-shamell-payment-apple-devicecheck',
};

@visibleForTesting
bool isOfflineSensitiveHeader(String name) =>
    _offlineSensitiveHeaders.contains(name.trim().toLowerCase());

@visibleForTesting
bool offlineTaskHasReplayProtection(OfflineTask task) {
  final method = task.method.trim().toUpperCase();
  if (method == 'GET' || method == 'HEAD' || method == 'OPTIONS') {
    return true;
  }
  for (final entry in task.headers.entries) {
    if (entry.key.trim().toLowerCase() == 'idempotency-key' &&
        entry.value.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}

@visibleForTesting
Map<String, String> sanitizeOfflineHeadersForStorage(
    Map<String, String> headers) {
  final out = <String, String>{};
  headers.forEach((key, value) {
    final k = key.trim();
    final v = value.trim();
    if (k.isEmpty || v.isEmpty) return;
    if (isOfflineSensitiveHeader(k)) return;
    out[k] = v;
  });
  return out;
}

@visibleForTesting
String? offlineAuthBaseFromTaskUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || uri.scheme.isEmpty || uri.host.trim().isEmpty) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  if (uri.hasPort) return '$scheme://$host:${uri.port}';
  return '$scheme://$host';
}

bool _offlineSameOrigin(Uri a, Uri b) {
  final aScheme = a.scheme.toLowerCase();
  final bScheme = b.scheme.toLowerCase();
  final aPort = a.hasPort ? a.port : (aScheme == 'https' ? 443 : 80);
  final bPort = b.hasPort ? b.port : (bScheme == 'https' ? 443 : 80);
  return aScheme == bScheme &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      aPort == bPort;
}

@visibleForTesting
String? offlineTrustedAuthBaseForTaskUrl(
  String rawUrl, {
  String? configuredBaseUrl,
}) {
  final normalizedConfigured =
      normalizeSecureApiBaseUrl((configuredBaseUrl ?? '').trim());
  if (normalizedConfigured == null) return null;
  final taskBase = offlineAuthBaseFromTaskUrl(rawUrl);
  if (taskBase == null) return null;
  final normalizedTask = normalizeSecureApiBaseUrl(taskBase);
  if (normalizedTask == null) return null;
  if (!_offlineSameOrigin(
    Uri.parse(normalizedTask),
    Uri.parse(normalizedConfigured),
  )) {
    return null;
  }
  return normalizedConfigured;
}

@visibleForTesting
bool offlineTaskMayAttachSessionCookie(
  String rawUrl, {
  String? configuredBaseUrl,
}) {
  return offlineTrustedAuthBaseForTaskUrl(
        rawUrl,
        configuredBaseUrl: configuredBaseUrl,
      ) !=
      null;
}

bool _sameHeaders(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

class OfflineTask {
  final String id;
  final String method;
  final String url;
  final String scope;
  final Map<String, String> headers;
  final String body;
  final String tag;
  final int createdAt;
  int retries;
  int nextAt = 0;
  OfflineTask({
    required this.id,
    required this.method,
    required this.url,
    this.scope = '',
    required this.headers,
    required this.body,
    required this.tag,
    required this.createdAt,
    this.retries = 0,
    int? nextAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'url': url,
        if (scope.trim().isNotEmpty) 'scope': scope,
        'headers': headers,
        'body': body,
        'tag': tag,
        'createdAt': createdAt,
        'retries': retries,
        'nextAt': nextAt,
      };
  static OfflineTask fromJson(Map<String, dynamic> j) => OfflineTask(
        id: j['id'],
        method: j['method'],
        url: j['url'],
        scope: (j['scope'] ?? '').toString(),
        headers: (j['headers'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        body: j['body'],
        tag: j['tag'] ?? 'misc',
        createdAt: j['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        retries: j['retries'] ?? 0,
        nextAt: j['nextAt'] ?? 0,
      );
}

@visibleForTesting
Future<Map<String, String>> buildOfflineHeadersForTask(
  OfflineTask t, {
  String? configuredBaseUrl,
}) async {
  final out = sanitizeOfflineHeadersForStorage(t.headers);
  final trustedBase = offlineTrustedAuthBaseForTaskUrl(
    t.url,
    configuredBaseUrl: configuredBaseUrl,
  );
  if (trustedBase == null) return out;
  try {
    final sessionHeaders = await shamellSessionHeadersForBaseUrl(
      trustedBase,
      includeSessionCookie: true,
    );
    out.addAll(sessionHeaders);
  } catch (_) {}
  return out;
}

@visibleForTesting
bool offlineTaskShouldDropAfterHttpFailure({
  required int statusCode,
  String? rawBody,
}) {
  if (shamellIsCriticalAccountSessionHttpFailure(
    statusCode: statusCode,
    rawBody: rawBody,
  )) {
    return true;
  }
  if (shamellContainsAttestationFailureDetail(rawBody)) {
    return true;
  }
  if (statusCode < 400 || statusCode >= 500) {
    return false;
  }
  return shamellIsCriticalDeviceBindingMismatch(
    statusCode: statusCode,
    rawBody: rawBody,
  );
}

String _offlineFailureDetail(String? rawBody) {
  final text = (rawBody ?? '').trim();
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final detail = (decoded['detail'] ?? '').toString().trim();
      if (detail.isNotEmpty) {
        return detail;
      }
    }
  } catch (_) {}
  return text;
}

@visibleForTesting
bool shamellContainsAttestationFailureDetail(String? rawBody) {
  final detail = _offlineFailureDetail(rawBody).toLowerCase();
  return detail.contains('attestation required') ||
      detail.contains('device attestation unavailable') ||
      detail.contains('device verification required');
}

class OfflineQueue {
  static List<OfflineTask> _items = [];
  static bool _flushing = false;
  static String _activeScope = _offlineQueueUnknownScope;

  static OfflineTask _copyWithHeaders(
    OfflineTask t,
    Map<String, String> headers,
  ) {
    return OfflineTask(
      id: t.id,
      method: t.method,
      url: t.url,
      scope: t.scope,
      headers: headers,
      body: t.body,
      tag: t.tag,
      createdAt: t.createdAt,
      retries: t.retries,
      nextAt: t.nextAt,
    );
  }

  static OfflineTask _sanitizeTaskHeaders(OfflineTask t) {
    final sanitized = sanitizeOfflineHeadersForStorage(t.headers);
    if (_sameHeaders(sanitized, t.headers)) return t;
    return _copyWithHeaders(t, sanitized);
  }

  static String _resolvedConfiguredBaseUrl(
    SharedPreferences prefs, {
    String? baseUrlOverride,
  }) {
    final normalizedOverride = shamellNormalizeRuntimeBaseUrl(baseUrlOverride);
    if (normalizedOverride != null && normalizedOverride.isNotEmpty) {
      return normalizedOverride;
    }
    final normalizedActive =
        shamellNormalizeRuntimeBaseUrl(shamellGetActiveRuntimeBaseUrl());
    if (normalizedActive != null && normalizedActive.isNotEmpty) {
      return normalizedActive;
    }
    return normalizeSecureApiBaseUrl(
          (prefs.getString(_offlineQueueBaseUrlPrefKey) ?? '').trim(),
        ) ??
        '';
  }

  static String _currentScope(
    SharedPreferences prefs, {
    String? baseUrlOverride,
  }) {
    final normalized = _resolvedConfiguredBaseUrl(
      prefs,
      baseUrlOverride: baseUrlOverride,
    );
    if (normalized.isEmpty) return _offlineQueueUnknownScope;
    return Uri.parse(normalized).origin;
  }

  static bool _isUnknownScope(String scope) =>
      scope == _offlineQueueUnknownScope;

  static OfflineTask _withScope(OfflineTask t, String scope) {
    final normalizedScope = scope.trim();
    if ((t.scope).trim() == normalizedScope) return t;
    return OfflineTask(
      id: t.id,
      method: t.method,
      url: t.url,
      scope: normalizedScope,
      headers: t.headers,
      body: t.body,
      tag: t.tag,
      createdAt: t.createdAt,
      retries: t.retries,
      nextAt: t.nextAt,
    );
  }

  static bool _taskBelongsToScope(OfflineTask t, String scope) {
    final taskScope = t.scope.trim();
    if (taskScope.isEmpty) return false;
    return taskScope == scope;
  }

  static bool _taskMatchesConfiguredOrigin(
    OfflineTask t, {
    required String configuredBaseUrl,
  }) {
    return offlineTaskMayAttachSessionCookie(
      t.url,
      configuredBaseUrl: configuredBaseUrl,
    );
  }

  static Future<Map<String, String>> _effectiveHeadersForTask(
    OfflineTask t, {
    String? baseUrlOverride,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configuredBaseUrl = _resolvedConfiguredBaseUrl(
        prefs,
        baseUrlOverride: baseUrlOverride,
      );
      return buildOfflineHeadersForTask(
        t,
        configuredBaseUrl: configuredBaseUrl,
      );
    } catch (_) {
      return buildOfflineHeadersForTask(t);
    }
  }

  static Future<http.Response> _sendTask(
    OfflineTask t, {
    String? baseUrlOverride,
  }) async {
    final uri = Uri.parse(t.url);
    final headers = await _effectiveHeadersForTask(
      t,
      baseUrlOverride: baseUrlOverride,
    );
    final client = shamellHttpClient();
    try {
      switch (t.method.toUpperCase()) {
        case 'POST':
          return client
              .post(uri, headers: headers, body: t.body)
              .timeout(_offlineQueueRequestTimeout);
        case 'PUT':
          return client
              .put(uri, headers: headers, body: t.body)
              .timeout(_offlineQueueRequestTimeout);
        case 'PATCH':
          return client
              .patch(uri, headers: headers, body: t.body)
              .timeout(_offlineQueueRequestTimeout);
        case 'DELETE':
          return client
              .delete(uri, headers: headers, body: t.body)
              .timeout(_offlineQueueRequestTimeout);
        default:
          return client
              .post(uri, headers: headers, body: t.body)
              .timeout(_offlineQueueRequestTimeout);
      }
    } finally {
      client.close();
    }
  }

  static Future<void> init({String? baseUrlOverride}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeScope = _currentScope(
        prefs,
        baseUrlOverride: baseUrlOverride,
      );
      final restored = await _loadPersistedTasks(
        baseUrlOverride: baseUrlOverride,
      );
      // Keep the in-memory queue growable even when restore path returns
      // immutable empty lists (for example, fail-closed secure-store paths).
      _items = List<OfflineTask>.from(restored, growable: true);
    } catch (_) {
      _items = [];
      _activeScope = _offlineQueueUnknownScope;
    }
  }

  static List<OfflineTask> pending({
    String? tag,
    String? baseUrlOverride,
  }) {
    final normalizedScope = (() {
      try {
        final explicit = shamellNormalizeRuntimeBaseUrl(baseUrlOverride);
        if (explicit != null && explicit.isNotEmpty) {
          return Uri.parse(explicit).origin;
        }
        final active =
            shamellNormalizeRuntimeBaseUrl(shamellGetActiveRuntimeBaseUrl());
        if (active != null && active.isNotEmpty) {
          return Uri.parse(active).origin;
        }
      } catch (_) {}
      return _activeScope;
    })();
    _activeScope = normalizedScope;
    final scoped = _items.where((t) => _taskBelongsToScope(t, normalizedScope));
    return List.unmodifiable(
      tag == null ? scoped : scoped.where((t) => t.tag == tag),
    );
  }

  static Future<void> _persist() async {
    try {
      if (_useSecureStore()) {
        if (_items.isEmpty) {
          await _offlineQueueSecureStore.delete(key: _offlineQueueSecureKey);
        } else {
          await _offlineQueueSecureStore.write(
            key: _offlineQueueSecureKey,
            value: jsonEncode(
              _items.map((t) => t.toJson()).toList(growable: false),
            ),
          );
        }
        await _removeLegacyPersistence();
        return;
      }

      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(
        _offlineQueueLegacyKey,
        _items.map((t) => jsonEncode(t.toJson())).toList(growable: false),
      );
    } catch (_) {}
  }

  static Future<void> enqueue(
    OfflineTask t, {
    String? baseUrlOverride,
  }) async {
    // initialize nextAt to now for first attempt
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    );
    _activeScope = scope;
    final queued = _withScope(_sanitizeTaskHeaders(t), scope);
    if (!offlineTaskHasReplayProtection(queued)) {
      throw StateError('Offline task missing replay protection');
    }
    queued.nextAt = DateTime.now().millisecondsSinceEpoch;
    _items.add(queued);
    await _persist();
  }

  static Future<int> flush({String? baseUrlOverride}) async {
    if (_flushing || _items.isEmpty) return 0;
    _flushing = true;
    int delivered = 0;
    try {
      // Simple sequential flush
      for (int i = 0; i < _items.length;) {
        final t = _items[i];
        final prefs = await SharedPreferences.getInstance();
        final configuredBaseUrl = _resolvedConfiguredBaseUrl(
          prefs,
          baseUrlOverride: baseUrlOverride,
        );
        final currentScope = _currentScope(
          prefs,
          baseUrlOverride: baseUrlOverride,
        );
        _activeScope = currentScope;
        if (!_taskBelongsToScope(t, currentScope) ||
            !_taskMatchesConfiguredOrigin(
              t,
              configuredBaseUrl: configuredBaseUrl,
            )) {
          _items.removeAt(i);
          await _persist();
          continue;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (t.nextAt > now) {
          i += 1;
          continue;
        }
        try {
          final r = await _sendTask(
            t,
            baseUrlOverride: configuredBaseUrl,
          );
          if (r.statusCode >= 200 && r.statusCode < 300) {
            _items.removeAt(i);
            delivered++;
            await _persist();
            continue;
          }
          if (offlineTaskShouldDropAfterHttpFailure(
            statusCode: r.statusCode,
            rawBody: r.body,
          )) {
            _items.removeAt(i);
            await _persist();
            continue;
          }
        } catch (_) {}
        // failed
        t.retries += 1;
        if (t.retries > 10) {
          _items.removeAt(i);
          await _persist();
          continue;
        }
        // exponential backoff with jitter (base 5s, cap 60s)
        final base = 5000 * (1 << (t.retries - 1));
        final cap = 60000;
        final jitter = math.Random().nextInt(3000);
        final delay = math.min(base, cap) + jitter;
        t.nextAt = now + delay;
        await _persist();
        i += 1;
      }
    } finally {
      _flushing = false;
    }
    return delivered;
  }

  static Future<int> flushTag(
    String tag, {
    String? baseUrlOverride,
  }) async {
    final matches = _items.where((t) => t.tag == tag).map((t) => t.id).toList();
    int ok = 0;
    for (final id in matches) {
      final r = await flushOne(id, baseUrlOverride: baseUrlOverride);
      if (r) ok++;
    }
    return ok;
  }

  static Future<int> removeTag(String tag) async {
    final before = _items.length;
    _items.removeWhere((t) => t.tag == tag);
    await _persist();
    return before - _items.length;
  }

  static Future<bool> flushOne(
    String id, {
    String? baseUrlOverride,
  }) async {
    final idx = _items.indexWhere((t) => t.id == id);
    if (idx < 0) return false;
    final t = _items[idx];
    final prefs = await SharedPreferences.getInstance();
    final configuredBaseUrl = _resolvedConfiguredBaseUrl(
      prefs,
      baseUrlOverride: baseUrlOverride,
    );
    final currentScope = _currentScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    );
    _activeScope = currentScope;
    if (!_taskBelongsToScope(t, currentScope) ||
        !_taskMatchesConfiguredOrigin(
          t,
          configuredBaseUrl: configuredBaseUrl,
        )) {
      _items.removeAt(idx);
      await _persist();
      return false;
    }
    try {
      final r = await _sendTask(
        t,
        baseUrlOverride: configuredBaseUrl,
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _items.removeAt(idx);
        await _persist();
        return true;
      }
      if (offlineTaskShouldDropAfterHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        _items.removeAt(idx);
        await _persist();
        return false;
      }
    } catch (_) {}
    // schedule retry soon
    final now = DateTime.now().millisecondsSinceEpoch;
    t.retries += 1;
    t.nextAt = now + 5000;
    await _persist();
    return false;
  }

  static Future<bool> remove(String id) async {
    final idx = _items.indexWhere((t) => t.id == id);
    if (idx < 0) return false;
    _items.removeAt(idx);
    await _persist();
    return true;
  }

  static Future<void> clearPersistentState() async {
    _items = [];
    _flushing = false;
    _activeScope = _offlineQueueUnknownScope;
    if (_useSecureStore()) {
      try {
        await _offlineQueueSecureStore.delete(key: _offlineQueueSecureKey);
      } catch (_) {}
    }
    await _removeLegacyPersistence();
  }

  static bool _useSecureStore() => !kIsWeb;

  static bool _allowLegacyOfflineQueueFallback() {
    if (kIsWeb) return false;
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      if (kReleaseMode) {
        return const bool.fromEnvironment(
          'ALLOW_LEGACY_OFFLINE_QUEUE_FALLBACK_ON_MOBILE_IN_RELEASE',
          defaultValue: false,
        );
      }
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_OFFLINE_QUEUE_FALLBACK_ON_MOBILE',
        defaultValue: false,
      );
    }
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_OFFLINE_QUEUE_FALLBACK_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_OFFLINE_QUEUE_FALLBACK',
      defaultValue: true,
    );
  }

  static Future<List<OfflineTask>> _loadPersistedTasks({
    String? baseUrlOverride,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    );
    _activeScope = scope;
    var secureReadFailed = false;
    if (_useSecureStore()) {
      try {
        final raw =
            (await _offlineQueueSecureStore.read(key: _offlineQueueSecureKey) ??
                    '')
                .trim();
        if (raw.isNotEmpty) {
          final decoded = _decodeTasksFromSecureRaw(raw, scope: scope);
          if (decoded.isEmpty) {
            try {
              await _offlineQueueSecureStore.delete(
                  key: _offlineQueueSecureKey);
            } catch (_) {}
          }
          await _removeLegacyPersistence();
          return decoded;
        }
      } catch (_) {
        secureReadFailed = true;
      }
    }

    // Fail closed by default: do not trust mutable SharedPreferences queued
    // tasks unless fallback is explicitly enabled or secure storage is
    // unavailable.
    if (_useSecureStore() &&
        !_allowLegacyOfflineQueueFallback() &&
        !secureReadFailed) {
      await _removeLegacyPersistence();
      return const <OfflineTask>[];
    }

    final raw = prefs.getStringList(_offlineQueueLegacyKey) ?? const <String>[];
    final restored = _decodeTasksFromLegacyRaw(raw, scope: scope);
    if (raw.isNotEmpty && restored.isEmpty) {
      await _removeLegacyPersistence();
    }
    if (restored.isNotEmpty && _useSecureStore()) {
      _items = restored;
      await _persist();
      return List<OfflineTask>.from(restored);
    }
    return restored;
  }

  static List<OfflineTask> _decodeTasksFromSecureRaw(
    String raw, {
    required String scope,
  }) {
    final restored = <OfflineTask>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <OfflineTask>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final task = OfflineTask.fromJson(
          entry.map((k, v) => MapEntry(k.toString(), v)),
        );
        final sanitized = _sanitizeTaskHeaders(task);
        if (!offlineTaskHasReplayProtection(sanitized)) {
          continue;
        }
        if (sanitized.scope.trim().isEmpty) {
          if (_isUnknownScope(scope)) {
            restored.add(_withScope(sanitized, scope));
          }
          continue;
        }
        restored.add(sanitized);
      }
    } catch (_) {
      return const <OfflineTask>[];
    }
    return restored;
  }

  static List<OfflineTask> _decodeTasksFromLegacyRaw(
    List<String> raw, {
    required String scope,
  }) {
    if (!_isUnknownScope(scope)) {
      return const <OfflineTask>[];
    }
    final restored = <OfflineTask>[];
    for (final s in raw) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is! Map) {
          continue;
        }
        final task = OfflineTask.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
        final sanitized = _sanitizeTaskHeaders(task);
        if (!offlineTaskHasReplayProtection(sanitized)) {
          continue;
        }
        restored.add(_withScope(sanitized, scope));
      } catch (_) {}
    }
    return restored;
  }

  static Future<void> _removeLegacyPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_offlineQueueLegacyKey);
    } catch (_) {}
  }
}
