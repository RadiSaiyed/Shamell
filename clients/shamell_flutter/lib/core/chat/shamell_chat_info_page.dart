import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../safe_clipboard.dart';
import '../safe_set_state.dart';
import '../shamell_ui.dart';

class ShamellChatInfoPage extends StatefulWidget {
  final String myDisplayName;
  final String displayName;
  final String peerId;
  final String? subtitle;
  /// Cycle 59 — peer's published profile status. The page renders a
  /// single line "🌴 vacation" near the top when either is set.
  final String? peerStatusEmoji;
  final String? peerStatusText;
  final String alias;
  final String tags;
  final String themeKey;
  final List<Uint8List> mediaPreview;
  final int mediaCount;
  final int fileCount;
  final int linkCount;
  final int voiceCount;
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

  /// Cycle 63 — current per-conversation notification preview mode,
  /// or `'default'` when the chat inherits the device-wide setting.
  /// One of: `default` / `full` / `name_only` / `silent`.
  final String notificationPreviewMode;

  /// Cycle 63 — invoked when the user picks a new mode. The chat
  /// page persists it through `ChatService.setConversationNotificationPref`.
  final Future<void> Function(String mode) onSetNotificationPreviewMode;

  /// Cycle 3D: optional callback that opens the system gallery, copies
  /// the chosen image into app-private storage, and returns the absolute
  /// path of the persisted copy. The info page feeds that path back
  /// through [onSetTheme] as `wallpaper:<path>`. Pass `null` to hide the
  /// "Pick from gallery" entry in the theme picker (e.g. for surfaces
  /// where wallpapers are unsupported or when image_picker is unavailable).
  final Future<String?> Function()? onPickWallpaperFile;

  const ShamellChatInfoPage({
    super.key,
    this.myDisplayName = '',
    required this.displayName,
    required this.peerId,
    this.subtitle,
    this.peerStatusEmoji,
    this.peerStatusText,
    this.alias = '',
    this.tags = '',
    this.themeKey = 'default',
    this.mediaPreview = const <Uint8List>[],
    this.mediaCount = 0,
    this.fileCount = 0,
    this.linkCount = 0,
    this.voiceCount = 0,
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
    this.onPickWallpaperFile,
    this.notificationPreviewMode = 'default',
    required this.onSetNotificationPreviewMode,
  });

  @override
  State<ShamellChatInfoPage> createState() => _ShamellChatInfoPageState();
}

