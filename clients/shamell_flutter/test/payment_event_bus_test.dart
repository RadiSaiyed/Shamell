import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/payment_event_bus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaymentEvent.kindFromWire', () {
    test('maps FCM payment_credit + server transfer.credit to credit', () {
      expect(
        PaymentEvent.kindFromWire('payment_credit'),
        PaymentEventKind.credit,
      );
      expect(
        PaymentEvent.kindFromWire('transfer.credit'),
        PaymentEventKind.credit,
      );
      expect(
        PaymentEvent.kindFromWire('wallet.credit'),
        PaymentEventKind.credit,
      );
    });

    test('maps transfer.debit and wallet.debit to debit', () {
      expect(
        PaymentEvent.kindFromWire('transfer.debit'),
        PaymentEventKind.debit,
      );
      expect(
        PaymentEvent.kindFromWire('wallet.debit'),
        PaymentEventKind.debit,
      );
    });

    test('maps payment_request and request.created to request', () {
      expect(
        PaymentEvent.kindFromWire('payment_request'),
        PaymentEventKind.request,
      );
      expect(
        PaymentEvent.kindFromWire('request.created'),
        PaymentEventKind.request,
      );
    });

    test('maps wallet.topup to topup', () {
      expect(
        PaymentEvent.kindFromWire('wallet.topup'),
        PaymentEventKind.topup,
      );
    });

    test('maps refund.credit and refund.applied to refundCredit', () {
      expect(
        PaymentEvent.kindFromWire('refund.credit'),
        PaymentEventKind.refundCredit,
      );
      expect(
        PaymentEvent.kindFromWire('refund.applied'),
        PaymentEventKind.refundCredit,
      );
    });

    test('falls back to unknown for unrecognised wire types', () {
      expect(PaymentEvent.kindFromWire(''), PaymentEventKind.unknown);
      expect(PaymentEvent.kindFromWire(null), PaymentEventKind.unknown);
      expect(
        PaymentEvent.kindFromWire('something.else'),
        PaymentEventKind.unknown,
      );
    });

    test('is case-insensitive on wire type', () {
      expect(
        PaymentEvent.kindFromWire('Transfer.Credit'),
        PaymentEventKind.credit,
      );
    });
  });

  group('PaymentEvent.fromFcmData', () {
    test('parses a typical payment_credit FCM payload', () {
      final event = PaymentEvent.fromFcmData(<Object?, Object?>{
        'type': 'payment_credit',
        'wallet_id': 'w-123',
        'amount_cents': 2950,
        'currency': 'SYP',
        'txn_id': 'txn-abc',
      });

      expect(event, isNotNull);
      expect(event!.kind, PaymentEventKind.credit);
      expect(event.walletId, 'w-123');
      expect(event.amountCents, 2950);
      expect(event.currency, 'SYP');
      expect(event.txnId, 'txn-abc');
      expect(event.source, PaymentEventSource.fcm);
      expect(event.isInbound, isTrue);
      expect(event.isOutbound, isFalse);
    });

    test('parses payment_request with request_id', () {
      final event = PaymentEvent.fromFcmData(<Object?, Object?>{
        'type': 'payment_request',
        'request_id': 'req-7',
        'wallet_id': 'w-9',
      });

      expect(event, isNotNull);
      expect(event!.kind, PaymentEventKind.request);
      expect(event.requestId, 'req-7');
      expect(event.walletId, 'w-9');
    });

    test('tolerates string-encoded amount_cents from FCM (no JSON ints)', () {
      // FCM data values arrive as strings on Android; parser must handle it.
      final event = PaymentEvent.fromFcmData(<Object?, Object?>{
        'type': 'payment_credit',
        'wallet_id': 'w-1',
        'amount_cents': '4242',
      });

      expect(event?.amountCents, 4242);
    });

    test('returns null for unknown push types so other handlers can dispatch',
        () {
      expect(
        PaymentEvent.fromFcmData(const <Object?, Object?>{'type': 'chat_wakeup'}),
        isNull,
      );
      expect(
        PaymentEvent.fromFcmData(const <Object?, Object?>{}),
        isNull,
      );
    });
  });

  group('PaymentEventBus', () {
    test('broadcasts emitted events to multiple subscribers', () async {
      final bus = PaymentEventBus.instance;
      final receivedA = <PaymentEvent>[];
      final receivedB = <PaymentEvent>[];
      final subA = bus.stream.listen(receivedA.add);
      final subB = bus.stream.listen(receivedB.add);

      bus.emit(const PaymentEvent(
        kind: PaymentEventKind.credit,
        walletId: 'w-1',
        amountCents: 1000,
        currency: 'SYP',
        txnId: 'bus-test-1',
        source: PaymentEventSource.sse,
      ));

      // Let the broadcast stream deliver.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedA, hasLength(1));
      expect(receivedB, hasLength(1));
      expect(receivedA.single.txnId, 'bus-test-1');

      await subA.cancel();
      await subB.cancel();
    });

    test('isInbound/isOutbound classifications match kinds', () {
      const credit = PaymentEvent(kind: PaymentEventKind.credit);
      const debit = PaymentEvent(kind: PaymentEventKind.debit);
      const topup = PaymentEvent(kind: PaymentEventKind.topup);
      const refund = PaymentEvent(kind: PaymentEventKind.refundCredit);
      const request = PaymentEvent(kind: PaymentEventKind.request);

      expect(credit.isInbound, isTrue);
      expect(topup.isInbound, isTrue);
      expect(refund.isInbound, isTrue);
      expect(request.isInbound, isFalse);
      expect(debit.isOutbound, isTrue);
      expect(credit.isOutbound, isFalse);
    });
  });
}
