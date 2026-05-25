import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_reaction_recent.dart';

void main() {
  group('topReactionEmojis', () {
    test('empty counts → default slate', () {
      final r = topReactionEmojis(counts: const <String, int>{});
      expect(r, defaultEmojiSlate.take(6).toList());
    });

    test('user-history emoji takes the top slot', () {
      final r = topReactionEmojis(counts: const <String, int>{'🚀': 5});
      // 🚀 wasn't in defaults; it now leads the row.
      expect(r.first, '🚀');
    });

    test('multiple user picks rank by count', () {
      final r = topReactionEmojis(counts: const <String, int>{
        '🔥': 10,
        '🚀': 4,
        '👍': 2,
      });
      expect(r[0], '🔥');
      // 🚀 (4) vs 👍 (2) vs other defaults (0) → 🚀 next.
      expect(r[1], '🚀');
      expect(r[2], '👍');
    });

    test('default slate fills the trailing slots when history is sparse',
        () {
      final r = topReactionEmojis(counts: const <String, int>{'🔥': 1});
      expect(r.first, '🔥');
      // The rest are defaults (excluding 🔥 which isn't in defaults).
      expect(r.skip(1).every(defaultEmojiSlate.contains), isTrue);
    });

    test('respects limit', () {
      expect(topReactionEmojis(counts: const <String, int>{}, limit: 3),
          hasLength(3));
    });
  });

  group('bumpReactionCount', () {
    test('+1 on first use', () {
      final next = bumpReactionCount(counts: const <String, int>{}, emoji: '👍');
      expect(next['👍'], 1);
    });

    test('+1 cumulative', () {
      final next = bumpReactionCount(
        counts: const <String, int>{'👍': 4},
        emoji: '👍',
      );
      expect(next['👍'], 5);
    });

    test('evicts lowest-count when over cap', () {
      final saturated = <String, int>{};
      for (int i = 0; i < 32; i++) {
        saturated['e$i'] = i;
      }
      // e0 has count 0 — should be evicted when we add a 33rd.
      final next = bumpReactionCount(counts: saturated, emoji: '🆕');
      expect(next.containsKey('e0'), isFalse);
      expect(next['🆕'], 1);
    });
  });
}
