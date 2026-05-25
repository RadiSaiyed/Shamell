import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/friend_annotations_store.dart';
import 'package:shamell_flutter/core/people_p2p.dart';

String _scopedSecureKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

Future<void> _pumpPeopleP2PPage(
  WidgetTester tester, {
  required String baseUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PeopleP2PPage(baseUrl, 'wallet_1', 'device_1'),
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
      'PeopleP2PPage shows cached shortlist before delayed alias load finishes',
      (tester) async {
    secStore[_scopedSecureKey(
      'legacy.contact_shortlist.v2.',
      'https://api.one.example',
    )] = jsonEncode(<String>[
      '{"name":"Cached Alice","phone":"+111"}',
    ]);
    await saveFriendAliases(
      <String, String>{'+111': 'Alias Alice'},
      baseUrlOverride: 'https://api.one.example',
    );
    delayedSecureRead = Completer<void>();
    delayedSecureReadKeyContains = 'friends.aliases.v2.';

    await _pumpPeopleP2PPage(tester, baseUrl: 'https://api.one.example');

    expect(find.text('Cached Alice'), findsOneWidget);
    expect(find.text('Alias Alice'), findsNothing);

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Alias Alice'), findsOneWidget);
    expect(find.text('+111'), findsOneWidget);
  });
}
