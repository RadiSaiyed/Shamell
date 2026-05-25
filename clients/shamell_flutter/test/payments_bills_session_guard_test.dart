import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/payments/payments_bills.dart';

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

  testWidgets('BillsPage fail-closes when billing APIs are disabled',
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
        home: BillsPage(
          'https://api.example.com',
          'wallet_demo',
          'device_demo',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Bills are unavailable on this server.'), findsOneWidget);
    expect(find.text('Pay bill'), findsNothing);
  });

  testWidgets('BillsPage rejects malformed base urls before network',
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
        home: BillsPage(
          'https://user:pass@api.example.com',
          'wallet_demo',
          'device_demo',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.byType(BillsPage), findsOneWidget);
    expect(find.text('Bills are unavailable on this server.'), findsOneWidget);
  });
}
