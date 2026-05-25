import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_scheduled_messages_page.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<List<ChatScheduledMessageRow>> Function() onRefresh,
    required Future<void> Function(String id) onCancel,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScheduledMessagesPage(
          onRefresh: onRefresh,
          onCancel: onCancel,
        ),
      ),
    );
  }

  testWidgets('initial spinner -> empty state hint', (tester) async {
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatScheduledMessageRow>[],
      onCancel: (_) async => fail('cancel should not be called'),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No scheduled messages.'), findsOneWidget);
    expect(find.textContaining('Long-press the send button'), findsOneWidget);
  });

  testWidgets('renders rows with recipient + body preview + time', (tester) async {
    final rows = <ChatScheduledMessageRow>[
      ChatScheduledMessageRow(
        id: 's1',
        recipientName: 'Alice',
        isGroup: false,
        scheduledForLocal:
            DateTime.now().add(const Duration(hours: 2)).copyWith(second: 0),
        bodyPreview: 'Happy birthday!',
      ),
      ChatScheduledMessageRow(
        id: 's2',
        recipientName: 'Lunch group',
        isGroup: true,
        scheduledForLocal:
            DateTime.now().add(const Duration(days: 1)).copyWith(second: 0),
      ),
    ];
    await pumpPage(
      tester,
      onRefresh: () async => rows,
      onCancel: (_) async => fail('cancel should not be called'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Lunch group'), findsOneWidget);
    expect(find.text('Happy birthday!'), findsOneWidget);
    // Body preview falls back to "(encrypted)" when null.
    expect(find.text('(encrypted)'), findsOneWidget);
  });

  testWidgets('tap close icon → confirm dialog → onCancel + row removed',
      (tester) async {
    final rows = <ChatScheduledMessageRow>[
      ChatScheduledMessageRow(
        id: 'pick-me',
        recipientName: 'Alice',
        isGroup: false,
        scheduledForLocal: DateTime.now().add(const Duration(hours: 1)),
        bodyPreview: 'Hi',
      ),
    ];
    final cancelled = <String>[];
    await pumpPage(
      tester,
      onRefresh: () async => List<ChatScheduledMessageRow>.from(rows),
      onCancel: (id) async => cancelled.add(id),
    );
    await tester.pumpAndSettle();

    // Tap the per-row close button.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Cancel scheduled message?'), findsOneWidget);

    // Confirm.
    await tester.tap(find.text('Cancel schedule'));
    await tester.pumpAndSettle();

    expect(cancelled, equals(<String>['pick-me']));
    expect(find.text('Alice'), findsNothing);
    expect(find.text('No scheduled messages.'), findsOneWidget);
  });

  testWidgets('cancel-confirm dismiss does NOT call onCancel', (tester) async {
    final rows = <ChatScheduledMessageRow>[
      ChatScheduledMessageRow(
        id: 'pick-me',
        recipientName: 'Alice',
        isGroup: false,
        scheduledForLocal: DateTime.now().add(const Duration(hours: 1)),
      ),
    ];
    var cancelCount = 0;
    await pumpPage(
      tester,
      onRefresh: () async => rows,
      onCancel: (_) async => cancelCount++,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    // Tap the "Cancel" dialog button (NOT "Cancel schedule").
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(cancelCount, 0);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('onRefresh failure surfaces retry hint', (tester) async {
    await pumpPage(
      tester,
      onRefresh: () async => throw StateError('boom'),
      onCancel: (_) async => fail('cancel should not be called'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load list'), findsOneWidget);
  });

  testWidgets('attempt_count > 0 surfaces warning chip', (tester) async {
    final rows = <ChatScheduledMessageRow>[
      ChatScheduledMessageRow(
        id: 's-err',
        recipientName: 'Alice',
        isGroup: false,
        scheduledForLocal: DateTime.now().add(const Duration(hours: 1)),
        bodyPreview: 'Hi',
        attemptCount: 3,
        lastError: 'peer offline',
      ),
    ];
    await pumpPage(
      tester,
      onRefresh: () async => rows,
      onCancel: (_) async => fail('cancel should not be called'),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 attempts'), findsOneWidget);
  });
}
