import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/l10n.dart';

void main() {
  setUp(() async {
    // Use in-memory SharedPreferences for widgets that touch it.
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('BusPage shows EN and AR actions', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.homeBus, 'Bus');
    expect(lAr.homeBus, 'الحافلات');
  });

  testWidgets('StaysPage shows key sections in EN and AR', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.homeStays, 'Hotels & Stays');
    expect(lAr.homeStays, 'الفنادق والإقامات');
    expect(lEn.rsBrowseByPropertyType, 'Browse by property type');
    expect(lAr.rsBrowseByPropertyType, 'تصفح حسب نوع العقار');
  });

  testWidgets('TaxiHistoryPage shows headings in EN and AR', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.filterLabel, 'Filter');
    expect(lAr.filterLabel, 'تصفية');
    expect(lEn.homeTaxi, 'Taxi');
    expect(lAr.homeTaxi, 'تاكسي');
  });

  testWidgets('FoodOrderDetailPage app bar uses EN and AR titles',
      (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.foodOrdersTitle, 'Food orders');
    expect(lAr.foodOrdersTitle, 'طلبات الطعام');
  });

  testWidgets('RealEstatePage shows key sections in EN and AR', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.realEstateTitle, 'RealEstate');
    expect(lAr.realEstateTitle, 'العقارات');
  });

  testWidgets('FreightPage shows EN and AR titles', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.freightTitle, 'Courier');
    expect(lAr.freightTitle, 'التوصيل');
  });

  testWidgets('CarmarketPage shows EN and AR titles', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.carmarketTitle, 'Carrental & Carmarket');
    expect(lAr.carmarketTitle, 'تأجير وبيع السيارات');
  });

  testWidgets('CarrentalPage shows EN and AR titles', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.carrentalTitle, 'Carrental & Carmarket');
    expect(lAr.carrentalTitle, 'تأجير وبيع السيارات');
  });

  testWidgets('BuildingMaterialsPage shows EN and AR titles', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.homeBuildingMaterials, 'Building Materials');
    expect(lAr.homeBuildingMaterials, 'مواد البناء');
  });
}
