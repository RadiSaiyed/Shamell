import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/main.dart' show ShamellSettingsPage;

Widget _testApp(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  testWidgets(
      'ShamellSettingsPage exposes only real logout actions without switch-account duplicate',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        ShamellSettingsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_1',
          deviceId: 'device_1',
          profileShamellId: 'ADA12345',
          showDev: false,
          hasDefaultOfficialAccount: false,
          onLogout: () async {},
          onLogoutForgetDevice: () async {},
          pushPage: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Switch Account'), findsNothing);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Logout & forget this device'), findsOneWidget);
  });

  testWidgets(
      'ShamellSettingsPage keeps official console but hides duplicate owners entry',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        ShamellSettingsPage(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_1',
          deviceId: 'device_1',
          profileShamellId: 'ADA12345',
          showDev: false,
          hasDefaultOfficialAccount: true,
          onLogout: () async {},
          onLogoutForgetDevice: () async {},
          pushPage: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Official account console'), findsOneWidget);
    expect(find.text('Official owners & access'), findsNothing);
  });
}
