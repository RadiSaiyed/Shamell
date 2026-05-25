import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/mini_programs_discover_page.dart';

Widget _testApp(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

void _configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpForNetwork(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
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

  testWidgets(
      'MiniProgramsDiscoverPage prefers DB registry but opens native app',
      (tester) async {
    _configureLargeViewport(tester);
    const baseUrl = 'https://example.test';
    final openedMods = <String>[];
    final requests = <String>[];

    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' && request.url.path == '/mini_programs') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'programs': <Object?>[
              <String, Object?>{
                'app_id': 'payments_db',
                'runtime_app_id': 'payments',
                'title_en': 'Server Pay',
                'description_en': 'Server registry wallet',
                'category_en': 'Finance & payments',
                'status': 'published',
                'review_status': 'approved',
                'enabled': true,
                'rating': 4.9,
                'rating_count': 34,
                'usage_score': 120,
                'moments_shares_30d': 9,
                'released_version': '2.4.0',
                'scopes': <String>['wallet.pay'],
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/me/mini_programs/shelf') {
        return http.Response(
          jsonEncode(<String, Object?>{'items': <Object?>[]}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/mini_programs/developer_json') {
        return http.Response(
          jsonEncode(<String, Object?>{'programs': <Object?>[]}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/mini_programs/payments_db/track_open') {
        return http.Response('{}', 200);
      }
      return http.Response('not found: ${request.method} ${request.url}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        MiniProgramsDiscoverPage(
          baseUrl: baseUrl,
          walletId: 'wallet_1',
          deviceId: 'device_1',
          httpClient: client,
          onOpenMod: openedMods.add,
        ),
      ),
    );
    await _pumpForNetwork(tester);

    expect(find.text('Mini Programs'), findsOneWidget);
    expect(find.text('Server Pay'), findsWidgets);
    expect(find.text('SyrChat Pay'), findsNothing);
    expect(requests, contains('GET /mini_programs'));

    await tester.enterText(find.byType(TextField).first, 'server');
    await tester.pumpAndSettle();

    expect(find.text('Server registry wallet'), findsOneWidget);
    expect(find.text('Wallet & payments'), findsOneWidget);

    await tester.tap(find.text('Server Pay').first);
    await tester.pump();

    expect(openedMods, contains('payments'));
  });
}
