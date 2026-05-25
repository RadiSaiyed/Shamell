import 'package:flutter/material.dart';

import '../l10n.dart';

/// One quick-pick option in the scheduled-message picker (Cycle 8).
class ChatScheduleOption {
  final String labelEn;
  final String labelAr;

  /// Offset from "now" — e.g. 1 hour, tomorrow morning, etc.
  final Duration offset;

  /// Optional override that pins the resulting time to a specific
  /// wall-clock (e.g. "Tomorrow at 09:00" should land at 09:00
  /// regardless of how long until tomorrow). When set, [offset] is
  /// ignored in favour of computing the next occurrence of this hour.
  final TimeOfDay? pinnedTimeOfDay;

  /// When `true`, the option means "tomorrow at the pinned time";
  /// when `false`, "today (if still in the future) or tomorrow at the
  /// pinned time".
  final bool nextDay;

  const ChatScheduleOption({
    required this.labelEn,
    required this.labelAr,
    this.offset = Duration.zero,
    this.pinnedTimeOfDay,
    this.nextDay = false,
  });

  String label(L10n l) => l.isArabic ? labelAr : labelEn;

  /// Resolve this option against `now` and return the wall-clock
  /// target. For relative offsets this is just `now + offset`. For
  /// pinned-time-of-day options we compute the next occurrence,
  /// honouring [nextDay] (which forces the time to be at least one
  /// calendar day away).
  DateTime resolve(DateTime now) {
    final tod = pinnedTimeOfDay;
    if (tod == null) return now.add(offset);
    DateTime target = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    if (nextDay || !target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }
}

/// Default schedule palette. Mirrors the cadences competitor apps
/// (Slack, Outlook) surface: short reminders for "next break / call",
/// and a "tomorrow 9am" / "next Monday 9am" set for morning sends.
const List<ChatScheduleOption> defaultChatScheduleOptions = <ChatScheduleOption>[
  ChatScheduleOption(
    labelEn: 'In 1 hour',
    labelAr: 'بعد ساعة',
    offset: Duration(hours: 1),
  ),
  ChatScheduleOption(
    labelEn: 'In 4 hours',
    labelAr: 'بعد 4 ساعات',
    offset: Duration(hours: 4),
  ),
  ChatScheduleOption(
    labelEn: 'Tomorrow at 09:00',
    labelAr: 'غدًا الساعة 09:00',
    pinnedTimeOfDay: TimeOfDay(hour: 9, minute: 0),
    nextDay: true,
  ),
  ChatScheduleOption(
    labelEn: 'Tomorrow at 18:00',
    labelAr: 'غدًا الساعة 18:00',
    pinnedTimeOfDay: TimeOfDay(hour: 18, minute: 0),
    nextDay: true,
  ),
];

/// Bottom-sheet picker for scheduling a message. Returns the chosen
/// UTC [DateTime] (via [show]), or `null` if dismissed / Custom flow
/// was cancelled.
class ChatSchedulePickerSheet extends StatelessWidget {
  final List<ChatScheduleOption> options;

  /// When non-null, a "Cancel schedule" row is appended that pops
  /// the sheet with the sentinel [DateTime] value
  /// [chatScheduleCancelSentinel]. Use this when the caller is
  /// editing an existing scheduled message.
  final bool offerCancelExisting;

  const ChatSchedulePickerSheet({
    super.key,
    this.options = defaultChatScheduleOptions,
    this.offerCancelExisting = false,
  });

  /// Convenience helper: opens the sheet, returns the chosen UTC
  /// [DateTime] or `null` on dismiss. When the user picks "Custom…"
  /// we open the platform date + time pickers in sequence.
  static Future<DateTime?> show(
    BuildContext context, {
    List<ChatScheduleOption> options = defaultChatScheduleOptions,
    bool offerCancelExisting = false,
  }) {
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (_) => ChatSchedulePickerSheet(
        options: options,
        offerCancelExisting: offerCancelExisting,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                isArabic ? 'جدولة الرسالة' : 'Schedule message',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final opt in options)
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: Text(opt.label(l)),
                subtitle: Text(
                  _formatResolved(opt.resolve(DateTime.now()), isArabic),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () =>
                    Navigator.of(context).pop(opt.resolve(DateTime.now()).toUtc()),
              ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.event_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                isArabic ? 'تاريخ ووقت مخصص' : 'Custom date & time',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              onTap: () async {
                final picked = await _pickCustomDateTime(context, l);
                if (!context.mounted) return;
                if (picked != null) {
                  Navigator.of(context).pop(picked.toUtc());
                }
                // If the user dismissed the custom picker, leave the
                // sheet open so they can pick a quick option instead.
              },
            ),
            if (offerCancelExisting) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.event_busy_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  isArabic ? 'إلغاء الجدولة' : 'Cancel schedule',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () =>
                    Navigator.of(context).pop(chatScheduleCancelSentinel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Format a wall-clock time as a short subtitle. Avoids spelling
  /// out the date when it's "today" — keeps the picker scannable.
  static String _formatResolved(DateTime when, bool isArabic) {
    final now = DateTime.now();
    final sameDay = when.year == now.year &&
        when.month == now.month &&
        when.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = when.year == tomorrow.year &&
        when.month == tomorrow.month &&
        when.day == tomorrow.day;
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    if (sameDay) return isArabic ? 'اليوم · $time' : 'Today · $time';
    if (isTomorrow) return isArabic ? 'غدًا · $time' : 'Tomorrow · $time';
    final dd = when.day.toString().padLeft(2, '0');
    final mo = when.month.toString().padLeft(2, '0');
    return isArabic ? '$dd/$mo · $time' : '$dd/$mo · $time';
  }

  /// Sequential date → time pickers using the platform's adaptive
  /// dialogs. Returns the combined `DateTime` in the local zone, or
  /// `null` if the user cancelled either step.
  static Future<DateTime?> _pickCustomDateTime(
      BuildContext context, L10n l) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: l.isArabic ? 'اختر التاريخ' : 'Pick a date',
    );
    if (date == null) return null;
    if (!context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      helpText: l.isArabic ? 'اختر الوقت' : 'Pick a time',
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

/// Sentinel value the picker returns when the caller offered the
/// "Cancel schedule" row and the user tapped it. Distinct from
/// `null` (sheet-dismissed) so callers can disambiguate.
final DateTime chatScheduleCancelSentinel = DateTime.utc(1970, 1, 1);
