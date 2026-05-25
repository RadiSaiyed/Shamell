part of '../main.dart';

enum AppMode { auto, user, operator, admin }

const String _appModeRaw =
    String.fromEnvironment('APP_MODE', defaultValue: 'auto');
const String _storedAppModeLegacyKey = 'app_mode';
const String _storedAppModeScopedKeyPrefix = 'app_mode.v2.';
const String _storedAppModeUnknownScope = 'unknown';
const bool _enableDesktopPush =
    bool.fromEnvironment('ENABLE_DESKTOP_PUSH', defaultValue: false);
const bool _debugSkipLogin =
    bool.fromEnvironment('SHAMELL_DEBUG_SKIP_LOGIN', defaultValue: false);
const bool _debugDisableDeferredStartup = bool.fromEnvironment(
  'SHAMELL_DEBUG_DISABLE_DEFERRED_STARTUP',
  defaultValue: false,
);

bool _isPushSupportedPlatform() {
  if (kIsWeb) return true;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return isMobile || _enableDesktopPush;
}

AppMode get currentAppMode {
  switch (_appModeRaw.toLowerCase()) {
    case 'auto':
      return AppMode.auto;
    case 'operator':
      return AppMode.operator;
    case 'admin':
      return AppMode.admin;
    default:
      return AppMode.user;
  }
}

Future<AppMode?> loadStoredAppModePreference({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _storedAppModeScope(
    baseUrlOverride ?? (prefs.getString('base_url') ?? ''),
  );
  final scoped = _parseStoredAppMode(
    (prefs.getString(_storedAppModeScopedKey(scope)) ?? '').trim(),
  );
  if (scoped != null) {
    await prefs.remove(_storedAppModeLegacyKey);
    return scoped;
  }

  final legacy = _parseStoredAppMode(
    (prefs.getString(_storedAppModeLegacyKey) ?? '').trim(),
  );
  if (legacy == null) return null;

  await prefs.remove(_storedAppModeLegacyKey);
  if (_isUnknownStoredAppModeScope(scope)) {
    await prefs.setString(
        _storedAppModeScopedKey(scope), _encodeStoredAppMode(legacy));
    return legacy;
  }
  return null;
}

Future<void> saveStoredAppModePreference(
  AppMode mode, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _storedAppModeScope(
    baseUrlOverride ?? (prefs.getString('base_url') ?? ''),
  );
  await prefs.setString(
      _storedAppModeScopedKey(scope), _encodeStoredAppMode(mode));
  await prefs.remove(_storedAppModeLegacyKey);
}

String _storedAppModeScope(String rawBaseUrl) {
  final normalized = normalizeSecureApiBaseUrl(rawBaseUrl.trim()) ?? '';
  if (normalized.isEmpty) return _storedAppModeUnknownScope;
  return Uri.parse(normalized).origin;
}

bool _isUnknownStoredAppModeScope(String scope) =>
    scope == _storedAppModeUnknownScope;

String _storedAppModeScopedKey(String scope) =>
    '$_storedAppModeScopedKeyPrefix$scope';

String _encodeStoredAppMode(AppMode mode) {
  switch (mode) {
    case AppMode.user:
      return 'user';
    case AppMode.operator:
      return 'operator';
    case AppMode.admin:
      return 'admin';
    case AppMode.auto:
      return 'auto';
  }
}

AppMode? _parseStoredAppMode(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'user':
      return AppMode.user;
    case 'operator':
      return AppMode.operator;
    case 'admin':
      return AppMode.admin;
    case 'auto':
      return AppMode.auto;
    default:
      return null;
  }
}

String appModeLabel(AppMode mode) {
  switch (mode) {
    case AppMode.operator:
      return 'Operator';
    case AppMode.admin:
      return 'Admin';
    case AppMode.auto:
      return 'Hybrid';
    case AppMode.user:
      return 'User';
  }
}

IconData appModeIcon(AppMode mode) {
  switch (mode) {
    case AppMode.operator:
      return Icons.support_agent;
    case AppMode.admin:
      return Icons.admin_panel_settings;
    case AppMode.user:
      return Icons.person_outline;
    case AppMode.auto:
      return Icons.all_inclusive;
  }
}

class _RoleChip extends StatelessWidget {
  final AppMode mode;
  final AppMode current;
  final VoidCallback onTap;
  final bool enabled;
  const _RoleChip(
      {required this.mode,
      required this.current,
      required this.onTap,
      this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isSelected = mode == current;
    String label;
    if (l.isArabic) {
      switch (mode) {
        case AppMode.user:
          label = 'مستخدم';
          break;
        case AppMode.operator:
          label = 'مشغل';
          break;
        case AppMode.admin:
          label = 'مسؤول';
          break;
        case AppMode.auto:
          label = 'هجين';
          break;
      }
    } else {
      label = appModeLabel(mode);
    }
    final icon = appModeIcon(mode);
    final theme = Theme.of(context);
    final isDisabled = !enabled;
    // Distinct tint per mode when selected
    Color tint;
    switch (mode) {
      case AppMode.user:
        tint = theme.colorScheme.primary;
        break;
      case AppMode.operator:
        tint = theme.colorScheme.primary;
        break;
      case AppMode.admin:
        tint = theme.colorScheme.primary;
        break;
      case AppMode.auto:
        tint = theme.colorScheme.primary;
        break;
    }
    final bg = isSelected
        ? tint.withValues(alpha: .12)
        : theme.colorScheme.surface.withValues(alpha: isDisabled ? .4 : .9);
    Color fg;
    if (isDisabled) {
      fg = theme.colorScheme.onSurface.withValues(alpha: .40);
    } else {
      fg = theme.colorScheme.onSurface;
    }
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? tint
                    : theme.dividerColor.withValues(alpha: .6),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: fg))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuperadminChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  const _SuperadminChip(
      {required this.selected, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = !enabled;
    final Color tint = theme.colorScheme.primary;
    final bg = selected
        ? tint.withValues(alpha: .12)
        : theme.colorScheme.surface.withValues(alpha: isDisabled ? .4 : .9);
    final fg = isDisabled
        ? theme.colorScheme.onSurface.withValues(alpha: .40)
        : theme.colorScheme.onSurface;
    return IconButton(
      style: IconButton.styleFrom(
        backgroundColor: bg,
      ),
      onPressed: enabled ? onTap : null,
      icon: Icon(
        Icons.security,
        size: 18,
        color: fg,
      ),
      tooltip: 'Superadmin',
    );
  }
}

bool _isInDndWindow({
  required DateTime now,
  required int startMinutes,
  required int endMinutes,
}) {
  final cur = now.hour * 60 + now.minute;
  final start = startMinutes.clamp(0, 24 * 60 - 1);
  final end = endMinutes.clamp(0, 24 * 60 - 1);
  if (start == end) return true;
  if (start < end) return cur >= start && cur < end;
  return cur >= start || cur < end;
}

@visibleForTesting
NotificationTapTarget? shamellParseSafeNotificationTapTarget(String payload) {
  final raw = payload.trim();
  final tapTarget = parseNotificationTapTargetPayload(raw);
  if (tapTarget == null) return null;
  final canonical = payloadForNotificationTapTarget(tapTarget);
  if (canonical != raw) return null;
  return tapTarget;
}

Future<String?> _loadStoredWalletIdForNotifications(String baseUrl) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final walletId = (await loadStoredWalletId(
              sp: sp,
              baseUrlOverride: baseUrl,
            ) ??
            '')
        .trim();
    if (walletId.isNotEmpty) return walletId;
  } catch (_) {}
  return null;
}

