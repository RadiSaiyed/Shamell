import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/account_session_bootstrap.dart';
import 'package:shamell_flutter/core/account_snapshot_store.dart';
import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/shamell_user_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const baseUrl = 'http://127.0.0.1:8080';
  const sessionToken = '0123456789abcdef0123456789abcdef';
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
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
    shamellSetActiveAppSurface(ShamellAppSurface.superapp);
    debugResetAccountSessionBootstrapInflightState();
    await wipeCachedAccountSnapshots();
    await clearSessionCookie();
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
  });

  test('bootstrap headers reject credentialed or path-prefixed base urls',
      () async {
    final credentialed = await shamellBootstrapHeadersForBaseUrl(
      'http://evil.test@127.0.0.1:8080',
      json: true,
    );
    final pathPrefixed = await shamellBootstrapHeadersForBaseUrl(
      'http://127.0.0.1:8080/auth',
      json: true,
    );

    expect(credentialed['content-type'], 'application/json');
    expect(credentialed.containsKey('cookie'), isFalse);
    expect(credentialed.containsKey('x-shamell-client-ip'), isFalse);
    expect(credentialed['x-shamell-app-surface'], 'superapp');

    expect(pathPrefixed['content-type'], 'application/json');
    expect(pathPrefixed.containsKey('cookie'), isFalse);
    expect(pathPrefixed.containsKey('x-shamell-client-ip'), isFalse);
    expect(pathPrefixed['x-shamell-app-surface'], 'superapp');
  });

  test(
      'bootstrap headers can omit local session cookie for unauthenticated flows',
      () async {
    final headers = await shamellBootstrapHeadersForBaseUrl(
      baseUrl,
      json: true,
      includeSessionCookie: false,
    );

    expect(headers['content-type'], 'application/json');
    expect(headers['x-shamell-client-ip'], '127.0.0.1');
    expect(headers['x-shamell-app-surface'], 'superapp');
    expect(headers.containsKey('cookie'), isFalse);
  });

  test('bootstrap headers include the active standalone app surface', () async {
    shamellSetActiveAppSurface(ShamellAppSurface.driver);

    final headers = await shamellBootstrapHeadersForBaseUrl(
      baseUrl,
      json: true,
      includeSessionCookie: false,
    );

    expect(headers['x-shamell-app-surface'], 'driver');
  });

  test('legacy account-create challenge fallback is disabled in release mode',
      () {
    expect(
      shamellAllowLegacyAccountCreateChallengeFallback(isReleaseMode: false),
      isTrue,
    );
    expect(
      shamellAllowLegacyAccountCreateChallengeFallback(isReleaseMode: true),
      isFalse,
    );
  });

  test('refreshAndPersistAccountHomeSnapshot stores wallet and SyrChat ID',
      () async {
    const otherBaseUrl = 'https://api.other.example';
    await saveCachedHomeSnapshotRaw(
      '{"wallet":{"wallet_id":"other-origin-cache"}}',
      baseUrlOverride: otherBaseUrl,
    );
    expect(
      await saveStoredWalletId(
        'wallet-other-origin',
        baseUrlOverride: otherBaseUrl,
      ),
      isTrue,
    );
    expect(
      await saveStoredShamellUserId(
        'HGFEDCBA',
        baseUrlOverride: otherBaseUrl,
      ),
      isTrue,
    );
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), '$baseUrl/me/home_snapshot');
      expect(req.headers['cookie'], '__Host-sa_session=$sessionToken');
      expect(req.headers['x-shamell-client-ip'], '127.0.0.1');
      return http.Response(
        jsonEncode(<String, Object?>{
          'shamell_id': 'ABCD2345',
          'wallet': <String, Object?>{
            'wallet_id': 'wallet-first-launch',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final snapshot = await refreshAndPersistAccountHomeSnapshot(
      baseUrl: baseUrl,
      client: mock,
      ensureSession: false,
    );

    expect(snapshot.shamellId, 'ABCD2345');
    expect(snapshot.walletId, 'wallet-first-launch');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('wallet_id'), isNull);
    expect(sp.getString('sa.user_id'), isNull);
    expect(
      await loadStoredWalletId(baseUrlOverride: baseUrl),
      'wallet-first-launch',
    );
    expect(await loadShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
    expect(
      await loadStoredWalletId(baseUrlOverride: otherBaseUrl),
      'wallet-other-origin',
    );
    expect(await loadShamellUserId(baseUrlOverride: otherBaseUrl), 'HGFEDCBA');
    expect(sp.getString('home_snapshot'), isNull);
    expect(
      await loadCachedHomeSnapshotRaw(baseUrlOverride: baseUrl),
      contains('wallet-first-launch'),
    );
    expect(
      await loadCachedHomeSnapshotRaw(baseUrlOverride: otherBaseUrl),
      contains('other-origin-cache'),
    );
  });

  test(
      'refreshAndPersistAccountHomeSnapshot preserves cached SyrChat ID when snapshot omits it',
      () async {
    await saveStoredShamellUserId('ABCD2345', baseUrlOverride: baseUrl);
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), '$baseUrl/me/home_snapshot');
      return http.Response(
        jsonEncode(<String, Object?>{
          'wallet': <String, Object?>{
            'wallet_id': 'wallet-no-shamell-id',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final snapshot = await refreshAndPersistAccountHomeSnapshot(
      baseUrl: baseUrl,
      client: mock,
      ensureSession: false,
    );

    expect(snapshot.shamellId, 'ABCD2345');
    expect(await loadShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
    expect(await loadStoredShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
  });

  test(
      'refreshAndPersistAccountHomeSnapshot keeps SyrChat ID even when wallet context is missing',
      () async {
    await saveStoredWalletId('wallet-stale', baseUrlOverride: baseUrl);
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), '$baseUrl/me/home_snapshot');
      return http.Response(
        jsonEncode(<String, Object?>{
          'shamell_id': 'ABCD2345',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final snapshot = await refreshAndPersistAccountHomeSnapshot(
      baseUrl: baseUrl,
      client: mock,
      ensureSession: false,
    );

    expect(snapshot.shamellId, 'ABCD2345');
    expect(snapshot.walletId, 'wallet-stale');
    expect(await loadShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
    expect(await loadStoredWalletId(baseUrlOverride: baseUrl), 'wallet-stale');
  });

  test(
      'refreshAndPersistAccountHomeSnapshot preserves cached SyrChat ID when snapshot value is invalid',
      () async {
    await saveStoredShamellUserId('ABCD2345', baseUrlOverride: baseUrl);
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), '$baseUrl/me/home_snapshot');
      return http.Response(
        jsonEncode(<String, Object?>{
          'shamell_id': 'invalid-id',
          'wallet': <String, Object?>{
            'wallet_id': 'wallet-invalid-shamell-id',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final snapshot = await refreshAndPersistAccountHomeSnapshot(
      baseUrl: baseUrl,
      client: mock,
      ensureSession: false,
    );

    expect(snapshot.shamellId, 'ABCD2345');
    expect(await loadShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
    expect(await loadStoredShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
  });

  test(
      'ensureSessionCookieViaAccountCreateDetailed fails closed on critical bootstrap failures',
      () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      fail('unexpected request: ${req.url}');
    });

    final result = await ensureSessionCookieViaAccountCreateDetailed(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(result, AccountSessionBootstrapResult.reauthRequired);
  });

  test(
      'ensureSessionCookieViaAccountCreateAttempt exposes create-phase auth-boundary failure details',
      () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      fail('unexpected request: ${req.url}');
    });

    final outcome = await ensureSessionCookieViaAccountCreateAttempt(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(outcome.result, AccountSessionBootstrapResult.reauthRequired);
    expect(outcome.failureStatusCode, 401);
    expect(outcome.failureRawBody, contains('auth session required'));
    expect(outcome.failureError, isNull);
    expect(outcome.challengePhase, isFalse);
  });

  test('retired account-create challenge is treated as reauth required',
      () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response(
          '{"detail":"only username/password sign-up and sign-in are supported"}',
          410,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      fail('unexpected request: ${req.url}');
    });

    final outcome = await ensureSessionCookieViaAccountCreateAttempt(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(outcome.result, AccountSessionBootstrapResult.reauthRequired);
    expect(outcome.failureStatusCode, 410);
    expect(outcome.challengePhase, isTrue);
  });

  test(
      'ensureSessionCookieViaAccountCreateDetailed keeps attestation-required bootstrap as ordinary failure',
      () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"attestation required"}', 401);
      }
      fail('unexpected request: ${req.url}');
    });

    final result = await ensureSessionCookieViaAccountCreateDetailed(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(result, AccountSessionBootstrapResult.failed);
  });

  test(
      'ensureSessionCookieViaAccountCreateDetailed persists SyrChat ID from account-create response',
      () async {
    await clearStoredShamellUserId(baseUrlOverride: baseUrl);
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response(
          '{"ok":true,"shamell_id":"ABCD2345"}',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'set-cookie':
                '__Host-sa_session=ffffffffffffffffffffffffffffffff; Path=/; HttpOnly; Secure; SameSite=Lax',
          },
        );
      }
      fail('unexpected request: ${req.url}');
    });

    final result = await ensureSessionCookieViaAccountCreateDetailed(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(result, AccountSessionBootstrapResult.success);
    expect(await loadShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
  });

  test(
      'ensureSessionCookieViaAccountCreateAttempt exposes challenge-phase transport errors for retry policies',
      () async {
    final mock = MockClient((req) async {
      throw Exception('SocketException: timed out');
    });

    final outcome = await ensureSessionCookieViaAccountCreateAttempt(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(outcome.result, AccountSessionBootstrapResult.failed);
    expect(outcome.failureStatusCode, isNull);
    expect(outcome.failureRawBody, isNull);
    expect(outcome.failureError, isNotNull);
    expect(outcome.failureError.toString(), contains('SocketException'));
    expect(outcome.challengePhase, isTrue);
  });

  test(
      'ensureSessionCookieViaAccountCreateAttempt surfaces required attestation when no hardware token can be minted',
      () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'enabled': false,
            'hw_attestation_enabled': true,
            'hw_attestation_required': true,
            'hw_attestation_nonce_b64': 'AAAAAAAAAAAAAAAAAAAA',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      fail('unexpected request: ${req.url}');
    });

    final outcome = await ensureSessionCookieViaAccountCreateAttempt(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(outcome.result, AccountSessionBootstrapResult.failed);
    expect(outcome.failureStatusCode, isNull);
    expect(outcome.failureRawBody, contains('attestation required'));
    expect(outcome.failureError, isNotNull);
    expect(outcome.failureError.toString(), contains('attestation required'));
    expect(outcome.challengePhase, isTrue);
  });

  test(
      'refreshAndPersistAccountHomeSnapshot preserves critical bootstrap resets during ensureSession',
      () async {
    await clearSessionCookie();
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      fail('unexpected request: ${req.url}');
    });

    await expectLater(
      () => refreshAndPersistAccountHomeSnapshot(
        baseUrl: baseUrl,
        client: mock,
        ensureSession: true,
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );
  });

  test(
      'refreshAndPersistAccountHomeSnapshot preserves noncritical bootstrap failure details during ensureSession',
      () async {
    await clearSessionCookie();
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"attestation required"}', 401);
      }
      fail('unexpected request: ${req.url}');
    });

    await expectLater(
      () => refreshAndPersistAccountHomeSnapshot(
        baseUrl: baseUrl,
        client: mock,
        ensureSession: true,
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('attestation required'),
        ),
      ),
    );
  });

  test(
      'refreshAndPersistAccountHomeSnapshot clears stale session on critical home snapshot failure',
      () async {
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), '$baseUrl/me/home_snapshot');
      expect(req.headers['cookie'], '__Host-sa_session=$sessionToken');
      return http.Response(
        '{"detail":"device_id mismatch"}',
        401,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await expectLater(
      () => refreshAndPersistAccountHomeSnapshot(
        baseUrl: baseUrl,
        client: mock,
        ensureSession: false,
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'refreshAndPersistAccountHomeSnapshot keeps session on noncritical home snapshot failure',
      () async {
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), '$baseUrl/me/home_snapshot');
      expect(req.headers['cookie'], '__Host-sa_session=$sessionToken');
      return http.Response(
        '{"detail":"temporary outage"}',
        503,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await expectLater(
      () => refreshAndPersistAccountHomeSnapshot(
        baseUrl: baseUrl,
        client: mock,
        ensureSession: false,
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('temporary outage'),
        ),
      ),
    );
    expect(
      await getSessionCookieHeader(baseUrl),
      '__Host-sa_session=$sessionToken',
    );
  });

  test(
      'ensureSessionCookieViaAccountCreateDetailed rejects malformed base urls',
      () async {
    final mock = MockClient((req) async {
      fail('unexpected request: ${req.url}');
    });

    final result = await ensureSessionCookieViaAccountCreateDetailed(
      baseUrl: 'http://evil.test@127.0.0.1:8080',
      client: mock,
      forceCreate: true,
    );

    expect(result, AccountSessionBootstrapResult.failed);
  });

  test(
      'ensureSessionCookieViaAccountCreateDetailed accepts challenge-token-only PoW bootstrap',
      () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        expect(req.headers.containsKey('cookie'), isFalse);
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'enabled': true,
            'challenge_token': 'challenge-only-token',
            'nonce': 'abcdef0123456789',
            'difficulty_bits': 0,
            'expires_at': 4102444800,
            'hw_attestation_enabled': false,
            'hw_attestation_required': false,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/auth/account/create') {
        expect(req.headers.containsKey('cookie'), isFalse);
        final decoded = jsonDecode(req.body) as Map<String, dynamic>;
        expect(decoded['challenge_token'], 'challenge-only-token');
        expect(decoded.containsKey('pow_token'), isFalse);
        expect((decoded['pow_solution'] ?? '').toString().trim(), isNotEmpty);
        expect(decoded.containsKey('token'), isFalse);
        return http.Response(
          '{"ok":true}',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'set-cookie':
                '__Host-sa_session=ffffffffffffffffffffffffffffffff; Path=/; HttpOnly; Secure; SameSite=Lax',
          },
        );
      }
      fail('unexpected request: ${req.url}');
    });

    final result = await ensureSessionCookieViaAccountCreateDetailed(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(result, AccountSessionBootstrapResult.success);
    expect(
      await getSessionCookieHeader(baseUrl),
      '__Host-sa_session=ffffffffffffffffffffffffffffffff',
    );
  });

  test(
      'ensureSessionCookieViaAccountCreateDetailed uses origin-scoped stable device id',
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

    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        expect(req.headers.containsKey('cookie'), isFalse);
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        expect(req.headers.containsKey('cookie'), isFalse);
        final decoded = jsonDecode(req.body) as Map<String, Object?>;
        expect(decoded['device_id'], 'device-active');
        return http.Response(
          '{"ok":true}',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'set-cookie':
                '__Host-sa_session=ffffffffffffffffffffffffffffffff; Path=/; HttpOnly; Secure; SameSite=Lax',
          },
        );
      }
      fail('unexpected request: ${req.url}');
    });

    final result = await ensureSessionCookieViaAccountCreateDetailed(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );

    expect(result, AccountSessionBootstrapResult.success);
  });

  test(
      'ensureSessionCookieViaAccountCreateAttempt deduplicates concurrent bootstrap for the same base url',
      () async {
    await clearSessionCookie();
    final createStarted = Completer<void>();
    final releaseCreate = Completer<void>();
    var challengeCalls = 0;
    var createCalls = 0;

    final mock = MockClient((req) async {
      if (req.url.path == '/auth/account/create/challenge') {
        challengeCalls += 1;
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        createCalls += 1;
        if (!createStarted.isCompleted) {
          createStarted.complete();
        }
        await releaseCreate.future;
        return http.Response(
          '{"ok":true,"shamell_id":"ABCD2345"}',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'set-cookie':
                '__Host-sa_session=ffffffffffffffffffffffffffffffff; Path=/; HttpOnly; Secure; SameSite=Lax',
          },
        );
      }
      fail('unexpected request: ${req.url}');
    });

    final first = ensureSessionCookieViaAccountCreateAttempt(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );
    await createStarted.future;
    final second = ensureSessionCookieViaAccountCreateAttempt(
      baseUrl: baseUrl,
      client: mock,
      forceCreate: true,
    );
    releaseCreate.complete();

    final outcomes =
        await Future.wait(<Future<AccountSessionBootstrapAttemptOutcome>>[
      first,
      second,
    ]);

    expect(
      outcomes.map((outcome) => outcome.result).toList(),
      everyElement(AccountSessionBootstrapResult.success),
    );
    expect(challengeCalls, 1);
    expect(createCalls, 1);
    expect(
      await getSessionCookieHeader(baseUrl),
      '__Host-sa_session=ffffffffffffffffffffffffffffffff',
    );
  });
}
