import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import '../l10n.dart';
import 'chat_stories_page.dart';

/// Cycle 32 — full-screen story viewer.
///
/// Instagram/WhatsApp-style: progress bars at the top (one segment
/// per story in the list), the story body in the centre, tap-right
/// to advance, tap-left to go back, long-press to pause, swipe-down
/// to dismiss. Each story auto-advances after [_storyDuration].
///
/// The page is dumb — it gets a list of stories + a callback to
/// fire a view-receipt the moment a story is shown. The chat page
/// wires the callback to `ChatService.markStoryViewed`.
class ChatStoryViewer extends StatefulWidget {
  final List<ChatStoryRow> stories;
  final int initialIndex;
  final Future<void> Function(String storyId) onMarkViewed;
  /// Cycle 33 — invoked when the viewer taps a reaction emoji. The
  /// caller (chat page) fires `ChatService.reactToStory`. Pass null
  /// to disable the reactions strip (e.g. for our own stories — the
  /// author doesn't react to their own).
  final Future<void> Function(String storyId, String emoji)? onReact;
  /// Cycle 33 — invoked when the viewer taps their currently-active
  /// reaction emoji a second time (toggle off). Calls
  /// `ChatService.clearStoryReaction`.
  final Future<void> Function(String storyId)? onClearReaction;
  /// Cycle 34 — author-only: fetches the list of viewers for the
  /// current story. Each element is `{viewer_id, viewed_at}`. The
  /// viewer surfaces a "👁" badge that opens a bottom-sheet drawer.
  final Future<List<Map<String, Object?>>> Function(String storyId)? onLoadViews;
  /// Cycle 34 — author-only: fetches the list of reactors for the
  /// current story. Each element is `{viewer_id, emoji, reacted_at}`.
  final Future<List<Map<String, Object?>>> Function(String storyId)?
      onLoadReactions;

  const ChatStoryViewer({
    super.key,
    required this.stories,
    this.initialIndex = 0,
    required this.onMarkViewed,
    this.onReact,
    this.onClearReaction,
    this.onLoadViews,
    this.onLoadReactions,
  });

  @override
  State<ChatStoryViewer> createState() => _ChatStoryViewerState();
}

