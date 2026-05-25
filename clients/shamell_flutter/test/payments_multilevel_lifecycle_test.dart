import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;
import 'package:shamell_flutter/core/superapp_api.dart';
import 'package:shamell_flutter/core/payments/payments_multilevel.dart';

class _FakeDelayedApi extends SuperappAPI {
  final Duration delay = const Duration(milliseconds: 60);

  _FakeDelayedApi()
      : super(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_demo',
          openMod: (_) {},
          pushPage: (_) {},
          ensureServiceOfficialFollow: ({
            required String officialId,
            required String chatPeerId,
          }) async {},
          recordModuleUse: (_) async {},
        );

  @override
  Future<Map<String, String>> sessionHeaders({
    bool json = false,
    Map<String, String>? extra,
    required Uri uri,
  }) async {
    return <String, String>{};
  }

  @override
  Future<http.Response> getUri(Uri uri, {Map<String, String>? headers}) async {
    await Future<void>.delayed(delay);
    return http.Response('{"detail":"unavailable"}', 503);
  }
}

class _FakeUnauthorizedApi extends SuperappAPI {
  _FakeUnauthorizedApi()
      : super(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_demo',
          openMod: (_) {},
          pushPage: (_) {},
          ensureServiceOfficialFollow: ({
            required String officialId,
            required String chatPeerId,
          }) async {},
          recordModuleUse: (_) async {},
        );

  @override
  Future<Map<String, String>> sessionHeaders({
    bool json = false,
    Map<String, String>? extra,
    required Uri uri,
  }) async {
    return <String, String>{};
  }

  @override
  Future<http.Response> getUri(Uri uri, {Map<String, String>? headers}) async {
    return http.Response('{"detail":"auth session required"}', 401);
  }
}

class _FakeSnapshotApi extends SuperappAPI {
  _FakeSnapshotApi()
      : super(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_demo',
          openMod: (_) {},
          pushPage: (_) {},
          ensureServiceOfficialFollow: ({
            required String officialId,
            required String chatPeerId,
          }) async {},
          recordModuleUse: (_) async {},
        );

  @override
  Future<Map<String, String>> sessionHeaders({
    bool json = false,
    Map<String, String>? extra,
    required Uri uri,
  }) async {
    return <String, String>{};
  }

  @override
  Future<http.Response> getUri(Uri uri, {Map<String, String>? headers}) async {
    return http.Response(
      '''
      {
        "phone": "+963944000111",
        "roles": [],
        "permissions": [
          "wallet.operator.read",
          "cash.agent.read",
          "wallet.admin.read",
          "wallet.credit.write",
          "wallet.guardrails.write"
        ],
        "products": ["wallet"],
        "operator_ids": ["merchant_damascus"],
        "wallet": {
          "wallet_id": "wallet_demo",
          "balance_cents": 125000,
          "currency": "SYP"
        },
        "txns": [{}, {}]
      }
      ''',
      200,
    );
  }
}

class _FakeAdminCreditApi extends SuperappAPI {
  String approvedPath = '';
  Map<String, String> approvalHeaders = const <String, String>{};

  _FakeAdminCreditApi()
      : super(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_demo',
          openMod: (_) {},
          pushPage: (_) {},
          ensureServiceOfficialFollow: ({
            required String officialId,
            required String chatPeerId,
          }) async {},
          recordModuleUse: (_) async {},
        );

  @override
  Future<Map<String, String>> sessionHeaders({
    bool json = false,
    Map<String, String>? extra,
    required Uri uri,
  }) async {
    return <String, String>{...?extra};
  }

  @override
  Future<http.Response> getUri(Uri uri, {Map<String, String>? headers}) async {
    if (uri.path.endsWith('/me/home_snapshot')) {
      return http.Response(
        jsonEncode(<String, Object?>{
          'phone': '+963944000111',
          'permissions': <String>[
            'wallet.credit.write',
            'wallet.finance.read',
          ],
          'products': <String>['wallet'],
          'wallet': <String, Object?>{
            'wallet_id': 'wallet_demo',
            'balance_cents': 125000,
            'currency': 'SYP',
          },
          'txns': <Object?>[],
        }),
        200,
      );
    }
    if (uri.path.endsWith('/payments/admin/credits')) {
      return http.Response(
        jsonEncode(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'approval_request_id': 'req_pending',
              'wallet_id': 'wallet_demo',
              'amount_cents': 1500,
              'currency': 'SYP',
              'status': 'pending_approval',
              'reason': 'ci_review',
              'created_at': '2026-04-26T10:00:00Z',
            },
          ],
          'metrics': <String, Object?>{
            'credited_count': 0,
            'credited_amount_cents': 0,
            'pending_approval_count': 1,
            'pending_approval_amount_cents': 1500,
          },
        }),
        200,
      );
    }
    return http.Response('{"detail":"not found"}', 404);
  }

  @override
  Future<http.Response> postUri(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    approvedPath = uri.path;
    approvalHeaders = Map<String, String>.from(headers ?? const {});
    return http.Response(
      jsonEncode(<String, Object?>{
        'approval_request_id': 'req_pending',
        'wallet_id': 'wallet_demo',
        'balance_cents': 126500,
        'currency': 'SYP',
        'status': 'credited',
      }),
      200,
    );
  }
}

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
  });

  testWidgets('PaymentsMultiLevelPage does not throw when disposed mid-load',
      (tester) async {
    final api = _FakeDelayedApi();
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsMultiLevelPage(api: api),
      ),
    );

    // Dispose the page while the async load is still in flight.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(api.delay + const Duration(milliseconds: 40));

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PaymentsMultiLevelPage reauths on critical account session failure',
      (tester) async {
    final api = _FakeUnauthorizedApi();
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsMultiLevelPage(api: api),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'PaymentsMultiLevelPage uses permission snapshot for operator admin and guardrails',
      (tester) async {
    final api = _FakeSnapshotApi();
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsMultiLevelPage(api: api),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Merchant POS'), findsOneWidget);
    expect(find.text('Cash agent'), findsOneWidget);
    expect(find.text('This phone has admin rights.'), findsOneWidget);
    expect(find.text('Credit balance'), findsOneWidget);
    expect(
      find.text(
        'Superadmin: full control over roles, guardrails and finance for Payments.',
      ),
      findsOneWidget,
    );
    expect(find.text('Operator scope: merchant_damascus'), findsOneWidget);
  });

  testWidgets('PaymentsMultiLevelPage approves pending admin credit requests',
      (tester) async {
    final api = _FakeAdminCreditApi();
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentsMultiLevelPage(api: api),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Credit history'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(api.approvedPath, '/payments/admin/credits/req_pending/approve');
    expect(api.approvalHeaders['Idempotency-Key'], startsWith('admin-credit-'));
    expect(find.textContaining('Approved. Balance:'), findsOneWidget);
  });
}
