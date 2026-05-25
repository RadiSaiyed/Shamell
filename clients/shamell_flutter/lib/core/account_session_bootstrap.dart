import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'account_create_pow.dart';
import 'account_identity_store.dart';
import 'account_snapshot_store.dart';
import 'app_surface.dart';
import 'base_url.dart';
import 'device_id.dart';
import 'device_binding_guard.dart';
import 'hardware_attestation.dart';
import 'privacy_redaction.dart';
import 'session_cookie_store.dart';
import 'shamell_user_id.dart';

const Duration _bootstrapRequestTimeout = Duration(seconds: 15);
const Duration _bootstrapRuntimeAttestationTimeout = Duration(seconds: 4);
const Duration _bootstrapDeviceIdTimeout = Duration(seconds: 6);
const String _bootstrapAppSurfaceHeader = 'x-shamell-app-surface';
const bool _bootstrapDiagnosticLogs =
    bool.fromEnvironment('SHAMELL_DIAGNOSTIC_BOOTSTRAP_LOGS');

final Map<String, Future<AccountSessionBootstrapAttemptOutcome>>
    _bootstrapAttemptInflightByBase =
    <String, Future<AccountSessionBootstrapAttemptOutcome>>{};

bool shamellAllowLegacyAccountCreateChallengeFallback({
  bool isReleaseMode = kReleaseMode,
}) =>
    !isReleaseMode;

enum AccountSessionBootstrapResult {
  success,
  failed,
  reauthRequired,
}

class AccountSessionBootstrapAttemptOutcome {
  final AccountSessionBootstrapResult result;
  final int? failureStatusCode;
  final String? failureRawBody;
  final Object? failureError;
  final bool challengePhase;

  const AccountSessionBootstrapAttemptOutcome({
    required this.result,
    this.failureStatusCode,
    this.failureRawBody,
    this.failureError,
    this.challengePhase = false,
  });
}

class AccountHomeSnapshot {
  final Map<String, dynamic> payload;
  final String rawBody;
  final String shamellId;
  final String walletId;

  const AccountHomeSnapshot({
    required this.payload,
    required this.rawBody,
    required this.shamellId,
    required this.walletId,
  });
}

String _extractBootstrapDetail(String body) {
  final text = body.trim();
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final detail = (decoded['detail'] ?? '').toString().trim();
      if (detail.isNotEmpty) return detail;
    }
  } catch (_) {}
  return text;
}

bool _containsCriticalBootstrapDetail(String? rawBody) {
  final detail = _extractBootstrapDetail(rawBody ?? '').toLowerCase();
  return detail.contains('device_id mismatch') ||
      detail.contains('client_device_id mismatch') ||
      detail.contains('auth session required') ||
      detail.contains('authentication required') ||
      detail.contains('unauthorized');
}

AccountSessionBootstrapResult _classifyBootstrapHttpFailure({
  required int statusCode,
  String? rawBody,
}) {
  final detail = _extractBootstrapDetail(rawBody ?? '').toLowerCase();
  if (statusCode == 410 &&
      (detail.contains('username/password') ||
          detail.contains('sign-up') ||
          detail.contains('sign-in'))) {
    return AccountSessionBootstrapResult.reauthRequired;
  }
  if (statusCode == 401) {
    if (detail.contains('attestation required')) {
      return AccountSessionBootstrapResult.failed;
    }
    return AccountSessionBootstrapResult.reauthRequired;
  }
  if (statusCode < 400) return AccountSessionBootstrapResult.failed;
  return _containsCriticalBootstrapDetail(rawBody)
      ? AccountSessionBootstrapResult.reauthRequired
      : AccountSessionBootstrapResult.failed;
}

class _BootstrapFailure implements Exception {
  const _BootstrapFailure(this.outcome);

  final AccountSessionBootstrapAttemptOutcome outcome;
}

String shamellAccountSessionBootstrapFailureMessage(
  AccountSessionBootstrapAttemptOutcome outcome, {
  String fallbackMessage = 'Could not establish authenticated session.',
}) {
  if (outcome.result == AccountSessionBootstrapResult.reauthRequired) {
    return 'auth session required';
  }
  final failureError = outcome.failureError;
  if (failureError != null) {
    final text = failureError.toString().trim();
    if (text.isNotEmpty) return text;
  }
  final detail = _extractBootstrapDetail(outcome.failureRawBody ?? '');
  if (detail.isNotEmpty) return detail;
  return fallbackMessage;
}