class _ChatStoryViewerState extends State<ChatStoryViewer>
    with SingleTickerProviderStateMixin {
  static const Duration _storyDuration = Duration(seconds: 5);

  /// Cycle 33 — six quick-react emojis. Matches the Instagram /
  /// WhatsApp Status interaction set; ordered by approximate global
  /// frequency.
  static const List<String> _quickEmojis = <String>[
    '❤️',
    '😂',
    '😮',
    '😢',
    '👍',
    '🔥',
  ];

  late final PageController _pageController;
  late final AnimationController _progressCtrl;
  int _index = 0;
  bool _paused = false;
  /// Cycle 33 — per-story override of the user's active reaction.
  /// `_reactionOverrides[storyId]` holds the latest emoji the user
  /// tapped during this viewing session (or '' to mean "cleared").
  /// Falls back to `ChatStoryRow.myReaction` when no override.
  final Map<String, String> _reactionOverrides = <String, String>{};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _pageController = PageController(initialPage: _index);
    _progressCtrl = AnimationController(
      vsync: this,
      duration: _storyDuration,
    );
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) _advance(1);
    });
    _startCurrent();
  }

  void _startCurrent() {
    if (_index < 0 || _index >= widget.stories.length) return;
    _progressCtrl.reset();
    if (!_paused) _progressCtrl.forward();
    final story = widget.stories[_index];
    // Fire view receipt for the now-visible story. Best-effort; we
    // don't await — the viewer shouldn't stall on network.
    // ignore: discarded_futures
    widget.onMarkViewed(story.id);
  }

  void _advance(int delta) {
    final next = _index + delta;
    if (next < 0) return; // stay on first
    if (next >= widget.stories.length) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _index = next;
    });
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    _startCurrent();
  }

  void _setPaused(bool paused) {
    setState(() => _paused = paused);
    if (paused) {
      _progressCtrl.stop();
    } else {
      _progressCtrl.forward();
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final width = MediaQuery.of(context).size.width;
            // Left third → back, right two-thirds → forward.
            if (details.localPosition.dx < width / 3) {
              _advance(-1);
            } else {
              _advance(1);
            }
          },
          onLongPressStart: (_) => _setPaused(true),
          onLongPressEnd: (_) => _setPaused(false),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 600) {
              Navigator.of(context).maybePop();
            }
          },
          child: Column(
            children: <Widget>[
              _buildProgressBars(theme),
              const SizedBox(height: 8),
              _buildHeader(l),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  // Tap drives advancement; the swipe gesture is
                  // reserved for vertical-down to dismiss.
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.stories.length,
                  itemBuilder: (ctx, i) => _buildStory(widget.stories[i]),
                ),
              ),
              if (widget.onReact != null) _buildReactionsBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBars(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < widget.stories.length; i++) ...<Widget>[
            Expanded(
              child: AnimatedBuilder(
                animation: _progressCtrl,
                builder: (_, __) {
                  double value;
                  if (i < _index) {
                    value = 1.0;
                  } else if (i == _index) {
                    value = _progressCtrl.value;
                  } else {
                    value = 0.0;
                  }
                  return Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(color: Colors.white),
                    ),
                  );
                },
              ),
            ),
            if (i < widget.stories.length - 1) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(L10n l) {
    final story = widget.stories[_index];
    final canSeeAudience =
        story.isMine && widget.onLoadViews != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            radius: 14,
            child: Icon(Icons.person_outline, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              story.authorDisplay,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (canSeeAudience)
            IconButton(
              icon: const Icon(Icons.visibility_outlined, color: Colors.white),
              tooltip: l.isArabic ? 'المشاهدون' : 'Viewers',
              onPressed: () => _openAudienceDrawer(story),
            ),
          // Cycle 54 — save an image story to the device gallery.
          // Only shown for image stories; text stories have nothing
          // to save.
          if (story.kind == 'image' && story.attachmentBytes != null)
            IconButton(
              icon: const Icon(Icons.download_outlined, color: Colors.white),
              tooltip: l.isArabic ? 'حفظ في المعرض' : 'Save to gallery',
              onPressed: () => _saveStoryToGallery(story),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: l.shamellDialogCancel,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  /// Cycle 54 — save an image story to the device gallery. Pauses
  /// the progress bar while the save dialog runs; restores the
  /// prior pause state on completion. SnackBar reports success.
  Future<void> _saveStoryToGallery(ChatStoryRow story) async {
    final bytes = story.attachmentBytes;
    if (bytes == null || bytes.isEmpty) return;
    final l = L10n.of(context);
    final wasPaused = _paused;
    _setPaused(true);
    try {
      final name = 'story_${story.id}_${DateTime.now().millisecondsSinceEpoch}';
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 95,
        name: name,
      );
      final success = (result['isSuccess'] == true) ||
          (result['isSuccess'] == 1) ||
          (result['success'] == true) ||
          (result['success'] == 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(success
              ? (l.isArabic ? 'تم حفظ الصورة.' : 'Image saved.')
              : (l.isArabic ? 'تعذّر حفظ الصورة.' : 'Save failed.')),
        ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic ? 'تعذّر حفظ الصورة.' : 'Save failed.'),
      ));
    } finally {
      if (mounted) _setPaused(wasPaused);
    }
  }

  /// Cycle 34 — open the "who viewed / reacted" drawer for one of
  /// the caller's own stories. Pauses the progress bar while open so
  /// the story doesn't auto-advance behind the sheet.
  Future<void> _openAudienceDrawer(ChatStoryRow story) async {
    final loadViews = widget.onLoadViews;
    final loadReactions = widget.onLoadReactions;
    if (loadViews == null) return;
    final wasPaused = _paused;
    _setPaused(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _StoryAudienceSheet(
        storyId: story.id,
        loadViews: loadViews,
        loadReactions: loadReactions,
      ),
    );
    if (!mounted) return;
    _setPaused(wasPaused);
  }

  /// Cycle 33 — the row of six quick-react emojis at the bottom of
  /// the viewer. Tapping a different emoji upserts; tapping the
  /// already-active one toggles off. The "active" emoji is shown
  /// scaled-up + with a translucent white ring.
  Widget _buildReactionsBar() {
    final story = widget.stories[_index];
    final overridden = _reactionOverrides[story.id];
    final active = overridden ?? story.myReaction ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          for (final e in _quickEmojis)
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkResponse(
                radius: 28,
                onTap: () => _onReactTap(story.id, e, active),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: e == active ? 52 : 44,
                  height: e == active ? 52 : 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: e == active
                        ? Colors.white.withValues(alpha: .18)
                        : Colors.transparent,
                    border: e == active
                        ? Border.all(
                            color: Colors.white.withValues(alpha: .65),
                            width: 1.5,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    e,
                    style: TextStyle(
                      fontSize: e == active ? 28 : 24,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onReactTap(String storyId, String tapped, String active) {
    if (tapped == active) {
      // Re-tap of active emoji clears it.
      setState(() {
        _reactionOverrides[storyId] = '';
      });
      final clear = widget.onClearReaction;
      if (clear != null) {
        // ignore: discarded_futures
        clear(storyId);
      }
      return;
    }
    setState(() {
      _reactionOverrides[storyId] = tapped;
    });
    final react = widget.onReact;
    if (react != null) {
      // ignore: discarded_futures
      react(storyId, tapped);
    }
  }

  Widget _buildStory(ChatStoryRow r) {
    if (r.kind == 'image' && r.attachmentBytes != null) {
      return Center(
        child: InteractiveViewer(
          maxScale: 4.0,
          child: Image.memory(r.attachmentBytes!, fit: BoxFit.contain),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          r.text ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// Cycle 34 — modal bottom sheet showing the audience of one of the
/// caller's own stories: tab "Viewed" (👁) and tab "Reacted" (❤️).
/// Each tab fetches its own list lazily on open + on tab switch.
class _StoryAudienceSheet extends StatefulWidget {
  final String storyId;
  final Future<List<Map<String, Object?>>> Function(String storyId) loadViews;
  final Future<List<Map<String, Object?>>> Function(String storyId)?
      loadReactions;

  const _StoryAudienceSheet({
    required this.storyId,
    required this.loadViews,
    required this.loadReactions,
  });

  @override
  State<_StoryAudienceSheet> createState() => _StoryAudienceSheetState();
}

class _StoryAudienceSheetState extends State<_StoryAudienceSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<Map<String, Object?>>? _views;
  List<Map<String, Object?>>? _reactions;
  Object? _viewsError;
  Object? _reactionsError;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: widget.loadReactions != null ? 2 : 1,
      vsync: this,
    );
    // Best-effort lazy load both tabs up-front; the lists are small.
    _loadViews();
    if (widget.loadReactions != null) _loadReactions();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadViews() async {
    try {
      final v = await widget.loadViews(widget.storyId);
      if (!mounted) return;
      setState(() {
        _views = v;
        _viewsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _viewsError = e);
    }
  }

  Future<void> _loadReactions() async {
    final loader = widget.loadReactions;
    if (loader == null) return;
    try {
      final r = await loader(widget.storyId);
      if (!mounted) return;
      setState(() {
        _reactions = r;
        _reactionsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _reactionsError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final hasReactionsTab = widget.loadReactions != null;
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scroll) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabCtrl,
                tabs: <Widget>[
                  Tab(text: isAr ? 'المشاهدون' : 'Viewed'),
                  if (hasReactionsTab)
                    Tab(text: isAr ? 'التفاعلات' : 'Reactions'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: <Widget>[
                    _buildViewsTab(scroll, isAr),
                    if (hasReactionsTab) _buildReactionsTab(scroll, isAr),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildViewsTab(ScrollController scroll, bool isAr) {
    if (_viewsError != null) {
      return Center(
        child: Text(isAr ? 'تعذّر التحميل.' : 'Could not load.'),
      );
    }
    final v = _views;
    if (v == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (v.isEmpty) {
      return Center(
        child: Text(isAr ? 'لا توجد مشاهدات بعد.' : 'No viewers yet.'),
      );
    }
    return ListView.separated(
      controller: scroll,
      itemCount: v.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final row = v[i];
        final viewerId = (row['viewer_id'] as String?) ?? '';
        final viewedAt = (row['viewed_at'] as String?) ?? '';
        return ListTile(
          leading: const CircleAvatar(
            radius: 16,
            child: Icon(Icons.person_outline, size: 18),
          ),
          title: Text(viewerId, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_relativeTime(viewedAt, isAr)),
        );
      },
    );
  }

  Widget _buildReactionsTab(ScrollController scroll, bool isAr) {
    if (_reactionsError != null) {
      return Center(
        child: Text(isAr ? 'تعذّر التحميل.' : 'Could not load.'),
      );
    }
    final r = _reactions;
    if (r == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (r.isEmpty) {
      return Center(
        child: Text(isAr ? 'لا توجد تفاعلات بعد.' : 'No reactions yet.'),
      );
    }
    return ListView.separated(
      controller: scroll,
      itemCount: r.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final row = r[i];
        final viewerId = (row['viewer_id'] as String?) ?? '';
        final emoji = (row['emoji'] as String?) ?? '';
        final reactedAt = (row['reacted_at'] as String?) ?? '';
        return ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          title: Text(viewerId, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_relativeTime(reactedAt, isAr)),
        );
      },
    );
  }

  /// Best-effort "Xm ago" / "Xh ago" rendering of an ISO 8601
  /// timestamp string. The viewer never needs second-precision.
  String _relativeTime(String iso, bool isAr) {
    if (iso.isEmpty) return '';
    try {
      final ts = DateTime.parse(iso).toLocal();
      final d = DateTime.now().difference(ts);
      if (d.inMinutes < 1) return isAr ? 'الآن' : 'just now';
      if (d.inHours < 1) {
        return isAr ? 'قبل ${d.inMinutes} د' : '${d.inMinutes}m ago';
      }
      if (d.inDays < 1) {
        return isAr ? 'قبل ${d.inHours} س' : '${d.inHours}h ago';
      }
      return isAr ? 'قبل ${d.inDays} ي' : '${d.inDays}d ago';
    } catch (_) {
      return iso;
    }
  }
}
