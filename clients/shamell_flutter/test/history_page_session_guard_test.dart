import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/history_page.dart';
import 'package:shamell_flutter/core/offline_queue.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

import 'fakes/fake_payment_event_gateway.dart';

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

  // Cycle 3C: HistoryPage's realtime-event source is now injectable via
  // [HistoryPage.paymentEventGateway]. Each test installs a fresh
  // [FakePaymentEventGateway] in [setUp] and tears it down so the
  // production [PaymentEventStream] singleton never opens its real SSE
  // socket inside the widget-test environment. This eliminates the
  // pre-3C `!timersPending` flake caused by the 500ms reconnect Timer.
  late FakePaymentEventGateway paymentEventGateway;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    await OfflineQueue.clearPersistentState();
    paymentEventGateway = FakePaymentEventGateway();
    addTearDown(paymentEventGateway.dispose);
  });

  Map<String, dynamic> historyTxn(int n) {
    return <String, dynamic>{
      'id': 'txn_$n',
      'from_wallet_id': n.isOdd ? 'wallet_demo' : 'wallet_peer',
      'to_wallet_id': n.isOdd ? 'wallet_peer' : 'wallet_demo',
      'amount_cents': 100 + n,
      'fee_cents': 0,
      'kind': 'transfer',
      'created_at': DateTime.utc(2026, 3, 18, 0, 0, 26 - n).toIso8601String(),
    };
  }

  String historySnapshotResponse(List<Map<String, dynamic>> txns) {
    return jsonEncode(<String, dynamic>{
      'wallet': <String, dynamic>{
        'wallet_id': 'wallet_demo',
        'balance_cents': 4200,
        'currency': 'USD',
      },
      'txns': txns,
    });
  }

  testWidgets('HistoryPage reauths on critical account session failure',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/wallets/wallet_demo/snapshot?limit=25',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          client: client,
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('HistoryPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: 'https://user:pass@example.com/root',
          walletId: 'wallet_demo',
          client: client,
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('HistoryPage avoids overflow on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          initialTxns: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'txn_narrow',
              'from_wallet_id': 'wallet_demo',
              'to_wallet_id': 'wallet_peer_with_a_very_long_identifier_123456',
              'amount_cents': 10000,
              'fee_cents': 150,
              'kind': 'transfer',
              'created_at':
                  DateTime.utc(2026, 4, 7, 0, 3, 44).toIso8601String(),
              'reference': 'transfer history overflow regression check',
            },
          ],
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Wallet history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HistoryPage sends localhost client-ip header on snapshot load',
      (tester) async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        '$baseUrl/wallets/wallet_demo/snapshot?limit=25',
      );
      expect(request.headers['x-shamell-client-ip'], '127.0.0.1');
      expect(
        request.headers['cookie'],
        '__Host-sa_session=0123456789abcdef0123456789abcdef',
      );
      return http.Response(
          historySnapshotResponse(const <Map<String, dynamic>>[]), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: baseUrl,
          walletId: 'wallet_demo',
          client: client,
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
  });

  testWidgets('HistoryPage paginates older wallet snapshot pages with cursor',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final seenUris = <Uri>[];
    final client = MockClient((request) async {
      seenUris.add(request.url);
      final beforeId = request.url.queryParameters['before_id'];
      if (beforeId == null) {
        expect(request.url.queryParameters['limit'], '25');
        final page = List<Map<String, dynamic>>.generate(
          25,
          historyTxn,
          growable: false,
        );
        return http.Response(historySnapshotResponse(page), 200);
      }
      expect(beforeId, 'txn_25');
      expect(
        request.url.queryParameters['before_created_at'],
        DateTime.utc(2026, 3, 18, 0, 0, 1).toIso8601String(),
      );
      final page = <Map<String, dynamic>>[historyTxn(26)];
      return http.Response(historySnapshotResponse(page), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          client: client,
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Load more'), findsOneWidget);

    final loadMoreButton = tester.widget<OutlinedButton>(
      find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    expect(loadMoreButton.onPressed, isNotNull);
    loadMoreButton.onPressed!.call();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(seenUris, hasLength(2));
  });

  testWidgets('HistoryPage refetches first page when kind filter changes',
      (tester) async {
    final seenUris = <Uri>[];
    final client = MockClient((request) async {
      seenUris.add(request.url);
      final kind = request.url.queryParameters['kind'];
      final page = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': kind == 'bill' ? 'txn_bill_1' : 'txn_transfer_1',
          'from_wallet_id': 'wallet_demo',
          'to_wallet_id': 'wallet_peer',
          'amount_cents': 500,
          'fee_cents': 0,
          'kind': kind ?? 'transfer',
          'created_at': DateTime.utc(2026, 3, 18, 0, 0, 1).toIso8601String(),
        }
      ];
      return http.Response(historySnapshotResponse(page), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          client: client,
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Bills'));
    await tester.pump();
    await tester.pump();

    expect(seenUris, hasLength(2));
    expect(seenUris.first.queryParameters.containsKey('kind'), isFalse);
    expect(seenUris.last.queryParameters['kind'], 'bill');
    expect(seenUris.last.queryParameters.containsKey('before_created_at'),
        isFalse);
    expect(seenUris.last.queryParameters.containsKey('before_id'), isFalse);
  });

  testWidgets(
      'HistoryPage shows offline pending tasks from explicit baseUrl scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);
    await OfflineQueue.enqueue(
      OfflineTask(
        id: 'pending-one',
        method: 'POST',
        url: '$originOne/payments/transfer',
        headers: const <String, String>{
          'Idempotency-Key': 'k-history',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":42}',
        tag: 'payments_transfer',
        createdAt: 9,
      ),
      baseUrlOverride: originOne,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: originOne,
          walletId: 'wallet_demo',
          initialTxns: const <Map<String, dynamic>>[],
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Pending (offline)'), findsOneWidget);
  });

  testWidgets('HistoryPage custom date filters wrap on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const baseUrl = 'https://api.example.com';
    await saveHistoryFilterPreferences(
      baseUrl: baseUrl,
      dir: 'all',
      kind: 'all',
      date: 'custom',
      fromDate: DateTime(2026, 4, 1),
      toDate: DateTime(2026, 4, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          baseUrl: baseUrl,
          walletId: 'wallet_demo',
          initialTxns: const <Map<String, dynamic>>[],
          paymentEventGateway: paymentEventGateway,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('2026-04-01'), findsOneWidget);
    expect(find.text('2026-04-30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
