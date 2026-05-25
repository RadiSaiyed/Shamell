import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/notification_tap_target.dart';

void main() {
  group('payload roundtrips', () {
    test('sync', () {
      final p = payloadForNotificationTapTarget(
        const NotificationTapTarget.sync(),
      );
      expect(p, 'sync');
      final back = parseNotificationTapTargetPayload(p);
      expect(back?.kind, NotificationTapTargetKind.sync);
    });

    test('chat root', () {
      final p = payloadForNotificationTapTarget(
        const NotificationTapTarget.chat(),
      );
      expect(p, isNotNull);
      final back = parseNotificationTapTargetPayload(p);
      expect(back?.kind, NotificationTapTargetKind.chat);
    });

    test('paymentRequest with id roundtrip preserves id', () {
      final tap = const NotificationTapTarget.paymentRequest('req_abc-123');
      final p = payloadForNotificationTapTarget(tap);
      expect(p, isNotNull);
      final back = parseNotificationTapTargetPayload(p);
      expect(back?.kind, NotificationTapTargetKind.paymentRequest);
      expect(back?.id, 'req_abc-123');
    });

    test('wallet roundtrip', () {
      final tap = const NotificationTapTarget.wallet('wal_99');
      final back =
          parseNotificationTapTargetPayload(payloadForNotificationTapTarget(tap));
      expect(back?.kind, NotificationTapTargetKind.wallet);
      expect(back?.id, 'wal_99');
    });

    test('ride roundtrip', () {
      final tap = const NotificationTapTarget.ride('ride_007');
      final back =
          parseNotificationTapTargetPayload(payloadForNotificationTapTarget(tap));
      expect(back?.kind, NotificationTapTargetKind.ride);
      expect(back?.id, 'ride_007');
    });

    test('incomingCall audio roundtrip preserves callId + fromDeviceId + mode', () {
      final tap = NotificationTapTarget.incomingCall(
        const IncomingCallTap(
          callId: 'call_a-b-c.42',
          fromDeviceId: 'dev_xyz_001',
          mode: 'audio',
        ),
      );
      final raw = payloadForNotificationTapTarget(tap);
      expect(raw, isNotNull);
      final back = parseNotificationTapTargetPayload(raw);
      expect(back?.kind, NotificationTapTargetKind.incomingCall);
      expect(back?.call?.callId, 'call_a-b-c.42');
      expect(back?.call?.fromDeviceId, 'dev_xyz_001');
      expect(back?.call?.mode, 'audio');
    });

    test('incomingCall video roundtrip preserves mode', () {
      final tap = NotificationTapTarget.incomingCall(
        const IncomingCallTap(
          callId: 'c1',
          fromDeviceId: 'd1',
          mode: 'video',
        ),
      );
      final back = parseNotificationTapTargetPayload(
        payloadForNotificationTapTarget(tap),
      );
      expect(back?.call?.mode, 'video');
    });
  });

  group('rejection', () {
    test('null payload yields null', () {
      expect(parseNotificationTapTargetPayload(null), isNull);
      expect(parseNotificationTapTargetPayload(''), isNull);
    });

    test('overlong payload rejected', () {
      final huge = 'sync${'X' * 300}';
      expect(parseNotificationTapTargetPayload(huge), isNull);
    });

    test('unknown scheme/host rejected for incoming-call lookalikes', () {
      expect(
        parseNotificationTapTargetPayload('shamell://otherhost/audio?id=x'),
        isNull,
      );
      expect(
        parseNotificationTapTargetPayload('https://call/audio?id=x'),
        isNull,
      );
    });

    test('incomingCall with invalid mode rejected', () {
      // Hand-build the URI directly to bypass formatter.
      expect(
        parseNotificationTapTargetPayload(
          'shamell://call/voice?id=abc&from=def',
        ),
        isNull,
      );
    });

    test('incomingCall with id chars outside allowlist rejected', () {
      expect(
        parseNotificationTapTargetPayload(
          'shamell://call/audio?id=bad%20id&from=ok_dev',
        ),
        isNull,
      );
    });

    test('canonicalizePendingNotificationPayload preserves the canonical token', () {
      const sample = 'shamell://chat';
      expect(canonicalizePendingNotificationPayload(sample), sample);
      expect(canonicalizePendingNotificationPayload('  sync  '), 'sync');
    });
  });
}
