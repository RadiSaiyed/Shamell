import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/taxi/taxi_history.dart';
import 'package:shamell_flutter/core/food_orders.dart';
import 'package:shamell_flutter/main.dart';

void main() {
  setUp(() async {
    // Use in-memory SharedPreferences for widgets that touch it.
    SharedPreferences.setMockInitialValues(const <String, Object?>{});
  });

  testWidgets('BusPage shows EN and AR actions', (tester) async {
    // EN
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
        home: const BusPage('https://example.com'),
      ),
    );

    expect(find.text('Bus'), findsOneWidget);
    expect(find.text('Open Booking'), findsOneWidget);
    expect(find.text('Operator Console'), findsOneWidget);

    // AR
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
          child: BusPage('https://example.com'),
        ),
      ),
    );

    expect(find.text('الحافلات'), findsOneWidget);
    expect(find.text('فتح صفحة الحجز'), findsOneWidget);
    expect(find.text('وحدة تشغيل الحافلات'), findsOneWidget);
  });

  testWidgets('StaysPage shows key sections in EN and AR', (tester) async {
    // EN
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
        home: const StaysPage('https://example.com'),
      ),
    );

    expect(find.text('Stays'), findsOneWidget);
    expect(find.text('Browse by property type'), findsOneWidget);
    expect(find.text('Search stays'), findsOneWidget);
    expect(find.text('Available listings'), findsOneWidget);
    expect(find.text('Book stay'), findsOneWidget);

    // AR
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
          child: StaysPage('https://example.com'),
        ),
      ),
    );

    expect(find.text('الإقامات'), findsOneWidget);
    expect(find.text('تصفح حسب نوع العقار'), findsOneWidget);
    expect(find.text('البحث عن إقامة'), findsOneWidget);
    expect(find.text('العروض المتاحة'), findsOneWidget);
    expect(find.text('حجز الإقامة'), findsOneWidget);
  });

  testWidgets('TaxiHistoryPage shows headings in EN and AR', (tester) async {
    // EN
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
        home: const TaxiHistoryPage('https://example.com'),
      ),
    );

    expect(find.text('Taxi Rides'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Rides'), findsOneWidget);

    // AR
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
          child: TaxiHistoryPage('https://example.com'),
        ),
      ),
    );

    expect(find.text('رحلات التاكسي'), findsOneWidget);
    expect(find.text('تصفية'), findsOneWidget);
    expect(find.text('الرحلات'), findsOneWidget);
  });

  testWidgets('FoodOrderDetailPage app bar uses EN and AR titles', (tester) async {
    // EN
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
        home: const FoodOrderDetailPage('https://example.com', '123'),
      ),
    );

    expect(find.text('Food orders 123'), findsOneWidget);

    // AR
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
          child: FoodOrderDetailPage('https://example.com', '123'),
        ),
      ),
    );

    expect(find.textContaining('طلبات الطعام'), findsOneWidget);
  });

  testWidgets('RealEstatePage shows key sections in EN and AR', (tester) async {
    // EN
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
        home: const RealEstatePage('https://example.com'),
      ),
    );

    expect(find.text('RealEstate'), findsOneWidget);
    expect(find.text('Search properties'), findsOneWidget);
    expect(find.text('Reserve or inquire'), findsOneWidget);

    // AR
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
          child: RealEstatePage('https://example.com'),
        ),
      ),
    );

    expect(find.text('العقارات'), findsOneWidget);
    expect(find.text('البحث عن عقارات'), findsOneWidget);
    expect(find.text('حجز / استفسار'), findsOneWidget);
  });

  testWidgets('FreightPage shows EN and AR titles', (tester) async {
    // EN
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
        home: const FreightPage('https://example.com'),
      ),
    );

    expect(find.text('Freight'), findsOneWidget);

    // AR
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
          child: FreightPage('https://example.com'),
        ),
      ),
    );

    expect(find.text('الشحن'), findsOneWidget);
  });

  testWidgets('CarmarketPage shows EN and AR titles', (tester) async {
    // EN
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
        home: const CarmarketPage('https://example.com'),
      ),
    );

    expect(find.text('Carmarket'), findsOneWidget);

    // AR
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
          child: CarmarketPage('https://example.com'),
        ),
      ),
    );

    expect(find.text('سوق السيارات'), findsOneWidget);
  });

  testWidgets('CarrentalPage shows EN and AR titles', (tester) async {
    // EN
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
        home: const CarrentalPage('https://example.com'),
      ),
    );

    expect(find.text('Carrental'), findsOneWidget);

    // AR
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
          child: CarrentalPage('https://example.com'),
        ),
      ),
    );

    expect(find.text('تأجير السيارات'), findsOneWidget);
  });

  testWidgets('BuildingMaterialsPage shows EN and AR titles', (tester) async {
    // EN
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
        home: const BuildingMaterialsPage('https://example.com'),
      ),
    );

    expect(find.text('Building Materials'), findsOneWidget);

    // AR
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
          child: BuildingMaterialsPage('https://example.com'),
        ),
      ),
    );

    expect(find.text('مواد البناء'), findsOneWidget);
  });
}
