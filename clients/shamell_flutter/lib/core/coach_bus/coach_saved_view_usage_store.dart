import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../base_url.dart';
import '../shamell_user_id.dart';

const String _coachSavedViewUsageScopedPrefKeyPrefix =
    'coach.ops.saved_view_usage.v1.';

Future<Map<String, String>> loadCoachSavedViewUsageMap({
  required String baseUrl,
  required String collectionKey,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachSavedViewUsageScopedPrefKey(
    baseUrl: baseUrl,
    collectionKey: collectionKey,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return const <String, String>{};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const <String, String>{};
    }
    final usage = <String, String>{};
    decoded.forEach((rawViewId, rawUsedAtIso) {
      final viewId = rawViewId.toString().trim();
      final usedAtIso = _normalizeRfc3339OrNull(rawUsedAtIso?.toString());
      if (viewId.isEmpty || usedAtIso == null) {
        return;
      }
      usage[viewId] = usedAtIso;
    });
    return usage;
  } catch (_) {
    return const <String, String>{};
  }
}

Future<Map<String, String>> markCoachSavedViewUsed({
  required String baseUrl,
  required String collectionKey,
  required String viewId,
  String? usedAtIso,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
  int maxEntries = 32,
}) async {
  final normalizedViewId = viewId.trim();
  if (normalizedViewId.isEmpty) {
    return const <String, String>{};
  }
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachSavedViewUsageScopedPrefKey(
    baseUrl: baseUrl,
    collectionKey: collectionKey,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existing = <String, String>{
    ...await loadCoachSavedViewUsageMap(
      baseUrl: baseUrl,
      collectionKey: collectionKey,
      sp: prefs,
      shamellUserIdOverride: shamellUserIdOverride,
    ),
  };
  final normalizedUsedAtIso = _normalizeRfc3339OrNull(usedAtIso) ??
      DateTime.now().toUtc().toIso8601String().replaceFirst('.000Z', 'Z');
  existing[normalizedViewId] = normalizedUsedAtIso;
  final rankedEntries = existing.entries.toList(growable: false)
    ..sort((left, right) => right.value.compareTo(left.value));
  final trimmed = <String, String>{
    for (final entry in rankedEntries.take(maxEntries))
      entry.key.trim(): entry.value,
  };
  await prefs.setString(key, jsonEncode(trimmed));
  return trimmed;
}

Future<String> _coachSavedViewUsageScopedPrefKey({
  required String baseUrl,
  required String collectionKey,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final userId =
      (shamellUserIdOverride ?? await loadShamellUserId(sp: sp) ?? '').trim();
  final normalizedBaseUrl =
      normalizeSecureApiBaseUrl(baseUrl) ?? baseUrl.trim();
  final scope =
      '$normalizedBaseUrl::${userId.isEmpty ? "anon" : userId}::${collectionKey.trim()}';
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachSavedViewUsageScopedPrefKeyPrefix$suffix';
}

String? _normalizeRfc3339OrNull(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) {
    return null;
  }
  return parsed.toUtc().toIso8601String().replaceFirst('.000Z', 'Z');
}
