import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/mini_programs_review_page.dart';

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

void _configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpForDataLoad(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
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

  testWidgets('MiniProgramsReviewPage exposes registry manifest and approval',
      (tester) async {
    _configureLargeViewport(tester);
    const baseUrl = 'https://example.test';
    final patchBodies = <Map<String, dynamic>>[];
    var approved = false;

    Map<String, Object?> program() => <String, Object?>{
          'id': 'market_rewards',
          'app_id': 'market_rewards',
          'runtime_app_id': 'market_rewards_runtime',
          'title_en': 'Market Rewards',
          'description_en': 'Rewards and coupons for daily shopping.',
          'category_en': 'Shopping',
          'owner_name': 'Market Team',
          'owner_contact': 'ops@example.test',
          'status': approved ? 'published' : 'pending_review',
          'review_status': approved ? 'approved' : 'pending',
          'enabled': approved,
          'official': false,
          'beta': true,
          'rating': 4.2,
          'rating_count': 12,
          'usage_score': 27,
          'moments_shares': 5,
          'moments_shares_30d': 3,
          'latest_version': '1.2.0',
          'latest_version_review_status': approved ? 'approved' : 'pending',
          'released_version': approved ? '1.2.0' : null,
          'released_bundle_url':
              approved ? 'https://cdn.example.test/market_rewards.js' : null,
          'released_changelog_en': approved ? 'Coupons release.' : null,
          'scopes': <String>['wallet.pay', 'moments.share'],
          'actions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'open_rewards',
              'label_en': 'Open rewards',
              'kind': 'open_mod',
              'mod_id': 'market_rewards',
            },
            <String, Object?>{
              'id': 'support',
              'label_en': 'Support',
              'kind': 'open_url',
              'url': 'https://example.test/support',
            },
          ],
          'created_at': '2026-05-01T10:00:00.000Z',
          'updated_at': '2026-05-01T11:00:00.000Z',
        };

    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/mini_programs') {
        expect(request.url.queryParameters['include_disabled'], 'true');
        expect(request.url.queryParameters['limit'], '200');
        return http.Response(
          jsonEncode(<String, Object?>{
            'programs': <Object?>[program()],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.method == 'PATCH' &&
          request.url.path == '/admin/mini_programs/market_rewards') {
        final decoded = jsonDecode(request.body);
        expect(decoded, isA<Map>());
        patchBodies.add((decoded as Map).cast<String, dynamic>());
        approved = true;
        return http.Response(
          jsonEncode(program()),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response(
        'not found: ${request.method} ${request.url}',
        404,
      );
    });

    await tester.pumpWidget(
      _testApp(
        MiniProgramsReviewPage(baseUrl: baseUrl, httpClient: client),
      ),
    );
    await _pumpForDataLoad(tester);

    expect(find.text('Mini‑program review center'), findsOneWidget);
    expect(find.text('Review queue'), findsOneWidget);
    expect(find.text('Market Rewards'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('wallet.pay'), findsOneWidget);
    expect(find.text('Open rewards'), findsOneWidget);
    expect(find.text('latest 1.2.0 · pending'), findsOneWidget);

    await tester.tap(find.text('Market Rewards').first);
    await tester.pumpAndSettle();

    expect(find.text('Registry manifest'), findsOneWidget);
    expect(find.text('runtime_app_id'), findsOneWidget);
    expect(find.text('market_rewards_runtime'), findsOneWidget);
    expect(find.text('open_rewards'), findsOneWidget);
    expect(find.text('open_mod · market_rewards'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').first);
    await _pumpForDataLoad(tester);

    expect(patchBodies, hasLength(1));
    expect(
      patchBodies.single,
      <String, Object?>{
        'status': 'published',
        'review_status': 'approved',
        'enabled': true,
      },
    );
    expect(find.text('Review status updated.'), findsOneWidget);
  });
}
