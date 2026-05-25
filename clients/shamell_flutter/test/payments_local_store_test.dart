import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/payments/payments_local_store.dart';

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
              throw PlatformException(
                code: 'secure-read-failed',
                message: 'simulated secure storage read failure',
              );
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
    await clearPaymentsLocalData();
  });

  test(
      'legacy shared-preferences payments state is ignored when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pay_recents': <String>['wallet-1', 'wallet-2'],
      'bill_templates': <String>[
        '{"biller_code":"electricity","account":"123"}',
      ],
      'seen_reqs': <String>['req-1', 'req-2'],
    });

    expect(await loadPaymentRecents(), isEmpty);
    expect(await loadBillTemplateEntries(), isEmpty);
    expect(await loadSeenPaymentRequestIds(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('pay_recents'), isNull);
    expect(sp.getStringList('bill_templates'), isNull);
    expect(sp.getStringList('seen_reqs'), isNull);
  });

  test(
      'legacy shared-preferences payments state is allowed when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pay_recents': <String>['wallet-1', 'wallet-2'],
      'bill_templates': <String>[
        '{"biller_code":"electricity","account":"123"}',
      ],
      'seen_reqs': <String>['req-1', 'req-2'],
    });

    expect(await loadPaymentRecents(), <String>['wallet-1', 'wallet-2']);
    expect(
      await loadBillTemplateEntries(),
      <String>['{"biller_code":"electricity","account":"123"}'],
    );
    expect(await loadSeenPaymentRequestIds(), <String>['req-1', 'req-2']);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('pay_recents'), <String>['wallet-1', 'wallet-2']);
    expect(
      sp.getStringList('bill_templates'),
      <String>['{"biller_code":"electricity","account":"123"}'],
    );
    expect(sp.getStringList('seen_reqs'), <String>['req-1', 'req-2']);
  });

  test('payments local data is isolated per canonical api origin', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(await savePaymentRecents(<String>['wallet-1']), isTrue);
    expect(
      await saveBillTemplateEntries(<String>[
        '{"biller_code":"electricity","account":"111"}',
      ]),
      isTrue,
    );
    expect(await saveSeenPaymentRequestIds(<String>['req-1']), isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadPaymentRecents(), isEmpty);
    expect(await loadBillTemplateEntries(), isEmpty);
    expect(await loadSeenPaymentRequestIds(), isEmpty);

    expect(await savePaymentRecents(<String>['wallet-2']), isTrue);
    expect(
      await saveBillTemplateEntries(<String>[
        '{"biller_code":"water","account":"222"}',
      ]),
      isTrue,
    );
    expect(await saveSeenPaymentRequestIds(<String>['req-2']), isTrue);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadPaymentRecents(), <String>['wallet-1']);
    expect(
      await loadBillTemplateEntries(),
      <String>['{"biller_code":"electricity","account":"111"}'],
    );
    expect(await loadSeenPaymentRequestIds(), <String>['req-1']);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadPaymentRecents(), <String>['wallet-2']);
    expect(
      await loadBillTemplateEntries(),
      <String>['{"biller_code":"water","account":"222"}'],
    );
    expect(await loadSeenPaymentRequestIds(), <String>['req-2']);
  });

  test(
      'legacy global payments local data does not rebind into canonical api origin',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'pay_recents': <String>['wallet-1'],
      'bill_templates': <String>[
        '{"biller_code":"electricity","account":"123"}',
      ],
      'seen_reqs': <String>['req-1'],
    });

    expect(await loadPaymentRecents(), isEmpty);
    expect(await loadBillTemplateEntries(), isEmpty);
    expect(await loadSeenPaymentRequestIds(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('pay_recents'), isNull);
    expect(sp.getStringList('bill_templates'), isNull);
    expect(sp.getStringList('seen_reqs'), isNull);
  });

  test('payments recents and templates save, load, and clear securely',
      () async {
    expect(
      await savePaymentRecents(<String>['wallet-3', 'wallet-4']),
      isTrue,
    );
    expect(
      await saveBillTemplateEntries(<String>[
        '{"biller_code":"water","account":"ABC"}',
      ]),
      isTrue,
    );
    expect(
      await saveSeenPaymentRequestIds(<String>['req-3', 'req-4']),
      isTrue,
    );

    expect(await loadPaymentRecents(), <String>['wallet-3', 'wallet-4']);
    expect(
      await loadBillTemplateEntries(),
      <String>['{"biller_code":"water","account":"ABC"}'],
    );
    expect(await loadSeenPaymentRequestIds(), <String>['req-3', 'req-4']);

    await clearPaymentsLocalData();

    expect(await loadPaymentRecents(), isEmpty);
    expect(await loadBillTemplateEntries(), isEmpty);
    expect(await loadSeenPaymentRequestIds(), isEmpty);
  });

  test('clearPaymentsLocalData removes scoped values across all origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(await savePaymentRecents(<String>['wallet-1']), isTrue);
    expect(await saveSeenPaymentRequestIds(<String>['req-1']), isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await savePaymentRecents(<String>['wallet-2']), isTrue);
    expect(await saveSeenPaymentRequestIds(<String>['req-2']), isTrue);

    await clearPaymentsLocalData();

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadPaymentRecents(), isEmpty);
    expect(await loadSeenPaymentRequestIds(), isEmpty);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadPaymentRecents(), isEmpty);
    expect(await loadSeenPaymentRequestIds(), isEmpty);
  });

  test('payments local data honors explicit baseUrl override over global scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.two.example');

    expect(
      await savePaymentRecents(
        <String>['wallet-one'],
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isTrue,
    );
    expect(
      await savePaymentRecents(
        <String>['wallet-two'],
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(
      await saveBillTemplateEntries(
        <String>['{"biller_code":"electricity","account":"111"}'],
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isTrue,
    );
    expect(
      await saveBillTemplateEntries(
        <String>['{"biller_code":"water","account":"222"}'],
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(
      await saveSeenPaymentRequestIds(
        <String>['req-one'],
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isTrue,
    );
    expect(
      await saveSeenPaymentRequestIds(
        <String>['req-two'],
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );

    expect(
      await loadPaymentRecents(
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      <String>['wallet-one'],
    );
    expect(
      await loadPaymentRecents(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      <String>['wallet-two'],
    );
    expect(
      await loadBillTemplateEntries(
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      <String>['{"biller_code":"electricity","account":"111"}'],
    );
    expect(
      await loadBillTemplateEntries(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      <String>['{"biller_code":"water","account":"222"}'],
    );
    expect(
      await loadSeenPaymentRequestIds(
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      <String>['req-one'],
    );
    expect(
      await loadSeenPaymentRequestIds(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      <String>['req-two'],
    );
  });
}
