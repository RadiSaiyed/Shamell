import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/notification_tap_target.dart';
import 'package:shamell_flutter/core/pending_notification_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;

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
            if (throwOnSecureRead) {
              throw PlatformException(code: 'secure-read-failed');
            }
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
    await clearPendingNotificationPayload();
  });

  test('pending notification payload ignores legacy prefs by default',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kPendingNotificationPayloadLegacyKey: 'shamell://chat?peer_id=abc',
    });

    final tapTarget = await takePendingNotificationTapTarget();
    expect(tapTarget, isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kPendingNotificationPayloadLegacyKey), isNull);
    expect(await takePendingNotificationTapTarget(), isNull);
  });

  test(
      'pending notification payload allows legacy fallback when secure reads fail',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kPendingNotificationPayloadLegacyKey: 'shamell://chat?peer_id=abc',
    });
    throwOnSecureRead = true;

    final tapTarget = await takePendingNotificationTapTarget();
    expect(tapTarget?.kind, NotificationTapTargetKind.chat);
    expect(tapTarget?.id, isNull);
  });

  test('pending notification payload is isolated per canonical api origin',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await savePendingNotificationTapTarget(
        const NotificationTapTarget.paymentRequest('req-one'),
      ),
      isTrue,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(await takePendingNotificationTapTarget(), isNull);

    expect(
      await savePendingNotificationTapTarget(
        const NotificationTapTarget.wallet('wallet-two'),
      ),
      isTrue,
    );

    await sp.setString('base_url', 'https://api.one.example');
    final reqTarget = await takePendingNotificationTapTarget();
    expect(reqTarget?.kind, NotificationTapTargetKind.paymentRequest);
    expect(reqTarget?.id, 'req-one');

    await sp.setString('base_url', 'https://api.two.example');
    final walletTarget = await takePendingNotificationTapTarget();
    expect(walletTarget?.kind, NotificationTapTargetKind.wallet);
    expect(walletTarget?.id, 'wallet-two');
  });

  test(
      'legacy global pending notification payload does not rebind into canonical api origin',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      kPendingNotificationPayloadLegacyKey: 'shamell://chat?peer_id=abc',
    });

    expect(await takePendingNotificationTapTarget(), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kPendingNotificationPayloadLegacyKey), isNull);
  });

  test('pending notification payload saves, takes, and clears securely',
      () async {
    expect(
      await savePendingNotificationTapTarget(
          const NotificationTapTarget.chat()),
      isTrue,
    );

    final chatTarget = await takePendingNotificationTapTarget();
    expect(chatTarget?.kind, NotificationTapTargetKind.chat);
    expect(await takePendingNotificationTapTarget(), isNull);

    await savePendingNotificationTapTarget(const NotificationTapTarget.chat());
    await clearPendingNotificationPayload();
    expect(await takePendingNotificationTapTarget(), isNull);
  });

  test('pending notification payload drops unsafe legacy payloads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kPendingNotificationPayloadLegacyKey: 'https://evil.test/x',
    });

    expect(await takePendingNotificationTapTarget(), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kPendingNotificationPayloadLegacyKey), isNull);
  });

  test('pending notification tap target saves and takes typed values',
      () async {
    const origin = 'https://api.example.com';

    expect(
      await savePendingNotificationTapTarget(
        const NotificationTapTarget.chat(),
        baseUrlOverride: origin,
      ),
      isTrue,
    );
    final chatTarget =
        await takePendingNotificationTapTarget(baseUrlOverride: origin);
    expect(chatTarget?.kind, NotificationTapTargetKind.chat);
    expect(chatTarget?.id, isNull);

    expect(
      await savePendingNotificationTapTarget(
        const NotificationTapTarget.paymentRequest('req_1'),
        baseUrlOverride: origin,
      ),
      isTrue,
    );
    final requestTarget =
        await takePendingNotificationTapTarget(baseUrlOverride: origin);
    expect(requestTarget?.kind, NotificationTapTargetKind.paymentRequest);
    expect(requestTarget?.id, 'req_1');
  });

  test(
      'clearPendingNotificationPayload removes scoped values across all origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await savePendingNotificationTapTarget(
      const NotificationTapTarget.paymentRequest('req-one'),
    );

    await sp.setString('base_url', 'https://api.two.example');
    await savePendingNotificationTapTarget(
      const NotificationTapTarget.wallet('wallet-two'),
    );

    await clearPendingNotificationPayload();

    await sp.setString('base_url', 'https://api.one.example');
    expect(await takePendingNotificationTapTarget(), isNull);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await takePendingNotificationTapTarget(), isNull);
  });

  test(
      'pending notification payload honors explicit baseUrl override over global scope',
      () async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': originTwo,
    });

    expect(
      await savePendingNotificationTapTarget(
        const NotificationTapTarget.paymentRequest('req-one'),
        baseUrlOverride: originOne,
      ),
      isTrue,
    );
    expect(
      await savePendingNotificationTapTarget(
        const NotificationTapTarget.wallet('wallet-two'),
        baseUrlOverride: originTwo,
      ),
      isTrue,
    );

    final requestTarget = await takePendingNotificationTapTarget(
      baseUrlOverride: originOne,
    );
    expect(requestTarget?.kind, NotificationTapTargetKind.paymentRequest);
    expect(requestTarget?.id, 'req-one');
    final walletTarget = await takePendingNotificationTapTarget(
      baseUrlOverride: originTwo,
    );
    expect(walletTarget?.kind, NotificationTapTargetKind.wallet);
    expect(walletTarget?.id, 'wallet-two');

    await savePendingNotificationTapTarget(
      const NotificationTapTarget.paymentRequest('req-clear-one'),
      baseUrlOverride: originOne,
    );
    await savePendingNotificationTapTarget(
      const NotificationTapTarget.wallet('wallet-keep-two'),
      baseUrlOverride: originTwo,
    );
    await clearPendingNotificationPayload(baseUrlOverride: originOne);

    expect(
      await takePendingNotificationTapTarget(baseUrlOverride: originOne),
      isNull,
    );
    final keptWalletTarget = await takePendingNotificationTapTarget(
      baseUrlOverride: originTwo,
    );
    expect(keptWalletTarget?.kind, NotificationTapTargetKind.wallet);
    expect(keptWalletTarget?.id, 'wallet-keep-two');
  });
}