Future<void> _openPaymentsNotificationTarget({
  required NavigatorState nav,
  required String baseUrl,
}) async {
  final walletId = await _loadStoredWalletIdForNotifications(baseUrl);
  if (walletId == null) return;
  final deviceId = await getOrCreateStableDeviceId(
    baseUrlOverride: baseUrl,
  );
  nav.push(
    MaterialPageRoute(
      builder: (_) => PaymentsPage(baseUrl, walletId, deviceId),
    ),
  );
}

Future<void> _openPaymentRequestsNotificationTarget({
  required NavigatorState nav,
  required String baseUrl,
}) async {
  final walletId = await _loadStoredWalletIdForNotifications(baseUrl);
  if (walletId == null) return;
  final deviceId = await getOrCreateStableDeviceId(
    baseUrlOverride: baseUrl,
  );
  nav.push(
    MaterialPageRoute(
      builder: (_) => RequestsPage(
        baseUrl: baseUrl,
        walletId: walletId,
        deviceId: deviceId,
      ),
    ),
  );
}

Future<void> _openRideNotificationTarget({
  required NavigatorState nav,
  required String baseUrl,
  required String? rideId,
}) async {
  final rawRideId = (rideId ?? '').trim();
  final normalizedRideId =
      RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(rawRideId) ? rawRideId : '';
  nav.push(
    MaterialPageRoute(
      builder: (_) => shamellBuildSignedInHome(
        appSurface: shamellActiveAppSurface,
        baseUrlOverride: baseUrl,
        initialRideId: normalizedRideId.isEmpty ? null : normalizedRideId,
        runStartupTasks: false,
      ),
    ),
  );
}

const String _pushTypeChatWakeup = 'chat_wakeup';
const String _pushTypeCallAudio = 'call_audio';
const String _pushTypeCallVideo = 'call_video';
const String _pushTypePaymentRequest = 'payment_request';
const String _pushTypePaymentCredit = 'payment_credit';
const String _pushTypeRideDriverDispatch = 'ride_driver_dispatch';
const String _pushTypeRideRiderUpdate = 'ride_rider_update';
const String _pushTypeRideDriverUpdate = 'ride_driver_update';
const String _pushTypeRideOperatorAlert = 'ride_operator_alert';
final RegExp _remotePushResourceIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,128}$');

String? _remoteRidePushId(Map<Object?, Object?> data) {
  final rawRideId = (data['ride_id'] ?? '').toString().trim();
  if (!_remotePushResourceIdPattern.hasMatch(rawRideId)) {
    return null;
  }
  return rawRideId;
}

String? _remotePushResourceId(Object? value) {
  final raw = (value ?? '').toString().trim();
  if (!_remotePushResourceIdPattern.hasMatch(raw)) {
    return null;
  }
  return raw;
}

String? _remoteRidePushPickupSummary(Map<Object?, Object?> data) {
  final raw = (data['pickup_summary'] ?? '').toString().trim();
  if (raw.isEmpty) {
    return null;
  }
  return compactRidePlaceLabel(raw, maxChars: 80);
}

String? _remoteRidePushStatusLabel(
  RideTripStatus? status, {
  required bool isArabic,
  required bool forDriver,
}) {
  if (status == null) {
    return null;
  }
  switch (status) {
    case RideTripStatus.driverAssigned:
      return isArabic
          ? (forDriver ? 'تم إسناد الرحلة إليك' : 'تم تعيين سائق')
          : (forDriver ? 'Trip assigned to you' : 'Driver assigned');
    case RideTripStatus.driverArriving:
      return isArabic
          ? (forDriver ? 'توجه إلى نقطة الالتقاط' : 'السائق في الطريق')
          : (forDriver ? 'Head to pickup' : 'Driver en route');
    case RideTripStatus.driverArrived:
      return isArabic
          ? (forDriver ? 'وصلت إلى نقطة الالتقاط' : 'وصل السائق')
          : (forDriver ? 'Arrived at pickup' : 'Driver arrived');
    case RideTripStatus.tripStarted:
      return isArabic
          ? (forDriver ? 'بدأت الرحلة' : 'بدأت الرحلة')
          : 'Trip started';
    case RideTripStatus.tripInProgress:
      return isArabic
          ? (forDriver ? 'الرحلة قيد التنفيذ' : 'الرحلة جارية')
          : (forDriver ? 'Trip in progress' : 'Ride in progress');
    case RideTripStatus.tripCompleted:
      return isArabic
          ? (forDriver ? 'اكتملت الرحلة' : 'اكتملت الرحلة')
          : 'Trip completed';
    case RideTripStatus.canceled:
      return isArabic
          ? (forDriver ? 'تم إلغاء الرحلة' : 'تم إلغاء الرحلة')
          : 'Trip cancelled';
    case RideTripStatus.paymentFailed:
      return isArabic ? 'فشل الدفع' : 'Payment failed';
    case RideTripStatus.matching:
      return isArabic
          ? (forDriver ? 'أعيدت الرحلة إلى المطابقة' : 'جاري البحث عن سائق')
          : (forDriver ? 'Trip returned to matching' : 'Matching');
    case RideTripStatus.idle:
    case RideTripStatus.quoteShown:
    case RideTripStatus.rideRequested:
      return isArabic ? 'تحديث الرحلة' : 'Ride update';
  }
}

