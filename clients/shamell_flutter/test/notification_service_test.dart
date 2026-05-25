import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    NotificationService.resetPermissionRequestCache();
  });

  test('NotificationService maps typed tap targets to coarse payloads', () {
    expect(
      NotificationService.payloadForTapTarget(
          const NotificationTapTarget.chat()),
      'shamell://chat',
    );
    expect(
      NotificationService.payloadForTapTarget(
          const NotificationTapTarget.sync()),
      'sync',
    );
    expect(
      NotificationService.payloadForTapTarget(
        const NotificationTapTarget.paymentRequest('req_1'),
      ),
      'req:req_1',
    );
    expect(
      NotificationService.payloadForTapTarget(
        const NotificationTapTarget.wallet('wallet-1'),
      ),
      'wallet:wallet-1',
    );
    expect(
      NotificationService.payloadForTapTarget(
        const NotificationTapTarget.ride('ride-1'),
      ),
      'ride:ride-1',
    );
    expect(NotificationService.payloadForTapTarget(null), isNull);
  });

  test('NotificationService parses typed tap targets from safe payloads', () {
    expect(
      NotificationService.parseTapTargetPayload('sync')?.kind,
      NotificationTapTargetKind.sync,
    );
    expect(
      NotificationService.parseTapTargetPayload('shamell://chat?peer_id=abc')
          ?.kind,
      NotificationTapTargetKind.chat,
    );
    expect(
      NotificationService.parseTapTargetPayload('req:req_1')?.kind,
      NotificationTapTargetKind.paymentRequest,
    );
    expect(
      NotificationService.parseTapTargetPayload('req:req_1')?.id,
      'req_1',
    );
    expect(
      NotificationService.parseTapTargetPayload('wallet:wallet-1')?.kind,
      NotificationTapTargetKind.wallet,
    );
    expect(
      NotificationService.parseTapTargetPayload('ride:ride-1')?.kind,
      NotificationTapTargetKind.ride,
    );
  });

  test('NotificationService sanitizes payloads to typed tap targets', () {
    expect(
      NotificationService.sanitizeTapTargetPayload('shamell://chat')?.kind,
      NotificationTapTargetKind.chat,
    );
    expect(
      NotificationService.sanitizeTapTargetPayload('shamell://chat?peer_id=abc')
          ?.kind,
      NotificationTapTargetKind.chat,
    );
    expect(
      NotificationService.payloadForTapTarget(
        NotificationService.sanitizeTapTargetPayload('shamell://chat/thread-1'),
      ),
      'shamell://chat',
    );
    expect(
      NotificationService.sanitizeTapTargetPayload('req:req_1')?.kind,
      NotificationTapTargetKind.paymentRequest,
    );
    expect(
      NotificationService.sanitizeTapTargetPayload('req:req_1')?.id,
      'req_1',
    );
  });

  test('NotificationService drops remote or foreign notification payloads', () {
    expect(
      NotificationService.sanitizeTapTargetPayload('https://evil.test/x'),
      isNull,
    );
    expect(
      NotificationService.sanitizeTapTargetPayload('shamell://official/shop_1'),
      isNull,
    );
  });

  test(
      'NotificationService requests Android notification permission through local notifications plugin',
      () async {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'requestNotificationsPermission') {
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await NotificationService.requestAndroidPermission();

    expect(
      calls.any((call) => call.method == 'requestNotificationsPermission'),
      isTrue,
    );
  });

  test(
      'NotificationService reuses a single notification consent flow across bootstrap and chat callers',
      () async {
    final calls = <String>[];

    final first = await NotificationService.ensureNotificationPermission(
      requestAndroidPermissionOverride: () async {
        calls.add('android');
      },
      requestRemotePermissionOverride: () async {
        calls.add('remote');
        return NotificationPermissionState.provisional;
      },
      isWebOverride: false,
      targetPlatformOverride: TargetPlatform.android,
    );
    final second = await NotificationService.ensureNotificationPermission(
      requestAndroidPermissionOverride: () async {
        calls.add('android_again');
      },
      requestRemotePermissionOverride: () async {
        calls.add('remote_again');
        return NotificationPermissionState.denied;
      },
      isWebOverride: false,
      targetPlatformOverride: TargetPlatform.android,
    );

    expect(first, NotificationPermissionState.provisional);
    expect(second, NotificationPermissionState.provisional);
    expect(calls, <String>['android', 'remote']);
    expect(notificationPermissionAllowsPush(second), isTrue);
  });

  test(
      'NotificationService treats missing Firebase Android resources as push unavailable',
      () async {
    var remoteCalls = 0;

    final state = await NotificationService.ensureNotificationPermission(
      requestAndroidPermissionOverride: () async {},
      initializeFirebaseOverride: () async {
        throw PlatformException(
          code: 'Exception',
          message:
              'java.lang.Exception: Failed to load FirebaseOptions from resource. Check that you have defined values.xml correctly.',
        );
      },
      requestRemotePermissionOverride: () async {
        remoteCalls += 1;
        return NotificationPermissionState.granted;
      },
      isWebOverride: false,
      targetPlatformOverride: TargetPlatform.android,
    );

    expect(state, NotificationPermissionState.denied);
    expect(remoteCalls, 0);
  });

  test('NotificationService keeps driver alert channels audible', () {
    expect(NotificationService.incomingRideNotificationsPlaySound(), isTrue);
    expect(
      NotificationService.driverTripUpdateNotificationsPlaySound(),
      isTrue,
    );
    expect(NotificationService.riderTripUpdateNotificationsPlaySound(), isTrue);
    expect(NotificationService.operatorAlertsPlaySound(), isTrue);
    expect(NotificationService.paymentRequestNotificationsPlaySound(), isTrue);
    expect(NotificationService.paymentCreditNotificationsPlaySound(), isTrue);
    expect(
        NotificationService.incomingAudioCallNotificationsPlaySound(), isTrue);
    expect(
        NotificationService.incomingVideoCallNotificationsPlaySound(), isTrue);
  });

  test('NotificationService posts operator alerts on the operator channel',
      () async {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await NotificationService.showOperatorAlert(
      title: 'Trip update',
      body: 'Bab Touma to Malki: now Driver arriving.',
      rideId: 'ride_123',
    );

    final showCall = calls.lastWhere((call) => call.method == 'show');
    final showArgs = showCall.arguments.toString();
    expect(showArgs, contains('ride_operator_alerts'));
    expect(showArgs, contains('Trip update'));
    expect(showArgs, contains('ride:ride_123'));
  });
}
