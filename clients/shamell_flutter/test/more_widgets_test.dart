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

  testWidgets('ServiceAccounts subtitle shows EN and AR', (tester) async {
    final lEn = L10n(const Locale('en'));
    final lAr = L10n(const Locale('ar'));
    expect(lEn.mirsaalContactsServiceAccountsSubtitle,
        'Shamell Bus, Pay and more');
    expect(lAr.mirsaalContactsServiceAccountsSubtitle,
        'Shamell Bus, Pay والمزيد');
  });
}
