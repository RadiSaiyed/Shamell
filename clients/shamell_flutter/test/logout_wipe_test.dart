import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/account_snapshot_store.dart';
import 'package:shamell_flutter/core/biometric_login.dart';
import 'package:shamell_flutter/core/biometric_preference_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/emergency_contact_store.dart';
import 'package:shamell_flutter/core/ephemeral_voice_file.dart';
import 'package:shamell_flutter/core/favorites_store.dart';
import 'package:shamell_flutter/core/friend_annotations_store.dart';
import 'package:shamell_flutter/core/history_page.dart';
import 'package:shamell_flutter/core/legacy_sensitive_pref_store.dart';
import 'package:shamell_flutter/core/logout_wipe.dart';
import 'package:shamell_flutter/core/offline_queue.dart';
import 'package:shamell_flutter/core/official_feed_seen_store.dart';
import 'package:shamell_flutter/core/payments/payments_local_store.dart';
import 'package:shamell_flutter/core/notification_service.dart';
import 'package:shamell_flutter/core/pending_notification_store.dart';
import 'package:shamell_flutter/core/perf.dart';
import 'package:shamell_flutter/core/plugin_visibility_store.dart';
import 'package:shamell_flutter/core/privacy_preference_store.dart';
import 'package:shamell_flutter/core/push_token_manager.dart';
import 'package:shamell_flutter/core/payments/currency_symbol_store.dart';
import 'package:shamell_flutter/core/shamell_settings_password_store.dart';
import 'package:shamell_flutter/core/shamell_user_id.dart';
import 'package:shamell_flutter/core/superapp_api.dart';
import 'package:shamell_flutter/core/v2_auth_strangler.dart';
import 'package:shamell_flutter/core/v2_chat_strangler.dart';
import 'package:shamell_flutter/main.dart';

const bool _forceLegacyChat = bool.fromEnvironment(
  'SHAMELL_FORCE_LEGACY_CHAT',
  defaultValue: true,
);
const String _v2ChatEnvFlagRaw = String.fromEnvironment(
  'V2_CHAT_STRANGLER',
  defaultValue: 'false',
);

bool _parseV2ChatFlag(String raw) {
  switch (raw.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
    case 'enabled':
      return true;
    default:
      return false;
  }
}

