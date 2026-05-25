// Cycle 229 — Coach journey post-trip rating client.
//
// Pairs with the BFF endpoints:
//   POST /me/coach/journeys/:journey_id/rating          — upsert
//   GET  /me/coach/journeys/:journey_id/rating          — fetch own
//   GET  /me/coach/operators/:operator_id/rating        — public aggregate
//
// Mirrors the taxi rider→driver pattern. The subject is the rider,
// the rated party is the operator.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../session_cookie_store.dart';

class CoachJourneyRating {
  final String journeyId;
  final String bookingId;
  final String subjectAccountId;
  final String operatorId;
  final int stars;
  final String? comment;
  final int? onTimeStars;
  final int? cleanlinessStars;
  final int? comfortStars;
  final int? crewStars;
  final String createdAt;
  final String updatedAt;

  const CoachJourneyRating({
    required this.journeyId,
    required this.bookingId,
    required this.subjectAccountId,
    required this.operatorId,
    required this.stars,
    this.comment,
    this.onTimeStars,
    this.cleanlinessStars,
    this.comfortStars,
    this.crewStars,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CoachJourneyRating.fromJson(Map<String, dynamic> json) {
    int? _i(dynamic v) =>
        v == null ? null : (v is int ? v : int.tryParse('${v ?? ''}'));
    return CoachJourneyRating(
      journeyId: (json['journey_id'] as String?) ?? '',
      bookingId: (json['booking_id'] as String?) ?? '',
      subjectAccountId: (json['subject_account_id'] as String?) ?? '',
      operatorId: (json['operator_id'] as String?) ?? '',
      stars: _i(json['stars']) ?? 0,
      comment: json['comment'] as String?,
      onTimeStars: _i(json['on_time_stars']),
      cleanlinessStars: _i(json['cleanliness_stars']),
      comfortStars: _i(json['comfort_stars']),
      crewStars: _i(json['crew_stars']),
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
    );
  }
}

class CoachOperatorRatingAggregate {
  final String operatorId;
  final int ratingCount;
  final double averageStars;
  final String? lastUpdatedAt;

  const CoachOperatorRatingAggregate({
    required this.operatorId,
    required this.ratingCount,
    required this.averageStars,
    this.lastUpdatedAt,
  });

  bool get isEmpty => ratingCount == 0;

  factory CoachOperatorRatingAggregate.fromJson(Map<String, dynamic> json) {
    final raw = json['average_stars'];
    final double avg = raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? 0}') ?? 0.0;
    return CoachOperatorRatingAggregate(
      operatorId: (json['operator_id'] as String?) ?? '',
      ratingCount: (json['rating_count'] is int)
          ? json['rating_count'] as int
          : int.tryParse('${json['rating_count'] ?? 0}') ?? 0,
      averageStars: avg,
      lastUpdatedAt: json['last_updated_at'] as String?,
    );
  }
}

class CoachJourneyRatingApiException implements Exception {
  final int statusCode;
  final String detail;
  const CoachJourneyRatingApiException(this.statusCode, this.detail);

  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() =>
      'CoachJourneyRatingApiException($statusCode, $detail)';
}

class CoachJourneyRatingApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const CoachJourneyRatingApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  Future<CoachJourneyRating> submit({
    required String journeyId,
    required String bookingId,
    required String operatorId,
    required int stars,
    String? comment,
    int? onTimeStars,
    int? cleanlinessStars,
    int? comfortStars,
    int? crewStars,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'journeys', journeyId, 'rating'],
    );
    if (uri == null) {
      throw const CoachJourneyRatingApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        'booking_id': bookingId,
        'operator_id': operatorId,
        'stars': stars,
      };
      final trimmed = comment?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body['comment'] = trimmed;
      if (onTimeStars != null) body['on_time_stars'] = onTimeStars;
      if (cleanlinessStars != null) {
        body['cleanliness_stars'] = cleanlinessStars;
      }
      if (comfortStars != null) body['comfort_stars'] = comfortStars;
      if (crewStars != null) body['crew_stars'] = crewStars;
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw CoachJourneyRatingApiException(
            resp.statusCode, _decodeDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final rating = decoded['rating'] as Map<String, dynamic>;
      return CoachJourneyRating.fromJson(rating);
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<CoachJourneyRating?> getOwn({required String journeyId}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'journeys', journeyId, 'rating'],
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
      return CoachJourneyRating.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<CoachOperatorRatingAggregate?> operatorAggregate({
    required String operatorId,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'operators', operatorId, 'rating'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return CoachOperatorRatingAggregate.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
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
