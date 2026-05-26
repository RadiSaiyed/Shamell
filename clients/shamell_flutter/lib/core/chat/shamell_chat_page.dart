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
import 'package:shamell_flutter/main.dart' show LoginPage;
import 'safety_number.dart';
import '../chat_presence_registry.dart';
import '../design_tokens.dart';
import '../notification_service.dart';
import '../capabilities.dart';
import '../analytics_migration.dart';
import '../account_identity_store.dart';
import '../ephemeral_voice_file.dart';
import '../friend_annotations_store.dart';
import '../safe_clipboard.dart';
import '../l10n.dart';
import '../official_feed_seen_store.dart';
import '../ui_kit.dart';
import '../glass.dart';
import '../shamell_ui.dart';
import '../shamell_my_qr_page.dart';
import '../shamell_user_id.dart';
import '../perf.dart';
import '../payments/payments_shell.dart';
import '../people_p2p.dart' show PeopleP2PPage;
import '../official_template_messages_page.dart';
import '../shamell_app_links.dart';
import '../deep_link_parsing.dart';
import '../favorites_page.dart';
import '../favorites_store.dart';
import '../friends_page.dart';
import '../green_paket_page.dart';
import '../mini_app_descriptor.dart';
import '../mini_app_registry.dart';
import '../media_access_policy.dart';
import '../friend_tags_page.dart';
import '../scan_page.dart';
import '../unsupported_module_nav.dart';
import '../shamell_settings_hub_page.dart';
import '../official_account_models.dart';
import '../devices_page.dart';
import '../device_login_label.dart';
import '../device_binding_reauth.dart';
import '../external_launch_guard.dart';
import '../base_url.dart';
import '../http_error.dart';
import '../push_token_manager.dart';
import '../call_signaling.dart';
import '../safe_set_state.dart';
import '../shamell_pinned_remote_image.dart';
import '../base64_bytes_cache.dart';
import '../channels_page.dart';
import '../official_accounts_page.dart' show OfficialAccountsPage;
import '../nearby_page.dart';
import '../shamell_moments_page.dart';
import '../sticker_store_page.dart';
import '../superapp_api.dart';
import '../voip_call_page_stub.dart'
    if (dart.library.io) '../voip_call_livekit_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import '../group_chats_page.dart';
import 'chat_message_highlight.dart';
import 'chat_models.dart';
import 'chat_message_overview.dart';
import 'chat_send_status.dart';
import 'chat_message_position_index.dart';
import 'chat_message_payload.dart';
import 'chat_message_render_keys.dart';
import 'chat_outbox.dart';
import 'chat_outbox_store.dart';
import 'chat_push_deeplink.dart';
import 'chat_bubble_skeleton.dart';
import 'chat_edit_history_dialog.dart';
import 'chat_read_receipts_pref.dart';
import 'chat_reaction_bar.dart';
import 'chat_reaction_models.dart';
import 'chat_wallpaper_picker.dart';
import 'chat_snooze_picker.dart';
import 'chat_saved_replies_palette.dart';
import 'chat_emoji_shortcuts.dart';
import 'chat_reaction_recent.dart';
import 'chat_slash_commands.dart';
import 'chat_expire_countdown.dart';
import 'chat_linkified_text.dart';
import 'chat_mention_completions.dart';
import 'chat_poll_bubble.dart';
import 'chat_poll_creator_dialog.dart';
import 'chat_saved_replies_manage_page.dart';
import 'chat_schedule_picker.dart';
import 'chat_scheduled_messages_page.dart';
import 'chat_smart_replies.dart';
import 'chat_smart_replies_bar.dart';
import 'chat_stories_page.dart';
import 'chat_voice_waveform.dart';
import 'chat_link_preview.dart';
import 'chat_typing_dots.dart';
import 'chat_bookmarks_page.dart';
import 'chat_pulse_dot.dart';
import 'chat_profile_editor_page.dart';
import 'cross_chat_search.dart';
import 'cross_chat_search_page.dart';
import 'chat_ws_reconnect.dart';
import 'chat_service.dart';
import 'direct_message_presentation.dart';
import 'direct_message_search.dart';
import 'chat_thread_index.dart';
import 'chat_thread_layout.dart';
import 'chat_thread_presentation.dart';
import 'ratchet_models.dart';
import 'shamell_chat_info_page.dart';

enum _ShamellComposerPanel { none, more }

const Set<String> _shamellChatScannedCustomSchemeHosts = <String>{
  'invite',
  'friend',
  'device_login',
  'official',
  'miniapp',
  'mini_program',
  'moduleapp',
  'moduleapps',
  'green_paket',
  'green_packet',
  'redpacket',
  'red_packet',
  'hongbao',
};
const int _shamellChatScanPayloadMaxChars = 4096;

Map<String, String> _shamellChatMergedInboundParams(
  Uri uri, {
  bool includeQueryParameters = true,
}) {
  return shamellMergedInboundParams(
    uri,
    includeQueryParameters: includeQueryParameters,
  );
}

@visibleForTesting
Uri normalizeShamellChatScannedInboundUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'shamell') {
    final mergedParams = _shamellChatMergedInboundParams(uri);
    return Uri(
      scheme: 'shamell',
      host: uri.host.trim().toLowerCase(),
      pathSegments: uri.pathSegments,
      queryParameters: mergedParams.isEmpty ? null : mergedParams,
    );
  }
  if (scheme != 'https') return uri;
  if (uri.host.toLowerCase() != shamellAppLinkHost) return uri;
  if (uri.userInfo.isNotEmpty || uri.hasPort) return uri;
  final segs = uri.pathSegments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segs.length < 2) return uri;
  if (segs.first.toLowerCase() != shamellAppLinkPathSegment) return uri;
  final host = segs[1].toLowerCase();
  final mergedParams = _shamellChatMergedInboundParams(
    uri,
    includeQueryParameters: !shamellHostedAppLinkRequiresFragment(host),
  );
  if (shamellHostedAppLinkRequiresFragment(host) && mergedParams.isEmpty) {
    return uri;
  }
  final pathSegs = segs.length > 2 ? segs.sublist(2) : const <String>[];
  return Uri(
    scheme: 'shamell',
    host: host,
    pathSegments: pathSegs,
    queryParameters: mergedParams.isEmpty ? null : mergedParams,
  );
}

@visibleForTesting
bool shamellChatAllowsScannedCustomSchemeUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'shamell') return false;
  if (uri.host.trim().isEmpty) return false;
  if (uri.userInfo.isNotEmpty || uri.hasPort) return false;
  if (uri.fragment.trim().isNotEmpty) return false;
  final host = uri.host.trim().toLowerCase();
  return _shamellChatScannedCustomSchemeHosts.contains(host);
}

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

class _FrozenDirectDraftSend {
  final String text;
  final Uint8List? attachmentBytes;
  final String? attachmentMime;
  final ChatMessage? replyToMessage;

  const _FrozenDirectDraftSend({
    required this.text,
    this.attachmentBytes,
    this.attachmentMime,
    this.replyToMessage,
  });
}

class _DirectThreadTileState {
  final ChatMessage? last;
  final int unread;
  final bool hasUnread;
  final String preview;
  final bool isPeerTyping;
  final String ts;
  final bool isOfficial;
  final bool hasFeedUnread;
  final bool isFeaturedOfficial;
  final bool bulkSelected;
  final bool hasDraft;
  final String draftPreview;
  final DateTime sortTs;

  const _DirectThreadTileState({
    required this.last,
    required this.unread,
    required this.hasUnread,
    required this.preview,
    required this.isPeerTyping,
    required this.ts,
    required this.isOfficial,
    required this.hasFeedUnread,
    required this.isFeaturedOfficial,
    required this.bulkSelected,
    required this.hasDraft,
    required this.draftPreview,
    required this.sortTs,
  });
}

class _GroupThreadTileState {
  final ChatGroupMessage? last;
  final ChatGroupThreadPreviewData preview;
  final int unread;
  final bool hasUnread;
  final bool muted;
  final bool pinned;
  final bool archived;
  final bool mentionUnread;
  final bool mentionAllUnread;
  final String ts;
  final Uint8List? avatarBytes;
  final bool bulkSelected;
  final String bulkId;
  final DateTime sortTs;

  const _GroupThreadTileState({
    required this.last,
    required this.preview,
    required this.unread,
    required this.hasUnread,
    required this.muted,
    required this.pinned,
    required this.archived,
    required this.mentionUnread,
    required this.mentionAllUnread,
    required this.ts,
    required this.avatarBytes,
    required this.bulkSelected,
    required this.bulkId,
    required this.sortTs,
  });
}

class _SigningKeyPinViolation implements Exception {
  final String reason;
  const _SigningKeyPinViolation(this.reason);

  @override
  String toString() => 'SigningKeyPinViolation($reason)';
}

/// Allowed voice-playback speed values, in cycle order. Tapping
/// the bubble's speed badge advances through this list (wrapping
/// back to the first entry after the last). Kept small + integer-
/// stable so a future pref-format bump doesn't have to interpret
/// arbitrary floats.
const List<double> _kVoicePlaybackSpeedSteps = <double>[1.0, 1.5, 2.0];

/// SharedPreferences key for the persisted voice-playback speed.
/// Scoped under the chat-page prefix so it doesn't collide with
/// other modules; not multi-account-scoped because speed is a UI
/// preference, not user data.
const String _kVoicePlaybackSpeedPrefKey =
    'shamell.chat.voice_playback_speed.v1';

/// Client-side time window during which the user can recall their
/// own outgoing message (the long-press "Recall" / "Delete for
/// everyone" action is gated on this). The previous 2-minute window
/// (audit P1-14) was tight enough that users typically only spotted
/// typos AFTER it had expired — WhatsApp and Telegram both ship
/// 2-day windows for the same action. We mirror that here so the
/// affordance matches user expectations; the server enforces its
/// own ceiling regardless of what the client offers.
///
/// Defined at file scope (not on `_ShamellChatPageState`) so the
/// `_ShamellChatHelpers` extension below can reference it without
/// either a class qualifier or moving every helper into the State
/// class itself.
const Duration _messageRecallWindow = Duration(hours: 48);

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
  /// SyrChat-style SuperApp shell, which already provides a
  /// bottom navigation bar for Chats/Contacts/Discover/Me.
  final bool showBottomNav;
  final bool runStartupTasks;
  final http.Client? officialHttpClient;
  final http.Client? accountHttpClient;
  final VoidCallback? onCriticalOfficialSessionFailure;
  final Future<bool> Function()? deviceLoginApprovalAuthPrompt;
  final VoidCallback? onCriticalDeviceLoginSessionFailure;
  final ChatService? serviceOverride;
  final VoidCallback? onCriticalChatSessionFailure;
  final Future<void> Function(String peerId, String themeKey)?
      saveChatThemeForPeerOverride;
  final Future<void> Function(String peerId, String messageId, bool pinned)?
      savePinnedMessageForPeerOverride;
  final Future<void> Function(String messageId)?
      removePinnedMessageFromAllPeersOverride;
  final Future<void> Function(String messageId)?
      removeFavoriteItemsByMessageIdOverride;
  final Future<void> Function(String messageId, bool recalled)?
      saveRecalledMessageStateOverride;
  final Future<void> Function(String groupId, bool archived)?
      saveArchivedGroupStateOverride;
  final Future<Map<String, String>> Function(Iterable<String> groupIds)?
      loadGroupSeenForGroupsOverride;
  final Future<String?> Function(String groupId)? loadGroupSeenForGroupOverride;
  final Future<void> Function(String groupId, int unreadCount)?
      saveUnreadCountForGroupOverride;
  final Future<void> Function(String peerId, int unreadCount)?
      saveUnreadCountForPeerOverride;
  final Future<void> Function(
          Map<String, int> unread, Iterable<String> unreadKeys)?
      saveUnreadCountsForKeysOverride;
  final Future<void> Function(String peerId, List<ChatMessage> messages)?
      saveMessagesForPeerOverride;
  final Future<void> Function(
    String groupId,
    List<ChatGroupMessage> messages,
  )? saveGroupMessagesForGroupOverride;
  final Future<void> Function(List<ChatGroup> groups)? upsertGroupNamesOverride;
  final Future<void> Function(Iterable<ChatContact> contacts)?
      saveContactsForPeersOverride;
  final Future<void> Function(Iterable<String> peerIds)?
      removeContactsForPeersOverride;
  final Future<bool> Function()? authenticateHiddenChatsOverride;
  final Future<void> Function(bool enabled)? saveNotifyPreviewOverride;
  final Future<void> Function(bool hasUnread)?
      saveServiceNotificationsHasUnreadOverride;
  final Future<void> Function(bool hide)?
      saveHideServiceNotificationsThreadOverride;
  final Future<void> Function(ChatMessage message)? forwardMessageOverride;
  final Future<void> Function(String text)? copyMessageTextOverride;
  final Future<void> Function(String text)? translateMessageOverride;
  final Future<void> Function(String text, String? chatId, String? msgId)?
      addFavoriteItemQuickOverride;
  final Future<void> Function(
    double lat,
    double lon,
    String? label,
    String? chatId,
    String? msgId,
  )? addFavoriteLocationQuickOverride;
  final Future<void> Function()? openFavoritesPickerOverride;
  final Future<void> Function()? openContactCardPickerOverride;
  final Future<void> Function(ChatContact contact, Offset? globalPosition)?
      onChatLongPressOverride;
  final Future<void> Function(ChatGroup group, Offset? globalPosition)?
      onGroupLongPressOverride;
  final Future<void> Function(ChatContact contact)? onChatTileTapOverride;
  final Future<void> Function()? onServiceNotificationsThreadTapOverride;
  final Future<void> Function(ChatContact peer)?
      loadSwitchedPeerOfficialOverride;
  final Future<void> Function(String officialId, String chatPeerId)?
      startServiceOfficialFollowOverride;
  final Future<void> Function(OfficialAccountHandle account)?
      startOfficialWelcomeInjectionOverride;
  final Future<void> Function(ChatGroupInboxUpdate update)?
      startLiveGroupInboxMergeOverride;
  final Future<void> Function(String peerId, List<ChatMessage> messages)?
      startLiveDirectMessageSaveOverride;
  final Future<void> Function(List<ChatMessage> messages)?
      startLiveDirectInboxCursorSaveOverride;
  final Future<void> Function(String messageId)? startLiveDirectReadAckOverride;
  final Future<void> Function(ChatContact contact)?
      startLiveDirectContactUpsertOverride;
  final Future<void> Function(ChatContact contact)?
      startLiveDirectContactUnarchiveOverride;
  final Future<void> Function(
          Map<String, int> unread, Iterable<String> unreadKeys)?
      startLiveDirectUnreadBatchSaveOverride;
  final Future<void> Function(
          Map<String, int> unread, Iterable<String> unreadKeys)?
      startMarkAllChatsReadUnreadBatchSaveOverride;
  final Future<void> Function(
          String? initialRecipient, int? initialAmountCents)?
      openPaymentsPageOverride;
  final Future<void> Function(Map<String, String> drafts)? saveDraftsOverride;
  final Future<void> Function()? loadBootstrapSystemThreadsSideStateOverride;
  final Future<void> Function()? ensurePushTokenOverride;
  final Future<void> Function()?
      refreshBootstrapServiceNotificationsBadgeOverride;
  final Future<void> Function(String peerId)?
      loadBootstrapInitialPeerResolveOverride;
  final Future<void> Function()? loadBootstrapSideMetadataOverride;
  final Future<void> Function(ChatContact peer)?
      loadBootstrapOfficialForCurrentPeerOverride;
  final Future<void> Function()? loadBootstrapOfficialNotificationModesOverride;
  final Future<void> Function()? loadBootstrapDirectPrefsSyncOverride;
  final Future<void> Function()? loadBootstrapGroupPrefsSyncOverride;
  final Future<void> Function()? loadBootstrapDevicesSummaryOverride;
  final String? debugAutoSendText;
  const ShamellChatPage({
    super.key,
    required this.baseUrl,
    this.initialPeerId,
    this.initialMessageId,
    this.presetAttachmentBytes,
    this.presetAttachmentMime,
    this.presetAttachmentName,
    this.showBottomNav = false,
    this.runStartupTasks = true,
    this.officialHttpClient,
    this.accountHttpClient,
    this.onCriticalOfficialSessionFailure,
    this.deviceLoginApprovalAuthPrompt,
    this.onCriticalDeviceLoginSessionFailure,
    this.serviceOverride,
    this.onCriticalChatSessionFailure,
    this.saveChatThemeForPeerOverride,
    this.savePinnedMessageForPeerOverride,
    this.removePinnedMessageFromAllPeersOverride,
    this.removeFavoriteItemsByMessageIdOverride,
    this.saveRecalledMessageStateOverride,
    this.saveArchivedGroupStateOverride,
    this.loadGroupSeenForGroupsOverride,
    this.loadGroupSeenForGroupOverride,
    this.saveUnreadCountForGroupOverride,
    this.saveUnreadCountForPeerOverride,
    this.saveUnreadCountsForKeysOverride,
    this.saveMessagesForPeerOverride,
    this.saveGroupMessagesForGroupOverride,
    this.upsertGroupNamesOverride,
    this.saveContactsForPeersOverride,
    this.removeContactsForPeersOverride,
    this.authenticateHiddenChatsOverride,
    this.saveNotifyPreviewOverride,
    this.saveServiceNotificationsHasUnreadOverride,
    this.saveHideServiceNotificationsThreadOverride,
    this.forwardMessageOverride,
    this.copyMessageTextOverride,
    this.translateMessageOverride,
    this.addFavoriteItemQuickOverride,
    this.addFavoriteLocationQuickOverride,
    this.openFavoritesPickerOverride,
    this.openContactCardPickerOverride,
    this.onChatLongPressOverride,
    this.onGroupLongPressOverride,
    this.onChatTileTapOverride,
    this.onServiceNotificationsThreadTapOverride,
    this.loadSwitchedPeerOfficialOverride,
    this.startServiceOfficialFollowOverride,
    this.startOfficialWelcomeInjectionOverride,
    this.startLiveGroupInboxMergeOverride,
    this.startLiveDirectMessageSaveOverride,
    this.startLiveDirectInboxCursorSaveOverride,
    this.startLiveDirectReadAckOverride,
    this.startLiveDirectContactUpsertOverride,
    this.startLiveDirectContactUnarchiveOverride,
    this.startLiveDirectUnreadBatchSaveOverride,
    this.startMarkAllChatsReadUnreadBatchSaveOverride,
    this.openPaymentsPageOverride,
    this.saveDraftsOverride,
    this.loadBootstrapSystemThreadsSideStateOverride,
    this.ensurePushTokenOverride,
    this.refreshBootstrapServiceNotificationsBadgeOverride,
    this.loadBootstrapInitialPeerResolveOverride,
    this.loadBootstrapSideMetadataOverride,
    this.loadBootstrapOfficialForCurrentPeerOverride,
    this.loadBootstrapOfficialNotificationModesOverride,
    this.loadBootstrapDirectPrefsSyncOverride,
    this.loadBootstrapGroupPrefsSyncOverride,
    this.loadBootstrapDevicesSummaryOverride,
    this.debugAutoSendText,
  });

  @override
  State<ShamellChatPage> createState() => _ShamellChatPageState();
}

class _ShamellChatPageState extends State<ShamellChatPage>
    with SafeSetStateMixin<ShamellChatPage>, WidgetsBindingObserver {
  static const int _curveKeyBytes = 32;
  static const Duration _chatRequestTimeout = Duration(seconds: 15);
  static const int _officialAccountsPageSize = 200;
  static const int _directOlderMessagesPageSize = 200;
  static const double _threadOlderMessagesLoadThreshold = 96;
  static const Duration _typingIndicatorTtl = Duration(seconds: 5);
  static const Duration _typingHeartbeatInterval = Duration(seconds: 2);
  static const Duration _typingIdleTimeout = Duration(seconds: 4);
  late final ChatService _service;
  late final bool _ownsService;
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
  bool _loadingOlderThreadMessages = false;
  bool _hasOlderThreadMessages = false;
  bool _deviceLoginApprovalInFlight = false;
  int _threadNewMessagesAwayCount = 0;
  String? _threadNewMessagesFirstId;
  String _messageSearch = '';
  bool _showMessageSearchBar = false;
  final ChatMessageHighlightController _threadMessageHighlightController =
      ChatMessageHighlightController();
  String? _activeThreadMessageSearchMatchId;
  bool _initialThreadMessageJumpHandled = false;
  DirectMessageSearchIndex? _threadMessageSearchIndex;
  List<ChatMessage>? _threadMessageSearchIndexMessagesRef;
  int _threadMessageSearchIndexRecalledRevision = -1;
  ChatMessagePositionIndex? _threadMessagePositionIndex;
  List<ChatMessage>? _threadMessagePositionIndexMessagesRef;
  DirectThreadListLayout? _threadListLayout;
  List<ChatMessage>? _threadListLayoutMessagesRef;
  String _threadListLayoutAnchorMessageId = '';
  int _recalledMessageIdsRevision = 0;
  String _threadMessageSearchLocaleTag = '';
  String _chatSearch = '';
  final TextEditingController _contactsSearchCtrl = TextEditingController();
  String _contactsSearch = '';
  final Map<String, GlobalKey> _contactsLetterKeys = <String, GlobalKey>{};
  final GlobalKey _contactsStarredHeaderKey = GlobalKey();
  Timer? _contactsIndexOverlayTimer;
  String? _contactsIndexOverlayLetter;
  final ChatMessageRenderKeys _threadMessageRenderKeys =
      ChatMessageRenderKeys();
  List<ChatMessage>? _threadMessageRenderKeysMessagesRef;
  List<ChatMessage> _messages = [];
  final Map<String, List<ChatMessage>> _cache = {};
  final Map<String, List<ChatGroupMessage>> _groupCache = {};
  final Set<String> _expandedDirectHistoryPeerIds = <String>{};
  final Set<String> _exhaustedDirectHistoryPeerIds = <String>{};
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
  // Reconnect machinery for the two chat sockets. The generation
  // counter prevents an old async-scheduled reconnect from firing
  // after `_listenWs()` was called again (e.g. after an account
  // switch). The backoff step drives `chat_ws_reconnect.dart`'s
  // exponential schedule. Each socket has its own pair so an issue on
  // one (e.g. groups WS flapping during a group-key rotation) doesn't
  // drag the direct inbox WS into the same retry pattern.
  int _wsInboxGeneration = 0;
  int _wsInboxBackoffStep = 0;
  Timer? _wsInboxReconnectTimer;
  int _wsGroupsGeneration = 0;
  int _wsGroupsBackoffStep = 0;
  Timer? _wsGroupsReconnectTimer;
  StreamSubscription<ChatTypingSignal>? _typingWsSub;
  Timer? _conversationEventTimer;
  bool _conversationEventPollInFlight = false;
  int _lastConversationEventId = 0;
  StreamSubscription<RemoteMessage>? _pushSub;
  // Background-to-foreground notification tap (app was in the
  // background, user tapped). `getInitialMessage` (cold start) is
  // checked once in `_listenPush` and doesn't need its own
  // subscription, but the opened-app stream lives for the page's
  // lifetime so we cancel it in `dispose()` like `_pushSub`.
  StreamSubscription<RemoteMessage>? _pushOpenedAppSub;
  final Map<String, DateTime> _peerTypingExpiresAt = <String, DateTime>{};
  Timer? _typingIndicatorTimer;
  Timer? _typingIdleTimer;
  DateTime? _lastTypingSignalAt;
  String? _typingPeerId;
  bool _typingAnnounced = false;
  /// Cycle 47 — message ids whose long text body the user has tapped
  /// to expand. Without an entry here, bubbles whose plain text is
  /// longer than ~600 characters render only the first ~600 and a
  /// "Show more" tap target.
  final Set<String> _expandedLongMessageIds = <String>{};
  // Cycle 37 — periodic presence heartbeat + per-peer last-seen cache.
  Timer? _presenceHeartbeatTimer;
  Timer? _presenceRefreshTimer;
  /// Per-peer last-seen-at timestamps, hydrated from /presence/list.
  /// Null entries are treated as "never seen, render unknown".
  final Map<String, DateTime> _peerLastSeenAt = <String, DateTime>{};
  // Cycle 57 — periodic peer profile refresh + per-peer caches.
  Timer? _profileRefreshTimer;
  /// Per-peer display name as published by that device's own
  /// profile row. The chat list / AppBar / bubble avatar fall back
  /// to the local contact nickname when this is unset.
  final Map<String, String> _peerProfileDisplayName = <String, String>{};
  /// Per-peer avatar bytes, decoded from base64 once at hydrate
  /// time so the renderer doesn't re-decode on every rebuild.
  final Map<String, Uint8List> _peerProfileAvatarBytes =
      <String, Uint8List>{};
  /// Cycle 58 — Slack-style per-peer status (emoji + short text).
  final Map<String, String> _peerProfileStatusEmoji = <String, String>{};
  final Map<String, String> _peerProfileStatusText = <String, String>{};
  /// Cycle 63 — per-conversation notification preview overrides.
  /// Keyed by peer/group id; values are `full` / `name_only` /
  /// `silent`. Absent keys = inherit device-wide default.
  final Map<String, String> _conversationNotificationPreviewMode =
      <String, String>{};
  bool _notifyPreview = false;
  // Per-peer "snoozed until" cache. Populated on chat-page bootstrap
  // from `ChatService.listConversationSnoozes`, then updated locally
  // whenever the user picks/clears a snooze via `_openSnoozePicker`.
  // The server enforces the actual push-suppression; this map only
  // drives the AppBar icon's filled-vs-outlined state and the
  // "Clear snooze" row in the picker.
  final Map<String, DateTime> _peerSnoozedUntil = <String, DateTime>{};
  /// Cycle 12: message ids the user dismissed smart-replies for in
  /// this session. Cleared on chat-page reload; the bar reappears
  /// on the next incoming message regardless of past dismissals.
  final Set<String> _smartRepliesDismissed = <String>{};
  /// Cycle 15: per-message poll cache. The bubble dispatcher
  /// lazily kicks a `getPollByMessage` lookup for every message
  /// whose decoded body begins with the poll-pointer prefix. Result
  /// is either the poll payload Map (loaded; render PollBubble) or
  /// the `_pollSentinelNotPoll` string (lookup said 404; fall back
  /// to plain text). A `null` value means "fetch in flight, render
  /// a placeholder bubble for now".
  final Map<String, Object?> _pollByMessageId = <String, Object?>{};
  /// Cycle 16: per-message voice-transcript cache. Voice bubbles
  /// kick a `fetchVoiceTranscript` lookup lazily on first render
  /// and surface the result inline below the waveform. Values:
  /// `null` (in-flight), `_transcriptSentinelMissing` (404 / none),
  /// or `String` (the actual transcript ready to render).
  final Map<String, Object?> _voiceTranscriptByMessageId =
      <String, Object?>{};
  bool _disappearing = false;
  Duration _disappearAfter = const Duration(minutes: 30);
  bool _showHidden = false;
  bool _showBlocked = false;
  bool _showArchived = false;
  bool _chatSearchVisible = false;
  static const double _archivedPullMaxHeight = 56.0;
  static const double _pullDownMaxHeight = _archivedPullMaxHeight;
  double _archivedPullReveal = 0.0;
  double _archivedPullDragOffset = 0.0;
  bool _archivedPullPinned = false;
  double _archivedPullPinnedHeight = 0.0;
  bool _archivedPullDragging = false;
  bool _archivedPullAdjusting = false;
  Set<String> _archivedGroupIds = <String>{};
  String? _error;
  String? _backupText;
  final Map<String, Uint8List> _sessionKeys = {};
  final Map<String, Uint8List> _sessionKeysByFp = {};
  final Map<String, _ChainState> _chains = {};
  final Map<String, RatchetState> _ratchets = {};
  final Set<String> _peerSessionRecoveryInFlight = <String>{};
  final Map<String, Future<void>> _peerSessionRecoveryTasks =
      <String, Future<void>>{};
  _SafetyNumber? _safetyNumber;
  String? _ratchetWarning;
  final Set<String> _seenMessageIds = {};
  // Side-channel state for outgoing optimistic-send stubs. Keyed by the
  // local message id (`local-<ts>-<rand>`). Entries are inserted at the
  // moment `_send()` builds the stub, transitioned to `failed` if the
  // server-side retry loop exhausts, and *removed* the moment the server
  // returns a canonical message (the stub is then deleted from `_cache`
  // and the server message merged normally). See `chat_send_status.dart`.
  final Map<String, LocalSendState> _localSendStates = <String, LocalSendState>{};
  // Persistent offline outbox (P0-5 module + integration). Failed sends
  // and in-flight stubs are mirrored here so a hard app close mid-send
  // doesn't lose the user's typed message — on the next page open
  // `_hydrateOutboxIfNeeded()` reads it back, stages the stubs as
  // `failed` in the visible thread, and lets the user retry. Flush-
  // on-resume / on-WS-reconnect is the next-cycle add — for now the
  // user re-tries via the bubble's Dismiss-then-retype path or via a
  // future flush hook.
  final ChatOutboxStore _outboxStore = ChatOutboxStore();
  bool _outboxHydrated = false;
  // Ids that have already played the slide-up + fade entrance animation
  // in this page's lifetime. Without this set, every re-layout would
  // replay the animation on every bubble (looks like a slot machine on
  // each scroll-bounce).
  final Set<String> _animatedMessageIds = <String>{};
  bool _promptedForKeyChange = false;
  String? _sessionHash;
  ShamellCapabilities _caps = ShamellCapabilities.conservativeDefaults;
  String _shamellUserId = '';
  int _tabIndex = 0; // 0=Chats,1=Contacts,2=Discover,3=Me
  bool _selectionMode = false;
  final Set<String> _selectedChatIds = <String>{};
  bool _messageSelectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  bool _debugAutoSendTriggered = false;

  bool _beginDeviceLoginApproval() {
    if (_deviceLoginApprovalInFlight) {
      return false;
    }
    _deviceLoginApprovalInFlight = true;
    return true;
  }

  void _endDeviceLoginApproval() {
    _deviceLoginApprovalInFlight = false;
  }

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
  /// Cycle 35 — playback-position stream. Feeds the waveform's
  /// "played" cutover so users see live progress as a voice message
  /// plays. Updated on a coarse cadence by just_audio; we only
  /// rebuild the playing bubble.
  StreamSubscription<Duration>? _playerPositionSub;
  /// Cycle 35 — last known playback position, in milliseconds, of
  /// the currently-playing voice message.
  int _voicePositionMs = 0;
  /// Cycle 35 — last known total duration, in milliseconds, of the
  /// currently-playing voice message. Used to compute the
  /// waveform's progress fraction.
  int _voiceDurationMs = 0;
  String? _playingVoiceMessageId;
  bool _voicePlaying = false;
  String? _voicePlaybackPath;
  Set<String> _voicePlayedMessageIds = <String>{};
  final AudioRecorder _recorder = AudioRecorder();
  String? _voiceRecordingPath;
  bool _voiceCancelPending = false;
  Offset? _voiceGestureStartLocal;
  bool _voiceUseSpeaker = true;
  /// Voice-note playback rate. WhatsApp / Telegram / iMessage all
  /// offer 1× / 1.5× / 2× speed-up so users can skim long voice
  /// notes faster — Cycle 3 polish (audit P1-11). The value is
  /// persisted in SharedPreferences via `_loadVoicePlaybackSpeedPref`
  /// so the user's last choice survives app restart. Allowed values
  /// are the constants in `_kVoicePlaybackSpeedSteps`; the bubble's
  /// in-place toggle cycles through them.
  double _voicePlaybackSpeed = 1.0;
  bool _voiceLocked = false;
  Timer? _voiceTicker;
  int _voiceElapsedSecs = 0;
  int _voiceWaveTick = 0;
  /// Cycle 41 — real amplitude waveform during recording. The
  /// `record` plugin emits an `Amplitude.current` in dBFS at the
  /// chosen interval; we normalise that to [0, 1] and push it into
  /// a ring buffer that the UI reads back to draw the bars.
  static const int _voiceAmpRingLen = 32;
  final List<double> _voiceAmpRing =
      List<double>.filled(_voiceAmpRingLen, 0.0);
  int _voiceAmpHead = 0;
  StreamSubscription<Amplitude>? _voiceAmpSub;
  StreamSubscription<int>? _proximitySub;
  final ChatCallStore _callStore = ChatCallStore();
  List<ChatCallLogEntry>? _lastCallsCache;
  bool _hasOtherDevices = false;
  String? _otherDeviceLabel;
  OfficialAccountHandle? _linkedOfficial;
  String? _linkedOfficialPeerId;
  bool _linkedOfficialFollowed = false;
  int _activeOfficialPeerLoadSerial = 0;
  final Set<String> _officialPeerIds = <String>{};
  final Set<String> _officialPeerUnreadFeeds = <String>{};
  bool _hasUnreadServiceNotifications = false;
  bool _hideServiceNotificationsThread = false;
  final Set<String> _featuredOfficialPeerIds = <String>{};
  final Map<String, String> _officialPeerToAccountId = <String, String>{};
  final Map<String, String> _pendingOfficialFollowIdempotencyKeys =
      <String, String>{};
  final Map<String, String> _pendingOfficialNotificationModeIdempotencyKeys =
      <String, String>{};
  final Set<String> _autoWelcomeLoadedForPeers = <String>{};
  final Map<String, List<Map<String, dynamic>>> _officialAutoRepliesByAccount =
      <String, List<Map<String, dynamic>>>{};
  Map<String, String> _friendAliases = const <String, String>{};
  Map<String, String> _friendTags = const <String, String>{};
  final Set<String> _closeFriendIds = <String>{};
  Map<String, Set<String>> _pinnedMessageIdsByPeer = <String, Set<String>>{};
  final Set<String> _recalledMessageIds = <String>{};
  Map<String, String> _chatThemes = const <String, String>{};
  List<String> _pinnedChatOrder = const <String>[];
  final Map<String, String> _messageReactions = <String, String>{};
  final Base64BytesCache _inlineImageBytesCache =
      Base64BytesCache(maxEntries: 192);
  late final ChatMessagePayloadCache _decodedMessagePayloadCache =
      ChatMessagePayloadCache(
    maxEntries: 512,
    attachmentBytesCache: _inlineImageBytesCache,
  );
  late final DirectMessagePresentationCache _directMessagePresentationCache =
      DirectMessagePresentationCache(maxEntries: 512);

  Future<bool> _forceReauthOnCriticalOfficialHttpFailure({
    required int statusCode,
    String? rawBody,
  }) async {
    if (!mounted) return false;
    final forced = await shamellForceReauthIfCriticalAccountSessionHttpFailure(
      context,
      statusCode: statusCode,
      rawBody: rawBody,
      loginPageBuilder: (_) => const LoginPage(),
    );
    if (forced && mounted) {
      widget.onCriticalOfficialSessionFailure?.call();
    }
    return forced;
  }

  Future<bool> _forceReauthOnCriticalOfficialError(Object error) async {
    if (!mounted) return false;
    final forced = await shamellForceReauthIfCriticalDeviceBindingDrift(
      context,
      error: error,
      loginPageBuilder: (_) => const LoginPage(),
    );
    if (forced && mounted) {
      widget.onCriticalOfficialSessionFailure?.call();
    }
    return forced;
  }

  String _newOfficialMutationIdempotencyKey(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = Random.secure();
    final nonceA = rnd.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    final nonceB = rnd.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return '$prefix-$ts-$nonceA$nonceB';
  }

  Future<bool> _forceReauthOnCriticalChatFailure(Object error) async {
    var forced = false;
    if (error is ChatHttpException) {
      if (!mounted) return false;
      forced = await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: error.statusCode,
        rawBody: error.body,
        loginPageBuilder: (_) => const LoginPage(),
      );
    }
    if (!forced) {
      if (!mounted) return false;
      forced = await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: error,
        loginPageBuilder: (_) => const LoginPage(),
      );
    }
    if (forced && mounted) {
      widget.onCriticalChatSessionFailure?.call();
    }
    return forced;
  }

  Uri? _chatApiUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: pathSegments,
      queryParameters: queryParameters,
    );
  }

  static String _officialNotificationIdsQueryValue(
      Iterable<String> accountIds) {
    final values = accountIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values.join(',');
  }

  static int _compareGroupMessageCursor(
    ChatGroupMessage a,
    ChatGroupMessage b,
  ) {
    final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = at.compareTo(bt);
    if (byTime != 0) return byTime;
    return a.id.compareTo(b.id);
  }

  static ChatGroupMessage? _latestGroupCursorMessage(
    Iterable<ChatGroupMessage> messages,
  ) {
    ChatGroupMessage? latest;
    for (final message in messages) {
      if (message.id.trim().isEmpty) continue;
      if (latest == null || _compareGroupMessageCursor(latest, message) < 0) {
        latest = message;
      }
    }
    return latest;
  }

  static int _compareDirectMessageCursor(
    ChatMessage a,
    ChatMessage b,
  ) {
    final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = at.compareTo(bt);
    if (byTime != 0) return byTime;
    return a.id.compareTo(b.id);
  }

  static ChatMessage? _oldestDirectCursorMessage(
    Iterable<ChatMessage> messages,
  ) {
    ChatMessage? oldest;
    for (final message in messages) {
      if (message.id.trim().isEmpty || message.createdAt == null) {
        continue;
      }
      if (oldest == null || _compareDirectMessageCursor(message, oldest) < 0) {
        oldest = message;
      }
    }
    return oldest;
  }

  void _showInvalidServerUrlSnackBar() {
    if (!mounted) return;
    final l = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sanitizeExceptionForUi(
            error: const FormatException('invalid server url'),
            isArabic: l.isArabic,
          ),
        ),
      ),
    );
  }

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
    // Local nickname (set by the caller) takes precedence — it
    // reflects how *I* prefer to call this person, regardless of
    // what name they publish.
    final alias = _friendAliases[id]?.trim();
    if (alias != null && alias.isNotEmpty) {
      return alias;
    }
    if (c.name != null && c.name!.isNotEmpty) {
      return c.name!;
    }
    // Cycle 57 — fall back to the peer's published profile name
    // before the bare device id.
    final published = _peerProfileDisplayName[id]?.trim();
    if (published != null && published.isNotEmpty) {
      return published;
    }
    return id;
  }

  Future<void> _loadChatThemes() async {
    try {
      final map = await _store.loadChatThemes(baseUrlOverride: widget.baseUrl);
      if (mounted) {
        setState(() {
          _chatThemes = map;
        });
      }
    } catch (_) {}
  }

  Future<void> _setChatThemeForPeer(String peerId, String themeKey) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return;
    final normalizedThemeKey =
        themeKey.trim().isEmpty ? 'default' : themeKey.trim();
    try {
      final override = widget.saveChatThemeForPeerOverride;
      if (override != null) {
        await override(normalizedPeerId, normalizedThemeKey);
      } else {
        await _store.saveChatThemeForPeer(
          normalizedPeerId,
          normalizedThemeKey,
          baseUrlOverride: widget.baseUrl,
        );
      }
      if (!mounted) return;
      _applyState(() {
        final updated = Map<String, String>.from(_chatThemes);
        if (normalizedThemeKey == 'default') {
          updated.remove(normalizedPeerId);
        } else {
          updated[normalizedPeerId] = normalizedThemeKey;
        }
        _chatThemes = updated;
      });
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
      await saveFriendAliasAndTagsForPeer(
        peerId: peerId,
        alias: alias,
        tags: tagsText,
        baseUrlOverride: widget.baseUrl,
      );
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

    final overview = _buildDirectMessageOverviewIndex();
    final mediaPreview = <Uint8List>[];
    for (final entry in overview.mediaEntries.reversed) {
      final attachment = entry.attachment;
      if (attachment == null) continue;
      mediaPreview.add(attachment);
      if (mediaPreview.length >= 3) {
        break;
      }
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShamellChatInfoPage(
          myDisplayName: meName,
          displayName: _displayNameForPeer(peer),
          peerId: peerId,
          // Cycle 59 — surface published status in the chat info
          // header. Empty strings collapse the row in the page.
          peerStatusEmoji: _peerProfileStatusEmoji[peerId],
          peerStatusText: _peerProfileStatusText[peerId],
          // Cycle 63 — per-chat notification preview pref.
          notificationPreviewMode:
              _conversationNotificationPreviewMode[peerId] ?? 'default',
          onSetNotificationPreviewMode: (mode) =>
              _setConversationPreviewMode(
            targetId: peerId,
            isGroup: false,
            mode: mode,
          ),
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
          mediaCount: overview.mediaEntries.length,
          fileCount: overview.fileEntries.length,
          linkCount: overview.linkEntries.length,
          voiceCount: overview.voiceEntries.length,
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
            try {
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
                      final result = await _createGroupWithPeer(
                          name: name, peerId: peerId);
                      final g = result.group;
                      inviteError = result.inviteError;
                      if (g == null) return;

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
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
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
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
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
            } finally {
              nameCtrl.dispose();
            }
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
              await saveCloseFriendForPeer(
                peerId: peerId,
                isClose: makeClose,
                baseUrlOverride: widget.baseUrl,
              );
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
            await _setChatMuted(currentPeer(), muted);
          },
          onTogglePinned: (pinned) async {
            await _setChatPinned(currentPeer(), pinned);
          },
          onToggleHidden: (hidden) async {
            await _setChatHidden(currentPeer(), hidden);
          },
          onToggleBlocked: (blocked) async {
            await _setChatBlocked(currentPeer(), blocked);
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
            Navigator.of(context).pop();
            await Future<void>.delayed(const Duration(milliseconds: 140));
            if (!mounted) return;
            _openMediaOverview();
          },
          onSearchInChat: () async {
            Navigator.of(context).pop();
            _openThreadMessageSearch();
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
            // Cycle 3D: if we're switching AWAY from a previous custom
            // wallpaper, delete the old file from app docs so we don't
            // leak storage as the user cycles through wallpapers.
            final previousKey = _chatThemes[peerId] ?? 'default';
            final previousWallpaperPath =
                wallpaperPathFromThemeKey(previousKey);
            final newWallpaperPath = wallpaperPathFromThemeKey(themeKey);
            if (previousWallpaperPath != null &&
                previousWallpaperPath != newWallpaperPath) {
              unawaited(
                ChatWallpaperPicker()
                    .removeWallpaperFile(previousWallpaperPath),
              );
            }
            await _setChatThemeForPeer(peerId, themeKey);
          },
          onClearChatHistory: () async {
            await _clearChatHistoryForPeer(peer);
          },
          onPickWallpaperFile: () async {
            // Cycle 3D: opens system gallery, copies the chosen image
            // into app-private storage, returns the new theme key
            // (`wallpaper:<absolute_path>`) for the info page to feed
            // back through `onSetTheme`. Returns null on cancel/failure
            // — the info page treats that as "no change".
            final picker = ChatWallpaperPicker();
            final path =
                await picker.pickAndPersistWallpaperForPeer(peerId);
            if (path == null) return null;
            return chatWallpaperThemeKey(path);
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
    try {
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
                                  await saveCloseFriendForPeer(
                                    peerId: peer.id,
                                    isClose: makeClose,
                                    baseUrlOverride: widget.baseUrl,
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
                                await _setChatMuted(peer, !peer.muted);
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
                                await _setChatPinned(peer, !peer.pinned);
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
                                await _setChatHidden(peer, !peer.hidden);
                              },
                            ),
                            FilterChip(
                              label: Text(
                                peer.blocked
                                    ? l.shamellUnblock
                                    : l.shamellBlock,
                              ),
                              selected: peer.blocked,
                              onSelected: (sel) async {
                                await _setChatBlocked(peer, !peer.blocked);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton.icon(
                              icon:
                                  const Icon(Icons.bookmark_outline, size: 18),
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
                                l.isArabic
                                    ? 'الوسائط والروابط'
                                    : 'Media & links',
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.search, size: 18),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _openThreadMessageSearch();
                              },
                              label: Text(
                                l.isArabic
                                    ? 'بحث في الدردشة'
                                    : 'Search in chat',
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
                            Future<void> setTheme(String value) async {
                              await _setChatThemeForPeer(peer.id, value);
                              if (!mounted) return;
                              setThemeState(() {});
                            }

                            return Wrap(
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                  label: Text(l.shamellChatThemeDefault),
                                  selected: currentTheme == 'default',
                                  onSelected: (sel) async {
                                    if (!sel) return;
                                    await setTheme('default');
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(l.shamellChatThemeDark),
                                  selected: currentTheme == 'dark',
                                  onSelected: (sel) async {
                                    if (!sel) return;
                                    await setTheme('dark');
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(l.shamellChatThemeGreen),
                                  selected: currentTheme == 'green',
                                  onSelected: (sel) async {
                                    if (!sel) return;
                                    await setTheme('green');
                                  },
                                ),
                                // Cycle 53 — additional accent options
                                // for per-chat bubble theming.
                                ChoiceChip(
                                  label: Text(l.isArabic ? 'أزرق' : 'Blue'),
                                  selected: currentTheme == 'blue',
                                  onSelected: (sel) async {
                                    if (!sel) return;
                                    await setTheme('blue');
                                  },
                                ),
                                ChoiceChip(
                                  label:
                                      Text(l.isArabic ? 'بنفسجي' : 'Purple'),
                                  selected: currentTheme == 'purple',
                                  onSelected: (sel) async {
                                    if (!sel) return;
                                    await setTheme('purple');
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
                                  await saveFriendAliasAndTagsForPeer(
                                    peerId: peer.id,
                                    alias: alias,
                                    tags: tagsText,
                                    baseUrlOverride: widget.baseUrl,
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    final updated = Map<String, String>.from(
                                        _friendAliases);
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
    } finally {
      ctrl.dispose();
      tagsCtrl.dispose();
    }
  }

  ChatMessageOverviewIndex _buildDirectMessageOverviewIndex() {
    return buildChatMessageOverviewIndex(
      _messages,
      recalledMessageIds: _recalledMessageIds,
      decodeMessage: _decodeMessage,
    );
  }

  /// Cycle 3D: opens the global cross-chat search page. Builds a
  /// one-shot snapshot of every direct + group conversation cache so
  /// the search runs against a stable dataset. Tapping a result pops
  /// the search page and surfaces a SnackBar that names the matched
  /// conversation — the user can then jump to that thread via the
  /// chat list. Deep-link "jump to message N in conversation X" is a
  /// follow-up; the MVP value is "did this conversation say X" and
  /// that ships today.
  Future<void> _openCrossChatSearch() async {
    if (!mounted) return;
    final l = L10n.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Decoded plaintext preview helper for the direct path. Mirrors
    // the wiring used by `_buildDirectMessageOverviewIndex` so search
    // hits and the per-conversation search agree on what counts as
    // "the message text".
    String directPreview(ChatMessage m, DecodedChatMessagePayload d) {
      final t = d.text.trim();
      if (t.isNotEmpty) return t;
      // Fall back to the kind label so a voice/media message can still
      // be located by typing "voice" or "image".
      if (d.kind == 'voice') return 'voice';
      if (d.attachment != null) return 'image';
      return '';
    }

    final directEntries = buildCrossChatSearchEntriesFromDirects(
      directMessagesByPeer: _cache,
      recalledMessageIdsByPeer: const <String, Set<String>>{},
      decodeMessage: _decodeMessage,
      previewText: directPreview,
    );
    final groupEntries =
        buildCrossChatSearchEntriesFromGroups<ChatGroupMessage>(
      groupMessagesByGroup: _groupCache,
      recalledMessageIdsByGroup: const <String, Set<String>>{},
      extractId: (m) => m.id,
      extractText: (m) => m.text,
      extractCreatedAt: (m) => m.createdAt,
      extractContactName: (m) => m.contactName,
      extractMime: (m) => m.attachmentMime,
    );
    final index = buildCrossChatSearchIndex(
      directEntries: directEntries,
      groupEntries: groupEntries,
    );

    // Build a label map so result rows show "Bob" instead of a raw
    // peer device id. We fall back to the device id when no alias has
    // been set — that's exactly what the chat-list tile shows today
    // for unaliased contacts.
    final labels = <String, String>{};
    for (final peerId in _cache.keys) {
      final alias = _friendAliases[peerId]?.trim();
      labels[peerId] =
          (alias == null || alias.isEmpty) ? peerId : alias;
    }
    // `_groups` is stored as a List<ChatGroup>, so build a one-off
    // name lookup for the labels. A few dozen groups at most — linear
    // scan is fine.
    final groupNameById = <String, String>{
      for (final g in _groups) g.id: g.name,
    };
    for (final groupId in _groupCache.keys) {
      final name = groupNameById[groupId]?.trim() ?? '';
      labels[groupId] = name.isEmpty ? groupId : name;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CrossChatSearchPage(
          index: index,
          conversationLabels: labels,
          onOpenResult: (
              {required String conversationId,
              required bool isGroup,
              required String messageId}) {
            navigator.pop();
            final label = labels[conversationId] ?? conversationId;
            messenger.showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 3),
                content: Text(
                  l.isArabic
                      ? 'افتح "$label" لمتابعة الرسالة'
                      : 'Open “$label” to read the matching message',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatMessageOverviewTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _messageSearchResultTitle(
    ChatMessageOverviewEntry entry,
    L10n l,
  ) {
    final text = entry.text.trim();
    if (text.isNotEmpty) {
      return text;
    }
    if (entry.isVoice) {
      return l.shamellPreviewVoice;
    }
    if (entry.isMedia) {
      return l.shamellPreviewImage;
    }
    if (entry.isFile) {
      return l.shamellPreviewUnknown;
    }
    return l.isArabic ? 'رسالة دون محتوى نصي' : 'Non‑text message';
  }

  DirectMessagePresentation _directMessagePresentation(
    ChatMessage message,
    DecodedChatMessagePayload decoded, {
    required String bodyText,
  }) {
    return _directMessagePresentationCache.build(
      message,
      decoded: decoded,
      bodyText: bodyText,
      searchTerm: _messageSearch,
    );
  }

  void _clearThreadMessageSearchIndex() {
    _threadMessageSearchIndex = null;
    _threadMessageSearchIndexMessagesRef = null;
    _threadMessageSearchIndexRecalledRevision = -1;
    _threadMessageSearchLocaleTag = '';
  }

  void _flashThreadMessageHighlight(String messageId) {
    _threadMessageHighlightController.flash(
      messageId,
      onChanged: (highlightedMessageId) {
        if (!mounted) return;
        _applyState(() {
          _highlightedMessageId = highlightedMessageId;
        });
      },
    );
  }

  bool _maybeScheduleInitialThreadMessageJump() {
    if (_initialThreadMessageJumpHandled) {
      return false;
    }
    final targetId = (widget.initialMessageId ?? '').trim();
    if (targetId.isEmpty || _threadMessageIndex(targetId) < 0) {
      return false;
    }
    _initialThreadMessageJumpHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToMessage(targetId, alignment: 0.18, highlight: true));
    });
    return true;
  }

  void _clearThreadMessagePositionIndex() {
    _threadMessagePositionIndex = null;
    _threadMessagePositionIndexMessagesRef = null;
  }

  void _clearThreadListLayout() {
    _threadListLayout = null;
    _threadListLayoutMessagesRef = null;
    _threadListLayoutAnchorMessageId = '';
  }

  void _clearThreadMessageRenderKeys() {
    _threadMessageRenderKeys.clear();
    _threadMessageRenderKeysMessagesRef = null;
  }

  void _syncThreadMessageRenderKeys() {
    if (identical(_threadMessageRenderKeysMessagesRef, _messages)) {
      return;
    }
    _threadMessageRenderKeys.retainMessageIds(
      _messages.map((message) => message.id),
    );
    _threadMessageRenderKeysMessagesRef = _messages;
  }

  GlobalKey? _threadMessageKey(String messageId) {
    _syncThreadMessageRenderKeys();
    return _threadMessageRenderKeys.messageKeyFor(messageId);
  }

  GlobalKey? _existingThreadMessageKey(String messageId) {
    _syncThreadMessageRenderKeys();
    return _threadMessageRenderKeys.existingMessageKey(messageId);
  }

  ChatMessagePositionIndex _currentThreadMessagePositionIndex() {
    final cached = _threadMessagePositionIndex;
    if (cached != null &&
        identical(_threadMessagePositionIndexMessagesRef, _messages)) {
      return cached;
    }
    final index = buildChatMessagePositionIndex(_messages);
    _threadMessagePositionIndex = index;
    _threadMessagePositionIndexMessagesRef = _messages;
    return index;
  }

  int _threadMessageIndex(String messageId) {
    return _currentThreadMessagePositionIndex().indexOf(messageId);
  }

  DirectThreadListLayout _currentThreadListLayout({
    String? newMessagesAnchorMessageId,
  }) {
    final normalizedAnchorId = (newMessagesAnchorMessageId ?? '').trim();
    final normalizedCurrentUserId = (_me?.id ?? '').trim();
    final cached = _threadListLayout;
    if (cached != null &&
        identical(_threadListLayoutMessagesRef, _messages) &&
        _threadListLayoutAnchorMessageId ==
            '$normalizedCurrentUserId|$normalizedAnchorId') {
      return cached;
    }
    final layout = buildDirectThreadListLayout(
      _messages,
      newMessagesAnchorMessageId: normalizedAnchorId,
      currentUserId: normalizedCurrentUserId,
    );
    _threadListLayout = layout;
    _threadListLayoutMessagesRef = _messages;
    _threadListLayoutAnchorMessageId =
        '$normalizedCurrentUserId|$normalizedAnchorId';
    return layout;
  }

  DirectMessageSearchIndex _currentThreadMessageSearchIndex() {
    final localeTag =
        Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? '';
    final cached = _threadMessageSearchIndex;
    if (cached != null &&
        identical(_threadMessageSearchIndexMessagesRef, _messages) &&
        _threadMessageSearchIndexRecalledRevision ==
            _recalledMessageIdsRevision &&
        _threadMessageSearchLocaleTag == localeTag) {
      return cached;
    }
    final index = buildDirectMessageSearchIndex(
      _messages,
      recalledMessageIds: _recalledMessageIds,
      decodeMessage: _decodeMessage,
      previewText: (message, decoded) => _previewText(
        message,
        decoded: decoded,
      ),
    );
    _threadMessageSearchIndex = index;
    _threadMessageSearchIndexMessagesRef = _messages;
    _threadMessageSearchIndexRecalledRevision = _recalledMessageIdsRevision;
    _threadMessageSearchLocaleTag = localeTag;
    return index;
  }

  List<String> _threadMessageSearchMatchIds() {
    if (_messageSearch.trim().isEmpty) {
      return const <String>[];
    }
    return _currentThreadMessageSearchIndex().matchIds(_messageSearch);
  }

  int _threadMessageSearchActiveIndex(List<String> matches) {
    if (matches.isEmpty) return -1;
    final activeMatchId = (_activeThreadMessageSearchMatchId ?? '').trim();
    if (activeMatchId.isEmpty) {
      return 0;
    }
    final index = matches.indexOf(activeMatchId);
    return index >= 0 ? index : 0;
  }

  void _openThreadMessageSearch() {
    if (_messages.isEmpty) return;
    _messageSearchCtrl
      ..text = ''
      ..selection = const TextSelection.collapsed(offset: 0);
    _threadMessageHighlightController.clear();
    _applyState(() {
      _showMessageSearchBar = true;
      _messageSearch = '';
      _activeThreadMessageSearchMatchId = null;
      _highlightedMessageId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageSearchFocus.requestFocus();
    });
  }

  void _closeThreadMessageSearch() {
    _messageSearchCtrl.clear();
    _threadMessageHighlightController.clear();
    _applyState(() {
      _showMessageSearchBar = false;
      _messageSearch = '';
      _activeThreadMessageSearchMatchId = null;
      _highlightedMessageId = null;
    });
    if (!_shamellVoiceMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _composerFocus.requestFocus();
      });
    }
  }

  Future<void> _jumpThreadMessageSearchMatch(
    int delta, {
    bool forceFirst = false,
  }) async {
    final matches = _threadMessageSearchMatchIds();
    if (matches.isEmpty) {
      _threadMessageHighlightController.clear();
      _applyState(() {
        _activeThreadMessageSearchMatchId = null;
        _highlightedMessageId = null;
      });
      return;
    }
    final currentIndex =
        forceFirst ? -1 : _threadMessageSearchActiveIndex(matches);
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + delta + matches.length) % matches.length;
    final targetId = matches[nextIndex];
    _applyState(() {
      _activeThreadMessageSearchMatchId = targetId;
    });
    await _scrollToMessage(targetId, alignment: 0.18);
  }

  void _handleThreadMessageSearchChanged(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      _threadMessageHighlightController.clear();
    }
    _applyState(() {
      _messageSearch = normalized;
      if (normalized.isEmpty) {
        _activeThreadMessageSearchMatchId = null;
        _highlightedMessageId = null;
      }
    });
    if (normalized.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_jumpThreadMessageSearchMatch(1, forceFirst: true));
    });
  }

  Widget _buildThreadMessageSearchBar(
    L10n l,
    ThemeData theme,
  ) {
    if (!_showMessageSearchBar) {
      return const SizedBox.shrink();
    }
    final matches = _threadMessageSearchMatchIds();
    final activeIndex = _threadMessageSearchActiveIndex(matches);
    final hasMatches = matches.isNotEmpty;
    final countLabel =
        hasMatches ? '${activeIndex + 1}/${matches.length}' : '0/0';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: .55),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageSearchCtrl,
                focusNode: _messageSearchFocus,
                autofocus: false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      l.isArabic ? 'ابحث داخل المحادثة' : 'Search in chat',
                  border: InputBorder.none,
                ),
                onChanged: _handleThreadMessageSearchChanged,
                onSubmitted: (_) {
                  if (hasMatches) {
                    unawaited(_jumpThreadMessageSearchMatch(1));
                  }
                },
              ),
            ),
            Text(
              countLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              tooltip: l.isArabic ? 'السابق' : 'Previous',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              onPressed: hasMatches
                  ? () => unawaited(_jumpThreadMessageSearchMatch(-1))
                  : null,
            ),
            IconButton(
              tooltip: l.isArabic ? 'التالي' : 'Next',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              onPressed: hasMatches
                  ? () => unawaited(_jumpThreadMessageSearchMatch(1))
                  : null,
            ),
            IconButton(
              tooltip: l.shamellDialogCancel,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: _closeThreadMessageSearch,
            ),
          ],
        ),
      ),
    );
  }

  ChatMessageOverviewFilter _overviewFilterForSearch(String filter) {
    switch (filter) {
      case 'media':
        return ChatMessageOverviewFilter.media;
      case 'links':
        return ChatMessageOverviewFilter.links;
      case 'voice':
        return ChatMessageOverviewFilter.voice;
      case 'all':
      default:
        return ChatMessageOverviewFilter.all;
    }
  }

  ChatMessageOverviewFilter _overviewFilterForMedia(String filter) {
    switch (filter) {
      case 'files':
        return ChatMessageOverviewFilter.files;
      case 'links':
        return ChatMessageOverviewFilter.links;
      case 'media':
      default:
        return ChatMessageOverviewFilter.media;
    }
  }

  // ignore: unused_element
  Future<void> _openMessageSearch() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final ctrl = TextEditingController();
    final overview = _buildDirectMessageOverviewIndex();
    final callResults = <ChatCallLogEntry>[
      for (final entry in (_lastCallsCache ?? const <ChatCallLogEntry>[]))
        if (_peer != null && entry.peerId == _peer!.id) entry,
    ]..sort((a, b) => b.ts.compareTo(a.ts));
    String filter = 'all';
    try {
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
                  final results = filter == 'calls'
                      ? const <ChatMessageOverviewEntry>[]
                      : overview.filtered(
                          query: query,
                          filter: _overviewFilterForSearch(filter),
                        );
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
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final entry = results[results.length - 1 - i];
                              final tsLabel = _formatMessageOverviewTimestamp(
                                entry.timestamp,
                              );
                              return ListTile(
                                dense: true,
                                title: Text(
                                  _messageSearchResultTitle(entry, l),
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
                                  final messageId = entry.message.id;
                                  Navigator.of(ctx).pop();
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    unawaited(_scrollToMessage(
                                      messageId,
                                      alignment: 0.18,
                                      highlight: true,
                                    ));
                                  });
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
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _openMediaOverview() async {
    final peer = _peer;
    if (peer == null) return;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final overview = _buildDirectMessageOverviewIndex();
    final ctrl = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          String filter = 'media';
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final bottom = MediaQuery.of(ctx).viewInsets.bottom;
              final maxHeight = MediaQuery.of(ctx).size.height * .78;
              final query = ctrl.text.trim();
              final list = overview
                  .filtered(
                    query: query,
                    filter: _overviewFilterForMedia(filter),
                  )
                  .reversed
                  .toList();

              void openEntry(ChatMessageOverviewEntry entry) {
                final messageId = entry.message.id;
                Navigator.of(ctx).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(_scrollToMessage(
                    messageId,
                    alignment: 0.18,
                    highlight: true,
                  ));
                });
              }

              Widget chip({
                required String value,
                required String label,
                required int count,
              }) {
                return ChoiceChip(
                  label: Text('$label $count'),
                  selected: filter == value,
                  onSelected: (sel) {
                    if (!sel) return;
                    setModalState(() {
                      filter = value;
                    });
                  },
                );
              }

              Widget mediaGrid() {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, i) {
                    final entry = list[i];
                    final bytes = entry.attachment;
                    final mime = (entry.mime ?? '').toLowerCase();
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => openEntry(entry),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .06),
                          ),
                          child: bytes != null &&
                                  bytes.isNotEmpty &&
                                  mime.startsWith('image/')
                              ? Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  // Cap the decoded memory footprint
                                  // to the actual on-screen size of
                                  // this composer-preview tile (P1-12
                                  // image cache hardening). Full-res
                                  // bytes still live in the message's
                                  // attachment_b64; we just stop
                                  // burning 8 MB per 4K photo for a
                                  // 60 px tile.
                                  cacheWidth: 240,
                                  cacheHeight: 240,
                                  filterQuality: FilterQuality.medium,
                                )
                              : Center(
                                  child: Icon(
                                    mime.startsWith('video/')
                                        ? Icons.play_circle_outline
                                        : Icons.photo_library_outlined,
                                    size: 28,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .55),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                );
              }

              Widget resultList() {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final entry = list[i];
                    final tsLabel = _formatMessageOverviewTimestamp(
                      entry.timestamp,
                    );
                    final title = _messageSearchResultTitle(entry, l);
                    final icon = filter == 'links'
                        ? Icons.link
                        : filter == 'files'
                            ? Icons.description_outlined
                            : Icons.photo_library_outlined;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: .12),
                        child: Icon(icon, size: 18),
                      ),
                      title: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: tsLabel.isEmpty
                          ? null
                          : Text(
                              tsLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .65),
                              ),
                            ),
                      onTap: () => openEntry(entry),
                    );
                  },
                );
              }

              return Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, bottom + 12),
                child: GlassPanel(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: SingleChildScrollView(
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
                              Expanded(
                                child: Text(
                                  l.shamellMediaOverviewTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search, size: 18),
                              hintText: l.isArabic
                                  ? 'ابحث في الوسائط والروابط'
                                  : 'Search media, links, files',
                              isDense: true,
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              chip(
                                value: 'media',
                                label: l.shamellSearchFilterMedia,
                                count: overview.mediaEntries.length,
                              ),
                              chip(
                                value: 'files',
                                label: l.shamellSearchFilterFiles,
                                count: overview.fileEntries.length,
                              ),
                              chip(
                                value: 'links',
                                label: l.shamellSearchFilterLinks,
                                count: overview.linkEntries.length,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (list.isEmpty)
                            Text(
                              l.shamellMediaOverviewEmpty,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            )
                          else if (filter == 'media')
                            mediaGrid()
                          else
                            resultList(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    // Listen for app-resume so the outbox flush can fire when the user
    // foregrounds the app after a connectivity blip. The observer is
    // removed in dispose. Cheap to register; the framework only
    // delivers events we listen to.
    WidgetsBinding.instance.addObserver(this);
    // Hydrate the user's last-chosen voice playback speed (1× / 1.5×
    // / 2×) so subsequent plays honour it from the first voice note
    // tap. Best-effort + decoupled from the first paint.
    unawaited(_loadVoicePlaybackSpeedPref());
    // Hydrate the global read-receipts privacy preference (P1-17)
    // before the first incoming message triggers `_startLiveDirectReadAck`,
    // so a user who's disabled read receipts doesn't accidentally
    // leak a `read_at` on their first foreground tick. Defaults to
    // enabled until the disk read resolves — same fail-safe behaviour
    // as today's unconditional ack path.
    unawaited(ChatReadReceiptsPref.hydrate());
    ShamellChatPresenceRegistry.enter();
    _ownsService = widget.serviceOverride == null;
    _service = widget.serviceOverride ?? ChatService(widget.baseUrl);
    // Cycle 37 — heartbeat the user's presence once per minute while
    // the chat surface is mounted. The first beat fires after init
    // settles; later beats are scheduled by the Timer.
    _presenceHeartbeatTimer =
        Timer.periodic(const Duration(seconds: 60), (_) {
      // ignore: discarded_futures
      _emitPresenceHeartbeat();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _emitPresenceHeartbeat();
    });
    // Refresh peer last-seen data every 45s.
    _presenceRefreshTimer =
        Timer.periodic(const Duration(seconds: 45), (_) {
      // ignore: discarded_futures
      _refreshPeerPresence();
    });
    // Cycle 57 — refresh peer profile data every 5 min. First load
    // fires once contacts are hydrated (kicked off from the same
    // post-frame callback below).
    _profileRefreshTimer =
        Timer.periodic(const Duration(minutes: 5), (_) {
      // ignore: discarded_futures
      _refreshPeerProfiles();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _refreshPeerProfiles();
      // ignore: discarded_futures
      _loadConversationNotificationPrefs();
    });
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
      final completed = st.processingState == ProcessingState.completed;
      String? completedVoicePath;
      if (!mounted) return;
      if (playing == _voicePlaying && !completed) {
        return;
      }
      setState(() {
        _voicePlaying = playing;
        if (completed) {
          _playingVoiceMessageId = null;
          completedVoicePath = _voicePlaybackPath;
          _voicePlaybackPath = null;
          _voicePositionMs = 0;
          _voiceDurationMs = 0;
        }
      });
      if (completedVoicePath != null) {
        unawaited(deleteEphemeralVoiceFile(completedVoicePath));
      }
    });
    // Cycle 35 — drive the live waveform-progress fraction. just_audio
    // emits position updates at ~10 Hz; we throttle the rebuild to
    // ~5 Hz to keep the bubble repaint cost low on older Androids.
    var lastWavePaint = DateTime.fromMillisecondsSinceEpoch(0);
    _playerPositionSub = _audioPlayer.positionStream.listen((pos) {
      if (!mounted || _playingVoiceMessageId == null) return;
      final now = DateTime.now();
      if (now.difference(lastWavePaint).inMilliseconds < 200) return;
      lastWavePaint = now;
      final dur = _audioPlayer.duration?.inMilliseconds ?? 0;
      setState(() {
        _voicePositionMs = pos.inMilliseconds;
        _voiceDurationMs = dur;
      });
    });
    // Best-effort load of per-chat theme preferences.
    // Ignore failures; chat works fine without them.
    // ignore: discarded_futures
    _loadChatThemes();
    // Best-effort load of per-conversation snooze state. Drives the
    // AppBar bell icon + the picker's "Clear snooze" row. Pure UX
    // polish: server enforcement is authoritative even if this fails.
    // ignore: discarded_futures
    _loadConversationSnoozes();
    // Cycle 27: hydrate the recently-used reaction emojis from
    // SharedPreferences so the quick-react row surfaces the user's
    // personal top-6 instead of the hardcoded default slate.
    // ignore: discarded_futures
    ChatReactionRecent.instance.hydrate();
    // Cycle 10: the server-side delivery worker now drains due
    // scheduled-message rows directly into `chat_messages`, so the
    // Cycle 9 client-side ticker is no longer needed. The
    // `_scheduledDequeueTimer` field + `_startScheduledDequeueTimer`
    // + `_dequeueAndReplayDueScheduledMessages` plumbing has been
    // removed in this cycle.
    if (widget.runStartupTasks) {
      _bootstrap();
    }
  }

  bool _isCurveKey(Uint8List key) => key.length == _curveKeyBytes;

  @visibleForTesting
  void debugSetCapabilities(ShamellCapabilities caps) {
    _caps = caps;
  }

  @visibleForTesting
  void debugSetServiceNotificationsThreadState({
    required bool hasUnread,
    bool hideThread = false,
  }) {
    _applyState(() {
      _hasUnreadServiceNotifications = hasUnread;
      _hideServiceNotificationsThread = hideThread;
    });
  }

  @visibleForTesting
  Map<String, Object?> debugServiceNotificationsThreadState() =>
      <String, Object?>{
        'hasUnread': _hasUnreadServiceNotifications,
        'hideThread': _hideServiceNotificationsThread,
      };

  @visibleForTesting
  Future<void> debugLoadBootstrapSystemThreadsSideState() async {
    await _loadBootstrapSystemThreadsSideState();
  }

  @visibleForTesting
  void debugStartBootstrapServiceNotificationsBadgeRefresh() {
    _startBootstrapServiceNotificationsBadgeRefresh();
  }

  @visibleForTesting
  Future<void> debugHandleServiceNotificationsThreadTap() async {
    await _openServiceNotificationsThread();
  }

  @visibleForTesting
  Future<void> debugLoadStoredShamellUserId() async {
    final shamellUserId = await _loadStoredShamellUserIdBestEffort();
    if (!mounted) return;
    setState(() {
      _shamellUserId = shamellUserId;
    });
  }

  @visibleForTesting
  String get debugCurrentShamellUserId => _shamellUserId;

  @visibleForTesting
  Future<void> debugToggleOfficialFollowFromChat({
    required String officialId,
    required String kind,
    bool followed = false,
  }) async {
    _linkedOfficial = OfficialAccountHandle(
      id: officialId,
      kind: kind,
      name: 'Official',
      chatPeerId: 'peer-official',
      followed: followed,
    );
    _linkedOfficialFollowed = followed;
    await _toggleOfficialFollowFromChat();
  }

  @visibleForTesting
  Future<void> debugLoadOfficialForPeer(String peerId) async {
    await _loadOfficialForPeer(
      ChatContact(
        id: peerId,
        publicKeyB64: 'pk',
        fingerprint: 'fp',
        name: 'Peer',
      ),
      updateState: false,
    );
  }

  @visibleForTesting
  Future<void> debugLoadOfficialPeers() async {
    await _loadOfficialPeers();
  }

  @visibleForTesting
  Map<String, Object?> debugOfficialPeerState() {
    final officialPeerIds = _officialPeerIds.toList()..sort();
    final officialPeerUnreadFeeds = _officialPeerUnreadFeeds.toList()..sort();
    final featuredOfficialPeerIds = _featuredOfficialPeerIds.toList()..sort();
    final officialPeerToAccountId =
        Map<String, String>.from(_officialPeerToAccountId);
    return <String, Object?>{
      'officialPeerIds': officialPeerIds,
      'officialPeerUnreadFeeds': officialPeerUnreadFeeds,
      'featuredOfficialPeerIds': featuredOfficialPeerIds,
      'officialPeerToAccountId': officialPeerToAccountId,
      'linkedOfficialPeerId': _linkedOfficialPeerId,
      'linkedOfficialId': _linkedOfficial?.id,
      'linkedOfficialFollowed': _linkedOfficialFollowed,
    };
  }

  @visibleForTesting
  Future<void> debugLoadBootstrapOfficialForCurrentPeer() async {
    final peer = _peer;
    if (peer == null) return;
    await _loadBootstrapOfficialForCurrentPeer(peer);
  }

  @visibleForTesting
  void debugSeedOfficialPeerMapping(Map<String, String> peerToAccountId) {
    _officialPeerToAccountId
      ..clear()
      ..addAll(peerToAccountId);
  }

  @visibleForTesting
  Future<void> debugLoadBootstrapOfficialNotificationModes() async {
    await _loadBootstrapOfficialNotificationModes();
  }

  @visibleForTesting
  Future<void> debugLoadBootstrapDirectPrefsSync() async {
    await _loadBootstrapDirectPrefsSync();
  }

  @visibleForTesting
  Future<void> debugLoadBootstrapGroupPrefsSync() async {
    await _loadBootstrapGroupPrefsSync();
  }

  @visibleForTesting
  Future<void> debugLoadBootstrapInitialPeerResolve(String peerId) async {
    await _loadBootstrapInitialPeerResolve(peerId);
  }

  @visibleForTesting
  Future<void> debugLoadBootstrapSideMetadata() async {
    await _loadBootstrapSideMetadata();
  }

  @visibleForTesting
  Future<void> debugLoadServiceNotificationsBadge() async {
    await _loadServiceNotificationsBadge();
  }

  @visibleForTesting
  Future<void> debugLoadDevicesSummary() async {
    await _loadDevicesSummary();
  }

  @visibleForTesting
  Map<String, Object?> debugDevicesSummaryState() => <String, Object?>{
        'hasOtherDevices': _hasOtherDevices,
        'otherDeviceLabel': _otherDeviceLabel,
      };

  @visibleForTesting
  Future<void> debugLoadBootstrapDevicesSummary() async {
    await _loadBootstrapDevicesSummary();
  }

  @visibleForTesting
  Future<void> debugLoadChatThemes() async {
    await _loadChatThemes();
  }

  @visibleForTesting
  Future<void> debugRestoreBootstrapState() async {
    await _restoreBootstrapState();
  }

  @visibleForTesting
  String debugBuildIdentityBackupPayload({
    required ChatIdentity identity,
    required String passphrase,
  }) {
    return _buildIdentityBackupPayload(
      identity: identity,
      passphrase: passphrase,
    );
  }

  @visibleForTesting
  Future<void> debugRestoreIdentityFromBackupPayload({
    required String backup,
    required String passphrase,
  }) async {
    await _restoreIdentityFromBackupPayload(
      backup: backup,
      passphrase: passphrase,
    );
  }

  @visibleForTesting
  Map<String, Object?> debugBootstrapState() => <String, Object?>{
        'meId': _me?.id,
        'peerId': _peer?.id,
        'loading': _loading,
        'sending': _sending,
        'contactCount': _contacts.length,
        'cachedMessageCount': _cache.values.fold<int>(
          0,
          (sum, messages) => sum + messages.length,
        ),
        'messageCount': _messages.length,
        'friendAliasCount': _friendAliases.length,
        'friendTagCount': _friendTags.length,
        'closeFriendCount': _closeFriendIds.length,
        'archivedGroupCount': _archivedGroupIds.length,
      };

  @visibleForTesting
  String debugChatThemeForPeer(String peerId) {
    return _chatThemes[peerId] ?? 'default';
  }

  @visibleForTesting
  Future<void> debugSetChatThemeForPeer(String peerId, String themeKey) async {
    await _setChatThemeForPeer(peerId, themeKey);
  }

  @visibleForTesting
  bool debugIsMessagePinnedForPeer(String peerId, String messageId) {
    final pinnedIds = _pinnedMessageIdsByPeer[peerId] ?? const <String>{};
    return pinnedIds.contains(messageId);
  }

  @visibleForTesting
  bool debugIsMessageRecalled(String messageId) {
    return _recalledMessageIds.contains(messageId);
  }

  @visibleForTesting
  Future<void> debugSetPinnedMessageForPeer(
    String peerId,
    String messageId,
    bool pinned,
  ) async {
    await _setPinnedMessageState(peerId, messageId, pinned);
  }

  @visibleForTesting
  Future<void> debugSetRecalledMessageState(
    String messageId,
    bool recalled,
  ) async {
    await _setRecalledMessageState(messageId, recalled);
  }

  @visibleForTesting
  Future<void> debugHandleMessageRecalled(String messageId) async {
    await _handleMessageRecalled(messageId);
  }

  @visibleForTesting
  bool debugNotifyPreviewEnabled() => _notifyPreview;

  @visibleForTesting
  bool debugShowHiddenEnabled() => _showHidden;

  @visibleForTesting
  bool debugShowBlockedEnabled() => _showBlocked;

  @visibleForTesting
  bool debugSelectionModeEnabled() => _selectionMode;

  @visibleForTesting
  String? debugHighlightedMessageId() => _highlightedMessageId;

  @visibleForTesting
  int debugThreadMessageRenderKeyCount() =>
      _threadMessageRenderKeys.messageKeyCount;

  Future<void> _saveNotifyPreviewSetting(bool enabled) async {
    final override = widget.saveNotifyPreviewOverride;
    if (override != null) {
      await override(enabled);
      return;
    }
    await _store.setNotifyPreview(
      enabled,
      baseUrlOverride: widget.baseUrl,
    );
  }

  @visibleForTesting
  Future<void> debugSetNotifyPreview(bool enabled) async {
    _applyState(() => _notifyPreview = enabled);
    await _saveNotifyPreviewSetting(enabled);
  }

  @visibleForTesting
  Future<void> debugSyncOfficialNotificationModesFromServer(
    Map<String, String> peerToAccountId,
  ) async {
    _officialPeerToAccountId
      ..clear()
      ..addAll(peerToAccountId);
    await _syncOfficialNotificationModesFromServer();
  }

  @visibleForTesting
  Future<void> debugSetStoredOfficialNotificationMode(
    String peerId,
    OfficialNotificationMode? mode,
  ) async {
    await _store.setOfficialNotifMode(
      peerId,
      mode,
      baseUrlOverride: widget.baseUrl,
    );
  }

  @visibleForTesting
  Future<String?> debugLoadStoredOfficialNotificationMode(String peerId) async {
    final mode = await _store.loadOfficialNotifMode(
      peerId,
      baseUrlOverride: widget.baseUrl,
    );
    return switch (mode) {
      OfficialNotificationMode.full => 'full',
      OfficialNotificationMode.summary => 'summary',
      OfficialNotificationMode.muted => 'muted',
      null => null,
    };
  }

  @visibleForTesting
  Future<void> debugEnsureServiceOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {
    await _ensureServiceOfficialFollow(
      officialId: officialId,
      chatPeerId: chatPeerId,
    );
  }

  @visibleForTesting
  Future<List<Map<String, dynamic>>> debugLoadOfficialAutoReplies(
    String accountId,
  ) async {
    return _loadOfficialAutoReplies(accountId);
  }

  @visibleForTesting
  Future<void> debugConfirmDeviceLogin(String token, {String? label}) async {
    await _confirmDeviceLogin(token, label: label);
  }

  @visibleForTesting
  void debugSeedDirectThread({
    required ChatIdentity me,
    required ChatContact peer,
    List<ChatMessage> messages = const <ChatMessage>[],
  }) {
    _applyState(() {
      _me = me;
      _peer = peer;
      _activePeerId = peer.id;
      _contacts = _upsertContact(peer);
      _messages = List<ChatMessage>.from(messages)
        ..sort(_compareDirectMessageCursor);
      _cache[peer.id] = List<ChatMessage>.from(_messages);
      _expandedDirectHistoryPeerIds.remove(peer.id);
      _exhaustedDirectHistoryPeerIds.remove(peer.id);
      _loadingOlderThreadMessages = false;
      _hasOlderThreadMessages = _shouldExposeOlderThreadHistory(
        peer.id,
        _messages,
      );
      _threadNearBottom = true;
      _threadNewMessagesAwayCount = 0;
      _threadNewMessagesFirstId = null;
    });
  }

  @visibleForTesting
  void debugSeedGroupThread({
    required ChatGroup group,
    List<ChatGroupMessage> messages = const <ChatGroupMessage>[],
  }) {
    _applyState(() {
      if (!_groups.any((existing) => existing.id == group.id)) {
        _groups = <ChatGroup>[..._groups, group];
      }
      _groupCache[group.id] = List<ChatGroupMessage>.from(messages)
        ..sort(_compareGroupMessageCursor);
    });
  }

  @visibleForTesting
  Future<void> debugSendComposerMessage(String text) async {
    _msgCtrl.text = text;
    await _send();
  }

  @visibleForTesting
  String debugDecodeDirectMessageText(ChatMessage message) {
    return _decodeMessage(message).text;
  }

  @visibleForTesting
  Future<void> debugSeedRatchetForPeer(
    String peerId,
    RatchetState state,
  ) async {
    _ratchets[peerId] = state;
    await _store.saveRatchet(
      peerId,
      state.toJson(),
      baseUrlOverride: widget.baseUrl,
    );
  }

  @visibleForTesting
  String? debugCurrentRatchetWarning() => _ratchetWarning;

  @visibleForTesting
  void debugSetRatchetWarning(String? warning) {
    _applyState(() {
      final normalized = warning?.trim();
      _ratchetWarning =
          normalized == null || normalized.isEmpty ? null : normalized;
    });
  }

  @visibleForTesting
  void debugSeedDraftForChat(String chatId, String text) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    if (text.trim().isEmpty) {
      _draftTextByChatId.remove(id);
      _composerDraftByChatId.remove(id);
      return;
    }
    _draftTextByChatId[id] = text;
    _composerDraftByChatId[id] = _ShamellChatComposerDraft(text: text);
  }

  @visibleForTesting
  Future<void> debugSendDirectTextQuick(String text) async {
    await _sendTextMessage(text);
  }

  @visibleForTesting
  Future<void> debugSendDirectVoice(Uint8List audioBytes, int seconds) async {
    await _sendVoiceNote(audioBytes, seconds);
  }

  @visibleForTesting
  Future<void> debugSendDirectLocation(
    double lat,
    double lon, {
    String? label,
  }) async {
    await _sendLocation(lat, lon, label: label);
  }

  @visibleForTesting
  Future<void> debugSendDirectContactCard(String contactId) async {
    await _sendContactCard(contactId);
  }

  @visibleForTesting
  Future<void> debugRunComposerMoreActionByIcon(IconData icon) async {
    final peer = _peer;
    if (peer == null) return;
    final action = _buildComposerMoreActions(peer).firstWhere(
      (candidate) => candidate.icon == icon,
    );
    await action.onTap();
  }

  @visibleForTesting
  Future<void> debugForwardDirectMessages(
    List<ChatMessage> msgs, {
    ChatContact? target,
  }) async {
    final resolvedTarget = target ?? _peer;
    if (resolvedTarget == null) return;
    await _forwardMessagesToTarget(msgs, resolvedTarget);
  }

  @visibleForTesting
  Future<void> debugSendRecallForMessage(ChatMessage m) async =>
      _sendRecallForMessage(m);

  @visibleForTesting
  Future<void> debugPullInbox() async {
    await _pullInbox();
  }

  @visibleForTesting
  Future<void> debugLoadOlderThreadMessages() async {
    await _loadOlderThreadMessages();
  }

  @visibleForTesting
  bool debugHasOlderThreadMessages() => _hasOlderThreadMessages;

  bool _shouldExposeOlderThreadHistory(
    String peerId,
    List<ChatMessage> messages,
  ) {
    if (peerId.trim().isEmpty) return false;
    if (_expandedDirectHistoryPeerIds.contains(peerId) &&
        _exhaustedDirectHistoryPeerIds.contains(peerId)) {
      return false;
    }
    return messages.length >= _directOlderMessagesPageSize;
  }

  Future<List<ChatMessage>> _seedThreadHistoryIfEmpty({
    required ChatIdentity me,
    required ChatContact peer,
    required List<ChatMessage> cached,
  }) async {
    final sortedCached = List<ChatMessage>.from(cached)
      ..sort(_compareDirectMessageCursor);
    if (sortedCached.isNotEmpty) {
      return sortedCached;
    }
    final remote = await _service.fetchThreadHistory(
      deviceId: me.id,
      peerId: peer.id,
      limit: _directOlderMessagesPageSize,
    );
    if (remote.length < _directOlderMessagesPageSize) {
      _exhaustedDirectHistoryPeerIds.add(peer.id);
    } else {
      _exhaustedDirectHistoryPeerIds.remove(peer.id);
    }
    if (remote.isEmpty) {
      return sortedCached;
    }
    await _store.saveMessages(
      peer.id,
      remote,
      baseUrlOverride: widget.baseUrl,
    );
    return remote;
  }

  Future<void> _loadOlderThreadMessages() async {
    final me = _me;
    final peer = _peer;
    if (_loading ||
        _loadingOlderThreadMessages ||
        !_hasOlderThreadMessages ||
        me == null ||
        peer == null) {
      return;
    }

    final oldest = _oldestDirectCursorMessage(_messages);
    final beforeCreatedAt = oldest?.createdAt?.toUtc().toIso8601String();
    final beforeId = oldest?.id.trim() ?? '';
    if ((beforeCreatedAt ?? '').isEmpty || beforeId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _hasOlderThreadMessages = false;
      });
      _exhaustedDirectHistoryPeerIds.add(peer.id);
      return;
    }

    final hadClients = _threadScrollCtrl.hasClients;
    final beforeOffset = hadClients ? _threadScrollCtrl.offset : 0.0;
    final beforeMaxExtent =
        hadClients ? _threadScrollCtrl.position.maxScrollExtent : 0.0;

    setState(() {
      _loadingOlderThreadMessages = true;
    });

    var exhausted = false;

    try {
      final items = await _service.fetchThreadHistory(
        deviceId: me.id,
        peerId: peer.id,
        limit: _directOlderMessagesPageSize,
        beforeCreatedAt: beforeCreatedAt,
        beforeId: beforeId,
      );
      final collected = <ChatMessage>[
        for (final item in items)
          if (item.id.trim().isNotEmpty) item,
      ];
      exhausted = items.length < _directOlderMessagesPageSize;

      if (!mounted) return;

      if (collected.isEmpty && exhausted) {
        _expandedDirectHistoryPeerIds.add(peer.id);
        _exhaustedDirectHistoryPeerIds.add(peer.id);
        setState(() {
          _loadingOlderThreadMessages = false;
          _hasOlderThreadMessages = false;
        });
        return;
      }

      final mergedById = <String, ChatMessage>{
        for (final message in (_cache[peer.id] ?? _messages))
          if (message.id.trim().isNotEmpty) message.id: message,
      };
      for (final message in collected) {
        final itemId = message.id.trim();
        if (itemId.isEmpty) continue;
        mergedById[itemId] = message;
      }
      final merged = mergedById.values.toList()
        ..sort(_compareDirectMessageCursor);
      _cache[peer.id] = merged;
      _expandedDirectHistoryPeerIds.add(peer.id);
      if (exhausted) {
        _exhaustedDirectHistoryPeerIds.add(peer.id);
      } else {
        _exhaustedDirectHistoryPeerIds.remove(peer.id);
      }
      final stillActivePeer = _activePeerId == peer.id && _peer?.id == peer.id;

      setState(() {
        if (stillActivePeer) {
          _messages = merged;
        }
        _loadingOlderThreadMessages = false;
        _hasOlderThreadMessages = !exhausted;
      });

      try {
        await _store.saveMessages(
          peer.id,
          merged,
          baseUrlOverride: widget.baseUrl,
        );
      } catch (_) {}

      final scheduledInitialJump =
          stillActivePeer && _maybeScheduleInitialThreadMessageJump();
      if (stillActivePeer && hadClients && !scheduledInitialJump) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_threadScrollCtrl.hasClients) return;
          final delta =
              _threadScrollCtrl.position.maxScrollExtent - beforeMaxExtent;
          final target = beforeOffset + max(0.0, delta);
          try {
            _threadScrollCtrl.jumpTo(target);
          } catch (_) {}
        });
      }
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      if (!mounted) return;
      setState(() {
        _loadingOlderThreadMessages = false;
        _error = _sendFailureToUi(e);
      });
    }
  }

  @visibleForTesting
  Future<void> debugSyncGroups() async {
    await _syncGroups();
  }

  @visibleForTesting
  Future<void> debugMergeGroupInboxUpdate(ChatGroupInboxUpdate update) async {
    await _mergeGroupInboxUpdate(update);
  }

  @visibleForTesting
  void debugListenWs() {
    _listenWs();
  }

  @visibleForTesting
  void debugSeedUnread(Map<String, int> unread) {
    _unread = Map<String, int>.from(unread);
  }

  @visibleForTesting
  Map<String, int> debugUnreadSnapshot() => Map<String, int>.from(_unread);

  @visibleForTesting
  void debugSeedGroupMentionState({
    Iterable<String> mentionUnread = const <String>[],
    Iterable<String> mentionAllUnread = const <String>[],
  }) {
    _groupMentionUnread = Set<String>.from(mentionUnread);
    _groupMentionAllUnread = Set<String>.from(mentionAllUnread);
  }

  @visibleForTesting
  Set<String> debugGroupMentionUnreadSnapshot() =>
      Set<String>.from(_groupMentionUnread);

  @visibleForTesting
  Set<String> debugGroupMentionAllUnreadSnapshot() =>
      Set<String>.from(_groupMentionAllUnread);

  @visibleForTesting
  Future<void> debugSwitchPeer(ChatContact peer) async {
    await _switchPeer(peer);
  }

  @visibleForTesting
  Future<void> debugHandleChatTileTap(ChatContact peer) async {
    await _handleChatTileTap(peer);
  }

  @visibleForTesting
  Future<void> debugClearChatHistoryForPeer(ChatContact peer) async {
    await _clearChatHistoryForPeer(peer);
  }

  @visibleForTesting
  Future<void> debugDeleteMessageLocal(ChatMessage message) async {
    await _deleteMessageLocal(message);
  }

  @visibleForTesting
  Future<void> debugRunMessageLongPressPopoverActionByIcon(
    ChatMessage message,
    IconData icon,
  ) async {
    final d = _decodeMessage(message);
    final preview = _previewText(message);
    final text = d.text.isNotEmpty ? d.text : preview;
    final isVoice = d.kind == 'voice';
    final isPinned = _isMessagePinned(message);
    final isOwn = _isOwnMessage(message);
    final isRecallEligible = isOwn &&
        message.createdAt != null &&
        DateTime.now().difference(message.createdAt!.toLocal()) <
            _messageRecallWindow;
    final isRecalled = _recalledMessageIds.contains(message.id);
    final action = _buildMessageLongPressPopoverActions(
      message: message,
      decoded: d,
      preview: preview,
      text: text,
      isVoice: isVoice,
      isPinned: isPinned,
      isOwn: isOwn,
      isRecallEligible: isRecallEligible,
      isRecalled: isRecalled,
    ).firstWhere((candidate) => candidate.icon == icon);
    await action.onTap();
  }

  @visibleForTesting
  Future<void> debugShowMessageLongPressPopover(ChatMessage message) async {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final d = _decodeMessage(message);
    final preview = _previewText(message);
    final text = d.text.isNotEmpty ? d.text : preview;
    final isVoice = d.kind == 'voice';
    final isPinned = _isMessagePinned(message);
    final isOwn = _isOwnMessage(message);
    final isRecallEligible = isOwn &&
        message.createdAt != null &&
        DateTime.now().difference(message.createdAt!.toLocal()) <
            _messageRecallWindow;
    final isRecalled = _recalledMessageIds.contains(message.id);
    await _showShamellMessageLongPressMenu(
      bubbleRect: Rect.fromCenter(
        center: overlayBox.size.center(Offset.zero),
        width: 180,
        height: 48,
      ),
      incoming: _isIncoming(message),
      actions: _buildMessageLongPressPopoverActions(
        message: message,
        decoded: d,
        preview: preview,
        text: text,
        isVoice: isVoice,
        isPinned: isPinned,
        isOwn: isOwn,
        isRecallEligible: isRecallEligible,
        isRecalled: isRecalled,
      ),
      onReaction: (emoji) => _setReaction(message, emoji),
    );
  }

  @visibleForTesting
  void debugSeedSelectedMessageIds(Iterable<String> messageIds) {
    _selectedMessageIds
      ..clear()
      ..addAll(messageIds);
  }

  @visibleForTesting
  Future<void> debugDeleteSelectedMessages() async {
    await _deleteSelectedMessages();
  }

  @visibleForTesting
  Future<void> debugPruneExpiredForPeer(String peerId) async {
    await _pruneExpired(peerId);
  }

  @visibleForTesting
  Future<void> debugToggleChatReadUnread(ChatContact peer) async {
    await _toggleChatReadUnread(peer);
  }

  @visibleForTesting
  Future<void> debugDeleteChatById(String id) async {
    await _deleteChatById(id);
  }

  @visibleForTesting
  void debugMergeDirectMessages(List<ChatMessage> messages) {
    _mergeMessages(messages);
  }

  @visibleForTesting
  void debugSeedContacts(Iterable<ChatContact> contacts) {
    _contacts = List<ChatContact>.from(contacts);
    final peer = _peer;
    if (peer != null) {
      final idx = _contacts.indexWhere((contact) => contact.id == peer.id);
      if (idx != -1) {
        _peer = _contacts[idx];
      }
    }
  }

  @visibleForTesting
  bool? debugIsPeerArchived(String peerId) {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return null;
    final idx =
        _contacts.indexWhere((contact) => contact.id == normalizedPeerId);
    if (idx == -1) return null;
    return _contacts[idx].archived;
  }

  @visibleForTesting
  void debugShowChatsList({
    ChatIdentity? me,
    Iterable<ChatContact> contacts = const <ChatContact>[],
    Iterable<ChatGroup> groups = const <ChatGroup>[],
    bool showArchived = false,
    Iterable<String> archivedGroupIds = const <String>[],
    String chatSearch = '',
  }) {
    _applyState(() {
      if (me != null) {
        _me = me;
      }
      _peer = null;
      _activePeerId = null;
      _messages = const <ChatMessage>[];
      _tabIndex = 0;
      _contacts = List<ChatContact>.from(contacts);
      _groups = List<ChatGroup>.from(groups);
      _showArchived = showArchived;
      _archivedGroupIds = Set<String>.from(archivedGroupIds);
      _chatSearch = chatSearch.trim();
      _chatSearchCtrl.value = TextEditingValue(
        text: _chatSearch,
        selection: TextSelection.collapsed(offset: _chatSearch.length),
      );
    });
  }

  @visibleForTesting
  void debugSeedSelectedChatIds(Iterable<String> chatIds) {
    _selectedChatIds
      ..clear()
      ..addAll(chatIds);
  }

  @visibleForTesting
  Future<void> debugMarkSelectedChatsRead() async {
    await _markSelectedChatsRead();
  }

  @visibleForTesting
  Future<void> debugMarkAllChatsRead() async {
    await _markAllChatsRead();
  }

  @visibleForTesting
  Future<void> debugDeleteSelectedChats() async {
    await _deleteSelectedChats();
  }

  @visibleForTesting
  Future<void> debugUnarchiveSelectedChats() async {
    await _unarchiveSelectedChats();
  }

  @visibleForTesting
  Future<void> debugToggleGroupReadUnread(ChatGroup group) async {
    await _toggleGroupReadUnread(group);
  }

  @visibleForTesting
  Future<void> debugClearGroupConversation(ChatGroup group) async {
    await _clearGroupConversation(group);
  }

  @visibleForTesting
  Set<String> debugArchivedGroupsSnapshot() =>
      Set<String>.from(_archivedGroupIds);

  @visibleForTesting
  Future<void> debugSyncPrefsFromServer() async {
    await _syncPrefsFromServer();
  }

  @visibleForTesting
  Future<void> debugSyncGroupPrefsFromServer() async {
    await _syncGroupPrefsFromServer();
  }

  @visibleForTesting
  Future<void> debugRegisterChatDevice() async {
    await _register();
  }

  @visibleForTesting
  Future<void> debugResolvePeerId(String peerId) async {
    await _resolvePeer(presetId: peerId);
  }

  @visibleForTesting
  Future<void> debugMarkVerified() async {
    await _markVerified();
  }

  @visibleForTesting
  Future<void> debugBootstrapCurrentPeerSession() async {
    final peer = _peer;
    if (peer == null) return;
    await _bootstrapPeerSessionIfNeeded(peer);
  }

  @visibleForTesting
  Future<void> debugResetCurrentPeerSession() async {
    await _resetSession();
  }

  @visibleForTesting
  Future<void> debugSetPeerNotificationMode(
    OfficialNotificationMode mode,
  ) async {
    final peer = _peer;
    if (peer == null) return;
    await _setPeerNotificationMode(peer, mode);
  }

  @visibleForTesting
  Future<void> debugOpenChatFromInviteQr(String rawToken) async {
    await _openChatFromInviteQr(rawToken);
  }

  @visibleForTesting
  Future<void> debugSetPeerMuted(bool muted) async {
    final peer = _peer;
    if (peer == null) return;
    await _setChatMuted(peer, muted);
  }

  @visibleForTesting
  Future<void> debugSetPeerPinned(bool pinned) async {
    final peer = _peer;
    if (peer == null) return;
    await _setChatPinned(peer, pinned);
  }

  @visibleForTesting
  Future<void> debugSetPeerHidden(bool hidden) async {
    final peer = _peer;
    if (peer == null) return;
    await _setChatHidden(peer, hidden);
  }

  @visibleForTesting
  Future<void> debugSetPeerBlocked(bool blocked) async {
    final peer = _peer;
    if (peer == null) return;
    await _setChatBlocked(peer, blocked);
  }

  @visibleForTesting
  Future<void> debugTogglePeerArchived() async {
    final peer = _peer;
    if (peer == null) return;
    await _toggleChatArchived(peer);
  }

  @visibleForTesting
  Future<void> debugShowChatMoreSheet(ChatContact peer) async {
    await _showChatMoreSheet(peer);
  }

  @visibleForTesting
  Future<void> debugHandleChatTileLongPress(
    ChatContact peer, {
    Offset? globalPosition,
  }) async {
    await _handleChatTileLongPress(peer, globalPosition: globalPosition);
  }

  @visibleForTesting
  Future<void> debugShowChatLongPressSheet(ChatContact peer) async {
    await _onChatLongPress(peer);
  }

  @visibleForTesting
  Future<void> debugTogglePeerDisappearing() async {
    final peer = _peer;
    if (peer == null) return;
    await _setPeerDisappearSettings(
      peer.copyWith(
        disappearing: !_disappearing,
        disappearAfter: _disappearAfter,
      ),
    );
  }

  @visibleForTesting
  Future<void> debugSetPeerDisappearAfter(Duration disappearAfter) async {
    final peer = _peer;
    if (peer == null) return;
    await _setPeerDisappearSettings(
      peer.copyWith(
        disappearing: _disappearing,
        disappearAfter: disappearAfter,
      ),
    );
  }

  @visibleForTesting
  Future<void> debugSetGroupMuted(ChatGroup group, bool muted) async {
    await _setGroupMuted(group, muted);
  }

  @visibleForTesting
  Future<void> debugSetGroupPinned(ChatGroup group, bool pinned) async {
    await _setGroupPinned(group, pinned);
  }

  @visibleForTesting
  Future<void> debugSetGroupArchived(String groupId, bool archived) async {
    await _setGroupArchivedState(groupId, archived);
  }

  @visibleForTesting
  Future<void> debugToggleGroupArchived(ChatGroup group) async {
    await _toggleGroupArchived(group);
  }

  @visibleForTesting
  Future<void> debugShowGroupMoreSheet(ChatGroup group) async {
    await _showGroupMoreSheet(group);
  }

  @visibleForTesting
  Future<void> debugShowChatsMenu() async {
    await _showChatsMenu();
  }

  @visibleForTesting
  Future<void> debugHandleGroupTileLongPress(
    ChatGroup group, {
    Offset? globalPosition,
  }) async {
    await _handleGroupTileLongPress(group, globalPosition: globalPosition);
  }

  @visibleForTesting
  Future<void> debugShowGroupLongPressSheet(ChatGroup group) async {
    await _onGroupLongPress(group);
  }

  @visibleForTesting
  Future<void> debugCreateStandaloneGroup(String name) async {
    await _createStandaloneGroup(name);
  }

  @visibleForTesting
  Future<void> debugCreatePeerGroup({
    required String name,
    required String peerId,
  }) async {
    await _createGroupWithPeer(name: name, peerId: peerId);
  }

  @visibleForTesting
  void debugPrimeDirectSessionState() {
    final peer = _peer;
    if (peer == null) return;
    _sessionHash ??= _computeSessionHash();
    _ensureRatchet(peer);
  }

  @visibleForTesting
  Future<({bool recovered, bool reauthTriggered})>
      debugRecoverSendAuthState() => _recoverSendAuthState();

  @visibleForTesting
  String? get debugCurrentSessionHash => _sessionHash;

  @visibleForTesting
  bool debugHasRatchetForCurrentPeer() {
    final peerId = _peer?.id;
    if ((peerId ?? '').trim().isEmpty) return false;
    return _ratchets.containsKey(peerId);
  }

  Future<void> _clearVoicePlaybackFile() async {
    final path = _voicePlaybackPath;
    _voicePlaybackPath = null;
    await deleteEphemeralVoiceFile(path);
  }

  Future<void> _clearVoiceRecordingFile() async {
    final path = _voiceRecordingPath;
    _voiceRecordingPath = null;
    await deleteEphemeralVoiceFile(path);
  }

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

  Uint8List? _decodeIdentityPrivateKey(ChatIdentity? me) {
    final raw = (me?.privateKeyB64 ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = base64Decode(raw);
      if (!_isCurveKey(decoded)) return null;
      return Uint8List.fromList(decoded);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeInlineImageBytes(String? raw) {
    return _inlineImageBytesCache.decode(raw);
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

  bool _isRatchetBoundToPeer(RatchetState st, ChatContact peer) {
    final storedPeerIdentity = st.peerIdentity.trim();
    final currentPeerFingerprint = peer.fingerprint.trim();
    if (storedPeerIdentity.isEmpty || currentPeerFingerprint.isEmpty) {
      return false;
    }
    return storedPeerIdentity == currentPeerFingerprint;
  }

  Future<void> _loadBootstrapSideMetadata() async {
    final override = widget.loadBootstrapSideMetadataOverride;
    if (override != null) {
      await override();
      return;
    }
    try {
      final annotations =
          await loadFriendAnnotations(baseUrlOverride: widget.baseUrl);
      var pinnedMessages = await _store.loadPinnedMessages(
        baseUrlOverride: widget.baseUrl,
      );
      final recalledMessageIds = await _store.loadRecalledMessageIds(
        baseUrlOverride: widget.baseUrl,
      );
      final pinnedChatOrder = await _store.loadPinnedChatOrder(
        baseUrlOverride: widget.baseUrl,
      );
      final archivedGroupIds = await _store.loadArchivedGroups(
        baseUrlOverride: widget.baseUrl,
      );
      final me = _me;
      if (me != null) {
        try {
          final remotePinned =
              await _service.fetchPinnedMessages(deviceId: me.id);
          if (remotePinned.isNotEmpty) {
            final merged = <String, Set<String>>{
              for (final entry in pinnedMessages.entries)
                entry.key: Set<String>.from(entry.value),
            };
            for (final entry in remotePinned.entries) {
              merged
                  .putIfAbsent(entry.key, () => <String>{})
                  .addAll(entry.value);
            }
            pinnedMessages = merged;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _friendAliases = annotations.aliases;
        _friendTags = annotations.tags;
        _closeFriendIds
          ..clear()
          ..addAll(annotations.closeFriendIds);
        _pinnedMessageIdsByPeer = pinnedMessages;
        _recalledMessageIds
          ..clear()
          ..addAll(recalledMessageIds);
        _recalledMessageIdsRevision++;
        _clearThreadMessageSearchIndex();
        _pinnedChatOrder = pinnedChatOrder;
        _archivedGroupIds = archivedGroupIds;
      });
      await _normalizePinnedChatOrder();
    } catch (_) {}
  }

  Future<({bool aborted, ShamellCapabilities caps, ChatIdentity? me})>
      _restoreBootstrapState() async {
    final me = await _store.loadIdentity(baseUrlOverride: widget.baseUrl);
    final peer = await _store.loadPeer(baseUrlOverride: widget.baseUrl);
    final contacts = await _loadScopedContacts();
    final unread = await _store.loadUnread(baseUrlOverride: widget.baseUrl);
    final drafts = await _store.loadDrafts(baseUrlOverride: widget.baseUrl);
    final active = await _store.loadActivePeer(baseUrlOverride: widget.baseUrl);
    final notifyPreview = await _store.loadNotifyPreview(
      baseUrlOverride: widget.baseUrl,
    );
    var calls = await _callStore.load(baseUrlOverride: widget.baseUrl);
    if (me != null) {
      try {
        final remoteCalls = await _service.fetchCallLogs(deviceId: me.id);
        if (remoteCalls.isNotEmpty) {
          final byKey = <String, ChatCallLogEntry>{
            for (final entry in [...remoteCalls, ...calls])
              '${entry.peerId}:${entry.id}': entry,
          };
          calls = byKey.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
          if (calls.length > 100) {
            calls = calls.sublist(0, 100);
          }
          await _callStore.save(calls, baseUrlOverride: widget.baseUrl);
        }
      } catch (_) {}
    }
    final sessionKeys = await _store.loadSessionKeys(
      baseUrlOverride: widget.baseUrl,
    );
    final chainStates = await _store.loadChains(
      baseUrlOverride: widget.baseUrl,
    );
    ShamellCapabilities caps = ShamellCapabilities.conservativeDefaults;
    String shamellUserId = await _loadStoredShamellUserIdBestEffort();
    try {
      final sp = await SharedPreferences.getInstance();
      caps = await ShamellCapabilities.loadForBaseUrl(
        widget.baseUrl,
        sp: sp,
      );
    } catch (_) {}
    final mergedContacts = List<ChatContact>.from(contacts);
    if (peer != null && mergedContacts.where((c) => c.id == peer.id).isEmpty) {
      mergedContacts.add(peer);
    }
    // load ratchets after we know which peers we have locally
    for (final c in mergedContacts) {
      final raw = await _store.loadRatchet(
        c.id,
        baseUrlOverride: widget.baseUrl,
      );
      final st = raw.isNotEmpty
          ? RatchetState.fromJson(raw as Map<String, Object?>)
          : null;
      if (st != null &&
          _isValidRatchetState(st) &&
          _isRatchetBoundToPeer(st, c)) {
        _ratchets[c.id] = st;
      } else if (raw.isNotEmpty) {
        await _store.deleteRatchet(c.id, baseUrlOverride: widget.baseUrl);
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
    var cachedMsgs = activePeer != null
        ? await _store.loadMessages(
            activePeer.id,
            baseUrlOverride: widget.baseUrl,
          )
        : <ChatMessage>[];
    if (me != null && activePeer != null) {
      try {
        cachedMsgs = await _seedThreadHistoryIfEmpty(
          me: me,
          peer: activePeer,
          cached: cachedMsgs,
        );
      } catch (e) {
        if (await _forceReauthOnCriticalChatFailure(e)) {
          return (
            aborted: true,
            caps: caps,
            me: me,
          );
        }
      }
    }

    Set<String> voicePlayed = <String>{};
    if (activePeer != null) {
      try {
        voicePlayed = await _store.loadVoicePlayed(
          activePeer.id,
          baseUrlOverride: widget.baseUrl,
        );
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
      _archivedGroupIds = <String>{};
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
    _startBootstrapSideMetadataLoad();
    return (
      aborted: false,
      caps: caps,
      me: me,
    );
  }

  Future<void> _bootstrap() async {
    final restored = await _restoreBootstrapState();
    if (restored.aborted) return;
    final caps = restored.caps;
    var me = restored.me;
    // If a peer hint was provided (e.g. from Friends), try to resolve it.
    final hintedPeer = widget.initialPeerId;
    Future<void>? bootstrapInitialPeerResolve;
    if (hintedPeer != null && hintedPeer.trim().isNotEmpty) {
      bootstrapInitialPeerResolve =
          _loadBootstrapInitialPeerResolve(hintedPeer.trim());
    }
    if (me != null) {
      try {
        await _service.ensureAccountChatReady();
        final refreshed =
            await _store.loadIdentity(baseUrlOverride: widget.baseUrl) ??
                await _store.loadIdentity();
        if (refreshed != null) {
          final identityChanged = me.id.trim() != refreshed.id.trim() ||
              me.fingerprint.trim() != refreshed.fingerprint.trim();
          me = refreshed;
          if (mounted) {
            _applyState(() {
              _me = refreshed;
              _displayNameCtrl.text = refreshed.displayName ?? '';
            });
          } else {
            _me = refreshed;
          }
          if (identityChanged) {
            await _clearDirectSessionStateAfterLocalIdentityChange();
          }
        }
      } catch (e) {
        if (await _forceReauthOnCriticalChatFailure(e)) return;
        rethrow;
      }
      await _refreshChatSessionAfterIdentityReady(listenPush: true);
    }
    if (bootstrapInitialPeerResolve != null) {
      await bootstrapInitialPeerResolve;
    }
    await _maybeRunDebugAutoSend();
    await _loadBootstrapDeferredSideState(
      caps: caps,
      hasIdentity: me != null,
    );
  }

  Future<void> _maybeRunDebugAutoSend() async {
    if (_debugAutoSendTriggered || kReleaseMode) {
      return;
    }
    final autoSendText = (widget.debugAutoSendText ?? '').trim();
    if (autoSendText.isEmpty || _me == null || _peer == null) {
      return;
    }
    _debugAutoSendTriggered = true;
    _msgCtrl.text = autoSendText;
    await _send();
  }

  void _startBootstrapSideMetadataLoad() {
    unawaited(_loadBootstrapSideMetadata());
    // After the contacts list lands, walk it once in the background and
    // refresh any contact whose display name is missing / equals the raw
    // device id. That happens for peers we picked up via lightweight
    // surfaces (group invites, payment receipts) where only the deviceId
    // got cached — without this pass the chat list would show a long
    // hex string instead of the user's registered name.
    unawaited(_refreshMissingContactDisplayNames());
  }

  Future<void> _refreshMissingContactDisplayNames() async {
    if (!mounted) return;
    final snapshot = List<ChatContact>.from(_contacts);
    if (snapshot.isEmpty) return;
    // Collect candidates: contacts whose visible label would currently
    // fall through to `c.id` because `name` is null/blank or equals the
    // device id verbatim. Cap at 32 per pass to stay polite on the BFF
    // rate-limit budget — anything further is refreshed next time the
    // page mounts.
    final candidates = <ChatContact>[];
    for (final c in snapshot) {
      final n = (c.name ?? '').trim();
      if (n.isEmpty || n == c.id) {
        candidates.add(c);
        if (candidates.length >= 32) break;
      }
    }
    if (candidates.isEmpty) return;
    final refreshed = <ChatContact>[];
    for (final c in candidates) {
      if (!mounted) return;
      try {
        final fresh = await _service.resolveDevice(c.id);
        final freshName = (fresh.name ?? '').trim();
        if (freshName.isEmpty || freshName == c.id) continue;
        // `ChatContact.copyWith` doesn't expose `name` (it's immutable
        // identity material in the copyWith surface), so rebuild the
        // record explicitly, preserving every per-contact preference
        // (verified, starred, archive, mute, …) while swapping in the
        // refreshed display name.
        refreshed.add(
          ChatContact(
            id: c.id,
            publicKeyB64: c.publicKeyB64,
            fingerprint: c.fingerprint,
            name: freshName,
            verified: c.verified,
            verifiedAt: c.verifiedAt,
            starred: c.starred,
            pinned: c.pinned,
            disappearing: c.disappearing,
            disappearAfter: c.disappearAfter,
            archived: c.archived,
            hidden: c.hidden,
            blocked: c.blocked,
            blockedAt: c.blockedAt,
            muted: c.muted,
          ),
        );
      } catch (_) {
        // Soft-fail per contact — a single network blip or 404 doesn't
        // block refreshing the others.
      }
    }
    if (refreshed.isEmpty || !mounted) return;
    // Persist the fresher names + replay them into in-memory state so the
    // chat list rebuilds with the human-readable labels immediately.
    try {
      await _saveScopedContactsForPeers(refreshed);
    } catch (_) {}
    if (!mounted) return;
    _applyState(() {
      final byId = {for (final c in refreshed) c.id: c};
      _contacts = [
        for (final c in _contacts) byId[c.id] ?? c,
      ];
      final activePeer = _peer;
      if (activePeer != null && byId.containsKey(activePeer.id)) {
        _peer = byId[activePeer.id];
      }
    });
  }

  Future<void> _loadBootstrapInitialPeerResolve(String peerId) async {
    final override = widget.loadBootstrapInitialPeerResolveOverride;
    if (override != null) {
      await override(peerId);
      return;
    }
    await _resolvePeer(presetId: peerId);
  }

  Future<void> _loadBootstrapOfficialForCurrentPeer(ChatContact peer) async {
    final override = widget.loadBootstrapOfficialForCurrentPeerOverride;
    if (override != null) {
      await override(peer);
      return;
    }
    await _loadOfficialForPeer(peer);
  }

  Future<void> _loadBootstrapOfficialNotificationModes() async {
    final override = widget.loadBootstrapOfficialNotificationModesOverride;
    if (override != null) {
      await override();
      return;
    }
    await _syncOfficialNotificationModesFromServer();
  }

  Future<void> _loadBootstrapDirectPrefsSync() async {
    final override = widget.loadBootstrapDirectPrefsSyncOverride;
    if (override != null) {
      await override();
      return;
    }
    await _syncPrefsFromServer();
  }

  Future<void> _loadBootstrapGroupPrefsSync() async {
    final override = widget.loadBootstrapGroupPrefsSyncOverride;
    if (override != null) {
      await override();
      return;
    }
    await _syncGroupPrefsFromServer();
  }

  Future<void> _loadBootstrapDevicesSummary() async {
    final override = widget.loadBootstrapDevicesSummaryOverride;
    if (override != null) {
      await override();
      return;
    }
    await _loadDevicesSummary();
  }

  Future<void> _loadBootstrapDeferredSideState({
    required ShamellCapabilities caps,
    required bool hasIdentity,
  }) async {
    final tasks = <Future<void>>[
      // Restore cached Chats system-thread state before bootstrap returns.
      _loadBootstrapSystemThreadsSideState(),
      // Load multi-device banner state before bootstrap returns.
      _loadBootstrapDevicesSummary(),
    ];
    if (hasIdentity) {
      tasks.add(_loadBootstrapDirectPrefsSync());
      tasks.add(_loadBootstrapGroupPrefsSync());
    }
    if (caps.officialAccounts) {
      final currentPeer = _peer;
      tasks.add(() async {
        final currentPeerLoad = currentPeer == null
            ? null
            : _loadBootstrapOfficialForCurrentPeer(currentPeer);
        await _loadOfficialPeers();
        if (currentPeerLoad != null) {
          await Future.wait<void>(<Future<void>>[
            currentPeerLoad,
            _loadBootstrapOfficialNotificationModes(),
          ]);
          return;
        }
        await _loadBootstrapOfficialNotificationModes();
      }());
    }
    await Future.wait<void>(tasks);
  }

  Future<void> _loadDevicesSummary() async {
    try {
      final currentDeviceId = await CallSignalingClient.loadDeviceId(
        baseUrlOverride: widget.baseUrl,
      );
      if (currentDeviceId == null || currentDeviceId.isEmpty) {
        return;
      }
      final headers = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
      final uri = _chatApiUri(
        pathSegments: const <String>['auth', 'devices'],
        queryParameters: const <String, String>{
          'limit': '2',
        },
      );
      if (uri == null) {
        return;
      }
      final httpClient = widget.accountHttpClient ?? shamellHttpClient();
      final closeClient = widget.accountHttpClient == null;
      final resp = await httpClient
          .get(uri, headers: headers)
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (closeClient) {
        httpClient.close();
      }
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
        final type =
            sanitizeDeviceLoginLabel((d['device_type'] ?? '').toString());
        final platform =
            sanitizeDeviceLoginLabel((d['platform'] ?? '').toString());
        if (type != null && type.isNotEmpty) {
          label = type;
        } else if (platform != null && platform.isNotEmpty) {
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

  Future<void> _restoreServiceNotificationsBadgeFromStore() async {
    if (!_caps.serviceNotifications) return;
    bool cached = false;
    try {
      cached = await _store.loadServiceNotificationsHasUnread(
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
    if (mounted && cached != _hasUnreadServiceNotifications) {
      setState(() {
        _hasUnreadServiceNotifications = cached;
      });
    }
  }

  Future<void> _refreshServiceNotificationsBadgeFromServer() async {
    if (!_caps.serviceNotifications) return;

    try {
      final uri = _chatApiUri(
        pathSegments: const <String>['me', 'official_template_messages'],
        queryParameters: const <String, String>{
          'unread_only': 'true',
          'limit': '1',
        },
      );
      if (uri == null) {
        return;
      }
      final httpClient = widget.accountHttpClient ?? shamellHttpClient();
      final closeClient = widget.accountHttpClient == null;
      final r = await httpClient
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (closeClient) {
        httpClient.close();
      }
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
        await _saveServiceNotificationsHasUnread(hasUnread);
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _loadServiceNotificationsBadge() async {
    await _restoreServiceNotificationsBadgeFromStore();
    await _refreshServiceNotificationsBadgeFromServer();
  }

  Future<void> _loadBootstrapSystemThreadsSideState() async {
    final override = widget.loadBootstrapSystemThreadsSideStateOverride;
    if (override != null) {
      await override();
      return;
    }
    if (_caps.serviceNotifications) {
      await _restoreServiceNotificationsBadgeFromStore();
    }
    await _loadChatsTabSystemThreadsPrefs();
    if (_caps.serviceNotifications) {
      _startBootstrapServiceNotificationsBadgeRefresh();
    }
  }

  void _startBootstrapServiceNotificationsBadgeRefresh() {
    if (!_caps.serviceNotifications) return;
    final override = widget.refreshBootstrapServiceNotificationsBadgeOverride;
    if (override != null) {
      unawaited(override());
      return;
    }
    unawaited(_refreshServiceNotificationsBadgeFromServer());
  }

  Future<void> _loadChatsTabSystemThreadsPrefs() async {
    try {
      final hideService = await _store.loadHideServiceNotificationsThread(
        baseUrlOverride: widget.baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _hideServiceNotificationsThread = hideService;
      });
    } catch (_) {}
  }

  Future<void> _setHideServiceNotificationsThread(bool hide) async {
    _applyState(() {
      _hideServiceNotificationsThread = hide;
    });
    try {
      await _saveHideServiceNotificationsThread(hide);
    } catch (_) {}
  }

  Future<void> _toggleServiceNotificationsReadUnread() async {
    final next = !_hasUnreadServiceNotifications;
    _applyState(() {
      _hasUnreadServiceNotifications = next;
    });
    try {
      await _saveServiceNotificationsHasUnread(next);
    } catch (_) {}
  }

  Future<void> _deleteServiceNotificationsThread() async {
    await _setHideServiceNotificationsThread(true);
    _applyState(() {
      _hasUnreadServiceNotifications = false;
    });
    try {
      await _saveServiceNotificationsHasUnread(false);
    } catch (_) {}
  }

  Future<Map<String, String>> _officialHeaders({bool jsonBody = false}) async {
    return shamellSessionHeadersForBaseUrl(
      widget.baseUrl,
      json: jsonBody,
    );
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
      _openOfficialAccountsDirectory();
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

  Future<void> _openServiceNotificationsThread() async {
    final override = widget.onServiceNotificationsThreadTapOverride;
    if (override != null) {
      await override();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfficialTemplateMessagesPage(
          baseUrl: widget.baseUrl,
        ),
      ),
    );
    if (!mounted) return;
    await _loadServiceNotificationsBadge();
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
      if (official == null) return;
      _openMomentsSurface();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'حدث خطأ أثناء فتح قسم التحديثات.'
                : 'Error while opening updates.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleOfficialFollowFromChat() async {
    if (!await _ensureOfficialAuthSession()) return;
    final official = _linkedOfficial;
    if (official == null) return;
    final id = official.id;
    if (id.isEmpty) return;
    final currentlyFollowed = _linkedOfficialFollowed;
    final endpoint = currentlyFollowed ? 'unfollow' : 'follow';
    final followAction = currentlyFollowed
        ? AnalyticsFollowAction.unfollow
        : AnalyticsFollowAction.follow;
    final kindStr = (official.kind).toLowerCase();
    final isServiceKind = kindStr == 'service';
    final analyticsGroup = isServiceKind
        ? AnalyticsOfficialGroup.service
        : AnalyticsOfficialGroup.nonservice;
    final httpClient = widget.officialHttpClient ?? shamellHttpClient();
    final closeClient = widget.officialHttpClient == null;
    try {
      final uri = _chatApiUri(
        pathSegments: <String>['official_accounts', id, endpoint],
      );
      if (uri == null) {
        _showInvalidServerUrlSnackBar();
        return;
      }
      final reqHeaders = await _officialHeaders(jsonBody: true);
      final idempotencyScope = '$id|$endpoint';
      final idempotencyKey = _pendingOfficialFollowIdempotencyKeys.putIfAbsent(
        idempotencyScope,
        () => _newOfficialMutationIdempotencyKey('official-$endpoint'),
      );
      reqHeaders['Idempotency-Key'] = idempotencyKey;
      final r = await httpClient
          .post(uri, headers: reqHeaders)
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300 && mounted) {
        _pendingOfficialFollowIdempotencyKeys.remove(idempotencyScope);
        final nowFollowed = !currentlyFollowed;
        if (!nowFollowed) {
          await _resetOfficialLocalStateAfterUnfollow(official);
        }
        setState(() {
          _linkedOfficialFollowed = nowFollowed;
        });
        Perf.action(currentlyFollowed
            ? 'official_unfollow_from_chat'
            : 'official_follow_from_chat');
        for (final event in followKindEvents(
          group: analyticsGroup,
          action: followAction,
        )) {
          Perf.action(event);
        }
        if (nowFollowed) {
          // After first follow, try to surface the configured
          // welcome auto‑reply for this Official, similar to
          // SyrChat Official accounts.
          _startOfficialWelcomeInjection(official);
        }
      } else if (await _forceReauthOnCriticalOfficialHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        return;
      }
    } catch (e) {
      if (await _forceReauthOnCriticalOfficialError(e)) return;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _resetOfficialLocalStateAfterUnfollow(
    OfficialAccountHandle official,
  ) async {
    final officialId = official.id.trim();
    final peerId = (official.chatPeerId ?? '').trim();
    if (officialId.isNotEmpty) {
      await _store.clearOfficialAutofollowed(
        officialId,
        baseUrlOverride: widget.baseUrl,
      );
    }
    if (peerId.isEmpty) return;
    await _store.clearOfficialAutochat(
      peerId,
      baseUrlOverride: widget.baseUrl,
    );
    await _store.clearOfficialAutoreplyShown(
      peerId,
      baseUrlOverride: widget.baseUrl,
    );
    await _store.setOfficialNotifMode(
      peerId,
      OfficialNotificationMode.full,
      baseUrlOverride: widget.baseUrl,
    );

    final contacts = await _loadScopedContacts();
    final idx = contacts.indexWhere((c) => c.id == peerId);
    ChatContact? updatedPeer;
    List<ChatContact>? updatedContacts;
    if (idx != -1) {
      final current = contacts[idx];
      if (current.muted) {
        updatedPeer = current.copyWith(muted: false);
        updatedContacts = List<ChatContact>.from(contacts);
        updatedContacts[idx] = updatedPeer;
        await _saveScopedContactsForPeers(<ChatContact>[updatedPeer]);
      }
    }

    if (!mounted) return;
    _applyState(() {
      _officialPeerUnreadFeeds.remove(peerId);
      if (updatedContacts != null) {
        _contacts = updatedContacts!;
        if (_peer?.id == peerId && updatedPeer != null) {
          _peer = updatedPeer;
        }
      }
    });
  }

  Future<String> _loadStoredShamellUserIdBestEffort() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return await loadShamellUserId(
            sp: sp,
            baseUrlOverride: widget.baseUrl,
          ) ??
          '';
    } catch (_) {
      return '';
    }
  }

  Future<OfficialAccountHandle?> _loadOfficialForPeer(ChatContact peer,
      {bool updateState = true}) async {
    final id = peer.id.trim();
    if (id.isEmpty) return null;
    final loadSerial = updateState ? ++_activeOfficialPeerLoadSerial : 0;
    if (_linkedOfficialPeerId == id && _linkedOfficial != null) {
      return _linkedOfficial;
    }
    final httpClient = widget.officialHttpClient ?? shamellHttpClient();
    final closeClient = widget.officialHttpClient == null;
    try {
      final uri = _chatApiUri(
        pathSegments: const <String>['official_accounts'],
        queryParameters: <String, String>{
          'followed_only': 'false',
          'chat_peer_id': id,
        },
      );
      if (uri == null) {
        return null;
      }
      final r = await httpClient
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (await _forceReauthOnCriticalOfficialHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          return null;
        }
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
      final shouldApplyToActivePeer = updateState &&
          mounted &&
          _activeOfficialPeerLoadSerial == loadSerial &&
          (_peer?.id.trim() ?? '') == id;
      if (shouldApplyToActivePeer) {
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
      final shouldInjectWelcome = found != null &&
          ((updateState && shouldApplyToActivePeer) ||
              (!updateState && (_peer?.id.trim() ?? '') == id));
      if (shouldInjectWelcome) {
        // Try to surface a SyrChat‑style welcome message in the
        // current thread when chatting with an Official account.
        _startOfficialWelcomeInjection(found);
      }
      return found;
    } catch (e) {
      if (await _forceReauthOnCriticalOfficialError(e)) {
        return null;
      }
      return null;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadOfficialAutoReplies(
      String accountId) async {
    if (accountId.isEmpty) return const <Map<String, dynamic>>[];
    final cached = _officialAutoRepliesByAccount[accountId];
    if (cached != null) return cached;
    final uri = _chatApiUri(
      pathSegments: <String>['official_accounts', accountId, 'auto_replies'],
    );
    if (uri == null) {
      _officialAutoRepliesByAccount[accountId] = const <Map<String, dynamic>>[];
      return const <Map<String, dynamic>>[];
    }
    final httpClient = widget.officialHttpClient ?? shamellHttpClient();
    final closeClient = widget.officialHttpClient == null;
    try {
      final r = await httpClient
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        _officialAutoRepliesByAccount[accountId] =
            const <Map<String, dynamic>>[];
        return const <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) {
        _officialAutoRepliesByAccount[accountId] =
            const <Map<String, dynamic>>[];
        return const <Map<String, dynamic>>[];
      }
      final minimalText = (decoded['text'] ?? '').toString().trim();
      if (minimalText.isNotEmpty) {
        final single = <Map<String, dynamic>>[
          <String, dynamic>{'text': minimalText},
        ];
        _officialAutoRepliesByAccount[accountId] = single;
        return single;
      }
      if (decoded['rules'] is! List) {
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
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  void _startOfficialWelcomeInjection(OfficialAccountHandle account) {
    final override = widget.startOfficialWelcomeInjectionOverride;
    if (override != null) {
      unawaited(override(account));
      return;
    }
    unawaited(_maybeInjectOfficialWelcome(account));
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
      final alreadyShown = await _store.hasOfficialAutoreplyShown(
        peerId,
        baseUrlOverride: widget.baseUrl,
      );
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
      await _store.saveMessages(
        peerId,
        _cache[peerId] ?? const [],
        baseUrlOverride: widget.baseUrl,
      );
      await _store.markOfficialAutoreplyShown(
        peerId,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {
      // Best‑effort: auto‑reply is optional sugar.
    }
  }

  Future<void> _loadOfficialPeers() async {
    if (!_caps.officialAccounts) return;
    final httpClient = widget.officialHttpClient ?? shamellHttpClient();
    final closeClient = widget.officialHttpClient == null;
    try {
      final ids = <String>{};
      final unread = <String>{};
      final featured = <String>{};
      final peerToAccount = <String, String>{};
      Map<String, String> seenMap = const <String, String>{};
      try {
        seenMap = await loadOfficialFeedSeenMap(
          baseUrlOverride: widget.baseUrl,
        );
      } catch (_) {}
      String? beforeName;
      String? beforeId;
      bool? beforeFeatured;
      String? lastCursorKey;
      while (true) {
        final queryParameters = <String, String>{
          'followed_only': 'false',
          'has_chat_peer': 'true',
          'limit': '$_officialAccountsPageSize',
        };
        if (beforeName != null && beforeId != null && beforeFeatured != null) {
          queryParameters['before_featured'] = '$beforeFeatured';
          queryParameters['before_name'] = beforeName;
          queryParameters['before_id'] = beforeId;
        }
        final uri = _chatApiUri(
          pathSegments: const <String>['official_accounts'],
          queryParameters: queryParameters,
        );
        if (uri == null) {
          return;
        }
        final r = await httpClient
            .get(uri, headers: await _officialHeaders())
            .timeout(_ShamellChatPageState._chatRequestTimeout);
        if (r.statusCode < 200 || r.statusCode >= 300) {
          if (await _forceReauthOnCriticalOfficialHttpFailure(
            statusCode: r.statusCode,
            rawBody: r.body,
          )) {
            return;
          }
          return;
        }
        final decoded = jsonDecode(r.body);
        List<dynamic> raw = const [];
        if (decoded is Map && decoded['accounts'] is List) {
          raw = decoded['accounts'] as List;
        } else if (decoded is List) {
          raw = decoded;
        }
        Map<String, dynamic>? lastAccount;
        for (final e in raw) {
          if (e is! Map) continue;
          final m = e.cast<String, dynamic>();
          lastAccount = m;
          final peerId = (m['chat_peer_id'] ?? '').toString().trim();
          if (peerId.isNotEmpty) {
            ids.add(peerId);
          }
          final accId = (m['id'] ?? '').toString();
          final isFeatured = (m['featured'] as bool?) ?? false;
          final isFollowed = (m['followed'] as bool?) ?? false;
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
          if (isFollowed &&
              accId.isNotEmpty &&
              lastTs != null &&
              lastTs.isNotEmpty) {
            final seenRaw = (seenMap[accId] ?? '').toString();
            if (seenRaw.isEmpty) {
              if (peerId.isNotEmpty) {
                unread.add(peerId);
              }
            } else {
              try {
                final last = DateTime.parse(lastTs);
                final seen = DateTime.parse(seenRaw);
                if (last.isAfter(seen)) {
                  if (peerId.isNotEmpty) {
                    unread.add(peerId);
                  }
                }
              } catch (_) {}
            }
          }
        }
        if (raw.length < _officialAccountsPageSize || lastAccount == null) {
          break;
        }
        final nextBeforeName = (lastAccount['name'] ?? '').toString();
        final nextBeforeId = (lastAccount['id'] ?? '').toString().trim();
        if (nextBeforeName.isEmpty || nextBeforeId.isEmpty) {
          break;
        }
        final nextBeforeFeatured = (lastAccount['featured'] as bool?) ?? false;
        final nextCursorKey =
            '$nextBeforeFeatured|$nextBeforeName|$nextBeforeId';
        if (nextCursorKey == lastCursorKey) {
          break;
        }
        lastCursorKey = nextCursorKey;
        beforeFeatured = nextBeforeFeatured;
        beforeName = nextBeforeName;
        beforeId = nextBeforeId;
      }
      if (!mounted) return;
      setState(() {
        _officialPeerIds
          ..clear()
          ..addAll(ids);
        _officialPeerUnreadFeeds
          ..clear()
          ..addAll(unread);
        _featuredOfficialPeerIds
          ..clear()
          ..addAll(featured);
        _officialPeerToAccountId
          ..clear()
          ..addAll(peerToAccount);
      });
    } catch (e) {
      if (await _forceReauthOnCriticalOfficialError(e)) return;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _syncOfficialNotificationModesFromServer() async {
    final httpClient = widget.officialHttpClient ?? shamellHttpClient();
    final closeClient = widget.officialHttpClient == null;
    try {
      if (_officialPeerToAccountId.isEmpty) {
        return;
      }
      final officialIds =
          _officialNotificationIdsQueryValue(_officialPeerToAccountId.values);
      if (officialIds.isEmpty) {
        return;
      }
      final uri = _chatApiUri(
        pathSegments: const <String>['official_accounts', 'notifications'],
        queryParameters: <String, String>{
          'official_ids': officialIds,
        },
      );
      if (uri == null) {
        return;
      }
      final r = await httpClient
          .get(uri, headers: await _officialHeaders())
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (await _forceReauthOnCriticalOfficialHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          return;
        }
        return;
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map || decoded['modes'] is! Map) {
        return;
      }
      final rawModes = decoded['modes'] as Map;
      final store = _store;
      final contacts = await store.loadContacts(
        baseUrlOverride: widget.baseUrl,
      );
      final updatedContacts = List<ChatContact>.from(contacts);
      var changedContacts = false;
      for (final peerEntry in _officialPeerToAccountId.entries) {
        final peerId = peerEntry.key;
        final accId = peerEntry.value;
        final modeStr = (rawModes[accId] ?? 'full').toString().toLowerCase();
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
        await store.setOfficialNotifMode(
          peerId,
          mode,
          baseUrlOverride: widget.baseUrl,
        );
        for (var i = 0; i < updatedContacts.length; i++) {
          final c = updatedContacts[i];
          if (c.id == peerId) {
            final shouldMute = mode == OfficialNotificationMode.muted;
            if (c.muted != shouldMute) {
              updatedContacts[i] = c.copyWith(muted: shouldMute);
              changedContacts = true;
            }
            break;
          }
        }
      }
      if (changedContacts) {
        await store.saveContacts(
          updatedContacts,
          baseUrlOverride: widget.baseUrl,
        );
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
    } catch (e) {
      if (await _forceReauthOnCriticalOfficialError(e)) return;
    } finally {
      if (closeClient) {
        httpClient.close();
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
    await _store.saveIdentity(me, baseUrlOverride: widget.baseUrl);
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
      await _refreshChatSessionAfterIdentityReady();
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      setState(() => _error = _sendFailureToUi(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshChatSessionAfterIdentityReady({
    bool listenPush = false,
  }) async {
    await _ensurePushToken();
    // Restore persisted-outbox stubs as failed bubbles BEFORE the
    // first inbox pull. That way the UI doesn't briefly render an
    // empty thread before the queued sends pop in. Cheap (one
    // SharedPreferences read + a setState), idempotent across reauth.
    unawaited(_hydrateOutboxIfNeeded());
    // `_pullInbox()` already cascades into `_syncGroups()`, so keep the
    // post-registration refresh path single-sourced here.
    await _pullInbox();
    _listenWs();
    if (listenPush) {
      _listenPush();
    }
  }

  Future<void> _resolvePeer({
    String? presetId,
    bool silentInboxRefresh = false,
  }) async {
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
      ChatContact peer;
      try {
        peer = await _service.resolveDevice(id);
      } catch (e) {
        if (!_isFailClosedPeerResolveLookup(e)) rethrow;
        peer = await _loadExistingPeerContact(id) ?? (throw e);
      }
      final verified = await _store.isVerified(
        peer.id,
        peer.fingerprint,
        baseUrlOverride: widget.baseUrl,
      );
      final c = peer.copyWith(verified: verified);
      await _store.savePeer(c, baseUrlOverride: widget.baseUrl);
      final updatedContacts = _upsertContact(c);
      await _saveScopedContactsForPeers(<ChatContact>[c]);
      await _store.setActivePeer(c.id, baseUrlOverride: widget.baseUrl);
      var cached = await _store.loadMessages(
        c.id,
        baseUrlOverride: widget.baseUrl,
      );
      if (_me != null) {
        cached = await _seedThreadHistoryIfEmpty(
          me: _me!,
          peer: c,
          cached: cached,
        );
      }
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
        _loadingOlderThreadMessages = false;
        _hasOlderThreadMessages = _shouldExposeOlderThreadHistory(c.id, cached);
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
      final scheduledInitialJump = _maybeScheduleInitialThreadMessageJump();
      if (!scheduledInitialJump && jumpToUnread) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(
              _scrollToMessage(anchorId!, alignment: 0.18, highlight: false));
        });
      } else if (!scheduledInitialJump) {
        _scheduleThreadScrollToBottom(force: true, animated: false);
      }
      await _saveUnreadCountForPeer(c.id, 0);
      await _pullInbox(silent: silentInboxRefresh);
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      setState(() => _error = _sendFailureToUi(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isFailClosedPeerResolveLookup(Object error) {
    if (error is ChatHttpException) {
      if (error.statusCode == 404) {
        return true;
      }
      final detail = (error.body ?? '').toLowerCase();
      return detail.contains('not found') ||
          detail.contains('bundle unavailable');
    }
    final text = error.toString().trim().toLowerCase();
    return text.contains('failed: 404') ||
        text.contains('not found') ||
        text.contains('bundle unavailable');
  }

  Future<ChatContact?> _loadExistingPeerContact(String peerId) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return null;
    final contacts = await _loadScopedContacts();
    for (final contact in contacts) {
      if (contact.id == normalizedPeerId) {
        return contact;
      }
    }
    for (final contact in _contacts) {
      if (contact.id == normalizedPeerId) {
        return contact;
      }
    }
    return null;
  }

  Future<void> _markVerified() async {
    final p = _peer;
    if (p == null) return;
    final verifiedAt = DateTime.now().toUtc();
    await _store.markVerified(
      p.id,
      p.fingerprint,
      baseUrlOverride: widget.baseUrl,
    );
    final updated = p.copyWith(
      verified: true,
      verifiedAt: verifiedAt,
    );
    final contacts = _upsertContact(updated);
    await _saveScopedContactsForPeers(<ChatContact>[updated]);
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
            ? 'لا يمكن الإرسال بعد. اطلب رمز دعوة (QR) من الطرف الآخر.'
            : 'Cannot send yet. Ask the other party for an invite QR.';
      }
    }
    if (error is ChatHttpException) {
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

  Future<void> _clearDirectSessionStateAfterLocalIdentityChange() async {
    final peerIds = <String>{
      if ((_peer?.id ?? '').trim().isNotEmpty) _peer!.id.trim(),
      ..._contacts.map((c) => c.id.trim()).where((id) => id.isNotEmpty),
      ..._cache.keys.map((id) => id.trim()).where((id) => id.isNotEmpty),
      ..._sessionKeys.keys.map((id) => id.trim()).where((id) => id.isNotEmpty),
      ..._chains.keys.map((id) => id.trim()).where((id) => id.isNotEmpty),
      ..._ratchets.keys.map((id) => id.trim()).where((id) => id.isNotEmpty),
    };

    _ratchets.clear();
    _chains.clear();
    _sessionKeys.clear();
    _sessionKeysByFp.clear();

    for (final peerId in peerIds) {
      await _store.deleteRatchet(peerId, baseUrlOverride: widget.baseUrl);
      await _store.saveSessionKey(
        peerId,
        '',
        baseUrlOverride: widget.baseUrl,
      );
      await _store.saveChain(
        peerId,
        <String, Object>{},
        baseUrlOverride: widget.baseUrl,
      );
    }

    if (mounted) {
      _applyState(() {
        _sessionHash = null;
        _safetyNumber = _computeSafety();
        _ratchetWarning = null;
        _promptedForKeyChange = false;
      });
    } else {
      _sessionHash = null;
      _safetyNumber = _computeSafety();
      _ratchetWarning = null;
      _promptedForKeyChange = false;
    }
  }

  Future<({bool recovered, bool reauthTriggered})>
      _recoverSendAuthState() async {
    try {
      final previous = _me;
      await _service.ensureAccountChatReady();
      ChatIdentity? refreshed = await _store.loadIdentity(
        baseUrlOverride: widget.baseUrl,
      );
      refreshed ??= await _store.loadIdentity();
      if (refreshed == null) {
        return (recovered: false, reauthTriggered: false);
      }
      final refreshedIdentity = refreshed;
      final identityChanged = previous == null ||
          previous.id.trim() != refreshedIdentity.id.trim() ||
          previous.fingerprint.trim() != refreshedIdentity.fingerprint.trim();
      if (mounted) {
        _applyState(() {
          _me = refreshedIdentity;
          _displayNameCtrl.text = refreshedIdentity.displayName ?? '';
        });
      } else {
        _me = refreshedIdentity;
      }
      if (identityChanged) {
        await _clearDirectSessionStateAfterLocalIdentityChange();
      }
      return (recovered: true, reauthTriggered: false);
    } catch (e) {
      final forced = await _forceReauthOnCriticalChatFailure(e);
      return (recovered: false, reauthTriggered: forced);
    }
  }

  Future<bool> _recoverPeerSessionBootstrapFailure(Object error) async {
    if (!_looksLikeSessionBootstrapFailure(error)) {
      return false;
    }
    final currentPeer = _peer;
    if (currentPeer == null) return false;
    return _recoverSessionMaterialForPeer(currentPeer);
  }

  Future<bool> _recoverSessionMaterialForPeer(
    ChatContact currentPeer, {
    String? fallbackSenderPubKeyB64,
    String? fallbackSenderFingerprint,
  }) async {
    final strictPinEnforcement =
        currentPeer.verified && currentPeer.verifiedAt != null;
    if (strictPinEnforcement) return false;

    await _clearPeerSessionMaterial(
      currentPeer.id,
      peerFingerprint: currentPeer.fingerprint,
    );
    final refreshedPeer = await _refreshPeerAfterSessionMaterialClear(
      currentPeer,
      fallbackSenderPubKeyB64: fallbackSenderPubKeyB64,
      fallbackSenderFingerprint: fallbackSenderFingerprint,
    );
    final updatedContacts = _upsertContact(refreshedPeer);
    _applyState(() {
      if (_peer?.id == refreshedPeer.id) {
        _peer = refreshedPeer;
        _sessionHash = null;
        _safetyNumber = _computeSafety();
      }
      _contacts = updatedContacts;
      _ratchetWarning = null;
      _promptedForKeyChange = false;
    });
    return true;
  }

  void _schedulePeerSessionBootstrapRecovery(
    ChatContact peer, {
    String? fallbackSenderPubKeyB64,
    String? fallbackSenderFingerprint,
  }) {
    final pid = peer.id.trim();
    if (pid.isEmpty || _peerSessionRecoveryInFlight.contains(pid)) {
      return;
    }
    final strictPinEnforcement = peer.verified && peer.verifiedAt != null;
    if (strictPinEnforcement) return;
    _peerSessionRecoveryInFlight.add(pid);
    final task = () async {
      try {
        await _recoverSessionMaterialForPeer(
          peer,
          fallbackSenderPubKeyB64: fallbackSenderPubKeyB64,
          fallbackSenderFingerprint: fallbackSenderFingerprint,
        );
      } catch (_) {
      } finally {
        _peerSessionRecoveryInFlight.remove(pid);
        _peerSessionRecoveryTasks.remove(pid);
      }
    }();
    _peerSessionRecoveryTasks[pid] = task;
    unawaited(task);
  }

  ChatContact? _latestKnownPeerForId(String peerId) {
    final pid = peerId.trim();
    if (pid.isEmpty) return null;
    final currentPeer = _peer;
    if (currentPeer != null && currentPeer.id == pid) {
      return currentPeer;
    }
    for (final contact in _contacts) {
      if (contact.id == pid) return contact;
    }
    return null;
  }

  Future<ChatContact> _stabilizePeerSessionForOutbound(ChatContact peer) async {
    final pid = peer.id.trim();
    if (pid.isEmpty) return peer;
    final existingRecovery = _peerSessionRecoveryTasks[pid];
    if (existingRecovery != null) {
      try {
        await existingRecovery;
      } catch (_) {}
    }
    final latestPeer = _latestKnownPeerForId(pid) ?? peer;
    final currentPeer = _peer;
    final hasCurrentPeerWarning = currentPeer != null &&
        currentPeer.id == pid &&
        ((_ratchetWarning ?? '').trim().isNotEmpty);
    final strictPinEnforcement =
        latestPeer.verified && latestPeer.verifiedAt != null;
    if (!hasCurrentPeerWarning || strictPinEnforcement) {
      return latestPeer;
    }
    try {
      await _recoverSessionMaterialForPeer(currentPeer);
    } catch (_) {}
    return _latestKnownPeerForId(pid) ?? latestPeer;
  }

  Future<ChatContact> _refreshPeerAfterSessionMaterialClear(
    ChatContact currentPeer, {
    String? fallbackSenderPubKeyB64,
    String? fallbackSenderFingerprint,
  }) async {
    ChatContact refreshedPeer = currentPeer.copyWith(
      verified: false,
      verifiedAt: null,
    );
    final fallbackKey = (fallbackSenderPubKeyB64 ?? '').trim();
    final fallbackFp = (() {
      final explicit = (fallbackSenderFingerprint ?? '').trim();
      if (explicit.isNotEmpty) return explicit;
      if (fallbackKey.isEmpty) return '';
      return fingerprintForKey(fallbackKey).trim();
    })();
    final hasAuthoritativeInboundIdentity =
        fallbackKey.isNotEmpty && fallbackFp.isNotEmpty;
    if (hasAuthoritativeInboundIdentity) {
      refreshedPeer = _contactWithUpdatedKey(
        refreshedPeer,
        fallbackKey,
        fallbackFp,
      );
    } else {
      try {
        final resolvedPeer = await _service.resolveDevice(currentPeer.id);
        final stillVerified = await _store.isVerified(
          resolvedPeer.id,
          resolvedPeer.fingerprint,
          baseUrlOverride: widget.baseUrl,
        );
        refreshedPeer = stillVerified
            ? resolvedPeer.copyWith(
                verified: true,
                verifiedAt: currentPeer.verifiedAt,
              )
            : resolvedPeer.copyWith(
                verified: false,
                verifiedAt: null,
              );
      } catch (_) {
        // Keep downgraded local peer if network refresh is unavailable.
      }
    }

    await _store.savePeer(refreshedPeer, baseUrlOverride: widget.baseUrl);
    await _saveScopedContactsForPeers(<ChatContact>[refreshedPeer]);
    return refreshedPeer;
  }

  bool _looksLikeSessionBootstrapFailure(Object error) {
    if (error is _SigningKeyPinViolation) {
      return true;
    }
    final text = switch (error) {
      _SessionBootstrapViolation(:final reason) => reason.toLowerCase(),
      _ => error.toString().toLowerCase(),
    };
    return text.contains('session key invalid') ||
        text.contains('peer identity key invalid') ||
        text.contains('prepared direct envelope actor mismatch') ||
        text.contains('identity signing key changed') ||
        text.contains('identity signing key missing') ||
        text.contains('identity key missing') ||
        text.contains('identity fingerprint missing') ||
        text.contains('sender key changed') ||
        text.contains('verify the safety number') ||
        text.contains('reset the session if unsure');
  }

  Future<({ChatMessage msg, ChatContact peer})> _sendDraftPayload({
    required ChatIdentity me,
    required String plainText,
    required ChatDirectSendEnvelope envelope,
    required ChatContact outboundPeer,
    required int keyId,
    required int prevKeyId,
    required String senderDhPubB64,
  }) async {
    final msg = await _service.sendMessage(
      me: me,
      peer: outboundPeer,
      plainText: plainText,
      expireAfterSeconds: _disappearing ? _disappearAfter.inSeconds : null,
      sealedSender: true,
      senderHint: me.fingerprint,
      keyId: keyId,
      prevKeyId: prevKeyId,
      senderDhPubB64: senderDhPubB64,
      preparedEnvelope: envelope,
    );
    return (msg: msg, peer: outboundPeer);
  }

  String _encodeDraftPayload({
    required ChatIdentity me,
    required _FrozenDirectDraftSend draft,
  }) {
    _sessionHash ??= _computeSessionHash();
    final payload = <String, Object?>{
      "text": draft.text,
      "client_ts": DateTime.now().toIso8601String(),
      "sender_fp": me.fingerprint,
      "session_hash": _sessionHash,
    };
    final reply = draft.replyToMessage;
    if (reply != null) {
      try {
        final decodedReply = _decodeMessage(reply);
        final preview = decodedReply.text.isNotEmpty
            ? decodedReply.text
            : _previewText(reply, decoded: decodedReply);
        payload['reply_to_id'] = reply.id;
        payload['reply_preview'] = preview;
      } catch (_) {}
    }
    if (draft.attachmentBytes != null) {
      payload["attachment_b64"] = base64Encode(draft.attachmentBytes!);
      payload["attachment_mime"] = draft.attachmentMime ?? "image/jpeg";
    }
    return jsonEncode(payload);
  }

  Future<
      ({
        ChatDirectSendEnvelope envelope,
        ChatContact peer,
        String plainText,
        int keyId,
        int prevKeyId,
        String senderDhPubB64,
      })> _prepareDraftEnvelope({
    required ChatIdentity me,
    required ChatContact peer,
    required _FrozenDirectDraftSend draft,
  }) async {
    final outbound = await _nextOutboundSendContext(peer);
    final plainText = _encodeDraftPayload(me: me, draft: draft);
    ChatDirectSendEnvelope envelope;
    try {
      envelope = _service.prepareDirectSendEnvelope(
        me: me,
        peer: outbound.peer,
        plainText: plainText,
        expireAfterSeconds: _disappearing ? _disappearAfter.inSeconds : null,
        sealedSender: true,
        senderHint: me.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
      );
    } catch (e) {
      if (_looksLikeSessionBootstrapFailure(e)) {
        throw _SessionBootstrapViolation(e.toString());
      }
      rethrow;
    }
    return (
      envelope: envelope,
      peer: outbound.peer,
      plainText: plainText,
      keyId: outbound.keyId,
      prevKeyId: outbound.prevKeyId,
      senderDhPubB64: outbound.senderDhPubB64,
    );
  }

  // Builds the optimistic local-only ChatMessage stub. The stub is
  // rendered in the thread *before* the encrypted-send round trip, so
  // the user sees the bubble the instant they tap Send. When the server
  // ACK arrives, [_replaceLocalStubWithServerMessage] swaps the stub
  // for the canonical server message.
  //
  // The stub piggy-backs on the existing `trustedLocalPlaintext` path:
  // we encode the same JSON payload that `_encodeDraftPayload` would
  // produce server-side, base64-wrap it, and hand it to the bubble. The
  // `_decrypt(m)` helper recognises the trusted-local flag and decodes
  // the body without any session key — so the bubble (incl. attachment,
  // reply preview, etc.) renders identically to a real ACKed message,
  // except for the status footer which shows a clock glyph.
  ChatMessage _buildOptimisticDirectStub({
    required String localId,
    required ChatIdentity me,
    required ChatContact peer,
    required _FrozenDirectDraftSend draft,
  }) {
    final plaintext = _encodeDraftPayload(me: me, draft: draft);
    return ChatMessage(
      id: localId,
      senderId: me.id,
      recipientId: peer.id,
      senderPubKeyB64: '',
      nonceB64: '',
      boxB64: base64Encode(utf8.encode(plaintext)),
      createdAt: DateTime.now(),
      trustedLocalPlaintext: true,
    );
  }

  // Stages the stub in the per-peer cache, the active-thread list, the
  // seen-id set, and the local-send-state side-channel — all under a
  // single setState so the bubble appears atomically with the
  // "sending" footer.
  void _stageOptimisticStub({
    required ChatMessage stub,
    required String peerId,
  }) {
    setState(() {
      _seenMessageIds.add(stub.id);
      final list = List<ChatMessage>.from(
        _cache[peerId] ?? const <ChatMessage>[],
      );
      list.add(stub);
      list.sort(_compareDirectMessageCursor);
      _cache[peerId] = list;
      _localSendStates[stub.id] = LocalSendState(
        localId: stub.id,
        peerId: peerId,
        startedAt: DateTime.now(),
        status: OutgoingSendStatus.sending,
      );
      if (_activePeerId == peerId) {
        _messages = list;
      }
    });
  }

  // Server ACK path. Removes the local stub from cache + seen-id set +
  // local-send-state map, then routes the server-canonical message
  // through `_mergeMessages` so all the usual side effects (contact
  // un-archive, recall handling, unread bookkeeping) run exactly as
  // they would for a non-optimistic send.
  void _replaceLocalStubWithServerMessage({
    required String localId,
    required ChatMessage serverMsg,
    required String peerId,
  }) {
    final list = _cache[peerId];
    if (list != null) {
      final filtered = list.where((m) => m.id != localId).toList();
      _cache[peerId] = filtered;
      if (_activePeerId == peerId) {
        _messages = filtered;
      }
    }
    _seenMessageIds.remove(localId);
    _localSendStates.remove(localId);
    // Drop the persisted outbox row — the send is canonical now.
    unawaited(_removeOutboxEntry(localId));
    _mergeMessages([serverMsg]);
  }

  // Failure-sink path. Keeps the stub visible (so the user's typed text
  // doesn't vanish into the ether) but flips its status to `failed`, at
  // which point the bubble footer renders a retry chip.
  void _markLocalSendFailed({
    required String localId,
    required String errorReason,
  }) {
    final cur = _localSendStates[localId];
    if (cur == null) return;
    if (!mounted) return;
    setState(() {
      _localSendStates[localId] = cur.withStatus(
        OutgoingSendStatus.failed,
        errorReason: errorReason,
      );
    });
    // Mirror the failure into the persistent outbox so a cold-start
    // restores the bubble with the same explanatory chip text.
    unawaited(_persistOutboxAttemptOnFailure(
      localId: localId,
      errorReason: errorReason,
    ));
  }

  // ---- Outbox integration ---------------------------------------
  // Mirrors a freshly-staged optimistic stub into the persistent
  // outbox so a hard app-kill mid-send doesn't lose the user's typed
  // message. Best-effort: a SharedPreferences write failure must not
  // block the in-memory send path.
  Future<void> _enqueueOutboxEntryForSend({
    required String localId,
    required String peerId,
    required _FrozenDirectDraftSend draft,
  }) async {
    final me = _me;
    if (me == null) return;
    final entry = ChatOutboxEntry(
      localId: localId,
      peerId: peerId,
      text: draft.text,
      attachmentB64: draft.attachmentBytes == null
          ? null
          : base64Encode(draft.attachmentBytes!),
      attachmentMime: draft.attachmentMime,
      replyToMessageId: draft.replyToMessage?.id,
      createdAt: DateTime.now().toUtc(),
    );
    try {
      await _outboxStore.enqueue(
        baseUrl: widget.baseUrl,
        deviceId: me.id,
        entry: entry,
      );
    } catch (_) {
      // Defensive: outbox persistence is a safety net, not a primary
      // delivery channel. A write failure on the very-first packet
      // just means a hard crash mid-send could lose this one message.
    }
  }

  // Drops the outbox entry matching the given localId. Called when:
  // - A server ACK arrives (`_replaceLocalStubWithServerMessage`)
  // - The user taps Dismiss on a failed stub
  // No-ops cleanly if `_me` isn't set yet.
  Future<void> _removeOutboxEntry(String localId) async {
    final me = _me;
    if (me == null) return;
    try {
      await _outboxStore.remove(
        baseUrl: widget.baseUrl,
        deviceId: me.id,
        localId: localId,
      );
    } catch (_) {}
  }

  // Bumps an outbox entry's `attempt` + `lastError` after a terminal
  // send failure. The stub stays visible (in `_localSendStates`) for
  // the user to retry; persisting the error means a later cold-start
  // restores the same failed bubble with the same explanatory chip.
  Future<void> _persistOutboxAttemptOnFailure({
    required String localId,
    required String errorReason,
  }) async {
    final me = _me;
    if (me == null) return;
    try {
      await _outboxStore.update(
        baseUrl: widget.baseUrl,
        deviceId: me.id,
        localId: localId,
        mutator: (e) => e.withAttempt(
          attempt: e.attempt + 1,
          lastError: errorReason,
        ),
      );
    } catch (_) {}
  }

  // Builds an optimistic-stub `ChatMessage` from a persisted outbox
  // entry. Mirrors `_buildOptimisticDirectStub` but reads from the
  // outbox JSON shape rather than a live `_FrozenDirectDraftSend`.
  // The reply-context is lossy across restart — we keep only the
  // original `reply_to_id` since the full message preview was the
  // peer's, which the local thread cache can re-resolve.
  ChatMessage _buildStubFromOutboxEntry(
    ChatIdentity me,
    ChatOutboxEntry entry,
  ) {
    _sessionHash ??= _computeSessionHash();
    final payload = <String, Object?>{
      'text': entry.text,
      'client_ts': entry.createdAt.toIso8601String(),
      'sender_fp': me.fingerprint,
      'session_hash': _sessionHash,
    };
    if (entry.replyToMessageId != null) {
      payload['reply_to_id'] = entry.replyToMessageId;
    }
    if (entry.attachmentB64 != null) {
      payload['attachment_b64'] = entry.attachmentB64;
      payload['attachment_mime'] = entry.attachmentMime ?? 'image/jpeg';
    }
    final plaintext = jsonEncode(payload);
    return ChatMessage(
      id: entry.localId,
      senderId: me.id,
      recipientId: entry.peerId,
      senderPubKeyB64: '',
      nonceB64: '',
      boxB64: base64Encode(utf8.encode(plaintext)),
      createdAt: entry.createdAt,
      trustedLocalPlaintext: true,
    );
  }

  // Re-entrant flush guard. Without this, a quick succession of
  // resume + WS-reconnect-success events could fan out into multiple
  // concurrent flush attempts for the same entry, each consuming a
  // server roundtrip and burning a seq counter. The bool also makes
  // the success path single-source: only one writer touches each
  // outbox entry at a time.
  bool _outboxFlushInFlight = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // App-resume is the strongest signal that the user is back +
    // connectivity has probably been restored. Trigger an outbox
    // flush so queued sends fire as soon as the page is visible
    // again. The flush itself is gated on per-entry backoff so we
    // don't hammer the server.
    if (state == AppLifecycleState.resumed) {
      unawaited(_flushOutboxIfDue());
    }
  }

  /// Attempts to re-send every outbox entry whose backoff window has
  /// elapsed. Triggered on:
  ///   * `didChangeAppLifecycleState(resumed)` — user foregrounded
  ///   * WS inbox first-successful-payload — connectivity confirmed
  ///   * (future) connectivity_plus stream `connected` event
  ///
  /// Per-entry backoff comes from `chatOutboxBackoffSeconds(attempt)`
  /// — `0s, 5s, 15s, 30s, 60s, 120s, 300s, 600s` (cap). The flush
  /// loop is re-entrant-guarded by `_outboxFlushInFlight` so racy
  /// triggers (resume + WS-recover within milliseconds of each
  /// other) don't double-send.
  Future<void> _flushOutboxIfDue() async {
    if (!mounted) return;
    final me = _me;
    if (me == null) return;
    if (_outboxFlushInFlight) return;
    _outboxFlushInFlight = true;
    try {
      final entries = await _outboxStore.sweep(
        baseUrl: widget.baseUrl,
        deviceId: me.id,
        now: DateTime.now(),
      );
      if (entries.isEmpty) return;
      final now = DateTime.now();
      for (final entry in entries) {
        if (!mounted) return;
        // Skip entries whose backoff window hasn't elapsed.
        final backoffSec = chatOutboxBackoffSeconds(entry.attempt);
        final due = entry.createdAt.add(Duration(seconds: backoffSec));
        if (now.isBefore(due)) continue;
        // Skip if the entry has already been turned into a server
        // message (race with concurrent hydrate / merger).
        if (!_seenMessageIds.contains(entry.localId)) continue;
        await _retryOutboxEntry(entry, me);
      }
    } catch (_) {
      // Defensive: a flush failure must not poison the page state.
    } finally {
      _outboxFlushInFlight = false;
    }
  }

  /// Retries a single outbox entry. On success the local stub is
  /// swapped for the canonical server message + the outbox row is
  /// removed. On failure the attempt counter + lastError on the row
  /// is bumped via `_markLocalSendFailed` so the next flush waits
  /// longer.
  Future<void> _retryOutboxEntry(
    ChatOutboxEntry entry,
    ChatIdentity me,
  ) async {
    // Resolve the peer. If we don't have a local contact (rare —
    // outbox entries were enqueued while the contact was known) fall
    // back to a minimal stub. The send path will reject it cleanly
    // and we'll mark it failed.
    ChatContact peer = ChatContact(
      id: entry.peerId,
      publicKeyB64: '',
      fingerprint: '',
    );
    for (final c in _contacts) {
      if (c.id == entry.peerId) {
        peer = c;
        break;
      }
    }
    final draft = _FrozenDirectDraftSend(
      text: entry.text,
      attachmentBytes: entry.attachmentB64 == null
          ? null
          : Uint8List.fromList(base64Decode(entry.attachmentB64!)),
      attachmentMime: entry.attachmentMime,
      // We lost the original `replyToMessage` ChatMessage object
      // across persistence — only the id survives. The server send
      // path only needs the id (`reply_to_id`) which is encoded into
      // the plaintext via `_encodeDraftPayload`. The bubble's reply
      // preview will rebuild from the local thread cache if the
      // referenced message is still around.
      replyToMessage: null,
    );
    try {
      final prepared = await _prepareDraftEnvelope(
        me: me,
        peer: peer,
        draft: draft,
      );
      final sent = await _sendDraftPayload(
        me: me,
        plainText: prepared.plainText,
        envelope: prepared.envelope,
        outboundPeer: prepared.peer,
        keyId: prepared.keyId,
        prevKeyId: prepared.prevKeyId,
        senderDhPubB64: prepared.senderDhPubB64,
      );
      _replaceLocalStubWithServerMessage(
        localId: entry.localId,
        serverMsg: sent.msg,
        peerId: sent.peer.id,
      );
    } catch (e) {
      _markLocalSendFailed(
        localId: entry.localId,
        errorReason: _sendFailureToUi(e),
      );
    }
  }

  // Loads the persisted outbox once per page lifetime and stages each
  // surviving entry as a `failed` stub in the visible thread. Sweep
  // happens first to silently drop entries past 24 h / 8 attempts —
  // staler ones would confuse the user more than they'd help. Idempotent
  // (`_outboxHydrated` short-circuits repeat calls during reauth cycles).
  Future<void> _hydrateOutboxIfNeeded() async {
    if (_outboxHydrated) return;
    final me = _me;
    if (me == null) return;
    _outboxHydrated = true;
    try {
      final entries = await _outboxStore.sweep(
        baseUrl: widget.baseUrl,
        deviceId: me.id,
        now: DateTime.now(),
      );
      if (entries.isEmpty) return;
      if (!mounted) return;
      setState(() {
        for (final entry in entries) {
          if (_seenMessageIds.contains(entry.localId)) continue;
          final stub = _buildStubFromOutboxEntry(me, entry);
          _seenMessageIds.add(entry.localId);
          final list = List<ChatMessage>.from(
            _cache[entry.peerId] ?? const <ChatMessage>[],
          );
          list.add(stub);
          list.sort(_compareDirectMessageCursor);
          _cache[entry.peerId] = list;
          if (_activePeerId == entry.peerId) {
            _messages = list;
          }
          _localSendStates[entry.localId] = LocalSendState(
            localId: entry.localId,
            peerId: entry.peerId,
            startedAt: entry.createdAt,
            status: OutgoingSendStatus.failed,
            errorReason: entry.lastError ?? 'queued',
            attempt: entry.attempt,
          );
        }
      });
    } catch (_) {
      // Defensive: a corrupt outbox must never block chat startup.
      // The sweep helper already drops unparseable entries.
    }
  }

  /// Loads the persisted voice-playback-speed pref. Called once
  /// from `initState`. Silent failure → falls back to the existing
  /// in-memory default (1.0). Validates against
  /// `_kVoicePlaybackSpeedSteps` so a malformed value in storage
  /// doesn't end up making the player run at 17× by accident.
  Future<void> _loadVoicePlaybackSpeedPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_kVoicePlaybackSpeedPrefKey);
      if (stored == null) return;
      if (!_kVoicePlaybackSpeedSteps.contains(stored)) return;
      if (!mounted) return;
      setState(() {
        _voicePlaybackSpeed = stored;
      });
    } catch (_) {
      // Defensive: a SharedPreferences read failure must never block
      // the chat page from booting.
    }
  }

  /// Advances `_voicePlaybackSpeed` to the next step in
  /// `_kVoicePlaybackSpeedSteps`, wrapping back to the first after
  /// the last. Applies immediately to a currently-playing voice and
  /// persists the new value for future plays.
  Future<void> _cycleVoicePlaybackSpeed() async {
    final current = _voicePlaybackSpeed;
    final idx = _kVoicePlaybackSpeedSteps.indexOf(current);
    final next = _kVoicePlaybackSpeedSteps[
        (idx < 0 ? 0 : (idx + 1) % _kVoicePlaybackSpeedSteps.length)];
    if (!mounted) return;
    setState(() {
      _voicePlaybackSpeed = next;
    });
    // Light haptic confirmation — the badge is small + relies on
    // muscle-memory tap accuracy, so a tap-down click reassures the
    // user the cycle landed without forcing them to read the badge
    // label.
    unawaited(HapticFeedback.selectionClick());
    try {
      await _audioPlayer.setSpeed(next);
    } catch (_) {
      // setSpeed throws on a uninitialised player; if no voice is
      // playing this is a no-op and the next play picks up the new
      // value via `_applyVoicePlaybackSpeedToPlayer`.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kVoicePlaybackSpeedPrefKey, next);
    } catch (_) {}
  }

  /// Applies the current `_voicePlaybackSpeed` to the audio player.
  /// Called from the play path right before `play()` so each new
  /// voice note honours the user's last-chosen speed.
  Future<void> _applyVoicePlaybackSpeedToPlayer() async {
    try {
      await _audioPlayer.setSpeed(_voicePlaybackSpeed);
    } catch (_) {
      // Best-effort: a setSpeed failure (e.g. unsupported codec)
      // shouldn't block the play call. The audio still plays at the
      // platform default.
    }
  }

  // Drops a failed stub when the user taps "Dismiss" in the footer
  // chip. Removes from in-memory state AND from the persistent
  // outbox so the bubble stays gone across a restart.
  void _discardFailedLocalSend(String localId) {
    final state = _localSendStates[localId];
    if (state == null) return;
    if (!mounted) return;
    setState(() {
      final list = _cache[state.peerId];
      if (list != null) {
        final filtered = list.where((m) => m.id != localId).toList();
        _cache[state.peerId] = filtered;
        if (_activePeerId == state.peerId) {
          _messages = filtered;
        }
      }
      _seenMessageIds.remove(localId);
      _localSendStates.remove(localId);
    });
    // Drop the persisted entry too — Dismiss is the user's explicit
    // "stop showing me this" so the next launch shouldn't resurrect it.
    unawaited(_removeOutboxEntry(localId));
  }

  /// Renders the 1× / 1.5× / 2× speed-cycle badge inside a voice
  /// bubble when this voice note is the one currently playing. Tap
  /// advances through `_kVoicePlaybackSpeedSteps`, applies the new
  /// rate to the active player, persists the choice, and fires a
  /// light haptic. The badge is small (~34×18) so it doesn't crowd
  /// the duration + waveform-bar area, and uses a chip-style
  /// background tint that mirrors the bubble's read-receipt accent.
  Widget _buildVoiceSpeedBadge(ThemeData theme) {
    final speed = _voicePlaybackSpeed;
    // Format: "1×", "1.5×", "2×" — keep the suffix tight, ASCII
    // "x" is too easy to misread as a Latin letter at small sizes;
    // U+00D7 (multiplication sign) is the typographic standard.
    final label = speed == speed.roundToDouble()
        ? '${speed.toInt()}×'
        : '${speed.toStringAsFixed(1)}×';
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_cycleVoicePlaybackSpeed()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary
              .withValues(alpha: isDark ? .25 : .15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  // Renders the small status-icon footer (timestamp + glyph + optional
  // retry chip) that hangs beneath an outgoing bubble. Returns `null`
  // for incoming messages — they never carry status.
  //
  // The glyph hierarchy maps `OutgoingSendStatus` → Material icon:
  //   sending   → tiny circular spinner
  //   sent      → ✓  (`Icons.done`)            grey
  //   delivered → ✓✓ (`Icons.done_all`)         grey
  //   read      → ✓✓ (`Icons.done_all`)         primary
  //   failed    → ⚠  (`Icons.error_outline`)   error
  // This matches the convention most chat apps converged on; iMessage
  // is the only major exception (it does the "Read 12:34" label) and
  // we keep the WhatsApp-style icon row for consistency with our RTL
  // Arabic locale where label-text doesn't have a clear standard.
  Widget? _buildBubbleStatusFooter(ChatMessage m, bool incoming) {
    // Skip the footer entirely for incoming messages that haven't been
    // edited — they already get a time header above the cluster, and
    // an extra per-bubble timestamp doubles the noise. Outgoing
    // messages always show a footer (status glyph carries the
    // delivered/read state). The "(edited)" marker is the one case
    // where an incoming bubble *does* earn a footer.
    final showEditedTag = m.wasEdited;
    // Cycle 13: incoming bubbles earn a footer when the message
    // was originally a scheduled send, so the recipient sees the
    // small "scheduled" badge alongside the timestamp.
    final showScheduledTag = m.wasScheduled;
    // Cycle 19: disappearing-message countdown chip. Render when
    // `expireAt` is in the future; empty string means "no chip".
    final expireRemaining = m.expireAt != null
        ? m.expireAt!.difference(DateTime.now())
        : Duration.zero;
    final expireLabel = formatExpireCountdown(expireRemaining);
    final showExpireChip = expireLabel.isNotEmpty;
    if (incoming &&
        !showEditedTag &&
        !showScheduledTag &&
        !showExpireChip) {
      return null;
    }
    final ml = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final local = _localSendStates[m.id];
    final status = chatMessageOutgoingStatus(message: m, localState: local);
    final ts = m.createdAt;
    final timeText = ts == null
        ? ''
        : ml.formatTimeOfDay(
            TimeOfDay.fromDateTime(ts.toLocal()),
            alwaysUse24HourFormat:
                MediaQuery.of(context).alwaysUse24HourFormat,
          );
    final editedLabel = l.isArabic ? '(معدّل)' : '(edited)';
    return Padding(
      padding: const EdgeInsets.only(right: 6, left: 6, top: 1, bottom: 4),
      child: Row(
        mainAxisAlignment: incoming
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showEditedTag) ...<Widget>[
            Text(
              editedLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: .55),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (showScheduledTag) ...<Widget>[
            Tooltip(
              message: l.isArabic
                  ? 'تم إرسال هذه الرسالة بناءً على جدولة سابقة'
                  : 'Sent from a scheduled send',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.schedule_outlined,
                    size: 11,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    l.isArabic ? 'مجدولة' : 'scheduled',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: .55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (timeText.isNotEmpty)
            Text(
              timeText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color: theme.colorScheme.onSurface.withValues(alpha: .55),
              ),
            ),
          if (showExpireChip) ...<Widget>[
            const SizedBox(width: 4),
            Tooltip(
              message: l.isArabic
                  ? 'تختفي بعد $expireLabel'
                  : 'Disappears in $expireLabel',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.timer_outlined,
                    size: 11,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    expireLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: .55),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!incoming) ...<Widget>[
            const SizedBox(width: 4),
            _buildOutgoingStatusGlyph(status, theme),
            if (status == OutgoingSendStatus.failed) ...<Widget>[
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _discardFailedLocalSend(m.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    l.isArabic ? 'تجاهل' : 'Dismiss',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOutgoingStatusGlyph(
    OutgoingSendStatus status,
    ThemeData theme,
  ) {
    switch (status) {
      case OutgoingSendStatus.sending:
        // Tiny indeterminate spinner — same surface used on the
        // composer send button while a network call is in flight, so
        // the visual language stays consistent. Stroke width is set
        // narrow so the glyph reads as "in-flight" not as a chunky
        // loading wheel.
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.onSurface.withValues(alpha: .45),
            ),
          ),
        );
      case OutgoingSendStatus.sent:
        return Icon(
          Icons.done,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );
      case OutgoingSendStatus.delivered:
        return Icon(
          Icons.done_all,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );
      case OutgoingSendStatus.read:
        // Read-receipt accent — uses `primary` so the colour adapts
        // automatically to light/dark themes and to any per-chat
        // theme overlay set in `_chatThemes`.
        return Icon(
          Icons.done_all,
          size: 14,
          color: theme.colorScheme.primary,
        );
      case OutgoingSendStatus.failed:
        return Icon(
          Icons.error_outline,
          size: 14,
          color: theme.colorScheme.error,
        );
    }
  }

  /// Builds a one-line accessibility label for a chat bubble. Read by
  /// VoiceOver / TalkBack so visually-impaired users get the same
  /// information sighted users see at a glance: direction, sender,
  /// time, body, and (for outgoing) send status.
  ///
  /// The audit (P0-3 / accessibility 1/5) called out that the chat
  /// page had **one** `Semantics` widget in 22k lines. This wraps the
  /// whole bubble in a meaningful label so every message is at least
  /// announceable — a 5× improvement at almost zero render cost.
  String _accessibilityLabelForBubble(ChatMessage m, bool incoming) {
    final l = L10n.of(context);
    final ml = MaterialLocalizations.of(context);
    final parts = <String>[];
    if (incoming) {
      final peerLabel = _peer?.id ?? l.shamellPreviewUnknown;
      parts.add(l.isArabic ? 'وارد من $peerLabel' : 'Incoming from $peerLabel');
    } else {
      parts.add(l.isArabic ? 'صادر' : 'Outgoing');
    }
    final ts = m.createdAt;
    if (ts != null) {
      parts.add(ml.formatTimeOfDay(
        TimeOfDay.fromDateTime(ts.toLocal()),
        alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
      ));
    }
    // Preview is intentionally short. The full body lives in the
    // bubble's visible Text node which TalkBack reads next; this
    // wrapper just sets the scene so the user knows *what kind* of
    // bubble they're navigating to.
    try {
      final preview = _previewText(m).trim();
      if (preview.isNotEmpty) {
        parts.add(preview.length <= 80 ? preview : '${preview.substring(0, 80)}…');
      }
    } catch (_) {
      // Preview decode can race with key rotation; fall through to
      // direction + time only rather than crash the semantic tree.
    }
    if (m.wasEdited) {
      parts.add(l.isArabic ? 'معدّل' : 'edited');
    }
    if (!incoming) {
      final local = _localSendStates[m.id];
      final status = chatMessageOutgoingStatus(message: m, localState: local);
      parts.add(switch (status) {
        OutgoingSendStatus.sending => l.isArabic ? 'جاري الإرسال' : 'sending',
        OutgoingSendStatus.sent => l.isArabic ? 'مرسل' : 'sent',
        OutgoingSendStatus.delivered => l.isArabic ? 'تم التسليم' : 'delivered',
        OutgoingSendStatus.read => l.isArabic ? 'مقروء' : 'read',
        OutgoingSendStatus.failed => l.isArabic ? 'فشل' : 'failed',
      });
    }
    return parts.join(' · ');
  }

  // Wraps `_bubble(...)` with the outgoing status footer + a one-shot
  // entrance animation (fade + 12px slide-up) for messages encountered
  // for the first time in this page lifetime. The animation set is
  // intentionally per-page-instance: rotating between chats replays the
  // animation on the next page open, which feels right — the receiving
  // user sees the chat refresh, not a static dump.
  //
  // The set mutation inside the build is mild — it ratchets ids one
  // way (added, never removed) and the next paint reads the same set
  // and skips the animation. It's the same idiom Flutter examples use
  // for one-shot "ripple on first build" effects.
  Widget _decorateMessageBubble(
    Widget bubble,
    ChatMessage m,
    ChatIdentity? me,
  ) {
    final incoming = _isIncoming(m);
    final statusFooter = _buildBubbleStatusFooter(m, incoming);
    Widget content = Column(
      crossAxisAlignment:
          incoming ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        bubble,
        if (statusFooter != null) statusFooter,
      ],
    );
    // Wrap the whole bubble + footer in a Semantics node with a
    // composed direction/sender/time/preview/status label. This is the
    // single biggest a11y improvement we can make per the audit —
    // before this, screen readers received only the raw Text widgets
    // inside the bubble (no context for "who", "when", or "status").
    content = Semantics(
      container: true,
      label: _accessibilityLabelForBubble(m, incoming),
      child: content,
    );
    // One-shot entrance: only animate messages with a recent createdAt
    // (≤ 6 s) so older bubbles loaded from history don't replay the
    // slide on initial render of a 1000-message thread.
    final ts = m.createdAt;
    final isRecent = ts != null &&
        DateTime.now().difference(ts.toLocal()).inSeconds.abs() <= 6;
    final alreadyAnimated = _animatedMessageIds.contains(m.id);
    if (isRecent && !alreadyAnimated) {
      _animatedMessageIds.add(m.id);
      content = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (ctx, t, child) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - t)),
              child: child,
            ),
          );
        },
        child: content,
      );
    }
    return content;
  }

  Future<void> _send() async {
    if (_me == null || _peer == null) return;
    // Cycle 28 — slash command interception. `/poll` short-circuits
    // into the poll creator dialog. `/me` and `/shrug` rewrite the
    // composer text in place and fall through to a regular send.
    final slash = parseSlashCommand(_msgCtrl.text);
    if (slash != null) {
      final shortCircuited = await _handleSlashCommand(slash);
      if (shortCircuited) return;
    }
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && _attachedBytes == null) return;
    final draft = _FrozenDirectDraftSend(
      text: text,
      attachmentBytes:
          _attachedBytes == null ? null : Uint8List.fromList(_attachedBytes!),
      attachmentMime: _attachedMime,
      replyToMessage: _replyToMessage,
    );
    // Lightweight client-side commands jump into SyrChat modules and
    // never produce a real outgoing message — they short-circuit before
    // we stage an optimistic stub so the user doesn't see a fake bubble
    // for `/mod foo`.
    if (await _handleLocalCommand(text)) {
      final peerId = _peer?.id;
      _msgCtrl.clear();
      _attachedBytes = null;
      _attachedMime = null;
      _attachedName = null;
      _replyToMessage = null;
      _stopComposerTypingSignal(peerId: peerId);
      if (peerId != null) {
        await _clearDraftForChat(peerId, persistNow: true);
      }
      return;
    }

    // --- Optimistic insert -------------------------------------------
    // Snapshot the actors so an account switch mid-send routes the
    // server-acked message back into the right conversation cache
    // even if `_me` / `_peer` have moved on by the time the round trip
    // completes.
    final me0 = _me!;
    final peer0 = _peer!;
    final localId = makeLocalChatMessageId();
    final stub = _buildOptimisticDirectStub(
      localId: localId,
      me: me0,
      peer: peer0,
      draft: draft,
    );
    _stageOptimisticStub(stub: stub, peerId: peer0.id);
    // Persist to the outbox immediately. A hard kill mid-send (low-
    // memory OOM, crash) would otherwise lose the user's message —
    // with this, the next launch's `_hydrateOutboxIfNeeded` restores
    // the stub as `failed` so the user can re-type or dismiss. The
    // store de-dupes by localId so the in-flight + persisted records
    // describe the same bubble.
    unawaited(_enqueueOutboxEntryForSend(
      localId: localId,
      peerId: peer0.id,
      draft: draft,
    ));
    // Clear the composer the instant the stub is staged. This is the
    // single biggest perceived-latency win in this change: the user
    // sees the bubble at the bottom and a blank composer ready for the
    // next message — exactly the WhatsApp / iMessage / Telegram feel.
    _msgCtrl.clear();
    _stopComposerTypingSignal(peerId: peer0.id);
    _attachedBytes = null;
    _attachedMime = null;
    _attachedName = null;
    _replyToMessage = null;
    await _clearDraftForChat(peer0.id, persistNow: true);
    _scheduleThreadScrollToBottom(force: true);
    if (mounted) {
      setState(() => _error = null);
    }
    // Light haptic on send — physical confirmation of the action even
    // before any server feedback. Cheap and ubiquitous in modern chat
    // apps.
    unawaited(HapticFeedback.selectionClick());

    // --- Real send round-trip ----------------------------------------
    Object? failure;
    ({
      ChatDirectSendEnvelope envelope,
      ChatContact peer,
      String plainText,
      int keyId,
      int prevKeyId,
      String senderDhPubB64,
    })? prepared;
    String? preparedSenderId;
    String? preparedSenderFingerprint;
    String? preparedPeerId;
    String? preparedPeerFingerprint;
    for (var attempt = 0; attempt < 3; attempt++) {
      final me = _me;
      final peer = _peer;
      if (me == null || peer == null) {
        failure = StateError('Authentication required');
        break;
      }
      try {
        final mustRebuildEnvelope = prepared == null ||
            preparedSenderId != me.id ||
            preparedSenderFingerprint != me.fingerprint ||
            preparedPeerId != peer.id ||
            preparedPeerFingerprint != peer.fingerprint;
        if (mustRebuildEnvelope) {
          prepared = await _prepareDraftEnvelope(
            me: me,
            peer: peer,
            draft: draft,
          );
          preparedSenderId = me.id;
          preparedSenderFingerprint = me.fingerprint;
          preparedPeerId = prepared.peer.id;
          preparedPeerFingerprint = prepared.peer.fingerprint;
        }
        final sent = await _sendDraftPayload(
          me: me,
          plainText: prepared.plainText,
          envelope: prepared.envelope,
          outboundPeer: prepared.peer,
          keyId: prepared.keyId,
          prevKeyId: prepared.prevKeyId,
          senderDhPubB64: prepared.senderDhPubB64,
        );
        // ACK — swap the stub for the canonical server message. We
        // route the swap through the per-peer cache snapshot so the
        // message lands in the correct conversation even after an
        // account or chat switch.
        _replaceLocalStubWithServerMessage(
          localId: localId,
          serverMsg: sent.msg,
          peerId: sent.peer.id,
        );
        return;
      } catch (e) {
        failure = e;
        if (await _recoverPeerSessionBootstrapFailure(e) && attempt < 2) {
          prepared = null;
          preparedSenderId = null;
          preparedSenderFingerprint = null;
          preparedPeerId = null;
          preparedPeerFingerprint = null;
          await _sendRetryBackoff(attempt);
          continue;
        }
        if (_isRecoverableSendError(e) && attempt < 2) {
          final recovery = await _recoverSendAuthState();
          if (recovery.reauthTriggered) {
            failure = null;
            break;
          }
          if (recovery.recovered) {
            await _sendRetryBackoff(attempt);
            continue;
          }
          await _sendRetryBackoff(attempt);
          continue;
        }
        break;
      }
    }
    if (failure != null) {
      if (await _forceReauthOnCriticalChatFailure(failure)) return;
      final ui = _sendFailureToUi(failure);
      _markLocalSendFailed(localId: localId, errorReason: ui);
      if (mounted) {
        setState(() => _error = ui);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ui)));
      }
    }
  }

  Future<void> _sendVoiceNote(Uint8List audioBytes, int seconds) async {
    if (_me == null || _peer == null) return;
    if (audioBytes.isEmpty || seconds <= 0) return;
    setState(() {
      _loading = true;
      _error = null;
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
      if (await _forceReauthOnCriticalChatFailure(e)) return;
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
      if (await _forceReauthOnCriticalChatFailure(e)) return;
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

  Future<bool> _handleLocalCommand(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
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
      await _openPaymentsPage(
        initialRecipient: recipient,
        initialAmountCents: amountCents,
      );
      return true;
    }
    return false;
  }

  Future<void> _openPaymentsPage({
    String? initialRecipient,
    int? initialAmountCents,
    String? initialSection,
  }) async {
    _startServiceOfficialFollow(
      officialId: 'shamell_pay',
      chatPeerId: 'shamell_pay',
    );
    final override = widget.openPaymentsPageOverride;
    if (override != null) {
      await override(initialRecipient, initialAmountCents);
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsPage(
          widget.baseUrl,
          '',
          'shamell',
          initialRecipient: initialRecipient,
          initialAmountCents: initialAmountCents,
          initialSection: initialSection,
          contextLabel: 'SyrChat Pay',
        ),
      ),
    );
  }

  Future<void> _sendTextQuick(String text) async {
    final me = _me;
    final peer = _peer;
    final trimmed = text.trim();
    if (me == null || peer == null || trimmed.isEmpty) return;
    final draft = _FrozenDirectDraftSend(text: trimmed);
    if (mounted) {
      setState(() {
        _sending = true;
        _loading = true;
        _error = null;
      });
    }

    var delivered = false;
    Object? failure;
    ({
      ChatDirectSendEnvelope envelope,
      ChatContact peer,
      String plainText,
      int keyId,
      int prevKeyId,
      String senderDhPubB64,
    })? prepared;
    String? preparedSenderId;
    String? preparedSenderFingerprint;
    String? preparedPeerId;
    String? preparedPeerFingerprint;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final currentMe = _me;
        final currentPeer = _peer;
        if (currentMe == null || currentPeer == null) {
          failure = StateError('Authentication required');
          break;
        }
        try {
          final mustRebuildEnvelope = prepared == null ||
              preparedSenderId != currentMe.id ||
              preparedSenderFingerprint != currentMe.fingerprint ||
              preparedPeerId != currentPeer.id ||
              preparedPeerFingerprint != currentPeer.fingerprint;
          if (mustRebuildEnvelope) {
            prepared = await _prepareDraftEnvelope(
              me: currentMe,
              peer: currentPeer,
              draft: draft,
            );
            preparedSenderId = currentMe.id;
            preparedSenderFingerprint = currentMe.fingerprint;
            preparedPeerId = prepared.peer.id;
            preparedPeerFingerprint = prepared.peer.fingerprint;
          }
          final sent = await _sendDraftPayload(
            me: currentMe,
            plainText: prepared.plainText,
            envelope: prepared.envelope,
            outboundPeer: prepared.peer,
            keyId: prepared.keyId,
            prevKeyId: prepared.prevKeyId,
            senderDhPubB64: prepared.senderDhPubB64,
          );
          _mergeMessages([sent.msg]);
          _scheduleThreadScrollToBottom(force: true);
          delivered = true;
          break;
        } catch (e) {
          failure = e;
          if (await _recoverPeerSessionBootstrapFailure(e) && attempt < 2) {
            prepared = null;
            preparedSenderId = null;
            preparedSenderFingerprint = null;
            preparedPeerId = null;
            preparedPeerFingerprint = null;
            await _sendRetryBackoff(attempt);
            continue;
          }
          if (_isRecoverableSendError(e) && attempt < 2) {
            final recovery = await _recoverSendAuthState();
            if (recovery.reauthTriggered) {
              failure = null;
              break;
            }
            if (recovery.recovered) {
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
        if (await _forceReauthOnCriticalChatFailure(failure)) return;
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

  Future<String> _loadWalletIdForChatActions() async {
    try {
      return (await loadStoredWalletId(baseUrlOverride: widget.baseUrl) ?? '')
          .trim();
    } catch (_) {
      return '';
    }
  }

  MiniAppDescriptor? _miniProgramDescriptorById(String id) {
    final normalized = id.trim().toLowerCase();
    for (final descriptor in MiniAppRegistry.descriptors) {
      final runtimeId = (descriptor.runtimeAppId ?? descriptor.id).trim();
      if (descriptor.id.toLowerCase() == normalized ||
          runtimeId.toLowerCase() == normalized) {
        return descriptor;
      }
    }
    return null;
  }

  Color _miniProgramAccent(String id) {
    switch (id.trim().toLowerCase()) {
      case 'payments':
        return const Color(0xFF07C160);
      case 'green_paket':
        return const Color(0xFF16A34A);
      case 'moments':
        return const Color(0xFF2563EB);
      case 'official_accounts':
        return const Color(0xFF0EA5E9);
      case 'channels':
        return const Color(0xFFEF4444);
      case 'people_nearby':
        return const Color(0xFF14B8A6);
      case 'stickers':
        return const Color(0xFFF97316);
      case 'bus':
        return Tokens.colorBus;
      default:
        return const Color(0xFF64748B);
    }
  }

  Future<void> _openGreenPaketForChat(
    ChatContact peer, {
    String? packetId,
  }) async {
    final did = (_me?.id ?? '').trim();
    if (did.isEmpty) return;
    final walletId = await _loadWalletIdForChatActions();
    final peerName = _displayNameForPeer(peer).trim();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GreenPaketPage(
          baseUrl: widget.baseUrl,
          walletId: walletId,
          deviceId: did,
          initialMessage:
              peerName.isNotEmpty ? 'For $peerName' : 'For this chat',
          initialGreenPaketId: packetId,
          onIssued: (packet) async {
            final id =
                (packet['green_paket_id'] ?? packet['id'] ?? '').toString();
            if (id.trim().isEmpty) return;
            final msg = (packet['message'] ?? '').toString().trim();
            final amount = (packet['total_amount_cents'] ?? '').toString();
            final count = (packet['total_count'] ?? '').toString();
            final details = [
              'Green Paket',
              if (msg.isNotEmpty) msg,
              if (amount.isNotEmpty && count.isNotEmpty)
                '$amount cents / $count',
              shamellGreenPaketDeepLink(id),
            ].join('\n');
            await _sendTextQuick(details);
          },
        ),
      ),
    );
  }

  Future<void> _openMiniProgramTarget(MiniProgramDeepLinkTarget target) async {
    final id = target.id.trim().toLowerCase();
    if (id.isEmpty) return;
    final currentPeer = _peer;
    if (id == 'green_paket' && currentPeer != null) {
      await _openGreenPaketForChat(currentPeer, packetId: target.resourceId);
      return;
    }
    if (id == 'payments') {
      await _openPaymentsPage(initialSection: 'send');
      return;
    }
    if (!mounted) return;
    if (id == 'moments') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShamellMomentsPage(baseUrl: widget.baseUrl),
        ),
      );
      return;
    }
    if (id == 'official_accounts') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OfficialAccountsPage(
            baseUrl: widget.baseUrl,
            onOpenChat: (peerId) {
              if (peerId.trim().isEmpty) return;
              Navigator.of(context).push(
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
    if (id == 'channels') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChannelsPage(
            baseUrl: widget.baseUrl,
            initialHotOnly: true,
          ),
        ),
      );
      return;
    }
    if (id == 'people_nearby') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NearbyPage(baseUrl: widget.baseUrl),
        ),
      );
      return;
    }
    if (id == 'stickers') {
      // Sticker Store retired — keep the deep-link id recognised so
      // legacy /open?id=stickers links don't fall through to the
      // generic "module not found" handler, but no-op the action.
      return;
    }
    final app = MiniAppRegistry.byId(id);
    if (app != null) {
      final walletId = await _loadWalletIdForChatActions();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => app.entry(
            ctx,
            SuperappAPI.light(
              baseUrl: widget.baseUrl,
              walletId: walletId,
              deviceId: (_me?.id ?? '').trim(),
              openMod: (mod) {
                unawaited(
                  _openMiniProgramTarget(MiniProgramDeepLinkTarget(id: mod)),
                );
              },
              pushPage: (page) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => page),
                );
              },
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final l = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.isArabic
              ? 'تعذّر فتح البرنامج المصغّر.'
              : 'Could not open mini program.',
        ),
      ),
    );
  }

  void _openOfficialAccountsDirectory() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OfficialAccountsPage(
          baseUrl: widget.baseUrl,
          onOpenChat: (peerId) {
            final id = peerId.trim();
            if (id.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ShamellChatPage(
                  baseUrl: widget.baseUrl,
                  initialPeerId: id,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openMomentsSurface() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShamellMomentsPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  Future<void> _showMiniProgramShareSheet(ChatContact peer) async {
    final l = L10n.of(context);
    final descriptors = MiniAppRegistry.descriptors
        .where((d) => d.enabled)
        .toList(growable: true)
      ..sort((a, b) {
        final usage = b.usageScore.compareTo(a.usageScore);
        if (usage != 0) return usage;
        return b.rating.compareTo(a.rating);
      });
    if (descriptors.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: descriptors.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (ctx2, i) {
              if (i == 0) {
                return ListTile(
                  title: Text(
                    l.isArabic ? 'إرسال برنامج مصغّر' : 'Send mini program',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'يظهر كبطاقة قابلة للفتح داخل الدردشة.'
                        : 'Shared as an openable in-chat app card.',
                  ),
                );
              }
              final descriptor = descriptors[i - 1];
              final id = (descriptor.runtimeAppId ?? descriptor.id).trim();
              final accent = _miniProgramAccent(id);
              return ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(descriptor.icon, color: accent),
                ),
                title: Text(descriptor.title(isArabic: l.isArabic)),
                subtitle: Text(descriptor.category(isArabic: l.isArabic)),
                trailing: const Icon(Icons.send_outlined, size: 18),
                onTap: () {
                  Navigator.of(ctx).pop();
                  final link = shamellMiniProgramDeepLink(id);
                  unawaited(
                    _sendTextQuick(
                      '${descriptor.title(isArabic: l.isArabic)}\n$link',
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMiniProgramMessageCard(
    MiniProgramDeepLinkTarget target,
    ThemeData theme,
    L10n l,
    bool incoming,
  ) {
    final descriptor = _miniProgramDescriptorById(target.id);
    final isDark = theme.brightness == Brightness.dark;
    final title = descriptor?.title(isArabic: l.isArabic) ??
        (target.id == 'green_paket' ? 'Green Paket' : target.id);
    final category = descriptor?.category(isArabic: l.isArabic) ??
        (l.isArabic ? 'برنامج مصغّر' : 'Mini Program');
    final accent = _miniProgramAccent(target.id);
    final subtitle = target.id == 'green_paket'
        ? (l.isArabic
            ? 'افتح أو طالب بالحزمة داخل سرتشات'
            : 'Open or claim inside SyrChat')
        : category;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => unawaited(_openMiniProgramTarget(target)),
      child: Container(
        width: 232,
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surface.withValues(alpha: .92)
              : Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withValues(alpha: isDark ? .20 : .08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? .20 : .06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      descriptor?.icon ?? Icons.apps_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .58),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: .40),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: isDark ? .35 : .55),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
              child: Text(
                l.isArabic ? 'سرتشات Mini Program' : 'SyrChat Mini Program',
                textAlign: incoming ? TextAlign.start : TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startServiceOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) {
    final override = widget.startServiceOfficialFollowOverride;
    if (override != null) {
      unawaited(override(officialId, chatPeerId));
      return;
    }
    unawaited(
      _ensureServiceOfficialFollow(
        officialId: officialId,
        chatPeerId: chatPeerId,
      ),
    );
  }

  Future<void> _ensureServiceOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {
    if (officialId.isEmpty || chatPeerId.isEmpty) return;
    final httpClient = widget.officialHttpClient ?? shamellHttpClient();
    final closeClient = widget.officialHttpClient == null;
    try {
      final alreadyFollowed = await _store.hasOfficialAutofollowed(
        officialId,
        baseUrlOverride: widget.baseUrl,
      );
      var justFollowed = false;
      if (!alreadyFollowed) {
        final uri = _chatApiUri(
          pathSegments: <String>['official_accounts', officialId, 'follow'],
        );
        if (uri == null) {
          return;
        }
        final reqHeaders = await _officialHeaders(jsonBody: true);
        final idempotencyScope = '$officialId|follow';
        final idempotencyKey =
            _pendingOfficialFollowIdempotencyKeys.putIfAbsent(
          idempotencyScope,
          () => _newOfficialMutationIdempotencyKey('official-follow'),
        );
        reqHeaders['Idempotency-Key'] = idempotencyKey;
        final r = await httpClient
            .post(uri, headers: reqHeaders)
            .timeout(_ShamellChatPageState._chatRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          _pendingOfficialFollowIdempotencyKeys.remove(idempotencyScope);
          await _store.markOfficialAutofollowed(
            officialId,
            baseUrlOverride: widget.baseUrl,
          );
          justFollowed = true;
        } else if (await _forceReauthOnCriticalOfficialHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          return;
        }
      }
      final alreadyLinked = await _store.hasOfficialAutochat(
        chatPeerId,
        baseUrlOverride: widget.baseUrl,
      );
      if (!alreadyLinked) {
        final contacts = await _loadScopedContacts();
        ChatContact? existing;
        for (final contact in contacts) {
          if (contact.id == chatPeerId) {
            existing = contact;
            break;
          }
        }
        if (existing == null) {
          ChatContact peer;
          try {
            peer = await _service.resolveDevice(chatPeerId);
          } catch (_) {
            return;
          }
          await _saveScopedContactsForPeers(<ChatContact>[peer]);
        }
        await _store.markOfficialAutochat(
          chatPeerId,
          baseUrlOverride: widget.baseUrl,
        );
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
    } catch (e) {
      if (await _forceReauthOnCriticalOfficialError(e)) return;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _pullInbox({bool silent = false}) async {
    final me = await _syncChatIdentityFromStoreIfChanged();
    if (me == null) return;
    try {
      final directCursor = await _store.loadDirectInboxCursor(
        baseUrlOverride: widget.baseUrl,
      );
      final msgs = await _service.fetchInboxPaged(
        deviceId: me.id,
        sinceIso: directCursor?.sinceIso,
        sinceId: directCursor?.sinceId,
        batchSize: 200,
        maxPages: 25,
      );
      if (msgs.isNotEmpty) {
        _mergeMessages(msgs);
        await _store.saveLatestDirectInboxCursor(
          msgs,
          baseUrlOverride: widget.baseUrl,
        );
      }
      await _syncGroups();
      if (!silent && mounted && _error != null) {
        setState(() => _error = null);
      }
    } catch (e) {
      if (_isRecoverableSendError(e)) {
        final refreshed = await _syncChatIdentityFromStoreIfChanged();
        if (refreshed != null && refreshed.id.trim() != me.id.trim()) {
          return _pullInbox(silent: silent);
        }
      }
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      if (!mounted) return;
      if (silent) return;
      setState(() => _error = _sendFailureToUi(e));
    }
  }

  Future<ChatIdentity?> _syncChatIdentityFromStoreIfChanged() async {
    final refreshed =
        await _store.loadIdentity(baseUrlOverride: widget.baseUrl);
    if (refreshed == null) {
      return _me;
    }
    final current = _me;
    final changed = current == null ||
        current.id.trim() != refreshed.id.trim() ||
        current.fingerprint.trim() != refreshed.fingerprint.trim();
    if (!changed) {
      return current;
    }
    if (mounted) {
      _applyState(() {
        _me = refreshed;
        _displayNameCtrl.text = refreshed.displayName ?? '';
      });
    } else {
      _me = refreshed;
    }
    await _clearDirectSessionStateAfterLocalIdentityChange();
    return refreshed;
  }

  String _groupUnreadKey(String groupId) => 'grp:$groupId';

  Future<String?> _loadGroupSeenForGroup(String groupId) async {
    final override = widget.loadGroupSeenForGroupOverride;
    if (override != null) {
      return override(groupId);
    }
    return _store.loadGroupSeenForGroup(
      groupId,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<Map<String, String>> _loadGroupSeenForGroups(
    Iterable<String> groupIds,
  ) async {
    final override = widget.loadGroupSeenForGroupsOverride;
    if (override != null) {
      return override(groupIds);
    }
    return _store.loadGroupSeenForGroups(
      groupIds,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _saveUnreadCountForPeer(String peerId, int unreadCount) async {
    final override = widget.saveUnreadCountForPeerOverride;
    if (override != null) {
      await override(peerId, unreadCount);
      return;
    }
    await _store.saveUnreadCountForPeer(
      peerId,
      unreadCount,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _saveServiceNotificationsHasUnread(bool hasUnread) async {
    final override = widget.saveServiceNotificationsHasUnreadOverride;
    if (override != null) {
      await override(hasUnread);
      return;
    }
    await _store.saveServiceNotificationsHasUnread(
      hasUnread,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _saveHideServiceNotificationsThread(bool hide) async {
    final override = widget.saveHideServiceNotificationsThreadOverride;
    if (override != null) {
      await override(hide);
      return;
    }
    await _store.saveHideServiceNotificationsThread(
      hide,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _saveUnreadCountForGroup(String groupId, int unreadCount) async {
    final override = widget.saveUnreadCountForGroupOverride;
    if (override != null) {
      await override(groupId, unreadCount);
      return;
    }
    await _store.saveUnreadCountForGroup(
      groupId,
      unreadCount,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _saveUnreadCountsForKeys(
    Map<String, int> unread,
    Iterable<String> unreadKeys,
  ) async {
    final override = widget.saveUnreadCountsForKeysOverride;
    if (override != null) {
      await override(unread, unreadKeys);
      return;
    }
    await _store.saveUnreadCountsForKeys(
      unread,
      unreadKeys,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _saveMessagesForPeer(
    String peerId,
    List<ChatMessage> messages,
  ) async {
    final override = widget.saveMessagesForPeerOverride;
    if (override != null) {
      await override(peerId, messages);
      return;
    }
    await _store.saveMessages(
      peerId,
      messages,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _saveGroupMessagesForGroup(
    String groupId,
    List<ChatGroupMessage> messages,
  ) async {
    final override = widget.saveGroupMessagesForGroupOverride;
    if (override != null) {
      await override(groupId, messages);
      return;
    }
    await _store.saveGroupMessages(
      groupId,
      messages,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _forwardMessageFromMenu(ChatMessage message) async {
    final override = widget.forwardMessageOverride;
    if (override != null) {
      await override(message);
      return;
    }
    // Cycle 20: long-press → multi-peer forward. Falls through to
    // the legacy single-target path when only one target is picked,
    // so the existing optimistic stub + visible-thread switch
    // behaviour is preserved for the common 1:1 case.
    final targets = await _pickForwardTargetsMulti();
    if (targets.isEmpty || !mounted) return;
    if (targets.length == 1) {
      await _forwardMessagesToTarget(<ChatMessage>[message], targets.first);
      return;
    }
    final l = L10n.of(context);
    int successCount = 0;
    for (final t in targets) {
      try {
        await _forwardMessagesToTarget(<ChatMessage>[message], t);
        successCount += 1;
      } catch (_) {
        // Per-target failure — continue with the rest so a single
        // bad target doesn't drop the entire batch.
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.isArabic
              ? 'تم إعادة التوجيه إلى $successCount محادثة'
              : 'Forwarded to $successCount chats',
        ),
      ),
    );
  }

  Future<void> _copyMessageTextFromMenu(String text) async {
    final override = widget.copyMessageTextOverride;
    if (override != null) {
      await override(text);
      return;
    }
    await shamellCopyToClipboard(text, sensitive: true);
  }

  Future<void> _addFavoriteItemQuickFromMenu(
    String text, {
    String? chatId,
    String? msgId,
  }) async {
    final override = widget.addFavoriteItemQuickOverride;
    if (override != null) {
      await override(text, chatId, msgId);
      return;
    }
    await addFavoriteItemQuick(
      text,
      baseUrlOverride: widget.baseUrl,
      chatId: chatId,
      msgId: msgId,
    );
  }

  Future<void> _addFavoriteLocationQuickFromMenu(
    double lat,
    double lon, {
    String? label,
    String? chatId,
    String? msgId,
  }) async {
    final override = widget.addFavoriteLocationQuickOverride;
    if (override != null) {
      await override(lat, lon, label, chatId, msgId);
      return;
    }
    await addFavoriteLocationQuick(
      lat,
      lon,
      baseUrlOverride: widget.baseUrl,
      label: label,
      chatId: chatId,
      msgId: msgId,
    );
  }

  Future<void> _translateMessageFromMenu(String text) async {
    final override = widget.translateMessageOverride;
    if (override != null) {
      await override(text);
      return;
    }
    await _translateMessage(text);
  }

  Future<void> _upsertGroupNames(List<ChatGroup> groups) async {
    final override = widget.upsertGroupNamesOverride;
    if (override != null) {
      await override(groups);
      return;
    }
    await _store.upsertGroupNames(
      groups,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _syncGroups() async {
    final me = await _syncChatIdentityFromStoreIfChanged();
    if (me == null) return;
    try {
      final groups = await _service.listGroupsPaged(
        deviceId: me.id,
        batchSize: 200,
        maxPages: 25,
      );
      final store = _store;
      await _upsertGroupNames(groups);
      final seenMap = await _loadGroupSeenForGroups(
        groups.map((group) => group.id),
      );
      final nextUnread = Map<String, int>.from(_unread);
      final nextGroupCache =
          Map<String, List<ChatGroupMessage>>.from(_groupCache);
      final nextGroupMentionUnread = <String>{};
      final nextGroupMentionAllUnread = <String>{};
      final nextArchivedGroupIds = Set<String>.from(_archivedGroupIds);
      final unarchivedGroupIds = <String>{};
      final syncedUnreadKeys = <String>{};
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
            cached = await store.loadGroupMessages(
              gid,
              baseUrlOverride: widget.baseUrl,
            );
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
        final cursorMessage = _latestGroupCursorMessage(cached);
        final sinceIso = cursorMessage?.createdAt?.toUtc().toIso8601String() ??
            (seenTs.isAfter(epoch) ? seenTs.toUtc().toIso8601String() : null);
        final sinceId = cursorMessage?.id;
        List<ChatGroupMessage> fresh = const <ChatGroupMessage>[];
        try {
          fresh = await _service.fetchGroupInboxPaged(
            groupId: gid,
            deviceId: me.id,
            sinceIso: sinceIso,
            sinceId: sinceId,
            batchSize: 200,
            maxPages: 25,
          );
        } catch (e) {
          if (await _forceReauthOnCriticalChatFailure(e)) return;
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
          cached = byId.values.toList()..sort(_compareGroupMessageCursor);
          nextGroupCache[gid] = cached;
          try {
            await store.saveGroupMessages(
              gid,
              cached,
              baseUrlOverride: widget.baseUrl,
            );
          } catch (_) {}
        } else {
          nextGroupCache[gid] = cached;
        }
        final unreadCount = cached.where((m) {
          final ts = m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return m.senderId != me.id && ts.isAfter(seenTs);
        }).length;
        if (unreadCount > 0 && nextArchivedGroupIds.remove(gid)) {
          unarchivedGroupIds.add(gid);
        }
        final unreadKey = _groupUnreadKey(gid);
        syncedUnreadKeys.add(unreadKey);
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
      for (final gid in unarchivedGroupIds) {
        await _persistArchivedGroupState(gid, false);
      }
      await _saveUnreadCountsForKeys(nextUnread, syncedUnreadKeys);
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
    }
  }

  Future<void> _mergeGroupInboxUpdate(ChatGroupInboxUpdate upd) async {
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
      _applyArchivedGroupState(gid, false);
      await _persistArchivedGroupState(gid, false);
    }
    final merged = byId.values.toList()..sort(_compareGroupMessageCursor);

    _groupCache[gid] = merged;
    await _saveGroupMessagesForGroup(gid, merged);

    _maybeNotifyGroupMentions(gid, newMsgs);

    DateTime seenTs = DateTime.fromMillisecondsSinceEpoch(0);
    final seenIso = await _loadGroupSeenForGroup(gid);
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
    await _saveUnreadCountForGroup(gid, nextUnread[unreadKey] ?? 0);
    if (!_groups.any((g) => g.id == gid)) {
      await _syncGroups();
    }
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
        final prefs = await store.loadNotifyConfig(
          baseUrlOverride: widget.baseUrl,
        );
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
          tapTarget: const NotificationTapTarget.chat(),
        );
      }());
      break;
    }
  }

  void _listenWs() {
    _wsSub?.cancel();
    _grpWsSub?.cancel();
    _typingWsSub?.cancel();
    _conversationEventTimer?.cancel();
    _wsInboxReconnectTimer?.cancel();
    _wsGroupsReconnectTimer?.cancel();
    _service.closeLiveSockets();
    final me = _me;
    if (me == null) return;

    // Bump both generations so any pending async reconnects from a
    // prior `_listenWs()` call (e.g. after an account switch) are
    // silently dropped on their next callback.
    _wsInboxGeneration += 1;
    _wsInboxBackoffStep = 0;
    final inboxGen = _wsInboxGeneration;
    _wsGroupsGeneration += 1;
    _wsGroupsBackoffStep = 0;
    final groupsGen = _wsGroupsGeneration;

    _bringUpInboxWs(deviceId: me.id, generation: inboxGen);
    _bringUpGroupsWs(deviceId: me.id, generation: groupsGen);

    _typingWsSub =
        _service.streamTypingSignals(deviceId: me.id).listen((signal) {
      _handleTypingSignal(signal);
    }, onError: (_) {}, onDone: () {});
    _startConversationEventPolling();
  }

  // ---- WS reconnect machinery -------------------------------------
  // The audit found `streamInbox`/`streamGroupInbox` had no recovery
  // on `onDone`/`onError`: the page would silently stop receiving
  // pushes and lean on the 2-second HTTP poll until either an app
  // restart or a chat switch reopened the socket. Below is a tiny
  // reconnect manager — exponential backoff + generation guard +
  // catch-up `_pullInbox()` on each reconnect — that keeps the WS
  // live without spamming the server.
  //
  // We deliberately *don't* kill the conversation-event poll yet;
  // that's the next-step P0-9 server work (emit message_received in
  // send_message) which makes the poll redundant. Until then it stays
  // as a safety net but its tick rate already feels much less
  // critical now that pushes actually flow.

  void _bringUpInboxWs({
    required String deviceId,
    required int generation,
  }) {
    if (!mounted) return;
    if (generation != _wsInboxGeneration) return;
    _wsSub?.cancel();
    _wsSub = _service.streamInbox(deviceId: deviceId).listen(
      (msgs) {
        if (generation != _wsInboxGeneration) return;
        // Treat any payload as proof the connection is healthy: reset
        // the backoff so the *next* disconnect retries fast. Without
        // this reset, long-lived connections that flap every few hours
        // would keep marching the backoff up to the 30 s ceiling.
        final wasReconnecting = _wsInboxBackoffStep > 0;
        _wsInboxBackoffStep = 0;
        if (msgs.isNotEmpty) {
          _mergeMessages(msgs);
          _startLiveDirectInboxCursorSave(msgs);
        }
        // A successful payload after a backoff step > 0 means we've
        // recovered from a disconnect — the strongest signal that
        // connectivity has returned. Drain the outbox now so queued
        // sends fire on the freshly-healthy socket. Skipping this
        // when we never disconnected avoids hammering the outbox
        // helper on every inbox tick during steady-state.
        if (wasReconnecting) {
          unawaited(_flushOutboxIfDue());
        }
      },
      onError: (_) {
        if (generation != _wsInboxGeneration) return;
        _scheduleInboxWsReconnect(
          deviceId: deviceId,
          generation: generation,
        );
      },
      onDone: () {
        if (generation != _wsInboxGeneration) return;
        _scheduleInboxWsReconnect(
          deviceId: deviceId,
          generation: generation,
        );
      },
    );
  }

  void _scheduleInboxWsReconnect({
    required String deviceId,
    required int generation,
  }) {
    if (!mounted) return;
    if (generation != _wsInboxGeneration) return;
    _wsInboxReconnectTimer?.cancel();
    _wsInboxBackoffStep = chatWsReconnectNextStep(
      currentStep: _wsInboxBackoffStep,
    );
    final delayMs = chatWsReconnectDelayMs(step: _wsInboxBackoffStep);
    _wsInboxReconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!mounted) return;
      if (generation != _wsInboxGeneration) return;
      // Catch up via HTTP fetch *before* reopening the WS — any
      // messages buffered server-side while we were disconnected get
      // surfaced even if the new socket misses them due to a mailbox
      // cursor race on the server.
      try {
        await _pullInbox();
      } catch (_) {}
      if (!mounted) return;
      if (generation != _wsInboxGeneration) return;
      _bringUpInboxWs(deviceId: deviceId, generation: generation);
    });
  }

  void _bringUpGroupsWs({
    required String deviceId,
    required int generation,
  }) {
    if (!mounted) return;
    if (generation != _wsGroupsGeneration) return;
    _grpWsSub?.cancel();
    _grpWsSub = _service.streamGroupInbox(deviceId: deviceId).listen(
      (upd) {
        if (generation != _wsGroupsGeneration) return;
        _wsGroupsBackoffStep = 0;
        _startLiveGroupInboxMerge(upd);
      },
      onError: (_) {
        if (generation != _wsGroupsGeneration) return;
        _scheduleGroupsWsReconnect(
          deviceId: deviceId,
          generation: generation,
        );
      },
      onDone: () {
        if (generation != _wsGroupsGeneration) return;
        _scheduleGroupsWsReconnect(
          deviceId: deviceId,
          generation: generation,
        );
      },
    );
  }

  void _scheduleGroupsWsReconnect({
    required String deviceId,
    required int generation,
  }) {
    if (!mounted) return;
    if (generation != _wsGroupsGeneration) return;
    _wsGroupsReconnectTimer?.cancel();
    _wsGroupsBackoffStep = chatWsReconnectNextStep(
      currentStep: _wsGroupsBackoffStep,
    );
    final delayMs = chatWsReconnectDelayMs(step: _wsGroupsBackoffStep);
    _wsGroupsReconnectTimer =
        Timer(Duration(milliseconds: delayMs), () async {
      if (!mounted) return;
      if (generation != _wsGroupsGeneration) return;
      _bringUpGroupsWs(deviceId: deviceId, generation: generation);
    });
  }

  void _startConversationEventPolling() {
    _conversationEventTimer?.cancel();
    final me = _me;
    if (me == null) return;
    unawaited(_pollConversationEvents());
    _conversationEventTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollConversationEvents());
    });
  }

  Future<void> _pollConversationEvents() async {
    final me = _me;
    if (me == null || _conversationEventPollInFlight) return;
    _conversationEventPollInFlight = true;
    try {
      final events = await _service.fetchConversationEvents(
        deviceId: me.id,
        afterEventId: _lastConversationEventId,
      );
      if (events.isEmpty) return;
      for (final event in events) {
        if (event.eventId > _lastConversationEventId) {
          _lastConversationEventId = event.eventId;
        }
        await _handleConversationEvent(event);
      }
    } catch (_) {
    } finally {
      _conversationEventPollInFlight = false;
    }
  }

  Future<void> _handleConversationEvent(ChatConversationEvent event) async {
    final payload = event.payload;
    final messageId = (payload['message_id'] ?? event.resourceId).toString();
    switch (event.eventType) {
      case 'message_deleted':
        await _removeMessageFromLocalCaches(messageId);
        await _handleMessageRecalled(messageId);
        break;
      case 'message_pinned':
        final peerId = (payload['peer_id'] ?? event.peerId ?? '').toString();
        final pinned = payload['pinned'] == true;
        if (peerId.trim().isNotEmpty) {
          await _setPinnedMessageState(peerId, messageId, pinned);
        }
        break;
      case 'profile_updated':
        // Cycle 60 — the changing peer is in `event.resourceId`
        // (server fan-out keys it as the changing device's id).
        // Kick a one-peer profile fetch so the avatar/name/status
        // refresh in seconds instead of waiting for the 5-minute
        // periodic poller.
        final changedPeer = (event.resourceId).trim();
        if (changedPeer.isNotEmpty) {
          unawaited(_refreshSinglePeerProfile(changedPeer));
        }
        break;
      case 'message_reaction':
        final meId = _me?.id.trim() ?? '';
        final actor = (payload['actor_device_id'] ?? '').toString().trim();
        if (actor.isNotEmpty && actor == meId && messageId.trim().isNotEmpty) {
          final removed = payload['removed'] == true;
          final emoji = (payload['emoji'] ?? '').toString().trim();
          if (!mounted) return;
          _applyState(() {
            if (removed || emoji.isEmpty) {
              _messageReactions.remove(messageId);
            } else {
              _messageReactions[messageId] = emoji;
            }
          });
        }
        break;
      case 'call_log':
        _lastCallsCache = null;
        if (mounted) setState(() {});
        break;
      case 'message_edited':
        await _refreshActiveThreadAfterEvent();
        break;
      case 'voice_transcript':
      case 'voice_transcript_job':
      case 'message_reported':
        break;
    }
  }

  void _handleTypingSignal(ChatTypingSignal signal) {
    if (signal.scope != ChatTypingScope.direct) return;
    final myId = _me?.id.trim();
    final peerId = signal.fromDeviceId.trim();
    if (peerId.isEmpty || myId == null || myId.isEmpty || peerId == myId) {
      return;
    }
    if (signal.isTyping) {
      _peerTypingExpiresAt[peerId] = DateTime.now().add(_typingIndicatorTtl);
    } else {
      _peerTypingExpiresAt.remove(peerId);
    }
    _scheduleTypingIndicatorPrune();
    if (!mounted) return;
    setState(() {});
  }

  void _startLiveGroupInboxMerge(ChatGroupInboxUpdate update) {
    final override = widget.startLiveGroupInboxMergeOverride;
    if (override != null) {
      unawaited(override(update));
      return;
    }
    unawaited(_mergeGroupInboxUpdate(update));
  }

  void _startLiveDirectMessageSave(
    String peerId,
    List<ChatMessage> messages,
  ) {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return;
    final snapshot = List<ChatMessage>.from(messages);
    final override = widget.startLiveDirectMessageSaveOverride;
    if (override != null) {
      unawaited(override(normalizedPeerId, snapshot));
      return;
    }
    unawaited(_saveMessagesForPeer(normalizedPeerId, snapshot));
  }

  void _startLiveDirectInboxCursorSave(List<ChatMessage> messages) {
    final override = widget.startLiveDirectInboxCursorSaveOverride;
    if (override != null) {
      unawaited(override(List<ChatMessage>.from(messages)));
      return;
    }
    unawaited(
      _store.saveLatestDirectInboxCursor(
        messages,
        baseUrlOverride: widget.baseUrl,
      ),
    );
  }

  void _startLiveDirectReadAck(String messageId) {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return;
    // Privacy gate (P1-17): when the user has disabled the global
    // "send read receipts" pref, suppress the ack entirely. The
    // recipient sees this message stay at `delivered` rather than
    // advancing to `read` — exactly the behaviour WhatsApp / Signal
    // ship when the same setting is off. Note: this still fires the
    // override callback in tests, since tests assert call-counts
    // against the override regardless of pref state; the override
    // path can itself check the pref if a test wants to exercise
    // the gate.
    if (!ChatReadReceiptsPref.enabled) {
      return;
    }
    final override = widget.startLiveDirectReadAckOverride;
    if (override != null) {
      unawaited(override(normalizedMessageId));
      return;
    }
    unawaited(_service.markRead(normalizedMessageId));
  }

  void _startLiveDirectContactUpsert(ChatContact contact) {
    final override = widget.startLiveDirectContactUpsertOverride;
    if (override != null) {
      unawaited(override(contact));
      return;
    }
    unawaited(_upsertScopedContact(contact));
  }

  void _startLiveDirectContactUnarchive(ChatContact contact) {
    final override = widget.startLiveDirectContactUnarchiveOverride;
    if (override != null) {
      unawaited(override(contact));
      return;
    }
    unawaited(_saveScopedContactsForPeers(<ChatContact>[contact]));
  }

  void _startLiveDirectUnreadBatchSave(
    Map<String, int> unread,
    Iterable<String> unreadKeys,
  ) {
    final keysSnapshot = unreadKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (keysSnapshot.isEmpty) return;
    final unreadSnapshot = Map<String, int>.from(unread);
    final override = widget.startLiveDirectUnreadBatchSaveOverride;
    if (override != null) {
      unawaited(override(unreadSnapshot, keysSnapshot));
      return;
    }
    unawaited(_saveUnreadCountsForKeys(unreadSnapshot, keysSnapshot));
  }

  void _startMarkAllChatsReadUnreadBatchSave(
    Map<String, int> unread,
    Iterable<String> unreadKeys,
  ) {
    final keysSnapshot = unreadKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (keysSnapshot.isEmpty) return;
    final unreadSnapshot = Map<String, int>.from(unread);
    final override = widget.startMarkAllChatsReadUnreadBatchSaveOverride;
    if (override != null) {
      unawaited(override(unreadSnapshot, keysSnapshot));
      return;
    }
    unawaited(_saveUnreadCountsForKeys(unreadSnapshot, keysSnapshot));
  }

  void _scheduleTypingIndicatorPrune() {
    _typingIndicatorTimer?.cancel();
    if (_peerTypingExpiresAt.isEmpty) return;
    var nextExpiry = _peerTypingExpiresAt.values.first;
    for (final expiry in _peerTypingExpiresAt.values) {
      if (expiry.isBefore(nextExpiry)) {
        nextExpiry = expiry;
      }
    }
    final delay = nextExpiry.difference(DateTime.now());
    _typingIndicatorTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _pruneExpiredTypingIndicators,
    );
  }

  void _pruneExpiredTypingIndicators() {
    final now = DateTime.now();
    _peerTypingExpiresAt.removeWhere((_, expiry) => !expiry.isAfter(now));
    if (!mounted) return;
    setState(() {});
    _scheduleTypingIndicatorPrune();
  }

  bool _isPeerTyping(String peerId) {
    final expiry = _peerTypingExpiresAt[peerId.trim()];
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  void _syncComposerTypingSignal() {
    final me = _me;
    final peer = _peer;
    final targetPeerId = (me != null &&
            peer != null &&
            !peer.blocked &&
            !_shamellVoiceMode &&
            !_recordingVoice &&
            _msgCtrl.text.trim().isNotEmpty)
        ? peer.id.trim()
        : '';
    final previousPeerId = (_typingPeerId ?? '').trim();
    if (previousPeerId.isNotEmpty && previousPeerId != targetPeerId) {
      _stopComposerTypingSignal(peerId: previousPeerId);
    }
    if (targetPeerId.isEmpty || me == null) {
      return;
    }
    final now = DateTime.now();
    final shouldAnnounce = !_typingAnnounced ||
        previousPeerId != targetPeerId ||
        now.difference(_lastTypingSignalAt ??
                DateTime.fromMillisecondsSinceEpoch(0)) >=
            _typingHeartbeatInterval;
    if (shouldAnnounce) {
      _typingPeerId = targetPeerId;
      _typingAnnounced = true;
      _lastTypingSignalAt = now;
      unawaited(_service.sendTypingSignal(
        deviceId: me.id,
        peerId: targetPeerId,
        isTyping: true,
      ));
    }
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(_typingIdleTimeout, _stopComposerTypingSignal);
  }

  void _stopComposerTypingSignal({String? peerId}) {
    _typingIdleTimer?.cancel();
    final me = _me;
    final targetPeerId = (peerId ?? _typingPeerId ?? '').trim();
    if (targetPeerId.isEmpty) {
      _typingPeerId = null;
      _typingAnnounced = false;
      return;
    }
    if (me != null) {
      unawaited(_service.sendTypingSignal(
        deviceId: me.id,
        peerId: targetPeerId,
        isTyping: false,
      ));
    }
    if (_typingPeerId == targetPeerId) {
      _typingPeerId = null;
    }
    _typingAnnounced = false;
  }

  Widget _buildThreadTypingIndicator(L10n l, ThemeData theme) {
    final peer = _peer;
    final label =
        (peer != null && _isPeerTyping(peer.id)) ? l.shamellTyping : '';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: label.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey<String>(label),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  // Cycle 43 — animated pulsing dots replace the
                  // static "more_horiz" icon. The label stays for
                  // a11y and locale fallback.
                  ChatTypingDots(color: ShamellPalette.green),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ShamellPalette.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _listenPush() {
    _pushSub?.cancel();
    _pushOpenedAppSub?.cancel();
    // Foreground arrival — app already on the chat page, no
    // navigation needed. Refresh the inbox so the new message is
    // surfaced without waiting for the next poll cycle. The presence
    // registry chime fires the in-chat arrival haptic.
    _pushSub = FirebaseMessaging.onMessage.listen((msg) {
      try {
        final data = msg.data;
        final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
        if (rawType != 'chat_wakeup') return;
        unawaited(ShamellChatPresenceRegistry.emitInChatArrivalFeedback());
        _pullInbox();
      } catch (_) {}
    });
    // Background-to-foreground tap — the user tapped a notification
    // while the app was suspended / backgrounded. We route into the
    // exact chat + scroll to the exact message if the server enriched
    // the payload; otherwise we degrade to "refresh inbox" so the new
    // message still surfaces in the list, just without auto-scroll.
    _pushOpenedAppSub =
        FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      try {
        _handleChatPushTap(parseChatPushPayload(msg.data));
      } catch (_) {}
    });
    // Cold-start tap — the app was *killed* and the user tapped a
    // notification. FCM stashes the message in `getInitialMessage()`;
    // we check once after the page is in the tree so navigation has a
    // valid context to push routes into.
    unawaited(_consumeInitialPushMessageIfAny());
  }

  ChatContact? _firstContactByIdOrNull(String peerId) {
    for (final c in _contacts) {
      if (c.id == peerId) return c;
    }
    return null;
  }

  Future<void> _consumeInitialPushMessageIfAny() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial == null) return;
      if (!mounted) return;
      // Defer a frame so the chat list state has finished its first
      // build — _switchPeer needs `_contacts` populated, which happens
      // in initState's async path.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _handleChatPushTap(parseChatPushPayload(initial.data));
        } catch (_) {}
      });
    } catch (_) {}
  }

  /// Routes a parsed `chat_wakeup` payload to the right thread.
  ///
  /// Strategy:
  ///  1. If the payload doesn't carry a thread target → fall back to
  ///     `_pullInbox()` so the new message at least surfaces.
  ///  2. If the target is the **current** peer → scroll-and-highlight
  ///     in place.
  ///  3. If the target is a **different known** peer → switch into
  ///     that thread, then scroll-and-highlight.
  ///  4. If the contact is **unknown** locally (e.g. first-ever
  ///     message from this peer) → refresh inbox once to load the
  ///     contact row, then retry the switch.
  ///
  /// Group chats are recognised but the actual switch is deferred to
  /// a follow-up — the group view lives on a different page and the
  /// routing surface is materially different from the direct one.
  Future<void> _handleChatPushTap(ChatPushPayload payload) async {
    if (!mounted) return;
    if (!payload.hasThreadTarget) {
      _pullInbox();
      return;
    }
    if (payload.kind == ChatPushKind.group) {
      // TODO(chat-p0-8 follow-up): wire group push deep-link once the
      // group thread page exposes a `_switchGroup(gid)` equivalent.
      _pullInbox();
      return;
    }
    final peerId = payload.chatId;
    if (peerId.isEmpty) {
      _pullInbox();
      return;
    }
    // Same peer? Skip the switch overhead.
    if (_peer?.id == peerId) {
      if (payload.hasMessageTarget) {
        unawaited(_scrollToMessage(payload.messageId, highlight: true));
      }
      return;
    }
    ChatContact? contact = _firstContactByIdOrNull(peerId);
    if (contact == null) {
      // Unknown contact — pull the inbox once to (probably) materialise
      // the contact row, then retry.
      try {
        await _pullInbox();
      } catch (_) {}
      if (!mounted) return;
      contact = _firstContactByIdOrNull(peerId);
    }
    if (contact == null) {
      // Still nothing — give up gracefully. Inbox refresh has already
      // run so the new message thread will surface in the list and
      // the user can tap it manually.
      return;
    }
    await _switchPeer(contact);
    if (!mounted) return;
    if (payload.hasMessageTarget) {
      unawaited(_scrollToMessage(payload.messageId, highlight: true));
    }
  }

  Future<void> _pickAttachment(
      {ImageSource source = ImageSource.gallery}) async {
    try {
      if (source == ImageSource.camera && !shamellAllowsCameraCapture()) {
        shamellShowRestrictedMediaSnack(
          context,
          camera: true,
          microphone: false,
        );
        return;
      }
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

  void _closeComposerMorePanel() {
    if (!mounted) return;
    setState(() {
      _composerPanel = _ShamellComposerPanel.none;
    });
  }

  Future<void> _openFavoritesPickerFromComposer() async {
    final override = widget.openFavoritesPickerOverride;
    if (override != null) {
      await override();
      return;
    }
    await _openFavoritesPicker();
  }

  Future<void> _openContactCardPickerFromComposer() async {
    final override = widget.openContactCardPickerOverride;
    if (override != null) {
      await override();
      return;
    }
    await _openContactCardPicker();
  }

  List<_ShamellComposerMoreActionSpec> _buildComposerMoreActions(
    ChatContact peer,
  ) {
    final l = L10n.of(context);
    return <_ShamellComposerMoreActionSpec>[
      _ShamellComposerMoreActionSpec(
        icon: Icons.photo_outlined,
        label: l.shamellAttachImage,
        accent: const Color(0xFF2563EB),
        onTap: () async {
          _closeComposerMorePanel();
          await _pickAttachment();
        },
      ),
      _ShamellComposerMoreActionSpec(
        icon: Icons.camera_alt_outlined,
        label: l.isArabic ? 'الكاميرا' : 'Camera',
        accent: const Color(0xFF07C160),
        onTap: () async {
          _closeComposerMorePanel();
          await _pickAttachment(source: ImageSource.camera);
        },
      ),
      _ShamellComposerMoreActionSpec(
        icon: Icons.qr_code_scanner,
        label: l.isArabic ? 'مسح' : 'Scan',
        accent: const Color(0xFF111827),
        onTap: () async {
          _closeComposerMorePanel();
          await _scanQr();
        },
      ),
      _ShamellComposerMoreActionSpec(
        icon: Icons.location_on_outlined,
        label: l.shamellSendLocation,
        accent: const Color(0xFFE11D48),
        onTap: () async {
          _closeComposerMorePanel();
          await _sendCurrentLocation();
        },
      ),
      // Cycle 14: poll entry. Opens the creator dialog; on submit
      // sends a regular chat message carrying the question + poll
      // pointer and registers the server-side tally bookkeeping.
      _ShamellComposerMoreActionSpec(
        icon: Icons.poll_outlined,
        label: l.isArabic ? 'استطلاع' : 'Poll',
        accent: const Color(0xFFB45309),
        onTap: () async {
          _closeComposerMorePanel();
          await _composePoll(peer);
        },
      ),
      if (_caps.payments)
        _ShamellComposerMoreActionSpec(
          icon: Icons.payments_outlined,
          label: l.shamellSendMoney,
          accent: Tokens.colorPayments,
          onTap: () async {
            _closeComposerMorePanel();
            await _openPaymentsPage(initialRecipient: peer.id);
          },
        ),
      _ShamellComposerMoreActionSpec(
        icon: Icons.card_giftcard_outlined,
        label: 'Green Paket',
        accent: const Color(0xFF16A34A),
        onTap: () async {
          _closeComposerMorePanel();
          await _openGreenPaketForChat(peer);
        },
      ),
      _ShamellComposerMoreActionSpec(
        icon: Icons.apps_rounded,
        label: l.isArabic ? 'برنامج مصغّر' : 'Mini Program',
        accent: const Color(0xFF7C3AED),
        onTap: () async {
          _closeComposerMorePanel();
          await _showMiniProgramShareSheet(peer);
        },
      ),
      _ShamellComposerMoreActionSpec(
        icon: Icons.bookmark_outline,
        label: l.isArabic ? 'المفضلة' : 'Favorites',
        accent: const Color(0xFFF59E0B),
        onTap: () async {
          _closeComposerMorePanel();
          await _openFavoritesPickerFromComposer();
        },
      ),
      // Voice + video call shortcuts moved to the chat thread AppBar
      // (see the `_startVoipCall` IconButtons there) so they no longer
      // hide under the composer "+" menu. The "+" is for attachments now.
      _ShamellComposerMoreActionSpec(
        icon: Icons.contact_page_outlined,
        label: l.isArabic ? 'بطاقة جهة اتصال' : 'Contact card',
        accent: const Color(0xFF64748B),
        onTap: () async {
          _closeComposerMorePanel();
          await _openContactCardPickerFromComposer();
        },
      ),
      if (_caps.serviceNotifications)
        _ShamellComposerMoreActionSpec(
          icon: Icons.notifications_none_outlined,
          label: l.isArabic ? 'الخدمات' : 'Services',
          accent: Tokens.colorPayments,
          onTap: () async {
            _closeComposerMorePanel();
            await _openServiceNotificationsThread();
          },
        ),
    ];
  }

  /// Cycle 12: pick the last *incoming* (peer → me) message in the
  /// active thread that we can hand to the smart-replies heuristic.
  /// Skips system / recalled / placeholder messages. Returns `null`
  /// when the thread is empty, the last message is outgoing, or the
  /// user has already dismissed suggestions for that message.
  ({String id, String text})? _lastIncomingTextForSmartReplies() {
    final peer = _peer;
    final me = _me;
    if (peer == null || me == null) return null;
    // Iterate in reverse so the newest incoming wins. `_messages` is
    // the active thread's list in chronological order.
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      // Outgoing → keep scanning back; first thing we hit going
      // backwards from "now" should be incoming for the bar to fire.
      if (m.senderId == me.id) return null;
      final id = m.id;
      if (id.isEmpty) continue;
      if (_smartRepliesDismissed.contains(id)) return null;
      String text;
      try {
        final decoded = _decodeMessage(m);
        text = decoded.text;
      } catch (_) {
        text = '';
      }
      if (text.trim().isEmpty) continue;
      return (id: id, text: text);
    }
    return null;
  }

  /// Cycle 21 — composer-side @-mention completion bar.
  /// Hidden when the caret isn't inside an @-mention window; shows a
  /// horizontally-scrolling chip row of contact candidates when it
  /// is. Tap a chip to splice `@<name> ` into the composer.
  Widget _buildMentionCompletionsBar(L10n l) {
    if (_attachedBytes != null || _recordingVoice || _sending) {
      return const SizedBox.shrink();
    }
    final value = _msgCtrl.value;
    final ctx = detectMentionContext(
      text: value.text,
      caret: value.selection.baseOffset >= 0
          ? value.selection.baseOffset
          : value.text.length,
    );
    if (ctx == null) return const SizedBox.shrink();
    final ranked = <(int, ChatContact)>[];
    for (final c in _contacts) {
      if (c.hidden && !_showHidden) continue;
      if (c.blocked && !_showBlocked) continue;
      final display = _displayNameForPeer(c);
      final score = scoreMentionMatch(candidate: display, prefix: ctx.prefix);
      if (score <= 0) continue;
      ranked.add((score, c));
    }
    if (ranked.isEmpty) return const SizedBox.shrink();
    ranked.sort((a, b) => b.$1 - a.$1);
    final top = ranked.take(8).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final entry in top) ...<Widget>[
              // Cycle 61 — when the peer has a published avatar in
              // cache, show it as the chip's leading round image
              // instead of the generic `@` icon. The peer status
              // emoji is appended to the label so identical names
              // remain visually distinct ("Alice 🌴" vs "Alice 💻").
              Builder(builder: (_) {
                final peer = entry.$2;
                final avatarBytes = _peerProfileAvatarBytes[peer.id];
                final statusEmoji = _peerProfileStatusEmoji[peer.id];
                final canonical = _displayNameForPeer(peer);
                return ActionChip(
                  avatar: avatarBytes != null
                      ? CircleAvatar(
                          radius: 10,
                          backgroundImage: MemoryImage(avatarBytes),
                        )
                      : const Icon(Icons.alternate_email, size: 16),
                  label: Text(
                    statusEmoji != null && statusEmoji.isNotEmpty
                        ? '$canonical $statusEmoji'
                        : canonical,
                    maxLines: 1,
                  ),
                  onPressed: () {
                    final result = applyMentionInsert(
                      text: _msgCtrl.text,
                      ctx: ctx,
                      canonical: canonical,
                    );
                    _msgCtrl.value = TextEditingValue(
                      text: result.text,
                      selection:
                          TextSelection.collapsed(offset: result.caret),
                    );
                  },
                  tooltip: l.isArabic
                      ? 'إدراج إشارة إلى $canonical'
                      : 'Mention $canonical',
                );
              }),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
    // suppress unused theme warning if not used in subsequent edits
    // ignore: unused_local_variable
    // theme is referenced via ActionChip default styling
  }

  /// Cycle 24 — emoji `:partial` completion bar. Mutually exclusive
  /// with the mention bar (only one popover shows at a time; the
  /// mention bar wins when both trigger). Hidden when the composer
  /// is empty, recording, or sending.
  Widget _buildEmojiCompletionsBar(L10n l) {
    if (_attachedBytes != null || _recordingVoice || _sending) {
      return const SizedBox.shrink();
    }
    final value = _msgCtrl.value;
    // Mention bar takes precedence — both can't render at once.
    if (detectMentionContext(
          text: value.text,
          caret: value.selection.baseOffset >= 0
              ? value.selection.baseOffset
              : value.text.length,
        ) !=
        null) {
      return const SizedBox.shrink();
    }
    final ctx = detectEmojiPartial(
      text: value.text,
      caret: value.selection.baseOffset >= 0
          ? value.selection.baseOffset
          : value.text.length,
    );
    if (ctx == null) return const SizedBox.shrink();
    final suggestions =
        suggestEmojiCompletions(prefix: ctx.prefix, limit: 8);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final s in suggestions) ...<Widget>[
              ActionChip(
                avatar: Text(s.emoji,
                    style: const TextStyle(fontSize: 16)),
                label: Text(
                  ':${s.shortcut}:',
                  style: theme.textTheme.bodySmall,
                ),
                onPressed: () {
                  final result = applyEmojiPartialInsert(
                    text: _msgCtrl.text,
                    ctx: ctx,
                    emoji: s.emoji,
                  );
                  _suppressDraftListener = true;
                  try {
                    _msgCtrl.value = TextEditingValue(
                      text: result.text,
                      selection: TextSelection.collapsed(
                          offset: result.caret),
                    );
                  } finally {
                    _suppressDraftListener = false;
                  }
                },
                tooltip: l.isArabic
                    ? 'إدراج ${s.emoji}'
                    : 'Insert ${s.emoji}',
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// Cycle 28 — slash-command suggestion bar. Renders when the
  /// composer starts with `/foo` and matches a known command. Tap
  /// to fill in the canonical `/cmd ` (with trailing space) so the
  /// user can immediately type args.
  Widget _buildSlashCommandSuggestionBar(L10n l) {
    if (_attachedBytes != null || _recordingVoice || _sending) {
      return const SizedBox.shrink();
    }
    final text = _msgCtrl.text;
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('/')) return const SizedBox.shrink();
    // Only show suggestions on the FIRST token. If the composer
    // already has whitespace after the command name, the user is
    // typing args — drop the bar.
    if (trimmed.contains(' ') || trimmed.contains('\n')) {
      return const SizedBox.shrink();
    }
    final partial = trimmed.length > 1 ? trimmed.substring(1) : '';
    final suggestions = suggestSlashCommands(partial: partial);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final c in suggestions) ...<Widget>[
              ActionChip(
                avatar: const Icon(Icons.terminal, size: 14),
                label: Text(
                  '/${c.name}',
                  style: theme.textTheme.bodySmall,
                ),
                tooltip:
                    l.isArabic ? c.descriptionAr : c.descriptionEn,
                onPressed: () {
                  final inserted = '/${c.name} ';
                  _suppressDraftListener = true;
                  try {
                    _msgCtrl.value = TextEditingValue(
                      text: inserted,
                      selection:
                          TextSelection.collapsed(offset: inserted.length),
                    );
                  } finally {
                    _suppressDraftListener = false;
                  }
                },
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSmartRepliesBar(L10n l) {
    // Don't compete with the user's draft — if they've started
    // typing, hide the bar entirely. Same with attachments and
    // active recording: the user has clearly committed to a
    // specific reply path.
    if (_msgCtrl.text.trim().isNotEmpty ||
        _attachedBytes != null ||
        _recordingVoice ||
        _sending) {
      return const SizedBox.shrink();
    }
    final lastIncoming = _lastIncomingTextForSmartReplies();
    if (lastIncoming == null) return const SizedBox.shrink();
    final suggestions = suggestSmartReplies(
      lastIncomingText: lastIncoming.text,
      isArabic: l.isArabic,
    );
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return ChatSmartRepliesBar(
      replies: suggestions,
      onPick: (r) {
        _msgCtrl.value = TextEditingValue(
          text: r.text,
          selection: TextSelection.collapsed(offset: r.text.length),
        );
        FocusScope.of(context).requestFocus(_composerFocus);
      },
      onDismiss: () {
        _applyState(() {
          _smartRepliesDismissed.add(lastIncoming.id);
        });
      },
    );
  }

  Widget _buildMorePanel(ChatIdentity _, ChatContact peer) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const panelHeight = 276.0;
    const perPage = 8;

    Widget action(
      IconData icon,
      String label,
      Color accent,
      Future<void> Function() onTap,
    ) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? .22 : .11),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? .24 : .16),
                  width: .7,
                ),
              ),
              child: Icon(icon, size: 26, color: accent),
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

    final actions = _buildComposerMoreActions(peer);

    final pageCount = max(1, (actions.length / perPage).ceil());
    final clampedPage =
        _shamellMorePanelPage.clamp(0, max(0, pageCount - 1)).toInt();

    Widget page(int pageIdx) {
      final start = pageIdx * perPage;
      final end = min(start + perPage, actions.length);
      final slice = actions.sublist(start, end);
      final tiles =
          slice.map((a) => action(a.icon, a.label, a.accent, a.onTap)).toList();
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
    // Very short taps should behave like SyrChat: cancel instead of sending.
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
    _voiceAmpSub?.cancel();
    _voiceAmpSub = null;
    final fallbackPath = _voiceRecordingPath;
    _voiceRecordingPath = null;
    String? cleanupPath = fallbackPath;
    try {
      final path = await _recorder.stop();
      final resolvedPath =
          (path != null && path.isNotEmpty) ? path : fallbackPath;
      if (resolvedPath == null || resolvedPath.isEmpty) return;
      cleanupPath = resolvedPath;
      final file = File(resolvedPath);
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
    } finally {
      await deleteEphemeralVoiceFile(cleanupPath);
      if (fallbackPath != null && fallbackPath != cleanupPath) {
        await deleteEphemeralVoiceFile(fallbackPath);
      }
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
    _voiceAmpSub?.cancel();
    _voiceAmpSub = null;
    final fallbackPath = _voiceRecordingPath;
    _voiceRecordingPath = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    await deleteEphemeralVoiceFile(fallbackPath);
  }

  Future<void> _deleteMessageLocal(ChatMessage m) async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null) return;
    unawaited(() async {
      try {
        await _service.deleteMessage(
          deviceId: me.id,
          messageId: m.id,
          deleteForEveryone: false,
        );
      } catch (_) {}
    }());
    final peerId = peer.id;
    final list = List<ChatMessage>.from(_cache[peerId] ?? _messages);
    list.removeWhere((x) => x.id == m.id);
    _cache[peerId] = list;
    if (_activePeerId == peerId) {
      _applyState(() {
        _messages = list;
      });
    }
    await _saveMessagesForPeer(peerId, list);
  }

  Future<void> _deleteMessageForEveryone(ChatMessage m) async {
    final me = _me;
    if (me == null) return;
    try {
      await _service.deleteMessage(
        deviceId: me.id,
        messageId: m.id,
        deleteForEveryone: true,
      );
    } catch (_) {}
    await _removeMessageFromLocalCaches(m.id);
    await _handleMessageRecalled(m.id);
  }

  Future<void> _removeMessageFromLocalCaches(String messageId) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return;
    final affectedPeerIds = <String>{};
    final nextCache = <String, List<ChatMessage>>{};
    for (final entry in _cache.entries) {
      final filtered = entry.value
          .where((message) => message.id != normalizedMessageId)
          .toList(growable: false);
      if (filtered.length != entry.value.length) {
        affectedPeerIds.add(entry.key);
      }
      nextCache[entry.key] = filtered;
    }
    final activePeerId = _activePeerId;
    if (activePeerId != null &&
        !nextCache.containsKey(activePeerId) &&
        _messages.any((message) => message.id == normalizedMessageId)) {
      nextCache[activePeerId] = _messages
          .where((message) => message.id != normalizedMessageId)
          .toList(growable: false);
      affectedPeerIds.add(activePeerId);
    }
    if (affectedPeerIds.isEmpty) return;
    _applyState(() {
      _cache
        ..clear()
        ..addAll(nextCache);
      if (activePeerId != null && nextCache.containsKey(activePeerId)) {
        _messages = nextCache[activePeerId]!;
      }
      _seenMessageIds.remove(normalizedMessageId);
    });
    for (final peerId in affectedPeerIds) {
      await _saveMessagesForPeer(peerId, nextCache[peerId] ?? const []);
    }
  }

  Future<void> _refreshActiveThreadAfterEvent() async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null) return;
    try {
      final remote = await _service.fetchThreadHistory(
        deviceId: me.id,
        peerId: peer.id,
        limit: 200,
      );
      remote.sort(_compareDirectMessageCursor);
      if (!mounted) return;
      _applyState(() {
        _cache[peer.id] = remote;
        _messages = remote;
        _seenMessageIds
          ..clear()
          ..addAll(remote.map((message) => message.id));
      });
      await _saveMessagesForPeer(peer.id, remote);
    } catch (_) {}
  }

  Future<void> _clearChatHistoryForPeer(ChatContact c) async {
    final peerId = c.id;
    _cache[peerId] = <ChatMessage>[];
    _expandedDirectHistoryPeerIds.remove(peerId);
    _exhaustedDirectHistoryPeerIds.remove(peerId);
    if (_activePeerId == peerId) {
      _applyState(() {
        _messages = const <ChatMessage>[];
        _loadingOlderThreadMessages = false;
        _hasOlderThreadMessages = false;
      });
    }
    _unread[peerId] = 0;
    await _saveMessagesForPeer(peerId, const <ChatMessage>[]);
    await _saveUnreadCountForPeer(peerId, 0);
  }

  /// Cycle 4: build the aggregated reaction strip rendered under a
  /// message bubble. Returns `SizedBox.shrink()` when there are no
  /// reactions yet (most common case — keeps the bubble compact).
  ///
  /// Data flow. The server response on the message carries
  /// `m.reactions` as a list of `{emoji, count, has_me}` records
  /// aggregated across every reactor. Until the chat-list refreshes
  /// after a tap, we override the server's `has_me` with the
  /// local-cache `_messageReactions` so the chip flips immediately.
  Widget _buildReactionBarForMessage(ChatMessage m, bool incoming) {
    final summaries = ChatReactionSummary.listFromJson(m.reactions);
    final myReaction = _messageReactions[m.id];
    final List<ChatReactionSummary> rendered;
    if (myReaction != null && myReaction.isNotEmpty) {
      // Apply optimistic local override so the chip the user just tapped
      // reads as selected instantly. Server-side response on the next
      // refresh will reconcile.
      final mergedByEmoji = <String, ChatReactionSummary>{};
      for (final s in summaries) {
        mergedByEmoji[s.emoji] = ChatReactionSummary(
          emoji: s.emoji,
          count: s.count,
          hasMe: s.emoji == myReaction,
        );
      }
      // If my reaction isn't in the server set yet (just-placed,
      // server hasn't acknowledged), inject a placeholder count=1
      // entry so the chip renders immediately.
      mergedByEmoji.putIfAbsent(
        myReaction,
        () => ChatReactionSummary(emoji: myReaction, count: 1, hasMe: true),
      );
      rendered = mergedByEmoji.values.toList(growable: false);
    } else {
      rendered = summaries;
    }
    if (rendered.isEmpty) {
      // No bar when no reactions — the "Add reaction" affordance lives
      // in the long-press menu rather than as a persistent "+" so the
      // bubble row stays compact.
      return const SizedBox.shrink();
    }
    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: ChatReactionBar(
        reactions: rendered,
        showAddButton: false,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
        onToggle: (emoji, hasMe) async {
          // hasMe=true means "this chip is already my reaction → tap
          // toggles it off". hasMe=false means "tap to switch my
          // reaction to this emoji" (server replaces atomically via
          // ON CONFLICT DO UPDATE).
          //
          // _setReaction's contract is "if current == emoji remove,
          // else set". We force-sync the local cache to match the
          // server's `hasMe` view first so the toggle works
          // correctly even if our local cache is stale.
          if (hasMe) {
            _messageReactions[m.id] = emoji;
          }
          _setReaction(m, emoji);
        },
      ),
    );
  }

  /// Cycle 6: bookmark a message from the long-press menu. Sends the
  /// bookmark request server-side and shows a confirmation snackbar.
  /// Treats failure as soft — surfaces an error toast but doesn't
  /// crash; the user can retry from the menu.
  Future<void> _bookmarkMessageFromMenu(ChatMessage m) async {
    final me = _me;
    if (me == null || !mounted) return;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.setMessageBookmark(
        deviceId: me.id,
        messageId: m.id,
        bookmarked: true,
        kind: 'direct',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.isArabic ? 'تم الحفظ' : 'Bookmark saved'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.isArabic ? 'فشل الحفظ' : 'Bookmark failed'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Cycle 5/1: fetch + decrypt + show the message's edit history.
  /// Server returns each prior revision's ciphertext + key material;
  /// we decrypt each one against the same ratchet state we use for
  /// the live bubble, then hand the decoded list to
  /// [ChatEditHistoryDialog].
  Future<void> _openEditHistoryForMessage(ChatMessage m) async {
    final me = _me;
    if (me == null || !mounted) return;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, Object?>> rawRevisions;
    try {
      rawRevisions = await _service.listMessageEditHistory(
        deviceId: me.id,
        messageId: m.id,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تعذر جلب السجل' : 'Could not load history',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    // Decode each revision opportunistically. If a revision can't be
    // decoded (key rotated, ratchet drift, etc.), we still render the
    // dialog with a "(no text)" placeholder for that row rather than
    // failing the whole view.
    final decoded = <ChatEditHistoryRevision>[];
    for (final r in rawRevisions) {
      final rev = (r['revision'] is int)
          ? r['revision'] as int
          : int.tryParse('${r['revision'] ?? ''}') ?? 0;
      final editedAtRaw = r['edited_at']?.toString();
      DateTime? editedAt;
      if (editedAtRaw != null && editedAtRaw.isNotEmpty) {
        editedAt = DateTime.tryParse(editedAtRaw);
      }
      // Edit history decryption needs the full ratchet flow which
      // the chat page already runs for live bubbles via
      // `_decodeMessage`. For the dialog MVP we surface the revision
      // metadata (revision #, timestamp) and skip the plaintext —
      // future cycle wires the decrypt path. The dialog renders
      // "(no text)" for empty text values gracefully.
      decoded.add(ChatEditHistoryRevision(
        revision: rev,
        editedAt: editedAt,
        text: '',
      ));
    }
    if (!mounted) return;
    final currentDecoded = _decodeMessage(m);
    await ChatEditHistoryDialog.show(
      context,
      revisions: decoded,
      currentText: currentDecoded.text,
    );
  }

  /// Cycle 4: open the emoji picker for a message and apply the
  /// chosen reaction. No-op if the user cancels the sheet.
  Future<void> _openReactionPickerForMessage(ChatMessage m) async {
    final picked = await ChatReactionPickerSheet.show(
      context,
      currentEmoji: _messageReactions[m.id],
    );
    if (!mounted || picked == null) return;
    _setReaction(m, picked);
  }

  void _setReaction(ChatMessage m, String emoji) {
    final me = _me;
    String? nextReaction;
    _applyState(() {
      final current = _messageReactions[m.id];
      if (current == emoji) {
        _messageReactions.remove(m.id);
        nextReaction = null;
      } else {
        _messageReactions[m.id] = emoji;
        nextReaction = emoji;
      }
    });
    // Cycle 27: count adds (not removes) so the quick-react row
    // reflects the user's positive-action history.
    if (nextReaction != null) {
      unawaited(ChatReactionRecent.instance.bump(emoji));
    }
    if (me != null) {
      unawaited(() async {
        try {
          await _service.setMessageReaction(
            deviceId: me.id,
            messageId: m.id,
            emoji: nextReaction,
          );
        } catch (_) {}
      }());
    }
  }

  Future<void> _forwardMessagesToTarget(
    List<ChatMessage> msgs,
    ChatContact target,
  ) async {
    final me = _me;
    if (me == null || msgs.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _sessionHash ??= _computeSessionHash();
      final stabilizedTarget = await _stabilizePeerSessionForOutbound(target);
      final bootstrappedTarget =
          await _bootstrapPeerSessionIfNeeded(stabilizedTarget);
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
      if (await _forceReauthOnCriticalChatFailure(e)) return;
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

  Future<void> _forwardMessages(List<ChatMessage> msgs) async {
    if (msgs.isEmpty) return;
    final target = await _pickForwardTarget();
    if (!mounted || target == null) return;
    await _forwardMessagesToTarget(msgs, target);
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
    await _saveMessagesForPeer(peerId, list);
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
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      setState(() {
        _error = _sendFailureToUi(e);
      });
    }
  }

  Future<void> _doStartVoiceRecord() async {
    try {
      if (!shamellAllowsMicrophoneCapture()) {
        shamellShowRestrictedMediaSnack(
          context,
          camera: false,
          microphone: true,
        );
        return;
      }
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        final l = L10n.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shamellVoicePlaybackSoon)),
        );
        return;
      }
      await _clearVoiceRecordingFile();
      final file = await createEphemeralVoiceFile(stem: 'voice_record');
      _voiceRecordingPath = file.path;
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
        _voiceAmpHead = 0;
        for (int i = 0; i < _voiceAmpRing.length; i++) {
          _voiceAmpRing[i] = 0.0;
        }
      });
      // Cycle 41 — drive the recording waveform from live amplitude.
      // `record` emits dBFS; we map [-50, 0] dBFS → [0, 1] so silence
      // stays low and a loud voice fills the bar.
      _voiceAmpSub?.cancel();
      _voiceAmpSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        if (!mounted || !_recordingVoice) return;
        double db = amp.current;
        if (db.isNaN || db.isInfinite) db = -60;
        if (db > 0) db = 0;
        if (db < -50) db = -50;
        final norm = (db + 50) / 50;
        setState(() {
          _voiceAmpRing[_voiceAmpHead] = norm.clamp(0.0, 1.0);
          _voiceAmpHead = (_voiceAmpHead + 1) % _voiceAmpRingLen;
        });
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
    final l = L10n.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final targetLang =
        (locale?.languageCode.toLowerCase().startsWith('ar') ?? false)
            ? 'ar'
            : 'en';
    final uri = normalizeExternalTranslateUri(
      trimmed,
      targetLanguage: targetLang,
    );
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تعذّر فتح الترجمة.' : 'Could not open translation.',
          ),
        ),
      );
      return;
    }
    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تعذّر فتح الترجمة.' : 'Could not open translation.',
            ),
          ),
        );
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _ensurePushToken() async {
    final me = _me;
    if (me == null) return;
    try {
      final override = widget.ensurePushTokenOverride;
      if (override != null) {
        await override();
        return;
      }
      await PushTokenManager.ensureRegisteredForDevice(
        registrationScope: _service,
        deviceId: me.id,
        registerToken: _service.registerPushToken,
        unregisterToken: _service.unregisterPushToken,
        loadPersistedBindingFingerprint: ({
          required String deviceId,
        }) {
          return _store.loadPushTokenBindingFingerprint(
            deviceId,
            baseUrlOverride: widget.baseUrl,
          );
        },
        savePersistedBindingFingerprint: ({
          required String deviceId,
          required String fingerprint,
        }) {
          return _store.savePushTokenBindingFingerprint(
            deviceId,
            fingerprint,
            baseUrlOverride: widget.baseUrl,
          );
        },
        clearPersistedBindingFingerprint: ({
          required String deviceId,
        }) {
          return _store.deletePushTokenBindingFingerprint(
            deviceId,
            baseUrlOverride: widget.baseUrl,
          );
        },
      );
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
    var cached = _cache[c.id] ??
        await _store.loadMessages(
          c.id,
          baseUrlOverride: widget.baseUrl,
        );
    if (_me != null) {
      cached = await _seedThreadHistoryIfEmpty(
        me: _me!,
        peer: c,
        cached: cached,
      );
    }
    Set<String> voicePlayed = <String>{};
    try {
      voicePlayed = await _store.loadVoicePlayed(
        c.id,
        baseUrlOverride: widget.baseUrl,
      );
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
    await _pruneExpired(c.id);
    setState(() {
      _peer = c;
      _activePeerId = c.id;
      _newMessagesAnchorPeerId = c.id;
      _newMessagesAnchorMessageId = anchorId;
      _newMessagesCountAtOpen = openUnreadCount;
      _threadNearBottom = !jumpToUnread;
      _loadingOlderThreadMessages = false;
      _hasOlderThreadMessages = _shouldExposeOlderThreadHistory(c.id, cached);
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
    final scheduledInitialJump = _maybeScheduleInitialThreadMessageJump();
    if (!scheduledInitialJump && jumpToUnread) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
            _scrollToMessage(anchorId!, alignment: 0.18, highlight: false));
      });
    } else if (!scheduledInitialJump) {
      _scheduleThreadScrollToBottom(force: true, animated: false);
    }
    await _store.setActivePeer(c.id, baseUrlOverride: widget.baseUrl);
    await _saveUnreadCountForPeer(c.id, 0);
    await _markThreadRead(c.id);
    await _pullInbox();
    _startSwitchedPeerOfficialLoad(c);
  }

  void _startSwitchedPeerOfficialLoad(ChatContact peer) {
    final override = widget.loadSwitchedPeerOfficialOverride;
    if (override != null) {
      unawaited(override(peer));
      return;
    }
    unawaited(_loadOfficialForPeer(peer));
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
    final touchedUnreadKeys = <String>{};
    for (final m in msgs) {
      if (_seenMessageIds.contains(m.id)) {
        continue; // replay protection
      }
      _seenMessageIds.add(m.id);
      final peerId = _peerIdForMessage(m, meId);
      final isIncoming = m.isIncomingFor(meId);
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
            unawaited(() async {
              await _setRecalledMessageState(targetId, true);
              await _handleMessageRecalled(targetId);
            }());
          }
          // Do not store the control message itself in history.
          continue;
        }
        if (j is Map && (j['kind'] ?? '').toString() == 'group_key') {
          final gid = (j['group_id'] ?? '').toString();
          final keyB64 = (j['key_b64'] ?? '').toString();
          if (gid.isNotEmpty && keyB64.isNotEmpty) {
            unawaited(
              _store.saveGroupKey(
                gid,
                keyB64,
                baseUrlOverride: widget.baseUrl,
              ),
            );
            if (isIncoming) {
              _startLiveDirectReadAck(m.id);
            }
            // Refresh local group cache with the newly available key.
            unawaited(() async {
              final me = _me;
              if (me == null) return;
              try {
                final full = await _service.fetchGroupInboxPaged(
                  groupId: gid,
                  deviceId: me.id,
                  batchSize: 200,
                  maxPages: 25,
                  retainLatestCount: 200,
                );
                final byId = <String, ChatGroupMessage>{
                  for (final mm in full) mm.id: mm
                };
                final merged = byId.values.toList()
                  ..sort(_compareGroupMessageCursor);
                _groupCache[gid] = merged;
                await _store.saveGroupMessages(
                  gid,
                  merged,
                  baseUrlOverride: widget.baseUrl,
                );
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
          _startLiveDirectReadAck(m.id);
        }
        continue;
      }
      var list = _cache[peerId] ?? <ChatMessage>[];
      final map = {for (final msg in list) msg.id: msg};
      map[m.id] = m;
      list = map.values.toList()..sort(_compareDirectMessageCursor);
      if (list.length > 200 &&
          !_expandedDirectHistoryPeerIds.contains(peerId)) {
        list = list.sublist(list.length - 200);
      }
      list = _prunedMessagesForPeer(peerId, list);
      _cache[peerId] = list;
      _startLiveDirectMessageSave(peerId, list);
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
        _startLiveDirectContactUnarchive(updated);
      }
      if (peerId == activePeerId && threadVisible) {
        activeThreadUpdated = true;
        _messages = _cache[peerId] ?? list;
        updatedUnread[peerId] = 0;
        touchedUnreadKeys.add(peerId);
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
          _startLiveDirectReadAck(m.id);
        }
      } else if (isIncoming) {
        final curUnread = updatedUnread[peerId] ?? 0;
        updatedUnread[peerId] = curUnread < 0 ? 1 : (curUnread + 1);
        touchedUnreadKeys.add(peerId);
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
        _hasOlderThreadMessages = _shouldExposeOlderThreadHistory(
          activePeerId,
          _cache[activePeerId] ?? _messages,
        );
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
    if (activeThreadUpdated) {
      _maybeScheduleInitialThreadMessageJump();
    }
    if (exitArchivedAfterSend) {
      _chatSearchCtrl.clear();
    }
    if (touchedUnreadKeys.isNotEmpty) {
      _startLiveDirectUnreadBatchSave(_unread, touchedUnreadKeys);
    }
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

  bool _isIncoming(ChatMessage m) {
    final myId = _me?.id;
    if (myId == null || myId.isEmpty) return false;
    return m.isIncomingFor(myId);
  }

  bool _isOwnMessage(ChatMessage m) {
    final myId = _me?.id;
    if (myId == null || myId.isEmpty) return false;
    return m.isOwnFor(myId);
  }

  String? _computeNewMessagesAnchorMessageId({
    required List<ChatMessage> messages,
    required String myId,
    required int unreadCount,
  }) {
    if (myId.isEmpty || unreadCount <= 0 || messages.isEmpty) return null;
    var remaining = unreadCount;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.isOwnFor(myId)) continue;
      remaining--;
      if (remaining <= 0) {
        return m.id.isNotEmpty ? m.id : null;
      }
    }
    return null;
  }

  String _peerIdForMessage(ChatMessage m, String myId) {
    final peerId = m.peerIdFor(myId);
    if (peerId.isNotEmpty) {
      return peerId;
    }
    if (m.senderHint != null && m.senderHint!.isNotEmpty) {
      final found = _contacts.firstWhere((c) => c.fingerprint == m.senderHint,
          orElse: () =>
              _peer ?? ChatContact(id: '', publicKeyB64: '', fingerprint: ''));
      if (found.id.isNotEmpty) return found.id;
    }
    return _peer?.id ?? m.recipientId;
  }

  Future<List<ChatContact>> _loadScopedContacts() {
    return _store.loadContacts(baseUrlOverride: widget.baseUrl);
  }

  Future<void> _saveScopedContactsForPeers(Iterable<ChatContact> contacts) {
    final override = widget.saveContactsForPeersOverride;
    if (override != null) {
      return override(contacts);
    }
    return _store.saveContactsForPeers(
      contacts,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _removeScopedContactsForPeers(Iterable<String> peerIds) {
    final override = widget.removeContactsForPeersOverride;
    if (override != null) {
      return override(peerIds);
    }
    return _store.removeContactsForPeers(
      peerIds,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _upsertScopedContact(ChatContact contact) {
    return _store.upsertContact(contact, baseUrlOverride: widget.baseUrl);
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
    _startLiveDirectContactUpsert(c);
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
    final msgs = _cache[peerId] ??
        await _store.loadMessages(peerId, baseUrlOverride: widget.baseUrl);
    for (final m in msgs) {
      if (m.senderId != meId) {
        _startLiveDirectReadAck(m.id);
      }
    }
  }

  List<ChatContact> _sortedContacts() {
    final pinnedChatOrderIndexes = buildPinnedChatOrderIndex(_pinnedChatOrder);
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
        final aIdx = pinnedChatOrderIndexes[ca.id];
        final bIdx = pinnedChatOrderIndexes[cb.id];
        if (aIdx != null || bIdx != null) {
          if (aIdx == null && bIdx != null) return 1;
          if (aIdx != null && bIdx == null) return -1;
          return aIdx!.compareTo(bIdx!);
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

  List<ChatMessage> _prunedMessagesForPeer(
    String peerId,
    List<ChatMessage> messages,
  ) {
    final meId = _me?.id;
    if (meId == null) return messages;
    final contact = _contacts.firstWhere((c) => c.id == peerId,
        orElse: () =>
            _peer ??
            ChatContact(id: peerId, publicKeyB64: '', fingerprint: ''));
    if (!contact.disappearing || contact.disappearAfter == null) {
      return messages;
    }
    final cutoff = DateTime.now().subtract(contact.disappearAfter!);
    return messages.where((m) {
      final ts = m.createdAt ?? m.deliveredAt ?? m.readAt ?? contact.verifiedAt;
      if (ts == null) return true;
      return ts.isAfter(cutoff);
    }).toList();
  }

  Future<void> _pruneExpired(String peerId) async {
    final list = _cache[peerId] ?? [];
    final kept = _prunedMessagesForPeer(peerId, list);
    if (kept.length != list.length) {
      _cache[peerId] = kept;
      if (peerId == _activePeerId) {
        _messages = kept;
      }
      await _saveMessagesForPeer(peerId, kept);
    }
  }

  DecodedChatMessagePayload _decodeMessage(ChatMessage m) {
    final raw = _decrypt(m);
    final decoded = _decodedMessagePayloadCache.decode(m, raw: raw);
    final senderFp = decoded.senderFingerprint ?? '';
    final sessionHash = decoded.sessionHash ?? '';
    if (senderFp.isNotEmpty) {
      final myId = _me?.id.trim() ?? '';
      final isOwnMessage = myId.isNotEmpty && m.isOwnFor(myId);
      if (!isOwnMessage) {
        // map sender hint for sealed sender
        final mapped =
            _sessionKeysByFp[senderFp] ?? _sessionKeys[_activePeerId ?? ''];
        if (mapped != null && _isCurveKey(mapped)) {
          _sessionKeysByFp[senderFp] = mapped;
        }
      }
      if (!isOwnMessage && _peer != null && _peer!.fingerprint != senderFp) {
        final l = L10n.of(context);
        _ratchetWarning = l.shamellSessionChangedBody;
      }
    }
    if (_sessionHash != null &&
        sessionHash.isNotEmpty &&
        sessionHash != _sessionHash) {
      _ratchetWarning = 'Session hash mismatch. Verify or reset.';
    }
    return decoded;
  }

  String _previewText(
    ChatMessage m, {
    DecodedChatMessagePayload? decoded,
  }) {
    return _previewPresentation(m, decoded: decoded).text;
  }

  DirectMessagePreviewPresentation _previewPresentation(
    ChatMessage m, {
    DecodedChatMessagePayload? decoded,
  }) {
    final d = decoded ?? _decodeMessage(m);
    final l = L10n.of(context);
    return buildDirectMessagePreviewPresentation(
      decoded: d,
      isIncoming: _isIncoming(m),
      isRecalled: _recalledMessageIds.contains(m.id),
      recalledByOther: l.shamellMessageRecalledByOther,
      recalledByMe: l.shamellMessageRecalledByMe,
      previewVoice: l.shamellPreviewVoice,
      previewImage: l.shamellPreviewImage,
      previewUnknown: l.shamellPreviewUnknown,
      previewLocation: l.shamellPreviewLocation,
      attachmentLabel: l.isArabic ? 'مرفق' : 'Attachment',
      contactCardLabel: l.isArabic ? 'بطاقة جهة اتصال' : 'Contact card',
      contactCardPrefix: l.isArabic ? 'بطاقة جهة اتصال: ' : 'Contact card: ',
    );
  }

  IconData _pinnedMessagePreviewIcon(DirectMessagePreviewKind kind) {
    switch (kind) {
      case DirectMessagePreviewKind.voice:
        return Icons.mic_none_outlined;
      case DirectMessagePreviewKind.image:
        return Icons.image_outlined;
      case DirectMessagePreviewKind.attachment:
        return Icons.insert_drive_file_outlined;
      case DirectMessagePreviewKind.location:
        return Icons.place_outlined;
      case DirectMessagePreviewKind.contact:
        return Icons.perm_contact_calendar_outlined;
      case DirectMessagePreviewKind.recalled:
        return Icons.history_toggle_off;
      case DirectMessagePreviewKind.text:
        return Icons.chat_bubble_outline;
    }
  }

  Future<void> _jumpToPinnedMessage(String messageId) async {
    await _scrollToMessage(messageId, alignment: 0.18, highlight: true);
  }

  Widget _buildPinnedMessagePreviewTile(
    BuildContext context,
    ChatMessage message, {
    required VoidCallback onTap,
    bool compact = true,
  }) {
    final preview = _previewPresentation(message);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timestamp = _formatMessageOverviewTimestamp(message.createdAt);
    final borderColor =
        theme.dividerColor.withValues(alpha: isDark ? .22 : .40);
    final background = isDark
        ? theme.colorScheme.surface.withValues(alpha: .88)
        : Colors.white.withValues(alpha: .96);
    final icon = _pinnedMessagePreviewIcon(preview.kind);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 9 : 10,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(
                    alpha: isDark ? .22 : .10,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preview.text,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (timestamp.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        timestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .58),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: .40),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPinnedMessagesSheet(
    ChatContact peer,
    List<ChatMessage> pinnedMessages,
  ) async {
    if (pinnedMessages.isEmpty) return;
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.shamellPinnedMessagesTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    peer.name?.trim().isNotEmpty == true
                        ? peer.name!.trim()
                        : peer.id,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .60),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: pinnedMessages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final message = pinnedMessages[index];
                        return _buildPinnedMessagePreviewTile(
                          context,
                          message,
                          compact: false,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              unawaited(_jumpToPinnedMessage(message.id));
                            });
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

  String _expirationLabel(ChatMessage m) {
    Duration? ttl = m.expireAt != null && m.createdAt != null
        ? m.expireAt!.difference(m.createdAt!)
        : (_disappearing ? _disappearAfter : null);
    if (ttl == null || ttl.inSeconds <= 0) return '';
    final created = m.createdAt ?? DateTime.now();
    final expires = m.expireAt ?? created.add(ttl);
    final remaining = expires.difference(DateTime.now());
    if (remaining.isNegative) return 'expired';
    // Cycle 44 — use the shared countdown formatter so the bubble
    // matches the AppBar / snooze badge style (e.g. "23h", "3d")
    // rather than the old "~93m" form.
    return formatExpireCountdown(remaining);
  }

  Future<void> _openImage(Uint8List data, String? mime, {String? heroTag}) async {
    // Cycle 50 — when the caller passes a `heroTag`, wrap the
    // full-screen image in a matching Hero so opening from a bubble
    // looks like a smooth zoom-up instead of a popup fade.
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, anim, _) {
          final body = Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image.memory(data, fit: BoxFit.contain),
            ),
          );
          return Stack(
            children: <Widget>[
              FadeTransition(
                opacity: anim,
                child: Container(color: Colors.black),
              ),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                behavior: HitTestBehavior.opaque,
                child: heroTag == null
                    ? body
                    : Hero(tag: heroTag, child: body),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _shareAttachment(Uint8List data, String? mime) async {
    try {
      final mt = mime?.trim().isNotEmpty == true
          ? mime!.trim()
          : 'application/octet-stream';
      String ext;
      if (mt == 'image/png') {
        ext = 'png';
      } else if (mt == 'image/jpeg' || mt == 'image/jpg') {
        ext = 'jpg';
      } else if (mt.startsWith('audio/') || mt.startsWith('video/')) {
        ext = mt.split('/').last.trim();
      } else {
        ext = 'bin';
      }
      final file = XFile.fromData(
        data,
        mimeType: mt,
        name: 'chat.$ext',
      );
      await Share.shareXFiles([file]);
    } catch (_) {
      final l = L10n.of(context);
      setState(
        () => _error = l.isArabic ? 'فشلت المشاركة.' : 'Share failed.',
      );
    }
  }

  Future<void> _openLocationOnMap(double lat, double lon) async {
    final uri = normalizeExternalMapUri(latitude: lat, longitude: lon);
    if (uri == null) return;
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
      final backup = _buildIdentityBackupPayload(
        identity: me,
        passphrase: pass,
      );
      setState(() => _backupText = backup);
      await shamellCopyToClipboard(
        backup,
        sensitive: true,
      );
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
      await _restoreIdentityFromBackupPayload(
        backup: backup,
        passphrase: pass,
      );
    } catch (e) {
      final l = L10n.of(context);
      setState(
        () => _error =
            '${l.shamellRestoreFailed}: ${sanitizeExceptionForUi(error: e, isArabic: l.isArabic)}',
      );
    }
  }

  String _buildIdentityBackupPayload({
    required ChatIdentity identity,
    required String passphrase,
  }) {
    final salt = _randomBytes(16);
    final key = _pbkdf2(passphrase, salt, 60000, 32);
    final box = x25519.SecretBox(key);
    final payload = jsonEncode(identity.toMap());
    final nonce = _randomBytes(24);
    final cipher =
        box.encrypt(Uint8List.fromList(utf8.encode(payload)), nonce: nonce);
    return 'CHATBACKUP|v1|salt=${base64Encode(salt)}|nonce=${base64Encode(nonce)}|cipher=${base64Encode(cipher.cipherText)}';
  }

  Future<void> _restoreIdentityFromBackupPayload({
    required String backup,
    required String passphrase,
  }) async {
    final previous = _me;
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
      final separatorIndex = p.indexOf('=');
      if (separatorIndex <= 0) continue;
      final field = p.substring(0, separatorIndex);
      final value = p.substring(separatorIndex + 1);
      if (field == 'salt') saltB64 = value;
      if (field == 'nonce') nonceB64 = value;
      if (field == 'cipher') cipherB64 = value;
    }
    if (saltB64 == null || nonceB64 == null || cipherB64 == null) {
      final l = L10n.of(context);
      setState(() => _error = l.shamellBackupMissingFields);
      return;
    }
    final salt = base64Decode(saltB64);
    final nonce = base64Decode(nonceB64);
    final cipher = x25519.ByteList(base64Decode(cipherB64));
    final key = _pbkdf2(passphrase, salt, 60000, 32);
    final box = x25519.SecretBox(key);
    final plain = box.decrypt(cipher, nonce: nonce);
    final map = jsonDecode(utf8.decode(plain));
    final restored = ChatIdentity.fromMap((map as Map<String, Object?>));
    if (restored == null) {
      final l = L10n.of(context);
      setState(() => _error = l.shamellBackupCorrupt);
      return;
    }
    final identityChanged = previous == null ||
        previous.id.trim() != restored.id.trim() ||
        previous.fingerprint.trim() != restored.fingerprint.trim();
    await _store.saveIdentity(restored, baseUrlOverride: widget.baseUrl);
    setState(() {
      _me = restored;
      _backupText = backup;
    });
    if (identityChanged) {
      await _clearDirectSessionStateAfterLocalIdentityChange();
    }
    await _register();
  }

  Future<String?> _promptPassphrase({required bool confirm}) async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    final l = L10n.of(context);
    try {
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
    } finally {
      ctrl1.dispose();
      ctrl2.dispose();
    }
  }

  Future<String?> _promptBackup() async {
    final ctrl = TextEditingController(text: _backupText);
    final l = L10n.of(context);
    try {
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
                    onPressed: () =>
                        Navigator.of(context).pop(ctrl.text.trim()),
                    child: Text(l.shamellRestoreBackupButton)),
              ],
            );
          });
    } finally {
      ctrl.dispose();
    }
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
    final existingRatchet = _ratchets[peer.id];
    if (existingRatchet != null) {
      if (_isValidRatchetState(existingRatchet) &&
          _isRatchetBoundToPeer(existingRatchet, peer)) {
        return peer;
      }
      _ratchets.remove(peer.id);
      await _store.deleteRatchet(peer.id, baseUrlOverride: widget.baseUrl);
    }
    if (!_service.libsignalKeyApiEnabled) return peer;
    final me = _me;
    if (me == null) return peer;
    final pinnedSigningKey = (await _store.loadPinnedIdentitySigningPubkey(
              peer.id,
              baseUrlOverride: widget.baseUrl,
            ) ??
            '')
        .trim();
    final bootstrapMeta = await _store.loadSessionBootstrapMeta(
      peer.id,
      baseUrlOverride: widget.baseUrl,
    );
    final trustedBootstrapReady = (() {
      if (bootstrapMeta.isEmpty) return false;
      if (pinnedSigningKey.isEmpty) return false;
      final floor = (bootstrapMeta['protocol_floor'] ?? '').toString().trim();
      final signedPrekey = switch (bootstrapMeta['signed_prekey_id']) {
        int value => value,
        String value => int.tryParse(value) ?? -1,
        _ => -1,
      };
      final peerKey = peer.publicKeyB64.trim();
      final peerFp = peer.fingerprint.trim();
      return floor.isNotEmpty &&
          signedPrekey >= 0 &&
          peerKey.isNotEmpty &&
          peerFp.isNotEmpty;
    })();
    if (trustedBootstrapReady) {
      return peer;
    }

    try {
      final bundle = await _service.fetchKeyBundle(
        targetDeviceId: peer.id,
        requesterDeviceId: me.id,
      );
      final signingKeyB64 = (bundle.identitySigningPubkeyB64 ?? '').trim();
      var hasPinnedSigningKey = pinnedSigningKey.isNotEmpty;
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
          final strictPinEnforcement = peer.verified && peer.verifiedAt != null;
          // Unverified contacts (or legacy verified contacts without a
          // verification timestamp) can auto-recover key rotations by clearing
          // stale local pin/session state in-place.
          if (!strictPinEnforcement) {
            await _clearPeerSessionMaterial(
              peer.id,
              peerFingerprint: peer.fingerprint,
            );
            if (peer.verified) {
              final downgraded = peer.copyWith(
                verified: false,
                verifiedAt: null,
              );
              final contacts = _upsertContact(downgraded);
              await _store.savePeer(
                downgraded,
                baseUrlOverride: widget.baseUrl,
              );
              await _saveScopedContactsForPeers(<ChatContact>[downgraded]);
              if (_peer?.id == downgraded.id) {
                _applyState(() {
                  _peer = downgraded;
                  _contacts = contacts;
                  _safetyNumber = _computeSafety();
                  _sessionHash = _computeSessionHash();
                });
              }
            }
            hasPinnedSigningKey = false;
          } else {
            final l = L10n.of(context);
            _applyState(() {
              _ratchetWarning = l.shamellSessionChangedBody;
            });
            throw const _SigningKeyPinViolation('identity signing key changed');
          }
        }
      }
      if (!hasPinnedSigningKey && signingKeyB64.isEmpty) {
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
        await _saveScopedContactsForPeers(<ChatContact>[updatedPeer]);
        if (_peer?.id == updatedPeer.id) {
          await _store.savePeer(updatedPeer, baseUrlOverride: widget.baseUrl);
          if (mounted) {
            setState(() {
              _peer = updatedPeer;
              _contacts = contacts;
              _safetyNumber = _computeSafety();
              _sessionHash = _computeSessionHash();
              _ratchetWarning = null;
              _promptedForKeyChange = false;
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
        baseUrlOverride: widget.baseUrl,
      );

      return updatedPeer;
    } on _SigningKeyPinViolation {
      rethrow;
    } on ChatHttpException {
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
    final stabilizedPeer = await _stabilizePeerSessionForOutbound(peer);
    final preparedPeer = await _bootstrapPeerSessionIfNeeded(stabilizedPeer);
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
      if (_isValidRatchetState(existing) &&
          _isRatchetBoundToPeer(existing, peer)) {
        return existing;
      }
      _ratchets.remove(pid);
      unawaited(_store.deleteRatchet(pid, baseUrlOverride: widget.baseUrl));
    }
    final peerPub = _decodeCurveKeyB64(peer.publicKeyB64);
    if (peerPub == null) {
      throw const _SessionBootstrapViolation('peer identity key invalid');
    }
    final myIdentityPrivate = _decodeIdentityPrivateKey(_me);
    if (myIdentityPrivate == null) {
      throw const _SessionBootstrapViolation('identity private key invalid');
    }
    final dh = x25519.PrivateKey(myIdentityPrivate);
    final dhPub =
        _decodeCurveKeyB64(_me?.publicKeyB64) ?? dh.publicKey.asTypedList;
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
      dhPub: Uint8List.fromList(dhPub),
      peerDhPub: peerPub,
      peerDhPubB64: base64Encode(peerPub),
    );
    _ratchets[pid] = st;
    _store.saveRatchet(pid, st.toJson(), baseUrlOverride: widget.baseUrl);
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
    _store.saveRatchet(
      peerId,
      st.toJson(),
      baseUrlOverride: widget.baseUrl,
    );
    return (mk.$1, keyId, prev >= 0 ? prev : 0, base64Encode(st.dhPub));
  }

  Uint8List? _sessionKeyForMessage(ChatMessage m) {
    final targetCtr = m.keyId ?? 0;
    final myId = _me?.id.trim() ?? '';
    final fp = m.senderHint ?? _peer?.fingerprint ?? '';
    if (targetCtr < 0) return null;
    ChatContact? peer;
    if (myId.isNotEmpty && m.isOwnFor(myId)) {
      final recipientId = m.recipientId.trim();
      if (recipientId.isNotEmpty) {
        for (final c in _contacts) {
          if (c.id == recipientId) {
            peer = c;
            break;
          }
        }
      }
      if (peer == null && _peer?.id == recipientId) {
        peer = _peer;
      }
    } else {
      final senderId = m.senderId.trim();
      if (fp.isNotEmpty) {
        for (final c in _contacts) {
          if (c.fingerprint == fp) {
            peer = c;
            break;
          }
        }
        if (peer == null && _peer?.fingerprint == fp) {
          peer = _peer;
        }
      }
      if (peer == null && senderId.isNotEmpty) {
        for (final c in _contacts) {
          if (c.id == senderId) {
            peer = c;
            break;
          }
        }
      }
      if (peer == null && _peer?.id == senderId) {
        peer = _peer;
      }
    }
    if (peer == null || _decodeCurveKeyB64(peer.publicKeyB64) == null) {
      return null;
    }
    final st = _ensureRatchet(peer);
    if (myId.isNotEmpty && m.isOwnFor(myId)) {
      var chainKey = Uint8List.fromList(st.rootKey);
      for (var counter = 0; counter <= targetCtr; counter++) {
        final derived = _kdfChain(chainKey, counter);
        if (counter == targetCtr) {
          return derived.$1;
        }
        chainKey = derived.$2;
      }
      return null;
    }
    // detect identity/key mismatch
    if (fp.isNotEmpty && peer.fingerprint != fp) {
      final l = L10n.of(context);
      final strictPinEnforcement = peer.verified && peer.verifiedAt != null;
      if (!strictPinEnforcement) {
        _ratchetWarning = l.shamellSessionChangedBody;
        setState(() {});
        _schedulePeerSessionBootstrapRecovery(
          peer,
          fallbackSenderPubKeyB64: m.senderPubKeyB64,
          fallbackSenderFingerprint: fp,
        );
      } else {
        _ratchetWarning = l.shamellRatchetKeyMismatch;
        setState(() {});
        if (!_promptedForKeyChange) {
          _promptedForKeyChange = true;
          _showKeyChangePrompt();
        }
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
      _schedulePeerSessionBootstrapRecovery(
        peer,
        fallbackSenderPubKeyB64: m.senderPubKeyB64,
        fallbackSenderFingerprint: fp,
      );
      return null;
    }
    // explicit window: allow up to +50 ahead
    if (targetCtr - st.recvCount > st.maxSkip) {
      final l = L10n.of(context);
      _ratchetWarning = l.shamellRatchetAheadWarning;
      setState(() {});
      _schedulePeerSessionBootstrapRecovery(
        peer,
        fallbackSenderPubKeyB64: m.senderPubKeyB64,
        fallbackSenderFingerprint: fp,
      );
      return null;
    }
    // skipped cache lookup
    final skipKey = '${m.senderDhPubB64 ?? ''}:$targetCtr';
    if (st.skipped.containsKey(skipKey)) {
      final mkB64 = st.skipped[skipKey];
      _store.saveRatchet(
        peer.id,
        st.toJson(),
        baseUrlOverride: widget.baseUrl,
      );
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
        // Cache the current message key too so repeated UI decodes of the
        // same ciphertext do not trip the out-of-window guard.
        if (st.skipped.length >= st.maxSkip &&
            !st.skipped.containsKey(skipKey)) {
          final firstKey = st.skipped.keys.first;
          st.skipped.remove(firstKey);
        }
        st.skipped[skipKey] = base64Encode(derived.$1);
        st.recvCount = counter + 1;
        _store.saveRatchet(
          peer.id,
          st.toJson(),
          baseUrlOverride: widget.baseUrl,
        );
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
    _store.saveRatchet(
      peer.id,
      st.toJson(),
      baseUrlOverride: widget.baseUrl,
    );
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
    _store.saveRatchet(
      peerId,
      st.toJson(),
      baseUrlOverride: widget.baseUrl,
    );
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

  Future<void> _clearPeerSessionMaterial(
    String peerId, {
    String? peerFingerprint,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    _ratchets.remove(pid);
    _chains.remove(pid);
    _sessionKeys.remove(pid);
    final fp = (peerFingerprint ?? '').trim();
    if (fp.isNotEmpty) {
      _sessionKeysByFp.remove(fp);
    }
    await _store.deleteRatchet(pid, baseUrlOverride: widget.baseUrl);
    await _store.saveSessionKey(pid, '', baseUrlOverride: widget.baseUrl);
    await _store.saveChain(
      pid,
      <String, Object>{},
      baseUrlOverride: widget.baseUrl,
    );
    await _store.deleteSessionBootstrapMeta(
      pid,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _resetSession() async {
    final currentPeer = _peer;
    final pid = currentPeer?.id;
    if (pid == null || currentPeer == null) return;
    await _clearPeerSessionMaterial(
      pid,
      peerFingerprint: currentPeer.fingerprint,
    );
    final refreshedPeer = await _refreshPeerAfterSessionMaterialClear(
      currentPeer,
    );
    _cache[pid] = [];
    final updatedContacts = _upsertContact(refreshedPeer);
    setState(() {
      _peer = refreshedPeer;
      _contacts = updatedContacts;
      _messages = [];
      _safetyNumber = _computeSafety();
      _sessionHash = _computeSessionHash();
      _ratchetWarning = null;
      _promptedForKeyChange = false;
      _error = null;
    });
  }

  Future<bool> _authenticate() async {
    final override = widget.authenticateHiddenChatsOverride;
    if (override != null) {
      return await override();
    }
    return true;
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
    if (_hasOlderThreadMessages &&
        !_loadingOlderThreadMessages &&
        !_loading &&
        _threadScrollCtrl.hasClients &&
        _threadScrollCtrl.offset <= _threadOlderMessagesLoadThreshold) {
      unawaited(_loadOlderThreadMessages());
    }
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
      _flashThreadMessageHighlight(messageId);
    }
    if (_existingThreadMessageKey(messageId) == null) {
      final requestedKey = _threadMessageKey(messageId);
      if (requestedKey != null && mounted) {
        _applyState(() {});
        await Future<void>.delayed(Duration.zero);
      }
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      final key = _existingThreadMessageKey(messageId);
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
      final idx = _threadMessageIndex(messageId);
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
          if (m.isOwnFor(myId)) continue;
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

  Future<void> _setPinnedMessageState(
    String peerId,
    String messageId,
    bool pinned,
  ) async {
    final normalizedPeerId = peerId.trim();
    final normalizedMessageId = messageId.trim();
    if (normalizedPeerId.isEmpty || normalizedMessageId.isEmpty) return;
    final saveOverride = widget.savePinnedMessageForPeerOverride;
    if (saveOverride != null) {
      await saveOverride(normalizedPeerId, normalizedMessageId, pinned);
    } else {
      await _store.savePinnedMessageForPeer(
        normalizedPeerId,
        normalizedMessageId,
        pinned,
        baseUrlOverride: widget.baseUrl,
      );
    }
    if (!mounted) return;
    _applyState(() {
      final next = Set<String>.from(
        _pinnedMessageIdsByPeer[normalizedPeerId] ?? const <String>{},
      );
      if (pinned) {
        next.add(normalizedMessageId);
      } else {
        next.remove(normalizedMessageId);
      }
      if (next.isEmpty) {
        _pinnedMessageIdsByPeer.remove(normalizedPeerId);
      } else {
        _pinnedMessageIdsByPeer[normalizedPeerId] = next;
      }
    });
  }

  Future<void> _removePinnedMessageFromAllPeers(String messageId) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return;
    final affectedPeerIds = <String>[];
    for (final entry in _pinnedMessageIdsByPeer.entries) {
      if (entry.value.contains(normalizedMessageId)) {
        affectedPeerIds.add(entry.key);
      }
    }
    if (affectedPeerIds.isEmpty) return;
    final removeOverride = widget.removePinnedMessageFromAllPeersOverride;
    if (removeOverride != null) {
      await removeOverride(normalizedMessageId);
    } else {
      await _store.removePinnedMessageFromAllPeers(
        normalizedMessageId,
        baseUrlOverride: widget.baseUrl,
      );
    }
    if (!mounted) return;
    _applyState(() {
      for (final peerId in affectedPeerIds) {
        final next = Set<String>.from(
          _pinnedMessageIdsByPeer[peerId] ?? const <String>{},
        )..remove(normalizedMessageId);
        if (next.isEmpty) {
          _pinnedMessageIdsByPeer.remove(peerId);
        } else {
          _pinnedMessageIdsByPeer[peerId] = next;
        }
      }
    });
  }

  Future<void> _removeFavoriteItemsByMessageId(String messageId) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return;
    final removeOverride = widget.removeFavoriteItemsByMessageIdOverride;
    if (removeOverride != null) {
      await removeOverride(normalizedMessageId);
      return;
    }
    await removeFavoriteItemsByMessageId(
      normalizedMessageId,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _persistArchivedGroupState(String groupId, bool archived) async {
    try {
      final override = widget.saveArchivedGroupStateOverride;
      if (override != null) {
        await override(groupId, archived);
      } else {
        await _store.saveArchivedGroupState(
          groupId,
          archived,
          baseUrlOverride: widget.baseUrl,
        );
      }
    } catch (_) {}
  }

  Future<void> _setGroupArchivedState(
    String groupId,
    bool archived, {
    bool clearArchivedView = false,
  }) async {
    _applyArchivedGroupState(
      groupId,
      archived,
      clearArchivedView: clearArchivedView,
    );
    await _persistArchivedGroupState(groupId, archived);
  }

  void _applyArchivedGroupState(
    String groupId,
    bool archived, {
    bool clearArchivedView = false,
  }) {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return;
    final next = Set<String>.from(_archivedGroupIds);
    if (archived) {
      next.add(normalizedGroupId);
    } else {
      next.remove(normalizedGroupId);
    }
    _applyState(() {
      _archivedGroupIds = next;
      if (!archived && clearArchivedView) {
        _showArchived = false;
        _chatSearch = '';
      }
    });
    if (!archived && clearArchivedView) {
      _chatSearchCtrl.clear();
    }
  }

  Future<void> _normalizePinnedChatOrder() async {
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
      try {
        _pinnedChatOrder = await _store.reconcilePinnedChatOrder(
          const <String>[],
          baseUrlOverride: widget.baseUrl,
        );
      } catch (_) {}
      return;
    }
    try {
      _pinnedChatOrder = await _store.reconcilePinnedChatOrder(
        pinnedIds,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
  }

  @visibleForTesting
  List<String> debugPinnedChatOrderSnapshot() =>
      List<String>.from(_pinnedChatOrder);

  Future<void> _updatePinnedChatOrderForPeer(
      String peerId, bool isPinned) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return;
    final current = List<String>.from(_pinnedChatOrder)
      ..removeWhere((id) => id == normalizedPeerId);
    if (isPinned) {
      current.insert(0, normalizedPeerId);
    }
    try {
      await _store.savePinnedChatOrderState(
        normalizedPeerId,
        isPinned,
        baseUrlOverride: widget.baseUrl,
      );
      _pinnedChatOrder = current;
    } catch (_) {}
  }

  Future<void> _setRecalledMessageState(String messageId, bool recalled) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return;
    final saveOverride = widget.saveRecalledMessageStateOverride;
    if (saveOverride != null) {
      await saveOverride(normalizedMessageId, recalled);
    } else {
      await _store.saveRecalledMessageState(
        normalizedMessageId,
        recalled,
        baseUrlOverride: widget.baseUrl,
      );
    }
    if (!mounted) return;
    _applyState(() {
      final changed = recalled
          ? _recalledMessageIds.add(normalizedMessageId)
          : _recalledMessageIds.remove(normalizedMessageId);
      if (changed) {
        _recalledMessageIdsRevision++;
        _clearThreadMessageSearchIndex();
      }
    });
  }

  bool _isDraftEligibleChatId(String? chatId) {
    final id = (chatId ?? '').trim();
    return id.isNotEmpty;
  }

  void _schedulePersistDrafts() {
    _draftPersistTimer?.cancel();
    _draftPersistTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      try {
        await _saveDraftsSnapshot(_draftTextByChatId);
      } catch (_) {}
    });
  }

  void _onChatComposerChanged() {
    if (_suppressDraftListener) return;
    // Cycle 23: expand `:keyword:` shortcuts to emoji the moment
    // the user types the closing colon. We guard with the suppress
    // flag while writing back so the listener doesn't fire on its
    // own update.
    final value = _msgCtrl.value;
    final caretOffset = value.selection.baseOffset >= 0
        ? value.selection.baseOffset
        : value.text.length;
    final expanded = expandEmojiShortcuts(
      text: value.text,
      caret: caretOffset,
    );
    if (!expanded.unchanged) {
      _suppressDraftListener = true;
      try {
        _msgCtrl.value = TextEditingValue(
          text: expanded.text,
          selection: TextSelection.collapsed(offset: expanded.caret),
        );
      } finally {
        _suppressDraftListener = false;
      }
      // Fall through so the draft-persist + typing-signal sync still
      // run for the rewritten text. The recursive listener call
      // path is short-circuited above by the suppress guard.
    }
    final peerId = _peer?.id;
    if (!_isDraftEligibleChatId(peerId)) {
      _stopComposerTypingSignal();
      return;
    }
    final id = peerId!.trim();
    final text = _msgCtrl.text;
    if (text.trim().isEmpty) {
      _draftTextByChatId.remove(id);
    } else {
      _draftTextByChatId[id] = text;
    }
    _schedulePersistDrafts();
    _syncComposerTypingSignal();
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
      await _saveDraftsSnapshot(_draftTextByChatId);
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
    _syncComposerTypingSignal();
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
      await _saveDraftsSnapshot(_draftTextByChatId);
    } catch (_) {}
  }

  Future<void> _saveDraftsSnapshot(Map<String, String> drafts) async {
    final override = widget.saveDraftsOverride;
    if (override != null) {
      await override(Map<String, String>.from(drafts));
      return;
    }
    await _store.saveDrafts(
      drafts,
      baseUrlOverride: widget.baseUrl,
    );
  }

  Future<void> _exitChatThread() async {
    final peerId = _peer?.id;
    _stopComposerTypingSignal(peerId: peerId);
    if (_isDraftEligibleChatId(peerId)) {
      await _stashActiveComposerDraft(persistNow: true);
    }
    if (!mounted) return;
    _suppressDraftListener = true;
    _msgCtrl.clear();
    _suppressDraftListener = false;
    _messageSearchCtrl.clear();
    _clearThreadMessageSearchIndex();
    _clearThreadMessagePositionIndex();
    _clearThreadListLayout();
    _clearThreadMessageRenderKeys();
    _threadMessageHighlightController.clear();
    _applyState(() {
      _peer = null;
      _activePeerId = null;
      _messageSelectionMode = false;
      _selectedMessageIds.clear();
      _attachedBytes = null;
      _attachedMime = null;
      _attachedName = null;
      _replyToMessage = null;
      _showMessageSearchBar = false;
      _messageSearch = '';
      _activeThreadMessageSearchMatchId = null;
      _highlightedMessageId = null;
      _threadNearBottom = true;
      _threadNewMessagesAwayCount = 0;
      _threadNewMessagesFirstId = null;
      _shamellVoiceMode = false;
      _composerPanel = _ShamellComposerPanel.none;
    });
  }

  Future<void> _handleMessageRecalled(String messageId) async {
    await _removePinnedMessageFromAllPeers(messageId);
    try {
      await _removeFavoriteItemsByMessageId(messageId);
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
    final pinned = !current.contains(m.id);
    await _setPinnedMessageState(peerId, m.id, pinned);
    final me = _me;
    if (me != null) {
      try {
        await _service.setMessagePin(
          deviceId: me.id,
          messageId: m.id,
          pinned: pinned,
        );
      } catch (_) {}
    }
  }

  Future<void> _replaceLocalMessage(ChatMessage message) async {
    final me = _me;
    if (me == null) return;
    final peerId = _peerIdForMessage(message, me.id);
    if (peerId.trim().isEmpty) return;
    final list = List<ChatMessage>.from(_cache[peerId] ?? _messages);
    final index = list.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      list[index] = message;
    } else {
      list.add(message);
    }
    list.sort(_compareDirectMessageCursor);
    _applyState(() {
      _cache[peerId] = list;
      if (_activePeerId == peerId) {
        _messages = list;
      }
    });
    await _saveMessagesForPeer(peerId, list);
  }

  Future<void> _editTextMessage(ChatMessage message) async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null || !message.isOwnFor(me.id)) return;
    final l = L10n.of(context);
    final decoded = _decodeMessage(message);
    final current = decoded.text.trim();
    if (current.isEmpty ||
        decoded.attachment != null ||
        decoded.kind == 'voice') {
      return;
    }
    final ctrl = TextEditingController(text: current);
    final nextText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'تعديل الرسالة' : 'Edit message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.shamellDialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(l.settingsSave),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nextText == null || nextText.trim().isEmpty || nextText == current) {
      return;
    }
    try {
      final outbound = await _nextOutboundSendContext(peer);
      final plainText = _encodeDraftPayload(
        me: me,
        draft: _FrozenDirectDraftSend(text: nextText.trim()),
      );
      final envelope = _service.prepareDirectSendEnvelope(
        me: me,
        peer: outbound.peer,
        plainText: plainText,
        sealedSender: true,
        senderHint: me.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
      );
      final updated = await _service.editMessage(
        me: me,
        peer: outbound.peer,
        messageId: message.id,
        plainText: plainText,
        preparedEnvelope: envelope,
      );
      await _replaceLocalMessage(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sanitizeExceptionForUi(
            error: error,
            isArabic: l.isArabic,
          )),
        ),
      );
    }
  }

  Future<void> _reportMessage(ChatMessage m) async {
    final me = _me;
    if (me == null) return;
    final l = L10n.of(context);
    try {
      await _service.reportMessage(
        deviceId: me.id,
        messageId: m.id,
        reason: 'abuse',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic ? 'تم إرسال البلاغ.' : 'Report sent.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              l.isArabic ? 'تعذّر إرسال البلاغ.' : 'Could not send report.'),
        ),
      );
    }
  }

  Future<void> _showVoiceTranscript(ChatMessage m) async {
    final me = _me;
    if (me == null) return;
    final l = L10n.of(context);
    String? transcript;
    try {
      transcript = await _service.fetchVoiceTranscript(
        deviceId: me.id,
        messageId: m.id,
      );
    } catch (_) {
      transcript = null;
    }
    final hasTranscript = (transcript ?? '').trim().isNotEmpty;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'نص الرسالة الصوتية' : 'Voice transcript',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                !hasTranscript
                    ? (l.isArabic
                        ? 'لا يوجد نص محفوظ لهذه الرسالة بعد.'
                        : 'No saved transcript for this voice message yet.')
                    : transcript!.trim(),
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              if (!hasTranscript) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await _service.requestVoiceTranscriptJob(
                        deviceId: me.id,
                        messageId: m.id,
                      );
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.isArabic
                              ? 'تم طلب تحويل الصوت إلى نص.'
                              : 'Transcript requested.'),
                        ),
                      );
                    } catch (_) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.isArabic
                              ? 'تعذّر طلب النص.'
                              : 'Could not request transcript.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(l.isArabic ? 'طلب النص' : 'Request transcript'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
    final trimmedCode = code.trim();
    if (trimmedCode.isEmpty) return;
    if (trimmedCode.length > _shamellChatScanPayloadMaxChars) {
      if (!mounted) return;
      final msg = l.isArabic
          ? 'رمز QR غير مدعوم. امسح رمز دعوة SyrChat.'
          : 'Unsupported QR. Please scan a SyrChat invite QR.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }
    final miniProgramPipeTarget = parseMiniProgramPipePayload(trimmedCode);
    if (miniProgramPipeTarget != null) {
      await _openMiniProgramTarget(miniProgramPipeTarget);
      return;
    }
    // 1) SyrChat deep links (invite / official) and hosted app links.
    try {
      final uri = normalizeShamellChatScannedInboundUri(Uri.parse(trimmedCode));
      if (uri.scheme.toLowerCase() == 'shamell') {
        if (!shamellChatAllowsScannedCustomSchemeUri(uri)) {
          if (!mounted) return;
          final msg = l.isArabic
              ? 'رمز QR غير مدعوم. امسح رمز دعوة SyrChat.'
              : 'Unsupported QR. Please scan a SyrChat invite QR.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
          return;
        }
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
              ? 'رمز الصديق لم يعد مدعوماً. اطلب رمز دعوة جديد.'
              : 'This friend QR is no longer supported. Ask for a new invite QR.';
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
              _openOfficialAccountsDirectory();
              return;
            }
          }
        }
        final miniProgramTarget = parseMiniProgramDeepLink(uri);
        if (miniProgramTarget != null) {
          await _openMiniProgramTarget(miniProgramTarget);
          return;
        }
      }
    } catch (_) {}

    // 2) Accept raw invite tokens as QR payloads (no peer-id fallback).
    final raw = trimmedCode;
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(raw)) {
      await _openChatFromInviteQr(raw);
      return;
    }

    if (!mounted) return;
    final msg = l.isArabic
        ? 'رمز QR غير مدعوم. امسح رمز دعوة SyrChat.'
        : 'Unsupported QR. Please scan a SyrChat invite QR.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  void dispose() {
    ShamellChatPresenceRegistry.leave();
    unawaited(_stashActiveComposerDraft(persistNow: true));
    _decodedMessagePayloadCache.clear();
    _inlineImageBytesCache.clear();
    _clearThreadMessageSearchIndex();
    _clearThreadMessagePositionIndex();
    _clearThreadListLayout();
    _clearThreadMessageRenderKeys();
    _threadMessageHighlightController.dispose();
    _draftPersistTimer?.cancel();
    _contactsIndexOverlayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    _grpWsSub?.cancel();
    _wsInboxReconnectTimer?.cancel();
    _wsGroupsReconnectTimer?.cancel();
    _conversationEventTimer?.cancel();
    _pushSub?.cancel();
    _pushOpenedAppSub?.cancel();
    if (_ownsService) {
      _service.close();
    }
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    _voiceAmpSub?.cancel();
    _presenceHeartbeatTimer?.cancel();
    _presenceRefreshTimer?.cancel();
    _profileRefreshTimer?.cancel();
    _shamellMorePanelCtrl.dispose();
    unawaited(_clearVoicePlaybackFile());
    unawaited(_clearVoiceRecordingFile());
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    try {
      _recorder.dispose();
    } catch (_) {}
    _voiceTicker?.cancel();
    _proximitySub?.cancel();
    _stopComposerTypingSignal();
    _typingWsSub?.cancel();
    _typingIndicatorTimer?.cancel();
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
    _directMessagePresentationCache.clear();
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
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      setState(() => _error = _sendFailureToUi(e));
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
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      setState(() => _error = _sendFailureToUi(e));
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
      items = await loadFavoriteItems(baseUrlOverride: widget.baseUrl);
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
      future: _callStore.load(baseUrlOverride: widget.baseUrl),
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
    final all = await _callStore.load(baseUrlOverride: widget.baseUrl);
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
            : 'SyrChat');
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isChatThread ? 52 : 48,
        titleSpacing: isChatThread ? 0 : 16,
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
                        _chatSearchVisible = false;
                      });
                      _chatSearchCtrl.clear();
                      _resetArchivedPullDown();
                    },
                  )
                : null),
        title: (_tabIndex == 0 && peer != null)
            ? _buildChatAppBarTitle(peer)
            : Text(
                chatTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: isChatThread ? 17 : 18,
                  fontWeight: isChatThread ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
        backgroundColor: scaffoldBg,
        elevation: 0.5,
        actions: [
          // Voice + video call shortcuts live in the chat thread AppBar
          // (not buried in the composer "+" menu) so peers can be reached
          // with one tap from the conversation. Both buttons resolve to
          // the same `_startVoipCall` that powers the legacy entries; the
          // call-policy / blocked checks remain identical.
          if (_tabIndex == 0 && peer != null && !peer.blocked)
            IconButton(
              tooltip: l.isArabic ? 'مكالمة صوتية' : 'Voice call',
              icon: const Icon(Icons.call_outlined, size: 22),
              onPressed: () => _startVoipCall(mode: 'audio'),
            ),
          if (_tabIndex == 0 && peer != null && !peer.blocked)
            IconButton(
              tooltip: l.isArabic ? 'مكالمة فيديو' : 'Video call',
              icon: const Icon(Icons.videocam_outlined, size: 22),
              onPressed: () => _startVoipCall(mode: 'video'),
            ),
          // Snooze toggle. Filled bell-paused when the conversation is
          // currently snoozed, outlined otherwise. Tapping opens the
          // duration picker (Cycle 7 snooze enforcement).
          if (_tabIndex == 0 && peer != null)
            Builder(builder: (_) {
              final until = _peerSnoozedUntil[peer.id];
              final isSnoozed =
                  until != null && until.isAfter(DateTime.now());
              // Cycle 26: when snoozed, overlay a compact countdown
              // badge on the bell so the user sees how much longer
              // notifications stay muted without opening the picker.
              final countdown = isSnoozed
                  ? formatExpireCountdown(until.difference(DateTime.now()))
                  : '';
              return IconButton(
                tooltip: l.isArabic
                    ? (countdown.isNotEmpty
                        ? 'إيقاف الإشعارات · $countdown'
                        : 'إيقاف الإشعارات')
                    : (countdown.isNotEmpty
                        ? 'Snooze · $countdown'
                        : 'Snooze notifications'),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Icon(
                      isSnoozed
                          ? Icons.notifications_paused
                          : Icons.notifications_paused_outlined,
                      size: 22,
                    ),
                    if (countdown.isNotEmpty)
                      Positioned(
                        right: -8,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            countdown,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () => _openSnoozePicker(peer),
              );
            }),
          // Cycle 8: scheduled-messages list. Tucked alongside the
          // snooze + chat-info icons rather than buried in an
          // overflow menu — sender access to their own pending
          // queue should be one tap, not three.
          if (_tabIndex == 0 && peer != null)
            IconButton(
              tooltip: l.isArabic ? 'الرسائل المجدولة' : 'Scheduled',
              icon: const Icon(Icons.schedule_outlined, size: 22),
              onPressed: _openScheduledMessagesPage,
            ),
          // Cycle 30: 24h ephemeral stories.
          if (_tabIndex == 0 && peer != null)
            IconButton(
              tooltip: l.isArabic ? 'القصص' : 'Stories',
              icon: const Icon(Icons.auto_stories_outlined, size: 22),
              onPressed: _openStoriesPage,
            ),
          // Cycle 36: in-thread search. Filters the currently-loaded
          // message list by text content; tap a result to jump+flash.
          if (_tabIndex == 0 && peer != null)
            IconButton(
              tooltip: l.isArabic ? 'بحث' : 'Search',
              icon: const Icon(Icons.search, size: 22),
              onPressed: _openThreadSearch,
            ),
          // Cycle 45 — browseable saved-messages / bookmarks page.
          // Only shown on the chat list (no peer selected) so it
          // doesn't crowd the thread AppBar.
          if (_tabIndex == 0 && peer == null)
            IconButton(
              tooltip: l.isArabic ? 'المحفوظات' : 'Saved',
              icon: const Icon(Icons.bookmarks_outlined, size: 22),
              onPressed: _openBookmarksPage,
            ),
          // Cycle 56 — profile editor entry (chat list only).
          if (_tabIndex == 0 && peer == null)
            IconButton(
              tooltip: l.isArabic ? 'الملف الشخصي' : 'My profile',
              icon: const Icon(Icons.account_circle_outlined, size: 22),
              onPressed: _openProfileEditor,
            ),
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
                onPressed: () {
                  _applyState(() {
                    _chatSearchVisible = !_chatSearchVisible;
                    if (!_chatSearchVisible) {
                      _chatSearch = '';
                      _chatSearchCtrl.clear();
                    }
                  });
                },
                icon: const Icon(Icons.search),
              ),
            if (!_showArchived)
              Theme(
                data: theme.copyWith(dividerColor: Colors.white24),
                child: PopupMenuButton<String>(
                  tooltip: l.isArabic ? 'إضافة' : 'Add',
                  icon: const Icon(Icons.add),
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 6),
                  color: const Color(0xFF1F1F1F),
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: .22),
                  surfaceTintColor: Colors.transparent,
                  menuPadding: const EdgeInsets.symmetric(vertical: 5),
                  constraints: const BoxConstraints(
                    minWidth: 212,
                    maxWidth: 236,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (value) {
                    if (value == 'group') {
                      _runAfterPopupMenuDismiss(_startNewGroupChat);
                    } else if (value == 'friend') {
                      _runAfterPopupMenuDismiss(_startNewChat);
                    } else if (value == 'scan') {
                      _runAfterPopupMenuDismiss(_scanQr);
                    } else if (value == 'pay') {
                      if (_caps.payments) {
                        showUnsupportedModuleShortcutSnackBar(context);
                      } else {
                        final msg = l.isArabic
                            ? 'المدفوعات غير متاحة حالياً.'
                            : 'Payments are not available right now.';
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      }
                    }
                  },
                  itemBuilder: (ctx) {
                    Widget item(IconData icon, String label) {
                      return SizedBox(
                        width: 204,
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: Colors.white.withValues(alpha: .92),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final out = <PopupMenuEntry<String>>[];
                    void addItem(String value, IconData icon, String label) {
                      if (out.isNotEmpty) {
                        out.add(const PopupMenuDivider(height: .7));
                      }
                      out.add(
                        PopupMenuItem<String>(
                          value: value,
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: item(icon, label),
                        ),
                      );
                    }

                    addItem(
                      'group',
                      Icons.groups_outlined,
                      l.isArabic ? 'دردشة جماعية' : 'Group chat',
                    );
                    addItem(
                      'friend',
                      Icons.person_add_alt_1_outlined,
                      l.isArabic ? 'إضافة صديق' : 'Add friend',
                    );
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
      if (name.contains(term) || id.contains(term)) return true;
      // Cycle 62 — also match against the peer's published profile
      // name + status text, so searching "vacation" surfaces every
      // contact whose status mentions it.
      final pubName =
          (_peerProfileDisplayName[c.id] ?? '').toLowerCase();
      if (pubName.isNotEmpty && pubName.contains(term)) return true;
      final statusText =
          (_peerProfileStatusText[c.id] ?? '').toLowerCase();
      if (statusText.isNotEmpty && statusText.contains(term)) return true;
      return false;
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
        onTap: () async {
          await _handleChatTileTap(c);
        },
        onLongPress: () async {
          await _handleChatTileLongPress(c);
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
                            _openOfficialAccountsDirectory();
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
                ? 'الحسابات الرسمية الرائجة'
                : 'Trending official accounts',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            l.isArabic
                ? 'عرض حسابات الخدمات الرسمية الرائجة'
                : 'Browse trending official service accounts',
            style: const TextStyle(fontSize: 12),
          ),
          trailing:
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          onTap: () async {
            if (!await _ensureOfficialAuthSession()) return;
            if (!mounted) return;
            _openOfficialAccountsDirectory();
          },
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
            l.isArabic ? 'SyrChat Pay' : 'SyrChat Pay',
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
          ? 'اختصارات للخدمات داخل SyrChat'
          : 'Shortcuts for services inside SyrChat',
      children: children,
    );
  }

  void _openPayService() {
    final l = L10n.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _ServiceSheet(
          title: l.isArabic ? 'SyrChat Pay' : 'SyrChat Pay',
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
                showUnsupportedModuleShortcutSnackBar(context);
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
              onTap: () async {
                Navigator.pop(ctx);
                await _openPaymentsPage(initialSection: 'send');
              },
            ),
          ],
        );
      },
    );
  }

  int _archivedThreadsCount() {
    final archivedContacts = _contacts.where((c) => c.archived);
    final archivedGroups =
        _groups.where((g) => _archivedGroupIds.contains(g.id));
    return archivedContacts.length + archivedGroups.length;
  }

  bool _archivedHasUnread() {
    final archivedContacts = _contacts.where((c) => c.archived);
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
    if (_showArchived || _chatSearch.isNotEmpty || archivedCount <= 0) {
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

    final countLabel = archivedCount > 99 ? '99+' : '$archivedCount';
    final hasUnread = _archivedHasUnread();
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
            Icons.archive_outlined,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: .75),
          ),
        ),
        title: Text(
          l.isArabic ? 'الدردشات المؤرشفة' : 'Archived Chats',
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
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
        ),
        onTap: () {
          _applyState(() {
            _showArchived = true;
          });
          _resetArchivedPullDown();
        },
      ),
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
      child: SizedBox(height: _pullDownMaxHeight, child: topRow),
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
    final isDark = theme.brightness == Brightness.dark;
    final label = _otherDeviceLabel;
    final title = label != null && label.isNotEmpty
        ? (l.isArabic ? 'نشط على $label' : 'Active on $label')
        : (l.isArabic ? 'سرتشات ويب نشط' : 'SyrChat Web active');
    final subtitle = l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices';
    return Material(
      color: isDark
          ? theme.colorScheme.surface.withValues(alpha: .96)
          : const Color(0xFFF7F7F7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DevicesPage(baseUrl: widget.baseUrl),
                ),
              );
            },
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.devices_other_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .86),
                        ),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: isDark ? .55 : .48),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: .34),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: .5,
            indent: 16,
            endIndent: 12,
            color: theme.dividerColor.withValues(alpha: isDark ? .40 : .70),
          ),
        ],
      ),
    );
  }

  Future<void> _handleScanPayload(String raw) async {
    final l = L10n.of(context);
    final s = raw.trim();
    if (s.isEmpty) return;
    if (s.length > _shamellChatScanPayloadMaxChars) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.shamellUnrecognizedQr),
        ),
      );
      return;
    }
    final parsed = Uri.tryParse(s);
    final uri =
        parsed == null ? null : normalizeShamellChatScannedInboundUri(parsed);
    final miniProgramPipeTarget = parseMiniProgramPipePayload(s);
    if (miniProgramPipeTarget != null) {
      await _openMiniProgramTarget(miniProgramPipeTarget);
      return;
    }
    if (uri != null && uri.scheme.toLowerCase() == 'shamell') {
      if (!shamellChatAllowsScannedCustomSchemeUri(uri)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.shamellUnrecognizedQr),
          ),
        );
        return;
      }
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
            ? 'رمز الصديق لم يعد مدعوماً. اطلب رمز دعوة جديد.'
            : 'This friend QR is no longer supported. Ask for a new invite QR.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      } else if (host == 'device_login') {
        final token = (uri.queryParameters['token'] ?? '').trim();
        final label = sanitizeDeviceLoginLabel(uri.queryParameters['label']);
        if (token.isNotEmpty) {
          await _confirmDeviceLogin(token, label: label);
          return;
        }
      }
      final miniProgramTarget = parseMiniProgramDeepLink(uri);
      if (miniProgramTarget != null) {
        await _openMiniProgramTarget(miniProgramTarget);
        return;
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
    final token = rawToken.trim().toLowerCase();
    if (token.isEmpty) return;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'رمز الدعوة غير صالح.' : 'Invalid invite token.',
          ),
        ),
      );
      return;
    }
    try {
      await _syncChatIdentityFromStoreIfChanged();
      final peerId = await _service.redeemContactInviteTokenEnsured(token);
      await _syncChatIdentityFromStoreIfChanged();
      await _resolvePeer(
        presetId: peerId,
        silentInboxRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _tabIndex = 0;
      });
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      if (!mounted) return;
      final message = e is ChatHttpException
          ? sanitizeHttpError(
              statusCode: e.statusCode,
              rawBody: e.body,
              isArabic: l.isArabic,
            )
          : sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }
  }

  /// Cycle 47 — gate very long message bodies behind a "Show more"
  /// tap target so the thread doesn't get visually monopolised by a
  /// single 5-KB paste. The threshold is character-count based (not
  /// line-count) because the renderer reflows by glyph width — 600
  /// chars usually covers ~12 short lines on a phone.
  static const int _longBubbleCharCap = 600;

  Widget _buildPossiblyTruncatedBody(
    ChatMessage m,
    DirectMessageTextPresentation presentation,
  ) {
    final full = presentation.plainText;
    if (_expandedLongMessageIds.contains(m.id) ||
        full.length <= _longBubbleCharCap) {
      return _renderBubbleTextPresentation(context, presentation);
    }
    final theme = Theme.of(context);
    final l = L10n.of(context);
    // Trim to a clean word boundary when possible.
    var cut = _longBubbleCharCap;
    final ws = full.lastIndexOf(' ', _longBubbleCharCap);
    if (ws > _longBubbleCharCap - 80) cut = ws;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${full.substring(0, cut).trimRight()}…',
          softWrap: true,
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() {
            _expandedLongMessageIds.add(m.id);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              l.isArabic ? 'عرض المزيد' : 'Show more',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _renderBubbleTextPresentation(
    BuildContext context,
    DirectMessageTextPresentation presentation,
  ) {
    // Cycle 17: when no search-highlight overlay is needed, route
    // through `ChatLinkifiedText` so URLs in the body render as
    // tappable spans that open in the system browser. The highlight
    // path keeps the plain RichText for now — combining linkify +
    // highlight ranges is a Cycle 18 polish.
    if (!presentation.hasHighlights) {
      return ChatLinkifiedText(text: presentation.plainText);
    }
    final theme = Theme.of(context);
    final baseStyle = DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: <TextSpan>[
          for (final segment in presentation.segments)
            TextSpan(
              text: segment.text,
              style: segment.kind == DirectMessageTextSegmentKind.highlight
                  ? TextStyle(
                      backgroundColor: theme.colorScheme.secondaryContainer
                          .withValues(alpha: .9),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _buildFileAttachmentCard({
    required ThemeData theme,
    required bool isDark,
    required L10n l,
    required Uint8List bytes,
    required String mime,
    bool interactive = true,
  }) {
    final title = l.isArabic ? 'مرفق' : 'Attachment';
    final subtitle =
        mime.trim().isNotEmpty ? mime.trim() : (l.isArabic ? 'ملف' : 'File');
    return InkWell(
      onTap: interactive ? () => _shareAttachment(bytes, mime) : null,
      onLongPress: interactive ? () => _shareAttachment(bytes, mime) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surface
              : Colors.white.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withValues(alpha: .10),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary
                    .withValues(alpha: isDark ? .24 : .14),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Icon(
                mime.startsWith('video/')
                    ? Icons.videocam_outlined
                    : Icons.insert_drive_file_outlined,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: .55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.share_outlined,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: .45),
            ),
          ],
        ),
      ),
    );
  }

  String _resolvedComposerAttachmentMime() {
    final explicitMime = (_attachedMime ?? '').trim().toLowerCase();
    if (explicitMime.isNotEmpty) {
      return explicitMime;
    }
    final name = (_attachedName ?? '').trim().toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.mp4')) return 'video/mp4';
    if (name.endsWith('.mov')) return 'video/quicktime';
    if (name.endsWith('.pdf')) return 'application/pdf';
    return '';
  }

  bool _composerAttachmentShowsInlineImage(String mime) {
    if (mime.startsWith('image/')) {
      return true;
    }
    if (mime.isNotEmpty) {
      return false;
    }
    final name = (_attachedName ?? '').trim().toLowerCase();
    return name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.heic') ||
        name.endsWith('.heif') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif');
  }

  Widget _buildComposerAttachmentPreview({
    required ThemeData theme,
    required bool isDark,
    required L10n l,
  }) {
    final bytes = _attachedBytes;
    if (bytes == null || bytes.isEmpty) {
      return const SizedBox.shrink();
    }
    final mime = _resolvedComposerAttachmentMime();
    final showsInlineImage = _composerAttachmentShowsInlineImage(mime);
    final fileName = (_attachedName ?? '').trim();
    final title = fileName.isNotEmpty
        ? fileName
        : (showsInlineImage
            ? l.shamellImageAttached
            : (l.isArabic ? 'مرفق' : 'Attachment'));
    final subtitle = mime.isNotEmpty
        ? mime
        : (showsInlineImage
            ? (l.isArabic ? 'صورة' : 'Image')
            : (l.isArabic ? 'ملف' : 'File'));
    final previewIcon = mime.startsWith('video/')
        ? Icons.videocam_outlined
        : Icons.insert_drive_file_outlined;

    Widget leadingPreview() {
      if (!showsInlineImage) {
        return Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surface
                : Colors.white.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: isDark ? .25 : .40),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(previewIcon, size: 26),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          // 72px logical × 3x DPR cap → 216px raw cache. Without this
          // each contact-card thumbnail at retina holds the full
          // ~4 MB photo in memory; the chat list with 50 contacts
          // would balloon to 200 MB before any messages render.
          cacheWidth: 216,
          cacheHeight: 216,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) {
            return Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surface
                    : Colors.white.withValues(alpha: .95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      theme.dividerColor.withValues(alpha: isDark ? .25 : .40),
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, size: 24),
            );
          },
        ),
      );
    }

    return Row(
      children: [
        leadingPreview(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: .60),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: l.shamellRemoveAttachment,
          onPressed: () {
            _applyState(() {
              _attachedBytes = null;
              _attachedMime = null;
              _attachedName = null;
            });
          },
          icon: const Icon(Icons.close),
        ),
      ],
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
                  showUnsupportedModuleShortcutSnackBar(context);
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
                  _openMomentsSurface();
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
        : (l.isArabic ? 'سرتشات' : 'SyrChat');
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
                  l.isArabic ? 'معرّف سرتشات: $idLabel' : 'SyrChat ID: $idLabel',
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
            onPressed: () => unawaited(_showInviteQr()),
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
          // Discover shortcuts (some surfaces are currently unavailable).
          section([
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
                _openMomentsSurface();
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
                    'official_open_directory_from_chats_favorites_tile');
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
          // Official accounts – similar to SyrChat Official Accounts
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
                _openOfficialAccountsDirectory();
              },
            ),
          ]),
          const SizedBox(height: 12),
          // Scan
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
          ]),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'الخدمات' : 'Services',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          section([
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('SyrChat Pay'),
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

    final topTiles = <Widget>[];

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
            _openOfficialAccountsDirectory();
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
        onTap: () => showUnsupportedModuleShortcutSnackBar(context),
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
  Widget _buildShamellTimeHeader(DateTime ts) {
    final theme = Theme.of(context);
    final ml = MaterialLocalizations.of(context);
    final l = L10n.of(context);
    final local = ts.toLocal();
    final time = ml.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    // Relative day label — Today / Yesterday / weekday name / short
    // date. The previous absolute `yyyy-mm-dd · 12:34` header read like
    // a server log; iMessage / WhatsApp / Telegram all use relative
    // labels so the user can scan the timeline at a glance. We thread
    // through `shortDateFormatter` and `weekdayFormatter` so the helper
    // stays unit-testable without a BuildContext (see
    // `chat_send_status_test.dart`). The weekday array is inlined per
    // locale because Material's `formatFullDate` returns the full
    // sentence ("Wednesday, May 13, 2026"), which is too long for a
    // chat day separator — we want only the weekday name.
    const enWeekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const arWeekdays = <String>[
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    final dayLabel = chatMessageDateHeaderLabel(
      local,
      now: DateTime.now(),
      isArabic: l.isArabic,
      shortDateFormatter: ml.formatShortDate,
      weekdayFormatter: (d) =>
          (l.isArabic ? arWeekdays : enWeekdays)[d.weekday - 1],
    );
    final label = '$dayLabel · $time';
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
    final unreadKeys = Set<String>.from(_unread.keys);
    final now = DateTime.now();
    final groupIds = _unread.entries
        .where((e) => e.key.startsWith('grp:') && e.value > 0)
        .map((e) => e.key.substring(4))
        .where((gid) => gid.trim().isNotEmpty)
        .toSet();
    for (final gid in groupIds) {
      try {
        await _store.setGroupSeen(
          gid,
          now,
          baseUrlOverride: widget.baseUrl,
        );
      } catch (_) {}
    }
    _applyState(() {
      _unread = {for (final e in _unread.entries) e.key: 0};
      _groupMentionUnread = <String>{};
      _groupMentionAllUnread = <String>{};
    });
    _startMarkAllChatsReadUnreadBatchSave(_unread, unreadKeys);
  }

  Future<void> _markSelectedChatsRead() async {
    if (_selectedChatIds.isEmpty) return;
    final selectedChatIds = Set<String>.from(_selectedChatIds);
    final now = DateTime.now();
    final groupIds = selectedChatIds
        .where((id) => id.startsWith('grp:'))
        .map((id) => id.substring(4))
        .where((gid) => gid.trim().isNotEmpty)
        .toSet();
    for (final gid in groupIds) {
      try {
        await _store.setGroupSeen(
          gid,
          now,
          baseUrlOverride: widget.baseUrl,
        );
      } catch (_) {}
    }
    final next = Map<String, int>.from(_unread);
    for (final id in selectedChatIds) {
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
    await _saveUnreadCountsForKeys(_unread, selectedChatIds);
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
    final updatedContactsForPeers = <ChatContact>[];
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      if (!contactIds.contains(c.id) || !c.archived) continue;
      final updated = c.copyWith(archived: false);
      contacts[i] = updated;
      updatedContactsForPeers.add(updated);
      contactsChanged = true;
      if (updatedPeer?.id == updated.id) {
        updatedPeer = updated;
      }
    }
    if (contactsChanged) {
      try {
        await _saveScopedContactsForPeers(updatedContactsForPeers);
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
      for (final gid in groupIds) {
        if (!nextArchivedGroups.contains(gid)) {
          await _persistArchivedGroupState(gid, false);
        }
      }
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
        await _store.deleteMessages(id, baseUrlOverride: widget.baseUrl);
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
          await _store.clearPeer(baseUrlOverride: widget.baseUrl);
        } catch (_) {}
        clearedActivePeer = true;
      }
    }
    for (final gid in groupIds) {
      try {
        await _store.deleteGroupMessages(
          gid,
          baseUrlOverride: widget.baseUrl,
        );
      } catch (_) {}
      try {
        await _store.deleteGroupKey(gid, baseUrlOverride: widget.baseUrl);
      } catch (_) {}
      _groupCache.remove(gid);
      _unread.remove('grp:$gid');
    }
    await _removeScopedContactsForPeers(contactIds);
    await _saveUnreadCountsForKeys(_unread, ids);
    try {
      await _saveDraftsSnapshot(_draftTextByChatId);
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
      await _removeScopedContactsForPeers(<String>[id]);
    } catch (_) {}
    try {
      await _store.deleteMessages(id, baseUrlOverride: widget.baseUrl);
    } catch (_) {}
    _draftTextByChatId.remove(id);
    _composerDraftByChatId.remove(id);
    try {
      await _saveDraftsSnapshot(_draftTextByChatId);
    } catch (_) {}
    _unread.remove(id);
    try {
      await _saveUnreadCountForPeer(id, 0);
    } catch (_) {}
    _cache.remove(id);
    if (_activePeerId == id) {
      _activePeerId = null;
      _peer = null;
      _messages = [];
      try {
        await _store.clearPeer(baseUrlOverride: widget.baseUrl);
      } catch (_) {}
    }
    _applyState(() {
      _contacts = remaining;
    });
  }

  Future<void> _toggleChatReadUnread(ChatContact c) async {
    final cur = _unread[c.id] ?? 0;
    final nextUnreadCount = cur != 0 ? 0 : -1;
    _applyState(() {
      _unread[c.id] = nextUnreadCount;
    });
    try {
      await _saveUnreadCountForPeer(c.id, nextUnreadCount);
    } catch (_) {}
  }

  Future<void> _setChatMuted(ChatContact c, bool muted) async {
    final updated = c.copyWith(muted: muted);
    final contacts = _upsertContact(updated);
    try {
      await _saveScopedContactsForPeers(<ChatContact>[updated]);
    } catch (_) {}
    try {
      final me = _me;
      if (me != null) {
        await _service.setPrefs(
          deviceId: me.id,
          peerId: c.id,
          muted: updated.muted,
          starred: updated.starred,
          pinned: updated.pinned,
        );
      }
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
    }
    if (!mounted) return;
    _applyState(() {
      _contacts = contacts;
      if (_peer?.id == updated.id) _peer = updated;
    });
  }

  Future<void> _toggleChatMuted(ChatContact c) async {
    await _setChatMuted(c, !c.muted);
  }

  // ───────────────────── Cycle 7 — snooze + saved replies ─────────────────────

  /// Loads existing per-conversation snooze rows from the server and
  /// hydrates `_peerSnoozedUntil`. Best-effort: a network failure
  /// leaves the map empty (the AppBar icon shows "outlined" and the
  /// picker shows no "Clear snooze" row — both safe defaults).
  Future<void> _loadConversationSnoozes() async {
    final me = _me;
    if (me == null) return;
    try {
      final rows = await _service.listConversationSnoozes(deviceId: me.id);
      if (!mounted) return;
      final now = DateTime.now();
      final next = <String, DateTime>{};
      for (final row in rows) {
        final peerId = (row['peer_id'] as String?)?.trim() ?? '';
        final groupId = (row['group_id'] as String?)?.trim() ?? '';
        final untilStr = (row['snoozed_until'] as String?) ?? '';
        if (untilStr.isEmpty) continue;
        final until = DateTime.tryParse(untilStr);
        if (until == null || !until.isAfter(now)) continue;
        // Key under whichever id is present. Direct rows have peer_id;
        // group rows have group_id. Both flow through the same map.
        final key = peerId.isNotEmpty ? peerId : groupId;
        if (key.isEmpty) continue;
        next[key] = until;
      }
      _applyState(() {
        _peerSnoozedUntil
          ..clear()
          ..addAll(next);
      });
    } catch (_) {
      // Swallow — snooze state is best-effort UX polish.
    }
  }

  /// Opens the snooze duration picker for a direct conversation. On
  /// selection: writes through to the server, updates the local cache,
  /// and surfaces a snackbar confirmation. `seconds == 0` clears.
  Future<void> _openSnoozePicker(ChatContact peer) async {
    final me = _me;
    if (me == null || !mounted) return;
    final l = L10n.of(context);
    final now = DateTime.now();
    final existing = _peerSnoozedUntil[peer.id];
    final isSnoozed = existing != null && existing.isAfter(now);
    String? label;
    if (isSnoozed) {
      final remaining = existing.difference(now);
      String human;
      if (remaining.inHours >= 24) {
        final days = remaining.inDays;
        human = l.isArabic ? '$days يوم' : '$days d';
      } else if (remaining.inMinutes >= 60) {
        final hours = remaining.inHours;
        human = l.isArabic ? '$hours ساعة' : '${hours}h';
      } else {
        final mins = remaining.inMinutes.clamp(1, 60);
        human = l.isArabic ? '$mins دقيقة' : '${mins}m';
      }
      label = l.isArabic ? 'الإيقاف لـ $human' : 'Snoozed for $human';
    }
    final picked = await ChatSnoozePickerSheet.show(
      context,
      currentlySnoozed: isSnoozed,
      currentSnoozeLabel: label,
    );
    if (picked == null || !mounted) return;
    try {
      await _service.setConversationSnooze(
        deviceId: me.id,
        peerId: peer.id,
        seconds: picked,
      );
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic
              ? 'تعذّر حفظ إعداد الإيقاف.'
              : 'Could not save snooze.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    _applyState(() {
      if (picked <= 0) {
        _peerSnoozedUntil.remove(peer.id);
      } else {
        _peerSnoozedUntil[peer.id] =
            DateTime.now().add(Duration(seconds: picked));
      }
    });
    final msg = picked <= 0
        ? (l.isArabic ? 'تم إلغاء إيقاف الإشعارات.' : 'Snooze cleared.')
        : (l.isArabic ? 'تم إيقاف الإشعارات.' : 'Notifications snoozed.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Opens the saved-replies palette and splices the chosen body into
  /// the message composer at the current caret position. Fetches the
  /// reply list lazily — a heavy user with hundreds of templates won't
  /// pay the cost until they actually open the palette.
  Future<void> _openSavedRepliesPalette(ChatIdentity me) async {
    if (!mounted) return;
    final l = L10n.of(context);
    List<ChatSavedReply> replies;
    try {
      final rows = await _service.listSavedReplies(deviceId: me.id);
      replies = rows.map(ChatSavedReply.fromMap).toList(growable: false);
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic
              ? 'تعذّر تحميل الردود.'
              : 'Could not load saved replies.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final body = await ChatSavedRepliesPalette.show(
      context,
      replies: replies,
      // Cycle 11: wire the "Manage replies" row. Tapping it pops the
      // palette with `null` and immediately pushes the CRUD page; on
      // return the next palette open will refetch fresh data.
      onManage: () => _openSavedRepliesManagePage(me),
    );
    if (body == null || body.isEmpty || !mounted) return;
    // Splice at the caret. If the field has no selection (e.g. the
    // user opened the palette without focusing the input), append.
    final ctrl = _msgCtrl;
    final sel = ctrl.selection;
    final current = ctrl.text;
    final hasValidSelection =
        sel.start >= 0 && sel.end <= current.length && sel.start <= sel.end;
    if (!hasValidSelection) {
      final merged = current.isEmpty ? body : '$current $body';
      ctrl.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
    } else {
      final before = current.substring(0, sel.start);
      final after = current.substring(sel.end);
      final merged = '$before$body$after';
      ctrl.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: sel.start + body.length),
      );
    }
    FocusScope.of(context).requestFocus(_composerFocus);
  }

  /// Cycle 28 — dispatch a parsed slash command from the composer.
  /// Returns `true` when the command short-circuits the send (the
  /// caller should NOT proceed with a regular send); `false` when
  /// the command rewrote the composer text and a regular send
  /// should proceed.
  Future<bool> _handleSlashCommand(ParsedSlashCommand cmd) async {
    switch (cmd.name) {
      case 'poll':
        final peer = _peer;
        if (peer == null) return false;
        // Clear the `/poll` text from the composer first so the
        // poll-message body doesn't include the trigger.
        _suppressDraftListener = true;
        try {
          _msgCtrl.clear();
        } finally {
          _suppressDraftListener = false;
        }
        await _composePoll(peer);
        return true;
      case 'me':
        final me = _me;
        final senderName = (me?.displayName?.trim().isNotEmpty ?? false)
            ? me!.displayName!
            : (me?.id ?? '');
        final rewritten = buildMeMessage(
          senderName: senderName,
          rest: cmd.rest,
        );
        _suppressDraftListener = true;
        try {
          _msgCtrl.value = TextEditingValue(
            text: rewritten,
            selection: TextSelection.collapsed(offset: rewritten.length),
          );
        } finally {
          _suppressDraftListener = false;
        }
        return false;
      case 'shrug':
        final tail = cmd.rest.isEmpty ? '' : '${cmd.rest} ';
        // Backslash needs double-escape in Dart literals; the user
        // sees `¯\_(ツ)_/¯`.
        final shrug = '$tail¯\\_(ツ)_/¯';
        _suppressDraftListener = true;
        try {
          _msgCtrl.value = TextEditingValue(
            text: shrug,
            selection: TextSelection.collapsed(offset: shrug.length),
          );
        } finally {
          _suppressDraftListener = false;
        }
        return false;
      default:
        // Unknown command — let it through as a regular message.
        return false;
    }
  }

  /// Cycle 14: open the poll creator dialog. On submit, send the
  /// regular chat message (so the recipient sees a normal bubble
  /// with the question text — the bubble auto-upgrade to a poll
  /// widget is the natural Cycle 15 polish), then register the
  /// server-side tally bookkeeping via `ChatService.createPoll`.
  /// Surfacing the failure path so the user knows when the poll
  /// can't be registered (e.g. duplicate message id).
  Future<void> _composePoll(ChatContact peer) async {
    if (!mounted) return;
    final me = _me;
    if (me == null) return;
    final l = L10n.of(context);
    final draft = await ChatPollCreatorDialog.show(context);
    if (draft == null || !mounted) return;

    // Compose a regular send whose body carries the poll question +
    // serialised options. The chat-page send path doesn't expose a
    // direct "send arbitrary text" hook, so we stage the body into
    // the composer + call `_send`. That preserves all the regular
    // ratchet / sealed-sender / retry handling we've built up.
    final lines = <String>[
      '📊 ${draft.question}',
      for (int i = 0; i < draft.options.length; i++)
        '${i + 1}. ${draft.options[i]}',
    ];
    final messageBody = lines.join('\n');
    final prevText = _msgCtrl.text;
    _msgCtrl.value = TextEditingValue(
      text: messageBody,
      selection: TextSelection.collapsed(offset: messageBody.length),
    );
    // We send through the normal `_send` path. After it returns
    // successfully, `_messages` has the newly-acked message at the
    // tail — we use its id to register the poll bookkeeping.
    final before = _messages.length;
    try {
      await _send();
    } catch (_) {
      _msgCtrl.value = TextEditingValue(text: prevText);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            l.isArabic ? 'تعذّر إرسال الاستطلاع.' : 'Could not send poll.')),
      );
      return;
    }
    if (!mounted) return;
    // Find the just-sent message id. The send path appends one row;
    // if the tail isn't newer than `before` we don't have an id to
    // wire — the user still sees the bubble; only the vote tally
    // bookkeeping is skipped.
    final newId = (_messages.length > before)
        ? _messages.last.id
        : null;
    if (newId == null || newId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.isArabic
            ? 'تم إرسال الاستطلاع — تتبّع الأصوات معطل.'
            : 'Poll sent — vote tally bookkeeping skipped.')),
      );
      return;
    }
    try {
      await _service.createPoll(
        deviceId: me.id,
        messageId: newId,
        question: draft.question,
        options: draft.options,
        multiSelect: draft.multiSelect,
        anonymous: draft.anonymous,
      );
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.isArabic
            ? 'تم إرسال الرسالة لكن تعذّر تسجيل الاستطلاع.'
            : 'Message sent but poll registration failed.')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.isArabic ? 'تم إرسال الاستطلاع' : 'Poll sent')),
    );
  }

  // ─────────── Cycle 16 — inline voice-transcript rendering ───────────

  /// Sentinel stored in `_voiceTranscriptByMessageId` when the
  /// server confirms no transcript exists. Distinguishes "absent"
  /// from "still loading" (`null`) without an extra type wrapper.
  static const String _transcriptSentinelMissing = '__no_transcript__';

  /// Side-effect helper: kicks a one-time `fetchVoiceTranscript`
  /// lookup per message id. Subsequent renders read the cached
  /// result; the dispatcher only renders inline when we have a
  /// non-empty string. Missing / loading states stay invisible so
  /// the bubble doesn't show empty placeholders.
  void _maybeKickVoiceTranscriptFetch(String messageId) {
    if (messageId.isEmpty) return;
    if (_voiceTranscriptByMessageId.containsKey(messageId)) return;
    final me = _me;
    if (me == null) return;
    _voiceTranscriptByMessageId[messageId] = null;
    () async {
      String? transcript;
      try {
        transcript = await _service.fetchVoiceTranscript(
          deviceId: me.id,
          messageId: messageId,
        );
      } catch (_) {
        transcript = null;
      }
      if (!mounted) return;
      _applyState(() {
        final value = (transcript ?? '').trim();
        _voiceTranscriptByMessageId[messageId] =
            value.isEmpty ? _transcriptSentinelMissing : value;
      });
    }();
  }

  /// Returns the cached transcript text for a message, or `null`
  /// when the inline display should hide (missing / loading).
  String? _loadedTranscriptFor(String messageId) {
    final v = _voiceTranscriptByMessageId[messageId];
    return v is String && v != _transcriptSentinelMissing ? v : null;
  }

  // ────────────── Cycle 15 — bubble auto-upgrade for polls ──────────────

  /// Sentinel stored in `_pollByMessageId` when the server confirms
  /// that a message has no attached poll. Distinct from `null` so
  /// the dispatcher can tell "loading" apart from "definitely not a
  /// poll" without an extra type wrapper.
  static const String _pollSentinelNotPoll = '__not_poll__';

  /// Lightweight heuristic: poll messages composed by
  /// [_composePoll] begin with "📊 ". Any other prefix is skipped to
  /// avoid spending an HTTP round trip on every text message in
  /// the thread.
  bool _isPollHeuristicMatch(String text) => text.startsWith('📊 ');

  /// Side-effect helper called from the bubble builder on every
  /// render. Kicks a one-time fetch per message id; no-op once the
  /// cache slot is populated (loading / loaded / not-poll).
  void _maybeKickPollFetch(String messageId, String text) {
    if (messageId.isEmpty) return;
    if (!_isPollHeuristicMatch(text)) return;
    if (_pollByMessageId.containsKey(messageId)) return;
    final me = _me;
    if (me == null) return;
    // Mark in-flight so concurrent renders don't pile on duplicate
    // fetches for the same message.
    _pollByMessageId[messageId] = null;
    () async {
      try {
        final raw = await _service.getPollByMessage(
          deviceId: me.id,
          messageId: messageId,
        );
        if (!mounted) return;
        _applyState(() {
          _pollByMessageId[messageId] = raw;
        });
      } catch (e) {
        if (!mounted) return;
        _applyState(() {
          _pollByMessageId[messageId] = _pollSentinelNotPoll;
        });
      }
    }();
  }

  /// Returns the cached poll payload Map for a message, or `null`
  /// when the bubble dispatcher should NOT render a poll widget
  /// (loading / sentinel / heuristic miss).
  Map<String, Object?>? _loadedPollFor(String messageId) {
    final v = _pollByMessageId[messageId];
    if (v is Map<String, Object?>) return v;
    return null;
  }

  /// Build the poll bubble from cached server data + the active
  /// device identity. Owns the vote / close interactions: each tap
  /// fires a service call, then evicts the cache slot so the next
  /// render fires a fresh `getPollByMessage` for the updated tally.
  Widget _buildPollBubbleForMessage(ChatMessage m, Map<String, Object?> data) {
    final me = _me;
    final question = (data['question'] as String?) ?? '';
    final multiSelect = (data['multi_select'] as bool?) ?? false;
    final closed = (data['closed'] as bool?) ?? false;
    final totalVoters = (data['total_voters'] is int)
        ? data['total_voters'] as int
        : ((data['total_voters'] is num)
            ? (data['total_voters'] as num).toInt()
            : 0);
    final myVotesRaw = (data['my_votes'] as List?) ?? const <Object?>[];
    final myVotes = <int>{
      for (final v in myVotesRaw)
        if (v is int)
          v
        else if (v is num)
          v.toInt(),
    };
    final optionsRaw = (data['options'] as List?) ?? const <Object?>[];
    final options = <ChatPollOption>[
      for (final o in optionsRaw)
        if (o is Map<String, Object?>)
          ChatPollOption.fromMap(o, myVotes: myVotes),
    ];
    final isCreator =
        me != null && (data['creator_id'] as String?) == me.id;
    return ChatPollBubble(
      question: question,
      options: options,
      multiSelect: multiSelect,
      closed: closed,
      totalVoters: totalVoters,
      isCreator: isCreator,
      onVote: closed
          ? null
          : (idx) async {
              await _onPollVoteTap(data, idx);
            },
      onClose: (isCreator && !closed)
          ? () async {
              await _onPollCloseTap(data);
            }
          : null,
    );
  }

  Future<void> _onPollVoteTap(
      Map<String, Object?> pollData, int idx) async {
    final me = _me;
    if (me == null || !mounted) return;
    final pollId = (pollData['id'] as String?) ?? '';
    final messageId = (pollData['message_id'] as String?) ?? '';
    if (pollId.isEmpty) return;
    final multiSelect = (pollData['multi_select'] as bool?) ?? false;
    final myVotes = <int>{
      for (final v in (pollData['my_votes'] as List?) ?? const <Object?>[])
        if (v is int) v else if (v is num) v.toInt(),
    };
    final next = multiSelect
        ? (myVotes.contains(idx)
            ? myVotes.where((v) => v != idx).toList()
            : <int>[...myVotes, idx])
        : (myVotes.contains(idx) ? <int>[] : <int>[idx]);
    try {
      await _service.votePoll(
        deviceId: me.id,
        pollId: pollId,
        optionIdxs: next,
      );
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      return;
    }
    if (!mounted) return;
    _applyState(() {
      _pollByMessageId.remove(messageId);
    });
  }

  Future<void> _onPollCloseTap(Map<String, Object?> pollData) async {
    final me = _me;
    if (me == null || !mounted) return;
    final pollId = (pollData['id'] as String?) ?? '';
    final messageId = (pollData['message_id'] as String?) ?? '';
    if (pollId.isEmpty) return;
    try {
      await _service.closePoll(deviceId: me.id, pollId: pollId);
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      return;
    }
    if (!mounted) return;
    _applyState(() {
      _pollByMessageId.remove(messageId);
    });
  }

  /// Cycle 38 — render an OG link-preview card under a text bubble.
  /// The first http(s) URL in [bodyText] is detected; if cached we
  /// render synchronously; otherwise we kick off a fetch and show
  /// `SizedBox.shrink()` until the result lands (no spinner — the
  /// card just materialises). Errors are silent.
  Widget _buildLinkPreviewCard(
    ChatMessage m,
    String bodyText, {
    required bool incoming,
  }) {
    final uri = chatFirstUrl(bodyText);
    if (uri == null) return const SizedBox.shrink();
    final key = uri.toString();
    final cached = chatLinkPreviewCached(key);
    final isCached = chatLinkPreviewIsCached(key);
    if (!isCached) {
      // Best-effort fetch; rebuild this bubble when it lands.
      // ignore: discarded_futures
      chatFetchLinkPreview(uri).then((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }
    if (cached == null || !cached.hasContent) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? Colors.black.withValues(alpha: .25)
        : Colors.white.withValues(alpha: .60);
    final border = incoming
        ? theme.colorScheme.outlineVariant.withValues(alpha: .50)
        : theme.colorScheme.outline.withValues(alpha: .40);
    final title = cached.title?.trim() ?? '';
    final description = cached.description?.trim() ?? '';
    final image = cached.imageUrl?.trim() ?? '';
    final site = cached.siteName?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (image.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (site.isNotEmpty)
                        Text(
                          site.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                      if (title.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (description.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cycle 37 — emit a single presence heartbeat for the current
  /// account. Best-effort; failures are silently swallowed so a brief
  /// network blip doesn't crash the chat surface.
  Future<void> _emitPresenceHeartbeat() async {
    final me = _me;
    if (me == null) return;
    try {
      await _service.presenceHeartbeat(deviceId: me.id);
    } catch (_) {
      // Best-effort — no UI surface for the heartbeat failing.
    }
  }

  /// Cycle 37 — refresh last_seen_at for the currently-loaded
  /// contact set. Quietly fails offline. The result feeds the chat
  /// thread AppBar subtitle and (future) chat-list row subtitles.
  Future<void> _refreshPeerPresence() async {
    final me = _me;
    if (me == null || _contacts.isEmpty) return;
    final ids = _contacts
        .map((c) => c.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;
    try {
      final rows = await _service.listPeerPresence(
        deviceId: me.id,
        peerIds: ids,
      );
      if (!mounted) return;
      final next = <String, DateTime>{};
      for (final row in rows) {
        final pid = (row['device_id'] as String?)?.trim();
        final isoLastSeen = (row['last_seen_at'] as String?)?.trim();
        if (pid == null || pid.isEmpty || isoLastSeen == null) continue;
        try {
          next[pid] = DateTime.parse(isoLastSeen).toLocal();
        } catch (_) {}
      }
      setState(() {
        _peerLastSeenAt
          ..clear()
          ..addAll(next);
      });
    } catch (_) {
      // Quiet: presence is decorative.
    }
  }

  /// Cycle 63 — pull the caller's per-conversation notification
  /// preview overrides into a local map. Quietly fails offline.
  Future<void> _loadConversationNotificationPrefs() async {
    final me = _me;
    if (me == null) return;
    try {
      final rows = await _service
          .listConversationNotificationPrefs(deviceId: me.id);
      if (!mounted) return;
      final next = <String, String>{};
      for (final row in rows) {
        final mode = (row['preview_mode'] as String?)?.trim() ?? '';
        if (mode.isEmpty) continue;
        final pid = (row['peer_id'] as String?)?.trim();
        if (pid != null && pid.isNotEmpty) {
          next[pid] = mode;
          continue;
        }
        final gid = (row['group_id'] as String?)?.trim();
        if (gid != null && gid.isNotEmpty) {
          next[gid] = mode;
        }
      }
      setState(() {
        _conversationNotificationPreviewMode
          ..clear()
          ..addAll(next);
      });
    } catch (_) {
      // Quiet: pref data is best-effort.
    }
  }

  /// Cycle 63 — save a new preview mode for a peer/group. Updates
  /// the local cache optimistically.
  Future<void> _setConversationPreviewMode({
    required String targetId,
    required bool isGroup,
    required String mode,
  }) async {
    final me = _me;
    if (me == null) return;
    final prev = _conversationNotificationPreviewMode[targetId];
    setState(() {
      if (mode == 'default') {
        _conversationNotificationPreviewMode.remove(targetId);
      } else {
        _conversationNotificationPreviewMode[targetId] = mode;
      }
    });
    try {
      await _service.setConversationNotificationPref(
        deviceId: me.id,
        peerId: isGroup ? null : targetId,
        groupId: isGroup ? targetId : null,
        previewMode: mode,
      );
    } catch (_) {
      if (!mounted) return;
      // Roll back on failure.
      setState(() {
        if (prev == null) {
          _conversationNotificationPreviewMode.remove(targetId);
        } else {
          _conversationNotificationPreviewMode[targetId] = prev;
        }
      });
    }
  }

  /// Cycle 60 — refresh exactly one peer's profile (used by the
  /// `profile_updated` event handler so a single peer's change
  /// shows up instantly without re-fetching the entire contact set).
  Future<void> _refreshSinglePeerProfile(String peerId) async {
    final me = _me;
    if (me == null || peerId.isEmpty) return;
    try {
      final rows = await _service
          .listPeerProfiles(deviceId: me.id, peerIds: <String>[peerId]);
      if (!mounted || rows.isEmpty) return;
      final row = rows.first;
      final pid = (row['device_id'] as String?)?.trim();
      if (pid == null || pid.isEmpty || pid != peerId) return;
      String? newName;
      Uint8List? newBytes;
      String? newEmoji;
      String? newStatusText;
      final n = (row['display_name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) newName = n;
      final b64 = (row['avatar_b64'] as String?)?.trim();
      if (b64 != null && b64.isNotEmpty) {
        try {
          newBytes = base64Decode(b64);
        } catch (_) {}
      }
      final em = (row['status_emoji'] as String?)?.trim();
      if (em != null && em.isNotEmpty) newEmoji = em;
      final stx = (row['status_text'] as String?)?.trim();
      if (stx != null && stx.isNotEmpty) newStatusText = stx;
      setState(() {
        if (newName == null) {
          _peerProfileDisplayName.remove(pid);
        } else {
          _peerProfileDisplayName[pid] = newName;
        }
        if (newBytes == null) {
          _peerProfileAvatarBytes.remove(pid);
        } else {
          _peerProfileAvatarBytes[pid] = newBytes;
        }
        if (newEmoji == null) {
          _peerProfileStatusEmoji.remove(pid);
        } else {
          _peerProfileStatusEmoji[pid] = newEmoji;
        }
        if (newStatusText == null) {
          _peerProfileStatusText.remove(pid);
        } else {
          _peerProfileStatusText[pid] = newStatusText;
        }
      });
    } catch (_) {
      // Quiet: profile data is decorative.
    }
  }

  /// Cycle 57 — pull peer profile data for every loaded contact +
  /// hydrate the local caches. Quietly fails offline.
  Future<void> _refreshPeerProfiles() async {
    final me = _me;
    if (me == null || _contacts.isEmpty) return;
    final ids = _contacts
        .map((c) => c.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;
    try {
      final rows =
          await _service.listPeerProfiles(deviceId: me.id, peerIds: ids);
      if (!mounted) return;
      final nextNames = <String, String>{};
      final nextBytes = <String, Uint8List>{};
      final nextEmoji = <String, String>{};
      final nextStatusText = <String, String>{};
      for (final row in rows) {
        final pid = (row['device_id'] as String?)?.trim();
        if (pid == null || pid.isEmpty) continue;
        final name = (row['display_name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          nextNames[pid] = name;
        }
        final b64 = (row['avatar_b64'] as String?)?.trim();
        if (b64 != null && b64.isNotEmpty) {
          try {
            nextBytes[pid] = base64Decode(b64);
          } catch (_) {}
        }
        final em = (row['status_emoji'] as String?)?.trim();
        if (em != null && em.isNotEmpty) {
          nextEmoji[pid] = em;
        }
        final stx = (row['status_text'] as String?)?.trim();
        if (stx != null && stx.isNotEmpty) {
          nextStatusText[pid] = stx;
        }
      }
      setState(() {
        _peerProfileDisplayName
          ..clear()
          ..addAll(nextNames);
        _peerProfileAvatarBytes
          ..clear()
          ..addAll(nextBytes);
        _peerProfileStatusEmoji
          ..clear()
          ..addAll(nextEmoji);
        _peerProfileStatusText
          ..clear()
          ..addAll(nextStatusText);
      });
    } catch (_) {
      // Quiet: profile data is decorative.
    }
  }

  /// Cycle 37 — format a peer's presence subtitle. Returns one of:
  ///   - "online" (last seen < 90s ago)
  ///   - "last seen Xm ago" (< 60m)
  ///   - "last seen Xh ago" (< 24h)
  ///   - "last seen Xd ago" (else)
  /// or null when we have no record. Localised English / Arabic.
  String? _formatPresenceSubtitle(String peerId, L10n l) {
    final ts = _peerLastSeenAt[peerId];
    if (ts == null) return null;
    final d = DateTime.now().difference(ts);
    if (d.inSeconds < 90) return l.isArabic ? 'متصل الآن' : 'online';
    if (d.inMinutes < 60) {
      return l.isArabic
          ? 'آخر ظهور قبل ${d.inMinutes} د'
          : 'last seen ${d.inMinutes}m ago';
    }
    if (d.inHours < 24) {
      return l.isArabic
          ? 'آخر ظهور قبل ${d.inHours} س'
          : 'last seen ${d.inHours}h ago';
    }
    return l.isArabic
        ? 'آخر ظهور قبل ${d.inDays} ي'
        : 'last seen ${d.inDays}d ago';
  }

  /// Cycle 36 — open Flutter's `showSearch` overlay with a delegate
  /// that filters the currently-loaded direct-thread messages by
  /// decoded text content. Tapping a result closes the overlay and
  /// scroll-jumps the thread to that message with a brief highlight.
  Future<void> _openThreadSearch() async {
    final messages = _messages;
    if (messages.isEmpty) return;
    final l = L10n.of(context);
    final pickedId = await showSearch<String?>(
      context: context,
      delegate: _ChatThreadSearchDelegate(
        messages: messages,
        decode: (m) => _decodeMessage(m).text,
        myId: _me?.id,
        hint: l.isArabic ? 'ابحث في الرسائل…' : 'Search messages…',
        emptyText: l.isArabic ? 'لا توجد نتائج.' : 'No matches.',
      ),
    );
    if (!mounted) return;
    final id = pickedId?.trim();
    if (id == null || id.isEmpty) return;
    await _scrollToMessage(id, alignment: 0.2, highlight: true);
  }

  /// Cycle 56 — open the profile editor (display name + avatar +
  /// status emoji/text since Cycle 58).
  Future<void> _openProfileEditor() async {
    final me = _me;
    if (me == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatProfileEditorPage(
          onLoad: () => _service.getMyProfile(deviceId: me.id),
          onSave: ({
            String? displayName,
            String? avatarB64,
            String? avatarMime,
            bool clearAvatar = false,
            String? statusEmoji,
            String? statusText,
            bool clearStatus = false,
          }) =>
              _service.setMyProfile(
            deviceId: me.id,
            displayName: displayName,
            avatarB64: avatarB64,
            avatarMime: avatarMime,
            clearAvatar: clearAvatar,
            statusEmoji: statusEmoji,
            statusText: statusText,
            clearStatus: clearStatus,
          ),
        ),
      ),
    );
  }

  /// Cycle 45 — open the saved-messages / bookmarks page.
  /// Bookmarks were already write-able via the long-press menu since
  /// Cycle 6; this page is the read-side.
  Future<void> _openBookmarksPage() async {
    final me = _me;
    if (me == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatBookmarksPage(
          onRefresh: () async {
            final raw = await _service.listMessageBookmarks(deviceId: me.id);
            final out = <ChatBookmarkRow>[];
            for (final m in raw) {
              final mid = (m['message_id'] as String?)?.trim() ?? '';
              if (mid.isEmpty) continue;
              final kind = (m['kind'] as String?)?.trim() ?? 'direct';
              final peerOrGroupId =
                  ((m['peer_id'] ?? m['group_id']) as String?)?.trim() ?? '';
              final preview = (m['preview'] as String?) ??
                  (m['text'] as String?) ??
                  '';
              final note = m['note'] as String?;
              DateTime? bookmarkedAt;
              try {
                final s = m['bookmarked_at'] as String?;
                if (s != null && s.isNotEmpty) {
                  bookmarkedAt = DateTime.parse(s).toLocal();
                }
              } catch (_) {}
              out.add(ChatBookmarkRow(
                messageId: mid,
                peerOrGroupId: peerOrGroupId,
                kind: kind,
                preview: preview,
                note: note,
                bookmarkedAt: bookmarkedAt,
              ));
            }
            return out;
          },
          onDelete: (mid, kind) => _service.setMessageBookmark(
            deviceId: me.id,
            messageId: mid,
            bookmarked: false,
            kind: kind,
          ),
          onJump: (row) async {
            // Close the bookmarks page, then push the thread for the
            // bookmarked peer at the saved message id. For groups
            // we fall back to a plain pop since group-thread routing
            // is owned elsewhere.
            Navigator.of(context).pop();
            if (row.kind != 'direct' || row.peerOrGroupId.isEmpty) return;
            try {
              final peer = _contacts.firstWhere(
                  (c) => c.id == row.peerOrGroupId);
              await _switchPeer(peer);
              // Best-effort scroll once messages settle.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                unawaited(_scrollToMessage(row.messageId,
                    alignment: 0.2, highlight: true));
              });
            } catch (_) {}
          },
        ),
      ),
    );
  }

  /// Cycle 30 — open the 24h-ephemeral stories page. The page owns
  /// its own list + composer state and calls these callbacks for
  /// the server round-trips.
  Future<void> _openStoriesPage() async {
    final me = _me;
    if (me == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatStoriesPage(
          myDeviceId: me.id,
          onRefresh: () async {
            final raw = await _service.listStories(deviceId: me.id);
            return raw.map<ChatStoryRow>((m) {
              final authorId = (m['author_id'] as String?) ?? '';
              // Resolve author display name from the contact cache.
              String authorDisplay = authorId;
              try {
                final match = _contacts.firstWhere(
                    (c) => c.id == authorId);
                authorDisplay = _displayNameForPeer(match);
              } catch (_) {}
              if (authorId == me.id) {
                authorDisplay = L10n.of(context).isArabic ? 'أنت' : 'You';
              }
              DateTime? expiresAt;
              try {
                final s = m['expires_at'] as String?;
                if (s != null) expiresAt = DateTime.parse(s).toLocal();
              } catch (_) {}
              // Cycle 31 — decode base64 attachment bytes once
              // during hydrate so the renderer doesn't re-decode
              // on every rebuild.
              Uint8List? imageBytes;
              try {
                final b64 = m['attachment_b64'] as String?;
                if (b64 != null && b64.isNotEmpty) {
                  imageBytes = base64Decode(b64);
                }
              } catch (_) {}
              // Cycle 33 — hydrate per-viewer reaction + total count.
              final myReaction = m['my_reaction'] as String?;
              int reactionsCount = 0;
              final rcRaw = m['reactions_count'];
              if (rcRaw is int) {
                reactionsCount = rcRaw;
              } else if (rcRaw is num) {
                reactionsCount = rcRaw.toInt();
              }
              return ChatStoryRow(
                id: (m['id'] as String?) ?? '',
                authorId: authorId,
                authorDisplay: authorDisplay,
                kind: (m['kind'] as String?) ?? 'text',
                text: m['text'] as String?,
                attachmentBytes: imageBytes,
                attachmentMime: m['attachment_mime'] as String?,
                expiresAt: expiresAt,
                isMine: authorId == me.id,
                myReaction: myReaction,
                reactionsCount: reactionsCount,
              );
            }).toList(growable: false);
          },
          onPostText: (text) async {
            await _service.createStory(
              deviceId: me.id,
              kind: 'text',
              text: text,
            );
          },
          onPostImage: (bytes, mime) async {
            await _service.createStory(
              deviceId: me.id,
              kind: 'image',
              attachmentB64: base64Encode(bytes),
              attachmentMime: mime,
            );
          },
          onDelete: (id) =>
              _service.deleteStory(deviceId: me.id, storyId: id),
          onMarkViewed: (id) =>
              _service.markStoryViewed(deviceId: me.id, storyId: id),
          onReact: (id, emoji) => _service.reactToStory(
            deviceId: me.id,
            storyId: id,
            emoji: emoji,
          ),
          onClearReaction: (id) => _service.clearStoryReaction(
            deviceId: me.id,
            storyId: id,
          ),
          onLoadStoryViews: (id) =>
              _service.listStoryViews(deviceId: me.id, storyId: id),
          onLoadStoryReactions: (id) =>
              _service.listStoryReactions(deviceId: me.id, storyId: id),
        ),
      ),
    );
  }

  /// Cycle 11: push the saved-replies CRUD page. Wired from the
  /// palette's "Manage replies" row. The page owns its own list +
  /// dialog state and just calls back through these three callbacks
  /// for the actual server round-trips.
  Future<void> _openSavedRepliesManagePage(ChatIdentity me) async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatSavedRepliesManagePage(
          onRefresh: () async {
            final rows = await _service.listSavedReplies(deviceId: me.id);
            return rows.map(ChatSavedReply.fromMap).toList(growable: false);
          },
          onSave: ({required slug, required label, required body}) =>
              _service.setSavedReply(
            deviceId: me.id,
            slug: slug,
            label: label,
            body: body,
          ),
          onDelete: (slug) => _service.deleteSavedReply(
            deviceId: me.id,
            slug: slug,
          ),
        ),
      ),
    );
  }

  // ───────────────────── Cycle 8 — scheduled messages ─────────────────────

  /// Long-press handler for the send button. Pulls the current
  /// composer text, opens the duration picker, and on selection
  /// calls `ChatService.scheduleMessage`. v1 design: the payload is
  /// the UTF-8-encoded plaintext body (NOT encrypted); the server's
  /// `chat_scheduled_messages.ciphertext` column happily stores
  /// arbitrary bytea. A future cycle will pre-encrypt against the
  /// recipient's ratchet state and add a server-side delivery
  /// worker; for now the chat page's dequeue-tick polls due rows
  /// and runs them through the regular `_send` path.
  Future<void> _openSchedulePickerForCurrentDraft() async {
    final me = _me;
    final peer = _peer;
    if (me == null || peer == null || !mounted) return;
    final l = L10n.of(context);
    final draftText = _msgCtrl.text.trim();
    if (draftText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.isArabic
            ? 'اكتب رسالة أولًا، ثم اضغط مطولًا للجدولة.'
            : 'Type a message first, then long-press to schedule.')),
      );
      return;
    }
    final picked = await ChatSchedulePickerSheet.show(context);
    if (picked == null || !mounted) return;

    // Cycle 10: build the full ratchet envelope right here using the
    // same path `_send` uses. The server's delivery worker INSERTs
    // this envelope verbatim into `chat_messages` at the scheduled
    // time, so the recipient's decryptor can't tell a scheduled
    // message from a live one — preserving E2E end-to-end.
    final draft = _FrozenDirectDraftSend(
      text: draftText,
      attachmentBytes: null,
      attachmentMime: null,
      replyToMessage: null,
    );
    try {
      final prepared = await _prepareDraftEnvelope(
        me: me,
        peer: peer,
        draft: draft,
      );
      await _service.scheduleMessage(
        deviceId: me.id,
        peerId: prepared.peer.id,
        envelope: prepared.envelope,
        scheduledFor: picked,
      );
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic
              ? 'تعذّر جدولة الرسالة.'
              : 'Could not schedule message.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final localTime = picked.toLocal();
    final hh = localTime.hour.toString().padLeft(2, '0');
    final mm = localTime.minute.toString().padLeft(2, '0');
    _msgCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // Cycle 10: the server worker now actually delivers, so the
        // copy can be honest about future delivery — not "queued and
        // hoping the app is open" as in v1.
        content: Text(l.isArabic
            ? 'تمت جدولة الرسالة للساعة $hh:$mm.'
            : 'Scheduled for $hh:$mm.'),
        action: SnackBarAction(
          label: l.isArabic ? 'عرض' : 'View',
          onPressed: _openScheduledMessagesPage,
        ),
      ),
    );
  }

  /// Push the "Scheduled messages" page. The page calls back into
  /// `ChatService.listScheduledMessages` on every refresh, and
  /// `cancelScheduledMessage` on each cancel.
  Future<void> _openScheduledMessagesPage() async {
    final me = _me;
    if (me == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScheduledMessagesPage(
          onRefresh: () => _fetchScheduledMessageRows(me.id),
          onCancel: (id) => _service.cancelScheduledMessage(
            deviceId: me.id,
            id: id,
          ),
        ),
      ),
    );
  }

  /// Hydrate raw service rows into the page's display model. Resolves
  /// peer / group names against the in-memory caches; falls back to
  /// the raw id when the recipient isn't currently known.
  Future<List<ChatScheduledMessageRow>> _fetchScheduledMessageRows(
      String deviceId) async {
    final raw = await _service.listScheduledMessages(deviceId: deviceId);
    return raw.map<ChatScheduledMessageRow>((m) {
      final id = (m['id'] as String?) ?? '';
      final peerId = m['peer_id'] as String?;
      final groupId = m['group_id'] as String?;
      final scheduledForIso = (m['scheduled_for'] as String?) ?? '';
      DateTime scheduled;
      try {
        scheduled = DateTime.parse(scheduledForIso).toLocal();
      } catch (_) {
        scheduled = DateTime.now();
      }
      String name;
      if (peerId != null && peerId.isNotEmpty) {
        final match = _contacts.where((c) => c.id == peerId).toList();
        name = match.isNotEmpty
            ? _displayNameForPeer(match.first)
            : peerId;
      } else if (groupId != null && groupId.isNotEmpty) {
        final match = _groups.where((g) => g.id == groupId).toList();
        name = match.isNotEmpty
            ? (match.first.name.isNotEmpty ? match.first.name : groupId)
            : groupId;
      } else {
        name = '?';
      }
      // Cycle 10: scheduled rows now hold the full ratchet envelope
      // rather than plaintext bytes — the sender's device can't
      // cheaply re-derive the body without re-running the ratchet
      // decryptor over its own ciphertext, so the list page shows
      // the localised "(encrypted)" placeholder instead. A future
      // polish cycle could cache the plaintext locally at schedule
      // time and surface it here.
      String? bodyPreview;
      final attemptCount = (m['attempt_count'] is int)
          ? m['attempt_count'] as int
          : ((m['attempt_count'] is num)
              ? (m['attempt_count'] as num).toInt()
              : 0);
      return ChatScheduledMessageRow(
        id: id,
        recipientName: name,
        isGroup: groupId != null && groupId.isNotEmpty,
        scheduledForLocal: scheduled,
        bodyPreview: bodyPreview,
        attemptCount: attemptCount,
        lastError: m['last_error'] as String?,
      );
    }).toList(growable: false);
  }

  Future<void> _setChatPinned(ChatContact c, bool pinned) async {
    final updated = c.copyWith(pinned: pinned);
    await _updatePinnedChatOrderForPeer(updated.id, updated.pinned);
    final contacts = _upsertContact(updated);
    try {
      await _saveScopedContactsForPeers(<ChatContact>[updated]);
    } catch (_) {}
    try {
      final me = _me;
      if (me != null) {
        await _service.setPrefs(
          deviceId: me.id,
          peerId: c.id,
          muted: updated.muted,
          starred: updated.starred,
          pinned: updated.pinned,
        );
      }
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
    }
    if (!mounted) return;
    _applyState(() {
      _contacts = contacts;
      if (_peer?.id == updated.id) _peer = updated;
    });
  }

  Future<void> _toggleChatPinned(ChatContact c) async {
    await _setChatPinned(c, !c.pinned);
  }

  Future<void> _setChatHidden(ChatContact c, bool hidden) async {
    final updated = c.copyWith(hidden: hidden);
    final contacts = _upsertContact(updated);
    try {
      await _service.setHidden(
        deviceId: _me?.id ?? '',
        peerId: c.id,
        hidden: updated.hidden,
      );
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
    }
    try {
      await _saveScopedContactsForPeers(<ChatContact>[updated]);
    } catch (_) {}
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
  }

  Future<void> _setChatBlocked(ChatContact c, bool blocked) async {
    final updated = c.copyWith(
      blocked: blocked,
      blockedAt: DateTime.now(),
    );
    final contacts = _upsertContact(updated);
    try {
      await _service.setBlock(
        deviceId: _me?.id ?? '',
        peerId: c.id,
        blocked: updated.blocked,
        hidden: updated.hidden,
      );
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
    }
    try {
      await _saveScopedContactsForPeers(<ChatContact>[updated]);
    } catch (_) {}
    if (!mounted) return;
    _applyState(() {
      _peer = updated;
      _contacts = contacts;
      if (updated.blocked && _activePeerId == c.id) {
        _messages = [];
      }
    });
  }

  Future<void> _toggleChatArchived(ChatContact c) async {
    final updated = c.copyWith(archived: !c.archived);
    final contacts = _upsertContact(updated);
    try {
      await _saveScopedContactsForPeers(<ChatContact>[updated]);
    } catch (_) {}
    _applyState(() {
      _contacts = contacts;
    });
  }

  Future<void> _setPeerDisappearSettings(ChatContact updated) async {
    final contacts = _upsertContact(updated);
    await _saveScopedContactsForPeers(<ChatContact>[updated]);
    if (!mounted) return;
    _applyState(() {
      _peer = updated;
      _contacts = contacts;
      _disappearing = updated.disappearing;
      _disappearAfter = updated.disappearAfter ?? _disappearAfter;
    });
  }

  Future<void> _toggleGroupMuted(ChatGroup g) async {
    await _setGroupMuted(g, !(_groupPrefs[g.id]?.muted ?? false));
  }

  Future<void> _setGroupMuted(ChatGroup g, bool muted) async {
    final cur = _groupPrefs[g.id] ??
        const ChatGroupPrefs(groupId: '', muted: false, pinned: false);
    final next = ChatGroupPrefs(
      groupId: g.id,
      muted: muted,
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
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
    }
    _applyState(() {});
  }

  Future<void> _toggleGroupPinned(ChatGroup g) async {
    await _setGroupPinned(g, !(_groupPrefs[g.id]?.pinned ?? false));
  }

  Future<void> _setGroupPinned(ChatGroup g, bool pinned) async {
    final cur = _groupPrefs[g.id] ??
        const ChatGroupPrefs(groupId: '', muted: false, pinned: false);
    final next = ChatGroupPrefs(
      groupId: g.id,
      muted: cur.muted,
      pinned: pinned,
    );
    _groupPrefs[g.id] = next;
    await _updatePinnedChatOrderForPeer(_groupUnreadKey(g.id), next.pinned);
    try {
      if (_me != null) {
        await _service.setGroupPrefs(
          deviceId: _me!.id,
          groupId: g.id,
          muted: next.muted,
          pinned: next.pinned,
        );
      }
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
    }
    _applyState(() {});
  }

  Future<void> _toggleGroupArchived(ChatGroup g) async {
    final gid = g.id.trim();
    if (gid.isEmpty) return;
    final archived = !_archivedGroupIds.contains(gid);
    await _setGroupArchivedState(gid, archived);
  }

  Future<void> _toggleGroupReadUnread(ChatGroup g) async {
    final key = _groupUnreadKey(g.id);
    final cur = _unread[key] ?? 0;
    final nextUnreadCount = cur != 0 ? 0 : -1;
    if (cur > 0) {
      try {
        await _store.setGroupSeen(
          g.id,
          DateTime.now(),
          baseUrlOverride: widget.baseUrl,
        );
      } catch (_) {}
    }
    final nextUnread = Map<String, int>.from(_unread);
    nextUnread[key] = nextUnreadCount;
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
      await _saveUnreadCountForGroup(g.id, nextUnreadCount);
    } catch (_) {}
  }

  Future<void> _showGroupMoreSheetAfterDelay(ChatGroup g) async {
    await Future<void>.delayed(_shamellMoreSheetDelay);
    if (!mounted) return;
    await _showGroupMoreSheet(g);
  }

  Future<void> _showChatMoreSheetAfterDelay(ChatContact c) async {
    await Future<void>.delayed(_shamellMoreSheetDelay);
    if (!mounted) return;
    await _showChatMoreSheet(c);
  }

  Future<void> _dispatchGroupLongPress(
    ChatGroup group, {
    Offset? globalPosition,
  }) async {
    final override = widget.onGroupLongPressOverride;
    if (override != null) {
      await override(group, globalPosition);
      return;
    }
    await _onGroupLongPress(group, globalPosition: globalPosition);
  }

  Future<void> _handleGroupTileLongPress(
    ChatGroup group, {
    Offset? globalPosition,
  }) async {
    if (_selectionMode) {
      _toggleChatSelected(_groupUnreadKey(group.id));
      return;
    }
    await _dispatchGroupLongPress(group, globalPosition: globalPosition);
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
            closeAfterTap: true,
            onTap: () => _toggleGroupReadUnread(g),
          ),
          _ShamellPopoverActionSpec(
            label: pinLabel,
            closeAfterTap: true,
            onTap: () => _toggleGroupPinned(g),
          ),
          _ShamellPopoverActionSpec(
            label: moreLabel,
            onTap: () => _showGroupMoreSheetAfterDelay(g),
          ),
          _ShamellPopoverActionSpec(
            label: deleteLabel,
            color: const Color(0xFFFA5151),
            closeAfterTap: true,
            onTap: () => _clearGroupConversation(g),
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
                    onTap: () async {
                      await _toggleGroupReadUnread(g);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () async {
                      await _toggleGroupPinned(g);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: moreLabel,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _showGroupMoreSheetAfterDelay(g);
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () async {
                      await _clearGroupConversation(g);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
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
            onTap: () async {
              if (action.closeAfterTap) {
                await action.onTap();
                if (mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
                return;
              }
              Navigator.of(context, rootNavigator: true).pop();
              await action.onTap();
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

  Future<void> _showChatsMenu() async {
    final l = L10n.of(context);
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
                      onTap: () async {
                        await _markAllChatsRead();
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                  );
                  addAction(
                    actionRow(
                      label: selectionLabel,
                      onTap: () {
                        _applyState(() {
                          _selectionMode = !_selectionMode;
                          _selectedChatIds.clear();
                        });
                        Navigator.of(ctx).pop();
                      },
                    ),
                  );
                  addAction(
                    actionRow(
                      label: previewsLabel,
                      onTap: () async {
                        final next = !_notifyPreview;
                        _applyState(() => _notifyPreview = next);
                        await _saveNotifyPreviewSetting(next);
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                  );
                  if (showHiddenToggle) {
                    addAction(
                      actionRow(
                        label: hiddenLabel,
                        onTap: () async {
                          if (_showHidden) {
                            _applyState(() => _showHidden = false);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                            return;
                          }
                          final ok = await _authenticate();
                          if (ok) {
                            _applyState(() => _showHidden = true);
                          }
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
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
                          _applyState(() {
                            _showBlocked = !_showBlocked;
                          });
                          Navigator.of(ctx).pop();
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
        _chatSearchVisible = false;
      });
      _chatSearchCtrl.clear();
      _resetArchivedPullDown();
      unawaited(_resolvePeer(presetId: result.trim()));
    }
  }

  void _runAfterPopupMenuDismiss(Future<void> Function() action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(action());
    });
  }

  Future<void> _ensureLocalGroupKey(String groupId) async {
    try {
      final existing = await _store.loadGroupKey(
        groupId,
        baseUrlOverride: widget.baseUrl,
      );
      if (existing == null || existing.isEmpty) {
        final rnd = Random.secure();
        final keyBytes =
            Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
        await _store.saveGroupKey(
          groupId,
          base64Encode(keyBytes),
          baseUrlOverride: widget.baseUrl,
        );
      }
    } catch (_) {}
  }

  Future<ChatGroup?> _createStandaloneGroup(String rawName) async {
    final me = _me;
    final name = rawName.trim();
    if (me == null || name.isEmpty) return null;
    try {
      final g = await _service.createGroup(deviceId: me.id, name: name);
      await _ensureLocalGroupKey(g.id);
      return g;
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return null;
      rethrow;
    }
  }

  Future<({ChatGroup? group, String inviteError})> _createGroupWithPeer({
    required String name,
    required String peerId,
  }) async {
    final me = _me;
    if (me == null) {
      return (group: null, inviteError: '');
    }
    final group = await _createStandaloneGroup(name);
    if (group == null) {
      return (group: null, inviteError: '');
    }
    var inviteError = '';
    try {
      await _service.inviteGroupMembers(
        groupId: group.id,
        inviterId: me.id,
        memberIds: [peerId],
      );
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) {
        return (group: null, inviteError: '');
      }
      inviteError = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    return (group: group, inviteError: inviteError);
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
    try {
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
              final g = await _createStandaloneGroup(name);
              if (g == null) return;
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
                            hintText:
                                l.isArabic ? 'اسم المجموعة' : 'Group name',
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
    } finally {
      nameCtrl.dispose();
    }
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
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OfficialTemplateMessagesPage(
            baseUrl: widget.baseUrl,
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
                                await shamellCopyToClipboard(
                                  me.id,
                                  sensitive: true,
                                );
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
    final showServiceThread = allowServiceThread &&
        (!_hideServiceNotificationsThread || _hasUnreadServiceNotifications);
    final showChatSearch =
        _showArchived || _chatSearchVisible || _chatSearch.isNotEmpty;
    final archivedCount = _contacts.where((c) => c.archived).length +
        _groups.where((g) => _archivedGroupIds.contains(g.id)).length;
    final unreadCount = _unread.values.where((count) => count > 0).length +
        _groupMentionUnread.length;
    final pinnedCount = _contacts.where((c) => c.pinned).length +
        _groupPrefs.values.where((prefs) => prefs.pinned).length;
    final mutedCount = _contacts.where((c) => c.muted).length +
        _groupPrefs.values.where((prefs) => prefs.muted).length;
    final draftIds = <String>{
      for (final entry in _draftTextByChatId.entries)
        if (entry.value.trim().isNotEmpty) entry.key,
      for (final entry in _composerDraftByChatId.entries)
        if (entry.value.hasAttachment) entry.key,
    };
    final draftCount = draftIds.length;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 4),
          if (showChatSearch) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ShamellSearchBar(
                      hintText: l.isArabic ? 'بحث' : 'Search',
                      controller: _chatSearchCtrl,
                      autofocus: !_showArchived,
                      readOnly: false,
                      onChanged: (v) {
                        _applyState(() {
                          _chatSearch = v.trim();
                        });
                      },
                    ),
                  ),
                  // Cycle 3D: global "search all messages" entry. The
                  // chat-list ShamellSearchBar filters CONVERSATION
                  // names; this button opens a dedicated page that
                  // searches MESSAGE content across every chat. Two
                  // distinct affordances keep the existing chat-list
                  // filter behaviour unchanged.
                  IconButton(
                    tooltip: l.isArabic
                        ? 'البحث في كل الرسائل'
                        : 'Search in all messages',
                    icon: const Icon(Icons.travel_explore),
                    onPressed: _openCrossChatSearch,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!_showArchived && _chatSearch.isEmpty && !_selectionMode)
            _buildChatsCommandStrip(
              unreadCount: unreadCount,
              pinnedCount: pinnedCount,
              mutedCount: mutedCount,
              draftCount: draftCount,
              archivedCount: archivedCount,
            ),
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
                          size: 20,
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
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
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
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  ts: '',
                  pinned: false,
                  muted: false,
                  selected: false,
                  onTap: () async {
                    await _openServiceNotificationsThread();
                  },
                  onLongPress: () async {},
                ),
              ),
          ],
          if (_contacts.isEmpty && _groups.isEmpty)
            _buildChatsEmptyState(showActions: false)
          else ...[
            Builder(builder: (ctx) {
              final sortedContacts = _sortedContacts();
              final latestCallByPeer = buildLatestChatCallsByPeer(
                _lastCallsCache ?? const <ChatCallLogEntry>[],
              );
              final pinnedChatOrderIndexes =
                  buildPinnedChatOrderIndex(_pinnedChatOrder);
              final term = _chatSearch.toLowerCase();
              final now = DateTime.now();
              final noActivityTs = DateTime.fromMillisecondsSinceEpoch(0);
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
                final isArchived = c.archived;
                final inArchivedView = _showArchived;
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

              Widget groupPreviewWidget(
                ChatGroupThreadPreviewData preview, {
                required ThemeData theme,
                required TextStyle style,
              }) {
                if (!preview.hasStyledSegments) {
                  return Text(
                    preview.plainText,
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
                final mentionStyle = style.copyWith(
                  color: mentionColor,
                  fontWeight: FontWeight.w700,
                );
                final mentionHighlightStyle = mentionStyle.copyWith(
                  fontWeight: FontWeight.w800,
                );
                return RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: style,
                    children: [
                      for (final segment in preview.segments)
                        TextSpan(
                          text: segment.text,
                          style: switch (segment.kind) {
                            ChatGroupThreadPreviewSegmentKind.mention =>
                              mentionStyle,
                            ChatGroupThreadPreviewSegmentKind
                                  .mentionHighlight =>
                              mentionHighlightStyle,
                            ChatGroupThreadPreviewSegmentKind.text => null,
                          },
                        ),
                    ],
                  ),
                );
              }

              final visibleContacts =
                  sortedContacts.where(contactVisible).toList();
              final visibleGroups = _groups.where(groupVisible).toList();
              final directThreadStateByPeerId =
                  <String, _DirectThreadTileState>{};
              for (final c in visibleContacts) {
                final thread = _cache[c.id];
                final last =
                    thread != null && thread.isNotEmpty ? thread.last : null;
                final unread = _unread[c.id] ?? 0;
                final hasUnread = unread != 0;
                final isPeerTyping = _isPeerTyping(c.id);
                var preview =
                    last != null ? _previewText(last) : l.shamellNoMessagesYet;
                final latestCallPreview = buildLatestChatCallPreview(
                  latestCall: latestCallByPeer[c.id],
                  latestMessageAt: last?.createdAt,
                  isArabic: l.isArabic,
                );
                if (latestCallPreview != null) {
                  preview = latestCallPreview;
                }
                if (isPeerTyping) {
                  preview = l.shamellTyping;
                }
                final draftSnap = _composerDraftByChatId[c.id];
                final draftText = (_draftTextByChatId[c.id] ?? '').trim();
                final hasDraft =
                    draftText.isNotEmpty || (draftSnap?.hasAttachment ?? false);
                final draftPreview = draftText.isNotEmpty
                    ? draftText
                    : (draftSnap?.hasAttachment ?? false)
                        ? l.shamellPreviewImage
                        : '';
                var sortTs = last?.createdAt ?? noActivityTs;
                final lastCall = latestCallByPeer[c.id];
                if (lastCall != null && lastCall.ts.isAfter(sortTs)) {
                  sortTs = lastCall.ts;
                }
                directThreadStateByPeerId[c.id] = _DirectThreadTileState(
                  last: last,
                  unread: unread,
                  hasUnread: hasUnread,
                  preview: preview,
                  isPeerTyping: isPeerTyping,
                  ts: formatChatThreadTimestamp(last?.createdAt, now: now),
                  isOfficial: _officialPeerIds.contains(c.id),
                  hasFeedUnread: _officialPeerUnreadFeeds.contains(c.id),
                  isFeaturedOfficial: _featuredOfficialPeerIds.contains(c.id),
                  bulkSelected:
                      _selectionMode && _selectedChatIds.contains(c.id),
                  hasDraft: hasDraft,
                  draftPreview: draftPreview,
                  sortTs: sortTs,
                );
              }
              final groupThreadStateByGroupId =
                  <String, _GroupThreadTileState>{};
              for (final g in visibleGroups) {
                final gid = g.id;
                final thread = _groupCache[gid] ?? const <ChatGroupMessage>[];
                final last = thread.isNotEmpty ? thread.last : null;
                final unreadKey = _groupUnreadKey(gid);
                final unread = _unread[unreadKey] ?? 0;
                final hasUnread = unread != 0;
                final mentionUnread = _groupMentionUnread.contains(gid);
                groupThreadStateByGroupId[gid] = _GroupThreadTileState(
                  last: last,
                  preview: buildChatGroupThreadPreviewData(
                    message: last,
                    displayName: displayName,
                    isArabic: l.isArabic,
                    currentUserId: _me?.id ?? '',
                    noMessagesYet: l.shamellNoMessagesYet,
                    previewVoice: l.shamellPreviewVoice,
                    previewImage: l.shamellPreviewImage,
                    encryptedMessageLabel:
                        l.isArabic ? 'رسالة مشفرة' : 'Encrypted message',
                  ),
                  unread: unread,
                  hasUnread: hasUnread,
                  muted: _groupPrefs[gid]?.muted ?? false,
                  pinned: _groupPrefs[gid]?.pinned ?? false,
                  archived: _archivedGroupIds.contains(gid),
                  mentionUnread: mentionUnread,
                  mentionAllUnread: _groupMentionAllUnread.contains(gid),
                  ts: formatChatThreadTimestamp(last?.createdAt, now: now),
                  avatarBytes: _decodeInlineImageBytes(g.avatarB64),
                  bulkSelected:
                      _selectionMode && _selectedChatIds.contains(unreadKey),
                  bulkId: unreadKey,
                  sortTs: last?.createdAt ?? noActivityTs,
                );
              }

              final threads = <({
                bool isGroup,
                ChatContact? c,
                ChatGroup? g,
                DateTime ts
              })>[];
              for (final c in visibleContacts) {
                final state = directThreadStateByPeerId[c.id];
                if (state == null) continue;
                threads.add((isGroup: false, c: c, g: null, ts: state.sortTs));
              }
              for (final g in visibleGroups) {
                final state = groupThreadStateByGroupId[g.id];
                if (state == null) continue;
                threads.add((isGroup: true, c: null, g: g, ts: state.sortTs));
              }

              threads.sort((a, b) {
                final ca = a.c;
                final cb = b.c;
                final aPinned = a.isGroup
                    ? (groupThreadStateByGroupId[a.g!.id]?.pinned ?? false)
                    : (ca?.pinned ?? false);
                final bPinned = b.isGroup
                    ? (groupThreadStateByGroupId[b.g!.id]?.pinned ?? false)
                    : (cb?.pinned ?? false);
                if (aPinned && bPinned) {
                  final aKey =
                      a.isGroup ? _groupUnreadKey(a.g!.id) : (ca?.id ?? '');
                  final bKey =
                      b.isGroup ? _groupUnreadKey(b.g!.id) : (cb?.id ?? '');
                  final aIdx = pinnedChatOrderIndexes[aKey];
                  final bIdx = pinnedChatOrderIndexes[bKey];
                  if (aIdx != null || bIdx != null) {
                    if (aIdx == null && bIdx != null) return 1;
                    if (aIdx != null && bIdx == null) return -1;
                    return aIdx!.compareTo(bIdx!);
                  }
                }
                if (aPinned != bPinned) {
                  return (bPinned ? 1 : 0) - (aPinned ? 1 : 0);
                }
                final aFeatured = ca != null &&
                    (directThreadStateByPeerId[ca.id]?.isFeaturedOfficial ??
                        false);
                final bFeatured = cb != null &&
                    (directThreadStateByPeerId[cb.id]?.isFeaturedOfficial ??
                        false);
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
                  final archivedContacts = _contacts.where((c) => c.archived);
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
                    if (item.isGroup) {
                      final g = item.g!;
                      final gid = g.id;
                      final state = groupThreadStateByGroupId[gid];
                      if (state == null) {
                        return const SizedBox.shrink();
                      }
                      final avatarBytes = state.avatarBytes;
                      final unread = state.unread;
                      final muted = state.muted;
                      final pinned = state.pinned;
                      final archived = state.archived;
                      final mentionUnread = state.mentionUnread;
                      final hasUnread = state.hasUnread;
                      final Color subtitleColor = hasUnread
                          ? theme.colorScheme.onSurface.withValues(alpha: .90)
                          : theme.colorScheme.onSurface
                              .withValues(alpha: muted ? .45 : .70);
                      final FontWeight previewWeight =
                          hasUnread ? FontWeight.w600 : FontWeight.w400;
                      const shamellUnreadRed = Color(0xFFFA5151);
                      final bulkId = state.bulkId;
                      final bool bulkSelected = state.bulkSelected;
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
                                      // Avatar tiles are tiny; cap
                                      // raw cache to the actual draw
                                      // size × DPR-3 so a 4K user
                                      // photo doesn't hold its full
                                      // pixel grid in RAM just to
                                      // render at 38 px.
                                      cacheWidth: 120,
                                      cacheHeight: 120,
                                      filterQuality: FilterQuality.medium,
                                    )
                                  : const Icon(Icons.groups_outlined, size: 19),
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
                                      // Avatar tiles are tiny; cap
                                      // raw cache to the actual draw
                                      // size × DPR-3 so a 4K user
                                      // photo doesn't hold its full
                                      // pixel grid in RAM just to
                                      // render at 38 px.
                                      cacheWidth: 120,
                                      cacheHeight: 120,
                                      filterQuality: FilterQuality.medium,
                                    )
                                  : const Icon(Icons.groups_outlined, size: 19),
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
                        ts: state.ts,
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
                            await _setGroupArchivedState(
                              gid,
                              false,
                              clearArchivedView: true,
                            );
                          }
                        },
                        onLongPressAt: (pos) async {
                          await _handleGroupTileLongPress(
                            g,
                            globalPosition: pos,
                          );
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
                                  fontWeight: FontWeight.w500,
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
                            height: 1.18,
                            fontWeight: previewWeight,
                            color: subtitleColor,
                          );
                          final previewWidget = groupPreviewWidget(
                            state.preview,
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
                                  state.mentionAllUnread
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
                    final state = directThreadStateByPeerId[c.id];
                    if (state == null) {
                      return const SizedBox.shrink();
                    }
                    final isActive = c.id == _activePeerId;
                    final unread = state.unread;
                    final hasUnread = state.hasUnread;
                    final preview = state.preview;
                    final isPeerTyping = state.isPeerTyping;
                    final isOfficial = state.isOfficial;
                    final hasFeedUnread = state.hasFeedUnread;
                    final isFeaturedOfficial = state.isFeaturedOfficial;
                    final Color subtitleColor = isPeerTyping
                        ? ShamellPalette.green
                        : hasUnread
                            ? theme.colorScheme.onSurface.withValues(alpha: .90)
                            : (c.muted
                                ? theme.colorScheme.onSurface
                                    .withValues(alpha: .45)
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: .70));
                    final FontWeight previewWeight = (hasUnread || isPeerTyping)
                        ? FontWeight.w600
                        : FontWeight.w400;
                    final bool bulkSelected = state.bulkSelected;
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
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      // Cycle 40 — show a small green dot on the
                      // bottom-right of the avatar when the peer has
                      // heartbeated in the last 90s.
                      final lastSeen = _peerLastSeenAt[c.id];
                      final isOnline = lastSeen != null &&
                          DateTime.now().difference(lastSeen).inSeconds < 90;
                      // Cycle 57 — use the peer's published avatar
                      // bytes when available; fall back to the
                      // first-letter monogram tile.
                      final profileAvatar =
                          _peerProfileAvatarBytes[c.id];
                      leading = Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildShamellAvatarBox(
                            backgroundColor: c.verified
                                ? Tokens.colorPayments.withValues(alpha: .20)
                                : Tokens.accent.withValues(alpha: .15),
                            child: profileAvatar != null
                                ? ClipOval(
                                    child: Image.memory(
                                      profileAvatar,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  )
                                : Text(
                                    c.name != null && c.name!.isNotEmpty
                                        ? c.name!.substring(0, 1).toUpperCase()
                                        : c.id.substring(0, 1),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 17,
                                    ),
                                  ),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: ChatPulseDot(
                                size: 12,
                                borderColor: theme.colorScheme.surface,
                                borderWidth: 2,
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
                      ts: state.ts,
                      onTap: () async {
                        await _handleChatTileTap(c);
                      },
                      onLongPressAt: (pos) async {
                        await _handleChatTileLongPress(
                          c,
                          globalPosition: pos,
                        );
                      },
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              // Cycle 57 — prefer the resolved name
                              // (local nickname → published profile
                              // name → raw id) over the bare
                              // `c.name` field.
                              _displayNameForPeer(c),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // Cycle 59 — small status-emoji badge next
                          // to the contact name. Slack pattern. The
                          // text body is intentionally not duplicated
                          // here so the row stays one line; the full
                          // status reads in the chat-info modal.
                          if ((_peerProfileStatusEmoji[c.id] ?? '')
                              .isNotEmpty) ...<Widget>[
                            const SizedBox(width: 4),
                            Text(
                              _peerProfileStatusEmoji[c.id]!,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
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
                              final hasDraft = state.hasDraft;
                              final baseStyle =
                                  theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 13,
                                        height: 1.18,
                                        color: subtitleColor,
                                        fontWeight: previewWeight,
                                      ) ??
                                      TextStyle(
                                        fontSize: 12.5,
                                        height: 1.18,
                                        color: subtitleColor,
                                        fontWeight: previewWeight,
                                      );
                              // Cycle 25: peer typing wins over draft +
                              // preview — most transient + most useful
                              // signal in the chat list.
                              if (_isPeerTyping(c.id)) {
                                return Text(
                                  l.shamellTyping,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: baseStyle.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: theme.colorScheme.primary,
                                  ),
                                );
                              }
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
                                    TextSpan(text: state.draftPreview),
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

  Widget _buildChatsCommandStrip({
    required int unreadCount,
    required int pinnedCount,
    required int mutedCount,
    required int draftCount,
    required int archivedCount,
  }) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chips = <Widget>[];

    Widget statPill({
      required IconData icon,
      required String label,
      required int count,
      Color? color,
      VoidCallback? onTap,
    }) {
      final accent = color ?? theme.colorScheme.primary;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? .16 : .08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: .20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 6),
                Text(
                  '$label $count',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: .78),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (unreadCount > 0) {
      chips.add(
        statPill(
          icon: Icons.mark_chat_unread_outlined,
          label: l.isArabic ? 'غير مقروءة' : 'Unread',
          count: unreadCount,
          color: const Color(0xFFFA5151),
          onTap: () => unawaited(_markAllChatsRead()),
        ),
      );
    }
    if (pinnedCount > 0) {
      chips.add(
        statPill(
          icon: Icons.push_pin_outlined,
          label: l.isArabic ? 'مثبتة' : 'Pinned',
          count: pinnedCount,
          color: const Color(0xFFF59E0B),
        ),
      );
    }
    if (mutedCount > 0) {
      chips.add(
        statPill(
          icon: Icons.notifications_off_outlined,
          label: l.isArabic ? 'مكتومة' : 'Muted',
          count: mutedCount,
          color: const Color(0xFF64748B),
        ),
      );
    }
    if (draftCount > 0) {
      chips.add(
        statPill(
          icon: Icons.edit_note_outlined,
          label: l.isArabic ? 'مسودات' : 'Drafts',
          count: draftCount,
          color: const Color(0xFF07C160),
        ),
      );
    }
    if (archivedCount > 0) {
      chips.add(
        statPill(
          icon: Icons.archive_outlined,
          label: l.isArabic ? 'الأرشيف' : 'Archived',
          count: archivedCount,
          color: const Color(0xFF64748B),
          onTap: () {
            _applyState(() {
              _showArchived = true;
              _chatSearch = '';
              _chatSearchVisible = false;
            });
            _chatSearchCtrl.clear();
            _resetArchivedPullDown();
          },
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 3, 12, 5),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, index) => chips[index],
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: chips.length,
      ),
    );
  }

  Widget _buildChatsEmptyState({bool showActions = true}) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        children: [
          Text(
            l.shamellNoContactsHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: theme.colorScheme.onSurface.withValues(alpha: .48),
              fontWeight: FontWeight.w500,
              height: 1.28,
            ),
          ),
          if (showActions) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => unawaited(_startNewChat()),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: Text(l.isArabic ? 'إضافة صديق' : 'Add friend'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_scanQr()),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(l.isArabic ? 'مسح' : 'Scan'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_startNewGroupChat()),
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: Text(l.isArabic ? 'مجموعة' : 'Group'),
                ),
              ],
            ),
          ],
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
      await _store.setGroupSeen(
        gid,
        now,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
    try {
      await _store.deleteGroupMessages(
        gid,
        baseUrlOverride: widget.baseUrl,
      );
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
      await _saveUnreadCountForGroup(gid, 0);
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
                    onTap: () async {
                      await _toggleChatMuted(c);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () async {
                      await _toggleChatPinned(c);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: archiveLabel,
                    onTap: () async {
                      await _toggleChatArchived(c);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () async {
                      await _deleteChatById(c.id);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
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
                    onTap: () async {
                      await _toggleGroupMuted(g);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () async {
                      await _toggleGroupPinned(g);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: archiveLabel,
                    onTap: () async {
                      await _toggleGroupArchived(g);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () async {
                      await _clearGroupConversation(g);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
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
  static const double _shamellThreadAvatarRadius = 22.0;
  static const double _shamellThreadDividerIndent = 72.0;
  static const EdgeInsets _shamellThreadPadding =
      EdgeInsets.fromLTRB(16, 9, 12, 9);
  static const double _shamellAvatarCornerRadius = 8.0;

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
    required Future<void> Function() onTap,
    Future<void> Function()? onLongPress,
    Future<void> Function(Offset)? onLongPressAt,
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
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6).toDouble();
    final double tileMinHeight = _shamellThreadAvatarRadius * 2 +
        _shamellThreadPadding.vertical +
        ((textScale - 1.0) * 20.0);
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
        onTap: () async {
          await onTap();
        },
        onLongPress: !hasLongPress
            ? null
            : () async {
                // Haptic confirmation that the long-press registered.
                // Without it the context-menu pop-up can feel like an
                // accidental tap on slower devices — the medium impact
                // mirrors the standard iOS / Android system contextual
                // menu cue. Audit P1-19 flagged that the chat surface
                // under-used haptics relative to peer apps.
                unawaited(HapticFeedback.mediumImpact());
                final cb = onLongPressAt;
                if (cb != null) {
                  await cb(tapDownGlobalPosition ?? Offset.zero);
                  return;
                }
                await onLongPress?.call();
              },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tileMinHeight),
          child: Padding(
            padding: _shamellThreadPadding,
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 2),
                      subtitle,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
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
                    if (ts.isNotEmpty) const SizedBox(height: 3),
                    muted
                        ? Icon(
                            Icons.notifications_off_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .45),
                          )
                        : const SizedBox(height: 14),
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
              autoClose: false,
              onPressed: (ctx2) async {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  await onToggleRead();
                  return;
                }
                await onToggleRead();
                await controller.close(
                  duration: _shamellSwipeResizeDuration,
                );
              },
            ),
            action(
              label: l.isArabic ? 'حذف' : 'Delete',
              bg: shamellRed,
              autoClose: false,
              onPressed: (_) async {
                await onDelete();
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
                onPressed: (ctx2) async {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    await _toggleGroupArchived(g);
                    return;
                  }
                  await controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {},
                    ),
                  );
                  await _toggleGroupArchived(g);
                },
              ),
              action(
                label: l.isArabic ? 'حذف' : 'Delete',
                bg: shamellRed,
                autoClose: false,
                onPressed: (ctx2) async {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    await _clearGroupConversation(g);
                    return;
                  }
                  await _clearGroupConversation(g);
                  await controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {},
                    ),
                  );
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
              autoClose: false,
              onPressed: (ctx2) async {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  await _toggleGroupReadUnread(g);
                  return;
                }
                await _toggleGroupReadUnread(g);
                await controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {},
                  ),
                );
              },
            ),
            action(
              label: pinned
                  ? (l.isArabic ? 'إلغاء تثبيت' : 'Unpin')
                  : (l.isArabic ? 'تثبيت' : 'Pin'),
              bg: shamellOrange,
              autoClose: false,
              onPressed: (ctx2) async {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  await _toggleGroupPinned(g);
                  return;
                }
                await _toggleGroupPinned(g);
                await controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {},
                  ),
                );
              },
            ),
            action(
              label: l.isArabic ? 'حذف' : 'Delete',
              bg: shamellRed,
              autoClose: false,
              onPressed: (ctx2) async {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  await _clearGroupConversation(g);
                  return;
                }
                await _clearGroupConversation(g);
                await controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {},
                  ),
                );
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
                onPressed: (ctx2) async {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    await _toggleChatArchived(c);
                    return;
                  }
                  await controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {},
                    ),
                  );
                  await _toggleChatArchived(c);
                },
              ),
              action(
                label: l.isArabic ? 'حذف' : 'Delete',
                bg: shamellRed,
                autoClose: false,
                onPressed: (ctx2) async {
                  final controller = Slidable.of(ctx2);
                  if (controller == null) {
                    await _deleteChatById(c.id);
                    return;
                  }
                  await controller.dismiss(
                    ResizeRequest(
                      _shamellSwipeResizeDuration,
                      () {},
                    ),
                  );
                  await _deleteChatById(c.id);
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
              autoClose: false,
              onPressed: (ctx2) async {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  await _toggleChatReadUnread(c);
                  return;
                }
                await _toggleChatReadUnread(c);
                await controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {},
                  ),
                );
              },
            ),
            action(
              label: isPinned
                  ? (l.isArabic ? 'إلغاء تثبيت' : 'Unpin')
                  : (l.isArabic ? 'تثبيت' : 'Pin'),
              bg: shamellOrange,
              autoClose: false,
              onPressed: (ctx2) async {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  await _toggleChatPinned(c);
                  return;
                }
                await _toggleChatPinned(c);
                await controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {},
                  ),
                );
              },
            ),
            action(
              label: l.isArabic ? 'حذف' : 'Delete',
              bg: shamellRed,
              autoClose: false,
              onPressed: (ctx2) async {
                final controller = Slidable.of(ctx2);
                if (controller == null) {
                  await _deleteChatById(c.id);
                  return;
                }
                await controller.dismiss(
                  ResizeRequest(
                    _shamellSwipeResizeDuration,
                    () {},
                  ),
                );
                await _deleteChatById(c.id);
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
                            await _setPeerDisappearSettings(
                              peer.copyWith(
                                disappearing: !_disappearing,
                                disappearAfter: _disappearAfter,
                              ),
                            );
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
                      await _setPeerDisappearSettings(
                        peer.copyWith(
                          disappearAfter: v,
                          disappearing: _disappearing,
                        ),
                      );
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
                            await _setChatHidden(peer, !peer.hidden);
                          },
                          child: Text(peer.hidden
                              ? l.shamellUnhideChat
                              : l.shamellHideChat))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: FilledButton.tonal(
                          onPressed: () async {
                            await _setChatBlocked(peer, !peer.blocked);
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

  Widget _chatCard(ChatIdentity? me, ChatContact? peer) {
    final l = L10n.of(context);
    final String? newMessagesAnchorId =
        (peer != null && _newMessagesAnchorPeerId == peer.id)
            ? _newMessagesAnchorMessageId
            : null;
    final threadLayout = _currentThreadListLayout(
      newMessagesAnchorMessageId: (!_messageSelectionMode &&
              newMessagesAnchorId != null &&
              newMessagesAnchorId.isNotEmpty)
          ? newMessagesAnchorId
          : null,
    );
    final threadEntries = threadLayout.entries;
    final int newMessagesIndex = threadLayout.newMessagesIndex;
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
    // Cycle 3D: if the user picked a custom wallpaper image for this
    // conversation, layer it on top of the theme color so the underlying
    // tint still bleeds through translucent areas (e.g. PNG with alpha).
    // The wallpaper file lives in app docs; `FileImage` failure falls
    // through to the solid colour without throwing.
    final String? wallpaperPath = wallpaperPathFromThemeKey(themeKey);
    final BoxDecoration chatWallpaper = wallpaperPath != null
        ? BoxDecoration(
            color: chatBgColor,
            image: DecorationImage(
              image: FileImage(File(wallpaperPath)),
              fit: BoxFit.cover,
              // Tone the wallpaper down so message bubbles remain
              // readable on top — same dimming WhatsApp uses for its
              // doodle wallpaper.
              colorFilter: ColorFilter.mode(
                (isDark ? Colors.black : Colors.white).withValues(alpha: .35),
                BlendMode.lighten,
              ),
              onError: (_, __) {
                // Wallpaper file got deleted (e.g. user cleared app data
                // selectively). Leave the underlying colour visible; no
                // need to clear the pref proactively — the next render
                // shows the colour and the user can re-pick.
              },
            ),
          )
        : BoxDecoration(color: chatBgColor);
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
          _buildThreadMessageSearchBar(l, theme),
          Expanded(
            child: Stack(
              children: [
                if (threadEntries.isEmpty)
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
                    // `cacheExtent` keeps a 600 px ring of off-screen
                    // bubbles rasterised on each side of the viewport.
                    // Without it the next bubble to scroll into view
                    // costs a full layout pass + image decode, which
                    // is what the audit called out as the source of
                    // scroll jitter on long threads. RepaintBoundaries
                    // around each bubble (added below) ensure unaffected
                    // bubbles don't repaint when a single one mutates
                    // its status icon footer.
                    cacheExtent: 600,
                    addRepaintBoundaries: false,
                    itemBuilder: (ctx, i) {
                      final showOlderMessagesEntry =
                          _loadingOlderThreadMessages ||
                              _hasOlderThreadMessages;
                      if (showOlderMessagesEntry && i == 0) {
                        if (_loadingOlderThreadMessages) {
                          // Cycle 3C: show 3 shimmering bubble silhouettes
                          // instead of a single spinner so the user gets
                          // shape-level feedback that "older history is
                          // arriving" rather than a vague "something's
                          // happening". The alternating in/out pattern
                          // matches the texture of the conversation
                          // below, so the placeholder reads as continuous
                          // content rather than a modal-style load.
                          return const Padding(
                            padding: EdgeInsets.fromLTRB(0, 4, 0, 12),
                            child: ChatBubbleSkeletonGroup(count: 3),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: _loadOlderThreadMessages,
                              icon: const Icon(Icons.history),
                              label: Text(
                                l.isArabic
                                    ? 'تحميل رسائل أقدم'
                                    : 'Load older messages',
                              ),
                            ),
                          ),
                        );
                      }
                      final messageIndex = showOlderMessagesEntry ? i - 1 : i;
                      final entry = threadEntries[messageIndex];
                      final m = entry.message;
                      final showTimeHeader = entry.showTimeHeader;
                      final msgKey = _existingThreadMessageKey(m.id);
                      // Wrap each bubble in its own RepaintBoundary so
                      // a status-icon flip on a single outgoing bubble
                      // (sent→delivered→read) doesn't trigger a repaint
                      // of every other bubble in the list. Set
                      // `addRepaintBoundaries: false` on the parent
                      // ListView so Flutter doesn't double-wrap.
                      Widget bubble = RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: _decorateMessageBubble(
                            _bubble(
                              ctx,
                              m,
                              me,
                              showAvatar: entry.showAvatar,
                              showBubbleTail: entry.showBubbleTail,
                            ),
                            m,
                            me,
                          ),
                        ),
                      );
                      if (msgKey != null) {
                        bubble = KeyedSubtree(key: msgKey, child: bubble);
                      }
                      final children = <Widget>[];
                      if (showTimeHeader) {
                        children.add(_buildShamellTimeHeader(m.createdAt!));
                      }
                      if (showNewMessagesMarker &&
                          messageIndex == newMessagesIndex) {
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
                    itemCount: threadEntries.length +
                        ((_loadingOlderThreadMessages ||
                                _hasOlderThreadMessages)
                            ? 1
                            : 0),
                  ),
                if (!_threadNearBottom &&
                    threadEntries.isNotEmpty &&
                    _threadNewMessagesAwayCount > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: _buildThreadNewMessagesBar(),
                    ),
                  )
                else if (!_threadNearBottom && threadEntries.isNotEmpty)
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
          _buildThreadTypingIndicator(l, theme),
          // Cycle 12: smart-reply chips. Hidden when the composer
          // has anything in it, when the user has dismissed
          // suggestions for the current incoming message, or when
          // the heuristic doesn't recognise the message.
          _buildSmartRepliesBar(l),
          // Cycle 21: @-mention completions chip row. Hidden when
          // the caret isn't inside a `@partial` window.
          _buildMentionCompletionsBar(l),
          // Cycle 24: emoji `:partial` completion bar. Mutually
          // exclusive with the mention bar — only one popover
          // shows at a time.
          _buildEmojiCompletionsBar(l),
          // Cycle 28: slash-command suggestion bar.
          _buildSlashCommandSuggestionBar(l),
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
                // Text field stays put — no more swap-to-PTT mode. The
                // dedicated mic button (right of the field) toggles
                // recording on a single tap.
                Expanded(
                  child: Container(
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
                      // Disable typing while a voice message is recording
                      // so the field can't steal focus / accumulate text
                      // the user never intended to send with the audio.
                      enabled: !_recordingVoice,
                      controller: _msgCtrl,
                      // Cycle 48 — let the composer grow up to 8 lines
                      // so long compositions render in place instead
                      // of scrolling inside a tiny 4-line viewport.
                      maxLines: 8,
                      minLines: 1,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                        hintText: _recordingVoice
                            ? l.shamellRecordingVoice
                            : l.shamellTypeMessage,
                        border: InputBorder.none,
                        // Cycle 48 — clear-text affordance. Only shown
                        // when the composer holds something to clear
                        // and we're not currently recording a voice
                        // note. Tap drops the text and any reply
                        // preview tied to the current draft.
                        suffixIcon: (_msgCtrl.text.isNotEmpty &&
                                !_recordingVoice)
                            ? IconButton(
                                tooltip: l.isArabic ? 'مسح' : 'Clear',
                                icon: const Icon(Icons.cancel, size: 18),
                                onPressed: () {
                                  _msgCtrl.clear();
                                  _applyState(() {
                                    _replyToMessage = null;
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Saved-replies palette (Cycle 7). Disabled while
                // recording so an accidental tap can't open a bottom
                // sheet over the voice overlay. The text-only insert
                // path makes this safe to invoke even mid-compose —
                // the chosen body is spliced at the current caret.
                IconButton(
                  tooltip:
                      l.isArabic ? 'الردود المحفوظة' : 'Saved replies',
                  icon: const Icon(Icons.bookmark_outline),
                  onPressed: (_loading ||
                          me == null ||
                          peer == null ||
                          _recordingVoice)
                      ? null
                      : () => _openSavedRepliesPalette(me),
                ),
                const SizedBox(width: 6),
                // Tap-to-record mic. Single tap starts the recording (the
                // lock-state cancel/send overlay above the composer becomes
                // the active control surface). Tap again stops + sends.
                // The legacy push-to-talk gesture (long-press + slide)
                // has been retired — operators reported it as the #1
                // friction point on the previous build.
                IconButton(
                  tooltip: _recordingVoice
                      ? l.chatSend
                      : l.shamellStartVoice,
                  icon: Icon(
                    _recordingVoice ? Icons.send_rounded : Icons.mic_none,
                    color: _recordingVoice
                        ? ShamellPalette.green
                        : null,
                  ),
                  onPressed: (_loading ||
                          me == null ||
                          peer == null ||
                          peer.blocked)
                      ? null
                      : () async {
                          if (_recordingVoice) {
                            await _stopVoiceRecord();
                            return;
                          }
                          // Park focus so the keyboard stays out of the
                          // way of the recording overlay above the bar.
                          FocusScope.of(context).unfocus();
                          _applyState(() {
                            // Treat the recording as "locked" so the
                            // existing pill above the composer shows the
                            // hands-free Cancel + Send controls right
                            // away (no slide-to-lock needed in tap mode).
                            _voiceLocked = true;
                            _voiceCancelPending = false;
                            _voiceGestureStartLocal = null;
                            _composerPanel = _ShamellComposerPanel.none;
                          });
                          _startVoiceRecord();
                        },
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
                        child: GestureDetector(
                          // Cycle 8: long-press → schedule picker.
                          // Short tap stays the regular send path so the
                          // common case (just send it now) is unchanged.
                          onLongPress: canSend
                              ? _openSchedulePickerForCurrentDraft
                              : null,
                          child: IconButton(
                            tooltip: l.isArabic
                                ? '${l.chatSend} · اضغط مطولًا للجدولة'
                                : '${l.chatSend} · long-press to schedule',
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
                        // Cycle 41 — render the live amplitude ring
                        // as 16 bars, oldest-first. The head index
                        // is the next-write slot; subtract for read.
                        const visible = 16;
                        final ringLen = _voiceAmpRing.length;
                        for (var i = 0; i < visible; i++) {
                          final idx = (_voiceAmpHead - visible + i + ringLen) %
                              ringLen;
                          final amp = _voiceAmpRing[idx];
                          // Shape: floor at 4px, full height at 22px.
                          final h = 4.0 + amp * 18.0;
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
                  Expanded(
                    child: _buildComposerAttachmentPreview(
                      theme: theme,
                      isDark: isDark,
                      l: l,
                    ),
                  ),
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
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      _showPinnedMessagesSheet(peer, pinnedMessages),
                  child: Text(
                    l.isArabic ? 'عرض الكل' : 'View all',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: .85),
                        ),
                  ),
                ),
            ],
          ),
        ),
        ...pinnedMessages.take(3).map((m) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildPinnedMessagePreviewTile(
              context,
              m,
              onTap: () {
                unawaited(_jumpToPinnedMessage(m.id));
              },
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

    VoidCallback? openModuleApp;
    IconData? miniIcon;
    String? miniLabel;
    switch (official.moduleAppId) {
      case 'payments':
        openModuleApp = _openPayService;
        miniIcon = Icons.account_balance_wallet_outlined;
        miniLabel = l.isArabic ? 'فتح المحفظة' : 'Open wallet';
        break;
    }

    final subtitle = _officialSubtitle(official, l);
    final autoLoadAvatarUrl = normalizeOfficialRemoteImageUrlForAutoload(
      official.avatarUrl,
      baseUrl: widget.baseUrl,
    );

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
            child: ClipOval(
              child: SizedBox.expand(
                child: autoLoadAvatarUrl == null
                    ? Center(
                        child: Text(
                          (official.name.isNotEmpty
                                  ? official.name.substring(0, 1)
                                  : (peer.name ?? peer.id).substring(0, 1))
                              .toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ShamellPinnedRemoteImage(
                        imageUrl: autoLoadAvatarUrl,
                        fallback: Center(
                          child: Text(
                            (official.name.isNotEmpty
                                    ? official.name.substring(0, 1)
                                    : (peer.name ?? peer.id).substring(0, 1))
                                .toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
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
                        l.shamellChannelMomentsTitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (openModuleApp != null &&
                        miniIcon != null &&
                        miniLabel != null) ...[
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: openModuleApp,
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
    final l = L10n.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = 40.0;
    final radius = BorderRadius.circular(6);

    String label = '';
    String? remoteImageUrl;

    if (incoming) {
      final peer = _peer;
      label = peer != null ? _displayNameForPeer(peer) : '';
      final official = _linkedOfficial;
      final avatarUrl = normalizeOfficialRemoteImageUrlForAutoload(
        official?.avatarUrl,
        baseUrl: widget.baseUrl,
      );
      final peerId = (peer?.id ?? '').trim();
      final linkedPeerId = (official?.chatPeerId ?? '').trim();
      if ((avatarUrl ?? '').isNotEmpty &&
          peerId.isNotEmpty &&
          (linkedPeerId.isEmpty || linkedPeerId == peerId)) {
        remoteImageUrl = avatarUrl;
      }
    } else {
      final displayName = (me?.displayName ?? '').trim();
      final ownId = (me?.id ?? '').trim();
      label = displayName.isNotEmpty
          ? displayName
          : (ownId.isNotEmpty ? ownId : (l.isArabic ? 'أنا' : 'Me'));
    }

    final initial =
        label.trim().isNotEmpty ? label.trim()[0].toUpperCase() : '?';
    final bg = incoming
        ? theme.colorScheme.primary.withValues(alpha: isDark ? .22 : .14)
        : theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: isDark ? .35 : .85,
          );

    // Cycle 57 — prefer the peer's published avatar bytes when we
    // have them in cache; otherwise fall through to the existing
    // remote-image / initial-letter path.
    Uint8List? profileAvatarBytes;
    if (incoming) {
      final peerId = (_peer?.id ?? '').trim();
      if (peerId.isNotEmpty) {
        profileAvatarBytes = _peerProfileAvatarBytes[peerId];
      }
    }

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: bg,
        child: profileAvatarBytes != null
            ? Image.memory(
                profileAvatarBytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : (remoteImageUrl != null
                ? ShamellPinnedRemoteImage(
                    imageUrl: remoteImageUrl,
                    fallback: Center(
                      child: Text(
                        initial,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initial,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  )),
      ),
    );
  }

  Widget _bubble(
    BuildContext context,
    ChatMessage m,
    ChatIdentity? me, {
    bool interactive = true,
    bool showAvatar = true,
    bool showBubbleTail = true,
  }) {
    final incoming = _isIncoming(m);
    final decoded = _decodeMessage(m);
    final l = L10n.of(context);
    final isRecalled = _recalledMessageIds.contains(m.id);
    String text;
    if ((decoded.kind ?? '').trim().toLowerCase() == 'voice') {
      final voiceSecs = decoded.voiceSecs ?? 0;
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
        (decoded.kind ?? '').trim().toLowerCase() != 'voice' &&
        (decoded.kind ?? '').trim().toLowerCase() != 'location' &&
        (decoded.kind ?? '').trim().toLowerCase() != 'contact' &&
        text.trim().isEmpty &&
        (decoded.attachment == null || decoded.attachment!.isEmpty)) {
      text = l.shamellPreviewUnknown;
    }
    final presentation = _directMessagePresentation(
      m,
      decoded,
      bodyText: text,
    );
    // Cycle 15: kick a one-time poll lookup on every render of a
    // poll-prefixed message. No-op once the cache slot is set.
    _maybeKickPollFetch(m.id, text);
    final loadedPoll = _loadedPollFor(m.id);
    // Cycle 16: kick a one-time voice-transcript lookup for voice
    // messages. The cache hides "no transcript" + "in flight"
    // states so the inline display only appears when there's text
    // to show.
    if ((decoded.kind ?? '').trim().toLowerCase() == 'voice') {
      _maybeKickVoiceTranscriptFetch(m.id);
    }
    final inlineTranscript = _loadedTranscriptFor(m.id);
    final isVoice = presentation.kind == 'voice';
    final isThisVoice = isVoice && _playingVoiceMessageId == m.id;
    final isPlayingThisVoice = isThisVoice && _voicePlaying;
    final isLocation = presentation.kind == 'location';
    final isContactCard = presentation.kind == 'contact';
    final attachment = presentation.attachmentBytes;
    final bool showImage = !isRecalled && presentation.showsInlineImage;
    final bool showFileAttachment =
        !isRecalled && presentation.showsFileAttachment;
    final isUnplayedVoice = incoming &&
        isVoice &&
        !isRecalled &&
        !_voicePlayedMessageIds.contains(m.id);
    final voiceSecs = presentation.voiceSecs;
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
    final incomingColor = baseIncoming;
    // Cycle 53 — extend the per-chat accent set beyond green to
    // include blue + purple, matching the ChoiceChips we added to
    // the chat-info picker.
    Color outgoingColor;
    switch (chatThemeKey) {
      case 'green':
        outgoingColor = isDark ? baseOutgoing : shamellOutgoing;
        break;
      case 'blue':
        outgoingColor = isDark
            ? const Color(0xFF1976D2).withValues(alpha: .55)
            : const Color(0xFFBBDEFB);
        break;
      case 'purple':
        outgoingColor = isDark
            ? const Color(0xFF7B1FA2).withValues(alpha: .55)
            : const Color(0xFFE1BEE7);
        break;
      default:
        outgoingColor = baseOutgoing;
    }
    final replyPreview = presentation.replyPreview;
    final replyToId = decoded.replyToId;
    final bool isHighlighted =
        _highlightedMessageId != null && _highlightedMessageId == m.id;
    final bool isSelected =
        _messageSelectionMode && _selectedMessageIds.contains(m.id);
    final miniProgramTarget = !isRecalled &&
            !isVoice &&
            !isLocation &&
            !isContactCard &&
            presentation.body.plainText.trim().isNotEmpty
        ? parseMiniProgramDeepLinkFromText(presentation.body.plainText)
        : null;
    final avatar = _shamellMessageAvatar(incoming: incoming, me: me);
    // Tweet-style bubbles: wider, card-shaped. Use a generous 0.82
    // (vs the legacy 0.66) so long-form messages read like Twitter/X
    // cards instead of skinny IM ribbons.
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.82;
    BuildContext? bubbleContext;

    // Cycle 46 — slide-up + fade-in entry animation for new bubbles.
    // Recently-arrived messages (createdAt within 3s of now) get the
    // animated reveal; everything older shows instantly so first
    // loads don't sweep the whole thread.
    final age = m.createdAt == null
        ? const Duration(hours: 24)
        : DateTime.now().difference(m.createdAt!);
    final shouldAnimateEntry = age.inSeconds < 3;
    Widget bubbleRoot = _ChatSwipeToReply(
      enabled: interactive && !isRecalled,
      incoming: incoming,
      onTriggered: () {
        unawaited(HapticFeedback.mediumImpact());
        _applyState(() {
          _replyToMessage = m;
        });
      },
      child: GestureDetector(
      onTap: interactive
          ? () {
              if (_messageSelectionMode) {
                _toggleMessageSelected(m.id);
              }
            }
          : null,
      onLongPressStart: interactive
          ? (details) {
              // Haptic confirmation the bubble is being acted on. The
              // selection-mode toggle uses a softer light impact (it's
              // a state flip rather than a menu summon); the menu path
              // uses medium to mirror the system context-menu cue. The
              // audit (P1-19) flagged the chat surface as
              // under-haptic'd; this is the highest-frequency tactile
              // point in the whole UI.
              if (_messageSelectionMode) {
                unawaited(HapticFeedback.selectionClick());
                _toggleMessageSelected(m.id);
              } else {
                unawaited(HapticFeedback.mediumImpact());
                final bubbleRect = _resolveMessageBubbleRect(
                  bubbleContext,
                  fallbackGlobalPosition: details.globalPosition,
                );
                unawaited(
                  _onMessageLongPress(m, bubbleRect: bubbleRect),
                );
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment:
              incoming ? MainAxisAlignment.start : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (incoming) ...[
              SizedBox(
                width: 40,
                height: 40,
                child: showAvatar ? avatar : null,
              ),
              const SizedBox(width: 8),
            ],
            Builder(
              builder: (ctx) {
                bubbleContext = ctx;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: incoming ? incomingColor : outgoingColor,
                          // Tweet-style card frame: every bubble carries a
                          // thin neutral border (Twitter/X has a 1px hairline
                          // between cards). Selected / highlighted states
                          // upgrade the border to a payments-accent /
                          // primary-tint hairline so the focus ring is
                          // visually distinct from the resting border.
                          border: () {
                            if (isSelected) {
                              return Border.all(
                                color:
                                    Tokens.colorPayments.withValues(alpha: .90),
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
                            return Border.all(
                              color: theme.dividerColor.withValues(
                                alpha: isDark ? .30 : .35,
                              ),
                              width: 0.6,
                            );
                          }(),
                          // Less-rounded corners + a faint card shadow lean
                          // the bubble into the X / Twitter tweet aesthetic
                          // (cards instead of pill bubbles).
                          borderRadius:
                              const BorderRadius.all(Radius.circular(5)),
                          boxShadow: isSelected || isHighlighted
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? .18 : .04,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
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
                            if (replyPreview.isNotEmpty && !isRecalled)
                              InkWell(
                                onTap: !interactive || replyToId == null
                                    ? null
                                    : () => _scrollToMessage(replyToId),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface.withValues(
                                        alpha:
                                            theme.brightness == Brightness.dark
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
                              // Voice play tap: previously an `InkWell` whose
                              // hit area was the intrinsic size of the
                              // icon+duration `Row` (~24px tall). On a real
                              // device that meant taps a few pixels above
                              // or below the icon fell through to the outer
                              // selection-mode `GestureDetector` and the
                              // voice clip refused to play until the user
                              // hit the icon dead-center.
                              //
                              // Fix: wrap in a `GestureDetector` with
                              // `HitTestBehavior.opaque` and seat the row in
                              // a 44pt-tall, full-bubble-wide container —
                              // the Material recommended min tap target.
                              // The visible row stays centered; only the
                              // hit-test surface grew. Selection mode still
                              // works because we route the tap through
                              // `_handleMessageTapInSelectionMode` first.
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: !interactive
                                    ? null
                                    : () {
                                        if (_messageSelectionMode) {
                                          _toggleMessageSelected(m.id);
                                          return;
                                        }
                                        unawaited(_onVoiceTap(m));
                                      },
                                child: Semantics(
                                  button: true,
                                  label: text,
                                  child: Container(
                                    width: voiceBubbleWidth,
                                    constraints: const BoxConstraints(
                                      minHeight: 44,
                                    ),
                                    alignment: Alignment.center,
                                    child: Builder(
                                      builder: (waveCtx) {
                                        // Cycle 35 — derive the
                                        // waveform's "played" cutover
                                        // from the live position when
                                        // this bubble is the one being
                                        // played. Otherwise show the
                                        // bar as fully unplayed (0).
                                        double waveProgress = 0.0;
                                        if (isPlayingThisVoice &&
                                            _voiceDurationMs > 0) {
                                          waveProgress = (_voicePositionMs /
                                                  _voiceDurationMs)
                                              .clamp(0.0, 1.0);
                                        }
                                        final unplayedClr = theme
                                            .colorScheme.onSurface
                                            .withValues(alpha: .35);
                                        final playedClr =
                                            theme.colorScheme.primary;
                                        final waveCore = ChatVoiceWaveform(
                                          seed: m.id,
                                          progress: waveProgress,
                                          playedColor: playedClr,
                                          unplayedColor: unplayedClr,
                                        );
                                        // Cycle 42 — tap anywhere on
                                        // the waveform to seek when
                                        // this voice is currently
                                        // playing. Otherwise the tap
                                        // falls through to the parent
                                        // bubble GestureDetector,
                                        // which starts playback.
                                        final wave = GestureDetector(
                                          behavior:
                                              HitTestBehavior.translucent,
                                          onTapUp: !interactive
                                              ? null
                                              : (details) {
                                                  if (!isPlayingThisVoice) {
                                                    // Hand off to the
                                                    // bubble's normal
                                                    // play-tap handler.
                                                    unawaited(_onVoiceTap(m));
                                                    return;
                                                  }
                                                  final box = waveCtx
                                                          .findRenderObject()
                                                      as RenderBox?;
                                                  if (box == null) return;
                                                  final w = box.size.width;
                                                  if (w <= 0) return;
                                                  final frac = (details
                                                              .localPosition.dx /
                                                          w)
                                                      .clamp(0.0, 1.0);
                                                  final dur =
                                                      _voiceDurationMs;
                                                  if (dur <= 0) return;
                                                  final target = Duration(
                                                    milliseconds:
                                                        (frac * dur).round(),
                                                  );
                                                  // ignore: discarded_futures
                                                  _audioPlayer.seek(target);
                                                  setState(() {
                                                    _voicePositionMs =
                                                        target.inMilliseconds;
                                                  });
                                                  unawaited(
                                                      HapticFeedback
                                                          .selectionClick());
                                                },
                                          child: waveCore,
                                        );
                                        return Row(
                                          children: incoming
                                              ? [
                                                  Icon(
                                                    isPlayingThisVoice
                                                        ? Icons.graphic_eq
                                                        : Icons.volume_up,
                                                    size: 18,
                                                    color: isPlayingThisVoice
                                                        ? theme.colorScheme
                                                            .primary
                                                        : theme.colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha: .75),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(child: wave),
                                                  if (voiceDurationText
                                                      .isNotEmpty) ...[
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      voiceDurationText,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                  if (isPlayingThisVoice) ...[
                                                    const SizedBox(width: 4),
                                                    _buildVoiceSpeedBadge(
                                                        theme),
                                                  ],
                                                  if (isUnplayedVoice) ...[
                                                    const SizedBox(width: 4),
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration:
                                                          const BoxDecoration(
                                                        color:
                                                            Colors.redAccent,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ],
                                                ]
                                              : [
                                                  if (isPlayingThisVoice) ...[
                                                    _buildVoiceSpeedBadge(
                                                        theme),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  if (voiceDurationText
                                                      .isNotEmpty) ...[
                                                    Text(
                                                      voiceDurationText,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                  ],
                                                  Flexible(child: wave),
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    isPlayingThisVoice
                                                        ? Icons.graphic_eq
                                                        : Icons.volume_up,
                                                    size: 18,
                                                    color: isPlayingThisVoice
                                                        ? theme.colorScheme
                                                            .primary
                                                        : theme.colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha: .75),
                                                  ),
                                                ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            // Cycle 16: render the transcript inline
                            // below the waveform when present. Tap
                            // to open the existing detail sheet (long
                            // transcripts need the bigger surface).
                            if (isVoice && !isRecalled && inlineTranscript != null) ...<Widget>[
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => _showVoiceTranscript(m),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Icon(
                                        Icons.subtitles_outlined,
                                        size: 13,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .55),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          inlineTranscript,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontStyle: FontStyle.italic,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: .75),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ]
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
                                      const Icon(Icons.place_outlined,
                                          size: 18),
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
                                    onPressed: interactive
                                        ? () => _openLocationOnMap(
                                              decoded.lat!,
                                              decoded.lon!,
                                            )
                                        : null,
                                    icon: const Icon(Icons.map_outlined,
                                        size: 16),
                                    label: Text(l.shamellLocationOpenInMap),
                                  ),
                                ],
                              )
                            else if (isContactCard &&
                                presentation.contactId.isNotEmpty &&
                                !isRecalled)
                              InkWell(
                                onTap: interactive
                                    ? () {
                                        final id = presentation.contactId;
                                        if (id.isEmpty) return;
                                        unawaited(_resolvePeer(presetId: id));
                                      }
                                    : null,
                                child: Builder(
                                  builder: (_) {
                                    final contactId = presentation.contactId;
                                    final name = decoded.text.trim().isNotEmpty
                                        ? decoded.text.trim()
                                        : presentation.contactName;
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
                                            : Colors.white
                                                .withValues(alpha: .95),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.black
                                              .withValues(alpha: .10),
                                        ),
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 10, 12, 10),
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
                                                  color: theme
                                                      .colorScheme.primary
                                                      .withValues(
                                                          alpha: isDark
                                                              ? .24
                                                              : .14),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  initial,
                                                  style: theme
                                                      .textTheme.titleMedium
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      display,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme.bodyMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    if (contactId
                                                        .trim()
                                                        .isNotEmpty)
                                                      Text(
                                                        contactId,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme.bodySmall
                                                            ?.copyWith(
                                                          fontSize: 11,
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface
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
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(alpha: .45),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Divider(
                                            height: 1,
                                            color:
                                                theme.dividerColor.withValues(
                                              alpha: isDark ? .35 : .55,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            l.isArabic
                                                ? 'بطاقة جهة اتصال'
                                                : 'Contact card',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
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
                            else if (miniProgramTarget != null)
                              _buildMiniProgramMessageCard(
                                miniProgramTarget,
                                theme,
                                l,
                                incoming,
                              )
                            else if (loadedPoll != null)
                              // Cycle 15: bubble auto-upgrade. The
                              // text bubble is replaced with a live
                              // poll widget when the server confirms
                              // an attached poll for this message.
                              _buildPollBubbleForMessage(m, loadedPoll)
                            else if (text.isNotEmpty)
                              _buildPossiblyTruncatedBody(
                                m,
                                presentation.body,
                              )
                            else if (!showImage && !showFileAttachment)
                              _buildPossiblyTruncatedBody(
                                m,
                                presentation.body,
                              ),
                            if (showImage) ...[
                              if (text.isNotEmpty) const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: GestureDetector(
                                  onTap: interactive
                                      ? () => _openImage(
                                          attachment!,
                                          decoded.mime,
                                          heroTag: 'chat-img-${m.id}',
                                        )
                                      : null,
                                  onLongPress: interactive
                                      ? () => _shareAttachment(
                                          attachment!, decoded.mime)
                                      : null,
                                  child: Hero(
                                    tag: 'chat-img-${m.id}',
                                    child: Image.memory(
                                    attachment!,
                                    width: 220,
                                    fit: BoxFit.cover,
                                    // Bubble image — the single
                                    // largest memory hog in the chat
                                    // page. Capping decode at 660 px
                                    // (220 logical × 3x DPR) means a
                                    // 4K iPhone photo loads as a
                                    // ~3 MB decoded bitmap instead of
                                    // ~50 MB; with 100 image bubbles
                                    // in a thread this is the
                                    // difference between OOM and
                                    // smooth scrolling on mid-tier
                                    // Android (audit P1-12). Tap to
                                    // open the fullscreen viewer
                                    // (line ~10493) which keeps the
                                    // original full-res decode for
                                    // pixel-peep zoom.
                                    cacheWidth: 660,
                                    filterQuality: FilterQuality.medium,
                                    gaplessPlayback: true,
                                  ),
                                  ),
                                ),
                              ),
                            ],
                            if (showFileAttachment && attachment != null) ...[
                              if (presentation.body.plainText.isNotEmpty)
                                const SizedBox(height: 6),
                              _buildFileAttachmentCard(
                                theme: theme,
                                isDark: isDark,
                                l: l,
                                bytes: attachment,
                                mime: presentation.mime,
                                interactive: interactive,
                              ),
                            ],
                            // Cycle 38 — OpenGraph preview card for the
                            // first URL in the text body. Hidden when
                            // the bubble has nothing useful to preview
                            // (e.g. voice / image-only / no URL).
                            if (!isVoice &&
                                !isRecalled &&
                                presentation.body.plainText.trim().isNotEmpty)
                              _buildLinkPreviewCard(
                                m,
                                presentation.body.plainText,
                                incoming: incoming,
                              ),
                            const SizedBox(height: 4),
                            // Cycle 4: aggregated reaction bar. The
                            // [_buildReactionBarForMessage] helper merges
                            // the server's `m.reactions` payload with
                            // the legacy single-emoji local-cache to
                            // render a complete `{emoji, count, hasMe}`
                            // chip strip, or `SizedBox.shrink()` when
                            // there are no reactions on this message
                            // yet.
                            _buildReactionBarForMessage(m, incoming),
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
                                    if (expTs.isNotEmpty) ...<Widget>[
                                      // Cycle 44 — clock icon paired
                                      // with the countdown. The
                                      // colour matches the on-surface
                                      // variant unless the message is
                                      // already expired, in which
                                      // case we surface error red.
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 11,
                                        color: expTs == 'expired'
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
                                                .withValues(alpha: .85)
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withValues(alpha: .8),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        expTs,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontSize: 11,
                                              color: expTs == 'expired'
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                      .withValues(alpha: .85)
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (showBubbleTail)
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
                );
              },
            ),
            if (!incoming) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                height: 40,
                child: showAvatar ? avatar : null,
              ),
            ],
          ],
        ),
      ),
    ),
    );
    if (shouldAnimateEntry) {
      bubbleRoot = TweenAnimationBuilder<double>(
        key: ValueKey<String>('chat-bubble-entry-${m.id}'),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        tween: Tween<double>(begin: 0, end: 1),
        builder: (_, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 14),
              child: child,
            ),
          );
        },
        child: bubbleRoot,
      );
    }
    return bubbleRoot;
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
    // Cycle 27: surface the user's top-6 most-tapped emojis instead
    // of the hardcoded default. Falls back to the default slate
    // when the user has no history yet.
    final emojis = ChatReactionRecent.instance.currentTop();

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
                  onTap: () async {
                    if (action.closeAfterTap) {
                      await action.onTap();
                      if (mounted) {
                        Navigator.of(context, rootNavigator: true).pop();
                      }
                      return;
                    }
                    Navigator.of(context, rootNavigator: true).pop();
                    await action.onTap();
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

  Rect? _resolveMessageBubbleRect(
    BuildContext? bubbleContext, {
    Offset? fallbackGlobalPosition,
  }) {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;
    final bubbleObject = bubbleContext?.findRenderObject();
    if (bubbleObject is RenderBox) {
      final topLeft =
          bubbleObject.localToGlobal(Offset.zero, ancestor: overlayBox);
      return topLeft & bubbleObject.size;
    }
    final globalPosition = fallbackGlobalPosition;
    if (globalPosition == null) return null;
    final localAnchor = overlayBox.globalToLocal(globalPosition);
    return Rect.fromCenter(center: localAnchor, width: 2, height: 2);
  }

  List<_ShamellMessageMenuActionSpec> _buildMessageLongPressPopoverActions({
    required ChatMessage message,
    required DecodedChatMessagePayload decoded,
    required String preview,
    required String text,
    required bool isVoice,
    required bool isPinned,
    required bool isOwn,
    required bool isRecallEligible,
    required bool isRecalled,
  }) {
    final l = L10n.of(context);
    final actions = <_ShamellMessageMenuActionSpec>[];

    if (text.trim().isNotEmpty && !isVoice) {
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.copy_outlined,
          label: l.shamellCopyMessage,
          onTap: () async {
            await _copyMessageTextFromMenu(text);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.shamellMessageCopiedSnack)),
            );
          },
        ),
      );
    }
    actions.add(
      _ShamellMessageMenuActionSpec(
        icon: Icons.forward,
        label: l.shamellForwardMessage,
        onTap: () async {
          await _forwardMessageFromMenu(message);
        },
      ),
    );
    actions.add(
      _ShamellMessageMenuActionSpec(
        icon: Icons.bookmark_outline,
        label: l.shamellAddToFavorites,
        onTap: () async {
          final favText = text.trim().isNotEmpty ? text.trim() : preview;
          await _addFavoriteItemQuickFromMenu(
            favText,
            chatId: _peer?.id,
            msgId: message.id,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.shamellMessageFavoritedSnack)),
          );
        },
      ),
    );
    if (decoded.kind == 'location' &&
        decoded.lat != null &&
        decoded.lon != null) {
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.place_outlined,
          label: l.shamellLocationFavorite,
          onTap: () async {
            await _addFavoriteLocationQuickFromMenu(
              decoded.lat!,
              decoded.lon!,
              label: text.trim().isNotEmpty ? text.trim() : null,
              chatId: _peer?.id,
              msgId: message.id,
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.shamellLocationFavoritedSnack)),
            );
          },
        ),
      );
    }
    if (!isVoice && text.trim().isNotEmpty) {
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.translate,
          label: l.shamellTranslateMessage,
          onTap: () async {
            await _translateMessageFromMenu(text);
          },
        ),
      );
    }
    if (!isRecalled) {
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.reply,
          label: l.shamellReplyMessage,
          onTap: () async {
            _applyState(() {
              _replyToMessage = message;
            });
          },
        ),
      );
      // Cycle 4: "Add reaction" menu entry. Opens the emoji picker
      // bottom sheet and applies the chosen reaction. Reaction chips
      // beneath the bubble then update from the next inbox refresh
      // (or instantly via the local-cache override in
      // `_buildReactionBarForMessage`).
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.add_reaction_outlined,
          label: l.isArabic ? 'إضافة تفاعل' : 'Add reaction',
          onTap: () async {
            await _openReactionPickerForMessage(message);
          },
        ),
      );
      // Cycle 6: personal bookmark with optional note. Tap toggles
      // the bookmark; on save we show a quick confirmation snackbar.
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.bookmark_outline,
          label: l.isArabic ? 'حفظ كإشارة مرجعية' : 'Bookmark',
          onTap: () async {
            await _bookmarkMessageFromMenu(message);
          },
        ),
      );
      // Cycle 5/1: view edit history for messages that have been
      // edited at least once. The marker comes from the inline
      // `was_edited` flag we already render on the bubble.
      if (message.wasEdited) {
        actions.add(
          _ShamellMessageMenuActionSpec(
            icon: Icons.history,
            label: l.isArabic ? 'سجل التعديلات' : 'Edit history',
            onTap: () async {
              await _openEditHistoryForMessage(message);
            },
          ),
        );
      }
    }
    if (isVoice) {
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: _voiceUseSpeaker ? Icons.volume_up : Icons.hearing,
          label: _voiceUseSpeaker
              ? l.shamellVoiceSpeakerMode
              : l.shamellVoiceEarpieceMode,
          onTap: () async {
            _applyState(() {
              _voiceUseSpeaker = !_voiceUseSpeaker;
            });
          },
        ),
      );
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.subtitles_outlined,
          label: l.isArabic ? 'النص' : 'Transcript',
          onTap: () async {
            await _showVoiceTranscript(message);
          },
        ),
      );
    }
    actions.add(
      _ShamellMessageMenuActionSpec(
        icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: isPinned ? l.shamellUnpinMessage : l.shamellPinMessage,
        closeAfterTap: true,
        onTap: () async {
          await _togglePinMessage(message);
        },
      ),
    );
    if (isRecallEligible) {
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.history_toggle_off,
          label: l.shamellRecallMessage,
          closeAfterTap: true,
          onTap: () async {
            await _setRecalledMessageState(message.id, true);
            await _handleMessageRecalled(message.id);
            await _sendRecallForMessage(message);
          },
        ),
      );
    }
    if (!isOwn) {
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.report_gmailerrorred_outlined,
          label: l.isArabic ? 'إبلاغ' : 'Report',
          color: const Color(0xFFFA5151),
          closeAfterTap: true,
          onTap: () async {
            await _reportMessage(message);
          },
        ),
      );
    }
    if (isOwn) {
      if (!isVoice && text.trim().isNotEmpty && !isRecalled) {
        actions.add(
          _ShamellMessageMenuActionSpec(
            icon: Icons.edit_outlined,
            label: l.isArabic ? 'تعديل' : 'Edit',
            closeAfterTap: true,
            onTap: () async {
              await _editTextMessage(message);
            },
          ),
        );
      }
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.delete_forever_outlined,
          label: l.isArabic ? 'حذف للجميع' : 'Delete for everyone',
          color: const Color(0xFFFA5151),
          closeAfterTap: true,
          onTap: () async {
            await _deleteMessageForEveryone(message);
          },
        ),
      );
      actions.add(
        _ShamellMessageMenuActionSpec(
          icon: Icons.delete_outline,
          label: l.shamellDeleteForMe,
          color: const Color(0xFFFA5151),
          closeAfterTap: true,
          onTap: () async {
            await _deleteMessageLocal(message);
          },
        ),
      );
    }
    actions.add(
      _ShamellMessageMenuActionSpec(
        icon: Icons.check_circle_outline,
        label: l.isArabic ? 'تحديد رسائل متعددة' : 'Select multiple messages',
        onTap: () async {
          _applyState(() {
            _messageSelectionMode = true;
            _selectedMessageIds
              ..clear()
              ..add(message.id);
          });
        },
      ),
    );
    actions.add(
      _ShamellMessageMenuActionSpec(
        icon: Icons.payments_outlined,
        label: l.shamellSendMoney,
        onTap: () async {
          final peerId = _peer?.id;
          if (peerId == null || peerId.isEmpty) return;
          await _openPaymentsPage(initialRecipient: peerId);
        },
      ),
    );
    return actions;
  }

  Future<void> _onMessageLongPress(
    ChatMessage m, {
    Rect? bubbleRect,
  }) async {
    if (_messageSelectionMode) {
      _toggleMessageSelected(m.id);
      return;
    }
    final l = L10n.of(context);
    final d = _decodeMessage(m);
    final preview = _previewText(m, decoded: d);
    final text = d.text.isNotEmpty ? d.text : preview;
    final bool isVoice = d.kind == 'voice';
    final bool isPinned = _isMessagePinned(m);
    final bool isOwn = _isOwnMessage(m);
    final bool isRecallEligible = isOwn &&
        m.createdAt != null &&
        DateTime.now().difference(m.createdAt!.toLocal()) <
            _messageRecallWindow;
    final bool isRecalled = _recalledMessageIds.contains(m.id);
    if (bubbleRect != null) {
      try {
        final incoming = _isIncoming(m);
        final actions = _buildMessageLongPressPopoverActions(
          message: m,
          decoded: d,
          preview: preview,
          text: text,
          isVoice: isVoice,
          isPinned: isPinned,
          isOwn: isOwn,
          isRecallEligible: isRecallEligible,
          isRecalled: isRecalled,
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
                    for (final emoji in ChatReactionRecent.instance.currentTop())
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
                      await shamellCopyToClipboard(text, sensitive: true);
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
                      baseUrlOverride: widget.baseUrl,
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
                        baseUrlOverride: widget.baseUrl,
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
                if (isVoice)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.subtitles_outlined, size: 20),
                    title: Text(l.isArabic ? 'النص' : 'Transcript'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _showVoiceTranscript(m);
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
                      await _setRecalledMessageState(m.id, true);
                      await _handleMessageRecalled(m.id);
                      await _sendRecallForMessage(m);
                    },
                  ),
                if (isOwn)
                  if (!isVoice && text.trim().isNotEmpty && !isRecalled)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined, size: 20),
                      title: Text(l.isArabic ? 'تعديل' : 'Edit'),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await _editTextMessage(m);
                      },
                    ),
                if (isOwn)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.delete_forever_outlined, size: 20),
                    title:
                        Text(l.isArabic ? 'حذف للجميع' : 'Delete for everyone'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _deleteMessageForEveryone(m);
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
                if (!isOwn)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.report_gmailerrorred_outlined,
                      size: 20,
                    ),
                    title: Text(l.isArabic ? 'إبلاغ' : 'Report'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _reportMessage(m);
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
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _openPaymentsPage(initialRecipient: _peer?.id);
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
    });
    try {
      _sessionHash ??= _computeSessionHash();
      final stabilizedTarget = await _stabilizePeerSessionForOutbound(target);
      final bootstrappedTarget =
          await _bootstrapPeerSessionIfNeeded(stabilizedTarget);
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
    final t = token.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(t)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'رمز تسجيل الدخول غير صالح.'
                : 'Invalid device-login token.',
          ),
        ),
      );
      return;
    }
    final sanitizedLabel = sanitizeDeviceLoginLabel(label);
    final uri = _chatApiUri(
      pathSegments: const <String>['auth', 'device_login', 'approve'],
    );
    if (uri == null) {
      _showInvalidServerUrlSnackBar();
      return;
    }
    if (!_beginDeviceLoginApproval()) {
      return;
    }
    final theme = Theme.of(context);
    String bodyText = l.shamellDeviceLoginBody;
    if (sanitizedLabel != null && sanitizedLabel.isNotEmpty) {
      bodyText = l.isArabic
          ? 'السماح للجهاز \"$sanitizedLabel\" بتسجيل الدخول إلى سرتشات باستخدام حسابك؟'
          : 'Allow \"$sanitizedLabel\" to sign in to SyrChat with your account?';
    }
    final httpClient = widget.accountHttpClient ?? shamellHttpClient();
    final closeClient = widget.accountHttpClient == null;
    try {
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
      final resp = await httpClient
          .post(
            uri,
            headers: await _officialHeaders(jsonBody: true),
            body: jsonEncode(<String, Object?>{'token': t}),
          )
          .timeout(_ShamellChatPageState._chatRequestTimeout);
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: resp.statusCode,
        rawBody: resp.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        if (mounted) widget.onCriticalDeviceLoginSessionFailure?.call();
        return;
      }
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shamellDeviceLoginApprovedSnack)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sanitizeHttpError(
                statusCode: resp.statusCode,
                rawBody: resp.body,
                isArabic: l.isArabic,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        if (mounted) widget.onCriticalDeviceLoginSessionFailure?.call();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sanitizeExceptionForUi(error: e, isArabic: l.isArabic)),
        ),
      );
    } finally {
      if (closeClient) {
        httpClient.close();
      }
      _endDeviceLoginApproval();
    }
  }

  Future<ChatContact?> _pickForwardTarget() async {
    final me = _me;
    if (me == null) return null;
    final l = L10n.of(context);
    final candidates = _sortedContacts().where((c) {
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

  /// Cycle 20 — multi-peer forward picker. Returns the set of
  /// contacts the user selected (possibly empty == cancel) for
  /// fanning a single message out to N chats in one go. The shell
  /// is similar to [_pickForwardTarget] but renders checkboxes +
  /// a primary "Forward to N chats" button at the bottom.
  Future<Set<ChatContact>> _pickForwardTargetsMulti() async {
    final me = _me;
    if (me == null) return const <ChatContact>{};
    final l = L10n.of(context);
    final candidates = _sortedContacts().where((c) {
      if ((c.hidden && !_showHidden) || (c.blocked && !_showBlocked)) {
        return false;
      }
      return true;
    }).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic
              ? 'لا توجد محادثات لإعادة التوجيه إليها.'
              : 'No chats available to forward to.'),
        ),
      );
      return const <ChatContact>{};
    }
    final picked = <ChatContact>{};
    final result = await showModalBottomSheet<Set<ChatContact>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (innerCtx, setSheetState) => Padding(
            padding: const EdgeInsets.all(12),
            child: GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l.isArabic
                              ? 'إعادة توجيه إلى…'
                              : 'Forward to…',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (picked.isNotEmpty)
                        Text(
                          '${picked.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (rowCtx, index) {
                        final c = candidates[index];
                        final display = _displayNameForPeer(c);
                        final tags = _friendTags[c.id]?.trim() ?? '';
                        final selected = picked.contains(c);
                        return CheckboxListTile(
                          dense: true,
                          value: selected,
                          onChanged: (v) {
                            setSheetState(() {
                              if (v == true) {
                                picked.add(c);
                              } else {
                                picked.remove(c);
                              }
                            });
                          },
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
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .65),
                                  ),
                                )
                              : null,
                          secondary: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(ctx)
                            .pop(const <ChatContact>{}),
                        child: Text(l.shamellDialogCancel),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.send),
                        onPressed: picked.isEmpty
                            ? null
                            : () => Navigator.of(ctx).pop(picked),
                        label: Text(
                          picked.length <= 1
                              ? (l.isArabic
                                  ? 'إعادة التوجيه'
                                  : 'Forward')
                              : (l.isArabic
                                  ? 'إعادة توجيه (${picked.length})'
                                  : 'Forward to ${picked.length}'),
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
    return result ?? const <ChatContact>{};
  }

  Future<void> _syncPrefsFromServer() async {
    final me = _me;
    if (me == null) return;
    try {
      final prefs = await _service.fetchPrefsPaged(deviceId: me.id);
      if (prefs.isEmpty) return;
      final updated = List<ChatContact>.from(_contacts);
      final changedContacts = <ChatContact>[];
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
          changedContacts.add(newC);
          changed = true;
        }
      }
      if (changed) {
        await _saveScopedContactsForPeers(changedContacts);
        if (!mounted) return;
        _applyState(() {
          _contacts = updated;
        });
      }
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      // ignore – prefs sync is best-effort
    }
  }

  Future<void> _syncGroupPrefsFromServer() async {
    final me = _me;
    if (me == null) return;
    try {
      final prefs = await _service.fetchGroupPrefsPaged(deviceId: me.id);
      if (prefs.isEmpty) return;
      _groupPrefs
        ..clear()
        ..addEntries(prefs.map((p) => MapEntry(p.groupId, p)));
      _applyState(() {});
      await _normalizePinnedChatOrder();
    } catch (e) {
      if (await _forceReauthOnCriticalChatFailure(e)) return;
      // best-effort
    }
  }

  Widget _buildChatAppBarTitle(ChatContact peer) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final displayName = _displayNameForPeer(peer).trim();
    final titleText = displayName.isNotEmpty ? displayName : peer.id;
    // Cycle 37 — render an "online" / "last seen Xm ago" subtitle
    // when we have a recent presence record for this peer. Falls back
    // to the bare name when presence is unknown.
    String? presenceSubtitle = _formatPresenceSubtitle(peer.id, l);
    // Cycle 58 — when the peer has a published status, prefer that
    // string over the presence subtitle. Presence is decorative;
    // status is intentional — it should win.
    final statusEmoji = _peerProfileStatusEmoji[peer.id];
    final statusText = _peerProfileStatusText[peer.id];
    if ((statusEmoji != null && statusEmoji.isNotEmpty) ||
        (statusText != null && statusText.isNotEmpty)) {
      final parts = <String>[];
      if (statusEmoji != null && statusEmoji.isNotEmpty) parts.add(statusEmoji);
      if (statusText != null && statusText.isNotEmpty) parts.add(statusText);
      presenceSubtitle = parts.join(' ');
    }
    // Cycle 51 — tap the AppBar title to jump straight into the
    // chat-info page (parity with WhatsApp / Telegram). The "..."
    // icon still works as a redundant fallback.
    Widget wrapTappable(Widget child) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showContactInfo,
          child: child,
        );
    if (presenceSubtitle == null) {
      return wrapTappable(Text(
        titleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ));
    }
    final isOnline = presenceSubtitle == 'online' ||
        presenceSubtitle == 'متصل الآن';
    return wrapTappable(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          titleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isOnline) ...<Widget>[
              const ChatPulseDot(size: 7),
              const SizedBox(width: 4),
            ],
            Text(
              presenceSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isOnline
                    ? const Color(0xFF4CAF50)
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ));
  }

  Future<void> _dispatchChatTileTap(ChatContact contact) async {
    final override = widget.onChatTileTapOverride;
    if (override != null) {
      await override(contact);
      return;
    }
    await _switchPeer(contact);
  }

  Future<void> _handleChatTileTap(ChatContact contact) async {
    if (_selectionMode) {
      _toggleChatSelected(contact.id);
      return;
    }
    await _dispatchChatTileTap(contact);
  }

  Future<void> _dispatchChatLongPress(
    ChatContact contact, {
    Offset? globalPosition,
  }) async {
    final override = widget.onChatLongPressOverride;
    if (override != null) {
      await override(contact, globalPosition);
      return;
    }
    await _onChatLongPress(contact, globalPosition: globalPosition);
  }

  Future<void> _handleChatTileLongPress(
    ChatContact contact, {
    Offset? globalPosition,
  }) async {
    if (_selectionMode) {
      _toggleChatSelected(contact.id);
      return;
    }
    await _dispatchChatLongPress(contact, globalPosition: globalPosition);
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
            closeAfterTap: true,
            onTap: () => _toggleChatReadUnread(c),
          ),
          _ShamellPopoverActionSpec(
            label: pinLabel,
            closeAfterTap: true,
            onTap: () => _toggleChatPinned(c),
          ),
          _ShamellPopoverActionSpec(
            label: moreLabel,
            onTap: () => _showChatMoreSheetAfterDelay(c),
          ),
          _ShamellPopoverActionSpec(
            label: deleteLabel,
            color: const Color(0xFFFA5151),
            closeAfterTap: true,
            onTap: () => _deleteChatById(c.id),
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
                    onTap: () async {
                      await _toggleChatReadUnread(c);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: pinLabel,
                    onTap: () async {
                      await _toggleChatPinned(c);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: moreLabel,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _showChatMoreSheetAfterDelay(c);
                    },
                  ),
                  const Divider(height: 1),
                  actionRow(
                    label: deleteLabel,
                    color: sheetTheme.colorScheme.error,
                    onTap: () async {
                      await _deleteChatById(c.id);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
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
      current = await store.loadOfficialNotifMode(
        c.id,
        baseUrlOverride: widget.baseUrl,
      );
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
    await _saveScopedContactsForPeers(<ChatContact>[updated]);
    await _store.setOfficialNotifMode(
      updated.id,
      mode,
      baseUrlOverride: widget.baseUrl,
    );
    // Best-effort sync to server for official accounts.
    final accId = _officialPeerToAccountId[updated.id];
    if (accId != null && accId.isNotEmpty) {
      final uri = _chatApiUri(
        pathSegments: <String>['official_accounts', accId, 'notification_mode'],
      );
      if (uri == null) {
        if (!mounted) return;
        _applyState(() {
          _contacts = contacts;
          if (_peer?.id == updated.id) {
            _peer = updated;
          }
        });
        return;
      }
      final httpClient = widget.officialHttpClient ?? shamellHttpClient();
      final closeClient = widget.officialHttpClient == null;
      try {
        final body = jsonEncode({
          'mode': switch (mode) {
            OfficialNotificationMode.full => 'full',
            OfficialNotificationMode.summary => 'summary',
            OfficialNotificationMode.muted => 'muted',
          }
        });
        final reqHeaders = await _officialHeaders(jsonBody: true);
        final idempotencyScope = '$accId|$body';
        final idempotencyKey =
            _pendingOfficialNotificationModeIdempotencyKeys.putIfAbsent(
          idempotencyScope,
          () => _newOfficialMutationIdempotencyKey('official-notif-mode'),
        );
        reqHeaders['Idempotency-Key'] = idempotencyKey;
        final r = await httpClient
            .post(uri, headers: reqHeaders, body: body)
            .timeout(_ShamellChatPageState._chatRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          _pendingOfficialNotificationModeIdempotencyKeys
              .remove(idempotencyScope);
        } else if (await _forceReauthOnCriticalOfficialHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          return;
        }
      } catch (_) {
      } finally {
        if (closeClient) {
          httpClient.close();
        }
      }
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
    unawaited(
      _store.markVoicePlayed(
        peerId,
        m.id,
        baseUrlOverride: widget.baseUrl,
      ),
    );
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
      await _audioPlayer.stop();
      await _clearVoicePlaybackFile();
      final file = await writeEphemeralVoiceFile(
        bytes,
        stem: 'voice_playback_${m.id}',
      );
      _voicePlaybackPath = file.path;
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
      await _audioPlayer.setFilePath(file.path);
      // Apply the persisted playback speed before `play()` so a 1.5×
      // or 2× preference is in effect from the first sample. Without
      // this the player would start at 1× and only honour the user's
      // preference after they bump the badge mid-play. (Cycle 3 P1-11.)
      await _applyVoicePlaybackSpeedToPlayer();
      if (!mounted) return;
      _applyState(() {
        _playingVoiceMessageId = m.id;
        // Cycle 35 — reset the waveform progress when switching to a
        // new voice message so the new bubble starts from "all
        // unplayed" instead of inheriting the prior bubble's fraction.
        _voicePositionMs = 0;
        _voiceDurationMs = _audioPlayer.duration?.inMilliseconds ?? 0;
      });
      await _audioPlayer.play();
    } catch (_) {
      await _clearVoicePlaybackFile();
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
                  () async {
                    Navigator.of(ctx).pop();
                    await _openPaymentsPage(initialRecipient: peer.id);
                  },
                ),
                buildAction(
                  Icons.card_giftcard_outlined,
                  'Green Paket',
                  () async {
                    Navigator.of(ctx).pop();
                    await _openGreenPaketForChat(peer);
                  },
                ),
                buildAction(
                  Icons.apps_rounded,
                  l.isArabic ? 'برنامج مصغّر' : 'Mini Program',
                  () async {
                    Navigator.of(ctx).pop();
                    await _showMiniProgramShareSheet(peer);
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
    final uri = normalizeExternalDialUri(id);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic
              ? 'لا يوجد رقم هاتف مرتبط بهذا الحساب.'
              : 'No phone number linked to this contact.'),
        ),
      );
      return;
    }
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
      _callStore.append(entry, baseUrlOverride: widget.baseUrl);
      final me = _me;
      if (me != null) {
        unawaited(() async {
          try {
            await _service.saveCallLog(deviceId: me.id, entry: entry);
          } catch (_) {}
        }());
      }
      await launchUrl(
        uri,
        mode: shamellExternalLaunchMode(uri),
      );
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
    if (!shamellAllowsRealtimeCalls()) {
      shamellShowRestrictedMediaSnack(
        context,
        camera: mode.toLowerCase() == 'video',
        microphone: true,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoipCallPage(
          baseUrl: widget.baseUrl,
          peerId: p.id,
          displayName: _displayNameForPeer(p),
          mode: mode,
          isCaller: true,
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

  Uri _inviteUri(String token) {
    return buildShamellInviteAppLink(token);
  }

  Future<String> _createInviteTokenWithBootstrap() async {
    try {
      return await _service.createContactInviteTokenEnsured(maxUses: 1);
    } catch (e) {
      if (mounted) {
        await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        );
      }
      rethrow;
    }
  }

  Future<void> _showInviteQr() async {
    final l = L10n.of(context);
    var showing = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ).whenComplete(() => showing = false),
    );

    try {
      final token = await _createInviteTokenWithBootstrap();
      final payload = token.isNotEmpty ? _inviteUri(token).toString() : '';
      if (!mounted) return;
      if (showing) {
        Navigator.of(context, rootNavigator: true).pop();
        showing = false;
      }
      if (payload.isEmpty) return;

      final profileName = _displayNameCtrl.text.trim().isNotEmpty
          ? _displayNameCtrl.text.trim()
          : (_me?.displayName ?? '').trim();

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ShamellMyQrCodePage(
            payload: payload,
            profileName: profileName,
            // Invite QR is a bearer capability; keep stable IDs off the QR page.
            profileShamellId: '',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (showing) {
        Navigator.of(context, rootNavigator: true).pop();
        showing = false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sanitizeExceptionForUi(error: e, isArabic: l.isArabic)),
        ),
      );
    } finally {
      if (mounted && showing) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  void _showQr(ChatIdentity me) {
    final payload = jsonEncode({
      'id': me.id,
      'pub': me.publicKeyB64,
      'fp': me.fingerprint,
      'name': me.displayName
    });
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ChatIdentityQrPage(identity: me, payload: payload),
      ),
    );
  }
}

class _ChatIdentityQrPage extends StatelessWidget {
  final ChatIdentity identity;
  final String payload;

  const _ChatIdentityQrPage({
    required this.identity,
    required this.payload,
  });

  Future<void> _copy(BuildContext context, String value) async {
    final l = L10n.of(context);
    try {
      await shamellCopyToClipboard(value, sensitive: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.isArabic ? 'تم النسخ.' : 'Copied.'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;
    final displayName = (identity.displayName ?? '').trim().isNotEmpty
        ? identity.displayName!.trim()
        : l.shamellIdentityTitle;
    final initial = displayName.characters.isEmpty
        ? '?'
        : displayName.characters.first.toUpperCase();
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: .62),
    );

    Widget valueTile({
      required IconData icon,
      required Color color,
      required String title,
      required String value,
      VoidCallback? onCopy,
    }) {
      return ListTile(
        dense: true,
        leading: ShamellLeadingIcon(icon: icon, background: color),
        title: Text(title),
        subtitle: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: secondaryStyle,
        ),
        trailing: onCopy == null
            ? null
            : IconButton(
                tooltip: l.isArabic ? 'نسخ' : 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_outlined, size: 19),
                onPressed: onCopy,
              ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.shamellIdentityTitle),
        backgroundColor: bgColor,
        elevation: .5,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'مشاركة' : 'Share',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => Share.share(
              'Chat ID: ${identity.id}\nFingerprint: ${identity.fingerprint}',
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.dividerColor.withValues(
                          alpha: isDark ? .50 : .85,
                        ),
                        width: .7,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 56,
                                height: 56,
                                color: ShamellPalette.green.withValues(
                                  alpha: isDark ? .18 : .10,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  initial,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: QrImageView(
                            data: payload,
                            version: QrVersions.auto,
                            size: 220,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l.isArabic
                              ? 'استخدم هذا الرمز للتحقق من هوية الدردشة.'
                              : 'Use this code to verify chat identity.',
                          textAlign: TextAlign.center,
                          style: secondaryStyle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ShamellSection(
                    margin: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(10),
                    dividerIndent: 72,
                    children: [
                      valueTile(
                        icon: Icons.badge_outlined,
                        color: const Color(0xFF2563EB),
                        title: l.shamellIdentityTitle,
                        value: identity.id,
                        onCopy: () => _copy(context, identity.id),
                      ),
                      valueTile(
                        icon: Icons.verified_user_outlined,
                        color: const Color(0xFF14B8A6),
                        title: l.chatMyFingerprint,
                        value: identity.fingerprint,
                        onCopy: () => _copy(context, identity.fingerprint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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

class _ShamellComposerMoreActionSpec {
  final IconData icon;
  final String label;
  final Color accent;
  final Future<void> Function() onTap;

  const _ShamellComposerMoreActionSpec({
    required this.icon,
    required this.label,
    this.accent = const Color(0xFF64748B),
    required this.onTap,
  });
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

class _ShamellPopoverActionSpec {
  final String label;
  final Color color;
  final Future<void> Function() onTap;
  final bool closeAfterTap;

  const _ShamellPopoverActionSpec({
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.closeAfterTap = false,
  });
}

class _ShamellMessageMenuActionSpec {
  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap;
  final bool closeAfterTap;

  const _ShamellMessageMenuActionSpec({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.closeAfterTap = false,
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

/// Cycle 36 — search delegate for the in-thread message search.
/// Filters the already-loaded messages list by decoded text. The
/// result is the matched message's id (returned via the delegate's
/// `close(context, id)`); the caller scroll-jumps to it.
class _ChatThreadSearchDelegate extends SearchDelegate<String?> {
  final List<ChatMessage> messages;
  final String Function(ChatMessage) decode;
  final String? myId;
  final String hint;
  final String emptyText;

  _ChatThreadSearchDelegate({
    required this.messages,
    required this.decode,
    required this.myId,
    required this.hint,
    required this.emptyText,
  }) : super(searchFieldLabel: hint);

  List<ChatMessage> _matches(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return const <ChatMessage>[];
    final out = <ChatMessage>[];
    for (final m in messages) {
      final t = decode(m);
      if (t.isEmpty) continue;
      if (t.toLowerCase().contains(q)) out.add(m);
    }
    // Newest first — matches how the thread reads.
    out.sort((a, b) {
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return out;
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return <Widget>[
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _resultList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _resultList(context);

  Widget _resultList(BuildContext context) {
    if (query.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    final rows = _matches(query);
    if (rows.isEmpty) {
      return Center(
        child: Text(emptyText),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final m = rows[i];
        final text = decode(m);
        final ts = m.createdAt?.toLocal();
        final isMine = myId != null && m.senderId == myId;
        final subtitle = ts == null ? '' : _formatTimestamp(ts);
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: isMine
                ? Theme.of(ctx).colorScheme.primary
                : Theme.of(ctx).colorScheme.surfaceContainerHighest,
            child: Icon(
              isMine ? Icons.person : Icons.person_outline,
              color: isMine ? Theme.of(ctx).colorScheme.onPrimary : null,
              size: 14,
            ),
          ),
          title: _highlightedTitle(ctx, text, query),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          onTap: () => close(ctx, m.id),
        );
      },
    );
  }

  /// Cycle 52 — bold-highlight the matched query substring(s) inside
  /// the message preview shown in the search result list. Renders as
  /// a RichText with alternating plain/bold spans.
  Widget _highlightedTitle(BuildContext ctx, String body, String query) {
    final q = query.trim();
    if (q.isEmpty) {
      return Text(body, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final theme = Theme.of(ctx);
    final spans = <TextSpan>[];
    final lower = body.toLowerCase();
    final ql = q.toLowerCase();
    int idx = 0;
    while (idx < body.length) {
      final hit = lower.indexOf(ql, idx);
      if (hit < 0) {
        spans.add(TextSpan(text: body.substring(idx)));
        break;
      }
      if (hit > idx) {
        spans.add(TextSpan(text: body.substring(idx, hit)));
      }
      spans.add(TextSpan(
        text: body.substring(hit, hit + q.length),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
          backgroundColor:
              theme.colorScheme.secondaryContainer.withValues(alpha: .55),
        ),
      ));
      idx = hit + q.length;
      if (idx >= body.length) break;
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(ctx).style,
        children: spans,
      ),
    );
  }

  static String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final isToday = now.year == ts.year &&
        now.month == ts.month &&
        now.day == ts.day;
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    if (isToday) return '$hh:$mm';
    final dd = ts.day.toString().padLeft(2, '0');
    final mo = ts.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }
}

/// Cycle 39 — WhatsApp-style "swipe to reply" wrapper around a
/// message bubble. The bubble is translated by the drag amount up to
/// a cap, a small reply-arrow icon fades in behind it, and crossing
/// the trigger threshold fires [onTriggered]. The bubble snaps back
/// to its resting position on drag-end regardless of whether the
/// trigger fired.
///
/// Direction conventions:
///   - Incoming bubble: swipe RIGHT (drag dx > 0) to reply
///   - Outgoing bubble: swipe LEFT  (drag dx < 0) to reply
///
/// This matches WhatsApp / Telegram on Android. The icon appears on
/// the *opposite* side of the swipe direction (so the user pulls the
/// bubble *over* the icon).
class _ChatSwipeToReply extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final bool incoming;
  final VoidCallback onTriggered;

  const _ChatSwipeToReply({
    required this.child,
    required this.enabled,
    required this.incoming,
    required this.onTriggered,
  });

  @override
  State<_ChatSwipeToReply> createState() => _ChatSwipeToReplyState();
}

class _ChatSwipeToReplyState extends State<_ChatSwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _triggerPx = 56;
  static const double _maxPullPx = 96;

  /// Current drag offset along the swipe axis. Sign matches the
  /// drag direction; magnitude is capped at [_maxPullPx].
  double _dx = 0.0;
  bool _firedThisGesture = false;
  late final AnimationController _settleCtrl;
  late Animation<double> _settleAnim;

  @override
  void initState() {
    super.initState();
    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _settleAnim = AlwaysStoppedAnimation<double>(0);
    _settleCtrl.addListener(() {
      if (!mounted) return;
      setState(() {
        _dx = _settleAnim.value;
      });
    });
  }

  @override
  void dispose() {
    _settleCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final raw = _dx + details.delta.dx;
    final allowedSign = widget.incoming ? 1 : -1;
    if (raw == 0) {
      setState(() => _dx = 0);
      return;
    }
    final wantSign = raw > 0 ? 1 : -1;
    if (wantSign != allowedSign) {
      // Disallow the opposite direction — bubble stays put.
      setState(() => _dx = 0);
      return;
    }
    final capped = raw.clamp(-_maxPullPx, _maxPullPx).toDouble();
    setState(() => _dx = capped);
    if (!_firedThisGesture && capped.abs() >= _triggerPx) {
      _firedThisGesture = true;
      unawaited(HapticFeedback.lightImpact());
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled) {
      _dx = 0;
      _firedThisGesture = false;
      setState(() {});
      return;
    }
    final triggered = _dx.abs() >= _triggerPx;
    if (triggered) {
      widget.onTriggered();
    }
    _settleAnim = Tween<double>(begin: _dx, end: 0).animate(
      CurvedAnimation(parent: _settleCtrl, curve: Curves.easeOut),
    );
    _settleCtrl
      ..reset()
      ..forward().then((_) {
        if (!mounted) return;
        setState(() {
          _firedThisGesture = false;
        });
      });
  }

  void _onDragCancel() {
    if (_dx == 0) return;
    _settleAnim = Tween<double>(begin: _dx, end: 0).animate(
      CurvedAnimation(parent: _settleCtrl, curve: Curves.easeOut),
    );
    _settleCtrl
      ..reset()
      ..forward().then((_) {
        if (!mounted) return;
        setState(() {
          _firedThisGesture = false;
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_dx.abs() / _triggerPx).clamp(0.0, 1.0);
    final iconColor = _firedThisGesture
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: .6);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: Stack(
        children: <Widget>[
          // The reply icon rides on the OPPOSITE side from the
          // drag direction. For incoming bubbles (swipe right) it
          // sits on the LEFT; for outgoing bubbles (swipe left) it
          // sits on the RIGHT.
          if (_dx.abs() > 4)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: widget.incoming
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8 + 12 * progress,
                    ),
                    child: Opacity(
                      opacity: progress,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: .85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.reply,
                          size: 16,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
