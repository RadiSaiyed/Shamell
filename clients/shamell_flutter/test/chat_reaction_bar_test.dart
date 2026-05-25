import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_reaction_bar.dart';
import 'package:shamell_flutter/core/chat/chat_reaction_models.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
    await tester.pump();
  }

  group('ChatReactionBar', () {
    testWidgets('renders one chip per reaction summary', (tester) async {
      await pump(
        tester,
        const ChatReactionBar(
          reactions: <ChatReactionSummary>[
            ChatReactionSummary(emoji: '👍', count: 2, hasMe: true),
            ChatReactionSummary(emoji: '❤️', count: 1, hasMe: false),
          ],
          // Show the "+" too to confirm it doesn't dedup the chip count.
          onAdd: _noOp,
        ),
      );

      expect(find.text('👍'), findsOneWidget);
      expect(find.text('❤️'), findsOneWidget);
      // Count badge only renders for count > 1.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      // Trailing "+" affordance.
      expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
    });

    testWidgets('omits count badge when count == 1', (tester) async {
      await pump(
        tester,
        const ChatReactionBar(
          reactions: <ChatReactionSummary>[
            ChatReactionSummary(emoji: '👍', count: 1, hasMe: false),
          ],
        ),
      );
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('tapping a chip calls onToggle with current hasMe',
        (tester) async {
      String? tappedEmoji;
      bool? tappedHasMe;
      await pump(
        tester,
        ChatReactionBar(
          reactions: const <ChatReactionSummary>[
            ChatReactionSummary(emoji: '👍', count: 2, hasMe: true),
          ],
          onToggle: (emoji, hasMe) async {
            tappedEmoji = emoji;
            tappedHasMe = hasMe;
          },
        ),
      );
      await tester.tap(find.text('👍'));
      await tester.pump();
      expect(tappedEmoji, '👍');
      expect(tappedHasMe, isTrue);
    });

    testWidgets('tapping "+" calls onAdd', (tester) async {
      int calls = 0;
      await pump(
        tester,
        ChatReactionBar(
          reactions: const <ChatReactionSummary>[],
          onAdd: () => calls += 1,
        ),
      );
      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('renders nothing when empty + showAddButton=false',
        (tester) async {
      await pump(
        tester,
        const ChatReactionBar(
          reactions: <ChatReactionSummary>[],
          showAddButton: false,
        ),
      );
      // No chips, no "+", no SizedBox.shrink-ed scaffold leaks.
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('omits "+" when onAdd is null even if showAddButton=true',
        (tester) async {
      await pump(
        tester,
        const ChatReactionBar(
          reactions: <ChatReactionSummary>[
            ChatReactionSummary(emoji: '👍', count: 1, hasMe: false),
          ],
        ),
      );
      // Chip renders, no add affordance.
      expect(find.text('👍'), findsOneWidget);
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
    });
  });

  group('ChatReactionPickerSheet', () {
    testWidgets('renders one chip per default emoji', (tester) async {
      await pump(
        tester,
        const ChatReactionPickerSheet(),
      );
      for (final emoji in defaultChatReactionEmojis) {
        expect(find.text(emoji), findsOneWidget,
            reason: 'default emoji $emoji must render');
      }
    });

    testWidgets('show() returns the tapped emoji and dismisses the sheet',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await ChatReactionPickerSheet.show(ctx);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Sheet is open; tap the heart.
      await tester.tap(find.text('❤️'));
      await tester.pumpAndSettle();
      expect(result, '❤️');
    });

    testWidgets('show() returns null when dismissed by tapping outside',
        (tester) async {
      String? result = 'placeholder';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await ChatReactionPickerSheet.show(ctx);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Tap the barrier (outside the sheet) at the very top of the screen.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}

void _noOp() {}
