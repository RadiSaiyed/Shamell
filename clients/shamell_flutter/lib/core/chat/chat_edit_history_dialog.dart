import 'package:flutter/material.dart';

import '../l10n.dart';

/// One decoded revision of an edited message, as the chat page passes
/// it to [ChatEditHistoryDialog]. The chat page is responsible for
/// fetching the raw history from the server (via
/// `ChatService.listMessageEditHistory`) and decrypting each
/// revision's ciphertext against the right ratchet state before
/// handing this list to the dialog.
class ChatEditHistoryRevision {
  final int revision;
  final DateTime? editedAt;

  /// Decrypted plaintext for this revision. Empty string is fine —
  /// some revisions might be media-only or unparseable; the dialog
  /// surfaces "(no text)" rather than rendering empty.
  final String text;

  const ChatEditHistoryRevision({
    required this.revision,
    required this.editedAt,
    required this.text,
  });
}

/// Bottom-sheet dialog showing every prior revision of a message
/// (Cycle 5 follow-up). Reads top-down "oldest → newest" so the user
/// scans the evolution of the message intuitively, with each entry
/// labelled by revision number and edit timestamp.
///
/// **Why bottom-sheet, not full page.** Edit chains are typically
/// 1-3 revisions for real users — showing them as a tall list inside
/// a bottom sheet keeps the active conversation visible behind the
/// scrim, which is the right context for "what did this message used
/// to say."
class ChatEditHistoryDialog extends StatelessWidget {
  /// Pre-decoded revisions ordered ascending by revision number
  /// (oldest first). The widget does NOT re-sort — caller controls
  /// presentation order so a future "newest first" toggle stays in
  /// the chat page.
  final List<ChatEditHistoryRevision> revisions;

  /// Optional current text — the live message body — appended at the
  /// bottom of the chain so the user sees the full history culminating
  /// in "(current)".
  final String? currentText;

  const ChatEditHistoryDialog({
    super.key,
    required this.revisions,
    this.currentText,
  });

  /// Convenience helper: opens the sheet and returns when dismissed.
  static Future<void> show(
    BuildContext context, {
    required List<ChatEditHistoryRevision> revisions,
    String? currentText,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChatEditHistoryDialog(
        revisions: revisions,
        currentText: currentText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    if (revisions.isEmpty && (currentText == null || currentText!.isEmpty)) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.isArabic ? 'لا يوجد سجل تعديلات' : 'No edit history',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                l.isArabic ? 'سجل التعديلات' : 'Edit history',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 4, endIndent: 4),
                itemCount: revisions.length +
                    (currentText != null && currentText!.isNotEmpty ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i < revisions.length) {
                    final r = revisions[i];
                    return _RevisionTile(
                      label: l.isArabic
                          ? 'النسخة ${r.revision}'
                          : 'Revision ${r.revision}',
                      timestamp: r.editedAt,
                      text: r.text,
                      isCurrent: false,
                      l: l,
                      theme: theme,
                    );
                  }
                  return _RevisionTile(
                    label: l.isArabic ? 'الحالي' : 'Current',
                    timestamp: null,
                    text: currentText!,
                    isCurrent: true,
                    l: l,
                    theme: theme,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevisionTile extends StatelessWidget {
  final String label;
  final DateTime? timestamp;
  final String text;
  final bool isCurrent;
  final L10n l;
  final ThemeData theme;

  const _RevisionTile({
    required this.label,
    required this.timestamp,
    required this.text,
    required this.isCurrent,
    required this.l,
    required this.theme,
  });

  String _formatTimestamp(DateTime ts) {
    final dt = ts.toLocal();
    String pad(int n) => n < 10 ? '0$n' : '$n';
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} '
        '${pad(dt.hour)}:${pad(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final accent = isCurrent ? scheme.primary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: accent.withValues(alpha: isCurrent ? 1 : .78),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (timestamp != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(timestamp!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: .55),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text.trim().isEmpty
                ? (l.isArabic ? '(لا يوجد نص)' : '(no text)')
                : text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontStyle: text.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}