Future<bool> _showRidePushNotification(Map<Object?, Object?> data) async {
  final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
  final rideId = _remoteRidePushId(data);
  if (rideId == null) {
    return false;
  }
  if (rideDriverBackgroundShouldKickForPushType(rawType)) {
    try {
      await rideDriverScheduleImmediateBackgroundKick();
    } catch (_) {}
  }
  final localeCode = PlatformDispatcher.instance.locale.languageCode;
  final isArabic = localeCode.toLowerCase().startsWith('ar');
  final pickupSummary = _remoteRidePushPickupSummary(data);
  final rawStatus = (data['ride_status'] ?? '').toString();
  final status = rideTripStatusFromWire(rawStatus);
  final rawTitle = (data['title'] ?? '').toString().trim();
  final rawBody = (data['body'] ?? '').toString().trim();

  switch (rawType) {
    case _pushTypeRideDriverDispatch:
      await NotificationService.showIncomingRide(
        rideId: rideId,
        pickupSummary: pickupSummary,
      );
      return true;
    case _pushTypeRideRiderUpdate:
      final label = _remoteRidePushStatusLabel(
            status,
            isArabic: isArabic,
            forDriver: false,
          ) ??
          (isArabic ? 'تحديث الرحلة' : 'Ride update');
      await NotificationService.showRiderTripUpdate(
        rideId: rideId,
        title: isArabic ? 'تحديث الرحلة' : 'Ride update',
        body: pickupSummary == null ? label : '$label • $pickupSummary',
      );
      return true;
    case _pushTypeRideDriverUpdate:
      final title = rawTitle.isNotEmpty
          ? rawTitle
          : (isArabic ? 'تحديث الرحلة' : 'Trip update');
      final body = rawBody.isNotEmpty
          ? rawBody
          : (_remoteRidePushStatusLabel(
                status,
                isArabic: isArabic,
                forDriver: true,
              ) ??
              (isArabic ? 'تم تحديث الرحلة الحالية.' : 'Active trip updated.'));
      await NotificationService.showDriverTripUpdate(
        rideId: rideId,
        title: title,
        body: body,
      );
      return true;
    case _pushTypeRideOperatorAlert:
      final title = rawTitle.isNotEmpty
          ? rawTitle
          : (isArabic ? 'تنبيه العمليات' : 'Ride operations alert');
      final body = rawBody.isNotEmpty
          ? rawBody
          : (_remoteRidePushStatusLabel(
                status,
                isArabic: isArabic,
                forDriver: false,
              ) ??
              (isArabic ? 'تم تحديث رحلة حرجة.' : 'Critical ride updated.'));
      await NotificationService.showOperatorAlert(
        title: title,
        body: body,
        rideId: rideId,
      );
      return true;
    default:
      return false;
  }
}

@visibleForTesting
NotificationTapTarget? shamellRemotePushTapTargetFromData(
  Map<Object?, Object?> data,
) {
  final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
  if (rawType == _pushTypeChatWakeup) {
    return const NotificationTapTarget.chat();
  }
  if (rawType == _pushTypePaymentRequest) {
    final requestId = _remotePushResourceId(data['request_id']);
    if (requestId == null) return null;
    return NotificationTapTarget.paymentRequest(requestId);
  }
  if (rawType == _pushTypePaymentCredit) {
    final walletId = _remotePushResourceId(data['wallet_id']);
    if (walletId == null) return null;
    return NotificationTapTarget.wallet(walletId);
  }
  if (rawType == _pushTypeRideDriverDispatch ||
      rawType == _pushTypeRideRiderUpdate ||
      rawType == _pushTypeRideDriverUpdate ||
      rawType == _pushTypeRideOperatorAlert) {
    final rideId = _remoteRidePushId(data);
    if (rideId == null) return null;
    return NotificationTapTarget.ride(rideId);
  }
  return null;
}

@visibleForTesting
({String callId, String fromDeviceId, String mode, String? fromName})?
    shamellRemoteCallInviteFromData(Map<Object?, Object?> data) {
  final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
  if (rawType != _pushTypeCallAudio && rawType != _pushTypeCallVideo) {
    return null;
  }
  final callId = _remotePushResourceId(data['call_id']);
  final fromDeviceId = _remotePushResourceId(data['from_device_id']);
  if (callId == null || fromDeviceId == null) {
    return null;
  }
  final modeRaw = (data['mode'] ?? '').toString().trim().toLowerCase();
  final mode = (modeRaw == 'audio' || modeRaw == 'video')
      ? modeRaw
      : (rawType == _pushTypeCallAudio ? 'audio' : 'video');
  // `from_name` is plumbed end-to-end (caller's app → BFF → chat_service →
  // FCM). Trim and cap defensively in case the field arrives with stray
  // whitespace or oversized content.
  final rawFromName = (data['from_name'] ?? '').toString().trim();
  final fromName = rawFromName.isEmpty
      ? null
      : rawFromName.characters.take(80).toString();
  return (
    callId: callId,
    fromDeviceId: fromDeviceId,
    mode: mode,
    fromName: fromName,
  );
}

bool _remoteMessageHasVisibleAlert(RemoteMessage message) {
  final notification = message.notification;
  if ((notification?.title ?? '').trim().isNotEmpty ||
      (notification?.body ?? '').trim().isNotEmpty) {
    return true;
  }
  final data = message.data;
  return (data['title'] ?? '').toString().trim().isNotEmpty &&
      (data['body'] ?? '').toString().trim().isNotEmpty;
}

// SyrChat-like "Plugins" visibility toggles (default: enabled).
const String _kShamellPluginShowScan = 'shamell.plugins.show_scan';

Future<String> _loadStoredBaseUrl() async {
  final fallbackBase = normalizeSecureApiBaseUrl(
        const String.fromEnvironment(
          'BASE_URL',
          defaultValue: 'https://api.shamell.online',
        ),
      ) ??
      'https://api.shamell.online';
  try {
    final sp = await SharedPreferences.getInstance();
    final rawStoredBase = sp.getString('base_url') ?? '';
    final storedBase = configuredApiBaseUrlOrFallbackIfUnset(
      storedBaseUrl: rawStoredBase,
      fallbackBaseUrl: fallbackBase,
    );
    if (storedBase != null) return storedBase;
    if (rawStoredBase.trim().isNotEmpty) {
      try {
        await sp.remove('base_url');
      } catch (_) {}
    }
  } catch (_) {}
  return fallbackBase;
}

@visibleForTesting
String? shamellNormalizeBootstrapBaseUrl(String? rawBaseUrl) {
  return shamellNormalizeRuntimeBaseUrl(rawBaseUrl);
}

@visibleForTesting
void shamellSetActiveBootstrapBaseUrl(String? baseUrl) {
  shamellSetActiveRuntimeBaseUrl(baseUrl);
}

@visibleForTesting
String? shamellGetActiveBootstrapBaseUrl() => shamellGetActiveRuntimeBaseUrl();