class _ShamellChatInfoPageState extends State<ShamellChatInfoPage>
    with SafeSetStateMixin<ShamellChatInfoPage> {
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
  late String _previewMode;

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
    _previewMode = widget.notificationPreviewMode;
  }

  Future<bool> _runBusy(Future<void> Function() op) async {
    if (_busy) return false;
    var ok = true;
    setState(() => _busy = true);
    try {
      await op();
    } catch (_) {
      ok = false;
      if (mounted) {
        final l = L10n.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر إكمال العملية.'
                  : 'Could not complete action.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    return ok;
  }

  Future<void> _copyToClipboard(String text, {bool sensitive = false}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await shamellCopyToClipboard(
        t,
        sensitive: sensitive,
      );
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
    final prev = _muted;
    final next = value;
    setState(() => _muted = next);
    final ok = await _runBusy(() async {
      await widget.onToggleMuted(next);
    });
    if (!ok && mounted) {
      setState(() => _muted = prev);
    }
  }

  Future<void> _togglePinned(bool value) async {
    final prev = _pinned;
    final next = value;
    setState(() => _pinned = next);
    final ok = await _runBusy(() async {
      await widget.onTogglePinned(next);
    });
    if (!ok && mounted) {
      setState(() => _pinned = prev);
    }
  }

  /// Cycle 63 — human-readable label for the notification preview
  /// mode shown as the picker's subtitle.
  String _previewModeLabel(L10n l, String mode) {
    final isAr = l.isArabic;
    switch (mode) {
      case 'full':
        return isAr ? 'محتوى كامل' : 'Show full preview';
      case 'name_only':
        return isAr ? 'الاسم فقط' : 'Sender name only';
      case 'silent':
        return isAr ? 'صامت' : 'Silent (count only)';
      case 'default':
      default:
        return isAr ? 'الإعداد الافتراضي للجهاز' : 'Device default';
    }
  }

  /// Cycle 63 — bottom-sheet picker for the four preview modes.
  Future<void> _openNotificationPreviewPicker() async {
    final l = L10n.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget row(String mode, IconData icon, String label, String desc) {
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            subtitle: Text(desc),
            trailing: _previewMode == mode
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () => Navigator.of(ctx).pop(mode),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              row(
                'default',
                Icons.settings_outlined,
                l.isArabic ? 'الإعداد الافتراضي' : 'Device default',
                l.isArabic
                    ? 'استخدم إعداد الإشعارات للتطبيق'
                    : 'Inherit the app-wide setting',
              ),
              row(
                'full',
                Icons.notifications_active_outlined,
                l.isArabic ? 'محتوى كامل' : 'Show full preview',
                l.isArabic
                    ? 'يعرض المرسل ونص الرسالة'
                    : 'Show sender + message body',
              ),
              row(
                'name_only',
                Icons.notifications_outlined,
                l.isArabic ? 'الاسم فقط' : 'Sender name only',
                l.isArabic
                    ? 'يعرض المرسل دون نص الرسالة'
                    : 'Show "X sent a message", hide the body',
              ),
              row(
                'silent',
                Icons.notifications_off_outlined,
                l.isArabic ? 'صامت' : 'Silent',
                l.isArabic
                    ? 'تحديث العدد فقط، دون إشعار'
                    : 'Update the badge count only',
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == _previewMode || !mounted) return;
    final prev = _previewMode;
    setState(() => _previewMode = picked);
    final ok = await _runBusy(() async {
      await widget.onSetNotificationPreviewMode(picked);
    });
    if (!ok && mounted) {
      setState(() => _previewMode = prev);
    }
  }

  Future<void> _toggleHidden(bool value) async {
    final prev = _hidden;
    final next = value;
    setState(() => _hidden = next);
    final ok = await _runBusy(() async {
      await widget.onToggleHidden(next);
    });
    if (!ok && mounted) {
      setState(() => _hidden = prev);
    }
  }

  Future<void> _toggleBlocked(bool value) async {
    final prev = _blocked;
    final next = value;
    setState(() => _blocked = next);
    final ok = await _runBusy(() async {
      await widget.onToggleBlocked(next);
    });
    if (!ok && mounted) {
      setState(() => _blocked = prev);
    }
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
    if (_themeKey.startsWith('wallpaper:')) {
      // Cycle 3D: a custom wallpaper is active. We don't surface the
      // file path itself — that's noise — just a concise label.
      return l.isArabic ? 'خلفية مخصصة' : 'Custom wallpaper';
    }
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
    // Sentinel value used only inside the modal to mark "user wants the
    // gallery picker, not a named theme". We translate it after the
    // sheet closes so the rest of the flow keeps dealing in real theme
    // keys.
    const String pickWallpaperSentinel = '__pick_wallpaper__';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget tile(String value, String label, {IconData? icon}) {
          final selected = _themeKey == value;
          return ListTile(
            leading: icon == null ? null : Icon(icon),
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
              if (widget.onPickWallpaperFile != null) ...[
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(
                    l.isArabic ? 'صورة من المعرض...' : 'Image from gallery…',
                  ),
                  trailing: _themeKey.startsWith('wallpaper:')
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () =>
                      Navigator.of(ctx).pop(pickWallpaperSentinel),
                ),
              ],
            ],
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    String finalKey = picked;
    if (picked == pickWallpaperSentinel) {
      // Pop the picker first; image_picker spawns its own native UI and
      // we don't want it to race against the closing bottom sheet.
      final cb = widget.onPickWallpaperFile;
      if (cb == null) return;
      final newKey = await cb();
      if (!mounted || newKey == null || newKey.isEmpty) return;
      finalKey = newKey;
    }
    setState(() => _themeKey = finalKey);
    await _runBusy(() async {
      await widget.onSetTheme(finalKey);
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

    Widget statusPill({
      required IconData icon,
      required String label,
      required Color color,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? .18 : .10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    Widget profileHero() {
      final subtitle = (widget.subtitle ?? '').trim();
      final peerSubtitle = subtitle.isNotEmpty ? subtitle : widget.peerId;
      return Row(
        children: [
          memberAvatar(
            label: peerName,
            bg: ShamellPalette.green.withValues(alpha: isDark ? .20 : .12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // Cycle 59 — render the peer's published status under
                // their name when set. Compact one-liner with the
                // emoji + short text.
                Builder(builder: (_) {
                  final em = (widget.peerStatusEmoji ?? '').trim();
                  final tx = (widget.peerStatusText ?? '').trim();
                  if (em.isEmpty && tx.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      [
                        if (em.isNotEmpty) em,
                        if (tx.isNotEmpty) tx,
                      ].join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.primary.withValues(alpha: .85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 3),
                Text(
                  peerSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .62),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    statusPill(
                      icon: _verified
                          ? Icons.verified_outlined
                          : Icons.shield_outlined,
                      label: _verified
                          ? (l.isArabic ? 'موثوق' : 'Verified')
                          : (l.isArabic ? 'غير موثق' : 'Unverified'),
                      color: _verified
                          ? ShamellPalette.green
                          : const Color(0xFF64748B),
                    ),
                    if (_pinned)
                      statusPill(
                        icon: Icons.push_pin_outlined,
                        label: l.isArabic ? 'مثبت' : 'Pinned',
                        color: const Color(0xFFF59E0B),
                      ),
                    if (_muted)
                      statusPill(
                        icon: Icons.notifications_off_outlined,
                        label: l.isArabic ? 'مكتوم' : 'Muted',
                        color: const Color(0xFF64748B),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget quickAction({
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback? onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: canTap ? onTap : null,
            child: SizedBox(
              height: 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? .18 : .10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(icon, size: 19, color: color),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget quickActions() {
      return Row(
        children: [
          quickAction(
            icon: Icons.search,
            label: l.isArabic ? 'بحث' : 'Search',
            color: const Color(0xFF2563EB),
            onTap: () {
              widget.onSearchInChat();
            },
          ),
          quickAction(
            icon: Icons.photo_library_outlined,
            label: l.isArabic ? 'وسائط' : 'Media',
            color: ShamellPalette.green,
            onTap: () {
              widget.onOpenMedia();
            },
          ),
          quickAction(
            icon: Icons.star_outline,
            label: l.isArabic ? 'المفضلة' : 'Favorites',
            color: const Color(0xFFF59E0B),
            onTap: () {
              widget.onOpenFavorites();
            },
          ),
          quickAction(
            icon: Icons.group_add_outlined,
            label: l.isArabic ? 'مجموعة' : 'Group',
            color: const Color(0xFF7C3AED),
            onTap: () {
              _createGroupChatFromHere();
            },
          ),
        ],
      );
    }

    Widget mediaCountTile({
      required String label,
      required int count,
      required IconData icon,
      required Color color,
    }) {
      return Expanded(
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? .14 : .08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: color.withValues(alpha: isDark ? .24 : .14),
              width: .7,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .62),
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    profileHero(),
                    const SizedBox(height: 14),
                    quickActions(),
                    const SizedBox(height: 12),
                    membersGrid(),
                  ],
                ),
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 12,
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
              // Cycle 63 — per-chat notification preview picker.
              // Four options: device default (inherit), full preview,
              // sender-name-only, silent (count badge update only).
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic
                    ? 'محتوى الإشعار'
                    : 'Notification preview'),
                subtitle: Text(_previewModeLabel(l, _previewMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: canTap ? _openNotificationPreviewPicker : null,
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
                  _verified
                      ? l.shamellTrustedFingerprint
                      : l.shamellUnverifiedContact,
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
                      color: theme.colorScheme.onSurface.withValues(alpha: .80),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l.isArabic ? 'نسخ' : 'Copy',
                    onPressed: canTap
                        ? () => _copyToClipboard(
                              safetyRaw,
                              sensitive: true,
                            )
                        : null,
                    icon: const Icon(Icons.copy),
                  ),
                  onTap: canTap
                      ? () => _copyToClipboard(
                            safetyRaw,
                            sensitive: true,
                          )
                      : null,
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
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l.isArabic ? 'نسخ' : 'Copy',
                    onPressed: canTap
                        ? () => _copyToClipboard(
                              peerFp,
                              sensitive: true,
                            )
                        : null,
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
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l.isArabic ? 'نسخ' : 'Copy',
                    onPressed: canTap
                        ? () => _copyToClipboard(
                              myFp,
                              sensitive: true,
                            )
                        : null,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Row(
                  children: [
                    mediaCountTile(
                      label: l.isArabic ? 'وسائط' : 'Media',
                      count: widget.mediaCount,
                      icon: Icons.photo_library_outlined,
                      color: ShamellPalette.green,
                    ),
                    const SizedBox(width: 8),
                    mediaCountTile(
                      label: l.isArabic ? 'روابط' : 'Links',
                      count: widget.linkCount,
                      icon: Icons.link,
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 8),
                    mediaCountTile(
                      label: l.isArabic ? 'ملفات' : 'Files',
                      count: widget.fileCount,
                      icon: Icons.description_outlined,
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(
                    l.isArabic ? 'بحث في سجل الدردشة' : 'Search Chat History'),
                trailing: chevron(enabled: canTap),
                onTap: canTap
                    ? () {
                        widget.onSearchInChat();
                      }
                    : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic
                    ? 'الوسائط والروابط والملفات'
                    : 'Media, Links, and Files'),
                trailing: mediaTrailing(),
                onTap: canTap
                    ? () {
                        widget.onOpenMedia();
                      }
                    : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.shamellFavoritesTitle),
                trailing: chevron(enabled: canTap),
                onTap: canTap
                    ? () {
                        widget.onOpenFavorites();
                      }
                    : null,
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
  State<_ShamellRemarksTagsPage> createState() =>
      _ShamellRemarksTagsPageState();
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
