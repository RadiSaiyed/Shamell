import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/official_owner_console_page.dart';
import 'package:shamell_flutter/core/official_owners_access_page.dart';
import 'package:shamell_flutter/core/official_service_inbox_page.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

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
  String? clipboardText;
  late SharePlatform originalSharePlatform;
  late _RecordingSharePlatform recordingSharePlatform;
  late PathProviderPlatform originalPathProviderPlatform;
  late _RecordingPathProviderPlatform recordingPathProviderPlatform;
  late Directory documentsDir;

  setUpAll(() async {
    originalSharePlatform = SharePlatform.instance;
    originalPathProviderPlatform = PathProviderPlatform.instance;
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            final args = (call.arguments as Map?) ?? const <String, Object?>{};
            clipboardText = (args['text'] ?? '').toString();
            return null;
          case 'Clipboard.getData':
            return <String, Object?>{'text': clipboardText};
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    SharePlatform.instance = originalSharePlatform;
    PathProviderPlatform.instance = originalPathProviderPlatform;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    clipboardText = null;
    documentsDir = Directory.systemTemp.createTempSync('official-owner-docs-');
    recordingSharePlatform = _RecordingSharePlatform();
    recordingPathProviderPlatform = _RecordingPathProviderPlatform(
      applicationDocumentsPath: documentsDir.path,
    );
    SharePlatform.instance = recordingSharePlatform;
    PathProviderPlatform.instance = recordingPathProviderPlatform;
    addTearDown(() {
      if (documentsDir.existsSync()) {
        documentsDir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('OfficialOwnerConsolePage renders loaded account from API',
      (tester) async {
    final requests = <String>[];
    final mock = MockClient((req) async {
      requests.add(req.url.toString());
      final path = req.url.path;
      if (path == '/official_accounts') {
        expect(req.url.queryParameters['account_id'], 'acc_1');
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 8,
            'feed_items_30d': 3,
            'followers': 120,
            'feed_items_per_1k_followers': 25.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(
      requests.any((u) =>
          u.contains('/official_accounts?followed_only=false') &&
          u.contains('account_id=acc_1')),
      isTrue,
      reason: 'requests=$requests',
    );
    expect(
      requests.any((u) => u.contains('/official_accounts/acc_1/moments_stats')),
      isTrue,
      reason: 'requests=$requests',
    );
    expect(
      requests.any(
          (u) => u.contains('/admin/official_accounts/acc_1/auto_replies')),
      isTrue,
      reason: 'requests=$requests',
    );
    expect(find.textContaining('Unique sharers'), findsNothing);
    expect(find.textContaining('Comments (30d)'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('OfficialOwnerConsolePage surfaces command desk priorities',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 8,
            'feed_items_30d': 3,
            'followers': 120,
            'feed_items_per_1k_followers': 25.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(find.text('Command desk'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Priority lanes'), findsOneWidget);
    expect(find.text('Add keyword rules'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerAttention_profile')),
        matching: find.text('Profile needs update'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerAttention_profile')),
        matching: find.text(
          'Add Address, Website before distributing this poster.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Service inbox'), findsOneWidget);
    expect(find.text('Manage access'), findsWidgets);
    expect(find.text('Feed comments'), findsOneWidget);
    expect(find.text('Welcome message'), findsWidgets);
    expect(find.text('New post'), findsOneWidget);
    expect(find.text('Service'), findsWidgets);
    expect(find.text('Access'), findsWidgets);
    expect(find.text('Publishing'), findsWidgets);
    expect(find.text('Offers'), findsWidgets);
    expect(find.text('Automation'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
    expect(
      find.byKey(const Key('officialOwnerWorkspaceFocusTone_all_alert')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceFocusTone_service_watch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceFocusTone_access_healthy')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('officialOwnerWorkspaceFocusTone_publishing_healthy'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceFocusTone_commerce_watch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceFocusTone_automation_alert')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceFocusTone_profile_watch')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerWorkspaceFocusSummary_alert')),
        matching: find.text('Alert 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerWorkspaceFocusSummary_watch')),
        matching: find.text('Watch 3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerWorkspaceFocusSummary_healthy')),
        matching: find.text('Healthy 2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneStatus_service')),
        matching: find.text('Watch'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneStatus_access')),
        matching: find.text('Healthy'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneStatus_publishing')),
        matching: find.text('Healthy'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneStatus_commerce')),
        matching: find.text('Watch'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneStatus_automation')),
        matching: find.text('Alert'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneStatus_profile')),
        matching: find.text('Needs update'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLane_profile')),
        matching: find.text('2 of 4 checks ready'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLane_profile')),
        matching: find.text(
          'Add Address, Website before distributing this poster.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneNext_service')),
        matching: find.text('Add keyword rule'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneNext_profile')),
        matching: find.text('Complete profile'),
      ),
      findsOneWidget,
    );
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Write'), findsWidgets);
  });

  testWidgets('OfficialOwnerConsolePage command lanes focus workspaces',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': 'Old Town, Damascus',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 12,
            'feed_items_30d': 4,
            'followers': 220,
            'feed_items_per_1k_followers': 18.2,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
              {
                'id': 2,
                'kind': 'keyword',
                'keyword': 'hours',
                'text': 'We are open 9-5.',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('officialOwnerCommandLane_automation')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 6 desks'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('officialOwnerWorkspaceFocus_automation')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_automation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_service')),
      findsNothing,
    );
  });

  testWidgets('OfficialOwnerConsolePage edits card offers through admin API',
      (tester) async {
    configureLargeViewport(tester);
    Map<String, dynamic>? patchPayload;
    int offersListLoads = 0;
    final requests = <Uri>[];
    final mock = MockClient((req) async {
      requests.add(req.url);
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': 'Old Town, Damascus',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 12,
            'feed_items_30d': 4,
            'followers': 220,
            'feed_items_per_1k_followers': 18.2,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/cards/dashboard') {
        return http.Response(
          jsonEncode({
            'active_offers': 1,
            'claimed_total': 9,
            'redeemed_total': 4,
            'cardholder_accounts': 3,
            'top_offers': [
              {
                'id': 'market_coupon',
                'title_en': 'Market coupon',
                'kind': 'coupon',
                'discount_text': '15%',
                'active': true,
                'featured': false,
                'claimed_count': 9,
                'redeemed_count': 4,
                'inventory_total': 100,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/cards/offers' &&
          req.method == 'GET') {
        offersListLoads += 1;
        return http.Response(
          jsonEncode({
            'offers': [
              {
                'id': 'market_coupon',
                'title_en': 'Market coupon',
                'title_ar': 'قسيمة السوق',
                'description_en': 'Saved in SyrChat cards.',
                'kind': 'coupon',
                'discount_text': offersListLoads > 1 ? '20%' : '15%',
                'active': true,
                'featured': false,
                'claimed_count': 9,
                'redeemed_count': 4,
                'inventory_total': 100,
                'valid_until': '2026-12-31T23:59:00Z',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/cards/offers/market_coupon' &&
          req.method == 'PATCH') {
        expect(req.headers['Idempotency-Key'], isNotNull);
        patchPayload = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'offer': {
              'id': 'market_coupon',
              'title_en': patchPayload?['title_en'],
              'kind': patchPayload?['kind'],
              'discount_text': patchPayload?['discount_text'],
              'active': patchPayload?['active'],
              'featured': patchPayload?['featured'],
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
              {
                'id': 2,
                'kind': 'keyword',
                'keyword': 'hours',
                'text': 'We are open 9-5.',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Offers desk'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Offers desk'), findsOneWidget);
    expect(find.text('Market coupon'), findsOneWidget);
    expect(find.textContaining('15%'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market coupon'));
    await tester.pumpAndSettle();

    expect(find.text('Edit offer'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Discount / benefit text'),
      '20%',
    );
    await tester.tap(find.text('Save').last);
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(patchPayload, isNotNull);
    expect(patchPayload?['offer_id'], isNull);
    expect(patchPayload?['title_en'], 'Market coupon');
    expect(patchPayload?['kind'], 'coupon');
    expect(patchPayload?['discount_text'], '20%');
    expect(patchPayload?['active'], isTrue);
    expect(offersListLoads, greaterThanOrEqualTo(2));
    expect(
      requests.any(
        (uri) =>
            uri.path == '/admin/official_accounts/acc_1/cards/offers' &&
            uri.queryParameters['limit'] == '12',
      ),
      isTrue,
    );
    expect(find.text('Offer updated.'), findsOneWidget);
  });

  testWidgets(
      'OfficialOwnerConsolePage edits Green Paket campaigns through admin API',
      (tester) async {
    configureLargeViewport(tester);
    Map<String, dynamic>? patchPayload;
    int campaignsListLoads = 0;
    final requests = <Uri>[];
    final mock = MockClient((req) async {
      requests.add(req.url);
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': 'Old Town, Damascus',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 12,
            'feed_items_30d': 4,
            'followers': 220,
            'feed_items_per_1k_followers': 18.2,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/campaigns/dashboard') {
        return http.Response(
          jsonEncode({
            'campaigns_total': 1,
            'campaigns_active': 1,
            'packets_issued': 7,
            'packets_claimed': 5,
            'amount_cents': 7000,
            'claimed_amount_cents': 5000,
            'moments_shares_total': 3,
            'moments_shares_30d': 2,
            'admin_events_total': 1,
            'admin_events_30d': 1,
            'top_campaigns': [
              {
                'id': 'spring_green',
                'campaign_id': 'spring_green',
                'official_account_id': 'acc_1',
                'title': 'Spring Green Paket',
                'description': 'Launch week campaign.',
                'default_amount_cents': 1000,
                'default_count': 10,
                'active': true,
                'packets_issued': 7,
                'packets_claimed': 5,
                'amount_cents': 7000,
                'claimed_amount_cents': 5000,
                'moments_shares': 3,
                'moments_shares_30d': 2,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/campaigns' &&
          req.method == 'GET') {
        campaignsListLoads += 1;
        return http.Response(
          jsonEncode({
            'campaigns': [
              {
                'id': 'spring_green',
                'campaign_id': 'spring_green',
                'official_account_id': 'acc_1',
                'title': 'Spring Green Paket',
                'description': campaignsListLoads > 1
                    ? 'Updated operator campaign.'
                    : 'Launch week campaign.',
                'default_amount_cents': 1000,
                'default_count': campaignsListLoads > 1 ? 12 : 10,
                'active': true,
                'packets_issued': 7,
                'packets_claimed': 5,
                'amount_cents': 7000,
                'claimed_amount_cents': 5000,
                'moments_shares': 3,
                'moments_shares_30d': 2,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/campaigns/spring_green' &&
          req.method == 'PATCH') {
        expect(req.headers['Idempotency-Key'], isNotNull);
        patchPayload = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'spring_green',
            'campaign_id': 'spring_green',
            'title': patchPayload?['title'],
            'description': patchPayload?['description'],
            'default_amount_cents': patchPayload?['default_amount_cents'],
            'default_count': patchPayload?['default_count'],
            'active': patchPayload?['active'],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
              {
                'id': 2,
                'kind': 'keyword',
                'keyword': 'hours',
                'text': 'We are open 9-5.',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Green Paket campaigns'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Green Paket campaigns'), findsOneWidget);
    expect(find.text('Spring Green Paket'), findsOneWidget);
    expect(find.textContaining('5 claimed'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spring Green Paket'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Green Paket campaign'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Default packet count'),
      '12',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Updated operator campaign.',
    );
    await tester.tap(find.text('Save').last);
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(patchPayload, isNotNull);
    expect(patchPayload?['campaign_id'], isNull);
    expect(patchPayload?['title'], 'Spring Green Paket');
    expect(patchPayload?['description'], 'Updated operator campaign.');
    expect(patchPayload?['default_amount_cents'], 1000);
    expect(patchPayload?['default_count'], 12);
    expect(patchPayload?['active'], isTrue);
    expect(campaignsListLoads, greaterThanOrEqualTo(2));
    expect(
      requests.any(
        (uri) =>
            uri.path == '/admin/official_accounts/acc_1/campaigns' &&
            uri.queryParameters['limit'] == '12',
      ),
      isTrue,
    );
    expect(find.text('Campaign updated.'), findsOneWidget);
  });

  testWidgets('OfficialOwnerConsolePage next actions open direct flows',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 8,
            'feed_items_30d': 3,
            'followers': 120,
            'feed_items_per_1k_followers': 25.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('officialOwnerCommandLaneNextAction_service')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keyword auto‑reply rule'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('officialOwnerCommandLaneNextAction_profile')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Official profile details'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Address'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'QR payload'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerProfileEditorCopyQr')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerProfileEditorShareQr')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerProfileEditorPosterQr')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const Key('officialOwnerProfileEditorPosterQr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Official QR poster'), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterPanel')), findsOneWidget);
    expect(
        find.byKey(const Key('officialOwnerQrPosterPayload')), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterShare')), findsOneWidget);

    await tester.tap(find.byKey(const Key('officialOwnerQrPosterClose')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Official QR poster'), findsNothing);
  });

  testWidgets('OfficialOwnerConsolePage attention items open direct flows',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': null,
                'website_url': null,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 8,
            'feed_items_30d': 3,
            'followers': 120,
            'feed_items_per_1k_followers': 25.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('officialOwnerAttention_keywords')));
    await tester.pumpAndSettle();
    expect(find.text('Keyword auto‑reply rule'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('officialOwnerAttention_profile')));
    await tester.pumpAndSettle();
    expect(find.text('Official profile details'), findsOneWidget);
  });

  testWidgets(
      'OfficialOwnerConsolePage profile next action patches payload and refreshes',
      (tester) async {
    configureLargeViewport(tester);
    final patchBodies = <Map<String, dynamic>>[];
    final patchHeaders = <Map<String, String>>[];
    var currentAccount = <String, dynamic>{
      'id': 'acc_1',
      'name': 'Demo Account',
      'verified': true,
      'avatar_url': null,
      'category': 'Shop',
      'city': 'Damascus',
      'opening_hours': '9-5',
      'qr_payload': null,
      'address': null,
      'website_url': null,
    };
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts' && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'accounts': [currentAccount],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 8,
            'feed_items_30d': 3,
            'followers': 120,
            'feed_items_per_1k_followers': 25.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1' && req.method == 'PATCH') {
        final body = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        patchBodies.add(body);
        patchHeaders.add(req.headers);
        currentAccount = <String, dynamic>{
          ...currentAccount,
          'address': body['address'],
          'opening_hours': body['opening_hours'],
          'website_url': body['website_url'],
          'qr_payload': body['qr_payload'],
        };
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('officialOwnerCommandLaneNextAction_profile')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      'Bab Touma',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Opening hours'),
      '8-6',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Website URL'),
      'https://example.test/store',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'QR payload'),
      'shamell://official/demo',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(patchBodies, hasLength(1));
    expect(patchHeaders, hasLength(1));
    expect(patchBodies.single['address'], 'Bab Touma');
    expect(patchBodies.single['opening_hours'], '8-6');
    expect(patchBodies.single['website_url'], 'https://example.test/store');
    expect(patchBodies.single['qr_payload'], 'shamell://official/demo');
    final idempotency = patchHeaders.single['Idempotency-Key'] ??
        patchHeaders.single['idempotency-key'];
    expect(idempotency, isNotNull);
    expect(idempotency!, startsWith('official-account-profile-patch-'));
    expect(find.text('Profile details updated.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneNext_profile')),
        matching: find.text('Review profile'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLaneStatus_profile')),
        matching: find.text('Ready to print'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerCommandLane_profile')),
        matching: find.text('4 of 4 checks ready'),
      ),
      findsOneWidget,
    );
    expect(find.text('Profile needs update'), findsNothing);
  });

  testWidgets(
      'OfficialOwnerConsolePage profile desk copies, shares and previews qr',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'shamell://official/demo',
                'address': 'Bab Touma',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 8,
            'feed_items_30d': 3,
            'followers': 120,
            'feed_items_per_1k_followers': 25.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerProfileCopyQr')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('officialOwnerProfileCopyQr')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('officialOwnerProfileReadinessPanel')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerProfileReadinessPanel')),
        matching: find.text('Ready to print'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerProfileReadinessPanel')),
        matching: find.text('4 of 4 checks ready'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerProfileReadinessCheck_payload')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerProfileReadinessCheck_address')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerProfileReadinessCheck_hours')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerProfileReadinessCheck_website')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('officialOwnerProfileCopyQr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'shamell://official/demo');

    await tester.tap(find.byKey(const Key('officialOwnerProfileShareQr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Official QR share'), findsOneWidget);
    expect(
        find.byKey(const Key('officialOwnerQrSharePayload')), findsOneWidget);
    expect(find.text('shamell://official/demo'), findsWidgets);

    await tester.tap(find.byKey(const Key('officialOwnerQrShareClose')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Official QR share'), findsNothing);

    expect(
        find.byKey(const Key('officialOwnerProfilePosterQr')), findsOneWidget);

    await tester.tap(find.byKey(const Key('officialOwnerProfilePosterQr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Official QR poster'), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterPanel')), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterCode')), findsOneWidget);
    expect(
        find.byKey(const Key('officialOwnerQrPosterPayload')), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerQrPosterReadinessPanel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerQrPosterReadinessStatus')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerQrPosterSetupPanel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerQrPosterSetup_print')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerQrPosterSetup_counter')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerQrPosterReadinessPanel')),
        matching: find.text('Ready to print'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerQrPosterReadinessPanel')),
        matching: find.text('4 of 4 checks ready'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_payload')),
        findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_address')),
        findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_hours')),
        findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_website')),
        findsOneWidget);
    expect(find.text('Quick setup guide'), findsOneWidget);
    expect(find.text('Print setup'), findsOneWidget);
    expect(find.text('Counter setup'), findsOneWidget);
    expect(find.text('Demo Account'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerQrPosterCopyPath')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('officialOwnerQrPosterSave')), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterShare')), findsOneWidget);

    final copyPathButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('officialOwnerQrPosterCopyPath')),
    );
    copyPathButton.onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final copiedPosterPath = await Clipboard.getData('text/plain');
    expect(
      copiedPosterPath?.text,
      '${documentsDir.path}/official_qr_posters/official_acc_1_qr_poster.svg',
    );

    await tester
        .ensureVisible(find.byKey(const Key('officialOwnerQrPosterSave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('officialOwnerQrPosterSave')));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      if (recordingPathProviderPlatform.downloadsPathCalls > 0 &&
          recordingPathProviderPlatform.applicationDocumentsPathCalls > 0) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(recordingPathProviderPlatform.downloadsPathCalls, greaterThan(0));
    expect(
      recordingPathProviderPlatform.applicationDocumentsPathCalls,
      greaterThan(0),
    );

    final shareButton = tester.widget<FilledButton>(
      find.byKey(const Key('officialOwnerQrPosterShare')),
    );
    shareButton.onPressed!.call();
    await tester.pump();
    for (var i = 0;
        i < 100 && recordingSharePlatform.shareXFilesInvocations.isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(recordingSharePlatform.shareXFilesInvocations, isNotEmpty);
    final shareCall = recordingSharePlatform.shareXFilesInvocations.last;
    expect(shareCall.text, 'Demo Account QR poster');
    expect(shareCall.fileNameOverrides, ['official_acc_1_qr_poster.svg']);
    expect(shareCall.files, hasLength(1));
    expect(shareCall.files.single.mimeType, 'image/svg+xml');
    final sharedBytes = await shareCall.files.single.readAsBytes();
    expect(sharedBytes, isNotEmpty);
    expect(utf8.decode(sharedBytes), contains('<svg'));

    await tester
        .ensureVisible(find.byKey(const Key('officialOwnerQrPosterClose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('officialOwnerQrPosterClose')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Official QR poster'), findsNothing);
  });

  testWidgets(
      'OfficialOwnerConsolePage poster signals needs update for incomplete profile',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '',
                'qr_payload': 'shamell://official/demo',
                'address': '',
                'website_url': '',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 2,
            'feed_items_30d': 1,
            'followers': 12,
            'feed_items_per_1k_followers': 8.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerProfileReadinessPanel')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('officialOwnerProfileReadinessPanel')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('officialOwnerProfileReadinessPanel')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerProfileReadinessPanel')),
        matching: find.text('Needs update'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerProfileReadinessPanel')),
        matching: find.text('1 of 4 checks ready'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerProfileReadinessPanel')),
        matching: find.text(
          'Add Address, Hours, Website before distributing this poster.',
        ),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerProfilePosterQr')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('officialOwnerProfilePosterQr')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('officialOwnerProfilePosterQr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const Key('officialOwnerQrPosterReadinessPanel')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerQrPosterReadinessPanel')),
        matching: find.text('Needs update'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerQrPosterReadinessPanel')),
        matching: find.text('1 of 4 checks ready'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerQrPosterReadinessPanel')),
        matching: find.text(
          'Add Address, Hours, Website before distributing this poster.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_payload')),
        findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_address')),
        findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_hours')),
        findsOneWidget);
    expect(find.byKey(const Key('officialOwnerQrPosterCheck_website')),
        findsOneWidget);
  });

  testWidgets('OfficialOwnerConsolePage filters workspaces locally',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': 'Old Town, Damascus',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 12,
            'feed_items_30d': 4,
            'followers': 220,
            'feed_items_per_1k_followers': 18.2,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
              {
                'id': 2,
                'kind': 'keyword',
                'keyword': 'hours',
                'text': 'We are open 9-5.',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(find.text('Workspace focus'), findsOneWidget);
    expect(find.text('All (6)'), findsOneWidget);
    expect(find.text('Publishing (4)'), findsOneWidget);
    expect(find.text('Automation (2)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerWorkspaceFocusSummary_alert')),
        matching: find.text('Alert 0'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerWorkspaceFocusSummary_watch')),
        matching: find.text('Watch 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerWorkspaceFocusSummary_healthy')),
        matching: find.text('Healthy 5'),
      ),
      findsOneWidget,
    );
    expect(find.text('Showing 6 of 6 desks'), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerWorkspace_service')),
        findsOneWidget);
    expect(
        find.byKey(const Key('officialOwnerWorkspace_access')), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspace_publishing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_commerce')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspace_automation')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_automation')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspace_profile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('officialOwnerWorkspace_profile')),
        findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspaceFocus_profile')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const Key('officialOwnerWorkspaceFocus_profile')),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspace_profile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Showing 1 of 6 desks'), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerWorkspace_profile')),
        findsOneWidget);
    expect(
        find.byKey(const Key('officialOwnerWorkspace_service')), findsNothing);
    expect(
        find.byKey(const Key('officialOwnerWorkspace_access')), findsNothing);
    expect(
      find.byKey(const Key('officialOwnerWorkspace_publishing')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_commerce')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_automation')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceSignal_profile_qr')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('officialOwnerWorkspaceFocusSummary_healthy')),
        matching: find.text('Healthy 1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('officialOwnerWorkspaceFocus_all')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspace_profile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Showing 6 of 6 desks'), findsOneWidget);
    expect(find.byKey(const Key('officialOwnerWorkspace_service')),
        findsOneWidget);
    expect(find.byKey(const Key('officialOwnerWorkspace_profile')),
        findsOneWidget);
  });

  testWidgets('OfficialOwnerConsolePage remembers workspace focus',
      (tester) async {
    configureLargeViewport(tester);
    final bucket = PageStorageBucket();
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': 'Old Town, Damascus',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 12,
            'feed_items_30d': 4,
            'followers': 220,
            'feed_items_per_1k_followers': 18.2,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
              {
                'id': 2,
                'kind': 'keyword',
                'keyword': 'hours',
                'text': 'We are open 9-5.',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    Widget buildConsole() {
      return _testApp(
        PageStorage(
          bucket: bucket,
          child: OfficialOwnerConsolePage(
            key: const PageStorageKey<String>('officialOwnerConsoleFocus'),
            baseUrl: 'https://example.test',
            accountId: 'acc_1',
            httpClient: mock,
            privilegeSnapshotOverride: _officialPrivilegeSnapshot,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('officialOwnerWorkspaceFocus_publishing')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 6 desks'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspace_publishing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_service')),
      findsNothing,
    );

    await tester.pumpWidget(buildConsole());
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 6 desks'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('officialOwnerWorkspaceFocus_publishing')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_publishing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspace_service')),
      findsNothing,
    );
  });

  testWidgets('OfficialOwnerConsolePage collapses and expands visible desks',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': 'Old Town, Damascus',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 12,
            'feed_items_30d': 4,
            'followers': 220,
            'feed_items_per_1k_followers': 18.2,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
              {
                'id': 2,
                'kind': 'keyword',
                'keyword': 'hours',
                'text': 'We are open 9-5.',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 6 desks'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_access')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspaceBody_profile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_profile')),
      findsOneWidget,
    );

    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('officialOwnerWorkspaceToggle_access')),
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Collapsed 1 of 6 desks'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Collapsed 1 of 6 desks'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_access')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceCollapsed_access')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerCollapseVisible')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('officialOwnerCollapseVisible')),
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 6 of 6 desks'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_profile')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspaceCollapsed_profile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceCollapsed_profile')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerExpandVisible')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('officialOwnerExpandVisible')),
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();

    expect(find.text('Collapsed 0 of 6 desks'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_access')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspaceBody_profile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_profile')),
      findsOneWidget,
    );
  });

  testWidgets('OfficialOwnerConsolePage remembers collapsed desks',
      (tester) async {
    configureLargeViewport(tester);
    final bucket = PageStorageBucket();
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
                'address': 'Old Town, Damascus',
                'website_url': 'https://example.test/store',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 12,
            'feed_items_30d': 4,
            'followers': 220,
            'feed_items_per_1k_followers': 18.2,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'id': 1,
                'kind': 'welcome',
                'text': 'Welcome to Demo Account!',
                'enabled': true,
              },
              {
                'id': 2,
                'kind': 'keyword',
                'keyword': 'hours',
                'text': 'We are open 9-5.',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    Widget buildConsole() {
      return _testApp(
        PageStorage(
          bucket: bucket,
          child: OfficialOwnerConsolePage(
            key: const PageStorageKey<String>('officialOwnerConsoleCollapsed'),
            baseUrl: 'https://example.test',
            accountId: 'acc_1',
            httpClient: mock,
            privilegeSnapshotOverride: _officialPrivilegeSnapshot,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildConsole());
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspaceToggle_automation')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('officialOwnerWorkspaceToggle_automation')),
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Collapsed 1 of 6 desks'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Collapsed 1 of 6 desks'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_automation')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspaceCollapsed_automation')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceCollapsed_automation')),
      findsOneWidget,
    );

    await tester.pumpWidget(buildConsole());
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Collapsed 1 of 6 desks'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Collapsed 1 of 6 desks'), findsOneWidget);
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_service')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceBody_automation')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('officialOwnerWorkspaceCollapsed_automation')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('officialOwnerWorkspaceCollapsed_automation')),
      findsOneWidget,
    );
  });

  testWidgets(
      'OfficialOwnerConsolePage loads older auto replies with a stable after cursor',
      (tester) async {
    final requests = <Uri>[];
    final firstPage = List.generate(200, (index) {
      final id = index + 1;
      return <String, dynamic>{
        'id': id,
        'kind': 'keyword',
        'keyword': 'rule_$id',
        'text': 'Reply $id',
        'enabled': true,
      };
    });
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/official_accounts') {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'acc_1',
                'name': 'Demo Account',
                'verified': true,
                'avatar_url': null,
                'category': 'Shop',
                'city': 'Damascus',
                'opening_hours': '9-5',
                'qr_payload': 'OFFICIAL|acc_1',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/moments_stats') {
        return http.Response(
          jsonEncode({
            'feed_items_total': 8,
            'feed_items_30d': 3,
            'followers': 120,
            'feed_items_per_1k_followers': 25.0,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/auto_replies') {
        requests.add(req.url);
        expect(req.url.queryParameters['limit'], '200');
        final afterId = req.url.queryParameters['after_id'];
        if (afterId == null) {
          return http.Response(
            jsonEncode(<String, dynamic>{'rules': firstPage}),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        expect(afterId, '200');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'rules': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 201,
                'kind': 'keyword',
                'keyword': 'rule_201',
                'text': 'Reply 201',
                'enabled': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnerConsolePage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Load more'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final loadMoreButton = find.widgetWithText(TextButton, 'Load more');
    expect(loadMoreButton, findsOneWidget);
    final loadMore = tester.widget<TextButton>(loadMoreButton).onPressed;
    expect(loadMore, isNotNull);
    await (loadMore! as dynamic)();
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('OfficialOwnersAccessPage renders owners list from API',
      (tester) async {
    final requests = <String>[];
    final mock = MockClient((req) async {
      requests.add(req.url.toString());
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/owners') {
        return http.Response(
          jsonEncode({
            'owners': [
              {
                'account_id': 'a'.padLeft(64, 'a'),
                'phone': '+963999000111',
                'created_at': '2026-03-06T10:00:00Z',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(
      requests.any(
          (u) => u.contains('/admin/official_accounts/acc_1/owners?limit=200')),
      isTrue,
      reason: 'requests=$requests',
    );
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('OfficialOwnersAccessPage filters owners locally',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      if (req.url.path == '/admin/official_accounts/acc_1/owners') {
        return http.Response(
          jsonEncode({
            'owners': [
              {
                'account_id': 'a'.padLeft(64, 'a'),
                'phone': '+963999000111',
                'created_at': '2026-03-06T10:00:00Z',
              },
              {
                'account_id': 'b'.padLeft(64, 'b'),
                'phone': '',
                'created_at': '2026-03-06T11:00:00Z',
              },
              {
                'account_id': '',
                'phone': '+963999000333',
                'created_at': '2026-03-06T12:00:00Z',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(find.text('Showing 3 of 3 owners'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Dual identity (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 owners'), findsOneWidget);
    expect(find.text('+963999000111'), findsOneWidget);
    expect(find.text('+963999000333'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search owners'),
      '000333',
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 owners'), findsOneWidget);
    expect(find.text('+963999000333'), findsOneWidget);
    expect(find.text('+963999000111'), findsNothing);
  });

  testWidgets(
      'OfficialOwnersAccessPage loads older owners with a stable before cursor',
      (tester) async {
    final requests = <Uri>[];
    final firstPage = List.generate(200, (index) {
      final id = 400 - index;
      final minute = (59 - (index % 60)).toString().padLeft(2, '0');
      return <String, dynamic>{
        'cursor_id': id,
        'account_id': ''.padLeft(64, 'a'),
        'phone': '+96395522${id.toString().padLeft(4, '0')}',
        'created_at': '2026-03-18T11:$minute:00Z',
      };
    });
    final mock = MockClient((req) async {
      requests.add(req.url);
      final beforeId = req.url.queryParameters['before_id'];
      if (beforeId == null) {
        return http.Response(
          jsonEncode(<String, dynamic>{'owners': firstPage}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      expect(beforeId, '201');
      expect(
        req.url.queryParameters['before_created_at'],
        '2026-03-18T11:40:00Z',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'owners': <Map<String, dynamic>>[
            <String, dynamic>{
              'cursor_id': 200,
              'account_id': ''.padLeft(64, 'b'),
              'phone': '+963955220200',
              'created_at': '2026-03-18T11:39:00Z',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    final loadMoreButton = find.widgetWithText(TextButton, 'Load more');
    expect(loadMoreButton, findsOneWidget);

    final loadMore = tester.widget<TextButton>(loadMoreButton).onPressed;
    expect(loadMore, isNotNull);
    await (loadMore! as dynamic)();
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('OfficialOwnersAccessPage add owner posts payload and refreshes',
      (tester) async {
    configureLargeViewport(tester);
    final requests = <String>[];
    final postedBodies = <Map<String, dynamic>>[];
    final postedHeaders = <Map<String, String>>[];
    final owners = <Map<String, dynamic>>[
      <String, dynamic>{
        'account_id': 'a'.padLeft(64, 'a'),
        'phone': '+963999000111',
        'created_at': '2026-03-06T10:00:00Z',
      },
    ];
    final newAccountIdInput = 'B'.padLeft(64, 'B');
    const newPhone = '+963988776655';

    final mock = MockClient((req) async {
      requests.add('${req.method} ${req.url}');
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{'owners': owners}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'POST') {
        final decoded = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        postedBodies.add(decoded);
        postedHeaders.add(req.headers);
        owners.add(<String, dynamic>{
          'account_id': decoded['account_id'] ?? '',
          'phone': decoded['phone'] ?? '',
          'created_at': '2026-03-07T08:00:00Z',
        });
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    await tester.scrollUntilVisible(
      find.text('Add owner'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add owner'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Account ID (optional)'),
      newAccountIdInput,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone E.164 (optional)'),
      newPhone,
    );
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await _pumpForDataLoad(tester);

    expect(postedBodies, hasLength(1));
    expect(postedHeaders, hasLength(1));
    expect(postedBodies.single['account_id'], 'b'.padLeft(64, 'b'));
    expect(postedBodies.single['phone'], newPhone);
    final addIkey = postedHeaders.single['Idempotency-Key'] ??
        postedHeaders.single['idempotency-key'];
    expect(addIkey, isNotNull);
    expect(addIkey!, startsWith('official-owner-add-'));
    expect(
      requests
          .where((u) => u.contains(
              'GET https://example.test/admin/official_accounts/acc_1/owners?limit=200'))
          .length,
      greaterThanOrEqualTo(2),
    );
    expect(find.text(newPhone), findsOneWidget);
  });

  testWidgets(
      'OfficialOwnersAccessPage reuses Idempotency-Key across add-owner retries in same sheet',
      (tester) async {
    configureLargeViewport(tester);
    final postHeaders = <Map<String, String>>[];
    var postCalls = 0;
    final owners = <Map<String, dynamic>>[];

    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{'owners': owners}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'POST') {
        postCalls += 1;
        postHeaders.add(req.headers);
        if (postCalls == 1) {
          return http.Response(
            '{"detail":"temporary upstream failure"}',
            500,
            headers: const {'content-type': 'application/json'},
          );
        }
        final decoded = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        owners.add(<String, dynamic>{
          'account_id': decoded['account_id'] ?? '',
          'phone': decoded['phone'] ?? '',
          'created_at': '2026-03-07T08:00:00Z',
        });
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    await tester.scrollUntilVisible(
      find.text('Add owner'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add owner'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Account ID (optional)'),
      'd'.padLeft(64, 'd'),
    );
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    expect(find.text('Add').last, findsOneWidget);

    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await _pumpForDataLoad(tester);

    expect(postHeaders, hasLength(2));
    final firstIkey =
        postHeaders[0]['Idempotency-Key'] ?? postHeaders[0]['idempotency-key'];
    final secondIkey =
        postHeaders[1]['Idempotency-Key'] ?? postHeaders[1]['idempotency-key'];
    expect(firstIkey, isNotNull);
    expect(secondIkey, isNotNull);
    expect(firstIkey, equals(secondIkey));
    expect(firstIkey!, startsWith('official-owner-add-'));
  });

  testWidgets(
      'OfficialOwnersAccessPage add owner reauths on critical session failure',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{'owners': const <Object?>[]}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'POST') {
        return http.Response(
          '{"detail":"auth session required"}',
          401,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    await tester.scrollUntilVisible(
      find.text('Add owner'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add owner'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Account ID (optional)'),
      'c'.padLeft(64, 'c'),
    );
    await tester.tap(find.text('Add').last);
    await tester.pump();
    await _pumpForReauth(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('OfficialOwnersAccessPage remove owner sends delete and reloads',
      (tester) async {
    final deleteBodies = <Map<String, dynamic>>[];
    final deleteHeaders = <Map<String, String>>[];
    final owners = <Map<String, dynamic>>[
      <String, dynamic>{
        'account_id': 'c'.padLeft(64, 'c'),
        'phone': '+963977665544',
        'created_at': '2026-03-06T10:00:00Z',
      },
    ];

    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{'owners': owners}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/owners' &&
          req.method == 'DELETE') {
        final decoded = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        deleteBodies.add(decoded);
        deleteHeaders.add(req.headers);
        owners.removeWhere((o) =>
            (o['account_id'] ?? '').toString() == decoded['account_id'] &&
            (o['phone'] ?? '').toString() == decoded['phone']);
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialOwnersAccessPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          accountName: 'Demo Account',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(find.text('+963977665544'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    await _pumpForDataLoad(tester);

    expect(deleteBodies, hasLength(1));
    expect(deleteHeaders, hasLength(1));
    expect(deleteBodies.single['account_id'], 'c'.padLeft(64, 'c'));
    expect(deleteBodies.single['phone'], '+963977665544');
    final removeIkey = deleteHeaders.single['Idempotency-Key'] ??
        deleteHeaders.single['idempotency-key'];
    expect(removeIkey, isNotNull);
    expect(removeIkey!, startsWith('official-owner-remove-'));
    expect(find.text('No additional owners yet.'), findsOneWidget);
  });

  testWidgets('OfficialServiceInboxPage renders sessions from API',
      (tester) async {
    final requests = <String>[];
    final mock = MockClient((req) async {
      requests.add(req.url.toString());
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/service_inbox') {
        return http.Response(
          jsonEncode({
            'sessions': [
              {
                'id': 1,
                'customer_phone': '+963955112233',
                'chat_peer_id': 'peer_1',
                'status': 'open',
                'last_message_ts': '2026-03-06T09:15:00Z',
                'unread_by_operator': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(
      requests.any((u) =>
          u.contains('/admin/official_accounts/acc_1/service_inbox?limit=100')),
      isTrue,
      reason: 'requests=$requests',
    );
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('OfficialServiceInboxPage filters sessions locally',
      (tester) async {
    configureLargeViewport(tester);
    final mock = MockClient((req) async {
      if (req.url.path == '/admin/official_accounts/acc_1/service_inbox') {
        return http.Response(
          jsonEncode({
            'sessions': [
              {
                'id': 1,
                'customer_phone': '+963955000001',
                'chat_peer_id': 'peer_1',
                'status': 'open',
                'last_message_ts': '2026-03-06T09:15:00Z',
                'unread_by_operator': true,
              },
              {
                'id': 2,
                'customer_phone': '+963955000002',
                'chat_peer_id': 'peer_2',
                'status': 'open',
                'last_message_ts': '2026-03-06T09:25:00Z',
                'unread_by_operator': false,
              },
              {
                'id': 3,
                'customer_phone': '+963955000003',
                'chat_peer_id': 'peer_3',
                'status': 'closed',
                'last_message_ts': '2026-03-06T09:35:00Z',
                'unread_by_operator': false,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(find.text('Showing 3 of 3 sessions'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Unread (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 sessions'), findsOneWidget);
    expect(find.text('+963955000001'), findsOneWidget);
    expect(find.text('+963955000002'), findsNothing);
    expect(find.text('+963955000003'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search sessions'),
      '000003',
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 sessions'), findsOneWidget);
    expect(find.text('+963955000003'), findsOneWidget);
    expect(find.text('+963955000001'), findsNothing);
  });

  testWidgets(
      'OfficialServiceInboxPage loads older sessions with a stable before cursor',
      (tester) async {
    final requests = <Uri>[];
    final firstPage = List.generate(100, (index) {
      final id = 200 - index;
      final minute = (59 - (index % 60)).toString().padLeft(2, '0');
      return <String, dynamic>{
        'id': id,
        'customer_phone': '+96395511${id.toString().padLeft(4, '0')}',
        'chat_peer_id': 'peer_$id',
        'status': 'open',
        'last_message_ts': '2026-03-18T10:$minute:00Z',
        'cursor_ts': '2026-03-18T10:$minute:00Z',
        'unread_by_operator': false,
      };
    });
    final mock = MockClient((req) async {
      requests.add(req.url);
      final beforeId = req.url.queryParameters['before_id'];
      if (beforeId == null) {
        return http.Response(
          jsonEncode(<String, dynamic>{'sessions': firstPage}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      expect(beforeId, '101');
      expect(
        req.url.queryParameters['before_ts'],
        startsWith('2026-03-18T10:20:00'),
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'sessions': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 100,
              'customer_phone': '+963955110100',
              'chat_peer_id': 'peer_100',
              'status': 'open',
              'last_message_ts': '2026-03-18T10:19:00Z',
              'cursor_ts': '2026-03-18T10:19:00Z',
              'unread_by_operator': false,
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    await tester.scrollUntilVisible(
      find.text('Load more'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(find.text('+963955110100'), findsOneWidget);
  });

  testWidgets('OfficialServiceInboxPage close session updates status',
      (tester) async {
    var closeCalls = 0;
    final closeHeaders = <Map<String, String>>[];
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/service_inbox' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'sessions': [
              {
                'id': 1,
                'customer_phone': '+963955112233',
                'chat_peer_id': 'peer_1',
                'status': 'open',
                'last_message_ts': '2026-03-06T09:15:00Z',
                'unread_by_operator': false,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/admin/official_accounts/acc_1/service_inbox/1/close' &&
          req.method == 'POST') {
        closeCalls += 1;
        closeHeaders.add(req.headers);
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(find.byTooltip('Close session'), findsOneWidget);

    await tester.tap(find.byTooltip('Close session'));
    await tester.pumpAndSettle();

    expect(closeCalls, 1);
    expect(closeHeaders, hasLength(1));
    final closeIdempotency = closeHeaders.single['Idempotency-Key'] ??
        closeHeaders.single['idempotency-key'];
    expect(closeIdempotency, isNotNull);
    expect(closeIdempotency!, startsWith('official-service-close-'));
    expect(find.byTooltip('Close session'), findsNothing);
    expect(find.textContaining('Closed'), findsWidgets);
  });

  testWidgets('OfficialServiceInboxPage send template message posts payload',
      (tester) async {
    final templateBodies = <Map<String, dynamic>>[];
    final templateHeaders = <Map<String, String>>[];
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/service_inbox' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'sessions': [
              {
                'id': 1,
                'customer_phone': '+963955112233',
                'chat_peer_id': 'peer_1',
                'status': 'open',
                'last_message_ts': '2026-03-06T09:15:00Z',
                'unread_by_operator': false,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path ==
              '/admin/official_accounts/acc_1/service_inbox/1/template_messages' &&
          req.method == 'POST') {
        templateBodies
            .add((jsonDecode(req.body) as Map).cast<String, dynamic>());
        templateHeaders.add(req.headers);
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    await tester.tap(find.byTooltip('Send service message'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Promo');
    await tester.enterText(
      find.widgetWithText(TextField, 'Message body'),
      'Your order is ready.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    expect(templateBodies, hasLength(1));
    expect(templateHeaders, hasLength(1));
    expect(templateBodies.single['title'], 'Promo');
    expect(templateBodies.single['body'], 'Your order is ready.');
    final idempotency = templateHeaders.single['Idempotency-Key'] ??
        templateHeaders.single['idempotency-key'];
    expect(idempotency, isNotNull);
    expect(idempotency!, startsWith('official-service-'));
    expect(find.text('Service message sent.'), findsOneWidget);
  });

  testWidgets(
      'OfficialServiceInboxPage send template message reauths on critical session failure',
      (tester) async {
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/admin/official_accounts/acc_1/service_inbox' &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'sessions': [
              {
                'id': 1,
                'customer_phone': '+963955112233',
                'chat_peer_id': 'peer_1',
                'status': 'open',
                'last_message_ts': '2026-03-06T09:15:00Z',
                'unread_by_operator': false,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path ==
              '/admin/official_accounts/acc_1/service_inbox/1/template_messages' &&
          req.method == 'POST') {
        return http.Response(
          '{"detail":"auth session required"}',
          401,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        OfficialServiceInboxPage(
          baseUrl: 'https://example.test',
          accountId: 'acc_1',
          httpClient: mock,
          privilegeSnapshotOverride: _officialPrivilegeSnapshot,
        ),
      ),
    );
    await _pumpForDataLoad(tester);

    await tester.tap(find.byTooltip('Send service message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Promo');
    await tester.enterText(
      find.widgetWithText(TextField, 'Message body'),
      'Your order is ready.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pump();
    await _pumpForReauth(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });
}

class _RecordingSharePlatform extends SharePlatform
    with MockPlatformInterfaceMixin {
  final List<_RecordedShareXFilesCall> shareXFilesInvocations =
      <_RecordedShareXFilesCall>[];

  @override
  Future<ShareResult> share(
    String text, {
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    return const ShareResult(
      'dev.fluttercommunity.plus/share/success',
      ShareResultStatus.success,
    );
  }

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    shareXFilesInvocations.add(
      _RecordedShareXFilesCall(
        files: files,
        subject: subject,
        text: text,
        fileNameOverrides: fileNameOverrides,
      ),
    );
    return const ShareResult(
      'dev.fluttercommunity.plus/share/success',
      ShareResultStatus.success,
    );
  }
}

class _RecordedShareXFilesCall {
  final List<XFile> files;
  final String? subject;
  final String? text;
  final List<String>? fileNameOverrides;

  const _RecordedShareXFilesCall({
    required this.files,
    required this.subject,
    required this.text,
    required this.fileNameOverrides,
  });
}

class _RecordingPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String applicationDocumentsPath;
  int applicationDocumentsPathCalls = 0;
  int downloadsPathCalls = 0;

  _RecordingPathProviderPlatform({
    required this.applicationDocumentsPath,
  });

  @override
  Future<String?> getApplicationDocumentsPath() async {
    applicationDocumentsPathCalls += 1;
    return applicationDocumentsPath;
  }

  @override
  Future<String?> getDownloadsPath() async {
    downloadsPathCalls += 1;
    return null;
  }
}
