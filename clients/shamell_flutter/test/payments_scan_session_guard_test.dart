import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/payments/payments_attestation.dart';
import 'package:shamell_flutter/core/payments/payments_scan.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

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
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async => 'play-token-$nonceB64';
  });

  tearDown(() {
    resetShamellPaymentAttestationTestHooks();
  });

  testWidgets('PaymentScanTab reauths on critical account session failure',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"enabled":true,"challenge_token":"challenge-1","hw_attestation_nonce_b64":"nonce-1","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      expect(request.url.path, '/payments/transfer');
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentScanTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            autoScan: true,
            client: client,
            scanLauncher: (_) async => 'PAY|wallet=wallet_target|amount=1',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Pay 1 SYP to wallet_target now?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'PaymentScanTab attaches idempotency, device-id and attestation headers',
      (tester) async {
    var transferCalled = false;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/payment_attestation/challenge') {
        final body = request.body;
        expect(body, contains('"operation":"payments_transfer"'));
        expect(body, contains('"resource_id":"from_wallet_id=wallet_me'));
        return http.Response(
          '{"enabled":true,"challenge_token":"challenge-2","hw_attestation_nonce_b64":"nonce-2","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      expect(request.url.path, '/payments/transfer');
      transferCalled = true;
      expect(request.headers['idempotency-key'], isNotEmpty);
      expect(request.headers['x-device-id'], isNotEmpty);
      expect(
        request.headers[shamellPaymentAttestationChallengeHeader.toLowerCase()],
        equals('challenge-2'),
      );
      expect(
        request.headers[
            shamellPaymentAttestationPlayIntegrityHeader.toLowerCase()],
        equals('play-token-nonce-2'),
      );
      final payload = request.body;
      expect(payload, contains('"amount_cents":100'));
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentScanTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            autoScan: true,
            client: client,
            scanLauncher: (_) async => 'PAY|wallet=wallet_target|amount=1',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(find.text('Pay 1 SYP to wallet_target now?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pump();
    await tester.pump();

    expect(transferCalled, isTrue);
    expect(find.text('Payment sent.'), findsOneWidget);
  });

  testWidgets('PaymentScanTab blocks versioned QR currency mismatch',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentScanTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me_syp',
            walletCurrency: 'SYP',
            autoScan: true,
            client: client,
            scanLauncher: (_) async =>
                'shamell://pay?v=2&wallet_id=wallet_target_usd&currency=USD&amount_cents=1050',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(
      find.text(
        'Currency mismatch: this QR is USD, but the open wallet is SYP.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('PaymentScanTab reads versioned QR amount and currency',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentScanTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me_usd',
            walletCurrency: 'USD',
            autoScan: true,
            client: client,
            scanLauncher: (_) async =>
                'shamell://pay?v=2&wallet_id=wallet_target_usd&currency=USD&amount_cents=1050',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(
      find.text('Pay 10.50 USD to wallet_target_usd now?'),
      findsOneWidget,
    );
  });

  testWidgets('PaymentScanTab blocks expired merchant QR', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentScanTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me_usd',
            walletCurrency: 'USD',
            autoScan: true,
            client: client,
            scanLauncher: (_) async =>
                'shamell://pay?v=2&wallet_id=wallet_target_usd&currency=USD&amount_cents=1050&mode=merchant&expires_at=2020-01-01T00%3A00%3A00.000Z',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('This payment QR has expired.'), findsOneWidget);
  });

  testWidgets(
      'PaymentScanTab fails closed when attestation proof is unavailable',
      (tester) async {
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async => null;
    var transferCalled = false;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"enabled":true,"challenge_token":"challenge-3","hw_attestation_nonce_b64":"nonce-3","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.url.path == '/payments/transfer') {
        transferCalled = true;
      }
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentScanTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            autoScan: true,
            client: client,
            scanLauncher: (_) async => 'PAY|wallet=wallet_target|amount=1',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pump();
    await tester.pump();

    expect(transferCalled, isFalse);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('PaymentScanTab rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentScanTab(
            baseUrl: 'https://user:pass@api.example.com/root',
            fromWalletId: 'wallet_me',
            autoScan: true,
            client: client,
            scanLauncher: (_) async => 'PAY|wallet=wallet_target|amount=1',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Pay 1 SYP to wallet_target now?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });
}
