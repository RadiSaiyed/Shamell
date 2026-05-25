// Cycle 135 — Post-trip rider→driver rating client.
//
// Pairs with the BFF endpoints in `services_rs/bff_gateway/src/auth.rs`:
//   POST /me/rides/trips/:ride_id/rating       — upsert rating
//   GET  /me/rides/trips/:ride_id/rating       — fetch own rating
//   GET  /me/rides/drivers/:driver_id/rating   — public aggregate
//
// Errors: structured RideRatingApiException so the UI can react to
// 403 ("you are not the rider") and 400 ("trip not completed") with
// targeted messages instead of a generic toast.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class RideRating {
  final String rideId;
  final String subjectAccountId;
  final String driverAccountId;
  final int stars;
  final String? comment;
  final String createdAt;
  final String updatedAt;

  const RideRating({
    required this.rideId,
    required this.subjectAccountId,
    required this.driverAccountId,
    required this.stars,
    this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RideRating.fromJson(Map<String, dynamic> json) {
    return RideRating(
      rideId: (json['ride_id'] as String?) ?? '',
      subjectAccountId: (json['subject_account_id'] as String?) ?? '',
      driverAccountId: (json['driver_account_id'] as String?) ?? '',
      stars: (json['stars'] is int)
          ? json['stars'] as int
          : int.tryParse('${json['stars']}') ?? 0,
      comment: json['comment'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
    );
  }
}

class DriverRatingAggregate {
  final String driverAccountId;
  final int ratingCount;
  final double averageStars;
  final String? lastUpdatedAt;

  const DriverRatingAggregate({
    required this.driverAccountId,
    required this.ratingCount,
    required this.averageStars,
    this.lastUpdatedAt,
  });

  bool get isEmpty => ratingCount == 0;

  factory DriverRatingAggregate.fromJson(Map<String, dynamic> json) {
    final raw = json['average_stars'];
    final double avg = raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? 0}') ?? 0.0;
    return DriverRatingAggregate(
      driverAccountId: (json['driver_account_id'] as String?) ?? '',
      ratingCount: (json['rating_count'] is int)
          ? json['rating_count'] as int
          : int.tryParse('${json['rating_count'] ?? 0}') ?? 0,
      averageStars: avg,
      lastUpdatedAt: json['last_updated_at'] as String?,
    );
  }
}

class RideRatingApiException implements Exception {
  final int statusCode;
  final String detail;
  const RideRatingApiException(this.statusCode, this.detail);

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'RideRatingApiException($statusCode, $detail)';
}

class RideRatingApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const RideRatingApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Submit (or update) a rating for a completed trip.
  Future<RideRating> submitRating({
    required String rideId,
    required int stars,
    String? comment,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'rating'],
    );
    if (uri == null) {
      throw const RideRatingApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{'stars': stars};
      final trimmed = comment?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        body['comment'] = trimmed;
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RideRatingApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final rating = decoded['rating'] as Map<String, dynamic>;
      return RideRating.fromJson(rating);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Read the rider's own rating for a trip. Returns null on 404
  /// (haven't rated yet), throws on auth / other errors.
  Future<RideRating?> getOwnRating({required String rideId}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'rating'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode == 404) return null;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideRating.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Caller's own driver aggregate. Convenience wrapper that hits
  /// `/me/rides/driver-rating`, which the BFF resolves to the
  /// session account without the client having to know its own id.
  Future<DriverRatingAggregate?> myDriverAggregate() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'driver-rating'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return DriverRatingAggregate.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Read the driver's public rating aggregate. Returns null on
  /// auth failure; returns a zero-count aggregate when the driver
  /// hasn't been rated yet.
  Future<DriverRatingAggregate?> driverAggregate({
    required String driverId,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'drivers', driverId, 'rating'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return DriverRatingAggregate.fromJson(
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