@visibleForTesting
String shamellResolveBootstrapBaseUrl({
  required String storedBaseUrl,
  String? activeBaseUrl,
}) {
  return shamellResolveRuntimeBaseUrl(
    storedBaseUrl: storedBaseUrl,
    activeBaseUrl: activeBaseUrl,
  );
}

@visibleForTesting
String shamellResolveNotificationBaseUrl({
  required String storedBaseUrl,
  String? activeBaseUrl,
}) {
  return shamellResolveBootstrapBaseUrl(
    storedBaseUrl: storedBaseUrl,
    activeBaseUrl: activeBaseUrl,
  );
}

Future<String> _resolveBootstrapBaseUrl() async {
  final storedBaseUrl = await _loadStoredBaseUrl();
  return shamellResolveBootstrapBaseUrl(
    storedBaseUrl: storedBaseUrl,
    activeBaseUrl: shamellGetActiveBootstrapBaseUrl(),
  );
}

Future<String> shamellResolveRuntimeBootstrapBaseUrl() async {
  return _resolveBootstrapBaseUrl();
}

Future<String> _resolveNotificationBaseUrl() async {
  return _resolveBootstrapBaseUrl();
}

@visibleForTesting
Future<void> Function({String? baseUrlOverride})?
    shamellPushBindingReconcileOverride;

@visibleForTesting
Future<void> shamellReconcileCurrentPushBinding({
  String? baseUrlOverride,
  Future<void> Function()? ensureAccountChatReadyOverride,
  Future<ChatIdentity?> Function({String? baseUrlOverride})?
      loadIdentityOverride,
  PushTokenRegistrar? registerTokenOverride,
  PushTokenUnregistrar? unregisterTokenOverride,
  PushTokenBindingFingerprintLoader? loadPersistedFingerprintOverride,
  PushTokenBindingFingerprintSaver? savePersistedFingerprintOverride,
  PushTokenBindingFingerprintClearer? clearPersistedFingerprintOverride,
  Future<void> Function()? initializeFirebaseOverride,
  Future<NotificationPermissionState> Function()? ensurePermissionOverride,
  Future<String?> Function()? getTokenOverride,
}) async {
  if (!_isPushSupportedPlatform()) {
    return;
  }
  final resolvedBase = normalizeSecureApiBaseUrl(
    ((baseUrlOverride ?? await _resolveNotificationBaseUrl())).trim(),
  );
  if (resolvedBase == null || resolvedBase.isEmpty) {
    await PushTokenManager.clearRegistrationForDevice();
    return;
  }

  ChatService? service;
  final store = ChatLocalStore();
  try {
    final shouldEnsureChatReady =
        ensureAccountChatReadyOverride != null || loadIdentityOverride == null;
    if (shouldEnsureChatReady) {
      try {
        if (ensureAccountChatReadyOverride != null) {
          await ensureAccountChatReadyOverride();
        } else {
          service ??= ChatService(resolvedBase);
          await service!.ensureAccountChatReady();
        }
      } catch (error) {
        debugPrint('PUSH_BINDING_CHAT_READY_ERROR: $error');
        await PushTokenManager.clearRegistrationForDevice();
        return;
      }
    }

    final identity = await (loadIdentityOverride?.call(
          baseUrlOverride: resolvedBase,
        ) ??
        ChatLocalStore().loadIdentity(baseUrlOverride: resolvedBase));
    final deviceId = identity?.id.trim() ?? '';
    if (deviceId.isEmpty) {
      await PushTokenManager.clearRegistrationForDevice();
      return;
    }

    final registerToken = registerTokenOverride ??
        ({
          required String deviceId,
          required String token,
          String? platform,
        }) async {
          service ??= ChatService(resolvedBase);
          await service!.registerPushToken(
            deviceId: deviceId,
            token: token,
            platform: platform,
          );
        };
    final unregisterToken = unregisterTokenOverride ??
        ({
          required String deviceId,
        }) async {
          service ??= ChatService(resolvedBase);
          await service!.unregisterPushToken(deviceId: deviceId);
        };
    final loadPersistedFingerprint = loadPersistedFingerprintOverride ??
        ({
          required String deviceId,
        }) async {
          try {
            return await store.loadPushTokenBindingFingerprint(
              deviceId,
              baseUrlOverride: resolvedBase,
            );
          } catch (error) {
            debugPrint('PUSH_BINDING_FINGERPRINT_LOAD_ERROR: $error');
            return null;
          }
        };
    final savePersistedFingerprint = savePersistedFingerprintOverride ??
        ({
          required String deviceId,
          required String fingerprint,
        }) async {
          try {
            await store.savePushTokenBindingFingerprint(
              deviceId,
              fingerprint,
              baseUrlOverride: resolvedBase,
            );
          } catch (error) {
            debugPrint('PUSH_BINDING_FINGERPRINT_SAVE_ERROR: $error');
          }
        };
    final clearPersistedFingerprint = clearPersistedFingerprintOverride ??
        ({
          required String deviceId,
        }) async {
          try {
            await store.deletePushTokenBindingFingerprint(
              deviceId,
              baseUrlOverride: resolvedBase,
            );
          } catch (error) {
            debugPrint('PUSH_BINDING_FINGERPRINT_CLEAR_ERROR: $error');
          }
        };
    final warmedToken = await PushTokenManager.warmUpPushToken(
      initializeFirebaseOverride: initializeFirebaseOverride,
      ensurePermissionOverride: ensurePermissionOverride,
      getTokenOverride: getTokenOverride,
    );
    if ((warmedToken ?? '').isNotEmpty) {
      final platform = pushTokenPlatformLabel(defaultTargetPlatform);
      final bindingFingerprint = pushTokenBindingFingerprint(
        token: warmedToken!,
        platform: platform,
      );
      final persistedFingerprint =
          (await loadPersistedFingerprint(deviceId: deviceId) ?? '').trim();
      if (persistedFingerprint == bindingFingerprint) {
        return;
      }
      await PushTokenManager.reconcileRegistrationForDevice(
        deviceId: deviceId,
        registerToken: registerToken,
        unregisterToken: unregisterToken,
        loadPersistedBindingFingerprint: loadPersistedFingerprint,
        savePersistedBindingFingerprint: savePersistedFingerprint,
        clearPersistedBindingFingerprint: clearPersistedFingerprint,
        initializeFirebaseOverride: () async {},
        ensurePermissionOverride: () async =>
            NotificationPermissionState.granted,
        getTokenOverride: () async => warmedToken,
      );
      return;
    }
    await PushTokenManager.reconcileRegistrationForDevice(
      deviceId: deviceId,
      registerToken: registerToken,
      unregisterToken: unregisterToken,
      loadPersistedBindingFingerprint: loadPersistedFingerprint,
      savePersistedBindingFingerprint: savePersistedFingerprint,
      clearPersistedBindingFingerprint: clearPersistedFingerprint,
      initializeFirebaseOverride: initializeFirebaseOverride,
      ensurePermissionOverride: ensurePermissionOverride,
      getTokenOverride: getTokenOverride,
    );
  } finally {
    service?.close();
  }
}

