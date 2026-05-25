import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/glass.dart';

void main() {
  testWidgets('GlassPanel keeps content and applies a blur layer',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ColoredBox(color: Colors.green),
              Center(
                child: GlassPanel(
                  child: Text('Liquid glass content'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Liquid glass content'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
  });
}
