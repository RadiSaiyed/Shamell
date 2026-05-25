import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/friend_annotations_store.dart';
import 'package:shamell_flutter/core/friends_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  Completer<void>? delayedSecureRead;
  String? delayedSecureReadKeyContains;
  Completer<void>? delayedSecureWrite;
  String? delayedSecureWriteKeyContains;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            if (delayedSecureWrite != null &&
                delayedSecureWriteKeyContains != null &&
                key.contains(delayedSecureWriteKeyContains!) &&
                !delayedSecureWrite!.isCompleted) {
              await delayedSecureWrite!.future;
            }
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
    delayedSecureWrite = null;
    delayedSecureWriteKeyContains = null;
  });

  testWidgets('FriendsPage reauths on critical account session failure load',
      (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/me/friends');
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://api.example.com',
          client: client,
          bootstrapChatReady: () async {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('FriendsPage reauths on critical account session failure accept',
      (tester) async {
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/me/friends':
          return http.Response('[]', 200);
        case '/me/friend_requests':
          return http.Response(
            '{"incoming":[{"request_id":"req_1","name":"Peer"}],"outgoing":[]}',
            200,
          );
        case '/friends/accept':
          return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://api.example.com',
          mode: FriendsPageMode.newFriends,
          client: client,
          bootstrapChatReady: () async {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, 'Accept'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Accept'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('FriendsPage rejects malformed base urls before network load',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://user:pass@api.example.com/root',
          client: client,
          bootstrapChatReady: () async {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('FriendsPage sends localhost client-ip header on load',
      (tester) async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    final client = MockClient((request) async {
      expect(request.url.path, '/me/friends');
      expect(request.headers['x-shamell-client-ip'], '127.0.0.1');
      expect(
        request.headers['cookie'],
        '__Host-sa_session=0123456789abcdef0123456789abcdef',
      );
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          baseUrl,
          client: client,
          bootstrapChatReady: () async {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
  });

  testWidgets('FriendsPage new-friends mode skips broad friends bootstrap load',
      (tester) async {
    final requests = <String>[];
    var bootstrapCalls = 0;
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path == '/me/friend_requests') {
        return http.Response(
          '{"incoming":[{"request_id":"req_1","name":"Peer"}],"outgoing":[]}',
          200,
        );
      }
      fail('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://api.example.com',
          mode: FriendsPageMode.newFriends,
          client: client,
          bootstrapChatReady: () async {
            bootstrapCalls += 1;
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(
      requests.where((entry) => entry == 'GET /me/friends'),
      isEmpty,
    );
    expect(
      requests.where((entry) => entry == 'GET /me/friend_requests'),
      hasLength(1),
    );
    expect(bootstrapCalls, 0);
    expect(find.widgetWithText(OutlinedButton, 'Accept'), findsOneWidget);
  });

  testWidgets(
      'FriendsPage manage mode still bootstraps chat readiness before friends load',
      (tester) async {
    var bootstrapCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/me/friends') {
        return http.Response('{"friends":[]}', 200);
      }
      fail('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://api.example.com',
          mode: FriendsPageMode.manage,
          client: client,
          bootstrapChatReady: () async {
            bootstrapCalls += 1;
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(bootstrapCalls, 1);
  });

  testWidgets(
      'FriendsPage manage mode shows friends before delayed alias load finishes',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    delayedSecureRead = Completer<void>();
    delayedSecureReadKeyContains = 'friends.aliases.v2.';
    secStore['friends.aliases.v2.aHR0cHM6Ly9hcGkuZXhhbXBsZS5jb20'] =
        '{"peer-1":"Remark Alice"}';

    final client = MockClient((request) async {
      if (request.url.path == '/me/friends') {
        return http.Response(
          '{"friends":[{"id":"peer-1","name":"Server Alice","device_id":"peer-1","close":false}]}',
          200,
        );
      }
      fail('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://api.example.com',
          mode: FriendsPageMode.manage,
          client: client,
          bootstrapChatReady: () async {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Server Alice'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Remark Alice'), findsNothing);

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Remark Alice'), findsOneWidget);
  });

  testWidgets('FriendsPage accept refreshes only requests in new-friends mode',
      (tester) async {
    final requests = <String>[];
    var requestLoads = 0;
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      switch (request.url.path) {
        case '/me/friend_requests':
          requestLoads += 1;
          if (requestLoads == 1) {
            return http.Response(
              '{"incoming":[{"request_id":"req_1","name":"Peer"}],"outgoing":[]}',
              200,
            );
          }
          return http.Response('{"incoming":[],"outgoing":[]}', 200);
        case '/friends/accept':
          return http.Response('{}', 200);
      }
      fail('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://api.example.com',
          mode: FriendsPageMode.newFriends,
          client: client,
          bootstrapChatReady: () async {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Accept'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      requests.where((entry) => entry == 'GET /me/friends'),
      isEmpty,
    );
    expect(
      requests.where((entry) => entry == 'GET /me/friend_requests'),
      hasLength(2),
    );
    expect(
      requests.where((entry) => entry == 'POST /friends/accept'),
      hasLength(1),
    );
    expect(find.widgetWithText(OutlinedButton, 'Accept'), findsNothing);
  });

  testWidgets(
      'FriendsPage manage mode waits for annotation snapshot save before closing editor',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    delayedSecureWrite = Completer<void>();
    delayedSecureWriteKeyContains = 'friends.tags.v2.';

    final client = MockClient((request) async {
      if (request.url.path == '/me/friends') {
        return http.Response(
          '{"friends":[{"id":"peer-1","name":"Server Alice","device_id":"peer-1","close":false}]}',
          200,
        );
      }
      fail('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          'https://api.example.com',
          mode: FriendsPageMode.manage,
          client: client,
          bootstrapChatReady: () async {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Server Alice'));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final fields = find.descendant(of: sheet, matching: find.byType(TextField));
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Remark Alice');
    await tester.enterText(fields.at(1), 'vip');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();

    expect(find.text('Friend alias'), findsOneWidget);

    delayedSecureWrite!.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Friend alias'), findsNothing);
    expect(
      await loadFriendAliases(baseUrlOverride: 'https://api.example.com'),
      <String, String>{'peer-1': 'Remark Alice'},
    );
    expect(
      await loadFriendTags(baseUrlOverride: 'https://api.example.com'),
      <String, String>{'peer-1': 'vip'},
    );
  });
}
