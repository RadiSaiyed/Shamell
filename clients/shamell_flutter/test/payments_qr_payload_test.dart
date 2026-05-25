import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/payments/payments_qr_payload.dart';

void main() {
  test('builds versioned pay QR payload with currency and amount cents', () {
    final expiresAt = DateTime.utc(2026, 4, 29, 12);
    final payload = buildShamellPaymentQrPayload(
      type: ShamellPaymentQrPayloadType.pay,
      walletId: 'wallet_usd',
      currency: 'usd',
      amountCents: 1050,
      note: 'lunch',
      label: 'Coffee stand',
      mode: 'merchant',
      expiresAt: expiresAt,
    );

    expect(payload, startsWith('shamell://pay?'));
    final parsed = parseShamellPaymentQrPayload(payload);
    expect(parsed, isNotNull);
    expect(parsed!.type, ShamellPaymentQrPayloadType.pay);
    expect(parsed.walletId, 'wallet_usd');
    expect(parsed.currency, 'USD');
    expect(parsed.amountCents, 1050);
    expect(parsed.amountMajorText, '10.50');
    expect(parsed.note, 'lunch');
    expect(parsed.label, 'Coffee stand');
    expect(parsed.mode, 'merchant');
    expect(parsed.expiresAt, expiresAt);
    expect(parsed.isVersioned, isTrue);
  });

  test('parses legacy pipe pay amounts as major units', () {
    final parsed = parseShamellPaymentQrPayload(
      'PAY|wallet=wallet_target|amount=1|currency=EUR',
    );

    expect(parsed, isNotNull);
    expect(parsed!.type, ShamellPaymentQrPayloadType.pay);
    expect(parsed.walletId, 'wallet_target');
    expect(parsed.currency, 'EUR');
    expect(parsed.amountCents, 100);
  });

  test('builds and parses topup QR payloads', () {
    final payload = buildShamellPaymentQrPayload(
      type: ShamellPaymentQrPayloadType.topup,
      walletId: 'wallet_aed',
      currency: 'AED',
      amountCents: 2500,
    );

    final parsed = parseShamellPaymentQrPayload(payload);
    expect(parsed, isNotNull);
    expect(parsed!.type, ShamellPaymentQrPayloadType.topup);
    expect(parsed.walletId, 'wallet_aed');
    expect(parsed.currency, 'AED');
    expect(parsed.amountCents, 2500);
    expect(parsed.amountMajorText, '25.00');
  });
}
