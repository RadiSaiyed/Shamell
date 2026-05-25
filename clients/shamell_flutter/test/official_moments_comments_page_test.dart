import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/official_moments_comments_page.dart';

const AccountPrivilegeSnapshot _officialPrivilegeSnapshot =
    AccountPrivilegeSnapshot(
  permissions: <String>[
    'official.dashboard.read',
    'official.dashboard.write',
  ],
  products: <String>['official_accounts'],
  officialAccountIds: <String>['acc_1'],
);

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

Future<void> _pumpForDataLoad(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
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

  testWidgets('OfficialMomentsCommentsPage filters comments locally',
      (tester) async {
    configureLargeViewport(tester);
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/moments/admin/comments?official_account_id=acc_1&limit=200',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 11,
              'post_id': 501,
              'text': 'Need price',
              'created_at': '2026-04-17T09:00:00Z',
              'user_key': 'user:alice',
            },
            <String, dynamic>{
              'id': 12,
              'post_id': 501,
              'reply_to_id': 11,
              'text': 'Price is 10',
              'created_at': '2026-04-17T09:05:00Z',
              'user_key': 'official:acc_1',
            },
            <String, dynamic>{
              'id': 13,
              'post_id': 700,
              'reply_to_id': 9,
              'text': 'Thanks for the update',
              'created_at': '2026-04-17T09:10:00Z',
              'user_key': 'user:bob',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _testApp(
        OfficialMomentsCommentsPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(find.text('Showing 3 of 3 comments'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Official (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 comments'), findsOneWidget);
    expect(find.text('Price is 10'), findsOneWidget);
    expect(find.text('Need price'), findsNothing);
    expect(find.text('Thanks for the update'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search comments'),
      'thanks',
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 comments'), findsOneWidget);
    expect(find.text('Thanks for the update'), findsOneWidget);
    expect(find.text('Need price'), findsNothing);
    expect(find.text('Price is 10'), findsNothing);
  });
}
