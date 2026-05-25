import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/main.dart'
    show
        AdminDashboardPage,
        LoginPage,
        OpsPage,
        SuperadminDashboardPage,
        SystemStatusPage,
        TopupKioskPage,
        buildSuperadminPaymentsApi;

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
    bool coach = false,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await ShamellCapabilities(
      coach: coach,
      chat: true,
      payments: true,
      friends: false,
      moments: false,
      officialAccounts: false,
      channels: false,
      serviceNotifications: false,
      paymentsPhoneTargets: false,
    ).persistForBaseUrl(sp, baseUrl);
  }

  testWidgets('TopupKioskPage fail-closes when kiosk APIs are unsupported',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupKioskPage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(
        find.text(
            'Your account is not allowed to access payments operator tools.'),
        findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'TopupKioskPage shows feature unavailable for permission-only payments operators',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      permissions: const <String>['wallet.operator.read'],
      products: const <String>['wallet'],
    );

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupKioskPage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(find.text('Topup kiosk is unavailable on this server.'),
        findsOneWidget);
  });

  testWidgets('SystemStatusPage fail-closes when status APIs are unsupported',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SystemStatusPage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(
      find.text('System status is unavailable on this server.'),
      findsOneWidget,
    );
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('TopupKioskPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TopupKioskPage(
          'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(
        find.text(
            'Your account is not allowed to access payments operator tools.'),
        findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('SystemStatusPage rejects malformed base urls before network',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SystemStatusPage(
          'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(
      find.text('System status is unavailable on this server.'),
      findsOneWidget,
    );
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('OpsPage denies access without stored ops roles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OpsPage('https://api.example.com'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Your account is not allowed to access operator tools.'),
      findsOneWidget,
    );
    expect(find.text('Risk Admin'), findsNothing);
  });

  testWidgets('OpsPage hides admin web consoles for operator-only accounts',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      roles: const <String>['operator_payments'],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: OpsPage('https://api.example.com'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Risk Admin'), findsNothing);
    expect(find.text('Admin Exports'), findsNothing);
    expect(find.text('Topup Sellers'), findsNothing);
    expect(find.text('No operator tools are enabled on this server.'),
        findsOneWidget);
  });

  testWidgets(
      'OpsPage allows permission-only operator access without admin web consoles',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      permissions: const <String>['rides.operator.read'],
      products: const <String>['rides'],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: OpsPage('https://api.example.com'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('Your account is not allowed to access operator tools.'),
      findsNothing,
    );
    expect(find.text('Risk Admin'), findsNothing);
    expect(find.text('Admin Exports'), findsNothing);
    expect(find.text('Topup Sellers'), findsNothing);
    expect(find.text('No operator tools are enabled on this server.'),
        findsOneWidget);
  });

  testWidgets('OpsPage hides Coach Boarding when coach capability is off',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      roles: const <String>['admin'],
    );
    await saveCapabilities(
      baseUrl: 'https://api.example.com',
      coach: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: OpsPage('https://api.example.com'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Coach Boarding'), findsNothing);
    expect(find.text('Risk Admin'), findsOneWidget);
  });

  testWidgets(
      'OpsPage shows Coach Boarding for permission-only coach crew accounts',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      permissions: const <String>['coach.manifest.read'],
      products: const <String>['coach'],
    );
    await saveCapabilities(
      baseUrl: 'https://api.example.com',
      coach: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: OpsPage('https://api.example.com'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Coach Boarding'), findsOneWidget);
    expect(find.text('Risk Admin'), findsNothing);
  });

  testWidgets('AdminDashboardPage denies access without admin roles',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardPage('https://api.example.com'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Your account is not allowed to access the admin console.'),
      findsOneWidget,
    );
    expect(find.text('Admin overview (web)'), findsNothing);
  });

  testWidgets('AdminDashboardPage hides coach ops queue when coach is off',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      roles: const <String>['admin'],
    );
    await saveCapabilities(
      baseUrl: 'https://api.example.com',
      coach: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardPage('https://api.example.com'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Admin command desk'), findsOneWidget);
    expect(find.text('Coach ops queue'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Admin overview (web)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Admin overview (web)'), findsOneWidget);
  });

  testWidgets('AdminDashboardPage allows permission-only admin snapshots',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      permissions: const <String>[
        'coach.admin.read',
        'control.dashboard.read',
      ],
      products: const <String>['coach', 'control'],
    );
    await saveCapabilities(
      baseUrl: 'https://api.example.com',
      coach: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardPage('https://api.example.com'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('Your account is not allowed to access the admin console.'),
      findsNothing,
    );
    expect(find.text('Admin command desk'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Admin overview (web)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Admin overview (web)'), findsOneWidget);
    expect(find.text('Coach admin'), findsOneWidget);
  });

  testWidgets('SuperadminDashboardPage denies access without dashboard grants',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SuperadminDashboardPage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(
      find.text(
          'Your account is not allowed to access the Superadmin console.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SuperadminDashboardPage fail-closes dead global stats APIs without network',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://api.example.com',
      permissions: const <String>['control.dashboard.read'],
      products: const <String>['control'],
    );

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SuperadminDashboardPage(
          'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
    expect(
      find.text('Global stats are unavailable on this server.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SuperadminDashboardPage rejects malformed base urls before network',
      (tester) async {
    await savePrivileges(
      baseUrl: 'https://user:pass@api.example.com/root',
      permissions: const <String>['control.dashboard.read'],
      products: const <String>['control'],
    );

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SuperadminDashboardPage(
          'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
    expect(
      find.text('Global stats are unavailable on this server.'),
      findsOneWidget,
    );
  });

  test('buildSuperadminPaymentsApi keeps mini-app kv state wallet-scoped',
      () async {
    final walletOne = buildSuperadminPaymentsApi(
      baseUrl: 'https://api.example.com',
      walletId: 'wallet-1',
    );
    final walletTwo = buildSuperadminPaymentsApi(
      baseUrl: 'https://api.example.com',
      walletId: 'wallet-2',
    );

    await walletOne.kvSetString('draft', 'wallet-one');

    expect(await walletOne.kvGetString('draft'), 'wallet-one');
    expect(await walletTwo.kvGetString('draft'), isNull);
    expect(walletOne.walletId, 'wallet-1');
    expect(walletTwo.walletId, 'wallet-2');
  });
}
