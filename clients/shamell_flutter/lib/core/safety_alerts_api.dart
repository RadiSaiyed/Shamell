// Cycle 151 — In-trip safety alerts (SOS) client.
//
// Pairs with the BFF endpoints:
//   POST /me/rides/trips/:ride_id/sos                  — raise alert
//   GET  /me/rides/operator/safety-alerts              — operator queue
//   POST /me/rides/operator/safety-alerts/:id/acknowledge
//   POST /me/rides/operator/safety-alerts/:id/resolve

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class SafetyAlert {
  final int id;
  final String rideId;
  final String reporterAccountId;
  final String reporterRole;
  final String kind;
  final String status;
  final double? lastKnownLat;
  final double? lastKnownLon;
  final String? note;
  final String createdAt;
  final String? acknowledgedAt;
  final String? acknowledgedByAccountId;
  final String? resolvedAt;
  final String? resolvedByAccountId;
  final String? resolutionNote;

  const SafetyAlert({
    required this.id,
    required this.rideId,
    required this.reporterAccountId,
    required this.reporterRole,
    required this.kind,
    required this.status,
    this.lastKnownLat,
    this.lastKnownLon,
    this.note,
    required this.createdAt,
    this.acknowledgedAt,
    this.acknowledgedByAccountId,
    this.resolvedAt,
    this.resolvedByAccountId,
    this.resolutionNote,
  });

  bool get isActive => status == 'active';
  bool get isAcknowledged => status == 'acknowledged';
  bool get isResolved => status == 'resolved';

  factory SafetyAlert.fromJson(Map<String, dynamic> json) {
    double? readDouble(Object? raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }

    return SafetyAlert(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      rideId: (json['ride_id'] as String?) ?? '',
      reporterAccountId: (json['reporter_account_id'] as String?) ?? '',
      reporterRole: (json['reporter_role'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'sos',
      status: (json['status'] as String?) ?? 'active',
      lastKnownLat: readDouble(json['last_known_lat']),
      lastKnownLon: readDouble(json['last_known_lon']),
      note: json['note'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      acknowledgedAt: json['acknowledged_at'] as String?,
      acknowledgedByAccountId: json['acknowledged_by_account_id'] as String?,
      resolvedAt: json['resolved_at'] as String?,
      resolvedByAccountId: json['resolved_by_account_id'] as String?,
      resolutionNote: json['resolution_note'] as String?,
    );
  }
}

class SafetyAlertApiException implements Exception {
  final int statusCode;
  final String detail;
  const SafetyAlertApiException(this.statusCode, this.detail);

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'SafetyAlertApiException($statusCode, $detail)';
}

class SafetyAlertsApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const SafetyAlertsApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Raise an SOS alert for an active trip. The server validates
  /// that the caller is actually on the trip (rider or driver) and
  /// derives the reporter_role from there — the client doesn't need
  /// to know which side it is.
  Future<SafetyAlert> raiseSos({
    required String rideId,
    double? lastKnownLat,
    double? lastKnownLon,
    double? accuracyMeters,
    String? note,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'sos'],
    );
    if (uri == null) {
      throw const SafetyAlertApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{'kind': 'sos'};
      if (lastKnownLat != null) body['last_known_lat'] = lastKnownLat;
      if (lastKnownLon != null) body['last_known_lon'] = lastKnownLon;
      if (accuracyMeters != null) body['accuracy_meters'] = accuracyMeters;
      final trimmedNote = note?.trim();
      if (trimmedNote != null && trimmedNote.isNotEmpty) {
        body['note'] = trimmedNote;
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw SafetyAlertApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final alert = decoded['alert'] as Map<String, dynamic>;
      return SafetyAlert.fromJson(alert);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator: list the active+acknowledged queue. Oldest first.
  Future<List<SafetyAlert>> operatorQueue() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'safety-alerts'],
    );
    if (uri == null) return const <SafetyAlert>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <SafetyAlert>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['alerts'];
      if (raw is! List) return const <SafetyAlert>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(SafetyAlert.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <SafetyAlert>[];
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator: acknowledge the alert (claim it).
  Future<SafetyAlert?> operatorAcknowledge({required int alertId}) async {
    return _operatorMutate(
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'safety-alerts',
        alertId.toString(),
        'acknowledge',
      ],
      body: const <String, dynamic>{},
    );
  }

  /// Operator: resolve the alert with an optional note.
  Future<SafetyAlert?> operatorResolve({
    required int alertId,
    String? resolutionNote,
  }) async {
    final body = <String, dynamic>{};
    final trimmed = resolutionNote?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      body['resolution_note'] = trimmed;
    }
    return _operatorMutate(
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'safety-alerts',
        alertId.toString(),
        'resolve',
      ],
      body: body,
    );
  }

  Future<SafetyAlert?> _operatorMutate({
    required List<String> pathSegments,
    required Map<String, dynamic> body,
  }) async {
    final uri =
        secureApiChildUri(baseUrl: baseUrl, pathSegments: pathSegments);
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final alert = decoded['alert'] as Map<String, dynamic>?;
      if (alert == null) return null;
      return SafetyAlert.fromJson(alert);
    } catch (_) {
      return null;
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
