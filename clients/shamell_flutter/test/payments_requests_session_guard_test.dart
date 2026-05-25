import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/payments/payments_attestation.dart';
import 'package:shamell_flutter/core/payments/payments_requests.dart';
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
    resetShamellPaymentAttestationTestHooks();
  });

  Map<String, dynamic> requestItem(
    int n, {
    required bool incoming,
    String status = 'pending',
  }) {
    return <String, dynamic>{
      'id': 'req_$n',
      'from_wallet_id': incoming ? 'wallet_peer_in_$n' : 'wallet_demo',
      'to_wallet_id': incoming ? 'wallet_demo' : 'wallet_peer_out_$n',
      'amount_cents': 1000 + n,
      'currency': 'USD',
      'message': 'request_$n',
      'status': status,
      'created_at': DateTime.utc(2026, 3, 18, 0, 0, 101 - n).toIso8601String(),
    };
  }

  String requestsResponse(List<Map<String, dynamic>> items) =>
      jsonEncode(items);

  testWidgets('RequestsPage reauths on critical account session failure',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      expect(request.url.host, 'api.example.com');
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('RequestsPage rejects malformed base urls before network',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://user:pass@api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(RequestsPage), findsOneWidget);
  });

  testWidgets('RequestsPage paginates pending requests with stable cursor',
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
      final kind = request.url.queryParameters['kind'];
      final beforeId = request.url.queryParameters['before_id'];
      if (kind == 'incoming' && beforeId == null) {
        final page = List<Map<String, dynamic>>.generate(
          100,
          (index) => requestItem(index + 1, incoming: true, status: 'pending'),
          growable: false,
        );
        return http.Response(requestsResponse(page), 200);
      }
      if (kind == 'incoming' && beforeId == 'req_100') {
        expect(
          request.url.queryParameters['before_created_at'],
          DateTime.utc(2026, 3, 18, 0, 0, 1).toIso8601String(),
        );
        return http.Response(
          requestsResponse(<Map<String, dynamic>>[
            requestItem(101, incoming: true, status: 'pending'),
          ]),
          200,
        );
      }
      if (kind == 'outgoing') {
        return http.Response(
            requestsResponse(const <Map<String, dynamic>>[]), 200);
      }
      return http.Response(
          requestsResponse(const <Map<String, dynamic>>[]), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Load more'),
      700,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 40,
    );
    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(seenUris, hasLength(3));
  });

  testWidgets('RequestsPage pending tab accepts only incoming pending requests',
      (tester) async {
    final client = MockClient((request) async {
      final kind = request.url.queryParameters['kind'];
      if (kind == 'incoming') {
        return http.Response(
          requestsResponse(<Map<String, dynamic>>[
            requestItem(1, incoming: true, status: 'pending'),
          ]),
          200,
        );
      }
      return http.Response(
        requestsResponse(<Map<String, dynamic>>[
          requestItem(2, incoming: false, status: 'pending'),
        ]),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
  });

  testWidgets('RequestsPage treats backend canceled status as cancelled label',
      (tester) async {
    final client = MockClient((request) async {
      final kind = request.url.queryParameters['kind'];
      if (kind == 'incoming') {
        return http.Response(
          requestsResponse(<Map<String, dynamic>>[
            requestItem(1, incoming: true, status: 'canceled'),
          ]),
          200,
        );
      }
      return http.Response(
        requestsResponse(const <Map<String, dynamic>>[]),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Incoming'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
  });

  testWidgets('RequestsPage QR payload encodes major-unit amount, not cents',
      (tester) async {
    final client = MockClient((request) async {
      final kind = request.url.queryParameters['kind'];
      if (kind == 'incoming') {
        return http.Response(
          requestsResponse(<Map<String, dynamic>>[
            requestItem(50, incoming: true, status: 'pending'),
          ]),
          200,
        );
      }
      return http.Response(
        requestsResponse(const <Map<String, dynamic>>[]),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Incoming'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('amount_cents=1050'), findsOneWidget);
    expect(find.textContaining('currency=USD'), findsOneWidget);
    expect(
      find.textContaining('wallet_id=wallet_peer_in_50'),
      findsOneWidget,
    );
  });

  testWidgets('RequestsPage accept sends idempotency key and wallet body',
      (tester) async {
    http.Request? acceptRequest;
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-accept');
      return 'play-accept-1';
    };
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        final kind = request.url.queryParameters['kind'];
        if (kind == 'incoming') {
          return http.Response(
            requestsResponse(<Map<String, dynamic>>[
              requestItem(1, incoming: true, status: 'pending'),
            ]),
            200,
          );
        }
        return http.Response(
          requestsResponse(const <Map<String, dynamic>>[]),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"ok":true,"enabled":true,"challenge_token":"chal-accept-1","expires_at":1710000000,"hw_attestation_nonce_b64":"nonce-accept","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/payments/requests/req_1/accept') {
        acceptRequest = request;
        return http.Response(
            '{"wallet_id":"wallet_demo","balance_cents":900}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(acceptRequest, isNotNull);
    expect(
      acceptRequest!.headers['Idempotency-Key'],
      startsWith('payments-request-accept-'),
    );
    expect(acceptRequest!.headers['X-Device-ID'], 'device_1');
    expect(acceptRequest!.headers['content-type'], 'application/json');
    expect(
      acceptRequest!.headers[shamellPaymentAttestationChallengeHeader],
      'chal-accept-1',
    );
    expect(
      acceptRequest!.headers[shamellPaymentAttestationPlayIntegrityHeader],
      'play-accept-1',
    );
    expect(
      jsonDecode(acceptRequest!.body),
      <String, dynamic>{'to_wallet_id': 'wallet_demo'},
    );
  });

  testWidgets('RequestsPage cancel sends idempotency key and attestation',
      (tester) async {
    http.Request? cancelRequest;
    shamellPaymentAttestationPlayIntegrityTokenProvider =
        ({required String nonceB64}) async {
      expect(nonceB64, 'nonce-cancel');
      return 'play-cancel-1';
    };
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        final kind = request.url.queryParameters['kind'];
        if (kind == 'outgoing') {
          return http.Response(
            requestsResponse(<Map<String, dynamic>>[
              requestItem(2, incoming: false, status: 'pending'),
            ]),
            200,
          );
        }
        return http.Response(
          requestsResponse(const <Map<String, dynamic>>[]),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/auth/payment_attestation/challenge') {
        return http.Response(
          '{"ok":true,"enabled":true,"challenge_token":"chal-cancel-1","expires_at":1710000000,"hw_attestation_nonce_b64":"nonce-cancel","hw_attestation_providers":["google_play_integrity"]}',
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/payments/requests/req_2/cancel') {
        cancelRequest = request;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RequestsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_1',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.cancel_outlined));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(cancelRequest, isNotNull);
    expect(
      cancelRequest!.headers['Idempotency-Key'],
      startsWith('payments-request-cancel-'),
    );
    expect(cancelRequest!.headers['X-Device-ID'], 'device_1');
    expect(
      cancelRequest!.headers[shamellPaymentAttestationChallengeHeader],
      'chal-cancel-1',
    );
    expect(
      cancelRequest!.headers[shamellPaymentAttestationPlayIntegrityHeader],
      'play-cancel-1',
    );
    expect(cancelRequest!.body, isEmpty);
  });
}