Future<void> _reconcilePushBindingOnForeground({
  String? baseUrlOverride,
}) async {
  final override = shamellPushBindingReconcileOverride;
  if (override != null) {
    await override(baseUrlOverride: baseUrlOverride);
    return;
  }
  try {
    await shamellReconcileCurrentPushBinding(baseUrlOverride: baseUrlOverride);
  } catch (error) {
    debugPrint('PUSH_BINDING_RECONCILE_ERROR: $error');
    rethrow;
  }
}

@visibleForTesting
Uri? shamellTrustedWebLaunchBaseForUri(
  Uri uri, {
  String? storedBaseUrl,
}) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.trim().isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  final normalizedStoredBase =
      normalizeSecureApiBaseUrl((storedBaseUrl ?? '').trim());
  if (normalizedStoredBase == null) return null;
  final parsed = Uri.tryParse(normalizedStoredBase);
  if (parsed == null) return null;
  final parsedScheme = parsed.scheme.toLowerCase();
  final parsedPort =
      parsed.hasPort ? parsed.port : (parsedScheme == 'https' ? 443 : 80);
  final uriPort = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
  final sameOrigin = parsedScheme == scheme &&
      parsed.host.toLowerCase() == uri.host.toLowerCase() &&
      parsedPort == uriPort;
  if (!sameOrigin) return null;
  return parsed;
}

@visibleForTesting
Uri? shamellTrustedWebChildUri({
  required String baseUrl,
  required List<String> pathSegments,
  Map<String, String>? queryParameters,
}) {
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (normalizedBase == null) return null;
  final baseUri = Uri.tryParse(normalizedBase);
  if (baseUri == null) return null;
  final cleanSegments = <String>[];
  for (final segment in pathSegments) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return null;
    cleanSegments.add(trimmed);
  }
  return baseUri.replace(
    pathSegments: <String>[
      ...baseUri.pathSegments.where((segment) => segment.trim().isNotEmpty),
      ...cleanSegments,
    ],
    queryParameters: queryParameters == null || queryParameters.isEmpty
        ? null
        : queryParameters,
    fragment: null,
  );
}

@visibleForTesting
LaunchMode shamellLaunchWithSessionFallbackMode(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    return LaunchMode.externalApplication;
  }
  return LaunchMode.platformDefault;
}

@visibleForTesting
bool shamellLaunchWithSessionUsesEmbeddedWebView({
  required bool isWeb,
  required bool hasNavigator,
  required Uri? trustedBaseUri,
  required bool injectSessionForSameOrigin,
}) {
  if (isWeb || !hasNavigator) return false;
  if (trustedBaseUri == null) return false;
  // Only embed when the native session will actually be bridged into a local
  // dev WebView. Otherwise prefer the external browser to avoid extra WebView
  // attack surface without any authenticated-session benefit.
  return injectSessionForSameOrigin;
}

Future<void> _handleNotificationTapTarget(
    NotificationTapTarget tapTarget) async {
  final baseUrl = await _resolveNotificationBaseUrl();
  // If the user isn't logged in yet, store and let HomePage consume it after login.
  try {
    final cookie = await _getCookie(baseUrlOverride: baseUrl);
    if (cookie == null || cookie.isEmpty) {
      await savePendingNotificationTapTarget(
        tapTarget,
        baseUrlOverride: baseUrl,
      );
      return;
    }
  } catch (_) {}

  final nav = _rootNavKey.currentState;
  if (nav == null) return;

  switch (tapTarget.kind) {
    case NotificationTapTargetKind.sync:
      await OfflineQueue.flush(baseUrlOverride: baseUrl);
      return;
    case NotificationTapTargetKind.paymentRequest:
      await _openPaymentRequestsNotificationTarget(nav: nav, baseUrl: baseUrl);
      return;
    case NotificationTapTargetKind.wallet:
      await _openPaymentsNotificationTarget(nav: nav, baseUrl: baseUrl);
      return;
    case NotificationTapTargetKind.ride:
      await _openRideNotificationTarget(
        nav: nav,
        baseUrl: baseUrl,
        rideId: tapTarget.id,
      );
      return;
    case NotificationTapTargetKind.incomingCall:
      final call = tapTarget.call;
      if (call == null) return;
      await NotificationService.cancelIncomingCall();
      await _handleRemoteCallInviteTap(
        callId: call.callId,
        fromDeviceId: call.fromDeviceId,
        mode: call.mode,
      );
      return;
    case NotificationTapTargetKind.chat:
      break;
  }

  // Keep notification-driven navigation coarse and internal-only.
  // Never deep-link into specific chats/messages/groups from payloads.
  if (shamellIsRideRiderSurface()) {
    return;
  }
  nav.push(
    MaterialPageRoute(
      builder: (_) => ShamellChatPage(
        baseUrl: baseUrl,
      ),
    ),
  );
}

/// Route a notification-action tap (Accept / Decline on the incoming-call
/// ringer) without going through the generic tap-target path. Accept reuses
/// the same destination as a body tap; Decline cancels the ringer and emits
/// a structured log so the lifecycle is observable.
///
/// The action handler runs even when the app process was launched cold by the
/// action button itself, which is why we save a pending tap-target before
/// routing — the navigator may not be mounted yet on first frame.
Future<void> _handleNotificationActionTarget(
    String actionId, NotificationTapTarget tapTarget) async {
  if (tapTarget.kind != NotificationTapTargetKind.incomingCall) {
    // Unknown action — fall through to the regular tap path so we don't
    // silently drop legitimate notifications that grow new actions later.
    await _handleNotificationTapTarget(tapTarget);
    return;
  }
  final call = tapTarget.call;
  if (call == null) return;

  switch (actionId) {
    case kShamellIncomingCallAcceptActionId:
      await NotificationService.cancelIncomingCall(reason: StopReason.accept);
      await _handleRemoteCallInviteTap(
        callId: call.callId,
        fromDeviceId: call.fromDeviceId,
        mode: call.mode,
      );
      return;
    case kShamellIncomingCallDeclineActionId:
      await NotificationService.cancelIncomingCall(reason: StopReason.decline);
      assert(() {
        debugPrint(
          'CALL_DECLINE_LOCAL: callId=${call.callId} from=${call.fromDeviceId} mode=${call.mode}',
        );
        return true;
      }());
      // Best-effort: forward the decline to the caller via the BFF so the
      // caller's UI updates immediately instead of waiting for the
      // server-side 30 s timeout. Fire-and-forget — when the app process is
      // not alive at action-tap time, the action callback never runs at all
      // (no `onDidReceiveBackgroundNotificationResponse` registered), in
      // which case the timeout path is the canonical fallback.
      unawaited(_sendCallDeclineSignal(call));
      return;
    default:
      // Unknown action id on a known target — treat as a body tap.
      await _handleNotificationTapTarget(tapTarget);
  }
}

