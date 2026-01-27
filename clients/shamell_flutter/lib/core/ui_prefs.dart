import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kUiLocaleKey = 'ui.locale';
const String kUiTextScaleKey = 'ui.text_scale';
const String kUiThemeModeKey = 'ui.theme_mode';

final ValueNotifier<Locale?> uiLocale = ValueNotifier<Locale?>(null);
final ValueNotifier<double> uiTextScale = ValueNotifier<double>(1.0);
final ValueNotifier<ThemeMode> uiThemeMode =
    ValueNotifier<ThemeMode>(ThemeMode.light);

Locale? _parseUiLocale(String raw) {
  final code = raw.trim().toLowerCase();
  if (code == 'en' || code == 'ar') return Locale(code);
  return null;
}

ThemeMode _parseUiThemeMode(String raw) {
  final v = raw.trim().toLowerCase();
  switch (v) {
    case 'system':
      return ThemeMode.system;
    case 'dark':
      return ThemeMode.dark;
    case 'light':
    default:
      return ThemeMode.light;
  }
}

Future<void> loadUiPrefs() async {
  try {
    final sp = await SharedPreferences.getInstance();
    uiLocale.value = _parseUiLocale(sp.getString(kUiLocaleKey) ?? '');
    final scale = sp.getDouble(kUiTextScaleKey) ?? 1.0;
    uiTextScale.value = scale.clamp(0.85, 1.35).toDouble();
    uiThemeMode.value = _parseUiThemeMode(sp.getString(kUiThemeModeKey) ?? '');
  } catch (_) {}
}

Future<void> setUiLocaleCode(String code) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final v = code.trim().toLowerCase();
    if (v.isEmpty || v == 'system') {
      await sp.remove(kUiLocaleKey);
      uiLocale.value = null;
      return;
    }
    await sp.setString(kUiLocaleKey, v);
    uiLocale.value = _parseUiLocale(v);
  } catch (_) {}
}

Future<void> setUiTextScale(double scale) async {
  final v = scale.clamp(0.85, 1.35).toDouble();
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(kUiTextScaleKey, v);
  } catch (_) {}
  uiTextScale.value = v;
}

Future<void> setUiThemeMode(ThemeMode mode) async {
  final v = switch (mode) {
    ThemeMode.system => 'system',
    ThemeMode.dark => 'dark',
    ThemeMode.light => 'light',
  };
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kUiThemeModeKey, v);
  } catch (_) {}
  uiThemeMode.value = mode;
}
