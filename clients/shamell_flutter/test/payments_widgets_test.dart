import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/payments_requests.dart';
import 'package:shamell_flutter/core/payments_receive.dart';
import 'package:shamell_flutter/core/payments_send.dart';

void main() {
  testWidgets('IncomingRequestBanner accept callback fires', (tester) async {
    bool accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncomingRequestBanner(
            req: {'amount_cents': 1500, 'from_wallet_id': 'w_from'},
            onAccept: () {
              accepted = true;
            },
            onDismiss: () {},
          ),
        ),
      ),
    );
    expect(find.text('Payment Request'), findsOneWidget);
    await tester.tap(find.text('Accept & Pay'));
    await tester.pump();
    expect(accepted, isTrue);
  });

  testWidgets('ShareQrPanel shows QR image', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareQrPanel(payload: 'PAY|wallet=w1|amount=1000'),
        ),
      ),
    );
    expect(find.byType(ShareQrPanel), findsOneWidget);
    // QrImageView is a widget from qr_flutter, assert present by type check on widget tree text and any widget count
    expect(find.textContaining('PAY|wallet=w1'), findsOneWidget);
  });

  testWidgets('SendButton shows cooldown seconds', (tester) async {
    int tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SendButton(
            cooldownSec: 12,
            onTap: () {
              tapped++;
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('Send (12s)'), findsOneWidget);
    // tap should not increment while cooldown
    await tester.tap(find.textContaining('Send'));
    await tester.pump();
    expect(tapped, 0);
  });

  testWidgets('SendButton has semantics label when wrapped', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            button: true,
            label: 'Send payment',
            child: const SendButton(
              cooldownSec: 0,
              onTap: null,
            ),
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(Semantics));
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(semantics.label, 'Send payment');
  });
}
