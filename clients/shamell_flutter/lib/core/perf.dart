import 'dart:developer' as dev;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

class Perf {
  static const String _metricsRemoteLegacyKey = 'metrics_remote';
  static const String _metricsRemoteScopedKeyPrefix = 'metrics_remote.v2.';
  static const String _metricsRemoteBaseUrlPrefKey = 'base_url';
  static const String _metricsRemoteUnknownScope = 'unknown';
  static DateTime? _start;
  static int _tapCount = 0;
  static bool _remote = false;
  static String _base = '';
  static String _device = '';
  static http.Client? _httpClientForTesting;

  static void init() {
    _start = DateTime.now();
    dev.postEvent('shamell_metric', {'phase': 'init'});
  }

  static Future<bool> loadRemotePreference({
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final scope = _currentMetricsRemoteScope(
      prefs,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _metricsRemoteScopedKey(scope);
    final scoped = prefs.getBool(scopedKey);
    if (scoped != null) {
      await prefs.remove(_metricsRemoteLegacyKey);
      return scoped;
    }
    final legacy = prefs.getBool(_metricsRemoteLegacyKey);
    if (legacy != null) {
      await prefs.remove(_metricsRemoteLegacyKey);
      if (_isUnknownMetricsRemoteScope(scope)) {
        await prefs.setBool(scopedKey, legacy);
        return legacy;
      }
    }
    return false;
  }

  static Future<void> saveRemotePreference(
    bool remote, {
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.setBool(
      _metricsRemoteScopedKey(
        _currentMetricsRemoteScope(
          prefs,
          baseUrlOverride: baseUrlOverride,
        ),
      ),
      remote,
    );
    await prefs.remove(_metricsRemoteLegacyKey);
  }

  static String currentRemotePreferenceKey({
    required SharedPreferences sp,
    String? baseUrlOverride,
  }) {
    return _metricsRemoteScopedKey(
      _currentMetricsRemoteScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
  }

  static void configure(
      {required String baseUrl,
      required String deviceId,
      required bool remote}) {
    _base = normalizeSecureApiBaseUrl(baseUrl.trim()) ?? '';
    _device = deviceId;
    _remote = remote && _base.isNotEmpty;
  }

  @visibleForTesting
  static void debugReset({http.Client? httpClient}) {
    _start = null;
    _tapCount = 0;
    _remote = false;
    _base = '';
    _device = '';
    _httpClientForTesting = httpClient;
  }

  static void tap(String label) {
    _tapCount++;
    dev.postEvent('shamell_tap', {'label': label, 'count': _tapCount});
    _post('tap', {'label': label});
  }

  static void action(String label) {
    final ms = _start == null
        ? null
        : DateTime.now().difference(_start!).inMilliseconds;
    dev.postEvent('shamell_action', {
      'label': label,
      if (ms != null) 'ms_since_start': ms,
      'tap_count': _tapCount
    });
    _post('action', {'label': label, if (ms != null) 'ms': ms});
  }

  static void sample(String metric, int valueMs) {
    dev.postEvent('shamell_sample', {'metric': metric, 'value_ms': valueMs});
    _post('sample', {'metric': metric, 'value_ms': valueMs});
  }

  static Future<void> _post(String type, Map<String, dynamic> data) async {
    if (!_remote) return;
    if (_base.isEmpty) return;
    final u = secureApiChildUri(
      baseUrl: _base,
      pathSegments: const <String>['metrics'],
    );
    if (u == null) return;
    final client = _httpClientForTesting ?? shamellHttpClient();
    final closeClient = _httpClientForTesting == null;
    try {
      final body = jsonEncode({
        'type': type,
        'data': data,
        'device': _device,
        'ts': DateTime.now().toUtc().toIso8601String()
      });
      await client
          .post(u,
              headers: {
                'content-type': 'application/json',
                'X-Device-ID': _device
              },
              body: body)
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {/* best-effort, ignore */} finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  static String _currentMetricsRemoteScope(
    SharedPreferences prefs, {
    String? baseUrlOverride,
  }) {
    final raw =
        (baseUrlOverride ?? prefs.getString(_metricsRemoteBaseUrlPrefKey) ?? '')
            .trim();
    final normalized = normalizeSecureApiBaseUrl(raw);
    if (normalized == null || normalized.isEmpty) {
      return _metricsRemoteUnknownScope;
    }
    return Uri.parse(normalized).origin;
  }

  static bool _isUnknownMetricsRemoteScope(String scope) =>
      scope == _metricsRemoteUnknownScope;

  static String _metricsRemoteScopedKey(String scope) =>
      '$_metricsRemoteScopedKeyPrefix$scope';
}
