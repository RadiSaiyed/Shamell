import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../base_url.dart';
import '../shamell_user_id.dart';

const String _coachSavedViewPinScopedPrefKeyPrefix =
    'coach.ops.saved_view_pins.v1.';

Future<Set<String>> loadCoachSavedViewPinnedIds({
  required String baseUrl,
  required String collectionKey,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachSavedViewPinScopedPrefKey(
    baseUrl: baseUrl,
    collectionKey: collectionKey,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return const <String>{};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <String>{};
    }
    return decoded
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
  } catch (_) {
    return const <String>{};
  }
}

Future<Set<String>> setCoachSavedViewPinned({
  required String baseUrl,
  required String collectionKey,
  required String viewId,
  required bool pinned,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
  int maxEntries = 32,
}) async {
  final normalizedViewId = viewId.trim();
  if (normalizedViewId.isEmpty) {
    return const <String>{};
  }
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachSavedViewPinScopedPrefKey(
    baseUrl: baseUrl,
    collectionKey: collectionKey,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final nextPins = <String>{
    ...await loadCoachSavedViewPinnedIds(
      baseUrl: baseUrl,
      collectionKey: collectionKey,
      sp: prefs,
      shamellUserIdOverride: shamellUserIdOverride,
    ),
  };
  if (pinned) {
    nextPins.add(normalizedViewId);
  } else {
    nextPins.remove(normalizedViewId);
  }
  final encodedPins = nextPins.toList(growable: false)
    ..sort((left, right) => left.compareTo(right));
  final trimmedPins = encodedPins.take(maxEntries).toSet();
  await prefs.setString(key, jsonEncode(trimmedPins.toList(growable: false)));
  return trimmedPins;
}

Future<String> _coachSavedViewPinScopedPrefKey({
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
  return '$_coachSavedViewPinScopedPrefKeyPrefix$suffix';
}
