import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'glass.dart';
import 'l10n.dart';
import 'perf.dart';
import 'mini_apps_config.dart';
import 'ui_kit.dart';
import 'chat/shamell_chat_page.dart';
import 'shamell_ui.dart';
import 'shamell_moments_composer_page.dart';
import 'shamell_photo_viewer_page.dart';

Future<Map<String, String>> _hdrMoments({
  required String baseUrl,
  bool json = false,
}) async {
  final headers = <String, String>{};
  if (json) {
    headers['content-type'] = 'application/json';
  }
  try {
    final cookie = await getSessionCookieHeader(baseUrl) ?? '';
    if (cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
  } catch (_) {}
  return headers;
}

class MomentsPage extends StatefulWidget {
  final String baseUrl;
  final String? initialPostId;
  final bool focusComments;
  final String? initialCommentId;
  final void Function(BuildContext)? onOpenOfficialDirectory;
  final String? originOfficialAccountId;
  final String? officialCategory;
  final String? officialCity;
  final bool showOnlyMine;
  final String? topicTag;
  final bool initialHotOfficialsOnly;
  final String? timelineAuthorId;
  final String? timelineAuthorName;
  final bool showComposer;
  const MomentsPage({
    super.key,
    required this.baseUrl,
    this.initialPostId,
    this.focusComments = false,
    this.initialCommentId,
    this.onOpenOfficialDirectory,
    this.originOfficialAccountId,
    this.officialCategory,
    this.officialCity,
    this.showOnlyMine = false,
    this.topicTag,
    this.initialHotOfficialsOnly = false,
    this.timelineAuthorId,
    this.timelineAuthorName,
    this.showComposer = true,
  });

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  final TextEditingController _postCtrl = TextEditingController();
  final TextEditingController _visibilityTagCtrl = TextEditingController();
  final GlobalKey _composerKey = GlobalKey();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _postFocus = FocusNode();
  final TextEditingController _inlineCommentCtrl = TextEditingController();
  final FocusNode _inlineCommentFocus = FocusNode();
  final Map<String, GlobalKey> _momentPostKeys = <String, GlobalKey>{};
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _usingApi = false;
  bool _filterOfficialOnly = false;
  bool _filterOfficialRepliesOnly = false;
  bool _filterHotOfficialsOnly = false;
  String? _topicCategory; // 'wallet'
  Map<String, List<Map<String, dynamic>>> _comments = {};
  final Map<String, _MomentOfficialAccount> _officialAccounts = {};
  Uint8List? _pendingImage;
  String? _pendingImageMime;
  String? _presetText;
  Uint8List? _presetImage;
  String _visibilityScope = 'public';
  String? _visibilityTag;
  String _visibilityTagMode = 'only'; // 'only' or 'except'
  bool _openedInitial = false;
  bool _filterLast3Days = false;
  bool _hideOfficialPosts = false;
  final Set<String> _mutedAuthors = <String>{};
  final Set<String> _hiddenPostIds = <String>{};
  String? _preferredCity;
  bool _isAdmin = false;
  bool _filterCloseFriendsOnly = false;
  bool _filterMiniProgramOnly = false;
  bool _filterOfficialLinkedOnly = false;
  bool _filterChannelClipsOnly = false;
  bool _enableInlineComposer = false;
  bool _enableAdvancedFilters = false;
  String? _filterAudienceTag;
  List<Map<String, dynamic>> _trendingTopics = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _myOfficialStats;
  List<String> _availableAudienceTags = const <String>[];
  bool _showAudienceOnboardingHint = true;
  String _myDisplayName = '';
  String? _myMomentsPseudonym;
  bool _openedPresetComposer = false;
  String? _inlineCommentPostId;
  String? _inlineReplyToId;
  String? _inlineReplyToName;
  bool _inlineCommentSending = false;

  Future<void> _openPhotoViewer(
    List<String> sources, {
    int initialIndex = 0,
    List<String>? heroTags,
  }) async {
    final cleaned = <String>[];
    final cleanedTags = <String>[];
    for (var i = 0; i < sources.length; i++) {
      final src = sources[i].trim();
      if (src.isEmpty) continue;
      cleaned.add(src);
      final tag =
          heroTags != null && i < heroTags.length ? heroTags[i].trim() : '';
      cleanedTags.add(tag);
    }
    if (cleaned.isEmpty) return;
    final idx = initialIndex.clamp(0, cleaned.length - 1);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShamellPhotoViewerPage(
          baseUrl: widget.baseUrl,
          sources: cleaned,
          initialIndex: idx,
          heroTags: heroTags == null ? null : cleanedTags,
        ),
      ),
    );
  }

  Widget _buildShamellCoverHeader(L10n l, ThemeData theme) {
    final isArabic = l.isArabic;
    final isFriendTimeline = (widget.timelineAuthorId ?? '').trim().isNotEmpty;

    String resolveTimelineName() {
      final explicit = (widget.timelineAuthorName ?? '').trim();
      if (explicit.isNotEmpty) return explicit;
      if (isFriendTimeline) {
        final id = (widget.timelineAuthorId ?? '').trim();
        if (id.isNotEmpty) {
          for (final p in _posts) {
            final pid = (p['author_id'] ?? '').toString().trim();
            if (pid != id) continue;
            final n = (p['author_name'] ?? '').toString().trim();
            if (n.isNotEmpty) return n;
          }
          return id;
        }
      }
      final mine = _myDisplayName.trim();
      if (mine.isNotEmpty) return mine;
      return isArabic ? 'أنت' : 'You';
    }

    final name = resolveTimelineName();
    final initial = name.isNotEmpty
        ? name.substring(0, 1).toUpperCase()
        : (isArabic ? 'أ' : 'Y');
    final isDark = theme.brightness == Brightness.dark;

    final List<Color> coverGradient = isDark
        ? const [
            Color(0xFF0B1220),
            Color(0xFF111827),
          ]
        : const [
            Color(0xFF64748B),
            Color(0xFF334155),
          ];

    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: coverGradient,
              ),
            ),
          ),
          Opacity(
            opacity: isDark ? .12 : .16,
            child: Image.asset(
              'assets/shamell_steering.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            right: isArabic ? null : 16,
            left: isArabic ? 16 : null,
            bottom: 16,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: (widget.showOnlyMine || isFriendTimeline)
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MomentsPage(
                            baseUrl: widget.baseUrl,
                            showOnlyMine: true,
                          ),
                        ),
                      );
                    },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          blurRadius: 10,
                          color: Colors.black45,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .95),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _scrollToComposerAndFocus() async {
    try {
      final ctx = _composerKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.25,
        );
      } else if (_scrollCtrl.hasClients) {
        await _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    _postFocus.requestFocus();
  }

  Future<({Uint8List bytes, String mime})?> _pickImageBytes({
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (x == null) return null;
      final bytes = await x.readAsBytes();
      final parts = x.name.split('.');
      final ext = parts.isNotEmpty ? parts.last.toLowerCase() : '';
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      return (bytes: bytes, mime: mime);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openShamellComposer({
    String initialText = '',
    Uint8List? initialImageBytes,
    String? initialImageMime,
    String initialVisibilityScope = 'public',
    bool clearPresetOnClose = false,
  }) async {
    final draft = await Navigator.of(context).push<ShamellMomentDraft>(
      MaterialPageRoute(
        builder: (_) => ShamellMomentsComposerPage(
          baseUrl: widget.baseUrl,
          initialText: initialText,
          initialImageBytes: initialImageBytes,
          initialImageMime: initialImageMime,
          initialVisibilityScope: initialVisibilityScope,
        ),
      ),
    );

    if (draft == null) {
      if (!mounted) return;
      if (clearPresetOnClose) {
        setState(() {
          _presetText = null;
          _presetImage = null;
        });
      }
      return;
    }

    final text = draft.text.trim();
    final images = draft.imageBytes.where((b) => b.isNotEmpty).toList();
    final hasImages = images.isNotEmpty;
    final locationLabel = (draft.locationLabel ?? '').trim();
    if (text.isEmpty && !hasImages) return;

    if (!mounted) return;
    setState(() {
      _visibilityScope = draft.visibilityScope;
      _visibilityTag = null;
      _visibilityTagMode = 'only';
      _visibilityTagCtrl.clear();
    });

    final imagesB64 = <String>[];
    for (final bytes in images) {
      if (bytes.isEmpty) continue;
      imagesB64.add(base64Encode(bytes));
      if (imagesB64.length >= 9) break;
    }
    var posted = false;
    if (_usingApi) {
      posted = await _addPostApi(
        text,
        imagesB64: imagesB64,
        locationLabel: locationLabel.isNotEmpty ? locationLabel : null,
      );
    }
    if (!posted) {
      await _addPostLocal(
        text,
        imagesB64: imagesB64,
        locationLabel: locationLabel.isNotEmpty ? locationLabel : null,
        clearInlineComposer: false,
      );
    }

    if (!mounted) return;
    setState(() {
      _presetText = null;
      _presetImage = null;
    });
    try {
      if (_scrollCtrl.hasClients) {
        await _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _inlineCommentFocus.addListener(_onInlineCommentFocusChanged);
    _filterHotOfficialsOnly = widget.initialHotOfficialsOnly;
    _markCommentsSeen();
    _loadPreset();
    _loadMutedAuthors();
    _loadHiddenPosts();
    _loadPreferredCity();
    _loadMyDisplayName();
    _loadMyMomentsPseudonym();
    _loadAdminFlag();
    _load();
    _loadOfficialAccounts();
    _loadTrendingTopics();
    _loadMyOfficialStats();
    _loadFriendsSummary();
    _loadAudienceHintFlag();
  }

  @override
  void dispose() {
    _postCtrl.dispose();
    _visibilityTagCtrl.dispose();
    _scrollCtrl.dispose();
    _postFocus.dispose();
    _inlineCommentCtrl.dispose();
    _inlineCommentFocus.removeListener(_onInlineCommentFocusChanged);
    _inlineCommentFocus.dispose();
    super.dispose();
  }

  GlobalKey _postKeyFor(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return GlobalKey();
    return _momentPostKeys.putIfAbsent(id, () => GlobalKey());
  }

  void _ensurePostVisible(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return;
    final key = _momentPostKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    try {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    } catch (_) {}
  }

  void _dismissInlineComment({bool clearText = true}) {
    if (!mounted) return;
    setState(() {
      _inlineCommentPostId = null;
      _inlineReplyToId = null;
      _inlineReplyToName = null;
      _inlineCommentSending = false;
      if (clearText) {
        _inlineCommentCtrl.clear();
      }
    });
    try {
      _inlineCommentFocus.unfocus();
    } catch (_) {}
  }

  void _startInlineComment(
    Map<String, dynamic> post, {
    String? replyToId,
    String? replyToName,
  }) {
    final postId = (post['id'] ?? '').toString().trim();
    if (postId.isEmpty) return;
    final cleanReplyId = (replyToId ?? '').trim();
    final cleanReplyName = (replyToName ?? '').trim();
    if (!mounted) return;
    setState(() {
      _inlineCommentPostId = postId;
      _inlineReplyToId = cleanReplyId.isNotEmpty ? cleanReplyId : null;
      _inlineReplyToName = cleanReplyName.isNotEmpty ? cleanReplyName : null;
      _inlineCommentSending = false;
      _inlineCommentCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensurePostVisible(postId);
      _inlineCommentFocus.requestFocus();
    });
  }

  Future<void> _submitInlineComment() async {
    final postId = (_inlineCommentPostId ?? '').trim();
    if (postId.isEmpty) return;
    final text = _inlineCommentCtrl.text.trim();
    if (text.isEmpty) return;
    if (_inlineCommentSending) return;
    final l = L10n.of(context);
    final youLabel = l.isArabic ? 'أنت' : 'You';
    setState(() {
      _inlineCommentSending = true;
    });

    final useApi = _usingApi && !postId.startsWith('local_');
    Map<String, dynamic>? comment;
    try {
      if (useApi) {
        comment = await _addCommentApi(
          postId,
          text,
          replyToId: _inlineReplyToId,
          replyToName: _inlineReplyToName,
        );
      } else {
        final currentLen = _comments[postId]?.length ?? 0;
        comment = <String, dynamic>{
          'text': text,
          'ts': DateTime.now().toIso8601String(),
          'id': 'c_${DateTime.now().millisecondsSinceEpoch}_$currentLen',
          'author_name': youLabel,
          if ((_inlineReplyToId ?? '').trim().isNotEmpty)
            'reply_to': _inlineReplyToId,
          if ((_inlineReplyToName ?? '').trim().isNotEmpty)
            'reply_to_name': _inlineReplyToName,
        };
      }
    } catch (_) {
      comment = null;
    }

    if (!mounted) return;
    if (comment == null) {
      setState(() {
        _inlineCommentSending = false;
      });
      return;
    }

    setState(() {
      final list = List<Map<String, dynamic>>.from(
        _comments[postId] ?? const <Map<String, dynamic>>[],
      );
      list.add(comment!);
      _comments[postId] = list;
      for (final p in _posts) {
        final id = (p['id'] ?? '').toString();
        if (id != postId) continue;
        final currentCount =
            (p['comment_count'] as int?) ?? (p['comments'] as int?) ?? 0;
        if (currentCount > 0) {
          p['comment_count'] = currentCount + 1;
        }
        break;
      }

      _inlineCommentCtrl.clear();
      _inlineReplyToId = null;
      _inlineReplyToName = null;
      _inlineCommentPostId = null;
      _inlineCommentSending = false;
    });
    if (!useApi) {
      unawaited(_saveComments());
    }
    try {
      _inlineCommentFocus.unfocus();
    } catch (_) {}
  }

  void _onInlineCommentFocusChanged() {
    if (!mounted) return;
    if (_inlineCommentFocus.hasFocus) return;
    if (_inlineCommentCtrl.text.trim().isNotEmpty) return;
    if ((_inlineCommentPostId ?? '').trim().isEmpty) return;
    _dismissInlineComment(clearText: true);
  }

  Future<void> _markCommentsSeen() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now().toUtc().toIso8601String();
      await sp.setString('moments.comments_seen_ts', now);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    await _loadLocal();
    await _loadComments();
    await _loadFromApi();
    await _maybeOpenInitialPost();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _maybeOpenInitialPost() async {
    if (_openedInitial) return;
    final targetId = widget.initialPostId;
    if (targetId == null || targetId.isEmpty) return;
    final idx = _posts
        .indexWhere((p) => (p['id'] ?? '').toString() == targetId.toString());
    if (idx < 0) return;
    _openedInitial = true;
    if (!mounted) return;
    if (widget.focusComments) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final p = _posts[idx];
      // ignore: discarded_futures
      _openComments(
        p,
        highlightCommentId: widget.initialCommentId,
        focusInput: widget.focusComments,
      );
    }
  }

  Future<void> _loadLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('moments_posts') ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _posts
          ..clear()
          ..addAll(decoded
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList());
      }
    } catch (_) {
      _posts.clear();
    }
  }

  Future<void> _loadComments() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('moments_comments');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final map = <String, List<Map<String, dynamic>>>{};
        decoded.forEach((k, v) {
          if (v is List) {
            final list = v
                .whereType<Map>()
                .map((m) => m.cast<String, dynamic>())
                .toList();
            map[k] = list;
          }
        });
        _comments = map;
      }
    } catch (_) {}
  }

  Future<void> _loadOfficialAccounts() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'false'});
      final r = await http.get(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl));
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      final list = <_MomentOfficialAccount>[];
      if (decoded is Map && decoded['accounts'] is List) {
        for (final e in decoded['accounts'] as List) {
          if (e is Map) {
            list.add(
              _MomentOfficialAccount.fromJson(e.cast<String, dynamic>()),
            );
          }
        }
      } else if (decoded is List) {
        for (final e in decoded) {
          if (e is Map) {
            list.add(
              _MomentOfficialAccount.fromJson(e.cast<String, dynamic>()),
            );
          }
        }
      }
      if (!mounted || list.isEmpty) return;
      setState(() {
        _officialAccounts
          ..clear()
          ..addEntries(
            list.map(
              (a) => MapEntry(a.id, a),
            ),
          );
      });
    } catch (_) {}
  }

  Future<void> _loadMyOfficialStats() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/official_moments_stats');
      final r = await http.get(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl));
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return;
      if (!mounted) return;
      setState(() {
        _myOfficialStats = decoded.cast<String, dynamic>();
      });
    } catch (_) {}
  }

  Future<void> _loadFriendsSummary() async {
    try {
      final tags = <String>{};
      // Best-practice: keep audience tags local-only to avoid leaking
      // social graph metadata to the backend by default.
      try {
        final sp = await SharedPreferences.getInstance();
        final raw = sp.getString('friends.tags') ?? '{}';
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((_, v) {
            final text = (v ?? '').toString();
            for (final part in text.split(',')) {
              final tag = part.trim();
              if (tag.isNotEmpty) tags.add(tag);
            }
          });
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _availableAudienceTags = tags.toList()..sort();
      });
    } catch (_) {}
  }

  Future<void> _loadAudienceHintFlag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final dismissed = sp.getBool('moments.audience_hint_dismissed') ?? false;
      if (!mounted) return;
      setState(() {
        _showAudienceOnboardingHint = !dismissed;
      });
    } catch (_) {}
  }

  Future<void> _dismissAudienceHint() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('moments.audience_hint_dismissed', true);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _showAudienceOnboardingHint = false;
    });
  }

  String _audienceSummaryLabel(L10n l) {
    final tag = (_visibilityTag ?? '').trim();
    switch (_visibilityScope) {
      case 'public':
        return l.isArabic ? 'عام (كل المستخدمين)' : 'Public (all users)';
      case 'only_me':
        return l.isArabic ? 'أنا فقط' : 'Only me';
      case 'close_friends':
        return l.isArabic ? 'الأصدقاء المقرّبون' : 'Close friends';
      case 'friends':
      default:
        if (tag.isNotEmpty) {
          if (_visibilityTagMode == 'except') {
            return l.isArabic
                ? 'الأصدقاء باستثناء $tag'
                : 'Friends except $tag';
          } else {
            return l.isArabic ? 'فقط $tag' : 'Only $tag';
          }
        }
        return l.isArabic ? 'الأصدقاء فقط' : 'Friends only';
    }
  }

  IconData _audienceSummaryIcon() {
    if (_visibilityScope == 'public') return Icons.public;
    if (_visibilityScope == 'only_me') return Icons.lock_outline;
    return Icons.group_outlined;
  }

  Widget _buildAudienceSummaryPill(L10n l, ThemeData theme) {
    final prefix = l.isArabic ? 'المشاركة مع: ' : 'Share to: ';
    final text = '$prefix${_audienceSummaryLabel(l)}';
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: isDark ? .12 : .06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: .35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _audienceSummaryIcon(),
            size: 16,
            color: theme.colorScheme.primary.withValues(alpha: .95),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: .90),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _pendingImage = bytes;
        final parts = x.name.split('.');
        final ext = parts.isNotEmpty ? parts.last.toLowerCase() : '';
        _pendingImageMime = ext == 'png' ? 'image/png' : 'image/jpeg';
      });
    } catch (_) {}
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImage = null;
      _pendingImageMime = null;
    });
  }

  Future<void> _loadPreset() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final text = sp.getString('moments_preset_text');
      final imgB64 = sp.getString('moments_preset_image');
      if (!mounted) return;
      setState(() {
        _presetText = (text ?? '').trim().isEmpty ? null : text;
        if (imgB64 != null && imgB64.isNotEmpty) {
          try {
            _presetImage = base64Decode(imgB64);
          } catch (_) {
            _presetImage = null;
          }
        }
      });
      // Clear preset once loaded so it is single-use.
      await sp.remove('moments_preset_text');
      await sp.remove('moments_preset_image');
    } catch (_) {}

    if (!mounted) return;
    final hasPreset = (_presetText != null && _presetText!.trim().isNotEmpty) ||
        _presetImage != null;
    final isFriendTimeline = (widget.timelineAuthorId ?? '').trim().isNotEmpty;
    if (widget.showComposer && !isFriendTimeline && hasPreset) {
      if (_openedPresetComposer) return;
      _openedPresetComposer = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _openShamellComposer(
            initialText: (_presetText ?? '').trim(),
            initialImageBytes: _presetImage,
            initialImageMime: null,
            clearPresetOnClose: true,
          ),
        );
      });
    }
  }

  Future<void> _loadMutedAuthors() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('moments.muted_authors');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final local = <String>{};
      for (final e in decoded) {
        if (e is String) {
          final v = e.trim();
          if (v.isNotEmpty) {
            local.add(v);
          }
        }
      }
      if (!mounted || local.isEmpty) return;
      setState(() {
        _mutedAuthors
          ..clear()
          ..addAll(local);
      });
    } catch (_) {}
  }

  Future<void> _saveMutedAuthors() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        'moments.muted_authors',
        jsonEncode(_mutedAuthors.toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadHiddenPosts() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('moments.hidden_posts');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final local = <String>{};
      for (final e in decoded) {
        if (e is String) {
          final v = e.trim();
          if (v.isNotEmpty) {
            local.add(v);
          }
        }
      }
      if (!mounted || local.isEmpty) return;
      setState(() {
        _hiddenPostIds
          ..clear()
          ..addAll(local);
      });
    } catch (_) {}
  }

  Future<void> _loadAdminFlag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final roles = sp.getStringList('roles') ?? const <String>[];
      final isSuper = sp.getBool('is_superadmin') ?? false;
      final hasAdminRole = roles.any((r) {
        final v = r.toLowerCase();
        return v.contains('admin');
      });
      if (!mounted) return;
      setState(() {
        _isAdmin = isSuper || hasAdminRole;
      });
    } catch (_) {}
  }

  Future<void> _saveHiddenPosts() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        'moments.hidden_posts',
        jsonEncode(_hiddenPostIds.toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadPreferredCity() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = (sp.getString('official.strip_city_label') ?? '').trim();
      if (!mounted || raw.isEmpty) return;
      setState(() {
        _preferredCity = raw;
      });
    } catch (_) {}
  }

  Future<void> _loadMyDisplayName() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final name = (sp.getString('last_login_name') ?? '').trim();
      final phone = (sp.getString('last_login_phone') ?? '').trim().isNotEmpty
          ? (sp.getString('last_login_phone') ?? '').trim()
          : (sp.getString('phone') ?? '').trim();
      final display = name.isNotEmpty ? name : phone;
      if (!mounted) return;
      setState(() {
        _myDisplayName = display;
      });
    } catch (_) {}
  }

  Future<void> _loadMyMomentsPseudonym() async {
    try {
      final tok = (await getSessionTokenForBaseUrl(widget.baseUrl) ?? '').trim();
      final pseudo = tok.isEmpty
          ? null
          : 'User ${crypto.sha1.convert(utf8.encode(tok)).toString().substring(0, 6)}';
      if (!mounted) return;
      setState(() {
        _myMomentsPseudonym = pseudo;
      });
    } catch (_) {}
  }

  Future<void> _loadTrendingTopics() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/topics/trending')
          .replace(queryParameters: const {'limit': '8'});
      final r = await http.get(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl));
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final tag = (m['tag'] ?? '').toString().trim();
        if (tag.isEmpty) continue;
        items.add(m);
      }
      if (!mounted || items.isEmpty) return;
      setState(() {
        _trendingTopics = items;
      });
    } catch (_) {}
  }

  // ignore: unused_element
  Future<void> _openModerationOverview() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final muted = _mutedAuthors.toList()..sort();
    final hidden = _posts
        .where((p) => _hiddenPostIds.contains((p['id'] ?? '').toString()))
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            top: 12,
          ),
          child: GlassPanel(
            radius: 16,
            padding: const EdgeInsets.all(12),
            child: StatefulBuilder(
              builder: (ctx, setModalState) {
                final hasMuted = muted.isNotEmpty;
                final hasHidden = hidden.isNotEmpty;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isArabic
                          ? 'إدارة اللحظات المخفية والمستخدمين المكتومين'
                          : 'Manage hidden posts and muted users',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (!hasMuted && !hasHidden)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          l.isArabic
                              ? 'لا توجد عناصر مخفية أو مكتومة حاليًا.'
                              : 'You do not have any hidden posts or muted users yet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      ),
                    if (hasMuted) ...[
                      Text(
                        l.isArabic
                            ? 'المستخدمون المكتومون'
                            : 'Muted users in Moments',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: muted.map((name) {
                          return FilterChip(
                            label: Text(name),
                            selected: true,
                            onSelected: (_) async {
                              setState(() {
                                _mutedAuthors.remove(name);
                              });
                              setModalState(() {
                                muted.remove(name);
                              });
                              await _saveMutedAuthors();
                            },
                            avatar: const Icon(
                              Icons.volume_off_outlined,
                              size: 16,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (hasHidden) ...[
                      Text(
                        l.isArabic ? 'المنشورات المخفية' : 'Hidden posts',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: hidden.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final p = hidden[i];
                            final id = (p['id'] ?? '').toString();
                            final text = (p['text'] ?? '').toString().trim();
                            final preview = text.isEmpty
                                ? (l.isArabic
                                    ? 'منشور بدون نص'
                                    : 'Post without text')
                                : (text.length > 80
                                    ? '${text.substring(0, 80)}…'
                                    : text);
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                l.isArabic
                                    ? 'اضغط لإلغاء إخفاء هذا المنشور'
                                    : 'Tap to unhide this post',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .65),
                                  fontSize: 11,
                                ),
                              ),
                              onTap: () async {
                                setState(() {
                                  _hiddenPostIds.remove(id);
                                });
                                setModalState(() {
                                  hidden.removeAt(i);
                                });
                                await _saveHiddenPosts();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Map<String, dynamic>? _mapApiPost(Map<String, dynamic> raw) {
    final text = (raw['text'] ?? raw['content'] ?? '').toString();
    final ts =
        (raw['created_at'] ?? raw['ts'] ?? DateTime.now().toIso8601String())
            .toString();
    final likesRaw = raw['likes'] ?? raw['likes_count'] ?? 0;
    final likes = likesRaw is num ? likesRaw.toInt() : 0;
    final likedByMe = (raw['liked_by_me'] as bool?) ?? false;
    final likedBy = <String>[];
    final likedByRaw =
        raw['liked_by'] ?? raw['liked_by_names'] ?? raw['likers'];
    if (likedByRaw is List) {
      for (final e in likedByRaw) {
        if (e == null) continue;
        final s = e.toString().trim();
        if (s.isNotEmpty) likedBy.add(s);
      }
    }
    var id = (raw['id'] ?? raw['post_id'] ?? '').toString();
    if (id.isEmpty) {
      id = 'api_${ts}_${text.hashCode}';
    }
    final imageUrl = (raw['image_url'] ?? raw['image'] ?? '').toString();
    final imageB64 = (raw['image_b64'] ?? '').toString();
    final locationLabel =
        (raw['location_label'] ?? raw['location'] ?? '').toString();
    final audienceTag = (raw['audience_tag'] ?? '').toString();
    final authorName = (raw['author_name'] ??
            raw['display_name'] ??
            raw['user_name'] ??
            raw['user'] ??
            '')
        .toString();
    final authorId = (raw['author_id'] ?? raw['user_id'] ?? '').toString();
    final avatarUrl = (raw['avatar_url'] ?? '').toString();
    final visibility =
        (raw['visibility'] ?? raw['scope'] ?? 'public').toString();
    final commentsRaw = raw['comments'] ?? raw['comment_count'] ?? 0;
    final comments = commentsRaw is num ? commentsRaw.toInt() : 0;
    final images = <String>[];
    final imagesRaw = raw['images'] ?? raw['image_urls'];
    if (imagesRaw is List) {
      for (final e in imagesRaw) {
        if (e == null) continue;
        final s = e.toString();
        if (s.isNotEmpty) images.add(s);
      }
    }
    if (text.trim().isEmpty &&
        imageUrl.isEmpty &&
        imageB64.isEmpty &&
        images.isEmpty) {
      return null;
    }
    return {
      'id': id,
      'text': text,
      'ts': ts,
      'likes': likes,
      'liked_by_me': likedByMe,
      if (likedBy.isNotEmpty) 'liked_by': likedBy,
      'comment_count': comments,
      if (authorName.isNotEmpty) 'author_name': authorName,
      if (authorId.isNotEmpty) 'author_id': authorId,
      if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
      'visibility': visibility,
      if (imageUrl.isNotEmpty) 'image_url': imageUrl,
      if (imageB64.isNotEmpty) 'image_b64': imageB64,
      if (images.isNotEmpty) 'images': images,
      if (locationLabel.isNotEmpty) 'location_label': locationLabel,
      if ((raw['origin_official_account_id'] ?? '').toString().isNotEmpty)
        'origin_official_account_id':
            (raw['origin_official_account_id'] ?? '').toString(),
      if ((raw['origin_official_item_id'] ?? '').toString().isNotEmpty)
        'origin_official_item_id':
            (raw['origin_official_item_id'] ?? '').toString(),
      if (audienceTag.isNotEmpty) 'audience_tag': audienceTag,
      if (raw['has_official_reply'] is bool)
        'has_official_reply': raw['has_official_reply'] as bool,
    };
  }

  Future<void> _loadFromApi() async {
    try {
      final topicTag = (widget.topicTag ?? '').trim();
      Uri uri;
      if (topicTag.isNotEmpty) {
        final tag =
            topicTag.startsWith('#') ? topicTag.substring(1).trim() : topicTag;
        final encTag = Uri.encodeComponent(tag);
        uri = Uri.parse('${widget.baseUrl}/moments/topic/$encTag')
            .replace(queryParameters: const {'limit': '50'});
      } else {
        final qp = <String, String>{'limit': '50'};
        final originAcc = (widget.originOfficialAccountId ?? '').trim();
        if (originAcc.isNotEmpty) {
          qp['official_account_id'] = originAcc;
        } else {
          final cat = (widget.officialCategory ?? '').trim();
          if (cat.isNotEmpty) {
            qp['official_category'] = cat;
          }
          final city = (widget.officialCity ?? '').trim();
          if (city.isNotEmpty) {
            qp['official_city'] = city;
          }
          if (widget.showOnlyMine) {
            qp['own_only'] = 'true';
          }
        }
        uri = Uri.parse('${widget.baseUrl}/moments/feed')
            .replace(queryParameters: qp);
      }
      final r = await http.get(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl));
      if (r.statusCode != 200) return;
      final body = r.body;
      if (body.isEmpty) return;
      final decoded = jsonDecode(body);
      List list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['items'] is List) {
        list = decoded['items'] as List;
      } else {
        return;
      }
      final mapped = list
          .whereType<Map>()
          .map((m) => _mapApiPost(m.cast<String, dynamic>()))
          .whereType<Map<String, dynamic>>()
          .toList();
      if (mapped.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(mapped);
        _usingApi = true;
      });
    } catch (_) {}
  }

  Future<void> _saveLocal() async {
    if (_usingApi) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('moments_posts', jsonEncode(_posts));
    } catch (_) {}
  }

  Future<void> _saveComments() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('moments_comments', jsonEncode(_comments));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadCommentsFromApi(String postId) async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/$postId/comments')
          .replace(queryParameters: const {'limit': '100'});
      final r = await http.get(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl));
      if (r.statusCode < 200 || r.statusCode >= 300) return const [];
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final id = (m['id'] ?? '').toString();
        final text = (m['text'] ?? '').toString();
        final ts = (m['ts'] ?? '').toString();
        if (id.isEmpty || text.isEmpty || ts.isEmpty) continue;
        final replyId = (m['reply_to_id'] ?? '').toString();
        final replyName = (m['reply_to_name'] ?? '').toString();
        final likesRaw = m['likes'] ?? 0;
        final likes = likesRaw is num ? likesRaw.toInt() : 0;
        final likedByMe = (m['liked_by_me'] as bool?) ?? false;
        out.add(<String, dynamic>{
          'id': id,
          'text': text,
          'ts': ts,
          'author_name': (m['author_name'] ?? '').toString(),
          if (replyId.isNotEmpty) 'reply_to': replyId,
          if (replyName.isNotEmpty) 'reply_to_name': replyName,
          'likes': likes,
          'liked_by_me': likedByMe,
        });
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _addCommentApi(
    String postId,
    String text, {
    String? replyToId,
    String? replyToName,
  }) async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/$postId/comments');
      final payload = <String, dynamic>{'text': text};
      if (replyToId != null && replyToId.trim().isNotEmpty) {
        payload['reply_to_id'] = replyToId;
      }
      final r = await http.post(
        uri,
        headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true),
        body: jsonEncode(payload),
      );
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return null;
      final m = decoded.cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final ts = (m['ts'] ?? '').toString();
      final bodyText = (m['text'] ?? '').toString();
      if (id.isEmpty || ts.isEmpty || bodyText.isEmpty) return null;
      return <String, dynamic>{
        'id': id,
        'text': bodyText,
        'ts': ts,
        // On the client we render author name as "You", regardless of backend.
        'author_name': L10n.of(context).isArabic ? 'أنت' : 'You',
        'likes': 0,
        'liked_by_me': false,
        if (replyToId != null && replyToId.trim().isNotEmpty)
          'reply_to': replyToId,
        if (replyToName != null && replyToName.trim().isNotEmpty)
          'reply_to_name': replyToName,
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> _deleteCommentApi(
    String commentId, {
    bool admin = false,
  }) async {
    final id = int.tryParse(commentId.trim());
    if (id == null) return false;
    try {
      final uri = admin
          ? Uri.parse('${widget.baseUrl}/moments/admin/comments/$id')
          : Uri.parse('${widget.baseUrl}/moments/comments/$id');
      final r = await http.delete(
        uri,
        headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true),
      );
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> _likePost(Map<String, dynamic> p) async {
    final alreadyLiked = (p['liked_by_me'] as bool?) ?? false;
    if (alreadyLiked) return;
    final myPseudo = (_myMomentsPseudonym ?? '').trim();
    final selfLabel = myPseudo.isNotEmpty
        ? myPseudo
        : (L10n.of(context).isArabic ? 'أنت' : 'You');
    setState(() {
      final current = (p['likes'] as int?) ?? 0;
      p['likes'] = current + 1;
      p['liked_by_me'] = true;
      final existing = (p['liked_by'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      final cleaned = <String>[];
      final seen = <String>{};
      for (final e in existing) {
        final v = e.trim();
        if (v.isEmpty) continue;
        if (v == selfLabel || v == 'You' || v == 'أنت' || v == myPseudo) {
          continue;
        }
        if (seen.add(v)) cleaned.add(v);
      }
      if (selfLabel.isNotEmpty) {
        cleaned.insert(0, selfLabel);
      }
      if (cleaned.isNotEmpty) {
        p['liked_by'] = cleaned;
      }
    });
    if (!_usingApi) {
      await _saveLocal();
      return;
    }
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/$id/like');
      await http.post(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true));
    } catch (_) {}
  }

  Future<void> _unlikePost(Map<String, dynamic> p) async {
    final liked = (p['liked_by_me'] as bool?) ?? false;
    if (!liked) return;
    final myPseudo = (_myMomentsPseudonym ?? '').trim();
    setState(() {
      final current = (p['likes'] as int?) ?? 0;
      p['likes'] = current > 0 ? current - 1 : 0;
      p['liked_by_me'] = false;
      final existing = (p['liked_by'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      final cleaned = <String>[];
      final seen = <String>{};
      for (final e in existing) {
        final v = e.trim();
        if (v.isEmpty) continue;
        if (v == myPseudo || v == 'You' || v == 'أنت') continue;
        if (seen.add(v)) cleaned.add(v);
      }
      if (cleaned.isNotEmpty) {
        p['liked_by'] = cleaned;
      } else {
        p.remove('liked_by');
      }
    });
    if (!_usingApi) {
      await _saveLocal();
      return;
    }
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/$id/like');
      await http.delete(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true));
    } catch (_) {}
  }

  Future<void> _showMomentPostActionsPopover(
    BuildContext anchorContext,
    Map<String, dynamic> post,
  ) async {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlayBox == null || anchorBox == null) return;

    final l = L10n.of(context);
    final isArabic = l.isArabic;

    final likedByMe = (post['liked_by_me'] as bool?) ?? false;
    final likes = (post['likes'] as int?) ?? 0;
    final isLiked = likedByMe || (!_usingApi && likes > 0);
    final likeLabel = isLiked
        ? (isArabic ? 'إلغاء الإعجاب' : 'Unlike')
        : (isArabic ? 'إعجاب' : 'Like');
    final commentLabel = isArabic ? 'تعليق' : 'Comment';

    final anchorOffset =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorSize = anchorBox.size;

    const menuWidth = 184.0;
    const menuHeight = 42.0;
    const margin = 8.0;

    final overlaySize = overlayBox.size;

    var left = anchorOffset.dx - menuWidth - 10;
    left = left.clamp(margin, overlaySize.width - menuWidth - margin);

    var top = anchorOffset.dy + (anchorSize.height / 2) - (menuHeight / 2);
    top = top.clamp(margin, overlaySize.height - menuHeight - margin);

    final arrowTopRaw = anchorOffset.dy + (anchorSize.height / 2) - 6;
    final arrowTop = arrowTopRaw.clamp(top + 8, top + menuHeight - 14);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: isArabic ? 'إغلاق' : 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, a1, a2) {
        final curved = CurvedAnimation(
          parent: a1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final menu = _ShamellMomentActionMenu(
          likeLabel: likeLabel,
          commentLabel: commentLabel,
          likeEnabled: true,
          onLike: () async {
            Navigator.of(ctx).pop();
            if (isLiked) {
              await _unlikePost(post);
            } else {
              await _likePost(post);
            }
          },
          onComment: () {
            Navigator.of(ctx).pop();
            _startInlineComment(post);
          },
        );

        final arrow = ClipPath(
          clipper: _ShamellPopoverArrowClipper(),
          child: Container(
            width: 10,
            height: 12,
            color: const Color(0xFF4C4C4C),
          ),
        );

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              AnimatedBuilder(
                animation: curved,
                builder: (context, _) {
                  final t = curved.value;
                  final dx = 18 * (1 - t);
                  return Stack(
                    children: [
                      Positioned(
                        left: left,
                        top: top,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: menu,
                          ),
                        ),
                      ),
                      Positioned(
                        left: left + menuWidth - 1,
                        top: arrowTop,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: arrow,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) => child,
    );
  }

  Future<void> _showMomentCommentActionsMenu({
    required Map<String, dynamic> post,
    required Map<String, dynamic> comment,
    Offset? globalPosition,
  }) async {
    final l = L10n.of(context);
    final postId = (post['id'] ?? '').toString().trim();
    if (postId.isEmpty) return;

    final text = (comment['text'] ?? '').toString().trim();
    if (text.isEmpty) return;
    final commentId = (comment['id'] ?? '').toString().trim();
    final authorName = (comment['author_name'] ?? '').toString().trim();
    final myPseudo = (_myMomentsPseudonym ?? '').trim();
    final youLabel = l.isArabic ? 'أنت' : 'You';
    final isMine = authorName == youLabel ||
        authorName == 'You' ||
        authorName == 'أنت' ||
        (myPseudo.isNotEmpty && authorName == myPseudo);
    final canDelete = commentId.isNotEmpty && (isMine || _isAdmin);

    final copyLabel = l.isArabic ? 'نسخ' : 'Copy';
    final deleteLabel = l.isArabic ? 'حذف' : 'Delete';
    final cancelLabel = l.isArabic ? 'إلغاء' : 'Cancel';

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    Future<void> doCopy() async {
      try {
        await Clipboard.setData(ClipboardData(text: text));
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l.isArabic ? 'تم النسخ.' : 'Copied.'),
          ),
        );
    }

    Future<void> doDelete() async {
      if (!canDelete) return;
      var ok = true;
      final useApi = _usingApi && !postId.startsWith('local_');
      final isApiId = useApi && int.tryParse(commentId) != null;
      if (isApiId) {
        if (!isMine && !_isAdmin) {
          ok = false;
        } else if (isMine && !_isAdmin) {
          ok = await _deleteCommentApi(commentId);
        } else if (!isMine && _isAdmin) {
          ok = await _deleteCommentApi(commentId, admin: true);
        } else {
          ok = await _deleteCommentApi(commentId);
          if (!ok) {
            ok = await _deleteCommentApi(commentId, admin: true);
          }
        }
      }
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic ? 'تعذّر حذف التعليق.' : 'Delete failed.',
              ),
            ),
          );
        return;
      }

      if (!mounted) return;
      setState(() {
        final list = List<Map<String, dynamic>>.from(
          _comments[postId] ?? const <Map<String, dynamic>>[],
        );
        if (commentId.isNotEmpty) {
          list.removeWhere((e) => (e['id'] ?? '').toString() == commentId);
        } else {
          list.removeWhere(
            (e) =>
                (e['text'] ?? '').toString().trim() == text &&
                (e['author_name'] ?? '').toString().trim() == authorName,
          );
        }
        _comments[postId] = list;

        final currentCount =
            (post['comment_count'] as int?) ?? (post['comments'] as int?) ?? 0;
        if (currentCount > 0) {
          post['comment_count'] = currentCount - 1;
        }
        if ((_inlineReplyToId ?? '').trim() == commentId) {
          _inlineReplyToId = null;
          _inlineReplyToName = null;
        }
      });
      unawaited(_saveComments());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تم حذف التعليق.' : 'Comment deleted.',
            ),
          ),
        );
    }

    final globalPos = globalPosition;
    if (globalPos != null) {
      final overlay = Overlay.of(context);
      final overlayBox = overlay.context.findRenderObject() as RenderBox?;
      if (overlayBox != null) {
        final overlaySize = overlayBox.size;
        final anchor = overlayBox.globalToLocal(globalPos) - const Offset(0, 8);

        final actionsCount = canDelete ? 2 : 1;
        final menuWidth = actionsCount == 2 ? 168.0 : 104.0;
        const menuHeight = 40.0;
        const arrowW = 14.0;
        const arrowH = 10.0;
        const margin = 8.0;
        const gap = 10.0;

        final canShowAbove = anchor.dy - gap - arrowH - menuHeight >= margin;
        final canShowBelow = anchor.dy + gap + arrowH + menuHeight <=
            overlaySize.height - margin;
        final showAbove = canShowAbove || !canShowBelow;

        var left = anchor.dx - (menuWidth / 2);
        left = left.clamp(margin, overlaySize.width - menuWidth - margin);

        double top;
        if (showAbove) {
          top = anchor.dy - gap - arrowH - menuHeight;
        } else {
          top = anchor.dy + gap + arrowH;
        }
        top = top.clamp(margin, overlaySize.height - menuHeight - margin);

        var arrowLeft = anchor.dx - (arrowW / 2);
        arrowLeft = arrowLeft.clamp(left + 10, left + menuWidth - arrowW - 10);
        final arrowTop = showAbove ? (top + menuHeight) : (top - arrowH);

        final bg = const Color(0xFF2C2C2C);
        final menu = Material(
          color: Colors.transparent,
          child: Container(
            width: menuWidth,
            height: menuHeight,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      Navigator.of(context).pop();
                      await doCopy();
                    },
                    child: Center(
                      child: Text(
                        copyLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                if (canDelete) ...[
                  Container(
                    width: 1,
                    height: 22,
                    color: Colors.white.withValues(alpha: .14),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        Navigator.of(context).pop();
                        await doDelete();
                      },
                      child: Center(
                        child: Text(
                          deleteLabel,
                          style: const TextStyle(
                            color: Color(0xFFFA5151),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

        final arrow = ClipPath(
          clipper: showAbove
              ? _ShamellPopoverDownArrowClipper()
              : _ShamellPopoverUpArrowClipper(),
          child: Container(
            width: arrowW,
            height: arrowH,
            color: bg,
          ),
        );

        await showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: cancelLabel,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 150),
          pageBuilder: (ctx, a1, _) {
            final curved = CurvedAnimation(
              parent: a1,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: curved,
                    builder: (context, _) {
                      final t = curved.value;
                      final dx = 14 * (1 - t);
                      return Stack(
                        children: [
                          Positioned(
                            left: left,
                            top: top,
                            child: Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(dx, 0),
                                child: menu,
                              ),
                            ),
                          ),
                          Positioned(
                            left: arrowLeft,
                            top: arrowTop,
                            child: Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(dx, 0),
                                child: arrow,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
          transitionBuilder: (ctx, anim, _, child) => child,
        );
        return;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sheetTheme = Theme.of(ctx);

        Widget actionRow({
          required String label,
          Color? color,
          required VoidCallback onTap,
        }) {
          return InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: sheetTheme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color ?? sheetTheme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        }

        Widget card(List<Widget> children) {
          return Material(
            color: sheetTheme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                card([
                  actionRow(
                    label: copyLabel,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await doCopy();
                    },
                  ),
                  if (canDelete) ...[
                    const Divider(height: 1),
                    actionRow(
                      label: deleteLabel,
                      color: const Color(0xFFFA5151),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await doDelete();
                      },
                    ),
                  ],
                ]),
                const SizedBox(height: 8),
                card([
                  actionRow(
                    label: cancelLabel,
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _addPostApi(
    String text, {
    String? imageB64,
    List<String>? imagesB64,
    String? locationLabel,
  }) async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments');
      final tagLabel = _visibilityTag?.trim();
      String visibility;
      if (tagLabel != null && tagLabel.isNotEmpty) {
        if (_visibilityTagMode == 'except') {
          visibility = 'friends_except:$tagLabel';
        } else {
          visibility = 'tag:$tagLabel';
        }
      } else {
        visibility = _visibilityScope;
      }
      final payload = <String, dynamic>{
        'text': text,
        'visibility': visibility,
      };
      final images = <String>[];
      for (final raw in (imagesB64 ?? const <String>[])) {
        final s = raw.trim();
        if (s.isEmpty) continue;
        images.add(s);
        if (images.length >= 9) break;
      }
      if (images.isEmpty) {
        final single = (imageB64 ?? '').trim();
        if (single.isNotEmpty) {
          images.add(single);
        }
      }
      if (images.isNotEmpty) {
        payload['images_b64'] = images;
        payload['image_b64'] = images.first;
      }
      final loc = (locationLabel ?? '').trim();
      if (loc.isNotEmpty) {
        payload['location_label'] = loc;
      }
      final r = await http.post(
        uri,
        headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true),
        body: jsonEncode(payload),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        try {
          final decoded = jsonDecode(r.body);
          if (decoded is Map) {
            final mapped = _mapApiPost(decoded.cast<String, dynamic>());
            if (mapped != null && mounted) {
              setState(() {
                if (loc.isNotEmpty) {
                  mapped['location_label'] ??= loc;
                }
                if (images.length > 1) {
                  final existing = (mapped['images'] as List?)
                          ?.whereType<String>()
                          .toList() ??
                      const <String>[];
                  if (existing.isEmpty) {
                    mapped['images'] = images;
                  }
                }
                _posts.insert(0, mapped);
              });
            }
          } else {
            await _loadFromApi();
          }
        } catch (_) {
          await _loadFromApi();
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _addPostLocal(
    String text, {
    List<String>? imagesB64,
    String? locationLabel,
    bool clearInlineComposer = true,
  }) async {
    final id =
        'local_${DateTime.now().millisecondsSinceEpoch}_${_posts.length}';
    final fromPending =
        _pendingImage != null ? base64Encode(_pendingImage!) : null;
    final fromPreset =
        _presetImage != null ? base64Encode(_presetImage!) : null;
    final provided = (imagesB64 ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(9)
        .toList();
    final images = provided.isNotEmpty
        ? provided
        : <String>[
            if ((fromPending ?? '').trim().isNotEmpty) fromPending!.trim(),
            if ((fromPending ?? '').trim().isEmpty &&
                (fromPreset ?? '').trim().isNotEmpty)
              fromPreset!.trim(),
          ];
    final loc = (locationLabel ?? '').trim();
    String visibility = _visibilityScope;
    final tagLabel = _visibilityTag?.trim();
    String? audienceTag;
    if (tagLabel != null && tagLabel.isNotEmpty) {
      audienceTag = tagLabel;
      if (_visibilityTagMode == 'except') {
        visibility = 'friends_except_tag';
      } else {
        visibility = 'friends_tag';
      }
    }
    setState(() {
      final post = <String, dynamic>{
        'id': id,
        'text': text,
        'ts': DateTime.now().toIso8601String(),
        'likes': 0,
        'visibility': visibility,
        if (audienceTag != null && audienceTag.isNotEmpty)
          'audience_tag': audienceTag,
        if (loc.isNotEmpty) 'location_label': loc,
      };
      if (images.length > 1) {
        post['images'] = images;
        post['image_b64'] = images.first;
      } else if (images.length == 1) {
        post['image_b64'] = images.first;
        if (_pendingImageMime != null && clearInlineComposer) {
          post['image_mime'] = _pendingImageMime;
        }
      }
      _posts.insert(0, post);
      if (clearInlineComposer) {
        _postCtrl.clear();
        _pendingImage = null;
        _pendingImageMime = null;
      }
    });
    await _saveLocal();
  }

  Future<void> _addPost() async {
    final text = _postCtrl.text.trim().isEmpty && _presetText != null
        ? _presetText!
        : _postCtrl.text.trim();
    if (text.isEmpty) return;
    final imgB64 = _pendingImage != null
        ? base64Encode(_pendingImage!)
        : (_presetImage != null ? base64Encode(_presetImage!) : null);
    if (_usingApi) {
      final ok = await _addPostApi(text, imageB64: imgB64);
      if (ok) {
        _postCtrl.clear();
        _clearPendingImage();
        return;
      }
    }
    await _addPostLocal(text);
  }

  Future<void> _deletePost(Map<String, dynamic> p) async {
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() {
      _posts.removeWhere((e) => (e['id'] ?? '').toString() == id);
    });
    if (!_usingApi) {
      await _saveLocal();
    }
  }

  Future<void> _toggleVisibility(Map<String, dynamic> p) async {
    final current = (p['visibility'] ?? 'public').toString();
    final next =
        (current == 'only_me' || current == 'private') ? 'public' : 'only_me';
    setState(() {
      p['visibility'] = next;
    });
    if (!_usingApi) {
      await _saveLocal();
      return;
    }
    final postId = (p['id'] ?? '').toString();
    if (postId.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/$postId');
      final payload = jsonEncode(<String, dynamic>{'visibility': next});
      await http.patch(
        uri,
        headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true),
        body: payload,
      );
    } catch (_) {}
  }

  Future<void> _reportPost(String postId) async {
    final l = L10n.of(context);
    if (postId.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/$postId/report');
      final payload = jsonEncode(<String, dynamic>{
        'reason': 'client_report',
      });
      final r = await http.post(
        uri,
        headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true),
        body: payload,
      );
      if (!mounted) return;
      final ok = r.statusCode >= 200 && r.statusCode < 300;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (l.isArabic ? 'تم إرسال البلاغ.' : 'Report sent.')
                : (l.isArabic
                    ? 'تعذّر إرسال البلاغ.'
                    : 'Failed to send report.'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final l2 = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l2.isArabic ? 'تعذّر إرسال البلاغ.' : 'Failed to send report.',
          ),
        ),
      );
    }
  }

  Future<void> _openPostActions(Map<String, dynamic> p) async {
    final l = L10n.of(context);
    final text = (p['text'] ?? '').toString();
    final isLocal = (p['id'] ?? '').toString().startsWith('local_');
    final visibility = (p['visibility'] ?? 'public').toString();
    final postId = (p['id'] ?? '').toString();
    final authorName = (p['author_name'] ?? '').toString().trim();
    final hasAuthor = authorName.isNotEmpty;
    final isMutedAuthor = hasAuthor && _mutedAuthors.contains(authorName);
    final bool canToggleVisibility =
        isLocal || (_usingApi && widget.showOnlyMine && postId.isNotEmpty);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'خيارات المنشور' : 'Post actions',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (text.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy, size: 20),
                    title: Text(l.isArabic ? 'نسخ' : 'Copy'),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.isArabic
                              ? 'تم نسخ النص'
                              : 'Text copied to clipboard'),
                        ),
                      );
                    },
                  ),
                if (text.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.share_outlined, size: 20),
                    title: Text(l.isArabic ? 'مشاركة' : 'Share'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Share.share(text.trim());
                    },
                  ),
                if (canToggleVisibility)
                  ListTile(
                    leading: Icon(
                      (visibility == 'only_me' || visibility == 'private')
                          ? Icons.public_outlined
                          : Icons.lock_outline,
                      size: 20,
                    ),
                    title: Text(
                      (visibility == 'only_me' || visibility == 'private')
                          ? (l.isArabic ? 'جعلها عامة' : 'Make post public')
                          : (l.isArabic
                              ? 'جعلها مرئية لي فقط'
                              : 'Make visible to me only'),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _toggleVisibility(p);
                    },
                  ),
                if (isLocal)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, size: 20),
                    title:
                        Text(l.isArabic ? 'حذف المنشور' : 'Delete this post'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _deletePost(p);
                    },
                  ),
                if (!isLocal && postId.isNotEmpty)
                  ListTile(
                    leading:
                        const Icon(Icons.visibility_off_outlined, size: 20),
                    title: Text(
                      l.isArabic ? 'إخفاء هذا المنشور' : 'Hide this post',
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      setState(() {
                        _hiddenPostIds.add(postId);
                      });
                      await _saveHiddenPosts();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l.isArabic
                                ? 'تم إخفاء هذا المنشور من موجز اللحظات.'
                                : 'This post was hidden from your Moments feed.',
                          ),
                        ),
                      );
                    },
                  ),
                if (!isLocal && postId.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.flag_outlined, size: 20),
                    title: Text(
                      l.isArabic
                          ? 'الإبلاغ عن هذا المنشور'
                          : 'Report this post',
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _reportPost(postId);
                    },
                  ),
                if (!isLocal && hasAuthor)
                  ListTile(
                    leading: Icon(
                      isMutedAuthor
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                      size: 20,
                    ),
                    title: Text(
                      isMutedAuthor
                          ? (l.isArabic
                              ? 'إلغاء كتم هذا المستخدم في اللحظات'
                              : 'Unmute this user in Moments')
                          : (l.isArabic
                              ? 'كتم هذا المستخدم في اللحظات'
                              : 'Mute this user in Moments'),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      setState(() {
                        if (isMutedAuthor) {
                          _mutedAuthors.remove(authorName);
                        } else {
                          _mutedAuthors.add(authorName);
                        }
                      });
                      await _saveMutedAuthors();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isOfficialShare(Map<String, dynamic> p) {
    final originAccId =
        (p['origin_official_account_id'] ?? '').toString().trim();
    if (originAccId.isNotEmpty) return true;
    final text = (p['text'] ?? '').toString();
    return text.contains('shamell://official/');
  }

  bool _isOfficialInPreferredCity(Map<String, dynamic> p) {
    final city = (_preferredCity ?? '').trim();
    if (city.isEmpty) return false;
    final originAccId =
        (p['origin_official_account_id'] ?? '').toString().trim();
    if (originAccId.isEmpty) return false;
    final acc = _officialAccounts[originAccId];
    if (acc == null) return false;
    final accCity = (acc.city ?? '').trim();
    if (accCity.isEmpty) return false;
    return accCity.toLowerCase() == city.toLowerCase();
  }

  bool _isRecentPost(Map<String, dynamic> p) {
    final rawTs = (p['ts'] ?? '').toString();
    if (rawTs.isEmpty) return false;
    try {
      final dt = DateTime.parse(rawTs).toUtc();
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 3));
      return dt.isAfter(cutoff);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openComments(
    Map<String, dynamic> p, {
    String? highlightCommentId,
    bool focusInput = false,
  }) async {
    final l = L10n.of(context);
    final postId = (p['id'] ?? '').toString();
    if (postId.isEmpty) return;
    _dismissInlineComment();
    final originAccId =
        (p['origin_official_account_id'] ?? '').toString().trim();
    final canAdminReply =
        _isAdmin && originAccId.isNotEmpty && !postId.startsWith('local_');
    final youLabel = l.isArabic ? 'أنت' : 'You';
    String? myPseudonym;
    try {
      final tok = (await getSessionTokenForBaseUrl(widget.baseUrl) ?? '').trim();
      if (tok.isNotEmpty) {
        final hex = crypto.sha1.convert(utf8.encode(tok)).toString();
        if (hex.length >= 6) {
          myPseudonym = 'User ${hex.substring(0, 6)}';
        }
      }
    } catch (_) {}

    String displayNameForAuthor(String authorName) {
      final raw = authorName.trim();
      if (raw.isEmpty) return youLabel;
      if (raw == 'You' || raw == 'أنت') return youLabel;
      if (myPseudonym != null && raw == myPseudonym) return youLabel;
      if (raw.startsWith('Official ·')) {
        final parts = raw.split('Official ·');
        if (parts.length >= 2) {
          final officialAccId = parts.last.trim();
          final officialAcc =
              officialAccId.isEmpty ? null : _officialAccounts[officialAccId];
          if (officialAcc != null && officialAcc.name.isNotEmpty) {
            return 'Official · ${officialAcc.name}';
          }
        }
      }
      return raw;
    }

    List<Map<String, dynamic>> existing;
    final useApi = _usingApi && !postId.startsWith('local_');
    if (useApi) {
      existing = await _loadCommentsFromApi(postId);
    } else {
      existing = List<Map<String, dynamic>>.from(
          _comments[postId] ?? const <Map<String, dynamic>>[]);
    }
    // Ensure older flat comments also have minimal metadata so threading works.
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < existing.length; i++) {
      final c = existing[i];
      final id = (c['id'] ?? '').toString();
      if (id.isEmpty) {
        c['id'] = 'c_${now}_$i';
      }
      final author = (c['author_name'] ?? '').toString().trim();
      if (author.isEmpty ||
          author == 'You' ||
          author == 'أنت' ||
          (myPseudonym != null && author == myPseudonym)) {
        c['author_name'] = youLabel;
      }
    }

    final byId = <String, String>{};
    for (final c in existing) {
      final id = (c['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final author = (c['author_name'] ?? '').toString();
      byId[id] = displayNameForAuthor(author);
    }
    for (final c in existing) {
      final replyTo =
          (c['reply_to'] ?? c['reply_to_id'] ?? '').toString().trim();
      if (replyTo.isEmpty) continue;
      c['reply_to'] = replyTo;
      final replyName = (c['reply_to_name'] ?? '').toString().trim();
      if (replyName.isNotEmpty) continue;
      final targetName = byId[replyTo];
      if (targetName != null && targetName.isNotEmpty) {
        c['reply_to_name'] = targetName;
      }
    }
    if (existing.isNotEmpty) {
      setState(() {
        _comments[postId] = existing;
      });
      // ignore: discarded_futures
      _saveComments();
    }

    final ctrl = TextEditingController();
    final inputFocus = FocusNode();
    String? replyToId;
    String? replyToName;
    ScrollController? listScrollCtrl;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .28),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final sheetBg = isDark ? theme.colorScheme.surface : Colors.white;
        final inputBg =
            isDark ? theme.colorScheme.surface : ShamellPalette.background;
        final dividerColor =
            isDark ? theme.dividerColor : ShamellPalette.divider;
        final nameColor =
            isDark ? theme.colorScheme.primary : const Color(0xFF576B95);
        final fieldBg = isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55)
            : Colors.white;
        final fieldBorder =
            isDark ? theme.dividerColor : ShamellPalette.divider;
        final sendDisabledBg = isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45)
            : ShamellPalette.searchFill;

        final baseStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 13) ??
            const TextStyle(fontSize: 13);
        final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: .60),
            ) ??
            TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: .60),
            );

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final visible = existing;

            Future<void> submitComment() async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Map<String, dynamic>? comment;
              if (useApi) {
                comment = await _addCommentApi(
                  postId,
                  text,
                  replyToId: replyToId,
                  replyToName: replyToName,
                );
              } else {
                comment = <String, dynamic>{
                  'text': text,
                  'ts': DateTime.now().toIso8601String(),
                  'id':
                      'c_${DateTime.now().millisecondsSinceEpoch}_${existing.length}',
                  'author_name': youLabel,
                  if (replyToId != null) 'reply_to': replyToId,
                  if (replyToName != null) 'reply_to_name': replyToName,
                };
              }
              if (comment == null) return;
              ctrl.clear();
              setState(() {
                final list = List<Map<String, dynamic>>.from(
                  _comments[postId] ?? const <Map<String, dynamic>>[],
                );
                list.add(comment!);
                _comments[postId] = list;
                final currentCount = (p['comment_count'] as int?) ??
                    (p['comments'] as int?) ??
                    0;
                if (currentCount > 0) {
                  p['comment_count'] = currentCount + 1;
                }
              });
              setModalState(() {
                existing.add(comment!);
                replyToId = null;
                replyToName = null;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final c = listScrollCtrl;
                if (c == null || !c.hasClients) return;
                try {
                  c.animateTo(
                    c.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                  );
                } catch (_) {}
              });
              if (!useApi) {
                // ignore: discarded_futures
                _saveComments();
              }
            }

            Widget buildCommentTile(
              Map<String, dynamic> c,
              int index,
            ) {
              final text = (c['text'] ?? '').toString();
              final authorName = (c['author_name'] ?? youLabel).toString();
              final replyName = (c['reply_to_name'] ?? '').toString();
              final replyToRaw = (c['reply_to'] ?? '').toString().trim();
              final isReply = replyToRaw.isNotEmpty;

              final commentId = (c['id'] ?? 'c_${now}_$index').toString();
              final isHighlighted = highlightCommentId != null &&
                  highlightCommentId.isNotEmpty &&
                  highlightCommentId == commentId;

              final displayName = displayNameForAuthor(authorName);
              final replyDisplayName = replyName.trim().isEmpty
                  ? ''
                  : displayNameForAuthor(replyName);

              final authorRaw = authorName.trim();
              final isMine = authorRaw == youLabel ||
                  authorRaw == 'You' ||
                  authorRaw == 'أنت' ||
                  (myPseudonym != null && authorRaw == myPseudonym);
              final canDelete = isMine || _isAdmin;

              final commentTextSpan = TextSpan(
                style: baseStyle.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .92),
                ),
                children: [
                  TextSpan(
                    text: displayName,
                    style: baseStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: nameColor,
                    ),
                  ),
                  if (isReply && replyDisplayName.isNotEmpty) ...[
                    TextSpan(
                      text: l.isArabic ? ' ردًا على ' : ' replied to ',
                      style: baseStyle.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    TextSpan(
                      text: replyDisplayName,
                      style: baseStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: nameColor,
                      ),
                    ),
                  ],
                  TextSpan(text: ': $text'),
                ],
              );

              return InkWell(
                onTap: () {
                  setModalState(() {
                    replyToId = commentId;
                    replyToName = displayName;
                  });
                  try {
                    HapticFeedback.selectionClick();
                  } catch (_) {}
                  inputFocus.requestFocus();
                },
                onLongPress: () async {
                  try {
                    HapticFeedback.lightImpact();
                  } catch (_) {}
                  final action = await showModalBottomSheet<String>(
                    context: ctx,
                    backgroundColor: sheetBg,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    builder: (actx) {
                      final l2 = L10n.of(actx);
                      Widget tile({
                        required IconData icon,
                        required String title,
                        required String value,
                        Color? color,
                      }) {
                        return ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(
                            title,
                            style: color == null
                                ? null
                                : TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                          ),
                          onTap: () => Navigator.of(actx).pop(value),
                        );
                      }

                      return SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            tile(
                              icon: Icons.copy,
                              title: l2.isArabic ? 'نسخ' : 'Copy',
                              value: 'copy',
                            ),
                            if (canDelete)
                              tile(
                                icon: Icons.delete_outline,
                                title: l2.isArabic ? 'حذف' : 'Delete',
                                value: 'delete',
                                color: Colors.redAccent,
                              ),
                            const Divider(height: 1),
                            ListTile(
                              title: Center(
                                child: Text(
                                  l2.isArabic ? 'إلغاء' : 'Cancel',
                                  style: TextStyle(
                                    color: Theme.of(actx).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              onTap: () => Navigator.of(actx).pop(),
                            ),
                          ],
                        ),
                      );
                    },
                  );

                  if (!mounted || action == null) return;
                  if (action == 'copy') {
                    try {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              l.isArabic ? 'تم النسخ.' : 'Copied.',
                            ),
                          ),
                        );
                    } catch (_) {}
                    return;
                  }

                  if (action == 'delete') {
                    if (!canDelete) return;
                    final idx = existing.indexWhere(
                      (e) => (e['id'] ?? '').toString() == commentId,
                    );
                    if (idx < 0) return;

                    var ok = true;
                    final isApiId = useApi && int.tryParse(commentId) != null;
                    if (isApiId) {
                      if (!isMine && !_isAdmin) {
                        ok = false;
                      } else if (isMine && !_isAdmin) {
                        ok = await _deleteCommentApi(commentId);
                      } else if (!isMine && _isAdmin) {
                        ok = await _deleteCommentApi(commentId, admin: true);
                      } else {
                        ok = await _deleteCommentApi(commentId);
                        if (!ok) {
                          ok = await _deleteCommentApi(commentId, admin: true);
                        }
                      }
                    }

                    if (!ok) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              l.isArabic
                                  ? 'تعذّر حذف التعليق.'
                                  : 'Delete failed.',
                            ),
                          ),
                        );
                      return;
                    }

                    setState(() {
                      final list = List<Map<String, dynamic>>.from(
                        _comments[postId] ?? const <Map<String, dynamic>>[],
                      );
                      list.removeWhere(
                        (e) => (e['id'] ?? '').toString() == commentId,
                      );
                      _comments[postId] = list;

                      final currentCount = (p['comment_count'] as int?) ??
                          (p['comments'] as int?) ??
                          0;
                      if (currentCount > 0) {
                        p['comment_count'] = currentCount - 1;
                      }
                    });
                    setModalState(() {
                      existing.removeAt(idx);
                      if (replyToId == commentId) {
                        replyToId = null;
                        replyToName = null;
                      }
                    });
                    // ignore: discarded_futures
                    _saveComments();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            l.isArabic ? 'تم حذف التعليق.' : 'Comment deleted.',
                          ),
                        ),
                      );
                  }
                },
                child: Container(
                  margin: isHighlighted ? const EdgeInsets.only(top: 4) : null,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: isHighlighted
                      ? BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(8),
                        )
                      : null,
                  child: RichText(
                    text: commentTextSpan,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }

            final title = l.isArabic ? 'التعليقات' : 'Comments';
            final countSuffix =
                existing.isNotEmpty ? '(${existing.length})' : '';

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: existing.isEmpty ? 0.55 : 0.75,
                minChildSize: 0.35,
                maxChildSize: 0.95,
                builder: (ctx, scrollController) {
                  listScrollCtrl = scrollController;
                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    child: Material(
                      color: sheetBg,
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .20),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 44,
                              child: Stack(
                                children: [
                                  PositionedDirectional(
                                    start: 2,
                                    top: 0,
                                    bottom: 0,
                                    child: IconButton(
                                      tooltip: l.isArabic ? 'إغلاق' : 'Close',
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        size: 20,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => Navigator.of(ctx).pop(),
                                    ),
                                  ),
                                  Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          title,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (countSuffix.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            countSuffix,
                                            style: secondaryStyle,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  PositionedDirectional(
                                    end: 2,
                                    top: 0,
                                    bottom: 0,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (canAdminReply)
                                          IconButton(
                                            tooltip: l.isArabic
                                                ? 'رد كحساب خدمة'
                                                : 'Reply as service',
                                            icon: const Icon(
                                              Icons.campaign_outlined,
                                              size: 20,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () async {
                                              final originAcc =
                                                  _officialAccounts[
                                                      originAccId];
                                              final accName = originAcc?.name ??
                                                  originAccId;
                                              final textCtrl =
                                                  TextEditingController();
                                              await showDialog<void>(
                                                context: ctx,
                                                builder: (dctx) {
                                                  return AlertDialog(
                                                    title: Text(
                                                      l.isArabic
                                                          ? 'رد كحساب خدمة'
                                                          : 'Reply as service account',
                                                    ),
                                                    content: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          l.isArabic
                                                              ? 'سيظهر الرد باسم الحساب الرسمي: $accName'
                                                              : 'Reply will appear as official account: $accName',
                                                          style: Theme.of(dctx)
                                                              .textTheme
                                                              .bodySmall,
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        TextField(
                                                          controller: textCtrl,
                                                          minLines: 2,
                                                          maxLines: 4,
                                                          decoration:
                                                              InputDecoration(
                                                            hintText: l.isArabic
                                                                ? 'نص الرد...'
                                                                : 'Reply text...',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () {
                                                          Navigator.of(dctx)
                                                              .pop();
                                                        },
                                                        child: Text(
                                                          l.isArabic
                                                              ? 'إلغاء'
                                                              : 'Cancel',
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () async {
                                                          final txt = textCtrl
                                                              .text
                                                              .trim();
                                                          if (txt.isEmpty) {
                                                            return;
                                                          }
                                                          Navigator.of(dctx)
                                                              .pop();
                                                          final created =
                                                              await _addOfficialAdminComment(
                                                            postId,
                                                            originAccId,
                                                            txt,
                                                          );
                                                          if (created == null) {
                                                            return;
                                                          }
                                                          setModalState(() {
                                                            existing
                                                                .add(created);
                                                          });
                                                          setState(() {
                                                            final list = List<
                                                                Map<String,
                                                                    dynamic>>.from(
                                                              _comments[
                                                                      postId] ??
                                                                  const <Map<
                                                                      String,
                                                                      dynamic>>[],
                                                            );
                                                            list.add(created);
                                                            _comments[postId] =
                                                                list;
                                                          });
                                                        },
                                                        child: Text(
                                                          l.isArabic
                                                              ? 'إرسال'
                                                              : 'Send',
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: dividerColor,
                            ),
                            Expanded(
                              child: visible.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                          l.isArabic
                                              ? 'كن أول من يعلّق على هذه اللحظة.'
                                              : 'Be the first to comment on this moment.',
                                          style: secondaryStyle,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: scrollController,
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        10,
                                        16,
                                        10,
                                      ),
                                      itemCount: visible.length,
                                      itemBuilder: (ctx, i) {
                                        return buildCommentTile(visible[i], i);
                                      },
                                    ),
                            ),
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              decoration: BoxDecoration(
                                color: inputBg,
                                border: Border(
                                  top: BorderSide(
                                    color: dividerColor,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((replyToName ?? '').trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              l.isArabic
                                                  ? 'الرد على $replyToName'
                                                  : 'Replying to $replyToName',
                                              style: secondaryStyle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            icon: Icon(
                                              Icons.close,
                                              size: 18,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: .60),
                                            ),
                                            onPressed: () {
                                              setModalState(() {
                                                replyToId = null;
                                                replyToName = null;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: fieldBg,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: fieldBorder,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: TextField(
                                            controller: ctrl,
                                            focusNode: inputFocus,
                                            autofocus: focusInput,
                                            minLines: 1,
                                            maxLines: 4,
                                            textInputAction:
                                                TextInputAction.send,
                                            onSubmitted: (_) {
                                              // ignore: discarded_futures
                                              submitComment();
                                            },
                                            style: baseStyle.copyWith(
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                            decoration: InputDecoration(
                                              border: InputBorder.none,
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 10,
                                              ),
                                              hintText: replyToName == null
                                                  ? (l.isArabic
                                                      ? 'أضف تعليقاً...'
                                                      : 'Add a comment...')
                                                  : (l.isArabic
                                                      ? 'رداً على $replyToName...'
                                                      : 'Reply to $replyToName...'),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: ctrl,
                                        builder: (ctx, value, _) {
                                          final canSend =
                                              value.text.trim().isNotEmpty;
                                          return TextButton(
                                            onPressed: canSend
                                                ? () {
                                                    // ignore: discarded_futures
                                                    submitComment();
                                                  }
                                                : null,
                                            style: TextButton.styleFrom(
                                              backgroundColor:
                                                  ShamellPalette.green,
                                              disabledBackgroundColor:
                                                  sendDisabledBg,
                                              foregroundColor: Colors.white,
                                              disabledForegroundColor: theme
                                                  .colorScheme.onSurface
                                                  .withValues(alpha: .38),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 9,
                                              ),
                                              minimumSize: const Size(0, 34),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                            ),
                                            child: Text(
                                              l.isArabic ? 'إرسال' : 'Send',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
    ctrl.dispose();
    inputFocus.dispose();
  }

  Widget _buildInlineCommentBar(L10n l, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final inputBg =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final dividerColor = isDark ? theme.dividerColor : ShamellPalette.divider;
    final fieldBg = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55)
        : Colors.white;
    final fieldBorder = isDark ? theme.dividerColor : ShamellPalette.divider;
    final sendDisabledBg = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45)
        : ShamellPalette.searchFill;

    final baseStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 13) ??
        const TextStyle(fontSize: 13);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
          fontSize: 11,
          color: theme.colorScheme.onSurface.withValues(alpha: .60),
        ) ??
        TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurface.withValues(alpha: .60),
        );
    final replyName = (_inlineReplyToName ?? '').trim();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: inputBg,
          border: Border(
            top: BorderSide(
              color: dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.isArabic
                            ? 'الرد على $replyName'
                            : 'Replying to $replyName',
                        style: secondaryStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .60),
                      ),
                      onPressed: () {
                        setState(() {
                          _inlineReplyToId = null;
                          _inlineReplyToName = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: fieldBorder,
                        width: 0.8,
                      ),
                    ),
                    child: TextField(
                      controller: _inlineCommentCtrl,
                      focusNode: _inlineCommentFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => unawaited(_submitInlineComment()),
                      style: baseStyle.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        hintText: replyName.isEmpty
                            ? (l.isArabic
                                ? 'أضف تعليقاً...'
                                : 'Add a comment...')
                            : (l.isArabic
                                ? 'ردًا على $replyName...'
                                : 'Reply to $replyName...'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _inlineCommentCtrl,
                  builder: (ctx, value, _) {
                    final canSend =
                        value.text.trim().isNotEmpty && !_inlineCommentSending;
                    return TextButton(
                      onPressed: canSend
                          ? () => unawaited(_submitInlineComment())
                          : null,
                      style: TextButton.styleFrom(
                        backgroundColor: ShamellPalette.green,
                        disabledBackgroundColor: sendDisabledBg,
                        foregroundColor: Colors.white,
                        disabledForegroundColor:
                            theme.colorScheme.onSurface.withValues(alpha: .38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: _inlineCommentSending
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withValues(alpha: .90),
                                ),
                              ),
                            )
                          : Text(
                              l.isArabic ? 'إرسال' : 'Send',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget buildPost(Map<String, dynamic> p) {
      final text = (p['text'] ?? '').toString();
      final rawTs = (p['ts'] ?? '').toString();
      final likes = (p['likes'] as int?) ?? 0;
      final likedByMe = (p['liked_by_me'] as bool?) ?? false;
      final likedByList =
          (p['liked_by'] as List?)?.whereType<String>().toList() ??
              const <String>[];
      final postId = (p['id'] ?? '').toString();
      final apiCommentCount =
          (p['comment_count'] as int?) ?? (p['comments'] as int?) ?? 0;
      final localCommentCount =
          postId.isEmpty ? 0 : (_comments[postId]?.length ?? 0);
      final commentCount =
          apiCommentCount > 0 ? apiCommentCount : localCommentCount;
      final imageUrl = (p['image_url'] ?? '').toString();
      final imageB64 = (p['image_b64'] ?? '').toString();
      final imagesList = (p['images'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      final authorName = (p['author_name'] ?? '').toString();
      final avatarUrl = (p['avatar_url'] ?? '').toString();
      final isLocal = p['id']?.toString().startsWith('local_') ?? false;
      final visibility = (p['visibility'] ?? 'public').toString();
      final hasOfficialReply = (p['has_official_reply'] as bool?) ?? false;
      final originAccId =
          (p['origin_official_account_id'] ?? '').toString().trim();
      final originAcc =
          originAccId.isNotEmpty ? _officialAccounts[originAccId] : null;

      DateTime? dt;
      try {
        dt = DateTime.parse(rawTs).toLocal();
      } catch (_) {}
      final ts = dt == null
          ? ''
          : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
              ' · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

      final heroBase = postId.isNotEmpty
          ? postId
          : '${rawTs}_${authorName}_${text.hashCode}';

      Widget? imageWidget;
      if (imagesList.isNotEmpty) {
        final heroTags = List<String>.generate(
          imagesList.length,
          (i) => 'moment:$heroBase:$i',
        );
        final count = imagesList.length;
        final columns = count == 1
            ? 1
            : count == 2
                ? 2
                : count == 4
                    ? 2
                    : 3;
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: imagesList.length,
            itemBuilder: (ctx, i) {
              final raw = imagesList[i].trim();
              final heroTag = heroTags[i];
              final isHttp =
                  raw.startsWith('http://') || raw.startsWith('https://');
              if (isHttp) {
                return GestureDetector(
                  onTap: () => unawaited(
                    _openPhotoViewer(
                      imagesList,
                      initialIndex: i,
                      heroTags: heroTags,
                    ),
                  ),
                  child: Hero(
                    tag: heroTag,
                    child: Image.network(raw, fit: BoxFit.cover),
                  ),
                );
              }
              final b64 =
                  raw.contains('base64,') ? raw.split('base64,').last : raw;
              try {
                final bytes = base64Decode(b64);
                return GestureDetector(
                  onTap: () => unawaited(
                    _openPhotoViewer(
                      imagesList,
                      initialIndex: i,
                      heroTags: heroTags,
                    ),
                  ),
                  child: Hero(
                    tag: heroTag,
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  ),
                );
              } catch (_) {
                return GestureDetector(
                  onTap: () => unawaited(
                    _openPhotoViewer(
                      imagesList,
                      initialIndex: i,
                      heroTags: heroTags,
                    ),
                  ),
                  child: Hero(
                    tag: heroTag,
                    child: Container(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: isDark ? .30 : .55),
                    ),
                  ),
                );
              }
            },
          ),
        );
      } else if (imageB64.isNotEmpty) {
        try {
          final bytes = base64Decode(imageB64);
          final heroTag = 'moment:$heroBase:0';
          imageWidget = GestureDetector(
            onTap: () => unawaited(
              _openPhotoViewer(
                [imageB64],
                heroTags: [heroTag],
              ),
            ),
            child: Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  bytes,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        } catch (_) {}
      } else if (imageUrl.isNotEmpty) {
        final heroTag = 'moment:$heroBase:0';
        imageWidget = GestureDetector(
          onTap: () => unawaited(
            _openPhotoViewer(
              [imageUrl],
              heroTags: [heroTag],
            ),
          ),
          child: Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      }

      final nameColor =
          isDark ? theme.colorScheme.primary : const Color(0xFF576B95);
      final avatar = SizedBox(
        width: 40,
        height: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: avatarUrl.isNotEmpty
              ? Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: theme.colorScheme.primary
                      .withValues(alpha: isDark ? .30 : .15),
                  alignment: Alignment.center,
                  child: Text(
                    (authorName.isNotEmpty
                            ? authorName[0]
                            : (isLocal ? (l.isArabic ? 'أ' : 'Y') : '?'))
                        .toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
        ),
      );

      final content = <Widget>[];
      content.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authorName.isNotEmpty
                        ? authorName
                        : (isLocal
                            ? (l.isArabic ? 'أنت' : 'You')
                            : (l.isArabic ? 'مستخدم' : 'User')),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: nameColor,
                    ),
                  ),
                  if (hasOfficialReply)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            size: 14,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .85),
                          ),
                          const SizedBox(width: 4),
                          Builder(
                            builder: (ctx) {
                              final originAccName =
                                  originAcc?.name ?? originAccId;
                              final baseLabel = l.isArabic
                                  ? 'تم الرد من حساب رسمي'
                                  : 'Replied by an official account';
                              final label = originAccName.isNotEmpty
                                  ? (l.isArabic
                                      ? '$baseLabel: $originAccName'
                                      : '$baseLabel: $originAccName')
                                  : baseLabel;
                              return InkWell(
                                onTap: () {
                                  if (originAccId.isEmpty) return;
                                  _openOfficialFromMoment(originAccId, null);
                                },
                                child: Text(
                                  label,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: .85),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  () {
                    String? scopeLabel;
                    String? audienceTag;
                    if (visibility == 'friends' ||
                        visibility == 'friends_only') {
                      scopeLabel = l.isArabic ? 'الأصدقاء فقط' : 'Friends only';
                    } else if (visibility == 'close_friends') {
                      scopeLabel =
                          l.isArabic ? 'الأصدقاء المقرّبون' : 'Close friends';
                    } else if (visibility == 'only_me' ||
                        visibility == 'private') {
                      scopeLabel = l.isArabic ? 'أنا فقط' : 'Only me';
                    } else if (visibility == 'friends_tag') {
                      final tagRaw =
                          (p['audience_tag'] ?? '').toString().trim();
                      if (tagRaw.isNotEmpty) {
                        scopeLabel = l.isArabic
                            ? 'الأصدقاء الموسومون: $tagRaw'
                            : 'Friends with tag: $tagRaw';
                        audienceTag = tagRaw;
                      } else {
                        scopeLabel = l.isArabic
                            ? 'الأصدقاء (موسومون)'
                            : 'Tagged friends';
                      }
                    } else if (visibility == 'friends_except_tag') {
                      final tagRaw =
                          (p['audience_tag'] ?? '').toString().trim();
                      if (tagRaw.isNotEmpty) {
                        scopeLabel = l.isArabic
                            ? 'الأصدقاء باستثناء: $tagRaw'
                            : 'Friends except: $tagRaw';
                        audienceTag = tagRaw;
                      } else {
                        scopeLabel = l.isArabic
                            ? 'الأصدقاء (مع استثناء)'
                            : 'Friends with exclusion';
                      }
                    }
                    if (scopeLabel == null) {
                      return const SizedBox.shrink();
                    }
                    final bg = theme.colorScheme.primary.withValues(
                      alpha: theme.brightness == Brightness.dark ? .20 : .10,
                    );
                    final fg = theme.colorScheme.primary.withValues(alpha: .85);
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          setState(() {
                            if (visibility == 'close_friends') {
                              _filterCloseFriendsOnly = true;
                              _filterAudienceTag = null;
                            } else if (visibility == 'friends_tag' &&
                                audienceTag != null &&
                                audienceTag!.isNotEmpty) {
                              _filterAudienceTag = audienceTag;
                              _filterCloseFriendsOnly = false;
                            } else if (visibility == 'friends' ||
                                visibility == 'friends_only') {
                              _filterCloseFriendsOnly = false;
                              _filterAudienceTag = null;
                            } else if (visibility == 'friends_except_tag') {
                              _filterCloseFriendsOnly = false;
                              _filterAudienceTag = null;
                            }
                          });
                          Perf.action('moments_scope_chip_tap');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            scopeLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: fg,
                            ),
                          ),
                        ),
                      ),
                    );
                  }(),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Builder(
              builder: (ctx) {
                IconData? icon;
                if (visibility == 'only_me' || visibility == 'private') {
                  icon = Icons.lock_outline;
                } else if (visibility == 'close_friends') {
                  icon = Icons.star_outline;
                } else if (visibility == 'friends' ||
                    visibility == 'friends_only' ||
                    visibility == 'friends_tag' ||
                    visibility == 'friends_except_tag') {
                  icon = Icons.group_outlined;
                }
                if (icon == null) return const SizedBox.shrink();
                return Icon(
                  icon,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: .75),
                );
              },
            ),
          ],
        ),
      );

      if (originAcc != null) {
        final featuredSuffix = originAcc.featured
            ? (l.isArabic ? ' · خدمة مميزة' : ' · Featured service')
            : '';
        content.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: InkWell(
              onTap: () {
                if (originAccId.isEmpty) return;
                _openOfficialFromMoment(originAccId, null);
              },
              child: Text(
                l.isArabic
                    ? 'مُشارَكة من ${originAcc.name}$featuredSuffix'
                    : 'Shared from ${originAcc.name}$featuredSuffix',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.primary.withValues(alpha: .85),
                ),
              ),
            ),
          ),
        );
      }

      // Small hint when this Moment was shared from a Shamell mini‑app.
      final miniMeta = _miniAppFromText(text);
      if (miniMeta != null) {
        final miniLabel = miniMeta.title(isArabic: l.isArabic);
        content.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l.isArabic
                  ? 'من تطبيق مصغر: $miniLabel'
                  : 'Shared from mini‑app: $miniLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
          ),
        );
      }

      content.add(const SizedBox(height: 6));

      var displayText = text;
      if (displayText.isNotEmpty) {
        final linkPattern = RegExp(
          r'^\s*shamell://official/.*$',
          multiLine: true,
        );
        final miniAppPattern = RegExp(
          r'^\s*shamell://miniapp/.*$',
          multiLine: true,
        );
        final miniProgramPattern = RegExp(
          r'^\s*shamell://mini_program/.*$',
          multiLine: true,
        );
        displayText = displayText
            .replaceAll(linkPattern, '')
            .replaceAll(miniAppPattern, '')
            .replaceAll(miniProgramPattern, '')
            .trim();
      }

      if (displayText.isNotEmpty) {
        final tags = _extractHashtags(displayText);
        content.add(
          Text(
            displayText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        );
        if (tags.isNotEmpty) {
          content.add(const SizedBox(height: 4));
          content.add(
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tags.map((tag) {
                final label = '#$tag';
                return ActionChip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _openTopic(label);
                  },
                );
              }).toList(),
            ),
          );
        }
        content.add(const SizedBox(height: 6));
      }

      final originItemId =
          (p['origin_official_item_id'] ?? '').toString().trim();
      final officialAttachment = _buildOfficialAttachment(
        text,
        theme,
        l,
        originAccountId: originAccId.isEmpty ? null : originAccId,
        originItemId: originItemId.isEmpty ? null : originItemId,
      );
      if (officialAttachment != null) {
        content.add(officialAttachment);
        content.add(const SizedBox(height: 6));
      }

      final miniAppAttachment = _buildMiniAppAttachment(text, theme, l);
      if (miniAppAttachment != null) {
        content.add(miniAppAttachment);
        content.add(const SizedBox(height: 6));
      }

      if (imageWidget != null) {
        content.add(imageWidget);
        content.add(const SizedBox(height: 8));
      }

      final locationLabel = (p['location_label'] ?? '').toString().trim();
      if (locationLabel.isNotEmpty) {
        final linkColor =
            isDark ? theme.colorScheme.primary : ShamellPalette.linkBlue;
        content.add(
          Text(
            locationLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: linkColor,
            ),
          ),
        );
        content.add(const SizedBox(height: 6));
      }

      content.add(
        Row(
          children: [
            if (ts.isNotEmpty)
              Text(
                ts,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: .55),
                ),
              ),
            if (hasOfficialReply)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            const Spacer(),
            if (postId.isNotEmpty)
              Builder(
                builder: (btnCtx) {
                  final bg = isDark
                      ? theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: .55,
                        )
                      : ShamellPalette.searchFill;
                  return InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _showMomentPostActionsPopover(btnCtx, p),
                    child: Container(
                      width: 34,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );

      final previewComments = postId.isNotEmpty
          ? List<Map<String, dynamic>>.from(
              _comments[postId] ?? const <Map<String, dynamic>>[],
            )
          : const <Map<String, dynamic>>[];
      final showSocial =
          likes > 0 || commentCount > 0 || previewComments.isNotEmpty;
      if (showSocial) {
        final bubbleBg = isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55)
            : ShamellPalette.searchFill;
        final baseStyle = theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: .82),
            ) ??
            TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: .82),
            );
        final authorStyle = baseStyle.copyWith(
          fontWeight: FontWeight.w600,
          color: nameColor,
        );

        Widget inlineComment(Map<String, dynamic> c) {
          final authorRaw = (c['author_name'] ?? '').toString().trim();
          final author =
              authorRaw.isNotEmpty ? authorRaw : (l.isArabic ? 'أنت' : 'You');
          final text = (c['text'] ?? '').toString().trim();
          final replyName = (c['reply_to_name'] ?? '').toString().trim();
          final replyToRaw = (c['reply_to'] ?? '').toString().trim();
          final hasReply = replyName.isNotEmpty && replyToRaw.isNotEmpty;
          final commentId = (c['id'] ?? '').toString().trim();

          final spans = <TextSpan>[
            TextSpan(text: author, style: authorStyle),
            if (hasReply) ...[
              TextSpan(
                text: l.isArabic ? ' ردًا على ' : ' replied to ',
                style: baseStyle,
              ),
              TextSpan(text: replyName, style: authorStyle),
            ],
            TextSpan(text: ': $text'),
          ];

          Offset? downPos;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTapDown: (d) => downPos = d.globalPosition,
            onLongPress: () => unawaited(
              _showMomentCommentActionsMenu(
                post: p,
                comment: c,
                globalPosition: downPos,
              ),
            ),
            onTap: postId.isNotEmpty && commentId.isNotEmpty
                ? () {
                    _startInlineComment(
                      p,
                      replyToId: commentId,
                      replyToName: author,
                    );
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: baseStyle,
                  children: spans,
                ),
              ),
            ),
          );
        }

        final preview = previewComments.take(2).toList();
        final likeIcon =
            likedByMe ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined;
        final likeColor = likedByMe
            ? (isDark ? theme.colorScheme.secondary : ShamellPalette.green)
            : theme.colorScheme.onSurface.withValues(alpha: .65);

        content.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (likes > 0) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              likeIcon,
                              size: 14,
                              color: likeColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Builder(
                                builder: (ctx) {
                                  final you = l.isArabic ? 'أنت' : 'You';
                                  final myPseudo =
                                      (_myMomentsPseudonym ?? '').trim();
                                  final names = <String>[];
                                  final seen = <String>{};
                                  for (final raw in likedByList) {
                                    final v = raw.trim();
                                    if (v.isEmpty) continue;
                                    final mapped =
                                        myPseudo.isNotEmpty && v == myPseudo
                                            ? you
                                            : v;
                                    if (seen.add(mapped)) names.add(mapped);
                                  }
                                  if (likedByMe && !seen.contains(you)) {
                                    names.insert(0, you);
                                  }

                                  if (names.isEmpty) {
                                    return Text(
                                      l.isArabic
                                          ? '$likes إعجاب'
                                          : '$likes likes',
                                      style: baseStyle,
                                    );
                                  }

                                  final sep = l.isArabic ? '، ' : ', ';
                                  final spans = <TextSpan>[];
                                  for (var i = 0; i < names.length; i++) {
                                    if (i > 0) {
                                      spans.add(TextSpan(
                                        text: sep,
                                        style: baseStyle,
                                      ));
                                    }
                                    spans.add(TextSpan(
                                      text: names[i],
                                      style: authorStyle,
                                    ));
                                  }
                                  return RichText(
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      style: baseStyle,
                                      children: spans,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        if (commentCount > 0 || preview.isNotEmpty)
                          Divider(
                            height: 12,
                            thickness: 0.5,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .10),
                          ),
                      ],
                      if (preview.isNotEmpty) ...[
                        for (final c in preview) inlineComment(c),
                        if (commentCount > preview.length)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: postId.isNotEmpty
                                  ? () => unawaited(_openComments(p))
                                  : null,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  l.isArabic
                                      ? 'عرض كل التعليقات ($commentCount)'
                                      : 'View all comments ($commentCount)',
                                  style: baseStyle.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .60),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ] else if (commentCount > 0) ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: postId.isNotEmpty
                              ? () => unawaited(_openComments(p))
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              l.isArabic
                                  ? 'عرض $commentCount تعليق'
                                  : 'View $commentCount comments',
                              style: baseStyle.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .60),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PositionedDirectional(
                  end: 26,
                  top: -4,
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      color: bubbleBg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return GestureDetector(
        onLongPress: () => _openPostActions(p),
        child: Container(
          key: postId.isNotEmpty ? _postKeyFor(postId) : null,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surface : Colors.white,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                ),
              ),
            ],
          ),
        ),
      );
    }

    List<Map<String, dynamic>> _filteredPostsForFeed() {
      Iterable<Map<String, dynamic>> base = _posts;
      final authorId = (widget.timelineAuthorId ?? '').trim();
      if (authorId.isNotEmpty) {
        base = base.where((p) {
          final pid = (p['author_id'] ?? '').toString().trim();
          return pid == authorId;
        });
      }

      if (_filterOfficialOnly) {
        if (_preferredCity != null && _preferredCity!.isNotEmpty) {
          base = base.where(_isOfficialInPreferredCity);
        } else {
          base = base.where(_isOfficialShare);
        }
      } else if (_filterOfficialRepliesOnly) {
        base = base.where((p) {
          return (p['has_official_reply'] as bool?) ?? false;
        });
      } else if (_filterHotOfficialsOnly) {
        base = base.where((p) {
          final originId =
              (p['origin_official_account_id'] ?? '').toString().trim();
          if (originId.isEmpty) return false;
          final acc = _officialAccounts[originId];
          if (acc == null) return false;
          final totalShares = acc.totalShares ?? 0; // may be null
          // Simple heuristic: treat accounts with >= 10 total shares as "hot".
          return totalShares >= 10;
        });
      }

      if (_filterCloseFriendsOnly) {
        base = base.where((p) {
          final v = (p['visibility'] ?? '').toString().toLowerCase();
          return v == 'close_friends';
        });
      }
      if (_filterMiniProgramOnly) {
        base = base.where((p) {
          final t = ((p['text'] ?? p['content'] ?? '')).toString();
          return t.contains('shamell://miniapp/') ||
              t.contains('shamell://mini_program/') ||
              t.contains('#ShamellMiniApp') ||
              t.contains('#ShamellMiniProgram') ||
              t.contains('#mp_');
        });
      }
      if (_filterChannelClipsOnly) {
        base = base.where(_isChannelClipMoment);
      }
      if (_filterOfficialLinkedOnly) {
        base = base.where((p) {
          final t = ((p['text'] ?? p['content'] ?? '')).toString();
          if (t.contains('shamell://official/')) {
            return true;
          }
          final originId =
              (p['origin_official_account_id'] ?? '').toString().trim();
          return originId.isNotEmpty;
        });
      }
      if ((_topicCategory ?? '').isNotEmpty) {
        final topic = _topicCategory!.toLowerCase();
        base = base.where((p) {
          final originId =
              (p['origin_official_account_id'] ?? '').toString().trim();
          if (originId.isEmpty) return false;
          final acc = _officialAccounts[originId];
          final cat = (acc?.category ?? '').toLowerCase();
          return cat == topic;
        });
      }
      if (_filterLast3Days) {
        base = base.where(_isRecentPost);
      }
      if ((_filterAudienceTag ?? '').trim().isNotEmpty) {
        final tagFilter = (_filterAudienceTag ?? '').trim().toLowerCase();
        base = base.where((p) {
          final v = (p['visibility'] ?? '').toString().toLowerCase();
          if (v != 'friends_tag') return false;
          final tag = (p['audience_tag'] ?? '').toString().trim();
          if (tag.isEmpty) return false;
          return tag.toLowerCase() == tagFilter;
        });
      }
      if (_hideOfficialPosts) {
        base = base.where((p) => !_isOfficialShare(p));
      }
      if (_mutedAuthors.isNotEmpty) {
        base = base.where((p) {
          final name = (p['author_name'] ?? '').toString().trim();
          if (name.isEmpty) return true;
          return !_mutedAuthors.contains(name);
        });
      }
      if (_hiddenPostIds.isNotEmpty) {
        base = base.where((p) {
          final id = (p['id'] ?? '').toString();
          if (id.isEmpty) return true;
          return !_hiddenPostIds.contains(id);
        });
      }

      return base.toList();
    }

    Widget _buildFeedList() {
      final filtered = _filteredPostsForFeed();
      if (filtered.isEmpty) {
        final isFriendTimeline =
            (widget.timelineAuthorId ?? '').trim().isNotEmpty;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            isFriendTimeline
                ? (l.isArabic ? 'لا توجد لحظات بعد.' : 'No moments yet.')
                : (l.isArabic
                    ? 'لا توجد لحظات بعد. شارك أول لحظة لك!'
                    : 'No moments yet. Share your first moment!'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
        );
      }

      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 0.5,
          indent: 64,
          color: isDark ? theme.dividerColor : ShamellPalette.divider,
        ),
        itemBuilder: (_, i) {
          final p = filtered[i];
          return buildPost(p);
        },
      );
    }

    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final isFriendTimeline = (widget.timelineAuthorId ?? '').trim().isNotEmpty;
    final showInlineComposer = _enableInlineComposer;
    final showAdvancedFilters = _enableAdvancedFilters;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            controller: _scrollCtrl,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildShamellCoverHeader(l, theme),
                Container(
                  color: isDark ? theme.colorScheme.surface : Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showInlineComposer &&
                          widget.showComposer &&
                          !isFriendTimeline)
                        Container(
                          key: _composerKey,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.isArabic
                                    ? 'مشاركة لحظة جديدة'
                                    : 'Share a new moment',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _postCtrl,
                                focusNode: _postFocus,
                                maxLines: 3,
                                minLines: 1,
                                decoration: InputDecoration(
                                  hintText: l.isArabic
                                      ? 'ما الذي يدور في بالك؟'
                                      : 'What\'s on your mind?',
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildAudienceSummaryPill(l, theme),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ChoiceChip(
                                    label: Text(
                                      l.isArabic ? 'عام' : 'Public',
                                    ),
                                    selected: _visibilityScope == 'public',
                                    onSelected: (sel) {
                                      if (!sel) return;
                                      setState(() {
                                        _visibilityScope = 'public';
                                        _visibilityTag = null;
                                        _visibilityTagMode = 'only';
                                        _visibilityTagCtrl.clear();
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: Text(
                                      l.isArabic
                                          ? 'الأصدقاء فقط'
                                          : 'Friends only',
                                    ),
                                    selected: _visibilityScope == 'friends',
                                    onSelected: (sel) {
                                      if (!sel) return;
                                      setState(() {
                                        _visibilityScope = 'friends';
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: Text(
                                      l.isArabic
                                          ? 'الأصدقاء المقرّبون'
                                          : 'Close friends',
                                    ),
                                    selected:
                                        _visibilityScope == 'close_friends',
                                    onSelected: (sel) {
                                      if (!sel) return;
                                      setState(() {
                                        _visibilityScope = 'close_friends';
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: Text(
                                      l.isArabic ? 'أنا فقط' : 'Only me',
                                    ),
                                    selected: _visibilityScope == 'only_me',
                                    onSelected: (sel) {
                                      if (!sel) return;
                                      setState(() {
                                        _visibilityScope = 'only_me';
                                        _visibilityTag = null;
                                        _visibilityTagMode = 'only';
                                        _visibilityTagCtrl.clear();
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l.isArabic
                                    ? 'حدد من يمكنه رؤية هذه اللحظة (كما في Shamell).'
                                    : 'Choose who can see this moment (similar to Shamell).',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .65),
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (_availableAudienceTags.isNotEmpty) ...[
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children:
                                      _availableAudienceTags.expand((tag) {
                                    final bool isOnlySelected =
                                        _visibilityTag == tag &&
                                            _visibilityTagMode == 'only';
                                    final bool isExceptSelected =
                                        _visibilityTag == tag &&
                                            _visibilityTagMode == 'except';
                                    final widgets = <Widget>[
                                      FilterChip(
                                        label: Text(
                                          l.isArabic ? 'فقط $tag' : 'Only $tag',
                                        ),
                                        selected: isOnlySelected,
                                        onSelected: (sel) {
                                          setState(() {
                                            if (sel) {
                                              _visibilityTag = tag;
                                              _visibilityTagMode = 'only';
                                              _visibilityScope = 'friends';
                                              _visibilityTagCtrl.text = tag;
                                            } else if (_visibilityTag == tag &&
                                                _visibilityTagMode == 'only') {
                                              _visibilityTag = null;
                                              _visibilityTagCtrl.clear();
                                            }
                                          });
                                        },
                                      ),
                                      FilterChip(
                                        label: Text(
                                          l.isArabic
                                              ? 'الأصدقاء باستثناء $tag'
                                              : 'Friends except $tag',
                                        ),
                                        selected: isExceptSelected,
                                        onSelected: (sel) {
                                          setState(() {
                                            if (sel) {
                                              _visibilityTag = tag;
                                              _visibilityTagMode = 'except';
                                              _visibilityScope = 'friends';
                                              _visibilityTagCtrl.text = tag;
                                            } else if (_visibilityTag == tag &&
                                                _visibilityTagMode ==
                                                    'except') {
                                              _visibilityTag = null;
                                              _visibilityTagCtrl.clear();
                                            }
                                          });
                                        },
                                      ),
                                    ];
                                    return widgets;
                                  }).toList(),
                                ),
                                const SizedBox(height: 6),
                              ],
                              TextField(
                                controller: _visibilityTagCtrl,
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon:
                                      const Icon(Icons.label_outline, size: 18),
                                  labelText: l.isArabic
                                      ? 'وسم الجمهور (اختياري، مثل Family)'
                                      : 'Audience label (optional, e.g. Family)',
                                  hintText: l.isArabic
                                      ? 'يجب أن يطابق الوسوم في قائمة الأصدقاء'
                                      : 'Must match your friend labels',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onChanged: (v) {
                                  setState(() {
                                    _visibilityTag =
                                        v.trim().isEmpty ? null : v.trim();
                                    if (_visibilityTag != null &&
                                        _visibilityTag!.isNotEmpty) {
                                      _visibilityTagMode = 'only';
                                      _visibilityScope = 'friends';
                                    }
                                  });
                                },
                              ),
                              if (_showAudienceOnboardingHint &&
                                  _availableAudienceTags.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface
                                        .withValues(alpha: .06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 16,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: .80),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          l.shamellMomentsAudienceHint,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontSize: 11,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: .70),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        icon: Icon(
                                          Icons.close,
                                          size: 16,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: .60),
                                        ),
                                        onPressed: _dismissAudienceHint,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (_availableAudienceTags.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  l.isArabic
                                      ? 'وسوم مقترحة للجمهور'
                                      : 'Suggested audience labels',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .65),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _availableAudienceTags
                                        .take(8)
                                        .map((tag) => Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 6.0),
                                              child: ActionChip(
                                                label: Text(tag),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () {
                                                  setState(() {
                                                    _visibilityTag = tag;
                                                    _visibilityTagCtrl.text =
                                                        tag;
                                                  });
                                                },
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ],
                              if (_trendingTopics.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  l.isArabic
                                      ? 'المواضيع الشائعة'
                                      : 'Trending topics',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: ActionChip(
                                          label: Text(
                                            l.isArabic
                                                ? 'من مشاركات البرامج المصغّرة'
                                                : 'Mini‑program shares',
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            _openTopic('#ShamellMiniApp');
                                          },
                                        ),
                                      ),
                                      ..._trendingTopics
                                          .map((it) => (it['tag'] ?? '')
                                              .toString()
                                              .trim())
                                          .where((rawTag) => rawTag.isNotEmpty)
                                          .map<Widget>((rawTag) {
                                        final lower = rawTag.toLowerCase();
                                        final isMiniProgramTopic =
                                            lower.startsWith('mp_');
                                        final topicTag = '#$rawTag';
                                        String label;
                                        if (isMiniProgramTopic) {
                                          final core = rawTag.substring(3);
                                          label = l.isArabic
                                              ? 'برنامج مصغّر: $core'
                                              : 'Mini‑program: $core';
                                        } else {
                                          label = topicTag;
                                        }
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(right: 6),
                                          child: ActionChip(
                                            avatar: isMiniProgramTopic
                                                ? Icon(
                                                    Icons.widgets_outlined,
                                                    size: 16,
                                                    color: theme
                                                        .colorScheme.primary
                                                        .withValues(alpha: .90),
                                                  )
                                                : null,
                                            label: Text(label),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () {
                                              _openTopic(topicTag);
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                              ],
                              if (_preferredCity != null &&
                                  _preferredCity!.isNotEmpty &&
                                  widget.onOpenOfficialDirectory != null) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () =>
                                      widget.onOpenOfficialDirectory!(context),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.verified_outlined,
                                        size: 16,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        l.isArabic
                                            ? 'من خدمات في ${_preferredCity!}'
                                            : 'From services in ${_preferredCity!}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontSize: 11,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.chevron_right,
                                        size: 14,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: .80),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if (_pendingImage != null)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        _pendingImage!,
                                        height: 180,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        icon: const Icon(Icons.close),
                                        tooltip: l.isArabic
                                            ? 'إزالة الصورة'
                                            : 'Remove photo',
                                        onPressed: _clearPendingImage,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                ),
                              Row(
                                children: [
                                  IconButton(
                                    icon:
                                        const Icon(Icons.photo_camera_outlined),
                                    tooltip:
                                        l.isArabic ? 'إضافة صورة' : 'Add photo',
                                    onPressed: _pickImage,
                                  ),
                                  const Spacer(),
                                  PrimaryButton(
                                    label: l.isArabic ? 'نشر' : 'Post',
                                    onPressed: _addPost,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (!isFriendTimeline && _myOfficialStats != null)
                        Builder(
                          builder: (ctx) {
                            final theme = Theme.of(ctx);
                            final isAr = l.isArabic;
                            final totalRaw = _myOfficialStats?['total_shares'];
                            final svcRaw = _myOfficialStats?['service_shares'];
                            final subRaw =
                                _myOfficialStats?['subscription_shares'];
                            final hotRaw = _myOfficialStats?['hot_accounts'];
                            final total =
                                totalRaw is num ? totalRaw.toInt() : 0;
                            final svc = svcRaw is num ? svcRaw.toInt() : 0;
                            final sub = subRaw is num ? subRaw.toInt() : 0;
                            final hot = hotRaw is num ? hotRaw.toInt() : 0;
                            if (total <= 0 && hot <= 0) {
                              return const SizedBox.shrink();
                            }

                            Widget pill(IconData icon, String label) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: .06),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 14,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: .85),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .8),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final pills = <Widget>[
                              pill(
                                Icons.share_outlined,
                                isAr
                                    ? 'مشاركات الحسابات الرسمية: $total'
                                    : 'Official shares: $total',
                              ),
                            ];
                            if (svc > 0 || sub > 0) {
                              pills.add(
                                pill(
                                  Icons.verified_outlined,
                                  isAr
                                      ? 'خدمات: $svc · اشتراكات: $sub'
                                      : 'Services: $svc · Subscriptions: $sub',
                                ),
                              );
                            }
                            if (hot > 0) {
                              pills.add(
                                pill(
                                  Icons.local_fire_department_outlined,
                                  isAr
                                      ? 'حسابات رائجة: $hot'
                                      : 'Hot official accounts: $hot',
                                ),
                              );
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface
                                    .withValues(alpha: .95),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.shadow
                                        .withValues(alpha: .03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.insights_outlined,
                                        size: 18,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: .9),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isAr
                                            ? 'أثرك مع الحسابات الرسمية'
                                            : 'Your impact with official accounts',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: pills,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      if (showAdvancedFilters && !isFriendTimeline)
                        _buildOfficialFiltersRow(l),
                      if (showAdvancedFilters && !isFriendTimeline)
                        const SizedBox(height: 8),
                      // Topic bar – Shamell-like Moments topics (Wallet)
                      if (showAdvancedFilters && !isFriendTimeline)
                        _buildTopicBar(l),
                      _buildFeedList(),
                    ],
                  ),
                ),
              ],
            ),
          );

    String titleText() {
      if (!isFriendTimeline) {
        return l.isArabic ? 'اللحظات' : 'Moments';
      }
      final explicit = (widget.timelineAuthorName ?? '').trim();
      if (explicit.isNotEmpty) return explicit;
      final id = (widget.timelineAuthorId ?? '').trim();
      return id.isNotEmpty ? id : (l.isArabic ? 'اللحظات' : 'Moments');
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(titleText()),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          if (widget.showComposer && !isFriendTimeline)
            GestureDetector(
              onLongPress: () {
                unawaited(_openShamellComposer());
              },
              child: IconButton(
                tooltip: l.isArabic ? 'إضافة لحظة' : 'New moment',
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: () async {
                  final sheetBg =
                      isDark ? theme.colorScheme.surface : Colors.white;
                  await showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: sheetBg,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    builder: (ctx) {
                      final l2 = L10n.of(ctx);
                      return SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.photo_camera_outlined),
                              title: Text(
                                l2.isArabic ? 'التقاط صورة' : 'Take Photo',
                              ),
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                final picked = await _pickImageBytes(
                                  source: ImageSource.camera,
                                );
                                if (picked == null) return;
                                if (!mounted) return;
                                await _openShamellComposer(
                                  initialImageBytes: picked.bytes,
                                  initialImageMime: picked.mime,
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: Text(
                                l2.isArabic
                                    ? 'اختيار من الألبوم'
                                    : 'Choose from Album',
                              ),
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                final picked = await _pickImageBytes(
                                  source: ImageSource.gallery,
                                );
                                if (picked == null) return;
                                if (!mounted) return;
                                await _openShamellComposer(
                                  initialImageBytes: picked.bytes,
                                  initialImageMime: picked.mime,
                                );
                              },
                            ),
                            ListTile(
                              title: Center(
                                child: Text(
                                  l2.isArabic ? 'إلغاء' : 'Cancel',
                                  style: TextStyle(
                                    color: Theme.of(ctx).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              onTap: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          body,
          if ((_inlineCommentPostId ?? '').trim().isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildInlineCommentBar(l, theme),
            ),
        ],
      ),
    );
  }

  Widget _buildOfficialFiltersRow(L10n l) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: Text(
              l.isArabic ? 'الكل' : 'All',
            ),
            selected: !_filterOfficialOnly &&
                !_filterOfficialRepliesOnly &&
                !_filterHotOfficialsOnly,
            onSelected: (sel) {
              if (!sel) return;
              setState(() {
                _filterOfficialOnly = false;
                _filterOfficialRepliesOnly = false;
                _filterHotOfficialsOnly = false;
              });
              Perf.action('moments_filter_official_only_off');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(
              l.isArabic ? 'المشاركات الرسمية فقط' : 'Only official shares',
            ),
            selected: _filterOfficialOnly,
            onSelected: (sel) {
              if (!sel) return;
              setState(() {
                _filterOfficialOnly = true;
                _filterOfficialRepliesOnly = false;
                _filterHotOfficialsOnly = false;
              });
              Perf.action('moments_filter_official_only_on');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(
              l.isArabic ? 'منشورات بها رد رسمي' : 'Only with official reply',
            ),
            selected: _filterOfficialRepliesOnly,
            onSelected: (sel) {
              if (!sel) return;
              setState(() {
                _filterOfficialRepliesOnly = true;
                _filterOfficialOnly = false;
                _filterHotOfficialsOnly = false;
                _topicCategory = null;
              });
              Perf.action('moments_filter_official_replies_on');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(
              l.isArabic ? 'الحسابات الرائجة فقط' : 'Only hot official shares',
            ),
            selected: _filterHotOfficialsOnly,
            onSelected: (sel) {
              if (!sel) return;
              setState(() {
                _filterHotOfficialsOnly = true;
                _filterOfficialOnly = false;
                _filterOfficialRepliesOnly = false;
              });
              Perf.action('moments_filter_hot_official_on');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopicBar(L10n l) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(
              l.isArabic ? 'الكل' : 'All',
            ),
            selected: (_topicCategory == null) &&
                !_filterOfficialOnly &&
                !_filterOfficialRepliesOnly,
            onSelected: (sel) {
              if (!sel) return;
              setState(() {
                _topicCategory = null;
                _filterOfficialOnly = false;
                _filterOfficialRepliesOnly = false;
              });
              Perf.action('moments_topic_all');
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(
              l.isArabic ? 'المحفظة' : 'Wallet',
            ),
            selected: _topicCategory == 'wallet',
            onSelected: (sel) {
              setState(() {
                _topicCategory = sel ? 'wallet' : null;
                _filterOfficialOnly = true;
                _filterOfficialRepliesOnly = false;
              });
              Perf.action(
                sel ? 'moments_topic_wallet_on' : 'moments_topic_wallet_off',
              );
            },
          ),
        ],
      ),
    );
  }

  List<String> _extractHashtags(String text) {
    final re = RegExp(r'#([\w]+)', unicode: true);
    final tags = <String>{};
    for (final m in re.allMatches(text)) {
      final raw = (m.group(1) ?? '').trim();
      if (raw.isEmpty) continue;
      tags.add(raw);
    }
    final list = tags.toList()..sort();
    return list;
  }

  bool _isChannelClipMoment(Map<String, dynamic> p) {
    final text = ((p['text'] ?? p['content'] ?? '')).toString();
    if (text.contains('#ch_')) return true;
    final originItem = (p['origin_official_item_id'] ?? '').toString().trim();
    if (originItem.isNotEmpty) return true;
    if (text.contains('shamell://official/')) {
      final pattern = RegExp(
        r'shamell://official/([^/\s]+)(?:/([^\s]+))?',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(text);
      if (match != null) {
        final itemIdRaw = (match.group(2) ?? '').trim();
        if (itemIdRaw.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  void _openTopic(String tag) {
    final t = tag.trim();
    if (t.isEmpty) return;
    final core = t.startsWith('#') ? t.substring(1) : t;
    if (core.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MomentsPage(
          baseUrl: widget.baseUrl,
          topicTag: '#$core',
        ),
      ),
    );
  }

  Widget? _buildOfficialAttachment(
    String text,
    ThemeData theme,
    L10n l, {
    String? originAccountId,
    String? originItemId,
  }) {
    String accountId = (originAccountId ?? '').trim();
    String? itemId = (originItemId ?? '').trim();
    if (itemId.isEmpty) itemId = null;
    if (accountId.isEmpty) {
      final pattern = RegExp(
        r'shamell://official/([^/\s]+)(?:/([^\s]+))?',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(text);
      if (match == null) return null;
      accountId = (match.group(1) ?? '').trim();
      if (accountId.isEmpty) return null;
      final itemIdRaw = (match.group(2) ?? '').trim();
      itemId = itemIdRaw.isEmpty ? null : itemIdRaw;
    }

    final acc = _officialAccounts[accountId];
    final accountName = (acc?.name ?? '').isNotEmpty ? acc!.name : accountId;
    final kind = (acc?.kind ?? 'service').toLowerCase();
    final isService = kind == 'service';
    final kindLabel = isService
        ? (l.isArabic ? 'حساب خدمة' : 'Service account')
        : (l.isArabic ? 'حساب اشتراك' : 'Subscription account');

    String? itemTitle;
    if (itemId != null) {
      final lines = text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        final first = lines.first;
        final lower = first.toLowerCase();
        if (!lower.startsWith('from ') && !lower.startsWith('من ')) {
          itemTitle = first;
        }
      }
    }

    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        theme.colorScheme.primary.withValues(alpha: isDark ? .20 : .06);

    return InkWell(
      onTap: () => _openOfficialFromMoment(accountId, itemId),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if ((acc?.avatarUrl ?? '').isNotEmpty)
              CircleAvatar(
                radius: 16,
                backgroundImage: NetworkImage(acc!.avatarUrl!),
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary
                      .withValues(alpha: isDark ? .30 : .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemTitle ??
                        (itemId != null
                            ? (l.isArabic ? 'منشور رسمي' : 'Official update')
                            : (l.isArabic ? 'حساب رسمي' : 'Official account')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$accountName · $kindLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((acc?.miniAppId ?? '').trim().isNotEmpty)
                  TextButton(
                    onPressed: () {
                      final mid = acc!.miniAppId!.trim();
                      try {
                        final uri = Uri.parse('shamell://miniapp/$mid');
                        launchUrl(uri);
                      } catch (_) {}
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      () {
                        final mid = acc?.miniAppId ?? '';
                        if (mid == 'bus') {
                          return l.isArabic ? 'فتح الباص' : 'Open bus';
                        }
                        if (mid == 'payments') {
                          return l.isArabic ? 'فتح المحفظة' : 'Open wallet';
                        }
                        return l.isArabic ? 'فتح الخدمة' : 'Open service';
                      }(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                if ((acc?.miniAppId ?? '').trim().isNotEmpty)
                  const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    _openOfficialFromMoment(accountId, itemId);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    l.isArabic ? 'القناة' : 'Channels',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                if (acc != null && !acc.followed)
                  TextButton(
                    onPressed: () =>
                        _toggleOfficialFollowFromMoment(accountId, isService),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      l.isArabic ? 'متابعة' : 'Follow',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                if ((acc?.chatPeerId ?? '').trim().isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        _openOfficialChatFromMoment(acc!.chatPeerId!.trim()),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      l.isArabic ? 'دردشة' : 'Chat',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  MiniAppDescriptor? _miniAppFromText(String text) {
    final pattern = RegExp(
      r'shamell://miniapp/([^\s/]+)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    final rawId = (match.group(1) ?? '').trim();
    if (rawId.isEmpty) return null;
    final id = rawId.toLowerCase();
    return miniAppById(id);
  }

  Widget? _buildMiniAppAttachment(
    String text,
    ThemeData theme,
    L10n l,
  ) {
    final meta = _miniAppFromText(text);
    if (meta == null) return null;
    final id = meta.id;
    final title = meta.title(isArabic: l.isArabic);
    final cat = meta.category(isArabic: l.isArabic);
    final icon = meta.icon;

    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        theme.colorScheme.surface.withValues(alpha: isDark ? .35 : .10);

    return InkWell(
      onTap: () {
        // Reuse global module routing via deep-link.
        try {
          final uri = Uri.parse('shamell://miniapp/$id');
          launchUrl(uri);
        } catch (_) {}
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary
                    .withValues(alpha: isDark ? .30 : .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (cat.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () {
                try {
                  final uri = Uri.parse('shamell://miniapp/$id');
                  launchUrl(uri);
                } catch (_) {}
              },
              child: Text(
                l.isArabic ? 'فتح التطبيق المصغر' : 'Open mini‑app',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOfficialFromMoment(
    String accountId,
    String? itemId,
  ) async {
    if (accountId.isEmpty) return;
    try {
      final uriStr = (itemId != null && itemId.isNotEmpty)
          ? 'shamell://official/$accountId/$itemId'
          : 'shamell://official/$accountId';
      final uri = Uri.parse(uriStr);
      Perf.action('moments_open_official');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openOfficialChatFromMoment(String peerId) async {
    if (peerId.isEmpty) return;
    try {
      Perf.action('official_open_chat_from_moments');
      // ignore: use_build_context_synchronously
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ShamellChatPage(baseUrl: widget.baseUrl, initialPeerId: peerId),
        ),
      );
    } catch (_) {}
  }

  Future<void> _toggleOfficialFollowFromMoment(
    String accountId,
    bool isService,
  ) async {
    final current = _officialAccounts[accountId];
    if (current == null) return;
    final currentlyFollowed = current.followed;
    if (currentlyFollowed) {
      // Keep Moments CTA as follow-only; unfollow remains available in profile.
      return;
    }
    final endpoint = currentlyFollowed ? 'unfollow' : 'follow';
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/official_accounts/$accountId/$endpoint');
      final r = await http.post(uri, headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true));
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      setState(() {
        _officialAccounts[accountId] = _MomentOfficialAccount(
          id: current.id,
          name: current.name,
          avatarUrl: current.avatarUrl,
          kind: current.kind,
          followed: !currentlyFollowed,
          chatPeerId: current.chatPeerId,
          city: current.city,
          category: current.category,
          featured: current.featured,
          totalShares: current.totalShares,
          miniAppId: current.miniAppId,
        );
      });
      final suffix = isService ? 'service' : 'subscription';
      Perf.action('official_follow_from_moments');
      Perf.action('official_follow_kind_$suffix');
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _addOfficialAdminComment(
    String postIdStr,
    String officialAccountId,
    String text, {
    String? replyToCommentId,
  }) async {
    final postId = int.tryParse(postIdStr);
    if (postId == null) return null;
    final payload = <String, dynamic>{
      'text': text,
      'official_account_id': officialAccountId,
    };
    final replyId = int.tryParse((replyToCommentId ?? '').trim());
    if (replyId != null) {
      payload['reply_to_id'] = replyId;
    }
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/moments/admin/posts/$postId/comment');
      final r = await http.post(
        uri,
        headers: await _hdrMoments(baseUrl: widget.baseUrl, json: true),
        body: jsonEncode(payload),
      );
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }
}

class _ShamellMomentActionMenu extends StatelessWidget {
  final String likeLabel;
  final String commentLabel;
  final bool likeEnabled;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const _ShamellMomentActionMenu({
    required this.likeLabel,
    required this.commentLabel,
    required this.likeEnabled,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled
                    ? Colors.white.withValues(alpha: .95)
                    : Colors.white.withValues(alpha: .45),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? Colors.white.withValues(alpha: .95)
                      : Colors.white.withValues(alpha: .45),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 184,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF4C4C4C),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: action(
                icon: Icons.thumb_up_alt_outlined,
                label: likeLabel,
                onTap: likeEnabled ? onLike : null,
              ),
            ),
            Container(
              width: 1,
              height: 22,
              color: Colors.white.withValues(alpha: .14),
            ),
            Expanded(
              child: action(
                icon: Icons.chat_bubble_outline,
                label: commentLabel,
                onTap: onComment,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShamellPopoverArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_ShamellPopoverArrowClipper oldClipper) => false;
}

class _ShamellPopoverDownArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_ShamellPopoverDownArrowClipper oldClipper) => false;
}

class _ShamellPopoverUpArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_ShamellPopoverUpArrowClipper oldClipper) => false;
}

class _MomentOfficialAccount {
  final String id;
  final String name;
  final String? avatarUrl;
  final String kind;
  final bool followed;
  final String? chatPeerId;
  final String? city;
  final String? category;
  final bool featured;
  final int? totalShares;
  final String? miniAppId;

  const _MomentOfficialAccount({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.kind = 'service',
    this.followed = false,
    this.chatPeerId,
    this.city,
    this.category,
    this.featured = false,
    this.totalShares,
    this.miniAppId,
  });

  factory _MomentOfficialAccount.fromJson(Map<String, dynamic> j) {
    return _MomentOfficialAccount(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      avatarUrl: (j['avatar_url'] ?? '').toString().isEmpty
          ? null
          : (j['avatar_url'] ?? '').toString(),
      kind: (j['kind'] ?? 'service').toString(),
      followed: (j['followed'] as bool?) ?? false,
      chatPeerId: (j['chat_peer_id'] ?? '').toString().isEmpty
          ? null
          : (j['chat_peer_id'] ?? '').toString(),
      city: (j['city'] ?? '').toString().isEmpty
          ? null
          : (j['city'] ?? '').toString(),
      category: (j['category'] ?? '').toString().isEmpty
          ? null
          : (j['category'] ?? '').toString(),
      featured: (j['featured'] as bool?) ?? false,
      totalShares: (j['moments_total_shares'] as num?)?.toInt(),
      miniAppId: (j['mini_app_id'] ?? '').toString().isEmpty
          ? null
          : (j['mini_app_id'] ?? '').toString(),
    );
  }
}
