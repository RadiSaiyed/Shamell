import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'favorites_page.dart';
import 'friends_page.dart';
import 'l10n.dart';
import 'mini_program_runtime.dart';
import 'mini_programs_discover_page.dart';
import 'ui_kit.dart';
import 'glass.dart';
import 'chat/chat_models.dart';
import 'chat/chat_service.dart';
import 'chat/shamell_chat_page.dart';
import 'safe_set_state.dart';
import 'shamell_ui.dart';
import 'shamell_group_chat_info_page.dart';

enum _ShamellGroupComposerPanel { none, more }

class GroupChatsPage extends StatefulWidget {
  final String baseUrl;
  const GroupChatsPage({super.key, required this.baseUrl});

  @override
  State<GroupChatsPage> createState() => _GroupChatsPageState();
}

class _GroupChatsPageState extends State<GroupChatsPage>
    with SafeSetStateMixin<GroupChatsPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _deviceId;
  String _error = '';
  late final ChatService _service;
  List<ChatGroup> _groups = const <ChatGroup>[];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _service = ChatService(widget.baseUrl);
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final me = await ChatLocalStore().loadIdentity();
      if (me == null) {
        _deviceId = null;
        _groups = const <ChatGroup>[];
      } else {
        _deviceId = me.id;
        _groups = await _service.listGroups(deviceId: me.id);
      }
    } catch (e) {
      _error = sanitizeExceptionForUi(error: e);
      _groups = const <ChatGroup>[];
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _createGroup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    try {
      final g = await _service.createGroup(
        deviceId: did,
        name: name,
      );
      try {
        final store = ChatLocalStore();
        final existing = await store.loadGroupKey(g.id);
        if (existing == null || existing.isEmpty) {
          final rnd = Random.secure();
          final keyBytes = Uint8List.fromList(
              List<int>.generate(32, (_) => rnd.nextInt(256)));
          await store.saveGroupKey(g.id, base64Encode(keyBytes));
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _groups = <ChatGroup>[g, ..._groups];
        _nameCtrl.clear();
      });
      await _openGroup(g);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
      });
    }
  }

  Future<void> _openGroup(ChatGroup g) async {
    final id = g.id;
    if (id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          baseUrl: widget.baseUrl,
          groupId: id,
          groupName: g.name,
        ),
      ),
    );
    await _load();
  }

  Future<void> _showCreateGroupSheet() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final fieldFill = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : ShamellPalette.searchFill;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.isArabic ? 'مجموعة جديدة' : 'New group chat',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l.isArabic ? 'إغلاق' : 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l.isArabic ? 'اسم المجموعة' : 'Group name',
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    Navigator.of(ctx).pop();
                    _createGroup();
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ShamellPalette.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: (_deviceId == null || (_deviceId ?? '').isEmpty)
                      ? null
                      : () {
                          Navigator.of(ctx).pop();
                          _createGroup();
                        },
                  child: Text(l.isArabic ? 'إنشاء' : 'Create'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    List<ChatGroup> filteredGroups() {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return _groups;
      return _groups.where((g) {
        final name = g.name.toLowerCase();
        final id = g.id.toLowerCase();
        return name.contains(q) || id.contains(q);
      }).toList();
    }

    Widget avatarFor(ChatGroup g) {
      Uint8List? avatarBytes;
      final gAvatar = g.avatarB64;
      if (gAvatar != null && gAvatar.isNotEmpty) {
        try {
          avatarBytes = base64Decode(gAvatar);
        } catch (_) {}
      }
      final label =
          g.name.isNotEmpty ? g.name.characters.first.toUpperCase() : '#';
      final fallback = Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: avatarBytes == null
            ? fallback
            : Image.memory(
                avatarBytes,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
      );
    }

    Widget groupTile(ChatGroup g) {
      final name = g.name.trim();
      final id = g.id.trim();
      final count = g.memberCount;
      final label = name.isNotEmpty ? name : (id.isNotEmpty ? id : 'Group');
      final title = count > 0 ? '$label ($count)' : label;

      return ListTile(
        dense: true,
        leading: avatarFor(g),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        trailing: chevron(),
        onTap: () => _openGroup(g),
      );
    }

    final groups = filteredGroups();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 8),
                ShamellSearchBar(
                  hintText: l.isArabic ? 'بحث' : 'Search',
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                ),
                ShamellSection(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const ShamellLeadingIcon(
                        icon: Icons.group_add_outlined,
                        background: ShamellPalette.green,
                      ),
                      title:
                          Text(l.isArabic ? 'مجموعة جديدة' : 'New group chat'),
                      trailing: chevron(),
                      onTap: _showCreateGroupSheet,
                    ),
                  ],
                ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      _error,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _search.trim().isNotEmpty
                          ? (l.isArabic
                              ? 'لا توجد نتائج.'
                              : 'No matches found.')
                          : (l.isArabic
                              ? 'لا توجد مجموعات بعد.'
                              : 'No group chats yet.'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  )
                else
                  ShamellSection(
                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                    children: [
                      for (final g in groups) groupTile(g),
                    ],
                  ),
              ],
            ),
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'مجموعات الدردشة' : 'Group chats'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'إنشاء' : 'Create',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _showCreateGroupSheet,
          ),
        ],
      ),
      body: body,
    );
  }
}

class _GroupBubbleTail extends StatelessWidget {
  final bool incoming;
  final Color color;

  const _GroupBubbleTail({required this.incoming, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GroupBubbleTailPainter(incoming: incoming, color: color),
      size: const Size(6, 10),
    );
  }
}

class _GroupBubbleTailPainter extends CustomPainter {
  final bool incoming;
  final Color color;

  _GroupBubbleTailPainter({required this.incoming, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (incoming) {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GroupBubbleTailPainter oldDelegate) {
    return oldDelegate.incoming != incoming || oldDelegate.color != color;
  }
}

class _MentionCandidate {
  final String id;
  final String label;
  const _MentionCandidate({required this.id, required this.label});
}

class _ShamellGroupMessageMenuActionSpec {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShamellGroupMessageMenuActionSpec({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });
}

class GroupChatPage extends StatefulWidget {
  final String baseUrl;
  final String groupId;
  final String groupName;
  final String? initialMessageId;
  const GroupChatPage({
    super.key,
    required this.baseUrl,
    required this.groupId,
    required this.groupName,
    this.initialMessageId,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage>
    with SafeSetStateMixin<GroupChatPage> {
  final TextEditingController _msgCtrl = TextEditingController();
  final FocusNode _msgFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  bool _loading = true;
  String? _deviceId;
  String _error = '';
  late final ChatService _service;
  List<ChatGroupMessage> _messages = const <ChatGroupMessage>[];
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _messageBubbleKeys = <String, GlobalKey>{};
  Map<String, String> _messageReactions = <String, String>{};
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  List<ChatGroupMember> _members = const <ChatGroupMember>[];
  Map<String, String> _contactNameById = <String, String>{};
  bool _isAdmin = false;
  String _groupName = '';
  String? _groupAvatarB64;
  bool _groupMuted = false;
  bool _groupPinned = false;
  String _chatThemeKey = 'default';
  String? _newMessagesAnchorMessageId;
  int _newMessagesCountAtOpen = 0;

  Uint8List? _attachedBytes;
  String? _attachedMime;
  String? _attachedName;

  static const double _shamellMorePanelHeight = 276.0;
  _ShamellGroupComposerPanel _composerPanel = _ShamellGroupComposerPanel.none;
  bool _shamellVoiceMode = false;
  final PageController _shamellMorePanelCtrl = PageController();
  int _shamellMorePanelPage = 0;

  bool _recordingVoice = false;
  DateTime? _voiceStart;
  Timer? _voiceTicker;
  int _voiceElapsedSecs = 0;
  bool _voiceCancelPending = false;
  bool _voiceLocked = false;
  Offset? _voiceGestureStartLocal;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSub;
  String? _playingVoiceId;
  bool _voicePlaying = false;
  bool _voiceUseSpeaker = true;
  StreamSubscription<int>? _proximitySub;
  Set<String> _playedVoiceMessageIds = <String>{};
  StreamSubscription<ChatGroupInboxUpdate>? _grpWsSub;
  bool _didSendMessage = false;

  bool _mentionActive = false;
  String _mentionQuery = '';
  int _mentionStart = -1;
  int _pendingNewMessageCount = 0;
  String? _pendingNewMessageFirstId;
  List<String> _pendingMentionMessageIds = const <String>[];

  Uint8List _randomGroupKeyBytes() {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  Future<void> _unarchiveGroupIfNeeded() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = sp.getStringList('chat.archived_groups') ?? const <String>[];
      if (!cur.contains(widget.groupId)) return;
      final next = List<String>.from(cur)
        ..removeWhere((x) => x == widget.groupId);
      if (next.isEmpty) {
        await sp.remove('chat.archived_groups');
      } else {
        await sp.setStringList('chat.archived_groups', next);
      }
    } catch (_) {}
  }

  Future<void> _loadChatThemeKey() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('chat.wallpaper_theme') ?? '{}';
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final k = _groupUnreadKey(widget.groupId);
      final v = (decoded[k] ?? '').toString().trim();
      if (!mounted) return;
      setState(() => _chatThemeKey = v.isNotEmpty ? v : 'default');
    } catch (_) {}
  }

  Future<void> _setChatThemeKey(String themeKey) async {
    final next = themeKey.trim().isNotEmpty ? themeKey.trim() : 'default';
    if (mounted) {
      setState(() => _chatThemeKey = next);
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('chat.wallpaper_theme') ?? '{}';
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        decoded = <String, dynamic>{};
      }

      final k = _groupUnreadKey(widget.groupId);
      if (next == 'default') {
        decoded.remove(k);
      } else {
        decoded[k] = next;
      }

      if (decoded.isEmpty) {
        await sp.remove('chat.wallpaper_theme');
      } else {
        await sp.setString('chat.wallpaper_theme', jsonEncode(decoded));
      }
    } catch (_) {}
  }

  static String _groupMessageReactionsPrefKey(String groupId) =>
      'chat.group_message_reactions.${groupId.trim()}';

  Future<void> _loadMessageReactions() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_groupMessageReactionsPrefKey(widget.groupId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <String, String>{};
      decoded.forEach((k, v) {
        final key = (k ?? '').toString().trim();
        final val = (v ?? '').toString().trim();
        if (key.isNotEmpty && val.isNotEmpty) {
          map[key] = val;
        }
      });
      if (!mounted) return;
      setState(() => _messageReactions = map);
    } catch (_) {}
  }

