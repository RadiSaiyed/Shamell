import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/base_url.dart';

const String _currencySymbolLegacyKey = 'currency_symbol';
const String _currencySymbolScopedKeyPrefix = 'currency_symbol.v2.';
const String _currencySymbolUnknownScope = 'unknown';

Future<String?> loadStoredCurrencySymbol({
  required String baseUrl,
  SharedPreferences? sp,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _currencySymbolScope(baseUrl);
  final scoped =
      (prefs.getString(_currencySymbolScopedKey(scope)) ?? '').trim();
  if (scoped.isNotEmpty) {
    await prefs.remove(_currencySymbolLegacyKey);
    return scoped;
  }

  final legacy = (prefs.getString(_currencySymbolLegacyKey) ?? '').trim();
  if (legacy.isEmpty) return null;

  await prefs.remove(_currencySymbolLegacyKey);
  if (_isUnknownCurrencySymbolScope(scope)) {
    await prefs.setString(_currencySymbolScopedKey(scope), legacy);
    return legacy;
  }
  return null;
}

Future<bool> saveStoredCurrencySymbol(
  String symbol, {
  required String baseUrl,
  SharedPreferences? sp,
}) async {
  final normalized = symbol.trim();
  if (normalized.isEmpty) {
    return clearStoredCurrencySymbol(baseUrl: baseUrl, sp: sp);
  }

  final prefs = sp ?? await SharedPreferences.getInstance();
  try {
    await prefs.setString(
      _currencySymbolScopedKey(_currencySymbolScope(baseUrl)),
      normalized,
    );
    await prefs.remove(_currencySymbolLegacyKey);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> clearStoredCurrencySymbol({
  required String baseUrl,
  SharedPreferences? sp,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  try {
    await prefs.remove(_currencySymbolScopedKey(_currencySymbolScope(baseUrl)));
    await prefs.remove(_currencySymbolLegacyKey);
    return true;
  } catch (_) {
    return false;
  }
}

String _currencySymbolScope(String baseUrl) {
  final normalized = normalizeSecureApiBaseUrl(baseUrl.trim()) ?? '';
  if (normalized.isEmpty) return _currencySymbolUnknownScope;
  return Uri.parse(normalized).origin;
}

bool _isUnknownCurrencySymbolScope(String scope) =>
    scope == _currencySymbolUnknownScope;

String _currencySymbolScopedKey(String scope) =>
    '$_currencySymbolScopedKeyPrefix$scope';
