import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'app_flags.dart' show kEnduserOnly;
import 'chat/chat_service.dart';
import 'l10n.dart';
import 'safe_clipboard.dart';
import 'safe_set_state.dart';
import 'shamell_ui.dart';

class ShamellGroupMemberDisplay {
  final String id;
  final String name;
  final bool isAdmin;
  final bool isMe;

  const ShamellGroupMemberDisplay({
    required this.id,
    required this.name,
    this.isAdmin = false,
    this.isMe = false,
  });
}

class ShamellGroupChatInfoPage extends StatefulWidget {
  final String baseUrl;
  final String groupId;
  final String groupName;
  final Uint8List? avatarBytes;
  final List<ShamellGroupMemberDisplay> members;
  final List<Uint8List> mediaPreview;
  final int mediaCount;
  final int fileCount;
  final int linkCount;
  final int voiceCount;
  final bool isAdmin;
  final bool muted;
  final bool pinned;
  final String themeKey;

  final Future<void> Function(bool muted) onToggleMuted;
  final Future<void> Function(bool pinned) onTogglePinned;
  final Future<void> Function(String themeKey) onSetTheme;

  final Future<void> Function() onShowMembers;
  final Future<void> Function() onInviteMembers;
  final Future<void> Function()? onSearchInChat;
  final Future<void> Function()? onOpenMedia;
  final Future<void> Function()? onSendGreenPaket;
  final Future<void> Function()? onShareMiniProgram;
  final Future<Uri?> Function()? onCreateSecureInviteLink;
  final Future<void> Function() onEditGroup;
  final Future<void> Function() onShowKeyEvents;
  final Future<void> Function() onRotateKey;
  final Future<void> Function() onClearChatHistory;
  final Future<void> Function() onLeaveGroup;

  const ShamellGroupChatInfoPage({
    super.key,
    required this.baseUrl,
    required this.groupId,
    required this.groupName,
    this.avatarBytes,
    this.members = const <ShamellGroupMemberDisplay>[],
    this.mediaPreview = const <Uint8List>[],
    this.mediaCount = 0,
    this.fileCount = 0,
    this.linkCount = 0,
    this.voiceCount = 0,
    this.isAdmin = false,
    this.muted = false,
    this.pinned = false,
    this.themeKey = 'default',
    required this.onToggleMuted,
    required this.onTogglePinned,
    required this.onSetTheme,
    required this.onShowMembers,
    required this.onInviteMembers,
    this.onSearchInChat,
    this.onOpenMedia,
    this.onSendGreenPaket,
    this.onShareMiniProgram,
    this.onCreateSecureInviteLink,
    required this.onEditGroup,
    required this.onShowKeyEvents,
    required this.onRotateKey,
    required this.onClearChatHistory,
    required this.onLeaveGroup,
  });

  @override
  State<ShamellGroupChatInfoPage> createState() =>
      _ShamellGroupChatInfoPageState();
}

