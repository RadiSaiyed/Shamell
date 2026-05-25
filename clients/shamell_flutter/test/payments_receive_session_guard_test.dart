import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/offline_queue.dart';
import 'package:shamell_flutter/core/payments/payments_receive.dart';

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
  });

  test('payments payload masking redacts key-value segments', () {
    expect(
      shamellPaymentsMaskSensitivePayloadForDisplay(
        'SONIC|token=0123456789abcdef',
      ),
      'SONIC|token=01***ef',
    );
    expect(
      shamellPaymentsMaskSensitivePayloadForDisplay(
        'PAY|wallet=abcdef12|amount=1234',
      ),
      'PAY|wallet=ab***12|amount=****',
    );
  });

  test('payments payload masking redacts non-segment payloads', () {
    expect(shamellPaymentsMaskSensitivePayloadForDisplay('abcd'), '****');
    expect(
      shamellPaymentsMaskSensitivePayloadForDisplay('abcdefghij'),
      'ab***ij',
    );
  });

  testWidgets('PaymentReceiveTab keeps core receive UI while hiding dead flows',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var walletCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.toString() ==
              'https://api.example.com/payments/wallets/wallet_demo') {
        walletCalls++;
        return http.Response('{"balance_cents":1000}', 200);
      }
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentReceiveTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_demo',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(walletCalls, 1);
    expect(find.text('Offline proximity payment (Sonic)'), findsNothing);
    expect(find.text('Redeem cash‑out code'), findsNothing);
  });

  testWidgets('PaymentReceiveTab masks generated pay payload until reveal',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.toString() ==
              'https://api.example.com/payments/wallets/wallet_demo') {
        return http.Response('{"balance_cents":1000}', 200);
      }
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentReceiveTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_demo',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pump();

    expect(
      find.textContaining('wallet_id=wallet_demo'),
      findsNothing,
    );
    expect(
      find.textContaining('wallet_id=wa***mo'),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets(
      'PaymentReceiveTab reveals localhost QA payload without device auth',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.toString() ==
              'http://127.0.0.1:8080/payments/wallets/wallet_demo') {
        return http.Response('{"balance_cents":1000}', 200);
      }
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentReceiveTab(
            baseUrl: 'http://127.0.0.1:8080',
            fromWalletId: 'wallet_demo',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pump();

    expect(find.textContaining('wallet_id=wa***mo'), findsOneWidget);

    await tester.tap(find.text('Reveal code'));
    await tester.pump();

    expect(find.textContaining('wallet_id=wallet_demo'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.text('Device authentication is required to reveal sensitive data.'),
      findsNothing,
    );
  });

  testWidgets('PaymentReceiveTab rejects malformed base urls before network',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentReceiveTab(
            baseUrl: 'https://user:pass@api.example.com/root',
            fromWalletId: 'wallet_demo',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);

    expect(calls, 0);
    expect(find.text('Offline proximity payment (Sonic)'), findsNothing);
    expect(find.text('Redeem cash‑out code'), findsNothing);
  });

  testWidgets('PaymentReceiveTab hides unfinished sonic and cash sections',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.toString() ==
              'https://api.example.com/payments/wallets/wallet_demo') {
        return http.Response('{"balance_cents":1000}', 200);
      }
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentReceiveTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_demo',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Offline proximity payment (Sonic)'), findsNothing);
    expect(find.text('Redeem cash‑out code'), findsNothing);
    expect(OfflineQueue.pending(tag: 'payments_sonic'), isEmpty);
  });

  testWidgets('PaymentReceiveTab fits large wallet balances on phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.toString() ==
              'https://api.example.com/payments/wallets/wallet_demo') {
        return http.Response(
          '{"balance_cents":100100102,"currency":"SYP"}',
          200,
        );
      }
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentReceiveTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_demo',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('1,001,001.02 SYP'), findsOneWidget);
    final balance = tester.widget<Text>(find.text('1,001,001.02 SYP'));
    expect(balance.maxLines, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PaymentReceiveTab uses stored wallet from explicit baseUrl scope',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final requestedPaths = <String>[];

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

    final client = MockClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path == '/payments/wallets/wallet_one') {
        return http.Response('{"balance_cents":1000}', 200);
      }
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentReceiveTab(
            baseUrl: originOne,
            fromWalletId: '',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(requestedPaths, contains('/payments/wallets/wallet_one'));
    expect(requestedPaths, isNot(contains('/payments/wallets/wallet_two')));
  });
}
