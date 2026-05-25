import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/official_moments_comments_page.dart';
import 'package:shamell_flutter/core/official_owner_console_page.dart';
import 'package:shamell_flutter/core/official_owners_access_page.dart';
import 'package:shamell_flutter/core/official_service_inbox_page.dart';
import 'package:shamell_flutter/core/official_template_messages_page.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

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

Future<void> _pumpForReauth(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
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

  testWidgets('OfficialOwnerConsolePage reauths on critical session failure',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );

    await _pumpForReauth(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('OfficialOwnerConsolePage denies access without grants',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(
      find.text(
        'Your account is not allowed to access this official account console.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('OfficialOwnersAccessPage reauths on critical session failure',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );

    await _pumpForReauth(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('OfficialServiceInboxPage reauths on critical session failure',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );

    await _pumpForReauth(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('OfficialMomentsCommentsPage reauths on critical session failure',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
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

    await _pumpForReauth(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'OfficialMomentsCommentsPage surfaces bounded latest-slice warning at hard cap',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/moments/admin/comments?official_account_id=acc_1&limit=200',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'items': List.generate(
            200,
            (index) => <String, Object?>{
              'id': index + 1,
              'post_id': 900 + index,
              'text': 'Comment ${index + 1}',
              'created_at': '2026-03-18T10:00:00Z',
            },
          ),
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

    await tester.pumpAndSettle();

    expect(
      find.text('Showing only the latest 200 comments in this view.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'OfficialTemplateMessagesPage reauths on critical session failure',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialTemplateMessagesPage(
          baseUrl: 'https://example.test',
          httpClient: client,
        ),
      ),
    );

    await _pumpForReauth(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'OfficialTemplateMessagesPage shows generic service label instead of raw account id',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/me/official_template_messages?unread_only=false',
      );
      return http.Response(
        '{"messages":[{"id":1,"kind":"service","title":"System update","body":"Done","created_at":"2026-03-16T00:00:00Z","read_at":null}]}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
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

    expect(find.text('System update'), findsOneWidget);
    expect(find.text('Service notification'), findsOneWidget);
    expect(find.text('acc_1'), findsNothing);
  });

  testWidgets(
      'OfficialTemplateMessagesPage ignores internal-only service deeplink metadata for shortcut UI',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/me/official_template_messages?unread_only=false',
      );
      return http.Response(
        '{"messages":[{"id":1,"kind":"service","title":"System update","body":"Done","deeplink_json":{"official_account_id":"shamell_pay","session_id":11},"created_at":"2026-03-16T00:00:00Z","read_at":null}]}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
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

    expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
  });

  testWidgets(
      'OfficialTemplateMessagesPage persists unread flag into explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    final store = ChatLocalStore();
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.two.example/me/official_template_messages?unread_only=false',
      );
      return http.Response(
        '{"messages":[{"id":1,"kind":"service","title":"System update","body":"Done","created_at":"2026-03-16T00:00:00Z","read_at":null}]}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _testApp(
        OfficialTemplateMessagesPage(
          baseUrl: 'https://api.two.example',
          httpClient: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      await store.loadServiceNotificationsHasUnread(
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(await store.loadServiceNotificationsHasUnread(), isFalse);
  });

  testWidgets(
      'OfficialTemplateMessagesPage loads older pages with a stable before cursor',
      (tester) async {
    final requests = <Uri>[];
    final firstPage = List.generate(50, (index) {
      final id = 150 - index;
      final minute = (50 - index).toString().padLeft(2, '0');
      return <String, dynamic>{
        'id': id,
        'kind': 'service',
        'title': 'Message $id',
        'body': 'Body $id',
        'created_at': '2026-03-18T10:$minute:00Z',
        'read_at': null,
      };
    });
    final client = MockClient((request) async {
      requests.add(request.url);
      final beforeId = request.url.queryParameters['before_id'];
      if (beforeId == null) {
        return http.Response(
          jsonEncode(<String, dynamic>{'messages': firstPage}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      expect(beforeId, '101');
      expect(
        request.url.queryParameters['before_created_at'],
        startsWith('2026-03-18T10:01:00'),
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 100,
              'kind': 'service',
              'title': 'Message 100',
              'body': 'Body 100',
              'created_at': '2026-03-18T10:00:00Z',
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
    expect(find.text('Message 150'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Load more'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(find.text('Message 100'), findsOneWidget);
  });

  testWidgets(
      'OfficialMomentsCommentsPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialMomentsCommentsPage(
          baseUrl: 'https://user:pass@example.test/root',
          accountId: 'acc_1',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'OfficialOwnerConsolePage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://user:pass@example.test/root',
          accountId: 'acc_1',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'OfficialOwnersAccessPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://user:pass@example.test/root',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'OfficialServiceInboxPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://user:pass@example.test/root',
          accountId: 'acc_1',
          httpClient: client,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'OfficialTemplateMessagesPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialTemplateMessagesPage(
          baseUrl: 'https://user:pass@example.test/root',
          httpClient: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid server URL.'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });
}
