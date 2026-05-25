import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/shamell_settings_about_page.dart';

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
  testWidgets('ShamellSettingsAboutPage shows static app-store update guidance',
      (tester) async {
    await tester.pumpWidget(_testApp(const ShamellSettingsAboutPage()));

    await tester.pumpAndSettle();

    expect(find.text('Check for updates'), findsNothing);
    expect(find.text('Updates'), findsOneWidget);
    expect(
      find.text('Updates are installed through your device app store.'),
      findsOneWidget,
    );
    expect(find.text('Terms of Service'), findsNothing);
    expect(find.text('Privacy Policy'), findsNothing);
    expect(find.text('Terms summary'), findsOneWidget);
    expect(find.text('Privacy summary'), findsOneWidget);
    expect(
      find.textContaining('Contact support for the official legal text.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
          'Contact support for the official policy or data-deletion requests.'),
      findsOneWidget,
    );

    final termsTile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Terms summary'));
    final privacyTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Privacy summary'),
    );
    expect(termsTile.onTap, isNull);
    expect(privacyTile.onTap, isNull);
  });
}
