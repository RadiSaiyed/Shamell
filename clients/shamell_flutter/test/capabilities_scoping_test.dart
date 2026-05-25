import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
            return null;
          case 'read':
            if (throwOnSecureRead) {
              throw PlatformException(code: 'secure-read-failed');
            }
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
  });

  test('Capabilities are scoped per base URL and ignore legacy global keys',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Legacy global key (must be ignored by scoped reader).
      ShamellCapabilities.kOfficialAccounts: true,
      // Scoped key for a specific origin.
      '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com': false,
    });

    final caps = await ShamellCapabilities.loadForBaseUrl(
      'https://api.example.com',
      sp: await SharedPreferences.getInstance(),
    );
    expect(caps.officialAccounts, isFalse);
  });

  test('loadForBaseUrl reads scoped capability values from secure storage',
      () async {
    secStore[
            '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com'] =
        '1';
    secStore['${ShamellCapabilities.kCoach}@https://api.example.com'] = '1';
    secStore['${ShamellCapabilities.kChannels}@https://api.example.com'] = '1';
    secStore['${ShamellCapabilities.kPaymentsSonic}@https://api.example.com'] =
        '1';
    secStore[
            '${ShamellCapabilities.kPaymentsCashVouchers}@https://api.example.com'] =
        '1';
    secStore['${ShamellCapabilities.kPaymentsBills}@https://api.example.com'] =
        '1';
    secStore[
            '${ShamellCapabilities.kPaymentsSavings}@https://api.example.com'] =
        '1';

    final caps = await ShamellCapabilities.loadForBaseUrl(
      'https://api.example.com',
      sp: await SharedPreferences.getInstance(),
    );
    expect(caps.coach, isTrue);
    expect(caps.officialAccounts, isTrue);
    expect(caps.channels, isFalse);
    expect(caps.paymentsSonic, isFalse);
    expect(caps.paymentsCashVouchers, isFalse);
    expect(caps.paymentsBills, isFalse);
    expect(caps.paymentsSavings, isFalse);
  });

  test('loadGlobal reads secure values and still forces channels off',
      () async {
    secStore[ShamellCapabilities.kOfficialAccounts] = '1';
    secStore[ShamellCapabilities.kChannels] = '1';

    final caps = await ShamellCapabilities.loadGlobal(
      sp: await SharedPreferences.getInstance(),
    );
    expect(caps.officialAccounts, isTrue);
    expect(caps.channels, isFalse);
  });

  test(
      'loadForBaseUrl ignores legacy SharedPreferences values by default on mobile',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com': true,
    });

    final caps = await ShamellCapabilities.loadForBaseUrl(
      'https://api.example.com',
      sp: await SharedPreferences.getInstance(),
    );

    expect(caps.officialAccounts, isFalse);
  });

  test(
      'loadForBaseUrl allows legacy SharedPreferences fallback when secure reads fail',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com': true,
    });
    throwOnSecureRead = true;

    final caps = await ShamellCapabilities.loadForBaseUrl(
      'https://api.example.com',
      sp: await SharedPreferences.getInstance(),
    );

    expect(caps.officialAccounts, isTrue);
  });

  test('persistForBaseUrl writes only scoped secure keys', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final sp = await SharedPreferences.getInstance();

    const caps = ShamellCapabilities(
      coach: true,
      chat: true,
      payments: false,
      friends: true,
      moments: false,
      officialAccounts: true,
      channels: true,
      serviceNotifications: false,
      paymentsPhoneTargets: false,
    );
    await caps.persistForBaseUrl(sp, 'https://api.example.com');

    expect(
      sp.getBool(
        '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com',
      ),
      isNull,
    );
    expect(
      secStore['${ShamellCapabilities.kCoach}@https://api.example.com'],
      '1',
    );
    expect(
      secStore[
          '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com'],
      '1',
    );
    expect(
      secStore['${ShamellCapabilities.kChannels}@https://api.example.com'],
      '0',
    );
    expect(
      secStore['${ShamellCapabilities.kPayments}@https://api.example.com'],
      '0',
    );
    expect(
      secStore['${ShamellCapabilities.kPaymentsSonic}@https://api.example.com'],
      '0',
    );
    expect(
      secStore[
          '${ShamellCapabilities.kPaymentsCashVouchers}@https://api.example.com'],
      '0',
    );
    expect(
      secStore['${ShamellCapabilities.kPaymentsBills}@https://api.example.com'],
      '0',
    );
    expect(
      secStore[
          '${ShamellCapabilities.kPaymentsSavings}@https://api.example.com'],
      '0',
    );
    expect(sp.getBool(ShamellCapabilities.kOfficialAccounts), isNull);
  });

  test('invalid scoped base does not read canonical capability keys', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com': true,
    });

    final caps = await ShamellCapabilities.loadForBaseUrl(
      'https://user:pass@api.example.com/app',
      sp: await SharedPreferences.getInstance(),
    );

    expect(caps.officialAccounts, isFalse);
  });

  test('persistForBaseUrl with invalid base avoids canonical scope keys',
      () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final sp = await SharedPreferences.getInstance();

    const caps = ShamellCapabilities(
      coach: true,
      chat: true,
      payments: true,
      friends: false,
      moments: false,
      officialAccounts: true,
      channels: false,
      serviceNotifications: false,
      paymentsPhoneTargets: false,
    );

    await caps.persistForBaseUrl(sp, 'https://user:pass@api.example.com/app');

    expect(
      secStore['${ShamellCapabilities.kCoach}@unknown'],
      '1',
    );
    expect(
      secStore[
          '${ShamellCapabilities.kOfficialAccounts}@https://api.example.com'],
      isNull,
    );
    expect(secStore['${ShamellCapabilities.kOfficialAccounts}@unknown'], '1');
  });

  test('clearPersistedState removes scoped and legacy capability keys',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ShamellCapabilities.kCoach: true,
      ShamellCapabilities.kOfficialAccounts: true,
      '${ShamellCapabilities.kFriends}@https://api.example.com': true,
    });
    secStore[ShamellCapabilities.kCoach] = '1';
    secStore[ShamellCapabilities.kPayments] = '1';
    secStore[ShamellCapabilities.kPaymentsSonic] = '1';
    secStore[ShamellCapabilities.kPaymentsBills] = '1';
    secStore[ShamellCapabilities.kPaymentsSavings] = '1';
    secStore[
            '${ShamellCapabilities.kServiceNotifications}@https://api.example.com'] =
        '1';
    secStore[
            '${ShamellCapabilities.kPaymentsCashVouchers}@https://api.example.com'] =
        '1';

    final sp = await SharedPreferences.getInstance();
    await ShamellCapabilities.clearPersistedState(sp: sp);

    expect(sp.getBool(ShamellCapabilities.kCoach), isNull);
    expect(secStore.containsKey(ShamellCapabilities.kCoach), isFalse);
    expect(sp.getBool(ShamellCapabilities.kOfficialAccounts), isNull);
    expect(
      sp.getBool('${ShamellCapabilities.kFriends}@https://api.example.com'),
      isNull,
    );
    expect(secStore.containsKey(ShamellCapabilities.kPayments), isFalse);
    expect(secStore.containsKey(ShamellCapabilities.kPaymentsSonic), isFalse);
    expect(secStore.containsKey(ShamellCapabilities.kPaymentsBills), isFalse);
    expect(secStore.containsKey(ShamellCapabilities.kPaymentsSavings), isFalse);
    expect(
      secStore.containsKey(
        '${ShamellCapabilities.kServiceNotifications}@https://api.example.com',
      ),
      isFalse,
    );
    expect(
      secStore.containsKey(
        '${ShamellCapabilities.kPaymentsCashVouchers}@https://api.example.com',
      ),
      isFalse,
    );
  });
}
