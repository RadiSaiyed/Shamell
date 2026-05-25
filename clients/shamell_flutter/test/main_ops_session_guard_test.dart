import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/perf.dart';
import 'package:shamell_flutter/main.dart'
    show
        CashMandatePage,
        SettingsPage,
        SonicPayPage,
        shamellOpsMaskSensitivePayloadForDisplay,
        shamellOpsTrustedWebPathRequiresSensitiveReveal;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

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
    await clearAccountPrivilegeSnapshot();
  });

  Future<void> savePrivileges({
    required String baseUrl,
    List<String> roles = const <String>[],
    List<String> permissions = const <String>[],
    List<String> products = const <String>[],
    bool isAdmin = false,
    bool isSuperadmin = false,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', baseUrl);
    await saveAccountPrivilegeSnapshot(
      roles: roles,
      permissions: permissions,
      products: products,
      isAdmin: isAdmin,
      isSuperadmin: isSuperadmin,
      sp: sp,
    );
  }

  Future<void> saveCapabilities({
    required String baseUrl,
    bool paymentsSonic = false,
    bool paymentsCashVouchers = false,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await ShamellCapabilities(
      coach: false,
      chat: true,
      payments: true,
      friends: false,
      moments: false,
      officialAccounts: false,
      channels: false,
      serviceNotifications: false,
      paymentsPhoneTargets: false,
      paymentsSonic: paymentsSonic,
      paymentsCashVouchers: paymentsCashVouchers,
    ).persistForBaseUrl(sp, baseUrl);
  }

  test('ops payload masking redacts secret segments in key-value payloads', () {
    expect(
      shamellOpsMaskSensitivePayloadForDisplay(
        'SONIC|token=0123456789abcdef',
      ),
      'SONIC|token=01***ef',
    );
    expect(
      shamellOpsMaskSensitivePayloadForDisplay('CASH|code=abcdef12'),
      'CASH|code=ab***12',
    );
  });

  test('ops payload masking redacts non-segment payloads', () {
    expect(shamellOpsMaskSensitivePayloadForDisplay('abcd'), '****');
    expect(
      shamellOpsMaskSensitivePayloadForDisplay('abcdefghij'),
      'ab***ij',
    );
  });

  test('admin web paths require local sensitive reveal before launch', () {
    expect(
      shamellOpsTrustedWebPathRequiresSensitiveReveal(
        const <String>['admin', 'risk'],
      ),
      isTrue,
    );
    expect(
      shamellOpsTrustedWebPathRequiresSensitiveReveal(
        const <String>['admin', 'exports'],
      ),
      isTrue,
    );
    expect(
      shamellOpsTrustedWebPathRequiresSensitiveReveal(
        const <String>['ops', 'status'],
      ),
      isFalse,
    );
    expect(
      shamellOpsTrustedWebPathRequiresSensitiveReveal(const <String>[]),
      isFalse,
    );
  });

  testWidgets('SonicPayPage fail-closes when Sonic APIs are disabled',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SonicPayPage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(
      find.text(
          'Your account is not allowed to access payments operator tools.'),
      findsOneWidget,
    );
    expect(find.text('Issue token'), findsNothing);
  });

  testWidgets(
      'SonicPayPage shows feature unavailable for permission-only payments operators',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      permissions: const <String>['wallet.operator.read'],
      products: const <String>['wallet'],
    );
    await saveCapabilities(
      baseUrl: 'https://api.example.com',
      paymentsSonic: false,
    );

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SonicPayPage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Sonic is unavailable on this server.'), findsOneWidget);
  });

  testWidgets('CashMandatePage fail-closes when cash APIs are disabled',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CashMandatePage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(
      find.text(
          'Your account is not allowed to access payments operator tools.'),
      findsOneWidget,
    );
    expect(find.text('Create'), findsNothing);
  });

  testWidgets(
      'CashMandatePage shows feature unavailable for permission-only cash agents',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      permissions: const <String>['cash.agent.read'],
      products: const <String>['wallet'],
    );
    await saveCapabilities(
      baseUrl: 'https://api.example.com',
      paymentsCashVouchers: false,
    );

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CashMandatePage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(
      find.text('Cash vouchers are unavailable on this server.'),
      findsOneWidget,
    );
  });

  testWidgets('SonicPayPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SonicPayPage(
          'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(
      find.text(
          'Your account is not allowed to access payments operator tools.'),
      findsOneWidget,
    );
  });

  testWidgets('CashMandatePage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unexpected', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CashMandatePage(
          'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(
      find.text(
          'Your account is not allowed to access payments operator tools.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SettingsPage loads metrics preference from explicit baseUrl scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);
    await Perf.saveRemotePreference(
      false,
      sp: sp,
      baseUrlOverride: originOne,
    );
    await Perf.saveRemotePreference(
      true,
      sp: sp,
      baseUrlOverride: originTwo,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsPage(
          baseUrl: originOne,
          walletId: 'wallet_one',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final switchTile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isFalse);
  });

  testWidgets(
      'SettingsPage saves wallet into explicit normalized baseUrl scope only',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);
    await saveStoredWalletId(
      'wallet_two',
      sp: sp,
      baseUrlOverride: originTwo,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsPage(
          baseUrl: originOne,
          walletId: 'wallet_one',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(1), 'wallet_scoped');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      await loadStoredWalletId(
        sp: sp,
        baseUrlOverride: originOne,
      ),
      'wallet_scoped',
    );
    expect(
      await loadStoredWalletId(
        sp: sp,
        baseUrlOverride: originTwo,
      ),
      'wallet_two',
    );
    expect(sp.getString('base_url'), originOne);
  });
}
