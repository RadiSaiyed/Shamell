import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import 'chat_story_viewer.dart';

/// Cycle 30 — minimal stories page (24h ephemeral content).
///
/// The chat list reaches this via an AppBar icon (the "story camera"
/// idiom). The page hosts:
///
/// * A "Post a story" composer (TextField + Send), and
/// * A scrollable list of currently-live stories, grouped by author.
///
/// v1 scope: text-only stories. Image / video support is a follow-up
/// cycle once we wire image_picker + a per-story attachment uploader.
/// The widget is dumb — it takes callbacks for the service round-
/// trips so the chat page owns the `ChatService.createStory` /
/// `listStories` / `deleteStory` plumbing.
class ChatStoriesPage extends StatefulWidget {
  /// Returns the visible-live stories. Called on mount + on pull-
  /// to-refresh + after a post / delete.
  final Future<List<ChatStoryRow>> Function() onRefresh;

  /// Post a new text story. Returning normally means it landed;
  /// throwing surfaces as a SnackBar.
  final Future<void> Function(String text) onPostText;

  /// Cycle 31 — post a new image story. Caller supplies the raw
  /// bytes + mime; the chat page base64-encodes for transport and
  /// calls `createStory(kind: 'image', ...)`.
  final Future<void> Function(Uint8List bytes, String mime)? onPostImage;

  /// Delete one of the caller's own stories.
  final Future<void> Function(String storyId) onDelete;

  /// Record a view receipt — fired the first time the user scrolls
  /// the story into the viewport. The chat page wires this to
  /// `ChatService.markStoryViewed`.
  final Future<void> Function(String storyId) onMarkViewed;

  /// Cycle 33 — react to a viewed story with an emoji. Optional —
  /// if null, the viewer hides the reactions strip.
  final Future<void> Function(String storyId, String emoji)? onReact;

  /// Cycle 33 — clear the caller's reaction on a story.
  final Future<void> Function(String storyId)? onClearReaction;

  /// Cycle 34 — author-only: fetch the list of viewers for one of
  /// the caller's own stories. Passed straight through to the viewer.
  final Future<List<Map<String, Object?>>> Function(String storyId)?
      onLoadStoryViews;

  /// Cycle 34 — author-only: fetch the list of reactors for one of
  /// the caller's own stories.
  final Future<List<Map<String, Object?>>> Function(String storyId)?
      onLoadStoryReactions;

  /// The caller's own device id — used to surface a "Delete" action
  /// on rows where `authorId == myDeviceId`.
  final String myDeviceId;

  const ChatStoriesPage({
    super.key,
    required this.onRefresh,
    required this.onPostText,
    required this.onDelete,
    required this.onMarkViewed,
    required this.myDeviceId,
    this.onPostImage,
    this.onReact,
    this.onClearReaction,
    this.onLoadStoryViews,
    this.onLoadStoryReactions,
  });

  @override
  State<ChatStoriesPage> createState() => _ChatStoriesPageState();
}

class ChatStoryRow {
  final String id;
  final String authorId;
  final String authorDisplay;
  final String kind;
  final String? text;
  /// Cycle 31 — raw image bytes for `kind == 'image'`. The chat
  /// page decodes the server's base64 string into bytes once when
  /// hydrating the row, so the renderer doesn't pay the cost on
  /// every rebuild.
  final Uint8List? attachmentBytes;
  final String? attachmentMime;
  final DateTime? expiresAt;
  final bool isMine;
  /// Cycle 33 — the calling viewer's own emoji reaction on this
  /// story, or null if they haven't reacted yet.
  final String? myReaction;
  /// Cycle 33 — total reactions across all viewers. Only the author
  /// sees this; for non-author rows it's still hydrated but the UI
  /// suppresses it.
  final int reactionsCount;
  const ChatStoryRow({
    required this.id,
    required this.authorId,
    required this.authorDisplay,
    required this.kind,
    this.text,
    this.attachmentBytes,
    this.attachmentMime,
    this.expiresAt,
    this.isMine = false,
    this.myReaction,
    this.reactionsCount = 0,
  });
}

class _ChatStoriesPageState extends State<ChatStoriesPage> {
  List<ChatStoryRow>? _rows;
  Object? _loadError;
  bool _firstLoad = true;
  bool _posting = false;
  final TextEditingController _composerCtrl = TextEditingController();
  final Set<String> _viewed = <String>{};
  /// Cycle 31 — staged image attachment. When non-null, the
  /// composer shows a thumbnail + "Post image" CTA instead of
  /// "Post text".
  Uint8List? _stagedImageBytes;
  String? _stagedImageMime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
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

