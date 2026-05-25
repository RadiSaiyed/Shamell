import 'base_url.dart';

String? _activeRuntimeBaseUrl;
const String _runtimeFallbackBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'https://api.shamell.online',
);

String? shamellNormalizeRuntimeBaseUrl(String? rawBaseUrl) {
  final normalized = normalizeSecureApiBaseUrl((rawBaseUrl ?? '').trim());
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

void shamellSetActiveRuntimeBaseUrl(String? baseUrl) {
  _activeRuntimeBaseUrl = shamellNormalizeRuntimeBaseUrl(baseUrl);
}

String? shamellGetActiveRuntimeBaseUrl() => _activeRuntimeBaseUrl;

String shamellResolveRuntimeBaseUrl({
  required String storedBaseUrl,
  String? activeBaseUrl,
}) {
  final normalizedActive = shamellNormalizeRuntimeBaseUrl(activeBaseUrl);
  if (normalizedActive != null) return normalizedActive;
  final normalizedStored = shamellNormalizeRuntimeBaseUrl(storedBaseUrl);
  if (normalizedStored != null) return normalizedStored;
  final normalizedFallback =
      shamellNormalizeRuntimeBaseUrl(_runtimeFallbackBaseUrl);
  if (normalizedFallback != null) return normalizedFallback;
  return 'https://api.shamell.online';
}
