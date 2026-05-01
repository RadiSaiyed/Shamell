import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../wechat_ui.dart';

class WeChatChatInfoPage extends StatefulWidget {
  final String myDisplayName;
  final String displayName;
  final String peerId;
  final String? subtitle;
  final String alias;
  final String tags;
  final String themeKey;
  final List<Uint8List> mediaPreview;
  final Future<void> Function() onCreateGroupChat;

  final bool isCloseFriend;
  final bool canToggleCloseFriend;
  final bool muted;
  final bool pinned;
  final bool hidden;
  final bool blocked;

  final Future<bool> Function(bool makeClose) onToggleCloseFriend;
  final Future<void> Function(bool muted) onToggleMuted;
  final Future<void> Function(bool pinned) onTogglePinned;
  final Future<void> Function(bool hidden) onToggleHidden;
  final Future<void> Function(bool blocked) onToggleBlocked;

  final Future<void> Function() onOpenFavorites;
  final Future<void> Function() onOpenMedia;
  final Future<void> Function() onSearchInChat;

  final Future<void> Function(String alias, String tags) onSaveRemarksTags;
  final Future<void> Function(String themeKey) onSetTheme;
  final Future<void> Function() onClearChatHistory;

  const WeChatChatInfoPage({
    super.key,
    this.myDisplayName = '',
    required this.displayName,
    required this.peerId,
    this.subtitle,
    this.alias = '',
    this.tags = '',
    this.themeKey = 'default',
    this.mediaPreview = const <Uint8List>[],
    required this.onCreateGroupChat,
    this.isCloseFriend = false,
    this.canToggleCloseFriend = false,
    this.muted = false,
    this.pinned = false,
    this.hidden = false,
    this.blocked = false,
    required this.onToggleCloseFriend,
    required this.onToggleMuted,
    required this.onTogglePinned,
    required this.onToggleHidden,
    required this.onToggleBlocked,
    required this.onOpenFavorites,
    required this.onOpenMedia,
    required this.onSearchInChat,
    required this.onSaveRemarksTags,
    required this.onSetTheme,
    required this.onClearChatHistory,
  });

  @override
  State<WeChatChatInfoPage> createState() => _WeChatChatInfoPageState();
}

class _WeChatChatInfoPageState extends State<WeChatChatInfoPage> {
  bool _busy = false;
  late bool _closeFriend;
  late bool _muted;
  late bool _pinned;
  late bool _hidden;
  late bool _blocked;
  late String _alias;
  late String _tags;
  late String _themeKey;

  @override
  void initState() {
    super.initState();
    _closeFriend = widget.isCloseFriend;
    _muted = widget.muted;
    _pinned = widget.pinned;
    _hidden = widget.hidden;
    _blocked = widget.blocked;
    _alias = widget.alias;
    _tags = widget.tags;
    _themeKey = widget.themeKey;
  }

