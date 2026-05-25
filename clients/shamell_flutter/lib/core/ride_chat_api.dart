// Cycle 166 — In-trip ride chat client.
//
// Pairs with the BFF endpoints:
//   POST /me/rides/trips/:ride_id/chat        — send a message
//   GET  /me/rides/trips/:ride_id/chat?after_id=N — cursor poll
//
// Both rider and driver hit the same endpoints; the server derives
// `sender_role` from the trip membership so neither side has to
// know which it is.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class RideChatMessage {
  final int id;
  final String rideId;
  final String senderAccountId;
  final String senderRole; // 'rider' | 'driver'
  final String body;
  final String createdAt;

  const RideChatMessage({
    required this.id,
    required this.rideId,
    required this.senderAccountId,
    required this.senderRole,
    required this.body,
    required this.createdAt,
  });

  bool get isFromRider => senderRole == 'rider';
  bool get isFromDriver => senderRole == 'driver';

  factory RideChatMessage.fromJson(Map<String, dynamic> json) {
    return RideChatMessage(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      rideId: (json['ride_id'] as String?) ?? '',
      senderAccountId: (json['sender_account_id'] as String?) ?? '',
      senderRole: (json['sender_role'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

class RideChatApiException implements Exception {
  final int statusCode;
  final String detail;
  const RideChatApiException(this.statusCode, this.detail);

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'RideChatApiException($statusCode, $detail)';
}

class RideChatApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const RideChatApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Send a message. Returns the freshly-inserted row.
  Future<RideChatMessage> send({
    required String rideId,
    required String body,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'chat'],
    );
    if (uri == null) {
      throw const RideChatApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final resp = await client
          .post(uri,
              headers: headers,
              body: jsonEncode(<String, dynamic>{'body': body}))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RideChatApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final message = decoded['message'] as Map<String, dynamic>;
      return RideChatMessage.fromJson(message);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Forward-cursor poll. Returns messages where `id > afterId`.
  Future<List<RideChatMessage>> list({
    required String rideId,
    int afterId = 0,
    int limit = 100,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', rideId, 'chat'],
      queryParameters: <String, String>{
        if (afterId > 0) 'after_id': afterId.toString(),
        'limit': limit.toString(),
      },
    );
    if (uri == null) return const <RideChatMessage>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <RideChatMessage>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['messages'];
      if (raw is! List) return const <RideChatMessage>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(RideChatMessage.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <RideChatMessage>[];
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
