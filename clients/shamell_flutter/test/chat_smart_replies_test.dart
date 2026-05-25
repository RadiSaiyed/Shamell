import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_smart_replies.dart';

List<String> _texts(List<ChatSmartReply> rs) => rs.map((r) => r.text).toList();

void main() {
  group('suggestSmartReplies — English', () {
    test('empty input -> no chips', () {
      expect(
        suggestSmartReplies(lastIncomingText: '', isArabic: false),
        isEmpty,
      );
      expect(
        suggestSmartReplies(lastIncomingText: '   ', isArabic: false),
        isEmpty,
      );
    });

    test('plain statement (no markers) -> no chips', () {
      // Heuristic intentionally returns nothing when no obvious
      // category matches — empty bar is better than wrong chips.
      expect(
        suggestSmartReplies(
          lastIncomingText: 'I went to the store earlier',
          isArabic: false,
        ),
        isEmpty,
      );
    });

    test('"thanks" -> welcome / anytime / glad', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'Hey, thanks for the help!',
        isArabic: false,
      );
      expect(rs, hasLength(3));
      expect(rs.every((r) => r.category == 'thanks'), isTrue);
      expect(_texts(rs), contains("You're welcome!"));
    });

    test('"thx" abbreviation -> thanks branch', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'thx 👍',
        isArabic: false,
      );
      expect(rs.first.category, 'thanks');
    });

    test('greeting at start -> greeting branch', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'Hi there!',
        isArabic: false,
      );
      expect(rs.first.category, 'greeting');
      expect(_texts(rs), contains('Hi! 👋'));
    });

    test('greeting mid-sentence does NOT trigger greeting branch', () {
      // "I told her hi already" -> should not be classified as a
      // greeting (false-positive guard via head-of-message check).
      final rs = suggestSmartReplies(
        lastIncomingText: 'I just had to say hi to her earlier today',
        isArabic: false,
      );
      // No category should match cleanly — empty.
      expect(rs, isEmpty);
    });

    test('"history" should NOT trigger "hi" greeting match', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'history is fun',
        isArabic: false,
      );
      expect(rs, isEmpty);
    });

    test('goodbye -> bye branch', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'see you tomorrow',
        isArabic: false,
      );
      expect(rs.first.category, 'goodbye');
    });

    test('time question -> time branch', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'when are you coming?',
        isArabic: false,
      );
      expect(rs.first.category, 'time');
      expect(_texts(rs), contains('In 10 minutes'));
    });

    test('generic question -> yes/no branch', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'Did you finish the report?',
        isArabic: false,
      );
      expect(rs.first.category, 'yes_no');
      expect(_texts(rs), <String>['Yes', 'No', 'Let me check']);
    });

    test('thanks beats greeting when both keywords appear', () {
      // "Hi, thanks for the file" has both "hi" and "thanks" — the
      // matcher checks thanks first (more specific signal).
      final rs = suggestSmartReplies(
        lastIncomingText: 'Hi, thanks for the file!',
        isArabic: false,
      );
      expect(rs.first.category, 'thanks');
    });

    test('result is capped at 3 chips', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'Did you get it?',
        isArabic: false,
      );
      expect(rs.length, lessThanOrEqualTo(3));
    });
  });

  group('suggestSmartReplies — Arabic', () {
    test('thanks (shukran) -> العفو etc.', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'شكرا جزيلا',
        isArabic: true,
      );
      expect(rs, hasLength(3));
      expect(rs.first.category, 'thanks');
      expect(_texts(rs), contains('العفو!'));
    });

    test('greeting (marhaba) -> Arabic greeting branch', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'مرحبا كيف حالك',
        isArabic: true,
      );
      expect(rs.first.category, 'greeting');
      expect(_texts(rs), contains('أهلاً'));
    });

    test('Arabic question mark (؟) triggers yes/no', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'هل أنت متفرغ؟',
        isArabic: true,
      );
      expect(rs.first.category, 'yes_no');
      expect(_texts(rs), <String>['نعم', 'لا', 'دعني أتحقق']);
    });

    test('time question (مta) -> time branch', () {
      final rs = suggestSmartReplies(
        lastIncomingText: 'متى ستصل؟',
        isArabic: true,
      );
      expect(rs.first.category, 'time');
    });
  });

  group('ChatSmartReply value class', () {
    test('exposes text + category', () {
      const r = ChatSmartReply(text: 'Yes', category: 'yes_no');
      expect(r.text, 'Yes');
      expect(r.category, 'yes_no');
    });
  });
}
