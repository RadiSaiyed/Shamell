import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/friend_annotations_store.dart';
import 'package:shamell_flutter/core/friend_tags_page.dart';

Future<void> _pumpFriendTagsPage(
  WidgetTester tester, {
  required String baseUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FriendTagsPage(baseUrl: baseUrl),
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
      'FriendTagsPage shows tag groups before delayed aliases load finishes',
      (tester) async {
    await saveFriendTags(
      <String, String>{'peer-1': 'alpha'},
      baseUrlOverride: 'https://api.one.example',
    );
    await saveFriendAliases(
      <String, String>{'peer-1': 'Alice'},
      baseUrlOverride: 'https://api.one.example',
    );
    delayedSecureRead = Completer<void>();
    delayedSecureReadKeyContains = 'friends.aliases.v2.';

    await _pumpFriendTagsPage(tester, baseUrl: 'https://api.one.example');

    expect(find.text('alpha'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
  });
}
