import 'package:flutter/material.dart';

import '../l10n.dart';

/// One row in the saved-replies palette. `slug` is the stable key used
/// by the server-side `chat_saved_replies` table; `label` is the
/// human-friendly name shown in the picker; `body` is what gets
/// inserted into the composer when the row is tapped.
class ChatSavedReply {
  final String slug;
  final String label;
  final String body;

  const ChatSavedReply({
    required this.slug,
    required this.label,
    required this.body,
  });

  /// Convenience constructor for the shape returned by
  /// `ChatService.listSavedReplies`.
  factory ChatSavedReply.fromMap(Map<String, Object?> m) => ChatSavedReply(
        slug: (m['slug'] as String?) ?? '',
        label: (m['label'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
      );
}

/// Bottom-sheet palette for picking a saved reply. Returns the body of
/// the chosen reply (to splice into the composer) or `null` on
/// dismiss / when the user taps "Manage replies".
///
/// When `onManage` is provided, a primary-coloured "Manage replies"
/// row is appended at the bottom — tapping it pops the sheet with
/// `null` and then invokes `onManage`, letting the caller push a
/// dedicated CRUD page.
class ChatSavedRepliesPalette extends StatelessWidget {
  final List<ChatSavedReply> replies;
  final VoidCallback? onManage;

  const ChatSavedRepliesPalette({
    super.key,
    required this.replies,
    this.onManage,
  });

  /// Opens the palette. Returns the picked reply body (or `null` on
  /// dismiss / when "Manage replies" is chosen).
  static Future<String?> show(
    BuildContext context, {
    required List<ChatSavedReply> replies,
    VoidCallback? onManage,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => ChatSavedRepliesPalette(
        replies: replies,
        onManage: onManage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    return SafeArea(
      // Scrollable so long lists of replies / large-font users don't
      // overflow the bottom sheet's constrained height.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                isArabic ? 'الردود المحفوظة' : 'Saved replies',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (replies.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  isArabic
                      ? 'لا توجد ردود محفوظة بعد. اضغط "إدارة الردود" لإضافة واحد.'
                      : 'No saved replies yet. Tap "Manage replies" to add one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final r in replies)
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(
                  r.label.isNotEmpty ? r.label : r.slug,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: r.body.isEmpty
                    ? null
                    : Text(
                        r.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => Navigator.of(context).pop(r.body),
              ),
            if (onManage != null) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.tune,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  isArabic ? 'إدارة الردود' : 'Manage replies',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onManage?.call();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
