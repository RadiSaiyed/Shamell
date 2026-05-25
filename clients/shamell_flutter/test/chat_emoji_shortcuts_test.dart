import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_emoji_shortcuts.dart';

void main() {
  test('table has a reasonable number of shortcuts', () {
    expect(emojiShortcutTableSize(), greaterThan(20));
  });

  test('direct lookup works (case-insensitive)', () {
    expect(emojiForShortcut('thumbsup'), '👍');
    expect(emojiForShortcut('ThumbsUp'), '👍');
    expect(emojiForShortcut('nope'), isNull);
  });

  group('detectEmojiPartial', () {
    test('returns null when caret not in a `:foo` window', () {
      expect(detectEmojiPartial(text: 'hello world', caret: 11), isNull);
      expect(detectEmojiPartial(text: 'hello :', caret: 7), isNull); // empty
    });

    test('detects `:foo` mid-type', () {
      final ctx = detectEmojiPartial(text: 'hi :tha', caret: 7);
      expect(ctx, isNotNull);
      expect(ctx!.openColonIdx, 3);
      expect(ctx.prefix, 'tha');
    });

    test('rejects when opening : is preceded by non-whitespace', () {
      // `a:foo` — ratio-like, should not open emoji popover.
      expect(detectEmojiPartial(text: 'a:tha', caret: 5), isNull);
    });

    test('rejects whitespace inside the partial', () {
      // closing-colon scan stops at whitespace.
      expect(detectEmojiPartial(text: ': hi', caret: 4), isNull);
    });

    test('rejects non-shortcut chars in the partial', () {
      // `:foo.bar` — period isn't in the shortcut charset.
      expect(detectEmojiPartial(text: ':foo.b', caret: 6), isNull);
    });
  });

  group('suggestEmojiCompletions', () {
    test('starts-with wins over substring', () {
      final s = suggestEmojiCompletions(prefix: 'hea');
      expect(s.first.shortcut, 'heart');
    });

    test('substring matches included when no starts-with', () {
      final s = suggestEmojiCompletions(prefix: 'rage');
      expect(s.any((x) => x.shortcut == 'rage'), isTrue);
    });

    test('limit caps the suggestion count', () {
      final s = suggestEmojiCompletions(prefix: 'a', limit: 3);
      expect(s.length, lessThanOrEqualTo(3));
    });

    test('empty prefix returns nothing', () {
      expect(suggestEmojiCompletions(prefix: ''), isEmpty);
    });

    test('non-match returns empty', () {
      expect(suggestEmojiCompletions(prefix: 'xyzzy'), isEmpty);
    });
  });

  group('applyEmojiPartialInsert', () {
    test('replaces partial range with emoji + space', () {
      final ctx = detectEmojiPartial(text: 'hi :tha', caret: 7)!;
      final result = applyEmojiPartialInsert(
        text: 'hi :tha',
        ctx: ctx,
        emoji: '👍',
      );
      expect(result.text, 'hi 👍 ');
      expect(result.caret, 'hi 👍 '.length);
    });

    test('preserves text after the caret', () {
      final ctx = detectEmojiPartial(text: 'see :hea world', caret: 8)!;
      final result = applyEmojiPartialInsert(
        text: 'see :hea world',
        ctx: ctx,
        emoji: '❤️',
      );
      expect(result.text, 'see ❤️  world');
    });
  });

  group('expandEmojiShortcuts', () {
    test('does nothing when caret is not after a closing colon', () {
      final r = expandEmojiShortcuts(text: 'hello :thumbsup', caret: 15);
      expect(r.unchanged, isTrue);
      expect(r.text, 'hello :thumbsup');
    });

    test('expands at the moment the closing : is typed', () {
      // text: "hello :thumbsup:" — caret right after the last colon.
      final r = expandEmojiShortcuts(
        text: 'hello :thumbsup:',
        caret: 16,
      );
      expect(r.unchanged, isFalse);
      expect(r.text, 'hello 👍');
      expect(r.caret, 'hello 👍'.length);
    });

    test('keeps trailing text after the closing colon intact', () {
      final r = expandEmojiShortcuts(
        text: 'hi :clap: there',
        caret: 9,
      );
      expect(r.unchanged, isFalse);
      expect(r.text, 'hi 👏 there');
    });

    test('unrecognised :foo: is left literal', () {
      final r = expandEmojiShortcuts(
        text: 'hello :asdfgh:',
        caret: 14,
      );
      expect(r.unchanged, isTrue);
      expect(r.text, 'hello :asdfgh:');
    });

    test('fires at start of text', () {
      final r = expandEmojiShortcuts(text: ':heart:', caret: 7);
      expect(r.unchanged, isFalse);
      expect(r.text, '❤️');
    });

    test('does NOT fire when opener is mid-token (e.g. ratio)', () {
      // "5:30" + closing colon "5:30:" — the opener `:` is preceded
      // by a digit, not whitespace, so we leave it alone.
      final r = expandEmojiShortcuts(text: '5:30:', caret: 5);
      expect(r.unchanged, isTrue);
    });

    test('empty keyword (`::`) is a no-op', () {
      final r = expandEmojiShortcuts(text: '::', caret: 2);
      expect(r.unchanged, isTrue);
    });

    test('case-insensitive keyword match', () {
      final r = expandEmojiShortcuts(text: ':HEART:', caret: 7);
      expect(r.unchanged, isFalse);
      expect(r.text, '❤️');
    });

    test('bound: caret out of range returns unchanged', () {
      expect(expandEmojiShortcuts(text: 'hi', caret: -1).unchanged, isTrue);
      expect(expandEmojiShortcuts(text: 'hi', caret: 99).unchanged, isTrue);
      expect(expandEmojiShortcuts(text: 'hi', caret: 0).unchanged, isTrue);
    });
  });
}
