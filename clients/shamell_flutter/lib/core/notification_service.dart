import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static Future<void> Function(String payload)? _onTap;

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
  static bool _inited = false;

  static void setOnTapHandler(Future<void> Function(String payload) handler) {
    _onTap = handler;
  }

  static Future<void> initialize() async {
    if (_inited) return;
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: initAndroid);
    await _fln.initialize(init,
        onDidReceiveNotificationResponse: (details) async {
      final payload = details.payload;
      if (payload == null || payload.isEmpty) return;
      final handler = _onTap;
      if (handler != null) {
        try {
          await handler(payload);
        } catch (_) {}
        return;
      }
      try {
        final uri = Uri.parse(payload);
        await launchUrl(uri);
      } catch (_) {
        // Ignore deep-link failures; notification tap should never crash the app.
      }
    });
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.createNotificationChannel(_chatChannelDefault);
    await android?.createNotificationChannel(_chatChannelSound);
    await android?.createNotificationChannel(_chatChannelVibrate);
    await android?.createNotificationChannel(_chatChannelSilent);
    _inited = true;
  }

  static Future<String?> getLaunchPayload() async {
    if (!_inited) await initialize();
    try {
      final details = await _fln.getNotificationAppLaunchDetails();
      if (details == null) return null;
      if (!details.didNotificationLaunchApp) return null;
      final payload = details.notificationResponse?.payload;
      if (payload == null || payload.isEmpty) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  static Future<void> requestAndroidPermission() async {
    // Older plugin versions do not expose requestPermission on Android; noop.
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
      payload: 'sync',
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
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: 'req:' + id);
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
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: 'wallet:' + walletId);
  }

  static Future<void> showIncomingRide({
    required String rideId,
    String? riderPhone,
    String? pickupSummary,
  }) async {
    if (!_inited) await initialize();
    final nid = 3200 + (rideId.hashCode & 0x0FFF);
    final title = 'New taxi ride request';
    final details = <String>[];
    if (riderPhone != null && riderPhone.isNotEmpty)
      details.add('Rider: $riderPhone');
    if (pickupSummary != null && pickupSummary.isNotEmpty)
      details.add(pickupSummary);
    final body =
        details.isEmpty ? 'Tap to open the driver app.' : details.join(' · ');
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: 'ride:' + rideId);
  }

  static Future<void> showChatMessage({
    required String title,
    required String body,
    bool playSound = true,
    bool vibrate = true,
    String? deepLink,
  }) async {
    if (!_inited) await initialize();
    final nid = 3400 + (title.hashCode ^ body.hashCode & 0x0FFF);

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
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: deepLink);
  }

  static Future<void> showSimple({
    required String title,
    required String body,
    String? deepLink,
  }) async {
    if (!_inited) await initialize();
    final nid = 3300 + (title.hashCode ^ body.hashCode & 0x0FFF);
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: deepLink);
  }
}
