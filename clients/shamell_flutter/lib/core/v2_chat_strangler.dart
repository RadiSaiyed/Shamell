import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/base_url.dart';

enum V2ChatFlowVariant { legacy, v2 }

class V2ChatFlowBench {
  final int attempts;
  final int successes;
  final int failures;
  final int successTotalMs;

  const V2ChatFlowBench({
    this.attempts = 0,
    this.successes = 0,
    this.failures = 0,
    this.successTotalMs = 0,
  });

  bool get hasSamples => attempts > 0;

  double? get avgSuccessMs {
    if (successes <= 0) return null;
    return successTotalMs / successes;
  }

  V2ChatFlowBench register({
    required int elapsedMs,
    required bool success,
  }) {
    final ms = elapsedMs < 0 ? 0 : elapsedMs;
    return V2ChatFlowBench(
      attempts: attempts + 1,
      successes: successes + (success ? 1 : 0),
      failures: failures + (success ? 0 : 1),
      successTotalMs: successTotalMs + (success ? ms : 0),
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'attempts': attempts,
      'successes': successes,
      'failures': failures,
      'success_total_ms': successTotalMs,
    };
  }

  static V2ChatFlowBench fromJson(dynamic raw) {
    if (raw is! Map) return const V2ChatFlowBench();
    return V2ChatFlowBench(
      attempts: _asNonNegativeInt(raw['attempts']),
      successes: _asNonNegativeInt(raw['successes']),
      failures: _asNonNegativeInt(raw['failures']),
      successTotalMs: _asNonNegativeInt(raw['success_total_ms']),
    );
  }
}

class V2ChatBenchmarks {
  final V2ChatFlowBench legacy;
  final V2ChatFlowBench v2;

  const V2ChatBenchmarks({
    required this.legacy,
    required this.v2,
  });

  const V2ChatBenchmarks.empty()
      : legacy = const V2ChatFlowBench(),
        v2 = const V2ChatFlowBench();

  bool get hasAnySamples => legacy.hasSamples || v2.hasSamples;

  V2ChatBenchmarks register({
    required V2ChatFlowVariant variant,
    required int elapsedMs,
    required bool success,
  }) {
    if (variant == V2ChatFlowVariant.legacy) {
      return V2ChatBenchmarks(
        legacy: legacy.register(elapsedMs: elapsedMs, success: success),
        v2: v2,
      );
    }
    return V2ChatBenchmarks(
      legacy: legacy,
      v2: v2.register(elapsedMs: elapsedMs, success: success),
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'v': 1,
      'legacy': legacy.toJson(),
      'v2': v2.toJson(),
    };
  }

  static V2ChatBenchmarks fromJson(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const V2ChatBenchmarks.empty();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return V2ChatBenchmarks(
          legacy: V2ChatFlowBench.fromJson(decoded['legacy']),
          v2: V2ChatFlowBench.fromJson(decoded['v2']),
        );
      }
    } catch (_) {}
    return const V2ChatBenchmarks.empty();
  }
}

class V2ChatStranglerStore {
  static const String _enabledPrefKey = 'v2_chat_strangler_enabled';
  static const String _metricsPrefKey = 'v2_chat_strangler_metrics_v1';
  static const String _enabledScopedPrefKeyPrefix =
      'v2_chat_strangler_enabled.v2.';
  static const String _metricsScopedPrefKeyPrefix =
      'v2_chat_strangler_metrics.v2.';
  static const String _baseUrlPrefKey = 'base_url';
  static const String _unknownScope = 'unknown';
  static const bool _forceLegacyChat = bool.fromEnvironment(
    'SHAMELL_FORCE_LEGACY_CHAT',
    defaultValue: true,
  );
  static const String _envFlag = String.fromEnvironment(
    'V2_CHAT_STRANGLER',
    defaultValue: 'false',
  );