bool get _defaultV2ChatEnabled =>
    _forceLegacyChat ? false : _parseV2ChatFlag(_v2ChatEnvFlagRaw);

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
    shamellSetActiveBootstrapBaseUrl(null);
    await PushTokenManager.resetForTesting();
  });

  test('wipeLocalAccountData preserves device prefs but wipes SyrChat-ID',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'last_login_name': 'Alice',
      'last_login_phone': '+1234567',
      'official.default_account_id': 'official-1',
      'official.default_account_name': 'Ops Console',
      'contact_shortlist': <String>['{"name":"Bob","phone":"+222"}'],
      kOfficialFeedSeenLegacyKey: '{"official-1":"2026-03-13T00:00:00Z"}',
      kPrivacyFriendVerificationPrefKey: false,
      kPrivacyMomentsAllowStrangersTenPostsPrefKey: false,
      kPrivacyMomentsUpdateRemindersPrefKey: false,
      kPrivacyStatusVisibleToOthersPrefKey: false,
      'phone': '+963955000111',
    });
    secStore.clear();
    await loadLegacyProfileSummary();
    await loadLegacyDefaultOfficialAccountContext();
    await loadLegacyContactShortlistEntries();
    await loadOfficialFeedSeenMap();
    await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey);
    await saveRequireBiometricsPreference(true);
    expect(
      await setBiometricLoginTokenForBaseUrl(
        'https://api.example.com',
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      isTrue,
    );
    expect(
      await setBiometricLoginTokenForBaseUrl(
        'https://api.other.example',
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
      isTrue,
    );
    await saveStableDeviceId('stable123');
    expect(
      await saveStoredLocalPasswordHash('local-password-hash'),
      isTrue,
    );
    final spForOtherOrigin = await SharedPreferences.getInstance();
    await spForOtherOrigin.setString('base_url', 'https://api.other.example');
    expect(
      await saveStoredLocalPasswordHash('local-password-hash-other'),
      isTrue,
    );
    await spForOtherOrigin.setString('base_url', 'https://api.example.com');
    const caps = ShamellCapabilities(
      chat: true,
      payments: true,
      friends: true,
      moments: false,
      officialAccounts: true,
      channels: false,
      serviceNotifications: true,
      paymentsPhoneTargets: false,
    );
    final spBeforeWipe = await SharedPreferences.getInstance();
    await caps.persistForBaseUrl(spBeforeWipe, 'https://api.example.com');
    await saveScopedPluginVisibilityPreference(
      key: 'shamell.plugins.show_scan',
      value: false,
    );
    await saveStoredAppModePreference(AppMode.operator, sp: spBeforeWipe);
    await saveHistoryFilterPreferences(
      baseUrl: 'https://api.example.com',
      dir: 'out',
      kind: 'transfer',
      date: 'custom',
      fromDate: DateTime.utc(2026, 3, 1),
      toDate: DateTime.utc(2026, 3, 15),
      sp: spBeforeWipe,
    );
    await saveStoredCurrencySymbol(
      'USD',
      baseUrl: 'https://api.example.com',
      sp: spBeforeWipe,
    );
    await Perf.saveRemotePreference(true, sp: spBeforeWipe);
    final chatStore = ChatLocalStore();
    await chatStore.setNotifyEnabled(
      false,
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.setNotifyPreview(
      true,
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.setNotifySound(
      false,
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.setNotifyVibrate(
      false,
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.setNotifyDndEnabled(
      true,
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.setNotifyDndSchedule(
      startMinutes: 60,
      endMinutes: 120,
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.setNotifyEnabled(
      false,
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.setNotifyPreview(
      true,
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.setNotifySound(
      false,
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.setNotifyVibrate(
      false,
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.setNotifyDndEnabled(
      true,
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.setNotifyDndSchedule(
      startMinutes: 180,
      endMinutes: 240,
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.saveChatThemes(
      <String, String>{
        'peer-1': 'dark',
        'grp:group-1': 'green',
      },
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.saveHideServiceNotificationsThread(
      true,
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.savePinnedChatOrder(
      <String>['grp:group-1', 'u1'],
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.savePinnedMessages(
      <String, Set<String>>{
        'u1': <String>{'m1', 'm2'},
      },
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.saveRecalledMessageIds(
      <String>{'m2', 'm3'},
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.saveArchivedGroups(
      <String>{'group-1', 'group-2'},
      baseUrlOverride: 'https://api.example.com',
    );
    await chatStore.saveChatThemes(
      <String, String>{
        'peer-2': 'green',
      },
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.saveHideServiceNotificationsThread(
      true,
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.savePinnedChatOrder(
      <String>['u2'],
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.savePinnedMessages(
      <String, Set<String>>{
        'u2': <String>{'mx'},
      },
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.saveRecalledMessageIds(
      <String>{'mx'},
      baseUrlOverride: 'https://api.other.example',
    );
    await chatStore.saveArchivedGroups(
      <String>{'group-9'},
      baseUrlOverride: 'https://api.other.example',
    );
    await saveStoredShamellUserId('ABCDEFGH');
    await saveStoredWalletId('w1');
    await saveCachedHomeSnapshotRaw('{"wallet":{"wallet_id":"w1"}}');
    await saveCachedWalletSnapshotRaw(
      'w1',
      '{"wallet":{"wallet_id":"w1","balance_cents":7}}',
    );
    await saveAccountPrivilegeSnapshot(
      roles: <String>['admin'],
      isSuperadmin: true,
    );
    await saveEmergencyContactRecord(name: 'Alice', phone: '+1234567');
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'saved message', 'msgId': 'm1'},
    ]);
    await saveFriendAliases(<String, String>{'u1': 'Alice'});
    await saveFriendTags(<String, String>{'u1': 'vip'});
    await saveCloseFriendIds(<String>{'u1'});
    await savePaymentRecents(<String>['wallet-2', 'wallet-3']);
    await saveBillTemplateEntries(<String>[
      '{"biller_code":"electricity","account":"123"}',
    ]);
    await saveSeenPaymentRequestIds(<String>['req-1', 'req-2']);
    await savePendingNotificationTapTarget(const NotificationTapTarget.chat());
    await OfflineQueue.enqueue(
      OfflineTask(
        id: 'q1',
        method: 'POST',
        url: 'https://api.example.com/pay',
        headers: <String, String>{
          'X-Device-ID': 'd1',
          'Idempotency-Key': 'logout-wipe-test-q1',
        },
        body: '{"amount":7,"to":"u1"}',
        tag: 'payments_transfer',
        createdAt: 1,
      ),
    );
    await V2AuthStranglerStore.setV2AuthEnabled(false, sp: spBeforeWipe);
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.v2,
      elapsedMs: 120,
      success: true,
      sp: spBeforeWipe,
    );
    await V2ChatStranglerStore.setEnabled(false, sp: spBeforeWipe);
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.v2,
      elapsedMs: 140,
      success: true,
      sp: spBeforeWipe,
    );
    await spBeforeWipe.setString('base_url', 'https://api.other.example');
    await V2AuthStranglerStore.setV2AuthEnabled(false, sp: spBeforeWipe);
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.legacy,
      elapsedMs: 240,
      success: false,
      sp: spBeforeWipe,
    );
    await V2ChatStranglerStore.setEnabled(false, sp: spBeforeWipe);
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.legacy,
      elapsedMs: 260,
      success: false,
      sp: spBeforeWipe,
    );
    final superappOne = SuperappAPI.light(
      baseUrl: 'https://api.example.com',
      walletId: 'wallet-1',
    );
    final superappTwo = SuperappAPI.light(
      baseUrl: 'https://api.other.example',
      walletId: 'wallet-2',
    );
    await superappOne.kvSetString('draft', 'keep private');
    await superappTwo.kvSetString('draft', 'keep private other');
    await spBeforeWipe.setString('base_url', 'https://api.example.com');

    await wipeLocalAccountData(preserveDevicePrefs: true);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('base_url'), 'https://api.example.com');
    expect(sp.getString(kStableDeviceIdPrefKey), isNull);
    expect(await loadStableDeviceId(), 'stable123');
    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: true,
      ),
      isFalse,
    );
    expect(await loadStoredAppModePreference(sp: sp), AppMode.operator);
    final historyPrefs = await loadHistoryFilterPreferences(
      baseUrl: 'https://api.example.com',
      sp: sp,
    );
    expect(historyPrefs.dir, 'out');
    expect(historyPrefs.kind, 'transfer');
    expect(historyPrefs.date, 'custom');
    expect(historyPrefs.fromDate, DateTime.utc(2026, 3, 1));
    expect(historyPrefs.toDate, DateTime.utc(2026, 3, 15));
    expect(
      await loadStoredCurrencySymbol(
        baseUrl: 'https://api.example.com',
        sp: sp,
      ),
      'USD',
    );
    expect(await Perf.loadRemotePreference(sp: sp), isTrue);
    final currentNotify = await chatStore.loadNotifyConfig(
      baseUrlOverride: 'https://api.example.com',
    );
    expect(currentNotify.enabled, isTrue);
    expect(currentNotify.preview, isFalse);
    expect(currentNotify.sound, isTrue);
    expect(currentNotify.vibrate, isTrue);
    expect(currentNotify.dnd, isFalse);
    expect(currentNotify.dndStart, 22 * 60);
    expect(currentNotify.dndEnd, 8 * 60);
    final otherNotify = await chatStore.loadNotifyConfig(
      baseUrlOverride: 'https://api.other.example',
    );
    expect(otherNotify.enabled, isTrue);
    expect(otherNotify.preview, isFalse);
    expect(otherNotify.sound, isTrue);
    expect(otherNotify.vibrate, isTrue);
    expect(otherNotify.dnd, isFalse);
    expect(otherNotify.dndStart, 22 * 60);
    expect(otherNotify.dndEnd, 8 * 60);
    expect(sp.getBool(kRequireBiometricsPrefKey), isNull);
    expect(await loadRequireBiometricsPreference(), isTrue);
    expect(
      await getBiometricLoginTokenForBaseUrl('https://api.example.com'),
      isNull,
    );
    expect(
      await getBiometricLoginTokenForBaseUrl('https://api.other.example'),
      isNull,
    );
    expect(await loadStoredLocalPasswordHash(), isNull);
    await sp.setString('base_url', 'https://api.other.example');
    expect(await loadStoredLocalPasswordHash(), isNull);
    await sp.setString('base_url', 'https://api.example.com');
    expect(
      (await ShamellCapabilities.loadForBaseUrl(
        'https://api.example.com',
        sp: sp,
      ))
          .officialAccounts,
      isFalse,
    );
    expect(
      (await ShamellCapabilities.loadForBaseUrl(
        'https://api.example.com',
        sp: sp,
      ))
          .serviceNotifications,
      isFalse,
    );
    expect(sp.getString(kOfficialFeedSeenLegacyKey), isNull);
    expect(await loadOfficialFeedSeenMap(), isEmpty);
    expect(sp.getBool(kPrivacyFriendVerificationPrefKey), isNull);
    expect(
      sp.getBool(kPrivacyMomentsAllowStrangersTenPostsPrefKey),
      isNull,
    );
    expect(sp.getBool(kPrivacyMomentsUpdateRemindersPrefKey), isNull);
    expect(sp.getBool(kPrivacyStatusVisibleToOthersPrefKey), isNull);
    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );

    // Account-scoped identifier must not survive logout.
    expect(sp.getString(kShamellUserIdPrefKey), isNull);
    expect(await loadStoredShamellUserId(), isNull);

    // Account/session scoped prefs should be wiped.
    expect(sp.getString('wallet_id'), isNull);
    expect(await loadStoredWalletId(), isNull);
    expect(sp.getStringList('roles'), isNull);
    expect(sp.getBool('is_superadmin'), isNull);
    expect(sp.getString('phone'), isNull);
    expect((await loadLegacyProfileSummary()).name, isEmpty);
    expect((await loadLegacyProfileSummary()).phone, isEmpty);
    expect(
      (await loadLegacyDefaultOfficialAccountContext()).accountId,
      isEmpty,
    );
    expect(await loadLegacyContactShortlistEntries(), isEmpty);
    final privileges = await loadAccountPrivilegeSnapshot();
    expect(privileges.roles, isEmpty);
    expect(privileges.isSuperadmin, isFalse);
    expect(await loadCachedHomeSnapshotRaw(), isNull);
    expect(await loadCachedWalletSnapshotRaw('w1'), isNull);
    final emergency = await loadEmergencyContactRecord();
    expect(emergency.name, isEmpty);
    expect(emergency.phone, isEmpty);
    expect(await loadFavoriteItems(), isEmpty);
    expect(await loadFriendAliases(), isEmpty);
    expect(await loadFriendTags(), isEmpty);
    expect(await loadCloseFriendIds(), isEmpty);
    expect(await loadPaymentRecents(), isEmpty);
    expect(await loadBillTemplateEntries(), isEmpty);
    expect(await loadSeenPaymentRequestIds(), isEmpty);
    expect(await takePendingNotificationTapTarget(), isNull);
    expect(OfflineQueue.pending(), isEmpty);
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isTrue);
    final currentAuthBenchmarks =
        await V2AuthStranglerStore.readBenchmarks(sp: sp);
    expect(currentAuthBenchmarks.hasAnySamples, isTrue);
    expect(currentAuthBenchmarks.v2.attempts, 1);
    expect(await V2ChatStranglerStore.isEnabled(sp: sp), isFalse);
    final currentChatBenchmarks =
        await V2ChatStranglerStore.readBenchmarks(sp: sp);
    expect(currentChatBenchmarks.hasAnySamples, isTrue);
    expect(currentChatBenchmarks.v2.attempts, greaterThan(0));
    expect(
      await chatStore.loadChatThemes(
          baseUrlOverride: 'https://api.example.com'),
      <String, String>{
        'peer-1': 'dark',
        'grp:group-1': 'green',
      },
    );
    expect(
      await chatStore.loadHideServiceNotificationsThread(
        baseUrlOverride: 'https://api.example.com',
      ),
      isTrue,
    );
    expect(
      await chatStore.loadPinnedChatOrder(
        baseUrlOverride: 'https://api.example.com',
      ),
      <String>['grp:group-1', 'u1'],
    );
    expect(
      await chatStore.loadPinnedMessages(
        baseUrlOverride: 'https://api.example.com',
      ),
      <String, Set<String>>{
        'u1': <String>{'m1', 'm2'},
      },
    );
    expect(
      await chatStore.loadRecalledMessageIds(
        baseUrlOverride: 'https://api.example.com',
      ),
      <String>{'m2', 'm3'},
    );
    expect(
      await chatStore.loadArchivedGroups(
        baseUrlOverride: 'https://api.example.com',
      ),
      <String>{'group-1', 'group-2'},
    );
    await sp.setString('base_url', 'https://api.other.example');
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isTrue);
    expect((await V2AuthStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
        isFalse);
    expect(await V2ChatStranglerStore.isEnabled(sp: sp), _defaultV2ChatEnabled);
    expect((await V2ChatStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
        isFalse);
    expect(
      await chatStore.loadChatThemes(
          baseUrlOverride: 'https://api.other.example'),
      isEmpty,
    );
    expect(
      await chatStore.loadHideServiceNotificationsThread(
        baseUrlOverride: 'https://api.other.example',
      ),
      isFalse,
    );
    expect(
      await chatStore.loadPinnedChatOrder(
        baseUrlOverride: 'https://api.other.example',
      ),
      isEmpty,
    );
    expect(
      await chatStore.loadPinnedMessages(
        baseUrlOverride: 'https://api.other.example',
      ),
      isEmpty,
    );
    expect(
      await chatStore.loadRecalledMessageIds(
        baseUrlOverride: 'https://api.other.example',
      ),
      isEmpty,
    );
    expect(
      await chatStore.loadArchivedGroups(
        baseUrlOverride: 'https://api.other.example',
      ),
      isEmpty,
    );
    expect(await superappOne.kvGetString('draft'), isNull);
    expect(await superappTwo.kvGetString('draft'), isNull);
    expect(
      sp.getKeys().where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
  });

  test(
      'bestEffortUnregisterCurrentChatPushToken unregisters current chat device and clears push binding',
      () async {
    final registrations = <String>[];
    final chatStore = ChatLocalStore();
    await chatStore.savePushTokenBindingFingerprint(
      'chat_dev_1',
      pushTokenBindingFingerprint(
        token: 'tok-1',
        platform: 'android',
      ),
      baseUrlOverride: 'https://api.example.com',
    );
    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: Object(),
      deviceId: 'chat_dev_1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        registrations.add('register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {},
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    final unregistrations = <String>[];
    await bestEffortUnregisterCurrentChatPushToken(
      baseUrl: 'https://api.example.com',
      loadIdentityOverride: ({String? baseUrlOverride}) async =>
          const ChatIdentity(
        id: 'chat_dev_1',
        publicKeyB64: 'pk',
        privateKeyB64: 'sk',
        fingerprint: 'fp',
      ),
      unregisterTokenOverride: ({
        required String deviceId,
      }) async {
        unregistrations.add(deviceId);
      },
    );

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: Object(),
      deviceId: 'chat_dev_1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        registrations.add('reregister:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {},
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    expect(unregistrations, <String>['chat_dev_1']);
    expect(
      registrations,
      <String>[
        'register:chat_dev_1|tok-1|android',
        'reregister:chat_dev_1|tok-1|android',
      ],
    );
    expect(
      await chatStore.loadPushTokenBindingFingerprint(
        'chat_dev_1',
        baseUrlOverride: 'https://api.example.com',
      ),
      isNull,
    );
  });

  test('wipeLocalAccountData purges leftover ephemeral voice files', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
    });
    secStore.clear();

    final file = await writeEphemeralVoiceFile(
      Uint8List.fromList(const <int>[1, 2, 3]),
      stem: 'logout_voice',
    );
    final dir = file.parent;
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    expect(await file.exists(), isTrue);

    await wipeLocalAccountData(preserveDevicePrefs: true);

    expect(await file.exists(), isFalse);
    expect(await dir.exists(), isFalse);
  });

  test(
      'wipeLocalAccountData preserves active runtime-scoped device prefs over stored scope',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.one.example',
    });
    secStore.clear();

    final sp = await SharedPreferences.getInstance();
    await saveScopedPluginVisibilityPreference(
      key: 'shamell.plugins.show_scan',
      value: false,
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveScopedPluginVisibilityPreference(
      key: 'shamell.plugins.show_scan',
      value: true,
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.v2,
      elapsedMs: 111,
      success: true,
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.legacy,
      elapsedMs: 222,
      success: false,
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    shamellSetActiveBootstrapBaseUrl('https://api.two.example');

    await wipeLocalAccountData(preserveDevicePrefs: true);

    expect(sp.getString('base_url'), 'https://api.one.example');
    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: false,
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: true,
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isTrue,
    );

    final activeBenchmarks = await V2AuthStranglerStore.readBenchmarks(
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );
    expect(activeBenchmarks.hasAnySamples, isTrue);
    expect(activeBenchmarks.legacy.attempts, 1);

    final storedScopeBenchmarks = await V2AuthStranglerStore.readBenchmarks(
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    expect(storedScopeBenchmarks.hasAnySamples, isFalse);
  });
}
