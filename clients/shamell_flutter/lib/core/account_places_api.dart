// Cycle 188 — Saved places client.
//
// Pairs with the BFF endpoints:
//   POST   /me/places          — create/upsert a saved place
//   GET    /me/places          — list mine (home+work first, then other)
//   DELETE /me/places/:id      — remove one of mine
//
// The server enforces "at most one home + one work per account"
// via partial unique indices; POST for those kinds is an UPSERT
// (DELETE-then-INSERT in a tx), so re-tapping "Set as Home"
// overwrites the previous entry cleanly.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class SavedPlace {
  final int id;
  final String accountId;
  final String label;
  final String? name;
  final String address;
  final double? lat;
  final double? lon;
  final String kind; // 'home' | 'work' | 'other'
  final String createdAt;
  final String updatedAt;

  const SavedPlace({
    required this.id,
    required this.accountId,
    required this.label,
    this.name,
    required this.address,
    this.lat,
    this.lon,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isHome => kind == 'home';
  bool get isWork => kind == 'work';
  bool get isOther => kind == 'other';

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      accountId: (json['account_id'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      name: json['name'] as String?,
      address: (json['address'] as String?) ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      kind: (json['kind'] as String?) ?? 'other',
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
    );
  }
}

class AccountPlacesApiException implements Exception {
  final int statusCode;
  final String detail;
  const AccountPlacesApiException(this.statusCode, this.detail);

  bool get isBadRequest => statusCode == 400;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'AccountPlacesApiException($statusCode, $detail)';
}

class AccountPlacesApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const AccountPlacesApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Create or upsert (for home/work) a saved place.
  Future<SavedPlace> save({
    required String label,
    required String address,
    String? name,
    double? lat,
    double? lon,
    String kind = 'other',
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'saved-places'],
    );
    if (uri == null) {
      throw const AccountPlacesApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{
        'label': label,
        'address': address,
        'kind': kind,
      };
      if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
      if (lat != null) body['lat'] = lat;
      if (lon != null) body['lon'] = lon;
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw AccountPlacesApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final place = decoded['place'] as Map<String, dynamic>;
      return SavedPlace.fromJson(place);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// List the caller's saved places (home + work first, then other).
  Future<List<SavedPlace>> listMine() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'saved-places'],
    );
    if (uri == null) return const <SavedPlace>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <SavedPlace>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['places'];
      if (raw is! List) return const <SavedPlace>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(SavedPlace.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <SavedPlace>[];
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Delete one of the caller's own saved places.
  Future<bool> delete({required int id}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'saved-places', '$id'],
    );
    if (uri == null) return false;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp = await client
          .delete(uri, headers: headers)
          .timeout(_requestTimeout);
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
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
