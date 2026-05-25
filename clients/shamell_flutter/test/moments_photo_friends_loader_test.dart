import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/shamell_moments_composer_page.dart';
import 'package:shamell_flutter/core/shamell_photo_viewer_page.dart';
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

  test(
      'ShamellMomentsComposer friends loader rejects malformed base urls before network',
      () async {
    var calls = 0;

    final response = await shamellMomentsComposerFetchFriendsResponse(
      baseUrl: 'https://user:pass@example.com/root',
      authHeadersLoader: () async => const <String, String>{},
      httpGet: (uri, {headers}) async {
        calls++;
        return http.Response('{}', 500);
      },
      timeout: const Duration(milliseconds: 1),
    );

    expect(response, isNull);
    expect(calls, 0);
  });

  test(
      'ShamellPhotoViewer friends loader rejects malformed base urls before network',
      () async {
    var calls = 0;

    final response = await shamellPhotoViewerFetchFriendsResponse(
      baseUrl: 'https://user:pass@example.com/root',
      authHeadersLoader: () async => const <String, String>{},
      httpGet: (uri, {headers}) async {
        calls++;
        return http.Response('{}', 500);
      },
      timeout: const Duration(milliseconds: 1),
    );

    expect(response, isNull);
    expect(calls, 0);
  });

  testWidgets(
      'photo viewer send-to-chat sheet shows friends before delayed alias enrichment finishes',
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
      const MaterialApp(
        home: SizedBox.shrink(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellPhotoViewerPage(
          baseUrl: 'https://api.example.com',
          sources: const <String>[
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=',
          ],
          friendsHttpGetForTesting: friendsHttpGet,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to chat'));
    await tester.pumpAndSettle();

    expect(find.text('Server Alice'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Alias Alice'), findsNothing);

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Alias Alice'), findsOneWidget);
  });

  testWidgets(
      'photo viewer send-to-chat sends localhost client-ip hint and cookie',
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
        home: ShamellPhotoViewerPage(
          baseUrl: baseUrl,
          sources: const <String>[
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=',
          ],
          friendsHttpGetForTesting: friendsHttpGet,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to chat'));
    await tester.pumpAndSettle();

    expect(find.text('Server Alice'), findsOneWidget);
  });
}
