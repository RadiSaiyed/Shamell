import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'account_create_pow.dart';
import 'base_url.dart';
import 'device_id.dart';
import 'hardware_attestation.dart';
import 'session_cookie_store.dart';

const Duration _bootstrapRequestTimeout = Duration(seconds: 15);

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

Future<Map<String, String>> _bootstrapHeaders(
  String baseUrl, {
  bool json = false,
}) async {
  final out = <String, String>{};
  if (json) out['content-type'] = 'application/json';
  final host = Uri.tryParse(baseUrl)?.host.toLowerCase();
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
    out['x-shamell-client-ip'] = '127.0.0.1';
  }
  final cookie = await getSessionCookieHeader(baseUrl);
  if (cookie != null && cookie.isNotEmpty) {
    out['cookie'] = cookie;
  }
  return out;
}

Future<bool> ensureSessionCookieViaAccountCreate({
  required String baseUrl,
  http.Client? client,
  bool forceCreate = false,
}) async {
  final base = baseUrl.trim();
  if (base.isEmpty || !isSecureApiBaseUrl(base)) return false;

  final existing = (await getSessionCookieHeader(base) ?? '').trim();
  if (existing.isNotEmpty && !forceCreate) return true;

  final did = (await getOrCreateStableDeviceId()).trim();
  if (did.isEmpty) return false;

  final ownedClient = client == null;
  final httpClient = client ?? http.Client();
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
            headers: await _bootstrapHeaders(base, json: true),
            body: jsonEncode(<String, Object?>{
              'device_id': did,
            }),
          )
          .timeout(_bootstrapRequestTimeout);

      if (challengeResp.statusCode == 404) {
        return (
          challengeToken: null,
          powSolution: null,
          iosDeviceCheckTokenB64: null,
          androidPlayIntegrityToken: null,
        );
      }
      if (challengeResp.statusCode != 200) return null;

      final decoded = jsonDecode(challengeResp.body);
      if (decoded is! Map) return null;

      String? challengeToken =
          (decoded['challenge_token'] ?? decoded['token'] ?? '')
              .toString()
              .trim();
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
        if (!hwOk && hwRequired) return null;
      }

      if (decoded['enabled'] == true) {
        final token = (decoded['token'] ?? '').toString().trim();
        final nonce = (decoded['nonce'] ?? '').toString().trim();
        final diffRaw = decoded['difficulty_bits'];
        final diffBits = diffRaw is num
            ? diffRaw.toInt()
            : int.tryParse((diffRaw ?? '').toString()) ?? -1;
        if (token.isEmpty || nonce.isEmpty || diffBits < 0) return null;
        if (challengeToken == null || challengeToken.trim().isEmpty) {
          challengeToken = token;
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
        if (powSolution == null || powSolution.trim().isEmpty) return null;
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
            headers: await _bootstrapHeaders(base, json: true),
            body: jsonEncode(<String, Object?>{
              'device_id': did,
              if (attestation?.challengeToken != null)
                'challenge_token': attestation!.challengeToken,
              if (attestation?.challengeToken != null)
                'pow_token': attestation!.challengeToken,
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
    var createResp = await doCreate(attestation);

    if (createResp.statusCode == 401) {
      final detail = _extractBootstrapDetail(createResp.body).toLowerCase();
      if (detail.contains('attestation required')) {
        attestation = await prepareChallenge();
        createResp = await doCreate(attestation);
      }
    }

    if (createResp.statusCode != 200) return false;

    final sessionToken = extractSessionTokenFromSetCookieHeader(
        createResp.headers['set-cookie']);
    if (sessionToken == null || sessionToken.isEmpty) return false;
    await setSessionTokenForBaseUrl(base, sessionToken);
    return true;
  } catch (_) {
    return false;
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}
