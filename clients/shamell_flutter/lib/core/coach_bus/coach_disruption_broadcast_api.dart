// Cycle 262 — Coach disruption broadcast client.
//
// Pairs with the BFF endpoints:
//   GET  /me/coach/operator/disruption-broadcasts
//   POST /me/coach/operator/disruption-broadcasts
//   POST /me/coach/operator/disruption-broadcasts/:id/revoke
//   GET  /me/coach/journeys/:journey_id/notices  (passenger feed)
//
// Operators publish journey-level disruption notices (delays, route
// changes, weather alerts). Riders on the matching journey see them
// surface in the live-journey page via the passenger feed.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../session_cookie_store.dart';

enum CoachDisruptionSeverity { info, warning, critical }

String coachDisruptionSeverityWire(CoachDisruptionSeverity s) {
  switch (s) {
    case CoachDisruptionSeverity.info:
      return 'info';
    case CoachDisruptionSeverity.warning:
      return 'warning';
    case CoachDisruptionSeverity.critical:
      return 'critical';
  }
}

CoachDisruptionSeverity coachDisruptionSeverityFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'critical':
      return CoachDisruptionSeverity.critical;
    case 'warning':
      return CoachDisruptionSeverity.warning;
    case 'info':
    default:
      return CoachDisruptionSeverity.info;
  }
}

class CoachDisruptionBroadcast {
  final int id;
  final String journeyId;
  final String operatorId;
  final String? publishedByAccountId;
  final CoachDisruptionSeverity severity;
  final String headline;
  final String body;
  final List<String> channels;
  final String createdAt;
  final String expiresAt;
  final String? revokedAt;
  final bool isActive;

  const CoachDisruptionBroadcast({
    required this.id,
    required this.journeyId,
    required this.operatorId,
    required this.publishedByAccountId,
    required this.severity,
    required this.headline,
    required this.body,
    required this.channels,
    required this.createdAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.isActive,
  });

  factory CoachDisruptionBroadcast.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    final channels = rawChannels is List
        ? rawChannels
            .map((v) => v.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return CoachDisruptionBroadcast(
      id: (json['id'] is int) ? json['id'] as int : 0,
      journeyId: (json['journey_id'] as String?) ?? '',
      operatorId: (json['operator_id'] as String?) ?? '',
      publishedByAccountId: json['published_by_account_id'] as String?,
      severity: coachDisruptionSeverityFromWire(
          (json['severity'] as String?) ?? 'info'),
      headline: (json['headline'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      channels: channels,
      createdAt: (json['created_at'] as String?) ?? '',
      expiresAt: (json['expires_at'] as String?) ?? '',
      revokedAt: json['revoked_at'] as String?,
      isActive: (json['is_active'] as bool?) ?? false,
    );
  }
}

class CoachDisruptionListResponse {
  final String generatedAt;
  final List<CoachDisruptionBroadcast> broadcasts;

  const CoachDisruptionListResponse({
    required this.generatedAt,
    required this.broadcasts,
  });

  factory CoachDisruptionListResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['broadcasts'];
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(CoachDisruptionBroadcast.fromJson)
            .toList(growable: false)
        : const <CoachDisruptionBroadcast>[];
    return CoachDisruptionListResponse(
      generatedAt: (json['generated_at'] as String?) ?? '',
      broadcasts: list,
    );
  }
}

class CoachDisruptionApiException implements Exception {
  final int statusCode;
  final String detail;
  const CoachDisruptionApiException(this.statusCode, this.detail);

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'CoachDisruptionApiException($statusCode, $detail)';
}

class CoachDisruptionBroadcastApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const CoachDisruptionBroadcastApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Operator: publish a new disruption broadcast.
  Future<CoachDisruptionBroadcast> publish({
    required String journeyId,
    required String operatorId,
    required CoachDisruptionSeverity severity,
    required String headline,
    required String body,
    List<String>? channels,
    int? expiresInSeconds,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'disruption-broadcasts',
      ],
    );
    if (uri == null) {
      throw const CoachDisruptionApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, dynamic>{
        'journey_id': journeyId,
        'operator_id': operatorId,
        'severity': coachDisruptionSeverityWire(severity),
        'headline': headline,
        'body': body,
      };
      if (channels != null && channels.isNotEmpty) {
        payload['channels'] = channels;
      }
      if (expiresInSeconds != null) {
        payload['expires_in_seconds'] = expiresInSeconds;
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw CoachDisruptionApiException(
            resp.statusCode, _decodeDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final b = decoded['broadcast'] as Map<String, dynamic>;
      return CoachDisruptionBroadcast.fromJson(b);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator: list own recent broadcasts.
  Future<CoachDisruptionListResponse> listOperatorBroadcasts() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'disruption-broadcasts',
      ],
    );
    if (uri == null) {
      throw const CoachDisruptionApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp = await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw CoachDisruptionApiException(
            resp.statusCode, _decodeDetail(resp.body));
      }
      return CoachDisruptionListResponse.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator: revoke a broadcast early.
  Future<CoachDisruptionBroadcast> revoke({required int id}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'disruption-broadcasts',
        '$id',
        'revoke',
      ],
    );
    if (uri == null) {
      throw const CoachDisruptionApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final resp = await client
          .post(uri, headers: headers, body: '{}')
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw CoachDisruptionApiException(
            resp.statusCode, _decodeDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final b = decoded['broadcast'] as Map<String, dynamic>;
      return CoachDisruptionBroadcast.fromJson(b);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Passenger: fetch currently-active notices for a journey.
  Future<CoachDisruptionListResponse> listJourneyNotices(
      String journeyId) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'journeys',
        journeyId,
        'notices',
      ],
    );
    if (uri == null) {
      throw const CoachDisruptionApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp = await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // Quietly empty on 4xx so the live page can render without
        // a crash if the notice route isn't deployed yet.
        return const CoachDisruptionListResponse(
          generatedAt: '',
          broadcasts: <CoachDisruptionBroadcast>[],
        );
      }
      return CoachDisruptionListResponse.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return const CoachDisruptionListResponse(
        generatedAt: '',
        broadcasts: <CoachDisruptionBroadcast>[],
      );
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