  Future<void> _saveMessageReactions() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final key = _groupMessageReactionsPrefKey(widget.groupId);
      if (_messageReactions.isEmpty) {
        await sp.remove(key);
      } else {
        await sp.setString(key, jsonEncode(_messageReactions));
      }
    } catch (_) {}
  }

  void _setReaction(ChatGroupMessage m, String emoji) {
    final id = m.id.trim();
    if (id.isEmpty) return;
    final nextEmoji = emoji.trim();
    setState(() {
      final updated = Map<String, String>.from(_messageReactions);
      if (nextEmoji.isEmpty) {
        updated.remove(id);
      } else {
        updated[id] = nextEmoji;
      }
      _messageReactions = updated;
    });
    unawaited(_saveMessageReactions());
  }

  Future<String?> _getOrCreateGroupKeyIfAdmin() async {
    final store = ChatLocalStore();
    var keyB64 = await store.loadGroupKey(widget.groupId);
    if ((keyB64 == null || keyB64.isEmpty) && _isAdmin) {
      keyB64 = base64Encode(_randomGroupKeyBytes());
      await store.saveGroupKey(widget.groupId, keyB64);
    }
    return keyB64;
  }

  Future<void> _shareGroupKey(String keyB64, List<String> ids) async {
    if (keyB64.isEmpty) return;
    final store = ChatLocalStore();
    final me = await store.loadIdentity();
    if (me == null) return;
    for (final id in ids) {
      final peerId = id.trim();
      if (peerId.isEmpty || peerId == me.id) continue;
      try {
        final peer = await _service.resolveDevice(peerId);
        final payload = jsonEncode({
          'kind': 'group_key',
          'group_id': widget.groupId,
          'key_b64': keyB64,
        });
        await _service.sendMessage(
          me: me,
          peer: peer,
          plainText: payload,
          sealedSender: true,
          senderHint: me.fingerprint,
        );
      } catch (_) {}
    }
  }

  String _shortId(String id) {
    final raw = id.trim();
    if (raw.length <= 10) return raw;
    return '${raw.substring(0, 6)}…';
  }

  String _displayNameForDeviceId(String id, L10n l, {String? fallback}) {
    final raw = id.trim();
    if (raw.isEmpty) {
      return fallback ?? (l.isArabic ? 'أحد الأعضاء' : 'Someone');
    }
    final myId = (_deviceId ?? '').trim();
    if (myId.isNotEmpty && raw == myId) {
      return l.isArabic ? 'أنت' : 'You';
    }
    final name = (_contactNameById[raw] ?? '').trim();
    if (name.isNotEmpty) return name;
    return _shortId(raw);
  }

  Widget _shamellGroupMessageAvatar({
    required String senderId,
    required bool incoming,
    required L10n l,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const size = 40.0;
    final radius = BorderRadius.circular(6);

    final label = _displayNameForDeviceId(senderId, l, fallback: senderId);
    final initial =
        label.trim().isNotEmpty ? label.trim()[0].toUpperCase() : '?';
    final bg = incoming
        ? theme.colorScheme.primary.withValues(alpha: isDark ? .22 : .14)
        : theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: isDark ? .35 : .85,
          );

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: bg,
        alignment: Alignment.center,
        child: Text(
          initial,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Future<void> _resolveMissingMemberNames(List<ChatGroupMember> members) async {
    final myId = (_deviceId ?? '').trim();
    final missing = members
        .map((m) => m.deviceId.trim())
        .where((id) => id.isNotEmpty && id != myId)
        .where((id) => (_contactNameById[id] ?? '').trim().isEmpty)
        .toSet()
        .toList();
    if (missing.isEmpty) return;

    final next = Map<String, String>.from(_contactNameById);
    var changed = false;
    for (final id in missing) {
      try {
        final c = await _service.resolveDevice(id);
        final name = (c.name ?? '').trim();
        if (name.isNotEmpty && (next[id] ?? '').trim().isEmpty) {
          next[id] = name;
          changed = true;
        }
      } catch (_) {}
    }
    if (!changed || !mounted) return;
    setState(() {
      _contactNameById = next;
    });
  }

  String _systemLabel(ChatGroupMessage m, L10n l) {
    final raw = m.text.trim();
    if (raw.isEmpty) {
      return l.isArabic ? 'حدث في المجموعة' : 'Group event';
    }
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final ev = (j['event'] ?? '').toString();
        final actor = (j['actor_id'] ?? '').toString();
        if (ev == 'invite') {
          final idsRaw = j['member_ids'];
          final ids = <String>[];
          if (idsRaw is List) {
            for (final x in idsRaw) {
              final s = x.toString().trim();
              if (s.isNotEmpty) ids.add(s);
            }
          }
          final who = _displayNameForDeviceId(actor, l);
          final added = ids
              .map((id) => _displayNameForDeviceId(id, l, fallback: id))
              .join(', ');
          if (l.isArabic) {
            return ids.isEmpty
                ? 'قام $who بإضافة أعضاء'
                : 'قام $who بإضافة $added';
          }
          return ids.isEmpty ? '$who invited members' : '$who invited $added';
        }
        if (ev == 'create') {
          final name = (j['name'] ?? '').toString();
          final idsRaw = j['member_ids'];
          final ids = <String>[];
          if (idsRaw is List) {
            for (final x in idsRaw) {
              final s = x.toString().trim();
              if (s.isNotEmpty) ids.add(s);
            }
          }
          final who = _displayNameForDeviceId(actor, l);
          final invited = ids
              .map((id) => _displayNameForDeviceId(id, l, fallback: id))
              .join(', ');
          if (l.isArabic) {
            final base = name.isNotEmpty
                ? 'أنشأ $who المجموعة \"$name\"'
                : 'أنشأ $who المجموعة';
            return ids.isEmpty ? base : '$base وأضاف $invited';
          }
          final base = name.isNotEmpty
              ? '$who created \"$name\"'
              : '$who created the group';
          return ids.isEmpty ? base : '$base and invited $invited';
        }
        if (ev == 'leave') {
          final who = _displayNameForDeviceId(actor, l);
          return l.isArabic ? 'غادر $who المجموعة' : '$who left the group';
        }
        if (ev == 'role') {
          final target = (j['target_id'] ?? '').toString();
          final role = (j['role'] ?? '').toString();
          final who = _displayNameForDeviceId(actor, l);
          final targetLabel = _displayNameForDeviceId(
            target,
            l,
            fallback: l.isArabic ? 'عضو' : 'a member',
          );
          if (role == 'admin') {
            return l.isArabic
                ? 'قام $who بترقية $targetLabel إلى مشرف'
                : '$who made $targetLabel admin';
          }
          return l.isArabic
              ? 'قام $who بإزالة صلاحية المشرف من $targetLabel'
              : '$who removed admin from $targetLabel';
        }
        if (ev == 'rename') {
          final newName = (j['new_name'] ?? '').toString();
          final who = _displayNameForDeviceId(actor, l);
          if (l.isArabic) {
            if (newName.isNotEmpty) {
              return 'قام $who بتغيير اسم المجموعة إلى \"$newName\"';
            }
            return 'قام $who بتغيير اسم المجموعة';
          }
          if (newName.isNotEmpty) {
            return '$who changed group name to \"$newName\"';
          }
          return '$who changed group name';
        }
        if (ev == 'avatar') {
          final action = (j['action'] ?? '').toString();
          final who = _displayNameForDeviceId(actor, l);
          if (l.isArabic) {
            if (action == 'remove') {
              return 'قام $who بإزالة صورة المجموعة';
            }
            return 'قام $who بتغيير صورة المجموعة';
          }
          if (action == 'remove') {
            return '$who removed group photo';
          }
          return '$who changed group photo';
        }
        if (ev == 'key_rotated') {
          final ver = (j['version'] ?? '').toString();
          final who = _displayNameForDeviceId(
            actor,
            l,
            fallback: l.isArabic ? 'مشرف' : 'An admin',
          );
          return l.isArabic
              ? 'قام $who بتدوير مفتاح التشفير${ver.isNotEmpty ? ' (v$ver)' : ''}'
              : '$who rotated encryption key${ver.isNotEmpty ? ' (v$ver)' : ''}';
        }
      }
    } catch (_) {}
    return raw;
  }

  Widget _renderMentions(
    String text,
    ThemeData theme, {
    TextStyle? baseStyle,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
  }) {
    final l = L10n.of(context);
    final base = baseStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);
    const mentionBlueLight = Color(0xFF576B95); // Shamell-like mention color
    const mentionBlueDark = Color(0xFF93C5FD);
    final mentionColor = theme.brightness == Brightness.dark
        ? mentionBlueDark
        : mentionBlueLight;
    final mentionStyle = base.copyWith(
      color: mentionColor,
      fontWeight: FontWeight.w600,
    );
    final highlightStyle = mentionStyle.copyWith(
      fontWeight: FontWeight.w800,
      backgroundColor: mentionColor.withValues(
        alpha: theme.brightness == Brightness.dark ? .18 : .14,
      ),
    );
    final meId = (_deviceId ?? '').toLowerCase();
    const arabicAllToken = '@الكل';
    final reg = RegExp(r'@([A-Za-z0-9_-]{2,})');
    final wsReg = RegExp(r'\s');
    final matches = <({int start, int end, String rawId})>[];

    for (final m in reg.allMatches(text)) {
      if (m.start > 0 && !wsReg.hasMatch(text[m.start - 1])) continue;
      final rawId = (m.group(1) ?? '').trim();
      if (rawId.isEmpty) continue;
      matches.add((start: m.start, end: m.end, rawId: rawId));
    }

    var idx = text.indexOf(arabicAllToken);
    while (idx != -1) {
      if (idx == 0 || wsReg.hasMatch(text[idx - 1])) {
        matches
            .add((start: idx, end: idx + arabicAllToken.length, rawId: 'all'));
      }
      idx = text.indexOf(arabicAllToken, idx + arabicAllToken.length);
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    if (matches.isEmpty) {
      return Text(
        text,
        style: base,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final rawId = m.rawId.trim();
      final idLower = rawId.toLowerCase();
      final display = idLower == 'all'
          ? (l.isArabic ? '@الكل' : '@all')
          : '@${_displayNameForDeviceId(rawId, l, fallback: rawId)}';
      final isHighlight = idLower == meId || idLower == 'all';
      spans.add(TextSpan(
        text: display,
        style: isHighlight ? highlightStyle : mentionStyle,
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(style: base, children: spans),
    );
  }

  void _onMessageChanged() {
    final text = _msgCtrl.text;
    final sel = _msgCtrl.selection.baseOffset;
    final cursor = (sel >= 0 && sel <= text.length) ? sel : text.length;
    final before = text.substring(0, cursor);
    final reg = RegExp(r'(?:^|\s)@([A-Za-z0-9_-]{0,24})$');
    final m = reg.firstMatch(before);
    if (m == null) {
      if (_mentionActive) {
        setState(() {
          _mentionActive = false;
          _mentionQuery = '';
          _mentionStart = -1;
        });
      }
      return;
    }
    final query = (m.group(1) ?? '').trim();
    final start = before.lastIndexOf('@');
    if (start < 0) return;
    if (!_mentionActive || _mentionQuery != query || _mentionStart != start) {
      setState(() {
        _mentionActive = true;
        _mentionQuery = query;
        _mentionStart = start;
      });
    }
  }

  List<_MentionCandidate> _mentionCandidates(L10n l) {
    final myId = (_deviceId ?? '').trim();
    final memberIds = <String>{};
    for (final m in _members) {
      final id = m.deviceId.trim();
      if (id.isEmpty || id == myId) continue;
      memberIds.add(id);
    }

    final q = _mentionQuery.toLowerCase();
    bool matches(String id) {
      if (q.isEmpty) return true;
      if (id.toLowerCase().startsWith(q)) return true;
      final name = (_contactNameById[id] ?? '').trim();
      return name.isNotEmpty && name.toLowerCase().startsWith(q);
    }

    final out = <_MentionCandidate>[];
    if (q.isEmpty || 'all'.startsWith(q)) {
      out.add(_MentionCandidate(id: 'all', label: l.isArabic ? 'الكل' : 'all'));
    }

    final filtered = memberIds.where(matches).toList();
    filtered.sort((a, b) {
      final an = (_contactNameById[a] ?? '').trim().toLowerCase();
      final bn = (_contactNameById[b] ?? '').trim().toLowerCase();
      final ak = an.isNotEmpty ? an : a.toLowerCase();
      final bk = bn.isNotEmpty ? bn : b.toLowerCase();
      final c = ak.compareTo(bk);
      if (c != 0) return c;
      return a.compareTo(b);
    });

    for (final id in filtered) {
      if (out.length >= 6) break;
      final name = (_contactNameById[id] ?? '').trim();
      final label = name.isNotEmpty ? name : _shortId(id);
      out.add(_MentionCandidate(id: id, label: label));
    }
    return out;
  }

  void _insertMention(String id) {
    final rawId = id.trim();
    if (rawId.isEmpty) return;
    final text = _msgCtrl.text;
    final sel = _msgCtrl.selection.baseOffset;
    final cursor = (sel >= 0 && sel <= text.length) ? sel : text.length;
    final replaceStart =
        (_mentionActive && _mentionStart >= 0 && _mentionStart <= cursor)
            ? _mentionStart
            : cursor;
    final before = text.substring(0, replaceStart);
    final after = text.substring(cursor);
    final needsSpace =
        before.isNotEmpty && !RegExp(r'\s').hasMatch(before[before.length - 1]);
    final insert = '${needsSpace ? ' ' : ''}@$rawId ';
    final newText = before + insert + after;
    _msgCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: before.length + insert.length),
    );
    setState(() {
      _mentionActive = false;
      _mentionQuery = '';
      _mentionStart = -1;
    });
  }

  Widget _buildMentionSuggestions(L10n l, ThemeData theme) {
    if (!_mentionActive) return const SizedBox.shrink();
    final list = _mentionCandidates(l);
    if (list.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: .08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in list)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  c.id == 'all'
                      ? '@'
                      : (c.label.isNotEmpty
                          ? c.label.characters.first.toUpperCase()
                          : '#'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              title: Text(
                '@${c.label}',
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: c.id != 'all' && c.label != c.id
                  ? Text(
                      '@${c.id}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    )
                  : null,
              onTap: () => _insertMention(c.id),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showMentionPickerSheet() async {
    try {
      await _refreshMembers();
    } catch (_) {}
    if (!mounted) return;
    final l = L10n.of(context);
    final did = (_deviceId ?? '').trim();

    final allCandidates = <({String id, String label, String? subtitle})>[
      (
        id: 'all',
        label: l.isArabic ? '@الكل' : '@all',
        subtitle: l.isArabic ? 'ذكر الجميع' : 'Mention everyone',
      ),
    ];
    for (final m in _members) {
      final id = m.deviceId.trim();
      if (id.isEmpty || id == did) continue;
      final name = _displayNameForDeviceId(id, l, fallback: id);
      allCandidates.add((
        id: id,
        label: '@$name',
        subtitle: '@$id',
      ));
    }
    allCandidates.sort((a, b) {
      if (a.id == 'all') return -1;
      if (b.id == 'all') return 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final maxH = MediaQuery.of(ctx).size.height * 0.72;
        String q = '';
        return SafeArea(
          child: SizedBox(
            height: maxH,
            child: StatefulBuilder(builder: (ctx2, setLocal) {
              final raw = q.trim().toLowerCase();
              final list = raw.isEmpty
                  ? allCandidates
                  : allCandidates.where((e) {
                      if (e.id == 'all') {
                        return 'all'.contains(raw) ||
                            (l.isArabic && 'الكل'.contains(raw));
                      }
                      final id = e.id.toLowerCase();
                      final label = e.label.toLowerCase();
                      final sub = (e.subtitle ?? '').toLowerCase();
                      return id.contains(raw) ||
                          label.contains(raw) ||
                          sub.contains(raw);
                    }).toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        Text(
                          l.isArabic ? 'الإشارة' : 'Mention',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        Text(
                          '${max(0, list.length - 1)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .60),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: l.isArabic ? 'بحث' : 'Search',
                      ),
                      onChanged: (v) => setLocal(() => q = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              l.isArabic ? 'لا توجد نتائج.' : 'No results.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 72),
                            itemBuilder: (_, i) {
                              final e = list[i];
                              final isAll = e.id == 'all';
                              final base = e.label.replaceFirst('@', '').trim();
                              final initial = isAll
                                  ? '@'
                                  : (base.isNotEmpty
                                      ? base.characters.first.toUpperCase()
                                      : '#');
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                title: Text(
                                  e.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: (e.subtitle ?? '').trim().isNotEmpty
                                    ? Text(
                                        e.subtitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: .65),
                                        ),
                                      )
                                    : null,
                                onTap: () => Navigator.of(ctx2).pop(e.id),
                              );
                            },
                          ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
    if (picked == null || picked.trim().isEmpty) return;
    _insertMention(picked);
    try {
      _msgFocus.requestFocus();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _service = ChatService(widget.baseUrl);
    _groupName = widget.groupName;
    _msgCtrl.addListener(_onMessageChanged);
    _scrollCtrl.addListener(_onScrollChanged);
    unawaited(_loadChatThemeKey());
    unawaited(_loadMessageReactions());
    _playerStateSub = _audioPlayer.playerStateStream.listen((st) {
      final playing =
          st.playing && st.processingState != ProcessingState.completed;
      if (!mounted) return;
      if (playing != _voicePlaying ||
          (!playing && st.processingState == ProcessingState.completed)) {
        if (!playing) {
          _proximitySub?.cancel();
          _proximitySub = null;
        }
        setState(() {
          _voicePlaying = playing;
          if (!playing && st.processingState == ProcessingState.completed) {
            _playingVoiceId = null;
          }
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _grpWsSub?.cancel();
    _playerStateSub?.cancel();
    _proximitySub?.cancel();
    try {
      _highlightTimer?.cancel();
    } catch (_) {}
    try {
      _voiceTicker?.cancel();
    } catch (_) {}
    _service.close();
    _msgCtrl.removeListener(_onMessageChanged);
    _msgCtrl.dispose();
    _msgFocus.dispose();
    _shamellMorePanelCtrl.dispose();
    _scrollCtrl.removeListener(_onScrollChanged);
    _scrollCtrl.dispose();
    try {
      _recorder.dispose();
    } catch (_) {}
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    super.dispose();
  }

  bool get _isNearBottom {
    try {
      if (!_scrollCtrl.hasClients) return true;
      final max = _scrollCtrl.position.maxScrollExtent;
      final off = _scrollCtrl.offset;
      return (max - off) < 140;
    } catch (_) {
      return true;
    }
  }

  bool _isMessageContextVisible(BuildContext itemCtx) {
    try {
      final scrollable = Scrollable.of(itemCtx);
      if (scrollable == null) return false;
      final scrollBox = scrollable.context.findRenderObject();
      final itemBox = itemCtx.findRenderObject();
      if (scrollBox is! RenderBox || itemBox is! RenderBox) return false;
      if (!scrollBox.attached || !itemBox.attached) return false;
      final topLeft = itemBox.localToGlobal(Offset.zero, ancestor: scrollBox);
      final top = topLeft.dy;
      final bottom = top + itemBox.size.height;
      final vpH = scrollBox.size.height;
      return bottom > 8 && top < vpH - 8;
    } catch (_) {
      return false;
    }
  }

  List<String> _pruneVisibleMentions(List<String> ids) {
    if (ids.isEmpty) return ids;
    final remove = <String>{};
    for (final id in ids) {
      final ctx = _messageKeys[id]?.currentContext;
      if (ctx == null) continue;
      if (_isMessageContextVisible(ctx)) {
        remove.add(id);
      }
    }
    if (remove.isEmpty) return ids;
    return ids.where((id) => !remove.contains(id)).toList();
  }

  void _onScrollChanged() {
    if (_pendingNewMessageCount <= 0 &&
        _pendingNewMessageFirstId == null &&
        _pendingMentionMessageIds.isEmpty) {
      return;
    }
    final nearBottom = _isNearBottom;
    final nextMentions = _pruneVisibleMentions(_pendingMentionMessageIds);
    final clearNew = nearBottom &&
        (_pendingNewMessageCount != 0 || _pendingNewMessageFirstId != null);
    final mentionChanged =
        nextMentions.length != _pendingMentionMessageIds.length;
    if (!clearNew && !mentionChanged) return;
    setState(() {
      if (clearNew) {
        _pendingNewMessageCount = 0;
        _pendingNewMessageFirstId = null;
      }
      if (mentionChanged) {
        _pendingMentionMessageIds = nextMentions;
      }
    });
  }

  void _flashMessageHighlight(String messageId) {
    final id = messageId.trim();
    if (id.isEmpty) return;
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = id;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      if (_highlightedMessageId != id) return;
      setState(() {
        _highlightedMessageId = null;
      });
    });
  }

  bool _messageMentionsMe(ChatGroupMessage m, String myIdLower) {
    final kind = (m.kind ?? '').toLowerCase();
    if (kind == 'system' || kind == 'sealed') return false;
    final text = m.text.trim();
    if (text.isEmpty || !text.contains('@')) return false;
    final reg = RegExp(r'@([A-Za-z0-9_-]{2,})');
    final wsReg = RegExp(r'\s');
    const arabicAllToken = '@الكل';
    if (text.contains(arabicAllToken)) {
      var idx = text.indexOf(arabicAllToken);
      while (idx != -1) {
        if (idx == 0 || wsReg.hasMatch(text[idx - 1])) return true;
        idx = text.indexOf(arabicAllToken, idx + arabicAllToken.length);
      }
    }
    for (final mm in reg.allMatches(text)) {
      if (mm.start > 0 && !wsReg.hasMatch(text[mm.start - 1])) {
        continue;
      }
      final raw = (mm.group(1) ?? '').trim().toLowerCase();
      if (raw.isEmpty) continue;
      if (raw == myIdLower || raw == 'all') return true;
    }
    return false;
  }

  bool _messageMentionsAll(ChatGroupMessage m) {
    final kind = (m.kind ?? '').toLowerCase();
    if (kind == 'system' || kind == 'sealed') return false;
    final text = m.text.trim();
    if (text.isEmpty || !text.contains('@')) return false;
    final reg = RegExp(r'@([A-Za-z0-9_-]{2,})');
    final wsReg = RegExp(r'\s');
    const arabicAllToken = '@الكل';
    if (text.contains(arabicAllToken)) {
      var idx = text.indexOf(arabicAllToken);
      while (idx != -1) {
        if (idx == 0 || wsReg.hasMatch(text[idx - 1])) return true;
        idx = text.indexOf(arabicAllToken, idx + arabicAllToken.length);
      }
    }
    for (final mm in reg.allMatches(text)) {
      if (mm.start > 0 && !wsReg.hasMatch(text[mm.start - 1])) {
        continue;
      }
      final raw = (mm.group(1) ?? '').trim().toLowerCase();
      if (raw == 'all') return true;
    }
    return false;
  }

  String _mentionPreviewText(ChatGroupMessage m, L10n l) {
    final kind = (m.kind ?? '').toLowerCase();
    if (kind == 'voice') return l.shamellPreviewVoice;
    final mime = (m.attachmentMime ?? '').toLowerCase();
    if (kind == 'image' || mime.startsWith('image/')) {
      final caption = m.text.trim();
      return caption.isNotEmpty
          ? '${l.shamellPreviewImage} $caption'
          : l.shamellPreviewImage;
    }
    final text = m.text.trim();
    return text.isNotEmpty ? text : l.shamellPreviewUnknown;
  }

  String _formatMentionsForPreview(String text, L10n l) {
    if (text.isEmpty || !text.contains('@')) return text;
    final reg = RegExp(r'@([A-Za-z0-9_-]{2,})');
    final wsReg = RegExp(r'\s');
    final out = text.replaceAllMapped(reg, (mm) {
      if (mm.start > 0 && !wsReg.hasMatch(text[mm.start - 1])) {
        return mm.group(0) ?? '';
      }
      final raw = (mm.group(1) ?? '').trim();
      if (raw.isEmpty) return mm.group(0) ?? '';
      if (raw.toLowerCase() == 'all') {
        return l.isArabic ? '@الكل' : '@all';
      }
      return '@${_displayNameForDeviceId(raw, l, fallback: raw)}';
    });
    if (l.isArabic) return out;
    return out.replaceAll('@الكل', '@all');
  }

  String _formatMentionSheetTs(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.toLocal();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom({bool force = false, bool animated = true}) {
    if (!_scrollCtrl.hasClients) return;
    if (!force && !_isNearBottom) return;
    final target = _scrollCtrl.position.maxScrollExtent;
    if (animated) {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollCtrl.jumpTo(target);
    }
    if (!mounted) return;
    if (_pendingNewMessageCount != 0 || _pendingNewMessageFirstId != null) {
      setState(() {
        _pendingNewMessageCount = 0;
        _pendingNewMessageFirstId = null;
      });
    }
  }

  Future<void> _scrollToMessage(
    String messageId, {
    double alignment = 0.18,
    bool highlight = false,
  }) async {
    if (messageId.isEmpty) return;
    if (highlight) {
      _flashMessageHighlight(messageId);
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      final key = _messageKeys[messageId];
      final ctx = key?.currentContext;
      if (ctx != null) {
        try {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 250),
            alignment: alignment,
          );
        } catch (_) {}
        return;
      }
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx < 0) return;
      if (!_scrollCtrl.hasClients) return;
      try {
        final maxScrollExtent = _scrollCtrl.position.maxScrollExtent;
        if (maxScrollExtent <= 0) return;
        final denom = max(1, _messages.length - 1);
        final ratio = (idx / denom).clamp(0.0, 1.0).toDouble();
        final target =
            (maxScrollExtent * ratio).clamp(0.0, maxScrollExtent).toDouble();
        _scrollCtrl.jumpTo(target);
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _jumpToFirstPendingNewMessage() async {
    var targetId = _pendingNewMessageFirstId;
    if ((targetId == null || targetId.isEmpty) && _pendingNewMessageCount > 0) {
      final myId = (_deviceId ?? '').trim();
      var remaining = _pendingNewMessageCount;
      for (var i = _messages.length - 1; i >= 0; i--) {
        final m = _messages[i];
        if (myId.isNotEmpty && m.senderId.trim() == myId) continue;
        remaining--;
        if (remaining <= 0) {
          targetId = m.id;
          break;
        }
      }
    }
    if (targetId == null || targetId.isEmpty) {
      _scrollToBottom(force: true);
      return;
    }
    await _scrollToMessage(targetId, alignment: 0.18);
    if (!mounted) return;
    setState(() {
      _pendingNewMessageCount = 0;
      _pendingNewMessageFirstId = null;
    });
  }

  Future<void> _jumpToFirstPendingMention() async {
    final ids = _pendingMentionMessageIds;
    if (ids.isEmpty) {
      _scrollToBottom(force: true);
      return;
    }
    final targetId = ids.first.trim();
    if (targetId.isEmpty) return;
    await _scrollToMessage(targetId, alignment: 0.18, highlight: true);
    if (!mounted) return;
    setState(() {
      _pendingMentionMessageIds =
          ids.length <= 1 ? const <String>[] : ids.sublist(1);
    });
  }

  Future<void> _jumpToMentionFromSheet(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return;
    if (!_messages.any((m) => m.id == id)) return;
    await _scrollToMessage(id, alignment: 0.18, highlight: true);
    if (!mounted) return;
    setState(() {
      _pendingMentionMessageIds =
          _pendingMentionMessageIds.where((x) => x != id).toList();
    });
  }

  Future<void> _showMentionsSheet() async {
    final ids = List<String>.from(_pendingMentionMessageIds);
    if (ids.isEmpty) {
      _scrollToBottom(force: true);
      return;
    }
    final l = L10n.of(context);
    final byId = <String, ChatGroupMessage>{
      for (final m in _messages) m.id: m,
    };
    final entries = <({
      String id,
      ChatGroupMessage m,
      String sender,
      String preview,
      String ts,
      bool isAll
    })>[];
    for (final id in ids) {
      final m = byId[id];
      if (m == null) continue;
      final sender =
          _displayNameForDeviceId(m.senderId, l, fallback: m.senderId);
      final preview = _mentionPreviewText(m, l);
      entries.add((
        id: id,
        m: m,
        sender: sender,
        preview: preview,
        ts: _formatMentionSheetTs(m.createdAt),
        isAll: _messageMentionsAll(m),
      ));
    }
    if (entries.isEmpty) {
      if (!mounted) return;
      setState(() {
        _pendingMentionMessageIds = const <String>[];
      });
      return;
    }

    const shamellUnreadRed = Color(0xFFFA5151);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final maxH = MediaQuery.of(ctx).size.height * 0.70;
        final title = l.isArabic ? 'الإشارات' : 'Mentions';
        return SafeArea(
          child: SizedBox(
            height: maxH,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        '${entries.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .60),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (ctx2, i) {
                      final e = entries[entries.length - 1 - i];
                      final initial =
                          e.sender.isNotEmpty ? e.sender.characters.first : '#';
                      final chipLabel =
                          e.isAll ? (l.isArabic ? '@الكل' : '@all') : '@';
                      final tsStyle = theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .55),
                      );
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            initial.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.sender,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (e.ts.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(e.ts, style: tsStyle),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: shamellUnreadRed,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  chipLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _renderMentions(
                                  e.preview,
                                  theme,
                                  baseStyle:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .78),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .45),
                        ),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await Future<void>.delayed(
                              const Duration(milliseconds: 140));
                          if (!mounted) return;
                          await _jumpToMentionFromSheet(e.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingNewMessagesBar(ThemeData theme, L10n l) {
    final count = _pendingNewMessageCount;
    if (count <= 0 || _isNearBottom) return const SizedBox.shrink();
    final isDark = theme.brightness == Brightness.dark;
    const shamellGreen = Color(0xFF07C160);
    final labelCount = count > 99 ? '99+' : '$count';
    final label = l.isArabic
        ? (count == 1 ? '$labelCount رسالة جديدة' : '$labelCount رسائل جديدة')
        : (count == 1 ? '$labelCount new message' : '$labelCount new messages');
    final bg = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .90)
        : const Color(0xFFF7F7F7);
    final borderColor =
        isDark ? Colors.white.withValues(alpha: .10) : const Color(0xFFE6E6E6);
    final fg = theme.colorScheme.onSurface.withValues(alpha: .72);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
      side: BorderSide(color: borderColor, width: 0.8),
    );
    return Material(
      color: bg,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: isDark ? .22 : .12),
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: _jumpToFirstPendingNewMessage,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down, size: 18, color: shamellGreen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingMentionButton(ThemeData theme) {
    final count = _pendingMentionMessageIds.length;
    if (count <= 0) return const SizedBox.shrink();
    final bg = theme.colorScheme.surface.withValues(
      alpha: theme.brightness == Brightness.dark ? .86 : .94,
    );
    final fg = theme.colorScheme.onSurface.withValues(alpha: .78);
    const shamellUnreadRed = Color(0xFFFA5151);
    final showCount = count > 1;
    final label = count > 99 ? '99+' : '$count';
    return Material(
      color: bg,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _showMentionsSheet,
        onLongPress: _jumpToFirstPendingMention,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Text(
                  '@',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: showCount
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: shamellUnreadRed,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: shamellUnreadRed,
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewMessagesMarker(ThemeData theme, L10n l) {
    final label = _newMessagesCountAtOpen <= 1
        ? l.shamellNewMessageTitle
        : (l.isArabic
            ? '${_newMessagesCountAtOpen} رسائل جديدة'
            : '${_newMessagesCountAtOpen} new messages');
    final dividerColor = theme.dividerColor.withValues(alpha: .35);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              height: 1,
              thickness: 0.6,
              color: dividerColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: .55,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 0.6,
              color: dividerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJumpToBottomButton(ThemeData theme) {
    final bg = theme.colorScheme.surface.withValues(
      alpha: theme.brightness == Brightness.dark ? .86 : .94,
    );
    final fg = theme.colorScheme.onSurface.withValues(alpha: .74);
    return Material(
      color: bg,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _scrollToBottom(force: true),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.keyboard_arrow_down, size: 22, color: fg),
        ),
      ),
    );
  }

  Future<void> _openImagePreview(Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.black,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareAttachment(
    Uint8List bytes,
    String mime, {
    String? fileName,
  }) async {
    try {
      final mt =
          mime.trim().isNotEmpty ? mime.trim() : 'application/octet-stream';
      String ext;
      if (mt == 'image/png') {
        ext = 'png';
      } else if (mt == 'image/jpeg' || mt == 'image/jpg') {
        ext = 'jpg';
      } else if (mt.startsWith('audio/')) {
        ext = mt.split('/').last.trim();
      } else if (mt.startsWith('video/')) {
        ext = mt.split('/').last.trim();
      } else {
        ext = 'bin';
      }
      final safeName = (fileName ?? '').trim().isNotEmpty
          ? fileName!.trim()
          : 'attachment.$ext';
      final file = XFile.fromData(
        bytes,
        mimeType: mt,
        name: safeName,
      );
      await Share.shareXFiles([file]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _deleteGroupMessageLocal(ChatGroupMessage m) async {
    final id = m.id.trim();
    if (id.isEmpty) return;

    try {
      if (_playingVoiceId == id) {
        await _audioPlayer.stop();
      }
    } catch (_) {}

    final nextMsgs = _messages.where((x) => x.id != id).toList();
    if (!mounted) return;
    setState(() {
      _messages = nextMsgs;
      _messageKeys.remove(id);
      _messageBubbleKeys.remove(id);
      if (_messageReactions.containsKey(id)) {
        final updated = Map<String, String>.from(_messageReactions);
        updated.remove(id);
        _messageReactions = updated;
      }
      if (_pendingNewMessageFirstId == id) {
        _pendingNewMessageFirstId = null;
      }
      _pendingMentionMessageIds =
          _pendingMentionMessageIds.where((x) => x != id).toList();
      if (_highlightedMessageId == id) {
        _highlightedMessageId = null;
      }
      if (_playingVoiceId == id) {
        _playingVoiceId = null;
        _voicePlaying = false;
      }
      _playedVoiceMessageIds.remove(id);
    });
    unawaited(_saveMessageReactions());
    try {
      await ChatLocalStore().saveGroupMessages(widget.groupId, nextMsgs);
    } catch (_) {}
  }

  Future<void> _showShamellGroupMessageLongPressMenu({
    required Rect bubbleRect,
    required bool incoming,
    required List<_ShamellGroupMessageMenuActionSpec> actions,
    required ValueChanged<String> onReaction,
  }) async {
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    const bg = Color(0xFF2C2C2C);
    const margin = 8.0;
    const gap = 10.0;
    const reactionH = 44.0;
    const reactionPadH = 10.0;
    const reactionSpacing = 6.0;
    const panelPadH = 12.0;
    const panelPadV = 12.0;
    const panelColSpacing = 10.0;
    const panelRowSpacing = 8.0;
    const panelCellW = 64.0;
    const panelCellH = 70.0;
    const shadow = [
      BoxShadow(
        color: Colors.black26,
        blurRadius: 10,
        offset: Offset(0, 6),
      ),
    ];

    final overlaySize = overlayBox.size;
    final emojis = const ['👍', '❤️', '😂', '😮', '😢', '😡'];

    final maxW = max(0.0, overlaySize.width - margin * 2);
    final maxH = max(0.0, overlaySize.height - margin * 2);
    if (maxW <= 0 || maxH <= 0) return;

    final double reactionItemW = (() {
      final needed = reactionPadH * 2 +
          emojis.length * 32 +
          (emojis.length - 1) * reactionSpacing;
      if (needed <= maxW) return 32.0;
      final available = max(
        24.0,
        maxW - reactionPadH * 2 - (emojis.length - 1) * reactionSpacing,
      );
      return max(24.0, available / emojis.length);
    })();
    final reactionW = min(
      maxW,
      reactionPadH * 2 +
          emojis.length * reactionItemW +
          (emojis.length - 1) * reactionSpacing,
    );

    int cols = min(5, max(1, actions.length));
    while (cols > 1) {
      final needed =
          panelPadH * 2 + cols * panelCellW + (cols - 1) * panelColSpacing;
      if (needed <= maxW) break;
      cols--;
    }
    final rows = max(1, (actions.length / cols).ceil());
    final panelW =
        panelPadH * 2 + cols * panelCellW + (cols - 1) * panelColSpacing;
    final panelH =
        panelPadV * 2 + rows * panelCellH + (rows - 1) * panelRowSpacing;

    var reactionLeft =
        incoming ? bubbleRect.left : bubbleRect.right - reactionW;
    reactionLeft =
        reactionLeft.clamp(margin, overlaySize.width - reactionW - margin);

    var panelLeft = incoming ? bubbleRect.left : bubbleRect.right - panelW;
    panelLeft = panelLeft.clamp(margin, overlaySize.width - panelW - margin);

    var reactionTop = bubbleRect.top - gap - reactionH;
    final reactionAbove = reactionTop >= margin;
    if (!reactionAbove) {
      reactionTop = bubbleRect.bottom + gap;
    }

    var panelTop = bubbleRect.bottom + gap;
    final panelBelow = panelTop + panelH <= overlaySize.height - margin;
    if (!panelBelow) {
      panelTop = bubbleRect.top - gap - panelH;
      if (panelTop < margin) {
        panelTop = ((overlaySize.height - panelH) / 2)
            .clamp(margin, overlaySize.height - panelH - margin);
      }
    }

    if (!reactionAbove && panelTop > bubbleRect.bottom) {
      panelTop = max(panelTop, reactionTop + reactionH + gap);
      panelTop = min(panelTop, overlaySize.height - panelH - margin);
    } else if (reactionAbove && panelTop < bubbleRect.top) {
      final minGapTop = reactionTop - gap - panelH;
      if (panelTop > minGapTop) {
        panelTop = max(margin, minGapTop);
      }
    }

    Widget reactionBar() {
      return Material(
        color: Colors.transparent,
        child: Container(
          width: reactionW,
          height: reactionH,
          padding: const EdgeInsets.symmetric(horizontal: reactionPadH),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < emojis.length; i++) ...[
                if (i > 0) const SizedBox(width: reactionSpacing),
                InkWell(
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    onReaction(emojis[i]);
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    width: reactionItemW,
                    height: reactionH,
                    child: Center(
                      child: Text(
                        emojis[i],
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget actionsPanel(ThemeData theme) {
      return Material(
        color: Colors.transparent,
        child: Container(
          width: panelW,
          height: panelH,
          padding: const EdgeInsets.symmetric(
            horizontal: panelPadH,
            vertical: panelPadV,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: shadow,
          ),
          child: Wrap(
            spacing: panelColSpacing,
            runSpacing: panelRowSpacing,
            children: [
              for (final action in actions)
                InkWell(
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    action.onTap();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: panelCellW,
                    height: panelCellH,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.icon, size: 22, color: action.color),
                        const SizedBox(height: 6),
                        Text(
                          action.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: action.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, a1, _) {
        final curved = CurvedAnimation(
          parent: a1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final theme = Theme.of(ctx);
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
                  final dx = (incoming ? -14 : 14) * (1 - t);
                  return Stack(
                    children: [
                      Positioned(
                        left: reactionLeft,
                        top: reactionTop,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: reactionBar(),
                          ),
                        ),
                      ),
                      if (actions.isNotEmpty)
                        Positioned(
                          left: panelLeft,
                          top: panelTop,
                          child: Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(dx, 0),
                              child: actionsPanel(theme),
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

  Future<void> _showGroupMessageActionsSheet(
    ChatGroupMessage m, {
    Offset? globalPosition,
    Uint8List? attachmentBytes,
    required String mime,
    required bool isVoice,
    required bool isImage,
  }) async {
    final l = L10n.of(context);
    final kind = (m.kind ?? '').toLowerCase();
    if (kind == 'system') return;

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    final rawText = m.text.trim();
    final canCopyText = rawText.isNotEmpty && !isVoice;
    final canShareAttachment =
        attachmentBytes != null && attachmentBytes.isNotEmpty;
    final shareLabel = l.isArabic ? 'مشاركة' : 'Share';
    final isMe = _deviceId != null && m.senderId == _deviceId;

    final actions = <_ShamellGroupMessageMenuActionSpec>[];
    if (canCopyText) {
      actions.add(
        _ShamellGroupMessageMenuActionSpec(
          icon: Icons.copy_outlined,
          label: l.shamellCopyMessage,
          onTap: () {
            unawaited(() async {
              final text = _formatMentionsForPreview(rawText, l);
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.shamellMessageCopiedSnack)),
              );
            }());
          },
        ),
      );
    }
    if (canShareAttachment) {
      actions.add(
        _ShamellGroupMessageMenuActionSpec(
          icon: Icons.ios_share_outlined,
          label: shareLabel,
          onTap: () {
            unawaited(() async {
              final bytes = attachmentBytes!;
              final String fileName;
              if (isVoice) {
                fileName = 'voice_message.aac';
              } else if (isImage) {
                final ext = mime == 'image/png' ? 'png' : 'jpg';
                fileName = 'image.$ext';
              } else {
                fileName = 'attachment';
              }
              await _shareAttachment(bytes, mime, fileName: fileName);
            }());
          },
        ),
      );
    }
    if (isVoice) {
      actions.add(
        _ShamellGroupMessageMenuActionSpec(
          icon: _voiceUseSpeaker ? Icons.volume_up : Icons.hearing,
          label: _voiceUseSpeaker
              ? l.shamellVoiceSpeakerMode
              : l.shamellVoiceEarpieceMode,
          onTap: () {
            unawaited(() async {
              if (!mounted) return;
              setState(() {
                _voiceUseSpeaker = !_voiceUseSpeaker;
              });
              await _configureVoiceSession();
            }());
          },
        ),
      );
    }
    actions.add(
      _ShamellGroupMessageMenuActionSpec(
        icon: Icons.delete_outline,
        label: l.shamellDeleteForMe,
        color: const Color(0xFFFA5151),
        onTap: () => unawaited(_deleteGroupMessageLocal(m)),
      ),
    );

    final globalPos = globalPosition;
    if (globalPos != null) {
      try {
        final overlayBox =
            Overlay.of(context).context.findRenderObject() as RenderBox;
        final localAnchor = overlayBox.globalToLocal(globalPos);
        var bubbleRect = Rect.fromCenter(
          center: localAnchor,
          width: 2,
          height: 2,
        );
        final bubbleKey = m.id.isNotEmpty ? _messageBubbleKeys[m.id] : null;
        final bubbleCtx = bubbleKey?.currentContext;
        final bubbleObj = bubbleCtx?.findRenderObject();
        if (bubbleObj is RenderBox) {
          final tl = bubbleObj.localToGlobal(Offset.zero, ancestor: overlayBox);
          bubbleRect = tl & bubbleObj.size;
        }
        await _showShamellGroupMessageLongPressMenu(
          bubbleRect: bubbleRect,
          incoming: !isMe,
          actions: actions,
          onReaction: (emoji) => _setReaction(m, emoji),
        );
        return;
      } catch (_) {
        // Fallback to bottom sheet below.
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.shamellMessageActionsTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '😡'])
                      InkWell(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _setReaction(m, emoji);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (canCopyText)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.copy, size: 20),
                    title: Text(l.shamellCopyMessage),
                    onTap: () async {
                      final text = _formatMentionsForPreview(rawText, l);
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!mounted) return;
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.shamellMessageCopiedSnack)),
                      );
                    },
                  ),
                if (canShareAttachment)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.ios_share_outlined, size: 20),
                    title: Text(shareLabel),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final bytes = attachmentBytes!;
                      final String fileName;
                      if (isVoice) {
                        fileName = 'voice_message.aac';
                      } else if (isImage) {
                        final ext = mime == 'image/png' ? 'png' : 'jpg';
                        fileName = 'image.$ext';
                      } else {
                        fileName = 'attachment';
                      }
                      await _shareAttachment(bytes, mime, fileName: fileName);
                    },
                  ),
                if (isVoice)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _voiceUseSpeaker ? Icons.volume_up : Icons.hearing,
                      size: 20,
                    ),
                    title: Text(
                      _voiceUseSpeaker
                          ? l.shamellVoiceSpeakerMode
                          : l.shamellVoiceEarpieceMode,
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (!mounted) return;
                      setState(() {
                        _voiceUseSpeaker = !_voiceUseSpeaker;
                      });
                      await _configureVoiceSession();
                    },
                  ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    l.shamellDeleteForMe,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _deleteGroupMessageLocal(m);
                  },
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l.shamellDialogCancel),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final store = ChatLocalStore();
      final me = await store.loadIdentity();
      if (me == null) {
        _deviceId = null;
        _messages = const <ChatGroupMessage>[];
        _playedVoiceMessageIds = <String>{};
        _contactNameById = <String, String>{};
        _newMessagesAnchorMessageId = null;
        _newMessagesCountAtOpen = 0;
      } else {
        _deviceId = me.id;
        try {
          final contacts = await store.loadContacts();
          _contactNameById = <String, String>{
            for (final c in contacts)
              if (c.id.trim().isNotEmpty && (c.name ?? '').trim().isNotEmpty)
                c.id.trim(): (c.name ?? '').trim(),
          };
        } catch (_) {
          _contactNameById = <String, String>{};
        }
        try {
          _playedVoiceMessageIds =
              await store.loadGroupVoicePlayed(widget.groupId);
        } catch (_) {
          _playedVoiceMessageIds = <String>{};
        }
        try {
          final groups = await _service.listGroups(deviceId: me.id);
          unawaited(store.upsertGroupNames(groups));
          final gdet = groups.firstWhere((g) => g.id == widget.groupId,
              orElse: () => ChatGroup(
                  id: widget.groupId,
                  name: _groupName,
                  creatorId: '',
                  memberCount: 0));
          _groupName = gdet.name;
          _groupAvatarB64 = gdet.avatarB64;
        } catch (_) {}
        try {
          final prefs = await _service.fetchGroupPrefs(deviceId: me.id);
          final p = prefs.firstWhere(
            (p) => p.groupId == widget.groupId,
            orElse: () => ChatGroupPrefs(
              groupId: widget.groupId,
              muted: false,
              pinned: false,
            ),
          );
          _groupMuted = p.muted;
          _groupPinned = p.pinned;
        } catch (_) {}
        int openUnreadCount = 0;
        try {
          final unread = await store.loadUnread();
          final raw = unread[_groupUnreadKey(widget.groupId)] ?? 0;
          openUnreadCount = raw > 0 ? raw : 0;
        } catch (_) {}
        final fetchLimit =
            openUnreadCount > 0 ? min(200, max(50, openUnreadCount * 2)) : 50;
        final msgs = await _service.fetchGroupInbox(
          groupId: widget.groupId,
          deviceId: me.id,
          limit: fetchLimit,
        );
        _messages = msgs;
        _newMessagesCountAtOpen = openUnreadCount;
        _newMessagesAnchorMessageId = _computeNewMessagesAnchorMessageId(
          messages: msgs,
          myId: me.id,
          unreadCount: openUnreadCount,
        );
        _pendingMentionMessageIds = const <String>[];
        if (openUnreadCount > 0 && me.id.trim().isNotEmpty) {
          final meIdLower = me.id.trim().toLowerCase();
          var remaining = openUnreadCount;
          final ids = <String>[];
          for (var i = msgs.length - 1; i >= 0; i--) {
            if (remaining <= 0) break;
            final m = msgs[i];
            if (m.senderId.trim() == me.id) continue;
            remaining--;
            if (meIdLower.isNotEmpty && _messageMentionsMe(m, meIdLower)) {
              final mid = m.id.trim();
              if (mid.isNotEmpty) ids.add(mid);
            }
          }
          _pendingMentionMessageIds = ids.reversed.toList();
        }
        try {
          await store.saveGroupMessages(widget.groupId, msgs);
        } catch (_) {}
        try {
          final members = await _service.listGroupMembers(
            groupId: widget.groupId,
            deviceId: me.id,
          );
          _members = members;
          _isAdmin =
              members.any((m) => m.deviceId == me.id && m.role == 'admin');
          unawaited(_resolveMissingMemberNames(members));
        } catch (_) {
          _members = const <ChatGroupMember>[];
          _isAdmin = false;
        }
        try {
          final keyB64 = await _getOrCreateGroupKeyIfAdmin();
          if (keyB64 != null && keyB64.isNotEmpty && _isAdmin) {
            final others = _members
                .where((m) => m.deviceId != me.id)
                .map((m) => m.deviceId)
                .toList();
            if (others.isNotEmpty) {
              await _shareGroupKey(keyB64, others);
            }
          }
        } catch (_) {}
        await _markSeenAndClearUnread(me.id);
        _listenGroupWs(me.id);
      }
    } catch (e) {
      _error = sanitizeExceptionForUi(error: e);
      _messages = const <ChatGroupMessage>[];
      _playedVoiceMessageIds = <String>{};
      _newMessagesAnchorMessageId = null;
      _newMessagesCountAtOpen = 0;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
    final anchorId = (_newMessagesCountAtOpen > 0)
        ? (_newMessagesAnchorMessageId ?? '').trim()
        : '';
    final targetId = (widget.initialMessageId ?? '').trim();
    final hasTarget =
        targetId.isNotEmpty && _messages.any((m) => m.id.trim() == targetId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasTarget) {
        unawaited(_scrollToMessage(targetId, alignment: 0.18, highlight: true));
      } else if (anchorId.isNotEmpty) {
        unawaited(_scrollToMessage(anchorId, alignment: 0.18));
      } else {
        _scrollToBottom(force: true, animated: false);
      }
    });
  }

  Future<void> _showEditGroupSheet() async {
    if (!_isAdmin) return;
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final l = L10n.of(context);
    final nameCtrl = TextEditingController(text: _groupName);
    Uint8List? avatarBytes;
    String? avatarMime;
    bool removeAvatar = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
              left: 12, right: 12, top: 12, bottom: bottom + 12),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: StatefulBuilder(builder: (ctx2, setLocal) {
              Widget avatarPreview() {
                Uint8List? bytes;
                if (removeAvatar) {
                  bytes = null;
                } else if (avatarBytes != null) {
                  bytes = avatarBytes;
                } else if (_groupAvatarB64 != null &&
                    _groupAvatarB64!.isNotEmpty) {
                  try {
                    bytes = base64Decode(_groupAvatarB64!);
                  } catch (_) {}
                }
                return CircleAvatar(
                  radius: 32,
                  backgroundColor: Theme.of(ctx2).colorScheme.primaryContainer,
                  child: bytes != null
                      ? ClipOval(
                          child: Image.memory(bytes,
                              width: 64, height: 64, fit: BoxFit.cover))
                      : const Icon(Icons.groups_outlined, size: 28),
                );
              }

              Future<void> pickAvatar() async {
                try {
                  final picker = ImagePicker();
                  final x = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 512,
                      imageQuality: 80);
                  if (x == null) return;
                  final bytes = await x.readAsBytes();
                  final ext = (x.name.split('.').last).toLowerCase();
                  setLocal(() {
                    avatarBytes = bytes;
                    avatarMime = ext == 'png' ? 'image/png' : 'image/jpeg';
                    removeAvatar = false;
                  });
                } catch (_) {}
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.isArabic ? 'تعديل المجموعة' : 'Edit group',
                    style: Theme.of(ctx2)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.center, child: avatarPreview()),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: pickAvatar,
                        icon: const Icon(Icons.photo),
                        label:
                            Text(l.isArabic ? 'تغيير الصورة' : 'Change photo'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => setLocal(() => removeAvatar = true),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l.isArabic ? 'إزالة' : 'Remove'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: l.isArabic ? 'اسم المجموعة' : 'Group name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PrimaryButton(
                      label: l.isArabic ? 'حفظ' : 'Save',
                      onPressed: () async {
                        Navigator.of(ctx2).pop();
                        try {
                          final nameVal = nameCtrl.text.trim();
                          final nameParam =
                              nameVal.isNotEmpty && nameVal != _groupName
                                  ? nameVal
                                  : null;
                          String? avatarB64Param;
                          String? avatarMimeParam;
                          if (removeAvatar) {
                            avatarB64Param = '';
                            avatarMimeParam = '';
                          } else if (avatarBytes != null) {
                            avatarB64Param = base64Encode(avatarBytes!);
                            avatarMimeParam = avatarMime ?? 'image/jpeg';
                          }
                          final updated = await _service.updateGroup(
                            groupId: widget.groupId,
                            actorId: did,
                            name: nameParam,
                            avatarB64: avatarB64Param,
                            avatarMime: avatarMimeParam,
                          );
                          if (!mounted) return;
                          setState(() {
                            _groupName = updated.name;
                            _groupAvatarB64 = updated.avatarB64;
                          });
                        } catch (e) {
                          if (!mounted) return;
                          setState(
                              () => _error = sanitizeExceptionForUi(error: e));
                        }
                      },
                    ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
    nameCtrl.dispose();
  }

  void _listenGroupWs(String did) {
    _grpWsSub?.cancel();
    _grpWsSub = _service.streamGroupInbox(deviceId: did).listen((upd) {
      if (upd.groupId != widget.groupId) return;
      final wasNearBottom = _isNearBottom;
      final existing = _messages;
      final byId = <String, ChatGroupMessage>{
        for (final m in existing) m.id: m,
      };
      var addedIncoming = 0;
      String? firstIncomingIdInBatch;
      DateTime? firstIncomingAtInBatch;
      final myIdLower = did.toLowerCase();
      final mentionMsgsInBatch = <ChatGroupMessage>[];
      for (final m in upd.messages) {
        if (m.id.isEmpty) continue;
        final isNew = !byId.containsKey(m.id);
        byId[m.id] = m;
        if (!isNew) continue;
        final isIncoming = m.senderId.trim() != did;
        if (isIncoming) {
          addedIncoming++;
          final ts = m.createdAt;
          if (myIdLower.isNotEmpty && _messageMentionsMe(m, myIdLower)) {
            mentionMsgsInBatch.add(m);
          }
          if (firstIncomingIdInBatch == null) {
            firstIncomingIdInBatch = m.id;
            firstIncomingAtInBatch = ts;
          } else if (ts != null &&
              (firstIncomingAtInBatch == null ||
                  ts.isBefore(firstIncomingAtInBatch!))) {
            firstIncomingIdInBatch = m.id;
            firstIncomingAtInBatch = ts;
          }
        }
      }
      final merged = byId.values.toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return at.compareTo(bt);
        });
      mentionMsgsInBatch.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });
      final mentionIdsInBatch = mentionMsgsInBatch
          .map((m) => m.id.trim())
          .where((id) => id.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _messages = merged;
        if (wasNearBottom) {
          _pendingNewMessageCount = 0;
          _pendingNewMessageFirstId = null;
          _pendingMentionMessageIds = const <String>[];
        } else if (addedIncoming > 0) {
          _pendingNewMessageCount += addedIncoming;
          if (_pendingNewMessageFirstId == null &&
              firstIncomingIdInBatch != null) {
            _pendingNewMessageFirstId = firstIncomingIdInBatch;
          }
        }
        if (!wasNearBottom && mentionIdsInBatch.isNotEmpty) {
          final nextMentions = <String>[
            ..._pendingMentionMessageIds,
            ...mentionIdsInBatch
                .where((id) => !_pendingMentionMessageIds.contains(id)),
          ];
          _pendingMentionMessageIds = nextMentions;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: wasNearBottom);
      });
      try {
        ChatLocalStore().saveGroupMessages(widget.groupId, merged);
      } catch (_) {}
      try {
        _markSeenAndClearUnread(did);
      } catch (_) {}
    });
  }

  Future<void> _rotateGroupKey() async {
    if (!_isAdmin) return;
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final l = L10n.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
                l.isArabic ? 'تدوير مفتاح التشفير' : 'Rotate encryption key'),
            content: Text(l.isArabic
                ? 'سيتم إنشاء مفتاح جديد وتوزيعه على الأعضاء. قد لا يتمكن الأعضاء غير المتصلين من قراءة الرسائل الجديدة حتى يستلموا المفتاح.'
                : 'A new key will be generated and shared to members. Offline members may not read new messages until they receive it.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.isArabic ? 'تدوير' : 'Rotate'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      final newKeyB64 = base64Encode(_randomGroupKeyBytes());
      final fp = fingerprintForKey(newKeyB64);
      final ver = await _service.rotateGroupKey(
        groupId: widget.groupId,
        actorId: did,
        keyFp: fp,
      );
      await ChatLocalStore().saveGroupKey(widget.groupId, newKeyB64);
      await _refreshMembers();
      final ids = _members.map((m) => m.deviceId).toList();
      await _shareGroupKey(newKeyB64, ids);
      if (!mounted) return;
      setState(() {
        _error =
            l.isArabic ? 'تم تدوير المفتاح (v$ver)' : 'Key rotated (v$ver)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _showKeyEventsSheet() async {
    if (!_isAdmin) return;
    final did = _deviceId ?? '';
    if (did.isEmpty) return;
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final maxHeight = MediaQuery.of(ctx).size.height * 0.72;
        return SafeArea(
          child: SizedBox(
            height: maxHeight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.isArabic ? 'سجل تدوير المفاتيح' : 'Key rotation log',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<List<ChatGroupKeyEvent>>(
                      future: _service.listGroupKeyEvents(
                        groupId: widget.groupId,
                        deviceId: did,
                        limit: 50,
                      ),
                      builder: (ctx2, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Text(
                              '${snap.error}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        final events = snap.data ?? const <ChatGroupKeyEvent>[];
                        if (events.isEmpty) {
                          return Center(
                            child: Text(
                              l.isArabic
                                  ? 'لا توجد عمليات تدوير بعد.'
                                  : 'No key rotations yet.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            ),
                          );
                        }
                        String fmtTs(DateTime? dt) {
                          if (dt == null) return '';
                          final x = dt.toLocal();
                          return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')} '
                              '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
                        }

                        return ListView.separated(
                          itemCount: events.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = events[i];
                            final fp = (e.keyFp ?? '').trim();
                            final actorLabel = _displayNameForDeviceId(
                              e.actorId,
                              l,
                              fallback: l.isArabic ? 'مشرف' : 'An admin',
                            );
                            return ListTile(
                              leading: const Icon(Icons.key_outlined),
                              title: Text(
                                'v${e.version}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (e.actorId.trim().isNotEmpty)
                                    l.isArabic
                                        ? 'بواسطة $actorLabel'
                                        : 'by $actorLabel',
                                  if (fp.isNotEmpty) 'fp $fp',
                                  if (e.createdAt != null) fmtTs(e.createdAt),
                                ].join(' • '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .70),
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
            ),
          ),
        );
      },
    );
  }

  String _groupUnreadKey(String gid) => 'grp:$gid';

  Future<void> _markSeenAndClearUnread(String did) async {
    final store = ChatLocalStore();
    try {
      await store.setGroupSeen(widget.groupId, DateTime.now());
      final unread = await store.loadUnread();
      unread[_groupUnreadKey(widget.groupId)] = 0;
      await store.saveUnread(unread);
    } catch (_) {}
  }

  String? _computeNewMessagesAnchorMessageId({
    required List<ChatGroupMessage> messages,
    required String myId,
    required int unreadCount,
  }) {
    final me = myId.trim();
    if (me.isEmpty || unreadCount <= 0 || messages.isEmpty) return null;
    var remaining = unreadCount;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      final mid = m.id.trim();
      if (mid.isEmpty) continue;
      if (m.senderId.trim() == me) continue;
      remaining--;
      if (remaining <= 0) return mid;
    }
    return null;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggleComposerPanel(_ShamellGroupComposerPanel panel) {
    if (_recordingVoice) return;
    if (_composerPanel == panel) {
      setState(() {
        _composerPanel = _ShamellGroupComposerPanel.none;
        _shamellVoiceMode = false;
      });
      try {
        _msgFocus.requestFocus();
      } catch (_) {}
      return;
    }

    setState(() {
      _composerPanel = panel;
      _shamellVoiceMode = false;
      if (panel == _ShamellGroupComposerPanel.more) {
        _shamellMorePanelPage = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            if (_shamellMorePanelCtrl.hasClients) {
              _shamellMorePanelCtrl.jumpToPage(0);
            }
          } catch (_) {}
        });
      }
    });
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
    });
  }

  Future<void> _sendTextQuick(String text) async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      final msg = await _service.sendGroupMessage(
        groupId: widget.groupId,
        senderId: did,
        text: trimmed,
      );
      _didSendMessage = true;
      unawaited(_unarchiveGroupIfNeeded());
      if (!mounted) return;
      setState(() {
        _messages = <ChatGroupMessage>[..._messages, msg];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: true);
      });
      try {
        await ChatLocalStore().saveGroupMessages(widget.groupId, _messages);
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _sendLocationQuick(
    double lat,
    double lon, {
    String? label,
  }) async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    try {
      final msg = await _service.sendGroupMessage(
        groupId: widget.groupId,
        senderId: did,
        kind: 'location',
        text: (label ?? '').trim(),
        lat: lat,
        lon: lon,
      );
      _didSendMessage = true;
      unawaited(_unarchiveGroupIfNeeded());
      if (!mounted) return;
      setState(() {
        _messages = <ChatGroupMessage>[..._messages, msg];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: true);
      });
      try {
        await ChatLocalStore().saveGroupMessages(widget.groupId, _messages);
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _sendCurrentLocation() async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final l = L10n.of(context);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _toast(l.isArabic
            ? 'خدمة الموقع معطلة على هذا الجهاز.'
            : 'Location services are disabled on this device.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast(l.isArabic
            ? 'لا يمكن الوصول إلى الموقع. تحقق من صلاحيات التطبيق.'
            : 'Cannot access location. Please check app permissions.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      await _sendLocationQuick(pos.latitude, pos.longitude);
      _toast(l.isArabic
          ? 'تم إرسال موقعك الحالي.'
          : 'Your current location was sent.');
    } catch (_) {
      _toast(l.isArabic ? 'تعذّر إرسال الموقع.' : 'Could not send location.');
    }
  }

  Future<void> _openLocationOnMap(double lat, double lon) async {
    final uri = Uri.parse('https://www.google.com/maps?q=$lat,$lon');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _toast(L10n.of(context).isArabic
            ? 'تعذّر فتح الخريطة.'
            : 'Could not open the map.');
      }
    } catch (_) {
      _toast(L10n.of(context).isArabic
          ? 'تعذّر فتح الخريطة.'
          : 'Could not open the map.');
    }
  }

  Future<void> _sendContactCard(String contactId) async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final id = contactId.trim();
    if (id.isEmpty) return;
    String name = '';
    try {
      final c = await _service.resolveDevice(id);
      name = (c.name ?? '').trim();
    } catch (_) {}
    final label = name.isNotEmpty ? name : id;
    try {
      final msg = await _service.sendGroupMessage(
        groupId: widget.groupId,
        senderId: did,
        kind: 'contact',
        text: label,
        contactId: id,
        contactName: name,
      );
      _didSendMessage = true;
      unawaited(_unarchiveGroupIfNeeded());
      if (!mounted) return;
      setState(() {
        _messages = <ChatGroupMessage>[..._messages, msg];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: true);
      });
      try {
        await ChatLocalStore().saveGroupMessages(widget.groupId, _messages);
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _openContactCardPicker() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            FriendsPage(widget.baseUrl, mode: FriendsPageMode.picker),
      ),
    );
    final id = (selected ?? '').trim();
    if (id.isEmpty) return;
    await _sendContactCard(id);
  }

  void _openMiniAppFromGroupChat(String id) {
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MiniProgramPage(
            id: id,
            baseUrl: widget.baseUrl,
            walletId: '',
            deviceId: _deviceId ?? '',
            onOpenMod: _openMiniAppFromGroupChat,
          ),
        ),
      ),
    );
  }

  Future<void> _openMiniPrograms() async {
    final did = _deviceId ?? '';
    String walletId = '';
    try {
      final sp = await SharedPreferences.getInstance();
      walletId = sp.getString('wallet_id') ?? '';
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniProgramsDiscoverPage(
          baseUrl: widget.baseUrl,
          walletId: walletId,
          deviceId: did,
          onOpenMod: _openMiniAppFromGroupChat,
        ),
      ),
    );
  }

  Future<void> _openFavoritesPicker() async {
    final l = L10n.of(context);

    List<Map<String, dynamic>> items = const <Map<String, dynamic>>[];
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('favorites_items') ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        items = decoded
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}

    bool isLocation(Map<String, dynamic> p) {
      final kind = (p['kind'] ?? '').toString();
      if (kind == 'location') return true;
      return p['lat'] is num && p['lon'] is num;
    }

    double? asDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String && v.trim().isNotEmpty) return double.tryParse(v);
      return null;
    }

    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final bg = isDark ? theme.colorScheme.surface : Colors.white;
        final title = l.isArabic ? 'المفضلة' : 'Favorites';
        final emptyLabel =
            l.isArabic ? 'لا توجد عناصر في المفضلة بعد.' : 'No favorites yet.';
        final viewAll = l.isArabic ? 'عرض الكل' : 'View all';

        final clipped = items.take(24).toList();
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Container(
            color: Colors.black54,
            child: GestureDetector(
              onTap: () {},
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FavoritesPage(
                                      baseUrl: widget.baseUrl,
                                    ),
                                  ),
                                );
                              },
                              child: Text(viewAll),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (clipped.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              emptyLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .65),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 420),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: clipped.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: theme.dividerColor,
                              ),
                              itemBuilder: (_, idx) {
                                final p = clipped[idx];
                                final txt = (p['text'] ?? '').toString().trim();
                                final loc = isLocation(p);
                                final subtitle = loc
                                    ? (l.isArabic ? 'موقع' : 'Location')
                                    : (l.isArabic ? 'ملاحظة' : 'Note');
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    loc
                                        ? Icons.place_outlined
                                        : Icons.bookmark_outline,
                                  ),
                                  title: Text(
                                    txt.isNotEmpty ? txt : subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(subtitle),
                                  onTap: () => Navigator.of(ctx).pop(p),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(l.shamellDialogCancel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (chosen == null) return;
    if (isLocation(chosen)) {
      final lat = asDouble(chosen['lat']);
      final lon = asDouble(chosen['lon']);
      if (lat == null || lon == null) return;
      final label = (chosen['text'] ?? '').toString().trim();
      await _sendLocationQuick(lat, lon, label: label.isEmpty ? null : label);
      return;
    }
    final txt = (chosen['text'] ?? '').toString().trim();
    if (txt.isEmpty) return;
    await _sendTextQuick(txt);
  }

  Widget _buildMorePanel(ThemeData theme, L10n l) {
    final isDark = theme.brightness == Brightness.dark;
    const perPage = 8;

    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap,
    ) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: isDark ? .35 : .80),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    void close() {
      if (!mounted) return;
      setState(() {
        _composerPanel = _ShamellGroupComposerPanel.none;
      });
    }

    void notSupported() {
      close();
      _toast(l.isArabic
          ? 'غير مدعوم في محادثات المجموعات بعد.'
          : 'Not supported in group chats yet.');
    }

    Widget dot(bool active) {
      final activeColor = isDark
          ? Colors.white.withValues(alpha: .70)
          : Colors.black.withValues(alpha: .55);
      final inactiveColor = isDark
          ? Colors.white.withValues(alpha: .18)
          : Colors.black.withValues(alpha: .18);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: active ? 10 : 6,
        height: 6,
        decoration: BoxDecoration(
          color: active ? activeColor : inactiveColor,
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.photo_outlined,
        label: l.shamellAttachImage,
        onTap: () {
          close();
          unawaited(_pickAttachment());
        },
      ),
      (
        icon: Icons.camera_alt_outlined,
        label: l.isArabic ? 'الكاميرا' : 'Camera',
        onTap: () {
          close();
          unawaited(_pickAttachment(source: ImageSource.camera));
        },
      ),
      (
        icon: Icons.videocam_outlined,
        label: l.shamellInternetCall,
        onTap: notSupported,
      ),
      (
        icon: Icons.call_outlined,
        label: l.isArabic ? 'مكالمة صوتية' : 'Voice call',
        onTap: notSupported,
      ),
      (
        icon: Icons.location_on_outlined,
        label: l.shamellSendLocation,
        onTap: () {
          close();
          unawaited(_sendCurrentLocation());
        },
      ),
      (
        icon: Icons.bookmark_outline,
        label: l.isArabic ? 'المفضلة' : 'Favorites',
        onTap: () {
          close();
          unawaited(_openFavoritesPicker());
        },
      ),
      (
        icon: Icons.contact_page_outlined,
        label: l.isArabic ? 'بطاقة جهة اتصال' : 'Contact card',
        onTap: () {
          close();
          unawaited(_openContactCardPicker());
        },
      ),
      (
        icon: Icons.apps_outlined,
        label: l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs',
        onTap: () {
          close();
          unawaited(_openMiniPrograms());
        },
      ),
    ];

    final pageCount = max(1, (actions.length / perPage).ceil());
    final clampedPage =
        _shamellMorePanelPage.clamp(0, max(0, pageCount - 1)).toInt();

    Widget page(int pageIdx) {
      final start = pageIdx * perPage;
      final end = min(start + perPage, actions.length);
      final slice = actions.sublist(start, end);
      final tiles = slice.map((a) => action(a.icon, a.label, a.onTap)).toList();
      while (tiles.length < perPage) {
        tiles.add(const SizedBox.shrink());
      }
      return GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        crossAxisCount: 4,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.95,
        children: tiles,
      );
    }

    return Container(
      height: _shamellMorePanelHeight,
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : ShamellPalette.background,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: isDark ? .18 : .38),
            width: 0.6,
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _shamellMorePanelCtrl,
              itemCount: pageCount,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (idx) {
                setState(() {
                  _shamellMorePanelPage = idx;
                });
              },
              itemBuilder: (_, pageIdx) => page(pageIdx),
            ),
          ),
          if (pageCount > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pageCount; i++) dot(i == clampedPage),
                ],
              ),
            )
          else
            const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _pickAttachment(
      {ImageSource source = ImageSource.gallery}) async {
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
        _attachedBytes = bytes;
        final ext = (x.name.split('.').last).toLowerCase();
        _attachedMime = ext == 'png' ? 'image/png' : 'image/jpeg';
        _attachedName = x.name;
      });
    } catch (e) {
      final l = L10n.of(context);
      setState(
        () => _error =
            '${l.shamellAttachFailed}: ${sanitizeExceptionForUi(error: e, isArabic: l.isArabic)}',
      );
    }
  }

  Future<void> _startVoiceRecord() async {
    try {
      if (_recordingVoice) return;
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) return;
      final tmp = Directory.systemTemp;
      final file = File(
          '${tmp.path}/shamell_grp_voice_${DateTime.now().millisecondsSinceEpoch}.aac');
      final config = const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );
      await _recorder.start(config, path: file.path);
      setState(() {
        _recordingVoice = true;
        _voiceStart = DateTime.now();
        _voiceElapsedSecs = 0;
        _voiceCancelPending = false;
        _voiceLocked = false;
      });
      _voiceTicker?.cancel();
      _voiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (!_recordingVoice) return;
        final start = _voiceStart;
        if (start == null) return;
        setState(() {
          _voiceElapsedSecs = DateTime.now().difference(start).inSeconds;
        });
      });
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _stopVoiceRecord() async {
    if (!_recordingVoice) return;
    final start = _voiceStart ?? DateTime.now();
    final elapsedMs = DateTime.now().difference(start).inMilliseconds;
    // Very short taps should behave like Shamell: cancel instead of sending.
    if (elapsedMs < 800) {
      final l = L10n.of(context);
      await _cancelVoiceRecord();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shamellVoiceTooShort)),
      );
      return;
    }
    setState(() {
      _recordingVoice = false;
      _voiceStart = null;
      _voiceCancelPending = false;
      _voiceLocked = false;
      _voiceGestureStartLocal = null;
      _voiceElapsedSecs = 0;
    });
    try {
      _voiceTicker?.cancel();
    } catch (_) {}
    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final elapsed = DateTime.now().difference(start).inSeconds;
      final secs = elapsed.clamp(1, 120);
      final did = _deviceId;
      if (did == null || did.isEmpty) return;
      final msg = await _service.sendGroupMessage(
        groupId: widget.groupId,
        senderId: did,
        kind: 'voice',
        attachmentB64: base64Encode(bytes),
        attachmentMime: 'audio/aac',
        voiceSecs: secs,
      );
      _didSendMessage = true;
      unawaited(_unarchiveGroupIfNeeded());
      if (!mounted) return;
      setState(() {
        _messages = <ChatGroupMessage>[..._messages, msg];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: true);
      });
      try {
        await ChatLocalStore().saveGroupMessages(widget.groupId, _messages);
      } catch (_) {}
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _cancelVoiceRecord() async {
    if (!_recordingVoice) return;
    setState(() {
      _recordingVoice = false;
      _voiceStart = null;
      _voiceCancelPending = false;
      _voiceLocked = false;
      _voiceGestureStartLocal = null;
      _voiceElapsedSecs = 0;
    });
    try {
      _voiceTicker?.cancel();
    } catch (_) {}
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && _attachedBytes == null) return;
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final att = _attachedBytes;
    final mime = _attachedMime;
    setState(() {
      _msgCtrl.clear();
      _attachedBytes = null;
      _attachedMime = null;
      _attachedName = null;
    });
    try {
      final msg = att != null
          ? await _service.sendGroupMessage(
              groupId: widget.groupId,
              senderId: did,
              text: text,
              kind: 'image',
              attachmentB64: base64Encode(att),
              attachmentMime: mime ?? 'image/jpeg',
            )
          : await _service.sendGroupMessage(
              groupId: widget.groupId,
              senderId: did,
              text: text,
            );
      _didSendMessage = true;
      unawaited(_unarchiveGroupIfNeeded());
      if (!mounted) return;
      setState(() {
        _messages = <ChatGroupMessage>[..._messages, msg];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: true);
      });
      try {
        await ChatLocalStore().saveGroupMessages(widget.groupId, _messages);
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
      });
    }
  }

  Future<void> _configureVoiceSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(_voiceUseSpeaker
          ? const AudioSessionConfiguration.music()
          : const AudioSessionConfiguration.speech());
    } catch (_) {}
  }

  void _startProximityListener() {
    _proximitySub?.cancel();
    try {
      _proximitySub = ProximitySensor.events.listen((int event) async {
        final near = event > 0;
        if (!mounted) return;
        _voiceUseSpeaker = !near;
        await _configureVoiceSession();
        setState(() {});
      });
    } catch (_) {}
  }

  Future<void> _playVoice(ChatGroupMessage m) async {
    final b64 = m.attachmentB64;
    if (b64 == null || b64.isEmpty) return;
    try {
      final bytes = base64Decode(b64);
      final tmp = Directory.systemTemp;
      final file = File('${tmp.path}/shamell_grp_voice_${m.id}.aac');
      await file.writeAsBytes(bytes, flush: true);
      await _configureVoiceSession();
      _startProximityListener();
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(file.path);
      if (!mounted) return;
      setState(() {
        _playingVoiceId = m.id;
      });
      await _audioPlayer.play();
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _toggleVoicePlayback(ChatGroupMessage m) async {
    if (!_playedVoiceMessageIds.contains(m.id)) {
      final did = _deviceId;
      if (did != null && did.isNotEmpty && m.senderId != did) {
        setState(() {
          _playedVoiceMessageIds = <String>{..._playedVoiceMessageIds, m.id};
        });
        unawaited(
          ChatLocalStore().markGroupVoicePlayed(widget.groupId, m.id),
        );
      }
    }
    if (_playingVoiceId == m.id) {
      try {
        if (_audioPlayer.playing) {
          await _audioPlayer.pause();
          return;
        }
        await _configureVoiceSession();
        _startProximityListener();
        await _audioPlayer.play();
        return;
      } catch (_) {
        // If resume fails, fallback to reloading from bytes.
      }
    }
    await _playVoice(m);
  }

  Future<void> _refreshMembers() async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    try {
      final members = await _service.listGroupMembers(
        groupId: widget.groupId,
        deviceId: did,
      );
      if (!mounted) return;
      setState(() {
        _members = members;
        _isAdmin = members.any((m) => m.deviceId == did && m.role == 'admin');
      });
      unawaited(_resolveMissingMemberNames(members));
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  Future<void> _showMembersSheet() async {
    await _refreshMembers();
    if (!mounted) return;
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final did = _deviceId ?? '';
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    '@',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(l.isArabic ? '@الكل' : '@all'),
                subtitle: Text(l.isArabic ? 'ذكر الجميع' : 'Mention everyone'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  _insertMention('all');
                },
              ),
              const Divider(height: 1),
              ..._members.map((m) {
                final isMe = m.deviceId == did;
                final isAdmin = m.role == 'admin';
                final titleLabel = _displayNameForDeviceId(m.deviceId, l);
                final roleLabel = isAdmin
                    ? (l.isArabic ? 'مسؤول' : 'Admin')
                    : (l.isArabic ? 'عضو' : 'Member');
                final idLabel = m.deviceId.trim();
                return ListTile(
                  onTap: isMe
                      ? null
                      : () {
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          _insertMention(m.deviceId);
                        },
                  leading: CircleAvatar(
                    child: Text(
                      titleLabel.isNotEmpty
                          ? titleLabel.characters.first.toUpperCase()
                          : (idLabel.isNotEmpty
                              ? idLabel.characters.first.toUpperCase()
                              : '#'),
                    ),
                  ),
                  title: Text(titleLabel),
                  subtitle: Text(
                    [
                      roleLabel,
                      if (idLabel.isNotEmpty) idLabel,
                    ].join(' • '),
                  ),
                  trailing: _isAdmin && !isMe
                      ? TextButton(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            final nextRole = isAdmin ? 'member' : 'admin';
                            try {
                              await _service.setGroupRole(
                                groupId: widget.groupId,
                                actorId: did,
                                targetId: m.deviceId,
                                role: nextRole,
                              );
                              await _refreshMembers();
                            } catch (e) {
                              setState(() =>
                                  _error = sanitizeExceptionForUi(error: e));
                            }
                          },
                          child: Text(
                            isAdmin
                                ? (l.isArabic
                                    ? 'إزالة الصلاحية'
                                    : 'Remove admin')
                                : (l.isArabic ? 'ترقية لمسؤول' : 'Make admin'),
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      : null,
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showInviteSheet() async {
    if (!_isAdmin) return;
    final did = _deviceId ?? '';
    if (did.isEmpty) return;
    final l = L10n.of(context);
    await _refreshMembers();
    final membersSet = _members.map((m) => m.deviceId.trim()).toSet();
    List<ChatContact> contacts = <ChatContact>[];
    try {
      contacts = await ChatLocalStore().loadContacts();
    } catch (_) {}
    final candidates = contacts
        .where((c) => c.id.trim().isNotEmpty)
        .where((c) => c.id.trim() != did)
        .where((c) => !membersSet.contains(c.id.trim()))
        .toList()
      ..sort((a, b) {
        final an = (a.name ?? '').trim().toLowerCase();
        final bn = (b.name ?? '').trim().toLowerCase();
        final ak = an.isNotEmpty ? an : a.id.toLowerCase();
        final bk = bn.isNotEmpty ? bn : b.id.toLowerCase();
        final c = ak.compareTo(bk);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    final manualCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    final selectedIds = <String>{};
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        final maxHeight = MediaQuery.of(ctx).size.height * 0.72;
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
              left: 12, right: 12, top: 12, bottom: bottom + 12),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: StatefulBuilder(
              builder: (ctx2, setLocal) {
                final q = query.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? candidates
                    : candidates.where((c) {
                        final name = (c.name ?? '').trim().toLowerCase();
                        final id = c.id.trim().toLowerCase();
                        return name.contains(q) || id.contains(q);
                      }).toList();

                List<String> buildIds() {
                  final ids = <String>{...selectedIds};
                  final raw = manualCtrl.text.trim();
                  if (raw.isNotEmpty) {
                    ids.addAll(
                      raw
                          .split(RegExp(r'[\s,]+'))
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty),
                    );
                  }
                  ids.remove(did);
                  ids.removeWhere((id) => membersSet.contains(id));
                  return ids.toList();
                }

                final inviteIds = buildIds();

                return SizedBox(
                  height: maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.isArabic ? 'إضافة أعضاء' : 'Invite members',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: l.isArabic ? 'بحث' : 'Search',
                        ),
                        onChanged: (v) => setLocal(() => query = v),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  l.isArabic
                                      ? 'لا توجد جهات اتصال.'
                                      : 'No contacts.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  final id = c.id.trim();
                                  final name = (c.name ?? '').trim();
                                  final title =
                                      name.isNotEmpty ? name : _shortId(id);
                                  final selected = selectedIds.contains(id);
                                  return ListTile(
                                    onTap: () {
                                      setLocal(() {
                                        if (selected) {
                                          selectedIds.remove(id);
                                        } else {
                                          selectedIds.add(id);
                                        }
                                      });
                                    },
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          theme.colorScheme.primaryContainer,
                                      child: Text(
                                        title.isNotEmpty
                                            ? title.characters.first
                                                .toUpperCase()
                                            : '#',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    title: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .70),
                                      ),
                                    ),
                                    trailing: Checkbox(
                                      value: selected,
                                      onChanged: (v) {
                                        setLocal(() {
                                          if (v == true) {
                                            selectedIds.add(id);
                                          } else {
                                            selectedIds.remove(id);
                                          }
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: manualCtrl,
                        decoration: InputDecoration(
                          hintText: l.isArabic
                              ? 'أدخل معرفات إضافية (اختياري)'
                              : 'Enter additional IDs (optional)',
                        ),
                        minLines: 1,
                        maxLines: 2,
                        onChanged: (_) => setLocal(() {}),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'المحدد: ${inviteIds.length}'
                                  : 'Selected: ${inviteIds.length}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(l.shamellDialogCancel),
                          ),
                          const SizedBox(width: 8),
                          PrimaryButton(
                            label: l.isArabic ? 'إضافة' : 'Invite',
                            onPressed: inviteIds.isEmpty
                                ? null
                                : () async {
                                    Navigator.of(ctx).pop();
                                    try {
                                      await _service.inviteGroupMembers(
                                        groupId: widget.groupId,
                                        inviterId: did,
                                        memberIds: inviteIds,
                                      );
                                      try {
                                        final keyB64 =
                                            await _getOrCreateGroupKeyIfAdmin();
                                        if (keyB64 != null &&
                                            keyB64.isNotEmpty) {
                                          await _shareGroupKey(
                                              keyB64, inviteIds);
                                        }
                                      } catch (_) {}
                                      await _refreshMembers();
                                    } catch (e) {
                                      setState(() => _error =
                                          sanitizeExceptionForUi(error: e));
                                    }
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    searchCtrl.dispose();
    manualCtrl.dispose();
  }

  Future<void> _updatePinnedChatOrderForGroup(bool pinned) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final current = sp.getStringList('chat.pinned_chats') ?? const <String>[];
      final key = _groupUnreadKey(widget.groupId);
      final next = List<String>.from(current)..removeWhere((x) => x == key);
      if (pinned) {
        next.insert(0, key);
      }
      if (next.isEmpty) {
        await sp.remove('chat.pinned_chats');
      } else {
        await sp.setStringList('chat.pinned_chats', next);
      }
    } catch (_) {}
  }

  Future<void> _setGroupMuted(bool muted) async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final prev = _groupMuted;
    setState(() => _groupMuted = muted);
    try {
      await _service.setGroupPrefs(
        deviceId: did,
        groupId: widget.groupId,
        muted: muted,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _groupMuted = prev);
      }
      rethrow;
    }
  }

  Future<void> _setGroupPinned(bool pinned) async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    final prev = _groupPinned;
    setState(() => _groupPinned = pinned);
    await _updatePinnedChatOrderForGroup(pinned);
    try {
      await _service.setGroupPrefs(
        deviceId: did,
        groupId: widget.groupId,
        pinned: pinned,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _groupPinned = prev);
      }
      unawaited(_updatePinnedChatOrderForGroup(prev));
      rethrow;
    }
  }

  Future<void> _clearGroupChatHistory() async {
    final store = ChatLocalStore();
    try {
      await store.setGroupSeen(widget.groupId, DateTime.now());
    } catch (_) {}
    try {
      await store.deleteGroupMessages(widget.groupId);
    } catch (_) {}
    try {
      final unread = await store.loadUnread();
      unread[_groupUnreadKey(widget.groupId)] = 0;
      await store.saveUnread(unread);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _messages = const <ChatGroupMessage>[];
      _messageKeys.clear();
      _messageBubbleKeys.clear();
      _messageReactions = <String, String>{};
      _newMessagesAnchorMessageId = null;
      _newMessagesCountAtOpen = 0;
      _pendingMentionMessageIds = const <String>[];
      _pendingNewMessageCount = 0;
      _pendingNewMessageFirstId = null;
    });
    unawaited(_saveMessageReactions());
  }

  Future<void> _openGroupInfo() async {
    final l = L10n.of(context);
    Uint8List? avatarBytes;
    final b64 = (_groupAvatarB64 ?? '').trim();
    if (b64.isNotEmpty) {
      try {
        avatarBytes = base64Decode(b64);
      } catch (_) {}
    }

    final myId = (_deviceId ?? '').trim();
    final members = _members
        .map((m) {
          final id = m.deviceId.trim();
          if (id.isEmpty) return null;
          return ShamellGroupMemberDisplay(
            id: id,
            name: _displayNameForDeviceId(id, l),
            isAdmin: m.role == 'admin',
            isMe: myId.isNotEmpty && id == myId,
          );
        })
        .whereType<ShamellGroupMemberDisplay>()
        .toList();

    final name =
        _groupName.trim().isNotEmpty ? _groupName.trim() : widget.groupId;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShamellGroupChatInfoPage(
          groupId: widget.groupId,
          groupName: name,
          avatarBytes: avatarBytes,
          members: members,
          isAdmin: _isAdmin,
          muted: _groupMuted,
          pinned: _groupPinned,
          themeKey: _chatThemeKey,
          onToggleMuted: _setGroupMuted,
          onTogglePinned: _setGroupPinned,
          onSetTheme: _setChatThemeKey,
          onShowMembers: _showMembersSheet,
          onInviteMembers: _showInviteSheet,
          onEditGroup: _showEditGroupSheet,
          onShowKeyEvents: _showKeyEventsSheet,
          onRotateKey: _rotateGroupKey,
          onClearChatHistory: _clearGroupChatHistory,
          onLeaveGroup: _leaveGroup,
        ),
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final did = _deviceId;
    if (did == null || did.isEmpty) return;
    try {
      await _service.leaveGroup(groupId: widget.groupId, deviceId: did);
      try {
        await ChatLocalStore().deleteGroupKey(widget.groupId);
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatBgColor = _chatThemeKey == 'dark'
        ? theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: isDark ? .72 : .96)
        : _chatThemeKey == 'green'
            ? ShamellPalette.green.withValues(alpha: isDark ? .14 : .08)
            : (isDark ? theme.colorScheme.surface : const Color(0xFFEDEDED));
    final newMessagesIndex = (_newMessagesAnchorMessageId != null &&
            _newMessagesAnchorMessageId!.isNotEmpty &&
            _newMessagesCountAtOpen > 0)
        ? _messages.indexWhere((m) => m.id == _newMessagesAnchorMessageId)
        : -1;
    final showNewMessagesMarker =
        newMessagesIndex != -1 && _newMessagesCountAtOpen > 0;
    final showJumpToBottom =
        _pendingNewMessageCount <= 0 && !_isNearBottom && _messages.isNotEmpty;
    final panelExtra = _composerPanel == _ShamellGroupComposerPanel.none
        ? 0.0
        : _shamellMorePanelHeight;
    final mentionBottomBase =
        (_pendingNewMessageCount > 0 || showJumpToBottom) ? 148.0 : 96.0;
    final mentionBottom = mentionBottomBase + panelExtra;
    final overlayBottom = 96.0 + panelExtra;

    Widget buildBubble(ChatGroupMessage m) {
      final dt = m.createdAt;
      final ts = dt == null
          ? ''
          : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      final isMe = _deviceId != null && m.senderId == _deviceId;
      final bg = isMe
          ? (isDark
              ? theme.colorScheme.primary.withValues(alpha: .55)
              : const Color(0xFF95EC69))
          : (isDark
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .75)
              : Colors.white);
      final cross = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
      final kind = (m.kind ?? '').toLowerCase();
      if (kind == 'system') {
        final label = _systemLabel(m, l);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      final hasAttachment =
          m.attachmentB64 != null && m.attachmentB64!.isNotEmpty;
      final mime = (m.attachmentMime ?? '').toLowerCase();
      final isImage =
          kind == 'image' || (hasAttachment && mime.startsWith('image/'));
      final isVoice = kind == 'voice';
      Uint8List? attBytes;
      if (hasAttachment) {
        try {
          attBytes = base64Decode(m.attachmentB64!);
        } catch (_) {}
      }

      Widget content;
      if (isImage && attBytes != null) {
        final bytes = attBytes;
        content = Column(
          crossAxisAlignment: cross,
          children: [
            if (m.text.isNotEmpty) _renderMentions(m.text, theme),
            GestureDetector(
              onTap: () => _openImagePreview(bytes),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  bytes,
                  width: 220,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        );
      } else if (isVoice && attBytes != null) {
        final secs = m.voiceSecs ?? 0;
        final secsLabel = secs > 0 ? '$secs' : '';
        final playing = _playingVoiceId == m.id && _voicePlaying;
        final unplayed = !isMe && !_playedVoiceMessageIds.contains(m.id);
        final clampedSecs = min(60, max(1, secs));
        final double bubbleWidth =
            (88.0 + clampedSecs * 2.4).clamp(88.0, 220.0).toDouble();
        final iconData = playing ? Icons.graphic_eq : Icons.volume_up;
        final iconColor = playing
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: .75);
        final durationText =
            secs > 0 ? (l.isArabic ? '$secs ث' : '${secs}s') : '';
        final durationStyle = theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface.withValues(alpha: .85),
        );
        content = Semantics(
          button: true,
          label: l.shamellVoiceMessageLabel(secsLabel),
          child: GestureDetector(
            onTap: () => _toggleVoicePlayback(m),
            child: SizedBox(
              width: bubbleWidth,
              child: Row(
                children: isMe
                    ? [
                        const Spacer(),
                        if (durationText.isNotEmpty)
                          Text(durationText, style: durationStyle),
                        if (durationText.isNotEmpty) const SizedBox(width: 6),
                        Icon(iconData, size: 18, color: iconColor),
                      ]
                    : [
                        Icon(iconData, size: 18, color: iconColor),
                        if (durationText.isNotEmpty) const SizedBox(width: 6),
                        if (durationText.isNotEmpty)
                          Text(durationText, style: durationStyle),
                        const Spacer(),
                        if (unplayed)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
              ),
            ),
          ),
        );
      } else if (kind == 'location' && m.lat != null && m.lon != null) {
        final lat = m.lat!;
        final lon = m.lon!;
        final label = m.text.trim();
        final title =
            label.isNotEmpty ? label : (l.isArabic ? 'موقع' : 'Location');
        content = Column(
          crossAxisAlignment: cross,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place_outlined, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _openLocationOnMap(lat, lon),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: Text(l.shamellLocationOpenInMap),
            ),
          ],
        );
      } else if (kind == 'contact' && (m.contactId ?? '').trim().isNotEmpty) {
        final contactId = (m.contactId ?? '').trim();
        final name = m.text.trim().isNotEmpty
            ? m.text.trim()
            : (m.contactName ?? '').trim();
        final display = name.isNotEmpty ? name : contactId;
        final initial =
            display.isNotEmpty ? display.substring(0, 1).toUpperCase() : '?';
        content = InkWell(
          onTap: () {
            if (contactId.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ShamellChatPage(
                  baseUrl: widget.baseUrl,
                  initialPeerId: contactId,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surface
                  : Colors.white.withValues(
                      alpha: .95,
                    ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.black.withValues(alpha: .10),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: isDark ? .24 : .14,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            contactId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: .45),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(
                    alpha: isDark ? .35 : .55,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.isArabic ? 'بطاقة جهة اتصال' : 'Contact card',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final displayText =
            (kind == 'sealed' && m.text.isEmpty && (!hasAttachment))
                ? (l.isArabic ? 'رسالة مشفرة' : 'Encrypted message')
                : m.text;
        content = _renderMentions(displayText, theme);
      }

      final isHighlighted = m.id.isNotEmpty && _highlightedMessageId == m.id;
      final highlightTint = theme.colorScheme.primary.withValues(
        alpha: isMe ? .18 : .14,
      );
      final highlightBg =
          isHighlighted ? (Color.lerp(bg, highlightTint, .55) ?? bg) : bg;
      final highlightBorderColor =
          theme.colorScheme.primary.withValues(alpha: .52);
      final highlightShadowColor = theme.colorScheme.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? .28 : .18,
      );

      final bubble = AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: highlightBg,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          border: isHighlighted
              ? Border.all(color: highlightBorderColor, width: 1.2)
              : null,
          boxShadow: isHighlighted
              ? <BoxShadow>[
                  BoxShadow(
                    color: highlightShadowColor,
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: cross,
          children: [
            content,
            if (ts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  ts,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ),
          ],
        ),
      );

      final bubbleKey = m.id.isNotEmpty
          ? _messageBubbleKeys.putIfAbsent(m.id, () => GlobalKey())
          : null;
      final reaction = m.id.isNotEmpty ? (_messageReactions[m.id] ?? '') : '';

      final incoming = !isMe;
      final maxBubbleWidth = MediaQuery.of(context).size.width * 0.66;
      final avatar = _shamellGroupMessageAvatar(
        senderId: m.senderId,
        incoming: incoming,
        l: l,
      );
      final name = incoming
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: InkWell(
                  onTap: () => _insertMention(m.senderId),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      _displayNameForDeviceId(
                        m.senderId,
                        l,
                        fallback: m.senderId,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .65),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null;

      final bubbleStack = Stack(
        key: bubbleKey,
        clipBehavior: Clip.none,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: bubble,
          ),
          Positioned(
            left: incoming ? -6 : null,
            right: incoming ? null : -6,
            top: 10,
            child: _GroupBubbleTail(
              incoming: incoming,
              color: highlightBg,
            ),
          ),
        ],
      );

      final bubbleColumn = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: cross,
        children: [
          if (name != null) name,
          bubbleStack,
          if (reaction.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Align(
              alignment:
                  incoming ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? .08 : .80),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: .08),
                  ),
                ),
                child: Text(
                  reaction,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      );

      return GestureDetector(
        onLongPressStart: (details) {
          unawaited(
            _showGroupMessageActionsSheet(
              m,
              globalPosition: details.globalPosition,
              attachmentBytes: attBytes,
              mime: mime.isNotEmpty
                  ? mime
                  : (isVoice ? 'audio/aac' : 'image/jpeg'),
              isVoice: isVoice,
              isImage: isImage,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment:
                incoming ? MainAxisAlignment.start : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (incoming) ...[
                avatar,
                const SizedBox(width: 8),
              ],
              bubbleColumn,
              if (!incoming) ...[
                const SizedBox(width: 8),
                avatar,
              ],
            ],
          ),
        ),
      );
    }

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    _error,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final msgKey = m.id.isNotEmpty
                        ? _messageKeys.putIfAbsent(m.id, () => GlobalKey())
                        : null;
                    final bubble = buildBubble(m);
                    Widget child = msgKey == null
                        ? bubble
                        : KeyedSubtree(key: msgKey, child: bubble);
                    if (showNewMessagesMarker && i == newMessagesIndex) {
                      child = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildNewMessagesMarker(theme, l),
                          child,
                        ],
                      );
                    }
                    return child;
                  },
                ),
              ),
              if (_recordingVoice)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.mic,
                            size: 16,
                            color: _voiceCancelPending
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'تسجيل… ${_voiceElapsedSecs}s'
                                  : 'Recording… ${_voiceElapsedSecs}s',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _voiceCancelPending
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: .85),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_voiceLocked) ...[
                            TextButton.icon(
                              onPressed: () async {
                                await _cancelVoiceRecord();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l.shamellVoiceCanceledSnack),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.close, size: 16),
                              label: Text(l.shamellDialogCancel),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.icon(
                              onPressed: _stopVoiceRecord,
                              icon: const Icon(Icons.send, size: 16),
                              label: Text(l.chatSend),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _voiceLocked
                            ? l.shamellVoiceLocked
                            : (_voiceCancelPending
                                ? l.shamellVoiceReleaseToCancel
                                : l.shamellVoiceSlideUpToCancel),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: _voiceCancelPending
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_attachedBytes != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.attachment, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _attachedName ?? (l.isArabic ? 'مرفق' : 'Attachment'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _attachedBytes = null;
                            _attachedMime = null;
                            _attachedName = null;
                          });
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildMentionSuggestions(l, theme),
              ),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surface
                      : ShamellPalette.background,
                  border: Border(
                    top: BorderSide(
                      color: theme.dividerColor
                          .withValues(alpha: isDark ? .20 : .45),
                      width: 0.6,
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: _shamellVoiceMode
                          ? (l.isArabic ? 'لوحة المفاتيح' : 'Keyboard')
                          : l.shamellStartVoice,
                      icon: Icon(
                        _shamellVoiceMode
                            ? Icons.keyboard_alt_outlined
                            : Icons.keyboard_voice_outlined,
                      ),
                      onPressed: (_loading ||
                              (_deviceId ?? '').trim().isEmpty ||
                              _recordingVoice)
                          ? null
                          : () {
                              final next = !_shamellVoiceMode;
                              setState(() {
                                _shamellVoiceMode = next;
                                _composerPanel =
                                    _ShamellGroupComposerPanel.none;
                              });
                              if (next) {
                                FocusScope.of(context).unfocus();
                              } else {
                                _msgFocus.requestFocus();
                              }
                            },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: _shamellVoiceMode
                            ? GestureDetector(
                                key: const ValueKey('voice'),
                                behavior: HitTestBehavior.opaque,
                                onPanDown: (_loading ||
                                        (_deviceId ?? '').trim().isEmpty)
                                    ? null
                                    : (details) {
                                        _voiceGestureStartLocal =
                                            details.localPosition;
                                        _voiceCancelPending = false;
                                        _voiceLocked = false;
                                        _startVoiceRecord();
                                      },
                                onPanUpdate: (details) {
                                  if (!_recordingVoice ||
                                      _voiceGestureStartLocal == null) {
                                    return;
                                  }
                                  const double cancelThreshold = 60.0;
                                  const double lockThreshold = 60.0;
                                  final dy = details.localPosition.dy -
                                      _voiceGestureStartLocal!.dy;
                                  final dx = details.localPosition.dx -
                                      _voiceGestureStartLocal!.dx;
                                  if (!_voiceLocked) {
                                    final cancelNow = dy < -cancelThreshold;
                                    if (cancelNow != _voiceCancelPending) {
                                      setState(() {
                                        _voiceCancelPending = cancelNow;
                                      });
                                    }
                                    if (dx > lockThreshold) {
                                      setState(() {
                                        _voiceLocked = true;
                                        _voiceCancelPending = false;
                                      });
                                    }
                                  }
                                },
                                onPanEnd: (_) async {
                                  if (!_recordingVoice) return;
                                  if (_voiceLocked) {
                                    if (mounted) {
                                      setState(() {
                                        _voiceGestureStartLocal = null;
                                        _voiceCancelPending = false;
                                      });
                                    }
                                    return;
                                  }
                                  if (_voiceCancelPending) {
                                    await _cancelVoiceRecord();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          l.shamellVoiceCanceledSnack,
                                        ),
                                      ),
                                    );
                                  } else {
                                    await _stopVoiceRecord();
                                  }
                                  if (mounted) {
                                    setState(() {
                                      _voiceGestureStartLocal = null;
                                      _voiceCancelPending = false;
                                    });
                                  }
                                },
                                onPanCancel: () async {
                                  if (!_recordingVoice) return;
                                  if (_voiceLocked) {
                                    if (mounted) {
                                      setState(() {
                                        _voiceGestureStartLocal = null;
                                        _voiceCancelPending = false;
                                      });
                                    }
                                  } else {
                                    await _cancelVoiceRecord();
                                    if (mounted) {
                                      setState(() {
                                        _voiceGestureStartLocal = null;
                                        _voiceCancelPending = false;
                                      });
                                    }
                                  }
                                },
                                child: Builder(
                                  builder: (context) {
                                    final label = () {
                                      if (_recordingVoice && _voiceLocked) {
                                        return l.shamellVoiceLocked;
                                      }
                                      if (_recordingVoice &&
                                          _voiceCancelPending) {
                                        return l.shamellVoiceReleaseToCancel;
                                      }
                                      if (_recordingVoice) {
                                        return l.shamellRecordingVoice;
                                      }
                                      return l.shamellVoiceHoldToTalk;
                                    }();
                                    final Color bg =
                                        (_recordingVoice && _voiceCancelPending)
                                            ? Colors.redAccent
                                                .withValues(alpha: .14)
                                            : theme.colorScheme.surface;
                                    final Color borderColor =
                                        (_recordingVoice && _voiceCancelPending)
                                            ? Colors.redAccent.withValues(
                                                alpha: .55,
                                              )
                                            : theme.dividerColor.withValues(
                                                alpha: isDark ? .25 : .55,
                                              );
                                    return Container(
                                      width: double.infinity,
                                      height: 40,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: borderColor,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Container(
                                key: const ValueKey('text'),
                                width: double.infinity,
                                constraints:
                                    const BoxConstraints(minHeight: 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: theme.dividerColor
                                        .withValues(alpha: isDark ? .22 : .50),
                                  ),
                                ),
                                child: TextField(
                                  controller: _msgCtrl,
                                  focusNode: _msgFocus,
                                  minLines: 1,
                                  maxLines: 4,
                                  onTap: () {
                                    if (_composerPanel !=
                                        _ShamellGroupComposerPanel.none) {
                                      setState(() {
                                        _composerPanel =
                                            _ShamellGroupComposerPanel.none;
                                      });
                                    }
                                  },
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    hintText: l.isArabic
                                        ? 'رسالة إلى المجموعة'
                                        : 'Message to group',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _msgCtrl,
                      builder: (context, value, _) {
                        final showSend = value.text.trim().isNotEmpty ||
                            _attachedBytes != null;
                        final canSend = !_loading &&
                            (_deviceId ?? '').trim().isNotEmpty &&
                            !_recordingVoice;
                        if (showSend && !_recordingVoice) {
                          return SizedBox(
                            height: 36,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: ShamellPalette.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              onPressed: canSend ? _send : null,
                              child: Text(
                                l.chatSend,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }
                        return IconButton(
                          tooltip: l.isArabic ? 'المزيد' : 'More',
                          onPressed: (_loading ||
                                  (_deviceId ?? '').trim().isEmpty ||
                                  _recordingVoice)
                              ? null
                              : () {
                                  _toggleComposerPanel(
                                    _ShamellGroupComposerPanel.more,
                                  );
                                },
                          icon: const Icon(Icons.add_circle_outline, size: 26),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (_composerPanel == _ShamellGroupComposerPanel.more)
                _buildMorePanel(theme, l),
            ],
          );

    final title =
        _groupName.isEmpty ? (l.isArabic ? 'مجموعة' : 'Group') : _groupName;
    final memberCount = _members.isNotEmpty ? _members.length : null;
    final titleText = memberCount != null && memberCount > 0
        ? '$title ($memberCount)'
        : title;
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_didSendMessage);
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: InkWell(
            onTap: _openGroupInfo,
            borderRadius: BorderRadius.circular(8),
            child: Text(
              titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            IconButton(
              tooltip: l.isArabic ? 'معلومات المجموعة' : 'Chat Info',
              icon: const Icon(Icons.more_horiz),
              onPressed: _openGroupInfo,
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: chatBgColor)),
            Positioned.fill(
              child: SafeArea(
                child: body,
              ),
            ),
            if (_pendingMentionMessageIds.isNotEmpty)
              PositionedDirectional(
                end: 12,
                bottom: mentionBottom,
                child: _buildPendingMentionButton(theme),
              ),
            if (_pendingNewMessageCount > 0 && !_isNearBottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: overlayBottom,
                child: Center(
                  child: _buildPendingNewMessagesBar(theme, l),
                ),
              ),
            if (showJumpToBottom)
              PositionedDirectional(
                end: 12,
                bottom: overlayBottom,
                child: _buildJumpToBottomButton(theme),
              ),
          ],
        ),
      ),
    );
  }
}
