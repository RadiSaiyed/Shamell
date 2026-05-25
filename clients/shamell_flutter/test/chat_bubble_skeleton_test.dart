import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_bubble_skeleton.dart';
import 'package:shamell_flutter/core/skeleton.dart';

void main() {
  // The skeleton is purely visual; we exercise it under `pumpWidget` to
  // make sure it lays out without throwing and produces the right
  // shape-class count (which is what the chat-page user actually sees).
  Future<void> pumpInside(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: child),
        ),
      ),
    );
    // Pump a couple of frames so the shimmer animation kicks in without
    // running forever (the animation is infinite by design, so we don't
    // settle).
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('ChatBubbleSkeleton', () {
    testWidgets('renders 2 SkeletonBoxes (body + timestamp) without throwing',
        (tester) async {
      await pumpInside(tester, const ChatBubbleSkeleton(seed: 1));
      expect(tester.takeException(), isNull);
      // One bubble body box + one timestamp box.
      expect(find.byType(SkeletonBox), findsNWidgets(2));
    });

    testWidgets('honours isMine alignment', (tester) async {
      // Incoming bubble aligns to centerLeft.
      await pumpInside(tester, const ChatBubbleSkeleton(isMine: false, seed: 1));
      final incoming = tester.widget<Align>(find.byType(Align));
      expect(incoming.alignment, Alignment.centerLeft);

      // Re-pump the outgoing variant in a fresh widget tree.
      await pumpInside(tester, const ChatBubbleSkeleton(isMine: true, seed: 1));
      final outgoing = tester.widget<Align>(find.byType(Align));
      expect(outgoing.alignment, Alignment.centerRight);
    });

    testWidgets('seed produces deterministic body widths', (tester) async {
      // Two skeletons with the same seed must render the same body width.
      // We check that the deterministic body width band is in [120, 240).
      await pumpInside(tester, const ChatBubbleSkeleton(seed: 7));
      final boxes = tester.widgetList<SkeletonBox>(find.byType(SkeletonBox));
      // First box is the body.
      final body = boxes.first;
      expect(body.width, isNotNull);
      expect(body.width!, greaterThanOrEqualTo(120));
      expect(body.width!, lessThan(241));
    });
  });

  group('ChatBubbleSkeletonGroup', () {
    testWidgets('default count renders 3 bubbles', (tester) async {
      await pumpInside(tester, const ChatBubbleSkeletonGroup());
      expect(find.byType(ChatBubbleSkeleton), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('custom count is respected', (tester) async {
      await pumpInside(tester, const ChatBubbleSkeletonGroup(count: 5));
      expect(find.byType(ChatBubbleSkeleton), findsNWidgets(5));
    });

    testWidgets('alternates incoming and outgoing for conversational feel',
        (tester) async {
      // Even indices are incoming (peer), odd are outgoing (me). This makes
      // the column read as a snippet of conversation, not a one-sided wall.
      await pumpInside(tester, const ChatBubbleSkeletonGroup(count: 4));
      final skeletons =
          tester.widgetList<ChatBubbleSkeleton>(find.byType(ChatBubbleSkeleton))
              .toList();
      expect(skeletons[0].isMine, isFalse);
      expect(skeletons[1].isMine, isTrue);
      expect(skeletons[2].isMine, isFalse);
      expect(skeletons[3].isMine, isTrue);
    });
  });
}
