import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../session_cookie_store.dart';

/// Subset of canonical workforce roles surfaced in the admin UI.
///
/// Mirrors the server-side `CANONICAL_WORKFORCE_ROLE_PERMISSIONS` allowlist
/// — only roles already validated by the server are offered, so a stale
/// client can't request a never-existed role. New entries here must also
/// appear in the BFF catalog.
const List<String> kSyrComAdminCanonicalRoles = <String>[
  'platform.admin',
  'platform.security_admin',
  'platform.support_l1',
  'platform.support_l2',
  'platform.finance_admin',
  'platform.finance_readonly',
  'platform.ops_manager',
  'audit.readonly',
];

/// Outcome of an admin access-assignment mutation. `error` is null on
/// success; `errorDetail` carries the BFF's `detail` field when it
/// returned a non-2xx.
class AccessAssignmentMutationResult {
  final bool ok;
  final int statusCode;
  final String? error;

  const AccessAssignmentMutationResult.success(this.statusCode)
      : ok = true,
        error = null;
  const AccessAssignmentMutationResult.failure(this.statusCode, this.error)
      : ok = false;
}

/// Derive the deterministic dev workforce_account_id from an email.
///
/// Matches the server's `resolve_or_create_workforce_account` derivation
/// for the dev IdP (`provider=dev`, `issuer=dev-localhost`,
/// `subject=dev:{email_lc}`). For other IdPs the subject differs and this
/// helper won't match — the admin UI is therefore dev-only.
String deriveDevWorkforceAccountIdForEmail(String email) {
  final emailLc = email.trim().toLowerCase();
  final humanIdPayload = utf8.encode('dev|dev-localhost|dev:$emailLc');
  final humanHash = sha256.convert(humanIdPayload).toString();
  final humanId = 'hum_${humanHash.substring(0, 60)}';
  final wfaPayload = utf8.encode('$humanId|workforce');
  final wfaHash = sha256.convert(wfaPayload).toString();
  return 'wfa_${wfaHash.substring(0, 60)}';
}

/// HTTP client for `POST /admin/access/assignments` and `DELETE
/// /admin/access/assignments`. Modeled after the existing `RideRatingApi`
/// pattern: session cookies via `shamellSessionHeadersForBaseUrl`,
/// injectable `http.Client` for tests.
class AccessAdminApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const AccessAdminApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  Future<AccessAssignmentMutationResult> grantWorkforceRole({
    required String workforceAccountId,
    required String roleId,
    /// When non-null the grant attaches an `organization` scope with this
    /// org_id. When null the grant uses the `platform` scope (no
    /// scope_value).
    String? organizationId,
    String? idempotencyKey,
  }) =>
      _mutate(
        method: 'POST',
        workforceAccountId: workforceAccountId,
        roleId: roleId,
        organizationId: organizationId,
        idempotencyKey: idempotencyKey,
      );

  Future<AccessAssignmentMutationResult> revokeWorkforceRole({
    required String workforceAccountId,
    required String roleId,
    String? organizationId,
    String? idempotencyKey,
  }) =>
      _mutate(
        method: 'DELETE',
        workforceAccountId: workforceAccountId,
        roleId: roleId,
        organizationId: organizationId,
        idempotencyKey: idempotencyKey,
      );

  Future<AccessAssignmentMutationResult> _mutate({
    required String method,
    required String workforceAccountId,
    required String roleId,
    String? organizationId,
    String? idempotencyKey,
  }) async {
    if (baseUrl.trim().isEmpty) {
      return const AccessAssignmentMutationResult.failure(0, 'missing base url');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['admin', 'access', 'assignments'],
    );
    if (uri == null) {
      return const AccessAssignmentMutationResult.failure(
          0, 'invalid base url');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] =
          idempotencyKey ?? _defaultIdempotencyKey(workforceAccountId, roleId);
      final scope = organizationId == null
          ? <String, Object?>{'platform': true}
          : <String, Object?>{'organization_id': organizationId};
      final body = jsonEncode(<String, Object?>{
        'workforce_account_id': workforceAccountId,
        'role_id': roleId,
        'scope': scope,
      });
      final req = http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body;
      final streamed = await client.send(req).timeout(_requestTimeout);
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return AccessAssignmentMutationResult.success(resp.statusCode);
      }
      return AccessAssignmentMutationResult.failure(
        resp.statusCode,
        _decodeDetail(resp.body),
      );
    } catch (e) {
      return AccessAssignmentMutationResult.failure(0, e.toString());
    } finally {
      if (closeClient) client.close();
    }
  }

  String _defaultIdempotencyKey(String workforceAccountId, String roleId) {
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return 'syrcom-admin-$workforceAccountId-$roleId-$ts';
  }

  String? _decodeDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
      }
    } catch (_) {
      // fall through
    }
    return null;
  }
}