Exception shamellAccountSessionBootstrapFailureException(
  AccountSessionBootstrapAttemptOutcome outcome, {
  String fallbackMessage = 'Could not establish authenticated session.',
}) {
  return Exception(
    shamellAccountSessionBootstrapFailureMessage(
      outcome,
      fallbackMessage: fallbackMessage,
    ),
  );
}

@visibleForTesting
Future<Map<String, String>> shamellBootstrapHeadersForBaseUrl(
  String baseUrl, {
  bool json = false,
  bool includeSessionCookie = true,
}) async {
  final headers = await shamellSessionHeadersForBaseUrl(
    baseUrl,
    json: json,
    includeSessionCookie: includeSessionCookie,
  );
  headers[_bootstrapAppSurfaceHeader] = shamellActiveAppSurface.name;
  return headers;
}

Future<AccountSessionBootstrapResult>
    ensureSessionCookieViaAccountCreateDetailed({
  required String baseUrl,
  http.Client? client,
  bool forceCreate = false,
}) async {
  return (await ensureSessionCookieViaAccountCreateAttempt(
    baseUrl: baseUrl,
    client: client,
    forceCreate: forceCreate,
  ))
      .result;
}

Future<AccountSessionBootstrapAttemptOutcome>
    ensureSessionCookieViaAccountCreateAttempt({
  required String baseUrl,
  http.Client? client,
  bool forceCreate = false,
}) async {
  final base = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (base == null) {
    return const AccountSessionBootstrapAttemptOutcome(
      result: AccountSessionBootstrapResult.failed,
    );
  }

  final inflight = _bootstrapAttemptInflightByBase[base];
  if (inflight != null) {
    return await inflight;
  }

  final future = _ensureSessionCookieViaAccountCreateAttemptInner(
    base: base,
    client: client,
    forceCreate: forceCreate,
  );
  _bootstrapAttemptInflightByBase[base] = future;
  try {
    return await future;
  } finally {
    if (identical(_bootstrapAttemptInflightByBase[base], future)) {
      _bootstrapAttemptInflightByBase.remove(base);
    }
  }
}

