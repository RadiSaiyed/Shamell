import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/main.dart';

Widget _testApp(HomePage home) {
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

ShamellCapabilities _caps({
  bool officialAccounts = false,
  bool serviceNotifications = false,
  bool friends = false,
}) {
  return ShamellCapabilities(
    chat: true,
    payments: true,
    friends: friends,
    moments: false,
    officialAccounts: officialAccounts,
    channels: false,
    serviceNotifications: serviceNotifications,
    paymentsPhoneTargets: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'HomePage legacy Me tab shows My pay code only once when wallet is available',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(
      strictUi: false,
      walletId: 'wallet_1',
    );
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(find.text('SyrChat Pay'), findsNothing);
    expect(find.text('My pay code'), findsOneWidget);
  });

  testWidgets(
      'HomePage strict Me tab does not expose duplicate SyrChat Pay entry',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(
      strictUi: true,
      walletId: 'wallet_1',
    );
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(find.text('SyrChat Pay'), findsOneWidget);
    expect(find.text('Cards & Offers'), findsNothing);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
  });

  testWidgets('HomePage legacy Me tab does not expose duplicate Friends entry',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          initialCapabilities: _caps(friends: true),
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(strictUi: false);
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(find.text('Manage your friends and organize close contacts'),
        findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
      'HomePage legacy Me tab does not expose duplicate Linked devices entry',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(strictUi: false);
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(find.text('Linked devices'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('HomePage legacy Me tab does not expose duplicate History entry',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(
      strictUi: false,
      walletId: 'wallet_1',
    );
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(find.text('My pay code'), findsOneWidget);
    expect(find.text('History'), findsNothing);
  });

  testWidgets(
      'HomePage legacy Me tab QR shortcut does not route to ProfilePage',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(strictUi: false);
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_2_outlined));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(ProfilePage), findsNothing);
  });

  testWidgets(
      'HomePage legacy Me tab does not expose duplicate Official admin entries',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          initialCapabilities: _caps(officialAccounts: true),
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(
      strictUi: false,
      hasDefaultOfficialAccount: true,
    );
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(find.text('Official account console'), findsNothing);
    expect(find.text('Official owners & access'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
      'HomePage legacy Me tab does not expose duplicate Service notifications entry',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          initialCapabilities: _caps(serviceNotifications: true),
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(
      strictUi: false,
      hasUnreadServiceNotifications: true,
    );
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(find.text('Service notifications'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
      'HomePage legacy Me tab settings tile opens ShamellSettingsPage instead of ops settings',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(strictUi: false);
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Account Security'), findsOneWidget);
    expect(find.text('New Message Notification'), findsOneWidget);
    expect(find.text('Base URL'), findsNothing);
  });

  testWidgets('HomePage legacy Me tab does not expose duplicate Call us entry',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    state.debugSeedLegacyMeTabState(strictUi: false);
    await tester.pump();

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Complaints'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Complaints'), findsOneWidget);
    expect(find.text('Call us'), findsNothing);
  });
}
