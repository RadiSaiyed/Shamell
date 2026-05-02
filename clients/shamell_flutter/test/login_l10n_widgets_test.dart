import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/l10n.dart';

void main() {
  setUp(() async {
    // Ensure SharedPreferences works without real disk IO.
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('LoginPage shows EN labels', (tester) async {
    final lEn = L10n(const Locale('en'));
    expect(lEn.loginTitle, 'Sign in');
    expect(lEn.loginPhone, 'Phone (+963…)');
  });

  testWidgets('LoginPage shows AR labels', (tester) async {
    final lAr = L10n(const Locale('ar'));
    expect(lAr.loginTitle, 'تسجيل الدخول');
    expect(lAr.loginPhone, 'رقم الهاتف (+963…)');
  });
}
