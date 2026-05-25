import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/payment_event_bus.dart';

import 'fakes/fake_payment_event_gateway.dart';

void main() {
  group('FakePaymentEventGateway', () {
    test('records start calls in order with full parameters', () async {
      final gateway = FakePaymentEventGateway();
      addTearDown(gateway.dispose);

      await gateway.start(
        baseUrl: 'https://api.example.com',
        walletId: 'wallet_demo',
        deviceId: null,
      );
      await gateway.start(
        baseUrl: 'https://api.example.com',
        walletId: 'wallet_demo',
        deviceId: 'dev_42',
      );

      expect(gateway.startCalls, hasLength(2));
      expect(gateway.startCalls[0].baseUrl, 'https://api.example.com');
      expect(gateway.startCalls[0].walletId, 'wallet_demo');
      expect(gateway.startCalls[0].deviceId, isNull);
      expect(gateway.startCalls[1].deviceId, 'dev_42');
    });

    test('counts reconnectNow and stop invocations', () async {
      final gateway = FakePaymentEventGateway();
      addTearDown(gateway.dispose);

      gateway.reconnectNow();
      gateway.reconnectNow();
      await gateway.stop();

      expect(gateway.reconnectCalls, 2);
      expect(gateway.stopCalls, 1);
    });

    test('emit delivers events to subscribers on the broadcast stream',
        () async {
      final gateway = FakePaymentEventGateway();
      addTearDown(gateway.dispose);

      final received = <PaymentEvent>[];
      final sub = gateway.stream.listen(received.add);
      addTearDown(sub.cancel);

      gateway.emit(const PaymentEvent(
        kind: PaymentEventKind.credit,
        walletId: 'wallet_demo',
        amountCents: 1234,
        currency: 'USD',
        source: PaymentEventSource.sse,
      ));

      // Allow microtask drain.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first.kind, PaymentEventKind.credit);
      expect(received.first.amountCents, 1234);
    });

    test('emit drops silently after dispose so late callers do not throw',
        () async {
      final gateway = FakePaymentEventGateway();
      await gateway.dispose();

      // Must not throw.
      gateway.emit(const PaymentEvent(
        kind: PaymentEventKind.debit,
        walletId: 'wallet_demo',
      ));
    });
  });

  // The production [DefaultPaymentEventGateway] is a thin pass-through to
  // [PaymentEventBus.instance.stream] and [PaymentEventStream.instance]'s
  // lifecycle methods. We deliberately don't unit-test it here because:
  //   1. The interface contract is enforced by the static `implements
  //      PaymentEventGateway` declaration.
  //   2. Touching the singleton bus from a unit test instantiates a
  //      `_dispatchSideEffects` listener that calls into the haptic /
  //      sound method channels, which aren't bound in a vanilla
  //      `test/` context (the bus is designed for `testWidgets`
  //      environments where the binding is initialized).
  //   3. Widget tests in `history_page_session_guard_test.dart` already
  //      exercise the production gateway path indirectly when run with
  //      no explicit override.
}
