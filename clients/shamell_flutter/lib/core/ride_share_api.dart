// Cycle 160 — Trip-share token client.
//
// Pairs with the BFF endpoints:
//   POST /me/rides/trips/:ride_id/share         — mint a token
//   POST /me/rides/trips/:ride_id/share/revoke  — revoke all active
//   GET  /shared/rides/:token                   — public (no auth)
//
// The mint response includes a `share_url` the rider hands to
// family/friends. We expose the raw token + url so the dialog
// can offer both a QR fallback and the native share intent.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class RideShareToken {
  final String token;
  final String rideId;
  final String? label;
  final String createdAt;
  final String expiresAt;
  final String shareUrl;

  const RideShareToken({
    required this.token,
    required this.rideId,
    this.label,
    required this.createdAt,
    required this.expiresAt,
    required this.shareUrl,
  });

  factory RideShareToken.fromJson(Map<String, dynamic> json) {
    return RideShareToken(
      token: (json['token'] as String?) ?? '',
      rideId: (json['ride_id'] as String?) ?? '',
      label: json['label'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      expiresAt: (json['expires_at'] as String?) ?? '',
      shareUrl: (json['share_url'] as String?) ?? '',
    );
  }
}

class RideShareApiException implements Exception {
  final int statusCode;
  final String detail;
  const RideShareApiException(this.statusCode, this.detail);

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'RideShareApiException($statusCode, $detail)';
}

class RideShareApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const RideShareApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Mint a short-lived share token. The server clamps
  /// `expiresInSeconds` to [15min, 12h]; passing null defaults
  /// to 6h on the server side.
  Future<RideShareToken> mintShare({
    required String rideId,
    String? label,
    int? expiresInSeconds,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'share'],
    );
    if (uri == null) {
      throw const RideShareApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{};
      final trimmed = label?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body['label'] = trimmed;
      if (expiresInSeconds != null) {
        body['expires_in_seconds'] = expiresInSeconds;
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RideShareApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final share = decoded['share'] as Map<String, dynamic>;
      return RideShareToken.fromJson(share);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Revoke every active share for a trip the caller owns. Returns
  /// the number of tokens invalidated.
  Future<int> revokeShares({required String rideId}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'share', 'revoke'],
    );
    if (uri == null) return 0;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final resp = await client
          .post(uri, headers: headers, body: '{}')
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return 0;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final count = decoded['revoked_count'];
      if (count is int) return count;
      return int.tryParse('${count ?? 0}') ?? 0;
    } catch (_) {
      return 0;
    } finally {
      if (closeClient) client.close();
    }
  }

  String _decodeErrorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {}
    return body;
  }
}
