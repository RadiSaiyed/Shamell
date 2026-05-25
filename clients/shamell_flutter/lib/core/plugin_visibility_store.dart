import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

const String _pluginVisibilityScopedKeyPrefix = 'plugin_visibility.v2.';
const String _pluginVisibilityUnknownScope = 'unknown';

Future<bool> loadScopedPluginVisibilityPreference({
  required String key,
  required bool fallback,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _pluginVisibilityScope(
    baseUrlOverride ?? (prefs.getString('base_url') ?? ''),
  );
  final scoped = prefs.getBool(_scopedPluginVisibilityKey(key, scope));
  if (scoped != null) {
    await prefs.remove(key);
    return scoped;
  }

  final legacy = prefs.getBool(key);
  if (legacy == null) return fallback;

  await prefs.remove(key);
  if (_isUnknownPluginVisibilityScope(scope)) {
    await prefs.setBool(_scopedPluginVisibilityKey(key, scope), legacy);
    return legacy;
  }
  return fallback;
}

Future<void> saveScopedPluginVisibilityPreference({
  required String key,
  required bool value,
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _pluginVisibilityScope(
    baseUrlOverride ?? (prefs.getString('base_url') ?? ''),
  );
  await prefs.setBool(_scopedPluginVisibilityKey(key, scope), value);
  await prefs.remove(key);
}

String currentScopedPluginVisibilityPrefKey({
  required String key,
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final scope = _pluginVisibilityScope(
    baseUrlOverride ?? (sp.getString('base_url') ?? ''),
  );
  return _scopedPluginVisibilityKey(key, scope);
}

String _pluginVisibilityScope(String rawBaseUrl) {
  final normalized = normalizeSecureApiBaseUrl(rawBaseUrl.trim()) ?? '';
  if (normalized.isEmpty) return _pluginVisibilityUnknownScope;
  return Uri.parse(normalized).origin;
}

bool _isUnknownPluginVisibilityScope(String scope) =>
    scope == _pluginVisibilityUnknownScope;

String _scopedPluginVisibilityKey(String key, String scope) =>
    '$_pluginVisibilityScopedKeyPrefix$key@$scope';