class _ShamellGroupChatInfoPageState extends State<ShamellGroupChatInfoPage>
    with SafeSetStateMixin<ShamellGroupChatInfoPage> {
  bool _busy = false;
  late bool _muted;
  late bool _pinned;
  late String _themeKey;
  String _notice = '';
  final ChatLocalStore _store = ChatLocalStore();

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
    _pinned = widget.pinned;
    _themeKey = widget.themeKey;
    _loadNotice();
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

  Future<void> _toggleMuted(bool value) async {
    final prev = _muted;
    final next = value;
    setState(() => _muted = next);
    final ok = await _runBusy(() => widget.onToggleMuted(next));
    if (!ok && mounted) {
      setState(() => _muted = prev);
    }
  }

  Future<void> _togglePinned(bool value) async {
    final prev = _pinned;
    final next = value;
    setState(() => _pinned = next);
    final ok = await _runBusy(() => widget.onTogglePinned(next));
    if (!ok && mounted) {
      setState(() => _pinned = prev);
    }
  }

  Future<void> _loadNotice() async {
    try {
      final raw = (await _store.loadGroupNotice(
                widget.groupId,
                baseUrlOverride: widget.baseUrl,
              ) ??
              '')
          .trim();
      if (!mounted) return;
      setState(() => _notice = raw);
    } catch (_) {}
  }

  Future<void> _saveNotice(String notice) async {
    try {
      await _store.saveGroupNotice(
        widget.groupId,
        notice,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
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
    await _runBusy(() => widget.onSetTheme(picked));
  }

  Future<void> _openGroupNotice() async {
    final l = L10n.of(context);
    final res = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _ShamellGroupNoticePage(
          groupName: widget.groupName,
          initialNotice: _notice,
          canEdit: widget.isAdmin,
        ),
      ),
    );
    if (!mounted || res == null) return;
    final next = res.trim();
    setState(() => _notice = next);
    await _saveNotice(next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.isArabic ? 'تم الحفظ' : 'Saved')),
    );
  }

  Future<void> _confirmClearHistory() async {
    final l = L10n.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.shamellClearChatHistory),
        content: Text(
          l.isArabic
              ? 'سيتم مسح كل رسائل هذه المجموعة من هذا الجهاز.'
              : 'All messages in this group will be cleared from this device.',
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

  Future<void> _confirmLeaveGroup() async {
    final l = L10n.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'مغادرة المجموعة' : 'Leave group'),
        content: Text(
          l.isArabic
              ? 'هل تريد مغادرة هذه المجموعة؟'
              : 'Do you want to leave this group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.shamellDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l.isArabic ? 'مغادرة' : 'Leave',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    Navigator.of(context).pop();
    await widget.onLeaveGroup();
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
    final members = widget.members;
    final memberCount = members.length;
    final groupName = widget.groupName.trim().isEmpty
        ? (l.isArabic ? 'مجموعة' : 'Group')
        : widget.groupName.trim();
    final notice = _notice.trim();
    final noticeLine = notice.replaceAll('\n', ' ').trim();

    void toast(String msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    Future<void> tryInviteMembers() async {
      if (!widget.isAdmin) {
        toast(l.isArabic ? 'فقط للمشرفين.' : 'Admins only.');
        return;
      }
      await widget.onInviteMembers();
    }

    Future<void> showGroupLinkSheet() async {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final t = Theme.of(ctx);
          final avatarBytes = widget.avatarBytes;
          Uri? inviteUri;
          var creatingInvite = false;
          var inviteError = '';

          Future<void> createInvite(StateSetter setModalState) async {
            final create = widget.onCreateSecureInviteLink;
            if (create == null) {
              setModalState(() {
                inviteError = l.isArabic
                    ? 'الدعوة الآمنة غير متاحة الآن.'
                    : 'Secure invite is not available right now.';
              });
              return;
            }
            setModalState(() {
              creatingInvite = true;
              inviteError = '';
            });
            try {
              final uri = await create();
              if (!ctx.mounted) return;
              setModalState(() {
                inviteUri = uri;
                creatingInvite = false;
                inviteError = uri == null
                    ? (l.isArabic
                        ? 'تعذّر إنشاء الدعوة.'
                        : 'Could not create invite.')
                    : '';
              });
            } catch (_) {
              if (!ctx.mounted) return;
              setModalState(() {
                creatingInvite = false;
                inviteError = l.isArabic
                    ? 'تعذّر إنشاء الدعوة.'
                    : 'Could not create invite.';
              });
            }
          }

          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final inviteText = inviteUri?.toString() ?? '';
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.isArabic
                              ? 'روابط المجموعة معطلة'
                              : 'Group links are disabled',
                          style: t.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.isArabic
                              ? 'تم تعطيل QR وروابط المجموعة المباشرة للحماية. استخدم دعوة آمنة بدلاً من مشاركة معرف مجموعة ثابت.'
                              : 'Direct group QR and deep links are disabled for safety. Use a secure invite instead of sharing a stable group ID.',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyMedium?.copyWith(
                            color:
                                t.colorScheme.onSurface.withValues(alpha: .72),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 54,
                            height: 54,
                            color: t.colorScheme.primaryContainer,
                            alignment: Alignment.center,
                            child: avatarBytes == null
                                ? Icon(
                                    Icons.groups_outlined,
                                    color: t.colorScheme.onSurface.withValues(
                                      alpha: .65,
                                    ),
                                  )
                                : Image.memory(
                                    avatarBytes,
                                    width: 54,
                                    height: 54,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          groupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (inviteText.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: .06),
                              ),
                            ),
                            child: QrImageView(
                              data: inviteText,
                              size: 188,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            inviteText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: t.colorScheme.onSurface
                                  .withValues(alpha: .60),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await shamellCopyToClipboard(
                                      inviteText,
                                      sensitive: true,
                                    );
                                    toast(
                                      l.isArabic
                                          ? 'تم نسخ الدعوة.'
                                          : 'Invite copied.',
                                    );
                                  },
                                  icon: const Icon(Icons.copy_rounded),
                                  label: Text(l.isArabic ? 'نسخ' : 'Copy'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: ShamellPalette.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => Share.share(inviteText),
                                  icon: const Icon(Icons.ios_share_rounded),
                                  label: Text(
                                    l.isArabic ? 'مشاركة' : 'Share',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (inviteError.isNotEmpty) ...[
                          Text(
                            inviteError,
                            textAlign: TextAlign.center,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: t.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            if (widget.isAdmin) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    Navigator.of(ctx).pop();
                                    await tryInviteMembers();
                                  },
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: Text(
                                    l.isArabic
                                        ? 'دعوة أعضاء'
                                        : 'Invite members',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: ShamellPalette.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: creatingInvite
                                    ? null
                                    : () => unawaited(
                                          createInvite(setModalState),
                                        ),
                                icon: creatingInvite
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.qr_code_2_rounded),
                                label: Text(
                                  inviteText.isEmpty
                                      ? (l.isArabic
                                          ? 'إنشاء QR آمن'
                                          : 'Create QR')
                                      : (l.isArabic
                                          ? 'تجديد QR'
                                          : 'Refresh QR'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    Future<void> tryEditGroup() async {
      if (!widget.isAdmin) {
        toast(l.isArabic ? 'فقط للمشرفين.' : 'Admins only.');
        return;
      }
      await widget.onEditGroup();
    }

    Widget memberGrid() {
      const crossAxisCount = 5;
      const maxPreview = 18;
      final preview = members.take(maxPreview).toList();
      final showRemove = widget.isAdmin;

      List<_MemberCell> cells = [
        for (final m in preview)
          _MemberCell.member(
            id: m.id,
            name: m.name,
            isMe: m.isMe,
          ),
        _MemberCell.action(
          icon: Icons.add,
          label: l.isArabic ? 'إضافة' : 'Add',
          onTap: canTap ? () => tryInviteMembers() : null,
        ),
        if (showRemove)
          _MemberCell.action(
            icon: Icons.remove,
            label: l.isArabic ? 'إزالة' : 'Remove',
            onTap: canTap ? widget.onShowMembers : null,
          ),
      ];

      return LayoutBuilder(
        builder: (ctx, constraints) {
          final maxWidth = constraints.maxWidth;
          const spacing = 12.0;
          final tileWidth =
              (maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
          return Wrap(
            spacing: spacing,
            runSpacing: 12,
            children: [
              for (final c in cells)
                SizedBox(
                  width: tileWidth,
                  child: c.build(ctx),
                ),
            ],
          );
        },
      );
    }

    Widget groupHero() {
      final avatarBytes = widget.avatarBytes;
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 58,
              height: 58,
              color: ShamellPalette.green.withValues(alpha: isDark ? .20 : .12),
              alignment: Alignment.center,
              child: avatarBytes == null
                  ? Icon(
                      Icons.groups_outlined,
                      color: theme.colorScheme.onSurface.withValues(alpha: .68),
                    )
                  : Image.memory(
                      avatarBytes,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l.isArabic ? '$memberCount أعضاء' : '$memberCount members',
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
                    if (_pinned)
                      _GroupInfoPill(
                        icon: Icons.push_pin_outlined,
                        label: l.isArabic ? 'مثبتة' : 'Pinned',
                        color: const Color(0xFFF59E0B),
                      ),
                    if (_muted)
                      _GroupInfoPill(
                        icon: Icons.notifications_off_outlined,
                        label: l.isArabic ? 'مكتومة' : 'Muted',
                        color: const Color(0xFF64748B),
                      ),
                    _GroupInfoPill(
                      icon: widget.isAdmin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.lock_outline,
                      label: widget.isAdmin
                          ? (l.isArabic ? 'مشرف' : 'Admin')
                          : (l.isArabic ? 'عضو' : 'Member'),
                      color: ShamellPalette.green,
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
      bool enabled = true,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: canTap && enabled ? onTap : null,
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
              widget.onSearchInChat?.call();
            },
            enabled: widget.onSearchInChat != null,
          ),
          quickAction(
            icon: Icons.photo_library_outlined,
            label: l.isArabic ? 'وسائط' : 'Media',
            color: ShamellPalette.green,
            onTap: () {
              widget.onOpenMedia?.call();
            },
            enabled: widget.onOpenMedia != null,
          ),
          quickAction(
            icon: Icons.person_add_alt_1_outlined,
            label: l.isArabic ? 'دعوة' : 'Invite',
            color: const Color(0xFFF59E0B),
            onTap: () {
              tryInviteMembers();
            },
            enabled: widget.isAdmin,
          ),
          quickAction(
            icon: Icons.qr_code_2_outlined,
            label: l.isArabic ? 'QR' : 'QR',
            color: const Color(0xFF111827),
            onTap: () {
              showGroupLinkSheet();
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
      Widget thumb(Widget child) {
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: isDark ? .20 : .35),
              width: .6,
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
              thumb(Image.memory(previews[i], fit: BoxFit.cover))
            else
              thumb(
                Center(
                  child: Icon(
                    i == 0
                        ? Icons.image_outlined
                        : i == 1
                            ? Icons.link
                            : Icons.description_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: .45),
                  ),
                ),
              ),
          ],
          const SizedBox(width: 8),
          chevron(enabled: canTap && widget.onOpenMedia != null),
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
                    groupHero(),
                    const SizedBox(height: 14),
                    quickActions(),
                    const SizedBox(height: 12),
                    memberGrid(),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'الأعضاء' : 'Members'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$memberCount',
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
                onTap: canTap ? widget.onShowMembers : null,
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 13,
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
            dividerEndIndent: 12,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'اسم المجموعة' : 'Group chat name'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: canTap ? .55 : .30),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    chevron(enabled: canTap),
                  ],
                ),
                onTap: canTap ? tryEditGroup : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'روابط المجموعة' : 'Group links'),
                subtitle: Text(
                  l.isArabic
                      ? 'QR آمن بدون مشاركة معرف ثابت'
                      : 'Secure QR without a stable group ID',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: chevron(enabled: canTap),
                onTap: canTap
                    ? () {
                        showGroupLinkSheet();
                      }
                    : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'إعلان المجموعة' : 'Group Notice'),
                subtitle: Text(
                  noticeLine.isNotEmpty
                      ? noticeLine
                      : (l.isArabic ? 'غير مضبوط' : 'Not set'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: chevron(enabled: canTap),
                onTap: canTap ? _openGroupNotice : null,
              ),
            ],
          ),
          if (widget.onSearchInChat != null || widget.onOpenMedia != null)
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
                if (widget.onSearchInChat != null)
                  ListTile(
                    dense: true,
                    enabled: canTap,
                    title: Text(l.isArabic
                        ? 'بحث في سجل الدردشة'
                        : 'Search Chat History'),
                    trailing: chevron(enabled: canTap),
                    onTap: canTap
                        ? () {
                            widget.onSearchInChat?.call();
                          }
                        : null,
                  ),
                if (widget.onOpenMedia != null)
                  ListTile(
                    dense: true,
                    enabled: canTap,
                    title: Text(l.isArabic
                        ? 'الوسائط والروابط والملفات'
                        : 'Media, Links, and Files'),
                    trailing: mediaTrailing(),
                    onTap: canTap
                        ? () {
                            widget.onOpenMedia?.call();
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
                enabled: canTap && widget.onSendGreenPaket != null,
                leading: const ShamellLeadingIcon(
                  icon: Icons.card_giftcard_outlined,
                  background: Color(0xFF16A34A),
                ),
                title: Text(l.isArabic ? 'الحزمة الخضراء' : 'Green Paket'),
                subtitle: Text(
                  l.isArabic
                      ? 'أرسل حزمة دفع اجتماعية إلى هذه المجموعة'
                      : 'Send a social payment gift to this group',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: chevron(
                  enabled: canTap && widget.onSendGreenPaket != null,
                ),
                onTap: canTap && widget.onSendGreenPaket != null
                    ? widget.onSendGreenPaket
                    : null,
              ),
              ListTile(
                dense: true,
                enabled: canTap && widget.onShareMiniProgram != null,
                leading: const ShamellLeadingIcon(
                  icon: Icons.widgets_outlined,
                  background: Color(0xFF7C3AED),
                ),
                title: Text(l.isArabic ? 'برنامج مصغّر' : 'Mini Program'),
                subtitle: Text(
                  l.isArabic
                      ? 'شارك خدمة قابلة للفتح داخل الدردشة'
                      : 'Share an openable service card in chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: chevron(
                  enabled: canTap && widget.onShareMiniProgram != null,
                ),
                onTap: canTap && widget.onShareMiniProgram != null
                    ? widget.onShareMiniProgram
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
          if (widget.isAdmin && !kEnduserOnly)
            ShamellSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  dense: true,
                  enabled: canTap,
                  title: Text(
                    l.isArabic ? 'سجل تدوير المفاتيح' : 'Key rotation log',
                  ),
                  trailing: chevron(enabled: canTap),
                  onTap: canTap ? widget.onShowKeyEvents : null,
                ),
                ListTile(
                  dense: true,
                  enabled: canTap,
                  title: Text(
                    l.isArabic
                        ? 'تدوير مفتاح التشفير'
                        : 'Rotate encryption key',
                  ),
                  trailing: chevron(enabled: canTap),
                  onTap: canTap ? widget.onRotateKey : null,
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
              ListTile(
                dense: true,
                enabled: canTap,
                title: Center(
                  child: Text(
                    l.isArabic ? 'مغادرة المجموعة' : 'Leave group',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                onTap: canTap ? _confirmLeaveGroup : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberCell {
  final String id;
  final String name;
  final bool isMe;
  final IconData? actionIcon;
  final VoidCallback? onTap;

  const _MemberCell._({
    required this.id,
    required this.name,
    required this.isMe,
    required this.actionIcon,
    required this.onTap,
  });

  factory _MemberCell.member({
    required String id,
    required String name,
    required bool isMe,
  }) {
    return _MemberCell._(
      id: id,
      name: name,
      isMe: isMe,
      actionIcon: null,
      onTap: null,
    );
  }

  factory _MemberCell.action({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return _MemberCell._(
      id: '',
      name: label,
      isMe: false,
      actionIcon: icon,
      onTap: onTap,
    );
  }

  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayName = name.trim().isNotEmpty ? name.trim() : id.trim();
    final letter = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : '?';
    final isAction = actionIcon != null;

    Widget avatar() {
      if (isAction) {
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
            actionIcon,
            size: 26,
            color: theme.colorScheme.onSurface.withValues(alpha: .55),
          ),
        );
      }
      final bg = isMe
          ? theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isDark ? .45 : .90,
            )
          : theme.colorScheme.primary.withValues(alpha: isDark ? .22 : .16);
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 54,
          height: 54,
          color: bg,
          alignment: Alignment.center,
          child: Text(
            letter,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    final label = displayName;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        children: [
          avatar(),
          const SizedBox(height: 6),
          Text(
            label,
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
}

class _GroupInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _GroupInfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
}

class _ShamellGroupNoticePage extends StatefulWidget {
  final String groupName;
  final String initialNotice;
  final bool canEdit;

  const _ShamellGroupNoticePage({
    required this.groupName,
    required this.initialNotice,
    required this.canEdit,
  });

  @override
  State<_ShamellGroupNoticePage> createState() =>
      _ShamellGroupNoticePageState();
}

class _ShamellGroupNoticePageState extends State<_ShamellGroupNoticePage> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialNotice);
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.canEdit && widget.initialNotice.trim().isEmpty;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    final notice = _ctrl.text.trim();
    final hint =
        l.isArabic ? 'اكتب إعلاناً للمجموعة…' : 'Write a group notice…';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'إعلان المجموعة' : 'Group Notice'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          if (widget.canEdit)
            TextButton(
              onPressed:
                  _editing ? _save : () => setState(() => _editing = true),
              child: Text(
                _editing ? l.settingsSave : (l.isArabic ? 'تعديل' : 'Edit'),
              ),
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
                title: Text(l.isArabic ? 'الإعلان' : 'Notice'),
                subtitle: _editing
                    ? TextField(
                        controller: _ctrl,
                        autofocus: true,
                        minLines: 4,
                        maxLines: 12,
                        decoration: InputDecoration(
                          hintText: hint,
                          border: InputBorder.none,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          notice.isNotEmpty
                              ? notice
                              : (l.isArabic ? 'غير مضبوط' : 'Not set'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                                alpha: notice.isNotEmpty ? .88 : .55),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (widget.canEdit && _editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                l.isArabic
                    ? 'سيتم عرض الإعلان لجميع أعضاء المجموعة.'
                    : 'The notice will be visible to all members.',
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
