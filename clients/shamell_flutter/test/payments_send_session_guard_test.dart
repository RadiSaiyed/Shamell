import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/offline_queue.dart';
import 'package:shamell_flutter/core/payments/payments_attestation.dart';
import 'package:shamell_flutter/core/payments/payments_local_store.dart';
import 'package:shamell_flutter/core/payments/payments_send.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

  Map<String, dynamic> favoriteItem(
    int n, {
    String? alias,
  }) {
    return <String, dynamic>{
      'id': 'fav_$n',
      'owner_wallet_id': 'wallet_me',
      'favorite_wallet_id': 'wallet_target_$n',
      'alias': alias,
      'created_at': DateTime.utc(2026, 3, 18, 0, 0, n).toIso8601String(),
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
    await clearStableDeviceId();
    await OfflineQueue.init();
    resetShamellPaymentAttestationTestHooks();
  });

  testWidgets('PaymentSendTab reauths on critical account session failure',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/payments/transfer') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(PaymentSendTab));
    await state.debugSubmitTransfer(
      recipient: 'wallet_target',
      amountMajor: 1.0,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'PaymentSendTab attaches attestation headers to transfer when challenge is enabled',
      (tester) async {
    http.Request? transferRequest;
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-send');
      return 'play-send-1';
    };
    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"ok":true,"enabled":true,"challenge_token":"chal-send-1","expires_at":1710000000,"hw_attestation_nonce_b64":"nonce-send","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.url.path == '/payments/transfer') {
        transferRequest = request;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(PaymentSendTab));
    await state.debugSubmitTransfer(
      recipient: 'wallet_target',
      amountMajor: 2.5,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(transferRequest, isNotNull);
    expect(
      transferRequest!.headers[shamellPaymentAttestationChallengeHeader],
      'chal-send-1',
    );
    expect(
      transferRequest!.headers[shamellPaymentAttestationPlayIntegrityHeader],
      'play-send-1',
    );
  });

  testWidgets(
      'PaymentSendTab prefers stored stable device id for transfer binding',
      (tester) async {
    http.Request? transferRequest;
    final stableDeviceId = await getOrCreateStableDeviceId(
      baseUrlOverride: 'https://api.example.com',
    );
    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response('{"ok":true,"enabled":false}', 200);
      }
      if (request.url.path == '/payments/transfer') {
        transferRequest = request;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            deviceId: 'runtime_random_device',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(PaymentSendTab));
    await state.debugSubmitTransfer(
      recipient: 'wallet_target',
      amountMajor: 2.5,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(transferRequest, isNotNull);
    expect(transferRequest!.headers['X-Device-ID'], stableDeviceId);
  });

  testWidgets('PaymentSendTab transfer payload uses amount_cents only',
      (tester) async {
    http.Request? transferRequest;
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async => 'play-send-cents-1';
    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"ok":true,"enabled":true,"challenge_token":"chal-send-cents-1","expires_at":1710000000,"hw_attestation_nonce_b64":"nonce-send-cents","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.url.path == '/payments/transfer') {
        transferRequest = request;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'wallet_target');
    await tester.enterText(find.byType(TextField).at(1), '2.50');

    await tester.tap(find.text('Send').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send').last);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(transferRequest, isNotNull);
    final payload = jsonDecode(transferRequest!.body) as Map<String, dynamic>;
    expect(payload['amount_cents'], 250);
    expect(payload.containsKey('amount'), isFalse);
  });

  testWidgets(
      'PaymentSendTab strips attestation headers when queueing offline transfer after transport failure',
      (tester) async {
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-offline');
      return 'play-offline-1';
    };
    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"ok":true,"enabled":true,"challenge_token":"chal-offline-1","expires_at":1710000000,"hw_attestation_nonce_b64":"nonce-offline","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.url.path == '/payments/transfer') {
        throw const SocketException('offline');
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'wallet_target');
    await tester.enterText(find.byType(TextField).at(1), '2.50');

    await tester.tap(find.text('Send').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send').last);
    await tester.pump();
    await tester.pumpAndSettle();

    final pending = OfflineQueue.pending(tag: 'payments_transfer');
    expect(pending, hasLength(1));
    expect(
      pending.first.headers['Idempotency-Key'],
      isNotEmpty,
    );
    expect(
      pending.first.headers['X-Device-ID'],
      'device_1',
    );
    expect(
      pending.first.headers[shamellPaymentAttestationChallengeHeader],
      isNull,
    );
    expect(
      pending.first.headers[shamellPaymentAttestationPlayIntegrityHeader],
      isNull,
    );
  });

  testWidgets('GroupPayPage reauths on critical account session failure',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: GroupPayPage(
          baseUrl: 'https://api.example.com',
          fromWalletId: 'wallet_me',
          deviceId: 'device_1',
          client: client,
          confirmDialogLauncher: (_, __) async => true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'PaymentSendTab rejects malformed base urls before network or queue',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://user:pass@api.example.com/root',
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);

    await tester.enterText(find.byType(TextField).at(0), 'wallet_target');
    await tester.enterText(find.byType(TextField).at(1), '1.00');

    await tester.tap(find.text('Send').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send').last);
    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(OfflineQueue.pending(tag: 'payments_transfer'), isEmpty);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('PaymentSendTab uses stored wallet from explicit baseUrl scope',
      (tester) async {
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
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: originOne,
            fromWalletId: '',
            deviceId: 'device_1',
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

  testWidgets('PaymentSendTab loads recents from explicit baseUrl scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);
    expect(
      await savePaymentRecents(
        <String>['wallet_recent_one'],
        sp: sp,
        baseUrlOverride: originOne,
      ),
      isTrue,
    );
    expect(
      await savePaymentRecents(
        <String>['wallet_recent_two'],
        sp: sp,
        baseUrlOverride: originTwo,
      ),
      isTrue,
    );

    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: originOne,
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(PaymentSendTab));
    expect(state.recents, <String>['wallet_recent_one']);
    expect(state.recents, isNot(contains('wallet_recent_two')));
  });

  testWidgets(
      'PaymentSendTab paginates favorites until the older slice is exhausted',
      (tester) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        final beforeId = request.url.queryParameters['before_id'];
        if (beforeId == null) {
          final firstPage = List<Map<String, dynamic>>.generate(
            100,
            (index) => favoriteItem(200 - index),
            growable: false,
          );
          return http.Response(jsonEncode(firstPage), 200);
        }
        expect(beforeId, 'fav_101');
        expect(
          request.url.queryParameters['before_created_at'],
          DateTime.utc(2026, 3, 18, 0, 0, 101).toIso8601String(),
        );
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            favoriteItem(100),
          ]),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(PaymentSendTab));
    expect(state.favorites, hasLength(101));
    expect(
      requests.where((uri) => uri.path == '/payments/favorites'),
      hasLength(2),
    );
  });

  testWidgets('PaymentSendTab favorite chips fill wallet id, not display alias',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            favoriteItem(1, alias: 'Mom'),
          ]),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: 'https://api.example.com',
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final chip =
        tester.widget<ActionChip>(find.widgetWithText(ActionChip, 'Mom'));
    chip.onPressed?.call();
    await tester.pump();

    final dynamic state = tester.state(find.byType(PaymentSendTab));
    expect(state.toCtrl.text, 'wallet_target_1');
  });

  testWidgets(
      'PaymentSendTab queues offline transfer in explicit baseUrl scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);

    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/payments/transfer') {
        return http.Response('{"detail":"temporary"}', 500);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSendTab(
            baseUrl: originOne,
            fromWalletId: 'wallet_me',
            deviceId: 'device_1',
            client: client,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'wallet_target');
    await tester.enterText(find.byType(TextField).at(1), '1.00');

    await tester.tap(find.text('Send').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send').last);
    await tester.pump();
    await tester.pump();

    expect(
      OfflineQueue.pending(
        tag: 'payments_transfer',
        baseUrlOverride: originOne,
      ),
      hasLength(1),
    );
    expect(
      OfflineQueue.pending(
        tag: 'payments_transfer',
        baseUrlOverride: originTwo,
      ),
      isEmpty,
    );
  });

  test('GroupPayPage request creation sends idempotency keys', () async {
    http.Request? createdRequest;
    final client = MockClient((request) async {
      createdRequest = request;
      return http.Response('{}', 200);
    });

    final response = await GroupPayPage.postGroupPaymentRequestCreate(
      client: client,
      uri: Uri.parse('https://api.example.com/payments/requests'),
      payload: const <String, Object?>{
        'from_wallet_id': 'wallet_me',
        'to_wallet_id': 'wallet_target_1',
        'amount_cents': 100,
      },
      deviceId: 'device_1',
      headersLoader: () async => <String, String>{
        'content-type': 'application/json',
      },
    );

    expect(response.statusCode, 200);
    expect(createdRequest, isNotNull);
    expect(createdRequest!.url.path, '/payments/requests');
    expect(
      createdRequest!.headers['Idempotency-Key'],
      startsWith('payments-request-create-'),
    );
    expect(createdRequest!.headers['X-Device-ID'], 'device_1');
    expect(createdRequest!.headers['content-type'], 'application/json');
    expect(
      jsonDecode(createdRequest!.body),
      const <String, Object?>{
        'from_wallet_id': 'wallet_me',
        'to_wallet_id': 'wallet_target_1',
        'amount_cents': 100,
      },
    );
  });

  testWidgets('GroupPayPage request creation uses bounded concurrency',
      (tester) async {
    var requestCreateCalls = 0;
    var inFlight = 0;
    var maxInFlight = 0;
    final twoStarted = Completer<void>();
    final release = Completer<void>();

    final client = MockClient((request) async {
      if (request.url.path == '/payments/wallets/wallet_me') {
        return http.Response('{"balance_cents":5000}', 200);
      }
      if (request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"ok":true,"enabled":false}',
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/payments/requests') {
        requestCreateCalls++;
        inFlight++;
        if (inFlight > maxInFlight) {
          maxInFlight = inFlight;
        }
        if (maxInFlight >= 2 && !twoStarted.isCompleted) {
          twoStarted.complete();
        }
        await release.future;
        inFlight--;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: GroupPayPage(
          baseUrl: 'https://api.example.com',
          fromWalletId: 'wallet_me',
          deviceId: 'device_1',
          client: client,
          confirmDialogLauncher: (_, __) async => true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), '6.00');
    await tester.enterText(
      find.byType(TextField).at(1),
      'wallet_a\nwallet_b\nwallet_c\nwallet_d\nwallet_e\nwallet_f',
    );

    final createRequestsButton =
        find.byKey(const Key('groupPayCreateRequestsButton'));
    await tester.scrollUntilVisible(
      createRequestsButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(createRequestsButton);
    await tester.pump();
    await tester.tap(createRequestsButton, warnIfMissed: false);
    await tester.pump();

    await twoStarted.future.timeout(const Duration(seconds: 1));
    expect(maxInFlight, greaterThan(1));
    expect(
      maxInFlight,
      lessThanOrEqualTo(GroupPayPage.requestCreateMaxConcurrency),
    );

    FocusManager.instance.primaryFocus?.unfocus();
    release.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(requestCreateCalls, 6);
  });
}