/// POST `/calls/{call_id}/decline` to the BFF so the caller is signalled
/// immediately. Uses the same trusted/pinned HTTP client the rest of the app
/// uses; silently absorbs all errors because the server-side timeout is the
/// canonical fallback when this best-effort path can't reach the BFF.
Future<void> _sendCallDeclineSignal(IncomingCallTap call) async {
  try {
    final baseUrl = await _resolveNotificationBaseUrl();
    final cookie = await _getCookie(baseUrlOverride: baseUrl);
    if (cookie == null || cookie.isEmpty) return;
    final deviceId = await CallSignalingClient.loadDeviceId(
      baseUrlOverride: baseUrl,
    );
    if (deviceId == null || deviceId.isEmpty) return;
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r"/+$"), "")}'
        '/calls/${Uri.encodeComponent(call.callId)}/decline');
    final client = shamellHttpClient();
    try {
      await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Cookie': cookie,
              'x-chat-device-id': deviceId,
            },
            body: jsonEncode(<String, String>{
              'caller_device_id': call.fromDeviceId,
              'reason': 'declined',
            }),
          )
          .timeout(const Duration(seconds: 5));
    } finally {
      client.close();
    }
  } catch (e) {
    assert(() {
      debugPrint('CALL_DECLINE_POST_FAIL: $e');
      return true;
    }());
  }
}

Future<void> _handleRemoteCallInviteTap({
  required String callId,
  required String fromDeviceId,
  required String mode,
  String? initialCallerName,
}) async {
  final baseUrl = await _resolveNotificationBaseUrl();
  try {
    final cookie = await _getCookie(baseUrlOverride: baseUrl);
    if (cookie == null || cookie.isEmpty) {
      return;
    }
  } catch (_) {}
  // The full-screen ringer notification stays sticky until explicitly
  // dismissed. Once the user has tapped through and we're routing into the
  // in-app call screen, the notification's job is done.
  unawaited(NotificationService.cancelIncomingCall());
  final nav = _rootNavKey.currentState;
  if (nav == null) return;
  nav.push(
    MaterialPageRoute(
      builder: (_) => IncomingCallPage(
        baseUrl: baseUrl,
        callId: callId,
        fromDeviceId: fromDeviceId,
        mode: mode,
        // Forward the FCM-side `from_name` (when the caller volunteered
        // one) so the page renders the human name immediately instead of
        // flashing the raw deviceId while the local resolver runs.
        initialCallerName: initialCallerName,
      ),
    ),
  );
}

