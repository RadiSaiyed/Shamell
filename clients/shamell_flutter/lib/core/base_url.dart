// Shared validation helpers for API base URLs.
//
// Security best practice:
// - Never send authentication material over plaintext transports.
// - In release builds, allow `http://` only for explicit localhost.
// - In non-release builds, also allow local-network dev hosts.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'base_url_transport_stub.dart'
    if (dart.library.html) 'base_url_transport_web.dart'
    if (dart.library.io) 'base_url_transport_io.dart' as transport;

const String _trustedApiOriginsDefine = String.fromEnvironment(
  'TRUSTED_API_ORIGINS',
  defaultValue: '',
);
const String _fallbackTrustedApiBaseUrlDefine = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'https://api.shamell.online',
);
const String _trustedTlsCertificatesDerBase64Define = String.fromEnvironment(
  'TRUSTED_TLS_CERTIFICATES_DER_BASE64',
  defaultValue: '',
);
const bool _allowLocalhostHttpInReleaseDefine = bool.fromEnvironment(
  'ALLOW_LOCALHOST_HTTP_IN_RELEASE',
  defaultValue: false,
);

bool isLocalhostHost(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1';
}

bool _isPrivateIpv4Host(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return false;
    octets.add(n);
  }
  final a = octets[0];
  final b = octets[1];
  if (a == 10) return true; // 10.0.0.0/8
  if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  if (a == 192 && b == 168) return true; // 192.168.0.0/16
  if (a == 169 && b == 254) return true; // Link-local
  return false;
}

bool isLocalNetworkHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  if (isLocalhostHost(h)) return true;
  if (_isPrivateIpv4Host(h)) return true;
  // Common mDNS hostname pattern on local networks (for example: my-mac.local).
  return h.endsWith('.local');
}

Uri? parseApiBaseUrl(String baseUrl) {
  final raw = baseUrl.trim();
  if (raw.isEmpty) return null;
  final u = Uri.tryParse(raw);
  if (u == null) return null;
  final scheme = u.scheme.trim().toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  if (u.host.trim().isEmpty) return null;
  if (u.userInfo.trim().isNotEmpty) return null;
  if (u.query.trim().isNotEmpty) return null;
  if (u.fragment.trim().isNotEmpty) return null;
  if (u.path.isNotEmpty && u.path != '/') return null;
  if (u.hasPort && (u.port <= 0 || u.port > 65535)) return null;
  return u.replace(
    scheme: scheme,
    path: '',
    query: null,
    fragment: null,
  );
}

String _canonicalApiOrigin(Uri uri) {
  final scheme = uri.scheme.trim().toLowerCase();
  final host = uri.host.trim().toLowerCase();
  final defaultPort = scheme == 'https' ? 443 : 80;
  final needsPort = uri.hasPort && uri.port != defaultPort;
  if (needsPort) {
    return '$scheme://$host:${uri.port}';
  }
  return '$scheme://$host';
}

@visibleForTesting
List<String> shamellTrustedApiOriginsForRelease({
  String? trustedOriginsRaw,
  String? fallbackBaseUrl,
}) {
  final allowed = <String>{};

  void addCandidates(String raw) {
    final normalizedRaw = raw.trim();
    if (normalizedRaw.isEmpty) return;
    for (final part in normalizedRaw.split(RegExp(r'[\s,]+'))) {
      final candidate = parseApiBaseUrl(part);
      if (candidate == null) continue;
      if (candidate.scheme.trim().toLowerCase() != 'https') continue;
      allowed.add(_canonicalApiOrigin(candidate));
    }
  }

  addCandidates(trustedOriginsRaw ?? _trustedApiOriginsDefine);
  addCandidates(fallbackBaseUrl ?? _fallbackTrustedApiBaseUrlDefine);
  if (allowed.isEmpty) {
    addCandidates('https://api.shamell.online');
  }
  return allowed.toList(growable: false);
}

@visibleForTesting
bool shamellIsTrustedReleaseApiBaseUri(
  Uri uri, {
  String? trustedOriginsRaw,
  String? fallbackBaseUrl,
  bool? allowLocalhostHttpInRelease,
}) {
  final scheme = uri.scheme.trim().toLowerCase();
  final host = uri.host.trim().toLowerCase();
  final allowLocalhostHttpInReleaseValue =
      allowLocalhostHttpInRelease ?? _allowLocalhostHttpInReleaseDefine;
  if (scheme == 'http') {
    return allowLocalhostHttpInReleaseValue && isLocalhostHost(host);
  }
  if (scheme != 'https') return false;
  final allowed = shamellTrustedApiOriginsForRelease(
    trustedOriginsRaw: trustedOriginsRaw,
    fallbackBaseUrl: fallbackBaseUrl,
  );
  return allowed.contains(_canonicalApiOrigin(uri));
}

