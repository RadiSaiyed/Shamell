import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat/shamell_chat_page.dart';
import 'l10n.dart';
import 'moments_page.dart';
import 'shamell_ui.dart';
import 'voip_call_page_stub.dart' if (dart.library.io) 'voip_call_page.dart';

class ShamellContactInfoPage extends StatefulWidget {
  final String baseUrl;
  final Map<String, dynamic> friend;
  final String peerId;
  final String displayName;
  final String alias;
  final String tags;
  final bool isCloseFriend;
  final void Function(Widget page) pushPage;

  const ShamellContactInfoPage({
    super.key,
    required this.baseUrl,
    required this.friend,
    required this.peerId,
    required this.displayName,
    required this.alias,
    required this.tags,
    required this.isCloseFriend,
    required this.pushPage,
  });

  @override
  State<ShamellContactInfoPage> createState() => _ShamellContactInfoPageState();
}

class _ShamellContactInfoPageState extends State<ShamellContactInfoPage> {
  bool _busy = false;
  late bool _closeFriend;
  late String _alias;
  late String _tags;

  @override
  void initState() {
    super.initState();
    _closeFriend = widget.isCloseFriend;
    _alias = widget.alias;
    _tags = widget.tags;
  }

  String _displayLetter() {
    final s = (_alias.trim().isNotEmpty ? _alias : widget.displayName).trim();
    if (s.isNotEmpty) return s.substring(0, 1).toUpperCase();
    final id = widget.peerId.trim();
    if (id.isNotEmpty) return id.substring(0, 1).toUpperCase();
    return '?';
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

  Future<void> _saveAliasTagsToPrefs({
    required String alias,
    required String tagsText,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final peerId = widget.peerId;

    Map<String, dynamic> decode(String key) {
      final raw = sp.getString(key) ?? '{}';
      try {
        return (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {
        return <String, dynamic>{};
      }
    }

    final aliases = decode('friends.aliases');
    if (alias.isEmpty) {
      aliases.remove(peerId);
    } else {
      aliases[peerId] = alias;
    }
    await sp.setString('friends.aliases', jsonEncode(aliases));

    final tags = decode('friends.tags');
    if (tagsText.isEmpty) {
      tags.remove(peerId);
    } else {
      tags[peerId] = tagsText;
    }
    await sp.setString('friends.tags', jsonEncode(tags));
  }

  Future<void> _openRemarksTags() async {
    final res = await Navigator.of(context).push<_ShamellRemarksResult?>(
      MaterialPageRoute(
        builder: (_) => _ShamellRemarksTagsPage(
          initialAlias: _alias,
          initialTags: _tags,
        ),
      ),
    );
    if (!mounted || res == null) return;
    final alias = res.alias.trim();
    final tagsText = res.tags.trim();
    setState(() {
      _alias = alias;
      _tags = tagsText;
    });
    await _runBusy(() async {
      await _saveAliasTagsToPrefs(alias: alias, tagsText: tagsText);
    });
  }

  Future<void> _toggleCloseFriend(bool value) async {
    final next = value;
    setState(() {
      _closeFriend = next;
      widget.friend['close'] = next;
    });
    await _runBusy(() async {
      try {
        final sp = await SharedPreferences.getInstance();
        final rawClose = sp.getString('friends.close') ?? '{}';
        Map<String, dynamic> decodedClose;
        try {
          decodedClose = jsonDecode(rawClose) as Map<String, dynamic>;
        } catch (_) {
          decodedClose = <String, dynamic>{};
        }
        if (next) {
          decodedClose[widget.peerId] = true;
        } else {
          decodedClose.remove(widget.peerId);
        }
        await sp.setString('friends.close', jsonEncode(decodedClose));
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _closeFriend = !next;
          widget.friend['close'] = _closeFriend;
        });
      }
    });
  }

  void _openChat() {
    final peerId = widget.peerId.trim();
    if (peerId.isEmpty) return;
    widget.pushPage(
      ShamellChatPage(
        baseUrl: widget.baseUrl,
        initialPeerId: peerId,
      ),
    );
  }

  void _startCall(String mode) {
    final peerId = widget.peerId.trim();
    if (peerId.isEmpty) return;
    final name =
        (_alias.trim().isNotEmpty ? _alias.trim() : widget.displayName).trim();
    widget.pushPage(
      VoipCallPage(
        baseUrl: widget.baseUrl,
        peerId: peerId,
        displayName: name.isEmpty ? peerId : name,
        mode: mode,
      ),
    );
  }

  void _openFriendTimeline() {
    final l = L10n.of(context);
    final phone = (widget.friend['phone'] ?? '').toString().trim();
    final id = (widget.friend['id'] ?? '').toString().trim();
    final authorId =
        phone.isNotEmpty ? phone : (id.isNotEmpty ? id : widget.peerId.trim());
    if (authorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              l.isArabic ? 'تعذر فتح اللحظات.' : 'Could not open Moments.'),
        ),
      );
      return;
    }
    final name =
        (_alias.trim().isNotEmpty ? _alias.trim() : widget.displayName).trim();
    widget.pushPage(
      MomentsPage(
        baseUrl: widget.baseUrl,
        timelineAuthorId: authorId,
        timelineAuthorName: name.isEmpty ? null : name,
        showComposer: false,
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

    Icon chevron({bool enabled = true}) => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface
              .withValues(alpha: enabled ? .40 : .20),
        );

    final headerName =
        (_alias.trim().isNotEmpty ? _alias.trim() : widget.displayName.trim())
            .trim();

    final subtitleParts = <String>[];
    if (widget.displayName.trim().isNotEmpty &&
        widget.displayName.trim() != headerName) {
      subtitleParts.add(widget.displayName.trim());
    }
    if (_tags.trim().isNotEmpty) subtitleParts.add(_tags.trim());

    final canTap = !_busy;

    Widget header() {
      final isDark = theme.brightness == Brightness.dark;
      final actionBg = isDark
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35)
          : ShamellPalette.searchFill;
      final actionFg = isDark
          ? theme.colorScheme.onSurface.withValues(alpha: .90)
          : ShamellPalette.green;

      Widget quickAction({
        required IconData icon,
        required String label,
        required VoidCallback onTap,
      }) {
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: canTap ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: actionBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 26, color: actionFg),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: .72),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Container(
        color: theme.colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: .16),
                  child: Text(
                    _displayLetter(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerName.isEmpty ? widget.peerId : headerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitleParts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitleParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .55),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${l.shamellContactChatIdPrefix} ${widget.peerId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                quickAction(
                  icon: Icons.chat_bubble_outline,
                  label: l.isArabic ? 'رسالة' : 'Message',
                  onTap: _openChat,
                ),
                quickAction(
                  icon: Icons.call_outlined,
                  label: l.isArabic ? 'مكالمة صوتية' : 'Voice call',
                  onTap: () => _startCall('audio'),
                ),
                quickAction(
                  icon: Icons.videocam_outlined,
                  label: l.isArabic ? 'مكالمة فيديو' : 'Video call',
                  onTap: () => _startCall('video'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.shamellContactInfoTitle),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 0, bottom: 24),
        children: [
          header(),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.isArabic ? 'اللحظات' : 'Moments'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: isDark ? .30 : .55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: isDark ? .30 : .55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: isDark ? .30 : .55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    chevron(enabled: canTap),
                  ],
                ),
                onTap: canTap ? _openFriendTimeline : null,
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
                  l.isArabic ? 'ملاحظة ووسوم' : 'Set Remarks and Tags',
                ),
                subtitle: _alias.trim().isEmpty && _tags.trim().isEmpty
                    ? null
                    : Text(
                        [_alias.trim(), _tags.trim()]
                            .where((e) => e.isNotEmpty)
                            .join(' · '),
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
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                enabled: canTap,
                title: Text(l.shamellFriendsCloseLabel),
                trailing: Switch(
                  value: _closeFriend,
                  onChanged: canTap ? _toggleCloseFriend : null,
                ),
                onTap: canTap ? () => _toggleCloseFriend(!_closeFriend) : null,
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
  final String initialAlias;
  final String initialTags;

  const _ShamellRemarksTagsPage({
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
