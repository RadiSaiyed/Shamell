import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/shamell_my_qr_page.dart';

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
      'ShamellMyQrCodePage exposes only name and optional SyrChat ID identity copy',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const ShamellMyQrCodePage(
          payload: 'https://online.shamell.online/app/invite?token=abc',
          profileName: 'Ada',
          profileShamellId: 'ADA12345',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
    expect(find.textContaining('SyrChat ID: ADA12345'), findsOneWidget);
    expect(find.textContaining('+963'), findsNothing);
  });
}
