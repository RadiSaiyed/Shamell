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

import 'call_signaling.dart';
import 'glass.dart';
import 'deep_link_parsing.dart';
import 'l10n.dart';
import 'mini_app_registry.dart';
import 'network_image_helpers.dart';
import 'perf.dart';
import 'mini_apps_config.dart';
import 'moments_action_meta.dart';
import 'moments_comment_meta.dart';
import 'moments_composer_meta.dart';
import 'moments_discovery_meta.dart';
import 'moments_feed_meta.dart';
import 'moments_media_meta.dart';
import 'moments_mini_program_attachment_meta.dart';
import 'moments_official_attachment_meta.dart';
import 'moments_page_meta.dart';
import 'moments_preset_store.dart';
import 'moments_social_meta.dart';
import 'mini_program_runtime.dart';
import 'official_accounts_page.dart';
import 'payments/payments_shell.dart';
import 'session_cookie_store.dart';
import 'shamell_loading_shimmer.dart';
import 'ui_kit.dart';
import 'chat/shamell_chat_page.dart';
import 'favorites_page.dart' show addFavoriteItemQuick;
import 'wechat_ui.dart';
import 'wechat_moments_composer_page.dart';
import 'wechat_photo_viewer_page.dart';

Future<Map<String, String>> _hdrMoments(
  String baseUrl, {
  bool json = false,
}) async {
  return shamellSessionHeadersForBaseUrl(baseUrl, json: json);
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
  final String? miniProgramId;
  final bool showOnlyMine;
  final bool initialRedpacketOnly;
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
    this.miniProgramId,
    this.showOnlyMine = false,
    this.initialRedpacketOnly = false,
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
  String? _presetMiniProgramId;
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
  bool _filterRedpacketOnly = false;
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
        builder: (_) => WeChatPhotoViewerPage(
          baseUrl: widget.baseUrl,
          sources: cleaned,
          initialIndex: idx,
          heroTags: heroTags == null ? null : cleanedTags,
        ),
      ),
    );
  }

  Widget _buildWeChatCoverHeader(L10n l, ThemeData theme) {
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
    final coverMeta = momentCoverHeaderMeta(isDark: isDark);

    return SizedBox(
      height: coverMeta.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: coverMeta.gradientColors,
              ),
            ),
          ),
          Opacity(
            opacity: coverMeta.assetOpacity,
            child: Image.asset(
              coverMeta.assetPath,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            right: isArabic ? null : coverMeta.horizontalInset,
            left: isArabic ? coverMeta.horizontalInset : null,
            bottom: coverMeta.bottomInset,
            child: InkWell(
              borderRadius: BorderRadius.circular(coverMeta.tapRadius),
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
                    style: TextStyle(
                      color: coverMeta.nameColor,
                      fontSize: coverMeta.nameFontSize,
                      fontWeight: coverMeta.nameFontWeight,
                      shadows: [
                        Shadow(
                          blurRadius: coverMeta.nameShadowBlurRadius,
                          color: coverMeta.nameShadowColor,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: coverMeta.nameAvatarGap),
                  Container(
                    width: coverMeta.avatarSize,
                    height: coverMeta.avatarSize,
                    decoration: BoxDecoration(
                      color: coverMeta.avatarFillColor.withValues(
                        alpha: coverMeta.avatarFillAlpha,
                      ),
                      borderRadius: BorderRadius.circular(
                        coverMeta.avatarRadius,
                      ),
                      border: Border.all(
                        color: coverMeta.avatarBorderColor.withValues(
                          alpha: coverMeta.avatarBorderAlpha,
                        ),
                        width: coverMeta.avatarBorderWidth,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: coverMeta.avatarShadowColor,
                          blurRadius: coverMeta.avatarShadowBlurRadius,
                          offset: coverMeta.avatarShadowOffset,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: coverMeta.initialFontSize,
                          fontWeight: coverMeta.initialFontWeight,
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

  String _activeMiniProgramId() {
    return (widget.miniProgramId ?? '').trim().toLowerCase();
  }

  String _inlineComposerMiniProgramId() {
    return momentInlineComposerMiniProgramId(
      activeMiniProgramId: _activeMiniProgramId(),
      presetMiniProgramId: _presetMiniProgramId ?? '',
    );
  }

  String _miniProgramContextMomentsTitle(L10n l) {
    final id = _activeMiniProgramId();
    final meta = momentMiniProgramContextMeta(
      id: id,
      descriptor: _miniAppDescriptorById(id),
      isArabic: l.isArabic,
    );
    return meta?.momentsTitle ?? '';
  }

  Widget _buildMiniProgramContextBar(
    L10n l, {
    String? miniProgramId,
  }) {
    final id = (miniProgramId ?? _activeMiniProgramId()).trim().toLowerCase();
    final descriptor = _miniAppDescriptorById(id);
    final meta = momentMiniProgramContextMeta(
      id: id,
      descriptor: descriptor,
      isArabic: l.isArabic,
    );
    if (meta == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = momentMiniProgramAccentColor(id);
    final chrome = momentMiniProgramContextChromeMeta();
    final borderColor = theme.dividerColor.withValues(
      alpha: isDark ? chrome.darkBorderAlpha : chrome.lightBorderAlpha,
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: chrome.horizontalPadding,
        vertical: chrome.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: borderColor, width: chrome.borderWidth),
          bottom: BorderSide(color: borderColor, width: chrome.borderWidth),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: meta.iconBoxSize,
            height: meta.iconBoxSize,
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: isDark
                    ? chrome.iconFillDarkAlpha
                    : chrome.iconFillLightAlpha,
              ),
              borderRadius: BorderRadius.circular(meta.iconRadius),
            ),
            child: Icon(
              meta.icon,
              size: meta.iconSize,
              color: accent,
            ),
          ),
          SizedBox(width: chrome.iconTitleGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  meta.momentsTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: meta.titleFontSize,
                    fontWeight: chrome.titleFontWeight,
                  ),
                ),
                SizedBox(height: chrome.categoryTopGap),
                Text(
                  meta.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: meta.categoryFontSize,
                    color: theme.colorScheme.onSurface.withValues(
                      alpha: chrome.categoryAlpha,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: chrome.actionGap),
          TextButton(
            onPressed: () {
              Perf.action(meta.allPerfKey);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
                ),
              );
            },
            style: TextButton.styleFrom(
              minimumSize: Size(chrome.actionMinWidth, chrome.actionHeight),
              padding: EdgeInsets.symmetric(
                horizontal: chrome.actionHorizontalPadding,
              ),
              visualDensity: chrome.actionVisualDensity,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(meta.allLabel),
                SizedBox(width: chrome.actionIconGap),
                Icon(meta.allIcon, size: chrome.actionIconSize),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMomentsQuickComposer(L10n l, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final headerMeta = momentQuickComposerHeaderMeta(
      displayName: _myDisplayName,
      isArabic: l.isArabic,
    );
    final chrome = momentQuickComposerChromeMeta();
    final borderColor = theme.dividerColor.withValues(
      alpha: isDark ? chrome.darkBorderAlpha : chrome.lightBorderAlpha,
    );

    Future<void> openWithImage(ImageSource source) async {
      final picked = await _pickImageBytes(source: source);
      if (picked == null || !mounted) return;
      await _openWeChatComposer(
        initialImageBytes: picked.bytes,
        initialImageMime: picked.mime,
      );
    }

    void runQuickAction(MomentQuickComposerActionMeta action) {
      switch (action.kind) {
        case MomentQuickComposerActionKind.camera:
          Perf.action(action.perfKey);
          unawaited(openWithImage(ImageSource.camera));
          break;
        case MomentQuickComposerActionKind.album:
          Perf.action(action.perfKey);
          unawaited(openWithImage(ImageSource.gallery));
          break;
        case MomentQuickComposerActionKind.friends:
          Perf.action(action.perfKey);
          unawaited(_openWeChatComposer(initialVisibilityScope: 'friends'));
          break;
        case MomentQuickComposerActionKind.closeFriends:
          Perf.action(action.perfKey);
          unawaited(
            _openWeChatComposer(initialVisibilityScope: 'close_friends'),
          );
          break;
        case MomentQuickComposerActionKind.onlyMe:
          Perf.action(action.perfKey);
          unawaited(_openWeChatComposer(initialVisibilityScope: 'only_me'));
          break;
        case MomentQuickComposerActionKind.filters:
          setState(() {
            _enableAdvancedFilters = !_enableAdvancedFilters;
          });
          Perf.action(action.perfKey);
          break;
      }
    }

    Widget quickAction({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
    }) {
      final color = selected
          ? WeChatPalette.green
          : theme.colorScheme.onSurface.withValues(
              alpha: chrome.unselectedTextAlpha,
            );
      final fill = selected
          ? WeChatPalette.green.withValues(
              alpha: isDark
                  ? chrome.selectedFillDarkAlpha
                  : chrome.selectedFillLightAlpha,
            )
          : Colors.transparent;
      return Padding(
        padding: EdgeInsetsDirectional.only(end: chrome.actionEndSpacing),
        child: InkWell(
          borderRadius: BorderRadius.circular(chrome.actionRadius),
          onTap: onTap,
          child: Container(
            height: chrome.actionHeight,
            padding: EdgeInsets.symmetric(
              horizontal: chrome.actionHorizontalPadding,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(chrome.actionRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: chrome.actionIconSize, color: color),
                SizedBox(width: chrome.actionIconGap),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: chrome.actionFontSize,
                    fontWeight: selected
                        ? chrome.selectedFontWeight
                        : chrome.unselectedFontWeight,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : chrome.lightSurfaceColor,
        border: Border(
          top: BorderSide(color: borderColor, width: chrome.borderWidth),
          bottom: BorderSide(color: borderColor, width: chrome.borderWidth),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              Perf.action(headerMeta.openPerfKey);
              unawaited(_openWeChatComposer());
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: chrome.headerHorizontalPadding,
                vertical: chrome.headerVerticalPadding,
              ),
              child: Row(
                children: [
                  Container(
                    width: chrome.initialBoxSize,
                    height: chrome.initialBoxSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WeChatPalette.green.withValues(
                        alpha: chrome.initialBackgroundAlpha,
                      ),
                      borderRadius: BorderRadius.circular(
                        chrome.initialBoxRadius,
                      ),
                    ),
                    child: Text(
                      headerMeta.initial,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: chrome.initialFontWeight,
                        color: WeChatPalette.green,
                      ),
                    ),
                  ),
                  SizedBox(width: chrome.initialFieldGap),
                  Expanded(
                    child: Container(
                      height: chrome.fieldHeight,
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.symmetric(
                        horizontal: chrome.fieldHorizontalPadding,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? WeChatPalette.searchFillDark
                            : WeChatPalette.searchFill,
                        borderRadius: BorderRadius.circular(chrome.fieldRadius),
                      ),
                      child: Text(
                        headerMeta.placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: chrome.placeholderAlpha),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: chrome.trailingGap),
                  Icon(
                    headerMeta.trailingIcon,
                    size: chrome.trailingIconSize,
                    color: theme.colorScheme.onSurface.withValues(
                      alpha: chrome.trailingIconAlpha,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: chrome.dividerHeight,
            thickness: chrome.dividerThickness,
            indent: chrome.dividerIndent,
            color: borderColor,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(
              chrome.actionsStartPadding,
              chrome.actionsVerticalPadding,
              chrome.actionsEndPadding,
              chrome.actionsVerticalPadding,
            ),
            child: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    children: momentQuickComposerActionMetas(
                      isArabic: l.isArabic,
                      filtersSelected: _enableAdvancedFilters,
                    )
                        .map(
                          (action) => quickAction(
                            icon: action.icon,
                            label: action.label,
                            selected: action.selected,
                            onTap: () => runQuickAction(action),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
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

  Future<void> _openWeChatComposer({
    String initialText = '',
    Uint8List? initialImageBytes,
    String? initialImageMime,
    String initialVisibilityScope = 'public',
    String? initialMiniProgramId,
    bool clearPresetOnClose = false,
  }) async {
    final activeMiniProgramId = _activeMiniProgramId();
    final presetMiniProgramId = (initialMiniProgramId ?? '').trim();
    final composerMiniProgramId = presetMiniProgramId.isNotEmpty
        ? presetMiniProgramId
        : (activeMiniProgramId.isEmpty ? null : activeMiniProgramId);
    final draft = await Navigator.of(context).push<WeChatMomentDraft>(
      MaterialPageRoute(
        builder: (_) => WeChatMomentsComposerPage(
          baseUrl: widget.baseUrl,
          initialText: initialText,
          initialImageBytes: initialImageBytes,
          initialImageMime: initialImageMime,
          initialVisibilityScope: initialVisibilityScope,
          initialVisibilityTag: _visibilityTag,
          initialVisibilityTagMode: _visibilityTagMode,
          initialMiniProgramId: composerMiniProgramId,
          availableAudienceTags: _availableAudienceTags,
        ),
      ),
    );

    if (draft == null) {
      if (!mounted) return;
      if (clearPresetOnClose) {
        setState(() {
          _presetText = null;
          _presetImage = null;
          _presetMiniProgramId = null;
        });
      }
      return;
    }

    final text = draft.text.trim();
    final images = draft.imageBytes.where((b) => b.isNotEmpty).toList();
    final hasImages = images.isNotEmpty;
    final locationLabel = (draft.locationLabel ?? '').trim();
    final miniProgramId = (draft.miniProgramId ?? '').trim();
    if (text.isEmpty && !hasImages && miniProgramId.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _visibilityScope = draft.visibilityScope;
      final tag = (draft.visibilityTag ?? '').trim();
      _visibilityTag = tag.isEmpty ? null : tag;
      _visibilityTagMode =
          draft.visibilityTagMode == 'except' ? 'except' : 'only';
      _visibilityTagCtrl.text = tag;
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
        miniProgramId: miniProgramId.isNotEmpty ? miniProgramId : null,
      );
    }
    if (!posted) {
      await _addPostLocal(
        text,
        imagesB64: imagesB64,
        locationLabel: locationLabel.isNotEmpty ? locationLabel : null,
        miniProgramId: miniProgramId.isNotEmpty ? miniProgramId : null,
        clearInlineComposer: false,
      );
    }

    if (!mounted) return;
    setState(() {
      _presetText = null;
      _presetImage = null;
      _presetMiniProgramId = null;
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
    _filterRedpacketOnly = widget.initialRedpacketOnly;
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

  void _applyMomentAudienceFilter(MomentAudienceMeta meta) {
    if (!meta.actionable) return;
    setState(() {
      switch (meta.key) {
        case 'close_friends':
          _filterCloseFriendsOnly = true;
          _filterAudienceTag = null;
          break;
        case 'friends_tag':
          final tag = (meta.audienceTag ?? '').trim();
          _filterCloseFriendsOnly = false;
          _filterAudienceTag = tag.isEmpty ? null : tag;
          break;
        case 'public':
        case 'friends':
        default:
          _filterCloseFriendsOnly = false;
          _filterAudienceTag = null;
          break;
      }
    });
    Perf.action('moments_audience_chip_tap');
  }

  Widget _buildMomentAudiencePill(
    MomentAudienceMeta meta,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final isPublic = meta.key == 'public';
    final chrome = momentAudiencePillChromeMeta();
    final baseColor = isPublic
        ? theme.colorScheme.onSurface.withValues(alpha: chrome.publicTextAlpha)
        : theme.colorScheme.primary.withValues(alpha: chrome.privateTextAlpha);
    final bgColor = isPublic
        ? theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: isDark
                ? chrome.publicDarkBackgroundAlpha
                : chrome.publicLightBackgroundAlpha,
          )
        : theme.colorScheme.primary.withValues(
            alpha: isDark
                ? chrome.privateDarkBackgroundAlpha
                : chrome.privateLightBackgroundAlpha,
          );
    final borderColor = isPublic
        ? theme.dividerColor.withValues(
            alpha: isDark
                ? chrome.publicDarkBorderAlpha
                : chrome.publicLightBorderAlpha,
          )
        : theme.colorScheme.primary.withValues(
            alpha: isDark
                ? chrome.privateDarkBorderAlpha
                : chrome.privateLightBorderAlpha,
          );

    final pill = Container(
      constraints: BoxConstraints(maxWidth: chrome.maxWidth),
      padding: EdgeInsets.symmetric(
        horizontal: chrome.horizontalPadding,
        vertical: chrome.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(chrome.radius),
        border: Border.all(color: borderColor, width: chrome.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: chrome.iconSize, color: baseColor),
          SizedBox(width: chrome.iconGap),
          Flexible(
            child: Text(
              meta.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: chrome.fontSize,
                height: chrome.lineHeight,
                fontWeight: chrome.labelWeight,
                color: baseColor,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: chrome.topGap),
      child: meta.actionable
          ? InkWell(
              borderRadius: BorderRadius.circular(chrome.radius),
              onTap: () => _applyMomentAudienceFilter(meta),
              child: pill,
            )
          : pill,
    );
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
      final r = await http.get(uri, headers: await _hdrMoments(widget.baseUrl));
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
      final r = await http.get(uri, headers: await _hdrMoments(widget.baseUrl));
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
      final tagUri = Uri.parse('${widget.baseUrl}/me/friends/tags');
      final tagResp =
          await http.get(tagUri, headers: await _hdrMoments(widget.baseUrl));
      if (tagResp.statusCode >= 200 && tagResp.statusCode < 300) {
        final decoded = jsonDecode(tagResp.body);
        if (decoded is Map && decoded['items'] is List) {
          for (final e in decoded['items'] as List) {
            if (e is! Map || e['tags'] is! List) continue;
            for (final t in e['tags'] as List) {
              final v = (t ?? '').toString().trim();
              if (v.isNotEmpty) {
                tags.add(v);
              }
            }
          }
        }
      }
      final friendsUri = Uri.parse('${widget.baseUrl}/me/friends');
      final friendsResp = await http.get(friendsUri,
          headers: await _hdrMoments(widget.baseUrl));
      if (friendsResp.statusCode >= 200 && friendsResp.statusCode < 300) {
        final decoded = jsonDecode(friendsResp.body);
        if (decoded is Map && decoded['friends'] is List) {
          final list = decoded['friends'] as List;
          for (final e in list) {
            if (e is Map && e['tags'] is List) {
              for (final t in (e['tags'] as List)) {
                final v = (t ?? '').toString().trim();
                if (v.isNotEmpty) {
                  tags.add(v);
                }
              }
            }
          }
        }
      }
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

  MomentComposerVisibilityMeta _audienceSummaryMeta(L10n l) {
    return momentComposerVisibilityMetaFor(
      visibilityScope: _visibilityScope,
      visibilityTag: _visibilityTag ?? '',
      visibilityTagMode: _visibilityTagMode,
      isArabic: l.isArabic,
    );
  }

  Widget _buildAudienceSummaryPill(L10n l, ThemeData theme) {
    final meta = _audienceSummaryMeta(l);
    final isDark = theme.brightness == Brightness.dark;
    final chrome = momentComposerAudienceSummaryPillChromeMeta();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: chrome.horizontalPadding,
        vertical: chrome.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(
          alpha:
              isDark ? chrome.darkBackgroundAlpha : chrome.lightBackgroundAlpha,
        ),
        borderRadius: BorderRadius.circular(chrome.radius),
        border: Border.all(
          color:
              theme.colorScheme.primary.withValues(alpha: chrome.borderAlpha),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            meta.icon,
            size: chrome.iconSize,
            color:
                theme.colorScheme.primary.withValues(alpha: chrome.iconAlpha),
          ),
          SizedBox(width: chrome.iconGap),
          Text(
            meta.summaryLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: chrome.fontSize,
              color: theme.colorScheme.onSurface
                  .withValues(alpha: chrome.textAlpha),
            ),
          ),
        ],
      ),
    );
  }

  bool _isRedPacketText(String text) {
    final t = text.toLowerCase();
    if (t.contains('Green Paket')) return true;
    if (t.contains('Green Pakets')) return true;
    if (t.contains('i am sending Green Pakets via shamell pay')) return true;
    if (text.contains('حزمة خضراء')) return true;
    if (text.contains('حزمًا حمراء')) return true;
    return false;
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

  void _clearInlineComposerFields() {
    _postCtrl.clear();
    _pendingImage = null;
    _pendingImageMime = null;
    _presetText = null;
    _presetImage = null;
    _presetMiniProgramId = null;
  }

  void _clearInlineComposerDraft() {
    setState(_clearInlineComposerFields);
  }

  MomentInlineComposerPublishStateMeta _inlineComposerPublishState() {
    return momentInlineComposerPublishStateMeta(
      draftText: _postCtrl.text,
      presetText: _presetText ?? '',
      hasPendingImage: _pendingImage != null,
      hasPresetImage: _presetImage != null,
      miniProgramId: _inlineComposerMiniProgramId(),
    );
  }

  Future<void> _loadPreset() async {
    try {
      final preset = await loadAndClearMomentsPreset();
      if (!mounted) return;
      setState(() {
        _presetText = preset.text;
        _presetImage = preset.imageBytes;
        _presetMiniProgramId = preset.miniProgramId;
      });
    } catch (_) {}

    if (!mounted) return;
    final hasPreset = (_presetText != null && _presetText!.trim().isNotEmpty) ||
        _presetImage != null ||
        (_presetMiniProgramId != null && _presetMiniProgramId!.isNotEmpty);
    final isFriendTimeline = (widget.timelineAuthorId ?? '').trim().isNotEmpty;
    if (widget.showComposer && !isFriendTimeline && hasPreset) {
      if (_openedPresetComposer) return;
      _openedPresetComposer = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _openWeChatComposer(
            initialText: (_presetText ?? '').trim(),
            initialImageBytes: _presetImage,
            initialImageMime: null,
            initialMiniProgramId: _presetMiniProgramId,
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
      final token =
          (await getSessionTokenForBaseUrl(widget.baseUrl) ?? '').trim();
      final pseudo = token.isEmpty
          ? null
          : 'User ${crypto.sha1.convert(utf8.encode(token)).toString().substring(0, 6)}';
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
      final r = await http.get(uri, headers: await _hdrMoments(widget.baseUrl));
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
    final chrome = momentModerationOverviewSheetChromeMeta();
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
            left: chrome.sheetEdgePadding,
            right: chrome.sheetEdgePadding,
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                chrome.viewInsetBottomGap,
            top: chrome.sheetEdgePadding,
          ),
          child: GlassPanel(
            radius: chrome.panelRadius,
            padding: EdgeInsets.all(chrome.panelPadding),
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
                          ?.copyWith(fontWeight: chrome.titleFontWeight),
                    ),
                    SizedBox(height: chrome.titleBottomGap),
                    if (!hasMuted && !hasHidden)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: chrome.emptyBottomPadding,
                        ),
                        child: Text(
                          l.isArabic
                              ? 'لا توجد عناصر مخفية أو مكتومة حاليًا.'
                              : 'You do not have any hidden posts or muted users yet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: chrome.emptyTextAlpha),
                          ),
                        ),
                      ),
                    if (hasMuted) ...[
                      Text(
                        l.isArabic
                            ? 'المستخدمون المكتومون'
                            : 'Muted users in Moments',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: chrome.sectionTitleFontWeight,
                        ),
                      ),
                      SizedBox(height: chrome.sectionTitleBottomGap),
                      Wrap(
                        spacing: chrome.chipSpacing,
                        runSpacing: chrome.chipRunSpacing,
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
                            avatar: Icon(
                              Icons.volume_off_outlined,
                              size: chrome.chipIconSize,
                            ),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: chrome.mutedSectionBottomGap),
                    ],
                    if (hasHidden) ...[
                      Text(
                        l.isArabic ? 'المنشورات المخفية' : 'Hidden posts',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: chrome.sectionTitleFontWeight,
                        ),
                      ),
                      SizedBox(height: chrome.sectionTitleBottomGap),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: chrome.hiddenListMaxHeight,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: hidden.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(height: chrome.hiddenRowGap),
                          itemBuilder: (_, i) {
                            final p = hidden[i];
                            final id = (p['id'] ?? '').toString();
                            final text = (p['text'] ?? '').toString().trim();
                            final preview = text.isEmpty
                                ? (l.isArabic
                                    ? 'منشور بدون نص'
                                    : 'Post without text')
                                : (text.length > chrome.hiddenPreviewMaxChars
                                    ? '${text.substring(0, chrome.hiddenPreviewMaxChars)}…'
                                    : text);
                            return ListTile(
                              dense: chrome.hiddenTileDense,
                              contentPadding: chrome.hiddenTileContentPadding,
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
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: chrome.hiddenSubtitleAlpha,
                                  ),
                                  fontSize: chrome.hiddenSubtitleFontSize,
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
      if ((raw['mini_program_id'] ?? '').toString().isNotEmpty)
        'mini_program_id': (raw['mini_program_id'] ?? '').toString(),
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
        final miniProgramId = (widget.miniProgramId ?? '').trim();
        if (miniProgramId.isNotEmpty) {
          qp['mini_program_id'] = miniProgramId;
        }
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
      final r = await http.get(uri, headers: await _hdrMoments(widget.baseUrl));
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
      final r = await http.get(uri, headers: await _hdrMoments(widget.baseUrl));
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
        headers: await _hdrMoments(widget.baseUrl, json: true),
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
        headers: await _hdrMoments(widget.baseUrl, json: true),
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
      await http.post(uri,
          headers: await _hdrMoments(widget.baseUrl, json: true));
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
      await http.delete(uri,
          headers: await _hdrMoments(widget.baseUrl, json: true));
    } catch (_) {}
  }

  String _momentShareText(Map<String, dynamic> post, L10n l) {
    final text = (post['text'] ?? post['content'] ?? '').toString().trim();
    final author = (post['author_name'] ?? '').toString().trim();
    final location = (post['location_label'] ?? '').toString().trim();
    final postId = (post['id'] ?? '').toString().trim();
    final buf = StringBuffer();
    if (text.isNotEmpty) {
      buf.writeln(text);
    }
    if (author.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln(l.isArabic ? 'من $author' : 'From $author');
    }
    if (location.isNotEmpty) {
      buf.writeln(location);
    }
    if (postId.isNotEmpty) {
      buf.writeln('shamell://moments?post_id=$postId');
    } else {
      buf.writeln('shamell://moments');
    }
    return buf.toString().trim();
  }

  Future<void> _shareMomentPost(Map<String, dynamic> post) async {
    final l = L10n.of(context);
    final text = _momentShareText(post, l);
    if (text.isEmpty) return;
    await Share.share(text);
  }

  Future<void> _saveMomentPost(Map<String, dynamic> post) async {
    final l = L10n.of(context);
    final text = _momentShareText(post, l);
    if (text.isEmpty) return;
    await addFavoriteItemQuick(text, baseUrlOverride: widget.baseUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.isArabic
              ? 'تم حفظ اللحظة في المفضلة.'
              : 'Moment saved to Favorites.',
        ),
      ),
    );
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
    final actions = momentPostQuickActionMetas(
      isLiked: isLiked,
      isArabic: isArabic,
    );
    final menuChrome = momentPostActionMenuChromeMeta();
    final popoverChrome = momentPostActionPopoverChromeMeta();

    final anchorOffset =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorSize = anchorBox.size;

    final menuHeight = menuChrome.height;
    final margin = popoverChrome.margin;

    final overlaySize = overlayBox.size;
    final menuWidth = math.min(
      popoverChrome.maxMenuWidth,
      math.max(popoverChrome.minMenuWidth, overlaySize.width - margin * 2),
    );

    var left = anchorOffset.dx - menuWidth - popoverChrome.anchorGap;
    left = left.clamp(margin, overlaySize.width - menuWidth - margin);

    var top = anchorOffset.dy + (anchorSize.height / 2) - (menuHeight / 2);
    top = top.clamp(margin, overlaySize.height - menuHeight - margin);

    final arrowTopRaw = anchorOffset.dy +
        (anchorSize.height / 2) -
        popoverChrome.arrowAnchorCenterOffset;
    final arrowTop = arrowTopRaw.clamp(
      top + popoverChrome.arrowTopInset,
      top + menuHeight - popoverChrome.arrowBottomInset,
    );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: isArabic ? 'إغلاق' : 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: popoverChrome.transitionDuration,
      pageBuilder: (ctx, a1, a2) {
        final curved = CurvedAnimation(
          parent: a1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final menu = _WeChatMomentActionMenu(
          likeAction: actions[0],
          commentAction: actions[1],
          shareAction: actions[2],
          saveAction: actions[3],
          width: menuWidth,
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
          onShare: () async {
            Navigator.of(ctx).pop();
            await _shareMomentPost(post);
          },
          onSave: () async {
            Navigator.of(ctx).pop();
            await _saveMomentPost(post);
          },
        );

        final arrow = ClipPath(
          clipper: _WeChatPopoverArrowClipper(),
          child: Container(
            width: popoverChrome.arrowWidth,
            height: popoverChrome.arrowHeight,
            color: popoverChrome.arrowColor,
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
                  final dx = popoverChrome.slideDx * (1 - t);
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
                        left: left +
                            menuWidth -
                            popoverChrome.arrowHorizontalOverlap,
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
        final chrome = momentCommentActionPopoverChromeMeta();
        final anchor = overlayBox.globalToLocal(globalPos) -
            Offset(0, chrome.anchorYOffset);

        final actionsCount = canDelete ? 2 : 1;
        final menuWidth =
            actionsCount == 2 ? chrome.copyDeleteWidth : chrome.copyOnlyWidth;
        final menuHeight = chrome.height;
        final arrowW = chrome.arrowWidth;
        final arrowH = chrome.arrowHeight;
        final margin = chrome.margin;
        final gap = chrome.gap;

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
        arrowLeft = arrowLeft.clamp(
          left + chrome.arrowHorizontalInset,
          left + menuWidth - arrowW - chrome.arrowHorizontalInset,
        );
        final arrowTop = showAbove ? (top + menuHeight) : (top - arrowH);

        final menu = Material(
          color: Colors.transparent,
          child: Container(
            width: menuWidth,
            height: menuHeight,
            decoration: BoxDecoration(
              color: chrome.backgroundColor,
              borderRadius: BorderRadius.circular(chrome.borderRadius),
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
                        style: TextStyle(
                          color: chrome.copyTextColor,
                          fontWeight: chrome.copyFontWeight,
                          fontSize: chrome.labelFontSize,
                        ),
                      ),
                    ),
                  ),
                ),
                if (canDelete) ...[
                  Container(
                    width: chrome.dividerWidth,
                    height: chrome.dividerHeight,
                    color: Colors.white.withValues(alpha: chrome.dividerAlpha),
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
                          style: TextStyle(
                            color: chrome.deleteTextColor,
                            fontWeight: chrome.deleteFontWeight,
                            fontSize: chrome.labelFontSize,
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
              ? _WeChatPopoverDownArrowClipper()
              : _WeChatPopoverUpArrowClipper(),
          child: Container(
            width: arrowW,
            height: arrowH,
            color: chrome.backgroundColor,
          ),
        );

        await showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: cancelLabel,
          barrierColor: Colors.transparent,
          transitionDuration: chrome.transitionDuration,
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
                      final dx = chrome.slideDx * (1 - t);
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
        final sheetChrome = momentCommentActionSheetChromeMeta();
        final isSheetDark = sheetTheme.brightness == Brightness.dark;
        final dividerColor = sheetTheme.dividerColor.withValues(
          alpha: isSheetDark
              ? sheetChrome.darkDividerAlpha
              : sheetChrome.lightDividerAlpha,
        );
        final cardColor = sheetTheme.colorScheme.surface.withValues(
          alpha: isSheetDark
              ? sheetChrome.darkRowAlpha
              : sheetChrome.lightRowAlpha,
        );

        Widget actionRow({
          required String label,
          Color? color,
          FontWeight? fontWeight,
          required VoidCallback onTap,
        }) {
          return InkWell(
            onTap: onTap,
            child: SizedBox(
              height: sheetChrome.rowHeight,
              width: double.infinity,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: sheetTheme.textTheme.titleMedium?.copyWith(
                    fontSize: sheetChrome.labelFontSize,
                    fontWeight: fontWeight ?? sheetChrome.actionFontWeight,
                    color: color ?? sheetTheme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        }

        Widget card(List<Widget> children) {
          return Material(
            color: cardColor,
            borderRadius: BorderRadius.circular(sheetChrome.fallbackCardRadius),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          );
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              sheetChrome.fallbackHorizontalPadding,
              sheetChrome.fallbackTopPadding,
              sheetChrome.fallbackHorizontalPadding,
              sheetChrome.fallbackBottomPadding,
            ),
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
                    Divider(
                      height: sheetChrome.dividerHeight,
                      thickness: sheetChrome.dividerThickness,
                      color: dividerColor,
                    ),
                    actionRow(
                      label: deleteLabel,
                      color: sheetChrome.deleteTextColor,
                      fontWeight: sheetChrome.actionFontWeight,
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await doDelete();
                      },
                    ),
                  ],
                ]),
                SizedBox(height: sheetChrome.sectionGap),
                card([
                  actionRow(
                    label: cancelLabel,
                    fontWeight: sheetChrome.cancelFontWeight,
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
    String? miniProgramId,
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
      final explicitMiniProgramId = (miniProgramId ?? '').trim();
      if (explicitMiniProgramId.isNotEmpty) {
        payload['mini_program_id'] = explicitMiniProgramId;
      } else {
        final miniProgramTarget = parseMiniProgramDeepLinkFromText(text);
        if (miniProgramTarget != null) {
          payload['mini_program_id'] = miniProgramTarget.id;
        }
      }
      final r = await http.post(
        uri,
        headers: await _hdrMoments(widget.baseUrl, json: true),
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
    String? miniProgramId,
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
      final miniProgramTarget = parseMiniProgramDeepLinkFromText(text);
      if (miniProgramTarget != null) {
        post['mini_program_id'] = miniProgramTarget.id;
      }
      final explicitMiniProgramId = (miniProgramId ?? '').trim();
      if (explicitMiniProgramId.isNotEmpty) {
        post['mini_program_id'] = explicitMiniProgramId;
      }
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
        _clearInlineComposerFields();
      }
    });
    await _saveLocal();
  }

  Future<void> _addPost() async {
    final publishState = _inlineComposerPublishState();
    if (!publishState.canPublish) return;
    final text = publishState.effectiveText;
    final imgB64 = _pendingImage != null
        ? base64Encode(_pendingImage!)
        : (_presetImage != null ? base64Encode(_presetImage!) : null);
    final miniProgramId = publishState.miniProgramId;
    if (_usingApi) {
      final ok = await _addPostApi(
        text,
        imageB64: imgB64,
        miniProgramId: miniProgramId.isNotEmpty ? miniProgramId : null,
      );
      if (ok) {
        _clearInlineComposerDraft();
        return;
      }
    }
    await _addPostLocal(
      text,
      miniProgramId: miniProgramId.isNotEmpty ? miniProgramId : null,
    );
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
        headers: await _hdrMoments(widget.baseUrl, json: true),
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
        headers: await _hdrMoments(widget.baseUrl, json: true),
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
    final shareText = _momentShareText(p, l);
    final isLocal = (p['id'] ?? '').toString().startsWith('local_');
    final visibility = (p['visibility'] ?? 'public').toString();
    final postId = (p['id'] ?? '').toString();
    final authorName = (p['author_name'] ?? '').toString().trim();
    final hasAuthor = authorName.isNotEmpty;
    final isMutedAuthor = hasAuthor && _mutedAuthors.contains(authorName);
    final canToggleVisibility =
        isLocal || (_usingApi && widget.showOnlyMine && postId.isNotEmpty);
    final isPrivate = visibility == 'only_me' || visibility == 'private';
    final sheetActions = momentPostSheetActionMetas(
      hasShareText: shareText.trim().isNotEmpty,
      canToggleVisibility: canToggleVisibility,
      isPrivate: isPrivate,
      isLocal: isLocal,
      canHideOrReport: !isLocal && postId.isNotEmpty,
      hasAuthor: hasAuthor,
      isMutedAuthor: isMutedAuthor,
      isArabic: l.isArabic,
    );

    Future<void> handleSheetAction(MomentPostSheetActionMeta action) async {
      switch (action.kind) {
        case MomentPostSheetActionKind.copy:
          await Clipboard.setData(ClipboardData(text: shareText));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic
                    ? 'تم نسخ رابط اللحظة'
                    : 'Moment link copied to clipboard',
              ),
            ),
          );
          return;
        case MomentPostSheetActionKind.share:
          await _shareMomentPost(p);
          return;
        case MomentPostSheetActionKind.save:
          await _saveMomentPost(p);
          return;
        case MomentPostSheetActionKind.toggleVisibility:
          await _toggleVisibility(p);
          return;
        case MomentPostSheetActionKind.delete:
          await _deletePost(p);
          return;
        case MomentPostSheetActionKind.hide:
          setState(() {
            _hiddenPostIds.add(postId);
          });
          await _saveHiddenPosts();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic
                    ? 'تم إخفاء هذا المنشور من موجز اللحظات.'
                    : 'This post was hidden from your Moments feed.',
              ),
            ),
          );
          return;
        case MomentPostSheetActionKind.report:
          await _reportPost(postId);
          return;
        case MomentPostSheetActionKind.muteAuthor:
          setState(() {
            _mutedAuthors.add(authorName);
          });
          await _saveMutedAuthors();
          return;
        case MomentPostSheetActionKind.unmuteAuthor:
          setState(() {
            _mutedAuthors.remove(authorName);
          });
          await _saveMutedAuthors();
          return;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sheetTheme = Theme.of(ctx);
        final isDark = sheetTheme.brightness == Brightness.dark;
        final sheetBg =
            isDark ? sheetTheme.colorScheme.surface : WeChatPalette.background;
        final actionSheetChrome = momentPostActionSheetChromeMeta();
        final rowBg = sheetTheme.colorScheme.surface.withValues(
          alpha: isDark
              ? actionSheetChrome.darkRowAlpha
              : actionSheetChrome.lightRowAlpha,
        );
        final dividerColor = sheetTheme.dividerColor.withValues(
          alpha: isDark
              ? actionSheetChrome.darkDividerAlpha
              : actionSheetChrome.lightDividerAlpha,
        );

        Widget section(List<Widget> rows) {
          if (rows.isEmpty) return const SizedBox.shrink();
          return Container(
            color: rowBg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(
                  height: actionSheetChrome.dividerHeight,
                  thickness: actionSheetChrome.dividerThickness,
                  color: dividerColor,
                ),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: actionSheetChrome.dividerHeight,
                      thickness: actionSheetChrome.dividerThickness,
                      indent: actionSheetChrome.innerDividerIndent,
                      color: dividerColor,
                    ),
                  rows[i],
                ],
                Divider(
                  height: actionSheetChrome.dividerHeight,
                  thickness: actionSheetChrome.dividerThickness,
                  color: dividerColor,
                ),
              ],
            ),
          );
        }

        Widget actionRow({
          required IconData icon,
          required String title,
          Color? color,
          required Future<void> Function() onTap,
        }) {
          final effectiveColor = color ?? sheetTheme.colorScheme.onSurface;
          return InkWell(
            onTap: () async {
              Navigator.of(ctx).pop();
              await onTap();
            },
            child: SizedBox(
              height: actionSheetChrome.rowHeight,
              width: double.infinity,
              child: Row(
                children: [
                  SizedBox(width: actionSheetChrome.edgeGap),
                  Icon(
                    icon,
                    size: actionSheetChrome.iconSize,
                    color: effectiveColor,
                  ),
                  SizedBox(width: actionSheetChrome.iconTextGap),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sheetTheme.textTheme.bodyLarge?.copyWith(
                        fontSize: actionSheetChrome.labelFontSize,
                        fontWeight: actionSheetChrome.actionFontWeight,
                        color: effectiveColor,
                      ),
                    ),
                  ),
                  SizedBox(width: actionSheetChrome.edgeGap),
                ],
              ),
            ),
          );
        }

        Widget cancelRow() {
          return InkWell(
            onTap: () => Navigator.of(ctx).pop(),
            child: SizedBox(
              height: actionSheetChrome.rowHeight,
              width: double.infinity,
              child: Center(
                child: Text(
                  l.isArabic ? 'إلغاء' : 'Cancel',
                  style: sheetTheme.textTheme.bodyLarge?.copyWith(
                    fontSize: actionSheetChrome.labelFontSize,
                    fontWeight: actionSheetChrome.cancelFontWeight,
                    color: sheetTheme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          );
        }

        final rows = <Widget>[
          for (final action in sheetActions)
            actionRow(
              icon: action.icon,
              title: action.label,
              color: action.destructive
                  ? actionSheetChrome.destructiveColor
                  : null,
              onTap: () => handleSheetAction(action),
            ),
        ];

        return SafeArea(
          top: false,
          child: Container(
            color: sheetBg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                section(rows),
                SizedBox(height: actionSheetChrome.sectionGap),
                section([cancelRow()]),
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
    return parseOfficialDeepLinkFromText(text) != null;
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
      final token =
          (await getSessionTokenForBaseUrl(widget.baseUrl) ?? '').trim();
      if (token.isNotEmpty) {
        final hex = crypto.sha1.convert(utf8.encode(token)).toString();
        if (hex.length >= 6) {
          myPseudonym = 'User ${hex.substring(0, 6)}';
        }
      }
    } catch (_) {}

    String displayNameForAuthor(String authorName) {
      final raw = normalizeMomentPersonLabel(
        rawName: authorName,
        youLabel: youLabel,
        myPseudonym: myPseudonym,
      );
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
    final sheetChrome = momentCommentSheetChromeMeta();

    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: sheetChrome.barrierAlpha),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final commentChrome = momentInlineCommentBarChromeMeta();
        final sheetBg = isDark ? theme.colorScheme.surface : Colors.white;
        final inputBg =
            isDark ? theme.colorScheme.surface : WeChatPalette.background;
        final dividerColor =
            isDark ? theme.dividerColor : WeChatPalette.divider;
        final feedTextChrome = momentFeedTextChromeMeta();
        final nameColor = isDark
            ? theme.colorScheme.primary
            : feedTextChrome.nameLinkLightColor;
        final fieldBg = isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: commentChrome.darkFieldFillAlpha,
              )
            : Colors.white;
        final fieldBorder = isDark ? theme.dividerColor : WeChatPalette.divider;
        final sendDisabledBg = isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: commentChrome.darkDisabledSendAlpha,
              )
            : WeChatPalette.searchFill;

        final baseStyle = theme.textTheme.bodyMedium?.copyWith(
              fontSize: commentChrome.baseFontSize,
            ) ??
            TextStyle(fontSize: commentChrome.baseFontSize);
        final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
              fontSize: commentChrome.secondaryFontSize,
              color: theme.colorScheme.onSurface.withValues(
                alpha: commentChrome.secondaryTextAlpha,
              ),
            ) ??
            TextStyle(
              fontSize: commentChrome.secondaryFontSize,
              color: theme.colorScheme.onSurface.withValues(
                alpha: commentChrome.secondaryTextAlpha,
              ),
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
              final isMine = isMomentPersonMe(
                rawName: authorRaw,
                youLabel: youLabel,
                myPseudonym: myPseudonym,
              );
              final canDelete = isMine || _isAdmin;
              final tileChrome = momentCommentTileChromeMeta();

              final commentTextSpan = TextSpan(
                style: baseStyle.copyWith(
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: tileChrome.textAlpha,
                  ),
                ),
                children: [
                  TextSpan(
                    text: displayName,
                    style: baseStyle.copyWith(
                      fontWeight: tileChrome.authorFontWeight,
                      color: nameColor,
                    ),
                  ),
                  if (isReply && replyDisplayName.isNotEmpty) ...[
                    TextSpan(
                      text: l.isArabic ? ' ردًا على ' : ' replied to ',
                      style: baseStyle.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: tileChrome.replyConnectorAlpha,
                        ),
                      ),
                    ),
                    TextSpan(
                      text: replyDisplayName,
                      style: baseStyle.copyWith(
                        fontWeight: tileChrome.authorFontWeight,
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
                    backgroundColor: Colors.transparent,
                    builder: (actx) {
                      final actTheme = Theme.of(actx);
                      final l2 = L10n.of(actx);
                      final actIsDark = actTheme.brightness == Brightness.dark;
                      final actionSheetChrome =
                          momentCommentActionSheetChromeMeta();
                      final actSheetBg = actIsDark
                          ? actTheme.colorScheme.surface
                          : WeChatPalette.background;
                      final rowBg = actTheme.colorScheme.surface.withValues(
                        alpha: actIsDark
                            ? actionSheetChrome.darkRowAlpha
                            : actionSheetChrome.lightRowAlpha,
                      );
                      final actionDivider = actTheme.dividerColor.withValues(
                        alpha: actIsDark
                            ? actionSheetChrome.darkDividerAlpha
                            : actionSheetChrome.lightDividerAlpha,
                      );

                      Widget section(List<Widget> rows) {
                        return Container(
                          color: rowBg,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Divider(
                                height: actionSheetChrome.dividerHeight,
                                thickness: actionSheetChrome.dividerThickness,
                                color: actionDivider,
                              ),
                              for (var i = 0; i < rows.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: actionSheetChrome.dividerHeight,
                                    thickness:
                                        actionSheetChrome.dividerThickness,
                                    indent:
                                        actionSheetChrome.innerDividerIndent,
                                    color: actionDivider,
                                  ),
                                rows[i],
                              ],
                              Divider(
                                height: actionSheetChrome.dividerHeight,
                                thickness: actionSheetChrome.dividerThickness,
                                color: actionDivider,
                              ),
                            ],
                          ),
                        );
                      }

                      Widget actionRow({
                        required IconData icon,
                        required String title,
                        required String value,
                        Color? color,
                      }) {
                        final effectiveColor =
                            color ?? actTheme.colorScheme.onSurface;
                        return InkWell(
                          onTap: () => Navigator.of(actx).pop(value),
                          child: SizedBox(
                            height: actionSheetChrome.rowHeight,
                            width: double.infinity,
                            child: Row(
                              children: [
                                SizedBox(width: actionSheetChrome.edgeGap),
                                Icon(
                                  icon,
                                  size: actionSheetChrome.iconSize,
                                  color: effectiveColor,
                                ),
                                SizedBox(width: actionSheetChrome.iconTextGap),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        actTheme.textTheme.bodyLarge?.copyWith(
                                      fontSize: actionSheetChrome.labelFontSize,
                                      fontWeight:
                                          actionSheetChrome.actionFontWeight,
                                      color: effectiveColor,
                                    ),
                                  ),
                                ),
                                SizedBox(width: actionSheetChrome.edgeGap),
                              ],
                            ),
                          ),
                        );
                      }

                      return SafeArea(
                        top: false,
                        child: Container(
                          color: actSheetBg,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              section([
                                actionRow(
                                  icon: Icons.copy,
                                  title: l2.isArabic ? 'نسخ' : 'Copy',
                                  value: 'copy',
                                ),
                                if (canDelete)
                                  actionRow(
                                    icon: Icons.delete_outline,
                                    title: l2.isArabic ? 'حذف' : 'Delete',
                                    value: 'delete',
                                    color: actionSheetChrome.deleteTextColor,
                                  ),
                              ]),
                              SizedBox(height: actionSheetChrome.sectionGap),
                              section([
                                InkWell(
                                  onTap: () => Navigator.of(actx).pop(),
                                  child: SizedBox(
                                    height: actionSheetChrome.rowHeight,
                                    width: double.infinity,
                                    child: Center(
                                      child: Text(
                                        l2.isArabic ? 'إلغاء' : 'Cancel',
                                        style: actTheme.textTheme.bodyLarge
                                            ?.copyWith(
                                          fontSize:
                                              actionSheetChrome.labelFontSize,
                                          fontWeight: actionSheetChrome
                                              .cancelFontWeight,
                                          color: actTheme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
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
                  margin: isHighlighted
                      ? EdgeInsets.only(top: sheetChrome.highlightedTopMargin)
                      : null,
                  padding: EdgeInsets.symmetric(
                    vertical: sheetChrome.commentVerticalPadding,
                  ),
                  decoration: isHighlighted
                      ? BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: sheetChrome.highlightedFillAlpha,
                          ),
                          borderRadius: BorderRadius.circular(
                            sheetChrome.highlightedRadius,
                          ),
                        )
                      : null,
                  child: RichText(
                    text: commentTextSpan,
                    maxLines: tileChrome.maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }

            final title = l.isArabic ? 'التعليقات' : 'Comments';
            final countSuffix =
                existing.isNotEmpty ? '(${existing.length})' : '';

            return AnimatedPadding(
              duration: sheetChrome.keyboardInsetDuration,
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: existing.isEmpty
                    ? sheetChrome.emptyInitialChildSize
                    : sheetChrome.populatedInitialChildSize,
                minChildSize: sheetChrome.minChildSize,
                maxChildSize: sheetChrome.maxChildSize,
                builder: (ctx, scrollController) {
                  listScrollCtrl = scrollController;
                  return ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: Material(
                      color: sheetBg,
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            SizedBox(height: sheetChrome.handleTopGap),
                            Container(
                              width: sheetChrome.handleWidth,
                              height: sheetChrome.handleHeight,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: sheetChrome.handleAlpha),
                                borderRadius: BorderRadius.circular(
                                  sheetChrome.handleRadius,
                                ),
                              ),
                            ),
                            SizedBox(height: sheetChrome.handleBottomGap),
                            SizedBox(
                              height: sheetChrome.headerHeight,
                              child: Stack(
                                children: [
                                  PositionedDirectional(
                                    start: sheetChrome.headerActionInset,
                                    top: 0,
                                    bottom: 0,
                                    child: IconButton(
                                      tooltip: l.isArabic ? 'إغلاق' : 'Close',
                                      icon: Icon(
                                        Icons.arrow_back,
                                        size: sheetChrome.headerIconSize,
                                      ),
                                      visualDensity:
                                          sheetChrome.headerActionVisualDensity,
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
                                            fontWeight:
                                                sheetChrome.titleFontWeight,
                                          ),
                                        ),
                                        if (countSuffix.isNotEmpty) ...[
                                          SizedBox(width: sheetChrome.countGap),
                                          Text(
                                            countSuffix,
                                            style: secondaryStyle,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  PositionedDirectional(
                                    end: sheetChrome.headerActionInset,
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
                                            icon: Icon(
                                              Icons.campaign_outlined,
                                              size: sheetChrome.headerIconSize,
                                            ),
                                            visualDensity: sheetChrome
                                                .headerActionVisualDensity,
                                            onPressed: () async {
                                              final originAcc =
                                                  _officialAccounts[
                                                      originAccId];
                                              final accName = originAcc?.name ??
                                                  originAccId;
                                              final textCtrl =
                                                  TextEditingController();
                                              try {
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
                                                        SizedBox(
                                                          height: sheetChrome
                                                              .officialReplyDialogFieldTopGap,
                                                        ),
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
                                              } finally {
                                                textCtrl.dispose();
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: sheetChrome.dividerHeight,
                              thickness: sheetChrome.dividerThickness,
                              color: dividerColor,
                            ),
                            Expanded(
                              child: visible.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(
                                          sheetChrome.emptyPadding,
                                        ),
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
                                      padding: EdgeInsets.symmetric(
                                        horizontal:
                                            sheetChrome.listHorizontalPadding,
                                        vertical:
                                            sheetChrome.listVerticalPadding,
                                      ),
                                      itemCount: visible.length,
                                      itemBuilder: (ctx, i) {
                                        return buildCommentTile(visible[i], i);
                                      },
                                    ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal:
                                    commentChrome.containerHorizontalPadding,
                                vertical:
                                    commentChrome.containerVerticalPadding,
                              ),
                              decoration: BoxDecoration(
                                color: inputBg,
                                border: Border(
                                  top: BorderSide(
                                    color: dividerColor,
                                    width: commentChrome.topBorderWidth,
                                  ),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((replyToName ?? '').trim().isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: commentChrome.replyBottomGap,
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
                                            visualDensity: commentChrome
                                                .closeVisualDensity,
                                            padding: commentChrome.closePadding,
                                            constraints: BoxConstraints(
                                              minWidth:
                                                  commentChrome.closeMinSize,
                                              minHeight:
                                                  commentChrome.closeMinSize,
                                            ),
                                            icon: Icon(
                                              Icons.close,
                                              size: commentChrome.closeIconSize,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(
                                                alpha: commentChrome
                                                    .closeIconAlpha,
                                              ),
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
                                            borderRadius: BorderRadius.circular(
                                              commentChrome.fieldRadius,
                                            ),
                                            border: Border.all(
                                              color: fieldBorder,
                                              width: commentChrome
                                                  .fieldBorderWidth,
                                            ),
                                          ),
                                          child: TextField(
                                            controller: ctrl,
                                            focusNode: inputFocus,
                                            autofocus: focusInput,
                                            minLines:
                                                commentChrome.fieldMinLines,
                                            maxLines:
                                                commentChrome.fieldMaxLines,
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
                                                  EdgeInsets.symmetric(
                                                horizontal: commentChrome
                                                    .fieldContentHorizontalPadding,
                                                vertical: commentChrome
                                                    .fieldContentVerticalPadding,
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
                                      SizedBox(width: commentChrome.sendGap),
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
                                                  WeChatPalette.green,
                                              disabledBackgroundColor:
                                                  sendDisabledBg,
                                              foregroundColor: Colors.white,
                                              disabledForegroundColor: theme
                                                  .colorScheme.onSurface
                                                  .withValues(
                                                alpha: commentChrome
                                                    .disabledForegroundAlpha,
                                              ),
                                              padding: EdgeInsets.symmetric(
                                                horizontal: commentChrome
                                                    .sendHorizontalPadding,
                                                vertical: commentChrome
                                                    .sendVerticalPadding,
                                              ),
                                              minimumSize: Size(
                                                commentChrome.sendMinWidth,
                                                commentChrome.sendMinHeight,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  commentChrome.sendRadius,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              l.isArabic ? 'إرسال' : 'Send',
                                              style: TextStyle(
                                                fontWeight: commentChrome
                                                    .sendFontWeight,
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
    } finally {
      ctrl.dispose();
      inputFocus.dispose();
    }
  }

  Widget _buildInlineCommentBar(L10n l, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final chrome = momentInlineCommentBarChromeMeta();
    final inputBg =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;
    final dividerColor = isDark ? theme.dividerColor : WeChatPalette.divider;
    final fieldBg = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: chrome.darkFieldFillAlpha,
          )
        : Colors.white;
    final fieldBorder = isDark ? theme.dividerColor : WeChatPalette.divider;
    final sendDisabledBg = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: chrome.darkDisabledSendAlpha,
          )
        : WeChatPalette.searchFill;

    final baseStyle =
        theme.textTheme.bodyMedium?.copyWith(fontSize: chrome.baseFontSize) ??
            TextStyle(fontSize: chrome.baseFontSize);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
          fontSize: chrome.secondaryFontSize,
          color: theme.colorScheme.onSurface.withValues(
            alpha: chrome.secondaryTextAlpha,
          ),
        ) ??
        TextStyle(
          fontSize: chrome.secondaryFontSize,
          color: theme.colorScheme.onSurface.withValues(
            alpha: chrome.secondaryTextAlpha,
          ),
        );
    final replyName = (_inlineReplyToName ?? '').trim();

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: chrome.containerHorizontalPadding,
          vertical: chrome.containerVerticalPadding,
        ),
        decoration: BoxDecoration(
          color: inputBg,
          border: Border(
            top: BorderSide(
              color: dividerColor,
              width: chrome.topBorderWidth,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyName.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: chrome.replyBottomGap),
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
                      visualDensity: chrome.closeVisualDensity,
                      padding: chrome.closePadding,
                      constraints: BoxConstraints(
                        minWidth: chrome.closeMinSize,
                        minHeight: chrome.closeMinSize,
                      ),
                      icon: Icon(
                        Icons.close,
                        size: chrome.closeIconSize,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: chrome.closeIconAlpha,
                        ),
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
                      borderRadius: BorderRadius.circular(chrome.fieldRadius),
                      border: Border.all(
                        color: fieldBorder,
                        width: chrome.fieldBorderWidth,
                      ),
                    ),
                    child: TextField(
                      controller: _inlineCommentCtrl,
                      focusNode: _inlineCommentFocus,
                      minLines: chrome.fieldMinLines,
                      maxLines: chrome.fieldMaxLines,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => unawaited(_submitInlineComment()),
                      style: baseStyle.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: chrome.fieldContentHorizontalPadding,
                          vertical: chrome.fieldContentVerticalPadding,
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
                SizedBox(width: chrome.sendGap),
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
                        backgroundColor: WeChatPalette.green,
                        disabledBackgroundColor: sendDisabledBg,
                        foregroundColor: Colors.white,
                        disabledForegroundColor:
                            theme.colorScheme.onSurface.withValues(
                          alpha: chrome.disabledForegroundAlpha,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: chrome.sendHorizontalPadding,
                          vertical: chrome.sendVerticalPadding,
                        ),
                        minimumSize: Size(
                          chrome.sendMinWidth,
                          chrome.sendMinHeight,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(chrome.sendRadius),
                        ),
                      ),
                      child: _inlineCommentSending
                          ? SizedBox(
                              width: chrome.progressSize,
                              height: chrome.progressSize,
                              child: CircularProgressIndicator(
                                strokeWidth: chrome.progressStrokeWidth,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withValues(
                                    alpha: chrome.progressAlpha,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              l.isArabic ? 'إرسال' : 'Send',
                              style: TextStyle(
                                fontWeight: chrome.sendFontWeight,
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
    final pageChrome = momentPageChromeMeta();
    final composerAudienceCopy = momentComposerAudienceCopyMeta(
      isArabic: l.isArabic,
    );
    final composerOfficialDirectoryLink =
        momentComposerOfficialDirectoryLinkMeta(
      city: _preferredCity ?? '',
      isArabic: l.isArabic,
    );
    final composerMediaAction = momentComposerMediaActionMeta(
      isArabic: l.isArabic,
    );
    final inlineComposerText = momentInlineComposerTextMeta(
      isArabic: l.isArabic,
    );
    final visibilityChipChrome = momentComposerVisibilityChipChromeMeta();
    final audienceTagChipChrome = momentComposerAudienceTagChipChromeMeta();
    final audienceFieldChrome = momentComposerAudienceFieldChromeMeta();
    final feedListChrome = momentFeedListChromeMeta();
    final inlinePublishState = _inlineComposerPublishState();

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
      final audienceMeta = momentAudienceMetaFor(
        visibility: visibility,
        audienceTag: (p['audience_tag'] ?? '').toString(),
        isArabic: l.isArabic,
      );
      final isRedPacket = _isRedPacketText(text);
      final hasOfficialReply = (p['has_official_reply'] as bool?) ?? false;
      final originAccId =
          (p['origin_official_account_id'] ?? '').toString().trim();
      final originAcc =
          originAccId.isNotEmpty ? _officialAccounts[originAccId] : null;

      final footerMeta = momentFooterMetaFor(
        rawTimestamp: rawTs,
        hasOfficialReply: hasOfficialReply,
        postId: postId,
        isArabic: l.isArabic,
      );

      final heroBase = postId.isNotEmpty
          ? postId
          : '${rawTs}_${authorName}_${text.hashCode}';

      Widget? imageWidget;
      final mediaChrome = momentMediaChromeMeta();
      if (imagesList.isNotEmpty) {
        final mediaMeta = momentMediaLayoutMeta(imageCount: imagesList.length);
        final visibleImages = imagesList.take(mediaMeta.visibleCount).toList();
        final heroTags = List<String>.generate(
          imagesList.length,
          (i) => 'moment:$heroBase:$i',
        );
        imageWidget = _buildMomentMediaFrame(
          mediaMeta: mediaMeta,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(mediaChrome.frameRadius),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: mediaMeta.columns,
                crossAxisSpacing: mediaMeta.spacing,
                mainAxisSpacing: mediaMeta.spacing,
                childAspectRatio: mediaMeta.childAspectRatio,
              ),
              itemCount: visibleImages.length,
              itemBuilder: (ctx, i) {
                final raw = visibleImages[i].trim();
                final heroTag = heroTags[i];
                final isHttp =
                    raw.startsWith('http://') || raw.startsWith('https://');
                Widget tile;
                if (isHttp) {
                  tile = GestureDetector(
                    onTap: () => unawaited(
                      _openPhotoViewer(
                        imagesList,
                        initialIndex: i,
                        heroTags: heroTags,
                      ),
                    ),
                    child: Hero(
                      tag: heroTag,
                      child: shamellCachedNetworkImage(
                        raw,
                        context: context,
                        logicalWidth: mediaMeta.tileLogicalSize,
                        logicalHeight: mediaMeta.tileLogicalSize,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                } else {
                  final b64 =
                      raw.contains('base64,') ? raw.split('base64,').last : raw;
                  try {
                    final bytes = base64Decode(b64);
                    tile = GestureDetector(
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
                    tile = GestureDetector(
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
                              .withValues(
                            alpha: isDark
                                ? mediaChrome.placeholderDarkAlpha
                                : mediaChrome.placeholderLightAlpha,
                          ),
                        ),
                      ),
                    );
                  }
                }
                if (mediaMeta.hiddenCount <= 0 ||
                    i != mediaMeta.visibleCount - 1) {
                  return tile;
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    tile,
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: mediaChrome.hiddenOverlayAlpha,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '+${mediaMeta.hiddenCount}',
                            style: TextStyle(
                              color: mediaChrome.hiddenCountTextColor,
                              fontSize: mediaChrome.hiddenCountFontSize,
                              fontWeight: mediaChrome.hiddenCountFontWeight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      } else if (imageB64.isNotEmpty) {
        try {
          final bytes = base64Decode(imageB64);
          final heroTag = 'moment:$heroBase:0';
          final mediaMeta = momentMediaLayoutMeta(imageCount: 1);
          imageWidget = _buildMomentMediaFrame(
            mediaMeta: mediaMeta,
            child: GestureDetector(
              onTap: () => unawaited(
                _openPhotoViewer(
                  [imageB64],
                  heroTags: [heroTag],
                ),
              ),
              child: Hero(
                tag: heroTag,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(mediaChrome.frameRadius),
                  child: AspectRatio(
                    aspectRatio: mediaMeta.childAspectRatio,
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          );
        } catch (_) {}
      } else if (imageUrl.isNotEmpty) {
        final heroTag = 'moment:$heroBase:0';
        final mediaMeta = momentMediaLayoutMeta(imageCount: 1);
        imageWidget = _buildMomentMediaFrame(
          mediaMeta: mediaMeta,
          child: GestureDetector(
            onTap: () => unawaited(
              _openPhotoViewer(
                [imageUrl],
                heroTags: [heroTag],
              ),
            ),
            child: Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(mediaChrome.frameRadius),
                child: AspectRatio(
                  aspectRatio: mediaMeta.childAspectRatio,
                  child: shamellCachedNetworkImage(
                    imageUrl,
                    context: context,
                    logicalWidth: mediaMeta.preferredWidth,
                    logicalHeight: mediaMeta.preferredWidth,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final textChrome = momentFeedTextChromeMeta();
      final contentChrome = momentFeedContentChromeMeta();
      final nameColor =
          isDark ? theme.colorScheme.primary : textChrome.nameLinkLightColor;
      final contextLineChrome = momentContextLineChromeMeta();
      final avatarMeta = momentAvatarMetaFor(
        authorName: authorName,
        avatarUrl: avatarUrl,
        isLocal: isLocal,
        isArabic: l.isArabic,
      );
      final avatar = SizedBox(
        width: avatarMeta.size,
        height: avatarMeta.size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(avatarMeta.radius),
          child: avatarMeta.hasImage
              ? shamellCachedNetworkImage(
                  avatarMeta.imageUrl,
                  context: context,
                  fit: BoxFit.cover,
                  logicalWidth: avatarMeta.size,
                  logicalHeight: avatarMeta.size,
                )
              : Container(
                  color: theme.colorScheme.primary.withValues(
                    alpha: isDark
                        ? avatarMeta.fallbackDarkAlpha
                        : avatarMeta.fallbackLightAlpha,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    avatarMeta.fallbackText,
                    style: TextStyle(
                      fontWeight: avatarMeta.fallbackFontWeight,
                      fontSize: avatarMeta.fallbackFontSize,
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
                    momentAuthorNameLabel(
                      authorName: authorName,
                      isLocal: isLocal,
                      isArabic: l.isArabic,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: textChrome.authorNameWeight,
                      color: nameColor,
                    ),
                  ),
                  if (hasOfficialReply)
                    Padding(
                      padding: EdgeInsets.only(top: contextLineChrome.topGap),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            contextLineChrome.officialReplyIcon,
                            size: contextLineChrome.iconSize,
                            color: theme.colorScheme.primary.withValues(
                                alpha: contextLineChrome.officialAlpha),
                          ),
                          SizedBox(width: contextLineChrome.iconGap),
                          Builder(
                            builder: (ctx) {
                              final label = momentOfficialReplyLabel(
                                hasOfficialReply: hasOfficialReply,
                                accountName: originAcc?.name ?? originAccId,
                                isArabic: l.isArabic,
                              );
                              if (label == null) {
                                return const SizedBox.shrink();
                              }
                              return InkWell(
                                onTap: () {
                                  if (originAccId.isEmpty) return;
                                  _openOfficialFromMoment(originAccId, null);
                                },
                                child: Text(
                                  label,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: contextLineChrome.fontSize,
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: contextLineChrome.officialAlpha,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  if (audienceMeta != null)
                    _buildMomentAudiencePill(audienceMeta, theme),
                ],
              ),
            ),
          ],
        ),
      );

      if (originAcc != null) {
        final originShareLabel = momentOfficialShareLabel(
          accountName: originAcc.name,
          featured: originAcc.featured,
          isArabic: l.isArabic,
        );
        content.add(
          Padding(
            padding: EdgeInsets.only(top: contextLineChrome.topGap),
            child: InkWell(
              onTap: () {
                if (originAccId.isEmpty) return;
                _openOfficialFromMoment(originAccId, null);
              },
              child: Text(
                originShareLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: contextLineChrome.fontSize,
                  color: theme.colorScheme.primary
                      .withValues(alpha: contextLineChrome.officialAlpha),
                ),
              ),
            ),
          ),
        );
      }

      // Small hint when this Moment was shared from a SyrChat mini‑app.
      final miniMeta = _miniAppFromText(text);
      if (miniMeta != null) {
        final miniLabel = miniMeta.title(isArabic: l.isArabic);
        content.add(
          Padding(
            padding: EdgeInsets.only(top: contextLineChrome.topGap),
            child: Text(
              momentMiniProgramShareLabel(
                title: miniLabel,
                isArabic: l.isArabic,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: contextLineChrome.fontSize,
                color: theme.colorScheme.onSurface
                    .withValues(alpha: contextLineChrome.miniProgramAlpha),
              ),
            ),
          ),
        );
      }

      if (isRedPacket) {
        content.add(
          Padding(
            padding: EdgeInsets.only(top: contextLineChrome.topGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  contextLineChrome.greenPaketIcon,
                  size: contextLineChrome.iconSize,
                  color: theme.colorScheme.primary.withValues(
                    alpha: theme.brightness == Brightness.dark
                        ? contextLineChrome.greenPaketIconDarkAlpha
                        : contextLineChrome.greenPaketIconLightAlpha,
                  ),
                ),
                SizedBox(width: contextLineChrome.iconGap),
                Text(
                  momentGreenPaketLabel(isArabic: l.isArabic),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: contextLineChrome.fontSize,
                    fontWeight: contextLineChrome.accentFontWeight,
                    color: theme.colorScheme.onSurface.withValues(
                        alpha: contextLineChrome.greenPaketLabelAlpha),
                  ),
                ),
              ],
            ),
          ),
        );
        final originItemId =
            (p['origin_official_item_id'] ?? '').toString().trim();
        final campaignLabel = momentGreenPaketCampaignLabel(
          campaignId: originItemId,
          isArabic: l.isArabic,
        );
        if (campaignLabel != null) {
          content.add(
            Padding(
              padding: EdgeInsets.only(top: contextLineChrome.topGap),
              child: Text(
                campaignLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: contextLineChrome.fontSize,
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: contextLineChrome.campaignAlpha),
                ),
              ),
            ),
          );
        }
      }

      content.add(SizedBox(height: contextLineChrome.bodyBottomGap));

      var displayText = text;
      if (displayText.isNotEmpty) {
        displayText = stripMiniProgramDeepLinksFromText(
          stripOfficialDeepLinksFromText(displayText),
        );
      }

      if (displayText.isNotEmpty) {
        final tags = momentHashtagMetasFromText(displayText);
        content.add(
          Text(
            displayText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: textChrome.bodyFontSize,
              fontWeight: textChrome.bodyWeight,
            ),
          ),
        );
        if (tags.isNotEmpty) {
          content.add(SizedBox(height: textChrome.topicTopGap));
          content.add(
            Wrap(
              spacing: textChrome.topicSpacing,
              runSpacing: textChrome.topicRunSpacing,
              children: tags.map((tag) {
                return InkWell(
                  borderRadius: BorderRadius.circular(textChrome.topicRadius),
                  onTap: () {
                    Perf.action(tag.perfKey);
                    _openTopic(tag.tag);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: textChrome.topicVerticalPadding,
                    ),
                    child: Text(
                      tag.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: textChrome.topicFontSize,
                        fontWeight: textChrome.topicWeight,
                        color: isDark
                            ? theme.colorScheme.primary
                            : WeChatPalette.linkBlue,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }
        content.add(SizedBox(height: textChrome.bottomGap));
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
        content
            .add(SizedBox(height: contentChrome.officialAttachmentBottomGap));
      }

      final miniAppAttachment = _buildMiniAppAttachment(p, text, theme, l);
      if (miniAppAttachment != null) {
        content.add(miniAppAttachment);
        content.add(
          SizedBox(height: contentChrome.miniProgramAttachmentBottomGap),
        );
      }

      if (imageWidget != null) {
        content.add(imageWidget);
        content.add(SizedBox(height: contentChrome.mediaBottomGap));
      }

      final locationMeta = momentLocationMetaFor(
        (p['location_label'] ?? '').toString(),
      );
      if (locationMeta != null) {
        final linkColor =
            isDark ? theme.colorScheme.primary : WeChatPalette.linkBlue;
        content.add(
          InkWell(
            borderRadius: BorderRadius.circular(locationMeta.radius),
            onTap: () => Perf.action(locationMeta.perfKey),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: locationMeta.verticalPadding,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    locationMeta.icon,
                    size: locationMeta.iconSize,
                    color: linkColor,
                  ),
                  SizedBox(width: locationMeta.iconGap),
                  Flexible(
                    child: Text(
                      locationMeta.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: locationMeta.fontSize,
                        fontWeight: locationMeta.fontWeight,
                        color: linkColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        content.add(SizedBox(height: locationMeta.bottomGap));
      }

      content.add(
        Row(
          children: [
            if (footerMeta.timestampLabel.isNotEmpty)
              Text(
                footerMeta.timestampLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: footerMeta.timestampFontSize,
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: footerMeta.timestampAlpha),
                ),
              ),
            if (footerMeta.showOfficialReplyIndicator)
              Padding(
                padding: EdgeInsets.only(
                  left: footerMeta.replyIndicatorLeftGap,
                ),
                child: Container(
                  width: footerMeta.replyIndicatorSize,
                  height: footerMeta.replyIndicatorSize,
                  decoration: BoxDecoration(
                    color: footerMeta.replyIndicatorColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            const Spacer(),
            if (footerMeta.canOpenActions)
              Builder(
                builder: (btnCtx) {
                  final bg = isDark
                      ? theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: footerMeta.actionButtonDarkFillAlpha,
                        )
                      : WeChatPalette.searchFill;
                  return Tooltip(
                    message: footerMeta.actionTooltip,
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(footerMeta.actionButtonRadius),
                      onTap: () {
                        Perf.action(footerMeta.actionPerfKey);
                        _showMomentPostActionsPopover(btnCtx, p);
                      },
                      child: Container(
                        width: footerMeta.actionButtonWidth,
                        height: footerMeta.actionButtonHeight,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(
                            footerMeta.actionButtonRadius,
                          ),
                          border: Border.all(
                            color: theme.dividerColor.withValues(
                              alpha: footerMeta.actionButtonBorderAlpha,
                            ),
                            width: footerMeta.actionButtonBorderWidth,
                          ),
                        ),
                        child: Icon(
                          footerMeta.actionIcon,
                          size: footerMeta.actionIconSize,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: footerMeta.actionIconAlpha),
                        ),
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
      final socialMeta = momentSocialSummaryMeta(
        likeCount: likes,
        commentCount: commentCount,
        loadedPreviewCount: previewComments.length,
        likedByMe: likedByMe,
      );
      if (socialMeta.showSocial) {
        final socialChrome = momentSocialBubbleChromeMeta();
        final bubbleBg = isDark
            ? theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: socialChrome.darkBubbleAlpha)
            : WeChatPalette.searchFill;
        final bubbleBorder = theme.dividerColor.withValues(
          alpha: isDark
              ? socialChrome.darkBorderAlpha
              : socialChrome.lightBorderAlpha,
        );
        final baseStyle = theme.textTheme.bodySmall?.copyWith(
              fontSize: socialChrome.baseFontSize,
              color: theme.colorScheme.onSurface
                  .withValues(alpha: socialChrome.baseTextAlpha),
            ) ??
            TextStyle(
              fontSize: socialChrome.baseFontSize,
              color: theme.colorScheme.onSurface
                  .withValues(alpha: socialChrome.baseTextAlpha),
            );
        final authorStyle = baseStyle.copyWith(
          fontWeight: socialChrome.authorWeight,
          color: nameColor,
        );

        Widget inlineComment(Map<String, dynamic> c) {
          final you = l.isArabic ? 'أنت' : 'You';
          final meta = momentCommentPreviewMeta(
            authorName: (c['author_name'] ?? '').toString(),
            text: (c['text'] ?? '').toString(),
            replyToId: (c['reply_to'] ?? '').toString(),
            replyToName: (c['reply_to_name'] ?? '').toString(),
            youLabel: you,
            myPseudonym: _myMomentsPseudonym,
          );
          if (meta == null) return const SizedBox.shrink();
          final commentId = (c['id'] ?? '').toString().trim();

          final spans = <TextSpan>[
            TextSpan(text: meta.authorLabel, style: authorStyle),
            if (meta.hasReply) ...[
              TextSpan(
                text: l.isArabic ? ' ردًا على ' : ' replied to ',
                style: baseStyle,
              ),
              TextSpan(text: meta.replyToLabel, style: authorStyle),
            ],
            TextSpan(text: ': ${meta.text}'),
          ];

          Offset? downPos;
          return InkWell(
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
                      replyToName: meta.authorLabel,
                    );
                  }
                : null,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: socialChrome.commentVerticalPadding,
              ),
              child: RichText(
                maxLines: socialChrome.commentMaxLines,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: baseStyle,
                  children: spans,
                ),
              ),
            ),
          );
        }

        final preview =
            previewComments.take(socialMeta.visiblePreviewCount).toList();
        final likeIcon = socialMeta.likeIcon;
        final likeColor = likedByMe
            ? (isDark ? theme.colorScheme.secondary : WeChatPalette.green)
            : theme.colorScheme.onSurface
                .withValues(alpha: socialChrome.unlikedIconAlpha);

        content.add(
          Padding(
            padding: EdgeInsets.only(top: socialChrome.topGap),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: socialChrome.horizontalPadding,
                    vertical: socialChrome.verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    border: Border.symmetric(
                      horizontal: BorderSide(
                        color: bubbleBorder,
                        width: socialChrome.borderWidth,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (socialMeta.showLikeRow) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              likeIcon,
                              size: socialChrome.likeIconSize,
                              color: likeColor,
                            ),
                            SizedBox(width: socialChrome.likeIconGap),
                            Expanded(
                              child: Builder(
                                builder: (ctx) {
                                  final you = l.isArabic ? 'أنت' : 'You';
                                  final names = momentLikerLabels(
                                    likedBy: likedByList,
                                    likedByMe: likedByMe,
                                    myPseudonym: _myMomentsPseudonym ?? '',
                                    youLabel: you,
                                  );
                                  final overflow = momentLikerOverflowLabel(
                                    likeCount: likes,
                                    visibleLabelCount: names.length,
                                    isArabic: l.isArabic,
                                  );

                                  if (names.isEmpty) {
                                    return Text(
                                      momentLikeCountLabel(
                                        likeCount: likes,
                                        isArabic: l.isArabic,
                                      ),
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
                                  if (overflow != null) {
                                    if (spans.isNotEmpty) {
                                      spans.add(TextSpan(
                                        text: sep,
                                        style: baseStyle,
                                      ));
                                    }
                                    spans.add(TextSpan(
                                      text: overflow,
                                      style: baseStyle,
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
                        if (socialMeta.showDivider)
                          Divider(
                            height: socialChrome.dividerHeight,
                            thickness: socialChrome.dividerThickness,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: socialChrome.dividerAlpha),
                          ),
                      ],
                      if (preview.isNotEmpty) ...[
                        for (final c in preview) inlineComment(c),
                        if (socialMeta.showAllCommentsLink)
                          Padding(
                            padding: EdgeInsets.only(
                                top: socialChrome.commentsLinkTopGap),
                            child: InkWell(
                              onTap: postId.isNotEmpty
                                  ? () => unawaited(_openComments(p))
                                  : null,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: socialChrome.commentVerticalPadding,
                                ),
                                child: Text(
                                  momentCommentLinkLabel(
                                    commentCount: socialMeta.commentLinkCount,
                                    showAll: true,
                                    isArabic: l.isArabic,
                                  ),
                                  style: baseStyle.copyWith(
                                    color:
                                        theme.colorScheme.onSurface.withValues(
                                      alpha: socialChrome.commentLinkAlpha,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ] else if (socialMeta.showCommentCountOnlyLink) ...[
                        InkWell(
                          onTap: postId.isNotEmpty
                              ? () => unawaited(_openComments(p))
                              : null,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: socialChrome.commentVerticalPadding,
                            ),
                            child: Text(
                              momentCommentLinkLabel(
                                commentCount: socialMeta.commentLinkCount,
                                showAll: false,
                                isArabic: l.isArabic,
                              ),
                              style: baseStyle.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: socialChrome.commentLinkAlpha,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PositionedDirectional(
                  start: socialChrome.pointerStart,
                  top: socialChrome.pointerTop,
                  child: Transform.rotate(
                    angle: socialChrome.pointerRotationRadians,
                    child: Container(
                      width: socialChrome.pointerSize,
                      height: socialChrome.pointerSize,
                      decoration: BoxDecoration(
                        color: bubbleBg,
                        border: Border(
                          top: BorderSide(
                            color: bubbleBorder,
                            width: socialChrome.borderWidth,
                          ),
                          left: BorderSide(
                            color: bubbleBorder,
                            width: socialChrome.borderWidth,
                          ),
                        ),
                      ),
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
          padding: EdgeInsets.symmetric(
            horizontal: feedListChrome.postHorizontalPadding,
            vertical: feedListChrome.postVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surface
                : feedListChrome.lightSurfaceColor,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              SizedBox(width: feedListChrome.postAvatarGap),
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
      final activeMiniProgramId = _activeMiniProgramId();
      if (activeMiniProgramId.isNotEmpty) {
        base = base.where((p) {
          final mid =
              (p['mini_program_id'] ?? '').toString().trim().toLowerCase();
          if (mid == activeMiniProgramId) return true;
          final text = ((p['text'] ?? p['content'] ?? '')).toString();
          final target = parseMiniProgramDeepLinkFromText(text);
          return (target?.id ?? '').trim().toLowerCase() == activeMiniProgramId;
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
      if (_filterRedpacketOnly) {
        base = base.where((p) {
          final t = ((p['text'] ?? p['content'] ?? '')).toString();
          return _isRedPacketText(t);
        });
      }
      if (_filterMiniProgramOnly) {
        base = base.where((p) {
          final t = ((p['text'] ?? p['content'] ?? '')).toString();
          final mid = (p['mini_program_id'] ?? '').toString().trim();
          if (mid.isNotEmpty) return true;
          return parseMiniProgramDeepLinkFromText(t) != null ||
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
          if (parseOfficialDeepLinkFromText(t) != null) {
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
        final emptyMeta = momentFeedEmptyMetaFor(
          isArabic: l.isArabic,
          isFriendTimeline: isFriendTimeline,
        );
        return Padding(
          padding: EdgeInsets.all(feedListChrome.emptyPadding),
          child: Text(
            emptyMeta.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: feedListChrome.emptyTextAlpha,
              ),
            ),
          ),
        );
      }

      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: feedListChrome.listTopPadding),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => Divider(
          height: feedListChrome.separatorHeight,
          thickness: feedListChrome.separatorThickness,
          indent: feedListChrome.separatorIndent,
          color: isDark ? theme.dividerColor : WeChatPalette.divider,
        ),
        itemBuilder: (_, i) {
          final p = filtered[i];
          return buildPost(p);
        },
      );
    }

    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;
    final isFriendTimeline = (widget.timelineAuthorId ?? '').trim().isNotEmpty;
    final showInlineComposer = _enableInlineComposer;
    final showAdvancedFilters = _enableAdvancedFilters;

    final body = _loading
        ? const ShamellSkeletonList(itemCount: 5)
        : SingleChildScrollView(
            controller: _scrollCtrl,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWeChatCoverHeader(l, theme),
                Container(
                  color: isDark
                      ? theme.colorScheme.surface
                      : feedListChrome.lightSurfaceColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!showInlineComposer &&
                          widget.showComposer &&
                          !isFriendTimeline)
                        _buildMomentsQuickComposer(l, theme),
                      if (showInlineComposer &&
                          widget.showComposer &&
                          !isFriendTimeline)
                        Container(
                          key: _composerKey,
                          padding: EdgeInsets.all(
                            inlineComposerText.panelPadding,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    inlineComposerText.titleIcon,
                                    size: inlineComposerText.titleIconSize,
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: inlineComposerText.titleIconAlpha,
                                    ),
                                  ),
                                  SizedBox(
                                    width: inlineComposerText.titleIconGap,
                                  ),
                                  Text(
                                    inlineComposerText.titleLabel,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight:
                                          inlineComposerText.titleWeight,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: inlineComposerText.titleBottomGap,
                              ),
                              TextField(
                                controller: _postCtrl,
                                focusNode: _postFocus,
                                maxLines: inlineComposerText.maxLines,
                                minLines: inlineComposerText.minLines,
                                decoration: InputDecoration(
                                  hintText: inlineComposerText.textHint,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              SizedBox(
                                height: inlineComposerText.textFieldBottomGap,
                              ),
                              _buildAudienceSummaryPill(l, theme),
                              SizedBox(
                                height: visibilityChipChrome.summaryBottomGap,
                              ),
                              Wrap(
                                spacing: visibilityChipChrome.wrapSpacing,
                                runSpacing: visibilityChipChrome.wrapRunSpacing,
                                children: momentComposerVisibilityOptionMetas(
                                  isArabic: l.isArabic,
                                  selectedScope: _visibilityScope,
                                ).map((meta) {
                                  final iconColor = meta.selected
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: visibilityChipChrome
                                              .selectedIconAlpha,
                                        )
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: visibilityChipChrome
                                              .unselectedIconAlpha,
                                        );
                                  return ChoiceChip(
                                    avatar: Icon(
                                      meta.icon,
                                      size: visibilityChipChrome.iconSize,
                                      color: iconColor,
                                    ),
                                    label: Text(meta.label),
                                    selected: meta.selected,
                                    onSelected: (sel) {
                                      if (!sel) return;
                                      setState(() {
                                        _visibilityScope = meta.scope;
                                        if (meta.clearsAudienceTag) {
                                          _visibilityTag = null;
                                          _visibilityTagMode = 'only';
                                          _visibilityTagCtrl.clear();
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              SizedBox(
                                height: visibilityChipChrome.helperTopGap,
                              ),
                              Text(
                                composerAudienceCopy.privacyHelperLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: visibilityChipChrome.helperFontSize,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: visibilityChipChrome.helperAlpha,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: visibilityChipChrome.helperBottomGap,
                              ),
                              if (_availableAudienceTags.isNotEmpty) ...[
                                Wrap(
                                  spacing: audienceTagChipChrome.wrapSpacing,
                                  runSpacing:
                                      audienceTagChipChrome.wrapRunSpacing,
                                  children:
                                      momentComposerAudienceTagActionMetas(
                                    tags: _availableAudienceTags,
                                    selectedTag: _visibilityTag ?? '',
                                    selectedTagMode: _visibilityTagMode,
                                    isArabic: l.isArabic,
                                  ).map((meta) {
                                    return FilterChip(
                                      avatar: Icon(
                                        meta.icon,
                                        size: audienceTagChipChrome.iconSize,
                                      ),
                                      label: Text(meta.label),
                                      selected: meta.selected,
                                      onSelected: (sel) {
                                        setState(() {
                                          if (sel) {
                                            _visibilityTag = meta.tag;
                                            _visibilityTagMode = meta.tagMode;
                                            _visibilityScope = 'friends';
                                            _visibilityTagCtrl.text = meta.tag;
                                          } else if (_visibilityTag ==
                                                  meta.tag &&
                                              _visibilityTagMode ==
                                                  meta.tagMode) {
                                            _visibilityTag = null;
                                            _visibilityTagCtrl.clear();
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                                SizedBox(
                                  height: audienceTagChipChrome.bottomGap,
                                ),
                              ],
                              TextField(
                                controller: _visibilityTagCtrl,
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: Icon(
                                    composerAudienceCopy.tagFieldIcon,
                                    size:
                                        audienceFieldChrome.fieldPrefixIconSize,
                                  ),
                                  labelText: composerAudienceCopy.tagFieldLabel,
                                  hintText: composerAudienceCopy.tagFieldHint,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      audienceFieldChrome.fieldBorderRadius,
                                    ),
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
                                SizedBox(
                                  height: audienceFieldChrome.onboardingTopGap,
                                ),
                                Container(
                                  padding: EdgeInsets.all(
                                    audienceFieldChrome.onboardingPadding,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface.withValues(
                                      alpha: audienceFieldChrome
                                          .onboardingBackgroundAlpha,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      audienceFieldChrome.onboardingRadius,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        composerAudienceCopy.onboardingIcon,
                                        size: audienceFieldChrome
                                            .onboardingIconSize,
                                        color: theme.colorScheme.primary
                                            .withValues(
                                          alpha: audienceFieldChrome
                                              .onboardingIconAlpha,
                                        ),
                                      ),
                                      SizedBox(
                                        width: audienceFieldChrome
                                            .onboardingIconGap,
                                      ),
                                      Expanded(
                                        child: Text(
                                          composerAudienceCopy.onboardingHint,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontSize: audienceFieldChrome
                                                .onboardingFontSize,
                                            color: theme.colorScheme.onSurface
                                                .withValues(
                                              alpha: audienceFieldChrome
                                                  .onboardingTextAlpha,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: audienceFieldChrome
                                            .onboardingDismissVisualDensity,
                                        padding: audienceFieldChrome
                                            .onboardingDismissPadding,
                                        constraints: BoxConstraints(
                                          minWidth: audienceFieldChrome
                                              .onboardingDismissMinSize,
                                          minHeight: audienceFieldChrome
                                              .onboardingDismissMinSize,
                                        ),
                                        tooltip: composerAudienceCopy
                                            .onboardingDismissTooltip,
                                        icon: Icon(
                                          Icons.close,
                                          size: audienceFieldChrome
                                              .onboardingDismissIconSize,
                                          color: theme.colorScheme.onSurface
                                              .withValues(
                                            alpha: audienceFieldChrome
                                                .onboardingDismissIconAlpha,
                                          ),
                                        ),
                                        onPressed: _dismissAudienceHint,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (_availableAudienceTags.isNotEmpty) ...[
                                SizedBox(
                                  height: audienceFieldChrome.suggestedTopGap,
                                ),
                                Text(
                                  composerAudienceCopy.suggestedTagsLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: audienceFieldChrome
                                        .suggestedLabelFontSize,
                                    color:
                                        theme.colorScheme.onSurface.withValues(
                                      alpha: audienceFieldChrome
                                          .suggestedLabelAlpha,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height:
                                      audienceFieldChrome.suggestedChipsTopGap,
                                ),
                                Wrap(
                                  spacing:
                                      audienceFieldChrome.suggestedWrapSpacing,
                                  runSpacing: audienceFieldChrome
                                      .suggestedWrapRunSpacing,
                                  children:
                                      momentComposerSuggestedAudienceTagMetas(
                                    tags: _availableAudienceTags,
                                    selectedTag: _visibilityTag ?? '',
                                  ).map((meta) {
                                    return ActionChip(
                                      avatar: Icon(
                                        meta.icon,
                                        size: audienceFieldChrome
                                            .suggestedChipIconSize,
                                      ),
                                      label: Text(meta.label),
                                      visualDensity: audienceFieldChrome
                                          .suggestedChipVisualDensity,
                                      side: meta.selected
                                          ? BorderSide(
                                              color: theme.colorScheme.primary
                                                  .withValues(
                                                alpha: audienceFieldChrome
                                                    .suggestedSelectedBorderAlpha,
                                              ),
                                            )
                                          : null,
                                      onPressed: () {
                                        setState(() {
                                          _visibilityTag = meta.tag;
                                          _visibilityTagMode = 'only';
                                          _visibilityScope = 'friends';
                                          _visibilityTagCtrl.text = meta.tag;
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                              ..._buildTrendingTopicComposerRows(l, theme),
                              if (composerOfficialDirectoryLink != null &&
                                  widget.onOpenOfficialDirectory != null) ...[
                                SizedBox(
                                  height: composerOfficialDirectoryLink.topGap,
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(
                                    composerOfficialDirectoryLink.radius,
                                  ),
                                  onTap: () {
                                    Perf.action(
                                      composerOfficialDirectoryLink.perfKey,
                                    );
                                    widget.onOpenOfficialDirectory!(context);
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        composerOfficialDirectoryLink.icon,
                                        size: composerOfficialDirectoryLink
                                            .iconSize,
                                        color: theme.colorScheme.primary,
                                      ),
                                      SizedBox(
                                        width: composerOfficialDirectoryLink
                                            .iconGap,
                                      ),
                                      Text(
                                        composerOfficialDirectoryLink.label,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontSize:
                                              composerOfficialDirectoryLink
                                                  .fontSize,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      SizedBox(
                                        width: composerOfficialDirectoryLink
                                            .trailingGap,
                                      ),
                                      Icon(
                                        composerOfficialDirectoryLink
                                            .trailingIcon,
                                        size: composerOfficialDirectoryLink
                                            .trailingIconSize,
                                        color: theme.colorScheme.primary
                                            .withValues(
                                          alpha: composerOfficialDirectoryLink
                                              .trailingIconAlpha,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              SizedBox(
                                height: composerMediaAction.controlsTopGap,
                              ),
                              if (_pendingImage != null)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        composerMediaAction.previewBorderRadius,
                                      ),
                                      child: Image.memory(
                                        _pendingImage!,
                                        height:
                                            composerMediaAction.previewHeight,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        icon: Icon(
                                          composerMediaAction.removePhotoIcon,
                                          size: composerMediaAction
                                              .removePhotoIconSize,
                                        ),
                                        tooltip: composerMediaAction
                                            .removePhotoTooltip,
                                        onPressed: () {
                                          Perf.action(
                                            composerMediaAction
                                                .removePhotoPerfKey,
                                          );
                                          _clearPendingImage();
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      height:
                                          composerMediaAction.previewBottomGap,
                                    ),
                                  ],
                                ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      composerMediaAction.addPhotoIcon,
                                      size:
                                          composerMediaAction.addPhotoIconSize,
                                    ),
                                    tooltip:
                                        composerMediaAction.addPhotoTooltip,
                                    onPressed: () {
                                      Perf.action(
                                        composerMediaAction.addPhotoPerfKey,
                                      );
                                      unawaited(_pickImage());
                                    },
                                  ),
                                  const Spacer(),
                                  PrimaryButton(
                                    label: composerMediaAction.publishLabel,
                                    icon: composerMediaAction.publishIcon,
                                    onPressed: inlinePublishState.canPublish
                                        ? () {
                                            Perf.action(
                                              composerMediaAction
                                                  .publishPerfKey,
                                            );
                                            unawaited(_addPost());
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: pageChrome.inlineComposerBottomGap),
                      if (inlinePublishState.miniProgramId.isNotEmpty)
                        _buildMiniProgramContextBar(
                          l,
                          miniProgramId: inlinePublishState.miniProgramId,
                        ),
                      if (inlinePublishState.miniProgramId.isNotEmpty)
                        SizedBox(
                          height: pageChrome.miniProgramContextBottomGap,
                        ),
                      if (!isFriendTimeline) _buildOfficialImpactStrip(l),
                      if (showAdvancedFilters && !isFriendTimeline)
                        _buildMomentsDiscoveryFilterBar(l),
                      if (showAdvancedFilters && !isFriendTimeline)
                        _buildOfficialFiltersRow(l),
                      // Topic bar – SyrChat-style Moments topics (Wallet)
                      if (showAdvancedFilters && !isFriendTimeline)
                        _buildTopicBar(l),
                      _buildFeedList(),
                    ],
                  ),
                ),
              ],
            ),
          );

    final pageTitle = momentPageTitleLabel(
      isArabic: l.isArabic,
      isFriendTimeline: isFriendTimeline,
      miniProgramMomentsTitle: _miniProgramContextMomentsTitle(l),
      timelineAuthorName: widget.timelineAuthorName ?? '',
      timelineAuthorId: widget.timelineAuthorId ?? '',
    );
    final appBarAction = momentPageAppBarActionMeta(
      showComposer: widget.showComposer,
      isFriendTimeline: isFriendTimeline,
      isArabic: l.isArabic,
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(pageTitle),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          if (appBarAction.showComposerAction)
            GestureDetector(
              onLongPress: () {
                Perf.action(appBarAction.quickOpenPerfKey);
                unawaited(_openWeChatComposer());
              },
              child: IconButton(
                tooltip: appBarAction.tooltip,
                icon: Icon(appBarAction.icon),
                onPressed: () async {
                  Perf.action(appBarAction.openSheetPerfKey);
                  await showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) {
                      final sheetTheme = Theme.of(ctx);
                      final l2 = L10n.of(ctx);
                      final isSheetDark =
                          sheetTheme.brightness == Brightness.dark;
                      final sheetBg = isSheetDark
                          ? sheetTheme.colorScheme.surface
                          : WeChatPalette.background;
                      final sheetChrome = momentComposerSheetChromeMeta();
                      final rowBg = sheetTheme.colorScheme.surface.withValues(
                        alpha: isSheetDark
                            ? sheetChrome.darkRowAlpha
                            : sheetChrome.lightRowAlpha,
                      );
                      final dividerColor = sheetTheme.dividerColor.withValues(
                        alpha: isSheetDark
                            ? sheetChrome.darkDividerAlpha
                            : sheetChrome.lightDividerAlpha,
                      );
                      final sheetMeta = momentComposerSheetMeta(
                        isArabic: l2.isArabic,
                      );

                      Widget section(List<Widget> rows) {
                        return Container(
                          color: rowBg,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Divider(
                                height: sheetChrome.dividerHeight,
                                thickness: sheetChrome.dividerThickness,
                                color: dividerColor,
                              ),
                              for (var i = 0; i < rows.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: sheetChrome.dividerHeight,
                                    thickness: sheetChrome.dividerThickness,
                                    indent: sheetChrome.innerDividerIndent,
                                    color: dividerColor,
                                  ),
                                rows[i],
                              ],
                              Divider(
                                height: sheetChrome.dividerHeight,
                                thickness: sheetChrome.dividerThickness,
                                color: dividerColor,
                              ),
                            ],
                          ),
                        );
                      }

                      Future<void> runSheetAction(
                        MomentComposerSheetActionMeta action,
                      ) async {
                        Perf.action(action.perfKey);
                        switch (action.kind) {
                          case MomentComposerSheetActionKind.text:
                            await _openWeChatComposer();
                            break;
                          case MomentComposerSheetActionKind.camera:
                            final picked = await _pickImageBytes(
                              source: ImageSource.camera,
                            );
                            if (picked == null) return;
                            if (!mounted) return;
                            await _openWeChatComposer(
                              initialImageBytes: picked.bytes,
                              initialImageMime: picked.mime,
                            );
                            break;
                          case MomentComposerSheetActionKind.album:
                            final picked = await _pickImageBytes(
                              source: ImageSource.gallery,
                            );
                            if (picked == null) return;
                            if (!mounted) return;
                            await _openWeChatComposer(
                              initialImageBytes: picked.bytes,
                              initialImageMime: picked.mime,
                            );
                            break;
                        }
                      }

                      Widget actionRow({
                        required IconData icon,
                        required String title,
                        required Future<void> Function() onTap,
                      }) {
                        return InkWell(
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await onTap();
                          },
                          child: SizedBox(
                            height: sheetChrome.rowHeight,
                            child: Row(
                              children: [
                                SizedBox(width: sheetChrome.edgeGap),
                                Icon(icon, size: sheetChrome.iconSize),
                                SizedBox(width: sheetChrome.iconTextGap),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sheetTheme.textTheme.bodyLarge
                                        ?.copyWith(
                                      fontSize: sheetChrome.labelFontSize,
                                      fontWeight: sheetChrome.actionFontWeight,
                                    ),
                                  ),
                                ),
                                SizedBox(width: sheetChrome.edgeGap),
                              ],
                            ),
                          ),
                        );
                      }

                      return SafeArea(
                        top: false,
                        child: Container(
                          color: sheetBg,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              section(
                                sheetMeta.actions
                                    .map(
                                      (action) => actionRow(
                                        icon: action.icon,
                                        title: action.label,
                                        onTap: () => runSheetAction(action),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                              SizedBox(height: sheetChrome.sectionGap),
                              section([
                                InkWell(
                                  onTap: () => Navigator.of(ctx).pop(),
                                  child: SizedBox(
                                    height: sheetChrome.rowHeight,
                                    width: double.infinity,
                                    child: Center(
                                      child: Text(
                                        sheetMeta.cancelLabel,
                                        style: sheetTheme.textTheme.bodyLarge
                                            ?.copyWith(
                                          fontSize: sheetChrome.labelFontSize,
                                          fontWeight:
                                              sheetChrome.cancelFontWeight,
                                          color: sheetTheme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
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

  Widget _momentsFilterButton({
    IconData? icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chrome = momentFilterStripChromeMeta();
    final color = selected
        ? WeChatPalette.green
        : theme.colorScheme.onSurface.withValues(
            alpha: isDark
                ? chrome.unselectedTextDarkAlpha
                : chrome.unselectedTextLightAlpha,
          );
    final fill = selected
        ? WeChatPalette.green.withValues(
            alpha: isDark
                ? chrome.selectedFillDarkAlpha
                : chrome.selectedFillLightAlpha,
          )
        : Colors.transparent;
    return Padding(
      padding: EdgeInsetsDirectional.only(end: chrome.buttonEndSpacing),
      child: InkWell(
        borderRadius: BorderRadius.circular(chrome.buttonRadius),
        onTap: onTap,
        child: Container(
          height: chrome.buttonHeight,
          padding: EdgeInsets.symmetric(
            horizontal: chrome.buttonHorizontalPadding,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(chrome.buttonRadius),
            border: Border(
              bottom: BorderSide(
                color: selected ? WeChatPalette.green : Colors.transparent,
                width: chrome.selectedUnderlineWidth,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: chrome.iconSize, color: color),
                SizedBox(width: chrome.iconGap),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: chrome.labelFontSize,
                  fontWeight: selected
                      ? chrome.selectedLabelWeight
                      : chrome.unselectedLabelWeight,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _momentsFilterStrip({
    required List<Widget> children,
    bool topBorder = true,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chrome = momentFilterStripChromeMeta();
    final borderColor = theme.dividerColor.withValues(
      alpha: isDark ? chrome.darkBorderAlpha : chrome.lightBorderAlpha,
    );
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: topBorder
            ? Border(
                top: BorderSide(color: borderColor, width: chrome.borderWidth),
                bottom:
                    BorderSide(color: borderColor, width: chrome.borderWidth),
              )
            : Border(
                bottom:
                    BorderSide(color: borderColor, width: chrome.borderWidth),
              ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: chrome.horizontalPadding,
          vertical: chrome.verticalPadding,
        ),
        child: Row(children: children),
      ),
    );
  }

  Widget _buildMomentMediaFrame({
    required MomentMediaLayoutMeta mediaMeta,
    required Widget child,
  }) {
    if (!mediaMeta.hasMedia) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final width = mediaMeta.widthFor(constraints.maxWidth);
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: width, child: child),
        );
      },
    );
  }

  List<Widget> _buildTrendingTopicComposerRows(L10n l, ThemeData theme) {
    final sectionMeta = momentComposerTrendingTopicsSectionMeta(
      isArabic: l.isArabic,
    );
    final topics = momentTrendingTopicMetas(
      isArabic: l.isArabic,
      rawTopics: _trendingTopics,
    );
    if (topics.isEmpty) return const <Widget>[];

    return <Widget>[
      SizedBox(height: sectionMeta.topGap),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sectionMeta.icon,
            size: sectionMeta.headerIconSize,
            color: theme.colorScheme.primary.withValues(
              alpha: sectionMeta.headerIconAlpha,
            ),
          ),
          SizedBox(width: sectionMeta.headerIconGap),
          Text(
            sectionMeta.titleLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: sectionMeta.titleFontSize,
              fontWeight: sectionMeta.titleWeight,
              color: theme.colorScheme.onSurface.withValues(
                alpha: sectionMeta.titleAlpha,
              ),
            ),
          ),
        ],
      ),
      SizedBox(height: sectionMeta.chipsTopGap),
      Wrap(
        spacing: sectionMeta.chipSpacing,
        runSpacing: sectionMeta.chipRunSpacing,
        children: topics.take(sectionMeta.visibleTopicLimit).map((topic) {
          return ActionChip(
            avatar: topic.icon == null
                ? null
                : Icon(
                    topic.icon,
                    size: sectionMeta.chipIconSize,
                    color: theme.colorScheme.primary.withValues(
                      alpha: sectionMeta.chipIconAlpha,
                    ),
                  ),
            label: Text(topic.label),
            visualDensity: sectionMeta.chipVisualDensity,
            onPressed: () {
              Perf.action(topic.perfKey);
              _openTopic(topic.tag);
            },
          );
        }).toList(growable: false),
      ),
    ];
  }

  Widget _buildOfficialImpactStrip(L10n l) {
    final stripMeta = momentOfficialImpactStripMeta(isArabic: l.isArabic);
    final metas = momentOfficialImpactMetas(
      isArabic: l.isArabic,
      stats: _myOfficialStats,
    );
    if (metas.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final maxPillWidth =
        MediaQuery.sizeOf(context).width - stripMeta.maxWidthInset;
    final borderColor = theme.dividerColor.withValues(
      alpha: theme.brightness == Brightness.dark
          ? stripMeta.darkBorderAlpha
          : stripMeta.lightBorderAlpha,
    );

    Widget pill(MomentOfficialImpactMeta meta) {
      return Container(
        constraints: BoxConstraints(maxWidth: maxPillWidth),
        padding: EdgeInsets.symmetric(
          horizontal: stripMeta.pillHorizontalPadding,
          vertical: stripMeta.pillVerticalPadding,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary
              .withValues(alpha: stripMeta.pillBackgroundAlpha),
          borderRadius: BorderRadius.circular(stripMeta.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              meta.icon,
              size: stripMeta.pillIconSize,
              color: theme.colorScheme.primary
                  .withValues(alpha: stripMeta.pillIconAlpha),
            ),
            SizedBox(width: stripMeta.pillIconGap),
            Flexible(
              child: Text(
                meta.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: stripMeta.pillFontSize,
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: stripMeta.pillLabelAlpha),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: stripMeta.bottomMargin),
      padding: EdgeInsets.symmetric(
        horizontal: stripMeta.horizontalPadding,
        vertical: stripMeta.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: borderColor, width: stripMeta.borderWidth),
          bottom: BorderSide(color: borderColor, width: stripMeta.borderWidth),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                stripMeta.icon,
                size: stripMeta.headerIconSize,
                color: theme.colorScheme.primary
                    .withValues(alpha: stripMeta.headerIconAlpha),
              ),
              SizedBox(width: stripMeta.headerIconGap),
              Flexible(
                child: Text(
                  stripMeta.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: stripMeta.headerTitleWeight,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: stripMeta.pillTopGap),
          Wrap(
            spacing: stripMeta.pillSpacing,
            runSpacing: stripMeta.pillRunSpacing,
            children: metas.map(pill).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildMomentsDiscoveryFilterBar(L10n l) {
    final allClear = !_filterOfficialOnly &&
        !_filterOfficialRepliesOnly &&
        !_filterHotOfficialsOnly &&
        !_filterRedpacketOnly &&
        !_filterMiniProgramOnly &&
        !_filterOfficialLinkedOnly &&
        !_filterChannelClipsOnly &&
        !_filterLast3Days &&
        !_filterCloseFriendsOnly &&
        (_topicCategory ?? '').isEmpty &&
        (_filterAudienceTag ?? '').isEmpty;

    final filters = momentDiscoveryFilterMetas(
      isArabic: l.isArabic,
      allSelected: allClear,
      officialSelected: _filterOfficialOnly,
      miniProgramsSelected: _filterMiniProgramOnly,
      channelsSelected: _filterChannelClipsOnly,
      greenPaketSelected: _filterRedpacketOnly,
      recentSelected: _filterLast3Days,
      closeFriendsSelected: _filterCloseFriendsOnly,
    );

    void applyFilter(MomentDiscoveryFilterMeta filter) {
      setState(() {
        switch (filter.kind) {
          case MomentDiscoveryFilterKind.all:
            _filterOfficialOnly = false;
            _filterOfficialRepliesOnly = false;
            _filterHotOfficialsOnly = false;
            _filterRedpacketOnly = false;
            _filterMiniProgramOnly = false;
            _filterOfficialLinkedOnly = false;
            _filterChannelClipsOnly = false;
            _filterLast3Days = false;
            _filterCloseFriendsOnly = false;
            _topicCategory = null;
            _filterAudienceTag = null;
            break;
          case MomentDiscoveryFilterKind.official:
            _filterOfficialOnly = !_filterOfficialOnly;
            if (_filterOfficialOnly) {
              _filterOfficialRepliesOnly = false;
              _filterHotOfficialsOnly = false;
            }
            break;
          case MomentDiscoveryFilterKind.miniPrograms:
            _filterMiniProgramOnly = !_filterMiniProgramOnly;
            break;
          case MomentDiscoveryFilterKind.channels:
            _filterChannelClipsOnly = !_filterChannelClipsOnly;
            break;
          case MomentDiscoveryFilterKind.greenPaket:
            _filterRedpacketOnly = !_filterRedpacketOnly;
            break;
          case MomentDiscoveryFilterKind.recent:
            _filterLast3Days = !_filterLast3Days;
            break;
          case MomentDiscoveryFilterKind.closeFriends:
            _filterCloseFriendsOnly = !_filterCloseFriendsOnly;
            break;
        }
      });
      Perf.action(filter.perfKey);
    }

    return _momentsFilterStrip(
      children: filters
          .map(
            (filter) => _momentsFilterButton(
              icon: filter.icon,
              label: filter.label,
              selected: filter.selected,
              onTap: () => applyFilter(filter),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildOfficialFiltersRow(L10n l) {
    final filters = momentOfficialFilterMetas(
      isArabic: l.isArabic,
      officialOnlySelected: _filterOfficialOnly,
      officialRepliesSelected: _filterOfficialRepliesOnly,
      hotOfficialsSelected: _filterHotOfficialsOnly,
    );

    void applyFilter(MomentOfficialFilterMeta filter) {
      setState(() {
        switch (filter.kind) {
          case MomentOfficialFilterKind.all:
            _filterOfficialOnly = false;
            _filterOfficialRepliesOnly = false;
            _filterHotOfficialsOnly = false;
            break;
          case MomentOfficialFilterKind.officialShares:
            _filterOfficialOnly = true;
            _filterOfficialRepliesOnly = false;
            _filterHotOfficialsOnly = false;
            break;
          case MomentOfficialFilterKind.officialReplies:
            _filterOfficialRepliesOnly = true;
            _filterOfficialOnly = false;
            _filterHotOfficialsOnly = false;
            _topicCategory = null;
            break;
          case MomentOfficialFilterKind.hotOfficialShares:
            _filterHotOfficialsOnly = true;
            _filterOfficialOnly = false;
            _filterOfficialRepliesOnly = false;
            break;
        }
      });
      Perf.action(filter.perfKey);
    }

    return _momentsFilterStrip(
      topBorder: false,
      children: filters
          .map(
            (filter) => _momentsFilterButton(
              icon: filter.icon,
              label: filter.label,
              selected: filter.selected,
              onTap: () => applyFilter(filter),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildTopicBar(L10n l) {
    final filters = momentTopicFilterMetas(
      isArabic: l.isArabic,
      topicCategory: _topicCategory,
      officialSelected: _filterOfficialOnly,
      officialRepliesSelected: _filterOfficialRepliesOnly,
    );

    void applyFilter(MomentTopicFilterMeta filter) {
      setState(() {
        switch (filter.kind) {
          case MomentTopicFilterKind.all:
            _topicCategory = null;
            _filterOfficialOnly = false;
            _filterOfficialRepliesOnly = false;
            break;
          case MomentTopicFilterKind.wallet:
            final enable = _topicCategory != 'wallet';
            _topicCategory = enable ? 'wallet' : null;
            _filterOfficialOnly = enable;
            _filterOfficialRepliesOnly = false;
            break;
        }
      });
      Perf.action(filter.perfKey);
    }

    return _momentsFilterStrip(
      topBorder: false,
      children: filters
          .map(
            (filter) => _momentsFilterButton(
              icon: filter.icon,
              label: filter.label,
              selected: filter.selected,
              onTap: () => applyFilter(filter),
            ),
          )
          .toList(growable: false),
    );
  }

  bool _isChannelClipMoment(Map<String, dynamic> p) {
    final text = ((p['text'] ?? p['content'] ?? '')).toString();
    if (text.contains('#ch_')) return true;
    final originItem = (p['origin_official_item_id'] ?? '').toString().trim();
    if (originItem.isNotEmpty) return true;
    final target = parseOfficialDeepLinkFromText(text);
    if ((target?.itemId ?? '').trim().isNotEmpty) {
      return true;
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
    final target = officialTargetFromExplicitOrText(
      explicitAccountId: originAccountId,
      explicitItemId: originItemId,
      text: text,
    );
    if (target == null) return null;
    final accountId = target.accountId.trim();
    if (accountId.isEmpty) return null;
    final itemId =
        (target.itemId ?? '').trim().isEmpty ? null : target.itemId!.trim();

    final acc = _officialAccounts[accountId];
    final accountName = (acc?.name ?? '').isNotEmpty ? acc!.name : accountId;
    final officialMeta = momentOfficialAttachmentMeta(
      accountName: accountName,
      accountKind: acc?.kind ?? 'service',
      itemId: itemId,
      itemTitle: itemId == null
          ? null
          : officialAttachmentItemTitleFromMomentText(text),
      linkedMiniProgramId: acc?.miniAppId,
      isArabic: l.isArabic,
    );
    final chrome = momentOfficialAttachmentChromeMeta();

    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: chrome.darkSurfaceAlpha,
          )
        : WeChatPalette.searchFill;
    final borderColor = theme.dividerColor.withValues(
      alpha: isDark ? chrome.darkBorderAlpha : chrome.lightBorderAlpha,
    );
    final mutedColor = theme.colorScheme.onSurface.withValues(
      alpha: chrome.mutedTextAlpha,
    );

    final actions = <Widget>[
      if ((acc?.miniAppId ?? '').trim().isNotEmpty)
        _momentAttachmentIconAction(
          theme: theme,
          tooltip: officialMeta.serviceActionLabel,
          icon: officialMeta.serviceActionIcon,
          buttonSize: officialMeta.actionButtonSize,
          iconSize: officialMeta.actionIconSize,
          onPressed: () {
            final mid = acc!.miniAppId!.trim();
            unawaited(
              _openMiniProgramFromMoment(
                MiniProgramDeepLinkTarget(id: mid),
                accountName,
              ),
            );
          },
        ),
      _momentAttachmentIconAction(
        theme: theme,
        tooltip: officialMeta.channelsActionLabel,
        icon: officialMeta.channelsActionIcon,
        buttonSize: officialMeta.actionButtonSize,
        iconSize: officialMeta.actionIconSize,
        onPressed: () => _openOfficialFromMoment(accountId, itemId),
      ),
      if (acc != null && !acc.followed)
        _momentAttachmentIconAction(
          theme: theme,
          tooltip: officialMeta.followActionLabel,
          icon: officialMeta.followActionIcon,
          buttonSize: officialMeta.actionButtonSize,
          iconSize: officialMeta.actionIconSize,
          onPressed: () => _toggleOfficialFollowFromMoment(
            accountId,
            officialMeta.isServiceAccount,
          ),
        ),
      if ((acc?.chatPeerId ?? '').trim().isNotEmpty)
        _momentAttachmentIconAction(
          theme: theme,
          tooltip: officialMeta.chatActionLabel,
          icon: officialMeta.chatActionIcon,
          buttonSize: officialMeta.actionButtonSize,
          iconSize: officialMeta.actionIconSize,
          onPressed: () => _openOfficialChatFromMoment(acc!.chatPeerId!.trim()),
        ),
    ];

    return InkWell(
      onTap: () => _openOfficialFromMoment(accountId, itemId),
      splashColor:
          theme.colorScheme.primary.withValues(alpha: chrome.splashAlpha),
      highlightColor:
          theme.colorScheme.primary.withValues(alpha: chrome.highlightAlpha),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: chrome.horizontalPadding,
          vertical: chrome.verticalPadding,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.symmetric(
            horizontal: BorderSide(
              color: borderColor,
              width: chrome.borderWidth,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if ((acc?.avatarUrl ?? '').isNotEmpty)
              CircleAvatar(
                radius: officialMeta.avatarRadius,
                backgroundImage: NetworkImage(acc!.avatarUrl!),
              )
            else
              Container(
                width: officialMeta.fallbackIconBoxSize,
                height: officialMeta.fallbackIconBoxSize,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(
                    alpha: isDark
                        ? chrome.fallbackIconFillDarkAlpha
                        : chrome.fallbackIconFillLightAlpha,
                  ),
                  borderRadius:
                      BorderRadius.circular(officialMeta.fallbackIconRadius),
                ),
                child: Icon(
                  officialMeta.fallbackIcon,
                  size: officialMeta.fallbackIconSize,
                  color: theme.colorScheme.primary,
                ),
              ),
            SizedBox(width: chrome.iconTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    officialMeta.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: officialMeta.titleFontSize,
                      fontWeight: chrome.titleFontWeight,
                    ),
                  ),
                  SizedBox(height: chrome.subtitleTopGap),
                  Text(
                    officialMeta.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: officialMeta.subtitleFontSize,
                      color: mutedColor,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: chrome.actionGap),
            ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: officialMeta.actionsMaxWidth),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: chrome.actionWrapSpacing,
                runSpacing: chrome.actionWrapRunSpacing,
                children: actions,
              ),
            ),
            Icon(
              officialMeta.chevronIcon,
              size: officialMeta.chevronSize,
              color: mutedColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _momentAttachmentIconAction({
    required ThemeData theme,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    double buttonSize = 30,
    double iconSize = 17,
    Color? color,
  }) {
    final chrome = momentAttachmentIconActionChromeMeta();
    final iconColor = color ??
        theme.colorScheme.onSurface.withValues(
          alpha: chrome.defaultIconAlpha,
        );
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize, color: iconColor),
      visualDensity: chrome.visualDensity,
      padding: chrome.padding,
      constraints:
          BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
      style: IconButton.styleFrom(
        tapTargetSize: chrome.tapTargetSize,
        minimumSize: Size(buttonSize, buttonSize),
        padding: chrome.padding,
      ),
    );
  }

  MiniProgramDeepLinkTarget? _miniProgramTargetFromText(String text) {
    return parseMiniProgramDeepLinkFromText(text);
  }

  MiniAppDescriptor? _miniAppDescriptorById(String id) {
    final normalized = id.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final descriptor in MiniAppRegistry.descriptors) {
      final runtimeId = (descriptor.runtimeAppId ?? descriptor.id).trim();
      if (descriptor.id.toLowerCase() == normalized ||
          runtimeId.toLowerCase() == normalized) {
        return descriptor;
      }
    }
    return miniAppById(normalized);
  }

  MiniAppDescriptor? _miniAppFromText(String text) {
    final target = _miniProgramTargetFromText(text);
    if (target == null) return null;
    return _miniAppDescriptorById(target.id);
  }

  Future<void> _openMiniProgramFromMoment(
    MiniProgramDeepLinkTarget target,
    String title,
  ) async {
    final id = target.id.trim().toLowerCase();
    if (id.isEmpty) return;
    Perf.action('moments_open_mini_program');

    String walletId = '';
    String deviceId = 'moments';
    try {
      final sp = await SharedPreferences.getInstance();
      walletId = sp.getString('wallet_id') ?? '';
      deviceId = await CallSignalingClient.loadDeviceId(
              baseUrlOverride: widget.baseUrl) ??
          deviceId;
    } catch (_) {}
    if (!mounted) return;

    if (_isPaymentMiniProgram(id)) {
      _pushPaymentsMiniProgram(
        id,
        walletId: walletId,
        deviceId: deviceId,
        resourceId: target.resourceId,
        contextLabel: title,
      );
      return;
    }

    late final void Function(String) openMod;
    openMod = (next) {
      final nextId = next.trim().toLowerCase();
      if (nextId.isEmpty || !mounted) return;
      if (_isPaymentMiniProgram(nextId)) {
        _pushPaymentsMiniProgram(
          nextId,
          walletId: walletId,
          deviceId: deviceId,
          contextLabel: title,
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MiniProgramPage(
            id: nextId,
            baseUrl: widget.baseUrl,
            walletId: walletId,
            deviceId: deviceId,
            onOpenMod: openMod,
          ),
        ),
      );
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniProgramPage(
          id: id,
          baseUrl: widget.baseUrl,
          walletId: walletId,
          deviceId: deviceId,
          onOpenMod: openMod,
        ),
      ),
    );
  }

  bool _isPaymentMiniProgram(String id) {
    final normalized = id.trim().toLowerCase();
    return normalized == 'payments' ||
        normalized == 'alias' ||
        normalized == 'merchant' ||
        normalized == 'green_paket';
  }

  void _pushPaymentsMiniProgram(
    String id, {
    required String walletId,
    required String deviceId,
    String? resourceId,
    String? contextLabel,
  }) {
    if (!mounted) return;
    final normalized = id.trim().toLowerCase();
    final packetId = (resourceId ?? '').trim();
    final initialSection = normalized == 'green_paket' && packetId.isNotEmpty
        ? 'redpacket:$packetId'
        : null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentsPage(
          widget.baseUrl,
          walletId,
          deviceId,
          initialSection: initialSection,
          contextLabel: (contextLabel ?? '').trim().isNotEmpty
              ? contextLabel!.trim()
              : null,
        ),
      ),
    );
  }

  Widget? _buildMiniAppAttachment(
    Map<String, dynamic> post,
    String text,
    ThemeData theme,
    L10n l,
  ) {
    final explicitId = (post['mini_program_id'] ?? '').toString().trim();
    final target = miniProgramTargetFromExplicitOrText(
      explicitId: explicitId,
      text: text,
    );
    if (target == null) return null;
    final meta = _miniAppDescriptorById(target.id);
    final id = target.id;
    final resourceId = (target.resourceId ?? '').trim();
    final attachmentMeta = momentMiniProgramAttachmentMeta(
      id: id,
      resourceId: resourceId,
      descriptor: meta,
      isArabic: l.isArabic,
    );
    final title = attachmentMeta.title;
    final accent = momentMiniProgramAccentColor(id);
    final chrome = momentMiniProgramAttachmentChromeMeta();

    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: chrome.darkSurfaceAlpha,
          )
        : WeChatPalette.searchFill;
    final borderColor = theme.dividerColor.withValues(
      alpha: isDark ? chrome.darkBorderAlpha : chrome.lightBorderAlpha,
    );
    final mutedColor = theme.colorScheme.onSurface.withValues(
      alpha: chrome.mutedTextAlpha,
    );

    return InkWell(
      onTap: () {
        unawaited(_openMiniProgramFromMoment(target, title));
      },
      splashColor: accent.withValues(alpha: chrome.splashAlpha),
      highlightColor: accent.withValues(alpha: chrome.highlightAlpha),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: chrome.horizontalPadding,
          vertical: chrome.verticalPadding,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.symmetric(
            horizontal: BorderSide(
              color: borderColor,
              width: chrome.borderWidth,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: attachmentMeta.iconBoxSize,
              height: attachmentMeta.iconBoxSize,
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: isDark
                      ? chrome.iconFillDarkAlpha
                      : chrome.iconFillLightAlpha,
                ),
                borderRadius: BorderRadius.circular(attachmentMeta.iconRadius),
              ),
              child: Icon(
                attachmentMeta.icon,
                size: attachmentMeta.iconSize,
                color: accent,
              ),
            ),
            SizedBox(width: chrome.iconTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: attachmentMeta.titleFontSize,
                      fontWeight: chrome.titleFontWeight,
                    ),
                  ),
                  SizedBox(height: chrome.subtitleTopGap),
                  Text(
                    attachmentMeta.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: attachmentMeta.subtitleFontSize,
                      color: mutedColor,
                    ),
                  ),
                  SizedBox(height: chrome.footerTopGap),
                  Text(
                    attachmentMeta.footer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: attachmentMeta.footerFontSize,
                      color: mutedColor,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: chrome.actionGap),
            _momentAttachmentIconAction(
              theme: theme,
              tooltip: attachmentMeta.openTooltip,
              icon: attachmentMeta.openIcon,
              color: accent,
              onPressed: () {
                unawaited(_openMiniProgramFromMoment(target, title));
              },
            ),
            Icon(
              attachmentMeta.chevronIcon,
              size: chrome.chevronSize,
              color: mutedColor,
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
      Perf.action('moments_open_official');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) {
            void openChat(String peerId) {
              if (peerId.trim().isEmpty || !mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShamellChatPage(
                    baseUrl: widget.baseUrl,
                    initialPeerId: peerId.trim(),
                  ),
                ),
              );
            }

            final cleanItemId = (itemId ?? '').trim();
            if (cleanItemId.isNotEmpty) {
              return OfficialFeedItemDeepLinkPage(
                baseUrl: widget.baseUrl,
                accountId: accountId.trim(),
                itemId: cleanItemId,
                onOpenChat: openChat,
              );
            }
            return OfficialAccountDeepLinkPage(
              baseUrl: widget.baseUrl,
              accountId: accountId.trim(),
              onOpenChat: openChat,
            );
          },
        ),
      );
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
      final r = await http.post(uri,
          headers: await _hdrMoments(widget.baseUrl, json: true));
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
        headers: await _hdrMoments(widget.baseUrl, json: true),
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

class _WeChatMomentActionMenu extends StatelessWidget {
  final MomentPostQuickActionMeta likeAction;
  final MomentPostQuickActionMeta commentAction;
  final MomentPostQuickActionMeta shareAction;
  final MomentPostQuickActionMeta saveAction;
  final double width;
  final bool likeEnabled;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;

  const _WeChatMomentActionMenu({
    required this.likeAction,
    required this.commentAction,
    required this.shareAction,
    required this.saveAction,
    required this.width,
    required this.likeEnabled,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = momentPostActionMenuChromeMeta();

    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: chrome.actionHorizontalPadding,
            vertical: chrome.actionVerticalPadding,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: chrome.iconSize,
                color: enabled
                    ? Colors.white.withValues(alpha: chrome.enabledAlpha)
                    : Colors.white.withValues(alpha: chrome.disabledAlpha),
              ),
              SizedBox(width: chrome.iconLabelGap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? Colors.white.withValues(alpha: chrome.enabledAlpha)
                        : Colors.white.withValues(alpha: chrome.disabledAlpha),
                    fontSize: chrome.labelFontSize,
                    fontWeight: chrome.labelFontWeight,
                  ),
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
        width: width,
        height: chrome.height,
        decoration: BoxDecoration(
          color: chrome.backgroundColor,
          borderRadius: BorderRadius.circular(chrome.borderRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: action(
                icon: likeAction.icon,
                label: likeAction.label,
                onTap: likeEnabled ? onLike : null,
              ),
            ),
            Container(
              width: chrome.dividerWidth,
              height: chrome.dividerHeight,
              color: Colors.white.withValues(alpha: chrome.dividerAlpha),
            ),
            Expanded(
              child: action(
                icon: commentAction.icon,
                label: commentAction.label,
                onTap: onComment,
              ),
            ),
            Container(
              width: chrome.dividerWidth,
              height: chrome.dividerHeight,
              color: Colors.white.withValues(alpha: chrome.dividerAlpha),
            ),
            Expanded(
              child: action(
                icon: shareAction.icon,
                label: shareAction.label,
                onTap: onShare,
              ),
            ),
            Container(
              width: chrome.dividerWidth,
              height: chrome.dividerHeight,
              color: Colors.white.withValues(alpha: chrome.dividerAlpha),
            ),
            Expanded(
              child: action(
                icon: saveAction.icon,
                label: saveAction.label,
                onTap: onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeChatPopoverArrowClipper extends CustomClipper<Path> {
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
  bool shouldReclip(_WeChatPopoverArrowClipper oldClipper) => false;
}

class _WeChatPopoverDownArrowClipper extends CustomClipper<Path> {
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
  bool shouldReclip(_WeChatPopoverDownArrowClipper oldClipper) => false;
}

class _WeChatPopoverUpArrowClipper extends CustomClipper<Path> {
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
  bool shouldReclip(_WeChatPopoverUpArrowClipper oldClipper) => false;
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
      miniAppId: _momentMiniProgramId(j),
    );
  }
}

String? _momentMiniProgramId(Map<String, dynamic> raw) {
  for (final key in const <String>[
    'mini_program_id',
    'mini_app_id',
    'app_id',
    'module_app_id',
  ]) {
    final value = (raw[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}
