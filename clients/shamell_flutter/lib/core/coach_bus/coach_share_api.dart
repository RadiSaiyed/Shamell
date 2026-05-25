// Cycle 244 — Coach journey share token client.
//
// Pairs with the BFF endpoints:
//   POST /me/coach/journeys/:journey_id/share         — mint
//   POST /me/coach/journeys/:journey_id/share/revoke  — revoke
//   GET  /shared/coach-journeys/:token                — public (no auth)
//
// Mirror of `RideShareApi` (Cycle 160) scoped to the (journey,
// booking, operator) triple instead of a single ride.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../session_cookie_store.dart';

class CoachShareToken {
  final String token;
  final String journeyId;
  final String bookingId;
  final String operatorId;
  final String? label;
  final String createdAt;
  final String expiresAt;
  final String shareUrl;

  const CoachShareToken({
    required this.token,
    required this.journeyId,
    required this.bookingId,
    required this.operatorId,
    this.label,
    required this.createdAt,
    required this.expiresAt,
    required this.shareUrl,
  });

  factory CoachShareToken.fromJson(Map<String, dynamic> json) {
    return CoachShareToken(
      token: (json['token'] as String?) ?? '',
      journeyId: (json['journey_id'] as String?) ?? '',
      bookingId: (json['booking_id'] as String?) ?? '',
      operatorId: (json['operator_id'] as String?) ?? '',
      label: json['label'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      expiresAt: (json['expires_at'] as String?) ?? '',
      shareUrl: (json['share_url'] as String?) ?? '',
    );
  }
}

class CoachShareApiException implements Exception {
  final int statusCode;
  final String detail;
  const CoachShareApiException(this.statusCode, this.detail);

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'CoachShareApiException($statusCode, $detail)';
}

class CoachShareApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const CoachShareApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Mint a coach share token. Server clamps `expiresInSeconds`
  /// to [30 min, 24 h]; default is 12 h.
  Future<CoachShareToken> mintShare({
    required String journeyId,
    required String bookingId,
    required String operatorId,
    String? label,
    int? expiresInSeconds,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'journeys', journeyId, 'share'],
    );
    if (uri == null) {
      throw const CoachShareApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        'booking_id': bookingId,
        'operator_id': operatorId,
      };
      final trimmed = label?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body['label'] = trimmed;
      if (expiresInSeconds != null) {
        body['expires_in_seconds'] = expiresInSeconds;
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw CoachShareApiException(
            resp.statusCode, _decodeDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final share = decoded['share'] as Map<String, dynamic>;
      return CoachShareToken.fromJson(share);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Revoke every active share token for this journey owned by
  /// the caller. Returns the number revoked.
  Future<int> revokeShares({required String journeyId}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'journeys',
        journeyId,
        'share',
        'revoke',
      ],
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

  String _decodeDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {}
    return body;
  }
}
