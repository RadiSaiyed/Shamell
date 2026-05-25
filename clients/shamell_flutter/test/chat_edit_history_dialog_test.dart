import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_edit_history_dialog.dart';

void main() {
  Future<void> showInsideApp(
    WidgetTester tester, {
    required List<ChatEditHistoryRevision> revisions,
    String? currentText,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await ChatEditHistoryDialog.show(
                    ctx,
                    revisions: revisions,
                    currentText: currentText,
                  );
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
  }

  testWidgets('renders header + one tile per revision', (tester) async {
    await showInsideApp(
      tester,
      revisions: <ChatEditHistoryRevision>[
        ChatEditHistoryRevision(
          revision: 1,
          editedAt: DateTime.utc(2026, 5, 14, 9, 30),
          text: 'first draft',
        ),
        ChatEditHistoryRevision(
          revision: 2,
          editedAt: DateTime.utc(2026, 5, 14, 9, 45),
          text: 'second draft',
        ),
      ],
      currentText: 'final wording',
    );
    expect(find.text('Edit history'), findsOneWidget);
    expect(find.text('Revision 1'), findsOneWidget);
    expect(find.text('Revision 2'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('first draft'), findsOneWidget);
    expect(find.text('second draft'), findsOneWidget);
    expect(find.text('final wording'), findsOneWidget);
  });

  testWidgets('current section is omitted when currentText is null',
      (tester) async {
    await showInsideApp(
      tester,
      revisions: <ChatEditHistoryRevision>[
        ChatEditHistoryRevision(
          revision: 1,
          editedAt: DateTime.utc(2026, 5, 14),
          text: 'first',
        ),
      ],
      currentText: null,
    );
    expect(find.text('Revision 1'), findsOneWidget);
    expect(find.text('Current'), findsNothing);
  });

  testWidgets('empty revisions + empty current shows "No edit history"',
      (tester) async {
    await showInsideApp(
      tester,
      revisions: const <ChatEditHistoryRevision>[],
      currentText: '',
    );
    expect(find.text('No edit history'), findsOneWidget);
  });

  testWidgets('empty text revision renders "(no text)" placeholder',
      (tester) async {
    await showInsideApp(
      tester,
      revisions: <ChatEditHistoryRevision>[
        ChatEditHistoryRevision(
          revision: 1,
          editedAt: DateTime.utc(2026, 5, 14),
          text: '   ',
        ),
      ],
      currentText: 'visible',
    );
    expect(find.text('(no text)'), findsOneWidget);
    expect(find.text('visible'), findsOneWidget);
  });

  testWidgets('timestamps render in YYYY-MM-DD HH:MM local format',
      (tester) async {
    await showInsideApp(
      tester,
      revisions: <ChatEditHistoryRevision>[
        ChatEditHistoryRevision(
          revision: 1,
          editedAt: DateTime(2026, 5, 14, 9, 5),
          text: 'hi',
        ),
      ],
      currentText: 'hello',
    );
    expect(find.text('2026-05-14 09:05'), findsOneWidget);
  });
}
