/// Cycle 12 — heuristic smart-replies.
///
/// Given the last incoming message in the active conversation, return
/// up to 3 short reply suggestions the chat page surfaces as chips
/// above the composer. Tapping a chip pre-fills the composer (it
/// does NOT auto-send — the user reviews + presses Send normally).
///
/// This is a pure-Dart heuristic, no ML, no server calls. The design
/// goal is "useful when obviously correct, invisible otherwise":
/// false-positive chips that miss the message are worse than no
/// chips at all, so the matcher is intentionally conservative.

/// One reply suggestion. `text` is what gets inserted into the
/// composer; `category` is a stable identifier for analytics / a11y
/// (e.g. "yes_no", "greeting", "thanks").
class ChatSmartReply {
  final String text;
  final String category;
  const ChatSmartReply({required this.text, required this.category});
}

/// Returns 0..3 suggestions for `lastIncomingText`. Empty list means
/// "no chip-worthy match" — the caller hides the bar.
List<ChatSmartReply> suggestSmartReplies({
  required String lastIncomingText,
  required bool isArabic,
}) {
  final raw = lastIncomingText.trim();
  if (raw.isEmpty) return const <ChatSmartReply>[];

  // Lower-case for the keyword matchers; the actual chip text uses
  // the localised verbatim string so casing comes out right.
  final lower = raw.toLowerCase();
  final out = <ChatSmartReply>[];

  // ── Thanks → "You're welcome" style.
  if (_containsAny(lower, _thanksKeywords(isArabic))) {
    out.addAll(_thanksReplies(isArabic));
    return _take3(out);
  }

  // ── Greeting → matching greeting.
  if (_isGreeting(lower, isArabic)) {
    out.addAll(_greetingReplies(isArabic));
    return _take3(out);
  }

  // ── Goodbye / good-night.
  if (_containsAny(lower, _goodbyeKeywords(isArabic))) {
    out.addAll(_goodbyeReplies(isArabic));
    return _take3(out);
  }

  // ── Time question ("when?", "what time?") → time options.
  if (_isTimeQuestion(lower, isArabic)) {
    out.addAll(_timeReplies(isArabic));
    return _take3(out);
  }

  // ── Question (ends with ?) — generic Yes / No / Let-me-check.
  // This is the broadest matcher, so it runs last; the specialised
  // categories above already short-circuited the obvious cases.
  if (_endsWithQuestionMark(raw)) {
    out.addAll(_yesNoReplies(isArabic));
    return _take3(out);
  }

  return const <ChatSmartReply>[];
}

// ───────────────────────── matchers ─────────────────────────

bool _containsAny(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(n)) return true;
  }
  return false;
}

bool _isGreeting(String lower, bool isArabic) {
  // Greetings are usually at the START of a message ("hi, how are
  // you?"), so look at the first ~12 chars. Catches "hi there" but
  // doesn't false-positive on "I said hi to her earlier".
  final head = lower.substring(0, lower.length.clamp(0, 16));
  final keys = isArabic
      ? const <String>['مرحبا', 'مرحباً', 'أهلا', 'أهلاً', 'السلام عليكم']
      : const <String>[
          'hi',
          'hello',
          'hey',
          'good morning',
          'good afternoon',
          'good evening',
          'morning',
          'howdy',
        ];
  // For very short keys ("hi", "hey") require a word boundary so we
  // don't match "history" → "hi".
  for (final k in keys) {
    if (k.length >= 4) {
      if (head.contains(k)) return true;
    } else {
      if (head == k) return true;
      if (head.startsWith('$k ') || head.startsWith('$k,') || head.startsWith('$k!')) {
        return true;
      }
    }
  }
  return false;
}

bool _isTimeQuestion(String lower, bool isArabic) {
  if (!_endsWithQuestionMark(lower) &&
      !_containsAny(lower, isArabic
          ? const <String>['متى', 'كم الساعة']
          : const <String>['when ', 'when?', 'what time', 'how long'])) {
    return false;
  }
  return _containsAny(
    lower,
    isArabic
        ? const <String>['متى', 'كم الساعة', 'ساعة']
        : const <String>['when', 'what time', 'how long'],
  );
}

