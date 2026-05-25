import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cycle 17 — render text with URLs as tappable spans.
///
/// The widget keeps the surrounding text untouched and wraps each
/// URL substring in a `TextSpan` with a `TapGestureRecognizer`. Tap
/// → `launchUrl` in the system browser; long-press optionally
/// surfaces the raw URL via the caller's [onLongPressUrl] callback
/// (useful for a future "Copy link" affordance).
///
/// The widget is deliberately dumb: it doesn't fetch link previews,
/// doesn't sanitise (other than the regex match), and doesn't open
/// URLs that don't start with `http(s)://`. The chat page wraps it
/// in the bubble container.
class ChatLinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow overflow;
  final void Function(String url)? onLongPressUrl;
  /// Override the URL-launch behaviour. Defaults to
  /// `launchUrl(uri, mode: externalApplication)`. Useful in tests
  /// to capture the URL without actually launching.
  final Future<bool> Function(Uri uri)? launchOverride;

  const ChatLinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.onLongPressUrl,
    this.launchOverride,
  });

  /// Public for tests: the regex used to detect URLs. Matches
  ///   * `http://...` / `https://...`
  ///   * `tel:+12025550100` / `mailto:foo@bar.com` (Cycle 22)
  ///   * bare `www.example.com` (Cycle 22 — normalised to https:// at tap)
  /// All variants stop at the first whitespace. Trailing `.,;)!?:`
  /// after the URL is excluded via [trimTrailingPunctuation] so
  /// "see https://x.com." doesn't capture the dot.
  static final RegExp urlRegex = RegExp(
    r'(?:https?://|tel:|mailto:|www\.)[^\s<>]+',
    caseSensitive: false,
  );

  /// Cycle 22 — bare-domain rewriter. `www.example.com` is
  /// rewritten to `https://www.example.com` so [launchUrl] (which
  /// requires a scheme) can fire. `tel:` / `mailto:` already carry
  /// a scheme; `http(s)` URLs pass through untouched.
  static String normalizeUrlForLaunch(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('tel:') ||
        lower.startsWith('mailto:')) {
      return url;
    }
    if (lower.startsWith('www.')) return 'https://$url';
    return url;
  }

  /// Cycle 18 — minimal Markdown subset the widget renders inline:
  /// `**bold**`, `__italic__`, and `` `monospace` `` (single
  /// backticks). The patterns are non-greedy + bounded to a single
  /// line so an unmatched delimiter doesn't swallow the rest of
  /// the message. Order of detection matters: bold (`**...**`)
  /// runs before italic (`__..._`) before monospace, with the
  /// surviving non-markdown ranges piped through `urlRegex` for
  /// tappable URLs.
  static final RegExp _mdBoldRegex = RegExp(r'\*\*([^*\n]+?)\*\*');
  static final RegExp _mdItalicRegex = RegExp(r'__([^_\n]+?)__');
  static final RegExp _mdMonoRegex = RegExp(r'`([^`\n]+?)`');

  /// Trim trailing punctuation that's typically NOT part of a URL.
  /// Mirrors how Slack / WhatsApp surface links.
  static String trimTrailingPunctuation(String url) {
    var end = url.length;
    const stripChars = {'.', ',', ';', '!', '?', ':', ')', ']', '}', '\''};
    while (end > 0 && stripChars.contains(url[end - 1])) {
      end -= 1;
    }
    return url.substring(0, end);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final effLinkStyle = linkStyle ??
        baseStyle.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        );

    // Cycle 18: tokenize the source into markdown-styled segments
    // first, then walk each non-monospace segment through the URL
    // linkify pass so URLs inside `code` spans stay literal.
    final mdSegs = tokenizeMarkdown(text);
    final spans = <InlineSpan>[];
    bool hadInteractive = false;
    for (final seg in mdSegs) {
      final isBold = seg.style == ChatTextStyle.bold;
      final isItalic = seg.style == ChatTextStyle.italic;
      final isMono = seg.style == ChatTextStyle.mono;
      final styledBase = baseStyle.copyWith(
        fontWeight: isBold ? FontWeight.w700 : null,
        fontStyle: isItalic ? FontStyle.italic : null,
        fontFamily: isMono ? 'monospace' : null,
        backgroundColor:
            isMono ? theme.colorScheme.surfaceContainerHighest : null,
      );
      if (isMono) {
        // No linkify inside code spans.
        spans.add(TextSpan(text: seg.text, style: styledBase));
        continue;
      }
      // Linkify this styled segment's text.
      int cursor = 0;
      for (final m in urlRegex.allMatches(seg.text)) {
        if (m.start > cursor) {
          spans.add(TextSpan(
              text: seg.text.substring(cursor, m.start), style: styledBase));
        }
        final raw = seg.text.substring(m.start, m.end);
        final clean = trimTrailingPunctuation(raw);
        final trailing = raw.substring(clean.length);
        spans.add(_buildLinkSpan(clean, effLinkStyle.merge(styledBase)));
        hadInteractive = true;
        if (trailing.isNotEmpty) {
          spans.add(TextSpan(text: trailing, style: styledBase));
        }
        cursor = m.end;
      }
      if (cursor < seg.text.length) {
        spans.add(
            TextSpan(text: seg.text.substring(cursor), style: styledBase));
      }
    }

    final isPlainText = !hadInteractive &&
        mdSegs.length == 1 &&
        mdSegs.first.style == ChatTextStyle.plain;
    if (isPlainText) {
      // No URLs detected AND no markdown styling — fall back to a
      // plain Text so the caller's semantics (selection, a11y) match
      // the pre-Cycle-17 behaviour.
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  InlineSpan _buildLinkSpan(String url, TextStyle linkStyle) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () async {
        final normalised = normalizeUrlForLaunch(url);
        final uri = Uri.tryParse(normalised);
        if (uri == null) return;
        if (launchOverride != null) {
          await launchOverride!(uri);
          return;
        }
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      };
    return TextSpan(
      text: url,
      style: linkStyle,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.click,
      onEnter: onLongPressUrl == null ? null : (_) {},
    );
  }

  /// Public for tests: split `raw` into Markdown-classified segments.
  /// Patterns are scanned left-to-right with no overlap; an unmatched
  /// delimiter (e.g. lonely `**`) is kept literal so the user sees
  /// what they typed instead of cascading style.
  static List<ChatTextSegment> tokenizeMarkdown(String raw) {
    if (raw.isEmpty) return const <ChatTextSegment>[];
    final out = <ChatTextSegment>[];
    int i = 0;
    while (i < raw.length) {
      // Try each pattern at position i, longest-prefix wins. Bold's
      // `**` would otherwise be eaten by italic / mono regexes.
      final mono = _matchAtIndex(raw, i, _mdMonoRegex);
      final bold = _matchAtIndex(raw, i, _mdBoldRegex);
      final italic = _matchAtIndex(raw, i, _mdItalicRegex);
      Match? hit;
      ChatTextStyle? style;
      if (mono != null) {
        hit = mono;
        style = ChatTextStyle.mono;
      } else if (bold != null) {
        hit = bold;
        style = ChatTextStyle.bold;
      } else if (italic != null) {
        hit = italic;
        style = ChatTextStyle.italic;
      }
      if (hit != null && style != null && hit.group(1) != null) {
        out.add(ChatTextSegment(hit.group(1)!, style));
        i = hit.end;
        continue;
      }
      // No pattern matched at i — scan ahead for the next opener so
      // we can emit a plain segment up to it.
      int next = raw.length;
      for (final pattern in <RegExp>[
        _mdMonoRegex,
        _mdBoldRegex,
        _mdItalicRegex,
      ]) {
        final m = pattern.firstMatch(raw.substring(i));
        if (m != null) {
          final globalStart = i + m.start;
          if (globalStart < next) next = globalStart;
        }
      }
      out.add(ChatTextSegment(raw.substring(i, next), ChatTextStyle.plain));
      i = next;
    }
    // Coalesce consecutive plain segments (shouldn't happen but
    // defensive against future regex tweaks).
    final merged = <ChatTextSegment>[];
    for (final s in out) {
      if (merged.isNotEmpty &&
          merged.last.style == ChatTextStyle.plain &&
          s.style == ChatTextStyle.plain) {
        merged[merged.length - 1] = ChatTextSegment(
            merged.last.text + s.text, ChatTextStyle.plain);
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  /// Returns a match anchored at `index` (i.e. `m.start == index`),
  /// or `null` when the pattern doesn't fire at that exact spot.
  static Match? _matchAtIndex(String raw, int index, RegExp pattern) {
    final m = pattern.matchAsPrefix(raw, index);
    return m;
  }
}

/// Cycle 18: classification of a tokenized markdown span.
enum ChatTextStyle { plain, bold, italic, mono }

/// Result of [ChatLinkifiedText.tokenizeMarkdown]. The `text` is the
/// inner content (delimiters stripped); `style` says how to render.
class ChatTextSegment {
  final String text;
  final ChatTextStyle style;
  const ChatTextSegment(this.text, this.style);

  @override
  bool operator ==(Object other) =>
      other is ChatTextSegment && other.text == text && other.style == style;
  @override
  int get hashCode => Object.hash(text, style);
  @override
  String toString() => 'ChatTextSegment(${style.name}: "$text")';
}