/// Render a local chat-wakeup notification, respecting the user's per-account
/// notify prefs (enabled / DnD window / sound / vibrate).
///
/// Shared between background and foreground FCM handlers so the user-visible
/// behavior is identical regardless of app process state. Without this, an
/// app in the foreground would receive `chat_wakeup` data-only pushes but
/// never surface them, which is what real-world testers were hitting.
///
/// When a chat surface is currently visible in the foreground process, we
/// downgrade to a haptic + soft system click instead of a full system banner
/// — a flagship messenger would not raise a tray banner while the user is
/// already typing in a chat. The background isolate's separate copy of the
/// presence registry always reads zero, so backgrounded apps still get the
/// full banner.
/// Best-effort caller name lookup for the incoming-call ringer.
///
/// Reads only the local contact + friend-alias caches — no network call —
/// so it is safe (and fast) to run inside the FCM background isolate where
/// auth cookies may not be fully bootstrapped. Priority:
///   1. user-set friend alias (most specific)
///   2. server-resolved contact name (the user-visible name from chat)
///   3. null  →  the ringer falls back to the generic "SyrChat" title
@visibleForTesting
String? shamellResolveCallerDisplayName({
  required String fromDeviceId,
  required String baseUrl,
  Iterable<ChatContact> contacts = const <ChatContact>[],
  Map<String, String> aliases = const <String, String>{},
}) {
  final normalized = fromDeviceId.trim();
  if (normalized.isEmpty) return null;
  final aliased = aliases[normalized]?.trim();
  if (aliased != null && aliased.isNotEmpty) return aliased;
  for (final contact in contacts) {
    if (contact.id.trim() != normalized) continue;
    final name = contact.name?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

Future<String?> _loadCallerDisplayName(String fromDeviceId) async {
  try {
    final baseUrl = await _resolveNotificationBaseUrl();
    final aliasesFuture =
        loadFriendAliases(baseUrlOverride: baseUrl).catchError((_) => const <String, String>{});
    final contactsFuture = ChatLocalStore()
        .loadContacts(baseUrlOverride: baseUrl)
        .catchError((_) => const <ChatContact>[]);
    final results = await Future.wait<Object>([aliasesFuture, contactsFuture])
        .timeout(const Duration(milliseconds: 600), onTimeout: () => const <Object>[]);
    if (results.isEmpty) return null;
    final aliases = results[0] as Map<String, String>;
    final contacts = (results[1] as List).cast<ChatContact>();
    return shamellResolveCallerDisplayName(
      fromDeviceId: fromDeviceId,
      baseUrl: baseUrl,
      aliases: aliases,
      contacts: contacts,
    );
  } catch (_) {
    return null;
  }
}

Future<void> _showChatWakeupNotification(RemoteMessage message) async {
  if (_remoteMessageHasVisibleAlert(message)) return;

  final store = ChatLocalStore();
  final prefs = await store.loadNotifyConfig(
    baseUrlOverride: await _resolveNotificationBaseUrl(),
  );
  if (!prefs.enabled) return;
  if (prefs.dnd &&
      _isInDndWindow(
        now: DateTime.now(),
        startMinutes: prefs.dndStart,
        endMinutes: prefs.dndEnd,
      )) {
    return;
  }

  if (ShamellChatPresenceRegistry.hasActiveChat) {
    if (prefs.sound || prefs.vibrate) {
      await ShamellChatPresenceRegistry.emitInChatArrivalFeedback();
    }
    return;
  }

  final localeCode = PlatformDispatcher.instance.locale.languageCode;
  final isArabic = localeCode.toLowerCase().startsWith('ar');

  await NotificationService.showChatMessage(
    title: 'SyrChat',
    body: isArabic ? 'لديك رسائل جديدة.' : 'You have new messages.',
    playSound: prefs.sound,
    vibrate: prefs.vibrate,
    tapTarget: const NotificationTapTarget.chat(),
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  final firebaseAvailable =
      await NotificationService.isFirebaseRuntimeAvailable();
  if (!firebaseAvailable) {
    return;
  }
  try {
    await NotificationService.initialize();
  } catch (_) {}

  try {
    final data = message.data;
    final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
    if (await _showRidePushNotification(data)) {
      return;
    }
    if (rawType == _pushTypeCallAudio || rawType == _pushTypeCallVideo) {
      // Background incoming call: surface the full-screen ringer so the
      // device wakes (or unlocks momentarily) and rings. The ongoing
      // notification carries an `incomingCall` tap-target so tapping the
      // ringer (or the system's full-screen activity launch) routes through
      // `_handleNotificationTapTarget` into `_handleRemoteCallInviteTap`.
      final callInvite = shamellRemoteCallInviteFromData(data);
      if (callInvite == null) return;
      // Caller name priority:
      //   1. server-provided `from_name` from the FCM payload — covers
      //      callers who aren't in this device's local contact cache,
      //   2. local friend-alias / chat-contact lookup,
      //   3. fall back to the generic title rendered by showIncomingCall.
      final callerName = callInvite.fromName ??
          await _loadCallerDisplayName(callInvite.fromDeviceId);
      await NotificationService.showIncomingCall(
        callId: callInvite.callId,
        fromDeviceId: callInvite.fromDeviceId,
        mode: callInvite.mode,
        callerName: callerName,
      );
      return;
    }
    if (rawType == _pushTypePaymentRequest ||
        rawType == _pushTypePaymentCredit) {
      return;
    }
    if (rawType != _pushTypeChatWakeup) return;
    await _showChatWakeupNotification(message);
  } catch (_) {}
}

final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();

void _handleRemoteMessageTap(RemoteMessage message) {
  try {
    final data = message.data;
    final callInvite = shamellRemoteCallInviteFromData(data);
    if (callInvite != null) {
      unawaited(_handleRemoteCallInviteTap(
        callId: callInvite.callId,
        fromDeviceId: callInvite.fromDeviceId,
        mode: callInvite.mode,
        // The FCM payload's `from_name` is the only way we know the caller
        // name on a cold-start tap (no local notification was built in the
        // foreground process), so forward it as the initial label hint.
        initialCallerName: callInvite.fromName,
      ));
      return;
    }
    final paymentEvent = PaymentEvent.fromFcmData(data);
    if (paymentEvent != null) {
      PaymentEventBus.instance.emit(paymentEvent);
    }
    final tapTarget = shamellRemotePushTapTargetFromData(data);
    if (tapTarget != null) {
      unawaited(_handleNotificationTapTarget(tapTarget));
    }
  } catch (_) {}
}

void _handleForegroundRemoteMessage(RemoteMessage message) {
  try {
    final data = message.data;
    final rawType = (data['type'] ?? '').toString().trim().toLowerCase();

    // Incoming call: even while the app is in the foreground, show the
    // full-screen ringer notification rather than silently switching to the
    // call page. The ongoing notification is the canonical "this call is
    // ringing" surface and gets dismissed by `_handleRemoteCallInviteTap`
    // once the user accepts.
    if (rawType == _pushTypeCallAudio || rawType == _pushTypeCallVideo) {
      final callInvite = shamellRemoteCallInviteFromData(data);
      if (callInvite != null) {
        unawaited(() async {
          final callerName = callInvite.fromName ??
              await _loadCallerDisplayName(callInvite.fromDeviceId);
          await NotificationService.showIncomingCall(
            callId: callInvite.callId,
            fromDeviceId: callInvite.fromDeviceId,
            mode: callInvite.mode,
            callerName: callerName,
          );
        }());
      }
      return;
    }

    // Chat wakeup: same display path as the background handler. The OS does
    // not raise a tray notification for data-only pushes while the app is in
    // the foreground, so we must surface one ourselves — otherwise the user
    // sees + hears nothing on incoming messages, which is what real-world
    // testers hit before this fix.
    if (rawType == _pushTypeChatWakeup) {
      unawaited(_showChatWakeupNotification(message));
      return;
    }

    final paymentEvent = PaymentEvent.fromFcmData(data);
    if (paymentEvent != null) {
      PaymentEventBus.instance.emit(paymentEvent);
      switch (paymentEvent.kind) {
        case PaymentEventKind.credit:
        case PaymentEventKind.refundCredit:
        case PaymentEventKind.topup:
          final walletId = paymentEvent.walletId;
          if (walletId != null) {
            unawaited(NotificationService.showWalletCredit(
              walletId: walletId,
              amountCents: paymentEvent.amountCents ?? 0,
              reference: message.notification?.body,
            ));
          }
          break;
        case PaymentEventKind.request:
          final requestId = paymentEvent.requestId;
          if (requestId != null) {
            unawaited(NotificationService.showIncomingRequest(
              id: requestId,
              amountCents: paymentEvent.amountCents ?? 0,
            ));
          }
          break;
        case PaymentEventKind.debit:
        case PaymentEventKind.unknown:
          break;
      }
    }
  } catch (_) {}
}

Future<void> _initPush() async {
  if (!_isPushSupportedPlatform()) {
    assert(() {
      debugPrint('PUSH_INIT_SKIP: unsupported platform');
      return true;
    }());
    return;
  }
  final firebaseAvailable =
      await NotificationService.isFirebaseRuntimeAvailable();
  if (!firebaseAvailable) {
    assert(() {
      debugPrint('PUSH_INIT_SKIP: firebase unavailable');
      return true;
    }());
    return;
  }
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}
  try {
    final permissionState =
        await NotificationService.ensureNotificationPermission();
    if (notificationPermissionAllowsPush(permissionState)) {
      final baseUrl = await _resolveNotificationBaseUrl();
      ChatService? bootstrapChatService;
      try {
        bootstrapChatService = ChatService(baseUrl);
        await bootstrapChatService.ensureAccountChatReady();
      } catch (error) {
        debugPrint('PUSH_CHAT_READY_ERROR: $error');
        // Best-effort: push binding may still succeed if chat identity already exists.
      } finally {
        bootstrapChatService?.close();
      }
      try {
        await PushTokenManager.warmUpPushToken();
      } catch (error) {
        debugPrint('PUSH_WARMUP_ERROR: $error');
      }
      try {
        FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageTap);
      } catch (_) {}
      try {
        FirebaseMessaging.onMessage.listen(_handleForegroundRemoteMessage);
      } catch (_) {}
      try {
        final initialMessage =
            await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          _handleRemoteMessageTap(initialMessage);
        }
      } catch (_) {}
    }
  } catch (error) {
    debugPrint('PUSH_PERMISSION_OR_BINDING_ERROR: $error');
  }
  try {
    await _reconcilePushBindingOnForeground();
  } catch (error) {
    debugPrint('PUSH_RECONCILE_ERROR: $error');
  }
}

