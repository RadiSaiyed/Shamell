// Cycle 181 — Trip-history client (rider + driver views).
//
// Pairs with BFF endpoints:
//   GET /me/rides/history           — rider's last 50 trips
//   GET /me/rides/driver/history    — driver's last 50 trips
//
// Each entry carries the caller's own rating (if any) so the page
// can show "you rated 4★" inline without a second roundtrip.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class TripHistoryEntry {
  final String rideId;
  final String status;
  final String rideClass;
  final String? pickupLabel;
  final String? destinationLabel;
  final String pickupText;
  final String destinationText;
  final int fareEstimateCents;
  final String createdAt;
  final String statusUpdatedAt;
  final String? completedAt;
  final String? cancelReasonCode;
  final String? counterpartName;
  final int? ownRatingStars;
  final String? ownRatingComment;

  const TripHistoryEntry({
    required this.rideId,
    required this.status,
    required this.rideClass,
    this.pickupLabel,
    this.destinationLabel,
    required this.pickupText,
    required this.destinationText,
    required this.fareEstimateCents,
    required this.createdAt,
    required this.statusUpdatedAt,
    this.completedAt,
    this.cancelReasonCode,
    this.counterpartName,
    this.ownRatingStars,
    this.ownRatingComment,
  });

  bool get isCompleted => status == 'trip_completed';
  bool get isCancelled => status == 'canceled' || status == 'cancelled';
  bool get hasOwnRating => ownRatingStars != null && ownRatingStars! > 0;

  factory TripHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TripHistoryEntry(
      rideId: (json['ride_id'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      rideClass: (json['ride_class'] as String?) ?? '',
      pickupLabel: json['pickup_label'] as String?,
      destinationLabel: json['destination_label'] as String?,
      pickupText: (json['pickup_text'] as String?) ?? '',
      destinationText: (json['destination_text'] as String?) ?? '',
      fareEstimateCents: (json['fare_estimate_cents'] is int)
          ? json['fare_estimate_cents'] as int
          : int.tryParse('${json['fare_estimate_cents'] ?? 0}') ?? 0,
      createdAt: (json['created_at'] as String?) ?? '',
      statusUpdatedAt: (json['status_updated_at'] as String?) ?? '',
      completedAt: json['completed_at'] as String?,
      cancelReasonCode: json['cancel_reason_code'] as String?,
      counterpartName: json['counterpart_name'] as String?,
      ownRatingStars: (json['own_rating_stars'] is int)
          ? json['own_rating_stars'] as int
          : (json['own_rating_stars'] is num)
              ? (json['own_rating_stars'] as num).toInt()
              : null,
      ownRatingComment: json['own_rating_comment'] as String?,
    );
  }
}

class RideHistoryApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const RideHistoryApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  Future<List<TripHistoryEntry>> rider() async {
    return _list(<String>['me', 'rides', 'history']);
  }

  Future<List<TripHistoryEntry>> driver() async {
    return _list(<String>['me', 'rides', 'driver', 'history']);
  }

  Future<List<TripHistoryEntry>> _list(List<String> path) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: path,
    );
    if (uri == null) return const <TripHistoryEntry>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <TripHistoryEntry>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['trips'];
      if (raw is! List) return const <TripHistoryEntry>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(TripHistoryEntry.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <TripHistoryEntry>[];
    } finally {
      if (closeClient) client.close();
    }
  }
}
