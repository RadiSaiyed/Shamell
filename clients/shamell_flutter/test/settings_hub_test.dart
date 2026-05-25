import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/shamell_settings_hub_page.dart';

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

void main() {
  testWidgets(
      'ShamellSettingsHubPage can hide account security when a separate security surface already exists',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsHubPage(
          baseUrl: 'https://api.example.com',
          deviceId: 'device-1',
          includeAccountSecurity: false,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Account Security'), findsNothing);
    expect(find.text('New Message Notification'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('About SyrChat'), findsOneWidget);
  });
}
