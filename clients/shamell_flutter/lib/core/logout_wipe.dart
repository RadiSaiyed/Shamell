// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'account_identity_store.dart';
import 'account_privilege_store.dart';
import 'account_snapshot_store.dart';
import 'base_url.dart';
import 'biometric_login.dart';
import 'biometric_preference_store.dart';
import 'capabilities.dart';
import 'chat/chat_models.dart';
import 'chat/chat_service.dart';
import 'device_id.dart';
import 'emergency_contact_store.dart';
import 'ephemeral_voice_file.dart';
import 'favorites_store.dart';
import 'profile_username_store.dart';
import 'friend_annotations_store.dart';
import 'legacy_sensitive_pref_store.dart';
import 'offline_queue.dart';
import 'official_feed_seen_store.dart';
import 'payments/payments_local_store.dart';
import 'pending_notification_store.dart';
import 'plugin_visibility_store.dart';
import 'perf.dart';
import 'privacy_preference_store.dart';
import 'push_token_manager.dart';
import 'runtime_base_scope.dart';
import 'session_cookie_store.dart';
import 'shamell_settings_password_store.dart';
import 'superapp_api.dart';
import 'ui_prefs.dart';
import 'v2_auth_strangler.dart';
import 'v2_chat_strangler.dart';

// Best practice: on logout/switch-account, wipe all account-scoped local data
// to prevent cross-account leakage. Preserve only explicit device preferences.
const Set<String> _kPreservePrefsKeys = <String>{
  // Environment/device prefs.
  'base_url',
  'app_mode',
  kUiLocaleKey,
  kUiTextScaleKey,
  kUiThemeModeKey,

  // SyrChat "Plugins" toggles (device preference).
  'shamell.plugins.show_scan',
};

const String _storedAppModeScopedKeyPrefix = 'app_mode.v2.';
const String _storedAppModeUnknownScope = 'unknown';
const String _historyDirScopedPrefKeyPrefix = 'ph_dir.v2.';
const String _historyKindScopedPrefKeyPrefix = 'ph_kind.v2.';
const String _historyDateScopedPrefKeyPrefix = 'ph_date.v2.';
const String _historyFromScopedPrefKeyPrefix = 'ph_from.v2.';
const String _historyToScopedPrefKeyPrefix = 'ph_to.v2.';
const String _historyUnknownScope = 'unknown';
const String _currencySymbolScopedKeyPrefix = 'currency_symbol.v2.';
const String _currencySymbolUnknownScope = 'unknown';
const String _v2ChatEnabledScopedKeyPrefix = 'v2_chat_strangler_enabled.v2.';
const String _v2ChatUnknownScope = 'unknown';

Map<String, Object> _snapshotPrefs(SharedPreferences sp, Set<String> keys) {
  final out = <String, Object>{};
  for (final k in keys) {
    final v = sp.get(k);
    if (v == null) continue;
    if (v is bool || v is int || v is double || v is String) {
      out[k] = v;
      continue;
    }
    if (v is List<String>) {
      out[k] = List<String>.from(v);
      continue;
    }
  }
  return out;
}

String _effectiveWipeBaseUrl(
  SharedPreferences sp, {
  String? baseUrlOverride,
}) {
  return shamellResolveRuntimeBaseUrl(
    storedBaseUrl: sp.getString('base_url') ?? '',
    activeBaseUrl: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
  );
}