  Future<void> _runBusy(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggleCloseFriend(bool value) async {
    if (!widget.canToggleCloseFriend) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'لا يوجد رقم هاتف مرتبط بهذا الصديق.'
                : 'No phone number linked to this friend.',
          ),
        ),
      );
      return;
    }
    final next = value;
    setState(() => _closeFriend = next);
    await _runBusy(() async {
      final ok = await widget.onToggleCloseFriend(next);
      if (!ok && mounted) {
        setState(() => _closeFriend = !next);
      }
    });
  }

  Future<void> _toggleMuted(bool value) async {
    final next = value;
    setState(() => _muted = next);
    await _runBusy(() async {
      await widget.onToggleMuted(next);
    });
  }

  Future<void> _togglePinned(bool value) async {
    final next = value;
    setState(() => _pinned = next);
    await _runBusy(() async {
      await widget.onTogglePinned(next);
    });
  }

  Future<void> _toggleHidden(bool value) async {
    final next = value;
    setState(() => _hidden = next);
    await _runBusy(() async {
      await widget.onToggleHidden(next);
    });
  }

  Future<void> _toggleBlocked(bool value) async {
    final next = value;
    setState(() => _blocked = next);
    await _runBusy(() async {
      await widget.onToggleBlocked(next);
    });
  }

  Future<void> _openRemarksTags() async {
    final res = await Navigator.of(context).push<_WeChatRemarksResult?>(
      MaterialPageRoute(
        builder: (_) => _WeChatRemarksTagsPage(
          displayName: widget.displayName,
          peerId: widget.peerId,
          initialAlias: _alias,
          initialTags: _tags,
        ),
      ),
    );
    if (!mounted || res == null) return;
    final alias = res.alias.trim();
    final tags = res.tags.trim();
    setState(() {
      _alias = alias;
      _tags = tags;
    });
    await _runBusy(() async {
      await widget.onSaveRemarksTags(alias, tags);
    });
  }

  String _themeLabel(L10n l) {
    switch (_themeKey) {
      case 'dark':
        return l.mirsaalChatThemeDark;
      case 'green':
        return l.mirsaalChatThemeGreen;
      default:
        return l.mirsaalChatThemeDefault;
    }
  }

  Future<void> _pickTheme() async {
    final l = L10n.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget tile(String value, String label) {
          final selected = _themeKey == value;
          return ListTile(
            title: Text(label),
            trailing: selected ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(ctx).pop(value),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile('default', l.mirsaalChatThemeDefault),
              tile('dark', l.mirsaalChatThemeDark),
              tile('green', l.mirsaalChatThemeGreen),
            ],
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() => _themeKey = picked);
    await _runBusy(() async {
      await widget.onSetTheme(picked);
    });
  }

  Future<void> _confirmClearHistory() async {
    final l = L10n.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.mirsaalClearChatHistory),
        content: Text(
          l.isArabic
              ? 'سيتم مسح كل رسائل هذه الدردشة من هذا الجهاز.'
              : 'All messages in this chat will be cleared from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.mirsaalDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l.isArabic ? 'مسح' : 'Clear',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _runBusy(widget.onClearChatHistory);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;

    Icon chevron({bool enabled = true}) => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface
              .withValues(alpha: enabled ? .40 : .20),
        );

    final canTap = !_busy;

    String initialFor(String label) {
      final t = label.trim();
      return t.isNotEmpty ? t.substring(0, 1).toUpperCase() : '?';
    }

    final peerName = widget.displayName.trim().isEmpty
        ? widget.peerId
        : widget.displayName.trim();
    final meName = widget.myDisplayName.trim().isNotEmpty
        ? widget.myDisplayName.trim()
        : (l.isArabic ? 'أنا' : 'Me');

    Future<void> _createGroupChatFromHere() async {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await widget.onCreateGroupChat();
    }

    Widget memberTile({
      required String name,
      required Widget avatar,
      VoidCallback? onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
          ],
        ),
      );
    }

    Widget memberAvatar({
      required String label,
      required Color bg,
    }) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 54,
          height: 54,
          color: bg,
          alignment: Alignment.center,
          child: Text(
            initialFor(label),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    Widget addAvatar() {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: isDark ? .25 : .55),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.add,
          size: 26,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        ),
      );
    }

    Widget membersGrid() {
      final items = <Widget>[
        memberTile(
          name: peerName,
          avatar: memberAvatar(
            label: peerName,
            bg: theme.colorScheme.primary.withValues(alpha: isDark ? .22 : .16),
          ),
        ),
        memberTile(
          name: meName,
          avatar: memberAvatar(
            label: meName,
            bg: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isDark ? .45 : .90,
            ),
          ),
        ),
        memberTile(
          name: l.isArabic ? 'إضافة' : 'Add',
          avatar: addAvatar(),
          onTap: canTap ? _createGroupChatFromHere : null,
        ),
      ];

      return LayoutBuilder(
        builder: (ctx, constraints) {
          final maxWidth = constraints.maxWidth;
          const spacing = 12.0;
          final columns = maxWidth >= 520 ? 5 : 4;
          final tileWidth = (maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: 12,
            children: [
              for (final w in items)
                SizedBox(
                  width: tileWidth,
                  child: w,
                ),
            ],
          );
        },
      );
    }

    Widget mediaTrailing() {
      final previews = widget.mediaPreview.take(3).toList();
      final placeholderIcons = <IconData>[
        Icons.image_outlined,
        Icons.link,
        Icons.description_outlined,
      ];

      Widget thumb(Widget child) {
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: isDark ? .20 : .35),
              width: 0.6,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            if (i < previews.length)
              thumb(
                Image.memory(
                  previews[i],
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              )
            else
              thumb(
                Center(
                  child: Icon(
                    placeholderIcons[i],
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: .45),
                  ),
                ),
              ),
          ],
          const SizedBox(width: 8),
          chevron(enabled: canTap),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'معلومات الدردشة' : 'Chat Info'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 0, bottom: 24),
        children: [
          WeChatSection(
            margin: const EdgeInsets.only(top: 0),
            dividerIndent: 0,
            dividerEndIndent: 0,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: membersGrid(),
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(
                  l.isArabic ? 'ملاحظة ووسوم' : 'Remarks and Tags',
                ),
                subtitle: (_alias.isEmpty && _tags.isEmpty)
                    ? null
                    : Text(
                        [
                          if (_alias.isNotEmpty) _alias,
                          if (_tags.isNotEmpty) _tags,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                      ),
                trailing: chevron(enabled: canTap),
                onTap: canTap ? _openRemarksTags : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'جهة اتصال مميّزة' : 'Star Friend'),
                trailing: Switch.adaptive(
                  value: _closeFriend,
                  onChanged: canTap ? _toggleCloseFriend : null,
                ),
                onTap: canTap ? () => _toggleCloseFriend(!_closeFriend) : null,
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(
                    l.isArabic ? 'بحث في سجل الدردشة' : 'Search Chat History'),
                trailing: chevron(enabled: canTap),
                onTap: canTap ? widget.onSearchInChat : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic
                    ? 'الوسائط والروابط والملفات'
                    : 'Media, Links, and Files'),
                trailing: mediaTrailing(),
                onTap: canTap ? widget.onOpenMedia : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.mirsaalFavoritesTitle),
                trailing: chevron(enabled: canTap),
                onTap: canTap ? widget.onOpenFavorites : null,
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'عدم الإزعاج' : 'Mute notifications'),
                trailing: Switch.adaptive(
                  value: _muted,
                  onChanged: canTap ? _toggleMuted : null,
                ),
                onTap: canTap ? () => _toggleMuted(!_muted) : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'تثبيت في الأعلى' : 'Sticky on Top'),
                trailing: Switch.adaptive(
                  value: _pinned,
                  onChanged: canTap ? _togglePinned : null,
                ),
                onTap: canTap ? () => _togglePinned(!_pinned) : null,
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'خلفية الدردشة' : 'Chat background'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _themeKey == 'dark'
                            ? const Color(0xFF111827)
                            : _themeKey == 'green'
                                ? WeChatPalette.green.withValues(alpha: .75)
                                : const Color(0xFFEDEDED),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: theme.dividerColor
                              .withValues(alpha: isDark ? .20 : .35),
                          width: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _themeLabel(l),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: canTap ? .55 : .30),
                      ),
                    ),
                    const SizedBox(width: 6),
                    chevron(enabled: canTap),
                  ],
                ),
                onTap: canTap ? _pickTheme : null,
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.mirsaalHideChat),
                trailing: Switch.adaptive(
                  value: _hidden,
                  onChanged: canTap ? _toggleHidden : null,
                ),
                onTap: canTap ? () => _toggleHidden(!_hidden) : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.mirsaalBlock),
                trailing: Switch.adaptive(
                  value: _blocked,
                  onChanged: canTap ? _toggleBlocked : null,
                ),
                onTap: canTap ? () => _toggleBlocked(!_blocked) : null,
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Center(
                  child: Text(
                    l.mirsaalClearChatHistory,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                onTap: canTap ? _confirmClearHistory : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeChatRemarksResult {
  final String alias;
  final String tags;

  const _WeChatRemarksResult({
    required this.alias,
    required this.tags,
  });
}

class _WeChatRemarksTagsPage extends StatefulWidget {
  final String displayName;
  final String peerId;
  final String initialAlias;
  final String initialTags;

  const _WeChatRemarksTagsPage({
    required this.displayName,
    required this.peerId,
    required this.initialAlias,
    required this.initialTags,
  });

  @override
  State<_WeChatRemarksTagsPage> createState() => _WeChatRemarksTagsPageState();
}

class _WeChatRemarksTagsPageState extends State<_WeChatRemarksTagsPage> {
  late final TextEditingController _aliasCtrl =
      TextEditingController(text: widget.initialAlias);
  late final TextEditingController _tagsCtrl =
      TextEditingController(text: widget.initialTags);

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      _WeChatRemarksResult(
        alias: _aliasCtrl.text,
        tags: _tagsCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'ملاحظة ووسوم' : 'Remarks & Tags'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(l.settingsSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          WeChatSection(
            margin: const EdgeInsets.only(top: 0),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.mirsaalContactRemarkLabel),
                subtitle: TextField(
                  controller: _aliasCtrl,
                  decoration: InputDecoration(
                    hintText: l.mirsaalFriendAliasHint,
                    border: InputBorder.none,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.mirsaalFriendTagsLabel),
                subtitle: TextField(
                  controller: _tagsCtrl,
                  decoration: InputDecoration(
                    hintText: l.mirsaalFriendTagsHint,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              l.isArabic
                  ? 'استخدم الفواصل للفصل بين الوسوم.'
                  : 'Use commas to separate tags.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
