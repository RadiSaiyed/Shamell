import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flags.dart' show kEnduserOnly;
import 'l10n.dart';
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
  final String groupId;
  final String groupName;
  final Uint8List? avatarBytes;
  final List<ShamellGroupMemberDisplay> members;
  final bool isAdmin;
  final bool muted;
  final bool pinned;
  final String themeKey;

  final Future<void> Function(bool muted) onToggleMuted;
  final Future<void> Function(bool pinned) onTogglePinned;
  final Future<void> Function(String themeKey) onSetTheme;

  final Future<void> Function() onShowMembers;
  final Future<void> Function() onInviteMembers;
  final Future<void> Function() onEditGroup;
  final Future<void> Function() onShowKeyEvents;
  final Future<void> Function() onRotateKey;
  final Future<void> Function() onClearChatHistory;
  final Future<void> Function() onLeaveGroup;

  const ShamellGroupChatInfoPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.avatarBytes,
    this.members = const <ShamellGroupMemberDisplay>[],
    this.isAdmin = false,
    this.muted = false,
    this.pinned = false,
    this.themeKey = 'default',
    required this.onToggleMuted,
    required this.onTogglePinned,
    required this.onSetTheme,
    required this.onShowMembers,
    required this.onInviteMembers,
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

  static String _noticePrefKey(String groupId) =>
      'chat.group_notice.${groupId.trim()}';

  Future<void> _loadNotice() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = (sp.getString(_noticePrefKey(widget.groupId)) ?? '').trim();
      if (!mounted) return;
      setState(() => _notice = raw);
    } catch (_) {}
  }

  Future<void> _saveNotice(String notice) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = notice.trim();
      final key = _noticePrefKey(widget.groupId);
      if (v.isEmpty) {
        await sp.remove(key);
      } else {
        await sp.setString(key, v);
      }
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

    Future<void> showQrSheet() async {
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
          final isDark = t.brightness == Brightness.dark;
          final payload = 'shamell://group/${widget.groupId}';
          final avatarBytes = widget.avatarBytes;

          void copy() {
            Clipboard.setData(ClipboardData(text: payload));
            Navigator.of(ctx).pop();
            toast(l.isArabic ? 'تم النسخ' : 'Copied');
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.isArabic ? 'رمز QR للمجموعة' : 'Group QR Code',
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: t.dividerColor
                            .withValues(alpha: isDark ? .20 : .35),
                        width: 0.6,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 196,
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
                  const SizedBox(height: 4),
                  Text(
                    widget.groupId.trim().isNotEmpty ? widget.groupId : payload,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurface.withValues(alpha: .60),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: copy,
                          icon: const Icon(Icons.copy),
                          label: Text(l.isArabic ? 'نسخ' : 'Copy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: ShamellPalette.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(l.isArabic ? 'تم' : 'Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    Future<void> tryInviteMembers() async {
      if (!widget.isAdmin) {
        toast(l.isArabic ? 'فقط للمشرفين.' : 'Admins only.');
        return;
      }
      await widget.onInviteMembers();
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
                child: memberGrid(),
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
            dividerEndIndent: 16,
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
                title: Text(l.isArabic ? 'رمز QR للمجموعة' : 'Group QR Code'),
                trailing: chevron(enabled: canTap),
                onTap: canTap ? showQrSheet : null,
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
