// Cycle 236 — Coach journey safety alerts (SOS) client.
//
// Pairs with the BFF endpoints:
//   POST /me/coach/journeys/:journey_id/sos              — raise alert
//   GET  /me/coach/operator/safety-alerts                — operator queue
//   POST /me/coach/operator/safety-alerts/:id/acknowledge
//   POST /me/coach/operator/safety-alerts/:id/resolve
//
// Mirror of `SafetyAlertsApi` (Cycle 151) scoped to the
// (journey, booking, operator) triple instead of a single rideId.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../session_cookie_store.dart';

class CoachSafetyAlert {
  final int id;
  final String journeyId;
  final String bookingId;
  final String operatorId;
  final String reporterAccountId;
  final String kind;
  final String status; // 'active' | 'acknowledged' | 'resolved'
  final double? lastKnownLat;
  final double? lastKnownLon;
  final String createdAt;
  final String? acknowledgedAt;
  final String? resolvedAt;
  final String? resolutionNote;

  const CoachSafetyAlert({
    required this.id,
    required this.journeyId,
    required this.bookingId,
    required this.operatorId,
    required this.reporterAccountId,
    required this.kind,
    required this.status,
    this.lastKnownLat,
    this.lastKnownLon,
    required this.createdAt,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNote,
  });

  bool get isActive => status == 'active';
  bool get isAcknowledged => status == 'acknowledged';
  bool get isResolved => status == 'resolved';

  factory CoachSafetyAlert.fromJson(Map<String, dynamic> json) {
    double? _d(Object? raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }
    return CoachSafetyAlert(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      journeyId: (json['journey_id'] as String?) ?? '',
      bookingId: (json['booking_id'] as String?) ?? '',
      operatorId: (json['operator_id'] as String?) ?? '',
      reporterAccountId: (json['reporter_account_id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'sos',
      status: (json['status'] as String?) ?? 'active',
      lastKnownLat: _d(json['last_known_lat']),
      lastKnownLon: _d(json['last_known_lon']),
      createdAt: (json['created_at'] as String?) ?? '',
      acknowledgedAt: json['acknowledged_at'] as String?,
      resolvedAt: json['resolved_at'] as String?,
      resolutionNote: json['resolution_note'] as String?,
    );
  }
}

class CoachSafetyAlertsApiException implements Exception {
  final int statusCode;
  final String detail;
  const CoachSafetyAlertsApiException(this.statusCode, this.detail);

  bool get isConflict => statusCode == 409;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() =>
      'CoachSafetyAlertsApiException($statusCode, $detail)';
}

class CoachSafetyAlertsApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const CoachSafetyAlertsApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Raise a new SOS alert on a coach journey. Server enforces
  /// caller authentication; the (journey, reporter) pair is
  /// captured as audit metadata.
  Future<CoachSafetyAlert> submit({
    required String journeyId,
    required String bookingId,
    required String operatorId,
    String kind = 'sos',
    double? lastKnownLat,
    double? lastKnownLon,
    String? note,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'journeys', journeyId, 'sos'],
    );
    if (uri == null) {
      throw const CoachSafetyAlertsApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        'booking_id': bookingId,
        'operator_id': operatorId,
        'kind': kind,
      };
      if (lastKnownLat != null) body['last_known_lat'] = lastKnownLat;
      if (lastKnownLon != null) body['last_known_lon'] = lastKnownLon;
      final trimmed = note?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body['note'] = trimmed;
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw CoachSafetyAlertsApiException(
            resp.statusCode, _decodeDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final alert = decoded['alert'] as Map<String, dynamic>;
      return CoachSafetyAlert.fromJson(alert);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator-only: pull active + acknowledged alerts queue.
  Future<List<CoachSafetyAlert>> operatorList() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'safety-alerts',
      ],
    );
    if (uri == null) return const <CoachSafetyAlert>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <CoachSafetyAlert>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['alerts'];
      if (raw is! List) return const <CoachSafetyAlert>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(CoachSafetyAlert.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <CoachSafetyAlert>[];
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<CoachSafetyAlert?> operatorAcknowledge({required int id}) async {
    return _operatorTransition(id: id, action: 'acknowledge');
  }

  Future<CoachSafetyAlert?> operatorResolve({
    required int id,
    String? note,
  }) async {
    return _operatorTransition(id: id, action: 'resolve', note: note);
  }

  Future<CoachSafetyAlert?> _operatorTransition({
    required int id,
    required String action,
    String? note,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'safety-alerts',
        '$id',
        action,
      ],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{};
      final trimmed = note?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body['note'] = trimmed;
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final alert = decoded['alert'] as Map<String, dynamic>;
      return CoachSafetyAlert.fromJson(alert);
    } catch (_) {
      return null;
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
