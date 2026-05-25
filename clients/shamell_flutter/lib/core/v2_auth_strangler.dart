import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/base_url.dart';

enum AuthFlowVariant { legacy, v2 }

class AuthFlowBench {
  final int attempts;
  final int successes;
  final int failures;
  final int successTotalMs;

  const AuthFlowBench({
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

  AuthFlowBench register({
    required int elapsedMs,
    required bool success,
  }) {
    final clampedMs = elapsedMs < 0 ? 0 : elapsedMs;
    return AuthFlowBench(
      attempts: attempts + 1,
      successes: successes + (success ? 1 : 0),
      failures: failures + (success ? 0 : 1),
      successTotalMs: successTotalMs + (success ? clampedMs : 0),
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

  static AuthFlowBench fromJson(dynamic raw) {
    if (raw is! Map) {
      return const AuthFlowBench();
    }
    final attempts = _asNonNegativeInt(raw['attempts']);
    final successes = _asNonNegativeInt(raw['successes']);
    final failures = _asNonNegativeInt(raw['failures']);
    final successTotalMs = _asNonNegativeInt(raw['success_total_ms']);
    return AuthFlowBench(
      attempts: attempts,
      successes: successes,
      failures: failures,
      successTotalMs: successTotalMs,
    );
  }
}

class AuthBenchmarks {
  final AuthFlowBench legacy;
  final AuthFlowBench v2;

  const AuthBenchmarks({
    required this.legacy,
    required this.v2,
  });

  const AuthBenchmarks.empty()
      : legacy = const AuthFlowBench(),
        v2 = const AuthFlowBench();

  bool get hasAnySamples => legacy.hasSamples || v2.hasSamples;

  AuthBenchmarks register({
    required AuthFlowVariant variant,
    required int elapsedMs,
    required bool success,
  }) {
    if (variant == AuthFlowVariant.legacy) {
      return AuthBenchmarks(
        legacy: legacy.register(elapsedMs: elapsedMs, success: success),
        v2: v2,
      );
    }
    return AuthBenchmarks(
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

  static AuthBenchmarks fromJson(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const AuthBenchmarks.empty();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return AuthBenchmarks(
          legacy: AuthFlowBench.fromJson(decoded['legacy']),
          v2: AuthFlowBench.fromJson(decoded['v2']),
        );
      }
    } catch (_) {}
    return const AuthBenchmarks.empty();
  }
}

class V2AuthStranglerStore {
  static const String _enabledPrefKey = 'v2_auth_strangler_enabled';
  static const String _metricsPrefKey = 'v2_auth_strangler_metrics_v1';
  static const String _enabledScopedPrefKeyPrefix =
      'v2_auth_strangler_enabled.v2.';
  static const String _metricsScopedPrefKeyPrefix =
      'v2_auth_strangler_metrics.v2.';
  static const String _baseUrlPrefKey = 'base_url';
  static const String _unknownScope = 'unknown';
  static const String _fallbackBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://api.shamell.online',
  );
  static const String _envFlag = String.fromEnvironment(
    'V2_AUTH_STRANGLER',
    defaultValue: 'true',
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

  static Future<bool> isV2AuthEnabled({SharedPreferences? sp}) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final scopedKey = _scopedPrefKey(
      _enabledScopedPrefKeyPrefix,
      _currentScope(prefs),
    );
    final stored = prefs.getBool(scopedKey);
    if (stored != null) return stored;
    final legacy = prefs.getBool(_enabledPrefKey);
    if (legacy != null) {
      await prefs.remove(_enabledPrefKey);
      if (_isUnknownScope(_currentScope(prefs))) {
        await prefs.setBool(scopedKey, legacy);
        return legacy;
      }
    }
    return _parseEnabledFlag(_envFlag);
  }

  static Future<void> setV2AuthEnabled(
    bool enabled, {
    SharedPreferences? sp,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.setBool(
      _scopedPrefKey(_enabledScopedPrefKeyPrefix, _currentScope(prefs)),
      enabled,
    );
    await prefs.remove(_enabledPrefKey);
  }

  static Future<String> resolveBaseUrl({SharedPreferences? sp}) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final rawStored = (prefs.getString(_baseUrlPrefKey) ?? '').trim();
    final stored = normalizeSecureApiBaseUrl(rawStored);
    if (stored != null) return stored;
    if (rawStored.isNotEmpty) {
      try {
        await prefs.remove(_baseUrlPrefKey);
      } catch (_) {}
      return '';
    }
    final fallback = normalizeSecureApiBaseUrl(_fallbackBaseUrl.trim()) ??
        'https://api.shamell.online';
    if (fallback.isNotEmpty) {
      try {
        await prefs.setString(_baseUrlPrefKey, fallback);
      } catch (_) {}
    }
    return fallback;
  }

  static Future<AuthBenchmarks> readBenchmarks({
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final scope = _currentScope(prefs, baseUrlOverride: baseUrlOverride);
    final encoded = (prefs.getString(
              _scopedPrefKey(_metricsScopedPrefKeyPrefix, scope),
            ) ??
            '')
        .trim();
    if (encoded.isNotEmpty) return AuthBenchmarks.fromJson(encoded);
    final legacy = (prefs.getString(_metricsPrefKey) ?? '').trim();
    if (legacy.isEmpty) return const AuthBenchmarks.empty();
    await prefs.remove(_metricsPrefKey);
    if (_isUnknownScope(scope)) {
      await prefs.setString(
        _scopedPrefKey(_metricsScopedPrefKeyPrefix, scope),
        legacy,
      );
      return AuthBenchmarks.fromJson(legacy);
    }
    return const AuthBenchmarks.empty();
  }

  static Future<void> writeBenchmarks(
    AuthBenchmarks benchmarks, {
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.setString(
      _scopedPrefKey(
        _metricsScopedPrefKeyPrefix,
        _currentScope(prefs, baseUrlOverride: baseUrlOverride),
      ),
      jsonEncode(benchmarks.toJson()),
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

  static Future<void> clearEnabledOverride({SharedPreferences? sp}) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    await prefs.remove(_enabledPrefKey);
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_enabledScopedPrefKeyPrefix)) {
        await prefs.remove(key);
      }
    }
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
    await clearEnabledOverride(sp: prefs);
    await prefs.remove(_metricsPrefKey);
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_metricsScopedPrefKeyPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> recordAuthAttempt({
    required AuthFlowVariant variant,
    required int elapsedMs,
    required bool success,
    SharedPreferences? sp,
    String? baseUrlOverride,
  }) async {
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
  }

  static String formatBenchmarkLine({
    required AuthBenchmarks benchmarks,
    required bool isArabic,
  }) {
    if (!benchmarks.hasAnySamples) {
      return isArabic
          ? 'لا توجد قياسات تسجيل دخول بعد.'
          : 'No sign-in diagnostics yet.';
    }

    final legacyPart = _flowSummary(
      label: isArabic ? 'الحالي' : 'current',
      value: benchmarks.legacy,
      isArabic: isArabic,
    );
    final v2Part = _flowSummary(
      label: isArabic ? 'الآمن' : 'secure',
      value: benchmarks.v2,
      isArabic: isArabic,
    );

    if (isArabic) {
      return 'متوسط تسجيل الدخول الناجح: $legacyPart | $v2Part';
    }
    return 'Sign-in success average: $legacyPart | $v2Part';
  }

  static String _flowSummary({
    required String label,
    required AuthFlowBench value,
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
        (baseUrlOverride ?? (prefs.getString(_baseUrlPrefKey) ?? '')).trim();
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
