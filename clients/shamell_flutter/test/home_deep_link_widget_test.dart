import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/main.dart';

class _TestNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount += 1;
    super.didPush(route, previousRoute);
  }
}

Widget _testApp({
  required HomePage home,
  required NavigatorObserver observer,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    navigatorObservers: <NavigatorObserver>[observer],
    home: home,
  );
}

HomePage _home({
  ShamellCapabilities? initialCapabilities,
}) {
  return HomePage(
    lockedMode: AppMode.user,
    initialTabIndex: 1,
    runStartupTasks: false,
    initialCapabilities: initialCapabilities,
  );
}

ShamellCapabilities _caps({
  required bool officialAccounts,
  required bool moments,
  bool coach = false,
}) {
  return ShamellCapabilities(
    coach: coach,
    chat: true,
    payments: true,
    friends: false,
    moments: moments,
    officialAccounts: officialAccounts,
    channels: false,
    serviceNotifications: false,
    paymentsPhoneTargets: false,
  );
}

Future<void> _invokeUri(WidgetTester tester, String rawUri) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugHandleUri(Uri.parse(rawUri));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _drainBackgroundSessionTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
}

Future<void> _invokeUriAsync(WidgetTester tester, String rawUri) async {
  final dynamic state = tester.state(find.byType(HomePage));
  unawaited(state.debugHandleUri(Uri.parse(rawUri)));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeScanResult(WidgetTester tester, String raw) async {
  final dynamic state = tester.state(find.byType(HomePage));
  unawaited(state.debugHandleScanResult(raw));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    debugClearVolatileSessionForTests();
  });

  test(
      'inbound uri handling only dispatches allowlisted shamell links after normalization',
      () {
    final oversizedToken = 'a' * 5000;

    expect(
      normalizeInboundShamellUri(
        Uri.parse('https://online.shamell.online/app/official/shop_123'),
      ).toString(),
      'shamell://official/shop_123',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse(
          'https://online.shamell.online/app/device_login#token=abc123&label=Demo%20Phone',
        ),
      ).toString(),
      'shamell://device_login?token=abc123&label=Demo+Phone',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse(
          'https://online.shamell.online/app/device_login?token=queryToken#token=fragmentToken',
        ),
      ).toString(),
      'shamell://device_login?token=fragmentToken',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse(
            'https://online.shamell.online/app/device_login?token=queryToken'),
      ).toString(),
      'https://online.shamell.online/app/device_login?token=queryToken',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse(
          'https://online.shamell.online/app/invite#token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ).toString(),
      'shamell://invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse(
          'https://online.shamell.online/app/invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ).toString(),
      'https://online.shamell.online/app/invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse(
          'shamell://invite#token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ).toString(),
      'shamell://invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse('https://online.shamell.online/app/ride?ride_id=ride_123'),
      ).toString(),
      'shamell://ride?ride_id=ride_123',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse(
          'https://online.shamell.online/app/coach?from=Damascus&to=Aleppo&departure_date=2026-04-20&passengers=2',
        ),
      ).toString(),
      'shamell://coach?from=Damascus&to=Aleppo&departure_date=2026-04-20&passengers=2',
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse('https://online.shamell.online/app/miniapp/payments'),
      ).toString(),
      'shamell://mini_program/payments',
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('https://online.shamell.online/app/official/shop_123'),
      ),
      isTrue,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('https://online.shamell.online/app/miniapp/payments'),
      ),
      isTrue,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse(
            'https://online.shamell.online/app/device_login?token=queryToken'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse(
          'https://online.shamell.online/app/invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(Uri.parse('https://evil.test/x')),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('http://online.shamell.online/app/official/shop_123'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse(
            'https://user:pass@online.shamell.online/app/official/shop_123'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('https://online.shamell.online:444/app/official/shop_123'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('https://online.shamell.online/'),
      ),
      isFalse,
    );
    expect(
      normalizeInboundShamellUri(
        Uri.parse('https://online.shamell.online/app/group/g1'),
      ).toString(),
      'https://online.shamell.online/app/group/g1',
    );
    expect(shamellShouldHandleInboundUri(Uri.parse('shamell://group/g1')),
        isFalse);
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('https://online.shamell.online/app/group/g1'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('shamell://user:pass@official/shop_123'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('shamell://official:444/shop_123'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('shamell://official/shop_123#hidden'),
      ),
      isTrue,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse('shamell://invite?token=$oversizedToken'),
      ),
      isFalse,
    );
    expect(
      shamellShouldHandleInboundUri(
        Uri.parse(
          'https://online.shamell.online/app/invite?token=$oversizedToken',
        ),
      ),
      isFalse,
    );
  });

  test('android manifest inbound filters stay in sync with runtime allowlist',
      () async {
    final manifest =
        await File('android/app/src/main/AndroidManifest.xml').readAsString();
    final customHosts = RegExp(
      r'<data\s+android:scheme="shamell"\s+android:host="([^"]+)"\s*/>',
    ).allMatches(manifest).map((m) => m.group(1)!.trim().toLowerCase()).toSet();
    final httpsPrefixes = RegExp(
      r'<data\s+android:scheme="https"\s+android:host="([^"]+)"\s+android:pathPrefix="([^"]+)"\s*/>',
    ).allMatches(manifest).map((m) => (
          host: m.group(1)!.trim().toLowerCase(),
          pathPrefix: m.group(2)!.trim(),
        ));

    expect(customHosts, shamellSupportedCustomSchemeInboundHosts());
    expect(customHosts.contains('device_login'), isFalse);
    expect(customHosts.contains('invite'), isFalse);
    expect(customHosts.contains('friend'), isFalse);

    final expectedHttpsPrefixes = shamellSupportedInboundHosts()
        .map((host) => '${shamellInboundAppLinkPathPrefix()}/$host')
        .toSet();
    final actualHttpsPrefixes = httpsPrefixes
        .where((entry) => entry.host == shamellInboundAppLinkHost())
        .map((entry) => entry.pathPrefix)
        .toSet();

    expect(actualHttpsPrefixes, expectedHttpsPrefixes);
    expect(actualHttpsPrefixes.contains(shamellInboundAppLinkPathPrefix()),
        isFalse);
  });

  test('release builds reject sensitive custom-scheme inbound hosts', () {
    expect(
      shamellAllowsCustomSchemeInboundHost('invite', isReleaseMode: true),
      isFalse,
    );
    expect(
      shamellAllowsCustomSchemeInboundHost('device_login', isReleaseMode: true),
      isFalse,
    );
    expect(
      shamellAllowsCustomSchemeInboundHost('friend', isReleaseMode: true),
      isFalse,
    );
    expect(
      shamellAllowsCustomSchemeInboundHost('official', isReleaseMode: true),
      isFalse,
    );
    expect(
      shamellAllowsCustomSchemeInboundHost('chat', isReleaseMode: true),
      isFalse,
    );
    expect(
      shamellAllowsCustomSchemeInboundHost('invite', isReleaseMode: false),
      isTrue,
    );
  });

  testWidgets(
      'official deeplink shows unavailable snackbar and does not navigate when capability is off',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: false,
            moments: false,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(tester, 'shamell://official/shop_123');

    expect(find.text('This feature is not available on this server.'),
        findsOneWidget);
    expect(observer.pushCount, baselinePushCount);
  });

  testWidgets(
      'first-party https app link normalizes into official deeplink handling',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(
      tester,
      'https://online.shamell.online/app/official/shop_123',
    );

    expect(find.text('This feature is not available on this server.'),
        findsOneWidget);
    expect(observer.pushCount, baselinePushCount);
  });

  testWidgets('official deeplink opens official accounts surface when enabled',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: true,
            moments: false,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(tester, 'shamell://official/shop_123');

    expect(observer.pushCount, greaterThan(baselinePushCount));
    await _drainBackgroundSessionTimers(tester);
  });

  testWidgets('ride deeplink opens taxi mini program surface', (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: false,
            moments: false,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(
      tester,
      'https://online.shamell.online/app/ride?ride_id=ride_123',
    );
    await tester.pumpAndSettle();

    expect(find.text('Taxi mini program'), findsOneWidget);
    expect(find.textContaining('ride_123'), findsOneWidget);
    expect(observer.pushCount, greaterThan(baselinePushCount));
    await _drainBackgroundSessionTimers(tester);
  });

  testWidgets('coach deeplink opens coach mini program surface',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: false,
            moments: false,
            coach: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(
      tester,
      'https://online.shamell.online/app/coach?from=Damascus&to=Aleppo&departure_date=2026-04-20&passengers=2',
    );
    await tester.pumpAndSettle();

    expect(find.text('Coach bus'), findsOneWidget);
    expect(find.text('Damascus'), findsOneWidget);
    expect(find.text('Aleppo'), findsOneWidget);
    expect(find.text('2026-04-20'), findsOneWidget);
    expect(observer.pushCount, greaterThan(baselinePushCount));
    await _drainBackgroundSessionTimers(tester);
  });

  testWidgets('moduleapp coach shortcut opens coach mini program surface',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: false,
            moments: false,
            coach: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(
      tester,
      'https://online.shamell.online/app/moduleapp?id=coach',
    );
    await tester.pumpAndSettle();

    expect(find.text('Coach bus'), findsOneWidget);
    expect(observer.pushCount, greaterThan(baselinePushCount));
    await _drainBackgroundSessionTimers(tester);
  });

  testWidgets(
      'coach deeplink shows unavailable snackbar when capability is off',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(
      tester,
      'https://online.shamell.online/app/bus?from=Damascus&to=Aleppo',
    );

    expect(
        find.text('Coach bus is not enabled on this server.'), findsOneWidget);
    expect(observer.pushCount, baselinePushCount);
  });

  testWidgets(
      'moments deeplink shows unavailable snackbar and does not navigate when capability is off',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: false,
            moments: false,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(tester, 'shamell://moments?post_id=p42');

    expect(find.text('This feature is not available on this server.'),
        findsOneWidget);
    expect(observer.pushCount, baselinePushCount);
  });

  testWidgets('moments deeplink opens moments surface when enabled',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: false,
            moments: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    debugSetVolatileSessionTokenForBaseUrl(
      'https://api.shamell.online',
      'a' * 32,
    );
    await _invokeUri(tester, 'shamell://moments?post_id=p42&focus=comments');

    expect(observer.pushCount, greaterThan(baselinePushCount));
    await _drainBackgroundSessionTimers(tester);
  });

  testWidgets('first-party https app link normalizes into moments handling',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(
          initialCapabilities: _caps(
            officialAccounts: false,
            moments: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    debugSetVolatileSessionTokenForBaseUrl(
      'https://api.shamell.online',
      'a' * 32,
    );
    await _invokeUri(
      tester,
      'https://online.shamell.online/app/moments?post_id=p42&focus=comments',
    );

    expect(observer.pushCount, greaterThan(baselinePushCount));
    await _drainBackgroundSessionTimers(tester);
  });

  testWidgets(
      'scan result dispatches first-party https app link through shamell handler',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeScanResult(
      tester,
      'https://online.shamell.online/app/official/shop_123',
    );

    expect(find.text('This feature is not available on this server.'),
        findsOneWidget);
    expect(observer.pushCount, baselinePushCount);
  });

  testWidgets('scan invite requires explicit confirmation before redeem flow',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();

    await _invokeScanResult(
      tester,
      'shamell://invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.pump();

    expect(find.text('Contact invite'), findsOneWidget);
    expect(
        find.text('Add this contact using the invite link?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Contact invite'), findsNothing);
  });

  testWidgets(
      'app-link invite requires explicit confirmation before redeem flow when token is in fragment',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();

    await _invokeUriAsync(
      tester,
      'https://online.shamell.online/app/invite#token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(find.text('Contact invite'), findsOneWidget);
    expect(
        find.text('Add this contact using the invite link?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Contact invite'), findsNothing);
  });

  testWidgets('query-only hosted invite app link is ignored by inbound handler',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUriAsync(
      tester,
      'https://online.shamell.online/app/invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(find.text('Contact invite'), findsNothing);
    expect(find.text('Add this contact using the invite link?'), findsNothing);
    expect(observer.pushCount, baselinePushCount);
  });

  testWidgets('scan result does not auto-open arbitrary external https urls',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeScanResult(tester, 'https://evil.test/x');

    expect(find.text('Scan result'), findsOneWidget);
    expect(find.text('https://evil.test/x'), findsOneWidget);
    expect(observer.pushCount, baselinePushCount + 1);
  });

  testWidgets(
      'scan PAY payload tolerates malformed percent-encoding without crashing',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeScanResult(
      tester,
      'PAY|wallet=wallet_target|amount=%E0%A4%A',
    );

    expect(tester.takeException(), isNull);
    expect(observer.pushCount, baselinePushCount);
  });

  testWidgets('external https app link is ignored by inbound handler',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(tester, 'https://evil.test/x');

    expect(observer.pushCount, baselinePushCount);
    expect(find.text('This feature is not available on this server.'),
        findsNothing);
    expect(find.text('Scan result'), findsNothing);
  });

  testWidgets('unknown shamell host is ignored by inbound handler',
      (tester) async {
    final observer = _TestNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        observer: observer,
        home: _home(),
      ),
    );
    await tester.pump();
    final baselinePushCount = observer.pushCount;

    await _invokeUri(tester, 'shamell://group/g1');

    expect(observer.pushCount, baselinePushCount);
    expect(find.text('This feature is not available on this server.'),
        findsNothing);
    expect(find.text('Scan result'), findsNothing);
  });

}
