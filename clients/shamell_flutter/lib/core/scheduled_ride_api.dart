// Cycle 174 — Scheduled (future-pickup) ride bookings client.
//
// Pairs with the BFF endpoints:
//   POST /me/rides/scheduled                 — create a booking
//   GET  /me/rides/scheduled                 — list my bookings
//   POST /me/rides/scheduled/:id/cancel      — cancel one of mine
//   GET  /me/rides/operator/scheduled        — operator queue
//
// The server enforces: pickup_at must be 10min-30d in the future.
// Cancel only works while still in `scheduled` status.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class ScheduledRide {
  final int id;
  final String riderAccountId;
  final String pickupText;
  final String destinationText;
  final String? pickupLabel;
  final String? destinationLabel;
  final double? pickupLat;
  final double? pickupLon;
  final double? destinationLat;
  final double? destinationLon;
  final String rideClass;
  final int fareEstimateCents;
  final String scheduledPickupAt;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? promotedAt;
  final String? promotedRideId;
  final String? cancelledAt;
  final String? cancelReason;
  final String? notes;

  const ScheduledRide({
    required this.id,
    required this.riderAccountId,
    required this.pickupText,
    required this.destinationText,
    this.pickupLabel,
    this.destinationLabel,
    this.pickupLat,
    this.pickupLon,
    this.destinationLat,
    this.destinationLon,
    required this.rideClass,
    required this.fareEstimateCents,
    required this.scheduledPickupAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.promotedAt,
    this.promotedRideId,
    this.cancelledAt,
    this.cancelReason,
    this.notes,
  });

  bool get isScheduled => status == 'scheduled';
  bool get isPromoted => status == 'promoted';
  bool get isCancelled => status == 'cancelled';
  bool get isExpired => status == 'expired';

  factory ScheduledRide.fromJson(Map<String, dynamic> json) {
    return ScheduledRide(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      riderAccountId: (json['rider_account_id'] as String?) ?? '',
      pickupText: (json['pickup_text'] as String?) ?? '',
      destinationText: (json['destination_text'] as String?) ?? '',
      pickupLabel: json['pickup_label'] as String?,
      destinationLabel: json['destination_label'] as String?,
      pickupLat: (json['pickup_lat'] as num?)?.toDouble(),
      pickupLon: (json['pickup_lon'] as num?)?.toDouble(),
      destinationLat: (json['destination_lat'] as num?)?.toDouble(),
      destinationLon: (json['destination_lon'] as num?)?.toDouble(),
      rideClass: (json['ride_class'] as String?) ?? 'economy',
      fareEstimateCents: (json['fare_estimate_cents'] is int)
          ? json['fare_estimate_cents'] as int
          : int.tryParse('${json['fare_estimate_cents'] ?? 0}') ?? 0,
      scheduledPickupAt: (json['scheduled_pickup_at'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      promotedAt: json['promoted_at'] as String?,
      promotedRideId: json['promoted_ride_id'] as String?,
      cancelledAt: json['cancelled_at'] as String?,
      cancelReason: json['cancel_reason'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

class ScheduledRideApiException implements Exception {
  final int statusCode;
  final String detail;
  const ScheduledRideApiException(this.statusCode, this.detail);

  bool get isBadRequest => statusCode == 400;
  bool get isConflict => statusCode == 409;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'ScheduledRideApiException($statusCode, $detail)';
}

class ScheduledRideApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const ScheduledRideApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Create a booking. `scheduledPickupAt` must be ISO-8601 UTC.
  Future<ScheduledRide> create({
    required String pickupText,
    required String destinationText,
    required DateTime scheduledPickupAtUtc,
    String? pickupLabel,
    String? destinationLabel,
    double? pickupLat,
    double? pickupLon,
    double? destinationLat,
    double? destinationLon,
    String rideClass = 'economy',
    int fareEstimateCents = 0,
    String? notes,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'scheduled'],
    );
    if (uri == null) {
      throw const ScheduledRideApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        'pickup_text': pickupText,
        'destination_text': destinationText,
        'scheduled_pickup_at':
            scheduledPickupAtUtc.toUtc().toIso8601String(),
        'ride_class': rideClass,
        'fare_estimate_cents': fareEstimateCents,
      };
      if (pickupLabel != null && pickupLabel.trim().isNotEmpty) {
        body['pickup_label'] = pickupLabel.trim();
      }
      if (destinationLabel != null && destinationLabel.trim().isNotEmpty) {
        body['destination_label'] = destinationLabel.trim();
      }
      if (pickupLat != null) body['pickup_lat'] = pickupLat;
      if (pickupLon != null) body['pickup_lon'] = pickupLon;
      if (destinationLat != null) body['destination_lat'] = destinationLat;
      if (destinationLon != null) body['destination_lon'] = destinationLon;
      if (notes != null && notes.trim().isNotEmpty) {
        body['notes'] = notes.trim();
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ScheduledRideApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final scheduled = decoded['scheduled'] as Map<String, dynamic>;
      return ScheduledRide.fromJson(scheduled);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// List the caller's own scheduled bookings (next 100, sorted
  /// ascending by pickup time, including recent past).
  Future<List<ScheduledRide>> listMine() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'scheduled'],
    );
    if (uri == null) return const <ScheduledRide>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <ScheduledRide>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['scheduled'];
      if (raw is! List) return const <ScheduledRide>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ScheduledRide.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <ScheduledRide>[];
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Cancel one of the caller's own bookings (only while still
  /// in `scheduled` status — the server enforces).
  Future<ScheduledRide?> cancel({required int id}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'scheduled', '$id', 'cancel'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final resp = await client
          .post(uri, headers: headers, body: '{}')
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ScheduledRideApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final scheduled = decoded['scheduled'] as Map<String, dynamic>;
      return ScheduledRide.fromJson(scheduled);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator-only — upcoming queue across all riders.
  Future<List<ScheduledRide>> operatorListUpcoming() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'scheduled'],
    );
    if (uri == null) return const <ScheduledRide>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <ScheduledRide>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['scheduled'];
      if (raw is! List) return const <ScheduledRide>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ScheduledRide.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <ScheduledRide>[];
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
