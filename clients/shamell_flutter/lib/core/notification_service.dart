import 'dart:async' show unawaited;
import 'dart:ui' show Color, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shamell_flutter/firebase_options.dart';

import 'incoming_call_ringer.dart';
import 'notification_tap_target.dart';

export 'notification_tap_target.dart';
export 'incoming_call_ringer.dart' show StopReason;

enum NotificationPermissionState {
  denied,
  granted,
  provisional,
}

@visibleForTesting
NotificationPermissionState notificationPermissionStateForAuthorizationStatus(
  AuthorizationStatus status,
) {
  return switch (status) {
    AuthorizationStatus.authorized => NotificationPermissionState.granted,
    AuthorizationStatus.provisional => NotificationPermissionState.provisional,
    _ => NotificationPermissionState.denied,
  };
}

bool notificationPermissionAllowsPush(NotificationPermissionState state) {
  return state == NotificationPermissionState.granted ||
      state == NotificationPermissionState.provisional;
}

/// Action IDs surfaced on the incoming-call ringer notification. Public so
/// the main bootstrap can branch on them when wiring the action handler.
const String kShamellIncomingCallAcceptActionId = 'shamell_call_accept';
const String kShamellIncomingCallDeclineActionId = 'shamell_call_decline';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static Future<void> Function(NotificationTapTarget tapTarget)? _onTap;
  static Future<void> Function(
    String actionId,
    NotificationTapTarget tapTarget,
  )? _onAction;
  static Future<NotificationPermissionState>? _permissionRequestFuture;
  static Future<bool>? _firebaseAvailabilityFuture;

  @visibleForTesting
  static String? payloadForTapTarget(NotificationTapTarget? tapTarget) {
    return payloadForNotificationTapTarget(tapTarget);
  }

  static NotificationTapTarget? parseTapTargetPayload(String? payload) {
    return parseNotificationTapTargetPayload(payload);
  }

  @visibleForTesting
  static NotificationTapTarget? sanitizeTapTargetPayload(String? payload) {
    return parseTapTargetPayload(payload);
  }

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'offline_sync_channel',
    'Offline Sync',
    description: 'Shows pending offline operations and quick sync',
    importance: Importance.high,
    playSound: false,
  );

  static const AndroidNotificationChannel _chatChannelDefault =
      AndroidNotificationChannel(
    'chat_messages_default',
    'Messages',
    description: 'Chat message notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _chatChannelSound =
      AndroidNotificationChannel(
    'chat_messages_sound',
    'Messages (sound)',
    description: 'Chat message notifications (sound)',
    importance: Importance.high,
    playSound: true,
    enableVibration: false,
  );

  static const AndroidNotificationChannel _chatChannelVibrate =
      AndroidNotificationChannel(
    'chat_messages_vibrate',
    'Messages (vibrate)',
    description: 'Chat message notifications (vibrate)',
    importance: Importance.high,
    playSound: false,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _chatChannelSilent =
      AndroidNotificationChannel(
    'chat_messages_silent',
    'Messages (silent)',
    description: 'Chat message notifications (silent)',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );

  static const AndroidNotificationChannel _paymentRequestChannel =
      AndroidNotificationChannel(
    'payment_requests',
    'Payment requests',
    description: 'Incoming payment request notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _paymentActivityChannel =
      AndroidNotificationChannel(
    'payment_activity',
    'Payments',
    description: 'Incoming payment credit notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _incomingCallAudioChannel =
      AndroidNotificationChannel(
    'incoming_call_audio',
    'Voice calls',
    description: 'Incoming voice call notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _incomingCallVideoChannel =
      AndroidNotificationChannel(
    'incoming_call_video',
    'Video calls',
    description: 'Incoming video call notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // V2 ringer channels: `playSound: false` because audio is owned by the
  // native foreground service `IncomingCallRingerService` which plays the
  // device default ringtone in a continuous loop. The v1 channels above are
  // kept registered so existing user-set channel preferences from prior
  // installs are preserved, but new notifications go to v2 to avoid a double
  // ring (channel single-shot + service loop).
  static const AndroidNotificationChannel _incomingCallAudioChannelV2 =
      AndroidNotificationChannel(
    'incoming_call_audio_v2',
    'Voice calls',
    description: 'Incoming voice call ringer (audio loop via foreground service)',
    importance: Importance.max,
    playSound: false,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _incomingCallVideoChannelV2 =
      AndroidNotificationChannel(
    'incoming_call_video_v2',
    'Video calls',
    description: 'Incoming video call ringer (audio loop via foreground service)',
    importance: Importance.max,
    playSound: false,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _driverDispatchChannel =
      AndroidNotificationChannel(
    'ride_driver_dispatches',
    'Driver dispatches',
    description: 'Driver dispatch notifications with sound',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _driverTripUpdateChannel =
      AndroidNotificationChannel(
    'ride_driver_trip_updates',
    'Driver trip updates',
    description: 'Driver trip status notifications with sound',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _riderTripUpdateChannel =
      AndroidNotificationChannel(
    'ride_rider_trip_updates',
    'Ride trip updates',
    description: 'Rider trip status notifications with sound',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _operatorAlertChannel =
      AndroidNotificationChannel(
    'ride_operator_alerts',
    'Ride operator alerts',
    description: 'Operator alerts for live board and queue changes',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );
  static bool _inited = false;

  static void setOnTapHandler(
    Future<void> Function(NotificationTapTarget tapTarget) handler,
  ) {
    _onTap = handler;
  }

  /// Register a handler invoked when the user clicks an action button on a
  /// notification (e.g. Accept / Decline on the incoming-call ringer). The
  /// `actionId` is one of [kShamellIncomingCallAcceptActionId] /
  /// [kShamellIncomingCallDeclineActionId]; consumers branch on it.
  static void setOnActionHandler(
    Future<void> Function(String actionId, NotificationTapTarget tapTarget)
        handler,
  ) {
    _onAction = handler;
  }

  static Future<void> initialize() async {
    if (_inited) return;
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initDarwin = DarwinInitializationSettings();
    const init = InitializationSettings(
      android: initAndroid,
      iOS: initDarwin,
      macOS: initDarwin,
    );
    await _fln.initialize(init,
        onDidReceiveNotificationResponse: (details) async {
      final tapTarget = sanitizeTapTargetPayload(details.payload);
      if (tapTarget == null) return;
      // Action-button taps (Accept / Decline on the call ringer) arrive on
      // the same response stream; we route them to a separate hook so the
      // bootstrap can branch on intent without re-parsing the payload.
      final actionId = (details.actionId ?? '').trim();
      if (actionId.isNotEmpty) {
        final actionHandler = _onAction;
        if (actionHandler != null) {
          try {
            await actionHandler(actionId, tapTarget);
          } catch (_) {}
        }
        return;
      }
      final handler = _onTap;
      if (handler != null) {
        try {
          await handler(tapTarget);
        } catch (_) {}
      }
    });
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.createNotificationChannel(_chatChannelDefault);
    await android?.createNotificationChannel(_chatChannelSound);
    await android?.createNotificationChannel(_chatChannelVibrate);
    await android?.createNotificationChannel(_chatChannelSilent);
    await android?.createNotificationChannel(_paymentRequestChannel);
    await android?.createNotificationChannel(_paymentActivityChannel);
    await android?.createNotificationChannel(_incomingCallAudioChannel);
    await android?.createNotificationChannel(_incomingCallVideoChannel);
    await android?.createNotificationChannel(_incomingCallAudioChannelV2);
    await android?.createNotificationChannel(_incomingCallVideoChannelV2);
    await android?.createNotificationChannel(_driverDispatchChannel);
    await android?.createNotificationChannel(_driverTripUpdateChannel);
    await android?.createNotificationChannel(_riderTripUpdateChannel);
    await android?.createNotificationChannel(_operatorAlertChannel);
    _inited = true;
  }

  static DarwinNotificationDetails _darwinDetails({required bool playSound}) {
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
    );
  }

  static Future<NotificationTapTarget?> getLaunchTapTarget() async {
    if (!_inited) await initialize();
    try {
      final details = await _fln.getNotificationAppLaunchDetails();
      if (details == null) return null;
      if (!details.didNotificationLaunchApp) return null;
      final tapTarget = sanitizeTapTargetPayload(
        details.notificationResponse?.payload,
      );
      return tapTarget;
    } catch (_) {
      return null;
    }
  }

  static Future<void> requestAndroidPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  @visibleForTesting
  static void resetPermissionRequestCache() {
    _permissionRequestFuture = null;
    _firebaseAvailabilityFuture = null;
  }

  @visibleForTesting
  static bool isMissingFirebaseConfigurationError(Object error) {
    final message = error.toString();
    return message.contains('Failed to load FirebaseOptions from resource') ||
        message.contains(
          'DefaultFirebaseOptions is only provided for Web in this stub',
        ) ||
        message.contains('No Firebase App');
  }

  static Future<bool> isFirebaseRuntimeAvailable({
    Future<void> Function()? initializeFirebaseOverride,
  }) {
    if (initializeFirebaseOverride != null) {
      return _probeFirebaseRuntimeAvailable(
        initializeFirebaseOverride: initializeFirebaseOverride,
      );
    }
    final existing = _firebaseAvailabilityFuture;
    if (existing != null) {
      return existing;
    }
    final future = _probeFirebaseRuntimeAvailable();
    _firebaseAvailabilityFuture = future;
    return future;
  }

  static Future<bool> _probeFirebaseRuntimeAvailable({
    Future<void> Function()? initializeFirebaseOverride,
  }) async {
    try {
      if (Firebase.apps.isEmpty) {
        if (initializeFirebaseOverride != null) {
          await initializeFirebaseOverride();
        } else {
          final explicitOptions = DefaultFirebaseOptions.currentPlatformOrNull;
          if (explicitOptions != null) {
            await Firebase.initializeApp(
              options: explicitOptions,
            );
          } else {
            await Firebase.initializeApp();
          }
        }
      }
      return true;
    } catch (error) {
      if (!isMissingFirebaseConfigurationError(error)) {
        assert(() {
          debugPrint('NotificationService: Firebase bootstrap failed: $error');
          return true;
        }());
      }
      return false;
    }
  }

  static Future<NotificationPermissionState> ensureNotificationPermission({
    Future<void> Function()? requestAndroidPermissionOverride,
    Future<void> Function()? initializeFirebaseOverride,
    Future<NotificationPermissionState> Function()?
        requestRemotePermissionOverride,
    bool? isWebOverride,
    TargetPlatform? targetPlatformOverride,
  }) {
    final existing = _permissionRequestFuture;
    if (existing != null) {
      return existing;
    }
    final future = _requestNotificationPermission(
      requestAndroidPermissionOverride: requestAndroidPermissionOverride,
      initializeFirebaseOverride: initializeFirebaseOverride,
      requestRemotePermissionOverride: requestRemotePermissionOverride,
      isWebOverride: isWebOverride,
      targetPlatformOverride: targetPlatformOverride,
    );
    _permissionRequestFuture = future.catchError((Object error, StackTrace st) {
      _permissionRequestFuture = null;
      throw error;
    });
    return _permissionRequestFuture!;
  }

  static Future<NotificationPermissionState> _requestNotificationPermission({
    Future<void> Function()? requestAndroidPermissionOverride,
    Future<void> Function()? initializeFirebaseOverride,
    Future<NotificationPermissionState> Function()?
        requestRemotePermissionOverride,
    bool? isWebOverride,
    TargetPlatform? targetPlatformOverride,
  }) async {
    final isWeb = isWebOverride ?? kIsWeb;
    final targetPlatform = targetPlatformOverride ?? defaultTargetPlatform;
    if (!isWeb && targetPlatform == TargetPlatform.android) {
      await (requestAndroidPermissionOverride ?? requestAndroidPermission)();
    }
    if (requestRemotePermissionOverride != null &&
        initializeFirebaseOverride == null) {
      return requestRemotePermissionOverride();
    }
    final firebaseAvailable = await isFirebaseRuntimeAvailable(
      initializeFirebaseOverride: initializeFirebaseOverride,
    );
    if (!firebaseAvailable) {
      return NotificationPermissionState.denied;
    }
    if (requestRemotePermissionOverride != null) {
      return requestRemotePermissionOverride();
    }
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return notificationPermissionStateForAuthorizationStatus(
        settings.authorizationStatus,
      );
    } catch (error) {
      if (!isMissingFirebaseConfigurationError(error)) {
        assert(() {
          debugPrint(
            'NotificationService: Firebase permission bootstrap unavailable: $error',
          );
          return true;
        }());
      }
      return NotificationPermissionState.denied;
    }
  }

  static Future<void> showPending(int count) async {
    if (!_inited) await initialize();
    if (count <= 0) {
      await hide();
      return;
    }
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.recommendation,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'sync_now',
          'Sync now',
          showsUserInterface: true,
        )
      ],
    );
    final n = NotificationDetails(android: android);
    await _fln.show(
      2001,
      'Offline pending: $count',
      'Tap to open and sync',
      n,
      payload: payloadForTapTarget(const NotificationTapTarget.sync()),
    );
  }

  static Future<void> hide() async {
    if (!_inited) return;
    await _fln.cancel(2001);
  }

  static Future<void> showIncomingRequest({
    required String id,
    required int amountCents,
    String? fromWallet,
  }) async {
    if (!_inited) await initialize();
    final nid = 3000 + (id.hashCode & 0x0FFF);
    final title = 'New payment request';
    final body = 'Amount: $amountCents' +
        (fromWallet != null && fromWallet.isNotEmpty
            ? ' · From: $fromWallet'
            : '');
    final android = AndroidNotificationDetails(
      _paymentRequestChannel.id,
      _paymentRequestChannel.name,
      channelDescription: _paymentRequestChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: true),
      macOS: _darwinDetails(playSound: true),
    );
    await _fln.show(
      nid,
      title,
      body,
      n,
      payload: payloadForTapTarget(NotificationTapTarget.paymentRequest(id)),
    );
  }

  static Future<void> showWalletCredit({
    required String walletId,
    required int amountCents,
    String? reference,
  }) async {
    if (!_inited) await initialize();
    final nid = 3100 + (walletId.hashCode & 0x0FFF);
    final title = 'Fare credited';
    final body = 'Amount: $amountCents' +
        (reference != null && reference.isNotEmpty ? ' · $reference' : '');
    final android = AndroidNotificationDetails(
      _paymentActivityChannel.id,
      _paymentActivityChannel.name,
      channelDescription: _paymentActivityChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: true),
      macOS: _darwinDetails(playSound: true),
    );
    await _fln.show(
      nid,
      title,
      body,
      n,
      payload: payloadForTapTarget(NotificationTapTarget.wallet(walletId)),
    );
  }

  static Future<void> showIncomingRide({
    required String rideId,
    String? riderPhone,
    String? pickupSummary,
  }) async {
    if (!_inited) await initialize();
    final nid = 3200 + (rideId.hashCode & 0x0FFF);
    final title = 'New ride request';
    final details = <String>[];
    if (riderPhone != null && riderPhone.isNotEmpty)
      details.add('Rider: $riderPhone');
    if (pickupSummary != null && pickupSummary.isNotEmpty)
      details.add(pickupSummary);
    final body = details.isEmpty ? 'Tap to view details.' : details.join(' · ');
    final android = AndroidNotificationDetails(
      _driverDispatchChannel.id,
      _driverDispatchChannel.name,
      channelDescription: _driverDispatchChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.call,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: true),
      macOS: _darwinDetails(playSound: true),
    );
    await _fln.show(
      nid,
      title,
      body,
      n,
      payload: payloadForTapTarget(NotificationTapTarget.ride(rideId)),
    );
  }

  static Future<void> showDriverTripUpdate({
    required String rideId,
    required String title,
    required String body,
  }) async {
    if (!_inited) await initialize();
    final nid = 3250 + (rideId.hashCode & 0x0FFF);
    final android = AndroidNotificationDetails(
      _driverTripUpdateChannel.id,
      _driverTripUpdateChannel.name,
      channelDescription: _driverTripUpdateChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: true),
      macOS: _darwinDetails(playSound: true),
    );
    await _fln.show(
      nid,
      title,
      body,
      n,
      payload: payloadForTapTarget(NotificationTapTarget.ride(rideId)),
    );
  }

  static Future<void> showRiderTripUpdate({
    required String rideId,
    required String title,
    required String body,
  }) async {
    if (!_inited) await initialize();
    final nid = 3275 + (rideId.hashCode & 0x0FFF);
    final android = AndroidNotificationDetails(
      _riderTripUpdateChannel.id,
      _riderTripUpdateChannel.name,
      channelDescription: _riderTripUpdateChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: true),
      macOS: _darwinDetails(playSound: true),
    );
    await _fln.show(
      nid,
      title,
      body,
      n,
      payload: payloadForTapTarget(NotificationTapTarget.ride(rideId)),
    );
  }

  static Future<void> showOperatorAlert({
    required String title,
    required String body,
    String? rideId,
  }) async {
    if (!_inited) await initialize();
    final nid = 3290 + (title.hashCode ^ body.hashCode & 0x0FFF);
    final android = AndroidNotificationDetails(
      _operatorAlertChannel.id,
      _operatorAlertChannel.name,
      channelDescription: _operatorAlertChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: true),
      macOS: _darwinDetails(playSound: true),
    );
    await _fln.show(
      nid,
      title,
      body,
      n,
      payload: payloadForTapTarget(
        rideId == null ? null : NotificationTapTarget.ride(rideId),
      ),
    );
  }

  /// Phone-call style vibration pattern: short pulse + pause + short pulse,
  /// repeated. Format expected by Android: [wait, vibrate, wait, vibrate, …]
  /// in milliseconds. The system loops the pattern while the notification's
  /// ringer is firing — the channel's `enableVibration` flag plus
  /// `vibrationPattern` are what actually drive haptics.
  static final Int64List _phoneRingVibrationPattern =
      Int64List.fromList(<int>[0, 600, 400, 600, 400, 600, 400]);

  /// Notification ID reserved for the single in-flight incoming-call ringer.
  /// Reusing the same id ensures a follow-up call invite replaces the previous
  /// banner instead of stacking — there can only be one incoming call at a
  /// time on the device. Also lets [cancelIncomingCall] target it directly.
  static const int _incomingCallNotificationId = 5100;

  /// Surface an incoming voice/video call as a full-screen ringer that
  /// bypasses the lock screen and stays sticky until accepted or declined.
  ///
  /// Sets `fullScreenIntent: true`, `category: call`, `Importance.max` so
  /// Android treats it as a call (priority ringer, bypasses DnD ringer
  /// suppression on most OEMs, and triggers the lock-screen full-screen
  /// activity). Combined with the `USE_FULL_SCREEN_INTENT` permission and
  /// `showWhenLocked` / `turnScreenOn` on MainActivity, this gives the
  /// WhatsApp-style ringer experience on Android 10+.
  static Future<void> showIncomingCall({
    required String callId,
    required String fromDeviceId,
    required String mode,
    String? callerName,
    bool? isArabicOverride,
  }) async {
    if (!_inited) await initialize();
    final normalizedMode = mode.trim().toLowerCase();
    final isVideo = normalizedMode == 'video';
    final channel =
        isVideo ? _incomingCallVideoChannelV2 : _incomingCallAudioChannelV2;
    // Locale-aware copy so the lockscreen ringer matches the user's primary
    // language. We can be called from the FCM background isolate where
    // `BuildContext` isn't available, so the platform dispatcher locale is
    // the canonical signal (overridable by callers that already know the
    // user's preferred locale).
    final isArabic = isArabicOverride ??
        PlatformDispatcher.instance.locale.languageCode
            .toLowerCase()
            .startsWith('ar');
    final resolvedName = (callerName ?? '').trim();
    final title = resolvedName.isNotEmpty
        ? resolvedName
        : (isArabic ? 'مكالمة واردة' : 'Incoming call');
    final body = isVideo
        ? (isArabic ? 'مكالمة فيديو واردة' : 'Incoming video call')
        : (isArabic ? 'مكالمة صوتية واردة' : 'Incoming voice call');
    final payload = payloadForTapTarget(
      NotificationTapTarget.incomingCall(IncomingCallTap(
        callId: callId,
        fromDeviceId: fromDeviceId,
        mode: isVideo ? 'video' : 'audio',
      )),
    );
    final android = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      // Sound is OWNED by the native foreground-service ringtone loop
      // (`IncomingCallRingerService`), not by the notification channel — the
      // channel-level one-shot would clash with the service's looped audio.
      // Vibration stays on the notification because the system loops the
      // pattern naturally per the channel definition.
      playSound: false,
      enableVibration: true,
      // Phone-ring style cadence: short buzz, brief pause, short buzz, ... so
      // the user can feel an incoming call distinct from a chat message
      // arrival. Pattern is [wait, vibrate, wait, vibrate, ...] in ms.
      vibrationPattern: _phoneRingVibrationPattern,
      // colorized + color paints the notification background with the brand
      // tint while it's ongoing — same affordance phone OEM dialer apps use
      // to signal "this is a call, not a regular alert".
      colorized: true,
      color: const Color.fromARGB(255, 22, 163, 74),
      visibility: NotificationVisibility.public,
      ticker: body,
      actions: <AndroidNotificationAction>[
        // Accept brings the app to the foreground (showsUserInterface=true)
        // so the call screen mounts immediately on tap of the green button.
        AndroidNotificationAction(
          kShamellIncomingCallAcceptActionId,
          isArabic ? 'قبول' : 'Accept',
          showsUserInterface: true,
          cancelNotification: true,
          titleColor: const Color.fromARGB(255, 22, 163, 74),
        ),
        // Decline runs silently in the background; the notification itself
        // is cancelled (autoCancel via cancelNotification: true), and the
        // bootstrap-side handler can fire a best-effort decline signal if a
        // session cookie is available.
        AndroidNotificationAction(
          kShamellIncomingCallDeclineActionId,
          isArabic ? 'رفض' : 'Decline',
          showsUserInterface: false,
          cancelNotification: true,
          titleColor: const Color.fromARGB(255, 220, 38, 38),
        ),
      ],
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: true),
      macOS: _darwinDetails(playSound: true),
    );
    await _fln.show(_incomingCallNotificationId, title, body, n,
        payload: payload);
    // Fire the native looped ringtone alongside the banner. The native side
    // also arms the +30 s missed-call fallback. Done last so a failure here
    // doesn't prevent the visible notification from appearing.
    unawaited(IncomingCallRinger.start(
      callerLabel: resolvedName,
      mode: isVideo ? 'video' : 'audio',
    ));
  }

  /// Dismiss the in-flight incoming-call ringer. Called when the call is
  /// answered in-app or otherwise ends — leaving the sticky notification on
  /// screen would outlive the call, and the foreground-service ringer would
  /// keep playing. [reason] suppresses the +30 s missed-call follow-up
  /// notification when the user actively answered (accept / decline).
  static Future<void> cancelIncomingCall({
    StopReason reason = StopReason.external,
  }) async {
    if (!_inited) await initialize();
    await IncomingCallRinger.stop(reason: reason);
    await _fln.cancel(_incomingCallNotificationId);
  }

  static Future<void> showChatMessage({
    required String title,
    required String body,
    bool playSound = true,
    bool vibrate = true,
    NotificationTapTarget? tapTarget,
  }) async {
    if (!_inited) await initialize();
    final nid = 3400 + (title.hashCode ^ body.hashCode & 0x0FFF);
    final payload = payloadForTapTarget(tapTarget);

    final channel = (playSound && vibrate)
        ? _chatChannelDefault
        : (playSound && !vibrate)
            ? _chatChannelSound
            : (!playSound && vibrate)
                ? _chatChannelVibrate
                : _chatChannelSilent;

    final android = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: playSound,
      enableVibration: vibrate,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: playSound),
      macOS: _darwinDetails(playSound: playSound),
    );
    await _fln.show(nid, title, body, n, payload: payload);
  }

  static Future<void> showSimple({
    required String title,
    required String body,
    NotificationTapTarget? tapTarget,
  }) async {
    if (!_inited) await initialize();
    final nid = 3300 + (title.hashCode ^ body.hashCode & 0x0FFF);
    final payload = payloadForTapTarget(tapTarget);
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(
      android: android,
      iOS: _darwinDetails(playSound: false),
      macOS: _darwinDetails(playSound: false),
    );
    await _fln.show(nid, title, body, n, payload: payload);
  }

  @visibleForTesting
  static bool incomingRideNotificationsPlaySound() =>
      _driverDispatchChannel.playSound;

  @visibleForTesting
  static bool driverTripUpdateNotificationsPlaySound() =>
      _driverTripUpdateChannel.playSound;

  @visibleForTesting
  static bool riderTripUpdateNotificationsPlaySound() =>
      _riderTripUpdateChannel.playSound;

  @visibleForTesting
  static bool operatorAlertsPlaySound() => _operatorAlertChannel.playSound;

  @visibleForTesting
  static bool paymentRequestNotificationsPlaySound() =>
      _paymentRequestChannel.playSound;

  @visibleForTesting
  static bool paymentCreditNotificationsPlaySound() =>
      _paymentActivityChannel.playSound;

  @visibleForTesting
  static bool incomingAudioCallNotificationsPlaySound() =>
      _incomingCallAudioChannel.playSound;

  @visibleForTesting
  static bool incomingVideoCallNotificationsPlaySound() =>
      _incomingCallVideoChannel.playSound;
}