  static bool _parseEnabledFlag(String raw) {
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
      case 'enabled':
        return true;
      default:
        return false;
    }
  }

  static Future<bool> isEnabled({
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    if (_forceLegacyChat) {
      final legacy = prefs.getBool(_enabledPrefKey);
      if (legacy != null) {
        await prefs.remove(_enabledPrefKey);
      }
      return false;
    }
    final scope = _currentScope(prefs, baseUrlOverride: baseUrlOverride);
    final stored =
        prefs.getBool(_scopedPrefKey(_enabledScopedPrefKeyPrefix, scope));
    if (stored != null) return stored;
    final legacy = prefs.getBool(_enabledPrefKey);
    if (legacy != null) {
      await prefs.remove(_enabledPrefKey);
      if (_isUnknownScope(scope)) {
        await prefs.setBool(
          _scopedPrefKey(_enabledScopedPrefKeyPrefix, scope),
          legacy,
        );
        return legacy;
      }
    }
    return _parseEnabledFlag(_envFlag);
  }

  static Future<void> setEnabled(
    bool enabled, {
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.setBool(
      _scopedPrefKey(
        _enabledScopedPrefKeyPrefix,
        _currentScope(prefs, baseUrlOverride: baseUrlOverride),
      ),
      enabled,
    );
    await prefs.remove(_enabledPrefKey);
  }

  static Future<V2ChatBenchmarks> readBenchmarks({
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final scope = _currentScope(prefs, baseUrlOverride: baseUrlOverride);
    final raw = (prefs.getString(
              _scopedPrefKey(_metricsScopedPrefKeyPrefix, scope),
            ) ??
            '')
        .trim();
    if (raw.isNotEmpty) return V2ChatBenchmarks.fromJson(raw);
    final legacy = (prefs.getString(_metricsPrefKey) ?? '').trim();
    if (legacy.isEmpty) return const V2ChatBenchmarks.empty();
    await prefs.remove(_metricsPrefKey);
    if (_isUnknownScope(scope)) {
      await prefs.setString(
        _scopedPrefKey(_metricsScopedPrefKeyPrefix, scope),
        legacy,
      );
      return V2ChatBenchmarks.fromJson(legacy);
    }
    return const V2ChatBenchmarks.empty();
  }

  static Future<void> writeBenchmarks(
    V2ChatBenchmarks value, {
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.setString(
      _scopedPrefKey(
        _metricsScopedPrefKeyPrefix,
        _currentScope(prefs, baseUrlOverride: baseUrlOverride),
      ),
      jsonEncode(value.toJson()),
    );
    await prefs.remove(_metricsPrefKey);
  }

  static Future<void> clearBenchmarks({
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(_metricsPrefKey);
    await prefs.remove(
      _scopedPrefKey(
        _metricsScopedPrefKeyPrefix,
        _currentScope(prefs, baseUrlOverride: baseUrlOverride),
      ),
    );
  }

  static String currentBenchmarksPrefKey({
    required SharedPreferences sp,
    String? baseUrlOverride,
  }) {
    return _scopedPrefKey(
      _metricsScopedPrefKeyPrefix,
      _currentScope(sp, baseUrlOverride: baseUrlOverride),
    );
  }

  static Future<void> clearPersistedState({SharedPreferences? sp}) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(_enabledPrefKey);
    await prefs.remove(_metricsPrefKey);
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_enabledScopedPrefKeyPrefix) ||
          key.startsWith(_metricsScopedPrefKeyPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> recordSendAttempt({
    required V2ChatFlowVariant variant,
    required int elapsedMs,
    required bool success,
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    try {
      final prefs = sp ?? await SharedPreferences.getInstance();
      final prev = await readBenchmarks(
        sp: prefs,
        baseUrlOverride: baseUrlOverride,
      );
      final next = prev.register(
        variant: variant,
        elapsedMs: elapsedMs,
        success: success,
      );
      await writeBenchmarks(
        next,
        sp: prefs,
        baseUrlOverride: baseUrlOverride,
      );
    } catch (_) {}
  }

  static String formatSummary({
    required V2ChatBenchmarks benchmarks,
    required bool isArabic,
  }) {
    if (!benchmarks.hasAnySamples) {
      return isArabic
          ? 'لا توجد قياسات دردشة بعد.'
          : 'No chat diagnostics yet.';
    }
    final legacy = _flowText(
      label: isArabic ? 'الحالي' : 'current',
      value: benchmarks.legacy,
      isArabic: isArabic,
    );
    final v2 = _flowText(
      label: isArabic ? 'الآمن' : 'secure',
      value: benchmarks.v2,
      isArabic: isArabic,
    );
    if (isArabic) {
      return 'متوسط إرسال الرسائل الناجح: $legacy | $v2';
    }
    return 'Chat delivery average: $legacy | $v2';
  }

  static String _flowText({
    required String label,
    required V2ChatFlowBench value,
    required bool isArabic,
  }) {
    final avg = value.avgSuccessMs;
    final avgText = avg == null ? 'n/a' : '${avg.round()} ms';
    if (isArabic) {
      return '$label $avgText (نجاح ${value.successes}/${value.attempts})';
    }
    return '$label $avgText (ok ${value.successes}/${value.attempts})';
  }

  static String _currentScope(
    SharedPreferences prefs, {
    String? baseUrlOverride,
  }) {
    final raw =
        (baseUrlOverride ?? prefs.getString(_baseUrlPrefKey) ?? '').trim();
    final normalized = normalizeSecureApiBaseUrl(raw);
    if (normalized == null || normalized.isEmpty) return _unknownScope;
    return Uri.parse(normalized).origin;
  }

  static bool _isUnknownScope(String scope) => scope == _unknownScope;

  static String _scopedPrefKey(String prefix, String scope) => '$prefix$scope';
}

int _asNonNegativeInt(dynamic raw) {
  final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}') ?? 0;
  return value < 0 ? 0 : value;
}
