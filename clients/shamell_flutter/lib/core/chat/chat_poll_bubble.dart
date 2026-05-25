import 'package:flutter/material.dart';

import '../l10n.dart';

/// One option in a [ChatPollBubble]. Mirrors the server's per-option
/// response shape (idx + label + votes) plus a `selected` flag the
/// caller computes from `my_votes`.
class ChatPollOption {
  final int idx;
  final String label;
  final int votes;
  final bool selected;

  const ChatPollOption({
    required this.idx,
    required this.label,
    required this.votes,
    required this.selected,
  });

  /// Convert a server `option` row into the bubble model.
  factory ChatPollOption.fromMap(
    Map<String, Object?> raw, {
    required Set<int> myVotes,
  }) {
    final idx = (raw['idx'] is int)
        ? raw['idx'] as int
        : ((raw['idx'] is num) ? (raw['idx'] as num).toInt() : 0);
    final votes = (raw['votes'] is int)
        ? raw['votes'] as int
        : ((raw['votes'] is num) ? (raw['votes'] as num).toInt() : 0);
    return ChatPollOption(
      idx: idx,
      label: (raw['label'] as String?) ?? '',
      votes: votes,
      selected: myVotes.contains(idx),
    );
  }
}

/// Cycle 14 — bubble that renders a poll inside the chat thread.
/// The widget is dumb: it takes the resolved poll model + tap
/// callbacks and renders. The chat page owns the
/// `ChatService.getPoll` / `votePoll` round-trips and re-renders
/// the bubble with fresh data after each interaction.
class ChatPollBubble extends StatelessWidget {
  final String question;
  final List<ChatPollOption> options;
  final bool multiSelect;
  final bool closed;
  final int totalVoters;
  /// `true` when the calling device created the poll. The bubble
  /// surfaces a "Close" affordance only for the creator.
  final bool isCreator;
  /// Tap an option to cast / change a vote. Called with the option
  /// index; the chat page debounces and round-trips through
  /// `ChatService.votePoll`. Disabled (no callback) when `closed`.
  final void Function(int optionIdx)? onVote;
  /// Long-press a vote count to see who voted (creator-only,
  /// anonymous polls omit this affordance entirely).
  final void Function(int optionIdx)? onShowVoters;
  /// Tap "Close poll" — fires `ChatService.closePoll`.
  final VoidCallback? onClose;

  const ChatPollBubble({
    super.key,
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.closed = false,
    this.totalVoters = 0,
    this.isCreator = false,
    this.onVote,
    this.onShowVoters,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final maxVotes = options.fold<int>(0, (m, o) => o.votes > m ? o.votes : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.poll_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l.isArabic
                      ? (multiSelect ? 'استطلاع — تعدد الاختيارات' : 'استطلاع')
                      : (multiSelect ? 'Poll — multi-select' : 'Poll'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (closed)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l.isArabic ? 'مغلق' : 'closed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            question,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final opt in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: closed || onVote == null
                    ? null
                    : () => onVote!(opt.idx),
                onLongPress: onShowVoters == null
                    ? null
                    : () => onShowVoters!(opt.idx),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            opt.selected
                                ? (multiSelect
                                    ? Icons.check_box
                                    : Icons.radio_button_checked)
                                : (multiSelect
                                    ? Icons.check_box_outline_blank
                                    : Icons.radio_button_unchecked),
                            size: 16,
                            color: opt.selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              opt.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: opt.selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          Text(
                            '${opt.votes}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: maxVotes == 0
                              ? 0
                              : (opt.votes / maxVotes).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          color: opt.selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Icon(
                Icons.group_outlined,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                l.isArabic
                    ? '$totalVoters مشارك'
                    : '$totalVoters voted',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (isCreator && !closed && onClose != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.lock_outline, size: 14),
                  label: Text(
                    l.isArabic ? 'إغلاق' : 'Close',
                    style: theme.textTheme.bodySmall,
                  ),
                  onPressed: onClose,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
