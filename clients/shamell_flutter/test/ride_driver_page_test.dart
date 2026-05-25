import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/dashboard_policy_scope.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/rides/ride_driver_page.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_mobility_api.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';

Widget _testApp(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeRideDriverApi extends RideMobilityApi {
  _FakeRideDriverApi() : super(baseUrl: 'https://api.example.com');

  int bootstrapCalls = 0;
  int presenceCalls = 0;
  int activeTripCalls = 0;
  int queueCalls = 0;
  int financeCalls = 0;
  int shiftCalls = 0;
  int documentCalls = 0;

  @override
  Future<RidePlatformBootstrap?> bootstrapConfig() async {
    bootstrapCalls++;
    return null;
  }

  @override
  Future<RideDriverPresence?> driverPresence() async {
    presenceCalls++;
    return null;
  }

  @override
  Future<RideTrip?> driverActiveTrip() async {
    activeTripCalls++;
    return null;
  }

  @override
  Future<List<RideTrip>> driverQueueTrips({int limit = 12}) async {
    queueCalls++;
    return const <RideTrip>[];
  }

  @override
  Future<RideDriverFinanceDashboard?> driverFinanceDashboard() async {
    financeCalls++;
    return null;
  }

  @override
  Future<RideDriverShiftSummary?> driverShiftSummary() async {
    shiftCalls++;
    return null;
  }

  @override
  Future<RideDriverDocumentDashboard?> driverDocuments() async {
    documentCalls++;
    return null;
  }

  @override
  Stream<String> driverUpdateStream() => const Stream<String>.empty();
}

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
  });

  testWidgets('ride driver page consumes dashboard policy override',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeRideDriverApi();

    await tester.pumpWidget(
      _testApp(
        RideDriverPage(
          baseUrl: 'https://api.example.com',
          api: api,
          dashboardPolicyOverride: const ShamellDashboardPolicy(
            baseUrl: 'https://api.example.com',
            privilegeSnapshot: AccountPrivilegeSnapshot(
              isSuperadmin: true,
            ),
            capabilities: ShamellCapabilities.conservativeDefaults,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('SyrChat Driver'), findsOneWidget);
    expect(api.bootstrapCalls, 1);
    expect(api.presenceCalls, greaterThanOrEqualTo(2));
    expect(api.activeTripCalls, 1);
    expect(api.financeCalls, 1);
    expect(api.shiftCalls, 1);
    expect(api.documentCalls, 1);
  });
}
