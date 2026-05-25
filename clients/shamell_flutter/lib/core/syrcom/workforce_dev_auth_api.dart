import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../session_cookie_store.dart';

/// Dart-define carrying the base64-encoded HMAC secret shared with the BFF
/// `BFF_WORKFORCE_DEV_AUTH_SHARED_SECRET`. When empty the dev login surface
/// is structurally hidden — prod release builds never compile in a value.
const String kWorkforceDevAuthSecretB64 = String.fromEnvironment(
  'SHAMELL_WORKFORCE_DEV_AUTH_SECRET',
  defaultValue: '',
);

/// Dart-define listing allowlisted dev emails (comma-separated). Mirror of
/// the BFF `BFF_WORKFORCE_DEV_AUTH_ALLOWED_EMAILS` env var; lets the dev
/// sign-in UI surface only the accounts the server will actually accept.
const String kWorkforceDevAuthEmailsCsv = String.fromEnvironment(
  'SHAMELL_WORKFORCE_DEV_AUTH_EMAILS',
  defaultValue: '',
);

/// `true` if and only if a dev workforce auth secret was compiled in.
bool workforceDevAuthAvailable() => kWorkforceDevAuthSecretB64.trim().isNotEmpty;

/// Parsed list of dev emails (lowercased, trimmed, empty entries dropped).
List<String> workforceDevAuthAllowedEmails() {
  return kWorkforceDevAuthEmailsCsv
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty && s.contains('@'))
      .toList(growable: false);
}

/// Outcome of a dev workforce sign-in attempt. `error` is null on success.
class WorkforceDevSignInResult {
  final bool ok;
  final String? error;

  const WorkforceDevSignInResult.success()
      : ok = true,
        error = null;
  const WorkforceDevSignInResult.failure(this.error) : ok = false;
}

/// HMAC-signed dev workforce sign-in client.
///
/// Mirrors the server's verification in `verify_workforce_dev_assertion`:
/// signs `format!("{email_lc}|{ts}")` with the base64-decoded shared
/// secret, posts to `/auth/workforce/session/exchange/dev`, extracts the
/// `__Host-sa_session` token from the response's `Set-Cookie` header, and
/// stores it via `setSessionTokenForBaseUrl` so subsequent
/// `shamellSessionHeadersForBaseUrl` calls attach it automatically.
///
/// Returns `WorkforceDevSignInResult.failure` (never throws) on any error,
/// including: missing/blank dart-define, unreachable BFF, non-2xx, missing
/// session cookie in response. The dev UI surfaces these as a banner.
class WorkforceDevAuthApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const WorkforceDevAuthApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  Future<WorkforceDevSignInResult> signIn({
    required String email,
    String? deviceId,
  }) async {
    final emailLc = email.trim().toLowerCase();
    if (emailLc.isEmpty || !emailLc.contains('@')) {
      return const WorkforceDevSignInResult.failure('invalid email');
    }
    if (baseUrl.trim().isEmpty) {
      return const WorkforceDevSignInResult.failure('missing base url');
    }
    final secretB64 = kWorkforceDevAuthSecretB64.trim();
    if (secretB64.isEmpty) {
      return const WorkforceDevSignInResult.failure(
        'dev workforce auth not compiled into this build',
      );
    }
    final List<int> secret;
    try {
      secret = base64.decode(secretB64);
    } catch (_) {
      return const WorkforceDevSignInResult.failure(
        'dev workforce auth secret is not valid base64',
      );
    }
    if (secret.length < 32) {
      return const WorkforceDevSignInResult.failure(
        'dev workforce auth secret must be at least 32 bytes',
      );
    }
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final mac = Hmac(sha256, secret);
    final tokenBytes = mac.convert(utf8.encode('$emailLc|$ts')).bytes;
    final devToken = base64.encode(tokenBytes);

    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'auth',
        'workforce',
        'session',
        'exchange',
        'dev'
      ],
    );
    if (uri == null) {
      return const WorkforceDevSignInResult.failure('invalid base url');
    }

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final body = jsonEncode(<String, Object?>{
        'email': emailLc,
        'dev_ts': ts,
        'dev_token': devToken,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      });
      final resp = await client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return WorkforceDevSignInResult.failure('HTTP ${resp.statusCode}');
      }
      final setCookie = resp.headers['set-cookie'];
      final token = extractSessionTokenFromSetCookieHeader(setCookie);
      if (token == null || token.isEmpty) {
        return const WorkforceDevSignInResult.failure(
          'no session cookie in response',
        );
      }
      await setSessionTokenForBaseUrl(baseUrl, token);
      return const WorkforceDevSignInResult.success();
    } catch (e) {
      return WorkforceDevSignInResult.failure(e.toString());
    } finally {
      if (closeClient) client.close();
    }
  }
}
