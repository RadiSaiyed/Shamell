import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/main.dart';

void main() {
  setUp(() async {
    // Ensure SharedPreferences works without real disk IO.
    SharedPreferences.setMockInitialValues(const <String, Object?>{});
  });

  testWidgets('LoginPage shows EN labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const LoginPage(),
      ),
    );

    expect(find.text('Shamell'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Phone (+963…)'), findsOneWidget);
  });

  testWidgets('LoginPage shows AR labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: LoginPage(),
        ),
      ),
    );

    expect(find.text('شامل'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('رقم الهاتف (+963…)'), findsOneWidget);
  });
}
