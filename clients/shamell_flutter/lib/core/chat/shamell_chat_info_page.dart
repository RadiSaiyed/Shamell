import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../shamell_ui.dart';

class ShamellChatInfoPage extends StatefulWidget {
  final String myDisplayName;
  final String displayName;
  final String peerId;
  final String? subtitle;
  final String alias;
  final String tags;
  final String themeKey;
  final List<Uint8List> mediaPreview;
  final Future<void> Function() onCreateGroupChat;

  // Security / verification
  final bool verified;
  final String? peerFingerprint;
  final String? myFingerprint;
  final String? safetyNumberFormatted;
  final String? safetyNumberRaw;
  final Future<void> Function()? onMarkVerified;
  final Future<void> Function()? onResetSession;

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

  const ShamellChatInfoPage({
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
    this.verified = false,
    this.peerFingerprint,
    this.myFingerprint,
    this.safetyNumberFormatted,
    this.safetyNumberRaw,
    this.onMarkVerified,
    this.onResetSession,
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
  State<ShamellChatInfoPage> createState() => _ShamellChatInfoPageState();
}

class _ShamellChatInfoPageState extends State<ShamellChatInfoPage> {
  bool _busy = false;
  late bool _closeFriend;
  late bool _muted;
  late bool _pinned;
  late bool _hidden;
  late bool _blocked;
  late bool _verified;
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
    _verified = widget.verified;
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

  Future<void> _copyToClipboard(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: t));
    } catch (_) {}
    if (!mounted) return;
    final l = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.isArabic ? 'تم النسخ.' : 'Copied.')),
    );
  }

  Future<void> _confirmMarkVerified() async {
    final cb = widget.onMarkVerified;
    if (_verified || cb == null) return;
    final l = L10n.of(context);
    final safety = (widget.safetyNumberFormatted ?? '').trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'تحقق من رقم الأمان' : 'Verify safety number'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic
                  ? 'قارن رقم الأمان مع جهة الاتصال عبر قناة مستقلة. ضع علامة "موثوق" فقط إذا كان مطابقًا.'
                  : 'Compare the safety number with your contact via an independent channel. Mark verified only if it matches.',
            ),
            if (safety.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                safety,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.shamellDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.isArabic ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _runBusy(() async {
      await cb();
      if (!mounted) return;
      setState(() => _verified = true);
    });
  }

  Future<void> _confirmResetSession() async {
    final cb = widget.onResetSession;
    if (cb == null) return;
    final l = L10n.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.shamellResetSessionLabel),
        content: Text(
          l.isArabic
              ? 'سيؤدي هذا إلى إعادة تعيين جلسة التشفير وربما حذف الرسائل المحلية لهذه الدردشة. استخدمه فقط إذا لزم الأمر.'
              : 'This will reset the encryption session and may clear local messages for this chat. Use only if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.shamellDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l.shamellResetSessionLabel,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _runBusy(() async {
      await cb();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _toggleCloseFriend(bool value) async {
    if (!widget.canToggleCloseFriend) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'هذا الخيار غير متاح لجهة الاتصال هذه.'
                : 'This option is not available for this contact.',
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
    final res = await Navigator.of(context).push<_ShamellRemarksResult?>(
      MaterialPageRoute(
        builder: (_) => _ShamellRemarksTagsPage(
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
        return l.shamellChatThemeDark;
      case 'green':
        return l.shamellChatThemeGreen;
      default:
        return l.shamellChatThemeDefault;
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
              tile('default', l.shamellChatThemeDefault),
              tile('dark', l.shamellChatThemeDark),
              tile('green', l.shamellChatThemeGreen),
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
        title: Text(l.shamellClearChatHistory),
        content: Text(
          l.isArabic
              ? 'سيتم مسح كل رسائل هذه الدردشة من هذا الجهاز.'
              : 'All messages in this chat will be cleared from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.shamellDialogCancel),
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
        : ShamellPalette.background;

    Icon chevron({bool enabled = true}) => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface
              .withValues(alpha: enabled ? .40 : .20),
        );

    final canTap = !_busy;
    final safetyFormatted = (widget.safetyNumberFormatted ?? '').trim();
    final safetyRaw = (widget.safetyNumberRaw ?? '').trim().isNotEmpty
        ? widget.safetyNumberRaw!.trim()
        : safetyFormatted.replaceAll(RegExp(r'\\s+'), '');
    final peerFp = (widget.peerFingerprint ?? '').trim();
    final myFp = (widget.myFingerprint ?? '').trim();

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
          ShamellSection(
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
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                leading: Icon(
                  _verified ? Icons.verified : Icons.shield_outlined,
                  color: _verified
                      ? ShamellPalette.green
                      : theme.colorScheme.onSurface.withValues(alpha: .55),
                ),
                title: Text(l.isArabic ? 'التحقق' : 'Verification'),
                subtitle: Text(
                  _verified ? l.shamellTrustedFingerprint : l.shamellUnverifiedContact,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: _verified
                        ? ShamellPalette.green.withValues(alpha: .85)
                        : theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: (!_verified && widget.onMarkVerified != null)
                    ? TextButton(
                        onPressed: canTap ? _confirmMarkVerified : null,
                        child: Text(l.shamellMarkVerifiedLabel),
                      )
                    : null,
              ),
              if (safetyFormatted.isNotEmpty)
                ListTile(
                  dense: true,
                  enabled: canTap,
                  title: Text(l.shamellSafetyLabel),
                  subtitle: SelectableText(
                    safetyFormatted,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: .80),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l.isArabic ? 'نسخ' : 'Copy',
                    onPressed: canTap ? () => _copyToClipboard(safetyRaw) : null,
                    icon: const Icon(Icons.copy),
                  ),
                  onTap: canTap ? () => _copyToClipboard(safetyRaw) : null,
                ),
              if (peerFp.isNotEmpty)
                ListTile(
                  dense: true,
                  enabled: canTap,
                  title: Text(l.shamellPeerFingerprintLabel),
                  subtitle: SelectableText(
                    peerFp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l.isArabic ? 'نسخ' : 'Copy',
                    onPressed: canTap ? () => _copyToClipboard(peerFp) : null,
                    icon: const Icon(Icons.copy),
                  ),
                ),
              if (myFp.isNotEmpty)
                ListTile(
                  dense: true,
                  enabled: canTap,
                  title: Text(l.shamellYourFingerprintLabel),
                  subtitle: SelectableText(
                    myFp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l.isArabic ? 'نسخ' : 'Copy',
                    onPressed: canTap ? () => _copyToClipboard(myFp) : null,
                    icon: const Icon(Icons.copy),
                  ),
                ),
              if (widget.onResetSession != null)
                ListTile(
                  dense: true,
                  enabled: canTap,
                  title: Center(
                    child: Text(
                      l.shamellResetSessionLabel,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  onTap: canTap ? _confirmResetSession : null,
                ),
            ],
          ),
          ShamellSection(
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
          ShamellSection(
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
                title: Text(l.shamellFavoritesTitle),
                trailing: chevron(enabled: canTap),
                onTap: canTap ? widget.onOpenFavorites : null,
              ),
            ],
          ),
          ShamellSection(
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
          ShamellSection(
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
                                ? ShamellPalette.green.withValues(alpha: .75)
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
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.shamellHideChat),
                trailing: Switch.adaptive(
                  value: _hidden,
                  onChanged: canTap ? _toggleHidden : null,
                ),
                onTap: canTap ? () => _toggleHidden(!_hidden) : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.shamellBlock),
                trailing: Switch.adaptive(
                  value: _blocked,
                  onChanged: canTap ? _toggleBlocked : null,
                ),
                onTap: canTap ? () => _toggleBlocked(!_blocked) : null,
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Center(
                  child: Text(
                    l.shamellClearChatHistory,
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

class _ShamellRemarksResult {
  final String alias;
  final String tags;

  const _ShamellRemarksResult({
    required this.alias,
    required this.tags,
  });
}

class _ShamellRemarksTagsPage extends StatefulWidget {
  final String displayName;
  final String peerId;
  final String initialAlias;
  final String initialTags;

  const _ShamellRemarksTagsPage({
    required this.displayName,
    required this.peerId,
    required this.initialAlias,
    required this.initialTags,
  });

  @override
  State<_ShamellRemarksTagsPage> createState() => _ShamellRemarksTagsPageState();
}

class _ShamellRemarksTagsPageState extends State<_ShamellRemarksTagsPage> {
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
      _ShamellRemarksResult(
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
        : ShamellPalette.background;

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
          ShamellSection(
            margin: const EdgeInsets.only(top: 0),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.shamellContactRemarkLabel),
                subtitle: TextField(
                  controller: _aliasCtrl,
                  decoration: InputDecoration(
                    hintText: l.shamellFriendAliasHint,
                    border: InputBorder.none,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.shamellFriendTagsLabel),
                subtitle: TextField(
                  controller: _tagsCtrl,
                  decoration: InputDecoration(
                    hintText: l.shamellFriendTagsHint,
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
