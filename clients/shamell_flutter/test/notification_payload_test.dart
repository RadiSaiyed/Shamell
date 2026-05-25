import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/notification_tap_target.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:shamell_flutter/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await clearSessionCookie();
  });

  test('parses only coarse internal notification tap targets', () {
    expect(
      shamellParseSafeNotificationTapTarget('sync')?.kind,
      NotificationTapTargetKind.sync,
    );
    expect(
      shamellParseSafeNotificationTapTarget('req:req_1')?.kind,
      NotificationTapTargetKind.paymentRequest,
    );
    expect(
      shamellParseSafeNotificationTapTarget('wallet:wallet-1')?.kind,
      NotificationTapTargetKind.wallet,
    );
    expect(
      shamellParseSafeNotificationTapTarget('ride:ride-1')?.kind,
      NotificationTapTargetKind.ride,
    );
    expect(
      shamellParseSafeNotificationTapTarget('shamell://chat')?.kind,
      NotificationTapTargetKind.chat,
    );
  });

  test('rejects remote or scoped notification payloads', () {
    expect(
        shamellParseSafeNotificationTapTarget('https://evil.test/x'), isNull);
    expect(
      shamellParseSafeNotificationTapTarget(
          'data:text/html,<script>alert(1)</script>'),
      isNull,
    );
    expect(
      shamellParseSafeNotificationTapTarget('shamell://chat?peer=abc'),
      isNull,
    );
    expect(
      shamellParseSafeNotificationTapTarget('shamell://chat/thread-1'),
      isNull,
    );
    expect(shamellParseSafeNotificationTapTarget('req:bad/id'), isNull);
    expect(
      shamellParseSafeNotificationTapTarget('req:${'a' * 129}'),
      isNull,
    );
    expect(shamellParseSafeNotificationTapTarget('   '), isNull);
  });

  test('notification routing prefers active base over stored base', () {
    expect(
      shamellResolveNotificationBaseUrl(
        storedBaseUrl: 'https://api.one.example',
        activeBaseUrl: 'https://api.two.example',
      ),
      'https://api.two.example',
    );
    expect(
      shamellResolveNotificationBaseUrl(
        storedBaseUrl: 'https://api.one.example',
        activeBaseUrl: null,
      ),
      'https://api.one.example',
    );
  });

  test('remote push tap routing maps payment notifications to coarse targets',
      () {
    expect(
      shamellRemotePushTapTargetFromData(
        const <Object?, Object?>{
          'type': 'payment_request',
          'request_id': 'req_42',
        },
      )?.kind,
      NotificationTapTargetKind.paymentRequest,
    );
    expect(
      shamellRemotePushTapTargetFromData(
        const <Object?, Object?>{
          'type': 'payment_credit',
          'wallet_id': 'wallet_42',
        },
      )?.kind,
      NotificationTapTargetKind.wallet,
    );
  });

  test('remote push tap routing parses incoming call payloads', () {
    final call = shamellRemoteCallInviteFromData(
      const <Object?, Object?>{
        'type': 'call_video',
        'call_id': 'call_1',
        'from_device_id': 'dev_1234',
        'mode': 'video',
      },
    );
    expect(call?.callId, 'call_1');
    expect(call?.fromDeviceId, 'dev_1234');
    expect(call?.mode, 'video');
    expect(call?.fromName, isNull); // payload omitted from_name
    expect(
      shamellRemoteCallInviteFromData(
        const <Object?, Object?>{
          'type': 'call_audio',
          'call_id': '',
          'from_device_id': 'dev_1234',
        },
      ),
      isNull,
    );
  });

  test('remote push surfaces from_name when chat_service includes it', () {
    final call = shamellRemoteCallInviteFromData(
      const <Object?, Object?>{
        'type': 'call_audio',
        'call_id': 'c_abc',
        'from_device_id': 'dev_caller',
        'mode': 'audio',
        'from_name': '  Anna Müller  ',
      },
    );
    expect(call?.fromName, 'Anna Müller');
  });

  test('remote push caps from_name at 80 grapheme clusters', () {
    final huge = 'A' * 200;
    final call = shamellRemoteCallInviteFromData(
      <Object?, Object?>{
        'type': 'call_audio',
        'call_id': 'c_x',
        'from_device_id': 'dev_caller',
        'from_name': huge,
      },
    );
    expect(call?.fromName?.length, 80);
  });

  test('remote push treats blank/whitespace from_name as null', () {
    final call = shamellRemoteCallInviteFromData(
      const <Object?, Object?>{
        'type': 'call_audio',
        'call_id': 'c_y',
        'from_device_id': 'dev_caller',
        'from_name': '   ',
      },
    );
    expect(call?.fromName, isNull);
  });

  test('session cookie lookup honors explicit active base over stored base',
      () async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    const token = '0123456789abcdef0123456789abcdef';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originOne);
    await setSessionTokenForBaseUrl(originTwo, token);

    expect(
      await shamellGetCookieForBaseUrl(baseUrlOverride: originTwo),
      '__Host-sa_session=$token',
    );
  });
}
