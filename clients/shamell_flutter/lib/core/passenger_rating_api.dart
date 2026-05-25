// Cycle 142 — Driver→passenger rating client.
//
// Pairs with the BFF endpoints in `services_rs/bff_gateway/src/auth.rs`:
//   POST /me/rides/trips/:ride_id/passenger-rating    — upsert rating
//   GET  /me/rides/trips/:ride_id/passenger-rating    — fetch own rating
//   GET  /me/rides/passenger-rating                   — caller's own aggregate
//   GET  /me/rides/passengers/:passenger_id/rating    — public aggregate
//
// Symmetric counterpart to `RideRatingApi` (Cycle 135). Roles are
// flipped: the driver is the rater, the passenger is the rated.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class PassengerRating {
  final String rideId;
  final String subjectAccountId;
  final String passengerAccountId;
  final int stars;
  final String? comment;
  final String createdAt;
  final String updatedAt;

  const PassengerRating({
    required this.rideId,
    required this.subjectAccountId,
    required this.passengerAccountId,
    required this.stars,
    this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PassengerRating.fromJson(Map<String, dynamic> json) {
    return PassengerRating(
      rideId: (json['ride_id'] as String?) ?? '',
      subjectAccountId: (json['subject_account_id'] as String?) ?? '',
      passengerAccountId: (json['passenger_account_id'] as String?) ?? '',
      stars: (json['stars'] is int)
          ? json['stars'] as int
          : int.tryParse('${json['stars']}') ?? 0,
      comment: json['comment'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
    );
  }
}

class PassengerRatingAggregate {
  final String passengerAccountId;
  final int ratingCount;
  final double averageStars;
  final String? lastUpdatedAt;

  const PassengerRatingAggregate({
    required this.passengerAccountId,
    required this.ratingCount,
    required this.averageStars,
    this.lastUpdatedAt,
  });

  bool get isEmpty => ratingCount == 0;

  factory PassengerRatingAggregate.fromJson(Map<String, dynamic> json) {
    final raw = json['average_stars'];
    final double avg = raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? 0}') ?? 0.0;
    return PassengerRatingAggregate(
      passengerAccountId: (json['passenger_account_id'] as String?) ?? '',
      ratingCount: (json['rating_count'] is int)
          ? json['rating_count'] as int
          : int.tryParse('${json['rating_count'] ?? 0}') ?? 0,
      averageStars: avg,
      lastUpdatedAt: json['last_updated_at'] as String?,
    );
  }
}

class PassengerRatingApiException implements Exception {
  final int statusCode;
  final String detail;
  const PassengerRatingApiException(this.statusCode, this.detail);

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'PassengerRatingApiException($statusCode, $detail)';
}

class PassengerRatingApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const PassengerRatingApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Submit (or update) a rating the driver gives the passenger
  /// after a completed trip.
  Future<PassengerRating> submitRating({
    required String rideId,
    required int stars,
    String? comment,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'passenger-rating'],
    );
    if (uri == null) {
      throw const PassengerRatingApiException(0, 'invalid base url');
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
        throw PassengerRatingApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final rating = decoded['rating'] as Map<String, dynamic>;
      return PassengerRating.fromJson(rating);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Read the driver's own rating for a trip. Returns null on 404
  /// (haven't rated yet), throws on auth / other errors.
  Future<PassengerRating?> getOwnRating({required String rideId}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'passenger-rating'],
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
      return PassengerRating.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Caller's own passenger aggregate. Useful for "your reputation"
  /// indicators in the rider app.
  Future<PassengerRatingAggregate?> mySelfAggregate() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'passenger-rating'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return PassengerRatingAggregate.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Public aggregate for a specific passenger. Operator uses this
  /// from the trip-details sheet to spot low-score riders. Returns
  /// a zero-count aggregate when the passenger hasn't been rated
  /// yet (driver-side decision: show "—" rather than nothing).
  Future<PassengerRatingAggregate?> passengerAggregate({
    required String passengerId,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'passengers',
        passengerId,
        'rating',
      ],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return PassengerRatingAggregate.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator-only: look up a passenger's rating aggregate by
  /// ride_id (no account_id leak). Used by the operator console's
  /// trip-details sheet to surface rider reputation.
  /// Returns a zero-count aggregate when the rider hasn't been rated.
  Future<PassengerRatingAggregate?> operatorTripPassengerAggregate({
    required String rideId,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'trips',
        rideId,
        'passenger-rating-aggregate',
      ],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      // Endpoint omits passenger_account_id by design; backfill with
      // empty so the same model can be reused without conditional
      // null handling in the UI.
      return PassengerRatingAggregate.fromJson(<String, dynamic>{
        'passenger_account_id': '',
        ...json,
      });
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
