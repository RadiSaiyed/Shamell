import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_typing_dot.dart';

void main() {
  Future<void> pumpInside(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
    // Pump a couple of frames so the AnimationController starts ticking.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders 3 dot containers + no label by default',
      (tester) async {
    await pumpInside(tester, const ChatTypingDot());
    expect(tester.takeException(), isNull);
    // The widget renders an Opacity per dot (3 total).
    expect(find.byType(Opacity), findsNWidgets(3));
    // No Text widget when label is null.
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows the provided label before the dots', (tester) async {
    await pumpInside(
      tester,
      const ChatTypingDot(label: 'Alice is typing…'),
    );
    expect(find.text('Alice is typing…'), findsOneWidget);
    expect(find.byType(Opacity), findsNWidgets(3));
  });

  testWidgets('dots animate over time (opacity changes)', (tester) async {
    await pumpInside(tester, const ChatTypingDot());
    final firstOpacity =
        tester.widget<Opacity>(find.byType(Opacity).first).opacity;
    // Pump 400ms so we're a third of the way through one cycle.
    await tester.pump(const Duration(milliseconds: 400));
    final secondOpacity =
        tester.widget<Opacity>(find.byType(Opacity).first).opacity;
    // Without animation the two would be equal; with the AnimationController
    // running we expect them to differ.
    expect(firstOpacity, isNot(secondOpacity));
  });

  testWidgets('honours custom size + color', (tester) async {
    await pumpInside(
      tester,
      const ChatTypingDot(size: 10, color: Color(0xFF00FF00)),
    );
    // First Container inside the Opacity should have a 10×10 size with
    // green decoration. We just confirm it doesn't throw + finds the
    // Containers.
    expect(find.byType(Container), findsNWidgets(3));
    final sizedBox = tester.widget<Container>(find.byType(Container).first);
    expect(
      (sizedBox.decoration as BoxDecoration).color,
      const Color(0xFF00FF00),
    );
  });
}
