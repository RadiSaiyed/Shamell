import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/l10n.dart';

void main() {
  setUp(() async {
    // Use in-memory SharedPreferences for widgets that touch it.
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('Service label shows EN and AR', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.homeBus, 'Service');
    expect(lAr.homeBus, 'الخدمة');
  });

  testWidgets('ServiceAccounts subtitle shows EN and AR', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.shamellContactsServiceAccountsSubtitle,
        'SyrChat services and more');
    expect(lAr.shamellContactsServiceAccountsSubtitle, 'خدمات SyrChat والمزيد');
  });
}
