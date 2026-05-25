import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/l10n.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('Core headings show in EN', (tester) async {
    final lEn = L10n(const Locale('en'));
    expect(lEn.journeyTitle, 'My activity');
    expect(lEn.profileTitle, 'Profile');
  });

  testWidgets('Core headings show in AR', (tester) async {
    final lAr = L10n(const Locale('ar'));
    expect(lAr.journeyTitle, 'نشاطي');
    expect(lAr.profileTitle, 'الملف الشخصي');
  });

  testWidgets('Activity filter labels show in EN', (tester) async {
    final lEn = L10n(const Locale('en'));
    expect(lEn.mobilityHistoryTitle, 'Activity history');
    expect(lEn.filterLabel, 'Filter');
    expect(lEn.statusAll, 'all');
    expect(lEn.statusCompleted, 'completed');
    expect(lEn.statusCanceled, 'canceled');
    expect(lEn.noMobilityHistory, 'No activity yet');
  });

  testWidgets('Activity filter labels show in AR', (tester) async {
    final lAr = L10n(const Locale('ar'));
    expect(lAr.mobilityHistoryTitle, 'سجل النشاط');
    expect(lAr.filterLabel, 'تصفية');
    expect(lAr.statusAll, 'الكل');
    expect(lAr.statusCompleted, 'مكتملة');
    expect(lAr.statusCanceled, 'ملغاة');
    expect(lAr.noMobilityHistory, 'لا يوجد نشاط بعد');
  });
}
