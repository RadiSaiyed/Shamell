import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/payments/payments_utils.dart';

void main() {
  group('parseCents', () {
    test('raw cents', () {
      expect(parseCents('0'), 0);
      expect(parseCents('12'), 12);
      expect(parseCents('1250'), 1250);
    });
    test('decimal formats', () {
      expect(parseCents('12.50'), 1250);
      expect(parseCents('12,50'), 1250);
      expect(parseCents('  1,2  '), 120);
      expect(parseCents('1,234.00'), 123400);
    });
    test('reject malformed or unsafe inputs', () {
      expect(parseCents('-5'), 0);
      expect(parseCents('+5'), 0);
      expect(parseCents('1e3'), 0);
      expect(parseCents('SYP 1,234.00'), 0);
      expect(parseCents('12,34.56'), 0);
      expect(parseCents('999999999999999999999999999999'), 0);
      expect(parseCents('--'), 0);
    });
  });

  group('buildTransferTarget', () {
    test('alias', () {
      final m = buildTransferTarget('@alice');
      expect(m.containsKey('to_alias'), true);
      expect(m['to_alias'], '@alice');
    });
    test('phone numbers are rejected', () {
      final m = buildTransferTarget('+963999');
      expect(m.isEmpty, true);
    });
    test('plain wallet id passthrough', () {
      final m = buildTransferTarget('w555');
      expect(m['to_wallet_id'], 'w555');
    });
  });
}
