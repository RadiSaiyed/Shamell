// Cycle 45 — browseable saved-messages / bookmarks page.
//
// The bookmark feature has shipped since Cycle 6, but until now the
// only access path was "long-press a message → Bookmark", with no
// way to see what you'd saved. This page surfaces the list, sorted
// newest-first, with a tap-to-jump action that pops back to the
// chat list and opens the corresponding thread at the bookmarked
// message.
//
// The page is dumb on purpose: it takes the load + delete callbacks
// from the chat page so all the network plumbing stays in one place.

import 'package:flutter/material.dart';

import '../l10n.dart';

/// One bookmark row as the page sees it. The chat page maps the raw
/// server response into this shape so the page doesn't need to know
/// the JSON keys.
class ChatBookmarkRow {
  final String messageId;
  final String peerOrGroupId;
  /// "direct" or "group".
  final String kind;
  /// Short, single-line preview of the bookmarked message.
  final String preview;
  /// Optional note the user typed when bookmarking. Rendered below
  /// the preview when present.
  final String? note;
  final DateTime? bookmarkedAt;

  const ChatBookmarkRow({
    required this.messageId,
    required this.peerOrGroupId,
    required this.kind,
    required this.preview,
    this.note,
    this.bookmarkedAt,
  });
}

class ChatBookmarksPage extends StatefulWidget {
  /// Refresh the list. Returns the rows in newest-first order.
  final Future<List<ChatBookmarkRow>> Function() onRefresh;

  /// Remove a bookmark by message id.
  final Future<void> Function(String messageId, String kind) onDelete;

  /// Jump to the bookmarked message. Caller is expected to pop the
  /// page and open the corresponding thread + scroll to the id.
  final void Function(ChatBookmarkRow row) onJump;

  const ChatBookmarksPage({
    super.key,
    required this.onRefresh,
    required this.onDelete,
    required this.onJump,
  });

  @override
  State<ChatBookmarksPage> createState() => _ChatBookmarksPageState();
}

class _ChatBookmarksPageState extends State<ChatBookmarksPage> {
  List<ChatBookmarkRow>? _rows;
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

  Future<void> _delete(ChatBookmarkRow r) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'إزالة الإشارة؟' : 'Remove bookmark?'),
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
            child: Text(l.isArabic ? 'إزالة' : 'Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.onDelete(r.messageId, r.kind);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.isArabic ? 'تعذّر الحذف.' : 'Could not remove.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _rows = (_rows ?? const <ChatBookmarkRow>[])
          .where((row) => row.messageId != r.messageId)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'المحفوظات' : 'Saved messages'),
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
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 80),
          Center(
            child: Text(
              l.isArabic
                  ? 'تعذّر تحميل المحفوظات.'
                  : 'Could not load saved messages.',
            ),
          ),
        ],
      );
    }
    final rows = _rows ?? const <ChatBookmarkRow>[];
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 80),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.bookmark_outline,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  l.isArabic ? 'لا توجد محفوظات.' : 'No saved messages yet.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                  child: Text(
                    l.isArabic
                        ? 'اضغط مطوّلاً على أي رسالة ثم اختر "إشارة مرجعية".'
                        : 'Long-press a message and pick "Bookmark" to save it here.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
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

  Widget _row(ChatBookmarkRow r, ThemeData theme, L10n l) {
    final ts = r.bookmarkedAt;
    String? tsText;
    if (ts != null) {
      final now = DateTime.now();
      final d = now.difference(ts);
      if (d.inMinutes < 1) {
        tsText = l.isArabic ? 'الآن' : 'just now';
      } else if (d.inHours < 1) {
        tsText = l.isArabic
            ? 'قبل ${d.inMinutes} د'
            : '${d.inMinutes}m ago';
      } else if (d.inDays < 1) {
        tsText = l.isArabic ? 'قبل ${d.inHours} س' : '${d.inHours}h ago';
      } else {
        tsText = l.isArabic ? 'قبل ${d.inDays} ي' : '${d.inDays}d ago';
      }
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          r.kind == 'group' ? Icons.group_outlined : Icons.person_outline,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        r.preview.isEmpty
            ? (l.isArabic ? '(بدون نص)' : '(no text)')
            : r.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: r.note != null && r.note!.trim().isNotEmpty
          ? Text(
              r.note!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.primary,
              ),
            )
          : (tsText == null
              ? null
              : Text(
                  tsText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )),
      trailing: IconButton(
        tooltip: l.isArabic ? 'إزالة' : 'Remove',
        icon: const Icon(Icons.bookmark_remove_outlined),
        onPressed: () => _delete(r),
      ),
      onTap: () => widget.onJump(r),
    );
  }
}
