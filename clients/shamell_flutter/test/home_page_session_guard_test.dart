import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/analytics_migration.dart';
import 'package:shamell_flutter/core/app_flags.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/legacy_sensitive_pref_store.dart';
import 'package:shamell_flutter/core/notification_tap_target.dart';
import 'package:shamell_flutter/core/pending_notification_store.dart';
import 'package:shamell_flutter/core/shamell_user_id.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/main.dart';

Widget _testApp(HomePage home) {
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

ShamellCapabilities _caps({
  bool friends = false,
  bool serviceNotifications = false,
  bool officialAccounts = false,
}) {
  return ShamellCapabilities(
    chat: true,
    payments: true,
    friends: friends,
    moments: false,
    officialAccounts: officialAccounts,
    channels: false,
    serviceNotifications: serviceNotifications,
    paymentsPhoneTargets: false,
  );
}

Future<void> _invokeFriendsSummaryLoad(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadFriendsSummary();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeContactsRosterLoad(
  WidgetTester tester, {
  bool force = false,
}) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadContactsRoster(force: force);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeRefreshFriendsSurface(
  WidgetTester tester, {
  bool forceRoster = false,
}) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugRefreshFriendsSurface(forceRoster: forceRoster);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeConsumePendingNotificationPayload(
  WidgetTester tester,
) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugConsumePendingNotificationPayload();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeRegisterDeviceBestEffort(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugRegisterDeviceBestEffort();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<bool> _invokeEnsureAuthSessionForGuardedNav(
  WidgetTester tester,
) async {
  final dynamic state = tester.state(find.byType(HomePage));
  final allowed = await state.debugEnsureAuthSessionForGuardedNav() as bool;
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return allowed;
}

Future<void> _invokeServiceNotificationsLoad(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadServiceNotificationsBadge();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeUnreadBadgeLoad(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadUnreadBadge();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

bool _readServiceNotificationsBadge(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return state.debugHasUnreadServiceNotificationsBadge() as bool;
}

int _readUnreadChatsCount(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return state.debugTotalUnreadChats() as int;
}

Map<String, int> _readFriendsSummaryState(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return Map<String, int>.from(state.debugFriendsSummaryState() as Map);
}

Map<String, Object?> _readPrivilegeState(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return Map<String, Object?>.from(state.debugPrivilegeState() as Map);
}

Map<String, Object?> _readWalletState(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return Map<String, Object?>.from(state.debugWalletState() as Map);
}

Map<String, Object?> _readCurrencyWalletsState(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return Map<String, Object?>.from(state.debugCurrencyWalletsState() as Map);
}

int _readCallSignalingInitRequestCount(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return state.debugCallSignalingInitRequestCount() as int;
}

bool _readDefaultOfficialAccountFlag(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return state.debugHasDefaultOfficialAccount() as bool;
}

Map<String, Object?> _readContactsState(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return Map<String, Object?>.from(state.debugContactsState() as Map);
}

Map<String, String> _readProfileIdentityState(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(HomePage));
  return Map<String, String>.from(state.debugProfileIdentityState() as Map);
}

Future<void> _invokeOpenOfficialNotifications(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugOpenOfficialNotifications();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeEnsureServiceOfficialFollow(
  WidgetTester tester, {
  required String officialId,
  required String chatPeerId,
}) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugEnsureServiceOfficialFollow(
    officialId: officialId,
    chatPeerId: chatPeerId,
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeApplyOfficialNotificationGroupMode(
  WidgetTester tester, {
  required List<Map<String, dynamic>> accounts,
  required AnalyticsOfficialGroup group,
  required OfficialNotificationMode mode,
}) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugApplyOfficialNotificationGroupMode(
    accounts: accounts,
    group: group,
    mode: mode,
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeLoadRoles(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadRoles();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeLoadWalletSummary(
  WidgetTester tester,
  String walletId,
) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadWalletSummary(walletId);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeRefreshHomeSnapshot(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugRefreshHomeSnapshot();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeRefreshHomeStartupState(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugRefreshHomeStartupState();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeRefreshHomeStartupStateSkippingSnapshot(
  WidgetTester tester,
) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugRefreshHomeStartupState(skipHomeSnapshotRefresh: true);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeCompleteOnlineHomeStartup(
  WidgetTester tester, {
  required bool bootstrappedHomeSnapshot,
}) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugCompleteOnlineHomeStartup(
    bootstrappedHomeSnapshot: bootstrappedHomeSnapshot,
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeLoadDefaultOfficialAccountFlag(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadDefaultOfficialAccountFlag();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeLoadStoredProfileIdentity(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadStoredProfileIdentity();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeLoadPrefs(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLoadPrefs();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void _seedContactsState(
  WidgetTester tester, {
  required List<Map<String, dynamic>> roster,
  String? error,
  bool loading = false,
  String? stickyHeader,
}) {
  final dynamic state = tester.state(find.byType(HomePage));
  state.debugSeedContactsState(
    roster: roster,
    error: error,
    loading: loading,
    stickyHeader: stickyHeader,
  );
}

Future<void> _invokeEnsureSessionBootstrap(
  WidgetTester tester, {
  bool force = false,
}) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugEnsureSessionBootstrap(force: force);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void _setSuppressCallSignalingInit(
  WidgetTester tester,
  bool suppress,
) {
  final dynamic state = tester.state(find.byType(HomePage));
  state.debugSuppressCallSignalingInit(suppress);
}

Future<void> _invokeHandleCallSignalingEvent(
  WidgetTester tester,
  Map<String, dynamic> msg,
) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugHandleCallSignalingEvent(msg);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeHandleUri(WidgetTester tester, String rawUri) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugHandleUri(Uri.parse(rawUri));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeShowInviteQr(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugShowInviteQr();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeLogout(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLogout();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _invokeLogoutForgetDevice(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(HomePage));
  await state.debugLogoutForgetDevice();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _seedScopedDefaultOfficialAccount({
  required SharedPreferences sp,
  required String baseUrl,
  required String accountId,
  required String accountName,
}) async {
  const secureStore = FlutterSecureStorage();
  await sp.setString('base_url', baseUrl);
  final suffix = base64Url.encode(utf8.encode(baseUrl)).replaceAll('=', '');
  await secureStore.write(
    key: 'legacy.official.default_account.id.v2.$suffix',
    value: accountId,
  );
  await secureStore.write(
    key: 'legacy.official.default_account.name.v2.$suffix',
    value: accountName,
  );
}

Future<void> _seedScopedLegacyProfile({
  required SharedPreferences sp,
  required String baseUrl,
  required String name,
  required String phone,
}) async {
  const secureStore = FlutterSecureStorage();
  await sp.setString('base_url', baseUrl);
  final suffix = base64Url.encode(utf8.encode(baseUrl)).replaceAll('=', '');
  await secureStore.write(
    key: 'legacy.profile.name.v2.$suffix',
    value: name,
  );
  await secureStore.write(
    key: 'legacy.profile.phone.v2.$suffix',
    value: phone,
  );
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

  test(
      'officialNotificationGroupModeForAccounts ignores unfollowed rows and falls back on mixed followed state',
      () {
    final accounts = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'service_followed',
        'kind': 'service',
        'followed': true,
      },
      <String, dynamic>{
        'id': 'service_unfollowed',
        'kind': 'service',
        'followed': false,
      },
      <String, dynamic>{
        'id': 'nonservice_one',
        'kind': 'channel',
        'followed': true,
      },
      <String, dynamic>{
        'id': 'nonservice_two',
        'kind': 'channel',
        'followed': true,
      },
    ];

    expect(
      officialNotificationGroupModeForAccounts(
        accounts: accounts,
        serverModes: const <String, String>{
          'service_followed': 'summary',
          'service_unfollowed': 'muted',
          'nonservice_one': 'muted',
          'nonservice_two': 'summary',
        },
        group: AnalyticsOfficialGroup.service,
      ),
      OfficialNotificationMode.summary,
    );
    expect(
      officialNotificationGroupModeForAccounts(
        accounts: accounts,
        serverModes: const <String, String>{
          'service_followed': 'summary',
          'service_unfollowed': 'muted',
          'nonservice_one': 'muted',
          'nonservice_two': 'summary',
        },
        group: AnalyticsOfficialGroup.nonservice,
      ),
      OfficialNotificationMode.full,
    );
  });

  testWidgets('HomePage reauths on critical friends-summary load failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.example.com/me/friends');
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(friends: true),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeFriendsSummaryLoad(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('HomePage logout forwards localhost session headers',
      (tester) async {
    await setSessionTokenForBaseUrl(
      'http://127.0.0.1:8080',
      '0123456789abcdef0123456789abcdef',
    );

    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://127.0.0.1:8080/auth/logout');
      expect(request.headers['cookie'],
          '__host-sa_session=0123456789abcdef0123456789abcdef');
      expect(request.headers['x-shamell-client-ip'], '127.0.0.1');
      return http.Response('{"ok":true}', 200);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'http://127.0.0.1:8080',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLogout(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage contacts roster uses injected client instead of raw network dispatch',
      (tester) async {
    var rawNetworkAttempted = false;
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.example.com/me/friends');
      return http.Response(
        '{"friends":[{"id":"peer_1","name":"Peer One","device_id":"peer_1"}]}',
        200,
      );
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(friends: true),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await HttpOverrides.runZoned(() async {
      await _invokeContactsRosterLoad(tester, force: true);
    }, createHttpClient: (SecurityContext? context) {
      rawNetworkAttempted = true;
      throw UnsupportedError('raw network dispatch disallowed in tests');
    });

    expect(rawNetworkAttempted, isFalse);
    expect(
      _readContactsState(tester),
      containsPair('count', 1),
    );
  });

  testWidgets(
      'HomePage refreshes friends summary and contacts roster from one shared friends response',
      (tester) async {
    final requests = <String>[];
    final client = MockClient((request) async {
      final url = request.url.toString();
      requests.add(url);
      switch (url) {
        case 'https://api.example.com/me/friends':
          return http.Response(
            '{"friends":[{"id":"peer_1","name":"Peer One","device_id":"peer_1"},{"id":"peer_2","name":"Peer Two","device_id":"peer_2"}]}',
            200,
          );
        case 'https://api.example.com/me/friend_requests':
          return http.Response('{"incoming":[{"id":"req_1"}]}', 200);
      }
      fail('unexpected request: $url');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(friends: true),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeRefreshFriendsSurface(tester, forceRoster: true);

    expect(
      requests.where((url) => url == 'https://api.example.com/me/friends'),
      hasLength(1),
    );
    expect(
      requests
          .where((url) => url == 'https://api.example.com/me/friend_requests'),
      hasLength(1),
    );
    expect(
      _readFriendsSummaryState(tester),
      <String, int>{
        'friends': 2,
        'close_friends': 0,
        'pending_requests': 1,
      },
    );
    expect(_readContactsState(tester), containsPair('count', 2));
  });

  testWidgets(
      'HomePage device registration uses injected client instead of raw network dispatch',
      (tester) async {
    const storedOrigin = 'https://api.one.example';
    const activeOrigin = 'https://api.example.com';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', storedOrigin);
    expect(
      await saveStableDeviceId(
        'device-stored',
        sp: sp,
        baseUrlOverride: storedOrigin,
      ),
      isTrue,
    );
    expect(
      await saveStableDeviceId(
        'device-active',
        sp: sp,
        baseUrlOverride: activeOrigin,
      ),
      isTrue,
    );

    var rawNetworkAttempted = false;
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        '$activeOrigin/auth/devices/register',
      );
      expect(request.method, 'POST');
      final body =
          jsonDecode(request.body.isEmpty ? '{}' : request.body) as Map;
      expect((body['device_id'] ?? '').toString(), 'device-active');
      expect((body['device_type'] ?? '').toString(), isNotEmpty);
      expect((body['platform'] ?? '').toString(), isNotEmpty);
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: activeOrigin,
          client: client,
        ),
      ),
    );
    await tester.pump();

    await HttpOverrides.runZoned(() async {
      await _invokeRegisterDeviceBestEffort(tester);
    }, createHttpClient: (SecurityContext? context) {
      rawNetworkAttempted = true;
      throw UnsupportedError('raw network dispatch disallowed in tests');
    });

    expect(rawNetworkAttempted, isFalse);
  });

  testWidgets(
      'HomePage consumes pending notification payloads from stored scope when override scope is active',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originOne);
    expect(
      await savePendingNotificationTapTarget(
        const NotificationTapTarget.chat(),
        baseUrlOverride: originOne,
      ),
      isTrue,
    );

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: originTwo,
        ),
      ),
    );
    await tester.pump();

    await _invokeConsumePendingNotificationPayload(tester);

    expect(
      await takePendingNotificationTapTarget(baseUrlOverride: originOne),
      isNull,
    );
    final migratedTarget =
        await takePendingNotificationTapTarget(baseUrlOverride: originTwo);
    expect(migratedTarget?.kind, NotificationTapTargetKind.chat);
    expect(migratedTarget?.id, isNull);
  });

  testWidgets(
      'HomePage guarded auth-session check honors explicit baseUrl override over stored scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    const token = '0123456789abcdef0123456789abcdef';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originOne);
    await setSessionTokenForBaseUrl(originTwo, token);

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: originTwo,
        ),
      ),
    );
    await tester.pump();

    expect(await _invokeEnsureAuthSessionForGuardedNav(tester), isTrue);
  });

  testWidgets('HomePage reauths on critical invite deeplink failure',
      (tester) async {
    const inviteToken =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    final pending = state.debugHandleUri(
      Uri.parse('shamell://invite?token=$inviteToken'),
    ) as Future<void>;
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await pending;
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('HomePage skips invite deeplink redemption for malformed token',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeHandleUri(
      tester,
      'shamell://invite?token=not-a-valid-token',
    );

    expect(calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Invalid invite token.'), findsOneWidget);
  });

  testWidgets(
      'HomePage invite deeplink redemption is canceled when user declines confirmation',
      (tester) async {
    const inviteToken =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    final pending = state.debugHandleUri(
      Uri.parse('shamell://invite?token=$inviteToken'),
    ) as Future<void>;
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await pending;
    await tester.pump();

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage ignores duplicate invite deeplinks while redeem confirmation is in flight',
      (tester) async {
    const inviteToken =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    final uri = Uri.parse('shamell://invite?token=$inviteToken');
    final first = state.debugHandleUri(uri) as Future<void>;
    final second = state.debugHandleUri(uri) as Future<void>;

    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await first;
    await second;
    await tester.pump();

    expect(calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('HomePage reauths on critical session bootstrap failure',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (request.url.path == '/auth/account/create') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      fail('unexpected request: ${request.url}');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeEnsureSessionBootstrap(tester, force: true);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('HomePage reauths on critical invite QR creation failure',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeShowInviteQr(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage reauths on critical friend-requests summary load failure',
      (tester) async {
    final client = MockClient((request) async {
      switch (request.url.toString()) {
        case 'https://api.example.com/me/friends':
          return http.Response('{"friends":[]}', 200);
        case 'https://api.example.com/me/friend_requests':
          return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(friends: true),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeFriendsSummaryLoad(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for friends summary',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(friends: true),
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeFriendsSummaryLoad(tester);

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage reauths on critical service-notifications badge failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/me/official_template_messages?unread_only=true&limit=1',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(serviceNotifications: true),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeServiceNotificationsLoad(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage keeps cached service-notifications badge on noncritical probe failure',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    final store = ChatLocalStore();
    await store.saveServiceNotificationsHasUnread(true);

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/me/official_template_messages?unread_only=true&limit=1',
      );
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(serviceNotifications: true),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeServiceNotificationsLoad(tester);

    expect(_readServiceNotificationsBadge(tester), isTrue);
  });

  testWidgets(
      'HomePage loads cached service-notifications badge from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    final store = ChatLocalStore();
    await store.saveServiceNotificationsHasUnread(
      true,
      baseUrlOverride: 'https://api.two.example',
    );

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.two.example/me/official_template_messages?unread_only=true&limit=1',
      );
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(serviceNotifications: true),
          baseUrlOverride: 'https://api.two.example',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeServiceNotificationsLoad(tester);

    expect(_readServiceNotificationsBadge(tester), isTrue);
  });

  testWidgets('HomePage loads unread badge from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    final store = ChatLocalStore();
    await store.saveUnread(<String, int>{'peer-global': 5});
    await store.saveUnread(
      <String, int>{'peer-scoped': 2},
      baseUrlOverride: 'https://api.two.example',
    );

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(),
          baseUrlOverride: 'https://api.two.example',
        ),
      ),
    );
    await tester.pump();

    await _invokeUnreadBadgeLoad(tester);

    expect(_readUnreadChatsCount(tester), 2);
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for service notifications badge',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://user:pass@api.example.com/root');
    final store = ChatLocalStore();
    await store.saveServiceNotificationsHasUnread(true);
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(serviceNotifications: true),
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeServiceNotificationsLoad(tester);

    expect(calls, 0);
    expect(_readServiceNotificationsBadge(tester), isTrue);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('HomePage reauths on critical call-signaling error event',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    await _invokeHandleCallSignalingEvent(tester, <String, dynamic>{
      'type': 'error',
      'detail': 'auth session required',
    });

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage reauths on critical service-official autofollow failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/shamell_pay/follow',
      );
      expect(request.method, 'POST');
      final idempotency = request.headers['Idempotency-Key'] ??
          request.headers['idempotency-key'];
      expect(idempotency, isNotNull);
      expect(idempotency!, startsWith('official-follow-'));
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeEnsureServiceOfficialFollow(
      tester,
      officialId: 'shamell_pay',
      chatPeerId: 'shamell_pay',
    );

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for service-official autofollow',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeEnsureServiceOfficialFollow(
      tester,
      officialId: 'shamell_pay',
      chatPeerId: 'shamell_pay',
    );

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage reauths on critical official-notifications preload failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts?followed_only=true&limit=200',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeOpenOfficialNotifications(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for official-notifications preload',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeOpenOfficialNotifications(tester);

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage preloads dedicated official-notification modes when opening notification sheet',
      (tester) async {
    final requests = <Uri>[];
    final firstPage = List.generate(200, (index) {
      return <String, dynamic>{
        'id': 'official_${index.toString().padLeft(3, '0')}',
        'name': 'Official ${index.toString().padLeft(3, '0')}',
        'kind': 'service',
        'featured': false,
        'followed': true,
      };
    });
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/official_accounts') {
        final beforeId = request.url.queryParameters['before_id'];
        if (beforeId == null) {
          expect(request.url.queryParameters['followed_only'], 'true');
          expect(request.url.queryParameters['limit'], '200');
          return http.Response(
            jsonEncode(<String, Object?>{'accounts': firstPage}),
            200,
          );
        }
        expect(beforeId, 'official_199');
        expect(request.url.queryParameters['before_featured'], 'false');
        expect(request.url.queryParameters['before_name'], 'Official 199');
        return http.Response(
          jsonEncode(<String, Object?>{
            'accounts': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'official_200',
                'name': 'Official 200',
                'kind': 'subscription',
                'featured': false,
                'followed': true,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/official_accounts/notifications') {
        return http.Response('{"modes":{"official_200":"summary"}}', 200);
      }
      fail('unexpected request: ${request.url}');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    final Map<String, Object?> sheetState =
        await state.debugLoadOfficialNotificationSheetState();
    await tester.pump();

    expect(
      requests,
      hasLength(3),
    );
    expect(requests[0].queryParameters['limit'], '200');
    expect(requests[1].queryParameters['before_id'], 'official_199');
    expect(requests[2].toString(),
        'https://api.example.com/official_accounts/notifications');
    expect((sheetState['accounts'] as List).length, 201);
    expect(sheetState['serviceMode'], 'full');
    expect(sheetState['nonServiceMode'], 'summary');
  });

  testWidgets(
      'HomePage reauths on critical official-notification mode sync failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/official_1/notification_mode',
      );
      expect(request.method, 'POST');
      final idempotency = request.headers['Idempotency-Key'] ??
          request.headers['idempotency-key'];
      expect(idempotency, isNotNull);
      expect(idempotency!, startsWith('official-notif-mode-'));
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeApplyOfficialNotificationGroupMode(
      tester,
      accounts: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'official_1',
          'kind': 'service',
          'followed': true,
          'chat_peer_id': 'peer_1',
        },
      ],
      group: AnalyticsOfficialGroup.service,
      mode: OfficialNotificationMode.summary,
    );

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for official-notification mode sync',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeApplyOfficialNotificationGroupMode(
      tester,
      accounts: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'official_1',
          'kind': 'service',
          'followed': true,
          'chat_peer_id': 'peer_1',
        },
      ],
      group: AnalyticsOfficialGroup.service,
      mode: OfficialNotificationMode.summary,
    );

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage syncs official-notification group mode only for followed accounts',
      (tester) async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{"ok":true}', 200);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeApplyOfficialNotificationGroupMode(
      tester,
      accounts: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'official_unfollowed',
          'kind': 'service',
          'followed': false,
          'chat_peer_id': 'peer_1',
        },
        <String, dynamic>{
          'id': 'official_followed_no_peer',
          'kind': 'service',
          'followed': true,
        },
        <String, dynamic>{
          'id': 'official_followed_with_peer',
          'kind': 'service',
          'followed': true,
          'chat_peer_id': 'peer_2',
        },
      ],
      group: AnalyticsOfficialGroup.service,
      mode: OfficialNotificationMode.summary,
    );

    expect(
      requests,
      <String>[
        'POST https://api.example.com/official_accounts/official_followed_no_peer/notification_mode',
        'POST https://api.example.com/official_accounts/official_followed_with_peer/notification_mode',
      ],
    );
  });

  testWidgets('HomePage reauths on critical roles load failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.example.com/me/roles');
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadRoles(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for roles load',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadRoles(tester);

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage loads stored superadmin privilege from explicit baseUrl scope during roles refresh',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originOne);
    await saveAccountPrivilegeSnapshot(
      roles: const <String>['seller'],
      isSuperadmin: false,
      sp: sp,
      baseUrlOverride: originOne,
    );
    await saveAccountPrivilegeSnapshot(
      roles: const <String>['operator_payments'],
      isSuperadmin: true,
      sp: sp,
      baseUrlOverride: originTwo,
    );

    final client = MockClient((request) async {
      expect(request.url.toString(), '$originTwo/me/roles');
      return http.Response('{"roles":["admin"]}', 200);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          runStartupTasks: false,
          baseUrlOverride: originTwo,
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadRoles(tester);

    expect(
      _readPrivilegeState(tester),
      <String, Object?>{
        'roles': <String>['admin'],
        'show_ops': !kEnduserOnly,
        'show_superadmin': !kEnduserOnly,
      },
    );
  });

  testWidgets(
      'HomePage loadPrefs keeps explicit baseUrl override instead of rebinding to stored scope',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originOne);
    await saveAccountPrivilegeSnapshot(
      roles: const <String>['seller'],
      isSuperadmin: false,
      sp: sp,
      baseUrlOverride: originOne,
    );
    await saveAccountPrivilegeSnapshot(
      roles: const <String>['operator_payments'],
      isSuperadmin: true,
      sp: sp,
      baseUrlOverride: originTwo,
    );

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: originTwo,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadPrefs(tester);

    expect(
      _readPrivilegeState(tester),
      containsPair('roles', <String>['operator_payments']),
    );
  });

  testWidgets(
      'HomePage loadPrefs derives ops visibility from permission-only snapshots',
      (tester) async {
    const baseUrl = 'https://api.example.com';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', baseUrl);
    await saveAccountPrivilegeSnapshot(
      roles: const <String>[],
      permissions: const <String>[
        'coach.admin.read',
        'control.dashboard.read',
      ],
      products: const <String>['coach', 'control'],
      isAdmin: true,
      isSuperadmin: false,
      sp: sp,
      baseUrlOverride: baseUrl,
    );

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          runStartupTasks: false,
          baseUrlOverride: baseUrl,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadPrefs(tester);

    expect(
      _readPrivilegeState(tester),
      <String, Object?>{
        'roles': const <String>[],
        'show_ops': !kEnduserOnly,
        'show_superadmin': false,
      },
    );

    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Admin console'),
      kEnduserOnly ? findsNothing : findsOneWidget,
    );
    expect(find.text('Superadmin console'), findsNothing);
  });

  testWidgets(
      'HomePage startup refresh skips legacy roles bridge when permission snapshot already exists',
      (tester) async {
    const baseUrl = 'https://api.example.com';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', baseUrl);
    await saveAccountPrivilegeSnapshot(
      roles: const <String>[],
      permissions: const <String>['rides.operator.read'],
      products: const <String>['rides'],
      isSuperadmin: false,
      sp: sp,
      baseUrlOverride: baseUrl,
    );

    var roleCalls = 0;
    final client = MockClient((request) async {
      if (request.url.toString() == '$baseUrl/me/roles') {
        roleCalls++;
        return http.Response('{"roles":["admin"]}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.operator,
          runStartupTasks: false,
          baseUrlOverride: baseUrl,
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadPrefs(tester);
    await _invokeRefreshHomeStartupStateSkippingSnapshot(tester);

    expect(roleCalls, 0);
    expect(
      _readPrivilegeState(tester),
      <String, Object?>{
        'roles': const <String>[],
        'show_ops': !kEnduserOnly,
        'show_superadmin': false,
      },
    );
  });

  testWidgets(
      'HomePage loadPrefs does not rewrite stored base_url while explicit override is active',
      (tester) async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originOne);

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: originTwo,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadPrefs(tester);

    expect(sp.getString('base_url'), originOne);
  });

  testWidgets('HomePage reauths on critical wallet summary load failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/wallets/wallet_1/snapshot?limit=1',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadWalletSummary(tester, 'wallet_1');

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage ignores stale default official account context while official-accounts capability is disabled',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await _seedScopedDefaultOfficialAccount(
      sp: sp,
      baseUrl: 'https://api.example.com',
      accountId: 'official_1',
      accountName: 'Official One',
    );

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(officialAccounts: false),
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadDefaultOfficialAccountFlag(tester);

    expect(_readDefaultOfficialAccountFlag(tester), isFalse);
  });

  testWidgets(
      'HomePage enables owner console from server-owned official accounts',
      (tester) async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url.toString());
      expect(
        request.url.toString(),
        'https://api.example.com/me/official_account_requests',
      );
      return http.Response(
        '{"requests":[{"account_id":"official_1","name":"Official One","status":"approved"}]}',
        200,
      );
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(officialAccounts: true),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadDefaultOfficialAccountFlag(tester);

    final official = await loadLegacyDefaultOfficialAccountContext(
      baseUrlOverride: 'https://api.example.com',
    );
    expect(requests, <String>[
      'https://api.example.com/me/official_account_requests',
    ]);
    expect(_readDefaultOfficialAccountFlag(tester), isTrue);
    expect(official.accountId, 'official_1');
    expect(official.accountName, 'Official One');
  });

  testWidgets(
      'HomePage does not invent a SyrChat ID when loading stored profile identity without a persisted handle',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await _seedScopedLegacyProfile(
      sp: sp,
      baseUrl: 'https://api.example.com',
      name: 'Ada',
      phone: '+963900000001',
    );

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadStoredProfileIdentity(tester);

    expect(
      _readProfileIdentityState(tester),
      <String, String>{
        'name': 'Ada',
        'phone': '+963900000001',
        'shamell_id': '',
      },
    );
    expect(
      await loadShamellUserId(
          sp: sp, baseUrlOverride: 'https://api.example.com'),
      isNull,
    );
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for wallet summary load',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadWalletSummary(tester, 'wallet_1');

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage startup reuses wallet summary embedded in home snapshot',
      (tester) async {
    final seen = <String>[];
    final client = MockClient((request) async {
      final url = request.url.toString();
      seen.add(url);
      if (url == 'https://api.example.com/me/home_snapshot') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'roles': <String>['admin'],
            'wallet_id': 'wallet_1',
            'wallet': <String, Object?>{
              'wallet_id': 'wallet_1',
              'balance_cents': 4321,
              'currency': 'EUR',
            },
            'wallets': <Map<String, Object?>>[
              <String, Object?>{
                'wallet_id': 'wallet_syp',
                'balance_cents': 1200,
                'currency': 'SYP',
              },
              <String, Object?>{
                'wallet_id': 'wallet_1',
                'balance_cents': 4321,
                'currency': 'EUR',
              },
            ],
          }),
          200,
        );
      }
      fail('unexpected request: $url');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          initialTabIndex: 2,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeRefreshHomeStartupState(tester);

    expect(
      seen,
      <String>['https://api.example.com/me/home_snapshot'],
    );
    expect(
      _readWalletState(tester),
      <String, Object?>{
        'wallet_id': 'wallet_1',
        'wallet_balance_cents': 4321,
        'wallet_currency': 'EUR',
        'wallet_loading': false,
      },
    );
    expect(
      _readCurrencyWalletsState(tester),
      <String, Object?>{
        'SYP': <String, Object?>{
          'wallet_id': 'wallet_syp',
          'balance_cents': 1200,
        },
        'EUR': <String, Object?>{
          'wallet_id': 'wallet_1',
          'balance_cents': 4321,
        },
      },
    );
    expect(find.text('Currency wallets'), findsOneWidget);
    expect(find.text('SYP - Syrian Pound'), findsOneWidget);
    expect(find.text('12.00 SYP'), findsOneWidget);
    expect(find.text('EUR - Euro'), findsOneWidget);
    expect(find.text('43.21 EUR'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
  });

  testWidgets('HomePage hides currency wallets section until wallet data loads',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      _testApp(
        const HomePage(
          initialTabIndex: 2,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Wallet'), findsWidgets);
    expect(find.text('Currency wallets'), findsNothing);
    expect(find.text('Prepare this wallet inside the app'), findsNothing);
    expect(find.text('Prepare wallet now'), findsNothing);
    expect(find.text('Prepare'), findsNothing);
  });

  testWidgets(
      'HomePage startup falls back to wallet summary when home snapshot omits wallet details',
      (tester) async {
    final seen = <String>[];
    final client = MockClient((request) async {
      final url = request.url.toString();
      seen.add(url);
      if (url == 'https://api.example.com/me/home_snapshot') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'roles': <String>['admin'],
            'wallet_id': 'wallet_1',
          }),
          200,
        );
      }
      if (url == 'https://api.example.com/wallets/wallet_1/snapshot?limit=1') {
        return http.Response(
          '{"wallet":{"balance_cents":1234,"currency":"SYP"}}',
          200,
        );
      }
      fail('unexpected request: $url');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeRefreshHomeStartupState(tester);

    expect(
      seen,
      <String>[
        'https://api.example.com/me/home_snapshot',
        'https://api.example.com/wallets/wallet_1/snapshot?limit=1',
      ],
    );
    expect(
      _readWalletState(tester),
      <String, Object?>{
        'wallet_id': 'wallet_1',
        'wallet_balance_cents': 1234,
        'wallet_currency': 'SYP',
        'wallet_loading': false,
      },
    );
  });

  testWidgets('HomePage P2P shortcut opens the payments Send UI',
      (tester) async {
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/wallets/wallet_1/snapshot') {
        return http.Response(
          '{"wallet":{"wallet_id":"wallet_1","balance_cents":1234,"currency":"SYP"},"txns":[]}',
          200,
        );
      }
      if (path == '/payments/requests') {
        return http.Response('[]', 200);
      }
      if (path == '/payments/wallets/wallet_1') {
        return http.Response(
          '{"balance_cents":1234,"currency":"SYP"}',
          200,
        );
      }
      if (path == '/payments/favorites') {
        return http.Response('[]', 200);
      }
      if (path == '/official_accounts/shamell_pay/follow') {
        return http.Response('{}', 200);
      }
      fail('unexpected request: ${request.url}');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          initialTabIndex: 2,
          runStartupTasks: false,
          initialCapabilities: _caps(),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadWalletSummary(tester, 'wallet_1');

    await tester.tap(find.text('P2P').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(find.text('Recipient & amount'), findsOneWidget);
    expect(find.text('Recipient (Wallet/Phone/@alias)'), findsOneWidget);
  });

  testWidgets(
      'HomePage startup skips redundant home snapshot refresh after a fresh bootstrap snapshot',
      (tester) async {
    var homeSnapshotCalls = 0;
    final seen = <String>[];
    final client = MockClient((request) async {
      final url = request.url.toString();
      seen.add(url);
      if (url == 'https://api.example.com/me/home_snapshot') {
        homeSnapshotCalls += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'roles': <String>['admin'],
            'wallet_id': 'wallet_1',
            'wallet': <String, Object?>{
              'wallet_id': 'wallet_1',
              'balance_cents': 4321,
              'currency': 'EUR',
            },
          }),
          200,
        );
      }
      fail('unexpected request: $url');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeRefreshHomeSnapshot(tester);
    await _invokeRefreshHomeStartupStateSkippingSnapshot(tester);

    expect(homeSnapshotCalls, 1);
    expect(
      seen,
      <String>['https://api.example.com/me/home_snapshot'],
    );
    expect(
      _readWalletState(tester),
      <String, Object?>{
        'wallet_id': 'wallet_1',
        'wallet_balance_cents': 4321,
        'wallet_currency': 'EUR',
        'wallet_loading': false,
      },
    );
  });

  testWidgets(
      'HomePage startup tail does not request call signaling init again after bootstrap already did',
      (tester) async {
    const baseUrl = 'https://api.example.com';
    const sessionToken = '0123456789abcdef0123456789abcdef';
    final seen = <String>[];
    final client = MockClient((request) async {
      final url = request.url.toString();
      seen.add(url);
      if (url == '$baseUrl/me/home_snapshot') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'roles': <String>['admin'],
            'wallet_id': 'wallet_1',
            'wallet': <String, Object?>{
              'wallet_id': 'wallet_1',
              'balance_cents': 111,
              'currency': 'SYP',
            },
          }),
          200,
        );
      }
      fail('unexpected request: $url');
    });

    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    await ChatLocalStore().saveIdentity(
      const ChatIdentity(
        id: 'device_self',
        publicKeyB64: 'pubkey',
        privateKeyB64: 'privkey',
        fingerprint: 'fingerprint',
      ),
      baseUrlOverride: baseUrl,
    );
    await ChatLocalStore().saveDeviceAuthToken(
      'device_self',
      'chat-token',
      baseUrlOverride: baseUrl,
    );

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          runStartupTasks: false,
          baseUrlOverride: baseUrl,
          client: client,
        ),
      ),
    );
    await tester.pump();

    _setSuppressCallSignalingInit(tester, true);

    expect(_readCallSignalingInitRequestCount(tester), 0);

    await _invokeEnsureSessionBootstrap(tester);

    expect(_readCallSignalingInitRequestCount(tester), 1);

    await _invokeCompleteOnlineHomeStartup(
      tester,
      bootstrappedHomeSnapshot: true,
    );

    expect(_readCallSignalingInitRequestCount(tester), 1);
    expect(
      seen,
      <String>['$baseUrl/me/home_snapshot'],
    );
  });

  testWidgets('HomePage reauths on critical home snapshot refresh failure',
      (tester) async {
    final client = MockClient((request) async {
      expect(
          request.url.toString(), 'https://api.example.com/me/home_snapshot');
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeRefreshHomeSnapshot(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage clears stale privilege and wallet state when refreshed snapshot omits roles and wallet_id',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await saveStoredShamellUserId(
      'ABCD2345',
      sp: sp,
      baseUrlOverride: 'https://api.example.com',
    );
    final client = MockClient((request) async {
      final url = request.url.toString();
      if (url == 'https://api.example.com/me/roles') {
        return http.Response('{"roles":["admin"]}', 200);
      }
      if (url == 'https://api.example.com/wallets/wallet_1/snapshot?limit=1') {
        return http.Response(
          '{"wallet":{"balance_cents":1234,"currency":"SYP"}}',
          200,
        );
      }
      if (url == 'https://api.example.com/me/home_snapshot') {
        return http.Response(
          '{"capabilities":{"friends":false,"service_notifications":false},"is_superadmin":false}',
          200,
        );
      }
      fail('unexpected request: $url');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadStoredProfileIdentity(tester);
    await _invokeLoadRoles(tester);
    await _invokeLoadWalletSummary(tester, 'wallet_1');

    expect(
      _readProfileIdentityState(tester),
      <String, String>{
        'name': '',
        'phone': '',
        'shamell_id': 'ABCD2345',
      },
    );
    expect(
      _readPrivilegeState(tester),
      <String, Object?>{
        'roles': <String>['admin'],
        'show_ops': !kEnduserOnly,
        'show_superadmin': false,
      },
    );
    expect(
      _readWalletState(tester),
      <String, Object?>{
        'wallet_id': 'wallet_1',
        'wallet_balance_cents': 1234,
        'wallet_currency': 'SYP',
        'wallet_loading': false,
      },
    );

    await _invokeRefreshHomeSnapshot(tester);

    expect(
      _readProfileIdentityState(tester),
      <String, String>{
        'name': '',
        'phone': '',
        'shamell_id': '',
      },
    );
    expect(
      await loadShamellUserId(
          sp: sp, baseUrlOverride: 'https://api.example.com'),
      isNull,
    );
    expect(
      _readPrivilegeState(tester),
      <String, Object?>{
        'roles': const <String>[],
        'show_ops': false,
        'show_superadmin': false,
      },
    );
    expect(
      _readWalletState(tester),
      <String, Object?>{
        'wallet_id': '',
        'wallet_balance_cents': null,
        'wallet_currency': 'SYP',
        'wallet_loading': false,
      },
    );
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for home snapshot refresh',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeRefreshHomeSnapshot(tester);

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
      'HomePage clears stale privilege and wallet state on noncritical home snapshot refresh failure',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await saveStoredShamellUserId(
      'ABCD2345',
      sp: sp,
      baseUrlOverride: 'https://api.example.com',
    );
    final client = MockClient((request) async {
      final url = request.url.toString();
      if (url == 'https://api.example.com/me/roles') {
        return http.Response('{"roles":["admin"]}', 200);
      }
      if (url == 'https://api.example.com/wallets/wallet_1/snapshot?limit=1') {
        return http.Response(
          '{"wallet":{"balance_cents":1234,"currency":"SYP"}}',
          200,
        );
      }
      if (url == 'https://api.example.com/me/home_snapshot') {
        return http.Response('{}', 500);
      }
      fail('unexpected request: $url');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.admin,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLoadStoredProfileIdentity(tester);
    await _invokeLoadRoles(tester);
    await _invokeLoadWalletSummary(tester, 'wallet_1');

    expect((_readPrivilegeState(tester)['roles'] as List<Object?>), isNotEmpty);
    expect(_readWalletState(tester)['wallet_id'], 'wallet_1');
    expect(_readProfileIdentityState(tester)['shamell_id'], 'ABCD2345');

    await _invokeRefreshHomeSnapshot(tester);

    expect(find.byType(LoginPage), findsNothing);
    expect(
      _readProfileIdentityState(tester),
      <String, String>{
        'name': '',
        'phone': '',
        'shamell_id': '',
      },
    );
    expect(
      await loadShamellUserId(
          sp: sp, baseUrlOverride: 'https://api.example.com'),
      isNull,
    );
    expect(
      _readPrivilegeState(tester),
      <String, Object?>{
        'roles': const <String>[],
        'show_ops': false,
        'show_superadmin': false,
      },
    );
    expect(
      _readWalletState(tester),
      <String, Object?>{
        'wallet_id': '',
        'wallet_balance_cents': null,
        'wallet_currency': 'SYP',
        'wallet_loading': false,
      },
    );
  });

  testWidgets(
      'HomePage clears capability-gated badge and friends summary state when home snapshot disables those modules',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await _seedScopedDefaultOfficialAccount(
      sp: sp,
      baseUrl: 'https://api.example.com',
      accountId: 'official_1',
      accountName: 'Official One',
    );
    final store = ChatLocalStore();
    await store.saveServiceNotificationsHasUnread(true);

    final client = MockClient((request) async {
      final url = request.url.toString();
      if (url == 'https://api.example.com/me/friends') {
        return http.Response(
          '{"friends":[{"id":"f1"},{"id":"f2"},{"id":"f3"}]}',
          200,
        );
      }
      if (url == 'https://api.example.com/me/friend_requests') {
        return http.Response('{"incoming":[{"id":"r1"}]}', 200);
      }
      if (url ==
          'https://api.example.com/me/official_template_messages?unread_only=true&limit=1') {
        return http.Response('{"messages":[{"id":"m1"}]}', 200);
      }
      if (url == 'https://api.example.com/me/home_snapshot') {
        return http.Response(
          '{"capabilities":{"friends":false,"official_accounts":false,"service_notifications":false}}',
          200,
        );
      }
      fail('unexpected request: $url');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(
            friends: true,
            officialAccounts: true,
            serviceNotifications: true,
          ),
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeFriendsSummaryLoad(tester);
    await _invokeServiceNotificationsLoad(tester);
    await _invokeLoadDefaultOfficialAccountFlag(tester);
    _seedContactsState(
      tester,
      roster: const <Map<String, dynamic>>[
        <String, dynamic>{'id': 'friend_1', 'name': 'Ada'},
      ],
      error: 'stale roster error',
      loading: true,
      stickyHeader: 'A',
    );
    await tester.pump();

    expect(_readServiceNotificationsBadge(tester), isTrue);
    expect(_readDefaultOfficialAccountFlag(tester), isTrue);
    expect(
      _readContactsState(tester),
      <String, Object?>{
        'count': 1,
        'loading': true,
        'error': 'stale roster error',
        'has_sticky_header': true,
      },
    );
    expect(
      _readFriendsSummaryState(tester),
      <String, int>{
        'friends': 3,
        'close_friends': 0,
        'pending_requests': 1,
      },
    );

    await _invokeRefreshHomeSnapshot(tester);

    expect(_readServiceNotificationsBadge(tester), isFalse);
    expect(_readDefaultOfficialAccountFlag(tester), isFalse);
    expect(
      _readContactsState(tester),
      <String, Object?>{
        'count': 0,
        'loading': false,
        'error': null,
        'has_sticky_header': false,
      },
    );
    expect(
      _readFriendsSummaryState(tester),
      <String, int>{
        'friends': 0,
        'close_friends': 0,
        'pending_requests': 0,
      },
    );
  });

  testWidgets('HomePage reauths on critical logout-forget-device failure',
      (tester) async {
    await saveStableDeviceId(
      'device_me',
      baseUrlOverride: 'https://api.example.com',
    );
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );

    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/auth/devices/device_me') {
        expect(request.method, 'DELETE');
        return http.Response('{"detail":"auth session required"}', 401);
      }
      fail('unexpected request: ${request.url}');
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLogoutForgetDevice(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('HomePage logout skips malformed base-url network dispatch',
      (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com',
          client: client,
        ),
      ),
    );
    await tester.pump();

    await _invokeLogout(tester);

    expect(called, isFalse);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'HomePage rejects malformed device-login deeplink token before auth prompt or network',
      (tester) async {
    var calls = 0;
    var prompts = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          client: client,
          deviceLoginApprovalAuthPrompt: () async {
            prompts++;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    await _invokeHandleUri(
      tester,
      'shamell://device_login?token=not-a-token&label=Demo',
    );

    expect(calls, 0);
    expect(prompts, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Invalid device-login token.'), findsOneWidget);
  });

  testWidgets(
      'HomePage skips malformed base-url network dispatch for device-login approve deeplink',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          baseUrlOverride: 'https://user:pass@api.example.com/root',
          client: client,
          deviceLoginApprovalAuthPrompt: () async => true,
        ),
      ),
    );
    await tester.pump();

    await _invokeHandleUri(
      tester,
      'shamell://device_login?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&label=Demo',
    );

    expect(calls, 0);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('Invalid server URL.'), findsOneWidget);
  });

  testWidgets(
      'HomePage ignores duplicate device-login approve deeplinks while approval is in flight',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          client: client,
          deviceLoginApprovalAuthPrompt: () async => true,
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(HomePage));
    final uri = Uri.parse(
      'shamell://device_login?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&label=Demo',
    );
    final first = state.debugHandleUri(uri) as Future<void>;
    final second = state.debugHandleUri(uri) as Future<void>;

    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pump();
    await first;
    await second;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, 1);
    expect(find.text('Device login approved.'), findsOneWidget);
  });
}