bool _endsWithQuestionMark(String raw) {
  if (raw.isEmpty) return false;
  final last = raw[raw.length - 1];
  return last == '?' || last == '؟';
}

// ───────────────────────── locale lookups ─────────────────────────

List<String> _thanksKeywords(bool isArabic) => isArabic
    ? const <String>['شكرا', 'شكراً', 'متشكر', 'ممنون']
    : const <String>['thank', 'thanks', 'thx', 'thnx', 'ty '];

List<ChatSmartReply> _thanksReplies(bool isArabic) => isArabic
    ? const <ChatSmartReply>[
        ChatSmartReply(text: 'العفو!', category: 'thanks'),
        ChatSmartReply(text: 'في أي وقت', category: 'thanks'),
        ChatSmartReply(text: '🙏', category: 'thanks'),
      ]
    : const <ChatSmartReply>[
        ChatSmartReply(text: "You're welcome!", category: 'thanks'),
        ChatSmartReply(text: 'Anytime', category: 'thanks'),
        ChatSmartReply(text: 'Glad to help 🙂', category: 'thanks'),
      ];

List<ChatSmartReply> _greetingReplies(bool isArabic) => isArabic
    ? const <ChatSmartReply>[
        ChatSmartReply(text: 'مرحبا! 👋', category: 'greeting'),
        ChatSmartReply(text: 'أهلاً', category: 'greeting'),
        ChatSmartReply(text: 'كيف حالك؟', category: 'greeting'),
      ]
    : const <ChatSmartReply>[
        ChatSmartReply(text: 'Hi! 👋', category: 'greeting'),
        ChatSmartReply(text: 'Hey!', category: 'greeting'),
        ChatSmartReply(text: 'How are you?', category: 'greeting'),
      ];

List<String> _goodbyeKeywords(bool isArabic) => isArabic
    ? const <String>['وداعا', 'إلى اللقاء', 'تصبح على خير', 'مع السلامة']
    : const <String>['bye', 'goodnight', 'good night', 'see you', 'talk later'];

List<ChatSmartReply> _goodbyeReplies(bool isArabic) => isArabic
    ? const <ChatSmartReply>[
        ChatSmartReply(text: 'مع السلامة 👋', category: 'goodbye'),
        ChatSmartReply(text: 'تصبح على خير', category: 'goodbye'),
        ChatSmartReply(text: 'إلى اللقاء', category: 'goodbye'),
      ]
    : const <ChatSmartReply>[
        ChatSmartReply(text: 'Bye! 👋', category: 'goodbye'),
        ChatSmartReply(text: 'See you', category: 'goodbye'),
        ChatSmartReply(text: 'Good night', category: 'goodbye'),
      ];

List<ChatSmartReply> _timeReplies(bool isArabic) => isArabic
    ? const <ChatSmartReply>[
        ChatSmartReply(text: 'خلال 10 دقائق', category: 'time'),
        ChatSmartReply(text: 'خلال نصف ساعة', category: 'time'),
        ChatSmartReply(text: 'في غضون ساعة', category: 'time'),
      ]
    : const <ChatSmartReply>[
        ChatSmartReply(text: 'In 10 minutes', category: 'time'),
        ChatSmartReply(text: 'In about half an hour', category: 'time'),
        ChatSmartReply(text: 'Within the hour', category: 'time'),
      ];

List<ChatSmartReply> _yesNoReplies(bool isArabic) => isArabic
    ? const <ChatSmartReply>[
        ChatSmartReply(text: 'نعم', category: 'yes_no'),
        ChatSmartReply(text: 'لا', category: 'yes_no'),
        ChatSmartReply(text: 'دعني أتحقق', category: 'yes_no'),
      ]
    : const <ChatSmartReply>[
        ChatSmartReply(text: 'Yes', category: 'yes_no'),
        ChatSmartReply(text: 'No', category: 'yes_no'),
        ChatSmartReply(text: 'Let me check', category: 'yes_no'),
      ];

List<ChatSmartReply> _take3(List<ChatSmartReply> all) =>
    all.length <= 3 ? all : all.sublist(0, 3);
