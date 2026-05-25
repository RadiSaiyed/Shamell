import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/biometric_enroll_attestation.dart';
import 'package:shamell_flutter/core/biometric_login_attestation.dart';
import 'package:shamell_flutter/core/biometric_login.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

String _bioTokenKeyForBaseUrl(String baseUrl) =>
    'bio_login_token.v3.${Uri.parse(baseUrl).origin}';

http.Response _disabledBiometricEnrollAttestationResponse() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'ok': true,
      'enabled': false,
      'hw_attestation_enabled': false,
      'hw_attestation_required': false,
      'hw_attestation_nonce_b64': '',
      'hw_attestation_providers': const <String>[],
      'expires_at': 0,
    }),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.Response _disabledBiometricLoginAttestationResponse() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'ok': true,
      'enabled': false,
      'hw_attestation_enabled': false,
      'hw_attestation_required': false,
      'hw_attestation_nonce_b64': '',
      'hw_attestation_providers': const <String>[],
      'expires_at': 0,
    }),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://api.shamell.online';
  const sessionToken = '0123456789abcdef0123456789abcdef';
  const storedBiometricToken =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const rotatedBiometricToken =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const nextBiometricToken =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var mutateWriteRoundTrip = false;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = mutateWriteRoundTrip
                ? 'tampered'
                : (args['value'] ?? '').toString();
            return null;
          case 'read':
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    mutateWriteRoundTrip = false;
    await clearSessionCookie();
    await clearBiometricLoginTokenForBaseUrl(baseUrl);
    resetShamellBiometricEnrollAttestationTestHooks();
    resetShamellBiometricLoginAttestationTestHooks();
  });

  test(
      'ensureBiometricLoginEnrolled stores only origin-scoped v3 token material',
      () async {
    secStore['bio_login_token.v1.api.shamell.online'] =
        'legacy-biometric-token';
    secStore['bio_login_token.v2.api.shamell.online'] =
        'legacy-host-scoped-token';
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    final calls = <String>[];

    final mock = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.headers['cookie'], '__Host-sa_session=$sessionToken');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      if (req.url.toString() == '$baseUrl/auth/devices/register') {
        calls.add('register');
        expect((body['device_id'] ?? '').toString().trim(), isNotEmpty);
        return http.Response(
          jsonEncode(<String, Object?>{'device_id': body['device_id']}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.toString() == '$baseUrl/auth/biometric/enroll/challenge') {
        calls.add('challenge');
        expect((body['device_id'] ?? '').toString().trim(), isNotEmpty);
        return _disabledBiometricEnrollAttestationResponse();
      }
      expect(req.url.toString(), '$baseUrl/auth/biometric/enroll');
      calls.add('enroll');
      expect((body['device_id'] ?? '').toString().trim(), isNotEmpty);
      return http.Response(
        jsonEncode(<String, Object?>{'token': rotatedBiometricToken}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final ok = await ensureBiometricLoginEnrolled(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(ok, isTrue);
    expect(calls, <String>['register', 'challenge', 'enroll']);
    expect(
      secStore[_bioTokenKeyForBaseUrl(baseUrl)],
      rotatedBiometricToken,
    );
    expect(
        secStore.containsKey('bio_login_token.v1.api.shamell.online'), isFalse);
    expect(
        secStore.containsKey('bio_login_token.v2.api.shamell.online'), isFalse);
  });

  test('ensureBiometricLoginEnrolled attaches biometric attestation headers',
      () async {
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    shamellBiometricEnrollAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-b64');
      return 'play-attestation-token';
    };
    final calls = <String>[];

    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      if (req.url.toString() == '$baseUrl/auth/devices/register') {
        calls.add('register');
        return http.Response(
          jsonEncode(<String, Object?>{'device_id': body['device_id']}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.toString() == '$baseUrl/auth/biometric/enroll/challenge') {
        calls.add('challenge');
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'enabled': true,
            'challenge_token': 'bio-challenge-1',
            'hw_attestation_nonce_b64': 'nonce-b64',
            'hw_attestation_providers': const <String>[
              'google_play_integrity',
            ],
            'expires_at': 123,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      calls.add('enroll');
      expect(
        req.headers[shamellBiometricEnrollAttestationChallengeHeader],
        'bio-challenge-1',
      );
      expect(
        req.headers[shamellBiometricEnrollAttestationPlayIntegrityHeader],
        'play-attestation-token',
      );
      return http.Response(
        jsonEncode(<String, Object?>{'token': rotatedBiometricToken}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await ensureBiometricLoginEnrolledDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.success);
    expect(calls, <String>['register', 'challenge', 'enroll']);
  });

  test('ensureBiometricLoginEnrolled rejects malformed token response',
      () async {
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);

    final mock = MockClient((req) async {
      if (req.url.toString() == '$baseUrl/auth/devices/register') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{'device_id': body['device_id']}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.toString() == '$baseUrl/auth/biometric/enroll/challenge') {
        return _disabledBiometricEnrollAttestationResponse();
      }
      return http.Response(
        jsonEncode(<String, Object?>{'token': 'not-hex'}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await ensureBiometricLoginEnrolledDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.failed);
    expect(await getBiometricLoginTokenForBaseUrl(baseUrl), isNull);
  });

  test('ensureBiometricLoginEnrolled fails closed when local auth is denied',
      () async {
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      return http.Response('{}', 500);
    });

    final ok = await ensureBiometricLoginEnrolled(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => false,
    );

    expect(ok, isFalse);
    expect(calls, 0);
  });

  test('biometricSignIn fails closed when user-presence prompt is denied',
      () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = storedBiometricToken;
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      return http.Response('{}', 500);
    });

    final ok = await biometricSignIn(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => false,
    );

    expect(ok, isFalse);
    expect(calls, 0);
  });

  test('biometricSignIn ignores legacy host-scoped tokens', () async {
    secStore['bio_login_token.v1.api.shamell.online'] =
        'legacy-biometric-token';
    secStore['bio_login_token.v2.api.shamell.online'] =
        'legacy-host-scoped-token';
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      return http.Response('{}', 500);
    });

    final ok = await biometricSignIn(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(ok, isFalse);
    expect(calls, 0);
    expect(
        secStore.containsKey('bio_login_token.v1.api.shamell.online'), isFalse);
    expect(
        secStore.containsKey('bio_login_token.v2.api.shamell.online'), isFalse);
  });

  test('getBiometricLoginTokenForBaseUrl clears malformed stored v3 token',
      () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = 'bad-token';

    final token = await getBiometricLoginTokenForBaseUrl(baseUrl);

    expect(token, isNull);
    expect(secStore.containsKey(_bioTokenKeyForBaseUrl(baseUrl)), isFalse);
  });

  test(
      'ensureBiometricLoginEnrolled ignores malformed stored v3 token and re-enrolls',
      () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = 'bad-token';
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      if (req.url.toString() == '$baseUrl/auth/devices/register') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{'device_id': body['device_id']}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.toString() == '$baseUrl/auth/biometric/enroll/challenge') {
        return _disabledBiometricEnrollAttestationResponse();
      }
      return http.Response(
        jsonEncode(<String, Object?>{'token': rotatedBiometricToken}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await ensureBiometricLoginEnrolledDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.success);
    expect(calls, 3);
    expect(
      await getBiometricLoginTokenForBaseUrl(baseUrl),
      rotatedBiometricToken,
    );
  });

  test('biometricSignIn refreshes session and rotates v2 token', () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = storedBiometricToken;
    final mock = MockClient((req) async {
      expect(req.method, 'POST');
      if (req.url.toString() == '$baseUrl/auth/biometric/login/challenge') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect(body['token'], storedBiometricToken);
        expect((body['device_id'] ?? '').toString().trim(), isNotEmpty);
        return _disabledBiometricLoginAttestationResponse();
      }
      expect(req.url.toString(), '$baseUrl/auth/biometric/login');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      expect(body['token'], storedBiometricToken);
      expect(body['rotate'], isTrue);
      expect((body['device_id'] ?? '').toString().trim(), isNotEmpty);
      return http.Response(
        jsonEncode(<String, Object?>{'token': nextBiometricToken}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json',
          'set-cookie':
              '__Host-sa_session=fedcba9876543210fedcba9876543210; Path=/; Secure; HttpOnly',
        },
      );
    });

    final ok = await biometricSignIn(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(ok, isTrue);
    expect(
      await getSessionTokenForBaseUrl(baseUrl),
      'fedcba9876543210fedcba9876543210',
    );
    expect(
      secStore[_bioTokenKeyForBaseUrl(baseUrl)],
      nextBiometricToken,
    );
  });

  test('biometricSignIn attaches biometric login attestation headers',
      () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = storedBiometricToken;
    shamellBiometricLoginAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'login-nonce-b64');
      return 'login-play-attestation-token';
    };
    final calls = <String>[];

    final mock = MockClient((req) async {
      if (req.url.toString() == '$baseUrl/auth/biometric/login/challenge') {
        calls.add('challenge');
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect(body['token'], storedBiometricToken);
        expect((body['device_id'] ?? '').toString().trim(), isNotEmpty);
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'enabled': true,
            'challenge_token': 'bio-login-challenge-1',
            'hw_attestation_nonce_b64': 'login-nonce-b64',
            'hw_attestation_providers': const <String>[
              'google_play_integrity',
            ],
            'expires_at': 123,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      calls.add('login');
      expect(
        req.headers[shamellBiometricLoginAttestationChallengeHeader],
        'bio-login-challenge-1',
      );
      expect(
        req.headers[shamellBiometricLoginAttestationPlayIntegrityHeader],
        'login-play-attestation-token',
      );
      return http.Response(
        jsonEncode(<String, Object?>{'token': nextBiometricToken}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json',
          'set-cookie':
              '__Host-sa_session=fedcba9876543210fedcba9876543210; Path=/; Secure; HttpOnly',
        },
      );
    });

    final result = await biometricSignInDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.success);
    expect(calls, <String>['challenge', 'login']);
  });

  test('biometricSignIn clears token when rotation payload is malformed',
      () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    final mock = MockClient((req) async {
      if (req.url.toString() == '$baseUrl/auth/biometric/login/challenge') {
        return _disabledBiometricLoginAttestationResponse();
      }
      return http.Response(
        jsonEncode(<String, Object?>{'token': 'bad-token'}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json',
          'set-cookie':
              '__Host-sa_session=fedcba9876543210fedcba9876543210; Path=/; Secure; HttpOnly',
        },
      );
    });

    final result = await biometricSignInDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.failed);
    expect(await getBiometricLoginTokenForBaseUrl(baseUrl), isNull);
    expect(await getSessionTokenForBaseUrl(baseUrl), isNull);
  });

  test('biometricSignIn clears auth material when rotation token is missing',
      () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = storedBiometricToken;

    final mock = MockClient((req) async {
      if (req.url.toString() == '$baseUrl/auth/biometric/login/challenge') {
        return _disabledBiometricLoginAttestationResponse();
      }
      return http.Response(
        jsonEncode(<String, Object?>{'ok': true}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json',
          'set-cookie':
              '__Host-sa_session=fedcba9876543210fedcba9876543210; Path=/; Secure; HttpOnly',
        },
      );
    });

    final result = await biometricSignInDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.failed);
    expect(await getBiometricLoginTokenForBaseUrl(baseUrl), isNull);
    expect(await getSessionTokenForBaseUrl(baseUrl), isNull);
  });

  test(
      'ensureBiometricLoginEnrolled clears stale auth material on critical session failure',
      () async {
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);

    final mock = MockClient((req) async {
      expect(req.url.toString(), '$baseUrl/auth/devices/register');
      return http.Response(
        jsonEncode(<String, Object?>{'detail': 'device_id mismatch'}),
        403,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await ensureBiometricLoginEnrolledDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.reauthRequired);
    expect(await getSessionTokenForBaseUrl(baseUrl), isNull);
  });

  test('ensureBiometricLoginEnrolled uses origin-scoped stable device id',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await saveStableDeviceId(
        'device-stored',
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isTrue,
    );
    expect(
      await saveStableDeviceId(
        'device-active',
        sp: sp,
        baseUrlOverride: baseUrl,
      ),
      isTrue,
    );
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    final calls = <String>[];

    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      if (req.url.toString() == '$baseUrl/auth/devices/register') {
        calls.add('register');
        expect(body['device_id'], 'device-active');
        return http.Response(
          jsonEncode(<String, Object?>{'device_id': 'device-active'}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.toString() == '$baseUrl/auth/biometric/enroll/challenge') {
        calls.add('challenge');
        expect(body['device_id'], 'device-active');
        return _disabledBiometricEnrollAttestationResponse();
      }
      expect(req.url.toString(), '$baseUrl/auth/biometric/enroll');
      calls.add('enroll');
      expect(body['device_id'], 'device-active');
      return http.Response(
        jsonEncode(<String, Object?>{'token': nextBiometricToken}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await ensureBiometricLoginEnrolledDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.success);
    expect(calls, <String>['register', 'challenge', 'enroll']);
  });

  test('biometricSignIn clears stale biometric token on unauthorized response',
      () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = storedBiometricToken;
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);

    final mock = MockClient((req) async {
      if (req.url.toString() == '$baseUrl/auth/biometric/login/challenge') {
        return _disabledBiometricLoginAttestationResponse();
      }
      return http.Response(
        jsonEncode(<String, Object?>{'detail': 'unauthorized'}),
        401,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await biometricSignInDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.reauthRequired);
    expect(
      secStore.containsKey(_bioTokenKeyForBaseUrl(baseUrl)),
      isFalse,
    );
    expect(await getSessionTokenForBaseUrl(baseUrl), isNull);
  });

  test('biometricSignIn keeps token on transient server failure', () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = storedBiometricToken;

    final mock = MockClient((req) async {
      if (req.url.toString() == '$baseUrl/auth/biometric/login/challenge') {
        return _disabledBiometricLoginAttestationResponse();
      }
      return http.Response(
        jsonEncode(<String, Object?>{'detail': 'temporary upstream issue'}),
        500,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await biometricSignInDetailed(
      baseUrl,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.failed);
    expect(
      secStore[_bioTokenKeyForBaseUrl(baseUrl)],
      storedBiometricToken,
    );
  });

  test('biometric tokens stay isolated across origins on the same host',
      () async {
    const sameHostDifferentPort = 'https://api.shamell.online:444';

    expect(
      await setBiometricLoginTokenForBaseUrl(baseUrl, storedBiometricToken),
      isTrue,
    );

    expect(
      await getBiometricLoginTokenForBaseUrl(sameHostDifferentPort),
      isNull,
    );
    expect(
      await getBiometricLoginTokenForBaseUrl(baseUrl),
      storedBiometricToken,
    );
  });

  test('clearAllBiometricLoginTokens removes tokens across all origins',
      () async {
    const sameHostDifferentPort = 'https://api.shamell.online:444';
    const secondOriginToken =
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

    expect(
      await setBiometricLoginTokenForBaseUrl(baseUrl, storedBiometricToken),
      isTrue,
    );
    expect(
      await setBiometricLoginTokenForBaseUrl(
        sameHostDifferentPort,
        secondOriginToken,
      ),
      isTrue,
    );

    await clearAllBiometricLoginTokens();

    expect(await getBiometricLoginTokenForBaseUrl(baseUrl), isNull);
    expect(
      await getBiometricLoginTokenForBaseUrl(sameHostDifferentPort),
      isNull,
    );
  });

  test('setBiometricLoginTokenForBaseUrl fails on write round-trip mismatch',
      () async {
    mutateWriteRoundTrip = true;

    expect(
      await setBiometricLoginTokenForBaseUrl(baseUrl, storedBiometricToken),
      isFalse,
    );
    expect(
      secStore.containsKey(_bioTokenKeyForBaseUrl(baseUrl)),
      isFalse,
    );
  });

  test(
      'ensureBiometricLoginEnrolled rejects malformed base urls before network',
      () async {
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      return http.Response('{}', 500);
    });

    final ok = await ensureBiometricLoginEnrolled(
      'https://user:pass@api.shamell.online/root',
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(ok, isFalse);
    expect(calls, 0);
  });

  test('ensureBiometricLoginEnrolled sends localhost client-ip header',
      () async {
    const localhostBase = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(localhostBase, sessionToken);
    final calls = <String>[];

    final mock = MockClient((req) async {
      expect(req.headers['x-shamell-client-ip'], '127.0.0.1');
      expect(req.headers['cookie'], '__Host-sa_session=$sessionToken');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      if (req.url.toString() == '$localhostBase/auth/devices/register') {
        calls.add('register');
        return http.Response(
          jsonEncode(<String, Object?>{'device_id': body['device_id']}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.toString() ==
          '$localhostBase/auth/biometric/enroll/challenge') {
        calls.add('challenge');
        return _disabledBiometricEnrollAttestationResponse();
      }
      calls.add('enroll');
      return http.Response(
        jsonEncode(<String, Object?>{'token': rotatedBiometricToken}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final result = await ensureBiometricLoginEnrolledDetailed(
      localhostBase,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.success);
    expect(calls, <String>['register', 'challenge', 'enroll']);
    expect(
      await getBiometricLoginTokenForBaseUrl(localhostBase),
      rotatedBiometricToken,
    );
  });

  test('biometricSignIn rejects malformed base urls before network', () async {
    secStore[_bioTokenKeyForBaseUrl(baseUrl)] = storedBiometricToken;
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      return http.Response('{}', 500);
    });

    final ok = await biometricSignIn(
      'https://user:pass@api.shamell.online/root',
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(ok, isFalse);
    expect(calls, 0);
  });

  test('biometricSignIn sends localhost client-ip header without cookie',
      () async {
    const localhostBase = 'http://127.0.0.1:8080';
    await setBiometricLoginTokenForBaseUrl(localhostBase, storedBiometricToken);
    await setSessionTokenForBaseUrl(localhostBase, sessionToken);

    final mock = MockClient((req) async {
      expect(req.headers['x-shamell-client-ip'], '127.0.0.1');
      expect(req.headers.containsKey('cookie'), isFalse);
      if (req.url.toString() ==
          '$localhostBase/auth/biometric/login/challenge') {
        return _disabledBiometricLoginAttestationResponse();
      }
      return http.Response(
        jsonEncode(<String, Object?>{'token': nextBiometricToken}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json',
          'set-cookie':
              '__Host-sa_session=fedcba9876543210fedcba9876543210; Path=/; Secure; HttpOnly',
        },
      );
    });

    final result = await biometricSignInDetailed(
      localhostBase,
      client: mock,
      promptForBiometricAuth: () async => true,
    );

    expect(result, BiometricFlowResult.success);
    expect(
      await getSessionTokenForBaseUrl(localhostBase),
      'fedcba9876543210fedcba9876543210',
    );
    expect(
      await getBiometricLoginTokenForBaseUrl(localhostBase),
      nextBiometricToken,
    );
  });
}