String _currentScopedAppModePrefKey(
  SharedPreferences sp, {
  String? baseUrlOverride,
}) {
  final rawBaseUrl = _effectiveWipeBaseUrl(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  final normalized = normalizeSecureApiBaseUrl(rawBaseUrl) ?? '';
  final scope = normalized.isEmpty
      ? _storedAppModeUnknownScope
      : Uri.parse(normalized).origin;
  return '$_storedAppModeScopedKeyPrefix$scope';
}

String _currentHistoryScope(
  SharedPreferences sp, {
  String? baseUrlOverride,
}) {
  final rawBaseUrl = _effectiveWipeBaseUrl(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  final normalized = normalizeSecureApiBaseUrl(rawBaseUrl) ?? '';
  if (normalized.isEmpty) return _historyUnknownScope;
  return Uri.parse(normalized).origin;
}

Set<String> _currentScopedHistoryPrefKeys(
  SharedPreferences sp, {
  String? baseUrlOverride,
}) {
  final scope = _currentHistoryScope(sp, baseUrlOverride: baseUrlOverride);
  return <String>{
    '$_historyDirScopedPrefKeyPrefix$scope',
    '$_historyKindScopedPrefKeyPrefix$scope',
    '$_historyDateScopedPrefKeyPrefix$scope',
    '$_historyFromScopedPrefKeyPrefix$scope',
    '$_historyToScopedPrefKeyPrefix$scope',
  };
}

String _currentScopedCurrencySymbolPrefKey(
  SharedPreferences sp, {
  String? baseUrlOverride,
}) {
  final rawBaseUrl = _effectiveWipeBaseUrl(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  final normalized = normalizeSecureApiBaseUrl(rawBaseUrl) ?? '';
  final scope = normalized.isEmpty
      ? _currencySymbolUnknownScope
      : Uri.parse(normalized).origin;
  return '$_currencySymbolScopedKeyPrefix$scope';
}

String _currentScopedV2ChatEnabledPrefKey(
  SharedPreferences sp, {
  String? baseUrlOverride,
}) {
  final rawBaseUrl = _effectiveWipeBaseUrl(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  final normalized = normalizeSecureApiBaseUrl(rawBaseUrl) ?? '';
  final scope =
      normalized.isEmpty ? _v2ChatUnknownScope : Uri.parse(normalized).origin;
  return '$_v2ChatEnabledScopedKeyPrefix$scope';
}

Future<void> _restorePrefs(
    SharedPreferences sp, Map<String, Object> snapshot) async {
  for (final e in snapshot.entries) {
    final k = e.key;
    final v = e.value;
    try {
      if (v is bool) {
        await sp.setBool(k, v);
      } else if (v is int) {
        await sp.setInt(k, v);
      } else if (v is double) {
        await sp.setDouble(k, v);
      } else if (v is String) {
        await sp.setString(k, v);
      } else if (v is List<String>) {
        await sp.setStringList(k, v);
      }
    } catch (_) {}
  }
}

const FlutterSecureStorage _shamellSecureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  mOptions:
      MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
);

const FlutterSecureStorage _chatSecureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'chat_secure_store',
  ),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  mOptions:
      MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
);

Future<void> _wipeSecureStoreAll(FlutterSecureStorage sec) async {
  try {
    await sec.deleteAll();
    return;
  } catch (_) {}

  // Fallback: enumerate keys and delete individually.
  try {
    final all = await sec.readAll();
    for (final k in all.keys) {
      try {
        await sec.delete(key: k);
      } catch (_) {}
    }
  } catch (_) {}
}

Future<void> bestEffortUnregisterCurrentChatPushToken({
  required String baseUrl,
  http.Client? client,
  String? baseUrlOverride,
  Future<ChatIdentity?> Function({String? baseUrlOverride})?
      loadIdentityOverride,
  PushTokenUnregistrar? unregisterTokenOverride,
  PushTokenBindingFingerprintClearer? clearPersistedFingerprintOverride,
}) async {
  final normalizedBase =
      normalizeSecureApiBaseUrl((baseUrlOverride ?? baseUrl).trim());
  if (normalizedBase == null) {
    await PushTokenManager.clearRegistrationForDevice();
    return;
  }

  final identity = await (loadIdentityOverride?.call(
        baseUrlOverride: normalizedBase,
      ) ??
      ChatLocalStore().loadIdentity(baseUrlOverride: normalizedBase));
  final deviceId = identity?.id.trim() ?? '';
  if (deviceId.isEmpty) {
    await PushTokenManager.clearRegistrationForDevice();
    return;
  }

  ChatService? service;
  final store = ChatLocalStore();
  try {
    final unregisterToken = unregisterTokenOverride ??
        ({
          required String deviceId,
        }) async {
          service = ChatService(normalizedBase, httpClient: client);
          await service!.unregisterPushToken(deviceId: deviceId);
        };
    final clearPersistedFingerprint = clearPersistedFingerprintOverride ??
        ({
          required String deviceId,
        }) {
          return store.deletePushTokenBindingFingerprint(
            deviceId,
            baseUrlOverride: normalizedBase,
          );
        };
    await PushTokenManager.unregisterForDevice(
      deviceId: deviceId,
      unregisterToken: unregisterToken,
      clearPersistedBindingFingerprint: clearPersistedFingerprint,
    );
  } catch (_) {
    await PushTokenManager.clearRegistrationForDevice(deviceId: deviceId);
  } finally {
    service?.close();
  }
}

Future<void> wipeLocalAccountData({
  bool preserveDevicePrefs = true,
  bool preserveContactsAndChats = false,
  String? baseUrlOverride,
}) async {
  // 1) Clear session material.
  try {
    await clearSessionCookie();
  } catch (_) {}

  // 2) Clear account-scoped snapshot caches stored in secure storage.
  try {
    await wipeCachedAccountSnapshots();
  } catch (_) {}

  // 3) Clear locally cached account privilege state.
  try {
    await clearAccountPrivilegeSnapshot();
  } catch (_) {}

  // 4) Clear secure account identity state.
  //
  // When the user is doing a soft logout ("Logout" rather than
  // "Logout & Forget Device"), we keep the cached identity so that
  // the next login resumes against the same chat deviceId + keypair
  // — re-issuing those would orphan every cached chat session.
  if (!preserveContactsAndChats) {
    try {
      await clearStoredAccountIdentity();
    } catch (_) {}
  }

  // 5) Clear emergency-contact data stored in secure storage.
  if (!preserveContactsAndChats) {
    try {
      await clearEmergencyContactRecord();
    } catch (_) {}
  }

  // 6) Clear favorites stored in secure storage.
  if (!preserveContactsAndChats) {
    try {
      await clearFavoriteItems();
    } catch (_) {}
  }

  // 7) Clear friend annotations stored in secure storage.
  //
  // Friend annotations are the user's per-contact nicknames + colour
  // tags. They live next to the contact list — wiping them on a soft
  // logout would leave the address book intact but strip away the
  // user-set labels, which feels broken to operators.
  if (!preserveContactsAndChats) {
    try {
      await clearFriendAnnotations();
    } catch (_) {}
  }

  // 8) Clear chat/session secrets stored in secure storage.
  //
  // THIS IS THE KEY GUARD for the "logout preserves chats" path:
  // `wipeSecrets` is what drops contacts, message history, and
  // session keys. The "Forget Device" flow still wipes everything.
  if (!preserveContactsAndChats) {
    try {
      await ChatLocalStore().wipeSecrets(
        preservePrefsCryptoKey: preserveDevicePrefs,
      );
    } catch (_) {}
  }

  // 9) Reset chat notification preferences to safe defaults on logout/reauth.
  // Preserving preview/mute state across account boundaries can leak the
  // previous user's privacy posture to the next session on the same device.
  if (!preserveContactsAndChats) {
    try {
      await ChatLocalStore().clearNotifyPreferences();
    } catch (_) {}
  }

  // 10) Clear offline queue persistence and in-memory tasks.
  try {
    await OfflineQueue.clearPersistentState();
  } catch (_) {}

  // 11) Clear leftover ephemeral voice files from chat/call flows.
  try {
    await purgeEphemeralVoiceFiles();
  } catch (_) {}

  // 12) Clear local payments recents/templates persisted in secure storage.
  try {
    await clearPaymentsLocalData();
  } catch (_) {}

  // 13) Clear pending notification deep-link payloads.
  try {
    await clearPendingNotificationPayload();
  } catch (_) {}

  // 14) Clear legacy sensitive compatibility state migrated out of prefs.
  try {
    await clearLegacySensitivePrefState();
  } catch (_) {}

  // 15) Clear local privacy-policy preferences.
  try {
    await clearPrivacyPreferenceState();
  } catch (_) {}

  // 16) Clear migrated legacy official-feed seen state.
  try {
    await clearOfficialFeedSeenMap();
  } catch (_) {}

  // 17) Clear persisted server capability gates.
  try {
    final sp = await SharedPreferences.getInstance();
    await ShamellCapabilities.clearPersistedState(sp: sp);
  } catch (_) {}

  // 18) Clear biometric login token material across all origins.
  try {
    await clearAllBiometricLoginTokens();
  } catch (_) {}

  // 19) Clear local password hash state across all origins.
  try {
    await clearStoredLocalPasswordHash();
  } catch (_) {}

  // 19a) Clear the persisted auth username (the @-handle the user typed
  // at signup/signin). Always wiped — even on a soft "keep my chats"
  // logout — because leaving it would surface the previous account's
  // handle under the Profile / Me hero of the next session.
  try {
    await clearProfileUsername();
  } catch (_) {}

  // 20) Clear persisted V2 auth overrides; visible V2 chat state is preserved
  // per current origin via the SharedPreferences snapshot below.
  try {
    final sp = await SharedPreferences.getInstance();
    await V2AuthStranglerStore.clearEnabledOverride(sp: sp);
  } catch (_) {}

  // 21) Clear persisted mini-app local KV state.
  try {
    final sp = await SharedPreferences.getInstance();
    await SuperappAPI.clearPersistedState(sp: sp);
  } catch (_) {}

  // 22) Migrate the stable install identifier out of legacy prefs before clear.
  try {
    await loadStableDeviceId(
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
  } catch (_) {}

  // 23) Migrate the biometric-login preference off legacy prefs before clear.
  try {
    await loadRequireBiometricsPreference(
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
  } catch (_) {}

  // 24) Clear SharedPreferences, preserving only device prefs.
  try {
    final sp = await SharedPreferences.getInstance();
    final scopedPluginScanKey = currentScopedPluginVisibilityPrefKey(
      key: 'shamell.plugins.show_scan',
      sp: sp,
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
    final scopedAppModeKey = _currentScopedAppModePrefKey(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedHistoryKeys = _currentScopedHistoryPrefKeys(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedCurrencySymbolKey = _currentScopedCurrencySymbolPrefKey(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedV2ChatEnabledKey = _currentScopedV2ChatEnabledPrefKey(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedChatThemesKey = shamellCurrentScopedChatThemesPrefKey(
      sp: sp,
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
    final scopedHideServiceThreadKey =
        shamellCurrentScopedHideServiceNotificationsThreadPrefKey(
      sp: sp,
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
    final scopedChatWorkspaceKeys = shamellCurrentScopedChatWorkspacePrefKeys(
      sp: sp,
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
    final scopedV2ChatBenchmarksKey =
        V2ChatStranglerStore.currentBenchmarksPrefKey(
      sp: sp,
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
    final scopedV2AuthBenchmarksKey =
        V2AuthStranglerStore.currentBenchmarksPrefKey(
      sp: sp,
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
    final scopedMetricsRemoteKey = Perf.currentRemotePreferenceKey(
      sp: sp,
      baseUrlOverride: baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
    );
    final scopedStableDeviceIdPrefKey = kIsWeb
        ? currentStableDeviceIdScopedPrefKey(
            sp: sp,
            baseUrlOverride:
                baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
          )
        : null;
    final scopedBiometricPrefKey = kIsWeb
        ? currentRequireBiometricsScopedPrefKey(
            sp: sp,
            baseUrlOverride:
                baseUrlOverride ?? shamellGetActiveRuntimeBaseUrl(),
          )
        : null;
    final preserveKeys = <String>{
      ..._kPreservePrefsKeys,
      scopedPluginScanKey,
      scopedAppModeKey,
      ...scopedHistoryKeys,
      scopedCurrencySymbolKey,
      scopedV2ChatEnabledKey,
      scopedChatThemesKey,
      scopedHideServiceThreadKey,
      ...scopedChatWorkspaceKeys,
      scopedV2ChatBenchmarksKey,
      scopedV2AuthBenchmarksKey,
      scopedMetricsRemoteKey,
      if (kIsWeb) ...<String>{
        kStableDeviceIdPrefKey,
        if (scopedStableDeviceIdPrefKey != null &&
            scopedStableDeviceIdPrefKey.isNotEmpty)
          scopedStableDeviceIdPrefKey,
        kRequireBiometricsPrefKey,
        if (scopedBiometricPrefKey != null && scopedBiometricPrefKey.isNotEmpty)
          scopedBiometricPrefKey,
      },
    };
    final preserved = preserveDevicePrefs
        ? _snapshotPrefs(sp, preserveKeys)
        : <String, Object>{};
    await sp.clear();
    if (preserved.isNotEmpty) {
      await _restorePrefs(sp, preserved);
    }
  } catch (_) {}

  // 25) Clear in-memory push registration state across account boundaries.
  try {
    await PushTokenManager.clearRegistrationForDevice();
  } catch (_) {}
}

/// "Forget this device" local wipe:
/// - clears all SharedPreferences (including stable device id)
/// - wipes secure storage (biometric tokens, local password, session, chat secrets)
Future<void> wipeLocalForForgetDevice() async {
  await wipeLocalAccountData(preserveDevicePrefs: false);
  await _wipeSecureStoreAll(_shamellSecureStore);
  await _wipeSecureStoreAll(_chatSecureStore);
}
