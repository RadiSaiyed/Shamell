import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:local_auth/local_auth.dart';
import 'package:pinenacl/x25519.dart' as x25519;
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'safety_number.dart';
import '../design_tokens.dart';
import '../notification_service.dart';
import '../capabilities.dart';
import '../l10n.dart';
import '../ui_kit.dart';
import '../glass.dart';
import '../shamell_ui.dart';
import '../shamell_user_id.dart';
import '../perf.dart';
import '../channels_page.dart';
import '../../mini_apps/payments/payments_shell.dart';
import '../people_p2p.dart' show PeopleP2PPage;
import '../moments_page.dart';
import '../official_template_messages_page.dart';
import '../favorites_page.dart';
import '../friends_page.dart';
import '../friend_tags_page.dart';
import '../scan_page.dart';
import '../global_search_page.dart';
import '../mini_program_runtime.dart';
import '../mini_programs_discover_page.dart';
import '../mini_apps_config.dart';
import '../shamell_settings_hub_page.dart';
import '../official_accounts_page.dart';
import '../devices_page.dart';
import '../http_error.dart';
import '../call_signaling.dart';
import '../safe_set_state.dart';
import '../voip_call_page_stub.dart'
    if (dart.library.io) '../voip_call_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import '../group_chats_page.dart';
import 'chat_models.dart';
import 'chat_service.dart';
import 'ratchet_models.dart';
import 'shamell_chat_info_page.dart';

enum _ShamellComposerPanel { none, more }

class _ShamellChatComposerDraft {
  final String text;
  final Uint8List? attachmentBytes;
  final String? attachmentMime;
  final String? attachmentName;
  final ChatMessage? replyToMessage;

  _ShamellChatComposerDraft({
    required this.text,
    this.attachmentBytes,
    this.attachmentMime,
    this.attachmentName,
    this.replyToMessage,
  });

  bool get hasText => text.trim().isNotEmpty;

  bool get hasAttachment =>
      attachmentBytes != null && attachmentBytes!.isNotEmpty;
}

class _SigningKeyPinViolation implements Exception {
  final String reason;
  const _SigningKeyPinViolation(this.reason);

  @override
  String toString() => 'SigningKeyPinViolation($reason)';
}

class _SessionBootstrapViolation implements Exception {
  final String reason;
  const _SessionBootstrapViolation(this.reason);

  @override
  String toString() => 'SessionBootstrapViolation($reason)';
}

class ShamellChatPage extends StatefulWidget {
  final String baseUrl;
  final String? initialPeerId;
  final String? initialMessageId;
  final Uint8List? presetAttachmentBytes;
  final String? presetAttachmentMime;
  final String? presetAttachmentName;

  /// When false, the internal bottom navigation bar is hidden.
  /// This is used when ShamellChatPage is embedded inside the
  /// Shamell-style SuperApp shell, which already provides a
  /// bottom navigation bar for Chats/Contacts/Discover/Me.
  final bool showBottomNav;
  const ShamellChatPage({
    super.key,
    required this.baseUrl,
    this.initialPeerId,
    this.initialMessageId,
    this.presetAttachmentBytes,
    this.presetAttachmentMime,
    this.presetAttachmentName,
    this.showBottomNav = false,
  });

  @override
  State<ShamellChatPage> createState() => _ShamellChatPageState();
}

class _ShamellChatPageState extends State<ShamellChatPage>
    with SafeSetStateMixin<ShamellChatPage> {
  static const int _curveKeyBytes = 32;
  static const Duration _chatRequestTimeout = Duration(seconds: 15);
  late final ChatService _service;
  final _store = ChatLocalStore();
  ChatIdentity? _me;
  ChatContact? _peer;
  List<ChatContact> _contacts = [];
  List<ChatGroup> _groups = [];
  final Map<String, ChatGroupPrefs> _groupPrefs = <String, ChatGroupPrefs>{};
  final _peerIdCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _chatSearchCtrl = TextEditingController();
  final _messageSearchCtrl = TextEditingController();
  final FocusNode _messageSearchFocus = FocusNode();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _chatsTabScrollCtrl = ScrollController();
  final ScrollController _contactsTabScrollCtrl = ScrollController();
  final ScrollController _threadScrollCtrl = ScrollController();
  bool _threadNearBottom = true;
  int _threadNewMessagesAwayCount = 0;
  String? _threadNewMessagesFirstId;
  String _messageSearch = '';
  String _chatSearch = '';
  final TextEditingController _contactsSearchCtrl = TextEditingController();
  String _contactsSearch = '';
  final Map<String, GlobalKey> _contactsLetterKeys = <String, GlobalKey>{};
  final GlobalKey _contactsStarredHeaderKey = GlobalKey();
  Timer? _contactsIndexOverlayTimer;
  String? _contactsIndexOverlayLetter;
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _messageBubbleKeys = <String, GlobalKey>{};
  List<ChatMessage> _messages = [];
  final Map<String, List<ChatMessage>> _cache = {};
  final Map<String, List<ChatGroupMessage>> _groupCache = {};
  Map<String, int> _unread = {};
  Set<String> _groupMentionUnread = <String>{};
  Set<String> _groupMentionAllUnread = <String>{};
  String? _activePeerId;
  String? _newMessagesAnchorPeerId;
  String? _newMessagesAnchorMessageId;
  int _newMessagesCountAtOpen = 0;
  String? _highlightedMessageId;
  Uint8List? _attachedBytes;
  String? _attachedMime;
  String? _attachedName;
  bool _loading = false;
  bool _sending = false;
  StreamSubscription<List<ChatMessage>>? _wsSub;
  StreamSubscription<ChatGroupInboxUpdate>? _grpWsSub;
  StreamSubscription<RemoteMessage>? _pushSub;
  bool _notifyPreview = false;
  bool _disappearing = false;
  Duration _disappearAfter = const Duration(minutes: 30);
  bool _showHidden = false;
  bool _showBlocked = false;
  bool _showArchived = false;
  static const double _archivedPullMaxHeight = 56.0;
  static const double _miniProgramsPullMaxHeight = 250.0;
  static const double _pullDownMaxHeight =
      _archivedPullMaxHeight + _miniProgramsPullMaxHeight;
  double _archivedPullReveal = 0.0;
  double _archivedPullDragOffset = 0.0;
  bool _archivedPullPinned = false;
  double _archivedPullPinnedHeight = 0.0;
  bool _archivedPullDragging = false;
  bool _archivedPullAdjusting = false;
  Map<String, String> _miniProgramsLatestReleaseById = <String, String>{};
  Map<String, String> _miniProgramsSeenReleaseById = <String, String>{};
  Set<String> _pullDownMiniProgramUpdateBadges = <String>{};
  Set<String> _pinnedMiniProgramIds = <String>{};
  Set<String> _recentMiniProgramIds = <String>{};
  Set<String> _archivedGroupIds = <String>{};
  String? _error;
  String? _backupText;
  final Map<String, Uint8List> _sessionKeys = {};
  final Map<String, Uint8List> _sessionKeysByFp = {};
  final Map<String, _ChainState> _chains = {};
  final Map<String, RatchetState> _ratchets = {};
  _SafetyNumber? _safetyNumber;
  String? _ratchetWarning;
  final Set<String> _seenMessageIds = {};
  bool _promptedForKeyChange = false;
  String? _sessionHash;
  ShamellCapabilities _caps = ShamellCapabilities.conservativeDefaults;
  String _shamellUserId = '';
  int _tabIndex = 0; // 0=Chats,1=Contacts,2=Discover,3=Me
  bool _selectionMode = false;
  final Set<String> _selectedChatIds = <String>{};
  bool _messageSelectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  ChatMessage? _replyToMessage;
  Map<String, String> _draftTextByChatId = <String, String>{};
  final Map<String, _ShamellChatComposerDraft> _composerDraftByChatId =
      <String, _ShamellChatComposerDraft>{};
  Timer? _draftPersistTimer;
  bool _suppressDraftListener = false;
  bool _shamellVoiceMode = false;
  _ShamellComposerPanel _composerPanel = _ShamellComposerPanel.none;
  final PageController _shamellMorePanelCtrl = PageController();
  int _shamellMorePanelPage = 0;
  bool _recordingVoice = false;
  DateTime? _voiceStart;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSub;
  String? _playingVoiceMessageId;
  bool _voicePlaying = false;
  Set<String> _voicePlayedMessageIds = <String>{};
  final AudioRecorder _recorder = AudioRecorder();
  bool _voiceCancelPending = false;
  Offset? _voiceGestureStartLocal;
  bool _voiceUseSpeaker = true;
  bool _voiceLocked = false;
  Timer? _voiceTicker;
  int _voiceElapsedSecs = 0;
  int _voiceWaveTick = 0;
  StreamSubscription<int>? _proximitySub;
  final ChatCallStore _callStore = ChatCallStore();
  List<ChatCallLogEntry>? _lastCallsCache;
  bool _hasOtherDevices = false;
  String? _otherDeviceLabel;
  OfficialAccountHandle? _linkedOfficial;
  String? _linkedOfficialPeerId;
  bool _linkedOfficialFollowed = false;
  final Set<String> _officialPeerIds = <String>{};
  final Set<String> _officialPeerUnreadFeeds = <String>{};
  bool _hasUnreadSubscriptionFeeds = false;
  bool _hasUnreadServiceNotifications = false;
  bool _hideServiceNotificationsThread = false;
  bool _hideSubscriptionsThread = false;
  final Set<String> _featuredOfficialPeerIds = <String>{};
  final Set<String> _subscriptionOfficialPeerIds = <String>{};
  final Map<String, String> _officialPeerToAccountId = <String, String>{};
  bool _showSubscriptionChatsOnly = false;
  static const String _subscriptionsPeerId = '__official_subscriptions__';
  final Set<String> _autoWelcomeLoadedForPeers = <String>{};
  final Map<String, List<Map<String, dynamic>>> _officialAutoRepliesByAccount =
      <String, List<Map<String, dynamic>>>{};
  bool _subscriptionsLoading = false;
  String? _subscriptionsError;
  List<_SubscriptionEntry> _subscriptionsItems = const <_SubscriptionEntry>[];
  bool _subscriptionsFilterUnreadOnly = false;
  int _subscriptionUnreadCount = 0;
  List<MiniAppDescriptor> _topMiniApps = const <MiniAppDescriptor>[];
  List<String> _pullDownMiniProgramIds = const <String>[];
  Map<String, String> _friendAliases = const <String, String>{};
  Map<String, String> _friendTags = const <String, String>{};
  final Set<String> _closeFriendIds = <String>{};
  Map<String, Set<String>> _pinnedMessageIdsByPeer = <String, Set<String>>{};
  final Set<String> _recalledMessageIds = <String>{};
  Map<String, String> _chatThemes = const <String, String>{};
  List<String> _pinnedChatOrder = const <String>[];
  final Map<String, String> _messageReactions = <String, String>{};

  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    final binding = SchedulerBinding.instance;
    final phase = binding.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      binding.addPostFrameCallback((_) {
        if (!mounted) return;
        super.setState(fn);
      });
      return;
    }
    super.setState(fn);
  }

  String _displayNameForPeer(ChatContact c) {
    final id = c.id;
    final alias = _friendAliases[id]?.trim();
    if (alias != null && alias.isNotEmpty) {
      return alias;
    }
    if (c.name != null && c.name!.isNotEmpty) {
      return c.name!;
    }
    return id;
  }

  Future<void> _loadChatThemes() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('chat.wallpaper_theme') ?? '{}';
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final map = <String, String>{};
        decoded.forEach((k, v) {
          final key = k;
          final val = (v ?? '').toString();
          if (key.isNotEmpty && val.isNotEmpty) {
            map[key] = val;
          }
        });
        if (mounted) {
          setState(() {
            _chatThemes = map;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveChatThemes() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('chat.wallpaper_theme', jsonEncode(_chatThemes));
    } catch (_) {}
  }

  Future<void> _showContactInfo() async {
    final peer = _peer;
    if (peer == null || !mounted) return;
    final l = L10n.of(context);
    final peerId = peer.id.trim();
    if (peerId.isEmpty) return;

    ChatContact currentPeer() {
      try {
        return _contacts.firstWhere((c) => c.id == peerId);
      } catch (_) {
        return _peer ?? peer;
      }
    }

    Future<void> saveAliasTagsToPrefs({
      required String alias,
      required String tagsText,
    }) async {
      final sp = await SharedPreferences.getInstance();

      final rawAliases = sp.getString('friends.aliases') ?? '{}';
      Map<String, dynamic> decodedAliases;
      try {
        decodedAliases = jsonDecode(rawAliases) as Map<String, dynamic>;
      } catch (_) {
        decodedAliases = <String, dynamic>{};
      }
      if (alias.isEmpty) {
        decodedAliases.remove(peerId);
      } else {
        decodedAliases[peerId] = alias;
      }
      await sp.setString('friends.aliases', jsonEncode(decodedAliases));

      final rawTags = sp.getString('friends.tags') ?? '{}';
      Map<String, dynamic> decodedTags;
      try {
        decodedTags = jsonDecode(rawTags) as Map<String, dynamic>;
      } catch (_) {
        decodedTags = <String, dynamic>{};
      }
      if (tagsText.isEmpty) {
        decodedTags.remove(peerId);
      } else {
        decodedTags[peerId] = tagsText;
      }
      await sp.setString('friends.tags', jsonEncode(decodedTags));
    }

    final meName = () {
      final me = _me;
      if (me == null) return l.isArabic ? 'أنا' : 'Me';
      final name = (me.displayName ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      return me.id.trim().isNotEmpty
          ? me.id.trim()
          : (l.isArabic ? 'أنا' : 'Me');
    }();

    final mediaPreview = <Uint8List>[];
    for (var i = _messages.length - 1; i >= 0 && mediaPreview.length < 3; i--) {
      final m = _messages[i];
      final decoded = _decodeMessage(m);
      final att = decoded.attachment;
      if (att == null || att.isEmpty) continue;
      final kind = (decoded.kind ?? '').toLowerCase();
      if (kind == 'voice') continue;
      mediaPreview.add(att);
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShamellChatInfoPage(
          myDisplayName: meName,
          displayName: _displayNameForPeer(peer),
          peerId: peerId,
          verified: peer.verified,
          peerFingerprint: peer.fingerprint,
          myFingerprint: _me?.fingerprint ?? '',
          safetyNumberFormatted: _safetyNumber?.formatted,
          safetyNumberRaw: _safetyNumber?.raw,
          onMarkVerified: peer.verified ? null : _markVerified,
          onResetSession: _resetSession,
          alias: _friendAliases[peerId] ?? '',
          tags: _friendTags[peerId] ?? '',
          themeKey: _chatThemes[peerId] ?? 'default',
          mediaPreview: mediaPreview,
          onCreateGroupChat: () async {
            final me = _me;
            if (me == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.shamellIdentityHint)),
              );
              return;
            }

            final nameCtrl = TextEditingController(
              text: (_displayNameForPeer(peer).trim().isNotEmpty
                      ? _displayNameForPeer(peer).trim()
                      : peerId)
                  .trim(),
            );
            ChatGroup? created;
            String inviteError = '';
            await showModalBottomSheet<ChatGroup?>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) {
                final theme = Theme.of(ctx);
                final bottom = MediaQuery.of(ctx).viewInsets.bottom;
                bool loading = false;
                String error = '';

                Future<void> create(StateSetter setLocal) async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty || loading) return;
                  setLocal(() {
                    loading = true;
                    error = '';
                    inviteError = '';
                  });
                  try {
                    final g =
                        await _service.createGroup(deviceId: me.id, name: name);
                    try {
                      final existing = await _store.loadGroupKey(g.id);
                      if (existing == null || existing.isEmpty) {
                        final rnd = Random.secure();
                        final keyBytes = Uint8List.fromList(
                          List<int>.generate(32, (_) => rnd.nextInt(256)),
                        );
                        await _store.saveGroupKey(g.id, base64Encode(keyBytes));
                      }
                    } catch (_) {}

                    try {
                      await _service.inviteGroupMembers(
                        groupId: g.id,
                        inviterId: me.id,
                        memberIds: [peerId],
                      );
                    } catch (e) {
                      inviteError = sanitizeExceptionForUi(error: e);
                    }

                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop(g);
                  } catch (e) {
                    setLocal(() {
                      error = sanitizeExceptionForUi(error: e);
                      loading = false;
                    });
                  }
                }

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 0,
                      bottom: bottom + 12,
                    ),
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: StatefulBuilder(
                        builder: (ctx2, setLocal) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  l.isArabic ? 'دردشة جماعية' : 'Group chat',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l.isArabic
                                      ? 'سيتم إضافة $peerId إلى المجموعة.'
                                      : '$peerId will be added to the group.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: nameCtrl,
                                  autofocus: true,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    hintText: l.isArabic
                                        ? 'اسم المجموعة'
                                        : 'Group name',
                                  ),
                                  onSubmitted: (_) => create(setLocal),
                                ),
                                if (error.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    error,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: loading
                                            ? null
                                            : () => Navigator.of(ctx2).pop(),
                                        child: Text(l.shamellDialogCancel),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: loading
                                            ? null
                                            : () => create(setLocal),
                                        child: Text(
                                          loading
                                              ? (l.isArabic ? '... ' : '... ')
                                              : (l.isArabic
                                                  ? 'إنشاء'
                                                  : 'Create'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ).then((value) {
              created = value;
            });
            nameCtrl.dispose();
            if (!mounted || created == null) return;
            if (inviteError.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l.isArabic
                        ? 'تم إنشاء المجموعة، لكن تعذر إضافة العضو.'
                        : 'Group created, but could not add the member.',
                  ),
                ),
              );
            }
            await _syncGroups();
            if (!mounted) return;
            await Navigator.push<bool?>(
              context,
              MaterialPageRoute(
                builder: (_) => GroupChatPage(
                  baseUrl: widget.baseUrl,
                  groupId: created!.id,
                  groupName: created!.name,
                ),
              ),
            );
            await _syncGroups();
          },
          isCloseFriend: _closeFriendIds.contains(peerId),
          canToggleCloseFriend: true,
          muted: peer.muted,
          pinned: peer.pinned,
          hidden: peer.hidden,
          blocked: peer.blocked,
          onToggleCloseFriend: (makeClose) async {
            try {
              final sp = await SharedPreferences.getInstance();
              final rawClose = sp.getString('friends.close') ?? '{}';
              Map<String, dynamic> decodedClose;
              try {
                decodedClose = jsonDecode(rawClose) as Map<String, dynamic>;
              } catch (_) {
                decodedClose = <String, dynamic>{};
              }
              if (makeClose) {
                decodedClose[peerId] = true;
              } else {
                decodedClose.remove(peerId);
              }
              await sp.setString('friends.close', jsonEncode(decodedClose));
              if (!mounted) return true;
              setState(() {
                if (makeClose) {
                  _closeFriendIds.add(peerId);
                } else {
                  _closeFriendIds.remove(peerId);
                }
              });
              return true;
            } catch (_) {
              return false;
            }
          },
          onToggleMuted: (muted) async {
            final c = currentPeer();
            final updated = c.copyWith(muted: muted);
            final contacts = _upsertContact(updated);
            await _store.saveContacts(contacts);
            try {
              final me = _me;
              if (me != null) {
                await _service.setPrefs(
                  deviceId: me.id,
                  peerId: peerId,
                  muted: updated.muted,
                  starred: updated.starred,
                  pinned: updated.pinned,
                );
              }
            } catch (_) {}
            if (!mounted) return;
            _applyState(() {
              _contacts = contacts;
              if (_peer?.id == updated.id) _peer = updated;
            });
          },
          onTogglePinned: (pinned) async {
            final c = currentPeer();
            final updated = c.copyWith(pinned: pinned);
            _updatePinnedChatOrderForPeer(updated.id, updated.pinned);
            final contacts = _upsertContact(updated);
            await _store.saveContacts(contacts);
            try {
              final me = _me;
              if (me != null) {
                await _service.setPrefs(
                  deviceId: me.id,
                  peerId: peerId,
                  muted: updated.muted,
                  starred: updated.starred,
                  pinned: updated.pinned,
                );
              }
            } catch (_) {}
            if (!mounted) return;
            _applyState(() {
              _contacts = contacts;
              if (_peer?.id == updated.id) _peer = updated;
            });
          },
          onToggleHidden: (hidden) async {
            final c = currentPeer();
            final updated = c.copyWith(hidden: hidden);
            final contacts = _upsertContact(updated);
            try {
              await _service.setHidden(
                deviceId: _me?.id ?? '',
                peerId: peerId,
                hidden: updated.hidden,
              );
            } catch (_) {}
            await _store.saveContacts(contacts);
            if (!mounted) return;
            _applyState(() {
              _peer = updated;
              _contacts = contacts;
              if (updated.hidden && !_showHidden) {
                _activePeerId = null;
                _peer = null;
                _messages = [];
              }
            });
          },
          onToggleBlocked: (blocked) async {
            final c = currentPeer();
            final updated = c.copyWith(
              blocked: blocked,
              blockedAt: DateTime.now(),
            );
            final contacts = _upsertContact(updated);
            try {
              await _service.setBlock(
                deviceId: _me?.id ?? '',
                peerId: peerId,
                blocked: updated.blocked,
                hidden: updated.hidden,
              );
            } catch (_) {}
            await _store.saveContacts(contacts);
            if (!mounted) return;
            _applyState(() {
              _peer = updated;
              _contacts = contacts;
              if (updated.blocked && _activePeerId == peerId) {
                _messages = [];
              }
            });
          },
          onOpenFavorites: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FavoritesPage(
                  baseUrl: widget.baseUrl,
                  chatIdFilter: peerId,
                ),
              ),
            );
          },
          onOpenMedia: () async {
            _openMediaOverview();
          },
          onSearchInChat: () async {
            Navigator.of(context).pop();
            if (_messages.isNotEmpty) {
              _applyState(() {
                _messageSearch = '';
              });
              FocusScope.of(context).requestFocus(_messageSearchFocus);
            }
          },
          onSaveRemarksTags: (alias, tagsText) async {
            final nextAlias = alias.trim();
            final nextTags = tagsText.trim();
            try {
              await saveAliasTagsToPrefs(alias: nextAlias, tagsText: nextTags);
              if (!mounted) return;
              setState(() {
                final updatedAliases = Map<String, String>.from(_friendAliases);
                if (nextAlias.isEmpty) {
                  updatedAliases.remove(peerId);
                } else {
                  updatedAliases[peerId] = nextAlias;
                }
                _friendAliases = updatedAliases;

                final updatedTags = Map<String, String>.from(_friendTags);
                if (nextTags.isEmpty) {
                  updatedTags.remove(peerId);
                } else {
                  updatedTags[peerId] = nextTags;
                }
                _friendTags = updatedTags;
              });
            } catch (_) {}
          },
          onSetTheme: (themeKey) async {
            _applyState(() {
              final updated = Map<String, String>.from(_chatThemes);
              if (themeKey == 'default') {
                updated.remove(peerId);
              } else {
                updated[peerId] = themeKey;
              }
              _chatThemes = updated;
            });
            await _saveChatThemes();
          },
          onClearChatHistory: () async {
            await _clearChatHistoryForPeer(peer);
          },
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showContactInfoLegacy() async {
    final peer = _peer;
    if (peer == null || !mounted) return;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final currentAlias = _friendAliases[peer.id] ?? '';
    final currentTags = _friendTags[peer.id] ?? '';
    final ctrl = TextEditingController(text: currentAlias);
    final tagsCtrl = TextEditingController(text: currentTags);
    final bool isCloseFriend = _closeFriendIds.contains(peer.id);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (ctx) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return Scaffold(
            appBar: AppBar(
              title: Text(l.shamellContactInfoTitle),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: bottom + 12,
                ),
                child: GlassPanel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayNameForPeer(peer),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (isCloseFriend)
                            Chip(
                              label: Text(
                                l.shamellFriendsCloseLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (currentTags.isNotEmpty)
                            Chip(
                              label: Text(
                                currentTags,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (peer.muted)
                            Chip(
                              label: Text(
                                l.shamellMuteChat,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (peer.pinned)
                            Chip(
                              label: Text(
                                l.shamellPinChat,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (peer.blocked)
                            Chip(
                              label: Text(
                                l.shamellBlock,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.shamellContactRemarkLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: ctrl,
                        decoration: InputDecoration(
                          hintText: l.shamellFriendAliasHint,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: tagsCtrl,
                        decoration: InputDecoration(
                          labelText: l.shamellFriendTagsLabel,
                          hintText: l.shamellFriendTagsHint,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${l.shamellContactChatIdPrefix} ${peer.id}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .65),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.isArabic ? 'حالة هذا الاتصال' : 'Contact status',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilterChip(
                            label: Text(
                              isCloseFriend
                                  ? (l.isArabic
                                      ? 'إزالة من الأصدقاء المقرّبين'
                                      : 'Remove from close friends')
                                  : (l.isArabic
                                      ? 'إضافة إلى الأصدقاء المقرّبين'
                                      : 'Add to close friends'),
                            ),
                            selected: isCloseFriend,
                            onSelected: (sel) async {
                              final makeClose = sel;
                              try {
                                final sp =
                                    await SharedPreferences.getInstance();
                                final rawClose =
                                    sp.getString('friends.close') ?? '{}';
                                Map<String, dynamic> decodedClose;
                                try {
                                  decodedClose = jsonDecode(rawClose)
                                      as Map<String, dynamic>;
                                } catch (_) {
                                  decodedClose = <String, dynamic>{};
                                }
                                if (makeClose) {
                                  decodedClose[peer.id] = true;
                                } else {
                                  decodedClose.remove(peer.id);
                                }
                                await sp.setString(
                                  'friends.close',
                                  jsonEncode(decodedClose),
                                );
                                if (!mounted) return;
                                setState(() {
                                  if (makeClose) {
                                    _closeFriendIds.add(peer.id);
                                  } else {
                                    _closeFriendIds.remove(peer.id);
                                  }
                                });
                              } catch (_) {
                                // ignore – best-effort close-friend toggle
                              }
                            },
                          ),
                          FilterChip(
                            label: Text(
                              peer.muted
                                  ? l.shamellUnmuteChat
                                  : l.shamellMuteChat,
                            ),
                            selected: peer.muted,
                            onSelected: (sel) async {
                              final c = peer;
                              final updated = c.copyWith(muted: !c.muted);
                              final contacts = _upsertContact(updated);
                              await _store.saveContacts(contacts);
                              try {
                                if (_me != null) {
                                  await _service.setPrefs(
                                    deviceId: _me!.id,
                                    peerId: c.id,
                                    muted: updated.muted,
                                    starred: updated.starred,
                                    pinned: updated.pinned,
                                  );
                                }
                              } catch (_) {}
                              if (!mounted) return;
                              _applyState(() {
                                _contacts = contacts;
                                if (_peer?.id == updated.id) {
                                  _peer = updated;
                                }
                              });
                            },
                          ),
                          FilterChip(
                            label: Text(
                              peer.pinned
                                  ? l.shamellUnpinChat
                                  : l.shamellPinChat,
                            ),
                            selected: peer.pinned,
                            onSelected: (sel) async {
                              final c = peer;
                              final updated = c.copyWith(pinned: !c.pinned);
                              _updatePinnedChatOrderForPeer(
                                  updated.id, updated.pinned);
                              final contacts = _upsertContact(updated);
                              await _store.saveContacts(contacts);
                              try {
                                if (_me != null) {
                                  await _service.setPrefs(
                                    deviceId: _me!.id,
                                    peerId: c.id,
                                    muted: updated.muted,
                                    starred: updated.starred,
                                    pinned: updated.pinned,
                                  );
                                }
                              } catch (_) {}
                              if (!mounted) return;
                              _applyState(() {
                                _contacts = contacts;
                                if (_peer?.id == updated.id) {
                                  _peer = updated;
                                }
                              });
                            },
                          ),
                          FilterChip(
                            label: Text(
                              peer.hidden
                                  ? l.shamellUnhideChat
                                  : l.shamellHideChat,
                            ),
                            selected: peer.hidden,
                            onSelected: (sel) async {
                              final updated =
                                  peer.copyWith(hidden: !peer.hidden);
                              final contacts = _upsertContact(updated);
                              try {
                                await _service.setHidden(
                                  deviceId: _me?.id ?? '',
                                  peerId: peer.id,
                                  hidden: updated.hidden,
                                );
                              } catch (_) {}
                              await _store.saveContacts(contacts);
                              if (!mounted) return;
                              _applyState(() {
                                _peer = updated;
                                _contacts = contacts;
                                if (updated.hidden && !_showHidden) {
                                  _activePeerId = null;
                                  _peer = null;
                                  _messages = [];
                                }
                              });
                            },
                          ),
                          FilterChip(
                            label: Text(
                              peer.blocked ? l.shamellUnblock : l.shamellBlock,
                            ),
                            selected: peer.blocked,
                            onSelected: (sel) async {
                              final updated = peer.copyWith(
                                blocked: !peer.blocked,
                                blockedAt: DateTime.now(),
                              );
                              final contacts = _upsertContact(updated);
                              try {
                                await _service.setBlock(
                                  deviceId: _me?.id ?? '',
                                  peerId: peer.id,
                                  blocked: updated.blocked,
                                  hidden: updated.hidden,
                                );
                              } catch (_) {}
                              await _store.saveContacts(contacts);
                              if (!mounted) return;
                              _applyState(() {
                                _peer = updated;
                                _contacts = contacts;
                                if (updated.blocked &&
                                    _activePeerId == peer.id) {
                                  _messages = [];
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.bookmark_outline, size: 18),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FavoritesPage(
                                    baseUrl: widget.baseUrl,
                                    chatIdFilter: peer.id,
                                  ),
                                ),
                              );
                            },
                            label: Text(l.shamellFavoritesTitle),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.photo_library_outlined,
                                size: 18),
                            onPressed: _openMediaOverview,
                            label: Text(
                              l.isArabic ? 'الوسائط والروابط' : 'Media & links',
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.search, size: 18),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              if (_messages.isNotEmpty) {
                                _applyState(() {
                                  _messageSearch = '';
                                });
                                FocusScope.of(context)
                                    .requestFocus(_messageSearchFocus);
                              }
                            },
                            label: Text(
                              l.isArabic ? 'بحث في الدردشة' : 'Search in chat',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.shamellChatThemeTitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StatefulBuilder(
                        builder: (ctx2, setThemeState) {
                          final currentTheme =
                              (_chatThemes[peer.id] ?? 'default');
                          void setTheme(String value) {
                            setThemeState(() {});
                            _applyState(() {
                              final updated =
                                  Map<String, String>.from(_chatThemes);
                              if (value == 'default') {
                                updated.remove(peer.id);
                              } else {
                                updated[peer.id] = value;
                              }
                              _chatThemes = updated;
                            });
                            // Fire-and-forget persistence.
                            // ignore: discarded_futures
                            _saveChatThemes();
                          }

                          return Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text(l.shamellChatThemeDefault),
                                selected: currentTheme == 'default',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  setTheme('default');
                                },
                              ),
                              ChoiceChip(
                                label: Text(l.shamellChatThemeDark),
                                selected: currentTheme == 'dark',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  setTheme('dark');
                                },
                              ),
                              ChoiceChip(
                                label: Text(l.shamellChatThemeGreen),
                                selected: currentTheme == 'green',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  setTheme('green');
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(l.shamellDialogCancel),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                    context: ctx,
                                    builder: (ctx2) => AlertDialog(
                                      title: Text(l.shamellClearChatHistory),
                                      content: Text(
                                        l.isArabic
                                            ? 'سيتم مسح كل رسائل هذه الدردشة من هذا الجهاز فقط.'
                                            : 'This will clear all messages in this chat on this device only.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx2).pop(false),
                                          child: Text(l.shamellDialogCancel),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx2).pop(true),
                                          child: Text(l.shamellDialogOk),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (!confirm) return;
                              await _clearChatHistoryForPeer(peer);
                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                            },
                            child: Text(
                              l.shamellClearChatHistory,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final alias = ctrl.text.trim();
                              final tagsText = tagsCtrl.text.trim();
                              try {
                                final sp =
                                    await SharedPreferences.getInstance();
                                final raw =
                                    sp.getString('friends.aliases') ?? '{}';
                                Map<String, dynamic> decoded;
                                try {
                                  decoded =
                                      jsonDecode(raw) as Map<String, dynamic>;
                                } catch (_) {
                                  decoded = <String, dynamic>{};
                                }
                                if (alias.isEmpty) {
                                  decoded.remove(peer.id);
                                } else {
                                  decoded[peer.id] = alias;
                                }
                                await sp.setString(
                                    'friends.aliases', jsonEncode(decoded));
                                final rawTags =
                                    sp.getString('friends.tags') ?? '{}';
                                Map<String, dynamic> decodedTags;
                                try {
                                  decodedTags = jsonDecode(rawTags)
                                      as Map<String, dynamic>;
                                } catch (_) {
                                  decodedTags = <String, dynamic>{};
                                }
                                if (tagsText.isEmpty) {
                                  decodedTags.remove(peer.id);
                                } else {
                                  decodedTags[peer.id] = tagsText;
                                }
                                await sp.setString(
                                    'friends.tags', jsonEncode(decodedTags));
                                if (!mounted) return;
                                setState(() {
                                  final updated =
                                      Map<String, String>.from(_friendAliases);
                                  if (alias.isEmpty) {
                                    updated.remove(peer.id);
                                  } else {
                                    updated[peer.id] = alias;
                                  }
                                  _friendAliases = updated;
                                  final updatedTags =
                                      Map<String, String>.from(_friendTags);
                                  if (tagsText.isEmpty) {
                                    updatedTags.remove(peer.id);
                                  } else {
                                    updatedTags[peer.id] = tagsText;
                                  }
                                  _friendTags = updatedTags;
                                });
                              } catch (_) {}
                              // ignore: use_build_context_synchronously
                              Navigator.of(ctx).pop();
                            },
                            child: Text(l.settingsSave),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Future<void> _openMessageSearch() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final ctrl = TextEditingController();
    String filter = 'all';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: bottom + 12,
          ),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: StatefulBuilder(
              builder: (ctx, setModalState) {
                final query = ctrl.text.trim().toLowerCase();
                final results = <ChatMessage>[];
                final callResults = <ChatCallLogEntry>[];
                if (filter == 'calls') {
                  final peer = _peer;
                  if (peer != null) {
                    final allCalls =
                        _lastCallsCache ?? const <ChatCallLogEntry>[];
                    for (final e in allCalls) {
                      if (e.peerId != peer.id) continue;
                      callResults.add(e);
                    }
                  }
                } else {
                  for (final m in _messages) {
                    if (_recalledMessageIds.contains(m.id)) {
                      continue;
                    }
                    try {
                      final d = _decodeMessage(m);
                      final t = d.text.toLowerCase();
                      if (query.isNotEmpty && !t.contains(query)) {
                        continue;
                      }
                      bool matches = true;
                      switch (filter) {
                        case 'media':
                          matches =
                              d.attachment != null && d.attachment!.isNotEmpty;
                          break;
                        case 'links':
                          matches = t.contains('http://') ||
                              t.contains('https://') ||
                              t.contains('www.');
                          break;
                        case 'voice':
                          matches = d.kind == 'voice' || d.voiceSecs != null;
                          break;
                        case 'all':
                        default:
                          matches = true;
                      }
                      if (matches) {
                        results.add(m);
                      }
                    } catch (_) {}
                  }
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isArabic
                          ? 'بحث في سجل المحادثة'
                          : 'Search chat history',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterAll),
                          selected: filter == 'all',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'all';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterMedia),
                          selected: filter == 'media',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'media';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterLinks),
                          selected: filter == 'links',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'links';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterVoice),
                          selected: filter == 'voice',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'voice';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterCalls),
                          selected: filter == 'calls',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'calls';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: l.isArabic
                            ? 'كلمة أو جملة في المحادثة'
                            : 'Word or phrase in this chat',
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 8),
                    if (query.isEmpty && filter != 'calls')
                      Text(
                        l.isArabic
                            ? 'اكتب للبحث في سجل المحادثة.'
                            : 'Type to search this conversation.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      )
                    else if (filter != 'calls' && results.isEmpty)
                      Text(
                        l.isArabic
                            ? 'لا توجد رسائل مطابقة.'
                            : 'No matching messages found.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      )
                    else if (filter != 'calls')
                      SizedBox(
                        height: 260,
                        child: ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = results[results.length - 1 - i];
                            final d = _decodeMessage(m);
                            final ts = m.createdAt ?? m.deliveredAt;
                            final tsLabel = ts != null
                                ? '${ts.toLocal().year}-${ts.toLocal().month.toString().padLeft(2, '0')}-${ts.toLocal().day.toString().padLeft(2, '0')} '
                                    '${ts.toLocal().hour.toString().padLeft(2, '0')}:${ts.toLocal().minute.toString().padLeft(2, '0')}'
                                : '';
                            return ListTile(
                              dense: true,
                              title: Text(
                                d.text.isEmpty
                                    ? (l.isArabic
                                        ? 'رسالة دون محتوى نصي'
                                        : 'Non‑text message')
                                    : d.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: tsLabel.isEmpty
                                  ? null
                                  : Text(
                                      tsLabel,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .65),
                                      ),
                                    ),
                              onTap: () {
                                _applyState(() {
                                  _highlightedMessageId = m.id;
                                });
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        ),
                      )
                    else if (callResults.isEmpty)
                      Text(
                        l.shamellNoCallsWithContact,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      )
                    else
                      SizedBox(
                        height: 260,
                        child: ListView.separated(
                          itemCount: callResults.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) =>
                              _buildCallHistoryRow(callResults[i]),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMediaOverview() async {
    final peer = _peer;
    if (peer == null) return;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String filter = 'media';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final mediaMessages = <ChatMessage>[];
            final fileMessages = <ChatMessage>[];
            final linkMessages = <ChatMessage>[];
            for (final m in _messages) {
              if (_recalledMessageIds.contains(m.id)) {
                continue;
              }
              try {
                final d = _decodeMessage(m);
                if (d.attachment != null && d.attachment!.isNotEmpty) {
                  final mime = (d.mime ?? '').toLowerCase();
                  final isImageLike =
                      mime.startsWith('image/') || mime.startsWith('video/');
                  final isVoice = (d.kind ?? '') == 'voice';
                  if (isImageLike && !isVoice) {
                    mediaMessages.add(m);
                  } else if (!isVoice) {
                    fileMessages.add(m);
                  }
                }
                final t = d.text.toLowerCase();
                if (t.contains('http://') ||
                    t.contains('https://') ||
                    t.contains('www.')) {
                  linkMessages.add(m);
                }
              } catch (_) {}
            }
            final List<ChatMessage> list;
            if (filter == 'media') {
              list = mediaMessages;
            } else if (filter == 'files') {
              list = fileMessages;
            } else {
              list = linkMessages;
            }
            return Padding(
              padding: const EdgeInsets.all(12),
              child: GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l.shamellMediaOverviewTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterMedia),
                          selected: filter == 'media',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'media';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterFiles),
                          selected: filter == 'files',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'files';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(l.shamellSearchFilterLinks),
                          selected: filter == 'links',
                          onSelected: (sel) {
                            if (!sel) return;
                            setModalState(() {
                              filter = 'links';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (list.isEmpty)
                      Text(
                        l.shamellMediaOverviewEmpty,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = list[list.length - 1 - i];
                            final d = _decodeMessage(m);
                            final ts = m.createdAt ?? m.deliveredAt;
                            String tsLabel = '';
                            if (ts != null) {
                              final dt = ts.toLocal();
                              tsLabel =
                                  '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                                  '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                            }
                            String title;
                            if (filter == 'media') {
                              title = d.text.isNotEmpty
                                  ? d.text
                                  : l.shamellPreviewImage;
                            } else if (filter == 'files') {
                              title = d.text.isNotEmpty
                                  ? d.text
                                  : l.shamellPreviewUnknown;
                            } else {
                              title = d.text.isNotEmpty
                                  ? d.text
                                  : l.shamellPreviewUnknown;
                            }
                            return ListTile(
                              dense: true,
                              title: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: tsLabel.isEmpty
                                  ? null
                                  : Text(
                                      tsLabel,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .65),
                                      ),
                                    ),
                              onTap: () {
                                _applyState(() {
                                  _highlightedMessageId = m.id;
                                });
                                Navigator.of(ctx).pop();
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
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _service = ChatService(widget.baseUrl);
    final preset = widget.presetAttachmentBytes;
    if (preset != null && preset.isNotEmpty) {
      _attachedBytes = preset;
      _attachedMime = widget.presetAttachmentMime;
      _attachedName = widget.presetAttachmentName;
    }
    _msgCtrl.addListener(_onChatComposerChanged);
    _composerFocus.addListener(() {
      if (!_composerFocus.hasFocus) return;
      if (_composerPanel == _ShamellComposerPanel.none) return;
      if (!mounted) return;
      setState(() {
        _composerPanel = _ShamellComposerPanel.none;
      });
    });
    _threadScrollCtrl.addListener(_onThreadScroll);
    _playerStateSub = _audioPlayer.playerStateStream.listen((st) {
      final playing =
          st.playing && st.processingState != ProcessingState.completed;
      if (!mounted) return;
      if (playing == _voicePlaying &&
          st.processingState != ProcessingState.completed) {
        return;
      }
      setState(() {
        _voicePlaying = playing;
        if (st.processingState == ProcessingState.completed) {
          _playingVoiceMessageId = null;
        }
      });
    });
    // Best-effort load of per-chat theme preferences.
    // Ignore failures; chat works fine without them.
    // ignore: discarded_futures
    _loadChatThemes();
    _bootstrap();
  }

  bool _isCurveKey(Uint8List key) => key.length == _curveKeyBytes;

  Uint8List? _decodeCurveKeyB64(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    try {
      final decoded = base64Decode(value);
      if (!_isCurveKey(decoded)) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  bool _isValidRatchetState(RatchetState st) {
    if (!_isCurveKey(st.rootKey) ||
        !_isCurveKey(st.sendChainKey) ||
        !_isCurveKey(st.recvChainKey) ||
        !_isCurveKey(st.dhPriv) ||
        !_isCurveKey(st.dhPub) ||
        !_isCurveKey(st.peerDhPub)) {
      return false;
    }
    if (st.sendCount < 0 || st.recvCount < 0 || st.pn < 0) {
      return false;
    }
    for (final skipped in st.skipped.values) {
      final k = _decodeCurveKeyB64(skipped);
      if (k == null) return false;
    }
    return true;
  }

  Future<void> _bootstrap() async {
    final me = await _store.loadIdentity();
    final peer = await _store.loadPeer();
    final contacts = await _store.loadContacts();
    final unread = await _store.loadUnread();
    final drafts = await _store.loadDrafts();
    final active = await _store.loadActivePeer();
    final notifyPreview = await _store.loadNotifyPreview();
    final calls = await _callStore.load();
    final sessionKeys = await _store.loadSessionKeys();
    final chainStates = await _store.loadChains();
    ShamellCapabilities caps = ShamellCapabilities.conservativeDefaults;
    String shamellUserId = '';
    try {
      final sp = await SharedPreferences.getInstance();
      caps = ShamellCapabilities.fromPrefsForBaseUrl(sp, widget.baseUrl);
      shamellUserId = await getOrCreateShamellUserId(sp: sp);
    } catch (_) {}
    if (shamellUserId.trim().isEmpty) {
      shamellUserId = await getOrCreateShamellUserId();
    }
    final mergedContacts = List<ChatContact>.from(contacts);
    if (peer != null && mergedContacts.where((c) => c.id == peer.id).isEmpty) {
      mergedContacts.add(peer);
    }
    // load ratchets after we know which peers we have locally
    for (final c in mergedContacts) {
      final raw = await _store.loadRatchet(c.id);
      final st = raw.isNotEmpty
          ? RatchetState.fromJson(raw as Map<String, Object?>)
          : null;
      if (st != null && _isValidRatchetState(st)) {
        _ratchets[c.id] = st;
      } else if (raw.isNotEmpty) {
        await _store.deleteRatchet(c.id);
      }
    }
    String? activeId = active ?? peer?.id;
    if (activeId == null && mergedContacts.isNotEmpty) {
      activeId = mergedContacts.first.id;
    }
    ChatContact? activePeer;
    if (activeId != null) {
      for (final c in mergedContacts) {
        if (c.id == activeId) {
          activePeer = c;
          break;
        }
      }
    }
    activePeer ??= mergedContacts.isNotEmpty ? mergedContacts.first : null;
    final cachedMsgs = activePeer != null
        ? await _store.loadMessages(activePeer.id)
        : <ChatMessage>[];
    // Load friend aliases, tags, pinned and recalled messages for Shamell‑style UX.
    Set<String> archivedGroupIds = <String>{};
    try {
      final sp = await SharedPreferences.getInstance();
      final rawAliases = sp.getString('friends.aliases') ?? '{}';
      final decodedAliases = jsonDecode(rawAliases);
      if (decodedAliases is Map) {
        final map = <String, String>{};
        decodedAliases.forEach((k, v) {
          final key = (k ?? '').toString();
          final val = (v ?? '').toString();
          if (key.isNotEmpty && val.isNotEmpty) {
            map[key] = val;
          }
        });
        _friendAliases = map;
      }
      final rawTags = sp.getString('friends.tags') ?? '{}';
      final decodedTags = jsonDecode(rawTags);
      if (decodedTags is Map) {
        final map = <String, String>{};
        decodedTags.forEach((k, v) {
          final key = (k ?? '').toString();
          final val = (v ?? '').toString();
          if (key.isNotEmpty && val.isNotEmpty) {
            map[key] = val;
          }
        });
        _friendTags = map;
      }
      final rawClose = sp.getString('friends.close') ?? '{}';
      final decodedClose = jsonDecode(rawClose);
      if (decodedClose is Map) {
        final set = <String>{};
        decodedClose.forEach((k, v) {
          final key = (k ?? '').toString();
          final boolVal = v is bool
              ? v
              : (v != null && v.toString().toLowerCase() == 'true');
          if (key.isNotEmpty && boolVal) {
            set.add(key);
          }
        });
        _closeFriendIds
          ..clear()
          ..addAll(set);
      }
      final rawPinned = sp.getString('chat.pinned_messages') ?? '{}';
      final decodedPinned = jsonDecode(rawPinned);
      if (decodedPinned is Map) {
        final map = <String, Set<String>>{};
        decodedPinned.forEach((k, v) {
          final peerId = (k ?? '').toString();
          if (peerId.isEmpty) return;
          final set = <String>{};
          if (v is List) {
            for (final item in v) {
              final id = (item ?? '').toString();
              if (id.isNotEmpty) set.add(id);
            }
          }
          if (set.isNotEmpty) {
            map[peerId] = set;
          }
        });
        _pinnedMessageIdsByPeer = map;
      }
      final recalledList =
          sp.getStringList('chat.recalled_messages') ?? const <String>[];
      _recalledMessageIds
        ..clear()
        ..addAll(
          recalledList.where((id) => id.trim().isNotEmpty),
        );
      final pinnedChats =
          sp.getStringList('chat.pinned_chats') ?? const <String>[];
      _pinnedChatOrder = List<String>.from(
        pinnedChats.where((id) => id.trim().isNotEmpty),
      );
      final archivedGroups =
          sp.getStringList('chat.archived_groups') ?? const <String>[];
      archivedGroupIds = archivedGroups
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {}

    Set<String> voicePlayed = <String>{};
    if (activePeer != null) {
      try {
        voicePlayed = await _store.loadVoicePlayed(activePeer.id);
      } catch (_) {
        voicePlayed = <String>{};
      }
    }

    setState(() {
      _caps = caps;
      _shamellUserId = shamellUserId;
      _me = me;
      _peer = null;
      _contacts = mergedContacts;
      _activePeerId = null;
      _messages = const <ChatMessage>[];
      if (activePeer != null) {
        _cache[activePeer.id] = cachedMsgs;
      }
      _unread = unread;
      _draftTextByChatId = drafts;
      _notifyPreview = notifyPreview;
      _disappearing = false;
      _disappearAfter = const Duration(minutes: 30);
      _voicePlayedMessageIds = voicePlayed;
      _showHidden = false;
      _showArchived = false;
      _archivedGroupIds = archivedGroupIds;
      _peerIdCtrl.text = '';
      _displayNameCtrl.text = me?.displayName ?? '';
      sessionKeys.forEach((k, v) {
        final key = _decodeCurveKeyB64(v);
        if (key != null) {
          _sessionKeys[k] = key;
        }
      });
      chainStates.forEach((pid, state) {
        final ck = _decodeCurveKeyB64(state['ck']?.toString());
        if (ck != null) {
          final ctr = int.tryParse(state['ctr']?.toString() ?? '0') ?? 0;
          _chains[pid] = _ChainState(chainKey: ck, counter: ctr);
        }
      });
      _safetyNumber = null;
      _sessionHash = null;
      _lastCallsCache = calls;
    });
    _normalizePinnedChatOrder();
    // If a peer hint was provided (e.g. from Friends), try to resolve it.
    final hintedPeer = widget.initialPeerId;
    if (hintedPeer != null && hintedPeer.trim().isNotEmpty) {
      // Do not await here to keep bootstrap responsive; errors are shown in _error.
      // ignore: unawaited_futures
      _resolvePeer(presetId: hintedPeer.trim());
    }
    if (me != null) {
      await _ensurePushToken();
      await _pullInbox();
      await _syncGroups();
      _listenWs();
      _listenPush();
      // Best-effort sync of server-side chat preferences (muted/starred).
      unawaited(_syncPrefsFromServer());
      unawaited(_syncGroupPrefsFromServer());
    }
    final currentPeer = _peer;
    if (currentPeer != null && caps.officialAccounts) {
      unawaited(_loadOfficialForPeer(currentPeer));
    }
    if (caps.officialAccounts) {
      await _loadOfficialPeers();
      unawaited(_syncOfficialNotificationModesFromServer());
    }
    // Load top mini‑apps for Shamell hub (Shamell-style).
    unawaited(_loadTopMiniApps());
    // Best-effort: badge for service notifications (Shamell-style system thread).
    if (caps.serviceNotifications) {
      unawaited(_loadServiceNotificationsBadge());
    }
    // Best-effort: persist/restore Chats system-thread state (hide/unread overrides).
    unawaited(_loadChatsTabSystemThreadsPrefs());
    // Best-effort: detect other active devices for multi-device UX banner.
    unawaited(_loadDevicesSummary());
  }

  Future<void> _loadTopMiniApps() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final recentIds = sp.getStringList('recent_modules') ?? const <String>[];
      final recentMiniPrograms =
          sp.getStringList('recent_mini_programs') ?? const <String>[];
      final pinnedIds = sp.getStringList('pinned_miniapps') ?? const <String>[];
      final pinnedOrder =
          sp.getStringList('mini_programs.pinned_order') ?? const <String>[];

      final pinnedSet = <String>{};
      for (final raw in pinnedIds) {
        final id = raw.trim();
        if (id.isNotEmpty) pinnedSet.add(id);
      }
      final recentSet = <String>{};
      for (final raw in recentMiniPrograms) {
        final id = raw.trim();
        if (id.isNotEmpty) recentSet.add(id);
      }
      for (final raw in recentIds) {
        final id = raw.trim();
        if (id.isNotEmpty) recentSet.add(id);
      }
      final orderedPinned = <String>[];
      final seenPinned = <String>{};
      void addPinned(String raw) {
        final id = raw.trim();
        if (id.isEmpty) return;
        if (!pinnedSet.contains(id)) return;
        if (seenPinned.add(id)) orderedPinned.add(id);
      }

      for (final id in pinnedOrder) {
        addPinned(id);
      }
      for (final id in pinnedIds) {
        addPinned(id);
      }
      final orderedIds = <String>[];
      final orderedSet = <String>{};
      void addOrdered(String raw) {
        final id = raw.trim();
        if (id.isEmpty) return;
        if (orderedSet.add(id)) orderedIds.add(id);
      }

      for (final id in orderedPinned) {
        addOrdered(id);
      }
      for (final id in recentMiniPrograms) {
        addOrdered(id);
      }
      for (final id in recentIds) {
        addOrdered(id);
      }

      final pullDownIds = <String>[];
      final pullDownSet = <String>{};
      void addPullDown(String raw) {
        final id = raw.trim();
        if (id.isEmpty) return;
        if (pullDownSet.add(id)) pullDownIds.add(id);
      }

      for (final id in orderedPinned) {
        addPullDown(id);
      }
      for (final id in recentMiniPrograms) {
        addPullDown(id);
      }
      for (final id in recentIds) {
        addPullDown(id);
      }
      if (pullDownIds.length > 8) {
        pullDownIds.removeRange(8, pullDownIds.length);
      }
      final allApps = visibleMiniApps();
      final picks = <MiniAppDescriptor>[];
      for (final id in orderedIds) {
        final m = allApps.firstWhere(
          (a) => a.id == id,
          orElse: () => const MiniAppDescriptor(
            id: '',
            icon: Icons.apps_outlined,
            titleEn: '',
            titleAr: '',
            categoryEn: '',
            categoryAr: '',
          ),
        );
        if (m.id.isEmpty) continue;
        picks.add(m);
        if (picks.length >= 3) break;
      }
      if (picks.isEmpty) {
        // Fallback: highlight a few core Shamell mini‑apps.
        final fallbackIds = ['payments', 'bus'];
        for (final id in fallbackIds) {
          final m = allApps.firstWhere(
            (a) => a.id == id,
            orElse: () => const MiniAppDescriptor(
              id: '',
              icon: Icons.apps_outlined,
              titleEn: '',
              titleAr: '',
              categoryEn: '',
              categoryAr: '',
            ),
          );
          if (m.id.isEmpty) continue;
          picks.add(m);
          if (picks.length >= 3) break;
        }
      }
      if (!mounted) return;
      setState(() {
        if (picks.isNotEmpty) {
          _topMiniApps = picks;
        }
        _pullDownMiniProgramIds = pullDownIds;
        _pinnedMiniProgramIds = pinnedSet;
        _recentMiniProgramIds = recentSet;
      });
      unawaited(_loadPullDownMiniProgramReleaseBadges(pullDownIds));
    } catch (_) {}
  }

  List<String> _cleanIdList(Iterable<String> items) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in items) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  Future<void> _togglePullDownMiniProgramPinned(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final curPinned =
          _cleanIdList(sp.getStringList('pinned_miniapps') ?? const <String>[]);
      final pinnedSet = curPinned.toSet();
      final isPinned = pinnedSet.contains(id);
      if (isPinned) {
        curPinned.removeWhere((e) => e == id);
      } else {
        curPinned.insert(0, id);
      }
      if (curPinned.isEmpty) {
        await sp.remove('pinned_miniapps');
      } else {
        await sp.setStringList('pinned_miniapps', curPinned);
      }

      final curOrder = _cleanIdList(
          sp.getStringList('mini_programs.pinned_order') ?? const <String>[]);
      curOrder.removeWhere((e) => e == id);
      if (!isPinned) {
        curOrder.insert(0, id);
      }
      final nextOrder = curOrder.where(curPinned.contains).toList();
      if (nextOrder.isEmpty) {
        await sp.remove('mini_programs.pinned_order');
      } else {
        await sp.setStringList('mini_programs.pinned_order', nextOrder);
      }
    } catch (_) {}
    if (mounted) {
      unawaited(_loadTopMiniApps());
    }
  }

  Future<void> _removePullDownMiniProgramFromRecents(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final curMini = _cleanIdList(
        sp.getStringList('recent_mini_programs') ?? const <String>[],
      )..removeWhere((e) => e == id);
      if (curMini.isEmpty) {
        await sp.remove('recent_mini_programs');
      } else {
        await sp.setStringList('recent_mini_programs', curMini);
      }

      final curMods = _cleanIdList(
        sp.getStringList('recent_modules') ?? const <String>[],
      )..removeWhere((e) => e == id);
      if (curMods.isEmpty) {
        await sp.remove('recent_modules');
      } else {
        await sp.setStringList('recent_modules', curMods);
      }
    } catch (_) {}
    if (mounted) {
      unawaited(_loadTopMiniApps());
    }
  }

  Future<void> _openPullDownMiniProgramActions(
    String appId, {
    Offset? globalPosition,
  }) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final l = L10n.of(context);
    final isPinned = _pinnedMiniProgramIds.contains(id);
    final isRecent = _recentMiniProgramIds.contains(id);
    final pinLabel = isPinned
        ? (l.isArabic ? 'إلغاء تثبيت' : 'Unpin')
        : (l.isArabic ? 'تثبيت' : 'Pin');
    final removeLabel = l.isArabic ? 'إزالة من الأخيرة' : 'Remove from recents';
    final editLabel = l.isArabic ? 'تعديل' : 'Edit';
    final moreLabel = l.isArabic ? 'المزيد' : 'More';
    final cancelLabel = l.isArabic ? 'إلغاء' : 'Cancel';

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    final globalPos = globalPosition;
    if (globalPos != null) {
      await _showShamellActionsPopover(
        globalPosition: globalPos,
        actions: [
          _ShamellPopoverActionSpec(
            label: pinLabel,
            onTap: () => unawaited(_togglePullDownMiniProgramPinned(id)),
          ),
          if (isRecent)
            _ShamellPopoverActionSpec(
              label: removeLabel,
              color: const Color(0xFFFA5151),
              onTap: () => unawaited(_removePullDownMiniProgramFromRecents(id)),
            ),
          _ShamellPopoverActionSpec(
            label: editLabel,
            onTap: () => unawaited(
              _openMiniProgramsHubFromChats(openPinnedManage: true),
            ),
          ),
          _ShamellPopoverActionSpec(
            label: moreLabel,
            onTap: () => unawaited(_openMiniProgramsHubFromChats()),
          ),
        ],
      );
      return;
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
                    label: pinLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_togglePullDownMiniProgramPinned(id));
                    },
                  ),
                  if (isRecent) ...[
                    const Divider(height: 1),
                    actionRow(
                      label: removeLabel,
                      color: const Color(0xFFFA5151),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        unawaited(_removePullDownMiniProgramFromRecents(id));
                      },
                    ),
                  ],
                  const Divider(height: 1),
                  actionRow(
                    label: editLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(
                        _openMiniProgramsHubFromChats(openPinnedManage: true),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: moreLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_openMiniProgramsHubFromChats());
                    },
                  ),
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

  Map<String, String> _decodeStringMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, String>{};
        decoded.forEach((k, v) {
          final key = (k ?? '').toString().trim();
          final val = (v ?? '').toString().trim();
          if (key.isNotEmpty && val.isNotEmpty) out[key] = val;
        });
        return out;
      }
    } catch (_) {}
    return const <String, String>{};
  }

  Future<void> _loadPullDownMiniProgramReleaseBadges(
      List<String> pullDownIds) async {
    try {
      final ids = pullDownIds.map((e) => e.trim()).where((e) => e.isNotEmpty);
      final interested = ids.toSet();
      if (interested.isEmpty) {
        if (!mounted) return;
        setState(() {
          _miniProgramsLatestReleaseById = <String, String>{};
          _miniProgramsSeenReleaseById = <String, String>{};
          _pullDownMiniProgramUpdateBadges = <String>{};
        });
        return;
      }

      final sp = await SharedPreferences.getInstance();
      final latest = _decodeStringMap(
        sp.getString('mini_programs.latest_released_versions.v1') ?? '{}',
      );
      final seen = _decodeStringMap(
        sp.getString('mini_programs.seen_release_versions.v1') ?? '{}',
      );

      final nextSeen = Map<String, String>.from(seen);
      var seenChanged = false;
      final updateBadges = <String>{};

      for (final id in interested) {
        final rel = (latest[id] ?? '').trim();
        if (rel.isEmpty) continue;
        final prev = (nextSeen[id] ?? '').trim();
        if (prev.isEmpty) {
          // Treat the current release as "seen" so we only badge
          // when a newer release appears later.
          nextSeen[id] = rel;
          seenChanged = true;
          continue;
        }
        if (prev != rel) {
          updateBadges.add(id);
        }
      }

      if (seenChanged) {
        try {
          await sp.setString(
            'mini_programs.seen_release_versions.v1',
            jsonEncode(nextSeen),
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _miniProgramsLatestReleaseById = latest;
        _miniProgramsSeenReleaseById = nextSeen;
        _pullDownMiniProgramUpdateBadges = updateBadges;
      });
    } catch (_) {}
  }

  Future<void> _markPullDownMiniProgramReleaseSeen(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final rel = (_miniProgramsLatestReleaseById[id] ?? '').trim();
    if (rel.isEmpty) return;

    final nextSeen = Map<String, String>.from(_miniProgramsSeenReleaseById);
    if ((nextSeen[id] ?? '').trim() == rel &&
        !_pullDownMiniProgramUpdateBadges.contains(id)) {
      return;
    }
    nextSeen[id] = rel;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        'mini_programs.seen_release_versions.v1',
        jsonEncode(nextSeen),
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _miniProgramsSeenReleaseById = nextSeen;
      _pullDownMiniProgramUpdateBadges = <String>{
        ..._pullDownMiniProgramUpdateBadges
      }..remove(id);
    });
  }

  Future<void> _loadDevicesSummary() async {
    try {
      final currentDeviceId = await CallSignalingClient.loadDeviceId();
      if (currentDeviceId == null || currentDeviceId.isEmpty) {
        return;
      }
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      final headers = <String, String>{};
      if (cookie.isNotEmpty) {
        headers['cookie'] = cookie;
      }
      final uri = Uri.parse('${widget.baseUrl}/auth/devices');
      final resp = await http
          .get(uri, headers: headers)
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(resp.body);
      List<Map<String, dynamic>> devices = const <Map<String, dynamic>>[];
      if (decoded is Map && decoded['devices'] is List) {
        final list = decoded['devices'] as List;
        final parsed = <Map<String, dynamic>>[];
        for (final e in list) {
          if (e is Map) {
            parsed.add(e.cast<String, dynamic>());
          }
        }
        devices = parsed;
      }
      bool hasOther = false;
      String? label;
      for (final d in devices) {
        final id = (d['device_id'] ?? '').toString();
        if (id.isEmpty || id == currentDeviceId) continue;
        hasOther = true;
        final type = (d['device_type'] ?? '').toString();
        final platform = (d['platform'] ?? '').toString();
        if (type.isNotEmpty) {
          label = type;
        } else if (platform.isNotEmpty) {
          label = platform;
        }
        if (label != null && label.isNotEmpty) {
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _hasOtherDevices = hasOther;
        _otherDeviceLabel = label;
      });
    } catch (_) {}
  }

  Future<void> _loadServiceNotificationsBadge() async {
    if (!_caps.serviceNotifications) return;
    bool cached = false;
    try {
      final sp = await SharedPreferences.getInstance();
      cached = sp.getBool('official_template_messages.has_unread') ?? false;
    } catch (_) {}
    if (mounted && cached != _hasUnreadServiceNotifications) {
      setState(() {
        _hasUnreadServiceNotifications = cached;
      });
    }

    try {
      final uri = Uri.parse('${widget.baseUrl}/me/official_template_messages')
          .replace(queryParameters: const {
        'unread_only': 'true',
        'limit': '1',
      });
      final r = await http
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['messages'] is List) {
        raw = decoded['messages'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final hasUnread = raw.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _hasUnreadServiceNotifications = hasUnread;
      });
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setBool('official_template_messages.has_unread', hasUnread);
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _loadChatsTabSystemThreadsPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final hideService =
          sp.getBool('chat.hide_service_notifications_thread') ?? false;
      final hideSubs = sp.getBool('chat.hide_subscriptions_thread') ?? false;
      final forceSubsUnread =
          sp.getBool('official.subscriptions_force_unread') ?? false;
      if (!mounted) return;
      setState(() {
        _hideServiceNotificationsThread = hideService;
        _hideSubscriptionsThread = hideSubs;
        if (forceSubsUnread) {
          _hasUnreadSubscriptionFeeds = true;
          _subscriptionUnreadCount =
              _subscriptionUnreadCount > 0 ? _subscriptionUnreadCount : 1;
        }
      });
    } catch (_) {}
  }

  Future<void> _setHideServiceNotificationsThread(bool hide) async {
    _applyState(() {
      _hideServiceNotificationsThread = hide;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('chat.hide_service_notifications_thread', hide);
    } catch (_) {}
  }

  Future<void> _setHideSubscriptionsThread(bool hide) async {
    _applyState(() {
      _hideSubscriptionsThread = hide;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('chat.hide_subscriptions_thread', hide);
    } catch (_) {}
  }

  Future<void> _setForceSubscriptionsUnread(bool force) async {
    _applyState(() {
      if (force) {
        _hasUnreadSubscriptionFeeds = true;
        _subscriptionUnreadCount =
            _subscriptionUnreadCount > 0 ? _subscriptionUnreadCount : 1;
      }
    });
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('official.subscriptions_force_unread', force);
    } catch (_) {}
  }

  Future<void> _markAllSubscriptionFeedsSeen() async {
    try {
      final headers = await _officialHeaders();
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'true'});
      final r = await http
          .get(uri, headers: headers)
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['accounts'] is List) {
        raw = decoded['accounts'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final sp = await SharedPreferences.getInstance();
      final rawSeen = sp.getString('official.feed_seen') ?? '{}';
      Map<String, dynamic> seenMap;
      try {
        seenMap = jsonDecode(rawSeen) as Map<String, dynamic>;
      } catch (_) {
        seenMap = <String, dynamic>{};
      }
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final kindStr = (m['kind'] ?? 'service').toString().toLowerCase();
        final isSubscription = kindStr != 'service';
        if (!isSubscription) continue;
        final accId = (m['id'] ?? '').toString();
        if (accId.isEmpty) continue;
        if (m['last_item'] is! Map) continue;
        final lm = m['last_item'] as Map;
        final tsRaw = (lm['ts'] ?? '').toString();
        if (tsRaw.isEmpty) continue;
        seenMap[accId] = tsRaw;
      }
      await sp.setString('official.feed_seen', jsonEncode(seenMap));
    } catch (_) {}
    unawaited(_loadOfficialPeers());
  }

  Future<void> _toggleServiceNotificationsReadUnread() async {
    final next = !_hasUnreadServiceNotifications;
    _applyState(() {
      _hasUnreadServiceNotifications = next;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('official_template_messages.has_unread', next);
    } catch (_) {}
  }

  Future<void> _deleteServiceNotificationsThread() async {
    await _setHideServiceNotificationsThread(true);
    _applyState(() {
      _hasUnreadServiceNotifications = false;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('official_template_messages.has_unread', false);
    } catch (_) {}
  }

  Future<void> _toggleSubscriptionsReadUnread() async {
    if (_hasUnreadSubscriptionFeeds) {
      await _setForceSubscriptionsUnread(false);
      _applyState(() {
        _hasUnreadSubscriptionFeeds = false;
        _subscriptionUnreadCount = 0;
      });
      await _markAllSubscriptionFeedsSeen();
      return;
    }
    await _setForceSubscriptionsUnread(true);
  }

  Future<void> _deleteSubscriptionsThread() async {
    await _setHideSubscriptionsThread(true);
    await _setForceSubscriptionsUnread(false);
    _applyState(() {
      _hasUnreadSubscriptionFeeds = false;
      _subscriptionUnreadCount = 0;
    });
    await _markAllSubscriptionFeedsSeen();
  }

  Future<Map<String, String>> _officialHeaders({bool jsonBody = false}) async {
    final h = <String, String>{};
    if (jsonBody) h['content-type'] = 'application/json';
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) {
        h['cookie'] = cookie;
      }
    } catch (_) {}
    return h;
  }

  Future<bool> _ensureOfficialAuthSession() async {
    if (!_caps.officialAccounts) {
      if (!mounted) return false;
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'هذا القسم غير متاح حالياً.'
                : 'This section is not available right now.',
          ),
        ),
      );
      return false;
    }
    // On web, we rely on HttpOnly cookies managed by the browser, so the app
    // cannot reliably check session state client-side.
    if (kIsWeb) return true;
    try {
      final tok =
          (await getSessionTokenForBaseUrl(widget.baseUrl) ?? '').trim();
      if (tok.isNotEmpty) return true;
    } catch (_) {}
    if (!mounted) return false;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l.isArabic
              ? 'يتطلب هذا القسم تسجيل الدخول أولاً.'
              : 'This section requires sign in first.',
        ),
      ),
    );
    return false;
  }

  Future<void> _openOfficialFeedForPeer() async {
    if (!await _ensureOfficialAuthSession()) return;
    final peer = _peer;
    if (peer == null) return;
    final l = L10n.of(context);
    try {
      OfficialAccountHandle? official = _linkedOfficial;
      if (official == null && peer.id.isNotEmpty) {
        official = await _loadOfficialForPeer(peer, updateState: true);
      }
      if (!mounted) return;
      if (official == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'لا يوجد حساب رسمي مرتبط بهذا المستخدم.'
                  : 'No official account linked to this contact.',
            ),
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfficialAccountFeedPage(
            baseUrl: widget.baseUrl,
            account: official!,
            onOpenChat: (peerId) {
              if (peerId.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShamellChatPage(
                    baseUrl: widget.baseUrl,
                    initialPeerId: peerId,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'حدث خطأ أثناء فتح الحساب الرسمي.'
                : 'Error while opening official account.',
          ),
        ),
      );
    }
  }

  Future<void> _openOfficialMomentsForPeer() async {
    if (!await _ensureOfficialAuthSession()) return;
    final peer = _peer;
    if (peer == null) return;
    final l = L10n.of(context);
    try {
      OfficialAccountHandle? official = _linkedOfficial;
      if (official == null && peer.id.isNotEmpty) {
        official = await _loadOfficialForPeer(peer, updateState: true);
      }
      if (!mounted) return;
      if (official == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'لا يوجد حساب رسمي مرتبط بهذا المستخدم.'
                  : 'No official account linked to this contact.',
            ),
          ),
        );
        return;
      }
      final acc = official;
      if (acc == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MomentsPage(
            baseUrl: widget.baseUrl,
            originOfficialAccountId: acc.id,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'حدث خطأ أثناء فتح منشورات اللحظات.'
                : 'Error while opening Moments posts.',
          ),
        ),
      );
    }
  }

  Future<void> _openSubscriptionsThread() async {
    if (!_caps.subscriptions) {
      if (!mounted) return;
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'الاشتراكات غير متاحة حالياً.'
                : 'Subscriptions are not available right now.',
          ),
        ),
      );
      return;
    }
    if (!await _ensureOfficialAuthSession()) return;
    final l = L10n.of(context);
    ChatContact? existing;
    for (final c in _contacts) {
      if (c.id == _ShamellChatPageState._subscriptionsPeerId) {
        existing = c;
        break;
      }
    }
    ChatContact contact;
    if (existing == null) {
      contact = ChatContact(
        id: _ShamellChatPageState._subscriptionsPeerId,
        publicKeyB64: 'subscriptions',
        fingerprint: 'subscriptions',
        name: l.isArabic ? 'الاشتراكات' : 'Subscriptions',
      );
      final contacts = _upsertContact(contact);
      await _store.saveContacts(contacts);
      _applyState(() {
        _contacts = contacts;
      });
    } else {
      contact = existing;
    }
    Perf.action('official_open_subscriptions_thread');
    await _switchPeer(contact);
  }

  Future<void> _toggleOfficialFollowFromChat() async {
    if (!await _ensureOfficialAuthSession()) return;
    final official = _linkedOfficial;
    if (official == null) return;
    final id = official.id;
    if (id.isEmpty) return;
    final currentlyFollowed = _linkedOfficialFollowed;
    final endpoint = currentlyFollowed ? 'unfollow' : 'follow';
    final kindStr = (official.kind).toLowerCase();
    final suffix = kindStr == 'service' ? 'service' : 'subscription';
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/official_accounts/$id/$endpoint');
      final r = await http
          .post(uri, headers: await _officialHeaders(jsonBody: true))
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300 && mounted) {
        final nowFollowed = !currentlyFollowed;
        setState(() {
          _linkedOfficialFollowed = nowFollowed;
        });
        Perf.action(currentlyFollowed
            ? 'official_unfollow_from_chat'
            : 'official_follow_from_chat');
        Perf.action(currentlyFollowed
            ? 'official_unfollow_kind_$suffix'
            : 'official_follow_kind_$suffix');
        if (nowFollowed) {
          // After first follow, try to surface the configured
          // welcome auto‑reply for this Official, similar to
          // Shamell Official accounts.
          unawaited(_maybeInjectOfficialWelcome(official));
        }
      }
    } catch (_) {}
  }

  Future<OfficialAccountHandle?> _loadOfficialForPeer(ChatContact peer,
      {bool updateState = true}) async {
    final id = peer.id.trim();
    if (id.isEmpty) return null;
    if (_linkedOfficialPeerId == id && _linkedOfficial != null) {
      return _linkedOfficial;
    }
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: {'followed_only': 'false'});
      final r = await http
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['accounts'] is List) {
        raw = decoded['accounts'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      OfficialAccountHandle? found;
      for (final e in raw) {
        if (e is Map) {
          final m = e.cast<String, dynamic>();
          final rawChat = (m['chat_peer_id'] ?? '').toString().trim();
          if (rawChat == id) {
            found = OfficialAccountHandle.fromJson(m);
            break;
          }
        }
      }
      if (updateState && mounted) {
        setState(() {
          _linkedOfficialPeerId = id;
          _linkedOfficial = found;
          _linkedOfficialFollowed = found?.followed ?? false;
        });
      } else if (!updateState) {
        _linkedOfficialPeerId = id;
        _linkedOfficial = found;
        _linkedOfficialFollowed = found?.followed ?? false;
      }
      if (found != null) {
        // Try to surface a Shamell‑style welcome message in the
        // current thread when chatting with an Official account.
        unawaited(_maybeInjectOfficialWelcome(found));
      }
      return found;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadOfficialAutoReplies(
      String accountId) async {
    if (accountId.isEmpty) return const <Map<String, dynamic>>[];
    final cached = _officialAutoRepliesByAccount[accountId];
    if (cached != null) return cached;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/official_accounts/${Uri.encodeComponent(accountId)}/auto_replies',
      );
      final r = await http
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        _officialAutoRepliesByAccount[accountId] =
            const <Map<String, dynamic>>[];
        return const <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map || decoded['rules'] is! List) {
        _officialAutoRepliesByAccount[accountId] =
            const <Map<String, dynamic>>[];
        return const <Map<String, dynamic>>[];
      }
      final list = <Map<String, dynamic>>[];
      for (final e in decoded['rules'] as List) {
        if (e is Map) {
          list.add(e.cast<String, dynamic>());
        }
      }
      _officialAutoRepliesByAccount[accountId] = list;
      return list;
    } catch (_) {
      _officialAutoRepliesByAccount[accountId] = const <Map<String, dynamic>>[];
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _maybeInjectOfficialWelcome(
      OfficialAccountHandle account) async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null) return;
    final peerId = peer.id.trim();
    if (peerId.isEmpty) return;
    if (_autoWelcomeLoadedForPeers.contains(peerId)) return;
    _autoWelcomeLoadedForPeers.add(peerId);
    try {
      final sp = await SharedPreferences.getInstance();
      final seenKey = 'official.autoreply.shown.$peerId';
      final alreadyShown = sp.getBool(seenKey) ?? false;
      if (alreadyShown) return;
      final rules = await _loadOfficialAutoReplies(account.id);
      if (rules.isEmpty) return;
      String? welcomeText;
      for (final m in rules) {
        final kind = (m['kind'] ?? 'welcome').toString().toLowerCase();
        final enabled = (m['enabled'] as bool?) ?? true;
        final txt = (m['text'] ?? '').toString().trim();
        if (kind == 'welcome' && enabled && txt.isNotEmpty) {
          welcomeText = txt;
          break;
        }
      }
      if (welcomeText == null || welcomeText.isEmpty) {
        return;
      }
      final now = DateTime.now();
      final msgId = 'local_auto_${peerId}_${now.millisecondsSinceEpoch}';
      if (_seenMessageIds.contains(msgId)) {
        return;
      }
      final synthetic = ChatMessage(
        id: msgId,
        senderId: peer.id,
        recipientId: me.id,
        senderPubKeyB64: 'invalid_base64',
        nonceB64: '',
        boxB64: base64Encode(utf8.encode(welcomeText)),
        createdAt: now,
        deliveredAt: now,
        readAt: null,
        expireAt: null,
        sealedSender: false,
        senderHint: null,
        keyId: null,
        prevKeyId: null,
        senderDhPubB64: null,
        trustedLocalPlaintext: true,
      );
      if (!mounted) return;
      setState(() {
        final list = List<ChatMessage>.from(_cache[peerId] ?? const []);
        list.add(synthetic);
        _cache[peerId] = list;
        if (_activePeerId == peerId) {
          _messages = list;
        }
        _seenMessageIds.add(msgId);
      });
      await _store.saveMessages(peerId, _cache[peerId] ?? const []);
      await sp.setBool(seenKey, true);
    } catch (_) {
      // Best‑effort: auto‑reply is optional sugar.
    }
  }

  Future<void> _maybeInjectOfficialKeywordReply(
      OfficialAccountHandle account, String userText) async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null) return;
    final text = userText.trim();
    if (text.isEmpty) return;
    try {
      final rules = await _loadOfficialAutoReplies(account.id);
      if (rules.isEmpty) return;
      String? replyText;
      for (final m in rules) {
        final kind = (m['kind'] ?? 'keyword').toString().toLowerCase();
        if (kind != 'keyword') continue;
        final enabled = (m['enabled'] as bool?) ?? true;
        if (!enabled) continue;
        final kw = (m['keyword'] ?? '').toString().trim();
        if (kw.isEmpty) continue;
        if (text.toLowerCase().contains(kw.toLowerCase())) {
          final txt = (m['text'] ?? '').toString().trim();
          if (txt.isEmpty) continue;
          replyText = txt;
          break;
        }
      }
      if (replyText == null || replyText.isEmpty) return;
      final peerId = peer.id.trim();
      if (peerId.isEmpty) return;
      final now = DateTime.now();
      final msgId = 'local_auto_kw_${peerId}_${now.millisecondsSinceEpoch}';
      if (_seenMessageIds.contains(msgId)) {
        return;
      }
      final synthetic = ChatMessage(
        id: msgId,
        senderId: peer.id,
        recipientId: me.id,
        senderPubKeyB64: 'invalid_base64',
        nonceB64: '',
        boxB64: base64Encode(utf8.encode(replyText)),
        createdAt: now,
        deliveredAt: now,
        readAt: null,
        expireAt: null,
        sealedSender: false,
        senderHint: null,
        keyId: null,
        prevKeyId: null,
        senderDhPubB64: null,
        trustedLocalPlaintext: true,
      );
      if (!mounted) return;
      setState(() {
        final list = List<ChatMessage>.from(_cache[peerId] ?? const []);
        list.add(synthetic);
        _cache[peerId] = list;
        if (_activePeerId == peerId) {
          _messages = list;
        }
        _seenMessageIds.add(msgId);
      });
      await _store.saveMessages(peerId, _cache[peerId] ?? const []);
    } catch (_) {
      // Optional sugar; ignore failures.
    }
  }

  Future<void> _loadOfficialPeers() async {
    if (!_caps.officialAccounts) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'false'});
      final r = await http
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['accounts'] is List) {
        raw = decoded['accounts'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final ids = <String>{};
      final unread = <String>{};
      final featured = <String>{};
      final subscriptionPeers = <String>{};
      bool hasSubscriptionUnread = false;
      var subscriptionUnreadCount = 0;
      final peerToAccount = <String, String>{};
      Map<String, dynamic> seenMap = const {};
      bool forceSubsUnread = false;
      try {
        final sp = await SharedPreferences.getInstance();
        forceSubsUnread =
            sp.getBool('official.subscriptions_force_unread') ?? false;
        final rawSeen = sp.getString('official.feed_seen') ?? '{}';
        final dec = jsonDecode(rawSeen);
        if (dec is Map<String, dynamic>) {
          seenMap = dec;
        }
      } catch (_) {}
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final peerId = (m['chat_peer_id'] ?? '').toString().trim();
        if (peerId.isNotEmpty) {
          ids.add(peerId);
        }
        final accId = (m['id'] ?? '').toString();
        final isFeatured = (m['featured'] as bool?) ?? false;
        final isFollowed = (m['followed'] as bool?) ?? false;
        final kindStr = (m['kind'] ?? 'service').toString().toLowerCase();
        String? lastTs;
        if (m['last_item'] is Map) {
          final lm = m['last_item'] as Map;
          final rawTs = (lm['ts'] ?? '').toString();
          lastTs = rawTs.isEmpty ? null : rawTs;
        }
        if (isFeatured && peerId.isNotEmpty) {
          featured.add(peerId);
        }
        if (peerId.isNotEmpty && accId.isNotEmpty) {
          peerToAccount[peerId] = accId;
        }
        final isSubscription = kindStr != 'service';
        if (isSubscription && peerId.isNotEmpty) {
          subscriptionPeers.add(peerId);
        }
        if (isFollowed &&
            accId.isNotEmpty &&
            lastTs != null &&
            lastTs.isNotEmpty) {
          final seenRaw = (seenMap[accId] ?? '').toString();
          if (seenRaw.isEmpty) {
            if (peerId.isNotEmpty) {
              unread.add(peerId);
            }
            if (isSubscription) {
              hasSubscriptionUnread = true;
              subscriptionUnreadCount++;
            }
          } else {
            try {
              final last = DateTime.parse(lastTs);
              final seen = DateTime.parse(seenRaw);
              if (last.isAfter(seen)) {
                if (peerId.isNotEmpty) {
                  unread.add(peerId);
                }
                if (isSubscription) {
                  hasSubscriptionUnread = true;
                  subscriptionUnreadCount++;
                }
              }
            } catch (_) {}
          }
        }
      }
      if (forceSubsUnread) {
        hasSubscriptionUnread = true;
        if (subscriptionUnreadCount <= 0) {
          subscriptionUnreadCount = 1;
        }
      }
      if (!mounted || ids.isEmpty) return;
      setState(() {
        _officialPeerIds
          ..clear()
          ..addAll(ids);
        _officialPeerUnreadFeeds
          ..clear()
          ..addAll(unread);
        _hasUnreadSubscriptionFeeds = hasSubscriptionUnread;
        _featuredOfficialPeerIds
          ..clear()
          ..addAll(featured);
        _subscriptionOfficialPeerIds
          ..clear()
          ..addAll(subscriptionPeers);
        _officialPeerToAccountId
          ..clear()
          ..addAll(peerToAccount);
        _subscriptionUnreadCount = subscriptionUnreadCount;
      });
    } catch (_) {}
  }

  Future<void> _syncOfficialNotificationModesFromServer() async {
    try {
      if (_officialPeerToAccountId.isEmpty) {
        return;
      }
      final uri =
          Uri.parse('${widget.baseUrl}/official_accounts/notifications');
      final r = await http
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map || decoded['modes'] is! Map) {
        return;
      }
      final rawModes = decoded['modes'] as Map;
      if (rawModes.isEmpty) return;
      final store = _store;
      final contacts = await store.loadContacts();
      final updatedContacts = List<ChatContact>.from(contacts);
      var changedContacts = false;
      for (final entry in rawModes.entries) {
        final accId = entry.key.toString();
        final modeStr = entry.value?.toString().toLowerCase() ?? '';
        OfficialNotificationMode? mode;
        switch (modeStr) {
          case 'summary':
            mode = OfficialNotificationMode.summary;
            break;
          case 'muted':
            mode = OfficialNotificationMode.muted;
            break;
          case 'full':
          default:
            mode = OfficialNotificationMode.full;
            break;
        }
        if (accId.isEmpty || mode == null) continue;
        for (final peerEntry in _officialPeerToAccountId.entries) {
          if (peerEntry.value != accId) continue;
          final peerId = peerEntry.key;
          await store.setOfficialNotifMode(peerId, mode);
          for (var i = 0; i < updatedContacts.length; i++) {
            final c = updatedContacts[i];
            if (c.id == peerId) {
              final shouldMute = mode == OfficialNotificationMode.muted;
              if (c.muted != shouldMute) {
                updatedContacts[i] = c.copyWith(muted: shouldMute);
                changedContacts = true;
              }
            }
          }
        }
      }
      if (changedContacts) {
        await store.saveContacts(updatedContacts);
        if (!mounted) return;
        _applyState(() {
          _contacts = updatedContacts;
          if (_peer != null) {
            final cur = updatedContacts
                .where((c) => c.id == _peer!.id)
                .cast<ChatContact?>()
                .firstWhere((c) => c != null, orElse: () => _peer);
            if (cur != null) {
              _peer = cur;
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSubscriptionsFeed() async {
    if (!_caps.subscriptions) return;
    final l = L10n.of(context);
    setState(() {
      _subscriptionsLoading = true;
      _subscriptionsError = null;
      _subscriptionsItems = const <_SubscriptionEntry>[];
    });
    try {
      final headers = await _officialHeaders();
      final sp = await SharedPreferences.getInstance();
      final rawSeen = sp.getString('official.feed_seen') ?? '{}';
      Map<String, dynamic> existingSeenMap;
      try {
        existingSeenMap = jsonDecode(rawSeen) as Map<String, dynamic>;
      } catch (_) {
        existingSeenMap = <String, dynamic>{};
      }
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'true'});
      final r = await http
          .get(uri, headers: headers)
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _subscriptionsError = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['accounts'] is List) {
        raw = decoded['accounts'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <_SubscriptionEntry>[];
      final subsForSeen = <Map<String, dynamic>>[];
      final latestByAccount = <String, String>{};
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final kindStr = (m['kind'] ?? 'service').toString().toLowerCase();
        final isSubscription = kindStr != 'service';
        if (!isSubscription) continue;
        final accId = (m['id'] ?? '').toString();
        final accName = (m['name'] ?? '').toString();
        if (accId.isEmpty || accName.isEmpty) continue;
        final accAvatar = (m['avatar_url'] ?? '').toString().trim().isEmpty
            ? null
            : (m['avatar_url'] ?? '').toString().trim();
        final chatPeerId = (m['chat_peer_id'] ?? '').toString().trim().isEmpty
            ? null
            : (m['chat_peer_id'] ?? '').toString().trim();
        subsForSeen.add(m);
        // Fetch recent feed items for this subscription account.
        try {
          final feedUri =
              Uri.parse('${widget.baseUrl}/official_accounts/$accId/feed')
                  .replace(queryParameters: const {'limit': '20'});
          final fr = await http
              .get(feedUri, headers: headers)
              .timeout(_ShamellChatPageState._chatRequestTimeout);
          if (fr.statusCode >= 200 && fr.statusCode < 300) {
            final fd = jsonDecode(fr.body);
            List<dynamic> rawItems = const [];
            if (fd is Map && fd['items'] is List) {
              rawItems = fd['items'] as List;
            } else if (fd is List) {
              rawItems = fd;
            }
            for (final it in rawItems) {
              if (it is! Map) continue;
              final jm = it.cast<String, dynamic>();
              final itemId = (jm['id'] ?? '').toString();
              if (itemId.isEmpty) continue;
              String title = (jm['title'] ?? '').toString();
              final snippet = (jm['snippet'] ?? '').toString().isEmpty
                  ? null
                  : (jm['snippet'] ?? '').toString();
              final thumb = (jm['thumb_url'] ?? '').toString().isEmpty
                  ? null
                  : (jm['thumb_url'] ?? '').toString();
              final tsRaw = (jm['ts'] ?? '').toString();
              DateTime? ts;
              if (tsRaw.isNotEmpty) {
                try {
                  ts = DateTime.parse(tsRaw);
                } catch (_) {}
              }
              if (title.isEmpty) {
                title = accName;
              }
              bool isUnread = false;
              if (ts != null) {
                final prevRaw = (existingSeenMap[accId] ?? '').toString();
                if (prevRaw.isEmpty) {
                  isUnread = true;
                } else {
                  try {
                    final prevDt = DateTime.parse(prevRaw);
                    if (ts.isAfter(prevDt)) {
                      isUnread = true;
                    }
                  } catch (_) {
                    isUnread = true;
                  }
                }
              }
              items.add(
                _SubscriptionEntry(
                  accountId: accId,
                  accountName: accName,
                  accountAvatarUrl: accAvatar,
                  accountKind: kindStr,
                  chatPeerId: chatPeerId,
                  itemId: itemId,
                  title: title,
                  snippet: snippet,
                  thumbUrl: thumb,
                  ts: ts,
                  isUnread: isUnread,
                ),
              );
              if (tsRaw.isNotEmpty) {
                final prev = latestByAccount[accId];
                if (prev == null) {
                  latestByAccount[accId] = tsRaw;
                } else {
                  try {
                    final prevDt = DateTime.parse(prev);
                    final curDt = DateTime.parse(tsRaw);
                    if (curDt.isAfter(prevDt)) {
                      latestByAccount[accId] = tsRaw;
                    }
                  } catch (_) {}
                }
              }
            }
          }
        } catch (_) {}
      }
      items.sort((a, b) {
        final at = a.ts ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.ts ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      if (!mounted) return;
      setState(() {
        _subscriptionsItems = items;
      });
      // Mark subscription feeds as seen in shared prefs (per account).
      try {
        Map<String, dynamic> seenMap;
        try {
          seenMap = jsonDecode(rawSeen) as Map<String, dynamic>;
        } catch (_) {
          seenMap = <String, dynamic>{};
        }
        for (final m in subsForSeen) {
          final accId = (m['id'] ?? '').toString();
          if (accId.isEmpty) continue;
          String? tsRaw = latestByAccount[accId];
          if ((tsRaw == null || tsRaw.isEmpty) && m['last_item'] is Map) {
            final lm = m['last_item'] as Map;
            tsRaw = (lm['ts'] ?? '').toString();
          }
          if (tsRaw == null || tsRaw.isEmpty) continue;
          seenMap[accId] = tsRaw;
        }
        await sp.setString('official.feed_seen', jsonEncode(seenMap));
        // Refresh official peer unread state.
        unawaited(_loadOfficialPeers());
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subscriptionsError = l.isArabic
            ? 'تعذّر تحميل الاشتراكات.'
            : 'Could not load subscriptions.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _subscriptionsLoading = false;
        });
      }
    }
  }

  Future<void> _generateIdentity() async {
    final sk = x25519.PrivateKey.generate();
    final pk = sk.publicKey;
    final me = ChatIdentity(
      id: generateShortId(),
      publicKeyB64: base64Encode(pk.asTypedList),
      privateKeyB64: base64Encode(sk.asTypedList),
      fingerprint: fingerprintForKey(base64Encode(pk.asTypedList)),
      displayName: _displayNameCtrl.text.trim().isEmpty
          ? null
          : _displayNameCtrl.text.trim(),
    );
    await _store.saveIdentity(me);
    setState(() {
      _me = me;
      _error = null;
    });
  }

  Future<void> _register() async {
    if (_me == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.registerDevice(_me!);
      await _pullInbox();
      _listenWs();
      await _ensurePushToken();
    } catch (e) {
      setState(() => _error = _sendFailureToUi(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolvePeer({String? presetId}) async {
    final id = (presetId ?? _peerIdCtrl.text).trim();
    if (id.isEmpty) return;
    final priorPeerId = _peer?.id;
    final shouldClearComposer = _isDraftEligibleChatId(priorPeerId);
    await _stashActiveComposerDraft(persistNow: true);
    if (shouldClearComposer) {
      _suppressDraftListener = true;
      _msgCtrl.clear();
      _suppressDraftListener = false;
      _applyState(() {
        _attachedBytes = null;
        _attachedMime = null;
        _attachedName = null;
        _replyToMessage = null;
      });
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final peer = await _service.resolveDevice(id);
      final verified = await _store.isVerified(peer.id, peer.fingerprint);
      final c = peer.copyWith(verified: verified);
      await _store.savePeer(c);
      final updatedContacts = _upsertContact(c);
      await _store.saveContacts(updatedContacts);
      await _store.setActivePeer(c.id);
      final cached = await _store.loadMessages(c.id);
      _cache[c.id] = cached;
      final myId = _me?.id ?? '';
      final priorUnread = _unread[c.id] ?? 0;
      final openUnreadCount = priorUnread > 0 ? priorUnread : 0;
      final anchorId = _computeNewMessagesAnchorMessageId(
        messages: cached,
        myId: myId,
        unreadCount: openUnreadCount,
      );
      final jumpToUnread =
          openUnreadCount > 0 && (anchorId ?? '').trim().isNotEmpty;
      setState(() {
        _peer = c;
        _activePeerId = c.id;
        _newMessagesAnchorPeerId = c.id;
        _newMessagesAnchorMessageId = anchorId;
        _newMessagesCountAtOpen = openUnreadCount;
        _threadNearBottom = !jumpToUnread;
        _threadNewMessagesAwayCount = 0;
        _threadNewMessagesFirstId = null;
        _contacts = updatedContacts;
        _messages = cached;
        _unread[c.id] = 0;
        _peerIdCtrl.text = c.id;
        _safetyNumber = _computeSafety();
        _ratchetWarning = null;
      });
      _restoreComposerDraftForChat(c.id);
      if (jumpToUnread) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(
              _scrollToMessage(anchorId!, alignment: 0.18, highlight: false));
        });
      } else {
        _scheduleThreadScrollToBottom(force: true, animated: false);
      }
      await _store.saveUnread(_unread);
      await _pullInbox();
    } catch (e) {
      setState(() => _error = _sendFailureToUi(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markVerified() async {
    final p = _peer;
    if (p == null) return;
    await _store.markVerified(p.id, p.fingerprint);
    final updated = p.copyWith(verified: true);
    final contacts = _upsertContact(updated);
    await _store.saveContacts(contacts);
    setState(() {
      _peer = updated;
      _contacts = contacts;
      _disappearing = updated.disappearing;
      _disappearAfter = updated.disappearAfter ?? _disappearAfter;
      _safetyNumber = _computeSafety();
    });
  }

  String _sendFailureToUi(Object error) {
    final l = L10n.of(context);
    if (error is _SigningKeyPinViolation) {
      return l.shamellSessionChangedBody;
    }
    if (error is _SessionBootstrapViolation) {
      return l.shamellSessionChangedBody;
    }
    if (error is ChatHttpException && error.op == 'send') {
      // Fail-closed 404: DM first-contact is invite-only and also avoids recipient enumeration.
      if (error.statusCode == 404) {
        return l.isArabic
            ? 'لا يمكن الإرسال بعد. اطلب رمز دعوة (QR) من الطرف الآخر أو تحقق من المعرّف.'
            : 'Cannot send yet. Ask the other party for an invite QR (or verify the ID).';
      }
      return sanitizeHttpError(
        statusCode: error.statusCode,
        rawBody: error.body,
        isArabic: l.isArabic,
      );
    }
    return sanitizeExceptionForUi(error: error, isArabic: l.isArabic);
  }

  bool _isRecoverableSendError(Object error) {
    if (error is ChatHttpException) {
      if (error.statusCode == 401 || error.statusCode == 403) return true;
      if (error.statusCode == 408 ||
          error.statusCode == 425 ||
          error.statusCode == 429 ||
          error.statusCode >= 500) {
        return true;
      }
      if (error.statusCode == 409) {
        final detail = (error.body ?? '').toLowerCase();
        return detail.contains('chat device not registered') ||
            detail.contains('device id already in use');
      }
    }
    final text = error.toString().toLowerCase();
    return text.contains('authentication required') ||
        text.contains('unauthorized') ||
        text.contains('sign-in required') ||
        text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection');
  }

  Future<void> _sendRetryBackoff(int attempt) async {
    final capped = attempt.clamp(0, 4);
    final base = 220 * (1 << capped);
    final jitter = Random.secure().nextInt(180);
    await Future<void>.delayed(Duration(milliseconds: base + jitter));
  }

  Future<bool> _recoverSendAuthState() async {
    try {
      await _service.ensureAccountChatReady();
      final refreshed = await _store.loadIdentity();
      if (refreshed == null) return false;
      if (mounted) {
        _applyState(() {
          _me = refreshed;
        });
      } else {
        _me = refreshed;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<({ChatMessage msg, ChatContact peer})> _sendDraftPayload({
    required ChatIdentity me,
    required ChatContact peer,
    required String text,
  }) async {
    final outbound = await _nextOutboundSendContext(peer);
    final outboundPeer = outbound.peer;
    _sessionHash ??= _computeSessionHash();
    final payload = <String, Object?>{
      "text": text,
      "client_ts": DateTime.now().toIso8601String(),
      "sender_fp": me.fingerprint,
      "session_hash": _sessionHash,
    };
    final reply = _replyToMessage;
    if (reply != null) {
      try {
        final decodedReply = _decodeMessage(reply);
        final preview = decodedReply.text.isNotEmpty
            ? decodedReply.text
            : _previewText(reply);
        payload['reply_to_id'] = reply.id;
        payload['reply_preview'] = preview;
      } catch (_) {}
    }
    if (_attachedBytes != null) {
      payload["attachment_b64"] = base64Encode(_attachedBytes!);
      payload["attachment_mime"] = _attachedMime ?? "image/jpeg";
    }
    final msg = await _service.sendMessage(
      me: me,
      peer: outboundPeer,
      plainText: jsonEncode(payload),
      expireAfterSeconds: _disappearing ? _disappearAfter.inSeconds : null,
      sealedSender: true,
      senderHint: me.fingerprint,
      sessionKey: outbound.sessionKey,
      keyId: outbound.keyId,
      prevKeyId: outbound.prevKeyId,
      senderDhPubB64: outbound.senderDhPubB64,
    );
    return (msg: msg, peer: outboundPeer);
  }

  Future<void> _send() async {
    if (_me == null || _peer == null) return;
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && _attachedBytes == null) return;
    setState(() {
      _sending = true;
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    // Lightweight client-side commands to jump into Shamell modules.
    if (_handleLocalCommand(text)) {
      final peerId = _peer?.id;
      _msgCtrl.clear();
      _attachedBytes = null;
      _attachedMime = null;
      _attachedName = null;
      _replyToMessage = null;
      if (peerId != null) {
        unawaited(_clearDraftForChat(peerId, persistNow: true));
      }
      return;
    }
    var delivered = false;
    Object? failure;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final me = _me;
        final peer = _peer;
        if (me == null || peer == null) {
          failure = StateError('Authentication required');
          break;
        }
        try {
          final sent = await _sendDraftPayload(me: me, peer: peer, text: text);
          final currentPeer = sent.peer;
          _msgCtrl.clear();
          _attachedBytes = null;
          _attachedMime = null;
          _attachedName = null;
          _replyToMessage = null;
          await _clearDraftForChat(currentPeer.id, persistNow: true);
          _mergeMessages([sent.msg]);
          _scheduleThreadScrollToBottom(force: true);
          final off = _linkedOfficial ??
              await _loadOfficialForPeer(currentPeer, updateState: false);
          if (off != null) {
            unawaited(_maybeInjectOfficialKeywordReply(off, text));
          }
          delivered = true;
          break;
        } catch (e) {
          failure = e;
          if (_isRecoverableSendError(e) && attempt < 2) {
            final recovered = await _recoverSendAuthState();
            if (recovered) {
              await _sendRetryBackoff(attempt);
              continue;
            }
            await _sendRetryBackoff(attempt);
            continue;
          }
          break;
        }
      }
      if (!delivered && failure != null && mounted) {
        final ui = _sendFailureToUi(failure);
        setState(() => _error = ui);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ui)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendVoiceNote(Uint8List audioBytes, int seconds) async {
    if (_me == null || _peer == null) return;
    if (audioBytes.isEmpty || seconds <= 0) return;
    setState(() {
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    try {
      final outbound = await _nextOutboundSendContext(_peer!);
      final outboundPeer = outbound.peer;
      _sessionHash ??= _computeSessionHash();
      final payload = <String, Object?>{
        "text": "",
        "kind": "voice",
        "voice_secs": seconds,
        "client_ts": DateTime.now().toIso8601String(),
        "sender_fp": _me?.fingerprint ?? '',
        "session_hash": _sessionHash,
        "attachment_b64": base64Encode(audioBytes),
        "attachment_mime": "audio/aac",
      };
      final msg = await _service.sendMessage(
        me: _me!,
        peer: outboundPeer,
        plainText: jsonEncode(payload),
        expireAfterSeconds: _disappearing ? _disappearAfter.inSeconds : null,
        sealedSender: true,
        senderHint: _me?.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
      );
      _mergeMessages([msg]);
      _scheduleThreadScrollToBottom(force: true);
    } catch (e) {
      setState(() => _error = _sendFailureToUi(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendLocation(double lat, double lon, {String? label}) async {
    if (_me == null || _peer == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    try {
      final outbound = await _nextOutboundSendContext(_peer!);
      final outboundPeer = outbound.peer;
      _sessionHash ??= _computeSessionHash();
      final payload = <String, Object?>{
        "text": (label ?? '').trim(),
        "kind": "location",
        "lat": lat,
        "lon": lon,
        "client_ts": DateTime.now().toIso8601String(),
        "sender_fp": _me?.fingerprint ?? '',
        "session_hash": _sessionHash,
      };
      final msg = await _service.sendMessage(
        me: _me!,
        peer: outboundPeer,
        plainText: jsonEncode(payload),
        expireAfterSeconds: _disappearing ? _disappearAfter.inSeconds : null,
        sealedSender: true,
        senderHint: _me?.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
      );
      _mergeMessages([msg]);
      _scheduleThreadScrollToBottom(force: true);
    } catch (e) {
      setState(() => _error = _sendFailureToUi(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCurrentLocation() async {
    if (_me == null || _peer == null) return;
    final l = L10n.of(context);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'خدمة الموقع معطلة على هذا الجهاز.'
                  : 'Location services are disabled on this device.',
            ),
          ),
        );
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'لا يمكن الوصول إلى الموقع. تحقق من صلاحيات التطبيق.'
                  : 'Cannot access location. Please check app permissions.',
            ),
          ),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);
      await _sendLocation(pos.latitude, pos.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تم إرسال موقعك الحالي.'
                : 'Your current location was sent.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تعذّر إرسال الموقع.' : 'Could not send location.',
          ),
        ),
      );
    }
  }

  bool _handleLocalCommand(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    // /bus -> open Bus mini-program
    if (lower == '/bus') {
      _openMiniAppFromShamell('bus');
      return true;
    }
    // /pay [amount] [@recipient or phone]
    if (lower.startsWith('/pay')) {
      String? recipient;
      int? amountCents;
      final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      // tokens after /pay
      for (var i = 1; i < parts.length; i++) {
        final token = parts[i];
        if (amountCents == null) {
          final amtStr = token.replaceAll(',', '.');
          final parsed = double.tryParse(amtStr);
          if (parsed != null && parsed > 0) {
            amountCents = (parsed * 100).round();
            continue;
          }
        }
        if (recipient == null) {
          if (token.startsWith('@') && token.length > 1) {
            recipient = token.substring(1);
          } else if (RegExp(r'^[+0-9]').hasMatch(token)) {
            recipient = token;
          }
        }
      }
      unawaited(_ensureServiceOfficialFollow(
          officialId: 'shamell_pay', chatPeerId: 'shamell_pay'));
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentsPage(
            widget.baseUrl,
            '',
            'shamell',
            initialRecipient: recipient,
            initialAmountCents: amountCents,
            contextLabel: 'Shamell Pay',
          ),
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> _ensureServiceOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {
    if (officialId.isEmpty || chatPeerId.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final followKey = 'official.autofollow.$officialId';
      final alreadyFollowed = sp.getBool(followKey) ?? false;
      var justFollowed = false;
      if (!alreadyFollowed) {
        final uri =
            Uri.parse('${widget.baseUrl}/official_accounts/$officialId/follow');
        final r = await http
            .post(uri, headers: await _officialHeaders(jsonBody: true))
            .timeout(_ShamellChatPageState._chatRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          await sp.setBool(followKey, true);
          justFollowed = true;
        }
      }
      final chatKey = 'official.autochat.$chatPeerId';
      final alreadyLinked = sp.getBool(chatKey) ?? false;
      if (!alreadyLinked) {
        final svc = ChatService(widget.baseUrl);
        ChatContact peer;
        try {
          peer = await svc.resolveDevice(chatPeerId);
        } catch (_) {
          return;
        }
        final contacts = await _store.loadContacts();
        final exists = contacts.any((c) => c.id == peer.id);
        if (!exists) {
          final updated = <ChatContact>[...contacts, peer];
          await _store.saveContacts(updated);
        }
        await sp.setBool(chatKey, true);
      }
      if (justFollowed && mounted) {
        final l = L10n.of(context);
        final msg = l.isArabic
            ? 'تمت متابعة الحساب الرسمي للخدمة تلقائياً.'
            : 'You now follow the service official account.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _pullInbox() async {
    if (_me == null) return;
    try {
      final msgs = await _service.fetchInbox(deviceId: _me!.id, limit: 80);
      _mergeMessages(msgs);
      await _syncGroups();
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    }
  }

  String _groupUnreadKey(String groupId) => 'grp:$groupId';

  Future<void> _syncGroups() async {
    final me = _me;
    if (me == null) return;
    try {
      final groups = await _service.listGroups(deviceId: me.id);
      final store = _store;
      unawaited(store.upsertGroupNames(groups));
      final seenMap = await store.loadGroupSeen();
      Map<String, int> unreadBase = _unread;
      try {
        unreadBase = await store.loadUnread();
      } catch (_) {}
      final nextUnread = Map<String, int>.from(unreadBase);
      final nextGroupCache =
          Map<String, List<ChatGroupMessage>>.from(_groupCache);
      final nextGroupMentionUnread = <String>{};
      final nextGroupMentionAllUnread = <String>{};
      final nextArchivedGroupIds = Set<String>.from(_archivedGroupIds);
      var archivedGroupsChanged = false;
      final meIdLower = me.id.toLowerCase();
      final mentionReg = RegExp(r'@([A-Za-z0-9_-]{2,})');
      final mentionWsReg = RegExp(r'\s');
      const arabicAllToken = '@الكل';
      for (final g in groups) {
        final gid = g.id;
        if (gid.isEmpty) continue;
        // Load cached messages once.
        var cached = nextGroupCache[gid];
        if (cached == null) {
          try {
            cached = await store.loadGroupMessages(gid);
          } catch (_) {
            cached = <ChatGroupMessage>[];
          }
        }
        DateTime seenTs = DateTime.fromMillisecondsSinceEpoch(0);
        final seenIso = seenMap[gid];
        if (seenIso != null && seenIso.isNotEmpty) {
          try {
            seenTs = DateTime.parse(seenIso);
          } catch (_) {}
        }
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        final sinceIso = (cached.isNotEmpty && cached.last.createdAt != null)
            ? cached.last.createdAt!.toUtc().toIso8601String()
            : (seenTs.isAfter(epoch) ? seenTs.toUtc().toIso8601String() : null);
        List<ChatGroupMessage> fresh = const <ChatGroupMessage>[];
        try {
          fresh = await _service.fetchGroupInbox(
            groupId: gid,
            deviceId: me.id,
            sinceIso: sinceIso,
            limit: 80,
          );
        } catch (_) {
          fresh = const <ChatGroupMessage>[];
        }
        if (fresh.isNotEmpty) {
          final byId = <String, ChatGroupMessage>{
            for (final m in cached) m.id: m
          };
          for (final m in fresh) {
            if (m.id.isEmpty) continue;
            byId[m.id] = m;
          }
          cached = byId.values.toList()
            ..sort((a, b) {
              final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return at.compareTo(bt);
            });
          nextGroupCache[gid] = cached;
          try {
            await store.saveGroupMessages(gid, cached);
          } catch (_) {}
        } else {
          nextGroupCache[gid] = cached;
        }
        final unreadCount = cached.where((m) {
          final ts = m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return m.senderId != me.id && ts.isAfter(seenTs);
        }).length;
        if (unreadCount > 0 && nextArchivedGroupIds.remove(gid)) {
          archivedGroupsChanged = true;
        }
        final unreadKey = _groupUnreadKey(gid);
        final prevUnread = nextUnread[unreadKey] ?? 0;
        if (unreadCount <= 0) {
          nextUnread[unreadKey] = prevUnread < 0 ? -1 : prevUnread;
        } else {
          nextUnread[unreadKey] = max(unreadCount, max(prevUnread, 0));
        }
        bool mentionHit = false;
        bool mentionAllHit = false;
        if (unreadCount > 0) {
          for (final m in cached.reversed) {
            final ts = m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            if (m.senderId == me.id || !ts.isAfter(seenTs)) continue;
            final kind = (m.kind ?? '').toLowerCase();
            if (kind == 'system' || kind == 'sealed') continue;
            final text = m.text.trim();
            if (text.isEmpty) continue;
            if (!mentionAllHit && text.contains(arabicAllToken)) {
              var idx = text.indexOf(arabicAllToken);
              while (idx != -1) {
                if (idx == 0 || mentionWsReg.hasMatch(text[idx - 1])) {
                  mentionHit = true;
                  mentionAllHit = true;
                  break;
                }
                idx = text.indexOf(arabicAllToken, idx + arabicAllToken.length);
              }
              if (mentionAllHit) break;
            }
            for (final mm in mentionReg.allMatches(text)) {
              if (mm.start > 0 && !mentionWsReg.hasMatch(text[mm.start - 1])) {
                continue;
              }
              final id = (mm.group(1) ?? '').toLowerCase();
              if (id == meIdLower) {
                mentionHit = true;
              } else if (id == 'all') {
                mentionHit = true;
                mentionAllHit = true;
              }
              if (mentionAllHit) break;
            }
            if (mentionAllHit) break;
          }
        }
        if (mentionHit) {
          nextGroupMentionUnread.add(gid);
          if (mentionAllHit) {
            nextGroupMentionAllUnread.add(gid);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _groupCache
          ..clear()
          ..addAll(nextGroupCache);
        _unread = nextUnread;
        _groupMentionUnread = nextGroupMentionUnread;
        _groupMentionAllUnread = nextGroupMentionAllUnread;
        _archivedGroupIds = nextArchivedGroupIds;
      });
      if (archivedGroupsChanged) {
        unawaited(_persistArchivedGroups());
      }
      await store.saveUnread(nextUnread);
    } catch (_) {}
  }

  void _mergeGroupInboxUpdate(ChatGroupInboxUpdate upd) {
    final me = _me;
    if (me == null) return;
    final gid = upd.groupId;
    if (gid.isEmpty || upd.messages.isEmpty) return;

    final existing = _groupCache[gid] ?? const <ChatGroupMessage>[];
    final existingIds = existing.map((m) => m.id).toSet();
    final newMsgs = <ChatGroupMessage>[];
    final byId = <String, ChatGroupMessage>{
      for (final m in existing) m.id: m,
    };
    for (final m in upd.messages) {
      if (m.id.isEmpty) continue;
      if (!existingIds.contains(m.id)) {
        newMsgs.add(m);
      }
      byId[m.id] = m;
    }
    final hasIncoming = newMsgs.any((m) => m.senderId != me.id);
    if (hasIncoming && _archivedGroupIds.contains(gid)) {
      final nextArchived = Set<String>.from(_archivedGroupIds);
      if (nextArchived.remove(gid)) {
        _archivedGroupIds = nextArchived;
        unawaited(_persistArchivedGroups());
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });

    _groupCache[gid] = merged;
    unawaited(_store.saveGroupMessages(gid, merged));

    _maybeNotifyGroupMentions(gid, newMsgs);

    unawaited(() async {
      final seenMap = await _store.loadGroupSeen();
      DateTime seenTs = DateTime.fromMillisecondsSinceEpoch(0);
      final seenIso = seenMap[gid];
      if (seenIso != null && seenIso.isNotEmpty) {
        try {
          seenTs = DateTime.parse(seenIso);
        } catch (_) {}
      }
      final unreadKey = _groupUnreadKey(gid);
      final unreadCount = merged.where((m) {
        final ts = m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return m.senderId != me.id && ts.isAfter(seenTs);
      }).length;
      bool mentionHit = false;
      bool mentionAllHit = false;
      if (unreadCount > 0) {
        final meIdLower = me.id.toLowerCase();
        final mentionReg = RegExp(r'@([A-Za-z0-9_-]{2,})');
        final mentionWsReg = RegExp(r'\s');
        const arabicAllToken = '@الكل';
        for (final m in merged.reversed) {
          final ts = m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (m.senderId == me.id || !ts.isAfter(seenTs)) continue;
          final kind = (m.kind ?? '').toLowerCase();
          if (kind == 'system' || kind == 'sealed') continue;
          final text = m.text.trim();
          if (text.isEmpty) continue;
          if (!mentionAllHit && text.contains(arabicAllToken)) {
            var idx = text.indexOf(arabicAllToken);
            while (idx != -1) {
              if (idx == 0 || mentionWsReg.hasMatch(text[idx - 1])) {
                mentionHit = true;
                mentionAllHit = true;
                break;
              }
              idx = text.indexOf(arabicAllToken, idx + arabicAllToken.length);
            }
            if (mentionAllHit) break;
          }
          for (final mm in mentionReg.allMatches(text)) {
            if (mm.start > 0 && !mentionWsReg.hasMatch(text[mm.start - 1])) {
              continue;
            }
            final id = (mm.group(1) ?? '').toLowerCase();
            if (id == meIdLower) {
              mentionHit = true;
            } else if (id == 'all') {
              mentionHit = true;
              mentionAllHit = true;
            }
            if (mentionAllHit) break;
          }
          if (mentionAllHit) break;
        }
      }
      final nextUnread = Map<String, int>.from(_unread);
      final prevUnread = _unread[unreadKey] ?? 0;
      if (unreadCount <= 0) {
        nextUnread[unreadKey] = prevUnread < 0 ? -1 : prevUnread;
      } else {
        nextUnread[unreadKey] = max(unreadCount, max(prevUnread, 0));
      }
      final nextMentions = Set<String>.from(_groupMentionUnread);
      final nextMentionAll = Set<String>.from(_groupMentionAllUnread);
      if (mentionHit) {
        nextMentions.add(gid);
        if (mentionAllHit) {
          nextMentionAll.add(gid);
        } else {
          nextMentionAll.remove(gid);
        }
      } else {
        nextMentions.remove(gid);
        nextMentionAll.remove(gid);
      }
      if (!mounted) return;
      setState(() {
        _groupCache[gid] = merged;
        _unread = nextUnread;
        _groupMentionUnread = nextMentions;
        _groupMentionAllUnread = nextMentionAll;
      });
      await _store.saveUnread(nextUnread);
      if (!_groups.any((g) => g.id == gid)) {
        await _syncGroups();
      }
    }());
  }

  void _maybeNotifyGroupMentions(String gid, List<ChatGroupMessage> newMsgs) {
    final me = _me;
    if (me == null || newMsgs.isEmpty) return;
    if (_groupPrefs[gid]?.muted ?? false) return;
    // Only notify when this page is visible.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final meIdLower = me.id.toLowerCase();
    final reg = RegExp(r'@([A-Za-z0-9_-]{2,})');
    final wsReg = RegExp(r'\s');
    const arabicAllToken = '@الكل';
    for (final m in newMsgs) {
      if (m.senderId == me.id) continue;
      final kind = (m.kind ?? '').toLowerCase();
      if (kind == 'system' || kind == 'sealed') continue;
      final text = m.text.trim();
      if (text.isEmpty) continue;
      bool hit = false;
      if (text.contains(arabicAllToken)) {
        var idx = text.indexOf(arabicAllToken);
        while (idx != -1) {
          if (idx == 0 || wsReg.hasMatch(text[idx - 1])) {
            hit = true;
            break;
          }
          idx = text.indexOf(arabicAllToken, idx + arabicAllToken.length);
        }
      }
      for (final mm in reg.allMatches(text)) {
        if (mm.start > 0 && !wsReg.hasMatch(text[mm.start - 1])) {
          continue;
        }
        final id = (mm.group(1) ?? '').toLowerCase();
        if (id == meIdLower || id == 'all') {
          hit = true;
          break;
        }
      }
      if (!hit) continue;
      // Rich notifications removed (metadata hardening): never include group
      // names, sender hints, message previews, or deep-links to specific chats.
      unawaited(() async {
        final store = ChatLocalStore();
        final prefs = await store.loadNotifyConfig();
        if (!prefs.enabled) return;
        if (prefs.dnd) {
          final now = DateTime.now();
          final cur = now.hour * 60 + now.minute;
          final start = prefs.dndStart;
          final end = prefs.dndEnd;
          final quiet = (start == end)
              ? true
              : (start < end)
                  ? (cur >= start && cur < end)
                  : (cur >= start || cur < end);
          if (quiet) return;
        }
        final l = L10n.of(context);
        await NotificationService.showChatMessage(
          title: l.shamellNewMessageTitle,
          body: l.shamellNewMessageBody,
          playSound: prefs.sound,
          vibrate: prefs.vibrate,
          deepLink: Uri(
            scheme: 'shamell',
            host: 'chat',
          ).toString(),
        );
      }());
      break;
    }
  }

  void _listenWs() {
    _wsSub?.cancel();
    _grpWsSub?.cancel();
    _service.close();
    final me = _me;
    if (me == null) return;
    _wsSub = _service.streamInbox(deviceId: me.id).listen((msgs) {
      if (msgs.isNotEmpty) {
        _mergeMessages(msgs);
      }
    }, onError: (_) {}, onDone: () {});

    _grpWsSub = _service.streamGroupInbox(deviceId: me.id).listen((upd) {
      _mergeGroupInboxUpdate(upd);
    });
  }

  void _listenPush() {
    _pushSub?.cancel();
    _pushSub = FirebaseMessaging.onMessage.listen((msg) {
      try {
        final data = msg.data;
        final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
        if (rawType != 'chat_wakeup') return;
        _pullInbox();
      } catch (_) {}
    });
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

  void _toggleComposerPanel(_ShamellComposerPanel panel) {
    final me = _me;
    final peer = _peer;
    if (_loading || me == null || peer == null || peer.blocked) return;
    if (_recordingVoice) return;

    if (_composerPanel == panel) {
      setState(() {
        _composerPanel = _ShamellComposerPanel.none;
      });
      if (!_shamellVoiceMode) {
        _composerFocus.requestFocus();
      }
      return;
    }

    setState(() {
      _shamellVoiceMode = false;
      _composerPanel = panel;
      if (panel == _ShamellComposerPanel.more) {
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
    _scheduleThreadScrollToBottom(force: true, animated: false);
  }

  Widget _buildMorePanel(ChatIdentity me, ChatContact peer) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const panelHeight = 276.0;
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
        _composerPanel = _ShamellComposerPanel.none;
      });
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
          _pickAttachment();
        },
      ),
      (
        icon: Icons.camera_alt_outlined,
        label: l.isArabic ? 'الكاميرا' : 'Camera',
        onTap: () {
          close();
          _pickAttachment(source: ImageSource.camera);
        },
      ),
      (
        icon: Icons.videocam_outlined,
        label: l.shamellInternetCall,
        onTap: () {
          close();
          _startVoipCall(mode: 'video');
        },
      ),
      (
        icon: Icons.call_outlined,
        label: l.isArabic ? 'مكالمة صوتية' : 'Voice call',
        onTap: () {
          close();
          _startVoipCall(mode: 'audio');
        },
      ),
      (
        icon: Icons.location_on_outlined,
        label: l.shamellSendLocation,
        onTap: () {
          close();
          _sendCurrentLocation();
        },
      ),
      if (_caps.payments)
        (
          icon: Icons.payments_outlined,
          label: l.shamellSendMoney,
          onTap: () {
            close();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentsPage(
                  widget.baseUrl,
                  '',
                  'shamell',
                  initialRecipient: peer.id,
                  contextLabel: 'Shamell Pay',
                ),
              ),
            );
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
      if (_caps.miniPrograms)
        (
          icon: Icons.apps_outlined,
          label: l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs',
          onTap: () {
            close();
            unawaited(_openMiniProgramsHubFromChats());
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
      height: panelHeight,
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

  // ignore: unused_element
  void _toggleVoiceRecord() {
    if (_me == null || _peer == null) return;
    if (_recordingVoice) {
      _stopVoiceRecord();
    } else {
      _startVoiceRecord();
    }
  }

  void _startVoiceRecord() {
    if (_me == null || _peer == null) return;
    _doStartVoiceRecord();
  }

  Future<void> _stopVoiceRecord() async {
    if (!_recordingVoice) return;
    final start = _voiceStart ?? DateTime.now();
    final elapsedMs = DateTime.now().difference(start).inMilliseconds;
    // Very short taps should behave like Shamell: cancel instead of sending.
    if (elapsedMs < 800) {
      final l = L10n.of(context);
      await _cancelVoiceRecord();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shamellVoiceTooShort)),
        );
      }
      return;
    }
    setState(() {
      _recordingVoice = false;
      _voiceStart = null;
      _voiceLocked = false;
      _voiceCancelPending = false;
      _voiceGestureStartLocal = null;
      _voiceElapsedSecs = 0;
      _voiceWaveTick = 0;
    });
    _voiceTicker?.cancel();
    _voiceTicker = null;
    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final elapsed = DateTime.now().difference(start).inSeconds;
      final secs = elapsed.clamp(1, 120);
      await _sendVoiceNote(bytes, secs);
    } catch (_) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shamellVoicePlaybackSoon)),
      );
    }
  }

  Future<void> _cancelVoiceRecord() async {
    if (!_recordingVoice) return;
    setState(() {
      _recordingVoice = false;
      _voiceStart = null;
      _voiceLocked = false;
      _voiceCancelPending = false;
      _voiceGestureStartLocal = null;
      _voiceElapsedSecs = 0;
      _voiceWaveTick = 0;
    });
    _voiceTicker?.cancel();
    _voiceTicker = null;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  Future<void> _deleteMessageLocal(ChatMessage m) async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null) return;
    final peerId = peer.id;
    final list = List<ChatMessage>.from(_cache[peerId] ?? _messages);
    list.removeWhere((x) => x.id == m.id);
    _cache[peerId] = list;
    if (_activePeerId == peerId) {
      _applyState(() {
        _messages = list;
      });
    }
    unawaited(_store.saveMessages(peerId, list));
  }

  Future<void> _clearChatHistoryForPeer(ChatContact c) async {
    final peerId = c.id;
    _cache[peerId] = <ChatMessage>[];
    if (_activePeerId == peerId) {
      _applyState(() {
        _messages = const <ChatMessage>[];
      });
    }
    _unread[peerId] = 0;
    unawaited(_store.saveMessages(peerId, const <ChatMessage>[]));
    unawaited(_store.saveUnread(_unread));
  }

  void _setReaction(ChatMessage m, String emoji) {
    _applyState(() {
      final current = _messageReactions[m.id];
      if (current == emoji) {
        _messageReactions.remove(m.id);
      } else {
        _messageReactions[m.id] = emoji;
      }
    });
  }

  Future<void> _forwardMessages(List<ChatMessage> msgs) async {
    final me = _me;
    if (me == null || msgs.isEmpty) return;
    final target = await _pickForwardTarget();
    if (!mounted || target == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    try {
      _sessionHash ??= _computeSessionHash();
      final bootstrappedTarget = await _bootstrapPeerSessionIfNeeded(target);
      final ratchet = _ensureRatchet(bootstrappedTarget);
      for (final m in msgs) {
        final decoded = _decodeMessage(m);
        if (decoded.text.isEmpty &&
            (decoded.attachment == null || decoded.attachment!.isEmpty) &&
            (decoded.kind == null || decoded.kind!.isEmpty)) {
          continue;
        }
        final payload = <String, Object?>{
          'text': decoded.text,
          'client_ts': DateTime.now().toIso8601String(),
          'sender_fp': me.fingerprint,
          'session_hash': _sessionHash,
        };
        final kind = decoded.kind;
        if (kind == 'voice') {
          payload['kind'] = kind;
        }
        if (kind == 'voice' && decoded.voiceSecs != null) {
          payload['voice_secs'] = decoded.voiceSecs;
        }
        if (decoded.attachment != null && decoded.attachment!.isNotEmpty) {
          payload['attachment_b64'] = base64Encode(decoded.attachment!);
          if (decoded.mime != null && decoded.mime!.isNotEmpty) {
            payload['attachment_mime'] = decoded.mime;
          }
        }
        final mk = _ratchetNextSend(ratchet, peerId: bootstrappedTarget.id);
        final sessionKey = mk.$1;
        final keyId = mk.$2;
        final prevKeyId = mk.$3;
        final dhPubB64 = mk.$4;
        final expireAfterSeconds = bootstrappedTarget.disappearing &&
                bootstrappedTarget.disappearAfter != null
            ? bootstrappedTarget.disappearAfter!.inSeconds
            : null;
        final forwarded = await _service.sendMessage(
          me: me,
          peer: bootstrappedTarget,
          plainText: jsonEncode(payload),
          expireAfterSeconds: expireAfterSeconds,
          sealedSender: true,
          senderHint: me.fingerprint,
          sessionKey: sessionKey,
          keyId: keyId,
          prevKeyId: prevKeyId,
          senderDhPubB64: dhPubB64,
        );
        _mergeMessages([forwarded]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _sendFailureToUi(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _toggleMessageSelected(String messageId) {
    _applyState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _messageSelectionMode = false;
        }
      } else {
        _messageSelectionMode = true;
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _clearMessageSelection() {
    _applyState(() {
      _messageSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  Future<void> _deleteSelectedMessages() async {
    final peer = _peer;
    if (peer == null || _selectedMessageIds.isEmpty) {
      _clearMessageSelection();
      return;
    }
    final peerId = peer.id;
    var list = List<ChatMessage>.from(_cache[peerId] ?? _messages);
    list.removeWhere((m) => _selectedMessageIds.contains(m.id));
    _cache[peerId] = list;
    if (_activePeerId == peerId) {
      _applyState(() {
        _messages = list;
        _messageSelectionMode = false;
        _selectedMessageIds.clear();
      });
    } else {
      _applyState(() {
        _messageSelectionMode = false;
        _selectedMessageIds.clear();
      });
    }
    unawaited(_store.saveMessages(peerId, list));
  }

  Future<void> _forwardSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    final peer = _peer;
    if (peer == null) {
      _clearMessageSelection();
      return;
    }
    final selected = Set<String>.from(_selectedMessageIds);
    final msgs = <ChatMessage>[];
    for (final m in _messages) {
      if (selected.contains(m.id)) {
        msgs.add(m);
      }
    }
    if (msgs.isEmpty) {
      _clearMessageSelection();
      return;
    }
    await _forwardMessages(msgs);
    if (!mounted) return;
    _clearMessageSelection();
  }

  Future<void> _sendRecallForMessage(ChatMessage m) async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null) return;
    final outbound = await _nextOutboundSendContext(peer);
    final outboundPeer = outbound.peer;
    _sessionHash ??= _computeSessionHash();
    final payload = <String, Object?>{
      "text": "",
      "client_ts": DateTime.now().toIso8601String(),
      "sender_fp": me.fingerprint,
      "session_hash": _sessionHash,
      "kind": "recall",
      "recall_id": m.id,
    };
    final expireAfterSeconds =
        outboundPeer.disappearing && outboundPeer.disappearAfter != null
            ? outboundPeer.disappearAfter!.inSeconds
            : null;
    try {
      final msg = await _service.sendMessage(
        me: me,
        peer: outboundPeer,
        plainText: jsonEncode(payload),
        expireAfterSeconds: expireAfterSeconds,
        sealedSender: true,
        senderHint: me.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
      );
      _mergeMessages([msg]);
    } catch (e) {
      setState(() {
        _error = _sendFailureToUi(e);
      });
    }
  }

  Future<void> _doStartVoiceRecord() async {
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        final l = L10n.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shamellVoicePlaybackSoon)),
        );
        return;
      }
      final tmp = Directory.systemTemp;
      final file = File(
          '${tmp.path}/shamell_voice_out_${DateTime.now().millisecondsSinceEpoch}.aac');
      final config = const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );
      await _recorder.start(config, path: file.path);
      setState(() {
        _recordingVoice = true;
        _voiceStart = DateTime.now();
        _voiceLocked = false;
        _voiceCancelPending = false;
        _voiceGestureStartLocal = null;
        _voiceElapsedSecs = 0;
        _voiceWaveTick = 0;
        _error = null;
      });
      _voiceTicker?.cancel();
      _voiceTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || !_recordingVoice) {
          _voiceTicker?.cancel();
          _voiceTicker = null;
          return;
        }
        // Update elapsed seconds for the timer label.
        final start = _voiceStart;
        if (start == null) {
          _voiceElapsedSecs = 0;
        } else {
          final elapsed = DateTime.now().difference(start).inSeconds;
          _voiceElapsedSecs = elapsed.clamp(0, 120);
        }
        // Advance simple waveform phase.
        _voiceWaveTick = (_voiceWaveTick + 1) % 32;
        if (mounted) {
          setState(() {});
        }
      });
    } catch (_) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shamellVoicePlaybackSoon)),
      );
    }
  }

  Future<void> _translateMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final locale = Localizations.maybeLocaleOf(context);
    final targetLang =
        (locale?.languageCode.toLowerCase().startsWith('ar') ?? false)
            ? 'ar'
            : 'en';
    final uri = Uri.https(
      'translate.google.com',
      '/',
      <String, String>{
        'sl': 'auto',
        'tl': targetLang,
        'text': trimmed,
      },
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _ensurePushToken() async {
    final me = _me;
    if (me == null) return;
    try {
      final perm = await FirebaseMessaging.instance.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final tok = await FirebaseMessaging.instance.getToken();
      if (tok == null || tok.isEmpty) return;
      final platform = switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        TargetPlatform.macOS => 'macos',
        TargetPlatform.windows => 'windows',
        TargetPlatform.linux => 'linux',
        _ => 'flutter',
      };
      await _service.registerPushToken(
          deviceId: me.id, token: tok, platform: platform);
    } catch (_) {
      // Soft-fail; push registration is best-effort for now.
    }
  }

  Future<void> _switchPeer(ChatContact c) async {
    final priorPeerId = _peer?.id;
    final shouldClearComposer =
        _isDraftEligibleChatId(priorPeerId) && priorPeerId != c.id;
    await _stashActiveComposerDraft(persistNow: true);
    if (shouldClearComposer) {
      _suppressDraftListener = true;
      _msgCtrl.clear();
      _suppressDraftListener = false;
      _applyState(() {
        _attachedBytes = null;
        _attachedMime = null;
        _attachedName = null;
        _replyToMessage = null;
      });
    }
    if (c.id == _ShamellChatPageState._subscriptionsPeerId) {
      unawaited(_setForceSubscriptionsUnread(false));
      _applyState(() {
        _peer = c;
        _activePeerId = c.id;
        _newMessagesAnchorPeerId = null;
        _newMessagesAnchorMessageId = null;
        _newMessagesCountAtOpen = 0;
        _threadNearBottom = true;
        _threadNewMessagesAwayCount = 0;
        _threadNewMessagesFirstId = null;
        _peerIdCtrl.text = c.id;
        _messages = const [];
        _voicePlayedMessageIds = <String>{};
        _unread[c.id] = 0;
        _disappearing = false;
        _disappearAfter = const Duration(minutes: 30);
        _safetyNumber = null;
        _ratchetWarning = null;
        _messageSelectionMode = false;
        _selectedMessageIds.clear();
        _attachedBytes = null;
        _attachedMime = null;
        _attachedName = null;
        _replyToMessage = null;
        _shamellVoiceMode = false;
        _composerPanel = _ShamellComposerPanel.none;
      });
      _suppressDraftListener = true;
      _msgCtrl.clear();
      _suppressDraftListener = false;
      _scheduleThreadScrollToBottom(force: true, animated: false);
      await _store.setActivePeer(c.id);
      await _store.saveUnread(_unread);
      await _loadSubscriptionsFeed();
      return;
    }
    final cached = _cache[c.id] ?? await _store.loadMessages(c.id);
    Set<String> voicePlayed = <String>{};
    try {
      voicePlayed = await _store.loadVoicePlayed(c.id);
    } catch (_) {
      voicePlayed = <String>{};
    }
    final myId = _me?.id ?? '';
    final priorUnread = _unread[c.id] ?? 0;
    final openUnreadCount = priorUnread > 0 ? priorUnread : 0;
    final anchorId = _computeNewMessagesAnchorMessageId(
      messages: cached,
      myId: myId,
      unreadCount: openUnreadCount,
    );
    final jumpToUnread =
        openUnreadCount > 0 && (anchorId ?? '').trim().isNotEmpty;
    _cache[c.id] = cached;
    _pruneExpired(c.id);
    setState(() {
      _peer = c;
      _activePeerId = c.id;
      _newMessagesAnchorPeerId = c.id;
      _newMessagesAnchorMessageId = anchorId;
      _newMessagesCountAtOpen = openUnreadCount;
      _threadNearBottom = !jumpToUnread;
      _threadNewMessagesAwayCount = 0;
      _threadNewMessagesFirstId = null;
      _peerIdCtrl.text = c.id;
      _messages = cached;
      _voicePlayedMessageIds = voicePlayed;
      _unread[c.id] = 0;
      _disappearing = c.disappearing;
      _disappearAfter = c.disappearAfter ?? _disappearAfter;
      _safetyNumber = _computeSafety();
      _messageSelectionMode = false;
      _selectedMessageIds.clear();
    });
    _restoreComposerDraftForChat(c.id);
    if (jumpToUnread) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
            _scrollToMessage(anchorId!, alignment: 0.18, highlight: false));
      });
    } else {
      _scheduleThreadScrollToBottom(force: true, animated: false);
    }
    await _store.setActivePeer(c.id);
    await _store.saveUnread(_unread);
    await _markThreadRead(c.id);
    await _pullInbox();
    unawaited(_loadOfficialForPeer(c));
  }

  void _mergeMessages(List<ChatMessage> msgs) {
    final meId = _me?.id;
    if (meId == null) return;
    final activePeerId = _activePeerId;
    final bool threadVisible = _tabIndex == 0 &&
        _peer != null &&
        activePeerId != null &&
        _peer!.id == activePeerId;
    final wasNearBottom = threadVisible ? _isThreadNearBottom : true;
    var activeIncomingAdded = 0;
    String? activeFirstIncomingIdInBatch;
    DateTime? activeFirstIncomingAtInBatch;
    bool activeThreadUpdated = false;
    final updatedUnread = Map<String, int>.from(_unread);
    var contactsChanged = false;
    var exitArchivedAfterSend = false;
    for (final m in msgs) {
      if (_seenMessageIds.contains(m.id)) {
        continue; // replay protection
      }
      _seenMessageIds.add(m.id);
      final peerId = _peerIdForMessage(m, meId);
      final isIncoming = m.senderId != meId;
      if (!isIncoming && _showArchived && peerId == activePeerId) {
        exitArchivedAfterSend = true;
      }
      // Handle recall control messages (kind: 'recall') by marking the
      // target id as recalled and skipping rendering this control message.
      try {
        final raw = _decrypt(m);
        final j = jsonDecode(raw);
        if (j is Map && (j['kind'] ?? '').toString() == 'recall') {
          final targetId = (j['recall_id'] ?? '').toString();
          if (targetId.isNotEmpty) {
            _recalledMessageIds.add(targetId);
            unawaited(_saveRecalledMessages());
            unawaited(_handleMessageRecalled(targetId));
          }
          // Do not store the control message itself in history.
          continue;
        }
        if (j is Map && (j['kind'] ?? '').toString() == 'group_key') {
          final gid = (j['group_id'] ?? '').toString();
          final keyB64 = (j['key_b64'] ?? '').toString();
          if (gid.isNotEmpty && keyB64.isNotEmpty) {
            unawaited(_store.saveGroupKey(gid, keyB64));
            if (isIncoming) {
              unawaited(_service.markRead(m.id));
            }
            // Refresh local group cache with the newly available key.
            unawaited(() async {
              final me = _me;
              if (me == null) return;
              try {
                final full = await _service.fetchGroupInbox(
                  groupId: gid,
                  deviceId: me.id,
                  limit: 200,
                );
                final byId = <String, ChatGroupMessage>{
                  for (final mm in full) mm.id: mm
                };
                final merged = byId.values.toList()
                  ..sort((a, b) {
                    final at =
                        a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bt =
                        b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return at.compareTo(bt);
                  });
                _groupCache[gid] = merged;
                await _store.saveGroupMessages(gid, merged);
                if (mounted) setState(() {});
              } catch (_) {}
            }());
          }
          continue;
        }
      } catch (_) {}
      final contact = _contacts.firstWhere((c) => c.id == peerId,
          orElse: () =>
              _peer ??
              ChatContact(id: peerId, publicKeyB64: '', fingerprint: ''));
      if (contact.blocked) {
        // Skip storing blocked contacts; mark read to clear server backlog
        if (isIncoming) {
          unawaited(_service.markRead(m.id));
        }
        continue;
      }
      var list = _cache[peerId] ?? <ChatMessage>[];
      final map = {for (final msg in list) msg.id: msg};
      map[m.id] = m;
      list = map.values.toList()
        ..sort((a, b) {
          final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });
      if (list.length > 200) {
        list = list.sublist(list.length - 200);
      }
      _cache[peerId] = list;
      unawaited(_store.saveMessages(peerId, list));
      contactsChanged =
          _ensureContact(peerId, m.senderPubKeyB64) || contactsChanged;
      final idx = _contacts.indexWhere((c) => c.id == peerId);
      if (idx != -1 && _contacts[idx].archived) {
        final updated = _contacts[idx].copyWith(archived: false);
        final copy = List<ChatContact>.from(_contacts);
        copy[idx] = updated;
        _contacts = copy;
        contactsChanged = true;
        if (_peer?.id == peerId) {
          _peer = updated;
        }
        unawaited(_store.saveContacts(copy));
      }
      _pruneExpired(peerId);
      if (peerId == activePeerId && threadVisible) {
        activeThreadUpdated = true;
        _messages = _cache[peerId] ?? list;
        updatedUnread[peerId] = 0;
        if (isIncoming) {
          activeIncomingAdded++;
          if (m.id.isNotEmpty) {
            final ts = m.createdAt;
            if (activeFirstIncomingIdInBatch == null) {
              activeFirstIncomingIdInBatch = m.id;
              activeFirstIncomingAtInBatch = ts;
            } else if (ts != null &&
                (activeFirstIncomingAtInBatch == null ||
                    ts.isBefore(activeFirstIncomingAtInBatch!))) {
              activeFirstIncomingIdInBatch = m.id;
              activeFirstIncomingAtInBatch = ts;
            }
          }
          unawaited(_service.markRead(m.id));
        }
      } else if (isIncoming) {
        final curUnread = updatedUnread[peerId] ?? 0;
        updatedUnread[peerId] = curUnread < 0 ? 1 : (curUnread + 1);
      }
    }
    setState(() {
      _unread = updatedUnread;
      if (exitArchivedAfterSend) {
        _showArchived = false;
        _chatSearch = '';
      }
      if (threadVisible && activePeerId != null) {
        _messages = _cache[activePeerId] ?? _messages;
      }
      if (activeThreadUpdated && !wasNearBottom && activeIncomingAdded > 0) {
        _threadNewMessagesAwayCount += activeIncomingAdded;
        if (_threadNewMessagesFirstId == null &&
            activeFirstIncomingIdInBatch != null) {
          _threadNewMessagesFirstId = activeFirstIncomingIdInBatch;
        }
      }
      if (activeThreadUpdated && wasNearBottom) {
        _threadNewMessagesAwayCount = 0;
        _threadNewMessagesFirstId = null;
      }
      if (contactsChanged) {
        _contacts = List<ChatContact>.from(_contacts);
      }
    });
    if (exitArchivedAfterSend) {
      _chatSearchCtrl.clear();
    }
    unawaited(_store.saveUnread(_unread));
    if (activeThreadUpdated && wasNearBottom) {
      _scheduleThreadScrollToBottom(force: true);
    }
  }

  String _decrypt(ChatMessage m) {
    final me = _me;
    if (me == null) return '<no identity>';
    if (m.trustedLocalPlaintext) {
      try {
        return utf8.decode(base64Decode(m.boxB64));
      } catch (_) {
        return '<encrypted>';
      }
    }
    if (!m.sealedSender) {
      return '<encrypted>';
    }
    // Try sealed-session secretbox first
    Uint8List? key;
    try {
      key = _sessionKeyForMessage(m);
    } catch (_) {
      key = null;
    }
    if (key != null && _isCurveKey(key)) {
      try {
        final box = x25519.SecretBox(key);
        final cipher = x25519.ByteList(base64Decode(m.boxB64));
        final nonce = base64Decode(m.nonceB64);
        final plain = box.decrypt(cipher, nonce: nonce);
        return utf8.decode(plain);
      } catch (_) {}
    }
    return '<encrypted>';
  }

  bool _isIncoming(ChatMessage m) => _me != null && m.senderId != _me!.id;

  String? _computeNewMessagesAnchorMessageId({
    required List<ChatMessage> messages,
    required String myId,
    required int unreadCount,
  }) {
    if (myId.isEmpty || unreadCount <= 0 || messages.isEmpty) return null;
    var remaining = unreadCount;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.senderId == myId) continue;
      remaining--;
      if (remaining <= 0) {
        return m.id.isNotEmpty ? m.id : null;
      }
    }
    return null;
  }

  String _peerIdForMessage(ChatMessage m, String myId) {
    if (m.senderId.isNotEmpty) {
      return m.senderId == myId ? m.recipientId : m.senderId;
    }
    if (m.senderHint != null && m.senderHint!.isNotEmpty) {
      final found = _contacts.firstWhere((c) => c.fingerprint == m.senderHint,
          orElse: () =>
              _peer ?? ChatContact(id: '', publicKeyB64: '', fingerprint: ''));
      if (found.id.isNotEmpty) return found.id;
    }
    return _peer?.id ?? m.recipientId;
  }

  bool _ensureContact(String peerId, String pubKeyB64) {
    if (peerId.isEmpty) return false;
    final exists = _contacts.any((c) => c.id == peerId);
    if (exists) return false;
    final c = ChatContact(
      id: peerId,
      publicKeyB64: pubKeyB64,
      fingerprint: fingerprintForKey(pubKeyB64),
      verified: false,
    );
    _contacts = [..._contacts, c];
    unawaited(_store.saveContacts(_contacts));
    return true;
  }

  List<ChatContact> _upsertContact(ChatContact c) {
    final idx = _contacts.indexWhere((x) => x.id == c.id);
    if (idx == -1) {
      _contacts = [..._contacts, c];
      return _contacts;
    }
    final copy = List<ChatContact>.from(_contacts);
    copy[idx] = c;
    _contacts = copy;
    return copy;
  }

  Future<void> _markThreadRead(String peerId) async {
    final meId = _me?.id;
    if (meId == null) return;
    final msgs = _cache[peerId] ?? await _store.loadMessages(peerId);
    for (final m in msgs) {
      if (m.senderId != meId) {
        unawaited(_service.markRead(m.id));
      }
    }
  }

  List<ChatContact> _sortedContacts() {
    final entries = _contacts.map((c) {
      final last = _cache[c.id] != null && _cache[c.id]!.isNotEmpty
          ? _cache[c.id]!.last
          : null;
      final ts = last?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return (c, ts);
    }).toList();
    entries.sort((a, b) {
      final ca = a.$1;
      final cb = b.$1;
      final aPinned = ca.pinned;
      final bPinned = cb.pinned;
      if (aPinned && bPinned) {
        final aIdx = _pinnedChatOrder.indexOf(ca.id);
        final bIdx = _pinnedChatOrder.indexOf(cb.id);
        if (aIdx != -1 || bIdx != -1) {
          if (aIdx == -1 && bIdx != -1) return 1;
          if (aIdx != -1 && bIdx == -1) return -1;
          return aIdx.compareTo(bIdx);
        }
      }
      if (aPinned != bPinned) {
        return (bPinned ? 1 : 0) - (aPinned ? 1 : 0);
      }
      final aFeatured = _featuredOfficialPeerIds.contains(ca.id);
      final bFeatured = _featuredOfficialPeerIds.contains(cb.id);
      if (aFeatured != bFeatured) {
        return (bFeatured ? 1 : 0) - (aFeatured ? 1 : 0);
      }
      final aStarred = ca.starred;
      final bStarred = cb.starred;
      if (aStarred != bStarred) {
        return (bStarred ? 1 : 0) - (aStarred ? 1 : 0);
      }
      return b.$2.compareTo(a.$2);
    });
    return entries.map((e) => e.$1).toList();
  }

  void _pruneExpired(String peerId) {
    final meId = _me?.id;
    if (meId == null) return;
    final contact = _contacts.firstWhere((c) => c.id == peerId,
        orElse: () =>
            _peer ??
            ChatContact(id: peerId, publicKeyB64: '', fingerprint: ''));
    if (!contact.disappearing || contact.disappearAfter == null) return;
    final cutoff = DateTime.now().subtract(contact.disappearAfter!);
    final list = _cache[peerId] ?? [];
    final kept = list.where((m) {
      final ts = m.createdAt ?? m.deliveredAt ?? m.readAt ?? contact.verifiedAt;
      if (ts == null) return true;
      return ts.isAfter(cutoff);
    }).toList();
    if (kept.length != list.length) {
      _cache[peerId] = kept;
      if (peerId == _activePeerId) {
        _messages = kept;
      }
      unawaited(_store.saveMessages(peerId, kept));
    }
  }

  _DecodedPayload _decodeMessage(ChatMessage m) {
    final raw = _decrypt(m);
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final text = (j['text'] ?? '').toString();
        Uint8List? att;
        String? mime;
        if (j['attachment_b64'] is String &&
            (j['attachment_b64'] as String).isNotEmpty) {
          try {
            att = base64Decode(j['attachment_b64'] as String);
            mime = (j['attachment_mime'] ?? 'image/jpeg').toString();
          } catch (_) {}
        }
        final kind = (j['kind'] ?? '').toString();
        final voiceSecsRaw = j['voice_secs'];
        final voiceSecs = voiceSecsRaw is num ? voiceSecsRaw.toInt() : null;
        double? lat;
        double? lon;
        final contactIdRaw = j['contact_id'] ?? j['contactId'];
        final contactId = (contactIdRaw ?? '').toString().trim();
        final contactNameRaw = j['contact_name'] ?? j['contactName'];
        final contactName = (contactNameRaw ?? '').toString().trim();
        final latRaw = j['lat'];
        final lonRaw = j['lon'];
        if (latRaw is num) {
          lat = latRaw.toDouble();
        } else if (latRaw is String && latRaw.isNotEmpty) {
          lat = double.tryParse(latRaw);
        }
        if (lonRaw is num) {
          lon = lonRaw.toDouble();
        } else if (lonRaw is String && lonRaw.isNotEmpty) {
          lon = double.tryParse(lonRaw);
        }
        final clientTs = j['client_ts'] as String?;
        DateTime? ts;
        if (clientTs != null && clientTs.isNotEmpty) {
          try {
            ts = DateTime.parse(clientTs);
          } catch (_) {}
        }
        final senderFp = (j['sender_fp'] ?? '').toString();
        final sessionHash = (j['session_hash'] ?? '').toString();
        if (senderFp.isNotEmpty) {
          // map sender hint for sealed sender
          final mapped =
              _sessionKeysByFp[senderFp] ?? _sessionKeys[_activePeerId ?? ''];
          if (mapped != null && _isCurveKey(mapped)) {
            _sessionKeysByFp[senderFp] = mapped;
          }
          if (_peer != null && _peer!.fingerprint != senderFp) {
            final l = L10n.of(context);
            _ratchetWarning = l.shamellSessionChangedBody;
          }
        }
        if (_sessionHash != null &&
            sessionHash.isNotEmpty &&
            sessionHash != _sessionHash) {
          _ratchetWarning = 'Session hash mismatch. Verify or reset.';
        }
        return _DecodedPayload(
            text: text,
            attachment: att,
            mime: mime,
            clientTs: ts,
            kind: kind.isEmpty ? null : kind,
            contactId: contactId.isEmpty ? null : contactId,
            contactName: contactName.isEmpty ? null : contactName,
            voiceSecs: voiceSecs,
            replyToId: (j['reply_to_id'] ?? '').toString().isEmpty
                ? null
                : (j['reply_to_id'] ?? '').toString(),
            replyPreview: (j['reply_preview'] ?? '').toString().trim().isEmpty
                ? null
                : (j['reply_preview'] ?? '').toString(),
            lat: lat,
            lon: lon);
      }
    } catch (_) {}
    return _DecodedPayload(
      text: raw,
      attachment: null,
      mime: null,
      kind: null,
      contactId: null,
      contactName: null,
      voiceSecs: null,
      replyToId: null,
      replyPreview: null,
      lat: null,
      lon: null,
    );
  }

  String _previewText(ChatMessage m) {
    final d = _decodeMessage(m);
    final l = L10n.of(context);
    if (_recalledMessageIds.contains(m.id)) {
      return _isIncoming(m)
          ? l.shamellMessageRecalledByOther
          : l.shamellMessageRecalledByMe;
    }
    if (d.kind == 'contact') {
      final name = d.text.trim().isNotEmpty
          ? d.text.trim()
          : (d.contactName ?? '').trim();
      if (name.isNotEmpty) {
        return l.isArabic ? 'بطاقة جهة اتصال: $name' : 'Contact card: $name';
      }
      return l.isArabic ? 'بطاقة جهة اتصال' : 'Contact card';
    }
    if (d.kind == 'voice') {
      return l.shamellPreviewVoice;
    }
    if (d.kind == 'location') {
      if (d.text.isNotEmpty) return d.text;
      if (d.lat != null && d.lon != null) {
        return l.shamellPreviewLocation;
      }
    }
    if (d.attachment != null) {
      final caption = d.text.trim();
      return caption.isNotEmpty
          ? '${l.shamellPreviewImage} $caption'
          : l.shamellPreviewImage;
    }
    if (d.text.isNotEmpty) return d.text;
    return l.shamellPreviewUnknown;
  }

  String _expirationLabel(ChatMessage m) {
    Duration? ttl = m.expireAt != null && m.createdAt != null
        ? m.expireAt!.difference(m.createdAt!)
        : (_disappearing ? _disappearAfter : null);
    if (ttl == null || ttl.inSeconds <= 0) return '';
    final created = m.createdAt ?? DateTime.now();
    final expires = m.expireAt ?? created.add(ttl);
    final remaining = expires.difference(DateTime.now());
    if (remaining.isNegative) return 'expired';
    final mins = remaining.inMinutes;
    if (mins >= 1) return '~${mins}m';
    return '<1m';
  }

  Future<void> _openImage(Uint8List data, String? mime) async {
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
                  child: Image.memory(data, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareAttachment(Uint8List data, String? mime) async {
    try {
      final ext = (mime == 'image/png') ? 'png' : 'jpg';
      final file = XFile.fromData(data,
          mimeType: mime ?? 'image/jpeg', name: 'chat.$ext');
      await Share.shareXFiles([file], text: 'Encrypted chat image');
    } catch (_) {
      final l = L10n.of(context);
      setState(
        () => _error = l.isArabic ? 'فشلت المشاركة.' : 'Share failed.',
      );
    }
  }

  Future<void> _openLocationOnMap(double lat, double lon) async {
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _backupIdentity() async {
    final me = _me;
    if (me == null) return;
    final pass = await _promptPassphrase(confirm: true);
    if (pass == null || pass.isEmpty) return;
    try {
      final salt = _randomBytes(16);
      final key = _pbkdf2(pass, salt, 60000, 32);
      final box = x25519.SecretBox(key);
      final payload = jsonEncode(me.toMap());
      final nonce = _randomBytes(24);
      final cipher =
          box.encrypt(Uint8List.fromList(utf8.encode(payload)), nonce: nonce);
      final backup =
          'CHATBACKUP|v1|salt=${base64Encode(salt)}|nonce=${base64Encode(nonce)}|cipher=${base64Encode(cipher.cipherText)}';
      setState(() => _backupText = backup);
      await Clipboard.setData(ClipboardData(text: backup));
      if (mounted) {
        final l = L10n.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.shamellBackupCreated)));
      }
    } catch (e) {
      final l = L10n.of(context);
      setState(
        () => _error =
            '${l.shamellBackupFailed}: ${sanitizeExceptionForUi(error: e, isArabic: l.isArabic)}',
      );
    }
  }

  Future<void> _restoreIdentity() async {
    try {
      final backup = await _promptBackup();
      if (backup == null || backup.isEmpty) return;
      final pass = await _promptPassphrase(confirm: false);
      if (pass == null || pass.isEmpty) return;
      final parts = backup.split('|');
      if (parts.length < 5 || !backup.startsWith('CHATBACKUP|v1|')) {
        final l = L10n.of(context);
        setState(() => _error = l.shamellBackupInvalidFormat);
        return;
      }
      String? saltB64;
      String? nonceB64;
      String? cipherB64;
      for (final p in parts.skip(2)) {
        final kv = p.split('=');
        if (kv.length == 2) {
          if (kv[0] == 'salt') saltB64 = kv[1];
          if (kv[0] == 'nonce') nonceB64 = kv[1];
          if (kv[0] == 'cipher') cipherB64 = kv[1];
        }
      }
      if (saltB64 == null || nonceB64 == null || cipherB64 == null) {
        final l = L10n.of(context);
        setState(() => _error = l.shamellBackupMissingFields);
        return;
      }
      final salt = base64Decode(saltB64);
      final nonce = base64Decode(nonceB64);
      final cipher = x25519.ByteList(base64Decode(cipherB64));
      final key = _pbkdf2(pass, salt, 60000, 32);
      final box = x25519.SecretBox(key);
      final plain = box.decrypt(cipher, nonce: nonce);
      final map = jsonDecode(utf8.decode(plain));
      final restored = ChatIdentity.fromMap((map as Map<String, Object?>));
      if (restored == null) {
        final l = L10n.of(context);
        setState(() => _error = l.shamellBackupCorrupt);
        return;
      }
      await _store.saveIdentity(restored);
      setState(() {
        _me = restored;
        _backupText = backup;
      });
      await _register();
      await _pullInbox();
      _listenWs();
    } catch (e) {
      final l = L10n.of(context);
      setState(
        () => _error =
            '${l.shamellRestoreFailed}: ${sanitizeExceptionForUi(error: e, isArabic: l.isArabic)}',
      );
    }
  }

  Future<String?> _promptPassphrase({required bool confirm}) async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    final l = L10n.of(context);
    return await showDialog<String>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text(confirm
                ? l.shamellBackupPassphraseTitleSet
                : l.shamellBackupPassphraseTitleEnter),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl1,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: l.shamellBackupPassphraseLabel),
                ),
                if (confirm)
                  TextField(
                    controller: ctrl2,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: l.shamellBackupPassphraseConfirm),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(l.shamellDialogCancel)),
              TextButton(
                  onPressed: () {
                    if (confirm && ctrl1.text != ctrl2.text) {
                      Navigator.of(context).pop(null);
                      return;
                    }
                    Navigator.of(context).pop(ctrl1.text);
                  },
                  child: Text(l.shamellDialogOk)),
            ],
          );
        });
  }

  Future<String?> _promptBackup() async {
    final ctrl = TextEditingController(text: _backupText);
    final l = L10n.of(context);
    return await showDialog<String>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text(l.shamellBackupDialogTitle),
            content: TextField(
              controller: ctrl,
              maxLines: 3,
              decoration:
                  InputDecoration(labelText: l.shamellBackupDialogLabel),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(l.shamellDialogCancel)),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
                  child: Text(l.shamellRestoreBackupButton)),
            ],
          );
        });
  }

  Uint8List _randomBytes(int len) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(len, (_) => rnd.nextInt(256)));
  }

  Uint8List _pbkdf2(String pass, Uint8List salt, int iterations, int length) {
    final passBytes = utf8.encode(pass);
    final hmac = crypto.Hmac(crypto.sha256, passBytes);
    final digestLen = hmac.convert(<int>[]).bytes.length;
    final blockCount = (length / digestLen).ceil();
    final out = BytesBuilder();
    for (var block = 1; block <= blockCount; block++) {
      var u = hmac.convert([...salt, ..._int32(block)]).bytes;
      var t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    final bytes = out.toBytes();
    return Uint8List.fromList(bytes.sublist(0, length));
  }

  List<int> _int32(int i) => [
        (i >> 24) & 0xff,
        (i >> 16) & 0xff,
        (i >> 8) & 0xff,
        i & 0xff,
      ];

  String _fmtDuration(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  ChatContact _contactWithUpdatedKey(
    ChatContact base,
    String publicKeyB64,
    String fingerprint,
  ) {
    return ChatContact(
      id: base.id,
      publicKeyB64: publicKeyB64,
      fingerprint: fingerprint,
      name: base.name,
      // Fail closed: a key change invalidates prior verification.
      verified: false,
      verifiedAt: null,
      starred: base.starred,
      pinned: base.pinned,
      disappearing: base.disappearing,
      disappearAfter: base.disappearAfter,
      archived: base.archived,
      hidden: base.hidden,
      blocked: base.blocked,
      blockedAt: base.blockedAt,
      muted: base.muted,
    );
  }

  Future<ChatContact> _bootstrapPeerSessionIfNeeded(ChatContact peer) async {
    if (_ratchets.containsKey(peer.id)) return peer;
    if (!_service.libsignalKeyApiEnabled) return peer;
    final me = _me;
    if (me == null) return peer;

    try {
      final bundle = await _service.fetchKeyBundle(
        targetDeviceId: peer.id,
        requesterDeviceId: me.id,
      );
      final signingKeyB64 = (bundle.identitySigningPubkeyB64 ?? '').trim();
      final pinnedSigningKey =
          (await _store.loadPinnedIdentitySigningPubkey(peer.id) ?? '').trim();
      final hasPinnedSigningKey = pinnedSigningKey.isNotEmpty;
      bool sameSigningKey = false;
      if (signingKeyB64.isNotEmpty && pinnedSigningKey.isNotEmpty) {
        try {
          final a = base64Decode(signingKeyB64);
          final b = base64Decode(pinnedSigningKey);
          if (a.length == b.length) {
            sameSigningKey = true;
            for (var i = 0; i < a.length; i++) {
              if (a[i] != b[i]) {
                sameSigningKey = false;
                break;
              }
            }
          }
        } catch (_) {
          sameSigningKey = false;
        }
      }
      if (hasPinnedSigningKey) {
        if (signingKeyB64.isEmpty || !sameSigningKey) {
          final l = L10n.of(context);
          _applyState(() {
            _ratchetWarning = l.shamellSessionChangedBody;
          });
          throw const _SigningKeyPinViolation('identity signing key changed');
        }
      } else if (signingKeyB64.isEmpty) {
        // Fail closed: key bundles without identity signing keys are not trusted
        // for initial TOFU pinning.
        final l = L10n.of(context);
        _applyState(() {
          _ratchetWarning = l.shamellSessionChangedBody;
        });
        throw const _SigningKeyPinViolation('identity signing key missing');
      }
      final identityKeyB64 = bundle.identityKeyB64.trim();
      if (identityKeyB64.isEmpty) {
        throw const _SessionBootstrapViolation('identity key missing');
      }
      final bundleFp = fingerprintForKey(identityKeyB64).trim();
      if (bundleFp.isEmpty) {
        throw const _SessionBootstrapViolation('identity fingerprint missing');
      }

      final keyChanged =
          identityKeyB64 != peer.publicKeyB64 || bundleFp != peer.fingerprint;
      final updatedPeer = keyChanged
          ? _contactWithUpdatedKey(peer, identityKeyB64, bundleFp)
          : peer;

      if (keyChanged) {
        final contacts = _upsertContact(updatedPeer);
        await _store.saveContacts(contacts);
        if (_peer?.id == updatedPeer.id) {
          await _store.savePeer(updatedPeer);
          if (mounted) {
            setState(() {
              _peer = updatedPeer;
              _contacts = contacts;
              _safetyNumber = _computeSafety();
              _sessionHash = _computeSessionHash();
            });
          }
        }
      }

      await _store.saveSessionBootstrapMeta(
        updatedPeer.id,
        protocolFloor: bundle.protocolFloor,
        signedPrekeyId: bundle.signedPrekeyId,
        oneTimePrekeyId: bundle.oneTimePrekeyId,
        v2Only: bundle.v2Only,
        identitySigningPubkeyB64: signingKeyB64,
      );

      return updatedPeer;
    } on _SigningKeyPinViolation {
      rethrow;
    } on _SessionBootstrapViolation {
      rethrow;
    } catch (e) {
      throw _SessionBootstrapViolation(e.toString());
    }
  }

  Future<
      ({
        ChatContact peer,
        Uint8List sessionKey,
        int keyId,
        int prevKeyId,
        String senderDhPubB64
      })> _nextOutboundSendContext(ChatContact peer) async {
    final preparedPeer = await _bootstrapPeerSessionIfNeeded(peer);
    final ratchet = _ensureRatchet(preparedPeer);
    final mk = _ratchetNextSend(ratchet, peerId: preparedPeer.id);
    return (
      peer: preparedPeer,
      sessionKey: mk.$1,
      keyId: mk.$2,
      prevKeyId: mk.$3,
      senderDhPubB64: mk.$4,
    );
  }

  RatchetState _ensureRatchet(ChatContact peer) {
    final pid = peer.id;
    final existing = _ratchets[pid];
    if (existing != null) {
      if (_isValidRatchetState(existing)) return existing;
      _ratchets.remove(pid);
      unawaited(_store.deleteRatchet(pid));
    }
    final peerPub = _decodeCurveKeyB64(peer.publicKeyB64);
    if (peerPub == null) {
      throw const _SessionBootstrapViolation('peer identity key invalid');
    }
    final dh = x25519.PrivateKey.generate();
    final dhPub = dh.publicKey;
    final shared = x25519.Box(
      myPrivateKey: dh,
      theirPublicKey: x25519.PublicKey(peerPub),
    ).sharedKey;
    final rk =
        Uint8List.fromList(crypto.sha256.convert(shared.asTypedList).bytes);
    final st = RatchetState(
      rootKey: rk,
      sendChainKey: rk,
      recvChainKey: rk,
      sendCount: 0,
      recvCount: 0,
      pn: 0,
      skipped: {},
      peerIdentity: peer.fingerprint,
      dhPriv: dh.asTypedList,
      dhPub: dhPub.asTypedList,
      peerDhPub: peerPub,
      peerDhPubB64: base64Encode(peerPub),
    );
    _ratchets[pid] = st;
    _store.saveRatchet(pid, st.toJson());
    return st;
  }

  (Uint8List, int, int, String) _ratchetNextSend(
    RatchetState st, {
    required String peerId,
  }) {
    final mk = _kdfChain(st.sendChainKey, st.sendCount);
    st.sendChainKey = mk.$2;
    final keyId = st.sendCount;
    final prev = st.sendCount - 1;
    st.sendCount += 1;
    _store.saveRatchet(peerId, st.toJson());
    return (mk.$1, keyId, prev >= 0 ? prev : 0, base64Encode(st.dhPub));
  }

  Uint8List? _sessionKeyForMessage(ChatMessage m) {
    final targetCtr = m.keyId ?? 0;
    final fp = m.senderHint ?? _peer?.fingerprint ?? '';
    if (fp.isEmpty || targetCtr < 0) return null;
    ChatContact? peer;
    for (final c in _contacts) {
      if (c.fingerprint == fp) {
        peer = c;
        break;
      }
    }
    if (peer == null && _peer?.fingerprint == fp) {
      peer = _peer;
    }
    if (peer == null || _decodeCurveKeyB64(peer.publicKeyB64) == null) {
      return null;
    }
    final st = _ensureRatchet(peer);
    // detect identity/key mismatch
    if (fp.isNotEmpty && peer.fingerprint != fp) {
      final l = L10n.of(context);
      _ratchetWarning = l.shamellRatchetKeyMismatch;
      setState(() {});
      if (!_promptedForKeyChange) {
        _promptedForKeyChange = true;
        _showKeyChangePrompt();
      }
      return null;
    }
    if (m.senderDhPubB64 != null && m.senderDhPubB64!.isNotEmpty) {
      final newPeerDh = _decodeCurveKeyB64(m.senderDhPubB64);
      if (newPeerDh == null) return null;
      if (st.peerDhPubB64 != m.senderDhPubB64) {
        if (!_dhRatchet(st, newPeerDh, peerId: peer.id)) {
          return null;
        }
        st.peerDhPubB64 = m.senderDhPubB64!;
      }
    }
    // out-of-order guard
    if (targetCtr < st.recvCount &&
        !st.skipped.containsKey('${m.senderDhPubB64 ?? ''}:$targetCtr')) {
      final l = L10n.of(context);
      _ratchetWarning = l.shamellRatchetWindowWarning;
      setState(() {});
      return null;
    }
    // explicit window: allow up to +50 ahead
    if (targetCtr - st.recvCount > st.maxSkip) {
      final l = L10n.of(context);
      _ratchetWarning = l.shamellRatchetAheadWarning;
      setState(() {});
      return null;
    }
    // skipped cache lookup
    final skipKey = '${m.senderDhPubB64 ?? ''}:$targetCtr';
    if (st.skipped.containsKey(skipKey)) {
      final mkB64 = st.skipped.remove(skipKey);
      _store.saveRatchet(peer.id, st.toJson());
      if (mkB64 == null || mkB64.isEmpty) return null;
      final mk = _decodeCurveKeyB64(mkB64);
      return mk;
    }
    // advance recv chain
    var counter = st.recvCount;
    while (counter <= targetCtr) {
      final derived = _kdfChain(st.recvChainKey, counter);
      st.recvChainKey = derived.$2;
      if (counter == targetCtr) {
        st.recvCount = counter + 1;
        _store.saveRatchet(peer.id, st.toJson());
        _ratchetWarning = null;
        return derived.$1;
      } else {
        if (st.skipped.length >= st.maxSkip) {
          final firstKey = st.skipped.keys.first;
          st.skipped.remove(firstKey);
        }
        st.skipped['${m.senderDhPubB64 ?? ''}:$counter'] =
            base64Encode(derived.$1);
        counter += 1;
      }
    }
    _store.saveRatchet(peer.id, st.toJson());
    return null;
  }

  bool _dhRatchet(RatchetState st, Uint8List newPeerDh,
      {required String peerId}) {
    if (!_isCurveKey(st.dhPriv) || !_isCurveKey(newPeerDh)) {
      return false;
    }
    st.pn = st.recvCount;
    st.recvCount = 0;
    st.peerDhPub = newPeerDh;
    st.skipped.clear();
    late Uint8List dhSharedBytes;
    try {
      // derive new root + recv chain
      final dhShared = x25519.Box(
        myPrivateKey: x25519.PrivateKey(st.dhPriv),
        theirPublicKey: x25519.PublicKey(newPeerDh),
      ).sharedKey;
      dhSharedBytes = dhShared.asTypedList;
    } catch (_) {
      return false;
    }
    final newRoot = _kdfRoot(st.rootKey, dhSharedBytes);
    st.rootKey = newRoot.$1;
    st.recvChainKey = newRoot.$2;
    // rotate our DH
    final newDh = x25519.PrivateKey.generate();
    st.dhPriv = newDh.asTypedList;
    st.dhPub = newDh.publicKey.asTypedList;
    final dhShared2 = x25519.Box(
      myPrivateKey: newDh,
      theirPublicKey: x25519.PublicKey(newPeerDh),
    ).sharedKey;
    final sendRoot = _kdfRoot(st.rootKey, dhShared2.asTypedList);
    st.rootKey = sendRoot.$1;
    st.sendChainKey = sendRoot.$2;
    st.sendCount = 0;
    _store.saveRatchet(peerId, st.toJson());
    _ratchetWarning = null;
    setState(() {});
    return true;
  }

  (Uint8List, Uint8List) _kdfRoot(Uint8List rk, Uint8List dh) {
    final hmac = crypto.Hmac(crypto.sha256, rk);
    final combined = hmac.convert(dh).bytes;
    final k1 = crypto.sha256.convert([...combined, 0x01]).bytes;
    final k2 = crypto.sha256.convert([...combined, 0x02]).bytes;
    return (Uint8List.fromList(k1), Uint8List.fromList(k2));
  }

  (Uint8List, Uint8List) _kdfChain(Uint8List ck, int n) {
    final hmac = crypto.Hmac(crypto.sha256, ck);
    final mk = hmac.convert(utf8.encode('msg-$n')).bytes;
    final next = hmac.convert(utf8.encode('ck-$n')).bytes;
    return (Uint8List.fromList(mk), Uint8List.fromList(next));
  }

  void _showKeyChangePrompt() {
    if (!mounted) return;
    final l = L10n.of(context);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(l.shamellSessionChangedTitle),
              content: Text(l.shamellSessionChangedBody),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.shamellLater)),
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _resetSession();
                    },
                    child: Text(l.shamellResetSessionLabel)),
              ],
            ));
  }

  Uint8List? _safetyKeyBytesFromB64(String b64) {
    final raw = b64.trim();
    if (raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      // Signal-style X25519 identity keys are often encoded with 0x05 prefix.
      // Accept both formats to keep legacy compatibility while we migrate.
      if (bytes.length == 32) {
        return Uint8List.fromList(<int>[0x05, ...bytes]);
      }
      if (bytes.length == 33 && bytes[0] == 0x05) {
        return bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  String _formatSafetyDigits(String digits) {
    final raw = digits.replaceAll(RegExp(r'\\s+'), '');
    if (raw.isEmpty) return '';
    final parts = <String>[];
    for (var i = 0; i < raw.length; i += 5) {
      parts.add(raw.substring(i, (i + 5).clamp(0, raw.length)));
    }
    return parts.join(' ');
  }

  _SafetyNumber? _computeSafety() {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null) return null;
    final meId = me.id.trim();
    final peerId = peer.id.trim();
    if (meId.isEmpty || peerId.isEmpty) return null;

    final meKey = _safetyKeyBytesFromB64(me.publicKeyB64);
    final peerKey = _safetyKeyBytesFromB64(peer.publicKeyB64);
    if (meKey == null || peerKey == null) return null;

    try {
      final raw = shamellSafetyNumber(
        localIdentifier: meId,
        localIdentityKey: meKey,
        remoteIdentifier: peerId,
        remoteIdentityKey: peerKey,
      );
      return _SafetyNumber(_formatSafetyDigits(raw), raw);
    } catch (_) {
      return null;
    }
  }

  String? _computeSessionHash() {
    if (_me == null || _peer == null) return null;
    final a = _me!.fingerprint;
    final b = _peer!.fingerprint;
    final combined = (a.compareTo(b) <= 0) ? '$a$b' : '$b$a';
    return crypto.sha256.convert(utf8.encode('sess|$combined')).toString();
  }

  Future<void> _resetSession() async {
    final pid = _peer?.id;
    if (pid == null) return;
    _ratchets.remove(pid);
    _chains.remove(pid);
    _sessionKeys.remove(pid);
    _sessionKeysByFp.remove(_peer?.fingerprint ?? '');
    _cache[pid] = [];
    await _store.deleteRatchet(pid);
    await _store.saveSessionKey(pid, '');
    await _store.saveChain(pid, {});
    await _store.deleteSessionBootstrapMeta(pid);
    setState(() {
      _messages = [];
      _safetyNumber = _computeSafety();
      _sessionHash = _computeSessionHash();
      _ratchetWarning = null;
      _promptedForKeyChange = false;
    });
  }

  Future<bool> _authenticate() async {
    try {
      final auth = LocalAuthentication();
      // Fail closed: hidden chats require biometrics (no device-passcode fallback).
      final can = await auth.canCheckBiometrics;
      if (!can) return false;
      final l = L10n.of(context);
      return await auth.authenticate(
        localizedReason: l.shamellUnlockHiddenReason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  void _applyState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  bool get _isChatTabNearBottom {
    try {
      if (!_chatsTabScrollCtrl.hasClients) return true;
      final max = _chatsTabScrollCtrl.position.maxScrollExtent;
      final off = _chatsTabScrollCtrl.offset;
      return (max - off) < 220;
    } catch (_) {
      return true;
    }
  }

  bool get _isThreadNearBottom {
    try {
      if (!_threadScrollCtrl.hasClients) return true;
      final max = _threadScrollCtrl.position.maxScrollExtent;
      final off = _threadScrollCtrl.offset;
      return (max - off) < 180;
    } catch (_) {
      return true;
    }
  }

  void _onThreadScroll() {
    final near = _isThreadNearBottom;
    if (near == _threadNearBottom) return;
    if (!mounted) return;
    setState(() {
      _threadNearBottom = near;
      if (near) {
        _threadNewMessagesAwayCount = 0;
        _threadNewMessagesFirstId = null;
      }
    });
  }

  void _scrollChatTabToBottom({bool force = false, bool animated = true}) {
    try {
      if (!_chatsTabScrollCtrl.hasClients) return;
      if (!force && !_isChatTabNearBottom) return;
      final target = _chatsTabScrollCtrl.position.maxScrollExtent;
      if (animated) {
        _chatsTabScrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _chatsTabScrollCtrl.jumpTo(target);
      }
    } catch (_) {}
  }

  // ignore: unused_element
  void _scheduleChatTabScrollToBottom(
      {bool force = false, bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollChatTabToBottom(force: force, animated: animated);
    });
  }

  void _scrollThreadToBottom({bool force = false, bool animated = true}) {
    try {
      if (!_threadScrollCtrl.hasClients) return;
      if (!force && !_isThreadNearBottom) return;
      final target = _threadScrollCtrl.position.maxScrollExtent;
      if (animated) {
        _threadScrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _threadScrollCtrl.jumpTo(target);
      }
      if (!mounted) return;
      if (_threadNewMessagesAwayCount != 0 ||
          _threadNewMessagesFirstId != null ||
          !_threadNearBottom) {
        setState(() {
          _threadNewMessagesAwayCount = 0;
          _threadNewMessagesFirstId = null;
          _threadNearBottom = true;
        });
      }
    } catch (_) {}
  }

  void _scheduleThreadScrollToBottom(
      {bool force = false, bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollThreadToBottom(force: force, animated: animated);
    });
  }

  Future<void> _scrollToMessage(
    String messageId, {
    double alignment = 0.5,
    bool highlight = true,
  }) async {
    if (messageId.isEmpty) return;
    if (highlight) {
      _applyState(() {
        _highlightedMessageId = messageId;
      });
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
      if (!_threadScrollCtrl.hasClients) return;
      try {
        final maxScrollExtent = _threadScrollCtrl.position.maxScrollExtent;
        if (maxScrollExtent <= 0) return;
        final denom = max(1, _messages.length - 1);
        final ratio = (idx / denom).clamp(0.0, 1.0).toDouble();
        final target =
            (maxScrollExtent * ratio).clamp(0.0, maxScrollExtent).toDouble();
        _threadScrollCtrl.jumpTo(target);
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _jumpToFirstThreadNewMessage() async {
    var targetId = _threadNewMessagesFirstId;
    if ((targetId == null || targetId.isEmpty) &&
        _threadNewMessagesAwayCount > 0) {
      final myId = _me?.id;
      if (myId != null && myId.isNotEmpty && _messages.isNotEmpty) {
        var remaining = _threadNewMessagesAwayCount;
        for (var i = _messages.length - 1; i >= 0; i--) {
          final m = _messages[i];
          if (m.senderId == myId) continue;
          remaining--;
          if (remaining <= 0) {
            targetId = m.id;
            break;
          }
        }
      }
    }
    if (targetId == null || targetId.isEmpty) {
      _scrollThreadToBottom(force: true);
      return;
    }
    await _scrollToMessage(targetId, alignment: 0.18);
    if (!mounted) return;
    setState(() {
      _threadNewMessagesAwayCount = 0;
      _threadNewMessagesFirstId = null;
    });
  }

  Widget _buildThreadNewMessagesBar() {
    final count = _threadNewMessagesAwayCount;
    if (count <= 0 || _threadNearBottom) return const SizedBox.shrink();
    final l = L10n.of(context);
    final theme = Theme.of(context);
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
        onTap: _jumpToFirstThreadNewMessage,
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

  Future<void> _savePinnedMessages() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final map = <String, List<String>>{};
      _pinnedMessageIdsByPeer.forEach((peerId, ids) {
        if (ids.isEmpty) return;
        map[peerId] = ids.toList();
      });
      if (map.isEmpty) {
        await sp.remove('chat.pinned_messages');
      } else {
        await sp.setString('chat.pinned_messages', jsonEncode(map));
      }
    } catch (_) {}
  }

  Future<void> _persistPinnedChatOrder() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (_pinnedChatOrder.isEmpty) {
        await sp.remove('chat.pinned_chats');
      } else {
        await sp.setStringList('chat.pinned_chats', _pinnedChatOrder);
      }
    } catch (_) {}
  }

  Future<void> _persistArchivedGroups() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (_archivedGroupIds.isEmpty) {
        await sp.remove('chat.archived_groups');
        return;
      }
      await sp.setStringList(
        'chat.archived_groups',
        _archivedGroupIds
            .map((id) => id.toString().trim())
            .where((id) => id.isNotEmpty)
            .toList(),
      );
    } catch (_) {}
  }

  void _normalizePinnedChatOrder() {
    final pinnedIds = <String>[
      ..._contacts.where((c) => c.pinned).map((c) => c.id),
      ..._groups
          .where((g) => _groupPrefs[g.id]?.pinned ?? false)
          .map((g) => _groupUnreadKey(g.id)),
    ];
    if (pinnedIds.isEmpty) {
      // If groups haven't been loaded yet, avoid clearing the order because
      // pinned groups may arrive after prefs sync.
      if (_groups.isEmpty) {
        return;
      }
      if (_pinnedChatOrder.isNotEmpty) {
        _pinnedChatOrder = const <String>[];
        unawaited(_persistPinnedChatOrder());
      }
      return;
    }
    final filtered =
        _pinnedChatOrder.where((id) => pinnedIds.contains(id)).toList();
    for (final id in pinnedIds) {
      if (!filtered.contains(id)) {
        filtered.add(id);
      }
    }
    if (filtered.length != _pinnedChatOrder.length ||
        !_pinnedChatOrder.every((id) => filtered.contains(id))) {
      _pinnedChatOrder = filtered;
      unawaited(_persistPinnedChatOrder());
    }
  }

  void _updatePinnedChatOrderForPeer(String peerId, bool isPinned) {
    final current = List<String>.from(_pinnedChatOrder);
    current.removeWhere((id) => id == peerId);
    if (isPinned) {
      current.insert(0, peerId);
    }
    _pinnedChatOrder = current;
    unawaited(_persistPinnedChatOrder());
  }

  Future<void> _saveRecalledMessages() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (_recalledMessageIds.isEmpty) {
        await sp.remove('chat.recalled_messages');
      } else {
        await sp.setStringList(
          'chat.recalled_messages',
          _recalledMessageIds.toList(),
        );
      }
    } catch (_) {}
  }

  bool _isDraftEligibleChatId(String? chatId) {
    final id = (chatId ?? '').trim();
    if (id.isEmpty) return false;
    if (id == _ShamellChatPageState._subscriptionsPeerId) return false;
    return true;
  }

  void _schedulePersistDrafts() {
    _draftPersistTimer?.cancel();
    _draftPersistTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      try {
        await _store.saveDrafts(_draftTextByChatId);
      } catch (_) {}
    });
  }

  void _onChatComposerChanged() {
    if (_suppressDraftListener) return;
    final peerId = _peer?.id;
    if (!_isDraftEligibleChatId(peerId)) return;
    final id = peerId!.trim();
    final text = _msgCtrl.text;
    if (text.trim().isEmpty) {
      _draftTextByChatId.remove(id);
    } else {
      _draftTextByChatId[id] = text;
    }
    _schedulePersistDrafts();
  }

  Future<void> _stashActiveComposerDraft({bool persistNow = false}) async {
    final peerId = _peer?.id;
    if (!_isDraftEligibleChatId(peerId)) return;
    final id = peerId!.trim();
    _composerDraftByChatId[id] = _ShamellChatComposerDraft(
      text: _msgCtrl.text,
      attachmentBytes: _attachedBytes,
      attachmentMime: _attachedMime,
      attachmentName: _attachedName,
      replyToMessage: _replyToMessage,
    );
    final text = _msgCtrl.text;
    if (text.trim().isEmpty) {
      _draftTextByChatId.remove(id);
    } else {
      _draftTextByChatId[id] = text;
    }
    if (!persistNow) {
      _schedulePersistDrafts();
      return;
    }
    _draftPersistTimer?.cancel();
    try {
      await _store.saveDrafts(_draftTextByChatId);
    } catch (_) {}
  }

  void _restoreComposerDraftForChat(String chatId) {
    final id = chatId.trim();
    if (!_isDraftEligibleChatId(id)) return;
    final snap = _composerDraftByChatId[id];
    final text = snap?.text ?? _draftTextByChatId[id] ?? '';
    _suppressDraftListener = true;
    _msgCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _suppressDraftListener = false;
    _applyState(() {
      if (snap != null) {
        _attachedBytes = snap.attachmentBytes;
        _attachedMime = snap.attachmentMime;
        _attachedName = snap.attachmentName;
        _replyToMessage = snap.replyToMessage;
      } else {
        _replyToMessage = null;
      }
      _shamellVoiceMode = false;
      _composerPanel = _ShamellComposerPanel.none;
    });
  }

  Future<void> _clearDraftForChat(String chatId,
      {bool persistNow = false}) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _draftTextByChatId.remove(id);
    _composerDraftByChatId.remove(id);
    if (!persistNow) {
      _schedulePersistDrafts();
      return;
    }
    _draftPersistTimer?.cancel();
    try {
      await _store.saveDrafts(_draftTextByChatId);
    } catch (_) {}
  }

  Future<void> _exitChatThread() async {
    final peerId = _peer?.id;
    if (_isDraftEligibleChatId(peerId)) {
      await _stashActiveComposerDraft(persistNow: true);
    }
    if (!mounted) return;
    _suppressDraftListener = true;
    _msgCtrl.clear();
    _suppressDraftListener = false;
    _applyState(() {
      _peer = null;
      _activePeerId = null;
      _messageSelectionMode = false;
      _selectedMessageIds.clear();
      _attachedBytes = null;
      _attachedMime = null;
      _attachedName = null;
      _replyToMessage = null;
      _highlightedMessageId = null;
      _threadNearBottom = true;
      _threadNewMessagesAwayCount = 0;
      _threadNewMessagesFirstId = null;
      _shamellVoiceMode = false;
      _composerPanel = _ShamellComposerPanel.none;
    });
  }

  Future<void> _handleMessageRecalled(String messageId) async {
    bool pinnedChanged = false;
    _applyState(() {
      final keys = List<String>.from(_pinnedMessageIdsByPeer.keys);
      for (final peerId in keys) {
        final ids = _pinnedMessageIdsByPeer[peerId];
        if (ids == null || ids.isEmpty) continue;
        if (ids.contains(messageId)) {
          final next = Set<String>.from(ids)..remove(messageId);
          if (next.isEmpty) {
            _pinnedMessageIdsByPeer.remove(peerId);
          } else {
            _pinnedMessageIdsByPeer[peerId] = next;
          }
          pinnedChanged = true;
        }
      }
    });
    if (pinnedChanged) {
      await _savePinnedMessages();
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('favorites_items') ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final kept = <Map<String, dynamic>>[];
      bool favoritesChanged = false;
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final msgId = (m['msgId'] ?? '').toString();
        if (msgId == messageId) {
          favoritesChanged = true;
          continue;
        }
        kept.add(m);
      }
      if (favoritesChanged) {
        await sp.setString('favorites_items', jsonEncode(kept));
      }
    } catch (_) {}
  }

  bool _isMessagePinned(ChatMessage m) {
    final peerId = _peer?.id;
    if (peerId == null || peerId.isEmpty) return false;
    final set = _pinnedMessageIdsByPeer[peerId];
    if (set == null || set.isEmpty) return false;
    return set.contains(m.id);
  }

  Future<void> _togglePinMessage(ChatMessage m) async {
    final peer = _peer;
    if (peer == null) return;
    final peerId = peer.id;
    final current = _pinnedMessageIdsByPeer[peerId] ?? <String>{};
    final next = Set<String>.from(current);
    if (next.contains(m.id)) {
      next.remove(m.id);
    } else {
      next.add(m.id);
    }
    _applyState(() {
      if (next.isEmpty) {
        _pinnedMessageIdsByPeer.remove(peerId);
      } else {
        _pinnedMessageIdsByPeer[peerId] = next;
      }
    });
    await _savePinnedMessages();
  }

  bool _hasHiddenContacts() => _contacts.any((c) => c.hidden);
  // ignore: unused_element
  bool _hasArchivedThreads() =>
      _contacts.any((c) => c.archived) || _archivedGroupIds.isNotEmpty;

  Color _trustColor(ChatContact p) {
    if (p.verified) return Tokens.colorPayments; // green when verified
    return Tokens.accent.withValues(alpha: 0.8);
  }

  Widget _ratchetBanner() {
    if (_ratchetWarning == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_ratchetWarning!,
                  style: const TextStyle(color: Colors.red))),
          TextButton(onPressed: _resetSession, child: const Text('Reset'))
        ],
      ),
    );
  }

  Future<void> _scanQr() async {
    final l = L10n.of(context);
    final code = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          return SizedBox(
            height: 420,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Text(l.shamellScanContactQrTitle),
                Expanded(
                  child: MobileScanner(
                    fit: BoxFit.cover,
                    onDetect: (barcodes) {
                      if (barcodes.barcodes.isEmpty) return;
                      Navigator.of(ctx).pop(barcodes.barcodes.first.rawValue);
                    },
                  ),
                ),
              ],
            ),
          );
        });
    if (code == null) return;
    // 1) Shamell deep links (invite / official).
    try {
      final uri = Uri.parse(code);
      if (uri.scheme == 'shamell') {
        final host = uri.host.toLowerCase();
        if (host == 'invite') {
          final token = (uri.queryParameters['token'] ?? '').trim();
          if (token.isNotEmpty) {
            await _openChatFromInviteQr(token);
            return;
          }
        }
        if (host == 'friend') {
          if (!mounted) return;
          final msg = l.isArabic
              ? 'رمز الصديق القديم لم يعد مدعوماً. اطلب رمز دعوة جديد.'
              : 'Legacy friend QR is no longer supported. Ask for a new invite QR.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
          return;
        }
        if (host == 'official') {
          final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
          if (segs.isNotEmpty) {
            final id = segs.first;
            if (id.isNotEmpty) {
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OfficialAccountDeepLinkPage(
                    baseUrl: widget.baseUrl,
                    accountId: id,
                    onOpenChat: (peerId) {
                      if (peerId.isEmpty) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ShamellChatPage(
                            baseUrl: widget.baseUrl,
                            initialPeerId: peerId,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
              return;
            }
          }
        }
      }
    } catch (_) {}

    // 2) Accept raw invite tokens as QR payloads (no peer-id fallback).
    final raw = code.trim();
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(raw)) {
      await _openChatFromInviteQr(raw);
      return;
    }

    if (!mounted) return;
    final msg = l.isArabic
        ? 'رمز QR غير مدعوم. امسح رمز دعوة Shamell.'
        : 'Unsupported QR. Please scan a Shamell invite QR.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  void dispose() {
    unawaited(_stashActiveComposerDraft(persistNow: true));
    _draftPersistTimer?.cancel();
    _contactsIndexOverlayTimer?.cancel();
    _wsSub?.cancel();
    _grpWsSub?.cancel();
    _pushSub?.cancel();
    _service.close();
    _playerStateSub?.cancel();
    _shamellMorePanelCtrl.dispose();
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    try {
      _recorder.dispose();
    } catch (_) {}
    _voiceTicker?.cancel();
    _proximitySub?.cancel();
    _chatsTabScrollCtrl.dispose();
    _contactsTabScrollCtrl.dispose();
    _threadScrollCtrl.dispose();
    _peerIdCtrl.dispose();
    _msgCtrl.removeListener(_onChatComposerChanged);
    _msgCtrl.dispose();
    _displayNameCtrl.dispose();
    _chatSearchCtrl.dispose();
    _contactsSearchCtrl.dispose();
    _messageSearchCtrl.dispose();
    _messageSearchFocus.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  String _displayNameForChatId(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return '';
    final alias = _friendAliases[id]?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    for (final c in _contacts) {
      if (c.id == id) {
        final name = (c.name ?? '').trim();
        if (name.isNotEmpty) return name;
        break;
      }
    }
    return id;
  }

  Future<void> _sendTextMessage(String text) async {
    if (_me == null || _peer == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    try {
      final outbound = await _nextOutboundSendContext(_peer!);
      final outboundPeer = outbound.peer;
      _sessionHash ??= _computeSessionHash();
      final payload = <String, Object?>{
        "text": trimmed,
        "client_ts": DateTime.now().toIso8601String(),
        "sender_fp": _me?.fingerprint ?? '',
        "session_hash": _sessionHash,
      };
      final msg = await _service.sendMessage(
        me: _me!,
        peer: outboundPeer,
        plainText: jsonEncode(payload),
        expireAfterSeconds: _disappearing ? _disappearAfter.inSeconds : null,
        sealedSender: true,
        senderHint: _me?.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
      );
      _mergeMessages([msg]);
      _scheduleThreadScrollToBottom(force: true);
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendContactCard(String contactId) async {
    if (_me == null || _peer == null) return;
    final id = contactId.trim();
    if (id.isEmpty) return;
    final label = _displayNameForChatId(id);
    setState(() {
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    try {
      final outbound = await _nextOutboundSendContext(_peer!);
      final outboundPeer = outbound.peer;
      _sessionHash ??= _computeSessionHash();
      final payload = <String, Object?>{
        "text": label,
        "kind": "contact",
        "contact_id": id,
        "client_ts": DateTime.now().toIso8601String(),
        "sender_fp": _me?.fingerprint ?? '',
        "session_hash": _sessionHash,
      };
      final msg = await _service.sendMessage(
        me: _me!,
        peer: outboundPeer,
        plainText: jsonEncode(payload),
        expireAfterSeconds: _disappearing ? _disappearAfter.inSeconds : null,
        sealedSender: true,
        senderHint: _me?.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
      );
      _mergeMessages([msg]);
      _scheduleThreadScrollToBottom(force: true);
    } catch (e) {
      setState(() => _error = sanitizeExceptionForUi(error: e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openContactCardPicker() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FriendsPage(
          widget.baseUrl,
          mode: FriendsPageMode.picker,
        ),
      ),
    );
    final id = (selected ?? '').trim();
    if (id.isEmpty) return;
    await _sendContactCard(id);
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
      await _sendLocation(lat, lon, label: label.isEmpty ? null : label);
      return;
    }
    final txt = (chosen['text'] ?? '').toString().trim();
    if (txt.isEmpty) return;
    await _sendTextMessage(txt);
  }

  Widget _callHistoryCard() {
    return FutureBuilder<List<ChatCallLogEntry>>(
      future: _callStore.load(),
      builder: (context, snapshot) {
        final l = L10n.of(context);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final list = snapshot.data ?? const <ChatCallLogEntry>[];
        if (list.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              l.shamellNoCallsWithContact,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final recent = list.take(5).toList();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'سجل المكالمات' : 'Call history',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final e in recent) ...[
                _buildCallHistoryRow(e),
                const SizedBox(height: 6),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCallHistoryRow(ChatCallLogEntry e) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final isOut = e.direction == 'out';
    final icon = e.kind == 'video'
        ? (isOut ? Icons.videocam_outlined : Icons.videocam)
        : (isOut ? Icons.call_made : Icons.call_received);
    String status;
    if (!e.accepted) {
      status = l.shamellCallStatusMissedShort;
    } else if (e.duration.inSeconds <= 1) {
      status = l.shamellCallStatusShort;
    } else {
      final mm = e.duration.inMinutes;
      status = mm > 0 ? '${mm}m' : '${e.duration.inSeconds.remainder(60)}s';
    }
    final ts = e.ts.toLocal();
    final tsLabel =
        '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final peer = _peer;
    final canRedial = peer != null && peer.id == e.peerId;
    return Row(
      children: [
        Icon(icon, size: 18, color: isOut ? Tokens.colorPayments : Colors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${e.kind == 'video' ? l.shamellCallKindVideo : l.shamellCallKindVoice} • ${isOut ? l.shamellCallDirectionOutgoing : l.shamellCallDirectionIncoming} • $status',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          tsLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: .60),
          ),
        ),
        if (canRedial) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: l.shamellCallRedial,
            onPressed: () {
              if (!mounted) return;
              if (e.kind == 'video') {
                _startVoipCall(mode: 'video');
              } else {
                _startVoipCall(mode: 'audio');
              }
            },
          ),
        ],
      ],
    );
  }

  Future<void> _showPeerCallHistory(ChatContact peer) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final all = await _callStore.load();
    final list = all.where((e) => e.peerId == peer.id).toList();
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
                  l.shamellCallHistory,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  Text(
                    l.shamellNoCallsWithContact,
                    style: theme.textTheme.bodySmall,
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _buildCallHistoryRow(list[i]),
                    ),
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
    final me = _me;
    final peer = _peer;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isChatsList = _tabIndex == 0 && peer == null;
    final Color scaffoldBg = isDark
        ? theme.colorScheme.surface.withValues(alpha: .98)
        : (isChatsList ? ShamellPalette.background : Colors.white);
    Widget body;
    switch (_tabIndex) {
      case 0:
        body = _buildChatsTab(me, peer);
        break;
      case 1:
        body = _buildContactsTab(me, peer);
        break;
      case 2:
        body = _buildChannelTab();
        break;
      case 3:
      default:
        body = _buildProfileTab(me);
        break;
    }
    final bool isChatThread = _tabIndex == 0 && peer != null;
    final chatTitle = (_tabIndex == 0 && peer != null)
        ? _displayNameForPeer(peer)
        : (_tabIndex == 0
            ? (_showArchived
                ? (l.isArabic ? 'الدردشات المؤرشفة' : 'Archived Chats')
                : l.shamellTabChats)
            : 'Shamell');
    return Scaffold(
      appBar: AppBar(
        centerTitle: isChatThread,
        leading: isChatThread
            ? IconButton(
                tooltip: l.isArabic ? 'رجوع' : 'Back',
                icon:
                    Icon(l.isArabic ? Icons.chevron_right : Icons.chevron_left),
                onPressed: () => unawaited(_exitChatThread()),
              )
            : (isChatsList && _showArchived
                ? IconButton(
                    tooltip: l.isArabic ? 'رجوع' : 'Back',
                    icon: Icon(
                        l.isArabic ? Icons.chevron_right : Icons.chevron_left),
                    onPressed: () {
                      _applyState(() {
                        _showArchived = false;
                        _chatSearch = '';
                      });
                      _chatSearchCtrl.clear();
                      _resetArchivedPullDown();
                    },
                  )
                : null),
        title: (_tabIndex == 0 && peer != null)
            ? _buildChatAppBarTitle(peer)
            : Text(chatTitle),
        backgroundColor: scaffoldBg,
        elevation: 0.5,
        actions: [
          if (_tabIndex == 0 && peer != null)
            IconButton(
              tooltip: l.isArabic ? 'معلومات الدردشة' : 'Chat Info',
              icon: const Icon(Icons.more_horiz),
              onPressed: _showContactInfo,
            ),
          if (_tabIndex == 0 && _linkedOfficial != null)
            PopupMenuButton<String>(
              tooltip: l.isArabic
                  ? 'خيارات الحساب الرسمي'
                  : 'Official account options',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'feed') {
                  _openOfficialFeedForPeer();
                } else if (value == 'moments') {
                  _openOfficialMomentsForPeer();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'feed',
                  child: Text(
                    l.isArabic ? 'عرض الخلاصة الرسمية' : 'View official feed',
                  ),
                ),
                PopupMenuItem(
                  value: 'moments',
                  child: Text(
                    l.isArabic ? 'منشورات في اللحظات' : 'Moments posts',
                  ),
                ),
              ],
            ),
          if (_tabIndex == 0 && _linkedOfficial != null)
            IconButton(
              tooltip: _linkedOfficialFollowed
                  ? (l.isArabic
                      ? 'إلغاء متابعة الحساب الرسمي'
                      : 'Unfollow official account')
                  : (l.isArabic
                      ? 'متابعة الحساب الرسمي'
                      : 'Follow official account'),
              icon: Icon(
                _linkedOfficialFollowed
                    ? Icons.favorite
                    : Icons.favorite_border,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: _toggleOfficialFollowFromChat,
            ),
          if (_tabIndex == 0 && peer != null)
            IconButton(
              tooltip: l.isArabic ? 'الخلاصة الرسمية' : 'Official feed',
              icon: const Icon(Icons.campaign_outlined, size: 20),
              onPressed: _openOfficialFeedForPeer,
            ),
          if (isChatsList) ...[
            if (!_showArchived)
              IconButton(
                tooltip: l.isArabic ? 'بحث' : 'Search',
                onPressed: () => unawaited(_openGlobalSearchFromChats()),
                icon: const Icon(Icons.search),
              ),
            if (!_showArchived)
              Theme(
                data: theme.copyWith(dividerColor: Colors.white24),
                child: PopupMenuButton<String>(
                  tooltip: l.isArabic ? 'إضافة' : 'Add',
                  icon: const Icon(Icons.add),
                  position: PopupMenuPosition.under,
                  color: const Color(0xFF2C2C2C),
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    if (value == 'group') {
                      unawaited(_startNewGroupChat());
                    } else if (value == 'friend') {
                      if (_caps.friends) {
                        unawaited(_startNewChat());
                      } else {
                        final msg = l.isArabic
                            ? 'إضافة الأصدقاء غير متاحة حالياً. استخدم المسح لرمز QR.'
                            : 'Adding friends is not available right now. Use Scan (QR).';
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      }
                    } else if (value == 'scan') {
                      unawaited(_scanQr());
                    } else if (value == 'pay') {
                      if (_caps.payments) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MiniProgramPage(
                              id: 'payments',
                              baseUrl: widget.baseUrl,
                              walletId: '',
                              deviceId: _me?.id ?? '',
                              onOpenMod: _openMiniAppFromShamell,
                            ),
                          ),
                        );
                      } else {
                        final msg = l.isArabic
                            ? 'المدفوعات غير متاحة حالياً.'
                            : 'Payments are not available right now.';
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      }
                    } else if (value == 'mini_programs') {
                      unawaited(_openMiniProgramsHubFromChats());
                    }
                  },
                  itemBuilder: (ctx) {
                    Widget item(IconData icon, String label) {
                      return Row(
                        children: [
                          Icon(icon, size: 20, color: Colors.white),
                          const SizedBox(width: 12),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    }

                    final out = <PopupMenuEntry<String>>[];
                    void addItem(String value, IconData icon, String label) {
                      if (out.isNotEmpty) {
                        out.add(const PopupMenuDivider(height: 1));
                      }
                      out.add(
                        PopupMenuItem<String>(
                          value: value,
                          child: item(icon, label),
                        ),
                      );
                    }

                    addItem(
                      'group',
                      Icons.groups_outlined,
                      l.isArabic ? 'دردشة جماعية' : 'Group chat',
                    );
                    if (_caps.friends) {
                      addItem(
                        'friend',
                        Icons.person_add_alt_1_outlined,
                        l.isArabic ? 'إضافة صديق' : 'Add friend',
                      );
                    }
                    addItem(
                      'scan',
                      Icons.qr_code_scanner_outlined,
                      l.isArabic ? 'مسح' : 'Scan',
                    );
                    if (_caps.payments) {
                      addItem(
                        'pay',
                        Icons.account_balance_wallet_outlined,
                        l.isArabic ? 'المال' : 'Money',
                      );
                    }
                    if (_caps.miniPrograms) {
                      addItem(
                        'mini_programs',
                        Icons.grid_view_outlined,
                        l.miniAppsTitle,
                      );
                    }

                    return out;
                  },
                ),
              ),
          ],
        ],
      ),
      backgroundColor: scaffoldBg,
      body: SafeArea(child: body),
      bottomNavigationBar: widget.showBottomNav
          ? BottomNavigationBar(
              currentIndex: _tabIndex,
              onTap: (value) {
                if (value != 0 && _tabIndex == 0 && _peer != null) {
                  unawaited(_stashActiveComposerDraft(persistNow: true));
                }
                setState(() {
                  if (value != 0) {
                    _showArchived = false;
                    _chatSearch = '';
                    _archivedPullPinned = false;
                    _archivedPullPinnedHeight = 0;
                    _archivedPullDragging = false;
                    _archivedPullReveal = 0;
                    _archivedPullDragOffset = 0;
                  }
                  _tabIndex = value;
                });
                if (value != 0) {
                  _chatSearchCtrl.clear();
                }
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor:
                  isDark ? theme.colorScheme.primary : Tokens.colorPayments,
              unselectedItemColor: Colors.grey,
              backgroundColor: scaffoldBg,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: l.shamellTabChats,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.contacts_outlined),
                  label: l.shamellTabContacts,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.explore_outlined),
                  label: l.shamellTabChannel,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.person_outline),
                  label: l.shamellTabProfile,
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildContactsTab(ChatIdentity? me, ChatContact? peer) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : (Colors.grey[100] ?? Colors.white);

    final term = _contactsSearch.trim().toLowerCase();
    final bool filtering = term.isNotEmpty;

    String displayName(ChatContact c) {
      final name = _displayNameForPeer(c).trim();
      if (name.isNotEmpty) return name;
      return c.id;
    }

    bool matchesContact(ChatContact c) {
      if (term.isEmpty) return true;
      final name = displayName(c).toLowerCase();
      final id = c.id.toLowerCase();
      return name.contains(term) || id.contains(term);
    }

    String letterFor(String name) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return '#';
      final first = trimmed[0].toUpperCase();
      final code = first.codeUnitAt(0);
      if (code >= 65 && code <= 90) return first;
      return '#';
    }

    GlobalKey keyForLetter(String letter) {
      final clean = letter.trim();
      return _contactsLetterKeys.putIfAbsent(clean, () => GlobalKey());
    }

    void showIndexOverlay(String letter) {
      final clean = letter.trim();
      if (clean.isEmpty) return;
      _contactsIndexOverlayTimer?.cancel();
      _applyState(() {
        _contactsIndexOverlayLetter = clean;
      });
      _contactsIndexOverlayTimer = Timer(
        const Duration(milliseconds: 650),
        () {
          if (!mounted) return;
          _applyState(() {
            _contactsIndexOverlayLetter = null;
          });
        },
      );
    }

    Future<void> jumpIndexLetter({
      required String letter,
      required List<String> indexLetters,
      required Set<String> existingLetters,
      required bool hasStarred,
    }) async {
      final clean = letter.trim();
      if (clean.isEmpty) return;
      showIndexOverlay(clean);
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}

      if (clean == '↑') {
        if (_contactsTabScrollCtrl.hasClients) {
          await _contactsTabScrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }

      if (clean == '☆') {
        final ctx = _contactsStarredHeaderKey.currentContext;
        if (ctx != null && hasStarred) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            alignment: 0,
          );
        } else if (_contactsTabScrollCtrl.hasClients) {
          await _contactsTabScrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }

      String? target;
      if (existingLetters.contains(clean)) {
        target = clean;
      } else {
        final idx = indexLetters.indexOf(clean);
        if (idx != -1) {
          for (var i = idx; i < indexLetters.length; i++) {
            final cand = indexLetters[i];
            if (existingLetters.contains(cand)) {
              target = cand;
              break;
            }
          }
          if (target == null) {
            for (var i = idx; i >= 0; i--) {
              final cand = indexLetters[i];
              if (existingLetters.contains(cand)) {
                target = cand;
                break;
              }
            }
          }
        } else {
          for (final cand in indexLetters) {
            if (existingLetters.contains(cand)) {
              target = cand;
              break;
            }
          }
        }
      }
      if (target == null) return;
      final ctx = _contactsLetterKeys[target]?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          alignment: 0,
        );
      }
    }

    Widget buildIndexBar({
      required List<String> indexLetters,
      required Set<String> existingLetters,
      required bool hasStarred,
    }) {
      final isArabic = l.isArabic;
      final baseColor = theme.colorScheme.onSurface.withValues(alpha: .62);
      final mutedColor = theme.colorScheme.onSurface.withValues(alpha: .28);
      final bg = theme.colorScheme.surface.withValues(alpha: .35);
      return Positioned(
        top: 86,
        bottom: 16,
        left: isArabic ? 4 : null,
        right: isArabic ? null : 4,
        child: Builder(builder: (barCtx) {
          void handle(Offset local) {
            final ro = barCtx.findRenderObject();
            if (ro is! RenderBox) return;
            final h = ro.size.height;
            if (h <= 0) return;
            final itemH = h / indexLetters.length;
            final idx =
                (local.dy / itemH).floor().clamp(0, indexLetters.length - 1);
            final picked = indexLetters[idx];
            unawaited(
              jumpIndexLetter(
                letter: picked,
                indexLetters: indexLetters,
                existingLetters: existingLetters,
                hasStarred: hasStarred,
              ),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => handle(d.localPosition),
            onVerticalDragStart: (d) => handle(d.localPosition),
            onVerticalDragUpdate: (d) => handle(d.localPosition),
            child: Container(
              width: 24,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final letter in indexLetters)
                    Text(
                      letter,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: (letter == '↑' ||
                                letter == '☆' ||
                                existingLetters.contains(letter))
                            ? baseColor
                            : mutedColor,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      );
    }

    Widget? buildIndexOverlay() {
      final letter = (_contactsIndexOverlayLetter ?? '').trim();
      if (letter.isEmpty) return null;
      return Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    final contacts = _contacts
        .where((c) => c.id != _ShamellChatPageState._subscriptionsPeerId)
        .where(
          (c) => (!c.hidden || _showHidden) && (!c.blocked || _showBlocked),
        )
        .where(matchesContact)
        .toList()
      ..sort((a, b) =>
          displayName(a).toLowerCase().compareTo(displayName(b).toLowerCase()));

    final starredContacts = contacts.where((c) => c.starred).toList();
    final others = contacts.where((c) => !c.starred).toList();

    final Map<String, List<ChatContact>> byLetter =
        <String, List<ChatContact>>{};
    for (final c in others) {
      final letter = letterFor(displayName(c));
      byLetter.putIfAbsent(letter, () => <ChatContact>[]).add(c);
    }

    final letters = byLetter.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });

    final existingLetters = byLetter.keys.toSet();
    final indexLetters = <String>[
      '↑',
      '☆',
      for (var code = 65; code <= 90; code++) String.fromCharCode(code),
      '#',
    ];

    final bool showIndexBar = !filtering &&
        (starredContacts.isNotEmpty || existingLetters.isNotEmpty);

    Widget buildContactTile(ChatContact c) {
      final bool bulkSelected =
          _selectionMode && _selectedChatIds.contains(c.id);
      Widget leading;
      if (_selectionMode) {
        leading = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: bulkSelected,
              onChanged: (_) => _toggleChatSelected(c.id),
            ),
            CircleAvatar(
              radius: 20,
              backgroundColor: c.verified
                  ? Tokens.colorPayments.withValues(alpha: .20)
                  : Tokens.accent.withValues(alpha: .15),
              child: Text(
                displayName(c).substring(0, 1).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      } else {
        leading = CircleAvatar(
          radius: 20,
          backgroundColor: c.verified
              ? Tokens.colorPayments.withValues(alpha: .20)
              : Tokens.accent.withValues(alpha: .15),
          child: Text(
            displayName(c).substring(0, 1).toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }

      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: leading,
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName(c),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (c.verified)
              const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Icon(
                  Icons.verified,
                  size: 16,
                  color: Tokens.colorPayments,
                ),
              ),
          ],
        ),
        onTap: () {
          if (_selectionMode) {
            _toggleChatSelected(c.id);
          } else {
            _switchPeer(c);
          }
        },
        onLongPress: () {
          if (_selectionMode) {
            _toggleChatSelected(c.id);
          } else {
            unawaited(_onChatLongPress(c));
          }
        },
      );
    }

    final indexOverlay = buildIndexOverlay();

    return Container(
      color: bgColor,
      child: RefreshIndicator(
        onRefresh: () async => _pullInbox(),
        child: Stack(
          children: [
            ListView(
              controller: _contactsTabScrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    const Icon(Icons.contacts_outlined, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      l.shamellTabContacts,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ShamellSearchBar(
                  controller: _contactsSearchCtrl,
                  hintText: l.isArabic ? 'بحث' : 'Search',
                  onChanged: (v) {
                    _applyState(() {
                      _contactsSearch = v;
                    });
                  },
                ),
                if (!filtering) ...[
                  const SizedBox(height: 10),
                  Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_add_alt_1_outlined,
                            size: 22),
                        dense: true,
                        title: Text(
                          l.shamellContactsNewFriends,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          l.shamellContactsNewFriendsSubtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 12),
                        ),
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FriendsPage(widget.baseUrl),
                            ),
                          );
                          if (result is String && result.trim().isNotEmpty) {
                            _applyState(() {
                              _tabIndex = 0;
                            });
                            // ignore: unawaited_futures
                            _resolvePeer(presetId: result.trim());
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.groups_outlined, size: 22),
                        dense: true,
                        title: Text(
                          l.shamellContactsGroups,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          l.shamellContactsGroupsSubtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 12),
                        ),
                        onTap: () {
                          Perf.action(
                              'official_open_directory_from_contacts_service_tile');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  GroupChatsPage(baseUrl: widget.baseUrl),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.sell_outlined, size: 22),
                        dense: true,
                        title: Text(
                          l.isArabic ? 'الوسوم' : 'Tags',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          l.isArabic
                              ? 'نظّم جهات الاتصال باستخدام الوسوم'
                              : 'Organize contacts with tags',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FriendTagsPage(baseUrl: widget.baseUrl),
                            ),
                          );
                        },
                      ),
                      if (_caps.officialAccounts)
                        ListTile(
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.verified_outlined, size: 22),
                              if (_officialPeerUnreadFeeds.isNotEmpty)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Icon(
                                    Icons.brightness_1,
                                    size: 8,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                          dense: true,
                          title: Text(
                            l.shamellContactsServiceAccounts,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            l.shamellContactsServiceAccountsSubtitle,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 12),
                          ),
                          onTap: () async {
                            if (!await _ensureOfficialAuthSession()) return;
                            Perf.action(
                                'official_open_directory_from_contacts_service_tile');
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OfficialAccountsPage(
                                  baseUrl: widget.baseUrl,
                                  onOpenChat: (peerId) {
                                    if (peerId.isEmpty) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ShamellChatPage(
                                          baseUrl: widget.baseUrl,
                                          initialPeerId: peerId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ListTile(
                        leading: const Icon(Icons.people_outline, size: 22),
                        dense: true,
                        title: Text(
                          l.shamellContactsPeopleP2P,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          l.shamellContactsPeopleP2PSubtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 12),
                        ),
                        onTap: _openPeopleP2PFromShamell,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      l.shamellContactsShamellServicesTitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .75),
                          ),
                    ),
                  ),
                  _buildServiceAccountsSection(l),
                  const SizedBox(height: 12),
                ],
                if (contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18.0),
                    child: Column(
                      children: [
                        Icon(
                          filtering ? Icons.search_off : Icons.person_off,
                          size: 34,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .35),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          filtering
                              ? (l.isArabic ? 'لا توجد نتائج' : 'No results')
                              : (l.isArabic
                                  ? 'لا توجد جهات اتصال'
                                  : 'No contacts yet'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .78),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          filtering
                              ? (l.isArabic
                                  ? 'جرّب البحث بكلمة أخرى.'
                                  : 'Try a different search.')
                              : (l.isArabic
                                  ? 'أضف أصدقاء لبدء الدردشة.'
                                  : 'Add friends to start chatting.'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .55),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (starredContacts.isNotEmpty) ...[
                    Padding(
                      key: _contactsStarredHeaderKey,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Text(
                        l.isArabic ? 'الأصدقاء المميزون' : 'Starred friends',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .75),
                        ),
                      ),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: starredContacts.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 68),
                      itemBuilder: (_, i) =>
                          buildContactTile(starredContacts[i]),
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (final letter in letters) ...[
                    Padding(
                      key: keyForLetter(letter),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Text(
                        letter,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .60),
                        ),
                      ),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount:
                          (byLetter[letter] ?? const <ChatContact>[]).length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 68),
                      itemBuilder: (_, i) => buildContactTile(
                          (byLetter[letter] ?? const <ChatContact>[])[i]),
                    ),
                    const SizedBox(height: 2),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            if (showIndexBar)
              buildIndexBar(
                indexLetters: indexLetters,
                existingLetters: existingLetters,
                hasStarred: starredContacts.isNotEmpty,
              ),
            if (indexOverlay != null) indexOverlay,
          ],
        ),
      ),
    );
  }

  Widget _buildServiceAccountsSection(L10n l) {
    final children = <Widget>[];
    if (_caps.officialAccounts) {
      children.add(
        ListTile(
          dense: true,
          leading: const Icon(Icons.local_fire_department_outlined),
          title: Text(
            l.isArabic
                ? 'الحسابات الرائجة في اللحظات'
                : 'Hot in Moments accounts',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            l.isArabic
                ? 'عرض حسابات الخدمات الرائجة في اللحظات'
                : 'See service accounts that are hot in Moments',
            style: const TextStyle(fontSize: 12),
          ),
          trailing:
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          onTap: () async {
            if (!await _ensureOfficialAuthSession()) return;
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OfficialAccountsPage(
                  baseUrl: widget.baseUrl,
                  initialCityFilter: null,
                  initialKindFilter: 'service',
                ),
              ),
            );
          },
        ),
      );
    }
    if (_caps.bus) {
      children.add(
        ListTile(
          dense: true,
          leading: const CircleAvatar(
            radius: 20,
            child: Icon(Icons.directions_bus_filled_outlined, size: 20),
          ),
          title: Text(
            l.isArabic ? 'Shamell Bus' : 'Shamell Bus',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            l.isArabic
                ? 'احجز رحلة أو راجع حجوزاتك'
                : 'Book a trip or review your bookings',
            style: const TextStyle(fontSize: 12),
          ),
          onTap: _openBusService,
        ),
      );
    }
    if (_caps.payments) {
      children.add(
        ListTile(
          dense: true,
          leading: const CircleAvatar(
            radius: 20,
            child: Icon(Icons.account_balance_wallet_outlined, size: 20),
          ),
          title: Text(
            l.isArabic ? 'Shamell Pay' : 'Shamell Pay',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            l.isArabic
                ? 'تحويل سريع ورؤية المعاملات'
                : 'Quick transfers and transaction history',
            style: const TextStyle(fontSize: 12),
          ),
          onTap: _openPayService,
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return FormSection(
      title: l.isArabic ? 'حسابات الخدمات' : 'Service accounts',
      subtitle: l.isArabic
          ? 'اختصارات للباص والمدفوعات داخل Shamell'
          : 'Shortcuts for bus and payments inside Shamell',
      children: children,
    );
  }

  void _openBusService() {
    final l = L10n.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _ServiceSheet(
          title: l.isArabic ? 'Shamell Bus' : 'Shamell Bus',
          actions: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.directions_bus_filled_outlined),
              minLeadingWidth: 32,
              title: Text(
                l.busTitle,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              trailing:
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MiniProgramPage(
                      id: 'bus',
                      baseUrl: widget.baseUrl,
                      walletId: '',
                      deviceId: _me?.id ?? '',
                      onOpenMod: _openMiniAppFromShamell,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              minLeadingWidth: 32,
              title: Text(
                l.menuTrips,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              trailing:
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                _openMiniAppFromShamell('bus');
              },
            ),
          ],
        );
      },
    );
  }

  void _openPayService() {
    final l = L10n.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _ServiceSheet(
          title: l.isArabic ? 'Shamell Pay' : 'Shamell Pay',
          actions: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.qr_code_scanner),
              minLeadingWidth: 32,
              title: Text(
                l.qaScanPay,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              trailing:
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MiniProgramPage(
                      id: 'payments',
                      baseUrl: widget.baseUrl,
                      walletId: '',
                      deviceId: _me?.id ?? '',
                      onOpenMod: _openMiniAppFromShamell,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.swap_horiz),
              minLeadingWidth: 32,
              title: Text(
                l.qaP2P,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              trailing:
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentsPage(
                      widget.baseUrl,
                      '',
                      'shamell',
                      contextLabel: 'Shamell Pay',
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  int _archivedThreadsCount() {
    final archivedContacts = _contacts.where((c) =>
        c.archived && c.id != _ShamellChatPageState._subscriptionsPeerId);
    final archivedGroups =
        _groups.where((g) => _archivedGroupIds.contains(g.id));
    return archivedContacts.length + archivedGroups.length;
  }

  bool _archivedHasUnread() {
    final archivedContacts = _contacts.where((c) =>
        c.archived && c.id != _ShamellChatPageState._subscriptionsPeerId);
    for (final c in archivedContacts) {
      if ((_unread[c.id] ?? 0) != 0) return true;
    }
    for (final g in _groups) {
      if (!_archivedGroupIds.contains(g.id)) continue;
      if ((_unread[_groupUnreadKey(g.id)] ?? 0) != 0) return true;
    }
    return false;
  }

  void _resetArchivedPullDown() {
    if (!_archivedPullPinned &&
        !_archivedPullDragging &&
        _archivedPullReveal == 0 &&
        _archivedPullDragOffset == 0 &&
        _archivedPullPinnedHeight == 0) {
      return;
    }
    _applyState(() {
      _archivedPullPinned = false;
      _archivedPullPinnedHeight = 0;
      _archivedPullDragging = false;
      _archivedPullReveal = 0;
      _archivedPullDragOffset = 0;
    });
  }

  Future<void> _openMiniProgramsHubFromChats({
    bool openPinnedManage = false,
    bool focusSearch = false,
  }) async {
    _resetArchivedPullDown();
    if (!_caps.miniPrograms) {
      final l = L10n.of(context);
      final msg = l.isArabic
          ? 'البرامج المصغّرة غير متاحة حالياً.'
          : 'Mini-programs are not available right now.';
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    final focusSearchOnStart = focusSearch && !openPinnedManage;
    try {
      final sp = await SharedPreferences.getInstance();
      final walletId = sp.getString('wallet_id') ?? '';
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MiniProgramsDiscoverPage(
            baseUrl: widget.baseUrl,
            walletId: walletId,
            deviceId: _me?.id ?? '',
            onOpenMod: _openMiniAppFromShamell,
            openPinnedManageOnStart: openPinnedManage,
            autofocusSearchOnStart: focusSearchOnStart,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MiniProgramsDiscoverPage(
            baseUrl: widget.baseUrl,
            walletId: '',
            deviceId: _me?.id ?? '',
            onOpenMod: _openMiniAppFromShamell,
            openPinnedManageOnStart: openPinnedManage,
            autofocusSearchOnStart: focusSearchOnStart,
          ),
        ),
      );
    } finally {
      if (mounted) {
        _resetArchivedPullDown();
        unawaited(_loadTopMiniApps());
      }
    }
  }

  Future<void> _openGlobalSearchFromChats() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final walletId = sp.getString('wallet_id') ?? '';
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GlobalSearchPage(
            baseUrl: widget.baseUrl,
            walletId: walletId,
            deviceId: _me?.id ?? '',
            onOpenMod: _openMiniAppFromShamell,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GlobalSearchPage(
            baseUrl: widget.baseUrl,
            walletId: '',
            deviceId: _me?.id ?? '',
            onOpenMod: _openMiniAppFromShamell,
          ),
        ),
      );
    }
  }

  bool _onChatsTabScrollNotification(ScrollNotification n) {
    if (_archivedPullAdjusting) return false;

    final canShowPanel = !_showArchived && _chatSearch.isEmpty;
    if (!canShowPanel) {
      _resetArchivedPullDown();
      return false;
    }

    if (_archivedPullPinned) {
      final pinnedHeight = _archivedPullPinnedHeight > 0
          ? _archivedPullPinnedHeight
          : _archivedPullMaxHeight;
      final pixels = n.metrics.pixels;
      if (pixels >= pinnedHeight && _chatsTabScrollCtrl.hasClients) {
        final off = _chatsTabScrollCtrl.offset;
        if (off >= pinnedHeight) {
          _archivedPullAdjusting = true;
          _chatsTabScrollCtrl.jumpTo(off - pinnedHeight);
          _archivedPullAdjusting = false;
        }
        _resetArchivedPullDown();
      }
      return false;
    }

    if (n is ScrollStartNotification) {
      if (n.dragDetails != null) {
        _applyState(() {
          _archivedPullDragging = true;
          _archivedPullDragOffset = 0;
          _archivedPullReveal = 0;
        });
      }
      return false;
    }

    if (n is ScrollUpdateNotification) {
      if (n.dragDetails == null) return false;
      if (n.metrics.pixels > n.metrics.minScrollExtent) {
        _resetArchivedPullDown();
        return false;
      }
      final delta = n.scrollDelta ?? 0;
      if (delta < 0) {
        _archivedPullDragOffset += -delta;
      } else if (delta > 0) {
        _archivedPullDragOffset -= delta;
      }
      if (_archivedPullDragOffset < 0) _archivedPullDragOffset = 0;
      final next =
          _archivedPullDragOffset.clamp(0.0, _pullDownMaxHeight).toDouble();
      if (next != _archivedPullReveal || !_archivedPullDragging) {
        _applyState(() {
          _archivedPullDragging = true;
          _archivedPullReveal = next;
        });
      }
      return false;
    }

    if (n is OverscrollNotification) {
      // Ignore non-drag overscroll (e.g. iOS bounce/ballistic), otherwise the
      // pull-down panel can open by itself without explicit user gesture.
      if (n.dragDetails == null) return false;
      final o = n.overscroll;
      if (o < 0) {
        _archivedPullDragOffset += -o;
      } else if (o > 0) {
        _archivedPullDragOffset -= o;
      }
      if (_archivedPullDragOffset < 0) _archivedPullDragOffset = 0;
      final next =
          _archivedPullDragOffset.clamp(0.0, _pullDownMaxHeight).toDouble();
      if (next != _archivedPullReveal || !_archivedPullDragging) {
        _applyState(() {
          _archivedPullDragging = true;
          _archivedPullReveal = next;
        });
      }
      return false;
    }

    if (n is ScrollEndNotification) {
      // Only finalize pin/reveal after an actual drag sequence.
      if (!_archivedPullDragging) {
        _resetArchivedPullDown();
        return false;
      }
      final reveal = _archivedPullReveal;
      if (reveal <= 0) {
        _resetArchivedPullDown();
        return false;
      }
      final hasArchived = _archivedThreadsCount() > 0;
      if (reveal > _archivedPullMaxHeight) {
        unawaited(HapticFeedback.selectionClick());
        _applyState(() {
          _archivedPullPinned = true;
          _archivedPullPinnedHeight = _pullDownMaxHeight;
          _archivedPullDragging = false;
          _archivedPullReveal = _pullDownMaxHeight;
          _archivedPullDragOffset = _pullDownMaxHeight;
        });
      } else if (hasArchived && reveal >= _archivedPullMaxHeight * 0.85) {
        unawaited(HapticFeedback.selectionClick());
        _applyState(() {
          _archivedPullPinned = true;
          _archivedPullPinnedHeight = _archivedPullMaxHeight;
          _archivedPullDragging = false;
          _archivedPullReveal = _archivedPullMaxHeight;
          _archivedPullDragOffset = _archivedPullMaxHeight;
        });
      } else {
        _resetArchivedPullDown();
      }
      return false;
    }

    return false;
  }

  Widget _pullDownArchivedChatsEntry() {
    final archivedCount = _archivedThreadsCount();
    if (_showArchived || _chatSearch.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final pinnedHeight = _archivedPullPinnedHeight > 0
        ? _archivedPullPinnedHeight
        : _archivedPullMaxHeight;
    final target = _archivedPullPinned ? pinnedHeight : _archivedPullReveal;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    ShamellLeadingIcon miniIcon(String appId) {
      final id = appId.trim().toLowerCase();
      if (id.contains('pay') ||
          id.contains('wallet') ||
          id.contains('payment')) {
        return const ShamellLeadingIcon(
          icon: Icons.account_balance_wallet_outlined,
          background: Tokens.colorPayments,
          foreground: Colors.white,
          size: 44,
          iconSize: 20,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        );
      }
      if (id.contains('bus') ||
          id.contains('ride') ||
          id.contains('mobility') ||
          id.contains('transport')) {
        return const ShamellLeadingIcon(
          icon: Icons.directions_bus_filled_outlined,
          background: Tokens.colorBus,
          foreground: Colors.white,
          size: 44,
          iconSize: 20,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        );
      }
      final local = miniAppById(appId);
      return ShamellLeadingIcon(
        icon: local?.icon ?? Icons.widgets_outlined,
        background: const Color(0xFF64748B),
        foreground: Colors.white,
        size: 44,
        iconSize: 20,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      );
    }

    String miniTitle(String appId) {
      final local = miniAppById(appId);
      final t = local?.title(isArabic: l.isArabic).trim();
      if (t != null && t.isNotEmpty) return t;
      final raw = appId.trim();
      if (raw.length <= 12) return raw;
      return '${raw.substring(0, 10)}…';
    }

    final hasArchived = archivedCount > 0;
    final countLabel = archivedCount > 99 ? '99+' : '$archivedCount';
    final hasUnread = hasArchived && _archivedHasUnread();
    const shamellUnreadRed = Color(0xFFFA5151);

    final topRow = Material(
      color: theme.colorScheme.surface,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: .06),
          child: Icon(
            hasArchived ? Icons.archive_outlined : Icons.grid_view_outlined,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: .75),
          ),
        ),
        title: Text(
          hasArchived
              ? (l.isArabic ? 'الدردشات المؤرشفة' : 'Archived Chats')
              : l.miniAppsTitle,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: hasArchived
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasUnread)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: shamellUnreadRed,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  if (hasUnread) const SizedBox(width: 6),
                  Text(
                    countLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: .60),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  chevron(),
                ],
              )
            : chevron(),
        onTap: () {
          if (hasArchived) {
            _applyState(() {
              _showArchived = true;
            });
            _resetArchivedPullDown();
            return;
          }
          unawaited(_openMiniProgramsHubFromChats());
        },
      ),
    );

    final idsRaw = _pullDownMiniProgramIds.isNotEmpty
        ? _pullDownMiniProgramIds
        : _topMiniApps.map((m) => m.id).toList();
    final ordered = <String>[];
    final seen = <String>{};
    for (final id in idsRaw) {
      final clean = id.trim();
      if (clean.isEmpty) continue;
      if (seen.add(clean)) ordered.add(clean);
    }
    if (ordered.isEmpty) {
      ordered.addAll(const ['payments', 'bus']);
    }
    final displayIds = ordered.take(7).toList();
    final hasMiniBadges =
        displayIds.any(_pullDownMiniProgramUpdateBadges.contains);

    final miniPanel = Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShamellSearchBar(
              hintText: l.isArabic ? 'بحث' : 'Search',
              readOnly: true,
              margin: EdgeInsets.zero,
              onTap: () {
                _resetArchivedPullDown();
                unawaited(_openGlobalSearchFromChats());
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  l.miniAppsTitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
                if (hasMiniBadges) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: shamellUnreadRed,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _resetArchivedPullDown();
                    unawaited(
                        _openMiniProgramsHubFromChats(openPinnedManage: true));
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l.isArabic ? 'تعديل' : 'Edit',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _resetArchivedPullDown();
                    unawaited(_openMiniProgramsHubFromChats());
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(left: 6, right: 0),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.isArabic ? 'المزيد' : 'More',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .65),
                        ),
                      ),
                      const SizedBox(width: 4),
                      chevron(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (ctx) {
                const columns = 4;
                const gap = 10.0;

                final tiles = <({String? id, bool isMore})>[
                  for (var i = 0; i < columns * 2; i++)
                    (id: null, isMore: false),
                ];
                for (var i = 0; i < displayIds.length && i < 7; i++) {
                  tiles[i] = (id: displayIds[i], isMore: false);
                }
                tiles[7] = (id: null, isMore: true);

                Widget tile({
                  required String label,
                  required Widget icon,
                  required VoidCallback onTap,
                  VoidCallback? onLongPress,
                  ValueChanged<Offset>? onTapDownAt,
                }) {
                  return InkWell(
                    onTapDown: onTapDownAt == null
                        ? null
                        : (d) => onTapDownAt(d.globalPosition),
                    onTap: onTap,
                    onLongPress: onLongPress,
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(height: 6),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .80),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                Widget tileAt(int index) {
                  if (index < 0 || index >= tiles.length) {
                    return const SizedBox.shrink();
                  }
                  final item = tiles[index];
                  if (item.isMore) {
                    return tile(
                      label: l.isArabic ? 'المزيد' : 'More',
                      icon: ShamellLeadingIcon(
                        icon: Icons.more_horiz,
                        background:
                            theme.colorScheme.onSurface.withValues(alpha: .08),
                        foreground:
                            theme.colorScheme.onSurface.withValues(alpha: .75),
                        size: 44,
                        iconSize: 20,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(12)),
                      ),
                      onTap: () {
                        _resetArchivedPullDown();
                        unawaited(_openMiniProgramsHubFromChats());
                      },
                    );
                  }
                  final id = (item.id ?? '').trim();
                  final showBadge =
                      _pullDownMiniProgramUpdateBadges.contains(id);
                  final icon = Stack(
                    clipBehavior: Clip.none,
                    children: [
                      miniIcon(id),
                      if (showBadge)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: shamellUnreadRed,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                  Offset? downPos;
                  return tile(
                    label: miniTitle(id),
                    icon: icon,
                    onTapDownAt: (pos) => downPos = pos,
                    onTap: () {
                      _resetArchivedPullDown();
                      unawaited(_markPullDownMiniProgramReleaseSeen(id));
                      _openMiniAppFromShamell(id);
                    },
                    onLongPress: () => unawaited(
                      _openPullDownMiniProgramActions(
                        id,
                        globalPosition: downPos,
                      ),
                    ),
                  );
                }

                final rows = <Widget>[];
                for (var r = 0; r < 2; r++) {
                  final base = r * columns;
                  rows.add(
                    Row(
                      children: [
                        for (var c = 0; c < columns; c++) ...[
                          Expanded(child: tileAt(base + c)),
                          if (c != columns - 1) const SizedBox(width: gap),
                        ],
                      ],
                    ),
                  );
                  if (r == 0) rows.add(const SizedBox(height: 14));
                }
                return Column(children: rows);
              },
            ),
          ],
        ),
      ),
    );

    final panel = Column(
      children: [
        SizedBox(height: _archivedPullMaxHeight, child: topRow),
        SizedBox(height: _miniProgramsPullMaxHeight, child: miniPanel),
      ],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: _archivedPullDragging
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      builder: (ctx, value, child) {
        final factor = (value / _pullDownMaxHeight).clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: factor,
            child: child,
          ),
        );
      },
      child: SizedBox(height: _pullDownMaxHeight, child: panel),
    );
  }

  Widget _buildChatsTab(ChatIdentity? me, ChatContact? peer) {
    if (peer != null) {
      return _chatCard(me, peer);
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;
    return Container(
      color: bgColor,
      child: RefreshIndicator(
        notificationPredicate: (n) {
          final canShowPullDown = !_showArchived && _chatSearch.isEmpty;
          if (canShowPullDown) return false;
          return n.depth == 0;
        },
        onRefresh: () async => _pullInbox(),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onChatsTabScrollNotification,
          child: ListView(
            controller: _chatsTabScrollCtrl,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              _pullDownArchivedChatsEntry(),
              _multiDeviceBanner(),
              _conversationsCard(),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _lastCallBanner(ChatContact peer) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final all = _lastCallsCache ?? const <ChatCallLogEntry>[];
    final list = all.where((e) => e.peerId == peer.id).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    list.sort((a, b) => b.ts.compareTo(a.ts));
    final last = list.first;
    final isOut = last.direction == 'out';
    final kindLabel =
        last.kind == 'video' ? l.shamellCallKindVideo : l.shamellCallKindVoice;
    String status;
    if (!last.accepted) {
      status = l.shamellCallStatusMissedShort;
    } else if (last.duration.inMinutes > 0) {
      status = '${last.duration.inMinutes}m';
    } else {
      status = '${last.duration.inSeconds.remainder(60)}s';
    }
    final ts = last.ts.toLocal();
    final tsLabel =
        '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final dirLabel =
        isOut ? l.shamellCallDirectionOutgoing : l.shamellCallDirectionIncoming;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPeerCallHistory(peer),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.call_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.shamellLastCallBannerPrefix,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$kindLabel • $dirLabel • $status',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tsLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .60),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _multiDeviceBanner() {
    if (!_hasOtherDevices) return const SizedBox.shrink();
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final label = _otherDeviceLabel;
    final title = l.isArabic
        ? 'شامل نشط أيضاً على جهاز مرتبط آخر'
        : 'Shamell is also active on a linked device';
    final subtitle = label != null && label.isNotEmpty
        ? (l.isArabic ? 'الجهاز الآخر: $label' : 'Other device: $label')
        : (l.isArabic
            ? 'يمكنك إدارة الأجهزة المرتبطة وتسجيل الخروج من شاشة الأجهزة.'
            : 'You can manage linked devices and log out remote sessions from the Devices screen.');
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Icon(
              Icons.devices_other_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .60),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.isArabic ? 'إدارة الأجهزة' : 'Manage devices',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: .35),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DevicesPage(baseUrl: widget.baseUrl),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 12),
        ],
      ),
    );
  }

  Future<void> _handleScanPayload(String raw) async {
    final l = L10n.of(context);
    final s = raw.trim();
    if (s.isEmpty) return;
    final uri = Uri.tryParse(s);
    if (uri != null && uri.scheme.toLowerCase() == 'shamell') {
      final host = uri.host.toLowerCase();
      if (host == 'invite') {
        final token = (uri.queryParameters['token'] ?? '').trim();
        if (token.isNotEmpty) {
          await _openChatFromInviteQr(token);
          return;
        }
      } else if (host == 'friend') {
        if (!mounted) return;
        final msg = l.isArabic
            ? 'رمز الصديق القديم لم يعد مدعوماً. اطلب رمز دعوة جديد.'
            : 'Legacy friend QR is no longer supported. Ask for a new invite QR.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      } else if (host == 'device_login') {
        final token = (uri.queryParameters['token'] ?? '').trim();
        final label = (uri.queryParameters['label'] ?? '').trim();
        if (token.isNotEmpty) {
          await _confirmDeviceLogin(token,
              label: label.isNotEmpty ? label : null);
          return;
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.shamellUnrecognizedQr),
      ),
    );
  }

  Future<void> _openChatFromInviteQr(String rawToken) async {
    final l = L10n.of(context);
    final token = rawToken.trim();
    if (token.isEmpty) return;
    try {
      final peerId = await _service.redeemContactInviteTokenEnsured(token);
      try {
        final peer = await _service.resolveDevice(peerId);
        await _store.upsertContact(peer);
      } catch (_) {}
      await _resolvePeer(presetId: peerId);
      if (!mounted) return;
      setState(() => _tabIndex = 0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sanitizeExceptionForUi(error: e, isArabic: l.isArabic)),
        ),
      );
    }
  }

  Widget _buildBubbleText(BuildContext context, String text) {
    final term = _messageSearch.trim();
    if (term.isEmpty || text.isEmpty) {
      return Text(text);
    }
    final lowerText = text.toLowerCase();
    final lowerTerm = term.toLowerCase();
    if (!lowerText.contains(lowerTerm)) {
      return Text(text);
    }
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerTerm, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + term.length),
          style: TextStyle(
            backgroundColor: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: .9),
          ),
        ),
      );
      start = index + term.length;
    }
    final baseStyle = DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  Widget _buildProfileTab(ChatIdentity? me) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    final deviceId = (me?.id ?? '').trim();
    final shamellId = _shamellUserId.trim();
    final profileNameRaw = _displayNameCtrl.text.trim().isNotEmpty
        ? _displayNameCtrl.text.trim()
        : (me?.displayName ?? '').trim();
    final profileName = profileNameRaw.isNotEmpty ? profileNameRaw : null;
    final profileId = shamellId.isNotEmpty ? shamellId : null;

    return Container(
      color: bgColor,
      child: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildProfileHeader(me),
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.account_balance_wallet_outlined,
                  background: ShamellPalette.green,
                ),
                title: Text(
                  l.mePayEntryTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: chevron(),
                onTap: () {
                  unawaited(() async {
                    String walletId = '';
                    try {
                      final sp = await SharedPreferences.getInstance();
                      walletId = (sp.getString('wallet_id') ?? '').trim();
                    } catch (_) {}
                    if (!mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MiniProgramPage(
                          id: 'payments',
                          baseUrl: widget.baseUrl,
                          walletId: walletId,
                          deviceId: deviceId,
                          onOpenMod: _openMiniAppFromShamell,
                        ),
                      ),
                    );
                  }());
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.bookmark_outline,
                  background: Color(0xFFF59E0B),
                ),
                title: Text(l.isArabic ? 'المفضلة' : 'Favorites'),
                trailing: chevron(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FavoritesPage(baseUrl: widget.baseUrl),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.photo_library_outlined,
                  background: Color(0xFF10B981),
                ),
                title: Text(l.shamellChannelMomentsTitle),
                trailing: chevron(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MomentsPage(
                        baseUrl: widget.baseUrl,
                        showOnlyMine: true,
                        showComposer: true,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.settings_outlined,
                  background: Color(0xFF64748B),
                ),
                title: Text(l.settingsTitle),
                trailing: chevron(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ShamellSettingsHubPage(
                        baseUrl: widget.baseUrl,
                        deviceId: deviceId,
                        profileName: profileName,
                        profileId: profileId,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.tune,
                  background: Color(0xFF8B5CF6),
                ),
                title: Text(l.isArabic ? 'متقدم' : 'Advanced'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (ctx) {
                        final t = Theme.of(ctx);
                        final isDark2 = t.brightness == Brightness.dark;
                        final bg = isDark2
                            ? t.colorScheme.surface.withValues(alpha: .96)
                            : ShamellPalette.background;
                        final l2 = L10n.of(ctx);
                        return Scaffold(
                          backgroundColor: bg,
                          appBar: AppBar(
                            title: Text(l2.isArabic ? 'متقدم' : 'Advanced'),
                            backgroundColor: bg,
                            elevation: 0.5,
                          ),
                          body: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _identityCard(me),
                              const SizedBox(height: 12),
                              _callHistoryCard(),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(ChatIdentity? me) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final displayNameRaw = _displayNameCtrl.text.trim().isNotEmpty
        ? _displayNameCtrl.text.trim()
        : (me?.displayName ?? '').trim();
    final displayName = displayNameRaw.isNotEmpty
        ? displayNameRaw
        : (l.isArabic ? 'شامل' : 'Shamell');
    final shamellId = _shamellUserId.trim();
    final idLabel = shamellId.isNotEmpty
        ? shamellId
        : (l.isArabic ? 'غير مضبوط' : 'Not set');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: .4),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: .12),
            child: Text(
              displayName.isNotEmpty
                  ? displayName.substring(0, 1).toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.isArabic ? 'معرّف شامل: $idLabel' : 'Shamell ID: $idLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_2_outlined),
            onPressed: _showInviteQr,
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildChannelTabLegacy() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : (Colors.grey[100] ?? Colors.white);

    Widget section(List<Widget> tiles) {
      return Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 16,
                  endIndent: 16,
                  color: theme.dividerColor.withValues(alpha: .40),
                ),
              tiles[i],
            ],
          ],
        ),
      );
    }

    return Container(
      color: bgColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(
                Icons.explore_outlined,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l.shamellTabChannel,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Channels, Moments & Favorites – top section like Shamell Discover
          section([
            ListTile(
              leading: Icon(
                Icons.live_tv_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                l.isArabic ? 'القنوات' : 'Channels',
              ),
              subtitle: Text(
                l.isArabic
                    ? 'مقاطع قصيرة من الحسابات الرسمية'
                    : 'Short clips from official accounts',
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChannelsPage(
                      baseUrl: widget.baseUrl,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l.shamellChannelMomentsTitle),
              subtitle: Text(
                l.shamellChannelMomentsSubtitle,
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Perf.action('official_open_directory_from_channel_officials');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.bookmark_outline,
                color: theme.colorScheme.primary,
              ),
              title: Text(l.shamellChannelFavoritesTitle),
              subtitle: Text(
                l.shamellChannelFavoritesSubtitle,
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Perf.action(
                    'official_open_directory_from_chats_subscription_tile');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FavoritesPage(baseUrl: widget.baseUrl),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 12),
          // Official accounts & subscriptions – similar to Shamell Official Accounts
          section([
            ListTile(
              leading: Icon(
                Icons.verified_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l.shamellChannelOfficialAccountsTitle),
              subtitle: Text(
                l.shamellChannelOfficialAccountsSubtitle,
                style: theme.textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_officialPeerUnreadFeeds.isNotEmpty)
                    Icon(
                      Icons.brightness_1,
                      size: 8,
                      color: theme.colorScheme.primary,
                    ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OfficialAccountsPage(
                      baseUrl: widget.baseUrl,
                      initialCityFilter: null,
                      onOpenChat: (peerId) {
                        if (peerId.isEmpty) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShamellChatPage(
                              baseUrl: widget.baseUrl,
                              initialPeerId: peerId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.subscriptions_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  if (_hasUnreadSubscriptionFeeds)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Icon(
                        Icons.brightness_1,
                        size: 8,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              title: Text(
                l.shamellChannelSubscriptionAccountsTitle,
              ),
              subtitle: Text(
                l.shamellChannelSubscriptionAccountsSubtitle,
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OfficialAccountsPage(
                      baseUrl: widget.baseUrl,
                      initialCityFilter: null,
                      initialKindFilter: 'subscription',
                      onOpenChat: (peerId) {
                        if (peerId.isEmpty) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShamellChatPage(
                              baseUrl: widget.baseUrl,
                              initialPeerId: peerId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 12),
          // Scan & Mini‑programs – mid section
          section([
            ListTile(
              leading: Icon(
                Icons.qr_code_scanner,
                color: theme.colorScheme.primary,
              ),
              title: Text(l.shamellChannelScanTitle),
              subtitle: Text(
                l.shamellChannelScanSubtitle,
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () async {
                final raw = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => const ScanPage()),
                );
                if (!mounted || raw == null || raw.isEmpty) return;
                await _handleScanPayload(raw);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.apps_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs'),
              subtitle: Text(
                l.isArabic
                    ? 'استعرض البرامج المصغّرة مثل الباص والمدفوعات'
                    : 'Browse mini‑programs like Bus and Pay',
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MiniProgramsDiscoverPage(
                      baseUrl: widget.baseUrl,
                      walletId: '',
                      deviceId: _me?.id ?? '',
                      onOpenMod: _openMiniAppFromShamell,
                    ),
                  ),
                );
              },
            ),
          ]),
          if (_topMiniApps.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              l.isArabic
                  ? 'البرامج المصغّرة الأكثر استخدامًا'
                  : 'Mini‑programs you use most',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _topMiniApps.map((m) {
                final title = m.title(isArabic: l.isArabic);
                return ActionChip(
                  avatar: Icon(m.icon, size: 18),
                  label: Text(title),
                  onPressed: () => _openMiniAppFromShamell(m.id),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'الخدمات' : 'Services',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          section([
            ListTile(
              leading: const Icon(Icons.directions_bus_filled_outlined),
              title: const Text('Shamell Bus'),
              subtitle: Text(
                l.isArabic
                    ? 'خدمة الباص مدمجة مع المحفظة'
                    : 'Bus service integrated with Shamell Pay',
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _openBusService,
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Shamell Pay'),
              subtitle: Text(
                l.isArabic
                    ? 'ادفع، حوّل، وأدِر محفظتك'
                    : 'Pay, transfer and manage your wallet',
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _openPayService,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildChannelTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    Widget badgeDot() => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.surface,
              width: 1.5,
            ),
          ),
        );

    IconData miniPreviewIconFor(String id) {
      final meta = miniAppById(id);
      if (meta != null) return meta.icon;
      final lower = id.toLowerCase();
      if (lower.contains('pay') ||
          lower.contains('wallet') ||
          lower.contains('payment')) {
        return Icons.account_balance_wallet_outlined;
      }
      if (lower.contains('bus') ||
          lower.contains('ride') ||
          lower.contains('mobility') ||
          lower.contains('transport')) {
        return Icons.directions_bus_filled_outlined;
      }
      return Icons.widgets_outlined;
    }

    Color miniPreviewBgFor(String id) {
      final lower = id.toLowerCase();
      if (lower.contains('pay') ||
          lower.contains('wallet') ||
          lower.contains('payment')) {
        return Tokens.colorPayments;
      }
      if (lower.contains('bus') ||
          lower.contains('ride') ||
          lower.contains('mobility') ||
          lower.contains('transport')) {
        return Tokens.colorBus;
      }
      return const Color(0xFF64748B);
    }

    Color miniPreviewFgFor(String id) {
      return Colors.white;
    }

    List<String> miniProgramsPreviewIds() {
      final ids = <String>[];
      for (final m in _topMiniApps) {
        if (ids.length >= 3) break;
        final id = m.id.trim();
        if (id.isEmpty) continue;
        if (ids.contains(id)) continue;
        ids.add(id);
      }
      return ids;
    }

    Widget miniPreviewIcon(String id) {
      const size = 22.0;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: miniPreviewBgFor(id),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: theme.colorScheme.surface,
            width: 2,
          ),
        ),
        child: Icon(
          miniPreviewIconFor(id),
          size: 12,
          color: miniPreviewFgFor(id),
        ),
      );
    }

    Widget miniProgramsTrailing() {
      final ids = miniProgramsPreviewIds();
      if (ids.isEmpty) return chevron();

      const size = 22.0;
      const overlap = 8.0;
      final width = size + (ids.length - 1) * (size - overlap);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < ids.length; i++)
                  Positioned(
                    left: i * (size - overlap),
                    child: miniPreviewIcon(ids[i]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          chevron(),
        ],
      );
    }

    final topTiles = <Widget>[
      if (_caps.moments)
        ListTile(
          dense: true,
          leading: const ShamellLeadingIcon(
            icon: Icons.photo_library_outlined,
            background: Color(0xFF10B981),
          ),
          title: Text(l.shamellChannelMomentsTitle),
          trailing: chevron(),
          onTap: () {
            Perf.action('official_open_directory_from_channel_officials');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
              ),
            );
          },
        ),
      if (_caps.channels)
        ListTile(
          dense: true,
          leading: const ShamellLeadingIcon(
            icon: Icons.live_tv_outlined,
            background: Color(0xFFF59E0B),
          ),
          title: Text(l.isArabic ? 'القنوات' : 'Channels'),
          trailing: chevron(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChannelsPage(baseUrl: widget.baseUrl),
              ),
            );
          },
        ),
      if (_caps.channels)
        ListTile(
          dense: true,
          leading: const ShamellLeadingIcon(
            icon: Icons.radio_button_checked,
            background: Color(0xFFF43F5E),
          ),
          title: Text(l.isArabic ? 'مباشر' : 'Live'),
          trailing: chevron(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChannelsPage(
                  baseUrl: widget.baseUrl,
                  initialLiveOnly: true,
                ),
              ),
            );
          },
        ),
    ];

    final miscTiles = <Widget>[
      ListTile(
        dense: true,
        leading: const ShamellLeadingIcon(
          icon: Icons.qr_code_scanner,
          background: Color(0xFF3B82F6),
        ),
        title: Text(l.shamellChannelScanTitle),
        trailing: chevron(),
        onTap: () async {
          final raw = await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const ScanPage()),
          );
          if (!mounted || raw == null || raw.isEmpty) return;
          await _handleScanPayload(raw);
        },
      ),
      if (_caps.moments && _caps.officialAccounts)
        ListTile(
          dense: true,
          leading: const ShamellLeadingIcon(
            icon: Icons.local_fire_department_outlined,
            background: Color(0xFFF59E0B),
          ),
          title: Text(l.isArabic ? 'الأخبار' : 'Top Stories'),
          trailing: chevron(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MomentsPage(
                  baseUrl: widget.baseUrl,
                  initialHotOfficialsOnly: true,
                  showComposer: false,
                ),
              ),
            );
          },
        ),
    ];

    final discoverTiles = <Widget>[
      if (_caps.officialAccounts)
        ListTile(
          dense: true,
          leading: const ShamellLeadingIcon(
            icon: Icons.verified_outlined,
            background: Color(0xFF10B981),
          ),
          title: Text(l.shamellChannelOfficialAccountsTitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_officialPeerUnreadFeeds.isNotEmpty) ...[
                badgeDot(),
                const SizedBox(width: 8),
              ],
              chevron(),
            ],
          ),
          onTap: () async {
            if (!await _ensureOfficialAuthSession()) return;
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OfficialAccountsPage(
                  baseUrl: widget.baseUrl,
                  initialCityFilter: null,
                  onOpenChat: (peerId) {
                    if (peerId.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShamellChatPage(
                          baseUrl: widget.baseUrl,
                          initialPeerId: peerId,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ListTile(
        dense: true,
        leading: const ShamellLeadingIcon(
          icon: Icons.search,
          background: Color(0xFF64748B),
        ),
        title: Text(l.isArabic ? 'بحث' : 'Search'),
        trailing: chevron(),
        onTap: () => unawaited(_openGlobalSearchFromChats()),
      ),
    ];

    final miniProgramTiles = <Widget>[
      if (_caps.miniPrograms)
        ListTile(
          dense: true,
          leading: const ShamellLeadingIcon(
            icon: Icons.grid_view_outlined,
            background: ShamellPalette.green,
          ),
          title: Text(l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs'),
          trailing: miniProgramsTrailing(),
          onTap: () => unawaited(_openMiniProgramsHubFromChats()),
        ),
    ];

    final sections = <Widget>[
      if (topTiles.isNotEmpty)
        ShamellSection(
          margin: const EdgeInsets.only(top: 8),
          children: topTiles,
        ),
      ShamellSection(
        children: miscTiles,
      ),
      ShamellSection(
        children: discoverTiles,
      ),
      if (miniProgramTiles.isNotEmpty)
        ShamellSection(
          children: miniProgramTiles,
        ),
    ];

    return Container(
      color: bgColor,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: sections,
      ),
    );
  }

  Future<void> _sendQuickCommand(String cmd) async {
    _msgCtrl.text = cmd;
    await _send();
  }
}

extension _MiniAppsFromShamell on _ShamellChatPageState {
  void _openMiniAppFromShamell(String id) {
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MiniProgramPage(
            id: id,
            baseUrl: widget.baseUrl,
            walletId: '',
            deviceId: _me?.id ?? '',
            onOpenMod: _openMiniAppFromShamell,
          ),
        ),
      ).then((_) => _loadTopMiniApps()),
    );
  }
}

class _ServiceSheet extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const _ServiceSheet({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {},
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: .98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 4,
                      width: 44,
                      margin: const EdgeInsets.only(bottom: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _ShamellChatHelpers on _ShamellChatPageState {
  bool _shouldShowShamellTimeHeader(int index) {
    if (index <= 0) return true;
    if (index >= _messages.length) return false;
    final cur = _messages[index].createdAt;
    final prev = _messages[index - 1].createdAt;
    if (cur == null) return false;
    if (prev == null) return true;
    final c = cur.toLocal();
    final p = prev.toLocal();
    final dayChanged = c.year != p.year || c.month != p.month || c.day != p.day;
    if (dayChanged) return true;
    final diff = c.difference(p).abs();
    return diff.inMinutes >= 10;
  }

  Widget _buildShamellTimeHeader(DateTime ts) {
    final theme = Theme.of(context);
    final ml = MaterialLocalizations.of(context);
    final local = ts.toLocal();
    final date = ml.formatShortDate(local);
    final time = ml.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    final label = '$date · $time';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: .35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: .35),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markAllChatsRead() async {
    if (_unread.isEmpty) return;
    final now = DateTime.now();
    final groupIds = _unread.entries
        .where((e) => e.key.startsWith('grp:') && e.value > 0)
        .map((e) => e.key.substring(4))
        .where((gid) => gid.trim().isNotEmpty)
        .toSet();
    for (final gid in groupIds) {
      try {
        await _store.setGroupSeen(gid, now);
      } catch (_) {}
    }
    _applyState(() {
      _unread = {for (final e in _unread.entries) e.key: 0};
      _groupMentionUnread = <String>{};
      _groupMentionAllUnread = <String>{};
    });
    unawaited(_store.saveUnread(_unread));
  }

  Future<void> _markSelectedChatsRead() async {
    if (_selectedChatIds.isEmpty) return;
    final now = DateTime.now();
    final groupIds = _selectedChatIds
        .where((id) => id.startsWith('grp:'))
        .map((id) => id.substring(4))
        .where((gid) => gid.trim().isNotEmpty)
        .toSet();
    for (final gid in groupIds) {
      try {
        await _store.setGroupSeen(gid, now);
      } catch (_) {}
    }
    final next = Map<String, int>.from(_unread);
    for (final id in _selectedChatIds) {
      if (next.containsKey(id)) {
        next[id] = 0;
      }
    }
    final nextMentions = Set<String>.from(_groupMentionUnread)
      ..removeAll(groupIds);
    final nextMentionAll = Set<String>.from(_groupMentionAllUnread)
      ..removeAll(groupIds);
    _applyState(() {
      _unread = next;
      _groupMentionUnread = nextMentions;
      _groupMentionAllUnread = nextMentionAll;
    });
    await _store.saveUnread(_unread);
  }

  Future<void> _unarchiveSelectedChats() async {
    if (_selectedChatIds.isEmpty) return;
    final ids = Set<String>.from(_selectedChatIds);
    final contactIds = ids.where((id) => !id.startsWith('grp:')).toSet();
    final groupIds = ids
        .where((id) => id.startsWith('grp:'))
        .map((id) => id.substring(4))
        .where((gid) => gid.trim().isNotEmpty)
        .toSet();

    bool contactsChanged = false;
    ChatContact? updatedPeer = _peer;
    final contacts = List<ChatContact>.from(_contacts);
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      if (!contactIds.contains(c.id) || !c.archived) continue;
      final updated = c.copyWith(archived: false);
      contacts[i] = updated;
      contactsChanged = true;
      if (updatedPeer?.id == updated.id) {
        updatedPeer = updated;
      }
    }
    if (contactsChanged) {
      try {
        await _store.saveContacts(contacts);
      } catch (_) {}
    }

    final nextArchivedGroups = Set<String>.from(_archivedGroupIds);
    var groupsChanged = false;
    for (final gid in groupIds) {
      groupsChanged = nextArchivedGroups.remove(gid) || groupsChanged;
    }

    _applyState(() {
      if (contactsChanged) {
        _contacts = contacts;
        if (_peer != null) {
          _peer = updatedPeer;
        }
      }
      if (groupsChanged) {
        _archivedGroupIds = nextArchivedGroups;
      }
      _selectionMode = false;
      _selectedChatIds.clear();
    });

    if (groupsChanged) {
      unawaited(_persistArchivedGroups());
    }
  }

  Future<void> _deleteSelectedChats() async {
    if (_selectedChatIds.isEmpty) return;
    final ids = Set<String>.from(_selectedChatIds);
    final contactIds = ids.where((id) => !id.startsWith('grp:')).toSet();
    final groupIds = ids
        .where((id) => id.startsWith('grp:'))
        .map((id) => id.substring(4))
        .toSet();
    var contacts = List<ChatContact>.from(_contacts);
    contacts.removeWhere((c) => contactIds.contains(c.id));
    bool clearedActivePeer = false;
    for (final id in contactIds) {
      try {
        await _store.deleteMessages(id);
      } catch (_) {}
      _draftTextByChatId.remove(id);
      _composerDraftByChatId.remove(id);
      _cache.remove(id);
      _unread.remove(id);
      if (_activePeerId == id && !clearedActivePeer) {
        _activePeerId = null;
        _peer = null;
        _messages = [];
        try {
          await _store.clearPeer();
        } catch (_) {}
        clearedActivePeer = true;
      }
    }
    for (final gid in groupIds) {
      try {
        await _store.deleteGroupMessages(gid);
      } catch (_) {}
      try {
        await _store.deleteGroupKey(gid);
      } catch (_) {}
      _groupCache.remove(gid);
      _unread.remove('grp:$gid');
    }
    await _store.saveContacts(contacts);
    await _store.saveUnread(_unread);
    try {
      await _store.saveDrafts(_draftTextByChatId);
    } catch (_) {}
    _applyState(() {
      _contacts = contacts;
      _selectionMode = false;
      _selectedChatIds.clear();
    });
  }

  Future<void> _deleteChatById(String id) async {
    final remaining = _contacts.where((x) => x.id != id).toList();
    try {
      await _store.saveContacts(remaining);
    } catch (_) {}
    try {
      await _store.deleteMessages(id);
    } catch (_) {}
    _draftTextByChatId.remove(id);
    _composerDraftByChatId.remove(id);
    try {
      await _store.saveDrafts(_draftTextByChatId);
    } catch (_) {}
    _unread.remove(id);
    try {
      await _store.saveUnread(_unread);
    } catch (_) {}
    _cache.remove(id);
    if (_activePeerId == id) {
      _activePeerId = null;
      _peer = null;
      _messages = [];
      try {
        await _store.clearPeer();
      } catch (_) {}
    }
    _applyState(() {
      _contacts = remaining;
    });
  }

  Future<void> _toggleChatReadUnread(ChatContact c) async {
    final cur = _unread[c.id] ?? 0;
    _applyState(() {
      _unread[c.id] = cur != 0 ? 0 : -1;
    });
    try {
      await _store.saveUnread(_unread);
    } catch (_) {}
  }

  Future<void> _toggleChatMuted(ChatContact c) async {
    final updated = c.copyWith(muted: !c.muted);
    final contacts = _upsertContact(updated);
    try {
      await _store.saveContacts(contacts);
    } catch (_) {}
    try {
      if (_me != null) {
        await _service.setPrefs(
          deviceId: _me!.id,
          peerId: c.id,
          muted: updated.muted,
          starred: updated.starred,
          pinned: updated.pinned,
        );
      }
    } catch (_) {}
    _applyState(() {
      _contacts = contacts;
    });
  }

  Future<void> _toggleChatPinned(ChatContact c) async {
    final updated = c.copyWith(pinned: !c.pinned);
    _updatePinnedChatOrderForPeer(updated.id, updated.pinned);
    final contacts = _upsertContact(updated);
    try {
      await _store.saveContacts(contacts);
    } catch (_) {}
    try {
      if (_me != null) {
        await _service.setPrefs(
          deviceId: _me!.id,
          peerId: c.id,
          muted: updated.muted,
          starred: updated.starred,
          pinned: updated.pinned,
        );
      }
    } catch (_) {}
    _applyState(() {
      _contacts = contacts;
    });
  }

  Future<void> _toggleChatArchived(ChatContact c) async {
    final updated = c.copyWith(archived: !c.archived);
    final contacts = _upsertContact(updated);
    try {
      await _store.saveContacts(contacts);
    } catch (_) {}
    _applyState(() {
      _contacts = contacts;
    });
  }

  Future<void> _toggleGroupMuted(ChatGroup g) async {
    final cur = _groupPrefs[g.id] ??
        const ChatGroupPrefs(groupId: '', muted: false, pinned: false);
    final next = ChatGroupPrefs(
      groupId: g.id,
      muted: !cur.muted,
      pinned: cur.pinned,
    );
    _groupPrefs[g.id] = next;
    try {
      if (_me != null) {
        await _service.setGroupPrefs(
          deviceId: _me!.id,
          groupId: g.id,
          muted: next.muted,
          pinned: next.pinned,
        );
      }
    } catch (_) {}
    _applyState(() {});
  }

  Future<void> _toggleGroupPinned(ChatGroup g) async {
    final cur = _groupPrefs[g.id] ??
        const ChatGroupPrefs(groupId: '', muted: false, pinned: false);
    final next = ChatGroupPrefs(
      groupId: g.id,
      muted: cur.muted,
      pinned: !cur.pinned,
    );
    _groupPrefs[g.id] = next;
    _updatePinnedChatOrderForPeer(_groupUnreadKey(g.id), next.pinned);
    try {
      if (_me != null) {
        await _service.setGroupPrefs(
          deviceId: _me!.id,
          groupId: g.id,
          muted: next.muted,
          pinned: next.pinned,
        );
      }
    } catch (_) {}
    _applyState(() {});
  }

  Future<void> _toggleGroupArchived(ChatGroup g) async {
    final gid = g.id.trim();
    if (gid.isEmpty) return;
    final next = Set<String>.from(_archivedGroupIds);
    if (next.contains(gid)) {
      next.remove(gid);
    } else {
      next.add(gid);
    }
    _applyState(() {
      _archivedGroupIds = next;
    });
    unawaited(_persistArchivedGroups());
  }

  Future<void> _toggleGroupReadUnread(ChatGroup g) async {
    final key = _groupUnreadKey(g.id);
    final cur = _unread[key] ?? 0;
    if (cur > 0) {
      try {
        await _store.setGroupSeen(g.id, DateTime.now());
      } catch (_) {}
    }
    final nextUnread = Map<String, int>.from(_unread);
    nextUnread[key] = cur != 0 ? 0 : -1;
    final nextMentions = Set<String>.from(_groupMentionUnread);
    final nextMentionAll = Set<String>.from(_groupMentionAllUnread);
    if (cur != 0) {
      nextMentions.remove(g.id);
      nextMentionAll.remove(g.id);
    }
    _applyState(() {
      _unread = nextUnread;
      _groupMentionUnread = nextMentions;
      _groupMentionAllUnread = nextMentionAll;
    });
    try {
      await _store.saveUnread(_unread);
    } catch (_) {}
  }

  Future<void> _onGroupLongPress(ChatGroup g, {Offset? globalPosition}) async {
    final l = L10n.of(context);
    final prefs = _groupPrefs[g.id];
    final pinned = prefs?.pinned ?? false;
    final hasUnread = (_unread[_groupUnreadKey(g.id)] ?? 0) != 0;
    final markLabel = hasUnread ? l.shamellMarkRead : l.shamellMarkUnread;
    final pinLabel = pinned ? l.shamellUnpinChat : l.shamellPinChat;
    final moreLabel = l.isArabic ? 'المزيد' : 'More…';
    final deleteLabel = l.shamellDeleteChat;
    final cancelLabel = l.isArabic ? 'إلغاء' : 'Cancel';
    final globalPos = globalPosition;
    if (globalPos != null) {
      await _showShamellActionsPopover(
        globalPosition: globalPos,
        actions: [
          _ShamellPopoverActionSpec(
            label: markLabel,
            onTap: () => unawaited(_toggleGroupReadUnread(g)),
          ),
          _ShamellPopoverActionSpec(
            label: pinLabel,
            onTap: () => unawaited(_toggleGroupPinned(g)),
          ),
          _ShamellPopoverActionSpec(
            label: moreLabel,
            onTap: () {
              unawaited(
                Future<void>.delayed(_shamellMoreSheetDelay, () {
                  if (!mounted) return;
                  unawaited(_showGroupMoreSheet(g));
                }),
              );
            },
          ),
          _ShamellPopoverActionSpec(
            label: deleteLabel,
            color: const Color(0xFFFA5151),
            onTap: () => unawaited(_clearGroupConversation(g)),
          ),
        ],
      );
      return;
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
                    label: markLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleGroupReadUnread(g));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleGroupPinned(g));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: moreLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(
                        Future<void>.delayed(_shamellMoreSheetDelay, () {
                          if (!mounted) return;
                          unawaited(_showGroupMoreSheet(g));
                        }),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_clearGroupConversation(g));
                    },
                  ),
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

  void _toggleChatSelected(String chatId) {
    _applyState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  Future<void> _showShamellActionsPopover({
    required Offset globalPosition,
    required List<_ShamellPopoverActionSpec> actions,
  }) async {
    if (actions.isEmpty) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}

    final overlaySize = overlayBox.size;
    final anchor =
        overlayBox.globalToLocal(globalPosition) - const Offset(0, 8);

    const rowH = 44.0;
    const menuW = 210.0;
    final menuH = rowH * actions.length;
    const arrowW = 14.0;
    const arrowH = 10.0;
    const margin = 8.0;
    const gap = 10.0;

    final canShowAbove = anchor.dy - gap - arrowH - menuH >= margin;
    final canShowBelow =
        anchor.dy + gap + arrowH + menuH <= overlaySize.height - margin;
    final showAbove = canShowAbove || !canShowBelow;

    var left = anchor.dx - (menuW / 2);
    left = left.clamp(margin, overlaySize.width - menuW - margin);

    double top;
    if (showAbove) {
      top = anchor.dy - gap - arrowH - menuH;
    } else {
      top = anchor.dy + gap + arrowH;
    }
    top = top.clamp(margin, overlaySize.height - menuH - margin);

    var arrowLeft = anchor.dx - (arrowW / 2);
    arrowLeft = arrowLeft.clamp(left + 10, left + menuW - arrowW - 10);
    final arrowTop = showAbove ? (top + menuH) : (top - arrowH);

    const bg = Color(0xFF2C2C2C);
    final theme = Theme.of(context);

    Widget actionRow(
      _ShamellPopoverActionSpec action, {
      required bool showDivider,
    }) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              action.onTap();
            },
            child: SizedBox(
              height: rowH,
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    action.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: action.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: .14),
            ),
        ],
      );
    }

    final menu = Material(
      color: Colors.transparent,
      child: Container(
        width: menuW,
        height: menuH,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++)
              actionRow(
                actions[i],
                showDivider: i != actions.length - 1,
              ),
          ],
        ),
      ),
    );

    final arrow = ClipPath(
      clipper: showAbove
          ? _ShamellPopoverDownArrowClipper()
          : _ShamellPopoverUpArrowClipper(),
      child: const ColoredBox(
        color: bg,
        child: SizedBox(width: arrowW, height: arrowH),
      ),
    );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
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
  }

  void _clearChatSelection() {
    _applyState(() {
      _selectionMode = false;
      _selectedChatIds.clear();
    });
  }

  // ignore: unused_element
  void _showChatsMenu() {
    final l = L10n.of(context);
    showModalBottomSheet<void>(
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

        final previewsLabel = _notifyPreview
            ? l.shamellMessagePreviewsDisable
            : l.shamellMessagePreviewsEnable;
        final showHiddenToggle = _hasHiddenContacts() || _showHidden;
        final hiddenLabel =
            _showHidden ? l.shamellHideLockedChats : l.shamellShowLockedChats;
        final showBlockedToggle =
            _contacts.any((c) => c.blocked) || _showBlocked;
        final blockedLabel = _showBlocked
            ? (l.isArabic ? 'إخفاء المحظورين' : 'Hide blocked chats')
            : (l.isArabic ? 'إظهار المحظورين' : 'Show blocked chats');
        final selectionLabel = _selectionMode
            ? (l.isArabic ? 'إنهاء التحديد' : 'Exit selection')
            : l.shamellChatsSelection;
        final cancelLabel = l.isArabic ? 'إلغاء' : 'Cancel';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(builder: (_) {
                  final actions = <Widget>[];

                  void addAction(Widget w) {
                    if (actions.isNotEmpty) {
                      actions.add(const Divider(height: 1));
                    }
                    actions.add(w);
                  }

                  addAction(
                    actionRow(
                      label: l.shamellChatsMarkAllRead,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _markAllChatsRead();
                      },
                    ),
                  );
                  addAction(
                    actionRow(
                      label: selectionLabel,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _applyState(() {
                          _selectionMode = !_selectionMode;
                          _selectedChatIds.clear();
                        });
                      },
                    ),
                  );
                  addAction(
                    actionRow(
                      label: previewsLabel,
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final next = !_notifyPreview;
                        _applyState(() => _notifyPreview = next);
                        await _store.setNotifyPreview(next);
                      },
                    ),
                  );
                  if (showHiddenToggle) {
                    addAction(
                      actionRow(
                        label: hiddenLabel,
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          if (_showHidden) {
                            _applyState(() => _showHidden = false);
                            return;
                          }
                          final ok = await _authenticate();
                          if (ok) {
                            _applyState(() => _showHidden = true);
                          }
                        },
                      ),
                    );
                  }
                  if (showBlockedToggle) {
                    addAction(
                      actionRow(
                        label: blockedLabel,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _applyState(() {
                            _showBlocked = !_showBlocked;
                          });
                        },
                      ),
                    );
                  }

                  return card(actions);
                }),
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

  Future<void> _startNewChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendsPage(widget.baseUrl),
      ),
    );
    if (!mounted) return;
    if (result is String && result.trim().isNotEmpty) {
      _applyState(() {
        _tabIndex = 0;
        _showArchived = false;
        _chatSearch = '';
      });
      _chatSearchCtrl.clear();
      _resetArchivedPullDown();
      unawaited(_resolvePeer(presetId: result.trim()));
    }
  }

  Future<void> _startNewGroupChat() async {
    final me = _me;
    final l = L10n.of(context);
    if (me == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shamellIdentityHint)),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    ChatGroup? created;
    await showModalBottomSheet<ChatGroup?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        bool loading = false;
        String error = '';

        Future<void> create(StateSetter setLocal) async {
          final name = nameCtrl.text.trim();
          if (name.isEmpty || loading) return;
          setLocal(() {
            loading = true;
            error = '';
          });
          try {
            final g = await _service.createGroup(deviceId: me.id, name: name);
            try {
              final existing = await _store.loadGroupKey(g.id);
              if (existing == null || existing.isEmpty) {
                final rnd = Random.secure();
                final keyBytes = Uint8List.fromList(
                    List<int>.generate(32, (_) => rnd.nextInt(256)));
                await _store.saveGroupKey(g.id, base64Encode(keyBytes));
              }
            } catch (_) {}
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop(g);
          } catch (e) {
            setLocal(() {
              error = sanitizeExceptionForUi(error: e);
              loading = false;
            });
          }
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                left: 12, right: 12, top: 0, bottom: bottom + 12),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: StatefulBuilder(builder: (ctx2, setLocal) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.isArabic ? 'دردشة جماعية' : 'Group chat',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: l.isArabic ? 'اسم المجموعة' : 'Group name',
                        ),
                        onSubmitted: (_) => create(setLocal),
                      ),
                      if (error.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          error,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: loading
                                  ? null
                                  : () => Navigator.of(ctx2).pop(),
                              child: Text(l.shamellDialogCancel),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  loading ? null : () => create(setLocal),
                              child: Text(
                                loading
                                    ? (l.isArabic ? '... ' : '... ')
                                    : (l.isArabic ? 'إنشاء' : 'Create'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        );
      },
    ).then((value) {
      created = value;
    });
    nameCtrl.dispose();
    if (!mounted) return;
    if (created == null) return;
    await _syncGroups();
    if (!mounted) return;
    await Navigator.push<bool?>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          baseUrl: widget.baseUrl,
          groupId: created!.id,
          groupName: created!.name,
        ),
      ),
    );
    await _syncGroups();
  }

  void _openPeopleP2PFromShamell() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeopleP2PPage(
          widget.baseUrl,
          '',
          'shamell',
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _openOfficialNotificationsFromShamell() async {
    try {
      Perf.action('official_open_notifications_from_shamell_settings');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfficialAccountsPage(
            baseUrl: widget.baseUrl,
            initialCityFilter: null,
            initialKindFilter: '',
            onOpenChat: (peerId) {
              if (peerId.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShamellChatPage(
                    baseUrl: widget.baseUrl,
                    initialPeerId: peerId,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (_) {}
  }

  Widget _identityCard(ChatIdentity? me) {
    final l = L10n.of(context);
    return _block(
        title: l.shamellIdentityTitle,
        trailing: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              me?.id ?? l.shamellIdentityNotCreated,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              me != null
                  ? '${l.chatMyFingerprint} ${me.fingerprint}'
                  : l.shamellIdentityHint,
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color ??
                      Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: TextField(
                  controller: _displayNameCtrl,
                  decoration:
                      InputDecoration(labelText: l.shamellDisplayNameOptional),
                )),
                const SizedBox(width: 8),
                FilledButton.icon(
                    onPressed: _generateIdentity,
                    icon: const Icon(Icons.bolt),
                    label: Text(l.shamellGenerate))
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                      onPressed: me == null ? null : _register,
                      child: Text(l.shamellRegisterWithRelay)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null ? null : () => _showQr(me),
                        child: Text(l.shamellShowQrButton))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null
                            ? null
                            : () async {
                                await Clipboard.setData(
                                    ClipboardData(text: me.id));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text(l.shamellIdCopiedSnack)));
                                }
                              },
                        child: Text(l.shamellCopyIdButton))),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null
                            ? null
                            : () async {
                                await Share.share(
                                    'My chat ID: ${me.id}\nFP: ${me.fingerprint}');
                              },
                        child: Text(l.shamellShareIdButton))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null ? null : _backupIdentity,
                        child: Text(l.shamellBackupPassphraseButton))),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: _restoreIdentity,
                        child: Text(l.shamellRestoreBackupButton))),
              ],
            ),
            if (_backupText != null && _backupText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: SelectableText(
                  _backupText!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              )
          ],
        ));
  }

  Widget _conversationsCard() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final allowServiceThread = _caps.serviceNotifications;
    final allowSubscriptionsThread = _caps.subscriptions;
    final showServiceThread = allowServiceThread &&
        (!_hideServiceNotificationsThread || _hasUnreadServiceNotifications);
    final showSubscriptionsThread = allowSubscriptionsThread &&
        (!_hideSubscriptionsThread || _hasUnreadSubscriptionFeeds);
    final showArchivedSearch = _showArchived;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),
          if (showArchivedSearch) ...[
            ShamellSearchBar(
              hintText: l.isArabic ? 'بحث' : 'Search',
              controller: _chatSearchCtrl,
              readOnly: false,
              onChanged: (v) {
                _applyState(() {
                  _chatSearch = v.trim();
                });
              },
            ),
            const SizedBox(height: 10),
          ],
          if (_chatSearch.isEmpty && !_showArchived && !_selectionMode) ...[
            if (showServiceThread)
              _buildSwipeableSystemThreadTile(
                keyId: 'service_notifications',
                hasUnread: _hasUnreadServiceNotifications,
                onToggleRead: _toggleServiceNotificationsReadUnread,
                onDelete: _deleteServiceNotificationsThread,
                child: _buildShamellThreadTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildShamellAvatarBox(
                        backgroundColor: Tokens.colorPayments,
                        child: const Icon(
                          Icons.notifications_none_outlined,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                      if (_hasUnreadServiceNotifications)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFA5151),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.isArabic
                              ? 'إشعارات الخدمات'
                              : 'Service notifications',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'رسائل القوالب والتحديثات'
                        : 'Template messages & updates',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  ts: '',
                  pinned: false,
                  muted: false,
                  selected: false,
                  onTap: () {
                    unawaited(
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OfficialTemplateMessagesPage(
                            baseUrl: widget.baseUrl,
                          ),
                        ),
                      ).then((_) => _loadServiceNotificationsBadge()),
                    );
                  },
                  onLongPress: () {},
                ),
              ),
            if (showServiceThread && showSubscriptionsThread)
              const Divider(height: 1, indent: 70, endIndent: 12),
            if (showSubscriptionsThread)
              _buildSwipeableSystemThreadTile(
                keyId: 'subscriptions',
                hasUnread: _hasUnreadSubscriptionFeeds,
                onToggleRead: _toggleSubscriptionsReadUnread,
                onDelete: _deleteSubscriptionsThread,
                child: _buildShamellThreadTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildShamellAvatarBox(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.subscriptions_outlined,
                          size: 22,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (_hasUnreadSubscriptionFeeds)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFA5151),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.shamellSubscriptionsFeedTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    () {
                      final subs = _subscriptionOfficialPeerIds.length;
                      final unread = _subscriptionUnreadCount;
                      if (subs <= 0) {
                        return l.shamellSubscriptionsFeedEmptySummary;
                      }
                      return l.shamellSubscriptionsFeedSummary(subs, unread);
                    }(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  ts: '',
                  pinned: false,
                  muted: false,
                  selected: false,
                  onTap: _openSubscriptionsThread,
                  onLongPress: () {},
                ),
              ),
            if (showSubscriptionsThread)
              const Divider(height: 1, indent: 70, endIndent: 12),
          ],
          if (_officialPeerIds.isNotEmpty && !_showArchived)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.subscriptions_outlined,
                        size: 16,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l.isArabic ? 'اشتراكات فقط' : 'Subscriptions only',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .75),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Switch(
                        value: _showSubscriptionChatsOnly,
                        onChanged: (v) {
                          _applyState(() {
                            _showSubscriptionChatsOnly = v;
                          });
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_contacts.isEmpty && _groups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(l.shamellNoContactsHint),
            )
          else ...[
            Builder(builder: (ctx) {
              final sortedContacts = _sortedContacts();
              final term = _chatSearch.toLowerCase();
              final contactNameById = <String, String>{
                for (final c in sortedContacts)
                  if ((c.name ?? '').trim().isNotEmpty)
                    c.id: (c.name ?? '').trim(),
              };

              String shortId(String id) {
                final raw = id.trim();
                if (raw.length <= 10) return raw;
                return '${raw.substring(0, 6)}…';
              }

              String displayName(String id, {String? fallback}) {
                final raw = id.trim();
                if (raw.isEmpty) {
                  return fallback ?? (l.isArabic ? 'أحد الأعضاء' : 'Someone');
                }
                final myId = (_me?.id ?? '').trim();
                if (myId.isNotEmpty && raw == myId) {
                  return l.isArabic ? 'أنت' : 'You';
                }
                final name = (contactNameById[raw] ?? '').trim();
                if (name.isNotEmpty) return name;
                return shortId(raw);
              }

              bool contactVisible(ChatContact c) {
                if ((c.hidden && !_showHidden) ||
                    (c.blocked && !_showBlocked)) {
                  return false;
                }
                if (c.id == _ShamellChatPageState._subscriptionsPeerId) {
                  return false;
                }
                final isArchived = c.archived;
                final inArchivedView = _showArchived;
                if (!inArchivedView && _showSubscriptionChatsOnly) {
                  if (!_officialPeerIds.contains(c.id) ||
                      !_subscriptionOfficialPeerIds.contains(c.id)) {
                    return false;
                  }
                }
                if (term.isEmpty) {
                  return inArchivedView ? isArchived : !isArchived;
                }
                final name = (c.name ?? '').toLowerCase();
                final id = c.id.toLowerCase();
                final matches = name.contains(term) || id.contains(term);
                if (!matches) return false;
                if (inArchivedView && !isArchived) return false;
                return true;
              }

              bool groupVisible(ChatGroup g) {
                final inArchivedView = _showArchived;
                if (!inArchivedView && _showSubscriptionChatsOnly) return false;
                final isArchived = _archivedGroupIds.contains(g.id);
                final thread = _groupCache[g.id] ?? const <ChatGroupMessage>[];
                final unread = _unread[_groupUnreadKey(g.id)] ?? 0;
                final mentionUnread = _groupMentionUnread.contains(g.id);
                final bool hasThreadActivity =
                    thread.isNotEmpty || unread != 0 || mentionUnread;
                if (term.isEmpty) {
                  if (!hasThreadActivity) return false;
                  return inArchivedView ? isArchived : !isArchived;
                }
                final name = g.name.toLowerCase();
                final id = g.id.toLowerCase();
                final matches = name.contains(term) || id.contains(term);
                if (!matches) return false;
                if (inArchivedView && !isArchived) return false;
                return true;
              }

              DateTime contactLastActivity(ChatContact c) {
                final thread = _cache[c.id];
                final lastMsg =
                    thread != null && thread.isNotEmpty ? thread.last : null;
                var ts = lastMsg?.createdAt ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                try {
                  final calls = _lastCallsCache ?? const <ChatCallLogEntry>[];
                  final callsForPeer =
                      calls.where((e) => e.peerId == c.id).toList();
                  if (callsForPeer.isNotEmpty) {
                    callsForPeer.sort((a, b) => b.ts.compareTo(a.ts));
                    final lastCall = callsForPeer.first;
                    if (lastCall.ts.isAfter(ts)) {
                      ts = lastCall.ts;
                    }
                  }
                } catch (_) {}
                return ts;
              }

              DateTime groupLastActivity(ChatGroup g) {
                final thread = _groupCache[g.id] ?? const <ChatGroupMessage>[];
                final last = thread.isNotEmpty ? thread.last : null;
                return last?.createdAt ??
                    DateTime.fromMillisecondsSinceEpoch(0);
              }

              String groupPreview(ChatGroupMessage m) {
                final kind = (m.kind ?? '').toLowerCase();
                if (kind == 'system') {
                  final raw = m.text.trim();
                  if (raw.isNotEmpty) {
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
                          final who = displayName(actor);
                          final joined = ids
                              .map((id) => displayName(id, fallback: id))
                              .join(', ');
                          return l.isArabic
                              ? 'قام $who بإضافة ${ids.isEmpty ? 'أعضاء' : joined}'
                              : '$who invited ${ids.isEmpty ? 'members' : joined}';
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
                          final who = displayName(actor);
                          final joined = ids
                              .map((id) => displayName(id, fallback: id))
                              .join(', ');
                          if (l.isArabic) {
                            final base = name.isNotEmpty
                                ? 'أنشأ $who \"$name\"'
                                : 'أنشأ $who المجموعة';
                            return ids.isEmpty ? base : '$base وأضاف $joined';
                          }
                          final base = name.isNotEmpty
                              ? '$who created \"$name\"'
                              : '$who created the group';
                          return ids.isEmpty
                              ? base
                              : '$base and invited $joined';
                        }
                        if (ev == 'leave') {
                          final who = displayName(actor);
                          return l.isArabic
                              ? 'غادر $who المجموعة'
                              : '$who left the group';
                        }
                        if (ev == 'role') {
                          final target = (j['target_id'] ?? '').toString();
                          final role = (j['role'] ?? '').toString();
                          final who = displayName(actor);
                          final targetLabel = displayName(
                            target,
                            fallback: l.isArabic ? 'عضو' : 'a member',
                          );
                          if (role == 'admin') {
                            return l.isArabic
                                ? 'قام $who بترقية $targetLabel'
                                : '$who made $targetLabel admin';
                          }
                          return l.isArabic
                              ? 'قام $who بإزالة صلاحية المشرف من $targetLabel'
                              : '$who removed admin from $targetLabel';
                        }
                        if (ev == 'rename') {
                          final newName = (j['new_name'] ?? '').toString();
                          final who = displayName(actor);
                          if (l.isArabic) {
                            return newName.isNotEmpty
                                ? 'قام $who بتغيير اسم المجموعة إلى \"$newName\"'
                                : 'قام $who بتغيير اسم المجموعة';
                          }
                          return newName.isNotEmpty
                              ? '$who changed group name to \"$newName\"'
                              : '$who changed group name';
                        }
                        if (ev == 'avatar') {
                          final action = (j['action'] ?? '').toString();
                          final who = displayName(actor);
                          if (l.isArabic) {
                            return action == 'remove'
                                ? 'قام $who بإزالة صورة المجموعة'
                                : 'قام $who بتغيير صورة المجموعة';
                          }
                          return action == 'remove'
                              ? '$who removed group photo'
                              : '$who changed group photo';
                        }
                        if (ev == 'key_rotated') {
                          final ver = (j['version'] ?? '').toString();
                          return l.isArabic
                              ? 'قام ${displayName(actor, fallback: l.isArabic ? 'مشرف' : 'An admin')} بتدوير مفتاح التشفير${ver.isNotEmpty ? ' (v$ver)' : ''}'
                              : '${displayName(actor, fallback: l.isArabic ? 'مشرف' : 'An admin')} rotated encryption key${ver.isNotEmpty ? ' (v$ver)' : ''}';
                        }
                      }
                    } catch (_) {}
                    return raw;
                  }
                  return l.isArabic ? 'حدث في المجموعة' : 'Group event';
                }
                String previewText;
                if (kind == 'sealed') {
                  previewText =
                      l.isArabic ? 'رسالة مشفرة' : 'Encrypted message';
                } else if (kind == 'voice') {
                  previewText = l.shamellPreviewVoice;
                } else {
                  final mime = (m.attachmentMime ?? '').toLowerCase();
                  if (kind == 'image' || mime.startsWith('image/')) {
                    final caption = m.text.trim();
                    previewText = caption.isNotEmpty
                        ? '${l.shamellPreviewImage} $caption'
                        : l.shamellPreviewImage;
                  } else if (m.text.isNotEmpty) {
                    previewText = m.text;
                  } else {
                    previewText = l.shamellNoMessagesYet;
                  }
                }

                String formatMentions(String text) {
                  final mentionReg = RegExp(r'@([A-Za-z0-9_-]{2,})');
                  final mentionWsReg = RegExp(r'\s');
                  if (!text.contains('@')) return text;
                  return text.replaceAllMapped(mentionReg, (mm) {
                    if (mm.start > 0 &&
                        !mentionWsReg.hasMatch(text[mm.start - 1])) {
                      return mm.group(0) ?? '';
                    }
                    final raw = (mm.group(1) ?? '').trim();
                    if (raw.isEmpty) return mm.group(0) ?? '';
                    if (raw.toLowerCase() == 'all') {
                      return l.isArabic ? '@الكل' : '@all';
                    }
                    return '@${displayName(raw, fallback: raw)}';
                  });
                }

                previewText = formatMentions(previewText);

                final senderLabel = displayName(m.senderId, fallback: '');

                if (senderLabel.isNotEmpty && previewText.isNotEmpty) {
                  return '$senderLabel: $previewText';
                }
                return previewText;
              }

              Widget groupPreviewWidget(
                ChatGroupMessage? m, {
                required ThemeData theme,
                required TextStyle style,
              }) {
                if (m == null) {
                  return Text(
                    l.shamellNoMessagesYet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  );
                }
                final kind = (m.kind ?? '').toLowerCase();
                if (kind == 'system' || kind == 'sealed' || kind == 'voice') {
                  return Text(
                    groupPreview(m),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  );
                }

                final mime = (m.attachmentMime ?? '').toLowerCase();
                final isImage = kind == 'image' || mime.startsWith('image/');
                final rawText = isImage ? m.text.trim() : m.text;
                final mentionReg = RegExp(r'@([A-Za-z0-9_-]{2,})');
                final mentionWsReg = RegExp(r'\s');
                const arabicAllToken = '@الكل';
                bool hasArabicAllMention(String text) {
                  if (!text.contains(arabicAllToken)) return false;
                  var idx = text.indexOf(arabicAllToken);
                  while (idx != -1) {
                    if (idx == 0 || mentionWsReg.hasMatch(text[idx - 1])) {
                      return true;
                    }
                    idx = text.indexOf(
                        arabicAllToken, idx + arabicAllToken.length);
                  }
                  return false;
                }

                final hasMentions = rawText.contains('@') &&
                    (hasArabicAllMention(rawText) ||
                        mentionReg.allMatches(rawText).any((mm) =>
                            mm.start == 0 ||
                            mentionWsReg.hasMatch(rawText[mm.start - 1])));
                if (!hasMentions) {
                  return Text(
                    groupPreview(m),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  );
                }

                const mentionBlueLight = Color(0xFF576B95);
                const mentionBlueDark = Color(0xFF93C5FD);
                final mentionColor = theme.brightness == Brightness.dark
                    ? mentionBlueDark
                    : mentionBlueLight;
                final meIdLower = (_me?.id ?? '').trim().toLowerCase();
                final mentionStyle = style.copyWith(
                  color: mentionColor,
                  fontWeight: FontWeight.w700,
                );
                final mentionHighlightStyle = mentionStyle.copyWith(
                  fontWeight: FontWeight.w800,
                );

                List<InlineSpan> spansForText(String text) {
                  final spans = <InlineSpan>[];
                  final matches = <({int start, int end, String rawId})>[];

                  for (final mm in mentionReg.allMatches(text)) {
                    if (mm.start > 0 &&
                        !mentionWsReg.hasMatch(text[mm.start - 1])) {
                      continue;
                    }
                    final rawId = (mm.group(1) ?? '').trim();
                    if (rawId.isEmpty) continue;
                    matches.add((start: mm.start, end: mm.end, rawId: rawId));
                  }

                  var idx = text.indexOf(arabicAllToken);
                  while (idx != -1) {
                    if (idx == 0 || mentionWsReg.hasMatch(text[idx - 1])) {
                      matches.add((
                        start: idx,
                        end: idx + arabicAllToken.length,
                        rawId: 'all',
                      ));
                    }
                    idx = text.indexOf(
                        arabicAllToken, idx + arabicAllToken.length);
                  }

                  matches.sort((a, b) => a.start.compareTo(b.start));
                  if (matches.isEmpty) {
                    return <InlineSpan>[TextSpan(text: text)];
                  }
                  var last = 0;
                  for (final mm in matches) {
                    if (mm.start > last) {
                      spans.add(TextSpan(text: text.substring(last, mm.start)));
                    }
                    final raw = mm.rawId.trim();
                    final rawLower = raw.toLowerCase();
                    final spanStyle = (rawLower == 'all' ||
                            (meIdLower.isNotEmpty && rawLower == meIdLower))
                        ? mentionHighlightStyle
                        : mentionStyle;
                    if (raw.isEmpty) {
                      spans.add(TextSpan(
                        text: text.substring(mm.start, mm.end),
                        style: spanStyle,
                      ));
                    } else if (rawLower == 'all') {
                      spans.add(TextSpan(
                        text: l.isArabic ? '@الكل' : '@all',
                        style: spanStyle,
                      ));
                    } else {
                      spans.add(TextSpan(
                        text: '@${displayName(raw, fallback: raw)}',
                        style: spanStyle,
                      ));
                    }
                    last = mm.end;
                  }
                  if (last < text.length) {
                    spans.add(TextSpan(text: text.substring(last)));
                  }
                  return spans;
                }

                final senderLabel = displayName(m.senderId, fallback: '');
                final spans = <InlineSpan>[];
                if (senderLabel.isNotEmpty) {
                  spans.add(TextSpan(text: '$senderLabel: '));
                }
                if (isImage) {
                  spans.add(TextSpan(text: l.shamellPreviewImage));
                  if (rawText.isNotEmpty) {
                    spans.add(const TextSpan(text: ' '));
                  }
                }
                spans.addAll(spansForText(rawText));

                return RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(style: style, children: spans),
                );
              }

              final visibleContacts =
                  sortedContacts.where(contactVisible).toList();
              final visibleGroups = _groups.where(groupVisible).toList();

              final threads = <({
                bool isGroup,
                ChatContact? c,
                ChatGroup? g,
                DateTime ts
              })>[];
              for (final c in visibleContacts) {
                threads.add((
                  isGroup: false,
                  c: c,
                  g: null,
                  ts: contactLastActivity(c)
                ));
              }
              for (final g in visibleGroups) {
                threads.add(
                    (isGroup: true, c: null, g: g, ts: groupLastActivity(g)));
              }

              threads.sort((a, b) {
                final ca = a.c;
                final cb = b.c;
                final aPinned = a.isGroup
                    ? (_groupPrefs[a.g!.id]?.pinned ?? false)
                    : (ca?.pinned ?? false);
                final bPinned = b.isGroup
                    ? (_groupPrefs[b.g!.id]?.pinned ?? false)
                    : (cb?.pinned ?? false);
                if (aPinned && bPinned) {
                  final aKey =
                      a.isGroup ? _groupUnreadKey(a.g!.id) : (ca?.id ?? '');
                  final bKey =
                      b.isGroup ? _groupUnreadKey(b.g!.id) : (cb?.id ?? '');
                  final aIdx = _pinnedChatOrder.indexOf(aKey);
                  final bIdx = _pinnedChatOrder.indexOf(bKey);
                  if (aIdx != -1 || bIdx != -1) {
                    if (aIdx == -1 && bIdx != -1) return 1;
                    if (aIdx != -1 && bIdx == -1) return -1;
                    return aIdx.compareTo(bIdx);
                  }
                }
                if (aPinned != bPinned) {
                  return (bPinned ? 1 : 0) - (aPinned ? 1 : 0);
                }
                final aFeatured =
                    ca != null && _featuredOfficialPeerIds.contains(ca.id);
                final bFeatured =
                    cb != null && _featuredOfficialPeerIds.contains(cb.id);
                if (aFeatured != bFeatured) {
                  return (bFeatured ? 1 : 0) - (aFeatured ? 1 : 0);
                }
                final aStarred = ca?.starred ?? false;
                final bStarred = cb?.starred ?? false;
                if (aStarred != bStarred) {
                  return (bStarred ? 1 : 0) - (aStarred ? 1 : 0);
                }
                return b.ts.compareTo(a.ts);
              });

              if (threads.isEmpty) {
                final theme = Theme.of(context);
                final bool hasSearch = term.isNotEmpty;
                final bool inArchivedView = _showArchived;
                if (!inArchivedView && !hasSearch) {
                  if (_showSubscriptionChatsOnly) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.subscriptions_outlined,
                            size: 34,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .35),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l.isArabic
                                ? 'لا توجد اشتراكات'
                                : 'No subscriptions',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .78),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.isArabic
                                ? 'أوقف خيار \"اشتراكات فقط\" لعرض كل الدردشات.'
                                : 'Turn off “Subscriptions only” to see all chats.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .55),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final archivedContacts = _contacts.where((c) =>
                      c.archived &&
                      c.id != _ShamellChatPageState._subscriptionsPeerId);
                  final archivedGroups =
                      _groups.where((g) => _archivedGroupIds.contains(g.id));
                  final archivedCount =
                      archivedContacts.length + archivedGroups.length;
                  if (archivedCount > 0) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.archive_outlined,
                            size: 34,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .35),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l.isArabic
                                ? 'كل الدردشات مؤرشفة'
                                : 'All chats are archived',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .78),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.isArabic
                                ? 'اسحب للأسفل لعرض \"الدردشات المؤرشفة\".'
                                : 'Pull down to view “Archived Chats”.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .55),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18.0),
                  child: Column(
                    children: [
                      Icon(
                        hasSearch ? Icons.search_off : Icons.archive_outlined,
                        size: 34,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .35),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hasSearch
                            ? (l.isArabic ? 'لا توجد نتائج' : 'No results')
                            : (l.isArabic
                                ? 'لا توجد دردشات مؤرشفة'
                                : 'No archived chats'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .78),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasSearch
                            ? (l.isArabic
                                ? 'جرّب البحث بكلمة أخرى.'
                                : 'Try a different search.')
                            : (l.isArabic
                                ? 'ستظهر الدردشات التي تقوم بأرشفتها هنا.'
                                : 'Chats you archive will show up here.'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return SlidableAutoCloseBehavior(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (ctx2, i) {
                    final item = threads[i];
                    final theme = Theme.of(context);
                    if (item.isGroup) {
                      final g = item.g!;
                      final gid = g.id;
                      Uint8List? avatarBytes;
                      final gAvatar = g.avatarB64;
                      if (gAvatar != null && gAvatar.isNotEmpty) {
                        try {
                          avatarBytes = base64Decode(gAvatar);
                        } catch (_) {}
                      }
                      final thread =
                          _groupCache[gid] ?? const <ChatGroupMessage>[];
                      final last = thread.isNotEmpty ? thread.last : null;
                      final unread = _unread[_groupUnreadKey(gid)] ?? 0;
                      final muted = _groupPrefs[gid]?.muted ?? false;
                      final pinned = _groupPrefs[gid]?.pinned ?? false;
                      final archived = _archivedGroupIds.contains(gid);
                      final mentionUnread = _groupMentionUnread.contains(gid);
                      final hasUnread = unread != 0;
                      final Color subtitleColor = hasUnread
                          ? theme.colorScheme.onSurface.withValues(alpha: .90)
                          : theme.colorScheme.onSurface
                              .withValues(alpha: muted ? .45 : .70);
                      final FontWeight previewWeight =
                          hasUnread ? FontWeight.w600 : FontWeight.w400;
                      String ts = '';
                      if (last?.createdAt != null) {
                        final dt = last!.createdAt!.toLocal();
                        final now = DateTime.now();
                        if (dt.year == now.year &&
                            dt.month == now.month &&
                            dt.day == now.day) {
                          ts =
                              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        } else {
                          ts =
                              '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                        }
                      }
                      const shamellUnreadRed = Color(0xFFFA5151);
                      final bulkId = _groupUnreadKey(gid);
                      final bool bulkSelected =
                          _selectionMode && _selectedChatIds.contains(bulkId);
                      Widget leading;
                      if (_selectionMode) {
                        leading = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: bulkSelected,
                              onChanged: (_) => _toggleChatSelected(bulkId),
                            ),
                            _buildShamellAvatarBox(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: avatarBytes != null
                                  ? Image.memory(
                                      avatarBytes,
                                      width: _shamellThreadAvatarRadius * 2,
                                      height: _shamellThreadAvatarRadius * 2,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    )
                                  : const Icon(Icons.groups_outlined, size: 20),
                            ),
                          ],
                        );
                      } else {
                        leading = Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildShamellAvatarBox(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: avatarBytes != null
                                  ? Image.memory(
                                      avatarBytes,
                                      width: _shamellThreadAvatarRadius * 2,
                                      height: _shamellThreadAvatarRadius * 2,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    )
                                  : const Icon(Icons.groups_outlined, size: 20),
                            ),
                            if (hasUnread)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: (unread < 0 || (muted && unread > 0))
                                    ? Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: shamellUnreadRed,
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: shamellUnreadRed,
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Center(
                                          child: Text(
                                            unread > 99 ? '99+' : '$unread',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10),
                                          ),
                                        ),
                                      ),
                              ),
                          ],
                        );
                      }
                      final tile = _buildShamellThreadTile(
                        leading: leading,
                        pinned: pinned,
                        muted: muted,
                        selected: _selectionMode ? bulkSelected : false,
                        ts: ts,
                        onTap: () async {
                          if (_selectionMode) {
                            _toggleChatSelected(bulkId);
                            return;
                          }
                          final didSend = await Navigator.push<bool?>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupChatPage(
                                baseUrl: widget.baseUrl,
                                groupId: gid,
                                groupName: g.name,
                              ),
                            ),
                          );
                          await _syncGroups();
                          if (!mounted) return;
                          if (didSend == true) {
                            final next = Set<String>.from(_archivedGroupIds);
                            if (next.remove(gid)) {
                              _applyState(() {
                                _archivedGroupIds = next;
                                _showArchived = false;
                                _chatSearch = '';
                              });
                              _chatSearchCtrl.clear();
                              unawaited(_persistArchivedGroups());
                            } else if (_showArchived) {
                              _applyState(() {
                                _showArchived = false;
                                _chatSearch = '';
                              });
                              _chatSearchCtrl.clear();
                            }
                          }
                        },
                        onLongPressAt: (pos) {
                          if (_selectionMode) {
                            _toggleChatSelected(bulkId);
                          } else {
                            unawaited(_onGroupLongPress(
                              g,
                              globalPosition: pos,
                            ));
                          }
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                g.name.isNotEmpty ? g.name : gid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (archived && !_showArchived)
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: Icon(
                                  Icons.archive_outlined,
                                  size: 14,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .45),
                                ),
                              ),
                          ],
                        ),
                        subtitle: () {
                          final baseStyle = theme.textTheme.bodySmall ??
                              const TextStyle(fontSize: 12);
                          final previewStyle = baseStyle.copyWith(
                            fontSize: 13,
                            fontWeight: previewWeight,
                            color: subtitleColor,
                          );
                          final previewWidget = groupPreviewWidget(
                            last,
                            theme: theme,
                            style: previewStyle,
                          );
                          if (!mentionUnread || unread <= 0) {
                            return previewWidget;
                          }
                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: shamellUnreadRed,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _groupMentionAllUnread.contains(gid)
                                      ? (l.isArabic ? '@الكل' : '@all')
                                      : '@',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: previewWidget),
                            ],
                          );
                        }(),
                      );
                      return _buildSwipeableGroupThreadTile(g, tile);
                    }

                    const shamellUnreadRed = Color(0xFFFA5151);
                    final c = item.c!;
                    final isActive = c.id == _activePeerId;
                    final unread = _unread[c.id] ?? 0;
                    final hasUnread = unread != 0;
                    final thread = _cache[c.id];
                    final last = thread != null && thread.isNotEmpty
                        ? thread.last
                        : null;
                    String preview = last != null
                        ? _previewText(last)
                        : l.shamellNoMessagesYet;
                    try {
                      final calls = _lastCallsCache ?? [];
                      final callsForPeer =
                          calls.where((e) => e.peerId == c.id).toList();
                      if (callsForPeer.isNotEmpty) {
                        callsForPeer.sort((a, b) => b.ts.compareTo(a.ts));
                        final lastCall = callsForPeer.first;
                        final msgTs = last?.createdAt ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        if (lastCall.ts.isAfter(msgTs)) {
                          final isOut = lastCall.direction == 'out';
                          final missed = !lastCall.accepted;
                          final kindLabel = lastCall.kind == 'video'
                              ? (l.isArabic ? 'فيديو' : 'Video')
                              : (l.isArabic ? 'صوت' : 'Voice');
                          String status;
                          if (missed) {
                            status =
                                l.isArabic ? 'مكالمة فائتة' : 'Missed call';
                          } else if (lastCall.duration.inMinutes > 0) {
                            status = '${lastCall.duration.inMinutes}m';
                          } else {
                            status =
                                '${lastCall.duration.inSeconds.remainder(60)}s';
                          }
                          preview =
                              '${isOut ? (l.isArabic ? 'صادر' : 'Outgoing') : (l.isArabic ? 'وارد' : 'Incoming')} $kindLabel • $status';
                        }
                      }
                    } catch (_) {}
                    String ts = '';
                    if (last?.createdAt != null) {
                      final dt = last!.createdAt!.toLocal();
                      final now = DateTime.now();
                      if (dt.year == now.year &&
                          dt.month == now.month &&
                          dt.day == now.day) {
                        ts =
                            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                      } else {
                        ts =
                            '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                      }
                    }
                    final isOfficial = _officialPeerIds.contains(c.id);
                    final hasFeedUnread =
                        _officialPeerUnreadFeeds.contains(c.id);
                    final isFeaturedOfficial =
                        _featuredOfficialPeerIds.contains(c.id);
                    final Color subtitleColor = hasUnread
                        ? theme.colorScheme.onSurface.withValues(alpha: .90)
                        : (c.muted
                            ? theme.colorScheme.onSurface.withValues(alpha: .45)
                            : theme.colorScheme.onSurface
                                .withValues(alpha: .70));
                    final FontWeight previewWeight =
                        hasUnread ? FontWeight.w600 : FontWeight.w400;
                    final bool bulkSelected =
                        _selectionMode && _selectedChatIds.contains(c.id);
                    Widget leading;
                    if (_selectionMode) {
                      leading = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: bulkSelected,
                            onChanged: (_) => _toggleChatSelected(c.id),
                          ),
                          _buildShamellAvatarBox(
                            backgroundColor: c.verified
                                ? Tokens.colorPayments.withValues(alpha: .20)
                                : Tokens.accent.withValues(alpha: .15),
                            child: Text(
                              c.name != null && c.name!.isNotEmpty
                                  ? c.name!.substring(0, 1).toUpperCase()
                                  : c.id.substring(0, 1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      leading = Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildShamellAvatarBox(
                            backgroundColor: c.verified
                                ? Tokens.colorPayments.withValues(alpha: .20)
                                : Tokens.accent.withValues(alpha: .15),
                            child: Text(
                              c.name != null && c.name!.isNotEmpty
                                  ? c.name!.substring(0, 1).toUpperCase()
                                  : c.id.substring(0, 1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (hasUnread)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: (unread < 0 || (c.muted && unread > 0))
                                  ? Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: shamellUnreadRed,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: shamellUnreadRed,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      child: Center(
                                        child: Text(
                                          unread > 99 ? '99+' : '$unread',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10),
                                        ),
                                      ),
                                    ),
                            ),
                        ],
                      );
                    }
                    final tile = _buildShamellThreadTile(
                      leading: leading,
                      pinned: c.pinned,
                      muted: c.muted,
                      selected: _selectionMode ? bulkSelected : isActive,
                      ts: ts,
                      onTap: () {
                        if (_selectionMode) {
                          _toggleChatSelected(c.id);
                        } else {
                          _switchPeer(c);
                        }
                      },
                      onLongPressAt: (pos) {
                        if (_selectionMode) {
                          _toggleChatSelected(c.id);
                        } else {
                          unawaited(_onChatLongPress(
                            c,
                            globalPosition: pos,
                          ));
                        }
                      },
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name ?? c.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isOfficial)
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.verified_outlined,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          else if (c.verified)
                            const Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.verified,
                                size: 16,
                                color: Tokens.colorPayments,
                              ),
                            ),
                          if (isFeaturedOfficial)
                            const Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.star,
                                size: 16,
                                color: Tokens.colorPayments,
                              ),
                            ),
                          if (hasFeedUnread)
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.brightness_1,
                                size: 8,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          if (c.archived && !_showArchived)
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.archive_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .45),
                              ),
                            ),
                          if (c.hidden)
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.lock,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .45),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Expanded(
                            child: () {
                              final draftSnap = _composerDraftByChatId[c.id];
                              final draftText =
                                  (_draftTextByChatId[c.id] ?? '').trim();
                              final hasDraft = draftText.isNotEmpty ||
                                  (draftSnap?.hasAttachment ?? false);
                              final draftPreview = draftText.isNotEmpty
                                  ? draftText
                                  : (draftSnap?.hasAttachment ?? false)
                                      ? l.shamellPreviewImage
                                      : '';
                              final baseStyle =
                                  theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 13,
                                        color: subtitleColor,
                                        fontWeight: previewWeight,
                                      ) ??
                                      TextStyle(
                                        fontSize: 13,
                                        color: subtitleColor,
                                        fontWeight: previewWeight,
                                      );
                              if (!hasDraft) {
                                return Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: baseStyle,
                                );
                              }
                              final label = l.isArabic ? 'مسودة' : 'Draft';
                              return RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: baseStyle,
                                  children: [
                                    TextSpan(
                                      text: label,
                                      style: baseStyle.copyWith(
                                        color: shamellUnreadRed,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const TextSpan(text: ' '),
                                    TextSpan(text: draftPreview),
                                  ],
                                ),
                              );
                            }(),
                          ),
                        ],
                      ),
                    );
                    return _buildSwipeableChatTile(c, tile);
                  },
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: _shamellThreadDividerIndent,
                    endIndent: 0,
                  ),
                  itemCount: threads.length,
                ),
              );
            }),
          ],
          if (_selectionMode) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _selectedChatIds.isEmpty
                          ? null
                          : (_showArchived
                              ? _unarchiveSelectedChats
                              : _markSelectedChatsRead),
                      child: Text(
                        _showArchived
                            ? (l.isArabic ? 'إلغاء الأرشفة' : 'Unarchive')
                            : (l.isArabic ? 'وضع مقروء' : 'Mark read'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: .10),
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: _selectedChatIds.isEmpty
                          ? null
                          : _deleteSelectedChats,
                      child: Text(
                        l.isArabic ? 'حذف الدردشات' : 'Delete chats',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _clearChatSelection,
                  child: Text(
                    l.isArabic
                        ? 'إلغاء التحديد (${_selectedChatIds.length})'
                        : 'Cancel (${_selectedChatIds.length})',
                  ),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Future<void> _clearGroupConversation(ChatGroup g) async {
    final me = _me;
    if (me == null) return;
    final gid = g.id.trim();
    if (gid.isEmpty) return;
    final now = DateTime.now();
    try {
      await _store.setGroupSeen(gid, now);
    } catch (_) {}
    try {
      await _store.deleteGroupMessages(gid);
    } catch (_) {}
    final unreadKey = _groupUnreadKey(gid);
    final nextUnread = Map<String, int>.from(_unread);
    nextUnread[unreadKey] = 0;
    final nextMentions = Set<String>.from(_groupMentionUnread)..remove(gid);
    final nextMentionAll = Set<String>.from(_groupMentionAllUnread)
      ..remove(gid);
    _applyState(() {
      _groupCache.remove(gid);
      _unread = nextUnread;
      _groupMentionUnread = nextMentions;
      _groupMentionAllUnread = nextMentionAll;
    });
    try {
      await _store.saveUnread(nextUnread);
    } catch (_) {}
  }

  Future<void> _showChatMoreSheet(ChatContact c) async {
    final l = L10n.of(context);
    final isMuted = c.muted;
    final isPinned = c.pinned;
    final isArchived = c.archived;
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

        final muteLabel = isMuted
            ? (l.isArabic ? 'إلغاء كتم' : 'Unmute')
            : (l.isArabic ? 'كتم' : 'Mute');
        final pinLabel = isPinned
            ? (l.isArabic ? 'إلغاء تثبيت' : 'Unpin')
            : (l.isArabic ? 'تثبيت' : 'Pin');
        final archiveLabel = isArchived
            ? (l.isArabic ? 'إلغاء الأرشفة' : 'Unarchive')
            : (l.isArabic ? 'أرشفة' : 'Archive');
        final deleteLabel = l.isArabic ? 'حذف' : 'Delete';
        final cancelLabel = l.isArabic ? 'إلغاء' : 'Cancel';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                card([
                  actionRow(
                    label: muteLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleChatMuted(c));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleChatPinned(c));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: archiveLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleChatArchived(c));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_deleteChatById(c.id));
                    },
                  ),
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

  Future<void> _showGroupMoreSheet(ChatGroup g) async {
    final l = L10n.of(context);
    final prefs = _groupPrefs[g.id];
    final muted = prefs?.muted ?? false;
    final pinned = prefs?.pinned ?? false;
    final archived = _archivedGroupIds.contains(g.id);
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

        final muteLabel = muted
            ? (l.isArabic ? 'إلغاء كتم' : 'Unmute')
            : (l.isArabic ? 'كتم' : 'Mute');
        final pinLabel = pinned
            ? (l.isArabic ? 'إلغاء تثبيت' : 'Unpin')
            : (l.isArabic ? 'تثبيت' : 'Pin');
        final archiveLabel = archived
            ? (l.isArabic ? 'إلغاء الأرشفة' : 'Unarchive')
            : (l.isArabic ? 'أرشفة' : 'Archive');
        final deleteLabel = l.isArabic ? 'حذف' : 'Delete';
        final cancelLabel = l.isArabic ? 'إلغاء' : 'Cancel';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                card([
                  actionRow(
                    label: muteLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleGroupMuted(g));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleGroupPinned(g));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: archiveLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleGroupArchived(g));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_clearGroupConversation(g));
                    },
                  ),
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

  static const double _shamellSwipeActionWidth = 78.0;
  static const Duration _shamellSwipeResizeDuration =
      Duration(milliseconds: 200);
  static const Duration _shamellMoreSheetDelay = Duration(milliseconds: 90);
  static const double _shamellThreadAvatarRadius = 24.0;
  static const double _shamellThreadDividerIndent = 76.0;
  static const EdgeInsets _shamellThreadPadding =
      EdgeInsets.fromLTRB(16, 12, 12, 12);
  static const double _shamellAvatarCornerRadius = 10.0;

  Widget _buildShamellAvatarBox({
    required Widget child,
    required Color backgroundColor,
  }) {
    final size = _shamellThreadAvatarRadius * 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_shamellAvatarCornerRadius),
      child: Container(
        width: size,
        height: size,
        color: backgroundColor,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  double _shamellSwipeExtentRatio(double width, int actionCount) {
    if (width <= 0) {
      return actionCount <= 2 ? 0.40 : 0.72;
    }
    return ((_shamellSwipeActionWidth * actionCount) / width).clamp(0.0, 0.92);
  }

  double _shamellSwipeSnapThreshold(double width) {
    if (width <= 0) return 0.16;
    final px = _shamellSwipeActionWidth * 0.70;
    return (px / width).clamp(0.10, 0.18);
  }

  Widget _buildShamellThreadTile({
    required Widget leading,
    required Widget title,
    required Widget subtitle,
    required String ts,
    required bool pinned,
    required bool muted,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    ValueChanged<Offset>? onLongPressAt,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseBg = isDark ? theme.colorScheme.surface : Colors.white;
    final pinnedBg = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35)
        : const Color(0xFFF2F2F2);
    final selectedBg =
        theme.colorScheme.primary.withValues(alpha: isDark ? .18 : .10);
    final bg = selected ? selectedBg : (pinned ? pinnedBg : baseBg);
    final tileHeight =
        _shamellThreadAvatarRadius * 2 + _shamellThreadPadding.vertical;
    Offset? tapDownGlobalPosition;
    final hasLongPress = onLongPressAt != null || onLongPress != null;

    return Material(
      color: bg,
      child: InkWell(
        onTapDown: onLongPressAt == null
            ? null
            : (d) {
                tapDownGlobalPosition = d.globalPosition;
              },
        onTap: onTap,
        onLongPress: !hasLongPress
            ? null
            : () {
                final cb = onLongPressAt;
                if (cb != null) {
                  cb(tapDownGlobalPosition ?? Offset.zero);
                  return;
                }
                onLongPress?.call();
              },
        child: SizedBox(
          height: tileHeight,
          child: Padding(
            padding: _shamellThreadPadding,
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      subtitle,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ts.isNotEmpty
                        ? Text(
                            ts,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: muted
                                  ? theme.colorScheme.onSurface
                                      .withValues(alpha: .45)
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: .60),
                            ),
                          )
                        : const SizedBox.shrink(),
                    muted
                        ? Icon(
                            Icons.notifications_off_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .45),
                          )
                        : const SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeableSystemThreadTile({
    required String keyId,
    required bool hasUnread,
    required Future<void> Function() onToggleRead,
    required Future<void> Function() onDelete,
    required Widget child,
  }) {
    final l = L10n.of(context);
    if (_selectionMode || _showArchived) {
      return child;
    }
    const shamellGray = Color(0xFFC7C7CC);
    const shamellRed = Color(0xFFFA5151);
    return LayoutBuilder(builder: (ctx, constraints) {
      final width = constraints.maxWidth;
      final extentRatio = _shamellSwipeExtentRatio(width, 2);
      final snap = _shamellSwipeSnapThreshold(width);
      Widget action({
        required String label,
        required Color bg,
        required SlidableActionCallback onPressed,
        bool autoClose = true,
      }) {
        return CustomSlidableAction(
          onPressed: onPressed,
          autoClose: autoClose,
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }

      return Slidable(
        key: ValueKey<String>('sys_$keyId'),
        useTextDirection: false,
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: extentRatio,
          openThreshold: snap,
          closeThreshold: snap,
          children: [
            action(
              label: hasUnread
                  ? (l.isArabic ? 'مقروء' : 'Read')
                  : (l.isArabic ? 'غير مقروء' : 'Unread'),
              bg: shamellGray,
              onPressed: (_) => unawaited(onToggleRead()),
            ),
            action(
              label: l.isArabic ? 'حذف' : 'Delete',
              bg: shamellRed,
              autoClose: false,
              onPressed: (ctx2) {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  unawaited(onDelete());
                  return;
                }
                unawaited(controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () => unawaited(onDelete()),
                  ),
                ));
              },
            ),
          ],
        ),
        child: child,
      );
    });
  }

  Widget _buildSwipeableGroupThreadTile(ChatGroup g, Widget child) {
    final l = L10n.of(context);
    final unreadKey = _groupUnreadKey(g.id);
    final bool hasUnread = (_unread[unreadKey] ?? 0) != 0;
    if (_selectionMode) {
      return child;
    }
    if (_showArchived) {
      const shamellGray = Color(0xFFC7C7CC);
      const shamellRed = Color(0xFFFA5151);
      return LayoutBuilder(builder: (ctx, constraints) {
        final width = constraints.maxWidth;
        final extentRatio = _shamellSwipeExtentRatio(width, 2);
        final snap = _shamellSwipeSnapThreshold(width);
        Widget action({
          required String label,
          required Color bg,
          required SlidableActionCallback onPressed,
          bool autoClose = true,
        }) {
          return CustomSlidableAction(
            onPressed: onPressed,
            autoClose: autoClose,
            backgroundColor: bg,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return Slidable(
          key: ValueKey<String>('grp_${g.id}'),
          useTextDirection: false,
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: extentRatio,
            openThreshold: snap,
            closeThreshold: snap,
            children: [
              action(
                label: l.isArabic ? 'إلغاء الأرشفة' : 'Unarchive',
                bg: shamellGray,
                autoClose: false,
                onPressed: (ctx2) {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    unawaited(_toggleGroupArchived(g));
                    return;
                  }
                  unawaited(controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {
                        unawaited(_toggleGroupArchived(g));
                      },
                    ),
                  ));
                },
              ),
              action(
                label: l.isArabic ? 'حذف' : 'Delete',
                bg: shamellRed,
                autoClose: false,
                onPressed: (ctx2) {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    unawaited(_clearGroupConversation(g));
                    return;
                  }
                  unawaited(controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {
                        unawaited(_clearGroupConversation(g));
                      },
                    ),
                  ));
                },
              ),
            ],
          ),
          child: child,
        );
      });
    }
    final prefs = _groupPrefs[g.id];
    final pinned = prefs?.pinned ?? false;
    const shamellGray = Color(0xFFC7C7CC);
    const shamellOrange = Color(0xFFF7B500);
    const shamellRed = Color(0xFFFA5151);
    return LayoutBuilder(builder: (ctx, constraints) {
      final width = constraints.maxWidth;
      final extentRatio = _shamellSwipeExtentRatio(width, 3);
      final snap = _shamellSwipeSnapThreshold(width);
      Widget action({
        required String label,
        required Color bg,
        required SlidableActionCallback onPressed,
        bool autoClose = true,
      }) {
        return CustomSlidableAction(
          onPressed: onPressed,
          autoClose: autoClose,
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }

      return Slidable(
        key: ValueKey<String>('grp_${g.id}'),
        useTextDirection: false,
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: extentRatio,
          openThreshold: snap,
          closeThreshold: snap,
          children: [
            action(
              label: hasUnread
                  ? (l.isArabic ? 'مقروء' : 'Read')
                  : (l.isArabic ? 'غير مقروء' : 'Unread'),
              bg: shamellGray,
              onPressed: (_) {
                unawaited(_toggleGroupReadUnread(g));
              },
            ),
            action(
              label: pinned
                  ? (l.isArabic ? 'إلغاء تثبيت' : 'Unpin')
                  : (l.isArabic ? 'تثبيت' : 'Pin'),
              bg: shamellOrange,
              onPressed: (_) {
                unawaited(_toggleGroupPinned(g));
              },
            ),
            action(
              label: l.isArabic ? 'حذف' : 'Delete',
              bg: shamellRed,
              autoClose: false,
              onPressed: (ctx2) {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  unawaited(_clearGroupConversation(g));
                  return;
                }
                unawaited(controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {
                      unawaited(_clearGroupConversation(g));
                    },
                  ),
                ));
              },
            ),
          ],
        ),
        child: child,
      );
    });
  }

  Widget _buildSwipeableChatTile(ChatContact c, Widget child) {
    final l = L10n.of(context);
    final bool hasUnread = (_unread[c.id] ?? 0) != 0;
    if (_selectionMode) {
      return child;
    }
    if (_showArchived) {
      const shamellGray = Color(0xFFC7C7CC);
      const shamellRed = Color(0xFFFA5151);
      return LayoutBuilder(builder: (ctx, constraints) {
        final width = constraints.maxWidth;
        final extentRatio = _shamellSwipeExtentRatio(width, 2);
        final snap = _shamellSwipeSnapThreshold(width);
        Widget action({
          required String label,
          required Color bg,
          required SlidableActionCallback onPressed,
          bool autoClose = true,
        }) {
          return CustomSlidableAction(
            onPressed: onPressed,
            autoClose: autoClose,
            backgroundColor: bg,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return Slidable(
          key: ValueKey<String>('chat_${c.id}'),
          useTextDirection: false,
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: extentRatio,
            openThreshold: snap,
            closeThreshold: snap,
            children: [
              action(
                label: l.isArabic ? 'إلغاء الأرشفة' : 'Unarchive',
                bg: shamellGray,
                autoClose: false,
                onPressed: (ctx2) {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    unawaited(_toggleChatArchived(c));
                    return;
                  }
                  unawaited(controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {
                        unawaited(_toggleChatArchived(c));
                      },
                    ),
                  ));
                },
              ),
              action(
                label: l.isArabic ? 'حذف' : 'Delete',
                bg: shamellRed,
                autoClose: false,
                onPressed: (ctx2) {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    unawaited(_deleteChatById(c.id));
                    return;
                  }
                  unawaited(controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {
                        unawaited(_deleteChatById(c.id));
                      },
                    ),
                  ));
                },
              ),
            ],
          ),
          child: child,
        );
      });
    }
    final isPinned = c.pinned;
    const shamellGray = Color(0xFFC7C7CC);
    const shamellOrange = Color(0xFFF7B500);
    const shamellRed = Color(0xFFFA5151);
    return LayoutBuilder(builder: (ctx, constraints) {
      final width = constraints.maxWidth;
      final extentRatio = _shamellSwipeExtentRatio(width, 3);
      final snap = _shamellSwipeSnapThreshold(width);
      Widget action({
        required String label,
        required Color bg,
        required SlidableActionCallback onPressed,
        bool autoClose = true,
      }) {
        return CustomSlidableAction(
          onPressed: onPressed,
          autoClose: autoClose,
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }

      return Slidable(
        key: ValueKey<String>('chat_${c.id}'),
        useTextDirection: false,
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: extentRatio,
          openThreshold: snap,
          closeThreshold: snap,
          children: [
            action(
              label: hasUnread
                  ? (l.isArabic ? 'مقروء' : 'Read')
                  : (l.isArabic ? 'غير مقروء' : 'Unread'),
              bg: shamellGray,
              onPressed: (_) {
                unawaited(_toggleChatReadUnread(c));
              },
            ),
            action(
              label: isPinned
                  ? (l.isArabic ? 'إلغاء تثبيت' : 'Unpin')
                  : (l.isArabic ? 'تثبيت' : 'Pin'),
              bg: shamellOrange,
              onPressed: (_) {
                unawaited(_toggleChatPinned(c));
              },
            ),
            action(
              label: l.isArabic ? 'حذف' : 'Delete',
              bg: shamellRed,
              autoClose: false,
              onPressed: (ctx2) {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  unawaited(_deleteChatById(c.id));
                  return;
                }
                unawaited(controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {
                      unawaited(_deleteChatById(c.id));
                    },
                  ),
                ));
              },
            ),
          ],
        ),
        child: child,
      );
    });
  }

  // Helper kept for future use in profile view; currently not wired.
  // ignore: unused_element
  Widget _contactCard(ChatContact? peer) {
    final verified = peer?.verified ?? false;
    final l = L10n.of(context);
    return _block(
        title: l.chatPeer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _peerIdCtrl,
              decoration: InputDecoration(
                  labelText: l.shamellPeerIdLabel,
                  suffixIcon: IconButton(
                      onPressed: _scanQr,
                      icon: const Icon(Icons.qr_code_scanner))),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: FilledButton(
                      onPressed: _resolvePeer, child: Text(l.shamellResolve))),
              const SizedBox(width: 8),
              Expanded(
                  child: FilledButton.tonal(
                      onPressed: verified ? null : _markVerified,
                      child: Text(verified
                          ? l.shamellVerifiedLabel
                          : l.shamellMarkVerifiedLabel))),
            ]),
            const SizedBox(height: 8),
            if (peer != null)
              Row(
                children: [
                  Expanded(
                      child: FilledButton.tonal(
                          onPressed: () async {
                            final next = !_disappearing;
                            _applyState(() {
                              _disappearing = next;
                            });
                            final updated = peer.copyWith(
                                disappearing: next,
                                disappearAfter: _disappearAfter);
                            final contacts = _upsertContact(updated);
                            await _store.saveContacts(contacts);
                            _applyState(() {
                              _peer = updated;
                              _contacts = contacts;
                            });
                          },
                          child: Text(_disappearing
                              ? l.shamellDisableDisappear
                              : l.shamellEnableDisappear))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DropdownButtonFormField<Duration>(
                    initialValue: _disappearAfter,
                    decoration:
                        InputDecoration(labelText: l.shamellDisappearAfter),
                    items: const [
                      Duration(minutes: 5),
                      Duration(minutes: 30),
                      Duration(hours: 1),
                      Duration(hours: 6),
                      Duration(days: 1),
                    ]
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(_fmtDuration(d)),
                            ))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      _applyState(() => _disappearAfter = v);
                      final updated = peer.copyWith(
                          disappearAfter: v, disappearing: _disappearing);
                      final contacts = _upsertContact(updated);
                      await _store.saveContacts(contacts);
                      _applyState(() {
                        _peer = updated;
                        _contacts = contacts;
                      });
                    },
                  )),
                ],
              ),
            const SizedBox(height: 8),
            if (peer != null)
              Row(
                children: [
                  Expanded(
                      child: FilledButton.tonal(
                          onPressed: () async {
                            final updated = peer.copyWith(hidden: !peer.hidden);
                            final contacts = _upsertContact(updated);
                            try {
                              await _service.setHidden(
                                  deviceId: _me?.id ?? '',
                                  peerId: peer.id,
                                  hidden: updated.hidden);
                            } catch (_) {}
                            await _store.saveContacts(contacts);
                            _applyState(() {
                              _peer = updated;
                              _contacts = contacts;
                              if (updated.hidden && !_showHidden) {
                                _activePeerId = null;
                                _peer = null;
                                _messages = [];
                              }
                            });
                          },
                          child: Text(peer.hidden
                              ? l.shamellUnhideChat
                              : l.shamellHideChat))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: FilledButton.tonal(
                          onPressed: () async {
                            final updated = peer.copyWith(
                                blocked: !peer.blocked,
                                blockedAt: DateTime.now());
                            final contacts = _upsertContact(updated);
                            try {
                              await _service.setBlock(
                                  deviceId: _me?.id ?? '',
                                  peerId: peer.id,
                                  blocked: updated.blocked,
                                  hidden: updated.hidden);
                            } catch (_) {}
                            await _store.saveContacts(contacts);
                            _applyState(() {
                              _peer = updated;
                              _contacts = contacts;
                              if (updated.blocked && _activePeerId == peer.id) {
                                _messages = [];
                              }
                            });
                          },
                          child: Text(peer.blocked
                              ? l.shamellUnblock
                              : l.shamellBlock))),
                ],
              ),
            if (peer != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.verified, color: _trustColor(peer)),
                  const SizedBox(width: 6),
                  Text(
                    peer.verified
                        ? l.shamellTrustedFingerprint
                        : l.shamellUnverifiedContact,
                    style: TextStyle(
                        color: _trustColor(peer), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${l.shamellPeerFingerprintLabel} ${peer.fingerprint}'),
              const SizedBox(height: 4),
              Text(
                  '${l.shamellYourFingerprintLabel} ${_me?.fingerprint ?? ''}'),
              const SizedBox(height: 8),
              if (_safetyNumber != null)
                Row(
                  children: [
                    Expanded(
                        child: Text(
                            '${l.shamellSafetyLabel} ${_safetyNumber!.formatted}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]))),
                    IconButton(
                        tooltip: l.shamellResetSessionLabel,
                        onPressed: _resetSession,
                        icon: const Icon(Icons.refresh)),
                  ],
                ),
            ]
          ],
        ));
  }

  Widget _subscriptionsCard() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final items = _subscriptionsFilterUnreadOnly
        ? _subscriptionsItems.where((e) => e.isUnread).toList()
        : _subscriptionsItems;
    return _block(
      title: l.shamellSubscriptionsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_subscriptionsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if ((_subscriptionsError ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _subscriptionsError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            )
          else if (_subscriptionsItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l.shamellSubscriptionsEmpty,
              ),
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.shamellSubscriptionsFilterAll),
                    selected: !_subscriptionsFilterUnreadOnly,
                    onSelected: (sel) {
                      if (!sel) return;
                      _applyState(() {
                        _subscriptionsFilterUnreadOnly = false;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Text(l.shamellSubscriptionsFilterUnread),
                    selected: _subscriptionsFilterUnreadOnly,
                    onSelected: (sel) {
                      if (!sel) return;
                      _applyState(() {
                        _subscriptionsFilterUnreadOnly = true;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _subscriptionsItems.isEmpty
                    ? null
                    : _markAllSubscriptionsRead,
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(
                  l.shamellSubscriptionsMarkAllRead,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.isArabic
                      ? 'لا توجد تحديثات غير مقروءة.'
                      : 'No unread updates.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final e = items[i];
                  return _buildSubscriptionItem(e);
                },
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _markAllSubscriptionsRead() async {
    if (_subscriptionsItems.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final rawSeen = sp.getString('official.feed_seen') ?? '{}';
      Map<String, dynamic> seenMap;
      try {
        seenMap = jsonDecode(rawSeen) as Map<String, dynamic>;
      } catch (_) {
        seenMap = <String, dynamic>{};
      }
      final latestPerAccount = <String, DateTime>{};
      for (final e in _subscriptionsItems) {
        final ts = e.ts;
        if (ts == null) continue;
        final prev = latestPerAccount[e.accountId];
        if (prev == null || ts.isAfter(prev)) {
          latestPerAccount[e.accountId] = ts;
        }
      }
      latestPerAccount.forEach((accId, ts) {
        seenMap[accId] = ts.toUtc().toIso8601String();
      });
      await sp.setString('official.feed_seen', jsonEncode(seenMap));
      unawaited(_loadOfficialPeers());
      _applyState(() {
        _subscriptionsFilterUnreadOnly = false;
        _subscriptionsItems = _subscriptionsItems
            .map(
              (e) => _SubscriptionEntry(
                accountId: e.accountId,
                accountName: e.accountName,
                accountAvatarUrl: e.accountAvatarUrl,
                accountKind: e.accountKind,
                chatPeerId: e.chatPeerId,
                itemId: e.itemId,
                title: e.title,
                snippet: e.snippet,
                thumbUrl: e.thumbUrl,
                ts: e.ts,
                isUnread: false,
              ),
            )
            .toList();
      });
    } catch (_) {}
  }

  Widget _chatCard(ChatIdentity? me, ChatContact? peer) {
    final l = L10n.of(context);
    if (peer != null && peer.id == _ShamellChatPageState._subscriptionsPeerId) {
      return _subscriptionsCard();
    }
    final String? newMessagesAnchorId =
        (peer != null && _newMessagesAnchorPeerId == peer.id)
            ? _newMessagesAnchorMessageId
            : null;
    final int newMessagesIndex = (!_messageSelectionMode &&
            newMessagesAnchorId != null &&
            newMessagesAnchorId.isNotEmpty)
        ? _messages.indexWhere((m) => m.id == newMessagesAnchorId)
        : -1;
    final bool showNewMessagesMarker =
        newMessagesIndex != -1 && _newMessagesCountAtOpen > 0;
    final themeKey =
        peer != null ? (_chatThemes[peer.id] ?? 'default') : 'default';
    final header = _buildOfficialChatHeader(peer);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color greenBase = Tokens.colorPayments;
    final Color chatBgColor;
    if (themeKey == 'dark') {
      chatBgColor = theme.colorScheme.surfaceContainerHighest
          .withValues(alpha: isDark ? .72 : .96);
    } else if (themeKey == 'green') {
      chatBgColor = greenBase.withValues(alpha: isDark ? .14 : .08);
    } else {
      chatBgColor =
          isDark ? theme.colorScheme.surface : const Color(0xFFEDEDED);
    }
    final BoxDecoration chatWallpaper = BoxDecoration(color: chatBgColor);
    return Container(
      decoration: chatWallpaper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ratchetWarning != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _ratchetBanner(),
            ),
          if (header != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: header,
            ),
            const SizedBox(height: 8),
          ],
          if (_messageSelectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.isArabic
                          ? 'تم تحديد ${_selectedMessageIds.length} رسائل'
                          : '${_selectedMessageIds.length} selected',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectedMessageIds.isEmpty
                        ? null
                        : () => _forwardSelectedMessages(),
                    child: Text(
                      l.isArabic ? 'إعادة توجيه' : 'Forward',
                    ),
                  ),
                  TextButton(
                    onPressed: _selectedMessageIds.isEmpty
                        ? null
                        : () => _deleteSelectedMessages(),
                    child: Text(
                      l.isArabic ? 'حذف' : 'Delete',
                    ),
                  ),
                  TextButton(
                    onPressed: _clearMessageSelection,
                    child: Text(
                      l.isArabic ? 'إلغاء' : l.shamellDialogCancel,
                    ),
                  ),
                ],
              ),
            ),
          if (peer != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildPinnedMessagesBanner(peer),
            ),
          Expanded(
            child: Stack(
              children: [
                if (_messages.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(peer == null
                          ? l.shamellAddContactFirst
                          : l.shamellNoMessagesYet),
                    ),
                  )
                else
                  ListView.separated(
                    controller: _threadScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      final showTimeHeader = _shouldShowShamellTimeHeader(i) &&
                          m.createdAt != null;
                      final msgKey = m.id.isNotEmpty
                          ? _messageKeys.putIfAbsent(
                              m.id,
                              () => GlobalKey(),
                            )
                          : null;
                      Widget bubble = Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _bubble(ctx, m, me),
                      );
                      if (msgKey != null) {
                        bubble = KeyedSubtree(key: msgKey, child: bubble);
                      }
                      final children = <Widget>[];
                      if (showTimeHeader) {
                        children.add(_buildShamellTimeHeader(m.createdAt!));
                      }
                      if (showNewMessagesMarker && i == newMessagesIndex) {
                        final theme = Theme.of(ctx);
                        final label = _newMessagesCountAtOpen <= 1
                            ? l.shamellNewMessageTitle
                            : (l.isArabic
                                ? '${_newMessagesCountAtOpen} رسائل جديدة'
                                : '${_newMessagesCountAtOpen} new messages');
                        final dividerColor =
                            theme.dividerColor.withValues(alpha: .35);
                        children.add(
                          Padding(
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest
                                        .withValues(alpha: .55),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    label,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: .65),
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
                          ),
                        );
                      }
                      children.add(bubble);
                      if (children.length == 1) {
                        return children.first;
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemCount: _messages.length,
                  ),
                if (!_threadNearBottom &&
                    _messages.isNotEmpty &&
                    _threadNewMessagesAwayCount > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: _buildThreadNewMessagesBar(),
                    ),
                  )
                else if (!_threadNearBottom && _messages.isNotEmpty)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _buildThreadJumpToBottomButton(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_replyToMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _previewText(_replyToMessage!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .75),
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.shamellDialogCancel,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _applyState(() {
                        _replyToMessage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surface
                  : ShamellPalette.background,
              border: Border(
                top: BorderSide(
                  color:
                      theme.dividerColor.withValues(alpha: isDark ? .20 : .45),
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
                          me == null ||
                          peer == null ||
                          peer.blocked ||
                          _recordingVoice)
                      ? null
                      : () {
                          final next = !_shamellVoiceMode;
                          _applyState(() {
                            _shamellVoiceMode = next;
                            _composerPanel = _ShamellComposerPanel.none;
                          });
                          if (next) {
                            FocusScope.of(context).unfocus();
                          } else {
                            _composerFocus.requestFocus();
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
                                    me == null ||
                                    peer == null ||
                                    peer.blocked)
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
                                  _applyState(() {
                                    _voiceCancelPending = cancelNow;
                                  });
                                }
                                if (dx > lockThreshold) {
                                  _applyState(() {
                                    _voiceLocked = true;
                                    _voiceCancelPending = false;
                                  });
                                }
                              }
                            },
                            onPanEnd: (_) async {
                              if (!_recordingVoice) return;
                              if (_voiceLocked) {
                                _applyState(() {
                                  _voiceGestureStartLocal = null;
                                  _voiceCancelPending = false;
                                });
                                return;
                              }
                              if (_voiceCancelPending) {
                                await _cancelVoiceRecord();
                                final l2 = L10n.of(context);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l2.shamellVoiceCanceledSnack,
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                await _stopVoiceRecord();
                              }
                              _applyState(() {
                                _voiceGestureStartLocal = null;
                                _voiceCancelPending = false;
                              });
                            },
                            onPanCancel: () async {
                              if (!_recordingVoice) return;
                              if (_voiceLocked) {
                                _applyState(() {
                                  _voiceGestureStartLocal = null;
                                  _voiceCancelPending = false;
                                });
                              } else {
                                await _cancelVoiceRecord();
                                _applyState(() {
                                  _voiceGestureStartLocal = null;
                                  _voiceCancelPending = false;
                                });
                              }
                            },
                            child: Builder(
                              builder: (context) {
                                final label = () {
                                  if (_recordingVoice && _voiceLocked) {
                                    return l.shamellVoiceLocked;
                                  }
                                  if (_recordingVoice && _voiceCancelPending) {
                                    return l.shamellVoiceReleaseToCancel;
                                  }
                                  if (_recordingVoice) {
                                    return l.shamellRecordingVoice;
                                  }
                                  return l.shamellVoiceHoldToTalk;
                                }();
                                final Color bg = (_recordingVoice &&
                                        _voiceCancelPending)
                                    ? Colors.redAccent.withValues(alpha: .14)
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
                                    style: theme.textTheme.bodyMedium?.copyWith(
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
                            constraints: const BoxConstraints(minHeight: 40),
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
                              focusNode: _composerFocus,
                              controller: _msgCtrl,
                              maxLines: 4,
                              minLines: 1,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                hintText: l.shamellTypeMessage,
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
                    final showSend =
                        value.text.trim().isNotEmpty || _attachedBytes != null;
                    if (showSend) {
                      final canSend = !(_sending ||
                          me == null ||
                          peer == null ||
                          peer.blocked ||
                          _recordingVoice);
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: canSend
                              ? ShamellPalette.green
                              : theme.disabledColor.withValues(alpha: .18),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          tooltip: l.chatSend,
                          padding: EdgeInsets.zero,
                          splashRadius: 18,
                          onPressed: canSend ? _send : null,
                          icon: Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: canSend
                                ? Colors.white
                                : theme.disabledColor.withValues(alpha: .75),
                          ),
                        ),
                      );
                    }
                    return IconButton(
                      tooltip: l.isArabic ? 'أداة إضافية' : 'More',
                      onPressed: (_loading ||
                              me == null ||
                              peer == null ||
                              peer.blocked)
                          ? null
                          : () {
                              _toggleComposerPanel(_ShamellComposerPanel.more);
                            },
                      icon: const Icon(Icons.add_circle_outline, size: 26),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_composerPanel == _ShamellComposerPanel.more &&
              me != null &&
              peer != null)
            _buildMorePanel(me, peer),
          if (_recordingVoice)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _voiceCancelPending
                            ? Colors.redAccent
                            : Colors.black.withValues(alpha: .70),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_voiceLocked) ...[
                                const Icon(Icons.lock,
                                    size: 14, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  l.shamellVoiceLocked,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  _voiceCancelPending
                                      ? l.shamellVoiceReleaseToCancel
                                      : l.shamellVoiceSlideUpToCancel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_voiceLocked) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    await _cancelVoiceRecord();
                                    final l2 = L10n.of(context);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              l2.shamellVoiceCanceledSnack),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    size: 14,
                                  ),
                                  label: Text(
                                    l.shamellDialogCancel,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    await _stopVoiceRecord();
                                  },
                                  icon: const Icon(
                                    Icons.send,
                                    size: 14,
                                  ),
                                  label: Text(
                                    l.chatSend,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Builder(builder: (ctx) {
                      final elapsed = _voiceElapsedSecs.clamp(0, 120);
                      const maxSecs = 120;
                      String _fmt(int s) =>
                          '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';
                      final label =
                          '${l.shamellRecordingVoice} • ${_fmt(elapsed)} / ${_fmt(maxSecs)}';
                      final remaining = maxSecs - elapsed;
                      final baseColor = Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .70);
                      final color =
                          remaining <= 10 ? Colors.redAccent : baseColor;
                      return Text(
                        label,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: color,
                            ),
                      );
                    }),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (ctx) {
                        if (!_recordingVoice) {
                          return const SizedBox.shrink();
                        }
                        final theme = Theme.of(ctx);
                        final baseColor = Colors.white
                            .withValues(alpha: _voiceCancelPending ? .9 : .7);
                        final bars = <Widget>[];
                        for (var i = 0; i < 6; i++) {
                          final phase = (_voiceWaveTick + i * 3) % 32;
                          final h = 8.0 + 6.0 * sin(phase * pi / 16).abs();
                          bars.add(
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 1.5),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 3,
                                height: h,
                                decoration: BoxDecoration(
                                  color: baseColor,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.black.withValues(alpha: .30)
                                          : Colors.black.withValues(alpha: .20),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        return SizedBox(
                          height: 22,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: bars,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (_attachedBytes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _attachedBytes!,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    _attachedName ?? l.shamellImageAttached,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
                  IconButton(
                      tooltip: l.shamellRemoveAttachment,
                      onPressed: () {
                        _applyState(() {
                          _attachedBytes = null;
                          _attachedMime = null;
                          _attachedName = null;
                        });
                      },
                      icon: const Icon(Icons.close))
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildThreadJumpToBottomButton() {
    final theme = Theme.of(context);
    const shamellUnreadRed = Color(0xFFFA5151);
    final count = _threadNewMessagesAwayCount;
    final bg = theme.colorScheme.surface.withValues(
      alpha: theme.brightness == Brightness.dark ? .86 : .94,
    );
    final fg = theme.colorScheme.onSurface.withValues(alpha: .74);
    Widget? badge;
    if (count > 0) {
      if (count == 1) {
        badge = Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: shamellUnreadRed,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      } else {
        badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: shamellUnreadRed,
            borderRadius: BorderRadius.circular(9),
          ),
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          child: Center(
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }

    return Material(
      color: bg,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _scrollThreadToBottom(force: true),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.keyboard_arrow_down, size: 22, color: fg),
              if (badge != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: badge,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedMessagesBanner(ChatContact peer) {
    final l = L10n.of(context);
    final pinnedIds = _pinnedMessageIdsByPeer[peer.id] ?? const <String>{};
    if (pinnedIds.isEmpty) return const SizedBox.shrink();
    final pinnedMessages = _messages
        .where(
          (m) =>
              pinnedIds.contains(m.id) && !_recalledMessageIds.contains(m.id),
        )
        .toList();
    if (pinnedMessages.isEmpty) return const SizedBox.shrink();
    final total = pinnedMessages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 16),
              const SizedBox(width: 6),
              Text(
                l.shamellPinnedMessagesTitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              Text(
                '($total)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .70),
                    ),
              ),
              const Spacer(),
              if (total > 3)
                Text(
                  l.isArabic ? 'عرض الكل' : 'View all',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: .85),
                      ),
                ),
            ],
          ),
        ),
        ...pinnedMessages.take(3).map((m) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _scrollToMessage(m.id),
              child: _bubble(context, m, _me),
            ),
          );
        }),
      ],
    );
  }

  Widget? _buildOfficialChatHeader(ChatContact? peer) {
    if (peer == null) return null;
    final official = _linkedOfficial;
    if (official == null) return null;
    final peerId = peer.id.trim();
    final linkedPeerId = (official.chatPeerId ?? '').trim();
    if (linkedPeerId.isNotEmpty && linkedPeerId != peerId) {
      return null;
    }
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final hasUnreadFeed = _officialPeerUnreadFeeds.contains(peerId);
    final isFollowed = _linkedOfficialFollowed;

    VoidCallback? openMiniApp;
    IconData? miniIcon;
    String? miniLabel;
    switch (official.miniAppId) {
      case 'bus':
        openMiniApp = _openBusService;
        miniIcon = Icons.directions_bus_filled_outlined;
        miniLabel = l.isArabic ? 'فتح الباص' : 'Open bus';
        break;
      case 'payments':
        openMiniApp = _openPayService;
        miniIcon = Icons.account_balance_wallet_outlined;
        miniLabel = l.isArabic ? 'فتح المحفظة' : 'Open wallet';
        break;
    }

    final subtitle = _officialSubtitle(official, l);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: .22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Tokens.colorPayments.withValues(alpha: .10),
            backgroundImage: official.avatarUrl != null &&
                    official.avatarUrl!.trim().isNotEmpty
                ? NetworkImage(official.avatarUrl!.trim())
                : null,
            child: (official.avatarUrl == null ||
                    official.avatarUrl!.trim().isEmpty)
                ? Text(
                    (official.name.isNotEmpty
                            ? official.name.substring(0, 1)
                            : (peer.name ?? peer.id).substring(0, 1))
                        .toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        official.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (official.verified)
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0),
                        child: Icon(
                          Icons.verified,
                          size: 16,
                          color: Tokens.colorPayments,
                        ),
                      ),
                    if (hasUnreadFeed)
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: Icon(
                          Icons.brightness_1,
                          size: 8,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Tokens.colorPayments.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.campaign_outlined,
                            size: 12,
                            color: Tokens.colorPayments,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l.isArabic ? 'حساب خدمة' : 'Service account',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (official.featured) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: theme.colorScheme.secondary,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (subtitle.isNotEmpty)
                      Expanded(
                        child: Text(
                          subtitle,
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton(
                      onPressed: _openOfficialFeedForPeer,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                      ),
                      child: Text(
                        l.isArabic ? 'الخلاصة' : 'Feed',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _openOfficialMomentsForPeer,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                      ),
                      child: Text(
                        l.isArabic ? 'اللحظات' : 'Moments',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (openMiniApp != null &&
                        miniIcon != null &&
                        miniLabel != null) ...[
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: openMiniApp,
                        icon: Icon(miniIcon, size: 14),
                        label: Text(
                          miniLabel,
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _toggleOfficialFollowFromChat,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(
                    color: Tokens.colorPayments,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  isFollowed
                      ? (l.isArabic ? 'إلغاء المتابعة' : 'Unfollow')
                      : (l.isArabic ? 'متابعة' : 'Follow'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip:
                    l.isArabic ? 'إعدادات الإشعارات' : 'Notification settings',
                icon: const Icon(Icons.more_horiz, size: 18),
                onPressed: () => _showPeerNotificationSheet(peer),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _officialSubtitle(OfficialAccountHandle official, L10n l) {
    final cat = (official.category ?? '').trim();
    final city = (official.city ?? '').trim();
    if (cat.isNotEmpty && city.isNotEmpty) {
      return '$cat • $city';
    }
    if (cat.isNotEmpty) return cat;
    if (city.isNotEmpty) return city;
    final desc = (official.description ?? '').trim();
    if (desc.isNotEmpty) return desc;
    return l.isArabic
        ? 'حساب خدمة مرتبط بهذه الدردشة'
        : 'Service account linked to this chat';
  }

  // ignore: unused_element
  Widget? _buildQuickServiceShortcuts(ChatContact? peer) {
    if (peer == null) return null;
    final id = peer.id;
    final l = L10n.of(context);
    final actions = <Map<String, Object>>[];
    if (id == 'shamell_pay') {
      actions.add({
        'icon': Icons.account_balance_wallet_outlined,
        'label': l.isArabic ? 'المحفظة والمدفوعات' : 'Wallet & pay',
        'onTap': () => _openPayService(),
      });
    }
    if (actions.isEmpty) return null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: actions
            .map(
              (a) => Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: OutlinedButton.icon(
                  onPressed: () {
                    final onTap = a['onTap'];
                    if (onTap is VoidCallback) {
                      onTap();
                    } else {
                      _sendQuickCommand((a['command'] as String?) ?? '');
                    }
                  },
                  icon: Icon(a['icon'] as IconData, size: 16),
                  label: Text(
                    (a['label'] as String?) ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _shamellMessageAvatar({
    required bool incoming,
    required ChatIdentity? me,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = 40.0;
    final radius = BorderRadius.circular(6);

    String label = '';
    ImageProvider? image;

    if (incoming) {
      final peer = _peer;
      label = peer != null ? _displayNameForPeer(peer) : '';
      final official = _linkedOfficial;
      final avatarUrl = (official?.avatarUrl ?? '').trim();
      final peerId = (peer?.id ?? '').trim();
      final linkedPeerId = (official?.chatPeerId ?? '').trim();
      if (avatarUrl.isNotEmpty &&
          peerId.isNotEmpty &&
          (linkedPeerId.isEmpty || linkedPeerId == peerId)) {
        image = NetworkImage(avatarUrl);
      }
    } else {
      label = (me?.displayName ?? '').trim();
    }

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
        child: image != null
            ? Image(image: image, fit: BoxFit.cover)
            : Center(
                child: Text(
                  initial,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m, ChatIdentity? me) {
    final incoming = _isIncoming(m);
    final decoded = _decodeMessage(m);
    final l = L10n.of(context);
    final isVoice = decoded.kind == 'voice';
    final isThisVoice = isVoice && _playingVoiceMessageId == m.id;
    final isPlayingThisVoice = isThisVoice && _voicePlaying;
    final isLocation = decoded.kind == 'location';
    final isContactCard = decoded.kind == 'contact';
    final isRecalled = _recalledMessageIds.contains(m.id);
    final attachment = decoded.attachment;
    final bool hasAttachment = attachment != null && attachment.isNotEmpty;
    final bool showImage = !isRecalled && !isVoice && hasAttachment;
    final isUnplayedVoice = incoming &&
        isVoice &&
        !isRecalled &&
        !_voicePlayedMessageIds.contains(m.id);
    final voiceSecs = decoded.voiceSecs ?? 0;
    String text;
    if (isVoice) {
      final secsLabel = voiceSecs > 0 ? '$voiceSecs' : '';
      text = l.shamellVoiceMessageLabel(secsLabel);
    } else {
      text = decoded.text;
    }
    if (isRecalled) {
      text = incoming
          ? l.shamellMessageRecalledByOther
          : l.shamellMessageRecalledByMe;
    }
    if (!isRecalled &&
        !isVoice &&
        !isLocation &&
        !isContactCard &&
        text.trim().isEmpty &&
        (decoded.kind ?? '').trim().isNotEmpty) {
      text = l.shamellPreviewUnknown;
    }
    final isPinned = _isMessagePinned(m);
    final expTs = _expirationLabel(m);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final voiceDurationText =
        voiceSecs > 0 ? (l.isArabic ? '$voiceSecs ث' : '${voiceSecs}s') : '';
    final clampedVoiceSecs = min(60, max(1, voiceSecs));
    final double voiceBubbleWidth =
        (88.0 + clampedVoiceSecs * 2.4).clamp(88.0, 220.0).toDouble();
    final baseIncoming = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .75)
        : Colors.white;
    const shamellOutgoing = Color(0xFF95EC69);
    final baseOutgoing = isDark
        ? theme.colorScheme.primary.withValues(alpha: .55)
        : shamellOutgoing;
    final String chatThemeKey =
        _peer != null ? (_chatThemes[_peer!.id] ?? 'default') : 'default';
    final incomingColor = chatThemeKey == 'green' ? baseIncoming : baseIncoming;
    final outgoingColor = chatThemeKey == 'green'
        ? (isDark ? baseOutgoing : shamellOutgoing)
        : baseOutgoing;
    final replyPreview = decoded.replyPreview;
    final replyToId = decoded.replyToId;
    final bool isHighlighted =
        (widget.initialMessageId != null && widget.initialMessageId == m.id) ||
            (_highlightedMessageId != null && _highlightedMessageId == m.id);
    final bool isSelected =
        _messageSelectionMode && _selectedMessageIds.contains(m.id);
    final avatar = _shamellMessageAvatar(incoming: incoming, me: me);
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.66;
    final bubbleKey = m.id.isNotEmpty
        ? _messageBubbleKeys.putIfAbsent(m.id, () => GlobalKey())
        : null;

    return GestureDetector(
      onTap: () {
        if (_messageSelectionMode) {
          _toggleMessageSelected(m.id);
        }
      },
      onLongPressStart: (details) {
        if (_messageSelectionMode) {
          _toggleMessageSelected(m.id);
        } else {
          unawaited(
            _onMessageLongPress(m, globalPosition: details.globalPosition),
          );
        }
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
            Stack(
              key: bubbleKey,
              clipBehavior: Clip.none,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: incoming ? incomingColor : outgoingColor,
                      border: () {
                        if (isSelected) {
                          return Border.all(
                            color: Tokens.colorPayments.withValues(alpha: .90),
                            width: 1.6,
                          );
                        }
                        if (isHighlighted) {
                          return Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: .90,
                            ),
                            width: 1.4,
                          );
                        }
                        return null;
                      }(),
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Column(
                      crossAxisAlignment: incoming
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.end,
                      children: [
                        if (m.sealedSender &&
                            incoming &&
                            _ratchetWarning != null)
                          Text(
                            _ratchetWarning!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 11),
                          ),
                        if (replyPreview != null &&
                            replyPreview.isNotEmpty &&
                            !isRecalled)
                          InkWell(
                            onTap: replyToId == null
                                ? null
                                : () => _scrollToMessage(replyToId),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                    alpha: theme.brightness == Brightness.dark
                                        ? .25
                                        : .15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                replyPreview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .75),
                                ),
                              ),
                            ),
                          ),
                        if (isVoice && !isRecalled)
                          InkWell(
                            onTap: () => _onVoiceTap(m),
                            child: Semantics(
                              button: true,
                              label: text,
                              child: SizedBox(
                                width: voiceBubbleWidth,
                                child: Row(
                                  children: incoming
                                      ? [
                                          Icon(
                                            isPlayingThisVoice
                                                ? Icons.graphic_eq
                                                : Icons.volume_up,
                                            size: 18,
                                            color: isPlayingThisVoice
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurface
                                                    .withValues(alpha: .75),
                                          ),
                                          if (voiceDurationText.isNotEmpty)
                                            const SizedBox(width: 6),
                                          if (voiceDurationText.isNotEmpty)
                                            Text(
                                              voiceDurationText,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          const Spacer(),
                                          if (isUnplayedVoice)
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Colors.redAccent,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ]
                                      : [
                                          const Spacer(),
                                          if (voiceDurationText.isNotEmpty)
                                            Text(
                                              voiceDurationText,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          if (voiceDurationText.isNotEmpty)
                                            const SizedBox(width: 6),
                                          Icon(
                                            isPlayingThisVoice
                                                ? Icons.graphic_eq
                                                : Icons.volume_up,
                                            size: 18,
                                            color: isPlayingThisVoice
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurface
                                                    .withValues(alpha: .75),
                                          ),
                                        ],
                                ),
                              ),
                            ),
                          )
                        else if (isLocation &&
                            decoded.lat != null &&
                            decoded.lon != null &&
                            !isRecalled)
                          Column(
                            crossAxisAlignment: incoming
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.place_outlined, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      text.isNotEmpty
                                          ? text
                                          : '${decoded.lat!.toStringAsFixed(5)}, ${decoded.lon!.toStringAsFixed(5)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _openLocationOnMap(
                                    decoded.lat!, decoded.lon!),
                                icon: const Icon(Icons.map_outlined, size: 16),
                                label: Text(l.shamellLocationOpenInMap),
                              ),
                            ],
                          )
                        else if (isContactCard &&
                            decoded.contactId != null &&
                            !isRecalled)
                          InkWell(
                            onTap: () {
                              final id = decoded.contactId?.trim() ?? '';
                              if (id.isEmpty) return;
                              unawaited(_resolvePeer(presetId: id));
                            },
                            child: Builder(
                              builder: (_) {
                                final contactId = decoded.contactId ?? '';
                                final name = decoded.text.trim().isNotEmpty
                                    ? decoded.text.trim()
                                    : (decoded.contactName ?? '').trim();
                                final display = name.isNotEmpty
                                    ? name
                                    : _displayNameForChatId(contactId);
                                final initial = display.trim().isNotEmpty
                                    ? display.trim()[0].toUpperCase()
                                    : '?';
                                return Container(
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? theme.colorScheme.surface
                                        : Colors.white.withValues(alpha: .95),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          Colors.black.withValues(alpha: .10),
                                    ),
                                  ),
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary
                                                  .withValues(
                                                      alpha:
                                                          isDark ? .24 : .14),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              initial,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  display,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                if (contactId.trim().isNotEmpty)
                                                  Text(
                                                    contactId,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      fontSize: 11,
                                                      color: theme
                                                          .colorScheme.onSurface
                                                          .withValues(
                                                              alpha: .55),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 18,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: .45),
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
                                        l.isArabic
                                            ? 'بطاقة جهة اتصال'
                                            : 'Contact card',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: .65),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          )
                        else if (text.isNotEmpty)
                          _buildBubbleText(context, text)
                        else if (!showImage)
                          _buildBubbleText(context, l.shamellPreviewUnknown),
                        if (showImage) ...[
                          if (text.isNotEmpty) const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: GestureDetector(
                              onTap: () =>
                                  _openImage(attachment!, decoded.mime),
                              onLongPress: () =>
                                  _shareAttachment(attachment!, decoded.mime),
                              child: Image.memory(
                                attachment!,
                                width: 220,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        if ((_messageReactions[m.id] ?? '').isNotEmpty) ...[
                          Align(
                            alignment: incoming
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withValues(alpha: isDark ? .08 : .80),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: .08),
                                ),
                              ),
                              child: Text(
                                _messageReactions[m.id]!,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        if (isPinned || expTs.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPinned)
                                  Icon(
                                    Icons.push_pin,
                                    size: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: .50),
                                  ),
                                if (isPinned && expTs.isNotEmpty)
                                  const SizedBox(width: 4),
                                if (expTs.isNotEmpty)
                                  Text(
                                    expTs,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error
                                              .withValues(alpha: .85),
                                        ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: incoming ? -6 : null,
                  right: incoming ? null : -6,
                  top: 10,
                  child: _BubbleTail(
                    incoming: incoming,
                    color: incoming ? incomingColor : outgoingColor,
                  ),
                ),
              ],
            ),
            if (!incoming) ...[
              const SizedBox(width: 8),
              avatar,
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showShamellMessageLongPressMenu({
    required Rect bubbleRect,
    required bool incoming,
    required List<_ShamellMessageMenuActionSpec> actions,
    required ValueChanged<String> onReaction,
  }) async {
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}

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
      final available = max(24.0,
          maxW - reactionPadH * 2 - (emojis.length - 1) * reactionSpacing);
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

  Future<void> _onMessageLongPress(
    ChatMessage m, {
    Offset? globalPosition,
  }) async {
    if (_messageSelectionMode) {
      _toggleMessageSelected(m.id);
      return;
    }
    final l = L10n.of(context);
    final d = _decodeMessage(m);
    final preview = _previewText(m);
    final text = d.text.isNotEmpty ? d.text : preview;
    final bool isVoice = d.kind == 'voice';
    final bool isPinned = _isMessagePinned(m);
    final bool isOwn = m.senderId == _me?.id;
    final bool isRecallEligible = isOwn &&
        m.createdAt != null &&
        DateTime.now().difference(m.createdAt!.toLocal()).inMinutes < 2;
    final bool isRecalled = _recalledMessageIds.contains(m.id);
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

        final incoming = _isIncoming(m);
        final actions = <_ShamellMessageMenuActionSpec>[];

        if (text.trim().isNotEmpty && !isVoice) {
          actions.add(
            _ShamellMessageMenuActionSpec(
              icon: Icons.copy_outlined,
              label: l.shamellCopyMessage,
              onTap: () {
                unawaited(() async {
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
        actions.add(
          _ShamellMessageMenuActionSpec(
            icon: Icons.forward,
            label: l.shamellForwardMessage,
            onTap: () => unawaited(_forwardMessage(m)),
          ),
        );
        actions.add(
          _ShamellMessageMenuActionSpec(
            icon: Icons.bookmark_outline,
            label: l.shamellAddToFavorites,
            onTap: () {
              unawaited(() async {
                final favText = text.trim().isNotEmpty ? text.trim() : preview;
                await addFavoriteItemQuick(
                  favText,
                  chatId: _peer?.id,
                  msgId: m.id,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.shamellMessageFavoritedSnack)),
                );
              }());
            },
          ),
        );
        if (d.kind == 'location' && d.lat != null && d.lon != null) {
          actions.add(
            _ShamellMessageMenuActionSpec(
              icon: Icons.place_outlined,
              label: l.shamellLocationFavorite,
              onTap: () {
                unawaited(() async {
                  await addFavoriteLocationQuick(
                    d.lat!,
                    d.lon!,
                    label: text.trim().isNotEmpty ? text.trim() : null,
                    chatId: _peer?.id,
                    msgId: m.id,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.shamellLocationFavoritedSnack)),
                  );
                }());
              },
            ),
          );
        }
        if (!isVoice && text.trim().isNotEmpty) {
          actions.add(
            _ShamellMessageMenuActionSpec(
              icon: Icons.translate,
              label: l.shamellTranslateMessage,
              onTap: () => unawaited(_translateMessage(text)),
            ),
          );
        }
        if (!isRecalled) {
          actions.add(
            _ShamellMessageMenuActionSpec(
              icon: Icons.reply,
              label: l.shamellReplyMessage,
              onTap: () {
                _applyState(() {
                  _replyToMessage = m;
                });
              },
            ),
          );
        }
        if (isVoice) {
          actions.add(
            _ShamellMessageMenuActionSpec(
              icon: _voiceUseSpeaker ? Icons.volume_up : Icons.hearing,
              label: _voiceUseSpeaker
                  ? l.shamellVoiceSpeakerMode
                  : l.shamellVoiceEarpieceMode,
              onTap: () {
                _applyState(() {
                  _voiceUseSpeaker = !_voiceUseSpeaker;
                });
              },
            ),
          );
        }
        actions.add(
          _ShamellMessageMenuActionSpec(
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: isPinned ? l.shamellUnpinMessage : l.shamellPinMessage,
            onTap: () => unawaited(_togglePinMessage(m)),
          ),
        );
        if (isRecallEligible) {
          actions.add(
            _ShamellMessageMenuActionSpec(
              icon: Icons.history_toggle_off,
              label: l.shamellRecallMessage,
              onTap: () {
                unawaited(() async {
                  _recalledMessageIds.add(m.id);
                  _applyState(() {});
                  unawaited(_saveRecalledMessages());
                  unawaited(_handleMessageRecalled(m.id));
                  await _sendRecallForMessage(m);
                }());
              },
            ),
          );
        }
        if (isOwn) {
          actions.add(
            _ShamellMessageMenuActionSpec(
              icon: Icons.delete_outline,
              label: l.shamellDeleteForMe,
              color: const Color(0xFFFA5151),
              onTap: () => unawaited(_deleteMessageLocal(m)),
            ),
          );
        }
        actions.add(
          _ShamellMessageMenuActionSpec(
            icon: Icons.check_circle_outline,
            label:
                l.isArabic ? 'تحديد رسائل متعددة' : 'Select multiple messages',
            onTap: () {
              _applyState(() {
                _messageSelectionMode = true;
                _selectedMessageIds
                  ..clear()
                  ..add(m.id);
              });
            },
          ),
        );
        actions.add(
          _ShamellMessageMenuActionSpec(
            icon: Icons.payments_outlined,
            label: l.shamellSendMoney,
            onTap: () {
              final peerId = _peer?.id;
              if (peerId == null || peerId.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentsPage(
                    widget.baseUrl,
                    '',
                    'shamell',
                    initialRecipient: peerId,
                    contextLabel: 'Shamell Pay',
                  ),
                ),
              );
            },
          ),
        );

        await _showShamellMessageLongPressMenu(
          bubbleRect: bubbleRect,
          incoming: incoming,
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
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
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
                if (text.trim().isNotEmpty && !isVoice)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.copy, size: 20),
                    title: Text(l.shamellCopyMessage),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.shamellMessageCopiedSnack),
                        ),
                      );
                    },
                  ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.forward, size: 20),
                  title: Text(l.shamellForwardMessage),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _forwardMessage(m);
                  },
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_outline, size: 20),
                  title: Text(l.shamellAddToFavorites),
                  onTap: () async {
                    final favText =
                        text.trim().isNotEmpty ? text.trim() : preview;
                    await addFavoriteItemQuick(
                      favText,
                      chatId: _peer?.id,
                      msgId: m.id,
                    );
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l.shamellMessageFavoritedSnack),
                      ),
                    );
                  },
                ),
                if (d.kind == 'location' && d.lat != null && d.lon != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place_outlined, size: 20),
                    title: Text(l.shamellLocationFavorite),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await addFavoriteLocationQuick(
                        d.lat!,
                        d.lon!,
                        label: text.trim().isNotEmpty ? text.trim() : null,
                        chatId: _peer?.id,
                        msgId: m.id,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.shamellLocationFavoritedSnack),
                        ),
                      );
                    },
                  ),
                if (!isVoice && text.trim().isNotEmpty)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.translate, size: 20),
                    title: Text(l.shamellTranslateMessage),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _translateMessage(text);
                    },
                  ),
                if (!isRecalled)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.reply, size: 20),
                    title: Text(l.shamellReplyMessage),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _applyState(() {
                        _replyToMessage = m;
                      });
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
                    title: Text(_voiceUseSpeaker
                        ? l.shamellVoiceSpeakerMode
                        : l.shamellVoiceEarpieceMode),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _applyState(() {
                        _voiceUseSpeaker = !_voiceUseSpeaker;
                      });
                    },
                  ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 20,
                  ),
                  title: Text(
                      isPinned ? l.shamellUnpinMessage : l.shamellPinMessage),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _togglePinMessage(m);
                  },
                ),
                if (isRecallEligible)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_toggle_off, size: 20),
                    title: Text(l.shamellRecallMessage),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      _recalledMessageIds.add(m.id);
                      _applyState(() {});
                      unawaited(_saveRecalledMessages());
                      unawaited(_handleMessageRecalled(m.id));
                      await _sendRecallForMessage(m);
                    },
                  ),
                if (isOwn)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline, size: 20),
                    title: Text(l.shamellDeleteForMe),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _deleteMessageLocal(m);
                    },
                  ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline, size: 20),
                  title: Text(
                    l.isArabic
                        ? 'تحديد رسائل متعددة'
                        : 'Select multiple messages',
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _applyState(() {
                      _messageSelectionMode = true;
                      _selectedMessageIds
                        ..clear()
                        ..add(m.id);
                    });
                  },
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined, size: 20),
                  title: Text(l.shamellSendMoney),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentsPage(
                          widget.baseUrl,
                          '',
                          'shamell',
                          initialRecipient: _peer?.id,
                          contextLabel: 'Shamell Pay',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _forwardMessage(ChatMessage m) async {
    final me = _me;
    if (me == null) return;
    final decoded = _decodeMessage(m);
    if (decoded.text.isEmpty &&
        (decoded.attachment == null || decoded.attachment!.isEmpty) &&
        (decoded.kind == null || decoded.kind!.isEmpty)) {
      return;
    }
    final target = await _pickForwardTarget();
    if (!mounted || target == null) return;
    _applyState(() {
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    try {
      _sessionHash ??= _computeSessionHash();
      final bootstrappedTarget = await _bootstrapPeerSessionIfNeeded(target);
      final payload = <String, Object?>{
        "text": decoded.text,
        "client_ts": DateTime.now().toIso8601String(),
        "sender_fp": me.fingerprint,
        "session_hash": _sessionHash,
      };
      final kind = decoded.kind;
      if (kind == 'voice') {
        payload["kind"] = kind;
      }
      if (kind == 'voice' && decoded.voiceSecs != null) {
        payload["voice_secs"] = decoded.voiceSecs;
      }
      if (decoded.attachment != null && decoded.attachment!.isNotEmpty) {
        payload["attachment_b64"] = base64Encode(decoded.attachment!);
        if (decoded.mime != null && decoded.mime!.isNotEmpty) {
          payload["attachment_mime"] = decoded.mime;
        }
      }
      final ratchet = _ensureRatchet(bootstrappedTarget);
      final mk = _ratchetNextSend(ratchet, peerId: bootstrappedTarget.id);
      final sessionKey = mk.$1;
      final keyId = mk.$2;
      final prevKeyId = mk.$3;
      final dhPubB64 = mk.$4;
      final expireAfterSeconds = bootstrappedTarget.disappearing &&
              bootstrappedTarget.disappearAfter != null
          ? bootstrappedTarget.disappearAfter!.inSeconds
          : null;
      final forwarded = await _service.sendMessage(
        me: me,
        peer: bootstrappedTarget,
        plainText: jsonEncode(payload),
        expireAfterSeconds: expireAfterSeconds,
        sealedSender: true,
        senderHint: me.fingerprint,
        sessionKey: sessionKey,
        keyId: keyId,
        prevKeyId: prevKeyId,
        senderDhPubB64: dhPubB64,
      );
      _mergeMessages([forwarded]);
    } catch (e) {
      if (!mounted) return;
      _applyState(() => _error = _sendFailureToUi(e));
    } finally {
      _applyState(() {
        _loading = false;
      });
    }
  }

  Future<void> _confirmDeviceLogin(String token, {String? label}) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    String bodyText = l.shamellDeviceLoginBody;
    if (label != null && label.isNotEmpty) {
      bodyText = l.isArabic
          ? 'السماح للجهاز \"$label\" بتسجيل الدخول إلى شامل باستخدام حسابك؟'
          : 'Allow \"$label\" to sign in to Shamell with your account?';
    }
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.shamellDeviceLoginTitle),
            content: Text(
              bodyText,
              style: theme.textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.shamellDialogCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.shamellDialogOk),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      final headers = <String, String>{
        'content-type': 'application/json',
        if (cookie.isNotEmpty) 'cookie': cookie,
      };
      final uri = Uri.parse('${widget.baseUrl}/auth/device_login/approve');
      final resp = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(<String, Object?>{
              'token': token,
              if (label != null && label.isNotEmpty) 'label': label,
            }),
          )
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shamellDeviceLoginApprovedSnack)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shamellDeviceLoginErrorExpired)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shamellDeviceLoginErrorExpired)),
      );
    }
  }

  Future<ChatContact?> _pickForwardTarget() async {
    final me = _me;
    if (me == null) return null;
    final l = L10n.of(context);
    final candidates = _sortedContacts().where((c) {
      if (c.id == _ShamellChatPageState._subscriptionsPeerId) {
        return false;
      }
      if ((c.hidden && !_showHidden) || (c.blocked && !_showBlocked)) {
        return false;
      }
      return true;
    }).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'لا توجد محادثات لإعادة التوجيه إليها.'
                : 'No chats available to forward to.',
          ),
        ),
      );
      return null;
    }
    return showModalBottomSheet<ChatContact>(
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
                  l.isArabic ? 'إعادة توجيه إلى…' : 'Forward to…',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final c = candidates[index];
                      final display = _displayNameForPeer(c);
                      final tags = _friendTags[c.id]?.trim() ?? '';
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: tags.isNotEmpty
                            ? Text(
                                tags,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .65),
                                ),
                              )
                            : null,
                        onTap: () => Navigator.of(ctx).pop(c),
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

  Future<void> _syncPrefsFromServer() async {
    final me = _me;
    if (me == null) return;
    try {
      final prefs = await _service.fetchPrefs(deviceId: me.id);
      if (prefs.isEmpty) return;
      final updated = List<ChatContact>.from(_contacts);
      bool changed = false;
      for (final p in prefs) {
        final idx = updated.indexWhere((c) => c.id == p.peerId);
        if (idx == -1) continue;
        final c = updated[idx];
        final newC =
            c.copyWith(muted: p.muted, starred: p.starred, pinned: p.pinned);
        if (newC.muted != c.muted ||
            newC.starred != c.starred ||
            newC.pinned != c.pinned) {
          updated[idx] = newC;
          changed = true;
        }
      }
      if (changed) {
        await _store.saveContacts(updated);
        if (!mounted) return;
        _applyState(() {
          _contacts = updated;
        });
      }
    } catch (_) {
      // ignore – prefs sync is best-effort
    }
  }

  Future<void> _syncGroupPrefsFromServer() async {
    final me = _me;
    if (me == null) return;
    try {
      final prefs = await _service.fetchGroupPrefs(deviceId: me.id);
      if (prefs.isEmpty) return;
      _groupPrefs
        ..clear()
        ..addEntries(prefs.map((p) => MapEntry(p.groupId, p)));
      _applyState(() {});
      _normalizePinnedChatOrder();
    } catch (_) {
      // best-effort
    }
  }

  Widget _buildChatAppBarTitle(ChatContact peer) {
    final theme = Theme.of(context);
    final displayName = _displayNameForPeer(peer).trim();
    final titleText = displayName.isNotEmpty ? displayName : peer.id;
    return Text(
      titleText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Future<void> _onChatLongPress(ChatContact c, {Offset? globalPosition}) async {
    final l = L10n.of(context);
    final hasUnread = (_unread[c.id] ?? 0) != 0;
    final markLabel = hasUnread ? l.shamellMarkRead : l.shamellMarkUnread;
    final pinLabel = c.pinned ? l.shamellUnpinChat : l.shamellPinChat;
    final moreLabel = l.isArabic ? 'المزيد' : 'More…';
    final deleteLabel = l.shamellDeleteChat;
    final cancelLabel = l.isArabic ? 'إلغاء' : 'Cancel';
    final globalPos = globalPosition;
    if (globalPos != null) {
      await _showShamellActionsPopover(
        globalPosition: globalPos,
        actions: [
          _ShamellPopoverActionSpec(
            label: markLabel,
            onTap: () => unawaited(_toggleChatReadUnread(c)),
          ),
          _ShamellPopoverActionSpec(
            label: pinLabel,
            onTap: () => unawaited(_toggleChatPinned(c)),
          ),
          _ShamellPopoverActionSpec(
            label: moreLabel,
            onTap: () {
              unawaited(
                Future<void>.delayed(_shamellMoreSheetDelay, () {
                  if (!mounted) return;
                  unawaited(_showChatMoreSheet(c));
                }),
              );
            },
          ),
          _ShamellPopoverActionSpec(
            label: deleteLabel,
            color: const Color(0xFFFA5151),
            onTap: () => unawaited(_deleteChatById(c.id)),
          ),
        ],
      );
      return;
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
                    label: markLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleChatReadUnread(c));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_toggleChatPinned(c));
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: moreLabel,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(
                        Future<void>.delayed(_shamellMoreSheetDelay, () {
                          if (!mounted) return;
                          unawaited(_showChatMoreSheet(c));
                        }),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_deleteChatById(c.id));
                    },
                  ),
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

  Future<void> _showPeerNotificationSheet(ChatContact c) async {
    final l = L10n.of(context);
    final store = _store;
    OfficialNotificationMode? current;
    try {
      current = await store.loadOfficialNotifMode(c.id);
    } catch (_) {
      current = null;
    }
    current ??= c.muted
        ? OfficialNotificationMode.muted
        : OfficialNotificationMode.full;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: RadioGroup<OfficialNotificationMode>(
              groupValue: current,
              onChanged: (mode) async {
                if (mode == null) return;
                Navigator.of(ctx).pop();
                await _setPeerNotificationMode(c, mode);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.full,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic
                          ? 'إظهار معاينة الرسائل'
                          : 'Show message preview',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عرض محتوى الرسائل في الإشعارات لهذه الدردشة'
                          : 'Show message content in notifications for this chat',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.summary,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic
                          ? 'إخفاء محتوى الرسائل'
                          : 'Hide message content',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'إظهار إشعار مختصر فقط عند وصول رسالة جديدة'
                          : 'Show a brief alert without message text',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.muted,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic ? 'كتم الإشعارات' : 'Mute notifications',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عدم إظهار إشعارات لهذه الدردشة'
                          : 'Turn off local notifications for this chat',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
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

  Future<void> _setPeerNotificationMode(
      ChatContact c, OfficialNotificationMode mode) async {
    final updated = c.copyWith(muted: mode == OfficialNotificationMode.muted);
    final contacts = _upsertContact(updated);
    await _store.saveContacts(contacts);
    await _store.setOfficialNotifMode(updated.id, mode);
    // Best-effort sync to server for official accounts.
    final accId = _officialPeerToAccountId[updated.id];
    if (accId != null && accId.isNotEmpty) {
      try {
        final uri = Uri.parse(
            '${widget.baseUrl}/official_accounts/$accId/notification_mode');
        final body = jsonEncode({
          'mode': switch (mode) {
            OfficialNotificationMode.full => 'full',
            OfficialNotificationMode.summary => 'summary',
            OfficialNotificationMode.muted => 'muted',
          }
        });
        await http
            .post(uri,
                headers: await _officialHeaders(jsonBody: true), body: body)
            .timeout(_ShamellChatPageState._chatRequestTimeout);
      } catch (_) {}
    }
    if (!mounted) return;
    _applyState(() {
      _contacts = contacts;
      if (_peer?.id == updated.id) {
        _peer = updated;
      }
    });
  }

  void _markVoiceMessagePlayed(ChatMessage m) {
    if (m.id.isEmpty) return;
    if (!_isIncoming(m)) return;
    final meId = _me?.id;
    if (meId == null) return;
    final peerId = _peerIdForMessage(m, meId);
    if (peerId.isEmpty) return;
    if (_voicePlayedMessageIds.contains(m.id)) return;
    _applyState(() {
      _voicePlayedMessageIds = <String>{..._voicePlayedMessageIds, m.id};
    });
    unawaited(_store.markVoicePlayed(peerId, m.id));
  }

  Future<void> _onVoiceTap(ChatMessage m) async {
    _markVoiceMessagePlayed(m);
    if (_playingVoiceMessageId == m.id) {
      try {
        if (_audioPlayer.playing) {
          await _audioPlayer.pause();
          return;
        }
        try {
          final session = await AudioSession.instance;
          await session.configure(_voiceUseSpeaker
              ? const AudioSessionConfiguration.music()
              : const AudioSessionConfiguration.speech());
        } catch (_) {}
        await _audioPlayer.play();
        return;
      } catch (_) {
        final l = L10n.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shamellVoicePlaybackSoon)),
        );
        return;
      }
    }

    final decoded = _decodeMessage(m);
    final bytes = decoded.attachment;
    if (bytes == null || bytes.isEmpty) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shamellVoicePlaybackSoon)),
      );
      return;
    }
    try {
      final tmp = Directory.systemTemp;
      final file = File('${tmp.path}/shamell_voice_${m.id}.aac');
      await file.writeAsBytes(bytes, flush: true);
      try {
        final session = await AudioSession.instance;
        await session.configure(_voiceUseSpeaker
            ? const AudioSessionConfiguration.music()
            : const AudioSessionConfiguration.speech());
      } catch (_) {}
      // Start/refresh proximity listener so bringing the phone to the ear
      // automatically switches to earpiece mode while voice is playing.
      _proximitySub?.cancel();
      try {
        _proximitySub = ProximitySensor.events.listen((int event) async {
          final near = event > 0;
          if (!mounted) return;
          // When near, prefer earpiece; when far, prefer speaker.
          _voiceUseSpeaker = !near;
          try {
            final session = await AudioSession.instance;
            await session.configure(_voiceUseSpeaker
                ? const AudioSessionConfiguration.music()
                : const AudioSessionConfiguration.speech());
          } catch (_) {}
          _applyState(() {});
        });
      } catch (_) {}
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(file.path);
      if (!mounted) return;
      _applyState(() {
        _playingVoiceMessageId = m.id;
      });
      await _audioPlayer.play();
    } catch (_) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shamellVoicePlaybackSoon)),
      );
    }
  }

  // ignore: unused_element
  void _openAdditionalActions() {
    final l = L10n.of(context);
    final me = _me;
    final peer = _peer;
    if (_loading || me == null || peer == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;

        Widget buildAction(
          IconData icon,
          String label,
          VoidCallback onTap,
        ) {
          return SizedBox(
            width: 80,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface
                          .withValues(alpha: isDark ? .32 : .08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      icon,
                      size: 26,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                buildAction(
                  Icons.photo_outlined,
                  l.shamellAttachImage,
                  () {
                    Navigator.of(ctx).pop();
                    _pickAttachment();
                  },
                ),
                buildAction(
                  Icons.location_on_outlined,
                  l.shamellSendLocation,
                  () {
                    Navigator.of(ctx).pop();
                    _sendCurrentLocation();
                  },
                ),
                buildAction(
                  Icons.payments_outlined,
                  l.shamellSendMoney,
                  () {
                    Navigator.of(ctx).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentsPage(
                          widget.baseUrl,
                          '',
                          'shamell',
                          initialRecipient: peer.id,
                          contextLabel: 'Shamell Pay',
                        ),
                      ),
                    );
                  },
                ),
                buildAction(
                  Icons.apps_outlined,
                  l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs',
                  () {
                    Navigator.of(ctx).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MiniProgramsDiscoverPage(
                          baseUrl: widget.baseUrl,
                          walletId: '',
                          deviceId: me.id,
                          onOpenMod: _openMiniAppFromShamell,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _startVoiceCall() async {
    final p = _peer;
    if (p == null) return;
    final l = L10n.of(context);
    final id = p.id.trim();
    final digitsOnly = id.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digitsOnly.isEmpty || !RegExp(r'^[+0-9][0-9]*$').hasMatch(digitsOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic
              ? 'لا يوجد رقم هاتف مرتبط بهذا الحساب.'
              : 'No phone number linked to this contact.'),
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: digitsOnly);
    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.isArabic
                ? 'لا يمكن فتح واجهة الاتصال على هذا الجهاز.'
                : 'Cannot open dialer on this device.'),
          ),
        );
        return;
      }
      // Log GSM voice call in local call history (duration unknown at this layer).
      // Best-effort; ignore failures.
      final entry = ChatCallLogEntry(
        id: 'gsm_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
        peerId: p.id,
        ts: DateTime.now(),
        direction: 'out',
        kind: 'voice',
        accepted: true,
        duration: Duration.zero,
      );
      // ignore: discarded_futures
      _callStore.append(entry);
      await launchUrl(uri);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'فشل بدء المكالمة.' : 'Failed to start call.',
          ),
        ),
      );
    }
  }

  void _startVoipCall({String mode = 'video'}) {
    final p = _peer;
    if (p == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoipCallPage(
          baseUrl: widget.baseUrl,
          peerId: p.id,
          displayName: _displayNameForPeer(p),
          mode: mode,
        ),
      ),
    );
  }

  Widget _block({
    required String title,
    Widget? titleWidget,
    Widget? trailing,
    required Widget child,
    bool flat = false,
  }) {
    final theme = Theme.of(context);
    final header = Row(
      children: [
        titleWidget ??
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
        const Spacer(),
        if (trailing != null) trailing
      ],
    );

    if (flat) {
      return Material(
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: header,
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: .2)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSubscriptionItem(_SubscriptionEntry e) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundImage:
            (e.accountAvatarUrl != null && e.accountAvatarUrl!.isNotEmpty)
                ? NetworkImage(e.accountAvatarUrl!)
                : null,
        child: (e.accountAvatarUrl == null || e.accountAvatarUrl!.isEmpty)
            ? Text(
                e.accountName.isNotEmpty
                    ? e.accountName.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l.isArabic ? 'اشتراك' : 'Subscription',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.primary.withValues(alpha: .85),
                ),
              ),
            ),
          ),
          if (e.isUnread)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Icon(
                Icons.brightness_1,
                size: 8,
                color: theme.colorScheme.primary,
              ),
            ),
          if (e.tsLabel.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              e.tsLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .60),
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.accountName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          if ((e.snippet ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                e.snippet!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
      onTap: () {
        Perf.action('official_open_feed_subscription');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OfficialFeedItemDeepLinkPage(
              baseUrl: widget.baseUrl,
              accountId: e.accountId,
              itemId: e.itemId,
              onOpenChat: (peerId) {
                if (peerId.isEmpty) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShamellChatPage(
                      baseUrl: widget.baseUrl,
                      initialPeerId: peerId,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      trailing: (e.chatPeerId != null && e.chatPeerId!.isNotEmpty)
          ? IconButton(
              tooltip: l.isArabic ? 'دردشة' : 'Chat',
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              onPressed: () {
                final peerId = e.chatPeerId!.trim();
                if (peerId.isEmpty) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShamellChatPage(
                      baseUrl: widget.baseUrl,
                      initialPeerId: peerId,
                    ),
                  ),
                );
              },
            )
          : null,
    );
  }

  Uri _inviteUri(String token) {
    return Uri(
      scheme: 'shamell',
      host: 'invite',
      queryParameters: <String, String>{'token': token},
    );
  }

  Future<String> _createInviteTokenWithBootstrap() async {
    return _service.createContactInviteTokenEnsured(maxUses: 1);
  }

  void _showInviteQr() {
    final l = L10n.of(context);
    final inviteFuture = _createInviteTokenWithBootstrap();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<String>(
            future: inviteFuture,
            builder: (ctx, snap) {
              final token = (snap.data ?? '').toString().trim();
              final payload =
                  token.isNotEmpty ? _inviteUri(token).toString() : '';

              Widget qrContent() {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final err = snap.error;
                if (err != null) {
                  return Text(
                    sanitizeExceptionForUi(error: err, isArabic: l.isArabic),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 220,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                    ),
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    l.isArabic ? 'رمز الدعوة' : 'Invite QR code',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  qrContent(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: payload.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await Clipboard.setData(
                                      ClipboardData(text: payload),
                                    );
                                  } catch (_) {}
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l.isArabic
                                            ? 'تم نسخ الرابط.'
                                            : 'Invite link copied.',
                                      ),
                                      duration:
                                          const Duration(milliseconds: 900),
                                    ),
                                  );
                                },
                          child: Text(l.isArabic ? 'نسخ' : 'Copy'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: payload.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await Share.share(payload);
                                  } catch (_) {}
                                },
                          child: Text(l.isArabic ? 'مشاركة' : 'Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showQr(ChatIdentity me) {
    final payload = jsonEncode({
      'id': me.id,
      'pub': me.publicKeyB64,
      'fp': me.fingerprint,
      'name': me.displayName
    });
    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) {
          final l = L10n.of(context);
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.shamellIdentityTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square),
                ),
                const SizedBox(height: 12),
                SelectableText(me.id),
                const SizedBox(height: 6),
                SelectableText('Fingerprint: ${me.fingerprint}'),
              ],
            ),
          );
        });
  }
}

class _DecodedPayload {
  final String text;
  final Uint8List? attachment;
  final String? mime;
  final DateTime? clientTs;
  final String? kind;
  final String? contactId;
  final String? contactName;
  final int? voiceSecs;
  final String? replyToId;
  final String? replyPreview;
  final double? lat;
  final double? lon;
  const _DecodedPayload(
      {required this.text,
      required this.attachment,
      required this.mime,
      this.clientTs,
      this.kind,
      this.contactId,
      this.contactName,
      this.voiceSecs,
      this.replyToId,
      this.replyPreview,
      this.lat,
      this.lon});
}

class _ChainState {
  Uint8List chainKey;
  int counter;
  _ChainState({required this.chainKey, required this.counter});
}

class _SafetyNumber {
  final String formatted;
  final String raw;
  const _SafetyNumber(this.formatted, this.raw);
}

class _BubbleTail extends StatelessWidget {
  final bool incoming;
  final Color color;

  const _BubbleTail({required this.incoming, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleTailPainter(incoming: incoming, color: color),
      size: const Size(7, 12),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final bool incoming;
  final Color color;

  _BubbleTailPainter({required this.incoming, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    final tipY = size.height * 0.50;
    if (incoming) {
      path.moveTo(size.width, 0);
      path.quadraticBezierTo(0, tipY, size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.quadraticBezierTo(size.width, tipY, 0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.incoming != incoming || oldDelegate.color != color;
  }
}

class _SubscriptionEntry {
  final String accountId;
  final String accountName;
  final String? accountAvatarUrl;
  final String accountKind;
  final String? chatPeerId;
  final String itemId;
  final String title;
  final String? snippet;
  final String? thumbUrl;
  final DateTime? ts;
  final bool isUnread;

  const _SubscriptionEntry({
    required this.accountId,
    required this.accountName,
    required this.accountAvatarUrl,
    required this.accountKind,
    required this.chatPeerId,
    required this.itemId,
    required this.title,
    required this.snippet,
    required this.thumbUrl,
    required this.ts,
    this.isUnread = false,
  });

  String get tsLabel {
    final t = ts;
    if (t == null) return '';
    final dt = t.toLocal();
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ShamellPopoverActionSpec {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShamellPopoverActionSpec({
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });
}

class _ShamellMessageMenuActionSpec {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShamellMessageMenuActionSpec({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });
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
