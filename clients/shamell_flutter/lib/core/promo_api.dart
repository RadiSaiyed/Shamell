// Cycle 207 — Promo / discount code client.
//
// Pairs with the BFF endpoints:
//   POST /me/promo/validate                         — rider check
//   GET  /me/rides/operator/promos                  — operator list
//   POST /me/rides/operator/promos                  — operator mint
//   POST /me/rides/operator/promos/:code/disable    — operator pause
//
// `kind == 'percent'` → `value` is basis-points (10 000 = 100 %).
// `kind == 'fixed'`   → `value` is minor units (cents/piastres).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class PromoValidation {
  final bool ok;
  final String code;
  final String kind; // 'percent' | 'fixed'
  final int value;
  final String currency;
  final int resolvedDiscountCents;
  final String? description;

  const PromoValidation({
    required this.ok,
    required this.code,
    required this.kind,
    required this.value,
    required this.currency,
    required this.resolvedDiscountCents,
    this.description,
  });

  bool get isPercent => kind == 'percent';
  bool get isFixed => kind == 'fixed';

  factory PromoValidation.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    return PromoValidation(
      ok: (json['ok'] as bool?) ?? false,
      code: (json['code'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'fixed',
      value: _toInt(json['value']),
      currency: (json['currency'] as String?) ?? 'SYP',
      resolvedDiscountCents: _toInt(json['resolved_discount_cents']),
      description: json['description'] as String?,
    );
  }
}

class Promo {
  final int id;
  final String code;
  final String? description;
  final String kind;
  final int value;
  final String currency;
  final int? maxRedemptions;
  final int redemptionCount;
  final String validFrom;
  final String? expiresAt;
  final String status; // 'active' | 'disabled'
  final String createdAt;
  final String updatedAt;

  const Promo({
    required this.id,
    required this.code,
    this.description,
    required this.kind,
    required this.value,
    required this.currency,
    this.maxRedemptions,
    required this.redemptionCount,
    required this.validFrom,
    this.expiresAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';
  bool get isDisabled => status == 'disabled';

  factory Promo.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    int? _toIntN(dynamic v) =>
        v == null ? null : (v is int ? v : int.tryParse('${v ?? ''}'));
    return Promo(
      id: _toInt(json['id']),
      code: (json['code'] as String?) ?? '',
      description: json['description'] as String?,
      kind: (json['kind'] as String?) ?? 'fixed',
      value: _toInt(json['value']),
      currency: (json['currency'] as String?) ?? 'SYP',
      maxRedemptions: _toIntN(json['max_redemptions']),
      redemptionCount: _toInt(json['redemption_count']),
      validFrom: (json['valid_from'] as String?) ?? '',
      expiresAt: json['expires_at'] as String?,
      status: (json['status'] as String?) ?? 'active',
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
    );
  }
}

class PromoApiException implements Exception {
  final int statusCode;
  final String detail;
  const PromoApiException(this.statusCode, this.detail);

  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isGone => statusCode == 410;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'PromoApiException($statusCode, $detail)';
}

class PromoApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const PromoApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Rider-facing: check whether a code is currently usable.
  /// `fareEstimateCents` is optional; passing it lets the server
  /// resolve the absolute discount alongside the kind/value.
  Future<PromoValidation> validate({
    required String code,
    int? fareEstimateCents,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'promo', 'validate'],
    );
    if (uri == null) {
      throw const PromoApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{'code': code};
      if (fareEstimateCents != null && fareEstimateCents > 0) {
        body['fare_estimate_cents'] = fareEstimateCents;
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw PromoApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      return PromoValidation.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator: list all promos, newest first.
  Future<List<Promo>> operatorList() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'promos'],
    );
    if (uri == null) return const <Promo>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return const <Promo>[];
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['promos'];
      if (raw is! List) return const <Promo>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Promo.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <Promo>[];
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator: mint a new code.
  Future<Promo> operatorCreate({
    required String code,
    required String kind, // 'percent' or 'fixed'
    required int value,
    String currency = 'SYP',
    String? description,
    int? maxRedemptions,
    DateTime? expiresAtUtc,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'promos'],
    );
    if (uri == null) {
      throw const PromoApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        'code': code,
        'kind': kind,
        'value': value,
        'currency': currency,
      };
      if (description != null && description.trim().isNotEmpty) {
        body['description'] = description.trim();
      }
      if (maxRedemptions != null) body['max_redemptions'] = maxRedemptions;
      if (expiresAtUtc != null) {
        body['expires_at'] = expiresAtUtc.toUtc().toIso8601String();
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw PromoApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final promo = decoded['promo'] as Map<String, dynamic>;
      return Promo.fromJson(promo);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Operator: disable an active code (history preserved).
  Future<Promo?> operatorDisable({required String code}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'promos',
        code,
        'disable',
      ],
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
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final promo = decoded['promo'] as Map<String, dynamic>;
      return Promo.fromJson(promo);
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
