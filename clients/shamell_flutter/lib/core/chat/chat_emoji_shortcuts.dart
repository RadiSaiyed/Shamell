// Cycle 23 — inline `:keyword:` → emoji expansion in the composer.
//
// The composer's onChanged handler calls [expandEmojiShortcuts] on
// every keystroke. When the user types a recognised `:shortcode:`
// the helper returns the rewritten text + new caret offset so the
// chat page can splice it back into the TextEditingController.
//
// Scope choices for v1:
// * Only `:keyword:` (colon-bounded) — no Slack-style :+1: without
//   the leading colon. Keeps the trigger explicit.
// * Replacement fires the moment the *closing* colon is typed, so
//   the user can keep typing past an unrecognised `:foo:` (it just
//   stays literal) without losing flow.
// * Conservative table (≈30 entries) — enough to cover the common
//   reactions WhatsApp users send. Easy to extend later.

const Map<String, String> _emojiTable = <String, String>{
  // Reactions / approval
  '+1': '👍',
  'thumbsup': '👍',
  '-1': '👎',
  'thumbsdown': '👎',
  'ok': '👌',
  'okhand': '👌',
  'pray': '🙏',
  'clap': '👏',
  'wave': '👋',
  // Emotion
  'smile': '😄',
  'grin': '😁',
  'joy': '😂',
  'rofl': '🤣',
  'laughing': '😆',
  'wink': '😉',
  'kissing_heart': '😘',
  'heart': '❤️',
  'broken_heart': '💔',
  'thinking': '🤔',
  'cry': '😢',
  'sob': '😭',
  'angry': '😠',
  'rage': '😡',
  'sleepy': '😴',
  'sweat_smile': '😅',
  // Symbols
  'fire': '🔥',
  'star': '⭐',
  'sparkles': '✨',
  '100': '💯',
  'rocket': '🚀',
  'tada': '🎉',
  'party': '🥳',
  'eyes': '👀',
  'check': '✅',
  'cross': '❌',
  // Time / scheduling
  'clock': '🕐',
  'calendar': '📅',
  'alarm': '⏰',
};

/// Result of an `:shortcode:` expansion pass over the composer
/// text. `unchanged` means the helper didn't rewrite anything — the
/// caller skips the controller update so we don't fight cursor
/// position with the user's typing.
class EmojiExpandResult {
  final String text;
  final int caret;
  final bool unchanged;
  const EmojiExpandResult({
    required this.text,
    required this.caret,
    required this.unchanged,
  });
}

/// Walk the text from the start of the longest plausible shortcut
/// preceding `caret` looking for an `:keyword:` match in
/// [_emojiTable]. When one fires, return the rewritten text +
/// adjusted caret. Multi-pass: a second shortcut earlier in the
/// same string is left alone — the user will hit it on the next
/// keystroke. Keeps this O(N) per keystroke instead of O(N²).
EmojiExpandResult expandEmojiShortcuts({
  required String text,
  required int caret,
}) {
  if (caret <= 0 || caret > text.length) {
    return EmojiExpandResult(text: text, caret: caret, unchanged: true);
  }
  // Only fire when the char immediately before `caret` is the
  // closing colon. Prevents firing on every keystroke before the
  // user actually closed the shortcode.
  if (text[caret - 1] != ':') {
    return EmojiExpandResult(text: text, caret: caret, unchanged: true);
  }
  // Scan backwards for the matching opening `:`. Max shortcut length
  // is bounded so we don't walk arbitrarily far.
  const maxShortcutLen = 32;
  final scanStart = caret - 2;
  if (scanStart < 0) {
    return EmojiExpandResult(text: text, caret: caret, unchanged: true);
  }
  int openIdx = -1;
  for (int i = scanStart;
      i >= 0 && i >= caret - 2 - maxShortcutLen;
      i--) {
    final ch = text[i];
    if (ch == ':') {
      openIdx = i;
      break;
    }
    if (ch == ' ' || ch == '\n' || ch == '\t') break;
  }
  if (openIdx < 0 || openIdx == caret - 1) {
    return EmojiExpandResult(text: text, caret: caret, unchanged: true);
  }
  final keyword = text.substring(openIdx + 1, caret - 1).toLowerCase();
  if (keyword.isEmpty) {
    return EmojiExpandResult(text: text, caret: caret, unchanged: true);
  }
  final emoji = _emojiTable[keyword];
  if (emoji == null) {
    return EmojiExpandResult(text: text, caret: caret, unchanged: true);
  }
  // Validate the char BEFORE the opening colon is whitespace or
  // start-of-text. Prevents firing on `a:foo:b` where the user
  // probably meant a ratio / range.
  if (openIdx > 0) {
    final prev = text[openIdx - 1];
    if (!(prev == ' ' || prev == '\n' || prev == '\t')) {
      return EmojiExpandResult(text: text, caret: caret, unchanged: true);
    }
  }
  final before = text.substring(0, openIdx);
  final after = text.substring(caret);
  final newText = '$before$emoji$after';
  final newCaret = before.length + emoji.length;
  return EmojiExpandResult(
    text: newText,
    caret: newCaret,
    unchanged: false,
  );
}

