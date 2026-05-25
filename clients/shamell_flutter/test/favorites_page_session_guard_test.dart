import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/favorites_page.dart';
import 'package:shamell_flutter/core/favorites_store.dart';

Future<void> _pumpFavoritesPage(
  WidgetTester tester, {
  required String baseUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FavoritesPage(baseUrl: baseUrl),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  Completer<void>? delayedSecureRead;
  String? delayedSecureReadKeyContains;

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
            if (delayedSecureRead != null &&
                delayedSecureReadKeyContains != null &&
                key.contains(delayedSecureReadKeyContains!) &&
                !delayedSecureRead!.isCompleted) {
              await delayedSecureRead!.future;
            }
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
    delayedSecureRead = null;
    delayedSecureReadKeyContains = null;
  });

  testWidgets(
      'FavoritesPage shows favorites before delayed friend annotations load finishes',
      (tester) async {
    await saveFavoriteItems(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'text': 'Scoped note',
          'ts': '2026-03-19T10:00:00Z',
        },
      ],
      baseUrlOverride: 'https://api.one.example',
    );
    delayedSecureRead = Completer<void>();
    delayedSecureReadKeyContains = 'friends.aliases.v2.';

    await _pumpFavoritesPage(tester, baseUrl: 'https://api.one.example');

    expect(find.text('Scoped note'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Scoped note'), findsOneWidget);
  });
}
