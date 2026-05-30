// Cycle 101 — Driver / Operator role-signup approval workflow client.
//
// Pairs with the BFF endpoints in `services_rs/bff_gateway/src/auth.rs`:
//   POST  /auth/role-signups            — current user submits a request
//   GET   /auth/role-signups/me         — current user's request history
//   GET   /admin/role-signups           — admin queue (pending only)
//   POST  /admin/role-signups/:id/approve
//   POST  /admin/role-signups/:id/reject
//
// All four methods reuse the shared session-header pipeline; the admin
// endpoints additionally require `access.assignment.write` privilege
// (the server enforces it, the client just renders 403 as a denial).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

/// Roles a user may request via the self-service signup form. Mirrors
/// `SIGNUP_REQUESTABLE_ROLES` on the server.
class RoleSignupRoleIds {
  static const String driver = 'rides.driver';
  // Ride/Taxi operator console (Shamell Control + the dedicated
  // TaxiOperator flavor both request the same platform role).
  static const String operator = 'rides.driver_ops';
  static const String taxiOperator = 'rides.driver_ops';
  static const String busOperator = 'coach.operator_admin';
  static const String hotelOperator = 'hotels.operator';
  static const String carrier = 'freight.carrier_admin';
  // SyrCom workforce-member onboarding — the WeCom-style enterprise
  // companion app; approval is per-organization and admin-reviewed
  // through the operator console's Signups workspace.
  static const String syrcom = 'syrcom.workforce_member';
}

class RoleSignupRequest {
  final int id;
  final String subjectAccountId;
  final String requestedRoleId;
  final Map<String, dynamic> profile;
  final String status; // pending | approved | rejected
  final String submittedAt;
  final String? reviewedByAccountId;
  final String? reviewedAt;
  final String? reviewerNotes;

  const RoleSignupRequest({
    required this.id,
    required this.subjectAccountId,
    required this.requestedRoleId,
    required this.profile,
    required this.status,
    required this.submittedAt,
    this.reviewedByAccountId,
    this.reviewedAt,
    this.reviewerNotes,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  /// Convenience getter for the most-used profile field. Returns
  /// `''` when the key is missing or not a non-empty trimmed string.
  String profileString(String key) {
    final raw = profile[key];
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  factory RoleSignupRequest.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['profile'];
    final Map<String, dynamic> profile = rawProfile is Map<String, dynamic>
        ? rawProfile
        : (rawProfile is Map
            ? Map<String, dynamic>.from(rawProfile)
            : const <String, dynamic>{});
    return RoleSignupRequest(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      subjectAccountId: (json['subject_account_id'] as String?) ?? '',
      requestedRoleId: (json['requested_role_id'] as String?) ?? '',
      profile: profile,
      status: (json['status'] as String?) ?? 'pending',
      submittedAt: (json['submitted_at'] as String?) ?? '',
      reviewedByAccountId: json['reviewed_by_account_id'] as String?,
      reviewedAt: json['reviewed_at'] as String?,
      reviewerNotes: json['reviewer_notes'] as String?,
    );
  }
}

/// Thin error wrapper so the UI can distinguish 400-class denial
/// from generic network failure when surfacing a SnackBar.
class RoleSignupApiException implements Exception {
  final int statusCode;
  final String detail;
  const RoleSignupApiException(this.statusCode, this.detail);

  @override
  String toString() => 'RoleSignupApiException($statusCode, $detail)';
}

class RoleSignupApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const RoleSignupApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Submit a new signup request. Idempotent for pending state: a
  /// second submission for the same (subject, role) overwrites the
  /// profile payload but keeps the original request id.
  Future<RoleSignupRequest> submitRequest({
    required String requestedRoleId,
    required Map<String, dynamic> profile,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['auth', 'role-signups'],
    );
    if (uri == null) {
      throw const RoleSignupApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final resp = await client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'requested_role_id': requestedRoleId,
              'profile': profile,
            }),
          )
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RoleSignupApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final request = decoded['request'] as Map<String, dynamic>;
      return RoleSignupRequest.fromJson(request);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Read the current user's signup request history. Returns an
  /// empty list when the user has never submitted one.
  Future<List<RoleSignupRequest>> selfList() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['auth', 'role-signups', 'me'],
    );
    if (uri == null) return const <RoleSignupRequest>[];
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <RoleSignupRequest>[];
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['requests'] as List<dynamic>? ?? const <dynamic>[];
      return raw
          .map((e) => RoleSignupRequest.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Admin queue. Returns null on auth / permission failure so the
  /// Signups workspace can fall back to its empty state without
  /// crashing the operator console.
  Future<List<RoleSignupRequest>?> adminList() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['admin', 'role-signups'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = decoded['requests'] as List<dynamic>? ?? const <dynamic>[];
      return raw
          .map((e) => RoleSignupRequest.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RoleSignupRequest> adminApprove({
    required int requestId,
    String? notes,
  }) {
    return _adminReview(
      requestId: requestId,
      decisionPath: 'approve',
      notes: notes,
    );
  }

  Future<RoleSignupRequest> adminReject({
    required int requestId,
    String? notes,
  }) {
    return _adminReview(
      requestId: requestId,
      decisionPath: 'reject',
      notes: notes,
    );
  }

  Future<RoleSignupRequest> _adminReview({
    required int requestId,
    required String decisionPath,
    String? notes,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'admin',
        'role-signups',
        requestId.toString(),
        decisionPath,
      ],
    );
    if (uri == null) {
      throw const RoleSignupApiException(0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final body = <String, dynamic>{};
      final trimmedNotes = notes?.trim();
      if (trimmedNotes != null && trimmedNotes.isNotEmpty) {
        body['notes'] = trimmedNotes;
      }
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RoleSignupApiException(
            resp.statusCode, _decodeErrorDetail(resp.body));
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final request = decoded['request'] as Map<String, dynamic>;
      return RoleSignupRequest.fromJson(request);
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
