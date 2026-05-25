import 'package:flutter/material.dart';

import '../l10n.dart';

/// Small "X is typing…" banner with animated dots.
///
/// Designed to slot above the message composer. Hides itself (returns
/// `SizedBox.shrink`) when [typingNames] is empty so callers can just
/// stick it in their column unconditionally.
///
/// - 1 name → "Alice is typing…"
/// - 2 names → "Alice and Bob are typing…"
/// - 3+     → "Several people are typing…"
///
/// Localised via [L10n] — Arabic uses the appropriate verb forms via
/// `shamellTypingNamed`, `shamellTyping` and `shamellSeveralPeopleTyping`.
class ChatTypingIndicator extends StatefulWidget {
  /// Display names of people currently typing. Order is preserved for
  /// the 2-name "and" form; duplicates are caller-deduped.
  final List<String> typingNames;

  /// Override the default text style (theme's `bodySmall` in the
  /// primary colour, italic).
  final TextStyle? textStyle;

  /// Override the dot-cycle duration. Defaults to 1.2s, matching
  /// WhatsApp/Slack.
  final Duration dotCycle;

  const ChatTypingIndicator({
    super.key,
    required this.typingNames,
    this.textStyle,
    this.dotCycle = const Duration(milliseconds: 1200),
  });

  @override
  State<ChatTypingIndicator> createState() => _ChatTypingIndicatorState();
}

class _ChatTypingIndicatorState extends State<ChatTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.dotCycle)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant ChatTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dotCycle != widget.dotCycle) {
      _ctrl.duration = widget.dotCycle;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.typingNames.isEmpty) return const SizedBox.shrink();
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final style = widget.textStyle ??
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
          fontStyle: FontStyle.italic,
        );
    final text = _label(l, widget.typingNames);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Use Flexible so very long display names ellipsise instead
          // of overflowing the row.
          Flexible(
            child: Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: 18,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Text(
                _dotsForProgress(_ctrl.value),
                style: style,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns 0–3 trailing dots based on the animation phase. Cycles
  /// "" → "." → ".." → "..." → "" every `dotCycle`.
  static String _dotsForProgress(double p) {
    final phase = (p * 4).floor().clamp(0, 3);
    switch (phase) {
      case 0:
        return '';
      case 1:
        return '.';
      case 2:
        return '..';
      default:
        return '...';
    }
  }

  static String _label(L10n l, List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) {
      final n = names.first.trim();
      return n.isEmpty ? l.shamellTyping : l.shamellTypingNamed(n);
    }
    if (names.length == 2) {
      final a = names[0].trim();
      final b = names[1].trim();
      if (a.isEmpty || b.isEmpty) return l.shamellSeveralPeopleTyping;
      return l.isArabic ? '$a و $b يكتبان' : '$a and $b are typing';
    }
    return l.shamellSeveralPeopleTyping;
  }
}
