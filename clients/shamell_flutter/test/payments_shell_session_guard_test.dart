import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/payments/payments_local_store.dart';
import 'package:shamell_flutter/core/payments/payments_shell.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

  Map<String, dynamic> requestItem(
    int n, {
    String status = 'pending',
  }) {
    return <String, dynamic>{
      'id': 'req_$n',
      'status': status,
      'amount_cents': 1000 + n,
      'from_wallet_id': 'wallet_from_$n',
      'to_wallet_id': 'wallet_me',
      'created_at': DateTime.utc(2026, 3, 18, 0, 0, 201 - n).toIso8601String(),
    };
  }

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
  });

  testWidgets('PaymentsPage uses scrollable compact tabs on phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      if (request.url.path == '/wallets/wallet_me/snapshot') {
        return http.Response(
          '{"wallet":{"balance_cents":100100102,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response(
          '{"balance_cents":100100102,"currency":"SYP"}',
          200,
        );
      }
      if (request.url.path == '/payments/requests') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          'https://api.example.com',
          'wallet_me',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.start);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PaymentsPage reauths on critical incoming-request polling failure',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/payments/requests') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (request.url.path == '/wallets/wallet_me/snapshot') {
        return http.Response(
            '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}', 200);
      }
      if (request.url.path == '/payments/savings/overview') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          'https://api.example.com',
          'wallet_me',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'PaymentsPage reauths on critical incoming-request accept failure',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/payments/requests' &&
          request.url.queryParameters['kind'] == 'incoming') {
        return http.Response(
          '[{"id":"req_1","status":"pending","amount_cents":1500,"from_wallet_id":"wallet_from"}]',
          200,
        );
      }
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response('{"enabled":false}', 200);
      }
      if (request.url.path == '/payments/requests/req_1/accept') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (request.url.path == '/wallets/wallet_me/snapshot') {
        return http.Response(
            '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}', 200);
      }
      if (request.url.path == '/payments/savings/overview') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          'https://api.example.com',
          'wallet_me',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Accept & Pay'), findsOneWidget);
    await tester.tap(find.text('Accept & Pay'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'PaymentsPage accept request forwards idempotency, device-id and wallet body',
      (tester) async {
    var incomingCalls = 0;
    var acceptCalled = false;
    final client = MockClient((request) async {
      if (request.url.path == '/payments/requests' &&
          request.url.queryParameters['kind'] == 'incoming') {
        incomingCalls += 1;
        if (incomingCalls == 1) {
          return http.Response(
            '[{"id":"req_1","status":"pending","amount_cents":1500,"from_wallet_id":"wallet_from"}]',
            200,
          );
        }
        return http.Response('[]', 200);
      }
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response('{"enabled":false}', 200);
      }
      if (request.url.path == '/payments/requests/req_1/accept') {
        acceptCalled = true;
        expect(request.method, 'POST');
        expect(request.headers['idempotency-key'], isNotEmpty);
        expect(request.headers['x-device-id'], 'device_1');
        expect(request.body, contains('"to_wallet_id":"wallet_me"'));
        return http.Response('{"ok":true}', 200);
      }
      if (request.url.path == '/wallets/wallet_me/snapshot') {
        return http.Response(
            '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}', 200);
      }
      if (request.url.path == '/payments/savings/overview') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          'https://api.example.com',
          'wallet_me',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Accept & Pay'), findsOneWidget);
    await tester.tap(find.text('Accept & Pay'));
    await tester.pump();
    await tester.pump();

    expect(acceptCalled, isTrue);
  });

  testWidgets('PaymentsPage rejects malformed base urls before request polling',
      (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          'https://user:pass@api.example.com',
          'wallet_me',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(called, isFalse);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(PaymentsPage), findsOneWidget);
  });

  testWidgets('PaymentsPage uses stored wallet from explicit baseUrl scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final requestedWallets = <String>[];

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
      final walletId = request.url.queryParameters['wallet_id'];
      if (walletId != null && walletId.isNotEmpty) {
        requestedWallets.add(walletId);
      }
      if (request.url.path == '/payments/requests') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/wallets/wallet_one/snapshot') {
        return http.Response(
            '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}', 200);
      }
      if (request.url.path == '/payments/savings/overview') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/wallets/wallet_one') {
        return http.Response('{"balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          originOne,
          '',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(requestedWallets, contains('wallet_one'));
    expect(requestedWallets, isNot(contains('wallet_two')));
  });

  testWidgets('PaymentsPage restores seen requests from explicit baseUrl scope',
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
      await saveSeenPaymentRequestIds(
        <String>['req_1'],
        sp: sp,
        baseUrlOverride: originOne,
      ),
      isTrue,
    );
    expect(
      await saveSeenPaymentRequestIds(
        <String>['req_2'],
        sp: sp,
        baseUrlOverride: originTwo,
      ),
      isTrue,
    );

    final client = MockClient((request) async {
      if (request.url.path == '/payments/requests' &&
          request.url.queryParameters['kind'] == 'incoming') {
        return http.Response(
          '[{"id":"req_1","status":"pending","amount_cents":1500,"from_wallet_id":"wallet_from"}]',
          200,
        );
      }
      if (request.url.path == '/wallets/wallet_one/snapshot') {
        return http.Response(
            '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}', 200);
      }
      if (request.url.path == '/payments/savings/overview') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/wallets/wallet_one') {
        return http.Response('{"balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          originOne,
          '',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Accept & Pay'), findsNothing);
  });

  testWidgets(
      'PaymentsPage paginates older incoming request pages until it finds an unseen pending request',
      (tester) async {
    const origin = 'https://api.example.com';
    final requests = <Uri>[];
    final seen = List<String>.generate(
      50,
      (index) => 'req_${100 - index}',
      growable: false,
    );
    expect(
      await saveSeenPaymentRequestIds(
        seen,
        baseUrlOverride: origin,
      ),
      isTrue,
    );

    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/payments/requests' &&
          request.url.queryParameters['kind'] == 'incoming') {
        final beforeId = request.url.queryParameters['before_id'];
        if (beforeId == null) {
          final firstPage = List<Map<String, dynamic>>.generate(
            50,
            (index) => requestItem(100 - index),
            growable: false,
          );
          return http.Response(
            jsonEncode(firstPage),
            200,
          );
        }
        expect(beforeId, 'req_51');
        expect(
          request.url.queryParameters['before_created_at'],
          DateTime.utc(2026, 3, 18, 0, 0, 150).toIso8601String(),
        );
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            requestItem(50),
          ]),
          200,
        );
      }
      if (request.url.path == '/wallets/wallet_me/snapshot') {
        return http.Response(
            '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}', 200);
      }
      if (request.url.path == '/payments/savings/overview') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          origin,
          'wallet_me',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Accept & Pay'), findsOneWidget);
    expect(requests.where((uri) => uri.path == '/payments/requests'),
        hasLength(2));
    expect(
      await loadSeenPaymentRequestIds(baseUrlOverride: origin),
      contains('req_50'),
    );
  });

  testWidgets(
      'PaymentsPage marks only the surfaced newest unseen request as seen',
      (tester) async {
    const origin = 'https://api.example.com';
    final client = MockClient((request) async {
      if (request.url.path == '/payments/requests' &&
          request.url.queryParameters['kind'] == 'incoming') {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            requestItem(3),
            requestItem(2),
            requestItem(1),
          ]),
          200,
        );
      }
      if (request.url.path == '/wallets/wallet_me/snapshot') {
        return http.Response(
            '{"wallet":{"balance_cents":0,"currency":"SYP"},"txns":[]}', 200);
      }
      if (request.url.path == '/payments/savings/overview') {
        return http.Response('{"savings_balance_cents":0}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsPage(
          origin,
          'wallet_me',
          'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('wallet_from_3'), findsOneWidget);
    expect(
      await loadSeenPaymentRequestIds(baseUrlOverride: origin),
      <String>['req_3'],
    );
  });
}