Future<AccountSessionBootstrapAttemptOutcome>
    _ensureSessionCookieViaAccountCreateAttemptInner({
  required String base,
  http.Client? client,
  required bool forceCreate,
}) async {
  final runtimeIntegrityFailClosed =
      await HardwareAttestation.isRuntimeIntegrityFailClosed()
          .timeout(_bootstrapRuntimeAttestationTimeout, onTimeout: () => true);
  final runtimeState = await HardwareAttestation.getRuntimeCompromiseState()
      .timeout(_bootstrapRuntimeAttestationTimeout, onTimeout: () {
    if (!runtimeIntegrityFailClosed) {
      return RuntimeCompromiseState.safe;
    }
    return const RuntimeCompromiseState(
      compromised: true,
      signals: <String>['runtime_compromise_check_timeout'],
    );
  });
  if (runtimeState.compromised) {
    return AccountSessionBootstrapAttemptOutcome(
      result: AccountSessionBootstrapResult.failed,
      failureError: Exception('device attestation unavailable'),
    );
  }

  final existing = (await getSessionCookieHeader(base) ?? '').trim();
  if (existing.isNotEmpty && !forceCreate) {
    return const AccountSessionBootstrapAttemptOutcome(
      result: AccountSessionBootstrapResult.success,
    );
  }

  final did = (await getOrCreateStableDeviceId(baseUrlOverride: base)
          .timeout(_bootstrapDeviceIdTimeout, onTimeout: () => ''))
      .trim();
  if (did.isEmpty) {
    return AccountSessionBootstrapAttemptOutcome(
      result: AccountSessionBootstrapResult.failed,
      failureError: Exception('device_id required'),
    );
  }

  final ownedClient = client == null;
  final httpClient = client ?? shamellHttpClient();
  var createRequestStarted = false;
  try {
    Future<
        ({
          String? challengeToken,
          String? powSolution,
          String? iosDeviceCheckTokenB64,
          String? androidPlayIntegrityToken,
        })?> prepareChallenge() async {
      final challengeResp = await httpClient
          .post(
            Uri.parse('$base/auth/account/create/challenge'),
            headers: await shamellBootstrapHeadersForBaseUrl(
              base,
              json: true,
              includeSessionCookie: false,
            ),
            body: jsonEncode(<String, Object?>{
              'device_id': did,
            }),
          )
          .timeout(_bootstrapRequestTimeout);

      if (challengeResp.statusCode == 404) {
        if (!shamellAllowLegacyAccountCreateChallengeFallback()) {
          throw _BootstrapFailure(
            AccountSessionBootstrapAttemptOutcome(
              result: AccountSessionBootstrapResult.failed,
              failureStatusCode: challengeResp.statusCode,
              failureRawBody: challengeResp.body,
              challengePhase: true,
            ),
          );
        }
        return (
          challengeToken: null,
          powSolution: null,
          iosDeviceCheckTokenB64: null,
          androidPlayIntegrityToken: null,
        );
      }
      if (challengeResp.statusCode != 200) {
        throw _BootstrapFailure(
          AccountSessionBootstrapAttemptOutcome(
            result: _classifyBootstrapHttpFailure(
              statusCode: challengeResp.statusCode,
              rawBody: challengeResp.body,
            ),
            failureStatusCode: challengeResp.statusCode,
            failureRawBody: challengeResp.body,
            challengePhase: true,
          ),
        );
      }

      final decoded = jsonDecode(challengeResp.body);
      if (decoded is! Map) {
        throw _BootstrapFailure(
          const AccountSessionBootstrapAttemptOutcome(
            result: AccountSessionBootstrapResult.failed,
            failureError:
                FormatException('invalid bootstrap challenge response'),
            challengePhase: true,
          ),
        );
      }

      String? challengeToken =
          (decoded['challenge_token'] ?? '').toString().trim();
      String? powSolution;
      String? iosToken;
      String? androidToken;

      final hwEnabled = decoded['hw_attestation_enabled'] == true;
      final hwRequired = decoded['hw_attestation_required'] == true;
      final hwNonceB64 =
          (decoded['hw_attestation_nonce_b64'] ?? '').toString().trim();
      if (hwEnabled) {
        iosToken = await HardwareAttestation.tryGetAppleDeviceCheckTokenB64();
        androidToken = await HardwareAttestation.tryGetPlayIntegrityToken(
          nonceB64: hwNonceB64,
        );
        final hwOk = (iosToken != null && iosToken.trim().isNotEmpty) ||
            (androidToken != null && androidToken.trim().isNotEmpty);
        if (!hwOk && hwRequired) {
          throw _BootstrapFailure(
            AccountSessionBootstrapAttemptOutcome(
              result: AccountSessionBootstrapResult.failed,
              failureRawBody: '{"detail":"attestation required"}',
              failureError: Exception('attestation required'),
              challengePhase: true,
            ),
          );
        }
      }

      if (decoded['enabled'] == true) {
        final nonce = (decoded['nonce'] ?? '').toString().trim();
        final diffRaw = decoded['difficulty_bits'];
        final diffBits = diffRaw is num
            ? diffRaw.toInt()
            : int.tryParse((diffRaw ?? '').toString()) ?? -1;
        if ((challengeToken == null || challengeToken.trim().isEmpty) ||
            nonce.isEmpty ||
            diffBits < 0) {
          throw _BootstrapFailure(
            AccountSessionBootstrapAttemptOutcome(
              result: AccountSessionBootstrapResult.failed,
              failureError: const FormatException(
                'invalid account-create challenge payload',
              ),
              challengePhase: true,
            ),
          );
        }
        powSolution = await compute(
          shamellSolveAccountCreatePow,
          <String, Object?>{
            'nonce': nonce,
            'device_id': did,
            'difficulty_bits': diffBits,
            'max_millis': 15000,
            'max_iters': 50000000,
          },
        );
        if (powSolution == null || powSolution.trim().isEmpty) {
          throw _BootstrapFailure(
            AccountSessionBootstrapAttemptOutcome(
              result: AccountSessionBootstrapResult.failed,
              failureError: Exception('proof-of-work solve failed'),
              challengePhase: true,
            ),
          );
        }
        powSolution = powSolution.trim();
      }

      return (
        challengeToken:
            (challengeToken != null && challengeToken.trim().isNotEmpty)
                ? challengeToken.trim()
                : null,
        powSolution: powSolution,
        iosDeviceCheckTokenB64: (iosToken != null && iosToken.trim().isNotEmpty)
            ? iosToken.trim()
            : null,
        androidPlayIntegrityToken:
            (androidToken != null && androidToken.trim().isNotEmpty)
                ? androidToken.trim()
                : null,
      );
    }

    Future<http.Response> doCreate(
      ({
        String? challengeToken,
        String? powSolution,
        String? iosDeviceCheckTokenB64,
        String? androidPlayIntegrityToken,
      })? attestation,
    ) async {
      return httpClient
          .post(
            Uri.parse('$base/auth/account/create'),
            headers: await shamellBootstrapHeadersForBaseUrl(
              base,
              json: true,
              includeSessionCookie: false,
            ),
            body: jsonEncode(<String, Object?>{
              'device_id': did,
              if (attestation?.challengeToken != null)
                'challenge_token': attestation!.challengeToken,
              if (attestation?.powSolution != null)
                'pow_solution': attestation!.powSolution,
              if (attestation?.iosDeviceCheckTokenB64 != null)
                'ios_devicecheck_token_b64':
                    attestation!.iosDeviceCheckTokenB64,
              if (attestation?.androidPlayIntegrityToken != null)
                'android_play_integrity_token':
                    attestation!.androidPlayIntegrityToken,
            }),
          )
          .timeout(_bootstrapRequestTimeout);
    }

    var attestation = await prepareChallenge();
    createRequestStarted = true;
    var createResp = await doCreate(attestation);

    if (createResp.statusCode == 401) {
      final detail = _extractBootstrapDetail(createResp.body).toLowerCase();
      if (detail.contains('attestation required')) {
        attestation = await prepareChallenge();
        createRequestStarted = true;
        createResp = await doCreate(attestation);
      }
    }

    if (createResp.statusCode != 200) {
      return AccountSessionBootstrapAttemptOutcome(
        result: _classifyBootstrapHttpFailure(
          statusCode: createResp.statusCode,
          rawBody: createResp.body,
        ),
        failureStatusCode: createResp.statusCode,
        failureRawBody: createResp.body,
        challengePhase: false,
      );
    }

    final sessionToken = extractSessionTokenFromSetCookieHeader(
        createResp.headers['set-cookie']);
    if (sessionToken == null || sessionToken.isEmpty) {
      return AccountSessionBootstrapAttemptOutcome(
        result: AccountSessionBootstrapResult.failed,
        failureError: Exception('missing session cookie'),
      );
    }
    await setSessionTokenForBaseUrl(base, sessionToken);
    // Persist SyrChat ID immediately from account-create response so profile
    // identity does not depend on a later /me/home_snapshot refresh.
    try {
      final decoded = jsonDecode(createResp.body);
      if (decoded is Map) {
        final rawShamellId = (decoded['shamell_id'] ?? '').toString().trim();
        final normalizedShamellId = rawShamellId.toUpperCase();
        if (isValidShamellUserId(normalizedShamellId)) {
          await saveStoredShamellUserId(
            normalizedShamellId,
            baseUrlOverride: base,
          );
        }
      }
    } catch (_) {}
    return const AccountSessionBootstrapAttemptOutcome(
      result: AccountSessionBootstrapResult.success,
    );
  } on _BootstrapFailure catch (e) {
    return e.outcome;
  } catch (e) {
    return AccountSessionBootstrapAttemptOutcome(
      result: AccountSessionBootstrapResult.failed,
      failureError: e,
      challengePhase: !createRequestStarted,
    );
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}

@visibleForTesting
void debugResetAccountSessionBootstrapInflightState() {
  _bootstrapAttemptInflightByBase.clear();
}

Future<bool> ensureSessionCookieViaAccountCreate({
  required String baseUrl,
  http.Client? client,
  bool forceCreate = false,
}) async {
  return (await ensureSessionCookieViaAccountCreateDetailed(
        baseUrl: baseUrl,
        client: client,
        forceCreate: forceCreate,
      )) ==
      AccountSessionBootstrapResult.success;
}

Future<AccountHomeSnapshot> refreshAndPersistAccountHomeSnapshot({
  required String baseUrl,
  http.Client? client,
  bool ensureSession = true,
}) async {
  final base = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (base == null) {
    throw Exception('Invalid API base URL. Configure HTTPS base_url.');
  }

  final ownedClient = client == null;
  final httpClient = client ?? shamellHttpClient();
  try {
    if (ensureSession) {
      final outcome = await ensureSessionCookieViaAccountCreateAttempt(
        baseUrl: base,
        client: httpClient,
      );
      if (_bootstrapDiagnosticLogs) {
        debugPrint(
          'HOME_SNAPSHOT_SESSION: origin=present result=${outcome.result.name} '
          'status=${outcome.failureStatusCode ?? 0}',
        );
      }
      if (outcome.result != AccountSessionBootstrapResult.success) {
        throw shamellAccountSessionBootstrapFailureException(outcome);
      }
    }

    final response = await httpClient
        .get(
          Uri.parse('$base/me/home_snapshot'),
          headers: await shamellBootstrapHeadersForBaseUrl(base),
        )
        .timeout(_bootstrapRequestTimeout);

    if (response.statusCode != 200) {
      if (shamellIsCriticalAccountSessionHttpFailure(
        statusCode: response.statusCode,
        rawBody: response.body,
      )) {
        await clearSessionCookie();
        throw Exception('auth session required');
      }
      final detail = _extractBootstrapDetail(response.body);
      if (detail.isNotEmpty) {
        throw Exception(detail);
      }
      throw Exception(
        'Failed to load account snapshot (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid account snapshot response.');
    }
    if (_bootstrapDiagnosticLogs) {
      final rawRoles = decoded['roles'];
      final roles = rawRoles is List
          ? rawRoles.map((item) => item.toString()).join(',')
          : '';
      debugPrint(
        'HOME_SNAPSHOT_OK: origin=present shamell_id=${shamellMaskIdentifier((decoded['shamell_id'] ?? '').toString(), prefix: 2, suffix: 2)} '
        'role_count=${roles.isEmpty ? 0 : roles.split(",").where((item) => item.trim().isNotEmpty).length} '
        'superadmin=${decoded['is_superadmin'] == true}',
      );
    }

    final shamellId =
        (decoded['shamell_id'] ?? '').toString().trim().toUpperCase();
    final normalizedShamellId =
        isValidShamellUserId(shamellId) ? shamellId : '';
    final cachedShamellId = ((await loadStoredShamellUserId(
              baseUrlOverride: base,
            )) ??
            '')
        .trim()
        .toUpperCase();
    final effectiveShamellId = normalizedShamellId.isNotEmpty
        ? normalizedShamellId
        : (isValidShamellUserId(cachedShamellId) ? cachedShamellId : '');
    var walletId = (decoded['wallet_id'] ?? '').toString().trim();
    if (walletId.isEmpty) {
      final wallet = decoded['wallet'];
      if (wallet is Map<String, dynamic>) {
        walletId =
            (wallet['wallet_id'] ?? wallet['id'] ?? '').toString().trim();
      }
    }
    if (walletId.isEmpty) {
      walletId = ((await loadStoredWalletId(
                baseUrlOverride: base,
              )) ??
              '')
          .trim();
    }

    await saveCachedHomeSnapshotRaw(response.body, baseUrlOverride: base);
    await saveStoredWalletId(walletId, baseUrlOverride: base);
    await saveStoredShamellUserId(
      effectiveShamellId,
      baseUrlOverride: base,
    );

    return AccountHomeSnapshot(
      payload: decoded,
      rawBody: response.body,
      shamellId: effectiveShamellId,
      walletId: walletId,
    );
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}
