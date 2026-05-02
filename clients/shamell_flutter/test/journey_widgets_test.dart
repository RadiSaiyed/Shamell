import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/l10n.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('JourneyPage shows EN headings', (tester) async {
    final lEn = L10n(const Locale('en'));
    expect(lEn.journeyTitle, 'My journey');
    expect(lEn.profileTitle, 'Profile');
    expect(lEn.rolesOverviewTitle, 'Roles overview');
  });

  testWidgets('JourneyPage shows AR headings', (tester) async {
    final lAr = L10n(const Locale('ar'));
    expect(lAr.journeyTitle, 'رحلتي');
    expect(lAr.profileTitle, 'الملف الشخصي');
    expect(lAr.rolesOverviewTitle, 'نظرة عامة على الأدوار');
  });

  testWidgets('MobilityHistoryPage shows filter and empty state in EN',
      (tester) async {
    final lEn = L10n(const Locale('en'));
    expect(lEn.mobilityHistoryTitle, 'Mobility history');
    expect(lEn.filterLabel, 'Filter');
    expect(lEn.statusAll, 'all');
    expect(lEn.statusCompleted, 'completed');
    expect(lEn.statusCanceled, 'canceled');
    expect(lEn.noMobilityHistory, 'No mobility history yet');
  });

  testWidgets('MobilityHistoryPage shows filter and empty state in AR',
      (tester) async {
    final lAr = L10n(const Locale('ar'));
    expect(lAr.mobilityHistoryTitle, 'سجل الحركة');
    expect(lAr.filterLabel, 'تصفية');
    expect(lAr.statusAll, 'الكل');
    expect(lAr.statusCompleted, 'مكتملة');
    expect(lAr.statusCanceled, 'ملغاة');
    expect(lAr.noMobilityHistory, 'لا توجد رحلات بعد');
  });
}
