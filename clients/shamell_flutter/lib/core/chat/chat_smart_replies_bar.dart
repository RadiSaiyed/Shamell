import 'package:flutter/material.dart';

import 'chat_smart_replies.dart';

/// Cycle 12: chip strip the chat page renders above the composer
/// when it has 1..3 smart-reply suggestions for the last incoming
/// message. Designed to slot into the existing composer column with
/// no padding around it — the caller controls vertical spacing.
///
/// The widget is dumb on purpose: it doesn't fetch suggestions, it
/// just renders the list the caller passes. The chat page owns the
/// "should we even compute suggestions right now?" decision.
class ChatSmartRepliesBar extends StatelessWidget {
  /// Suggestions to render. Empty list collapses to `SizedBox.shrink`
  /// so callers can stick this in their column unconditionally.
  final List<ChatSmartReply> replies;

  /// Invoked when the user taps a chip. Caller typically writes the
  /// text into the composer's TextEditingController and focuses it.
  /// The bar does NOT auto-send — the user reviews + presses Send.
  final void Function(ChatSmartReply reply) onPick;

  /// Optional dismiss callback. When present, a small × button is
  /// rendered at the trailing edge so users can hide the bar for
  /// this message. The chat page typically tracks "dismissed for
  /// message id X" so the bar doesn't reappear on rebuild.
  final VoidCallback? onDismiss;

  const ChatSmartRepliesBar({
    super.key,
    required this.replies,
    required this.onPick,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final r in replies) ...<Widget>[
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome, size: 16),
                      label: Text(r.text),
                      onPressed: () => onPick(r),
                      tooltip: _categoryTooltip(r.category),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  /// Short a11y label per category — surfaced via the chip's
  /// `tooltip`. Doesn't need to be perfect prose; helps screen
  /// readers explain WHY the suggestion was offered.
  static String _categoryTooltip(String category) {
    switch (category) {
      case 'thanks':
        return 'thank-you reply';
      case 'greeting':
        return 'greeting reply';
      case 'goodbye':
        return 'goodbye reply';
      case 'time':
        return 'time-of-arrival reply';
      case 'yes_no':
        return 'quick yes/no reply';
      default:
        return 'smart reply';
    }
  }
}
