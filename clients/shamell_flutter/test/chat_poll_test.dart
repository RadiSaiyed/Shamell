import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_poll_bubble.dart';
import 'package:shamell_flutter/core/chat/chat_poll_creator_dialog.dart';

void main() {
  group('ChatPollOption.fromMap', () {
    test('parses idx + label + votes + selected', () {
      final o = ChatPollOption.fromMap(
        const <String, Object?>{'idx': 1, 'label': 'Pizza', 'votes': 3},
        myVotes: <int>{1},
      );
      expect(o.idx, 1);
      expect(o.label, 'Pizza');
      expect(o.votes, 3);
      expect(o.selected, isTrue);
    });

    test('tolerates num types (int vs double from JSON)', () {
      final o = ChatPollOption.fromMap(
        const <String, Object?>{'idx': 0, 'label': 'A', 'votes': 5.0},
        myVotes: <int>{},
      );
      expect(o.votes, 5);
      expect(o.selected, isFalse);
    });
  });

  group('ChatPollBubble', () {
    Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

    testWidgets('renders question + options + vote counts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      await tester.pumpWidget(wrap(ChatPollBubble(
        question: 'Lunch?',
        options: const <ChatPollOption>[
          ChatPollOption(idx: 0, label: 'Pizza', votes: 4, selected: true),
          ChatPollOption(idx: 1, label: 'Sushi', votes: 2, selected: false),
        ],
        totalVoters: 6,
        onVote: (_) {},
      )));
      expect(find.text('Lunch?'), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);
      expect(find.text('Sushi'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('6 voted'), findsOneWidget);
    });

    testWidgets('single-select uses radio icons; selected option marked',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      await tester.pumpWidget(wrap(ChatPollBubble(
        question: 'Q',
        options: const <ChatPollOption>[
          ChatPollOption(idx: 0, label: 'A', votes: 1, selected: true),
          ChatPollOption(idx: 1, label: 'B', votes: 0, selected: false),
        ],
        onVote: (_) {},
      )));
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });

    testWidgets('multi-select uses checkbox icons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      await tester.pumpWidget(wrap(ChatPollBubble(
        question: 'Q',
        options: const <ChatPollOption>[
          ChatPollOption(idx: 0, label: 'A', votes: 1, selected: true),
        ],
        multiSelect: true,
        onVote: (_) {},
      )));
      expect(find.byIcon(Icons.check_box), findsOneWidget);
    });

    testWidgets('tap option fires onVote with idx', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      int? picked;
      await tester.pumpWidget(wrap(ChatPollBubble(
        question: 'Q',
        options: const <ChatPollOption>[
          ChatPollOption(idx: 0, label: 'A', votes: 0, selected: false),
          ChatPollOption(idx: 1, label: 'B', votes: 0, selected: false),
        ],
        onVote: (i) => picked = i,
      )));
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(picked, 1);
    });

    testWidgets('closed poll disables onVote + shows "closed" chip',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      int taps = 0;
      await tester.pumpWidget(wrap(ChatPollBubble(
        question: 'Q',
        options: const <ChatPollOption>[
          ChatPollOption(idx: 0, label: 'A', votes: 0, selected: false),
        ],
        closed: true,
        onVote: (_) => taps++,
      )));
      expect(find.text('closed'), findsOneWidget);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('Close button only shows for the creator', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      await tester.pumpWidget(wrap(ChatPollBubble(
        question: 'Q',
        options: const <ChatPollOption>[
          ChatPollOption(idx: 0, label: 'A', votes: 0, selected: false),
        ],
        onVote: (_) {},
      )));
      expect(find.text('Close'), findsNothing);

      bool closeFired = false;
      await tester.pumpWidget(wrap(ChatPollBubble(
        question: 'Q',
        options: const <ChatPollOption>[
          ChatPollOption(idx: 0, label: 'A', votes: 0, selected: false),
        ],
        isCreator: true,
        onVote: (_) {},
        onClose: () => closeFired = true,
      )));
      expect(find.text('Close'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(closeFired, isTrue);
    });
  });

  group('ChatPollCreatorDialog', () {
    Future<Future<ChatPollDraft?>> openDialog(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ));
      // `show` returns a Future that completes when the dialog pops.
      // We hand it back so the caller can `await` it after driving
      // interactions; the inner pumpAndSettle drains the open-anim.
      final future = ChatPollCreatorDialog.show(navKey.currentContext!);
      await tester.pumpAndSettle();
      return future;
    }

    testWidgets('renders 2 option fields + Add/Send buttons', (tester) async {
      final f = await openDialog(tester);
      expect(find.text('New poll'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Option 1'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Option 2'), findsOneWidget);
      expect(find.text('Add option'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await f, isNull);
    });

    testWidgets('add up to 10 options; the + button hides at the cap',
        (tester) async {
      await openDialog(tester);
      for (int i = 2; i < 10; i++) {
        await tester.tap(find.text('Add option'));
        await tester.pumpAndSettle();
      }
      expect(find.widgetWithText(TextField, 'Option 10'), findsOneWidget);
      expect(find.text('Add option'), findsNothing);
    });

    testWidgets('rejects empty question', (tester) async {
      await openDialog(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Option 1'), 'A');
      await tester.enterText(
          find.widgetWithText(TextField, 'Option 2'), 'B');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Question required'), findsOneWidget);
    });

    testWidgets('rejects duplicate options', (tester) async {
      await openDialog(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Question'), 'Lunch?');
      await tester.enterText(
          find.widgetWithText(TextField, 'Option 1'), 'Pizza');
      await tester.enterText(
          find.widgetWithText(TextField, 'Option 2'), 'Pizza');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Options must be unique'), findsOneWidget);
    });

    testWidgets('returns ChatPollDraft on valid submit', (tester) async {
      final f = await openDialog(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Question'), 'Lunch?');
      await tester.enterText(
          find.widgetWithText(TextField, 'Option 1'), 'Pizza');
      await tester.enterText(
          find.widgetWithText(TextField, 'Option 2'), 'Sushi');
      await tester.tap(find.text('Allow multiple choices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      final draft = await f;
      expect(draft, isNotNull);
      expect(draft!.question, 'Lunch?');
      expect(draft.options, <String>['Pizza', 'Sushi']);
      expect(draft.multiSelect, isTrue);
      expect(draft.anonymous, isFalse);
    });
  });
}
