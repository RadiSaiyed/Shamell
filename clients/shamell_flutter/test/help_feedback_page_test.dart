import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/main.dart' show ShamellHelpFeedbackPage;

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
  testWidgets('ShamellHelpFeedbackPage inlines help topics without extra hop',
      (tester) async {
    await tester.pumpWidget(
      _testApp(const ShamellHelpFeedbackPage()),
    );

    await tester.pumpAndSettle();

    expect(find.text('Help center'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
  });
}
