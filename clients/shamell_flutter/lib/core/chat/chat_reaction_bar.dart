import 'package:flutter/material.dart';

import 'chat_reaction_models.dart';

/// Horizontal strip of reaction chips rendered under a chat message
/// bubble (Cycle 4). Tapping a chip toggles the local user's reaction
/// (passing `(emoji, hasMe)` to [onToggle], which sets/removes
/// server-side). Tapping the trailing "+" button opens an emoji picker.
///
/// Empty `reactions` collapses to just a "+" affordance — or to nothing
/// at all if [showAddButton] is false (used in stripped-down views like
/// search results).
class ChatReactionBar extends StatelessWidget {
  /// Aggregated reaction state for this message.
  final List<ChatReactionSummary> reactions;

  /// Called when a chip is tapped. Receives the chip's emoji and the
  /// current `hasMe` so the caller knows whether to add or remove.
  /// Returning a Future is fine — the chip stays in its current visual
  /// state until the chat page re-renders with the server-confirmed
  /// new aggregation.
  final Future<void> Function(String emoji, bool hasMe)? onToggle;

  /// Called when the trailing "+" button is tapped. Typically opens a
  /// [ChatReactionPickerSheet]; passed as a callback so the page can
  /// sequence the navigator and emoji picker correctly without this
  /// widget owning the bottom-sheet logic.
  final VoidCallback? onAdd;

  /// Whether to render the trailing "+" button. Always shown when there
  /// are no reactions yet (so the user can place the first one).
  final bool showAddButton;

  /// Horizontal padding around the row. Defaults to a compact 8px so
  /// the chips hug the bubble's edge without floating in whitespace.
  final EdgeInsetsGeometry padding;

  const ChatReactionBar({
    super.key,
    required this.reactions,
    this.onToggle,
    this.onAdd,
    this.showAddButton = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (reactions.isEmpty && !showAddButton) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          for (final r in reactions)
            _ReactionChip(
              summary: r,
              onTap: onToggle == null
                  ? null
                  : () => onToggle!(r.emoji, r.hasMe),
              theme: theme,
            ),
          if (showAddButton && onAdd != null)
            _AddReactionButton(onTap: onAdd!, theme: theme),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final ChatReactionSummary summary;
  final VoidCallback? onTap;
  final ThemeData theme;

  const _ReactionChip({
    required this.summary,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final selected = summary.hasMe;
    final scheme = theme.colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: theme.brightness == Brightness.dark
            ? .22
            : .14)
        : scheme.onSurface.withValues(alpha: .06);
    final border = selected
        ? scheme.primary.withValues(alpha: .45)
        : scheme.onSurface.withValues(alpha: .12);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.2 : 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(summary.emoji, style: const TextStyle(fontSize: 14)),
              if (summary.count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  summary.count.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: .78),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddReactionButton extends StatelessWidget {
  final VoidCallback onTap;
  final ThemeData theme;

  const _AddReactionButton({required this.onTap, required this.theme});

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: .10),
            ),
          ),
          child: Icon(
            Icons.add_reaction_outlined,
            size: 16,
            color: scheme.onSurface.withValues(alpha: .62),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet emoji picker with a compact set of common chat
/// reactions. Pops with the chosen emoji string, or `null` if dismissed.
/// Designed to be opened from a long-press menu's "Add reaction" entry
/// or from the [ChatReactionBar]'s "+" button.
class ChatReactionPickerSheet extends StatelessWidget {
  /// The set of emojis to offer. Defaults to
  /// [defaultChatReactionEmojis]. Override when a conversation has a
  /// custom palette (e.g. group with admin-curated reaction set).
  final List<String> emojis;

  /// Currently-placed emoji by the local user (if any) — used to
  /// highlight which chip in the picker is "active" so re-tapping it
  /// reads as "remove this reaction".
  final String? currentEmoji;

  const ChatReactionPickerSheet({
    super.key,
    this.emojis = defaultChatReactionEmojis,
    this.currentEmoji,
  });

  /// Convenience helper: pops the sheet and returns the chosen emoji,
  /// or `null` if the user dismissed without picking.
  static Future<String?> show(
    BuildContext context, {
    List<String> emojis = defaultChatReactionEmojis,
    String? currentEmoji,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => ChatReactionPickerSheet(
        emojis: emojis,
        currentEmoji: currentEmoji,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final emoji in emojis)
              _PickerChip(
                emoji: emoji,
                selected: emoji == currentEmoji,
                onTap: () => Navigator.of(context).pop(emoji),
                theme: theme,
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _PickerChip({
    required this.emoji,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: .15)
                : scheme.onSurface.withValues(alpha: .04),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: .55)
                  : scheme.onSurface.withValues(alpha: .12),
            ),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}
