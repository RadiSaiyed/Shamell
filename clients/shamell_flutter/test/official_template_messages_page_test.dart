import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/official_template_messages_page.dart';

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

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

  testWidgets('OfficialTemplateMessagesPage filters notifications locally',
      (tester) async {
    configureLargeViewport(tester);
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/me/official_template_messages?unread_only=false',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'kind': 'service',
              'title': 'Payment alert',
              'body': 'New payout requires review',
              'created_at': '2026-04-17T09:00:00Z',
              'read_at': null,
              'deeplink_json': <String, dynamic>{
                'mini_program_id': 'payments',
                'payload': <String, dynamic>{'section': 'review'},
              },
            },
            <String, dynamic>{
              'id': 2,
              'kind': 'service',
              'title': 'Maintenance complete',
              'body': 'The nightly task finished',
              'created_at': '2026-04-17T08:00:00Z',
              'read_at': '2026-04-17T08:30:00Z',
            },
            <String, dynamic>{
              'id': 3,
              'kind': 'campaign',
              'title': 'Promo update',
              'body': 'Campaign copy changed',
              'created_at': '2026-04-17T07:00:00Z',
              'read_at': null,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _testApp(
        OfficialTemplateMessagesPage(
          baseUrl: 'https://example.test',
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 3 of 3 notifications'), findsOneWidget);

    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 notifications'), findsOneWidget);
    expect(find.text('Payment alert'), findsOneWidget);
    expect(find.text('Maintenance complete'), findsNothing);
    expect(find.text('Promo update'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'promo');
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 notifications'), findsOneWidget);
    expect(find.text('Promo update'), findsOneWidget);
    expect(find.text('Payment alert'), findsNothing);
    expect(find.text('Maintenance complete'), findsNothing);
  });
}
