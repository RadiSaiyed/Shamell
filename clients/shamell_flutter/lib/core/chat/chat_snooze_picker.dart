import 'package:flutter/material.dart';

import '../l10n.dart';

/// One snooze-duration choice in the picker (Cycle 7).
class ChatSnoozeOption {
  final String labelEn;
  final String labelAr;

  /// Duration in seconds. `0` means "clear snooze" — a special row
  /// only shown when the conversation is already snoozed.
  final int seconds;

  const ChatSnoozeOption({
    required this.labelEn,
    required this.labelAr,
    required this.seconds,
  });

  String label(L10n l) => l.isArabic ? labelAr : labelEn;
}

/// Default duration palette. Picked to match WhatsApp/Slack
/// conventions: hour, until-end-of-day-ish (8h), day, week. The
/// chat page can pass a custom list if a product prefers a finer
/// granularity.
const List<ChatSnoozeOption> defaultChatSnoozeOptions = <ChatSnoozeOption>[
  ChatSnoozeOption(labelEn: '15 minutes', labelAr: '15 دقيقة', seconds: 15 * 60),
  ChatSnoozeOption(labelEn: '1 hour', labelAr: 'ساعة', seconds: 60 * 60),
  ChatSnoozeOption(labelEn: '8 hours', labelAr: '8 ساعات', seconds: 8 * 60 * 60),
  ChatSnoozeOption(labelEn: '1 day', labelAr: 'يوم', seconds: 24 * 60 * 60),
  ChatSnoozeOption(labelEn: '1 week', labelAr: 'أسبوع', seconds: 7 * 24 * 60 * 60),
];

/// Bottom-sheet picker for snoozing a conversation. Returns the
/// chosen seconds (or `0` to clear) via [show], or `null` if
/// dismissed. The chat page wires this to
/// `ChatService.setConversationSnooze`.
class ChatSnoozePickerSheet extends StatelessWidget {
  /// Set of durations to offer. Defaults to
  /// [defaultChatSnoozeOptions].
  final List<ChatSnoozeOption> options;

  /// Pass `true` when the conversation is already snoozed — adds a
  /// "Clear snooze" row that returns `0`. Defaults to `false`.
  final bool currentlySnoozed;

  /// Optional `"Snoozed until 18:00"` style headline shown above the
  /// options when `currentlySnoozed` is true. Helps the user remember
  /// what they set last.
  final String? currentSnoozeLabel;

  const ChatSnoozePickerSheet({
    super.key,
    this.options = defaultChatSnoozeOptions,
    this.currentlySnoozed = false,
    this.currentSnoozeLabel,
  });

  /// Convenience helper: opens the sheet, returns the chosen seconds
  /// or `null` on dismiss.
  static Future<int?> show(
    BuildContext context, {
    List<ChatSnoozeOption> options = defaultChatSnoozeOptions,
    bool currentlySnoozed = false,
    String? currentSnoozeLabel,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => ChatSnoozePickerSheet(
        options: options,
        currentlySnoozed: currentlySnoozed,
        currentSnoozeLabel: currentSnoozeLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      // Scrollable so the sheet handles small viewports / long option
      // lists / large text scales without overflowing the bottom edge.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                l.isArabic ? 'إيقاف الإشعارات' : 'Snooze notifications',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (currentlySnoozed && (currentSnoozeLabel ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  currentSnoozeLabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            for (final opt in options)
              ListTile(
                leading: const Icon(Icons.notifications_paused_outlined),
                title: Text(opt.label(l)),
                onTap: () => Navigator.of(context).pop(opt.seconds),
              ),
            if (currentlySnoozed) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  l.isArabic ? 'إلغاء الإيقاف' : 'Clear snooze',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
                onTap: () => Navigator.of(context).pop(0),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