@visibleForTesting
String? normalizeSecureApiBaseUrlForRuntime(
  String baseUrl, {
  required bool releaseMode,
  String? trustedOriginsRaw,
  String? fallbackBaseUrl,
  bool? allowLocalhostHttpInRelease,
}) {
  final u = parseApiBaseUrl(baseUrl);
  if (u == null) return null;
  final scheme = u.scheme.trim().toLowerCase();
  final host = u.host.trim().toLowerCase();
  if (scheme == 'https') {
    if (releaseMode &&
        !shamellIsTrustedReleaseApiBaseUri(
          u,
          trustedOriginsRaw: trustedOriginsRaw,
          fallbackBaseUrl: fallbackBaseUrl,
          allowLocalhostHttpInRelease: allowLocalhostHttpInRelease,
        )) {
      return null;
    }
    return u.toString();
  }
  if (scheme != 'http') return null;
  if (releaseMode) {
    final allowLocalhostHttpInReleaseValue =
        allowLocalhostHttpInRelease ?? _allowLocalhostHttpInReleaseDefine;
    if (!allowLocalhostHttpInReleaseValue) return null;
    return isLocalhostHost(host) ? u.toString() : null;
  }
  if (isLocalhostHost(host)) return u.toString();
  return isLocalNetworkHost(host) ? u.toString() : null;
}

String? normalizeSecureApiBaseUrl(String baseUrl) {
  return normalizeSecureApiBaseUrlForRuntime(
    baseUrl,
    releaseMode: kReleaseMode,
  );
}

bool isSecureApiBaseUrl(String baseUrl) {
  return normalizeSecureApiBaseUrl(baseUrl) != null;
}

@visibleForTesting
List<Uint8List> shamellTrustedTlsCertificatesDerForRuntime({
  String? trustedTlsCertificatesDerBase64,
}) {
  final raw = (trustedTlsCertificatesDerBase64 ??
          _trustedTlsCertificatesDerBase64Define)
      .trim();
  if (raw.isEmpty) {
    return const <Uint8List>[];
  }
  final certificates = <Uint8List>[];
  for (final part in raw.split(';')) {
    final entry = part.trim();
    if (entry.isEmpty) {
      continue;
    }
    certificates.add(base64Decode(base64.normalize(entry)));
  }
  return certificates;
}

int shamellTrustedTlsCertificateCountForRuntime({
  String? trustedTlsCertificatesDerBase64,
}) {
  return shamellTrustedTlsCertificatesDerForRuntime(
    trustedTlsCertificatesDerBase64: trustedTlsCertificatesDerBase64,
  ).length;
}

/// Central seam for mobile transport hardening.
///
/// Release mobile builds now fail closed unless a pinned trust bundle is
/// injected with `TRUSTED_TLS_CERTIFICATES_DER_BASE64`.
http.Client shamellHttpClient({
  bool? releaseModeOverride,
  String? trustedTlsCertificatesDerBase64,
}) {
  return transport.createShamellHttpClient(
    releaseMode: releaseModeOverride ?? kReleaseMode,
    trustedTlsCertificatesDer: shamellTrustedTlsCertificatesDerForRuntime(
      trustedTlsCertificatesDerBase64: trustedTlsCertificatesDerBase64,
    ),
  );
}

WebSocketChannel shamellConnectWebSocket(
  Uri wsUri, {
  Map<String, String> headers = const <String, String>{},
  bool failWithoutHeadersOnIo = true,
  bool? releaseModeOverride,
  String? trustedTlsCertificatesDerBase64,
}) {
  return transport.connectShamellWebSocket(
    wsUri,
    headers: headers,
    failWithoutHeadersOnIo: failWithoutHeadersOnIo,
    releaseMode: releaseModeOverride ?? kReleaseMode,
    trustedTlsCertificatesDer: shamellTrustedTlsCertificatesDerForRuntime(
      trustedTlsCertificatesDerBase64: trustedTlsCertificatesDerBase64,
    ),
  );
}

String? preferredConfiguredApiBaseUrl({
  required String storedBaseUrl,
  required String fallbackBaseUrl,
  bool releaseMode = kReleaseMode,
}) {
  final normalizedFallback = normalizeSecureApiBaseUrl(fallbackBaseUrl.trim());
  final normalizedStored = normalizeSecureApiBaseUrl(storedBaseUrl.trim());
  if (normalizedStored != null) {
    if (normalizedFallback != null) {
      final fallbackHost = Uri.tryParse(normalizedFallback)?.host ?? '';
      final storedHost = Uri.tryParse(normalizedStored)?.host ?? '';
      final hasReachableFallback =
          normalizedFallback.isNotEmpty && !isLocalhostHost(fallbackHost);
      if (releaseMode && hasReachableFallback && isLocalhostHost(storedHost)) {
        return normalizedFallback;
      }
    }
    return normalizedStored;
  }
  return normalizedFallback;
}

String? configuredApiBaseUrlOrFallbackIfUnset({
  required String storedBaseUrl,
  required String fallbackBaseUrl,
}) {
  final rawStored = storedBaseUrl.trim();
  if (rawStored.isNotEmpty) {
    return normalizeSecureApiBaseUrl(rawStored);
  }
  return normalizeSecureApiBaseUrl(fallbackBaseUrl.trim());
}

Uri? secureApiChildUri({
  required String baseUrl,
  required List<String> pathSegments,
  Map<String, String>? queryParameters,
}) {
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (normalizedBase == null) return null;
  final baseUri = Uri.tryParse(normalizedBase);
  if (baseUri == null) return null;
  final cleanSegments = <String>[];
  for (final segment in pathSegments) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return null;
    cleanSegments.add(trimmed);
  }
  return baseUri.replace(
    pathSegments: <String>[
      ...baseUri.pathSegments.where((segment) => segment.trim().isNotEmpty),
      ...cleanSegments,
    ],
    queryParameters: queryParameters == null || queryParameters.isEmpty
        ? null
        : queryParameters,
    fragment: null,
  );
}
