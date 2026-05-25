// Cycle 194 — Post-trip tip client (rider → driver).
//
// Pairs with the BFF endpoints:
//   POST /me/rides/trips/:ride_id/tip      — submit/update a tip
//   GET  /me/rides/trips/:ride_id/tip      — fetch own tip
//   GET  /me/rides/driver/tips             — driver tip aggregate
//
// Re-submitting a tip for the same ride UPDATEs the existing row
// (server enforces uniqueness on (ride, rider)), so a retry or
// "adjust tip" tap never double-charges.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class RideTip {
  final int id;
  final String rideId;
  final String riderAccountId;
  final String driverAccountId;
  final int amountCents;
  final String currency;
  final String status; // 'pending' | 'paid' | 'refunded'
  final String? message;
  final String createdAt;
  final String updatedAt;
  final String? settledAt;

  const RideTip({
    required this.id,
    required this.rideId,
    required this.riderAccountId,
    required this.driverAccountId,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.message,
    required this.createdAt,
    required this.updatedAt,
    this.settledAt,
  });

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isRefunded => status == 'refunded';

  factory RideTip.fromJson(Map<String, dynamic> json) {
    return RideTip(
      id: (json['id'] is int) ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      rideId: (json['ride_id'] as String?) ?? '',
      riderAccountId: (json['rider_account_id'] as String?) ?? '',
      driverAccountId: (json['driver_account_id'] as String?) ?? '',
      amountCents: (json['amount_cents'] is int)
          ? json['amount_cents'] as int
          : int.tryParse('${json['amount_cents'] ?? 0}') ?? 0,
      currency: (json['currency'] as String?) ?? 'SYP',
      status: (json['status'] as String?) ?? 'pending',
      message: json['message'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      settledAt: json['settled_at'] as String?,
    );
  }
}

class DriverTipAggregate {
  final String driverAccountId;
  final int todayCount;
  final int todayAmountCents;
  final int allTimeCount;
  final int allTimeAmountCents;
  final String? lastUpdatedAt;

  const DriverTipAggregate({
    required this.driverAccountId,
    required this.todayCount,
    required this.todayAmountCents,
    required this.allTimeCount,
    required this.allTimeAmountCents,
    this.lastUpdatedAt,
  });

  bool get isEmpty => allTimeCount == 0;
  bool get hasToday => todayCount > 0;

  factory DriverTipAggregate.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    return DriverTipAggregate(
      driverAccountId: (json['driver_account_id'] as String?) ?? '',
      todayCount: _toInt(json['today_count']),
      todayAmountCents: _toInt(json['today_amount_cents']),
      allTimeCount: _toInt(json['all_time_count']),
      allTimeAmountCents: _toInt(json['all_time_amount_cents']),
      lastUpdatedAt: json['last_updated_at'] as String?,
    );
  }
}

class RideTipApiException implements Exception {
  final int statusCode;
  final String detail;
  const RideTipApiException(this.statusCode, this.detail);

  bool get isBadRequest => statusCode == 400;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'RideTipApiException($statusCode, $detail)';
}

class RideTipApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const RideTipApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Submit (or update) a tip for a completed trip. Re-submit
  /// updates the existing row; never stacks.
  Future<RideTip> submitTip({
    required String rideId,
    required int amountCents,
    String currency = 'SYP',
    String? message,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'tip'],
    );
    if (uri == null) {
      throw const RideTipApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        'amount_cents': amountCents,
        'currency': currency,
      };
      final trimmed = message?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body['message'] = trimmed;
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RideTipApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final tip = decoded['tip'] as Map<String, dynamic>;
      return RideTip.fromJson(tip);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Get the rider's own tip for a trip. null if not tipped yet.
  Future<RideTip?> getOwnTip({required String rideId}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'tip'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode == 404) return null;
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return RideTip.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Driver: today's + all-time tip counts and totals. Used by the
  /// peek hero "Today's tips" mini-card.
  Future<DriverTipAggregate?> myDriverAggregate() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'driver', 'tips'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return DriverTipAggregate.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
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