  Future<void> _post() async {
    if (_posting) return;
    final stagedBytes = _stagedImageBytes;
    final stagedMime = _stagedImageMime;
    final text = _composerCtrl.text.trim();
    if (stagedBytes == null && text.isEmpty) return;
    setState(() => _posting = true);
    try {
      if (stagedBytes != null && widget.onPostImage != null) {
        await widget.onPostImage!(stagedBytes, stagedMime ?? 'image/jpeg');
      } else {
        await widget.onPostText(text);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).isArabic
            ? 'تعذّر نشر القصة.'
            : 'Could not post story.')),
      );
      setState(() => _posting = false);
      return;
    }
    if (!mounted) return;
    _composerCtrl.clear();
    setState(() {
      _posting = false;
      _stagedImageBytes = null;
      _stagedImageMime = null;
    });
    await _load();
  }

  /// Cycle 31 — open the gallery image picker, stage the picked
  /// image for posting. Cap raw bytes at ~4 MiB (server enforces
  /// ~6 MiB base64, ≈4.5 MiB decoded).
  Future<void> _pickImage() async {
    if (widget.onPostImage == null) return;
    final l = L10n.of(context);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 4 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.isArabic
              ? 'الصورة كبيرة جدًا (حد 4 ميغابايت).'
              : 'Image too large (4 MB max).')),
        );
        return;
      }
      setState(() {
        _stagedImageBytes = bytes;
        _stagedImageMime = file.mimeType ?? 'image/jpeg';
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.isArabic
            ? 'تعذّر اختيار الصورة.'
            : 'Could not pick image.')),
      );
    }
  }

  Future<void> _delete(ChatStoryRow r) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'حذف القصة؟' : 'Delete story?'),
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
      await widget.onDelete(r.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.isArabic ? 'تعذّر الحذف.' : 'Could not delete.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _rows = (_rows ?? const <ChatStoryRow>[])
          .where((row) => row.id != r.id)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'القصص' : 'Stories'),
      ),
      body: Column(
        children: <Widget>[
          _buildComposer(theme, l),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(theme, l),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(ThemeData theme, L10n l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Cycle 31 — staged-image preview. Shown above the text
          // composer when the user has picked an image but not yet
          // posted. Tap × to discard.
          if (_stagedImageBytes != null) ...<Widget>[
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: <Widget>[
                  Center(child: Image.memory(_stagedImageBytes!)),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Material(
                      color: Colors.black.withValues(alpha: .55),
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        iconSize: 18,
                        tooltip:
                            l.isArabic ? 'تجاهل' : 'Discard',
                        onPressed: () => setState(() {
                          _stagedImageBytes = null;
                          _stagedImageMime = null;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (widget.onPostImage != null && _stagedImageBytes == null)
                IconButton(
                  tooltip: l.isArabic ? 'إرفاق صورة' : 'Attach image',
                  icon: const Icon(Icons.image_outlined),
                  onPressed: _posting ? null : _pickImage,
                ),
              Expanded(
                child: TextField(
                  controller: _composerCtrl,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 2000,
                  enabled: _stagedImageBytes == null,
                  decoration: InputDecoration(
                    hintText: _stagedImageBytes != null
                        ? (l.isArabic
                            ? 'اضغط "نشر" لإرسال الصورة'
                            : 'Tap "Post" to send the image')
                        : (l.isArabic
                            ? 'شارك ما يجول في خاطرك...'
                            : "What's on your mind?"),
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _posting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: Text(l.isArabic ? 'نشر' : 'Post'),
                onPressed: _posting ? null : _post,
              ),
            ],
          ),
        ],
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
                  ? 'تعذّر تحميل القصص.'
                  : 'Could not load stories.',
            ),
          ),
        ],
      );
    }
    final rows = _rows ?? const <ChatStoryRow>[];
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 80),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.auto_stories_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  l.isArabic ? 'لا توجد قصص حية الآن.' : 'No live stories.',
                  style: theme.textTheme.bodyLarge,
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
      itemBuilder: (ctx, i) => _row(rows[i], i, theme, l),
    );
  }

  void _openViewer(int index) {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChatStoryViewer(
          stories: rows,
          initialIndex: index.clamp(0, rows.length - 1),
          onMarkViewed: (storyId) async {
            if (_viewed.add(storyId)) {
              await widget.onMarkViewed(storyId);
            }
          },
          onReact: widget.onReact,
          onClearReaction: widget.onClearReaction,
          onLoadViews: widget.onLoadStoryViews,
          onLoadReactions: widget.onLoadStoryReactions,
        ),
      ),
    );
  }

  Widget _row(ChatStoryRow r, int index, ThemeData theme, L10n l) {
    String? expireText;
    final exp = r.expiresAt;
    if (exp != null) {
      final remaining = exp.difference(DateTime.now());
      if (remaining.inHours >= 1) {
        expireText = l.isArabic
            ? 'بعد ${remaining.inHours} ساعة'
            : 'in ${remaining.inHours}h';
      } else if (remaining.inMinutes > 0) {
        expireText = l.isArabic
            ? 'بعد ${remaining.inMinutes} دقيقة'
            : 'in ${remaining.inMinutes}m';
      }
    }
    return ListTile(
      onTap: () => _openViewer(index),
      leading: CircleAvatar(
        backgroundColor: r.isMine
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_outline,
          color: r.isMine ? theme.colorScheme.onPrimary : null,
        ),
      ),
      title: Text(
        r.authorDisplay,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: r.attachmentBytes != null && r.kind == 'image'
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                r.attachmentBytes!,
                height: 160,
                fit: BoxFit.cover,
              ),
            )
          : (r.text != null
              ? Text(
                  r.text!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(l.isArabic ? '(${r.kind})' : '(${r.kind})')),
      trailing: r.isMine
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (r.reactionsCount > 0) ...<Widget>[
                  const Icon(Icons.favorite, size: 14, color: Colors.pinkAccent),
                  const SizedBox(width: 2),
                  Text(
                    '${r.reactionsCount}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  tooltip: l.isArabic ? 'حذف' : 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(r),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (r.myReaction != null && r.myReaction!.isNotEmpty)
                  Text(r.myReaction!, style: const TextStyle(fontSize: 18)),
                if (expireText != null)
                  Text(
                    expireText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
    );
  }
}
