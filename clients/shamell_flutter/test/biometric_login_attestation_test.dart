import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/biometric_login_attestation.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://api.shamell.online';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetShamellBiometricLoginAttestationTestHooks();
    await clearSessionCookie();
  });

  test('biometric login attestation challenge 404 fails closed in release',
      () async {
    final mock = MockClient((req) async {
      expect(req.url.toString(), '$baseUrl/auth/biometric/login/challenge');
      return http.Response('missing', 404);
    });

    expect(
      () => shamellBuildBiometricLoginAttestationHeaders(
        baseUrl: baseUrl,
        deviceId: 'device-1',
        biometricToken:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        client: mock,
        isReleaseMode: true,
      ),
      throwsA(isA<BiometricLoginAttestationUnavailable>()),
    );
  });

  test(
      'biometric login attestation http failure redacts raw backend body in toString',
      () {
    const failure = BiometricLoginAttestationHttpFailure(
      statusCode: 401,
      rawBody: '{"detail":"attestation required","token":"secret"}',
    );

    expect(failure.toString(), 'biometric login attestation failed: 401');
    expect(failure.toString(), isNot(contains('secret')));
  });

  test('biometric login attestation builds play-integrity headers', () async {
    shamellBiometricLoginAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-b64');
      return 'play-attestation-token';
    };

    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      expect(body['device_id'], 'device-1');
      expect(
        body['token'],
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'ok': true,
          'enabled': true,
          'challenge_token': 'bio-login-challenge-1',
          'hw_attestation_nonce_b64': 'nonce-b64',
          'hw_attestation_providers': const <String>[
            'google_play_integrity',
          ],
          'expires_at': 123,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final headers = await shamellBuildBiometricLoginAttestationHeaders(
      baseUrl: baseUrl,
      deviceId: 'device-1',
      biometricToken:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      client: mock,
    );

    expect(
      headers[shamellBiometricLoginAttestationChallengeHeader],
      'bio-login-challenge-1',
    );
    expect(
      headers[shamellBiometricLoginAttestationPlayIntegrityHeader],
      'play-attestation-token',
    );
  });
}
