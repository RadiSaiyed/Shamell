import 'package:flutter/material.dart';

import '../l10n.dart';

/// One row in the scheduled-messages list. The chat page hydrates
/// these from `ChatService.listScheduledMessages` and resolves peer
/// / group display names from its local contact / group cache before
/// pushing them into this page.
class ChatScheduledMessageRow {
  /// Server-assigned id; passed back to `cancel` on swipe.
  final String id;

  /// Resolved "Alice" / "Lunch group" name. Falls back to the raw id
  /// when the chat page can't resolve it.
  final String recipientName;

  /// `true` for group sends, `false` for direct sends. Drives the
  /// icon + accessibility hint.
  final bool isGroup;

  /// The scheduled wall-clock time (already converted to local).
  final DateTime scheduledForLocal;

  /// Plaintext body preview when the chat page can decrypt it
  /// locally; otherwise the i18n string for "(encrypted)".
  final String? bodyPreview;

  /// Number of failed delivery attempts; >0 surfaces a warning chip.
  final int attemptCount;

  /// Last error string from the server (if any).
  final String? lastError;

  const ChatScheduledMessageRow({
    required this.id,
    required this.recipientName,
    required this.isGroup,
    required this.scheduledForLocal,
    this.bodyPreview,
    this.attemptCount = 0,
    this.lastError,
  });
}

/// Full-screen "Scheduled messages" page. The chat page pushes this
/// via the AppBar overflow menu; on enter the page calls [onRefresh],
/// renders the returned rows, and lets the user swipe-to-cancel each
/// pending row. [onCancel] is invoked with the row id, then the row
/// is removed locally; a subsequent pull-to-refresh re-fetches the
/// authoritative server state.
class ChatScheduledMessagesPage extends StatefulWidget {
  /// Returns the current snapshot of pending scheduled messages.
  /// Called on mount + on pull-to-refresh + after a successful
  /// cancel. The chat page is the source of truth for the
  /// `ChatService.listScheduledMessages` plumbing.
  final Future<List<ChatScheduledMessageRow>> Function() onRefresh;

  /// Called when the user confirms cancellation of one row. Throws
  /// surface as a SnackBar; the chat page typically calls
  /// `ChatService.cancelScheduledMessage`.
  final Future<void> Function(String id) onCancel;

  const ChatScheduledMessagesPage({
    super.key,
    required this.onRefresh,
    required this.onCancel,
  });

  @override
  State<ChatScheduledMessagesPage> createState() =>
      _ChatScheduledMessagesPageState();
}

class _ChatScheduledMessagesPageState extends State<ChatScheduledMessagesPage> {
  List<ChatScheduledMessageRow>? _rows;
  Object? _loadError;
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loadError = null;
        _firstLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _firstLoad = false;
      });
    }
  }

  Future<void> _confirmAndCancel(ChatScheduledMessageRow row) async {
    final l = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'إلغاء الرسالة المجدولة؟' : 'Cancel scheduled message?'),
        content: Text(
          l.isArabic
              ? 'لن يتم إرسال هذه الرسالة. لا يمكن التراجع عن هذا الإجراء.'
              : 'This message will not be sent. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.shamellDialogCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.isArabic ? 'إلغاء الجدولة' : 'Cancel schedule'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.onCancel(row.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).isArabic
              ? 'فشل إلغاء الجدولة.'
              : 'Could not cancel schedule.'),
        ),
      );
      return;
    }
    // Optimistic local removal.
    if (!mounted) return;
    setState(() {
      _rows = (_rows ?? const <ChatScheduledMessageRow>[])
          .where((r) => r.id != row.id)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'الرسائل المجدولة' : 'Scheduled messages'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme, l),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, L10n l) {
    if (_firstLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return ListView(
        // Need a scrollable so RefreshIndicator works in the error state.
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                l.isArabic
                    ? 'تعذّر تحميل القائمة. اسحب للأسفل لإعادة المحاولة.'
                    : 'Could not load list. Pull down to retry.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      );
    }
    final rows = _rows ?? const <ChatScheduledMessageRow>[];
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.schedule_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.isArabic
                        ? 'لا توجد رسائل مجدولة.'
                        : 'No scheduled messages.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.isArabic
                        ? 'اضغط مطولًا على زر الإرسال لجدولة رسالة.'
                        : 'Long-press the send button to schedule a message.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) => _row(rows[i], theme, l),
    );
  }

  Widget _row(ChatScheduledMessageRow r, ThemeData theme, L10n l) {
    final hasError = r.attemptCount > 0;
    final timeStr = _formatScheduled(r.scheduledForLocal, l.isArabic);
    return Dismissible(
      key: ValueKey<String>('scheduled-${r.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        await _confirmAndCancel(r);
        // Always return false — we drive the local list update from
        // `_confirmAndCancel` so the row isn't yanked out twice.
        return false;
      },
      child: ListTile(
        leading: Icon(
          r.isGroup ? Icons.group_outlined : Icons.person_outline,
          color: hasError ? theme.colorScheme.error : null,
        ),
        title: Text(
          r.recipientName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              r.bodyPreview ?? (l.isArabic ? '(مشفّر)' : '(encrypted)'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                Icon(
                  Icons.schedule_outlined,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  timeStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (hasError) ...<Widget>[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 12,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l.isArabic
                        ? 'محاولات: ${r.attemptCount}'
                        : '${r.attemptCount} attempts',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l.isArabic ? 'إلغاء الجدولة' : 'Cancel schedule',
          onPressed: () => _confirmAndCancel(r),
        ),
      ),
    );
  }

  /// Compact "Today · 18:00" / "Tomorrow · 09:00" / "14/05 · 09:00"
  /// style format mirroring the schedule picker subtitle.
  static String _formatScheduled(DateTime when, bool isArabic) {
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
}
