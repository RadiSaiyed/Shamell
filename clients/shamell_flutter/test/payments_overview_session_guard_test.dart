import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_snapshot_store.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/payments/payments_attestation.dart';
import 'package:shamell_flutter/core/payments/payments_overview.dart';

Future<void> _pumpOverview(
  WidgetTester tester, {
  required http.Client client,
  String baseUrl = 'https://api.example.com',
  String deviceId = 'device_1',
  VoidCallback? onCriticalSessionFailure,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PaymentOverviewTab(
        baseUrl: baseUrl,
        walletId: 'wallet_1',
        deviceId: deviceId,
        client: client,
        onCriticalSessionFailure: onCriticalSessionFailure,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _invokeTopup(WidgetTester tester, double amountMajor) async {
  final dynamic state = tester.state(find.byType(PaymentOverviewTab));
  await state.debugSubmitTopup(amountMajor);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  Completer<void>? delayedSecureRead;
  String? delayedSecureReadKeyContains;

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
            if (delayedSecureRead != null &&
                delayedSecureReadKeyContains != null &&
                key.contains(delayedSecureReadKeyContains!) &&
                !delayedSecureRead!.isCompleted) {
              await delayedSecureRead!.future;
            }
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
    delayedSecureRead = null;
    delayedSecureReadKeyContains = null;
    resetShamellPaymentAttestationTestHooks();
  });

  testWidgets('PaymentOverviewTab reauths on critical topup failure',
      (tester) async {
    var reauthTriggered = false;
    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/wallets/wallet_1/snapshot?limit=25') {
        return http.Response(
          '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/payments/savings/overview?wallet_id=wallet_1') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.toString() ==
          'https://api.example.com/payments/wallets/wallet_1/topup') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(
      tester,
      client: client,
      onCriticalSessionFailure: () => reauthTriggered = true,
    );
    await _invokeTopup(tester, 10);

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'PaymentOverviewTab attaches attestation headers to topup when challenge is enabled',
      (tester) async {
    http.Request? topupRequest;
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-b64');
      return 'play-attest-1';
    };
    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/wallets/wallet_1/snapshot?limit=25') {
        return http.Response(
          '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/auth/payment_attestation/challenge') {
        return http.Response(
          '{"ok":true,"enabled":true,"challenge_token":"chal-topup-1","expires_at":1710000000,"hw_attestation_nonce_b64":"nonce-b64","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/payments/wallets/wallet_1/topup') {
        topupRequest = request;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(tester, client: client);
    await _invokeTopup(tester, 10);

    expect(topupRequest, isNotNull);
    expect(
      topupRequest!.headers[shamellPaymentAttestationChallengeHeader],
      'chal-topup-1',
    );
    expect(
      topupRequest!.headers[shamellPaymentAttestationPlayIntegrityHeader],
      'play-attest-1',
    );
    final payload = jsonDecode(topupRequest!.body) as Map<String, dynamic>;
    expect(payload['amount_cents'], 1000);
    expect(payload.containsKey('amount'), isFalse);
  });

  testWidgets(
      'PaymentOverviewTab prefers stored stable device id for topup binding',
      (tester) async {
    http.Request? topupRequest;
    final stableDeviceId = await getOrCreateStableDeviceId(
      baseUrlOverride: 'https://api.example.com',
    );
    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/wallets/wallet_1/snapshot?limit=25') {
        return http.Response(
          '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/auth/payment_attestation/challenge') {
        return http.Response('{"ok":true,"enabled":false}', 200);
      }
      if (request.url.toString() ==
          'https://api.example.com/payments/wallets/wallet_1/topup') {
        topupRequest = request;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(
      tester,
      client: client,
      deviceId: 'runtime_random_device',
    );
    await _invokeTopup(tester, 10);

    expect(topupRequest, isNotNull);
    expect(topupRequest!.headers['X-Device-ID'], stableDeviceId);
  });

  testWidgets(
      'PaymentOverviewTab fail-closes cashout when vouchers are disabled',
      (tester) async {
    var calls = 0;
    var reauthTriggered = false;
    final client = MockClient((request) async {
      calls++;
      if (request.url.toString() ==
          'https://api.example.com/wallets/wallet_1/snapshot?limit=25') {
        return http.Response(
          '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/payments/savings/overview?wallet_id=wallet_1') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(
      tester,
      client: client,
      onCriticalSessionFailure: () => reauthTriggered = true,
    );
    final dynamic state = tester.state(find.byType(PaymentOverviewTab));
    await expectLater(
      state.debugSubmitCashout(
        amountMajor: 10.0,
        secret: 'secret phrase',
        recipientPhone: '+963955000111',
      ),
      throwsA(isA<StateError>()),
    );

    expect(calls, 2);
    expect(reauthTriggered, isFalse);
    expect(find.text('Cash out (code)'), findsNothing);
  });

  testWidgets('PaymentOverviewTab fail-closes savings moves when disabled',
      (tester) async {
    var calls = 0;
    var reauthTriggered = false;
    final client = MockClient((request) async {
      calls++;
      if (request.url.toString() ==
          'https://api.example.com/wallets/wallet_1/snapshot?limit=25') {
        return http.Response(
          '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(
      tester,
      client: client,
      onCriticalSessionFailure: () => reauthTriggered = true,
    );
    final dynamic state = tester.state(find.byType(PaymentOverviewTab));
    await expectLater(
      state.debugSubmitSavingsMove(
        toSavings: true,
        amountMajor: 10.0,
      ),
      throwsA(isA<StateError>()),
    );

    expect(calls, 2);
    expect(reauthTriggered, isFalse);
    expect(find.text('Savings'), findsNothing);
  });

  testWidgets(
      'PaymentOverviewTab rejects malformed base urls before network across overview actions',
      (tester) async {
    var calls = 0;
    var reauthTriggered = false;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await _pumpOverview(
      tester,
      client: client,
      baseUrl: 'https://user:pass@api.example.com/root',
      onCriticalSessionFailure: () => reauthTriggered = true,
    );

    expect(calls, 0);

    final dynamic state = tester.state(find.byType(PaymentOverviewTab));

    await expectLater(
      state.debugSubmitTopup(10.0),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      state.debugSubmitCashout(
        amountMajor: 10.0,
        secret: 'secret phrase',
        recipientPhone: '+963955000111',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      state.debugSubmitSavingsMove(
        toSavings: true,
        amountMajor: 10.0,
      ),
      throwsA(isA<StateError>()),
    );

    expect(calls, 0);
    expect(reauthTriggered, isFalse);
  });

  testWidgets(
      'PaymentOverviewTab loads cached wallet snapshot and linked cards from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.two.example');
    await saveCachedWalletSnapshotRaw(
      'wallet_1',
      '{"wallet":{"balance_cents":1111,"currency":"SYP"},"txns":[]}',
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveCachedWalletSnapshotRaw(
      'wallet_1',
      '{"wallet":{"balance_cents":2222,"currency":"SYP"},"txns":[]}',
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );
    await saveCachedWalletLinkedCardsRawList(
      <String>[
        '{"label":"Origin One Card","last4":"1111","brand":"visa"}',
      ],
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveCachedWalletLinkedCardsRawList(
      <String>[
        '{"label":"Origin Two Card","last4":"2222","brand":"visa"}',
      ],
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.one.example/wallets/wallet_1/snapshot?limit=25') {
        return http.Response('{}', 500);
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(
      tester,
      client: client,
      baseUrl: 'https://api.one.example',
    );

    expect(find.text('11.11 SYP'), findsOneWidget);
    expect(find.text('Origin One Card'), findsOneWidget);
    expect(find.text('Last 4 digits: 1111'), findsOneWidget);
    expect(find.text('22.22 SYP'), findsNothing);
    expect(find.text('Origin Two Card'), findsNothing);
    expect(find.text('Last 4 digits: 2222'), findsNothing);
  });

  testWidgets('PaymentOverviewTab fits large wallet balances on phone width',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/wallets/wallet_1/snapshot?limit=25') {
        return http.Response(
          '{"wallet":{"balance_cents":100100102,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/wallets/wallet_1/buckets') {
        return http.Response(
          '{"cash_balance_cents":100100102,"promo_credit_cents":0,"refund_credit_cents":0,"corporate_credit_cents":0}',
          200,
        );
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(tester, client: client);
    await tester.pumpAndSettle();

    expect(find.text('1,001,001.02 SYP'), findsOneWidget);
    final walletLabel = tester.widget<Text>(find.text('Wallet'));
    expect(walletLabel.maxLines, 1);
    expect(walletLabel.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PaymentOverviewTab shows cached wallet snapshot before delayed linked cards load finishes',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await saveCachedWalletSnapshotRaw(
      'wallet_1',
      '{"wallet":{"balance_cents":1111,"currency":"SYP"},"txns":[]}',
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveCachedWalletLinkedCardsRawList(
      <String>[
        '{"label":"Origin One Card","last4":"1111","brand":"visa"}',
      ],
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    delayedSecureRead = Completer<void>();
    delayedSecureReadKeyContains = 'account.wallet.linked_cards.v2.';

    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.one.example/wallets/wallet_1/snapshot?limit=25') {
        return http.Response('{}', 500);
      }
      return http.Response('{}', 404);
    });

    await _pumpOverview(
      tester,
      client: client,
      baseUrl: 'https://api.one.example',
    );

    expect(find.text('11.11 SYP'), findsOneWidget);
    expect(find.text('Origin One Card'), findsNothing);

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('11.11 SYP'), findsOneWidget);
    expect(find.text('Origin One Card'), findsOneWidget);
    expect(find.text('Last 4 digits: 1111'), findsOneWidget);
  });
}
