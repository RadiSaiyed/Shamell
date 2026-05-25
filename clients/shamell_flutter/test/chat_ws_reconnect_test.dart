import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_ws_reconnect.dart';

void main() {
  group('chatWsReconnectDelayMs', () {
    test('step 0 is immediate', () {
      // The first reconnect after a clean disconnect should be
      // instant — a network blip that hands the socket back without a
      // real outage shouldn't cost the user a second of "where's my
      // chat" feedback. iMessage's behaviour, deliberately.
      expect(chatWsReconnectDelayMs(step: 0), 0);
    });

    test('step 1 is 1s, step 2 is 2s, ... doubling', () {
      expect(chatWsReconnectDelayMs(step: 1), 1000);
      expect(chatWsReconnectDelayMs(step: 2), 2000);
      expect(chatWsReconnectDelayMs(step: 3), 4000);
      expect(chatWsReconnectDelayMs(step: 4), 8000);
      expect(chatWsReconnectDelayMs(step: 5), 16000);
    });

    test('caps at maxDelayMs', () {
      // 32 s ≥ 30 s ceiling → clamp.
      expect(chatWsReconnectDelayMs(step: 6), 30000);
      expect(chatWsReconnectDelayMs(step: 7), 30000);
      expect(chatWsReconnectDelayMs(step: 99), 30000);
    });

    test('absurd step doesn\'t crash', () {
      // Without the internal step-cap an attacker (or a bug) feeding
      // step=10_000 would do `1 << 9999` and OOM. Cap at 20 to keep
      // arithmetic bounded.
      expect(
        () => chatWsReconnectDelayMs(step: 1000000),
        returnsNormally,
      );
    });

    test('custom maxDelayMs honoured', () {
      expect(
        chatWsReconnectDelayMs(step: 99, maxDelayMs: 5000),
        5000,
      );
      expect(
        chatWsReconnectDelayMs(step: 2, maxDelayMs: 5000),
        2000,
      );
    });

    test('zero or negative maxDelayMs returns zero', () {
      expect(chatWsReconnectDelayMs(step: 5, maxDelayMs: 0), 0);
      expect(chatWsReconnectDelayMs(step: 5, maxDelayMs: -10), 0);
    });
  });

  group('chatWsReconnectNextStep', () {
    test('counts up while below ceiling', () {
      expect(chatWsReconnectNextStep(currentStep: 0), 1);
      expect(chatWsReconnectNextStep(currentStep: 1), 2);
      expect(chatWsReconnectNextStep(currentStep: 2), 3);
    });

    test('stays at ceiling once delay hits cap', () {
      // Once the delay equals the cap, we keep the step where it is
      // so a long outage doesn't march the counter to infinity. This
      // is mostly a defence against confusing logs (`step=10393`)
      // rather than a correctness issue.
      final n6 = chatWsReconnectNextStep(currentStep: 6);
      expect(chatWsReconnectDelayMs(step: 6), 30000);
      expect(chatWsReconnectDelayMs(step: n6), 30000);
      expect(n6, 6);
    });

    test('negative currentStep treated as zero', () {
      expect(chatWsReconnectNextStep(currentStep: -5), 1);
    });
  });
}
