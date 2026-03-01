import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration _offlineQueueRequestTimeout = Duration(seconds: 10);

// Never persist authentication material in SharedPreferences.
const Set<String> _offlineSensitiveHeaders = <String>{
  'cookie',
  'authorization',
  'set-cookie',
  'x-chat-device-token',
  'x-internal-secret',
  'x-bus-payments-internal-secret',
};

@visibleForTesting
bool isOfflineSensitiveHeader(String name) =>
    _offlineSensitiveHeaders.contains(name.trim().toLowerCase());

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
        headers: (j['headers'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        body: j['body'],
        tag: j['tag'] ?? 'misc',
        createdAt: j['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        retries: j['retries'] ?? 0,
        nextAt: j['nextAt'] ?? 0,
      );
}

class OfflineQueue {
  static final _key = 'offline_queue_v1';
  static List<OfflineTask> _items = [];
  static bool _flushing = false;

  static OfflineTask _copyWithHeaders(
    OfflineTask t,
    Map<String, String> headers,
  ) {
    return OfflineTask(
      id: t.id,
      method: t.method,
      url: t.url,
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

  static Future<Map<String, String>> _effectiveHeadersForTask(
      OfflineTask t) async {
    final out = sanitizeOfflineHeadersForStorage(t.headers);
    final base = offlineAuthBaseFromTaskUrl(t.url);
    if (base != null) {
      try {
        final cookie = await getSessionCookieHeader(base);
        if (cookie != null && cookie.isNotEmpty) {
          out['cookie'] = cookie;
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<http.Response> _sendTask(OfflineTask t) async {
    final uri = Uri.parse(t.url);
    final headers = await _effectiveHeadersForTask(t);
    switch (t.method.toUpperCase()) {
      case 'POST':
        return http
            .post(uri, headers: headers, body: t.body)
            .timeout(_offlineQueueRequestTimeout);
      case 'PUT':
        return http
            .put(uri, headers: headers, body: t.body)
            .timeout(_offlineQueueRequestTimeout);
      case 'PATCH':
        return http
            .patch(uri, headers: headers, body: t.body)
            .timeout(_offlineQueueRequestTimeout);
      case 'DELETE':
        return http
            .delete(uri, headers: headers, body: t.body)
            .timeout(_offlineQueueRequestTimeout);
      default:
        return http
            .post(uri, headers: headers, body: t.body)
            .timeout(_offlineQueueRequestTimeout);
    }
  }

  static Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList(_key) ?? [];
      final restored = <OfflineTask>[];
      var normalized = false;
      for (final s in raw) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is! Map) {
            normalized = true;
            continue;
          }
          final task = OfflineTask.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
          final sanitized = _sanitizeTaskHeaders(task);
          if (!identical(task, sanitized)) {
            normalized = true;
          }
          restored.add(sanitized);
        } catch (_) {
          normalized = true;
        }
      }
      _items = restored;
      if (normalized) {
        await _persist();
      }
    } catch (_) {
      _items = [];
    }
  }

  static List<OfflineTask> pending({String? tag}) {
    return List.unmodifiable(
        tag == null ? _items : _items.where((t) => t.tag == tag));
  }

  static Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(
          _key, _items.map((t) => jsonEncode(t.toJson())).toList());
    } catch (_) {}
  }

  static Future<void> enqueue(OfflineTask t) async {
    // initialize nextAt to now for first attempt
    final queued = _sanitizeTaskHeaders(t);
    queued.nextAt = DateTime.now().millisecondsSinceEpoch;
    _items.add(queued);
    await _persist();
  }

  static Future<int> flush() async {
    if (_flushing || _items.isEmpty) return 0;
    _flushing = true;
    int delivered = 0;
    try {
      // Simple sequential flush
      for (int i = 0; i < _items.length;) {
        final t = _items[i];
        final now = DateTime.now().millisecondsSinceEpoch;
        if (t.nextAt > now) {
          i += 1;
          continue;
        }
        try {
          final r = await _sendTask(t);
          if (r.statusCode >= 200 && r.statusCode < 300) {
            _items.removeAt(i);
            delivered++;
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

  static Future<int> flushTag(String tag) async {
    final matches = _items.where((t) => t.tag == tag).map((t) => t.id).toList();
    int ok = 0;
    for (final id in matches) {
      final r = await flushOne(id);
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

  static Future<bool> flushOne(String id) async {
    final idx = _items.indexWhere((t) => t.id == id);
    if (idx < 0) return false;
    final t = _items[idx];
    try {
      final r = await _sendTask(t);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _items.removeAt(idx);
        await _persist();
        return true;
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
}
