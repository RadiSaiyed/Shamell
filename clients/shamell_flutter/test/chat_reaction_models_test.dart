import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_reaction_models.dart';

void main() {
  group('ChatReactionSummary.fromJson', () {
    test('parses a complete server payload', () {
      final s = ChatReactionSummary.fromJson(<String, Object?>{
        'emoji': '👍',
        'count': 3,
        'has_me': true,
      });
      expect(s, isNotNull);
      expect(s!.emoji, '👍');
      expect(s.count, 3);
      expect(s.hasMe, isTrue);
    });

    test('returns null for missing emoji', () {
      expect(
        ChatReactionSummary.fromJson(<String, Object?>{
          'count': 1,
          'has_me': false,
        }),
        isNull,
      );
    });

    test('returns null for empty emoji string', () {
      expect(
        ChatReactionSummary.fromJson(<String, Object?>{
          'emoji': '   ',
          'count': 1,
          'has_me': false,
        }),
        isNull,
      );
    });

    test('coerces count from num / string forms', () {
      // Some JSON libraries deserialise integers as doubles or strings;
      // the parser should accept both.
      expect(
        ChatReactionSummary.fromJson(<String, Object?>{
          'emoji': '❤️',
          'count': 2.0,
          'has_me': false,
        })!
            .count,
        2,
      );
      expect(
        ChatReactionSummary.fromJson(<String, Object?>{
          'emoji': '❤️',
          'count': '5',
          'has_me': false,
        })!
            .count,
        5,
      );
      expect(
        ChatReactionSummary.fromJson(<String, Object?>{
          'emoji': '❤️',
          'count': 'not-a-number',
          'has_me': false,
        })!
            .count,
        0,
      );
    });

    test('hasMe defaults to false when missing or non-true', () {
      expect(
        ChatReactionSummary.fromJson(<String, Object?>{
          'emoji': '🙏',
          'count': 1,
        })!
            .hasMe,
        isFalse,
      );
      expect(
        ChatReactionSummary.fromJson(<String, Object?>{
          'emoji': '🙏',
          'count': 1,
          'has_me': 'yes',
        })!
            .hasMe,
        isFalse,
        reason: 'only the literal `true` boolean counts',
      );
    });

    test('tolerates non-map raw input', () {
      expect(ChatReactionSummary.fromJson(null), isNull);
      expect(ChatReactionSummary.fromJson('👍'), isNull);
      expect(ChatReactionSummary.fromJson(42), isNull);
    });
  });

  group('ChatReactionSummary.listFromJson', () {
    test('parses a well-formed list', () {
      final list = ChatReactionSummary.listFromJson(<Object?>[
        <String, Object?>{'emoji': '👍', 'count': 2, 'has_me': true},
        <String, Object?>{'emoji': '❤️', 'count': 1, 'has_me': false},
      ]);
      expect(list, hasLength(2));
      expect(list[0].emoji, '👍');
      expect(list[1].hasMe, isFalse);
    });

    test('drops malformed entries instead of throwing', () {
      final list = ChatReactionSummary.listFromJson(<Object?>[
        <String, Object?>{'emoji': '👍', 'count': 2, 'has_me': true},
        'not-a-map',
        <String, Object?>{'count': 1}, // missing emoji
      ]);
      expect(list, hasLength(1));
      expect(list.single.emoji, '👍');
    });

    test('returns empty list for non-list payload', () {
      expect(ChatReactionSummary.listFromJson(null), isEmpty);
      expect(ChatReactionSummary.listFromJson(<String, Object?>{}), isEmpty);
      expect(ChatReactionSummary.listFromJson('foo'), isEmpty);
    });
  });

  group('equality + hashCode', () {
    test('two identical summaries are equal and hash-equal', () {
      const a = ChatReactionSummary(emoji: '👍', count: 3, hasMe: true);
      const b = ChatReactionSummary(emoji: '👍', count: 3, hasMe: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differ on any field => not equal', () {
      const base = ChatReactionSummary(emoji: '👍', count: 3, hasMe: true);
      expect(
          base,
          isNot(equals(
              const ChatReactionSummary(emoji: '❤️', count: 3, hasMe: true))));
      expect(
          base,
          isNot(equals(
              const ChatReactionSummary(emoji: '👍', count: 4, hasMe: true))));
      expect(
          base,
          isNot(equals(
              const ChatReactionSummary(emoji: '👍', count: 3, hasMe: false))));
    });
  });

  group('defaultChatReactionEmojis', () {
    test('is non-empty and contains exactly 6 entries', () {
      // The picker UI sizes itself for 6 chips on the assumption that
      // they fit on one row without scrolling. Adding/removing entries
      // is fine but worth a heads-up if the picker layout changes.
      expect(defaultChatReactionEmojis, hasLength(6));
    });

    test('all entries are non-empty strings', () {
      for (final e in defaultChatReactionEmojis) {
        expect(e.trim(), isNotEmpty);
      }
    });
  });
}
