// Cycle 21 — composer-side @-mention completion helpers.
//
// Detects whether the user is currently typing an @-mention based
// on the composer's text + caret position, then matches the typed
// prefix against a candidate list. The chat page renders the
// returned suggestions as a horizontally-scrolling chip row above
// the composer; tapping a chip replaces the in-progress mention
// with `@<canonical-name> ` and advances the caret.

/// Result of [detectMentionContext]. Carries both the text region
/// that should be replaced on insert AND the partial prefix the
/// caller filters its candidate list with.
class MentionContext {
  /// Start offset (inclusive) of the `@` symbol in the composer
  /// text. Used to compute the replacement range.
  final int atStart;

  /// End offset (exclusive) — equals the caret position.
  final int caret;

  /// Lower-cased partial after `@`. May be empty when the user has
  /// just typed `@` and nothing yet — the caller still shows the
  /// full candidate list in that case.
  final String prefix;

  const MentionContext({
    required this.atStart,
    required this.caret,
    required this.prefix,
  });
}

/// Walk backwards from `caret` looking for an `@` that's preceded
/// by whitespace / start-of-text and not followed by whitespace.
/// Returns a [MentionContext] when the user is mid-mention; `null`
/// when the caret isn't inside a mention partial.
///
/// Rules:
/// * The `@` must be at the start of the composer, OR preceded by
///   whitespace. Avoids matching `email@example.com`.
/// * The text between `@` and `caret` must contain no whitespace.
/// * Empty prefix (user just typed `@`) is a valid trigger — the
///   caller shows the unfiltered candidate list.
MentionContext? detectMentionContext({
  required String text,
  required int caret,
}) {
  if (caret < 0 || caret > text.length) return null;
  // Scan backwards from caret looking for either an `@` or
  // whitespace / start-of-text.
  int i = caret;
  while (i > 0) {
    final ch = text[i - 1];
    if (ch == '@') {
      final atIdx = i - 1;
      // Validate the char BEFORE `@` is whitespace or start-of-text.
      if (atIdx == 0 || _isWhitespace(text[atIdx - 1])) {
        final prefix = text.substring(atIdx + 1, caret).toLowerCase();
        return MentionContext(
          atStart: atIdx,
          caret: caret,
          prefix: prefix,
        );
      }
      return null;
    }
    if (_isWhitespace(ch)) return null;
    i -= 1;
  }
  return null;
}

/// Score a candidate name against the typed prefix. Higher = better
/// match. `0` means no match (caller filters these out).
///
/// Scoring:
/// * `+10` if the candidate's lowercased name starts with the prefix
/// * `+5`  if any word in the candidate's name starts with the prefix
/// * `+1`  if the candidate contains the prefix as a substring
/// * `0`   otherwise
int scoreMentionMatch({required String candidate, required String prefix}) {
  if (prefix.isEmpty) return 1;
  final c = candidate.toLowerCase();
  if (c.startsWith(prefix)) return 10;
  for (final word in c.split(RegExp(r'\s+'))) {
    if (word.isNotEmpty && word.startsWith(prefix)) return 5;
  }
  if (c.contains(prefix)) return 1;
  return 0;
}

/// Compute the result of inserting `@<canonical> ` into `text` at
/// the mention context. Returns `(text, caret)` so the caller can
/// update the `TextEditingController.value`.
({String text, int caret}) applyMentionInsert({
  required String text,
  required MentionContext ctx,
  required String canonical,
}) {
  final before = text.substring(0, ctx.atStart);
  final after = text.substring(ctx.caret);
  final inserted = '@${canonical.trim()} ';
  final merged = '$before$inserted$after';
  final newCaret = before.length + inserted.length;
  return (text: merged, caret: newCaret);
}

bool _isWhitespace(String ch) {
  if (ch.isEmpty) return false;
  final code = ch.codeUnitAt(0);
  return code == 0x20 || // space
      code == 0x09 || // tab
      code == 0x0A || // newline
      code == 0x0D || // carriage return
      code == 0x00A0; // nbsp
}
