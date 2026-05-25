import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_saved_replies_palette.dart';

void main() {
  Future<void> openPalette(
    WidgetTester tester, {
    required void Function(String? result) onResult,
    List<ChatSavedReply> replies = const <ChatSavedReply>[],
    VoidCallback? onManage,
  }) async {
    // Phone-sized viewport so the sheet (half-height by default) has
    // room for replies + Manage row without scrolling them offscreen.
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    // ignore: discarded_futures
    ChatSavedRepliesPalette.show(
      navKey.currentContext!,
      replies: replies,
      onManage: onManage,
    ).then(onResult);
    await tester.pumpAndSettle();
  }

  testWidgets('empty state shows hint, no Manage row when onManage is null',
      (tester) async {
    String? picked = 'unset';
    await openPalette(tester, onResult: (r) => picked = r);
    expect(find.text('Saved replies'), findsOneWidget);
    expect(find.textContaining('No saved replies yet'), findsOneWidget);
    expect(find.text('Manage replies'), findsNothing);
    expect(picked, 'unset'); // never resolved
  });

  testWidgets('renders replies and returns body on tap', (tester) async {
    String? picked;
    await openPalette(
      tester,
      onResult: (r) => picked = r,
      replies: const <ChatSavedReply>[
        ChatSavedReply(slug: 'thx', label: 'Thanks', body: 'Thanks so much!'),
        ChatSavedReply(slug: 'busy', label: 'Busy', body: 'Will get back soon.'),
      ],
    );
    expect(find.text('Thanks'), findsOneWidget);
    expect(find.text('Busy'), findsOneWidget);
    // Body shows as the subtitle preview.
    expect(find.text('Thanks so much!'), findsOneWidget);
    await tester.tap(find.text('Thanks'));
    await tester.pumpAndSettle();
    expect(picked, 'Thanks so much!');
  });

  testWidgets('falls back to slug when label is empty', (tester) async {
    String? picked;
    await openPalette(
      tester,
      onResult: (r) => picked = r,
      replies: const <ChatSavedReply>[
        ChatSavedReply(slug: 'only-slug', label: '', body: 'body here'),
      ],
    );
    // Title row should fall back to the slug.
    expect(find.text('only-slug'), findsOneWidget);
  });

  testWidgets('Manage row shown only when onManage provided', (tester) async {
    bool manageCalled = false;
    String? picked = 'unset';
    await openPalette(
      tester,
      onResult: (r) => picked = r,
      replies: const <ChatSavedReply>[
        ChatSavedReply(slug: 'a', label: 'A', body: 'body'),
      ],
      onManage: () => manageCalled = true,
    );
    expect(find.text('Manage replies'), findsOneWidget);
    await tester.tap(find.text('Manage replies'));
    await tester.pumpAndSettle();
    expect(manageCalled, isTrue);
    expect(picked, isNull); // popped with null
  });

  testWidgets('dismiss via barrier tap returns null', (tester) async {
    String? picked = 'unset';
    await openPalette(tester, onResult: (r) => picked = r);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  test('ChatSavedReply.fromMap reads the standard service shape', () {
    final r = ChatSavedReply.fromMap(<String, Object?>{
      'slug': 'thx',
      'label': 'Thanks',
      'body': 'Thanks!',
    });
    expect(r.slug, 'thx');
    expect(r.label, 'Thanks');
    expect(r.body, 'Thanks!');
  });

  test('ChatSavedReply.fromMap tolerates missing keys', () {
    final r = ChatSavedReply.fromMap(const <String, Object?>{});
    expect(r.slug, '');
    expect(r.label, '');
    expect(r.body, '');
  });
}
