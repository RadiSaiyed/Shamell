import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/biometric_enroll_attestation.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  const baseUrl = 'https://api.shamell.online';
  const sessionToken = '0123456789abcdef0123456789abcdef';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await clearSessionCookie();
    resetShamellBiometricEnrollAttestationTestHooks();
  });

  tearDown(() {
    resetShamellBiometricEnrollAttestationTestHooks();
  });

  test(
      'shamellBuildBiometricEnrollAttestationHeaders fails closed on release when challenge endpoint is missing',
      () async {
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    final client = MockClient((req) async {
      expect(req.url.toString(), '$baseUrl/auth/biometric/enroll/challenge');
      return http.Response('{}', 404);
    });

    expect(
      shamellBuildBiometricEnrollAttestationHeaders(
        baseUrl: baseUrl,
        deviceId: 'device-1',
        client: client,
        isReleaseMode: true,
      ),
      throwsA(isA<BiometricEnrollAttestationUnavailable>()),
    );
  });

  test(
      'shamellBuildBiometricEnrollAttestationHeaders returns challenge and play integrity headers',
      () async {
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    shamellBiometricEnrollAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-b64');
      return 'play-token';
    };

    final client = MockClient((req) async {
      expect(req.headers['cookie'], '__Host-sa_session=$sessionToken');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      expect(body['device_id'], 'device-1');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ok': true,
          'enabled': true,
          'challenge_token': 'challenge-1',
          'hw_attestation_nonce_b64': 'nonce-b64',
          'hw_attestation_providers': const <String>['google_play_integrity'],
          'expires_at': 123,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final headers = await shamellBuildBiometricEnrollAttestationHeaders(
      baseUrl: baseUrl,
      deviceId: 'device-1',
      client: client,
    );

    expect(
      headers,
      <String, String>{
        shamellBiometricEnrollAttestationChallengeHeader: 'challenge-1',
        shamellBiometricEnrollAttestationPlayIntegrityHeader: 'play-token',
      },
    );
  });

  test('BiometricEnrollAttestationHttpFailure redacts raw body in toString',
      () {
    const failure = BiometricEnrollAttestationHttpFailure(
      statusCode: 401,
      rawBody: '{"detail":"attestation required"}',
    );

    expect(failure.toString(), 'biometric enroll attestation failed: 401');
    expect(failure.toString().contains('attestation required'), isFalse);
  });
}
