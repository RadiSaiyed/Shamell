import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_saved_replies_manage_page.dart';
import 'package:shamell_flutter/core/chat/chat_saved_replies_palette.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<List<ChatSavedReply>> Function() onRefresh,
    Future<void> Function({
      required String slug,
      required String label,
      required String body,
    })? onSave,
    Future<void> Function(String slug)? onDelete,
    int max = 32,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatSavedRepliesManagePage(
          onRefresh: onRefresh,
          onSave: onSave ?? ({required slug, required label, required body}) async {},
          onDelete: onDelete ?? (slug) async {},
          maxRepliesPerDevice: max,
        ),
      ),
    );
  }

  group('slugify', () {
    test('lowercases and underscores spaces', () {
      expect(slugify('Got it, thanks!'), 'got_it_thanks');
    });

    test('truncates to 32 chars', () {
      final long = 'a' * 50;
      expect(slugify(long).length, 32);
    });

    test('strips leading/trailing underscores', () {
      expect(slugify('!!hello!!'), 'hello');
    });

    test('returns empty when no alphanumerics and no fallback', () {
      expect(slugify('!!!'), '');
    });

    test('falls back to fallback string when primary is empty', () {
      expect(slugify('!!!', fallback: 'Hello world'), 'hello_world');
    });

    test('collapses runs of non-alnum to a single underscore', () {
      expect(slugify('hello    world!!  foo'), 'hello_world_foo');
    });

    test('handles non-ASCII (Arabic) via fallback rule', () {
      // No ASCII letters/digits at all → empty primary → falls back
      // to itself which is also empty. Caller surfaces validation
      // error in that path.
      expect(slugify('مرحبا'), '');
    });
  });

  testWidgets('initial spinner -> empty state hint', (tester) async {
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatSavedReply>[],
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No saved replies yet.'), findsOneWidget);
    expect(find.textContaining('Tap + to add'), findsOneWidget);
  });

  testWidgets('renders rows + counter footer', (tester) async {
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatSavedReply>[
        ChatSavedReply(slug: 'ack', label: 'Got it', body: 'Got it, thanks!'),
        ChatSavedReply(slug: 'busy', label: 'Busy', body: 'I will get back to you soon.'),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Busy'), findsOneWidget);
    expect(find.text('Got it, thanks!'), findsOneWidget);
    expect(find.text('2 of 32 saved'), findsOneWidget);
  });

  testWidgets('+ FAB disabled when at the cap', (tester) async {
    final fullList = List<ChatSavedReply>.generate(
      32,
      (i) => ChatSavedReply(slug: 'r$i', label: 'R$i', body: 'b$i'),
    );
    await pumpPage(
      tester,
      onRefresh: () async => fullList,
      max: 32,
    );
    await tester.pumpAndSettle();
    final addBtn = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add));
    expect(addBtn.onPressed, isNull);
  });

  testWidgets('tap + opens editor and saves a new reply', (tester) async {
    final savedCalls = <Map<String, String>>[];
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatSavedReply>[],
      onSave: ({required slug, required label, required body}) async {
        savedCalls.add({'slug': slug, 'label': label, 'body': body});
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    // Editor visible.
    expect(find.text('New saved reply'), findsOneWidget);
    // Fill in label + body. The slug is auto-derived.
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'Got it');
    await tester.enterText(find.widgetWithText(TextField, 'Body'), 'Got it, thanks!');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedCalls, hasLength(1));
    expect(savedCalls.first['label'], 'Got it');
    expect(savedCalls.first['slug'], 'got_it');
    expect(savedCalls.first['body'], 'Got it, thanks!');
  });

  testWidgets('editor surfaces "Body required" when body is blank',
      (tester) async {
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatSavedReply>[],
      onSave: ({required slug, required label, required body}) async {
        fail('onSave should not be called when body is empty');
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'Got it');
    // leave body empty
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Body required'), findsOneWidget);
    // Editor still open.
    expect(find.text('New saved reply'), findsOneWidget);
  });

  testWidgets('edit existing row pre-fills + slug is read-only', (tester) async {
    final savedCalls = <Map<String, String>>[];
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatSavedReply>[
        ChatSavedReply(slug: 'ack', label: 'Got it', body: 'old body'),
      ],
      onSave: ({required slug, required label, required body}) async {
        savedCalls.add({'slug': slug, 'label': label, 'body': body});
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Edit saved reply'), findsOneWidget);
    expect(find.textContaining('immutable after creation'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Body'), 'new body');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedCalls.first['slug'], 'ack');
    expect(savedCalls.first['body'], 'new body');
  });

  testWidgets('delete confirm + cancel branches', (tester) async {
    final deleted = <String>[];
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatSavedReply>[
        ChatSavedReply(slug: 'ack', label: 'Got it', body: 'body'),
      ],
      onDelete: (slug) async => deleted.add(slug),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete saved reply?'), findsOneWidget);
    // Cancel branch
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.text('Got it'), findsOneWidget);
    // Now the delete branch.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleted, equals(<String>['ack']));
    expect(find.text('Got it'), findsNothing);
  });

  testWidgets('onRefresh failure shows retry hint', (tester) async {
    await pumpPage(
      tester,
      onRefresh: () async => throw StateError('boom'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load list'), findsOneWidget);
  });

  testWidgets('over-cap save surfaces a "hit the limit" snackbar',
      (tester) async {
    await pumpPage(
      tester,
      onRefresh: () async => const <ChatSavedReply>[],
      onSave: ({required slug, required label, required body}) async {
        throw Exception('server returned 409 too-many-saved-replies');
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'x');
    await tester.enterText(find.widgetWithText(TextField, 'Body'), 'y');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hit the limit'), findsOneWidget);
  });
}
