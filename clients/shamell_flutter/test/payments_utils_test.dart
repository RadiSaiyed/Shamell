import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/mini_apps/payments/payments_utils.dart';

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
    });
    test('ignore non-numeric', () {
      expect(parseCents('SYP 1,234.00'), 123400);
      expect(parseCents('--'), 0);
    });
  });

  group('buildTransferTarget', () {
    test('alias', () {
      final m = buildTransferTarget('@alice');
      expect(m.containsKey('to_alias'), true);
      expect(m['to_alias'], '@alice');
    });
    test('resolved phone to wallet id', () {
      final m = buildTransferTarget('+963999', resolvedWalletId: 'w123');
      expect(m['to_wallet_id'], 'w123');
    });
    test('plain wallet id passthrough', () {
      final m = buildTransferTarget('w555');
      expect(m['to_wallet_id'], 'w555');
    });
  });
}