/// Launches a web URL and, for trusted same-origin HTTP(S) endpoints,
/// reuses the current SyrChat session via embedded WebView cookies.
///
/// Session material is never appended to URL query parameters.
Future<void> launchWithSession(Uri uri) async {
  final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
  Uri? trustedBaseUri;
  bool injectSessionForSameOrigin = false;
  if (isHttp) {
    try {
      trustedBaseUri = shamellTrustedWebLaunchBaseForUri(
        uri,
        storedBaseUrl: await _resolveBootstrapBaseUrl(),
      );
      if (trustedBaseUri != null) {
        // webview_flutter can't set HttpOnly/Secure cookies; only allow
        // session bridging for localhost dev to avoid leaking bearer tokens
        // to JS in production WebViews.
        final host = trustedBaseUri.host.toLowerCase();
        final isLocal =
            host == 'localhost' || host == '127.0.0.1' || host == '::1';
        injectSessionForSameOrigin = !kReleaseMode && isLocal;
      }
    } catch (_) {
      trustedBaseUri = null;
      injectSessionForSameOrigin = false;
    }
  }
  try {
    if (isHttp &&
        shamellLaunchWithSessionUsesEmbeddedWebView(
          isWeb: kIsWeb,
          hasNavigator: _rootNavKey.currentState != null,
          trustedBaseUri: trustedBaseUri,
          injectSessionForSameOrigin: injectSessionForSameOrigin,
        )) {
      _rootNavKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => ShamellWebViewPage(
            initialUri: uri,
            baseUri: trustedBaseUri,
            injectSessionForSameOrigin: injectSessionForSameOrigin,
          ),
        ),
      );
      return;
    }
  } catch (_) {}
  await launchUrl(uri, mode: shamellLaunchWithSessionFallbackMode(uri));
}

Future<void> _runStartupTask(
  String name,
  Future<void> Function() task, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  try {
    await task().timeout(timeout);
  } catch (e) {
    assert(() {
      debugPrint('STARTUP_TASK_FAIL[$name]: $e');
      return true;
    }());
  }
}

Future<void> _runDeferredStartup() async {
  await _runStartupTask('push_init', _initPush,
      timeout: const Duration(seconds: 20));

  await _runStartupTask('notification_init', () async {
    await NotificationService.initialize();
    NotificationService.setOnTapHandler(_handleNotificationTapTarget);
    NotificationService.setOnActionHandler(_handleNotificationActionTarget);
    final tapTarget = await NotificationService.getLaunchTapTarget();
    if (tapTarget != null) {
      try {
        await savePendingNotificationTapTarget(
          tapTarget,
          baseUrlOverride: await _resolveNotificationBaseUrl(),
        );
      } catch (_) {}
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_handleNotificationTapTarget(tapTarget));
      });
    }
  });

  await _runStartupTask('offline_queue_init', () async {
    await OfflineQueue.init(baseUrlOverride: await _resolveBootstrapBaseUrl());
  });

  await _runStartupTask('ui_prefs_load', () async {
    await loadUiPrefs();
  }, timeout: const Duration(seconds: 6));

  await _runStartupTask('sound_prefs_load', () async {
    await ShamellSoundEffects.loadPrefs();
    unawaited(ShamellSoundEffects.warmUp());
  }, timeout: const Duration(seconds: 6));

  // After the main UI is mounted, check for a newer published APK and show a
  // non-blocking SnackBar with a "tap to update" action when one is
  // available. No-op on dev builds (APP_RELEASE_ID empty) and rate-limited
  // to once every 6 hours per device.
  await _runStartupTask('app_update_check', () async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rootNavKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      unawaited(maybeShowAppUpdateBanner(ctx));
    });
  }, timeout: const Duration(seconds: 4));
}

class _CompromisedRuntimePage extends StatelessWidget {
  final RuntimeCompromiseState state;

  const _CompromisedRuntimePage({required this.state});

  @override
  Widget build(BuildContext context) {
    final details = state.signals.join(', ');
    return Scaffold(
      backgroundColor: Tokens.darkScaffold,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: Tokens.darkSurface,
            elevation: 10,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 44,
                    color: Tokens.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SyrChat blocked this session.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Tokens.darkOnSurface,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The runtime failed device integrity checks. Restart on a non-compromised device or without active instrumentation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Tokens.darkOnSurfaceSecondary,
                      height: 1.4,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      details,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Tokens.darkOnSurfaceSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> runShamellApp({
  ShamellAppSurface surface = ShamellAppSurface.superapp,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  Perf.init();
  shamellSetActiveAppSurface(surface);
  final runtimeState = await HardwareAttestation.getRuntimeCompromiseState();

  runApp(
    MaterialApp(
      navigatorKey: _rootNavKey,
      home: runtimeState.compromised
          ? _CompromisedRuntimePage(state: runtimeState)
          : SuperApp(appSurface: surface),
    ),
  );

  // Never block first frame on startup integrations/plugins.
  if (!runtimeState.compromised && !_debugDisableDeferredStartup) {
    unawaited(_runDeferredStartup());
  }
}

void main() async {
  await runShamellApp(surface: shamellConfiguredAppSurface);
}

void showBackoff(BuildContext context, http.Response resp) {
  try {
    final j = jsonDecode(resp.body);
    final ms = (j['retry_after_ms'] ?? 0) as int;
    final reasons = (j['reasons'] ?? []).toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Backoff: ${(ms / 1000).toStringAsFixed(0)}s  reasons: $reasons')));
  } catch (_) {
    final ra = resp.headers['retry-after'] ?? '?';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Backoff: Retry-After=$ra')));
  }
}

bool shamellAllowsOpsConsoleSnapshot(AccountPrivilegeSnapshot snapshot) {
  return shamellDashboardAllowsOpsConsoleSnapshot(snapshot);
}

bool shamellAllowsAdminConsoleSnapshot(AccountPrivilegeSnapshot snapshot) {
  return shamellDashboardAllowsAdminConsoleSnapshot(snapshot);
}

bool shamellAllowsCoachBoardingSnapshot(AccountPrivilegeSnapshot snapshot) {
  return shamellDashboardAllowsCoachBoardingSnapshot(snapshot);
}
