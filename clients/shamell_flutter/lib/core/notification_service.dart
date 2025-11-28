import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'offline_sync_channel',
    'Offline Sync',
    description: 'Shows pending offline operations and quick sync',
    importance: Importance.high,
    playSound: false,
  );
  static bool _inited = false;

  static Future<void> initialize() async {
    if (_inited) return;
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: initAndroid);
    await _fln.initialize(init,
        onDidReceiveNotificationResponse: (details) async {
      // We rely on deep links handled by uni_links; nothing to do here.
    });
    await _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _inited = true;
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
        const AndroidNotificationAction('sync_now', 'Sync now', showsUserInterface: true)
      ],
    );
    final n = NotificationDetails(android: android);
    await _fln.show(2001, 'Offline pending: $count', 'Tap to open and sync', n, payload: 'sync');
  }

  static Future<void> hide() async {
    if (!_inited) return;
    await _fln.cancel(2001);
  }

  static Future<void> showIncomingRequest({required String id, required int amountCents, String? fromWallet}) async {
    if (!_inited) await initialize();
    final nid = 3000 + (id.hashCode & 0x0FFF);
    final title = 'New payment request';
    final body = 'Amount: $amountCents' + (fromWallet!=null && fromWallet.isNotEmpty? ' · From: $fromWallet' : '');
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: 'req:'+id);
  }

  static Future<void> showWalletCredit({required String walletId, required int amountCents, String? reference}) async {
    if(!_inited) await initialize();
    final nid = 3100 + (walletId.hashCode & 0x0FFF);
    final title = 'Fare credited';
    final body = 'Amount: $amountCents' + (reference!=null && reference.isNotEmpty? ' · $reference' : '');
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: 'wallet:'+walletId);
  }

  static Future<void> showIncomingRide({required String rideId, String? riderPhone, String? pickupSummary}) async {
    if(!_inited) await initialize();
    final nid = 3200 + (rideId.hashCode & 0x0FFF);
    final title = 'New taxi ride request';
    final details = <String>[];
    if (riderPhone != null && riderPhone.isNotEmpty) details.add('Rider: $riderPhone');
    if (pickupSummary != null && pickupSummary.isNotEmpty) details.add(pickupSummary);
    final body = details.isEmpty ? 'Tap to open the driver app.' : details.join(' · ');
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n, payload: 'ride:'+rideId);
  }

  static Future<void> showSimple({required String title, required String body}) async {
    if(!_inited) await initialize();
    final nid = 3300 + (title.hashCode ^ body.hashCode & 0x0FFF);
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    final n = NotificationDetails(android: android);
    await _fln.show(nid, title, body, n);
  }
}
