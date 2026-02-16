import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Capabilities are scoped per base URL and ignore legacy global keys',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Legacy global key (must be ignored by scoped reader).
      ShamellCapabilities.kOfficialAccounts: true,
      // Scoped key for a specific origin.
      '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com': false,
    });

    final sp = await SharedPreferences.getInstance();
    final caps = ShamellCapabilities.fromPrefsForBaseUrl(
      sp,
      'https://api.example.com',
    );
    expect(caps.officialAccounts, isFalse);
  });

  test('persistForBaseUrl writes only scoped keys', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final sp = await SharedPreferences.getInstance();

    const caps = ShamellCapabilities(
      chat: true,
      payments: false,
      bus: true,
      friends: true,
      moments: false,
      officialAccounts: true,
      channels: false,
      miniPrograms: false,
      serviceNotifications: false,
      subscriptions: false,
      paymentsPhoneTargets: false,
    );
    await caps.persistForBaseUrl(sp, 'https://api.example.com');

    expect(
      sp.getBool('${ShamellCapabilities.kOfficialAccounts}@https://api.example.com'),
      isTrue,
    );
    expect(
      sp.getBool('${ShamellCapabilities.kPayments}@https://api.example.com'),
      isFalse,
    );
    expect(sp.getBool(ShamellCapabilities.kOfficialAccounts), isNull);
  });
}

