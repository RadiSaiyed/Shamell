import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_mention_completions.dart';

void main() {
  group('detectMentionContext', () {
    test('returns null when no @ present', () {
      expect(detectMentionContext(text: 'hello world', caret: 11), isNull);
    });

    test('returns null when caret is before any @', () {
      expect(detectMentionContext(text: 'hi @ali', caret: 2), isNull);
    });

    test('matches @ at start of text', () {
      final ctx = detectMentionContext(text: '@ali', caret: 4);
      expect(ctx, isNotNull);
      expect(ctx!.atStart, 0);
      expect(ctx.prefix, 'ali');
    });

    test('matches @ after whitespace', () {
      final ctx = detectMentionContext(text: 'hey @al', caret: 7);
      expect(ctx!.atStart, 4);
      expect(ctx.prefix, 'al');
    });

    test('rejects @ inside an email-style address', () {
      // `email@example.com` should NOT trigger because @ is preceded
      // by a non-whitespace char.
      final ctx =
          detectMentionContext(text: 'see you@example.com', caret: 19);
      expect(ctx, isNull);
    });

    test('rejects when whitespace appears after @ before caret', () {
      // `@al ` then more text → caret is after the space, mention
      // window already closed.
      final ctx = detectMentionContext(text: '@al hello', caret: 9);
      expect(ctx, isNull);
    });

    test('empty prefix at "@" trigger fires (full list mode)', () {
      final ctx = detectMentionContext(text: 'send @', caret: 6);
      expect(ctx, isNotNull);
      expect(ctx!.prefix, '');
    });

    test('caret not at end works (mid-edit)', () {
      // Composer text: "hey @al world", caret right after `l`.
      final ctx = detectMentionContext(text: 'hey @al world', caret: 7);
      expect(ctx, isNotNull);
      expect(ctx!.prefix, 'al');
    });
  });

  group('scoreMentionMatch', () {
    test('starts-with wins highest', () {
      expect(scoreMentionMatch(candidate: 'Alice', prefix: 'al'), 10);
    });

    test('word-start matches at +5', () {
      expect(scoreMentionMatch(candidate: 'Mr Alice', prefix: 'al'), 5);
    });

    test('substring matches at +1', () {
      expect(scoreMentionMatch(candidate: 'A Salice', prefix: 'al'), 1);
    });

    test('non-match scores 0', () {
      expect(scoreMentionMatch(candidate: 'Bob', prefix: 'al'), 0);
    });

    test('empty prefix accepts everything (score 1)', () {
      expect(scoreMentionMatch(candidate: 'Bob', prefix: ''), 1);
      expect(scoreMentionMatch(candidate: 'Alice', prefix: ''), 1);
    });
  });

  group('applyMentionInsert', () {
    test('replaces partial with canonical + space', () {
      final ctx = detectMentionContext(text: 'hi @al', caret: 6)!;
      final result = applyMentionInsert(
        text: 'hi @al',
        ctx: ctx,
        canonical: 'Alice',
      );
      expect(result.text, 'hi @Alice ');
      expect(result.caret, 'hi @Alice '.length);
    });

    test('preserves text after the caret', () {
      final ctx = detectMentionContext(text: 'hey @al world', caret: 7)!;
      final result = applyMentionInsert(
        text: 'hey @al world',
        ctx: ctx,
        canonical: 'Alice',
      );
      expect(result.text, 'hey @Alice  world');
    });

    test('canonical is trimmed', () {
      final ctx = detectMentionContext(text: '@', caret: 1)!;
      final result = applyMentionInsert(
        text: '@',
        ctx: ctx,
        canonical: '  Alice  ',
      );
      expect(result.text, '@Alice ');
    });
  });
}
