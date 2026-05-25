import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/offline_queue.dart';
import 'package:shamell_flutter/core/payments/payments_attestation.dart';
import 'package:shamell_flutter/main.dart' show LoginPage, TopupPage;

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
    await OfflineQueue.init();
    resetShamellPaymentAttestationTestHooks();
  });

  testWidgets('TopupPage reauths on critical session failure during topup',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response('{"ok":true,"enabled":false}', 200);
      }
      expect(request.url.path, '/payments/wallets/wallet_target/topup');
      expect(request.headers['X-Device-ID'], isNotEmpty);
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['amount_cents'], 100);
      expect(payload.containsKey('amount'), isFalse);
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupPage(
          'https://api.example.com',
          triggerScanOnOpen: true,
          client: client,
          scanLauncher: (_) async => 'TOPUP|wallet=wallet_target|amount=1',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('TopupPage attaches payment attestation headers on topup',
      (tester) async {
    http.Request? topupRequest;
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-topup');
      return 'play-topup-token';
    };
    final client = MockClient((request) async {
      if (request.url.path == '/auth/payment_attestation/challenge') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['operation'], 'payments_topup');
        expect(
            payload['resource_id'], 'wallet_id=wallet_target&amount_cents=100');
        return http.Response(
          '{"ok":true,"enabled":true,"challenge_token":"chal-topup-1","hw_attestation_nonce_b64":"nonce-topup","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.url.path == '/payments/wallets/wallet_target/topup') {
        topupRequest = request;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupPage(
          'https://api.example.com',
          triggerScanOnOpen: true,
          client: client,
          scanLauncher: (_) async => 'TOPUP|wallet=wallet_target|amount=1',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(topupRequest, isNotNull);
    expect(
      topupRequest!.headers[shamellPaymentAttestationChallengeHeader],
      'chal-topup-1',
    );
    expect(
      topupRequest!.headers[shamellPaymentAttestationPlayIntegrityHeader],
      'play-topup-token',
    );
    final payload = jsonDecode(topupRequest!.body) as Map<String, dynamic>;
    expect(payload['amount_cents'], 100);
    expect(payload.containsKey('amount'), isFalse);
  });

  testWidgets('TopupPage scans versioned QR amount cents', (tester) async {
    http.Request? topupRequest;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response('{"ok":true,"enabled":false}', 200);
      }
      if (request.url.path == '/payments/wallets/wallet_usd/topup') {
        topupRequest = request;
        return http.Response('{"ok":true,"currency":"USD"}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupPage(
          'https://api.example.com',
          triggerScanOnOpen: true,
          client: client,
          scanLauncher: (_) async =>
              'shamell://topup?v=2&wallet_id=wallet_usd&currency=USD&amount_cents=250',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(topupRequest, isNotNull);
    final payload = jsonDecode(topupRequest!.body) as Map<String, dynamic>;
    expect(payload['amount_cents'], 250);
    expect(payload.containsKey('currency'), isFalse);
  });

  testWidgets(
      'TopupPage does not queue offline replay when attestation challenge is unavailable',
      (tester) async {
    var topupCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/payment_attestation/challenge') {
        throw SocketException('offline');
      }
      if (request.url.path == '/payments/wallets/wallet_target/topup') {
        topupCalls++;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupPage(
          'https://api.example.com',
          triggerScanOnOpen: true,
          client: client,
          scanLauncher: (_) async => 'TOPUP|wallet=wallet_target|amount=1',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(topupCalls, 0);
    expect(OfflineQueue.pending(tag: 'payments_topup'), isEmpty);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'TopupPage fail-closes voucher redeem when vouchers are unsupported',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupPage(
          'https://api.example.com',
          triggerScanOnOpen: true,
          client: client,
          scanLauncher: (_) async => 'TOPUP|code=abc|sig=sig1|amount=100',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(
      find.text('Topup vouchers are unavailable on this server.'),
      findsOneWidget,
    );
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'TopupPage rejects malformed base urls before network or queue during topup',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupPage(
          'https://user:pass@api.example.com/root',
          triggerScanOnOpen: true,
          client: client,
          scanLauncher: (_) async => 'TOPUP|wallet=wallet_target|amount=1',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(OfflineQueue.pending(tag: 'payments_topup'), isEmpty);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'TopupPage keeps voucher redeem fail-closed before base-url validation',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupPage(
          'https://user:pass@api.example.com/root',
          triggerScanOnOpen: true,
          client: client,
          scanLauncher: (_) async => 'TOPUP|code=abc|sig=sig1|amount=100',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(
      find.text('Topup vouchers are unavailable on this server.'),
      findsOneWidget,
    );
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('TopupPage uses stored wallet from explicit baseUrl scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);
    expect(
      await saveStoredWalletId('wallet_one', baseUrlOverride: originOne),
      isTrue,
    );
    expect(
      await saveStoredWalletId('wallet_two', baseUrlOverride: originTwo),
      isTrue,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: TopupPage(originOne),
      ),
    );

    await tester.pump();
    await tester.pump();

    final walletField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Wallet ID'));
    expect(walletField.controller?.text, 'wallet_one');

    await tester.tap(find.text('Generate Topup QR'));
    await tester.pump();

    expect(find.textContaining('wallet_id=wallet_one'), findsOneWidget);
    expect(find.textContaining('wallet_id=wallet_two'), findsNothing);
  });
}
