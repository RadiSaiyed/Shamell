import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/v2_auth_strangler.dart';
import 'package:shamell_flutter/main.dart'
    show
        HomePage,
        LoginGate,
        LoginPage,
        shamellAllowsDebugAndroidEmulatorSignInBypass,
        shamellAllowLocalhostControlWebDirectDashboards,
        shamellPushBindingReconcileOverride,
        shamellSetActiveBootstrapBaseUrl;

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
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'base_url': 'https://api.example.com',
    });
    secStore.clear();
    shamellPushBindingReconcileOverride = null;
    shamellSetActiveBootstrapBaseUrl(null);
    await clearSessionCookie();
  });

  testWidgets(
      'LoginGate does not expose the cosmetic V2 credential sign-in surface without a session',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginGate(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Welcome to SyrChat V2'), findsNothing);
    expect(find.text('Sign in to access core flows.'), findsNothing);
    expect(find.text('Prefer v2 sign-in'), findsNothing);
  });

  testWidgets(
      'LoginGate honors active bootstrap base for authenticated home routing',
      (tester) async {
    const storedOrigin = 'https://api.one.example';
    const activeOrigin = 'https://api.two.example';
    const token = '0123456789abcdef0123456789abcdef';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', storedOrigin);
    shamellSetActiveBootstrapBaseUrl(activeOrigin);
    await setSessionTokenForBaseUrl(activeOrigin, token);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginGate(
          debugHomeBuilder: (baseUrlOverride) => Text(
            'home:${baseUrlOverride ?? ''}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('home:$activeOrigin'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'LoginGate forwards active bootstrap base into LoginPage when no session exists',
      (tester) async {
    const storedOrigin = 'https://api.one.example';
    const activeOrigin = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', storedOrigin);
    shamellSetActiveBootstrapBaseUrl(activeOrigin);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginGate(
          debugLoginBuilder: (baseUrlOverride) => Text(
            'login:${baseUrlOverride ?? ''}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('login:$activeOrigin'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  test('localhost control web bypass stays limited to operator web on loopback',
      () {
    expect(
      shamellAllowLocalhostControlWebDirectDashboards(
        appSurface: ShamellAppSurface.operator,
        currentUri: Uri.parse('http://127.0.0.1/control/'),
        isWeb: true,
        isReleaseMode: true,
      ),
      isTrue,
    );
    expect(
      shamellAllowLocalhostControlWebDirectDashboards(
        appSurface: ShamellAppSurface.operator,
        currentUri: Uri.parse('https://shamell.online/control/'),
        isWeb: true,
        isReleaseMode: true,
      ),
      isFalse,
    );
    expect(
      shamellAllowLocalhostControlWebDirectDashboards(
        appSurface: ShamellAppSurface.operator,
        currentUri: Uri.parse('https://online.shamell.online/control/'),
        isWeb: true,
        isReleaseMode: true,
        directDashboardHostsRaw: 'online.shamell.online',
      ),
      isTrue,
    );
    expect(
      shamellAllowLocalhostControlWebDirectDashboards(
        appSurface: ShamellAppSurface.superapp,
        currentUri: Uri.parse('http://127.0.0.1/control/'),
        isWeb: true,
        isReleaseMode: true,
      ),
      isFalse,
    );
    expect(
      shamellAllowLocalhostControlWebDirectDashboards(
        appSurface: ShamellAppSurface.superapp,
        currentUri: Uri.parse('https://shamell.online/'),
        isWeb: true,
        isReleaseMode: true,
        directAppHostsRaw: 'shamell.online',
      ),
      isTrue,
    );
  });

  test('android emulator sign-in bypass stays limited to debug superapp', () {
    expect(
      shamellAllowsDebugAndroidEmulatorSignInBypass(
        appSurface: ShamellAppSurface.superapp,
        isWeb: false,
        isReleaseMode: false,
        platformIsAndroid: true,
      ),
      isTrue,
    );
    expect(
      shamellAllowsDebugAndroidEmulatorSignInBypass(
        appSurface: ShamellAppSurface.ride,
        isWeb: false,
        isReleaseMode: false,
        platformIsAndroid: true,
      ),
      isFalse,
    );
    expect(
      shamellAllowsDebugAndroidEmulatorSignInBypass(
        appSurface: ShamellAppSurface.operator,
        isWeb: false,
        isReleaseMode: false,
        platformIsAndroid: true,
      ),
      isFalse,
    );
    expect(
      shamellAllowsDebugAndroidEmulatorSignInBypass(
        appSurface: ShamellAppSurface.superapp,
        isWeb: false,
        isReleaseMode: true,
        platformIsAndroid: true,
      ),
      isFalse,
    );
    expect(
      shamellAllowsDebugAndroidEmulatorSignInBypass(
        appSurface: ShamellAppSurface.superapp,
        isWeb: true,
        isReleaseMode: false,
        platformIsAndroid: true,
      ),
      isFalse,
    );
  });

  testWidgets(
      'LoginGate can bypass localhost control web login and preseed dashboard privileges',
      (tester) async {
    const activeOrigin = 'https://api.two.example';
    shamellSetActiveBootstrapBaseUrl(activeOrigin);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginGate(
          appSurface: ShamellAppSurface.operator,
          debugAllowLocalhostControlWebBypassOverride: true,
          debugHomeBuilder: (baseUrlOverride) => Text(
            'home:${baseUrlOverride ?? ''}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('home:$activeOrigin'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    final privileges =
        await loadAccountPrivilegeSnapshotForBaseUrl(activeOrigin);
    expect(privileges.isSuperadmin, isTrue);
    expect(privileges.roles, contains('ops'));
    expect(privileges.roles, contains('operator_dispatch'));
  });

  testWidgets(
      'LoginGate can bypass android emulator sign-in and disable startup tasks',
      (tester) async {
    const activeOrigin = 'https://api.two.example';
    shamellSetActiveBootstrapBaseUrl(activeOrigin);

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginGate(
          appSurface: ShamellAppSurface.superapp,
          debugAllowAndroidEmulatorSignInBypassOverride: true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LoginPage), findsNothing);
    final home = tester.widget<HomePage>(find.byType(HomePage));
    expect(home.baseUrlOverride, activeOrigin);
    expect(home.runStartupTasks, isFalse);
  });

  testWidgets(
      'LoginPage keeps explicit bootstrap base override instead of stored base_url',
      (tester) async {
    const storedOrigin = 'https://api.one.example';
    const activeOrigin = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', storedOrigin);

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginPage(
          hasSession: true,
          baseUrlOverride: activeOrigin,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final dynamic state = tester.state(find.byType(LoginPage));
    expect(state.debugCurrentBaseUrl(), activeOrigin);
    expect(sp.getString('base_url'), storedOrigin);
  });

  testWidgets(
      'LoginPage does not persist selected base_url while explicit bootstrap override is active',
      (tester) async {
    const storedOrigin = 'https://api.one.example';
    const activeOrigin = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', storedOrigin);

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginPage(
          hasSession: true,
          baseUrlOverride: activeOrigin,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final dynamic state = tester.state(find.byType(LoginPage));
    await state.debugPersistSelectedBaseUrl();

    expect(sp.getString('base_url'), storedOrigin);
  });

  testWidgets(
      'LoginPage records auth benchmarks in explicit bootstrap scope instead of stored scope',
      (tester) async {
    const storedOrigin = 'https://api.one.example';
    const activeOrigin = 'https://api.two.example';

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', storedOrigin);

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginPage(
          hasSession: true,
          baseUrlOverride: activeOrigin,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final dynamic state = tester.state(find.byType(LoginPage));
    await state.debugRecordAuthAttempt(
      variant: AuthFlowVariant.legacy,
      elapsedMs: 210,
      success: true,
    );

    final scoped = await V2AuthStranglerStore.readBenchmarks(
      sp: sp,
      baseUrlOverride: activeOrigin,
    );
    final stored = await V2AuthStranglerStore.readBenchmarks(
      sp: sp,
      baseUrlOverride: storedOrigin,
    );

    expect(scoped.legacy.attempts, 1);
    expect(scoped.legacy.successes, 1);
    expect(stored.hasAnySamples, isFalse);
  });

  testWidgets('LoginPage replaces the auth route after post-login navigation',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: LoginPage(
          hasSession: true,
          debugSignedInHomeBuilder: (baseUrlOverride) => Text(
            'home:${baseUrlOverride ?? ''}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(navigatorKey.currentState?.canPop(), isFalse);

    final dynamic state = tester.state(find.byType(LoginPage));
    await state.debugHandlePostLoginNavigation();
    await tester.pumpAndSettle();

    expect(find.text('home:https://api.example.com'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(navigatorKey.currentState?.canPop(), isFalse);
  });

  testWidgets('LoginPage renders approved username/password auth on operator web',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginPage(
          appSurface: ShamellAppSurface.operator,
          debugIsWebOverride: true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sign in to SyrChat Control'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Sign up'), findsNothing);
    expect(find.text('SyrChat Control Web'), findsNothing);
    expect(find.text('Check browser session'), findsNothing);
    expect(find.text('Open QR sign-in'), findsNothing);
  });

  testWidgets('LoginGate reconciles push binding when app resumes',
      (tester) async {
    final calls = <String?>[];
    shamellPushBindingReconcileOverride = ({
      String? baseUrlOverride,
    }) async {
      calls.add(baseUrlOverride);
    };

    await tester.pumpWidget(
      MaterialApp(
        home: LoginGate(
          debugLoginBuilder: (baseUrlOverride) => Text(
            'login:${baseUrlOverride ?? ''}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, <String?>['https://api.example.com']);
  });
}
