import 'package:flutter/material.dart';

import '../l10n.dart';
import 'chat_saved_replies_palette.dart';

/// Cycle 11: CRUD page for saved-reply templates. Pushed from the
/// saved-replies palette's "Manage replies" row (the `onManage` hook
/// the palette has carried since Cycle 7).
///
/// The page is self-contained: it takes three callbacks for the
/// service round-trips (`onRefresh` / `onSave` / `onDelete`) and
/// drives all the local list state itself. The chat page wires the
/// callbacks to the matching `ChatService` methods so the page
/// doesn't depend on `ChatService` directly — keeps the widget
/// trivially testable.
class ChatSavedRepliesManagePage extends StatefulWidget {
  /// Fetches the current saved-reply list. Called on mount + on
  /// pull-to-refresh + after every successful save / delete.
  final Future<List<ChatSavedReply>> Function() onRefresh;

  /// Upsert one reply by slug. Returning normally means the server
  /// stored it; throwing surfaces as a SnackBar.
  final Future<void> Function({
    required String slug,
    required String label,
    required String body,
  }) onSave;

  /// Delete one reply by slug.
  final Future<void> Function(String slug) onDelete;

  /// Server-enforced per-device cap. Displayed under the title so
  /// users know they can have, say, "0/32 saved" rather than
  /// guessing. The server returns HTTP 409 once the cap is hit.
  final int maxRepliesPerDevice;

  const ChatSavedRepliesManagePage({
    super.key,
    required this.onRefresh,
    required this.onSave,
    required this.onDelete,
    this.maxRepliesPerDevice = 32,
  });

  @override
  State<ChatSavedRepliesManagePage> createState() =>
      _ChatSavedRepliesManagePageState();
}

class _ChatSavedRepliesManagePageState
    extends State<ChatSavedRepliesManagePage> {
  List<ChatSavedReply>? _rows;
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

  Future<void> _openEditor({ChatSavedReply? existing}) async {
    final l = L10n.of(context);
    final result = await showDialog<_SavedReplyDraft>(
      context: context,
      builder: (ctx) => _SavedReplyEditorDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    try {
      await widget.onSave(
        slug: result.slug,
        label: result.label,
        body: result.body,
      );
    } catch (e) {
      if (!mounted) return;
      // 409 == cap hit on the server side.
      final msg = e.toString().contains('409')
          ? (l.isArabic
              ? 'وصلت إلى الحد الأقصى (${widget.maxRepliesPerDevice}).'
              : 'You\'ve hit the limit (${widget.maxRepliesPerDevice}).')
          : (l.isArabic ? 'تعذّر الحفظ.' : 'Could not save.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    await _load();
  }

  Future<void> _confirmAndDelete(ChatSavedReply row) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            l.isArabic ? 'حذف الرد المحفوظ؟' : 'Delete saved reply?'),
        content: Text(
          l.isArabic
              ? 'سيتم حذف "${row.label.isNotEmpty ? row.label : row.slug}".'
              : '"${row.label.isNotEmpty ? row.label : row.slug}" will be removed.',
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
            child: Text(l.isArabic ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.onDelete(row.slug);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic ? 'تعذّر الحذف.' : 'Could not delete.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    // Optimistic local removal so the UI feels snappy even if the
    // server is slow; the next `_load()` after the user pulls to
    // refresh will reconcile.
    setState(() {
      _rows = (_rows ?? const <ChatSavedReply>[])
          .where((r) => r.slug != row.slug)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final rows = _rows ?? const <ChatSavedReply>[];
    final count = rows.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'الردود المحفوظة' : 'Saved replies'),
        actions: <Widget>[
          IconButton(
            tooltip: l.isArabic ? 'إضافة رد' : 'Add reply',
            icon: const Icon(Icons.add),
            onPressed: count >= widget.maxRepliesPerDevice
                ? null
                : () => _openEditor(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme, l, rows),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, L10n l, List<ChatSavedReply> rows) {
    if (_firstLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return ListView(
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
              ),
            ),
          ),
        ],
      );
    }
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
                    Icons.bookmark_outline,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.isArabic
                        ? 'لا توجد ردود محفوظة.'
                        : 'No saved replies yet.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.isArabic
                        ? 'اضغط + لإضافة أول رد.'
                        : 'Tap + to add your first one.',
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
      itemCount: rows.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        if (i == rows.length) {
          // Footer counter: lets the user see how close they are to
          // the per-device cap without having to count.
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Text(
              l.isArabic
                  ? '${rows.length} / ${widget.maxRepliesPerDevice} ردًا محفوظًا'
                  : '${rows.length} of ${widget.maxRepliesPerDevice} saved',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final r = rows[i];
        return ListTile(
          leading: const Icon(Icons.bookmark_outline),
          title: Text(
            r.label.isNotEmpty ? r.label : r.slug,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            r.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: l.isArabic ? 'تعديل' : 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _openEditor(existing: r),
              ),
              IconButton(
                tooltip: l.isArabic ? 'حذف' : 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmAndDelete(r),
              ),
            ],
          ),
          onTap: () => _openEditor(existing: r),
        );
      },
    );
  }
}

/// Result of the editor dialog. `null` from the dialog means
/// "cancel"; a non-null instance carries validated data ready for
/// `ChatService.setSavedReply`.
class _SavedReplyDraft {
  final String slug;
  final String label;
  final String body;
  const _SavedReplyDraft({
    required this.slug,
    required this.label,
    required this.body,
  });
}