/// Public for tests/debugging: count of supported shortcuts.
int emojiShortcutTableSize() => _emojiTable.length;

/// Public for tests: lookup a shortcut directly.
String? emojiForShortcut(String keyword) => _emojiTable[keyword.toLowerCase()];

/// Cycle 24 — one suggestion in the inline emoji popover.
class EmojiSuggestion {
  final String shortcut;
  final String emoji;
  const EmojiSuggestion({required this.shortcut, required this.emoji});
}

/// Cycle 24 — context describing an in-progress `:partial` the
/// composer is mid-typing. `null` means "no popover" (caret not in
/// an emoji partial). The chat page reads `.prefix`, fetches
/// matches via [suggestEmojiCompletions], and renders a chip row.
class EmojiPartialContext {
  final int openColonIdx;
  final int caret;
  final String prefix;
  const EmojiPartialContext({
    required this.openColonIdx,
    required this.caret,
    required this.prefix,
  });
}

/// Detect whether the caret is inside an open `:partial` emoji
/// shortcut (no closing `:` yet). Returns the context for the
/// caller to filter the candidate list; `null` if the caret isn't
/// in such a window.
///
/// Rules mirror [expandEmojiShortcuts]:
/// * Opening `:` must be at start-of-text or preceded by whitespace.
/// * Partial must be non-empty (avoid showing a popover on every
///   bare `:` keystroke — too noisy).
/// * Partial must be ≤ 32 chars + contain only `[a-z0-9_+-]`.
EmojiPartialContext? detectEmojiPartial({
  required String text,
  required int caret,
}) {
  if (caret <= 0 || caret > text.length) return null;
  int i = caret;
  while (i > 0) {
    final ch = text[i - 1];
    if (ch == ':') {
      final openIdx = i - 1;
      // Validate the char BEFORE the opening `:` is whitespace or
      // start-of-text.
      if (openIdx > 0) {
        final prev = text[openIdx - 1];
        if (!(prev == ' ' || prev == '\n' || prev == '\t')) return null;
      }
      final prefix = text.substring(openIdx + 1, caret).toLowerCase();
      if (prefix.isEmpty) return null;
      // Validate prefix charset.
      for (final r in prefix.runes) {
        final c = String.fromCharCode(r);
        if (!_isShortcutChar(c)) return null;
      }
      return EmojiPartialContext(
        openColonIdx: openIdx,
        caret: caret,
        prefix: prefix,
      );
    }
    if (ch == ' ' || ch == '\n' || ch == '\t') return null;
    i -= 1;
    if (caret - i > 32) return null;
  }
  return null;
}

bool _isShortcutChar(String c) {
  if (c.isEmpty) return false;
  final code = c.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || // 0-9
      (code >= 0x61 && code <= 0x7A) || // a-z
      code == 0x5F || // _
      code == 0x2B || // +
      code == 0x2D; // -
}

/// Return up to [limit] emoji shortcuts whose keys match `prefix`.
/// Scoring matches [scoreMentionMatch]'s style: starts-with wins
/// over substring. Sorted highest-score first, then alphabetical.
List<EmojiSuggestion> suggestEmojiCompletions({
  required String prefix,
  int limit = 8,
}) {
  if (prefix.isEmpty) return const <EmojiSuggestion>[];
  final p = prefix.toLowerCase();
  final ranked = <(int, EmojiSuggestion)>[];
  for (final entry in _emojiTable.entries) {
    final k = entry.key;
    int score;
    if (k.startsWith(p)) {
      score = 10;
    } else if (k.contains(p)) {
      score = 3;
    } else {
      score = 0;
    }
    if (score == 0) continue;
    ranked.add(
      (score, EmojiSuggestion(shortcut: k, emoji: entry.value)),
    );
  }
  ranked.sort((a, b) {
    final byScore = b.$1 - a.$1;
    if (byScore != 0) return byScore;
    return a.$2.shortcut.compareTo(b.$2.shortcut);
  });
  return ranked.take(limit).map((e) => e.$2).toList(growable: false);
}

/// Apply a tap-to-insert from the emoji popover: replace the
/// `:partial` range with the chosen emoji + a trailing space, and
/// return the new text + caret offset.
({String text, int caret}) applyEmojiPartialInsert({
  required String text,
  required EmojiPartialContext ctx,
  required String emoji,
}) {
  final before = text.substring(0, ctx.openColonIdx);
  final after = text.substring(ctx.caret);
  final inserted = '$emoji ';
  final merged = '$before$inserted$after';
  final newCaret = before.length + inserted.length;
  return (text: merged, caret: newCaret);
}
