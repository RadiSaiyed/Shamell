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
    expect(lEn.loginBiometricSignIn, 'Sign in with biometrics');
    expect(
      lEn.loginTerms,
      'By signing in you agree to SyrChat terms and privacy policy. About shows in-app summaries only.',
    );
  });

  testWidgets('LoginPage shows AR labels', (tester) async {
    final lAr = L10n(const Locale('ar'));
    expect(lAr.loginTitle, 'تسجيل الدخول');
    expect(lAr.loginBiometricSignIn, 'تسجيل الدخول بالبصمة');
    expect(
      lAr.loginTerms,
      'بمتابعة تسجيل الدخول، فأنت توافق على شروط سرتشات وسياسة الخصوصية. صفحة "حول" تعرض ملخصات داخل التطبيق فقط.',
    );
  });
}
