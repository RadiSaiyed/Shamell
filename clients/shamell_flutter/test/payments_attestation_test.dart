import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/payments/payments_attestation.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    resetShamellPaymentAttestationTestHooks();
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );
  });

  Future<Map<String, dynamic>> loadContractFixture() async {
    final raw =
        await File('../../testdata/payment_attestation_contract_vectors.json')
            .readAsString();
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  test('payment attestation resource ids stay canonical', () {
    expect(
      shamellPaymentCreateUserAttestationResourceId(
        accountId: 'acct/demo@x',
      ),
      'account_id=acct%2Fdemo%40x',
    );
    expect(
      shamellPaymentTopupAttestationResourceId(
        walletId: 'wallet 1',
        amountCents: 250,
      ),
      'wallet_id=wallet%201&amount_cents=250',
    );
    expect(
      shamellPaymentTransferAttestationResourceId(
        fromWalletId: 'wallet/me',
        toWalletId: 'wallet target',
        amountCents: 123,
      ),
      'from_wallet_id=wallet%2Fme&to_wallet_id=wallet%20target&amount_cents=123',
    );
    expect(
      shamellPaymentTransferAttestationResourceId(
        fromWalletId: 'wallet/me',
        toAlias: '@merchant',
        amountCents: 123,
      ),
      'from_wallet_id=wallet%2Fme&to_alias=%40merchant&amount_cents=123',
    );
    expect(
      shamellPaymentRequestAcceptAttestationResourceId(
        requestId: 'req/1',
        toWalletId: 'wallet demo',
      ),
      'rid=req%2F1&to_wallet_id=wallet%20demo',
    );
    expect(
      shamellPaymentRequestCreateAttestationResourceId(
        fromWalletId: 'wallet/me',
        toWalletId: 'wallet target',
        amountCents: 123,
      ),
      'from_wallet_id=wallet%2Fme&to_wallet_id=wallet%20target&amount_cents=123',
    );
    expect(
      shamellPaymentRequestCreateAttestationResourceId(
        fromWalletId: 'wallet/me',
        toAlias: '@merchant',
        amountCents: 123,
      ),
      'from_wallet_id=wallet%2Fme&to_alias=%40merchant&amount_cents=123',
    );
    expect(
      shamellPaymentRequestCancelAttestationResourceId(
        requestId: 'req/1',
        fromWalletId: 'wallet demo',
      ),
      'rid=req%2F1&from_wallet_id=wallet%20demo',
    );
    expect(
      shamellPaymentFavoriteCreateAttestationResourceId(
        ownerWalletId: 'wallet/me',
        favoriteWalletId: 'wallet target',
        alias: 'coffee shop',
      ),
      'owner_wallet_id=wallet%2Fme&favorite_wallet_id=wallet%20target&alias=coffee%20shop',
    );
    expect(
      shamellPaymentFavoriteDeleteAttestationResourceId(
        favoriteId: 'fav/1',
        ownerWalletId: 'wallet demo',
      ),
      'fid=fav%2F1&owner_wallet_id=wallet%20demo',
    );
  });

  test('payment major-to-cents conversion is stable for valid decimals', () {
    expect(shamellPaymentAmountMajorToCents(0), 0);
    expect(shamellPaymentAmountMajorToCents(1.23), 123);
    expect(shamellPaymentAmountMajorToCents(12.3), 1230);
  });

  test('payment major-to-cents rejects negative and non-finite values', () {
    expect(
      () => shamellPaymentAmountMajorToCents(-1.23),
      throwsA(isA<PaymentMutationAttestationUnavailable>()),
    );
    expect(
      () => shamellPaymentAmountMajorToCents(double.nan),
      throwsA(isA<PaymentMutationAttestationUnavailable>()),
    );
    expect(
      () => shamellPaymentAmountMajorToCents(double.infinity),
      throwsA(isA<PaymentMutationAttestationUnavailable>()),
    );
  });

  test('payment attestation contract vectors stay in sync with BFF', () async {
    final fixture = await loadContractFixture();
    final headers = Map<String, dynamic>.from(
      fixture['header_names'] as Map,
    );
    expect(
      shamellPaymentAttestationChallengeHeader,
      headers['challenge'],
    );
    expect(
      shamellPaymentAttestationPlayIntegrityHeader,
      headers['play_integrity'],
    );
    expect(
      shamellPaymentAttestationAppleDeviceCheckHeader,
      headers['apple_devicecheck'],
    );

    final vectors = (fixture['resource_vectors'] as List)
        .cast<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
    for (final vector in vectors) {
      final operation = vector['operation'] as String;
      final expected = vector['resource_id'] as String;
      late final String actual;
      switch (operation) {
        case 'payments_create_user':
          actual = shamellPaymentCreateUserAttestationResourceId(
            accountId: vector['account_id'] as String,
          );
          break;
        case 'payments_topup':
          actual = shamellPaymentTopupAttestationResourceId(
            walletId: vector['wallet_id'] as String,
            amountCents: vector['amount_cents'] as int,
          );
          break;
        case 'payments_transfer':
          actual = shamellPaymentTransferAttestationResourceId(
            fromWalletId: vector['from_wallet_id'] as String,
            toWalletId: vector['to_wallet_id'] as String?,
            toAlias: vector['to_alias'] as String?,
            amountCents: vector['amount_cents'] as int,
          );
          break;
        case 'payments_requests_accept':
          actual = shamellPaymentRequestAcceptAttestationResourceId(
            requestId: vector['request_id'] as String,
            toWalletId: vector['to_wallet_id'] as String,
          );
          break;
        case 'payments_requests_create':
          actual = shamellPaymentRequestCreateAttestationResourceId(
            fromWalletId: vector['from_wallet_id'] as String,
            toWalletId: vector['to_wallet_id'] as String?,
            toAlias: vector['to_alias'] as String?,
            amountCents: vector['amount_cents'] as int,
          );
          break;
        case 'payments_requests_cancel':
          actual = shamellPaymentRequestCancelAttestationResourceId(
            requestId: vector['request_id'] as String,
            fromWalletId: vector['from_wallet_id'] as String,
          );
          break;
        case 'payments_favorites_create':
          actual = shamellPaymentFavoriteCreateAttestationResourceId(
            ownerWalletId: vector['owner_wallet_id'] as String,
            favoriteWalletId: vector['favorite_wallet_id'] as String,
            alias: vector['alias'] as String?,
          );
          break;
        case 'payments_favorites_delete':
          actual = shamellPaymentFavoriteDeleteAttestationResourceId(
            favoriteId: vector['favorite_id'] as String,
            ownerWalletId: vector['owner_wallet_id'] as String,
          );
          break;
        default:
          fail('unexpected operation in contract fixture: $operation');
      }
      expect(actual, expected, reason: 'operation=$operation');
    }
  });

  test(
      'payment mutation attestation helper returns empty headers on 404 outside release mode',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/payment_attestation/challenge');
      return http.Response('{}', 404);
    });

    final headers = await shamellBuildPaymentMutationAttestationHeaders(
      baseUrl: 'https://api.example.com',
      deviceId: 'device_1',
      operation: 'payments_topup',
      resourceId: shamellPaymentTopupAttestationResourceId(
        walletId: 'wallet_1',
        amountCents: 100,
      ),
      client: client,
      isReleaseMode: false,
    );

    expect(headers, isEmpty);
  });

  test('payment auth bypass is limited to localhost QA builds', () {
    expect(
      shamellAllowLocalhostQaPaymentAuthBypass(
        'http://127.0.0.1:19480',
        isReleaseMode: false,
      ),
      isTrue,
    );
    expect(
      shamellAllowLocalhostQaPaymentAuthBypass(
        'http://127.0.0.1:19480',
        isReleaseMode: true,
        allowLocalhostHttpInRelease: true,
      ),
      isTrue,
    );
    expect(
      shamellAllowLocalhostQaPaymentAuthBypass(
        'https://api.shamell.online',
        isReleaseMode: true,
      ),
      isFalse,
    );
    expect(
      shamellAllowLocalhostQaPaymentAuthBypass(
        'http://127.0.0.1:19480',
        isReleaseMode: true,
        allowLocalhostHttpInRelease: false,
      ),
      isFalse,
    );
    expect(
      shamellAllowLocalhostQaPaymentAuthBypass(
        'http://127.0.0.1:19480',
        isReleaseMode: false,
        allowLocalhostHttpInRelease: true,
      ),
      isTrue,
    );
  });

  test(
      'payment mutation attestation bypass skips challenge fetch on localhost QA release',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('unexpected', 500);
    });

    final headers = await shamellBuildPaymentMutationAttestationHeaders(
      baseUrl: 'http://127.0.0.1:19480',
      deviceId: 'device_1',
      operation: 'payments_topup',
      resourceId: shamellPaymentTopupAttestationResourceId(
        walletId: 'wallet_1',
        amountCents: 100,
      ),
      client: client,
      isReleaseMode: true,
      allowLocalhostHttpInRelease: true,
    );

    expect(headers, isEmpty);
    expect(requests, 0);
  });

  test(
      'payment mutation attestation bypass skips challenge fetch on localhost QA debug',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('unexpected', 500);
    });

    final headers = await shamellBuildPaymentMutationAttestationHeaders(
      baseUrl: 'http://127.0.0.1:19480',
      deviceId: 'device_1',
      operation: 'payments_topup',
      resourceId: shamellPaymentTopupAttestationResourceId(
        walletId: 'wallet_1',
        amountCents: 100,
      ),
      client: client,
      isReleaseMode: false,
    );

    expect(headers, isEmpty);
    expect(requests, 0);
  });

  test(
      'payment mutation attestation helper fails closed on 404 in release mode',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/payment_attestation/challenge');
      return http.Response('{}', 404);
    });

    await expectLater(
      shamellBuildPaymentMutationAttestationHeaders(
        baseUrl: 'https://api.example.com',
        deviceId: 'device_1',
        operation: 'payments_topup',
        resourceId: shamellPaymentTopupAttestationResourceId(
          walletId: 'wallet_1',
          amountCents: 100,
        ),
        client: client,
        isReleaseMode: true,
      ),
      throwsA(isA<PaymentMutationAttestationUnavailable>()),
    );
  });

  test('payment mutation attestation helper forwards challenge and play token',
      () async {
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-b64');
      return 'play-token-1';
    };
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/payment_attestation/challenge');
      expect(
        request.headers['cookie'],
        '__Host-sa_session=0123456789abcdef0123456789abcdef',
      );
      expect(request.headers['content-type'], 'application/json');
      expect(
        jsonDecode(request.body),
        <String, Object?>{
          'device_id': 'device_1',
          'operation': 'payments_transfer',
          'resource_id':
              'from_wallet_id=wallet_me&to_wallet_id=wallet_peer&amount_cents=250',
        },
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'ok': true,
          'enabled': true,
          'challenge_token': 'challenge-1',
          'expires_at': 1710000000,
          'hw_attestation_nonce_b64': 'nonce-b64',
          'hw_attestation_providers': <String>['google_play_integrity'],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final headers = await shamellBuildPaymentMutationAttestationHeaders(
      baseUrl: 'https://api.example.com',
      deviceId: 'device_1',
      operation: 'payments_transfer',
      resourceId: shamellPaymentTransferAttestationResourceId(
        fromWalletId: 'wallet_me',
        toWalletId: 'wallet_peer',
        amountCents: 250,
      ),
      client: client,
    );

    expect(
      headers[shamellPaymentAttestationChallengeHeader],
      'challenge-1',
    );
    expect(
      headers[shamellPaymentAttestationPlayIntegrityHeader],
      'play-token-1',
    );
    expect(
      headers.containsKey(shamellPaymentAttestationAppleDeviceCheckHeader),
      isFalse,
    );
  });

  test(
      'payment mutation attestation helper fails closed when token fetch fails',
      () async {
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async => null;
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'ok': true,
          'enabled': true,
          'challenge_token': 'challenge-1',
          'expires_at': 1710000000,
          'hw_attestation_nonce_b64': 'nonce-b64',
          'hw_attestation_providers': <String>['google_play_integrity'],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await expectLater(
      shamellBuildPaymentMutationAttestationHeaders(
        baseUrl: 'https://api.example.com',
        deviceId: 'device_1',
        operation: 'payments_topup',
        resourceId: shamellPaymentTopupAttestationResourceId(
          walletId: 'wallet_1',
          amountCents: 100,
        ),
        client: client,
      ),
      throwsA(isA<PaymentMutationAttestationUnavailable>()),
    );
  });

  test('payment attestation http failure redacts raw backend body in toString',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/payment_attestation/challenge');
      return http.Response(
        '{"detail":"secret-internal-debug-body"}',
        500,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await expectLater(
      shamellBuildPaymentMutationAttestationHeaders(
        baseUrl: 'https://api.example.com',
        deviceId: 'device_1',
        operation: 'payments_topup',
        resourceId: shamellPaymentTopupAttestationResourceId(
          walletId: 'wallet_1',
          amountCents: 100,
        ),
        client: client,
      ),
      throwsA(
        isA<PaymentMutationAttestationHttpFailure>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('payment attestation failed: 500'),
                isNot(contains('secret-internal-debug-body')),
              ),
            ),
      ),
    );
  });
}
