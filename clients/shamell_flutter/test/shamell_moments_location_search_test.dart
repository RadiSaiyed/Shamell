import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/shamell_moments_composer_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

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

  testWidgets('location search ignores stale first-party proxy responses',
      (tester) async {
    final responses = <String, Completer<http.Response>>{};
    const baseUrl = 'https://api.example.com';
    const sessionToken = '0123456789abcdef0123456789abcdef';
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);

    Future<http.Response> httpGet(
      Uri uri, {
      Map<String, String>? headers,
    }) {
      expect(uri.host, 'api.example.com');
      expect(uri.path, '/me/geo/search');
      expect(headers?['cookie'], '__Host-sa_session=$sessionToken');
      expect(headers?['accept'], 'application/json');
      expect(headers?['accept-language'], 'en');
      final query = uri.queryParameters['q'] ?? '';
      final completer = Completer<http.Response>();
      responses[query] = completer;
      return completer.future;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellMomentsComposerPage(
          baseUrl: baseUrl,
          locationHttpGetForTesting: httpGet,
          disableLocationAutoloadForTesting: true,
        ),
      ),
    );

    await tester.tap(find.text('Location'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pa');
    await tester.pump(const Duration(milliseconds: 350));
    expect(responses.containsKey('pa'), isTrue);

    await tester.enterText(find.byType(TextField), 'par');
    await tester.pump(const Duration(milliseconds: 350));
    expect(responses.containsKey('par'), isTrue);

    responses['par']!.complete(
      http.Response(
        '[{"display_name":"Paris, France"}]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    await tester.pump();

    expect(find.text('Paris'), findsOneWidget);

    responses['pa']!.complete(
      http.Response(
        '[{"display_name":"Palo Alto, California, United States"}]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    await tester.pump();

    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('Palo Alto'), findsNothing);
  });

  testWidgets('location search sends localhost client-ip hint and cookie',
      (tester) async {
    const baseUrl = 'http://localhost:8080';
    const sessionToken = '0123456789abcdef0123456789abcdef';
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);

    Future<http.Response> httpGet(
      Uri uri, {
      Map<String, String>? headers,
    }) async {
      expect(uri.host, 'localhost');
      expect(uri.path, '/me/geo/search');
      expect(headers?['cookie'], '__Host-sa_session=$sessionToken');
      expect(headers?['x-shamell-client-ip'], '127.0.0.1');
      expect(headers?['accept'], 'application/json');
      expect(headers?['accept-language'], 'en');
      return http.Response(
        '[{"display_name":"Paris, France"}]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellMomentsComposerPage(
          baseUrl: baseUrl,
          locationHttpGetForTesting: httpGet,
          disableLocationAutoloadForTesting: true,
        ),
      ),
    );

    await tester.tap(find.text('Location'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'par');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Paris'), findsOneWidget);
  });

  testWidgets(
      'remind picker shows friends before delayed alias enrichment finishes',
      (tester) async {
    delayedSecureRead = Completer<void>();
    delayedSecureReadKeyContains = 'friends.aliases.v2.';
    secStore['friends.aliases.v2.aHR0cHM6Ly9hcGkuZXhhbXBsZS5jb20'] =
        '{"peer-1":"Alias Alice"}';

    Future<http.Response> friendsHttpGet(
      Uri uri, {
      Map<String, String>? headers,
    }) async {
      expect(uri.path, '/me/friends');
      return http.Response(
        '{"friends":[{"id":"peer-1","name":"Server Alice"}]}',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellMomentsComposerPage(
          baseUrl: 'https://api.example.com',
          friendsHttpGetForTesting: friendsHttpGet,
          disableLocationAutoloadForTesting: true,
        ),
      ),
    );

    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();

    expect(find.text('Server Alice'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Alias Alice'), findsNothing);

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Alias Alice'), findsOneWidget);
  });

  testWidgets('remind picker sends localhost client-ip hint and cookie',
      (tester) async {
    const baseUrl = 'http://localhost:8080';
    const sessionToken = '0123456789abcdef0123456789abcdef';
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);

    Future<http.Response> friendsHttpGet(
      Uri uri, {
      Map<String, String>? headers,
    }) async {
      expect(uri.host, 'localhost');
      expect(uri.path, '/me/friends');
      expect(headers?['cookie'], '__Host-sa_session=$sessionToken');
      expect(headers?['x-shamell-client-ip'], '127.0.0.1');
      return http.Response(
        '{"friends":[{"id":"peer-1","name":"Server Alice"}]}',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellMomentsComposerPage(
          baseUrl: baseUrl,
          friendsHttpGetForTesting: friendsHttpGet,
          disableLocationAutoloadForTesting: true,
        ),
      ),
    );

    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();

    expect(find.text('Server Alice'), findsOneWidget);
  });

  testWidgets('remind picker hides raw backend not-found JSON', (tester) async {
    Future<http.Response> friendsHttpGet(
      Uri uri, {
      Map<String, String>? headers,
    }) async {
      expect(uri.path, '/me/friends');
      return http.Response(
        '{"detail":"not found"}',
        404,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellMomentsComposerPage(
          baseUrl: 'https://api.example.com',
          friendsHttpGetForTesting: friendsHttpGet,
          disableLocationAutoloadForTesting: true,
        ),
      ),
    );

    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();

    expect(find.text('Friends are not available right now.'), findsOneWidget);
    expect(find.text('{"detail":"not found"}'), findsNothing);
  });
}
