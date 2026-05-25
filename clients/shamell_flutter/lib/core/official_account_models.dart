import 'package:flutter/foundation.dart';

import 'base_url.dart'
    show isLocalNetworkHost, isLocalhostHost, normalizeSecureApiBaseUrl;

@visibleForTesting
String? normalizeOfficialRemoteHttpUrlForRuntime(
  Object? raw, {
  required bool releaseMode,
}) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty || text.length > 2048) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final scheme = uri.scheme.trim().toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  if (uri.host.trim().isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (scheme == 'http') {
    final host = uri.host.trim().toLowerCase();
    if (isLocalhostHost(host)) {
      return uri.toString();
    }
    if (releaseMode || !isLocalNetworkHost(host)) {
      return null;
    }
  }
  return uri.replace(scheme: scheme).toString();
}

String? _normalizeOfficialRemoteHttpUrl(Object? raw) =>
    normalizeOfficialRemoteHttpUrlForRuntime(
      raw,
      releaseMode: kReleaseMode,
    );

String? normalizeOfficialRemoteImageUrl(Object? raw) =>
    _normalizeOfficialRemoteHttpUrl(raw);

@visibleForTesting
String? normalizeOfficialRemoteImageUrlForAutoloadRuntime(
  Object? raw, {
  required String baseUrl,
  required bool releaseMode,
}) {
  final normalized = normalizeOfficialRemoteHttpUrlForRuntime(
    raw,
    releaseMode: releaseMode,
  );
  if (normalized == null) return null;
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (normalizedBase == null || normalizedBase.isEmpty) return null;
  final imageUri = Uri.tryParse(normalized);
  final baseUri = Uri.tryParse(normalizedBase);
  if (imageUri == null || baseUri == null) return null;
  final imageScheme = imageUri.scheme.toLowerCase();
  final baseScheme = baseUri.scheme.toLowerCase();
  final imageHost = imageUri.host.toLowerCase();
  final baseHost = baseUri.host.toLowerCase();
  final imagePort =
      imageUri.hasPort ? imageUri.port : (imageScheme == 'https' ? 443 : 80);
  final basePort =
      baseUri.hasPort ? baseUri.port : (baseScheme == 'https' ? 443 : 80);
  final sameOrigin = imageScheme == baseScheme &&
      imageHost == baseHost &&
      imagePort == basePort;
  if (!sameOrigin) return null;
  return normalized;
}

String? normalizeOfficialRemoteImageUrlForAutoload(
  Object? raw, {
  required String baseUrl,
}) =>
    normalizeOfficialRemoteImageUrlForAutoloadRuntime(
      raw,
      baseUrl: baseUrl,
      releaseMode: kReleaseMode,
    );

String? normalizeOfficialRemoteWebsiteUrl(Object? raw) =>
    _normalizeOfficialRemoteHttpUrl(raw);

String? normalizeOfficialQrPayload(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty || text.length > 1024) return null;
  for (final unit in text.codeUnits) {
    if (unit < 0x20 || unit == 0x7F) return null;
  }
  return text;
}

class OfficialAccountHandle {
  final String id;
  final String kind;
  final String name;
  final String? description;
  final String? avatarUrl;
  final bool verified;
  final bool featured;
  final String? chatPeerId;
  final String? moduleAppId;
  final String? category;
  final String? city;
  final String? address;
  final String? openingHours;
  final String? websiteUrl;
  final String? qrPayload;
  final bool followed;

  const OfficialAccountHandle({
    required this.id,
    required this.kind,
    required this.name,
    this.description,
    this.avatarUrl,
    this.verified = false,
    this.featured = false,
    this.chatPeerId,
    this.moduleAppId,
    this.category,
    this.city,
    this.address,
    this.openingHours,
    this.websiteUrl,
    this.qrPayload,
    this.followed = false,
  });

  factory OfficialAccountHandle.fromJson(Map<String, dynamic> j) {
    final rawChatId = (j['chat_peer_id'] ?? '').toString().trim();
    return OfficialAccountHandle(
      id: (j['id'] ?? '').toString(),
      kind: (j['kind'] ?? 'service').toString(),
      name: (j['name'] ?? '').toString(),
      description: (j['description'] ?? '').toString().trim().isEmpty
          ? null
          : (j['description'] ?? '').toString(),
      avatarUrl: normalizeOfficialRemoteImageUrl(j['avatar_url']),
      verified: (j['verified'] as bool?) ?? false,
      featured: (j['featured'] as bool?) ?? false,
      chatPeerId: rawChatId.isEmpty ? null : rawChatId,
      moduleAppId: _officialMiniProgramId(j),
      category: (j['category'] ?? '').toString().trim().isEmpty
          ? null
          : (j['category'] ?? '').toString(),
      city: (j['city'] ?? '').toString().trim().isEmpty
          ? null
          : (j['city'] ?? '').toString(),
      address: (j['address'] ?? '').toString().trim().isEmpty
          ? null
          : (j['address'] ?? '').toString(),
      openingHours: (j['opening_hours'] ?? '').toString().trim().isEmpty
          ? null
          : (j['opening_hours'] ?? '').toString(),
      websiteUrl: normalizeOfficialRemoteWebsiteUrl(j['website_url']),
      qrPayload: normalizeOfficialQrPayload(j['qr_payload']),
      followed: (j['followed'] as bool?) ?? false,
    );
  }
}

String? _officialMiniProgramId(Map<String, dynamic> raw) {
  for (final key in const <String>[
    'mini_program_id',
    'module_app_id',
    'mini_app_id',
    'app_id',
  ]) {
    final value = (raw[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}
