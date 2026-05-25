import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/scan_page.dart';

void main() {
  testWidgets('manual scan entry trims and submits payload', (tester) async {
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanManualEntrySheet(
            onSubmit: (value) {
              submitted = value;
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      '  PAY|wallet=wallet-123|amount=60.00  ',
    );
    await tester.tap(find.text('Use code'));
    await tester.pump();

    expect(submitted, 'PAY|wallet=wallet-123|amount=60.00');
  });
}
