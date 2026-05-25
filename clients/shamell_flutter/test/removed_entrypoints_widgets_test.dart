import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_page.dart';
import 'package:shamell_flutter/core/friend_annotations_store.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/official_moments_comments_page.dart';
import 'package:shamell_flutter/core/shamell_contact_info_page.dart';
import 'package:shamell_flutter/core/shamell_moments_page.dart';

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

  testWidgets('ShamellChatPage search entry opens chat search', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const ShamellChatPage(
          baseUrl: 'https://example.test',
          runStartupTasks: false,
          showBottomNav: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Search',
      ),
      findsOneWidget,
    );
    expect(find.text('This module shortcut is no longer supported.'),
        findsNothing);
  });

  testWidgets('ShamellContactInfoPage moments tile opens Moments',
      (tester) async {
    var pushedPages = 0;
    Widget? pushedPage;
    await tester.pumpWidget(
      _testApp(
        ShamellContactInfoPage(
          baseUrl: 'https://example.test',
          friend: const <String, dynamic>{
            'id': 'friend_1',
            'phone': '+963955000111',
          },
          peerId: 'peer_1',
          displayName: 'Friend',
          alias: '',
          tags: '',
          isCloseFriend: false,
          pushPage: (page) {
            pushedPages += 1;
            pushedPage = page;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Moments'));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(pushedPages, 1);
    expect(pushedPage, isA<ShamellMomentsPage>());
  });

  testWidgets(
      'ShamellContactInfoPage saves remarks and tags without overwriting other peers',
      (tester) async {
    await saveFriendAliases(
      <String, String>{'peer_1': 'Old Alias', 'peer_2': 'Keep Alias'},
      baseUrlOverride: 'https://example.test',
    );
    await saveFriendTags(
      <String, String>{'peer_1': 'old-tag', 'peer_2': 'keep-tag'},
      baseUrlOverride: 'https://example.test',
    );

    await tester.pumpWidget(
      _testApp(
        ShamellContactInfoPage(
          baseUrl: 'https://example.test',
          friend: const <String, dynamic>{
            'id': 'friend_1',
            'phone': '+963955000111',
          },
          peerId: 'peer_1',
          displayName: 'Friend',
          alias: 'Old Alias',
          tags: 'old-tag',
          isCloseFriend: false,
          pushPage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Set Remarks and Tags'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Updated Alias');
    await tester.enterText(fields.at(1), 'fresh-tag');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      await loadFriendAliases(baseUrlOverride: 'https://example.test'),
      <String, String>{
        'peer_1': 'Updated Alias',
        'peer_2': 'Keep Alias',
      },
    );
    expect(
      await loadFriendTags(baseUrlOverride: 'https://example.test'),
      <String, String>{
        'peer_1': 'fresh-tag',
        'peer_2': 'keep-tag',
      },
    );
    expect(find.text('Updated Alias'), findsOneWidget);
  });

  testWidgets(
      'ShamellContactInfoPage close-friend toggle preserves other peers',
      (tester) async {
    await saveCloseFriendIds(
      <String>{'peer_2'},
      baseUrlOverride: 'https://example.test',
    );
    final closeFriendRequests = <http.Request>[];
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.pathSegments.length == 3 &&
          request.url.pathSegments[0] == 'me' &&
          request.url.pathSegments[1] == 'close_friends' &&
          request.url.pathSegments[2] == '+963955000111') {
        closeFriendRequests.add(request);
        return http.Response(jsonEncode(<String, Object?>{'ok': true}), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      _testApp(
        ShamellContactInfoPage(
          baseUrl: 'https://example.test',
          friend: const <String, dynamic>{
            'id': 'friend_1',
            'phone': '+963955000111',
          },
          peerId: 'peer_1',
          displayName: 'Friend',
          alias: '',
          tags: '',
          isCloseFriend: false,
          httpClient: client,
          pushPage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Close friend'));
    await tester.pumpAndSettle();

    expect(closeFriendRequests, hasLength(1));
    expect(
      await loadCloseFriendIds(baseUrlOverride: 'https://example.test'),
      <String>{'peer_1', 'peer_2'},
    );
  });

  testWidgets(
      'OfficialMomentsCommentsPage open action opens Moments',
      (tester) async {
    final requests = <String>[];
    final mock = MockClient((req) async {
      requests.add('${req.method} ${req.url}');
      if (req.method == 'GET' && req.url.path == '/moments/admin/comments') {
        return http.Response(
          jsonEncode({
            'items': [],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialMomentsCommentsPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            permissions: <String>[
              'official.dashboard.read',
              'official.dashboard.write',
            ],
            products: <String>['official_accounts'],
            officialAccountIds: <String>['acc_1'],
          ),
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(
      requests.any((r) => r.contains(
          'GET https://example.test/moments/admin/comments?official_account_id=acc_1&limit=200')),
      isTrue,
      reason: 'requests=$requests',
    );

    final dynamic state =
        tester.state(find.byType(OfficialMomentsCommentsPage));
    final baselineRoute = ModalRoute.of(
      tester.element(find.byType(OfficialMomentsCommentsPage)),
    );
    state.debugShowRemovedMomentsEntry();
    await tester.pumpAndSettle();

    expect(baselineRoute?.isCurrent, isFalse);
    expect(find.byType(ShamellMomentsPage), findsOneWidget);
  });
}