class _SavedReplyEditorDialog extends StatefulWidget {
  /// Existing row when editing; `null` when creating a new reply.
  final ChatSavedReply? existing;
  const _SavedReplyEditorDialog({this.existing});

  @override
  State<_SavedReplyEditorDialog> createState() =>
      _SavedReplyEditorDialogState();
}

class _SavedReplyEditorDialogState extends State<_SavedReplyEditorDialog> {
  late final TextEditingController _slugCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _bodyCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _slugCtrl = TextEditingController(text: existing?.slug ?? '');
    _labelCtrl = TextEditingController(text: existing?.label ?? '');
    _bodyCtrl = TextEditingController(text: existing?.body ?? '');
  }

  @override
  void dispose() {
    _slugCtrl.dispose();
    _labelCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _onSave() {
    final slug = slugify(_slugCtrl.text, fallback: _labelCtrl.text);
    final label = _labelCtrl.text.trim();
    final body = _bodyCtrl.text;
    if (slug.isEmpty) {
      setState(() => _error = 'slug-empty');
      return;
    }
    if (label.isEmpty) {
      setState(() => _error = 'label-empty');
      return;
    }
    if (body.trim().isEmpty) {
      setState(() => _error = 'body-empty');
      return;
    }
    Navigator.of(context).pop(
      _SavedReplyDraft(slug: slug, label: label, body: body),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    String? errorText() {
      switch (_error) {
        case 'slug-empty':
          return l.isArabic ? 'المعرف مطلوب' : 'Slug required';
        case 'label-empty':
          return l.isArabic ? 'الاسم مطلوب' : 'Label required';
        case 'body-empty':
          return l.isArabic ? 'الجسم مطلوب' : 'Body required';
      }
      return null;
    }

    return AlertDialog(
      title: Text(
        isEditing
            ? (l.isArabic ? 'تعديل الرد' : 'Edit saved reply')
            : (l.isArabic ? 'إضافة رد' : 'New saved reply'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _labelCtrl,
              decoration: InputDecoration(
                labelText: l.isArabic ? 'الاسم' : 'Label',
                hintText: l.isArabic ? 'مثل: شكرًا' : 'e.g. Thanks',
              ),
              maxLength: 64,
              textCapitalization: TextCapitalization.sentences,
            ),
            // Slug is auto-derived from the label when creating. Show
            // it so power users can override (useful for keyboard-
            // shortcut workflows that key on slug).
            TextField(
              controller: _slugCtrl,
              enabled: !isEditing,
              decoration: InputDecoration(
                labelText: l.isArabic ? 'المعرف' : 'Slug',
                helperText: isEditing
                    ? (l.isArabic
                        ? 'لا يمكن تغيير المعرف بعد الإنشاء.'
                        : 'Slug is immutable after creation.')
                    : (l.isArabic
                        ? 'يُنشأ تلقائيًا من الاسم. يقبل التعديل.'
                        : 'Auto-derived from the label. Editable.'),
              ),
              maxLength: 32,
            ),
            TextField(
              controller: _bodyCtrl,
              decoration: InputDecoration(
                labelText: l.isArabic ? 'النص' : 'Body',
                hintText: l.isArabic
                    ? 'النص الذي يُدرج في المحادثة'
                    : 'Text that gets inserted into the chat',
              ),
              maxLines: 4,
              minLines: 2,
              maxLength: 2048,
            ),
            if (errorText() != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                errorText()!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.shamellDialogCancel),
        ),
        FilledButton(
          onPressed: _onSave,
          child: Text(l.isArabic ? 'حفظ' : 'Save'),
        ),
      ],
    );
  }
}

/// Pure helper: derive a server-friendly slug (lowercase, ASCII,
/// underscores) from a free-form string. Extracted as top-level so
/// the unit tests can drive it without standing up a widget tree.
///
/// Rules (tuned to match the server's `chk_chat_saved_replies_slug`
/// constraint of 1..=32 chars + the per-device uniqueness PK):
/// * Lower-case ASCII letters + digits + `_` survive.
/// * Everything else (spaces, punctuation, non-ASCII) collapses to
///   a single underscore.
/// * Leading / trailing underscores are stripped.
/// * Result is truncated to 32 chars.
/// * When the input is purely whitespace / unprintable, falls back
///   to slugifying `fallback`. If `fallback` is also empty the
///   helper returns the empty string (caller surfaces a validation
///   error).
String slugify(String raw, {String fallback = ''}) {
  String inner(String s) {
    final buf = StringBuffer();
    bool prevWasUnderscore = false;
    for (final ch in s.toLowerCase().runes) {
      final c = String.fromCharCode(ch);
      final isAlnum = (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) ||
          (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A);
      if (isAlnum) {
        buf.write(c);
        prevWasUnderscore = false;
      } else {
        if (!prevWasUnderscore && buf.isNotEmpty) {
          buf.write('_');
          prevWasUnderscore = true;
        }
      }
    }
    var out = buf.toString();
    while (out.endsWith('_')) {
      out = out.substring(0, out.length - 1);
    }
    if (out.length > 32) out = out.substring(0, 32);
    return out;
  }

  final primary = inner(raw);
  if (primary.isNotEmpty) return primary;
  return inner(fallback);
}
