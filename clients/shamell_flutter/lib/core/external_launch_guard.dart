import 'package:url_launcher/url_launcher.dart';

const int _maxExternalDialDigits = 32;
const int _maxExternalTranslateChars = 2000;

LaunchMode shamellExternalLaunchMode(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' ||
      scheme == 'https' ||
      scheme == 'mailto' ||
      scheme == 'tel') {
    return LaunchMode.externalApplication;
  }
  return LaunchMode.platformDefault;
}

Uri? normalizeExternalMapUri({
  required double latitude,
  required double longitude,
}) {
  if (!latitude.isFinite || !longitude.isFinite) {
    return null;
  }
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return null;
  }
  final lat = latitude.toStringAsFixed(6);
  final lon = longitude.toStringAsFixed(6);
  return Uri.https('www.google.com', '/maps/search/', <String, String>{
    'api': '1',
    'query': '$lat,$lon',
  });
}

Uri? normalizeExternalDialUri(String raw) {
  final digitsOnly = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
  if (digitsOnly.isEmpty || digitsOnly.length > _maxExternalDialDigits) {
    return null;
  }
  if (!RegExp(r'^[+0-9][0-9]{2,31}$').hasMatch(digitsOnly)) {
    return null;
  }
  return Uri(scheme: 'tel', path: digitsOnly);
}

Uri? normalizeExternalTranslateUri(
  String text, {
  required String targetLanguage,
}) {
  final trimmed = text.trim();
  final normalizedLanguage = targetLanguage.trim().toLowerCase();
  if (trimmed.isEmpty || trimmed.length > _maxExternalTranslateChars) {
    return null;
  }
  if (!RegExp(r'^[a-z]{2,8}$').hasMatch(normalizedLanguage)) {
    return null;
  }
  for (final rune in trimmed.runes) {
    if ((rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) ||
        rune == 0x7F) {
      return null;
    }
  }
  return Uri.https('translate.google.com', '/', <String, String>{
    'sl': 'auto',
    'tl': normalizedLanguage,
    'text': trimmed,
  });
}
