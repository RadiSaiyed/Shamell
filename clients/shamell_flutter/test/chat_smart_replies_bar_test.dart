import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_smart_replies.dart';
import 'package:shamell_flutter/core/chat/chat_smart_replies_bar.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required List<ChatSmartReply> replies,
    required void Function(ChatSmartReply reply) onPick,
    VoidCallback? onDismiss,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatSmartRepliesBar(
            replies: replies,
            onPick: onPick,
            onDismiss: onDismiss,
          ),
        ),
      ),
    );
  }

  testWidgets('empty replies -> collapses to SizedBox.shrink',
      (tester) async {
    await pumpBar(
      tester,
      replies: const <ChatSmartReply>[],
      onPick: (_) => fail('onPick should not fire'),
    );
    expect(find.byType(ActionChip), findsNothing);
    // SizedBox.shrink renders zero-size — no chip text visible.
    expect(find.text('Yes'), findsNothing);
  });

  testWidgets('renders one chip per suggestion', (tester) async {
    await pumpBar(
      tester,
      replies: const <ChatSmartReply>[
        ChatSmartReply(text: 'Yes', category: 'yes_no'),
        ChatSmartReply(text: 'No', category: 'yes_no'),
        ChatSmartReply(text: 'Let me check', category: 'yes_no'),
      ],
      onPick: (_) {},
    );
    expect(find.byType(ActionChip), findsNWidgets(3));
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Let me check'), findsOneWidget);
  });

  testWidgets('tap fires onPick with the matched reply', (tester) async {
    ChatSmartReply? picked;
    await pumpBar(
      tester,
      replies: const <ChatSmartReply>[
        ChatSmartReply(text: 'Yes', category: 'yes_no'),
        ChatSmartReply(text: 'No', category: 'yes_no'),
      ],
      onPick: (r) => picked = r,
    );
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.text, 'No');
    expect(picked!.category, 'yes_no');
  });

  testWidgets('× button only renders when onDismiss is provided',
      (tester) async {
    await pumpBar(
      tester,
      replies: const <ChatSmartReply>[
        ChatSmartReply(text: 'Yes', category: 'yes_no'),
      ],
      onPick: (_) {},
    );
    expect(find.byIcon(Icons.close), findsNothing);

    bool dismissed = false;
    await pumpBar(
      tester,
      replies: const <ChatSmartReply>[
        ChatSmartReply(text: 'Yes', category: 'yes_no'),
      ],
      onPick: (_) {},
      onDismiss: () => dismissed = true,
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
