import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/journey_page.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/mobility_history.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object?>{});
  });

  testWidgets('JourneyPage shows EN headings', (tester) async {
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
        home: const JourneyPage('https://example.com', testMode: true),
      ),
    );

    expect(find.text('My journey'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Roles overview'), findsOneWidget);
  });

  testWidgets('JourneyPage shows AR headings', (tester) async {
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
          child: JourneyPage('https://example.com', testMode: true),
        ),
      ),
    );

    expect(find.text('رحلتي'), findsOneWidget);
    expect(find.text('الملف الشخصي'), findsOneWidget);
    expect(find.text('نظرة عامة على الأدوار'), findsOneWidget);
  });

  testWidgets('MobilityHistoryPage shows filter and empty state in EN', (tester) async {
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
        home: const MobilityHistoryPage('https://example.com', testMode: true),
      ),
    );

    expect(find.text('Mobility history'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('all'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('canceled'), findsOneWidget);
    expect(find.text('No mobility history yet'), findsOneWidget);
  });

  testWidgets('MobilityHistoryPage shows filter and empty state in AR', (tester) async {
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
          child: MobilityHistoryPage('https://example.com', testMode: true),
        ),
      ),
    );

    expect(find.text('سجل الحركة'), findsOneWidget);
    expect(find.text('تصفية'), findsOneWidget);
    expect(find.text('الكل'), findsOneWidget);
    expect(find.text('مكتملة'), findsOneWidget);
    expect(find.text('ملغاة'), findsOneWidget);
    expect(find.text('لا توجد رحلات بعد'), findsOneWidget);
  });
}

