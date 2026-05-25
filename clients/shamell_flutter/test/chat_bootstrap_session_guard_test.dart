import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pinenacl/x25519.dart' as x25519;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/shamell_user_id.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/ratchet_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_page.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/favorites_store.dart';
import 'package:shamell_flutter/core/friend_annotations_store.dart';
import 'package:shamell_flutter/core/official_account_models.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/v2_chat_strangler.dart';

const _baseUrl = 'https://api.example.com';
const _meId = 'device_self';
const _peerId = 'peer_1';
const _groupId = 'group_1';

String _curveKeyB64(int seed) => base64Encode(
      Uint8List.fromList(
        List<int>.generate(32, (i) => ((seed + i) % 251) + 1),
      ),
    );

ChatIdentity _buildMe() => ChatIdentity(
      id: _meId,
      publicKeyB64: _curveKeyB64(1),
      privateKeyB64: _curveKeyB64(97),
      fingerprint: 'fp-self',
    );

ChatContact _buildPeer() => ChatContact(
      id: _peerId,
      publicKeyB64: _curveKeyB64(33),
      fingerprint: 'fp-peer',
      name: 'Peer',
    );

ChatIdentity _buildRealIdentity({
  required String id,
  required int seed,
  String? name,
}) {
  final raw = Uint8List.fromList(
    List<int>.generate(32, (i) => ((seed + (i * 17)) % 251) + 1),
  );
  final sk = x25519.PrivateKey(raw);
  final publicKeyB64 = base64Encode(sk.publicKey.asTypedList);
  return ChatIdentity(
    id: id,
    publicKeyB64: publicKeyB64,
    privateKeyB64: base64Encode(raw),
    fingerprint: fingerprintForKey(publicKeyB64),
    displayName: name,
  );
}

ChatContact _contactForIdentity(ChatIdentity identity, {String? name}) =>
    ChatContact(
      id: identity.id,
      publicKeyB64: identity.publicKeyB64,
      fingerprint: identity.fingerprint,
      name: name,
    );

Uint8List _deriveInitialRatchetMessageKey({
  required ChatIdentity sender,
  required ChatIdentity recipient,
  required int counter,
}) {
  final shared = x25519.Box(
    myPrivateKey: x25519.PrivateKey(base64Decode(sender.privateKeyB64)),
    theirPublicKey: x25519.PublicKey(base64Decode(recipient.publicKeyB64)),
  ).sharedKey;
  final rootKey =
      Uint8List.fromList(crypto.sha256.convert(shared.asTypedList).bytes);
  final hmac = crypto.Hmac(crypto.sha256, rootKey);
  return Uint8List.fromList(hmac.convert(utf8.encode('msg-$counter')).bytes);
}

ChatMessage _buildSealedRatchetMessage({
  required ChatIdentity sender,
  required ChatIdentity recipient,
  required String text,
  required String id,
  required DateTime createdAt,
  int keyId = 0,
}) {
  final messageKey = _deriveInitialRatchetMessageKey(
    sender: sender,
    recipient: recipient,
    counter: keyId,
  );
  final nonce = Uint8List.fromList(
    List<int>.generate(24, (i) => ((keyId + i) % 251) + 1),
  );
  final payload = jsonEncode(<String, Object?>{
    'text': text,
    'client_ts': createdAt.toIso8601String(),
    'sender_fp': sender.fingerprint,
  });
  final cipher = x25519.SecretBox(messageKey).encrypt(
    Uint8List.fromList(utf8.encode(payload)),
    nonce: nonce,
  );
  return ChatMessage(
    id: id,
    senderId: sender.id,
    recipientId: recipient.id,
    senderPubKeyB64: sender.publicKeyB64,
    nonceB64: base64Encode(cipher.nonce.asTypedList),
    boxB64: base64Encode(cipher.cipherText.asTypedList),
    createdAt: createdAt,
    sealedSender: true,
    senderHint: sender.fingerprint,
    keyId: keyId,
    prevKeyId: keyId > 0 ? keyId - 1 : 0,
    senderDhPubB64: sender.publicKeyB64,
  );
}

ChatGroup _buildGroup() => const ChatGroup(
      id: _groupId,
      name: 'Security Group',
      creatorId: _meId,
      memberCount: 2,
    );

ChatGroupMessage _buildGroupMessage({
  String id = 'group_msg_1',
  String text = 'hello group',
  DateTime? createdAt,
}) =>
    ChatGroupMessage(
      id: id,
      groupId: _groupId,
      senderId: _meId,
      text: text,
      createdAt: createdAt ?? DateTime.now(),
    );

ChatMessage _buildDirectMessage({
  String id = 'direct_msg_1',
  String text = 'hello direct',
  Map<String, Object?>? payload,
  DateTime? createdAt,
  String senderId = _peerId,
  String recipientId = _meId,
}) {
  final effectiveCreatedAt = createdAt ?? DateTime.utc(2026, 3, 20, 10, 0, 0);
  final encodedPayload = payload ??
      <String, Object?>{
        'text': text,
        'client_ts': effectiveCreatedAt.toIso8601String(),
      };
  return ChatMessage(
    id: id,
    senderId: senderId,
    recipientId: recipientId,
    senderPubKeyB64: _curveKeyB64(33),
    nonceB64: '',
    boxB64: base64Encode(utf8.encode(jsonEncode(encodedPayload))),
    trustedLocalPlaintext: true,
    createdAt: effectiveCreatedAt,
  );
}

class _FakeChatBootstrapService extends ChatService {
  _FakeChatBootstrapService({
    this.fetchInboxError,
    this.fetchThreadHistoryHandler,
    this.fetchKeyBundleHandler,
    this.libsignalKeyApiEnabledOverride = false,
    this.resolveDeviceHandler,
    this.sendTypingSignalHandler,
    this.listGroupsError,
    this.fetchGroupInboxError,
    this.fetchPrefsError,
    this.fetchGroupPrefsError,
    this.listGroupsPagedHandler,
    this.fetchInboxPagedHandler,
    this.fetchPrefsPagedHandler,
    this.fetchGroupPrefsPagedHandler,
    this.setGroupPrefsHandler,
    this.streamInboxHandler,
    this.streamGroupInboxHandler,
    this.ensureAccountChatReadyHandler,
  }) : super(_baseUrl);

  final Object? fetchInboxError;
  final List<ChatMessage> Function({
    String? beforeCreatedAt,
    String? beforeId,
  })? fetchThreadHistoryHandler;
  final Future<ChatKeyBundle> Function({
    required String targetDeviceId,
    String? requesterDeviceId,
  })? fetchKeyBundleHandler;
  final bool libsignalKeyApiEnabledOverride;
  final Future<ChatContact> Function(String peerId)? resolveDeviceHandler;
  final Future<void> Function({
    required String deviceId,
    required bool isTyping,
    String? peerId,
    String? groupId,
  })? sendTypingSignalHandler;
  final Object? listGroupsError;
  final Object? fetchGroupInboxError;
  final Object? fetchPrefsError;
  final Object? fetchGroupPrefsError;
  final Future<List<ChatGroup>> Function({
    required String deviceId,
    int batchSize,
    int maxPages,
  })? listGroupsPagedHandler;
  final Future<List<ChatMessage>> Function({
    required String deviceId,
    String? sinceIso,
    String? sinceId,
    int batchSize,
    int maxPages,
    int? retainLatestCount,
  })? fetchInboxPagedHandler;
  final Future<List<ChatContactPrefs>> Function({
    required String deviceId,
    int batchSize,
    int maxPages,
  })? fetchPrefsPagedHandler;
  final Future<List<ChatGroupPrefs>> Function({
    required String deviceId,
    int batchSize,
    int maxPages,
  })? fetchGroupPrefsPagedHandler;
  final Future<void> Function({
    required String deviceId,
    required String groupId,
    bool? muted,
    bool? pinned,
  })? setGroupPrefsHandler;
  final Stream<List<ChatMessage>> Function({required String deviceId})?
      streamInboxHandler;
  final Stream<ChatGroupInboxUpdate> Function({required String deviceId})?
      streamGroupInboxHandler;
  final Future<void> Function()? ensureAccountChatReadyHandler;
  int resolveDeviceCallCount = 0;
  int fetchKeyBundleCallCount = 0;
  String? lastFetchGroupInboxSinceIso;
  String? lastFetchGroupInboxSinceId;
  String? lastFetchInboxPagedSinceIso;
  String? lastFetchInboxPagedSinceId;
  String? lastFetchInboxPagedDeviceId;
  String? lastFetchInboxDeviceId;
  String? lastStreamInboxDeviceId;
  int ensureAccountChatReadyCallCount = 0;
  int streamInboxCallCount = 0;
  final List<String?> fetchInboxBeforeIds = <String?>[];
  final List<String?> fetchThreadHistoryBeforeIds = <String?>[];
  int fetchInboxCallCount = 0;
  int fetchThreadHistoryCallCount = 0;
  int fetchInboxPagedCallCount = 0;
  int fetchPrefsCallCount = 0;
  int fetchGroupPrefsCallCount = 0;
  int fetchPrefsPagedCallCount = 0;
  int fetchGroupPrefsPagedCallCount = 0;
  int listGroupsPagedCallCount = 0;
  int fetchGroupInboxCallCount = 0;
  final List<
          ({String deviceId, bool isTyping, String? peerId, String? groupId})>
      typingSignals =
      <({String deviceId, bool isTyping, String? peerId, String? groupId})>[];

  @override
  bool get libsignalKeyApiEnabled => libsignalKeyApiEnabledOverride;

  @override
  Future<List<ChatMessage>> fetchInbox({
    required String deviceId,
    int limit = 50,
    String? sinceIso,
    String? sinceId,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    fetchInboxCallCount += 1;
    lastFetchInboxDeviceId = deviceId;
    fetchInboxBeforeIds.add(beforeId);
    final error = fetchInboxError;
    if (error != null) throw error;
    return const <ChatMessage>[];
  }

  @override
  Future<List<ChatMessage>> fetchInboxPaged({
    required String deviceId,
    String? sinceIso,
    String? sinceId,
    int batchSize = 200,
    int maxPages = 25,
    int? retainLatestCount,
  }) async {
    fetchInboxPagedCallCount += 1;
    lastFetchInboxPagedDeviceId = deviceId;
    lastFetchInboxPagedSinceIso = sinceIso;
    lastFetchInboxPagedSinceId = sinceId;
    final handler = fetchInboxPagedHandler;
    if (handler != null) {
      return handler(
        deviceId: deviceId,
        sinceIso: sinceIso,
        sinceId: sinceId,
        batchSize: batchSize,
        maxPages: maxPages,
        retainLatestCount: retainLatestCount,
      );
    }
    final error = fetchInboxError;
    if (error != null) throw error;
    return const <ChatMessage>[];
  }

  @override
  Future<List<ChatMessage>> fetchThreadHistory({
    required String deviceId,
    required String peerId,
    int limit = 200,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    fetchThreadHistoryCallCount += 1;
    fetchThreadHistoryBeforeIds.add(beforeId);
    final handler = fetchThreadHistoryHandler;
    if (handler != null) {
      return handler(
        beforeCreatedAt: beforeCreatedAt,
        beforeId: beforeId,
      );
    }
    return const <ChatMessage>[];
  }

  @override
  Future<ChatContact> resolveDevice(String id) async {
    resolveDeviceCallCount += 1;
    final handler = resolveDeviceHandler;
    if (handler != null) {
      return handler(id);
    }
    final publicKeyB64 = _curveKeyB64(55);
    return ChatContact(
      id: id,
      publicKeyB64: publicKeyB64,
      fingerprint: fingerprintForKey(publicKeyB64),
      name: 'Resolved Peer',
    );
  }

  @override
  Future<void> sendTypingSignal({
    required String deviceId,
    required bool isTyping,
    String? peerId,
    String? groupId,
  }) async {
    typingSignals.add((
      deviceId: deviceId,
      isTyping: isTyping,
      peerId: peerId,
      groupId: groupId,
    ));
    final handler = sendTypingSignalHandler;
    if (handler != null) {
      await handler(
        deviceId: deviceId,
        isTyping: isTyping,
        peerId: peerId,
        groupId: groupId,
      );
    }
  }

  @override
  Future<ChatKeyBundle> fetchKeyBundle({
    required String targetDeviceId,
    String? requesterDeviceId,
  }) async {
    fetchKeyBundleCallCount += 1;
    final handler = fetchKeyBundleHandler;
    if (handler != null) {
      return handler(
        targetDeviceId: targetDeviceId,
        requesterDeviceId: requesterDeviceId,
      );
    }
    return ChatKeyBundle(
      deviceId: targetDeviceId,
      identityKeyB64: _curveKeyB64(88),
      identitySigningPubkeyB64: _curveKeyB64(89),
      signedPrekeyId: 1,
      signedPrekeyB64: _curveKeyB64(90),
      signedPrekeySigB64: 'sig',
    );
  }

  @override
  Future<List<ChatGroup>> listGroups({required String deviceId}) async {
    final error = listGroupsError;
    if (error != null) throw error;
    return const <ChatGroup>[
      ChatGroup(
        id: _groupId,
        name: 'Security Group',
        creatorId: _meId,
        memberCount: 2,
      ),
    ];
  }

  @override
  Future<List<ChatGroup>> listGroupsPaged({
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    listGroupsPagedCallCount += 1;
    final handler = listGroupsPagedHandler;
    if (handler != null) {
      return handler(
        deviceId: deviceId,
        batchSize: batchSize,
        maxPages: maxPages,
      );
    }
    return listGroups(deviceId: deviceId);
  }

  @override
  Future<List<ChatGroupMessage>> fetchGroupInbox({
    required String groupId,
    required String deviceId,
    int limit = 50,
    String? sinceIso,
    String? sinceId,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    fetchGroupInboxCallCount += 1;
    lastFetchGroupInboxSinceIso = sinceIso;
    lastFetchGroupInboxSinceId = sinceId;
    final error = fetchGroupInboxError;
    if (error != null) throw error;
    return const <ChatGroupMessage>[];
  }

  @override
  Stream<ChatGroupInboxUpdate> streamGroupInbox({required String deviceId}) {
    final handler = streamGroupInboxHandler;
    if (handler != null) {
      return handler(deviceId: deviceId);
    }
    return const Stream<ChatGroupInboxUpdate>.empty();
  }

  @override
  Future<List<ChatContactPrefs>> fetchPrefs({
    required String deviceId,
    int limit = 200,
    String? afterPeerId,
  }) async {
    fetchPrefsCallCount += 1;
    final error = fetchPrefsError;
    if (error != null) throw error;
    return const <ChatContactPrefs>[];
  }

  @override
  Future<List<ChatContactPrefs>> fetchPrefsPaged({
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    fetchPrefsPagedCallCount += 1;
    final handler = fetchPrefsPagedHandler;
    if (handler != null) {
      return handler(
        deviceId: deviceId,
        batchSize: batchSize,
        maxPages: maxPages,
      );
    }
    final error = fetchPrefsError;
    if (error != null) throw error;
    return const <ChatContactPrefs>[];
  }

  @override
  Future<List<ChatGroupPrefs>> fetchGroupPrefs({
    required String deviceId,
    int limit = 200,
    String? afterGroupId,
  }) async {
    fetchGroupPrefsCallCount += 1;
    final error = fetchGroupPrefsError;
    if (error != null) throw error;
    return const <ChatGroupPrefs>[];
  }

  @override
  Future<List<ChatGroupPrefs>> fetchGroupPrefsPaged({
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    fetchGroupPrefsPagedCallCount += 1;
    final handler = fetchGroupPrefsPagedHandler;
    if (handler != null) {
      return handler(
        deviceId: deviceId,
        batchSize: batchSize,
        maxPages: maxPages,
      );
    }
    final error = fetchGroupPrefsError;
    if (error != null) throw error;
    return const <ChatGroupPrefs>[];
  }

  @override
  Future<void> setGroupPrefs({
    required String deviceId,
    required String groupId,
    bool? muted,
    bool? pinned,
  }) async {
    final handler = setGroupPrefsHandler;
    if (handler != null) {
      await handler(
        deviceId: deviceId,
        groupId: groupId,
        muted: muted,
        pinned: pinned,
      );
    }
  }

  @override
  Future<void> setPrefs({
    required String deviceId,
    required String peerId,
    bool? muted,
    bool? starred,
    bool? pinned,
  }) async {}

  @override
  Future<void> setHidden({
    required String deviceId,
    required String peerId,
    required bool hidden,
  }) async {}

  @override
  Future<void> setBlock({
    required String deviceId,
    required String peerId,
    required bool blocked,
    bool? hidden,
  }) async {}

  @override
  Future<ChatMessage> sendMessage({
    required ChatIdentity me,
    required ChatContact peer,
    required String plainText,
    int? expireAfterSeconds,
    bool sealedSender = true,
    String? senderHint,
    Uint8List? sessionKey,
    int? keyId,
    int? prevKeyId,
    String? senderDhPubB64,
    ChatDirectSendEnvelope? preparedEnvelope,
    V2ChatFlowVariant metricVariant = V2ChatFlowVariant.legacy,
  }) async {
    return ChatMessage(
      id: 'noop',
      senderId: me.id,
      recipientId: peer.id,
      senderPubKeyB64: me.publicKeyB64,
      nonceB64: '',
      boxB64: base64Encode(utf8.encode(plainText)),
      trustedLocalPlaintext: true,
    );
  }

  @override
  Future<void> markRead(String messageId, {String? deviceId}) async {}

  @override
  Stream<List<ChatMessage>> streamInbox({required String deviceId}) {
    streamInboxCallCount += 1;
    lastStreamInboxDeviceId = deviceId;
    final handler = streamInboxHandler;
    if (handler != null) {
      return handler(deviceId: deviceId);
    }
    return const Stream<List<ChatMessage>>.empty();
  }

  @override
  Future<void> ensureAccountChatReady() async {
    ensureAccountChatReadyCallCount += 1;
    final handler = ensureAccountChatReadyHandler;
    if (handler != null) {
      await handler();
    }
  }

  @override
  Stream<ChatTypingSignal> streamTypingSignals({required String deviceId}) {
    return const Stream<ChatTypingSignal>.empty();
  }
}

Future<dynamic> _pumpChatPage(
  WidgetTester tester, {
  required ChatService service,
  required VoidCallback onCritical,
  http.Client? officialHttpClient,
  http.Client? accountHttpClient,
  Future<Map<String, String>> Function(Iterable<String> groupIds)?
      loadGroupSeenForGroupsOverride,
  Future<String?> Function(String groupId)? loadGroupSeenForGroupOverride,
  Future<void> Function(String groupId, bool archived)?
      saveArchivedGroupStateOverride,
  Future<void> Function(String groupId, int unreadCount)?
      saveUnreadCountForGroupOverride,
  Future<void> Function(String peerId, int unreadCount)?
      saveUnreadCountForPeerOverride,
  Future<void> Function(Map<String, int> unread, Iterable<String> unreadKeys)?
      saveUnreadCountsForKeysOverride,
  Future<void> Function(String peerId, String messageId, bool pinned)?
      savePinnedMessageForPeerOverride,
  Future<void> Function(String messageId, bool recalled)?
      saveRecalledMessageStateOverride,
  Future<void> Function(String peerId, List<ChatMessage> messages)?
      saveMessagesForPeerOverride,
  Future<void> Function(String groupId, List<ChatGroupMessage> messages)?
      saveGroupMessagesForGroupOverride,
  Future<void> Function(List<ChatGroup> groups)? upsertGroupNamesOverride,
  Future<void> Function(Iterable<ChatContact> contacts)?
      saveContactsForPeersOverride,
  Future<void> Function(Iterable<String> peerIds)?
      removeContactsForPeersOverride,
  Future<bool> Function()? authenticateHiddenChatsOverride,
  Future<void> Function(bool enabled)? saveNotifyPreviewOverride,
  Future<void> Function(bool hasUnread)?
      saveServiceNotificationsHasUnreadOverride,
  Future<void> Function(bool hide)? saveHideServiceNotificationsThreadOverride,
  Future<void> Function(ChatMessage message)? forwardMessageOverride,
  Future<void> Function(String text)? copyMessageTextOverride,
  Future<void> Function(String text)? translateMessageOverride,
  Future<void> Function(String text, String? chatId, String? msgId)?
      addFavoriteItemQuickOverride,
  Future<void> Function(
    double lat,
    double lon,
    String? label,
    String? chatId,
    String? msgId,
  )? addFavoriteLocationQuickOverride,
  Future<void> Function()? openFavoritesPickerOverride,
  Future<void> Function()? openContactCardPickerOverride,
  Future<void> Function(ChatContact contact, Offset? globalPosition)?
      onChatLongPressOverride,
  Future<void> Function(ChatGroup group, Offset? globalPosition)?
      onGroupLongPressOverride,
  Future<void> Function(ChatContact contact)? onChatTileTapOverride,
  Future<void> Function()? onServiceNotificationsThreadTapOverride,
  Future<void> Function(ChatContact peer)? loadSwitchedPeerOfficialOverride,
  Future<void> Function(String officialId, String chatPeerId)?
      startServiceOfficialFollowOverride,
  Future<void> Function(OfficialAccountHandle account)?
      startOfficialWelcomeInjectionOverride,
  Future<void> Function(ChatGroupInboxUpdate update)?
      startLiveGroupInboxMergeOverride,
  Future<void> Function(String peerId, List<ChatMessage> messages)?
      startLiveDirectMessageSaveOverride,
  Future<void> Function(List<ChatMessage> messages)?
      startLiveDirectInboxCursorSaveOverride,
  Future<void> Function(String messageId)? startLiveDirectReadAckOverride,
  Future<void> Function(ChatContact contact)?
      startLiveDirectContactUpsertOverride,
  Future<void> Function(ChatContact contact)?
      startLiveDirectContactUnarchiveOverride,
  Future<void> Function(Map<String, int> unread, Iterable<String> unreadKeys)?
      startLiveDirectUnreadBatchSaveOverride,
  Future<void> Function(Map<String, int> unread, Iterable<String> unreadKeys)?
      startMarkAllChatsReadUnreadBatchSaveOverride,
  Future<void> Function(String? initialRecipient, int? initialAmountCents)?
      openPaymentsPageOverride,
  Future<void> Function(Map<String, String> drafts)? saveDraftsOverride,
  Future<void> Function()? loadBootstrapSystemThreadsSideStateOverride,
  Future<void> Function()? refreshBootstrapServiceNotificationsBadgeOverride,
  Future<void> Function(String peerId)? loadBootstrapInitialPeerResolveOverride,
  Future<void> Function()? loadBootstrapSideMetadataOverride,
  Future<void> Function(ChatContact peer)?
      loadBootstrapOfficialForCurrentPeerOverride,
  Future<void> Function()? loadBootstrapOfficialNotificationModesOverride,
  Future<void> Function()? loadBootstrapDirectPrefsSyncOverride,
  Future<void> Function()? loadBootstrapGroupPrefsSyncOverride,
  Future<void> Function()? loadBootstrapDevicesSummaryOverride,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ShamellChatPage(
        baseUrl: _baseUrl,
        runStartupTasks: false,
        officialHttpClient: officialHttpClient,
        accountHttpClient: accountHttpClient,
        serviceOverride: service,
        onCriticalChatSessionFailure: onCritical,
        loadGroupSeenForGroupsOverride: loadGroupSeenForGroupsOverride,
        loadGroupSeenForGroupOverride: loadGroupSeenForGroupOverride,
        saveArchivedGroupStateOverride: saveArchivedGroupStateOverride,
        saveUnreadCountForGroupOverride: saveUnreadCountForGroupOverride,
        saveUnreadCountForPeerOverride: saveUnreadCountForPeerOverride,
        saveUnreadCountsForKeysOverride: saveUnreadCountsForKeysOverride,
        savePinnedMessageForPeerOverride: savePinnedMessageForPeerOverride,
        saveRecalledMessageStateOverride: saveRecalledMessageStateOverride,
        saveMessagesForPeerOverride: saveMessagesForPeerOverride,
        saveGroupMessagesForGroupOverride: saveGroupMessagesForGroupOverride,
        upsertGroupNamesOverride: upsertGroupNamesOverride,
        saveContactsForPeersOverride: saveContactsForPeersOverride,
        removeContactsForPeersOverride: removeContactsForPeersOverride,
        authenticateHiddenChatsOverride: authenticateHiddenChatsOverride,
        saveNotifyPreviewOverride: saveNotifyPreviewOverride,
        saveServiceNotificationsHasUnreadOverride:
            saveServiceNotificationsHasUnreadOverride,
        saveHideServiceNotificationsThreadOverride:
            saveHideServiceNotificationsThreadOverride,
        forwardMessageOverride: forwardMessageOverride,
        copyMessageTextOverride: copyMessageTextOverride,
        translateMessageOverride: translateMessageOverride,
        addFavoriteItemQuickOverride: addFavoriteItemQuickOverride,
        addFavoriteLocationQuickOverride: addFavoriteLocationQuickOverride,
        openFavoritesPickerOverride: openFavoritesPickerOverride,
        openContactCardPickerOverride: openContactCardPickerOverride,
        onChatLongPressOverride: onChatLongPressOverride,
        onGroupLongPressOverride: onGroupLongPressOverride,
        onChatTileTapOverride: onChatTileTapOverride,
        onServiceNotificationsThreadTapOverride:
            onServiceNotificationsThreadTapOverride,
        loadSwitchedPeerOfficialOverride: loadSwitchedPeerOfficialOverride,
        startServiceOfficialFollowOverride: startServiceOfficialFollowOverride,
        startOfficialWelcomeInjectionOverride:
            startOfficialWelcomeInjectionOverride,
        startLiveGroupInboxMergeOverride: startLiveGroupInboxMergeOverride,
        startLiveDirectMessageSaveOverride: startLiveDirectMessageSaveOverride,
        startLiveDirectInboxCursorSaveOverride:
            startLiveDirectInboxCursorSaveOverride,
        startLiveDirectReadAckOverride: startLiveDirectReadAckOverride,
        startLiveDirectContactUpsertOverride:
            startLiveDirectContactUpsertOverride,
        startLiveDirectContactUnarchiveOverride:
            startLiveDirectContactUnarchiveOverride,
        startLiveDirectUnreadBatchSaveOverride:
            startLiveDirectUnreadBatchSaveOverride,
        startMarkAllChatsReadUnreadBatchSaveOverride:
            startMarkAllChatsReadUnreadBatchSaveOverride,
        openPaymentsPageOverride: openPaymentsPageOverride,
        saveDraftsOverride: saveDraftsOverride,
        loadBootstrapSystemThreadsSideStateOverride:
            loadBootstrapSystemThreadsSideStateOverride,
        refreshBootstrapServiceNotificationsBadgeOverride:
            refreshBootstrapServiceNotificationsBadgeOverride,
        loadBootstrapInitialPeerResolveOverride:
            loadBootstrapInitialPeerResolveOverride,
        loadBootstrapSideMetadataOverride: loadBootstrapSideMetadataOverride,
        loadBootstrapOfficialForCurrentPeerOverride:
            loadBootstrapOfficialForCurrentPeerOverride,
        loadBootstrapOfficialNotificationModesOverride:
            loadBootstrapOfficialNotificationModesOverride,
        loadBootstrapDirectPrefsSyncOverride:
            loadBootstrapDirectPrefsSyncOverride,
        loadBootstrapGroupPrefsSyncOverride:
            loadBootstrapGroupPrefsSyncOverride,
        loadBootstrapDevicesSummaryOverride:
            loadBootstrapDevicesSummaryOverride,
      ),
    ),
  );
  await tester.pump();
  final dynamic state = tester.state(find.byType(ShamellChatPage));
  state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
  await tester.pump();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  Completer<void>? delayedSecureRead;
  String? delayedSecureReadKeyContains;
  const criticalChatError = ChatHttpException(
    op: 'chat',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
            return null;
          case 'read':
            if (delayedSecureRead != null &&
                delayedSecureReadKeyContains != null &&
                key.contains(delayedSecureReadKeyContains!) &&
                !delayedSecureRead!.isCompleted) {
              await delayedSecureRead!.future;
            }
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    delayedSecureRead = null;
    delayedSecureReadKeyContains = null;
    await clearSessionCookie();
  });

  testWidgets('ShamellChatPage reauths on critical inbox pull failure',
      (tester) async {
    final service =
        _FakeChatBootstrapService(fetchInboxError: criticalChatError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugPullInbox();
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage bootstrap refreshes registered chat identity before inbox and live sockets',
      (tester) async {
    final store = ChatLocalStore();
    final initial = _buildMe();
    final rotated = ChatIdentity(
      id: 'device_rotated',
      publicKeyB64: _curveKeyB64(141),
      privateKeyB64: _curveKeyB64(177),
      fingerprint: 'fp-rotated',
    );
    await store.saveIdentity(initial, baseUrlOverride: _baseUrl);

    final service = _FakeChatBootstrapService(
      ensureAccountChatReadyHandler: () async {
        await store.saveIdentity(rotated, baseUrlOverride: _baseUrl);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          serviceOverride: service,
          onCriticalChatSessionFailure: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    final bootstrapState =
        Map<String, Object?>.from(state.debugBootstrapState());

    expect(service.ensureAccountChatReadyCallCount, 1);
    expect(bootstrapState['meId'], rotated.id);
  });

  testWidgets(
      'ShamellChatPage starts live direct inbox cursor persistence through the dedicated detached seam',
      (tester) async {
    final savedMessageIds = <List<String>>[];
    final saveCompleter = Completer<void>();
    final inboxController = StreamController<List<ChatMessage>>();
    addTearDown(inboxController.close);
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(
        streamInboxHandler: ({required String deviceId}) {
          return inboxController.stream;
        },
      ),
      onCritical: () {},
      startLiveDirectInboxCursorSaveOverride: (messages) async {
        savedMessageIds.add(
          messages.map((message) => message.id).toList(growable: false),
        );
        await saveCompleter.future;
      },
    );

    state.debugListenWs();
    await tester.pump();

    inboxController.add(<ChatMessage>[
      _buildDirectMessage(
        id: 'msg-stream-direct-001',
        text: 'streamed direct message',
        createdAt: DateTime.utc(2026, 3, 20, 10, 0, 1),
      ),
    ]);
    await tester.pump();

    expect(savedMessageIds, <List<String>>[
      <String>['msg-stream-direct-001'],
    ]);

    saveCompleter.complete();
  });

  testWidgets(
      'ShamellChatPage uses the persisted direct inbox cursor for catch-up',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveDirectInboxCursor(
      '2026-03-18T10:00:00Z',
      sinceId: 'msg-002',
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      fetchInboxPagedHandler: ({
        required String deviceId,
        String? sinceIso,
        String? sinceId,
        int batchSize = 200,
        int maxPages = 25,
        int? retainLatestCount,
      }) async {
        return <ChatMessage>[
          ChatMessage(
            id: 'msg-003',
            senderId: 'peer_1',
            recipientId: _meId,
            senderPubKeyB64: '',
            nonceB64: 'AQ==',
            boxB64: 'Ag==',
            sealedSender: true,
            createdAt: DateTime.utc(2026, 3, 18, 10, 0, 1),
          ),
        ];
      },
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugPullInbox();
    await tester.pump();

    expect(service.lastFetchInboxPagedSinceIso, '2026-03-18T10:00:00Z');
    expect(service.lastFetchInboxPagedSinceId, 'msg-002');
    final nextCursor =
        await store.loadDirectInboxCursor(baseUrlOverride: _baseUrl);
    expect(nextCursor?.sinceIso, '2026-03-18T10:00:01.000Z');
    expect(nextCursor?.sinceId, 'msg-003');
  });

  testWidgets(
      'ShamellChatPage backfills direct inbox via paged sync when no cursor exists',
      (tester) async {
    final service = _FakeChatBootstrapService(
      fetchInboxPagedHandler: ({
        required String deviceId,
        String? sinceIso,
        String? sinceId,
        int batchSize = 200,
        int maxPages = 25,
        int? retainLatestCount,
      }) async {
        return <ChatMessage>[
          ChatMessage(
            id: 'msg-001',
            senderId: 'peer_1',
            recipientId: _meId,
            senderPubKeyB64: '',
            nonceB64: 'AQ==',
            boxB64: 'Ag==',
            sealedSender: true,
            createdAt: DateTime.utc(2026, 3, 18, 10, 0, 0),
          ),
        ];
      },
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugPullInbox();
    await tester.pump();

    expect(service.fetchInboxPagedCallCount, 1);
    expect(service.lastFetchInboxPagedSinceIso, isNull);
    expect(service.lastFetchInboxPagedSinceId, isNull);
  });

  testWidgets(
      'ShamellChatPage loads older direct thread history on demand after startup',
      (tester) async {
    List<ChatMessage> makeMessages(int start, int end) {
      return List<ChatMessage>.generate(end - start + 1, (index) {
        final number = start + index;
        return ChatMessage(
          id: 'msg-${number.toString().padLeft(3, '0')}',
          senderId: number.isEven ? _peerId : _meId,
          recipientId: number.isEven ? _meId : _peerId,
          senderPubKeyB64: '',
          nonceB64: 'AQ==',
          boxB64: 'Ag==',
          sealedSender: true,
          createdAt: DateTime.utc(2026, 3, 18, 10, 0, number),
        );
      });
    }

    final service = _FakeChatBootstrapService(
      fetchThreadHistoryHandler: ({
        String? beforeCreatedAt,
        String? beforeId,
      }) {
        if (beforeId == 'msg-154') {
          return makeMessages(1, 153);
        }
        return const <ChatMessage>[];
      },
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: makeMessages(154, 353),
    );
    await tester.pump();

    expect(state.debugHasOlderThreadMessages(), isTrue);

    await state.debugLoadOlderThreadMessages();
    await tester.pump();

    final stored = await ChatLocalStore().loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );

    expect(service.fetchThreadHistoryCallCount, 1);
    expect(service.fetchThreadHistoryBeforeIds, <String?>['msg-154']);
    expect(stored, hasLength(353));
    expect(stored.first.id, 'msg-001');
    expect(stored.last.id, 'msg-353');
    expect(stored.any((m) => m.senderId == _meId), isTrue);
    expect(stored.any((m) => m.senderId == _peerId), isTrue);
    expect(state.debugHasOlderThreadMessages(), isFalse);
  });

  testWidgets(
      'ShamellChatPage restores primary local thread state before delayed friend annotations finish',
      (tester) async {
    final store = ChatLocalStore();
    final me = _buildMe();
    final peer = _buildPeer();
    final cached = ChatMessage(
      id: 'msg-001',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: '',
      nonceB64: 'AQ==',
      boxB64: base64Encode(utf8.encode('hello')),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 18, 10, 0, 0),
    );
    await store.saveIdentity(me, baseUrlOverride: _baseUrl);
    await store.savePeer(peer, baseUrlOverride: _baseUrl);
    await store.saveContacts(<ChatContact>[peer], baseUrlOverride: _baseUrl);
    await store.setActivePeer(_peerId, baseUrlOverride: _baseUrl);
    await store.saveMessages(
      _peerId,
      <ChatMessage>[cached],
      baseUrlOverride: _baseUrl,
    );
    await saveFriendAliases(
      <String, String>{_peerId: 'Alias Peer'},
      baseUrlOverride: _baseUrl,
    );

    delayedSecureRead = Completer<void>();
    delayedSecureReadKeyContains = 'friends.aliases.v2.';

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          runStartupTasks: false,
          serviceOverride: _FakeChatBootstrapService(),
          onCriticalChatSessionFailure: () {},
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugRestoreBootstrapState();
    await tester.pump();

    expect(state.debugBootstrapState(), containsPair('meId', _meId));
    expect(state.debugBootstrapState(), containsPair('contactCount', 1));
    expect(state.debugBootstrapState(), containsPair('cachedMessageCount', 1));
    expect(state.debugBootstrapState(), containsPair('friendAliasCount', 0));

    delayedSecureRead!.complete();
    await tester.pump();
    await tester.pump();

    expect(state.debugBootstrapState(), containsPair('friendAliasCount', 1));
  });

  testWidgets(
      'ShamellChatPage starts bootstrap side metadata through the dedicated detached seam',
      (tester) async {
    final loadCompleter = Completer<void>();
    var loadCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapSideMetadataOverride: () async {
        loadCount += 1;
        await loadCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugRestoreBootstrapState();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isTrue);
    expect(loadCount, 1);

    loadCompleter.complete();
    await tester.pump();
  });

  testWidgets('ShamellChatPage loads bootstrap side metadata on demand',
      (tester) async {
    final store = ChatLocalStore();
    await saveFriendAliases(
      <String, String>{_peerId: 'Alias Peer'},
      baseUrlOverride: _baseUrl,
    );
    await saveFriendTags(
      <String, String>{_peerId: 'vip'},
      baseUrlOverride: _baseUrl,
    );
    await saveCloseFriendIds(
      <String>{_peerId},
      baseUrlOverride: _baseUrl,
    );
    await store.savePinnedMessages(
      <String, Set<String>>{
        _peerId: <String>{'msg-1'},
      },
      baseUrlOverride: _baseUrl,
    );
    await store.savePinnedChatOrder(
      <String>[_peerId],
      baseUrlOverride: _baseUrl,
    );
    await store.saveArchivedGroups(
      <String>{_groupId},
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugLoadBootstrapSideMetadata();
    await tester.pump();

    expect(state.debugBootstrapState(), containsPair('friendAliasCount', 1));
    expect(state.debugBootstrapState(), containsPair('friendTagCount', 1));
    expect(state.debugBootstrapState(), containsPair('closeFriendCount', 1));
    expect(state.debugIsMessagePinnedForPeer(_peerId, 'msg-1'), isTrue);
    expect(state.debugPinnedChatOrderSnapshot(), <String>[_peerId]);
    expect(state.debugArchivedGroupsSnapshot(), <String>{_groupId});
  });

  test('ChatLocalStore saveChatThemeForPeer updates only the targeted peer',
      () async {
    final store = ChatLocalStore();

    await store.saveChatThemes(
      <String, String>{_peerId: 'dark', 'peer-2': 'green'},
      baseUrlOverride: _baseUrl,
    );

    await store.saveChatThemeForPeer(
      _peerId,
      'default',
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadChatThemes(baseUrlOverride: _baseUrl),
      <String, String>{'peer-2': 'green'},
    );
  });

  test('ChatLocalStore saveChatThemeForGroup updates only the targeted group',
      () async {
    final store = ChatLocalStore();

    await store.saveChatThemes(
      <String, String>{
        'grp:$_groupId': 'dark',
        'grp:group-2': 'green',
        _peerId: 'light',
      },
      baseUrlOverride: _baseUrl,
    );

    await store.saveChatThemeForGroup(
      _groupId,
      'default',
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadChatThemes(baseUrlOverride: _baseUrl),
      <String, String>{'grp:group-2': 'green', _peerId: 'light'},
    );
  });

  test('ChatLocalStore saveArchivedGroupState updates only the targeted group',
      () async {
    final store = ChatLocalStore();

    await store.saveArchivedGroups(
      <String>{_groupId, 'group-2'},
      baseUrlOverride: _baseUrl,
    );

    await store.saveArchivedGroupState(
      _groupId,
      false,
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadArchivedGroups(baseUrlOverride: _baseUrl),
      <String>{'group-2'},
    );
  });

  test('ChatLocalStore saveUnreadCountForGroup updates only the targeted group',
      () async {
    final store = ChatLocalStore();

    await store.saveUnread(
      <String, int>{
        'grp:$_groupId': 3,
        'grp:group-2': 5,
        _peerId: 7,
      },
      baseUrlOverride: _baseUrl,
    );

    await store.saveUnreadCountForGroup(
      _groupId,
      0,
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadUnread(baseUrlOverride: _baseUrl),
      <String, int>{'grp:group-2': 5, _peerId: 7},
    );
  });

  test('ChatLocalStore loadUnreadCountForGroup returns only the targeted group',
      () async {
    final store = ChatLocalStore();

    await store.saveUnread(
      <String, int>{
        'grp:$_groupId': 3,
        'grp:group-2': 5,
        _peerId: 7,
      },
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadUnreadCountForGroup(
        _groupId,
        baseUrlOverride: _baseUrl,
      ),
      3,
    );
  });

  test('ChatLocalStore saveUnreadCountForPeer updates only the targeted peer',
      () async {
    final store = ChatLocalStore();

    await store.saveUnread(
      <String, int>{
        _peerId: 7,
        'peer-2': 5,
        'grp:$_groupId': 3,
      },
      baseUrlOverride: _baseUrl,
    );

    await store.saveUnreadCountForPeer(
      _peerId,
      0,
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadUnread(baseUrlOverride: _baseUrl),
      <String, int>{'peer-2': 5, 'grp:$_groupId': 3},
    );
  });

  test('ChatLocalStore loadUnreadCountForPeer returns only the targeted peer',
      () async {
    final store = ChatLocalStore();

    await store.saveUnread(
      <String, int>{
        _peerId: 7,
        'peer-2': 5,
        'grp:$_groupId': 3,
      },
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadUnreadCountForPeer(
        _peerId,
        baseUrlOverride: _baseUrl,
      ),
      7,
    );
  });

  test('ChatLocalStore saveUnreadCountsForKeys updates only targeted keys',
      () async {
    final store = ChatLocalStore();

    await store.saveUnread(
      <String, int>{
        _peerId: 7,
        'peer-2': 5,
        'grp:$_groupId': 3,
        'grp:group-2': 4,
      },
      baseUrlOverride: _baseUrl,
    );

    await store.saveUnreadCountsForKeys(
      <String, int>{
        _peerId: 0,
        'peer-2': 6,
        'grp:$_groupId': 0,
        'grp:group-2': 4,
      },
      <String>[_peerId, 'peer-2', 'grp:$_groupId'],
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadUnread(baseUrlOverride: _baseUrl),
      <String, int>{
        'peer-2': 6,
        'grp:group-2': 4,
      },
    );
  });

  test('ChatLocalStore saveGroupSeenForGroup updates only the targeted group',
      () async {
    final store = ChatLocalStore();

    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    await store.saveGroupSeenForGroup(
      _groupId,
      DateTime.parse('2026-03-19T00:00:00Z'),
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadGroupSeen(baseUrlOverride: _baseUrl),
      <String, String>{
        _groupId: '2026-03-19T00:00:00.000Z',
        'group-2': '2026-03-17T00:00:00Z',
      },
    );
  });

  test('ChatLocalStore loadGroupSeenForGroup returns only the targeted value',
      () async {
    final store = ChatLocalStore();

    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-19T00:00:00.000Z',
        'group-2': '2026-03-17T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadGroupSeenForGroup(
        _groupId,
        baseUrlOverride: _baseUrl,
      ),
      '2026-03-19T00:00:00.000Z',
    );
  });

  test('ChatLocalStore loadGroupSeenForGroups returns only targeted values',
      () async {
    final store = ChatLocalStore();

    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-19T00:00:00.000Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadGroupSeenForGroups(
        <String>[_groupId, 'group-3'],
        baseUrlOverride: _baseUrl,
      ),
      <String, String>{
        _groupId: '2026-03-19T00:00:00.000Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
    );
  });

  test('ChatLocalStore savePinnedMessageForPeer updates only the targeted peer',
      () async {
    final store = ChatLocalStore();

    await store.savePinnedMessages(
      <String, Set<String>>{
        _peerId: <String>{'msg-1'},
        'peer-2': <String>{'msg-2'},
      },
      baseUrlOverride: _baseUrl,
    );

    await store.savePinnedMessageForPeer(
      _peerId,
      'msg-3',
      true,
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadPinnedMessages(baseUrlOverride: _baseUrl),
      <String, Set<String>>{
        _peerId: <String>{'msg-1', 'msg-3'},
        'peer-2': <String>{'msg-2'},
      },
    );
  });

  test('ChatLocalStore saveRecalledMessageState updates only the targeted id',
      () async {
    final store = ChatLocalStore();

    await store.saveRecalledMessageIds(
      <String>{'msg-1', 'msg-2'},
      baseUrlOverride: _baseUrl,
    );

    await store.saveRecalledMessageState(
      'msg-1',
      false,
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadRecalledMessageIds(baseUrlOverride: _baseUrl),
      <String>{'msg-2'},
    );
  });

  test(
      'ChatLocalStore removePinnedMessageFromAllPeers updates only affected peers',
      () async {
    final store = ChatLocalStore();

    await store.savePinnedMessages(
      <String, Set<String>>{
        _peerId: <String>{'msg-1', 'msg-2'},
        'peer-2': <String>{'msg-1'},
        'peer-3': <String>{'msg-3'},
      },
      baseUrlOverride: _baseUrl,
    );

    await store.removePinnedMessageFromAllPeers(
      'msg-1',
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadPinnedMessages(baseUrlOverride: _baseUrl),
      <String, Set<String>>{
        _peerId: <String>{'msg-2'},
        'peer-3': <String>{'msg-3'},
      },
    );
  });

  testWidgets(
      'ShamellChatPage waits for chat theme persistence before committing local theme state',
      (tester) async {
    final delayedThemeSave = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          runStartupTasks: false,
          serviceOverride: _FakeChatBootstrapService(),
          onCriticalChatSessionFailure: () {},
          saveChatThemeForPeerOverride: (peerId, themeKey) async {
            await delayedThemeSave.future;
            await ChatLocalStore().saveChatThemeForPeer(
              peerId,
              themeKey,
              baseUrlOverride: _baseUrl,
            );
          },
        ),
      ),
    );
    await tester.pump();
    final dynamic state2 = tester.state(find.byType(ShamellChatPage));
    state2.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    final pending = state2.debugSetChatThemeForPeer(_peerId, 'dark');
    await tester.pump();

    expect(state2.debugChatThemeForPeer(_peerId), 'default');

    delayedThemeSave.complete();
    await pending;
    await tester.pump();

    expect(state2.debugChatThemeForPeer(_peerId), 'dark');
    expect(
      await ChatLocalStore().loadChatThemes(baseUrlOverride: _baseUrl),
      <String, String>{_peerId: 'dark'},
    );
  });

  testWidgets(
      'ShamellChatPage persists a single archived group without rewriting unrelated ids',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveArchivedGroups(
      <String>{_groupId, 'group-2'},
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetGroupArchived(_groupId, false);

    expect(
      await store.loadArchivedGroups(baseUrlOverride: _baseUrl),
      <String>{'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage waits for group archive toggle persistence before returning',
      (tester) async {
    final archivedCalls = <({String groupId, bool archived})>[];
    final archivePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
        await archivePersistCompleter.future;
      },
    );

    var completed = false;
    final toggleFuture = state.debugToggleGroupArchived(_buildGroup());
    unawaited(toggleFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(
      archivedCalls,
      <({String groupId, bool archived})>[
        (groupId: _groupId, archived: true),
      ],
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{_groupId},
    );

    archivePersistCompleter.complete();
    await toggleFuture;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for group archive persistence before closing the group more sheet',
      (tester) async {
    final archivePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveArchivedGroupStateOverride: (groupId, archived) async {
        await archivePersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowGroupMoreSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pump();

    expect(find.text('Archive'), findsOneWidget);
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{_groupId},
    );

    archivePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Archive'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group mute persistence before closing the group more sheet',
      (tester) async {
    final mutePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(
        setGroupPrefsHandler: ({
          required deviceId,
          required groupId,
          bool? muted,
          bool? pinned,
        }) async {
          await mutePersistCompleter.future;
        },
      ),
      onCritical: () {},
    );

    final openSheetFuture = state.debugShowGroupMoreSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('Mute'), findsOneWidget);

    await tester.tap(find.text('Mute'));
    await tester.pump();

    expect(find.text('Mute'), findsOneWidget);

    mutePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Mute'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group pin persistence before closing the group more sheet',
      (tester) async {
    final pinPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(
        setGroupPrefsHandler: ({
          required deviceId,
          required groupId,
          bool? muted,
          bool? pinned,
        }) async {
          await pinPersistCompleter.future;
        },
      ),
      onCritical: () {},
    );

    final openSheetFuture = state.debugShowGroupMoreSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('Pin'), findsOneWidget);

    await tester.tap(find.text('Pin'));
    await tester.pump();

    expect(find.text('Pin'), findsOneWidget);

    pinPersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Pin'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group delete persistence before closing the group more sheet',
      (tester) async {
    final deletePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        await deletePersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowGroupMoreSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(find.text('Delete'), findsOneWidget);

    deletePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Delete'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct archive persistence before closing the chat more sheet',
      (tester) async {
    final archivePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveContactsForPeersOverride: (contacts) async {
        await archivePersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatMoreSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pump();

    expect(find.text('Archive'), findsOneWidget);

    archivePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Archive'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct mute persistence before closing the chat more sheet',
      (tester) async {
    final mutePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveContactsForPeersOverride: (contacts) async {
        await mutePersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatMoreSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('Mute'), findsOneWidget);

    await tester.tap(find.text('Mute'));
    await tester.pump();

    expect(find.text('Mute'), findsOneWidget);

    mutePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Mute'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct pin persistence before closing the chat more sheet',
      (tester) async {
    final pinPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveContactsForPeersOverride: (contacts) async {
        await pinPersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatMoreSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('Pin'), findsOneWidget);

    await tester.tap(find.text('Pin'));
    await tester.pump();

    expect(find.text('Pin'), findsOneWidget);

    pinPersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Pin'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct delete persistence before closing the chat more sheet',
      (tester) async {
    final deletePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      removeContactsForPeersOverride: (peerIds) async {
        await deletePersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatMoreSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(find.text('Delete'), findsOneWidget);

    deletePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Delete'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct delete persistence before closing the chat long-press sheet',
      (tester) async {
    final deletePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      removeContactsForPeersOverride: (peerIds) async {
        await deletePersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatLongPressSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('Delete chat'), findsOneWidget);

    await tester.tap(find.text('Delete chat'));
    await tester.pump();

    expect(find.text('Delete chat'), findsOneWidget);

    deletePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Delete chat'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group unread persistence before closing the group long-press sheet',
      (tester) async {
    final unreadPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        await unreadPersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowGroupLongPressSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('Mark as unread'), findsOneWidget);

    await tester.tap(find.text('Mark as unread'));
    await tester.pump();

    expect(find.text('Mark as unread'), findsOneWidget);

    unreadPersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Mark as unread'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group pin persistence before closing the group long-press sheet',
      (tester) async {
    final pinPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(
        setGroupPrefsHandler: ({
          required deviceId,
          required groupId,
          bool? muted,
          bool? pinned,
        }) async {
          await pinPersistCompleter.future;
        },
      ),
      onCritical: () {},
    );

    final openSheetFuture = state.debugShowGroupLongPressSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('Pin chat'), findsOneWidget);

    await tester.tap(find.text('Pin chat'));
    await tester.pump();

    expect(find.text('Pin chat'), findsOneWidget);

    pinPersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Pin chat'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group delete persistence before closing the group long-press sheet',
      (tester) async {
    final deletePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        await deletePersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowGroupLongPressSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('Delete chat'), findsOneWidget);

    await tester.tap(find.text('Delete chat'));
    await tester.pump();

    expect(find.text('Delete chat'), findsOneWidget);

    deletePersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Delete chat'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage opens the group more sheet from the group long-press sheet transition',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    final openSheetFuture = state.debugShowGroupLongPressSheet(_buildGroup());
    await tester.pumpAndSettle();

    expect(find.text('More…'), findsOneWidget);

    await tester.tap(find.text('More…'));
    await tester.pump();

    expect(find.text('Archive'), findsNothing);

    await openSheetFuture;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets(
      'ShamellChatPage opens the chat more sheet from the chat long-press sheet transition',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    final openSheetFuture = state.debugShowChatLongPressSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('More…'), findsOneWidget);

    await tester.tap(find.text('More…'));
    await tester.pump();

    expect(find.text('Archive'), findsNothing);

    await openSheetFuture;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets(
      'ShamellChatPage waits for chat-tile long-press entry before returning',
      (tester) async {
    final longPressCompleter = Completer<void>();
    final calls = <({String contactId, Offset? globalPosition})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      onChatLongPressOverride: (contact, globalPosition) async {
        calls.add((contactId: contact.id, globalPosition: globalPosition));
        await longPressCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugHandleChatTileLongPress(
      _buildPeer(),
      globalPosition: const Offset(24, 48),
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(calls, hasLength(1));
    expect(calls.single.contactId, _peerId);
    expect(calls.single.globalPosition, const Offset(24, 48));

    longPressCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for group-tile long-press entry before returning',
      (tester) async {
    final longPressCompleter = Completer<void>();
    final calls = <({String groupId, Offset? globalPosition})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      onGroupLongPressOverride: (group, globalPosition) async {
        calls.add((groupId: group.id, globalPosition: globalPosition));
        await longPressCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugHandleGroupTileLongPress(
      _buildGroup(),
      globalPosition: const Offset(32, 64),
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(calls, hasLength(1));
    expect(calls.single.groupId, _groupId);
    expect(calls.single.globalPosition, const Offset(32, 64));

    longPressCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets('ShamellChatPage waits for chat-tile tap entry before returning',
      (tester) async {
    final tapCompleter = Completer<void>();
    final tappedPeers = <String>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      onChatTileTapOverride: (contact) async {
        tappedPeers.add(contact.id);
        await tapCompleter.future;
      },
    );
    const otherPeerId = 'peer-2';
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
    );

    var completed = false;
    final pending = state.debugHandleChatTileTap(otherPeer);
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(tappedPeers, <String>[otherPeerId]);
    expect(
      state.debugBootstrapState(),
      containsPair('peerId', _peerId),
    );

    tapCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for direct pin persistence before closing the chat long-press sheet',
      (tester) async {
    final pinPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveContactsForPeersOverride: (contacts) async {
        await pinPersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatLongPressSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('Pin chat'), findsOneWidget);

    await tester.tap(find.text('Pin chat'));
    await tester.pump();

    expect(find.text('Pin chat'), findsOneWidget);

    pinPersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Pin chat'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct unread persistence before closing the chat long-press sheet',
      (tester) async {
    final unreadPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForPeerOverride: (peerId, unreadCount) async {
        await unreadPersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatLongPressSheet(_buildPeer());
    await tester.pumpAndSettle();

    expect(find.text('Mark as unread'), findsOneWidget);

    await tester.tap(find.text('Mark as unread'));
    await tester.pump();

    expect(find.text('Mark as unread'), findsOneWidget);

    unreadPersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Mark as unread'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct unread persistence before dismissing the swipe action',
      (tester) async {
    final unreadPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForPeerOverride: (peerId, unreadCount) async {
        await unreadPersistCompleter.future;
      },
    );

    state.debugShowChatsList(
        me: _buildMe(), contacts: <ChatContact>[_buildPeer()]);
    await tester.pump();

    final chatTile = find.byKey(const ValueKey<String>('chat_peer_1'));
    expect(chatTile, findsOneWidget);

    await tester.drag(chatTile, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Unread'), findsOneWidget);

    await tester.tap(find.text('Unread'));
    await tester.pump();

    expect(find.text('Read'), findsOneWidget);

    unreadPersistCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for system-thread unread persistence before dismissing the swipe action',
      (tester) async {
    final unreadPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveServiceNotificationsHasUnreadOverride: (hasUnread) async {
        await unreadPersistCompleter.future;
      },
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: false,
        channels: false,
        serviceNotifications: true,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSetServiceNotificationsThreadState(hasUnread: true);
    state.debugShowChatsList(
        me: _buildMe(), contacts: <ChatContact>[_buildPeer()]);
    await tester.pump();

    final serviceTile =
        find.byKey(const ValueKey<String>('sys_service_notifications'));
    expect(serviceTile, findsOneWidget);

    await tester.drag(serviceTile, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsOneWidget);

    await tester.tap(find.text('Read'));
    await tester.pump();

    expect(find.text('Unread'), findsOneWidget);

    unreadPersistCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Unread'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for system-thread tap entry before returning',
      (tester) async {
    final tapCompleter = Completer<void>();
    var openCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      onServiceNotificationsThreadTapOverride: () async {
        openCount += 1;
        await tapCompleter.future;
      },
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: false,
        channels: false,
        serviceNotifications: true,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSetServiceNotificationsThreadState(hasUnread: true);
    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[_buildPeer()],
    );
    await tester.pump();

    var completed = false;
    final pending = state.debugHandleServiceNotificationsThreadTap();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(openCount, 1);
    expect(
      state.debugBootstrapState(),
      containsPair('peerId', null),
    );

    tapCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for bootstrap system-thread side-state load before returning',
      (tester) async {
    final loadCompleter = Completer<void>();
    var loadCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapSystemThreadsSideStateOverride: () async {
        loadCount += 1;
        await loadCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugLoadBootstrapSystemThreadsSideState();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(loadCount, 1);

    loadCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage restores cached system-thread side state during bootstrap load',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveServiceNotificationsHasUnread(
      true,
      baseUrlOverride: _baseUrl,
    );
    await store.saveHideServiceNotificationsThread(
      true,
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      accountHttpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'messages': <Map<String, Object?>>[
              <String, Object?>{'id': 'msg-1'},
            ],
          }),
          200,
        ),
      ),
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: false,
        channels: false,
        serviceNotifications: true,
        paymentsPhoneTargets: false,
      ),
    );

    await state.debugLoadBootstrapSystemThreadsSideState();
    await tester.pump();

    expect(
      state.debugServiceNotificationsThreadState(),
      containsPair('hasUnread', true),
    );
    expect(
      state.debugServiceNotificationsThreadState(),
      containsPair('hideThread', true),
    );
  });

  testWidgets(
      'ShamellChatPage starts bootstrap service-notifications badge refresh through the dedicated detached seam',
      (tester) async {
    final refreshCompleter = Completer<void>();
    var refreshCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      refreshBootstrapServiceNotificationsBadgeOverride: () async {
        refreshCount += 1;
        await refreshCompleter.future;
      },
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: false,
        channels: false,
        serviceNotifications: true,
        paymentsPhoneTargets: false,
      ),
    );

    var completed = false;
    final pending = state.debugLoadBootstrapSystemThreadsSideState();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isTrue);
    expect(refreshCount, 1);

    refreshCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage refreshes the cached system-thread badge in the background during bootstrap load',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      accountHttpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'messages': <Map<String, Object?>>[
              <String, Object?>{'id': 'msg-1'},
            ],
          }),
          200,
        ),
      ),
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: false,
        channels: false,
        serviceNotifications: true,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSetServiceNotificationsThreadState(hasUnread: false);

    await state.debugLoadBootstrapSystemThreadsSideState();
    await tester.pump();
    await tester.pump();

    expect(
      state.debugServiceNotificationsThreadState(),
      containsPair('hasUnread', true),
    );
  });

  testWidgets(
      'ShamellChatPage waits for bootstrap initial-peer resolve before returning',
      (tester) async {
    final loadCompleter = Completer<void>();
    String? loadedPeerId;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapInitialPeerResolveOverride: (peerId) async {
        loadedPeerId = peerId;
        await loadCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugLoadBootstrapInitialPeerResolve(_peerId);
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(loadedPeerId, _peerId);

    loadCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage resolves the bootstrap initial peer through the targeted peer contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      resolveDeviceHandler: (peerId) async {
        final publicKeyB64 = _curveKeyB64(77);
        return ChatContact(
          id: peerId,
          publicKeyB64: publicKeyB64,
          fingerprint: fingerprintForKey(publicKeyB64),
          name: 'Resolved Peer',
        );
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugLoadBootstrapInitialPeerResolve(_peerId);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final resolvedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(resolvedPeer.name, 'Resolved Peer');
    expect(resolvedPeer.publicKeyB64, _curveKeyB64(77));
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.publicKeyB64, _curveKeyB64(49));
    expect(
      state.debugBootstrapState(),
      containsPair('peerId', _peerId),
    );
  });

  testWidgets(
      'ShamellChatPage waits for bootstrap current-peer official load before returning',
      (tester) async {
    final loadCompleter = Completer<void>();
    String? loadedPeerId;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapOfficialForCurrentPeerOverride: (peer) async {
        loadedPeerId = peer.id;
        await loadCompleter.future;
      },
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: true,
        channels: false,
        serviceNotifications: false,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    var completed = false;
    final pending = state.debugLoadBootstrapOfficialForCurrentPeer();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(loadedPeerId, _peerId);

    loadCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage starts independent bootstrap side loads in parallel after refresh',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveIdentity(_buildMe(), baseUrlOverride: _baseUrl);

    final directStarted = Completer<void>();
    final directRelease = Completer<void>();
    final groupStarted = Completer<void>();
    final groupRelease = Completer<void>();
    var systemStarted = false;
    var devicesStarted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          serviceOverride: _FakeChatBootstrapService(),
          onCriticalChatSessionFailure: () {},
          ensurePushTokenOverride: () async {},
          loadBootstrapDirectPrefsSyncOverride: () async {
            if (!directStarted.isCompleted) {
              directStarted.complete();
            }
            await directRelease.future;
          },
          loadBootstrapGroupPrefsSyncOverride: () async {
            if (!groupStarted.isCompleted) {
              groupStarted.complete();
            }
            await groupRelease.future;
          },
          loadBootstrapSystemThreadsSideStateOverride: () async {
            systemStarted = true;
          },
          loadBootstrapDevicesSummaryOverride: () async {
            devicesStarted = true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(directStarted.isCompleted, isTrue);
    expect(groupStarted.isCompleted, isTrue);
    expect(systemStarted, isTrue);
    expect(devicesStarted, isTrue);

    directRelease.complete();
    groupRelease.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage hydrates current-peer official state during bootstrap load',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((request) async {
        if (request.url.path.endsWith('/official_accounts')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'accounts': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'official-1',
                  'kind': 'service',
                  'name': 'Official Peer',
                  'chat_peer_id': _peerId,
                  'followed': true,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: true,
        channels: false,
        serviceNotifications: false,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    await state.debugLoadBootstrapOfficialForCurrentPeer();
    await tester.pump();

    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialPeerId', _peerId),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialId', 'official-1'),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialFollowed', true),
    );
  });

  testWidgets(
      'ShamellChatPage starts switched-peer official hydration through the dedicated detached seam',
      (tester) async {
    final loadCompleter = Completer<void>();
    String? loadedPeerId;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadSwitchedPeerOfficialOverride: (peer) async {
        loadedPeerId = peer.id;
        await loadCompleter.future;
      },
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: true,
        channels: false,
        serviceNotifications: false,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    const otherPeerId = 'peer-2';
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
    );

    var completed = false;
    final pending = state.debugSwitchPeer(otherPeer);
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isTrue);
    expect(loadedPeerId, otherPeerId);

    loadCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage hydrates switched-peer official state in the background after switch',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((request) async {
        if (request.url.path.endsWith('/official_accounts') &&
            request.url.queryParameters['chat_peer_id'] == 'peer-2') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'accounts': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'official-2',
                  'kind': 'service',
                  'name': 'Official Peer Two',
                  'chat_peer_id': 'peer-2',
                  'followed': true,
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{'accounts': const <Object>[]}),
          200,
        );
      }),
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: true,
        channels: false,
        serviceNotifications: false,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
    );

    await state.debugSwitchPeer(otherPeer);
    await tester.pump();
    await tester.pump();

    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialPeerId', 'peer-2'),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialId', 'official-2'),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialFollowed', true),
    );
  });

  testWidgets(
      'ShamellChatPage ignores stale official hydration responses after peer switch',
      (tester) async {
    final firstPeerResponse = Completer<http.Response>();
    final secondPeerResponse = Completer<http.Response>();
    var firstPeerRequested = false;
    var secondPeerRequested = false;
    final injectedOfficialIds = <String>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((request) async {
        if (request.url.path.endsWith('/official_accounts') &&
            request.url.queryParameters['chat_peer_id'] == _peerId) {
          firstPeerRequested = true;
          return firstPeerResponse.future;
        }
        if (request.url.path.endsWith('/official_accounts') &&
            request.url.queryParameters['chat_peer_id'] == 'peer-2') {
          secondPeerRequested = true;
          return secondPeerResponse.future;
        }
        return http.Response(
          jsonEncode(<String, Object?>{'accounts': const <Object>[]}),
          200,
        );
      }),
      startOfficialWelcomeInjectionOverride: (account) async {
        injectedOfficialIds.add(account.id);
      },
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: true,
        channels: false,
        serviceNotifications: false,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    final pendingFirstLoad = state.debugLoadBootstrapOfficialForCurrentPeer();
    await tester.pump();
    expect(firstPeerRequested, isTrue);

    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
    );

    await state.debugSwitchPeer(otherPeer);
    await tester.pump();
    await tester.pump();
    expect(secondPeerRequested, isTrue);

    secondPeerResponse.complete(
      http.Response(
        jsonEncode(<String, Object?>{
          'accounts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'official-2',
              'kind': 'service',
              'name': 'Official Peer Two',
              'chat_peer_id': 'peer-2',
              'followed': true,
            },
          ],
        }),
        200,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialPeerId', 'peer-2'),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialId', 'official-2'),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialFollowed', true),
    );
    expect(injectedOfficialIds, <String>['official-2']);

    firstPeerResponse.complete(
      http.Response(
        jsonEncode(<String, Object?>{
          'accounts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'official-1',
              'kind': 'service',
              'name': 'Official Peer',
              'chat_peer_id': _peerId,
              'followed': true,
            },
          ],
        }),
        200,
      ),
    );
    await pendingFirstLoad;
    await tester.pump();
    await tester.pump();

    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialPeerId', 'peer-2'),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialId', 'official-2'),
    );
    expect(
      state.debugOfficialPeerState(),
      containsPair('linkedOfficialFollowed', true),
    );
    expect(injectedOfficialIds, <String>['official-2']);
  });

  testWidgets(
      'ShamellChatPage starts official welcome injection through the dedicated detached seam',
      (tester) async {
    final loadCompleter = Completer<void>();
    String? loadedOfficialId;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((request) async {
        if (request.url.path.endsWith('/official_accounts')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'accounts': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'official-1',
                  'kind': 'service',
                  'name': 'Official Peer',
                  'chat_peer_id': _peerId,
                  'followed': true,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
      startOfficialWelcomeInjectionOverride: (account) async {
        loadedOfficialId = account.id;
        await loadCompleter.future;
      },
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    var completed = false;
    final pending = state.debugLoadOfficialForPeer(_peerId);
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isTrue);
    expect(loadedOfficialId, 'official-1');

    loadCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage injects official welcome in the background after official hydration',
      (tester) async {
    final store = ChatLocalStore();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((request) async {
        if (request.url.path.endsWith('/official_accounts') &&
            request.url.queryParameters['chat_peer_id'] == _peerId) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'accounts': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'official-1',
                  'kind': 'service',
                  'name': 'Official Peer',
                  'chat_peer_id': _peerId,
                  'followed': true,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path
            .endsWith('/official_accounts/official-1/auto_replies')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'rules': <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'welcome',
                  'enabled': true,
                  'text': 'Welcome aboard',
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    await state.debugLoadOfficialForPeer(_peerId);
    await tester.pump();
    await tester.pump();

    expect(
      await store.hasOfficialAutoreplyShown(
        _peerId,
        baseUrlOverride: _baseUrl,
      ),
      isTrue,
    );
    final storedMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    expect(storedMessages, hasLength(1));
    expect(
      utf8.decode(base64Decode(storedMessages.single.boxB64)),
      'Welcome aboard',
    );
  });

  testWidgets(
      'ShamellChatPage starts payments service follow through the dedicated detached seam',
      (tester) async {
    final followCompleter = Completer<void>();
    String? startedOfficialId;
    String? startedChatPeerId;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startServiceOfficialFollowOverride: (officialId, chatPeerId) async {
        startedOfficialId = officialId;
        startedChatPeerId = chatPeerId;
        await followCompleter.future;
      },
      openPaymentsPageOverride: (_, __) async {},
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    var completed = false;
    final pending = state.debugSendComposerMessage('/pay 12 @peer-2');
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isTrue);
    expect(startedOfficialId, 'shamell_pay');
    expect(startedChatPeerId, 'shamell_pay');

    followCompleter.complete();
    await tester.pump();
  });

  testWidgets('ShamellChatPage waits for /pay payments open before returning',
      (tester) async {
    final openCompleter = Completer<void>();
    final openCalls = <({String? initialRecipient, int? initialAmountCents})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startServiceOfficialFollowOverride: (_, __) async {},
      openPaymentsPageOverride: (initialRecipient, initialAmountCents) async {
        openCalls.add((
          initialRecipient: initialRecipient,
          initialAmountCents: initialAmountCents,
        ));
        await openCompleter.future;
      },
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    var completed = false;
    final pending = state.debugSendComposerMessage('/pay 12 @peer-2');
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(
      openCalls,
      <({String? initialRecipient, int? initialAmountCents})>[
        (initialRecipient: 'peer-2', initialAmountCents: 1200),
      ],
    );

    openCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage follows the payments service official in the background after /pay',
      (tester) async {
    final store = ChatLocalStore();
    await setSessionTokenForBaseUrl(
      _baseUrl,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      openPaymentsPageOverride: (_, __) async {},
      officialHttpClient: MockClient((request) async {
        if (request.url.path
            .endsWith('/official_accounts/shamell_pay/follow')) {
          return http.Response('{}', 200);
        }
        return http.Response('{}', 200);
      }),
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    await state.debugSendComposerMessage('/pay 12 @peer-2');
    await tester.pump();
    await tester.pump();

    expect(
      await store.hasOfficialAutofollowed(
        'shamell_pay',
        baseUrlOverride: _baseUrl,
      ),
      isTrue,
    );
    expect(
      await store.hasOfficialAutochat(
        'shamell_pay',
        baseUrlOverride: _baseUrl,
      ),
      isTrue,
    );
    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    expect(storedContacts.any((c) => c.id == 'shamell_pay'), isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for /pay draft clear persistence before returning',
      (tester) async {
    final draftCompleter = Completer<void>();
    Map<String, String>? persistedDrafts;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startServiceOfficialFollowOverride: (_, __) async {},
      openPaymentsPageOverride: (_, __) async {},
      saveDraftsOverride: (drafts) async {
        persistedDrafts = Map<String, String>.from(drafts);
        await draftCompleter.future;
      },
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    state.debugSeedDraftForChat(_peerId, 'old draft');
    await tester.pump();

    var completed = false;
    final pending = state.debugSendComposerMessage('/pay 12 @peer-2');
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(persistedDrafts, <String, String>{});

    draftCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage clears the persisted draft for /pay through the draft-save seam',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveDrafts(
      <String, String>{_peerId: 'old draft'},
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startServiceOfficialFollowOverride: (_, __) async {},
      openPaymentsPageOverride: (_, __) async {},
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    state.debugSeedDraftForChat(_peerId, 'old draft');
    await tester.pump();

    await state.debugSendComposerMessage('/pay 12 @peer-2');
    await tester.pump();

    expect(
      await store.loadDrafts(baseUrlOverride: _baseUrl),
      <String, String>{},
    );
  });

  testWidgets(
      'ShamellChatPage resets send busy state after /pay local command completes',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startServiceOfficialFollowOverride: (_, __) async {},
      openPaymentsPageOverride: (_, __) async {},
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    await state.debugSendComposerMessage('/pay 12 @peer-2');
    await tester.pump();

    expect(
      state.debugBootstrapState(),
      containsPair('loading', false),
    );
    expect(
      state.debugBootstrapState(),
      containsPair('sending', false),
    );
  });

  testWidgets(
      'ShamellChatPage stops composer typing after /pay local command completes',
      (tester) async {
    final service = _FakeChatBootstrapService(
      sendTypingSignalHandler: ({
        required String deviceId,
        required bool isTyping,
        String? peerId,
        String? groupId,
      }) async {},
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
      startServiceOfficialFollowOverride: (_, __) async {},
      openPaymentsPageOverride: (_, __) async {},
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    await state.debugSendComposerMessage('/pay 12 @peer-2');
    await tester.pump();

    expect(
      service.typingSignals,
      contains(
        (
          deviceId: _meId,
          isTyping: false,
          peerId: _peerId,
          groupId: null,
        ),
      ),
    );
  });

  testWidgets(
      'ShamellChatPage routes composer send-money through the shared payments seam',
      (tester) async {
    final openCompleter = Completer<void>();
    final openCalls = <({String? initialRecipient, int? initialAmountCents})>[];
    final followCalls = <({String officialId, String chatPeerId})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startServiceOfficialFollowOverride: (officialId, chatPeerId) async {
        followCalls.add((officialId: officialId, chatPeerId: chatPeerId));
      },
      openPaymentsPageOverride: (initialRecipient, initialAmountCents) async {
        openCalls.add((
          initialRecipient: initialRecipient,
          initialAmountCents: initialAmountCents,
        ));
        await openCompleter.future;
      },
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());

    var completed = false;
    final pending = state.debugRunComposerMoreActionByIcon(
      Icons.payments_outlined,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(
      followCalls,
      <({String officialId, String chatPeerId})>[
        (officialId: 'shamell_pay', chatPeerId: 'shamell_pay'),
      ],
    );
    expect(
      openCalls,
      <({String? initialRecipient, int? initialAmountCents})>[
        (initialRecipient: _peerId, initialAmountCents: null),
      ],
    );

    openCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for message-popover send-money through the shared payments seam',
      (tester) async {
    final openCompleter = Completer<void>();
    final openCalls = <({String? initialRecipient, int? initialAmountCents})>[];
    final followCalls = <({String officialId, String chatPeerId})>[];
    final message = _buildDirectMessage(
      id: 'msg-popover-pay-001',
      text: 'pay me',
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startServiceOfficialFollowOverride: (officialId, chatPeerId) async {
        followCalls.add((officialId: officialId, chatPeerId: chatPeerId));
      },
      openPaymentsPageOverride: (initialRecipient, initialAmountCents) async {
        openCalls.add((
          initialRecipient: initialRecipient,
          initialAmountCents: initialAmountCents,
        ));
        await openCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[message],
    );

    var completed = false;
    final pending = state.debugRunMessageLongPressPopoverActionByIcon(
      message,
      Icons.payments_outlined,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(
      followCalls,
      <({String officialId, String chatPeerId})>[
        (officialId: 'shamell_pay', chatPeerId: 'shamell_pay'),
      ],
    );
    expect(
      openCalls,
      <({String? initialRecipient, int? initialAmountCents})>[
        (initialRecipient: _peerId, initialAmountCents: null),
      ],
    );

    openCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for bootstrap official notification mode sync before returning',
      (tester) async {
    final loadCompleter = Completer<void>();
    var loadCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapOfficialNotificationModesOverride: () async {
        loadCount += 1;
        await loadCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugLoadBootstrapOfficialNotificationModes();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(loadCount, 1);

    loadCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage syncs official notification modes during bootstrap load',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((request) async {
        if (request.url.path.endsWith('/official_accounts/notifications')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'modes': <String, String>{'official-1': 'muted'},
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    state.debugSeedOfficialPeerMapping(<String, String>{_peerId: 'official-1'});
    await tester.pump();

    await state.debugLoadBootstrapOfficialNotificationModes();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(updatedPeer.muted, isTrue);
    expect(
      await state.debugLoadStoredOfficialNotificationMode(_peerId),
      'muted',
    );
    expect(preservedPeer.muted, isFalse);
  });

  testWidgets(
      'ShamellChatPage waits for bootstrap direct prefs sync before returning',
      (tester) async {
    final loadCompleter = Completer<void>();
    var loadCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapDirectPrefsSyncOverride: () async {
        loadCount += 1;
        await loadCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugLoadBootstrapDirectPrefsSync();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(loadCount, 1);

    loadCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage runs direct prefs bootstrap sync through the paged sync path',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      fetchPrefsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatContactPrefs>[
          ChatContactPrefs(
            peerId: _peerId,
            muted: true,
            starred: false,
            pinned: true,
          ),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugLoadBootstrapDirectPrefsSync();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final syncedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(service.fetchPrefsPagedCallCount, 1);
    expect(syncedPeer.muted, isTrue);
    expect(syncedPeer.pinned, isTrue);
    expect(preservedPeer.muted, isFalse);
    expect(preservedPeer.pinned, isFalse);
  });

  testWidgets(
      'ShamellChatPage waits for bootstrap group prefs sync before returning',
      (tester) async {
    final loadCompleter = Completer<void>();
    var loadCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapGroupPrefsSyncOverride: () async {
        loadCount += 1;
        await loadCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugLoadBootstrapGroupPrefsSync();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(loadCount, 1);

    loadCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage runs group prefs bootstrap sync through the pinned-order reconcile path',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['stale-peer', 'grp:group-2'],
      baseUrlOverride: _baseUrl,
    );

    final service = _FakeChatBootstrapService(
      fetchGroupPrefsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatGroupPrefs>[
          ChatGroupPrefs(groupId: _groupId, muted: false, pinned: true),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncGroups();
    await tester.pump();
    await state.debugLoadBootstrapGroupPrefsSync();
    await tester.pump();

    expect(service.fetchGroupPrefsPagedCallCount, 1);
    expect(
      state.debugPinnedChatOrderSnapshot(),
      <String>['grp:$_groupId'],
    );
  });

  testWidgets(
      'ShamellChatPage waits for bootstrap devices summary load before returning',
      (tester) async {
    final loadCompleter = Completer<void>();
    var loadCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadBootstrapDevicesSummaryOverride: () async {
        loadCount += 1;
        await loadCompleter.future;
      },
    );

    var completed = false;
    final pending = state.debugLoadBootstrapDevicesSummary();
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(loadCount, 1);

    loadCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets('ShamellChatPage loads devices summary during bootstrap load',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveIdentity(_buildMe(), baseUrlOverride: _baseUrl);

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      accountHttpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'devices': <Map<String, Object?>>[
              <String, Object?>{
                'device_id': _meId,
                'device_type': 'This device',
              },
              <String, Object?>{
                'device_id': 'device-2',
                'device_type': 'Desktop',
              },
            ],
          }),
          200,
        ),
      ),
    );

    await state.debugLoadBootstrapDevicesSummary();
    await tester.pump();

    expect(
      state.debugDevicesSummaryState(),
      containsPair('hasOtherDevices', true),
    );
    expect(
      state.debugDevicesSummaryState(),
      containsPair('otherDeviceLabel', 'Desktop'),
    );
  });

  testWidgets(
      'ShamellChatPage waits for system-thread delete persistence before dismissing the swipe action',
      (tester) async {
    final hidePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveHideServiceNotificationsThreadOverride: (hide) async {
        await hidePersistCompleter.future;
      },
    );

    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: false,
        channels: false,
        serviceNotifications: true,
        paymentsPhoneTargets: false,
      ),
    );
    state.debugSetServiceNotificationsThreadState(hasUnread: true);
    state.debugShowChatsList(
        me: _buildMe(), contacts: <ChatContact>[_buildPeer()]);
    await tester.pump();

    final serviceTile =
        find.byKey(const ValueKey<String>('sys_service_notifications'));
    expect(serviceTile, findsOneWidget);

    await tester.drag(serviceTile, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(find.text('Delete'), findsOneWidget);

    hidePersistCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsNothing);
    expect(serviceTile, findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group unread persistence before dismissing the swipe action',
      (tester) async {
    final unreadPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        await unreadPersistCompleter.future;
      },
    );

    state.debugShowChatsList(
      me: _buildMe(),
      groups: <ChatGroup>[_buildGroup()],
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedUnread(<String, int>{'grp:$_groupId': 1});
    await tester.pump();

    final groupTile = find.byKey(const ValueKey<String>('grp_group_1'));
    expect(groupTile, findsOneWidget);

    await tester.drag(groupTile, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsOneWidget);

    await tester.tap(find.text('Read'));
    await tester.pump();

    expect(find.text('Unread'), findsOneWidget);

    unreadPersistCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Unread'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for group pin persistence before dismissing the swipe action',
      (tester) async {
    final pinPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(
        setGroupPrefsHandler: ({
          required deviceId,
          required groupId,
          bool? muted,
          bool? pinned,
        }) async {
          await pinPersistCompleter.future;
        },
      ),
      onCritical: () {},
    );

    state.debugShowChatsList(
      me: _buildMe(),
      groups: <ChatGroup>[_buildGroup()],
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedUnread(<String, int>{'grp:$_groupId': 1});
    await tester.pump();

    final groupTile = find.byKey(const ValueKey<String>('grp_group_1'));
    expect(groupTile, findsOneWidget);

    await tester.drag(groupTile, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Pin'), findsOneWidget);

    await tester.tap(find.text('Pin'));
    await tester.pump();

    expect(find.text('Pin'), findsOneWidget);

    pinPersistCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Pin'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for archived group delete persistence before dismissing the swipe action',
      (tester) async {
    final deletePersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        await deletePersistCompleter.future;
      },
    );

    state.debugShowChatsList(
      me: _buildMe(),
      groups: <ChatGroup>[_buildGroup()],
      showArchived: true,
      archivedGroupIds: <String>{_groupId},
      chatSearch: 'security',
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedUnread(<String, int>{'grp:$_groupId': 1});
    await tester.pump();

    final groupTile = find.byKey(const ValueKey<String>('grp_group_1'));
    expect(groupTile, findsOneWidget);

    await tester.drag(groupTile, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(find.text('Delete'), findsOneWidget);

    deletePersistCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for direct pin persistence before dismissing the swipe action',
      (tester) async {
    final pinPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveContactsForPeersOverride: (contacts) async {
        await pinPersistCompleter.future;
      },
    );

    state.debugShowChatsList(
        me: _buildMe(), contacts: <ChatContact>[_buildPeer()]);
    await tester.pump();

    final chatTile = find.byKey(const ValueKey<String>('chat_peer_1'));
    expect(chatTile, findsOneWidget);

    await tester.drag(chatTile, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Pin'), findsOneWidget);

    await tester.tap(find.text('Pin'));
    await tester.pump();

    expect(find.text('Pin'), findsOneWidget);

    pinPersistCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Pin'), findsNothing);
  });

  testWidgets(
      'ChatLocalStore savePinnedChatOrderState updates only the targeted peer key',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['peer-2', 'grp:group-2'],
      baseUrlOverride: _baseUrl,
    );

    await store.savePinnedChatOrderState(
      _peerId,
      true,
      baseUrlOverride: _baseUrl,
    );

    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _baseUrl),
      <String>[_peerId, 'peer-2', 'grp:group-2'],
    );
  });

  testWidgets(
      'ChatLocalStore reconcilePinnedChatOrder keeps only the normalized pinned keys',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['stale-peer', 'grp:group-2'],
      baseUrlOverride: _baseUrl,
    );

    final next = await store.reconcilePinnedChatOrder(
      <String>['grp:$_groupId'],
      baseUrlOverride: _baseUrl,
    );

    expect(next, <String>['grp:$_groupId']);
    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _baseUrl),
      <String>['grp:$_groupId'],
    );
  });

  testWidgets(
      'ChatLocalStore reconcilePinnedChatOrder clears the order when no pinned keys remain',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['stale-peer', 'grp:group-2'],
      baseUrlOverride: _baseUrl,
    );

    final next = await store.reconcilePinnedChatOrder(
      const <String>[],
      baseUrlOverride: _baseUrl,
    );

    expect(next, isEmpty);
    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _baseUrl),
      isEmpty,
    );
  });

  testWidgets(
      'ShamellChatPage updates pinned chat order through the targeted peer contract',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['peer-2', 'grp:group-2'],
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetPeerPinned(true);
    await tester.pump();

    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _baseUrl),
      <String>[_peerId, 'peer-2', 'grp:group-2'],
    );
  });

  testWidgets(
      'ShamellChatPage normalizes pinned chat order through the reconcile contract during group prefs sync',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['stale-peer', 'grp:group-2'],
      baseUrlOverride: _baseUrl,
    );

    final service = _FakeChatBootstrapService(
      fetchGroupPrefsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatGroupPrefs>[
          ChatGroupPrefs(groupId: _groupId, muted: false, pinned: true),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncGroups();
    await tester.pump();
    await state.debugSyncGroupPrefsFromServer();
    await tester.pump();

    expect(
      state.debugPinnedChatOrderSnapshot(),
      <String>['grp:$_groupId'],
    );
    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _baseUrl),
      <String>['grp:$_groupId'],
    );
  });

  testWidgets(
      'ShamellChatPage clears pinned chat order through the reconcile contract when no pinned group prefs remain',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['stale-peer', 'grp:group-2'],
      baseUrlOverride: _baseUrl,
    );

    final service = _FakeChatBootstrapService(
      fetchGroupPrefsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatGroupPrefs>[
          ChatGroupPrefs(groupId: _groupId, muted: false, pinned: false),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncGroups();
    await tester.pump();
    await state.debugSyncGroupPrefsFromServer();
    await tester.pump();

    expect(state.debugPinnedChatOrderSnapshot(), isEmpty);
    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _baseUrl),
      isEmpty,
    );
  });

  testWidgets(
      'ShamellChatPage waits for pinned-message persistence before committing local pin state',
      (tester) async {
    final delayedPinnedSave = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          runStartupTasks: false,
          serviceOverride: _FakeChatBootstrapService(),
          onCriticalChatSessionFailure: () {},
          savePinnedMessageForPeerOverride: (peerId, messageId, pinned) async {
            await delayedPinnedSave.future;
            await ChatLocalStore().savePinnedMessageForPeer(
              peerId,
              messageId,
              pinned,
              baseUrlOverride: _baseUrl,
            );
          },
        ),
      ),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(ShamellChatPage));
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
    );
    await tester.pump();

    final pending = state.debugSetPinnedMessageForPeer(_peerId, 'msg-1', true);
    await tester.pump();

    expect(state.debugIsMessagePinnedForPeer(_peerId, 'msg-1'), isFalse);

    delayedPinnedSave.complete();
    await pending;
    await tester.pump();

    expect(state.debugIsMessagePinnedForPeer(_peerId, 'msg-1'), isTrue);
    expect(
      await ChatLocalStore().loadPinnedMessages(baseUrlOverride: _baseUrl),
      <String, Set<String>>{
        _peerId: <String>{'msg-1'},
      },
    );
  });

  testWidgets(
      'ShamellChatPage waits for recalled-message persistence before committing local recall state',
      (tester) async {
    final delayedRecallSave = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          runStartupTasks: false,
          serviceOverride: _FakeChatBootstrapService(),
          onCriticalChatSessionFailure: () {},
          saveRecalledMessageStateOverride: (messageId, recalled) async {
            await delayedRecallSave.future;
            await ChatLocalStore().saveRecalledMessageState(
              messageId,
              recalled,
              baseUrlOverride: _baseUrl,
            );
          },
        ),
      ),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(ShamellChatPage));
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
    );
    await tester.pump();

    final pending = state.debugSetRecalledMessageState('msg-1', true);
    await tester.pump();

    expect(state.debugIsMessageRecalled('msg-1'), isFalse);

    delayedRecallSave.complete();
    await pending;
    await tester.pump();

    expect(state.debugIsMessageRecalled('msg-1'), isTrue);
    expect(
      await ChatLocalStore().loadRecalledMessageIds(baseUrlOverride: _baseUrl),
      <String>{'msg-1'},
    );
  });

  testWidgets(
      'ShamellChatPage waits for recall-triggered pin cleanup persistence before clearing local pin state',
      (tester) async {
    final delayedPinnedRemoval = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          runStartupTasks: false,
          serviceOverride: _FakeChatBootstrapService(),
          onCriticalChatSessionFailure: () {},
          removePinnedMessageFromAllPeersOverride: (messageId) async {
            await delayedPinnedRemoval.future;
            await ChatLocalStore().removePinnedMessageFromAllPeers(
              messageId,
              baseUrlOverride: _baseUrl,
            );
          },
        ),
      ),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(ShamellChatPage));
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
    );
    await tester.pump();
    await state.debugSetPinnedMessageForPeer(_peerId, 'msg-1', true);
    await tester.pump();

    final pending = state.debugHandleMessageRecalled('msg-1');
    await tester.pump();

    expect(state.debugIsMessagePinnedForPeer(_peerId, 'msg-1'), isTrue);

    delayedPinnedRemoval.complete();
    await pending;
    await tester.pump();

    expect(state.debugIsMessagePinnedForPeer(_peerId, 'msg-1'), isFalse);
    expect(
      await ChatLocalStore().loadPinnedMessages(baseUrlOverride: _baseUrl),
      isEmpty,
    );
  });

  testWidgets(
      'ShamellChatPage waits for recall-triggered favorites cleanup before completing recall handling',
      (tester) async {
    final delayedFavoritesCleanup = Completer<void>();
    var recallFinished = false;

    await saveFavoriteItems(
      <Map<String, dynamic>>[
        <String, dynamic>{'text': 'saved one', 'msgId': 'msg-1'},
        <String, dynamic>{'text': 'saved two', 'msgId': 'msg-2'},
      ],
      baseUrlOverride: _baseUrl,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellChatPage(
          baseUrl: _baseUrl,
          runStartupTasks: false,
          serviceOverride: _FakeChatBootstrapService(),
          onCriticalChatSessionFailure: () {},
          removeFavoriteItemsByMessageIdOverride: (messageId) async {
            await delayedFavoritesCleanup.future;
            await removeFavoriteItemsByMessageId(
              messageId,
              baseUrlOverride: _baseUrl,
            );
          },
        ),
      ),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(ShamellChatPage));
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
    );
    await tester.pump();

    final pending = state.debugHandleMessageRecalled('msg-1').then((_) {
      recallFinished = true;
    });
    await tester.pump();

    expect(recallFinished, isFalse);
    expect(
      await loadFavoriteItems(baseUrlOverride: _baseUrl),
      <Map<String, dynamic>>[
        <String, dynamic>{'text': 'saved one', 'msgId': 'msg-1'},
        <String, dynamic>{'text': 'saved two', 'msgId': 'msg-2'},
      ],
    );

    delayedFavoritesCleanup.complete();
    await pending;
    await tester.pump();

    expect(recallFinished, isTrue);
    expect(
      await loadFavoriteItems(baseUrlOverride: _baseUrl),
      <Map<String, dynamic>>[
        <String, dynamic>{'text': 'saved two', 'msgId': 'msg-2'},
      ],
    );
  });

  testWidgets(
      'ShamellChatPage does not invent a local SyrChat ID when none is stored',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await clearStoredShamellUserId(sp: sp);

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugLoadStoredShamellUserId();
    await tester.pump();

    expect(state.debugCurrentShamellUserId, isEmpty);
    expect(await loadShamellUserId(sp: sp), isNull);
  });

  testWidgets('ShamellChatPage reauths on critical groups list failure',
      (tester) async {
    final service =
        _FakeChatBootstrapService(listGroupsError: criticalChatError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSyncGroups();
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical group inbox sync failure',
      (tester) async {
    final service = _FakeChatBootstrapService(
      fetchGroupInboxError: criticalChatError,
    );
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSyncGroups();
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage uses stable group cursor with since_id during sync',
      (tester) async {
    final service = _FakeChatBootstrapService();
    final createdAt = DateTime.utc(2026, 3, 18, 10, 0, 0);
    await ChatLocalStore().saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'msg-002',
          groupId: _groupId,
          senderId: _peerId,
          text: 'later id',
          createdAt: createdAt,
        ),
        ChatGroupMessage(
          id: 'msg-001',
          groupId: _groupId,
          senderId: _peerId,
          text: 'earlier id',
          createdAt: createdAt,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncGroups();
    await tester.pump();

    expect(
      service.lastFetchGroupInboxSinceIso,
      createdAt.toIso8601String(),
    );
    expect(service.lastFetchGroupInboxSinceId, 'msg-002');
  });

  testWidgets('ShamellChatPage uses paged groups list sync', (tester) async {
    final service = _FakeChatBootstrapService(
      listGroupsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatGroup>[
          ChatGroup(
            id: _groupId,
            name: 'Security Group',
            creatorId: _meId,
            memberCount: 2,
          ),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncGroups();
    await tester.pump();

    expect(service.listGroupsPagedCallCount, 1);
  });

  testWidgets(
      'ShamellChatPage waits for group-name upsert persistence before continuing group sync',
      (tester) async {
    final service = _FakeChatBootstrapService(
      listGroupsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatGroup>[
          ChatGroup(
            id: _groupId,
            name: 'Security Group',
            creatorId: _meId,
            memberCount: 2,
          ),
        ];
      },
    );
    final upsertCalls = <List<String>>[];
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final upsertCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
      upsertGroupNamesOverride: (groups) async {
        upsertCalls
            .add(groups.map((group) => group.id).toList(growable: false));
        await upsertCompleter.future;
      },
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false),
        ));
      },
    );

    var completed = false;
    final syncFuture = state.debugSyncGroups();
    unawaited(syncFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(upsertCalls, <List<String>>[
      <String>[_groupId],
    ]);
    expect(service.fetchGroupInboxCallCount, 0);
    expect(unreadBatchCalls, isEmpty);

    upsertCompleter.complete();
    await syncFuture;
    await tester.pump();

    expect(completed, isTrue);
    expect(service.fetchGroupInboxCallCount, 1);
    expect(unreadBatchCalls, hasLength(1));
  });

  testWidgets(
      'ShamellChatPage preserves current direct unread state during group sync',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': 3,
    });

    await state.debugSyncGroups();
    await tester.pump();

    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 3,
      },
    );
  });

  testWidgets(
      'ShamellChatPage clears direct unread through the targeted peer contract when switching threads',
      (tester) async {
    final unreadCalls = <({String peerId, int unreadCount})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((_) async {
        return http.Response('{"accounts":[]}', 200);
      }),
      saveUnreadCountForPeerOverride: (peerId, unreadCount) async {
        unreadCalls.add((peerId: peerId, unreadCount: unreadCount));
      },
    );
    const otherPeerId = 'peer-2';
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      otherPeerId: 5,
      'grp:$_groupId': 3,
    });

    await state.debugSwitchPeer(otherPeer);
    await tester.pump();

    expect(
      unreadCalls,
      <({String peerId, int unreadCount})>[
        (peerId: otherPeerId, unreadCount: 0),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        otherPeerId: 0,
        'grp:$_groupId': 3,
      },
    );
  });

  testWidgets(
      'ShamellChatPage clears direct unread through the targeted peer contract when clearing chat history',
      (tester) async {
    final savedMessageCalls = <({String peerId, List<ChatMessage> messages})>[];
    final unreadCalls = <({String peerId, int unreadCount})>[];
    final saveMessagesCompleter = Completer<void>();
    final unreadPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveMessagesForPeerOverride: (peerId, messages) async {
        savedMessageCalls.add((
          peerId: peerId,
          messages: List<ChatMessage>.from(messages),
        ));
        await saveMessagesCompleter.future;
      },
      saveUnreadCountForPeerOverride: (peerId, unreadCount) async {
        unreadCalls.add((peerId: peerId, unreadCount: unreadCount));
        await unreadPersistCompleter.future;
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
    });

    var completed = false;
    final clearFuture = state.debugClearChatHistoryForPeer(_buildPeer());
    unawaited(clearFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(savedMessageCalls, hasLength(1));
    expect(savedMessageCalls.single.peerId, _peerId);
    expect(savedMessageCalls.single.messages, isEmpty);
    expect(unreadCalls, isEmpty);

    saveMessagesCompleter.complete();
    await tester.pump();

    expect(completed, isFalse);

    expect(
      unreadCalls,
      <({String peerId, int unreadCount})>[
        (peerId: _peerId, unreadCount: 0),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 5,
        'grp:$_groupId': 3,
      },
    );

    unreadPersistCompleter.complete();
    await clearFuture;
  });

  testWidgets(
      'ShamellChatPage waits for local message deletion persistence before returning',
      (tester) async {
    final savedMessageCalls = <({String peerId, List<ChatMessage> messages})>[];
    final saveMessagesCompleter = Completer<void>();
    final message = ChatMessage(
      id: 'msg-local-delete-001',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('hello')),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 2, 0),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveMessagesForPeerOverride: (peerId, messages) async {
        savedMessageCalls.add((
          peerId: peerId,
          messages: List<ChatMessage>.from(messages),
        ));
        await saveMessagesCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[message],
    );

    var completed = false;
    final deleteFuture = state.debugDeleteMessageLocal(message);
    unawaited(deleteFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(savedMessageCalls, hasLength(1));
    expect(savedMessageCalls.single.peerId, _peerId);
    expect(savedMessageCalls.single.messages, isEmpty);
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 0),
    );

    saveMessagesCompleter.complete();
    await deleteFuture;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for selected-message deletion persistence before returning',
      (tester) async {
    final savedMessageCalls = <({String peerId, List<ChatMessage> messages})>[];
    final saveMessagesCompleter = Completer<void>();
    final firstMessage = ChatMessage(
      id: 'msg-selected-delete-001',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('first')),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 3, 0),
    );
    final secondMessage = ChatMessage(
      id: 'msg-selected-delete-002',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('second')),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 4, 0),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveMessagesForPeerOverride: (peerId, messages) async {
        savedMessageCalls.add((
          peerId: peerId,
          messages: List<ChatMessage>.from(messages),
        ));
        await saveMessagesCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[firstMessage, secondMessage],
    );
    state.debugSeedSelectedMessageIds(<String>[firstMessage.id]);

    var completed = false;
    final deleteFuture = state.debugDeleteSelectedMessages();
    unawaited(deleteFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(savedMessageCalls, hasLength(1));
    expect(savedMessageCalls.single.peerId, _peerId);
    expect(
      savedMessageCalls.single.messages.map((message) => message.id).toList(),
      <String>[secondMessage.id],
    );
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 1),
    );

    saveMessagesCompleter.complete();
    await deleteFuture;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for expiring-message prune persistence before returning',
      (tester) async {
    final savedMessageCalls = <({String peerId, List<ChatMessage> messages})>[];
    final saveMessagesCompleter = Completer<void>();
    final now = DateTime.now().toUtc();
    final expiredMessage = ChatMessage(
      id: 'msg-expired-prune-001',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('expired')),
      trustedLocalPlaintext: true,
      createdAt: now.subtract(const Duration(hours: 2)),
    );
    final recentMessage = ChatMessage(
      id: 'msg-expired-prune-002',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('recent')),
      trustedLocalPlaintext: true,
      createdAt: now.subtract(const Duration(minutes: 5)),
    );
    final disappearingPeer = _buildPeer().copyWith(
      disappearing: true,
      disappearAfter: const Duration(minutes: 30),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveMessagesForPeerOverride: (peerId, messages) async {
        savedMessageCalls.add((
          peerId: peerId,
          messages: List<ChatMessage>.from(messages),
        ));
        await saveMessagesCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: disappearingPeer,
      messages: <ChatMessage>[expiredMessage, recentMessage],
    );

    var completed = false;
    final pruneFuture = state.debugPruneExpiredForPeer(disappearingPeer.id);
    unawaited(pruneFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(savedMessageCalls, hasLength(1));
    expect(savedMessageCalls.single.peerId, _peerId);
    expect(
      savedMessageCalls.single.messages.map((message) => message.id).toList(),
      <String>[recentMessage.id],
    );
    expect(
      state.debugBootstrapState(),
      containsPair('cachedMessageCount', 1),
    );
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 1),
    );

    saveMessagesCompleter.complete();
    await pruneFuture;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for copy-message popover actions before returning',
      (tester) async {
    final copiedTexts = <String>[];
    final copyCompleter = Completer<void>();
    final message = _buildDirectMessage(
      id: 'msg-popover-copy-001',
      text: 'copy me',
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      copyMessageTextOverride: (text) async {
        copiedTexts.add(text);
        await copyCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[message],
    );

    var completed = false;
    final pending = state.debugRunMessageLongPressPopoverActionByIcon(
      message,
      Icons.copy_outlined,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(copiedTexts, <String>['copy me']);

    copyCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for composer favorites actions before returning',
      (tester) async {
    final pickerCompleter = Completer<void>();
    var openCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      openFavoritesPickerOverride: () async {
        openCount += 1;
        await pickerCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
    );

    var completed = false;
    final pending = state.debugRunComposerMoreActionByIcon(
      Icons.bookmark_outline,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(openCount, 1);

    pickerCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for composer contact-card actions before returning',
      (tester) async {
    final pickerCompleter = Completer<void>();
    var openCount = 0;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      openContactCardPickerOverride: () async {
        openCount += 1;
        await pickerCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
    );

    var completed = false;
    final pending = state.debugRunComposerMoreActionByIcon(
      Icons.contact_page_outlined,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(openCount, 1);

    pickerCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for message-forward popover actions before returning',
      (tester) async {
    final forwardCalls = <String>[];
    final forwardCompleter = Completer<void>();
    final message = _buildDirectMessage(
      id: 'msg-popover-forward-001',
      text: 'forward me',
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      forwardMessageOverride: (message) async {
        forwardCalls.add(message.id);
        await forwardCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[message],
    );

    var completed = false;
    final pending = state.debugRunMessageLongPressPopoverActionByIcon(
      message,
      Icons.forward,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(forwardCalls, <String>[message.id]);

    forwardCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for add-to-favorites popover actions before returning',
      (tester) async {
    final favoriteCalls = <({String text, String? chatId, String? msgId})>[];
    final favoriteCompleter = Completer<void>();
    final message = _buildDirectMessage(
      id: 'msg-popover-favorite-001',
      text: 'favorite me',
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      addFavoriteItemQuickOverride: (text, chatId, msgId) async {
        favoriteCalls.add((text: text, chatId: chatId, msgId: msgId));
        await favoriteCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[message],
    );

    var completed = false;
    final pending = state.debugRunMessageLongPressPopoverActionByIcon(
      message,
      Icons.bookmark_outline,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(favoriteCalls, hasLength(1));
    expect(favoriteCalls.single.text, 'favorite me');
    expect(favoriteCalls.single.chatId, _peerId);
    expect(favoriteCalls.single.msgId, message.id);

    favoriteCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for location-favorite popover actions before returning',
      (tester) async {
    final locationCalls = <({
      double lat,
      double lon,
      String? label,
      String? chatId,
      String? msgId
    })>[];
    final locationCompleter = Completer<void>();
    final message = _buildDirectMessage(
      id: 'msg-popover-location-favorite-001',
      payload: <String, Object?>{
        'text': 'Cafe',
        'kind': 'location',
        'lat': 36.8065,
        'lon': 10.1815,
        'client_ts': DateTime.utc(2026, 3, 20, 10, 5, 0).toIso8601String(),
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      addFavoriteLocationQuickOverride: (lat, lon, label, chatId, msgId) async {
        locationCalls.add((
          lat: lat,
          lon: lon,
          label: label,
          chatId: chatId,
          msgId: msgId,
        ));
        await locationCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[message],
    );

    var completed = false;
    final pending = state.debugRunMessageLongPressPopoverActionByIcon(
      message,
      Icons.place_outlined,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(locationCalls, hasLength(1));
    expect(locationCalls.single.lat, closeTo(36.8065, 0.00001));
    expect(locationCalls.single.lon, closeTo(10.1815, 0.00001));
    expect(locationCalls.single.label, 'Cafe');
    expect(locationCalls.single.chatId, _peerId);
    expect(locationCalls.single.msgId, message.id);

    locationCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage waits for translate popover actions before returning',
      (tester) async {
    final translatedTexts = <String>[];
    final translateCompleter = Completer<void>();
    final message = _buildDirectMessage(
      id: 'msg-popover-translate-001',
      text: 'translate me',
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      translateMessageOverride: (text) async {
        translatedTexts.add(text);
        await translateCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[message],
    );

    var completed = false;
    final pending = state.debugRunMessageLongPressPopoverActionByIcon(
      message,
      Icons.translate,
    );
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(translatedTexts, <String>['translate me']);

    translateCompleter.complete();
    await pending;
    expect(completed, isTrue);
  });

  testWidgets(
      'ShamellChatPage starts thread-open read acknowledgements through the dedicated detached seam',
      (tester) async {
    final store = ChatLocalStore();
    const otherPeerId = 'peer-2';
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
    );
    final incomingA = ChatMessage(
      id: 'msg-thread-read-001',
      senderId: otherPeerId,
      recipientId: _meId,
      senderPubKeyB64: otherPeer.publicKeyB64,
      nonceB64: '',
      boxB64: base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{'text': 'incoming a'})),
      ),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 0, 1),
    );
    final outgoing = ChatMessage(
      id: 'msg-thread-read-002',
      senderId: _meId,
      recipientId: otherPeerId,
      senderPubKeyB64: _curveKeyB64(1),
      nonceB64: '',
      boxB64: base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{'text': 'outgoing'})),
      ),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 0, 2),
    );
    final incomingB = ChatMessage(
      id: 'msg-thread-read-003',
      senderId: otherPeerId,
      recipientId: _meId,
      senderPubKeyB64: otherPeer.publicKeyB64,
      nonceB64: '',
      boxB64: base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{'text': 'incoming b'})),
      ),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 0, 3),
    );
    await store.saveMessages(
      otherPeerId,
      <ChatMessage>[incomingA, outgoing, incomingB],
      baseUrlOverride: _baseUrl,
    );

    final ackedMessageIds = <String>[];
    final ackCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectReadAckOverride: (messageId) async {
        ackedMessageIds.add(messageId);
        await ackCompleter.future;
      },
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    var completed = false;
    final pending = state.debugSwitchPeer(otherPeer);
    unawaited(pending.then((_) => completed = true));
    await tester.pump();

    expect(completed, isTrue);
    expect(
      ackedMessageIds,
      <String>[
        incomingA.id,
        incomingB.id,
      ],
    );

    ackCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage starts live direct read acknowledgements through the dedicated detached seam',
      (tester) async {
    final ackedMessageIds = <String>[];
    final ackCompleter = Completer<void>();
    final blockedPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Blocked Peer',
      blocked: true,
    );
    final groupKeyMessage = ChatMessage(
      id: 'msg-live-read-group-key-001',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'kind': 'group_key',
            'group_id': _groupId,
            'key_b64': 'AQ==',
          }),
        ),
      ),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 0, 1),
    );
    final blockedMessage = ChatMessage(
      id: 'msg-live-read-blocked-001',
      senderId: blockedPeer.id,
      recipientId: _meId,
      senderPubKeyB64: blockedPeer.publicKeyB64,
      nonceB64: '',
      boxB64: base64Encode(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'text': 'blocked message',
          }),
        ),
      ),
      trustedLocalPlaintext: true,
      createdAt: DateTime.utc(2026, 3, 20, 10, 0, 2),
    );
    final activeMessage = _buildDirectMessage(
      id: 'msg-live-read-active-001',
      text: 'active message',
      createdAt: DateTime.utc(2026, 3, 20, 10, 0, 3),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectReadAckOverride: (messageId) async {
        ackedMessageIds.add(messageId);
        await ackCompleter.future;
      },
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    state.debugSeedContacts(<ChatContact>[_buildPeer(), blockedPeer]);

    state.debugMergeDirectMessages(<ChatMessage>[
      groupKeyMessage,
      blockedMessage,
      activeMessage,
    ]);
    await tester.pump();

    expect(
      ackedMessageIds,
      <String>[
        groupKeyMessage.id,
        blockedMessage.id,
        activeMessage.id,
      ],
    );
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 1),
    );

    ackCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage starts live direct message saves through the dedicated detached seam',
      (tester) async {
    final savedMessageCalls = <({String peerId, List<ChatMessage> messages})>[];
    final saveCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectMessageSaveOverride: (peerId, messages) async {
        savedMessageCalls.add((
          peerId: peerId,
          messages: List<ChatMessage>.from(messages),
        ));
        await saveCompleter.future;
      },
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());

    final freshMessage = _buildDirectMessage(
      id: 'msg-live-save-001',
      text: 'fresh save seam',
      createdAt: DateTime.utc(2026, 3, 20, 10, 5, 0),
    );

    state.debugMergeDirectMessages(<ChatMessage>[freshMessage]);
    await tester.pump();

    expect(savedMessageCalls, hasLength(1));
    expect(savedMessageCalls.single.peerId, _peerId);
    expect(
      savedMessageCalls.single.messages.map((message) => message.id).toList(),
      <String>[freshMessage.id],
    );
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 1),
    );

    saveCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage persists live direct merges through the shared pruned message seam',
      (tester) async {
    final savedMessageCalls = <({String peerId, List<ChatMessage> messages})>[];
    final saveMessagesCompleter = Completer<void>();
    final store = ChatLocalStore();
    final now = DateTime.now().toUtc();
    final expiredMessage = ChatMessage(
      id: 'msg-live-expired-001',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('expired')),
      trustedLocalPlaintext: true,
      createdAt: now.subtract(const Duration(hours: 2)),
    );
    final freshMessage = ChatMessage(
      id: 'msg-live-expired-002',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('fresh')),
      trustedLocalPlaintext: true,
      createdAt: now.subtract(const Duration(minutes: 5)),
    );
    final disappearingPeer = _buildPeer().copyWith(
      disappearing: true,
      disappearAfter: const Duration(minutes: 30),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveMessagesForPeerOverride: (peerId, messages) async {
        savedMessageCalls.add((
          peerId: peerId,
          messages: List<ChatMessage>.from(messages),
        ));
        await saveMessagesCompleter.future;
      },
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: disappearingPeer,
      messages: <ChatMessage>[expiredMessage],
    );

    state.debugMergeDirectMessages(<ChatMessage>[freshMessage]);
    await tester.pump();

    expect(savedMessageCalls, hasLength(1));
    expect(savedMessageCalls.single.peerId, _peerId);
    expect(
      savedMessageCalls.single.messages.map((message) => message.id).toList(),
      <String>[freshMessage.id],
    );
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 1),
    );
    final storedMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    expect(storedMessages, isEmpty);

    saveMessagesCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage toggles direct unread through the targeted peer contract',
      (tester) async {
    final unreadCalls = <({String peerId, int unreadCount})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForPeerOverride: (peerId, unreadCount) async {
        unreadCalls.add((peerId: peerId, unreadCount: unreadCount));
      },
    );

    state.debugSeedUnread(<String, int>{
      'peer-2': 5,
      'grp:$_groupId': 3,
    });

    await state.debugToggleChatReadUnread(_buildPeer());
    await tester.pump();

    expect(
      unreadCalls,
      <({String peerId, int unreadCount})>[
        (peerId: _peerId, unreadCount: -1),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: -1,
        'peer-2': 5,
        'grp:$_groupId': 3,
      },
    );
  });

  testWidgets(
      'ShamellChatPage deletes direct unread through the targeted peer contract',
      (tester) async {
    final unreadCalls = <({String peerId, int unreadCount})>[];
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForPeerOverride: (peerId, unreadCount) async {
        unreadCalls.add((peerId: peerId, unreadCount: unreadCount));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
    });

    await state.debugDeleteChatById(_peerId);
    await tester.pump();

    expect(
      unreadCalls,
      <({String peerId, int unreadCount})>[
        (peerId: _peerId, unreadCount: 0),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        'peer-2': 5,
        'grp:$_groupId': 3,
      },
    );
    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{'peer-2'},
    );
  });

  testWidgets(
      'ShamellChatPage starts live direct contact auto-unarchive through the dedicated detached seam',
      (tester) async {
    final unarchivedContacts = <ChatContact>[];
    final unarchiveCompleter = Completer<void>();
    const archivedPeerId = 'peer-2';
    final archivedPeer = ChatContact(
      id: archivedPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
      archived: true,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectContactUnarchiveOverride: (contact) async {
        unarchivedContacts.add(contact);
        await unarchiveCompleter.future;
      },
    );
    state.debugSeedContacts(<ChatContact>[_buildPeer(), archivedPeer]);

    state.debugMergeDirectMessages(<ChatMessage>[
      ChatMessage(
        id: 'msg-live-contact-unarchive-001',
        senderId: archivedPeerId,
        recipientId: _meId,
        senderPubKeyB64: archivedPeer.publicKeyB64,
        nonceB64: '',
        boxB64: base64Encode(utf8.encode('fresh archived peer')),
        trustedLocalPlaintext: true,
        createdAt: DateTime.utc(2026, 3, 20, 10, 2, 0),
      ),
    ]);
    await tester.pump();

    expect(unarchivedContacts, hasLength(1));
    expect(unarchivedContacts.single.id, archivedPeerId);
    expect(unarchivedContacts.single.archived, isFalse);
    expect(state.debugIsPeerArchived(archivedPeerId), isFalse);
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        archivedPeerId: 1,
      },
    );

    unarchiveCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage starts live direct unread batch saves through the dedicated detached seam',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    const otherPeerId = 'peer-2';
    final archivedOtherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
      archived: true,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false),
        ));
        await unreadBatchCompleter.future;
      },
    );
    state.debugSeedContacts(<ChatContact>[_buildPeer(), archivedOtherPeer]);
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      otherPeerId: 5,
      'grp:$_groupId': 3,
    });

    state.debugMergeDirectMessages(<ChatMessage>[
      ChatMessage(
        id: 'msg-live-unread-batch-001',
        senderId: otherPeerId,
        recipientId: _meId,
        senderPubKeyB64: archivedOtherPeer.publicKeyB64,
        nonceB64: '',
        boxB64: base64Encode(utf8.encode('fresh')),
        trustedLocalPlaintext: true,
        createdAt: DateTime.utc(2026, 3, 20, 10, 3, 0),
      ),
    ]);
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>[otherPeerId]);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 7,
        otherPeerId: 6,
        'grp:$_groupId': 3,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        otherPeerId: 6,
        'grp:$_groupId': 3,
      },
    );
    expect(state.debugIsPeerArchived(otherPeerId), isFalse);

    unreadBatchCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage persists live direct unread updates through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final store = ChatLocalStore();
    const otherPeerId = 'peer-2';
    const storeOnlyPeerId = 'peer-3';
    final archivedOtherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
      archived: true,
    );
    final storeOnlyPeer = ChatContact(
      id: storeOnlyPeerId,
      publicKeyB64: _curveKeyB64(51),
      fingerprint: 'fp-peer-3',
      name: 'Peer Three',
      archived: true,
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), archivedOtherPeer, storeOnlyPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false),
        ));
      },
    );
    state.debugSeedContacts(<ChatContact>[_buildPeer(), archivedOtherPeer]);

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      otherPeerId: 5,
      'grp:$_groupId': 3,
    });

    state.debugMergeDirectMessages(<ChatMessage>[
      ChatMessage(
        id: 'msg-live-001',
        senderId: otherPeerId,
        recipientId: _meId,
        senderPubKeyB64: _curveKeyB64(41),
        nonceB64: '',
        boxB64: base64Encode(utf8.encode('fresh')),
        trustedLocalPlaintext: true,
        createdAt: DateTime.utc(2026, 3, 20, 10, 0, 0),
      ),
    ]);
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>[otherPeerId]);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 7,
        otherPeerId: 6,
        'grp:$_groupId': 3,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        otherPeerId: 6,
        'grp:$_groupId': 3,
      },
    );
    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedOtherPeer =
        storedContacts.firstWhere((c) => c.id == otherPeerId);
    final preservedPeer =
        storedContacts.firstWhere((c) => c.id == storeOnlyPeerId);
    expect(updatedOtherPeer.archived, isFalse);
    expect(preservedPeer.archived, isTrue);
  });

  testWidgets(
      'ShamellChatPage keeps redacted outgoing sealed live messages out of unread counts for background peers',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final ackedMessageIds = <String>[];
    const otherPeerId = 'peer-2';
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(41),
      fingerprint: 'fp-peer-2',
      name: 'Peer Two',
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectReadAckOverride: (messageId) async {
        ackedMessageIds.add(messageId);
      },
      startLiveDirectUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false),
        ));
      },
    );
    state.debugSeedContacts(<ChatContact>[_buildPeer(), otherPeer]);
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      otherPeerId: 5,
      'grp:$_groupId': 3,
    });

    state.debugMergeDirectMessages(<ChatMessage>[
      ChatMessage(
        id: 'msg-live-redacted-outgoing-background-001',
        senderId: '',
        recipientId: otherPeerId,
        senderPubKeyB64: '',
        nonceB64: 'AQ==',
        boxB64: 'Ag==',
        sealedSender: true,
        senderHint: _buildMe().fingerprint,
        createdAt: DateTime.utc(2026, 3, 20, 10, 4, 0),
      ),
    ]);
    await tester.pump();

    expect(ackedMessageIds, isEmpty);
    expect(unreadBatchCalls, isEmpty);
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        otherPeerId: 5,
        'grp:$_groupId': 3,
      },
    );
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 0),
    );
    expect(
      state.debugBootstrapState(),
      containsPair('cachedMessageCount', 1),
    );
  });

  testWidgets(
      'ShamellChatPage merges redacted outgoing sealed live messages into the active thread without read ack',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final ackedMessageIds = <String>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectReadAckOverride: (messageId) async {
        ackedMessageIds.add(messageId);
      },
      startLiveDirectUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false),
        ));
      },
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 4,
    });

    state.debugMergeDirectMessages(<ChatMessage>[
      ChatMessage(
        id: 'msg-live-redacted-outgoing-active-001',
        senderId: '',
        recipientId: _peerId,
        senderPubKeyB64: '',
        nonceB64: 'AQ==',
        boxB64: 'Ag==',
        sealedSender: true,
        senderHint: _buildMe().fingerprint,
        createdAt: DateTime.utc(2026, 3, 20, 10, 5, 0),
      ),
    ]);
    await tester.pump();

    expect(ackedMessageIds, isEmpty);
    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>[_peerId]);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{_peerId: 0},
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{_peerId: 0},
    );
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 1),
    );
    expect(
      state.debugBootstrapState(),
      containsPair('cachedMessageCount', 1),
    );
  });

  testWidgets(
      'ShamellChatPage starts live direct contact upserts through the dedicated detached seam',
      (tester) async {
    final upsertedContacts = <ChatContact>[];
    final upsertCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startLiveDirectContactUpsertOverride: (contact) async {
        upsertedContacts.add(contact);
        await upsertCompleter.future;
      },
    );
    state.debugSeedContacts(<ChatContact>[_buildPeer()]);

    final newPeerPublicKey = _curveKeyB64(41);
    state.debugMergeDirectMessages(<ChatMessage>[
      ChatMessage(
        id: 'msg-live-contact-upsert-001',
        senderId: 'peer-2',
        recipientId: _meId,
        senderPubKeyB64: newPeerPublicKey,
        nonceB64: '',
        boxB64: base64Encode(utf8.encode('fresh unknown peer')),
        trustedLocalPlaintext: true,
        createdAt: DateTime.utc(2026, 3, 20, 10, 1, 0),
      ),
    ]);
    await tester.pump();

    expect(upsertedContacts, hasLength(1));
    expect(upsertedContacts.single.id, 'peer-2');
    expect(upsertedContacts.single.publicKeyB64, newPeerPublicKey);
    expect(
      state.debugBootstrapState(),
      containsPair('contactCount', 2),
    );

    upsertCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage upserts an unknown live peer through the targeted peer contact contract',
      (tester) async {
    final store = ChatLocalStore();
    const newPeerId = 'peer-2';
    const storeOnlyPeerId = 'peer-3';
    final storeOnlyPeer = ChatContact(
      id: storeOnlyPeerId,
      publicKeyB64: _curveKeyB64(51),
      fingerprint: 'fp-peer-3',
      name: 'Peer Three',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), storeOnlyPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );
    state.debugSeedContacts(<ChatContact>[_buildPeer()]);

    final newPeerPublicKey = _curveKeyB64(41);
    state.debugMergeDirectMessages(<ChatMessage>[
      ChatMessage(
        id: 'msg-live-unknown-001',
        senderId: newPeerId,
        recipientId: _meId,
        senderPubKeyB64: newPeerPublicKey,
        nonceB64: '',
        boxB64: base64Encode(utf8.encode('fresh unknown peer')),
        trustedLocalPlaintext: true,
        createdAt: DateTime.utc(2026, 3, 20, 10, 1, 0),
      ),
    ]);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final newPeer = storedContacts.firstWhere((c) => c.id == newPeerId);
    final preservedPeer =
        storedContacts.firstWhere((c) => c.id == storeOnlyPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, newPeerId, storeOnlyPeerId},
    );
    expect(newPeer.publicKeyB64, newPeerPublicKey);
    expect(newPeer.fingerprint, fingerprintForKey(newPeerPublicKey));
    expect(preservedPeer.publicKeyB64, _curveKeyB64(51));
  });

  testWidgets(
      'ShamellChatPage marks selected chats read through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2', 'group-3'},
      mentionAllUnread: <String>{_groupId, 'group-3'},
    );
    state.debugSeedSelectedChatIds(<String>[
      _peerId,
      'grp:$_groupId',
    ]);

    await state.debugMarkSelectedChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'grp:$_groupId']..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 5,
        'grp:$_groupId': 0,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 5,
        'grp:$_groupId': 0,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{'group-2', 'group-3'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{'group-3'},
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      '2026-03-17T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );
  });

  testWidgets(
      'ShamellChatPage marks selected contacts read through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2'},
      mentionAllUnread: <String>{_groupId, 'group-2'},
    );
    state.debugSeedSelectedChatIds(<String>[_peerId]);

    await state.debugMarkSelectedChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>[_peerId]);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 5,
        'grp:$_groupId': 3,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 5,
        'grp:$_groupId': 3,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{_groupId, 'group-2'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{_groupId, 'group-2'},
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      '2026-03-18T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      '2026-03-17T00:00:00Z',
    );
  });

  testWidgets(
      'ShamellChatPage marks selected groups read through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedSelectedChatIds(<String>['grp:$_groupId']);

    await state.debugMarkSelectedChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>['grp:$_groupId']);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 0,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 0,
        'grp:group-2': 4,
      },
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      '2026-03-17T00:00:00Z',
    );
  });

  testWidgets(
      'ShamellChatPage clears selected group mentions while marking selected chats read',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2'},
      mentionAllUnread: <String>{_groupId, 'group-2'},
    );
    state.debugSeedSelectedChatIds(<String>['grp:$_groupId']);

    await state.debugMarkSelectedChatsRead();
    await tester.pump();

    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 0,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{'group-2'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage clears only selected group mentions during mixed mark-selected-read',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2'},
      mentionAllUnread: <String>{_groupId, 'group-2'},
    );
    state.debugSeedSelectedChatIds(<String>[
      _peerId,
      'grp:$_groupId',
    ]);

    await state.debugMarkSelectedChatsRead();
    await tester.pump();

    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'grp:$_groupId': 0,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{'group-2'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage keeps group mentions unchanged during contact-only mark-selected-read',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2'},
      mentionAllUnread: <String>{_groupId, 'group-2'},
    );
    state.debugSeedSelectedChatIds(<String>[_peerId]);

    await state.debugMarkSelectedChatsRead();
    await tester.pump();

    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'grp:$_groupId': 3,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{_groupId, 'group-2'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{_groupId, 'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage waits for mark-all-read persistence before closing the chats menu',
      (tester) async {
    final unreadBatchCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        await unreadBatchCompleter.future;
      },
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
    });

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Mark all as read'), findsOneWidget);

    await tester.tap(find.text('Mark all as read'));
    await tester.pump();

    expect(find.text('Mark all as read'), findsOneWidget);
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
      },
    );

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Mark all as read'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage clears group mentions immediately on the chats-menu mark-all-read path',
      (tester) async {
    final unreadBatchCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        await unreadBatchCompleter.future;
      },
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2'},
      mentionAllUnread: <String>{'group-2'},
    );

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Mark all as read'), findsOneWidget);

    await tester.tap(find.text('Mark all as read'));
    await tester.pump();

    expect(find.text('Mark all as read'), findsOneWidget);
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
      },
    );
    expect(state.debugGroupMentionUnreadSnapshot(), isEmpty);
    expect(state.debugGroupMentionAllUnreadSnapshot(), isEmpty);

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;
  });

  testWidgets(
      'ShamellChatPage updates group seen state on the chats-menu mark-all-read path',
      (tester) async {
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        await unreadBatchCompleter.future;
      },
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Mark all as read'), findsOneWidget);

    await tester.tap(find.text('Mark all as read'));
    await tester.pump();

    expect(find.text('Mark all as read'), findsOneWidget);
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;
  });

  testWidgets(
      'ShamellChatPage clears mentions after positive group-seen updates on the chats-menu mark-all-read path',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2', 'group-3'},
      mentionAllUnread: <String>{'group-2', 'group-3'},
    );

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Mark all as read'), findsOneWidget);

    await tester.tap(find.text('Mark all as read'));
    await tester.pump();

    expect(find.text('Mark all as read'), findsOneWidget);
    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'peer-2', 'grp:$_groupId', 'grp:group-2', 'grp:group-3']
        ..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(state.debugGroupMentionUnreadSnapshot(), isEmpty);
    expect(state.debugGroupMentionAllUnreadSnapshot(), isEmpty);
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;
  });

  testWidgets(
      'ShamellChatPage skips negative group-seen sentinels on the chats-menu mark-all-read path',
      (tester) async {
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        await unreadBatchCompleter.future;
      },
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': -1,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Mark all as read'), findsOneWidget);

    await tester.tap(find.text('Mark all as read'));
    await tester.pump();

    expect(find.text('Mark all as read'), findsOneWidget);
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      '2026-03-18T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;
  });

  testWidgets(
      'ShamellChatPage clears group mentions for negative sentinels on the chats-menu mark-all-read path',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': -1,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2', 'group-3'},
      mentionAllUnread: <String>{_groupId, 'group-2'},
    );

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Mark all as read'), findsOneWidget);

    await tester.tap(find.text('Mark all as read'));
    await tester.pump();

    expect(find.text('Mark all as read'), findsOneWidget);
    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'peer-2', 'grp:$_groupId', 'grp:group-2', 'grp:group-3']
        ..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(state.debugGroupMentionUnreadSnapshot(), isEmpty);
    expect(state.debugGroupMentionAllUnreadSnapshot(), isEmpty);
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      '2026-03-18T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;
  });

  testWidgets(
      'ShamellChatPage waits for notify-preview persistence before closing the chats menu',
      (tester) async {
    final previewPersistCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveNotifyPreviewOverride: (enabled) async {
        await previewPersistCompleter.future;
      },
    );

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Enable message previews'), findsOneWidget);

    await tester.tap(find.text('Enable message previews'));
    await tester.pump();

    expect(find.text('Enable message previews'), findsOneWidget);
    expect(state.debugNotifyPreviewEnabled(), isTrue);

    previewPersistCompleter.complete();
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Enable message previews'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits notify-preview reset before closing the chats menu',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    final enableSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Enable message previews'), findsOneWidget);

    await tester.tap(find.text('Enable message previews'));
    await tester.pumpAndSettle();
    await enableSheetFuture;

    expect(state.debugNotifyPreviewEnabled(), isTrue);

    final disableSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Disable message previews'), findsOneWidget);

    await tester.tap(find.text('Disable message previews'));
    await tester.pump();

    expect(state.debugNotifyPreviewEnabled(), isFalse);

    await tester.pumpAndSettle();
    await disableSheetFuture;

    expect(find.text('Disable message previews'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits hidden-chats reset before closing the chats menu',
      (tester) async {
    final hiddenPeer = _buildPeer().copyWith(hidden: true);
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      authenticateHiddenChatsOverride: () async => true,
    );
    state.debugSeedContacts(<ChatContact>[hiddenPeer]);

    final showSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show locked chats (requires auth)'));
    await tester.pumpAndSettle();
    await showSheetFuture;

    expect(state.debugShowHiddenEnabled(), isTrue);

    final hideSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Hide locked chats'), findsOneWidget);

    await tester.tap(find.text('Hide locked chats'));
    await tester.pump();

    expect(state.debugShowHiddenEnabled(), isFalse);

    await tester.pumpAndSettle();
    await hideSheetFuture;

    expect(find.text('Hide locked chats'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for hidden-chats auth before closing the chats menu',
      (tester) async {
    final authCompleter = Completer<bool>();
    final hiddenPeer = _buildPeer().copyWith(hidden: true);
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      authenticateHiddenChatsOverride: () async {
        return await authCompleter.future;
      },
    );
    state.debugSeedContacts(<ChatContact>[hiddenPeer]);

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Show locked chats (requires auth)'), findsOneWidget);

    await tester.tap(find.text('Show locked chats (requires auth)'));
    await tester.pump();

    expect(find.text('Show locked chats (requires auth)'), findsOneWidget);
    expect(state.debugShowHiddenEnabled(), isFalse);

    authCompleter.complete(true);
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugShowHiddenEnabled(), isTrue);
    expect(find.text('Show locked chats (requires auth)'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits blocked-chats reset before closing the chats menu',
      (tester) async {
    final blockedPeer = _buildPeer().copyWith(blocked: true);
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );
    state.debugSeedContacts(<ChatContact>[blockedPeer]);

    final showSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show blocked chats'));
    await tester.pumpAndSettle();
    await showSheetFuture;

    expect(state.debugShowBlockedEnabled(), isTrue);

    final hideSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Hide blocked chats'), findsOneWidget);

    await tester.tap(find.text('Hide blocked chats'));
    await tester.pump();

    expect(state.debugShowBlockedEnabled(), isFalse);

    await tester.pumpAndSettle();
    await hideSheetFuture;

    expect(find.text('Hide blocked chats'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits blocked-chats visibility before closing the chats menu',
      (tester) async {
    final blockedPeer = _buildPeer().copyWith(blocked: true);
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );
    state.debugSeedContacts(<ChatContact>[blockedPeer]);

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Show blocked chats'), findsOneWidget);

    await tester.tap(find.text('Show blocked chats'));
    await tester.pump();

    expect(state.debugShowBlockedEnabled(), isTrue);

    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Show blocked chats'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits selection mode before closing the chats menu',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pump();

    expect(state.debugSelectionModeEnabled(), isTrue);

    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(find.text('Selection'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits selection reset before closing the chats menu',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    final showSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await showSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);

    final hideSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Exit selection'), findsOneWidget);

    await tester.tap(find.text('Exit selection'));
    await tester.pump();

    expect(state.debugSelectionModeEnabled(), isFalse);

    await tester.pumpAndSettle();
    await hideSheetFuture;

    expect(find.text('Selection'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits selection-bar cancel before clearing the selection UI',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[_buildPeer()],
    );
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Cancel (0)'), findsOneWidget);

    await tester.tap(find.text('Cancel (0)'));
    await tester.pump();

    expect(state.debugSelectionModeEnabled(), isFalse);

    await tester.pumpAndSettle();

    expect(find.text('Cancel (0)'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits selection-bar mark-read state before the batch write settles',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-bar',
          text: 'Unread message',
        ),
      ],
    );
    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[_buildPeer()],
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2'},
      mentionAllUnread: <String>{_groupId, 'group-2'},
    );
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);

    expect(find.text('Peer'), findsOneWidget);

    await tester.tap(find.text('Peer'));
    await tester.pump();

    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);

    await tester.tap(find.text('Mark read'));
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>[_peerId]);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'grp:$_groupId': 3,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'grp:$_groupId': 3,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{_groupId, 'group-2'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{_groupId, 'group-2'},
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      '2026-03-18T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      '2026-03-17T00:00:00Z',
    );
    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Cancel (1)'), findsOneWidget);

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'ShamellChatPage commits mixed selection-bar mark-read state before the batch write settles',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );
    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    const otherGroup = ChatGroup(
      id: 'group-2',
      name: 'Other Group',
      creatorId: _meId,
      memberCount: 2,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-mixed-mark-read-peer',
          text: 'mixed unread peer',
        ),
      ],
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: otherPeer,
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-mixed-mark-read-other-peer',
          senderId: otherPeer.id,
          recipientId: _meId,
          text: 'other unread peer',
          createdAt: DateTime.utc(2026, 3, 20, 10, 13, 0),
        ),
      ],
    );
    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[_buildPeer(), otherPeer],
      groups: <ChatGroup>[_buildGroup(), otherGroup],
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedGroupThread(
      group: otherGroup,
      messages: <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_mark_read',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other unread group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 14, 0),
        ),
      ],
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      otherPeer.id: 5,
      'grp:$_groupId': 3,
      'grp:${otherGroup.id}': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, otherGroup.id, 'group-3'},
      mentionAllUnread: <String>{_groupId, 'group-3'},
    );
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('Security Group'), findsOneWidget);

    await tester.tap(find.text('Peer'));
    await tester.pump();
    await tester.tap(find.text('Security Group'));
    await tester.pump();

    expect(find.text('Cancel (2)'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);

    await tester.tap(find.text('Mark read'));
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'grp:$_groupId']..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        otherPeer.id: 5,
        'grp:$_groupId': 0,
        'grp:${otherGroup.id}': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        otherPeer.id: 5,
        'grp:$_groupId': 0,
        'grp:${otherGroup.id}': 4,
      },
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{otherGroup.id, 'group-3'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{'group-3'},
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup(otherGroup.id,
          baseUrlOverride: _baseUrl),
      '2026-03-17T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );
    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Cancel (2)'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'ShamellChatPage commits selection-bar group mark-read state before the batch write settles',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );
    const otherGroup = ChatGroup(
      id: 'group-2',
      name: 'Other Group',
      creatorId: _meId,
      memberCount: 2,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugShowChatsList(
      me: _buildMe(),
      groups: <ChatGroup>[_buildGroup(), otherGroup],
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedGroupThread(
      group: otherGroup,
      messages: <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_selection_mark_read_other',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other selection unread group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 16, 0),
        ),
      ],
    );
    state.debugSeedUnread(<String, int>{
      'grp:$_groupId': 3,
      'grp:${otherGroup.id}': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, otherGroup.id, 'group-3'},
      mentionAllUnread: <String>{_groupId, 'group-3'},
    );
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Security Group'), findsOneWidget);

    await tester.tap(find.text('Security Group'));
    await tester.pump();

    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);

    await tester.tap(find.text('Mark read'));
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>['grp:$_groupId']);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{'grp:$_groupId': 0, 'grp:${otherGroup.id}': 4},
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{'grp:$_groupId': 0, 'grp:${otherGroup.id}': 4},
    );
    expect(
      state.debugGroupMentionUnreadSnapshot(),
      <String>{otherGroup.id, 'group-3'},
    );
    expect(
      state.debugGroupMentionAllUnreadSnapshot(),
      <String>{'group-3'},
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup(otherGroup.id,
          baseUrlOverride: _baseUrl),
      '2026-03-17T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );
    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'ShamellChatPage waits for selection-bar unarchive persistence before clearing the archived UI state',
      (tester) async {
    final saveContactsCalls = <List<ChatContact>>[];
    final saveContactsCompleter = Completer<void>();
    final store = ChatLocalStore();
    final archivedPeer = _buildPeer().copyWith(archived: true);
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_contact_unarchive_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      'peer-2',
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_contact_unarchive_other',
          senderId: 'peer-2',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveContactsForPeersOverride: (contacts) async {
        saveContactsCalls.add(List<ChatContact>.from(contacts));
        await saveContactsCompleter.future;
      },
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: archivedPeer,
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-unarchive',
          text: 'Archived message',
        ),
      ],
    );
    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[archivedPeer],
      showArchived: true,
    );
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(state.debugIsPeerArchived(_peerId), isTrue);
    expect(find.text('Unarchive'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(find.text('Cancel (1)'), findsOneWidget);

    await tester.tap(find.text('Unarchive'));
    await tester.pump();

    expect(saveContactsCalls, hasLength(1));
    expect(saveContactsCalls.single, hasLength(1));
    expect(saveContactsCalls.single.single.id, _peerId);
    expect(saveContactsCalls.single.single.archived, isFalse);
    final persistedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final persistedOtherMessages = await store.loadMessages(
      'peer-2',
      baseUrlOverride: _baseUrl,
    );
    expect(
      persistedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_contact_unarchive_target'],
    );
    expect(
      persistedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_contact_unarchive_other'],
    );
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(state.debugIsPeerArchived(_peerId), isTrue);
    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Unarchive'), findsOneWidget);

    saveContactsCompleter.complete();
    await tester.pumpAndSettle();

    expect(state.debugSelectionModeEnabled(), isFalse);
    expect(state.debugIsPeerArchived(_peerId), isFalse);
    expect(find.text('Cancel (1)'), findsNothing);
    expect(find.text('Unarchive'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage commits selection-bar archived-group unarchive state before the group write settles',
      (tester) async {
    final archivedCalls = <({String groupId, bool archived})>[];
    Completer<void>? archivePersistCompleter;
    final store = ChatLocalStore();
    const otherGroup = ChatGroup(
      id: 'group-2',
      name: 'Other Group',
      creatorId: _meId,
      memberCount: 2,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_group_unarchive_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      'peer-2',
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_group_unarchive_other',
          senderId: 'peer-2',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      otherGroup.id,
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
        final completer = archivePersistCompleter;
        if (completer != null) {
          await completer.future;
        }
      },
    );

    state.debugShowChatsList(
      me: _buildMe(),
      groups: <ChatGroup>[_buildGroup(), otherGroup],
      showArchived: true,
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedGroupThread(
      group: otherGroup,
      messages: <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_archived',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other archived group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 5, 0),
        ),
      ],
    );
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived(otherGroup.id, true);
    archivedCalls.clear();
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Security Group'), findsOneWidget);
    expect(find.text('Other Group'), findsOneWidget);
    expect(find.text('Unarchive'), findsOneWidget);

    await tester.tap(find.text('Security Group'));
    await tester.pump();

    expect(find.text('Cancel (1)'), findsOneWidget);

    archivePersistCompleter = Completer<void>();

    await tester.tap(find.text('Unarchive'));
    await tester.pump();

    expect(
      archivedCalls,
      <({String groupId, bool archived})>[
        (groupId: _groupId, archived: false),
      ],
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{otherGroup.id},
    );
    final persistedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final persistedOtherMessages = await store.loadMessages(
      'peer-2',
      baseUrlOverride: _baseUrl,
    );
    expect(
      persistedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_group_unarchive_target'],
    );
    expect(
      persistedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_group_unarchive_other'],
    );
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey(otherGroup.id, baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(state.debugSelectionModeEnabled(), isFalse);
    expect(find.text('Security Group'), findsNothing);
    expect(find.text('Other Group'), findsOneWidget);
    expect(find.text('Cancel (1)'), findsNothing);
    expect(find.text('Unarchive'), findsNothing);

    archivePersistCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'ShamellChatPage commits mixed selection-bar unarchive state before the group write settles',
      (tester) async {
    final saveContactsCalls = <List<ChatContact>>[];
    final archivedCalls = <({String groupId, bool archived})>[];
    Completer<void>? archivePersistCompleter;
    final store = ChatLocalStore();
    final archivedPeer = _buildPeer().copyWith(archived: true);
    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
      archived: true,
    );
    const otherGroup = ChatGroup(
      id: 'group-2',
      name: 'Other Group',
      creatorId: _meId,
      memberCount: 2,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_mixed_unarchive_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      otherPeer.id,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_mixed_unarchive_other',
          senderId: otherPeer.id,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      otherGroup.id,
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveContactsForPeersOverride: (contacts) async {
        saveContactsCalls.add(List<ChatContact>.from(contacts));
      },
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
        final completer = archivePersistCompleter;
        if (completer != null) {
          await completer.future;
        }
      },
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: archivedPeer,
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-mixed-unarchive-peer',
          text: 'mixed archived peer',
        ),
      ],
    );
    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[archivedPeer, otherPeer],
      groups: <ChatGroup>[_buildGroup(), otherGroup],
      showArchived: true,
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedGroupThread(
      group: otherGroup,
      messages: <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_mixed_unarchive',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other archived group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 15, 0),
        ),
      ],
    );
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived(otherGroup.id, true);
    archivedCalls.clear();
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('Security Group'), findsOneWidget);

    await tester.tap(find.text('Peer'));
    await tester.pump();
    await tester.tap(find.text('Security Group'));
    await tester.pump();

    expect(find.text('Cancel (2)'), findsOneWidget);
    expect(find.text('Unarchive'), findsOneWidget);

    await tester.tap(find.text('Unarchive'));
    await tester.pump();

    archivePersistCompleter = Completer<void>();

    expect(saveContactsCalls, hasLength(1));
    expect(saveContactsCalls.single, hasLength(1));
    expect(saveContactsCalls.single.single.id, _peerId);
    expect(saveContactsCalls.single.single.archived, isFalse);
    expect(
      archivedCalls,
      <({String groupId, bool archived})>[
        (groupId: _groupId, archived: false),
      ],
    );
    expect(state.debugIsPeerArchived(_peerId), isFalse);
    expect(state.debugIsPeerArchived(otherPeer.id), isTrue);
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{otherGroup.id},
    );
    final persistedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final persistedOtherMessages = await store.loadMessages(
      otherPeer.id,
      baseUrlOverride: _baseUrl,
    );
    expect(
      persistedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_mixed_unarchive_target'],
    );
    expect(
      persistedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_mixed_unarchive_other'],
    );
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey(otherGroup.id, baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(state.debugSelectionModeEnabled(), isFalse);
    expect(find.text('Cancel (2)'), findsNothing);
    expect(find.text('Unarchive'), findsNothing);

    archivePersistCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'ShamellChatPage waits for selection-bar delete persistence before clearing the selection UI',
      (tester) async {
    final removeContactCalls = <List<String>>[];
    final removeContactsCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_delete_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      'peer-2',
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_delete_other',
          senderId: 'peer-2',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[_buildGroupMessage()],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      'group-2',
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_selection_delete_other',
          groupId: 'group-2',
          senderId: _meId,
          text: 'other group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 10, 0),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      removeContactsForPeersOverride: (peerIds) async {
        removeContactCalls.add(
          peerIds.toList(growable: false)..sort(),
        );
        await removeContactsCompleter.future;
      },
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-delete',
          text: 'Delete message',
        ),
      ],
    );
    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[_buildPeer()],
    );
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Peer'), findsOneWidget);

    await tester.tap(find.text('Peer'));
    await tester.pump();

    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Delete chats'), findsOneWidget);

    await tester.tap(find.text('Delete chats'));
    await tester.pump();

    expect(removeContactCalls, <List<String>>[
      <String>[_peerId],
    ]);
    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Delete chats'), findsOneWidget);
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    final deletedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherMessages = await store.loadMessages(
      'peer-2',
      baseUrlOverride: _baseUrl,
    );
    expect(deletedTargetMessages, isEmpty);
    expect(
      preservedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_delete_other'],
    );
    final preservedTargetGroupMessages = await store.loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherGroupMessages = await store.loadGroupMessages(
      'group-2',
      baseUrlOverride: _baseUrl,
    );
    expect(
      preservedTargetGroupMessages.map((message) => message.id).toList(),
      <String>['group_msg_1'],
    );
    expect(
      preservedOtherGroupMessages.map((message) => message.id).toList(),
      <String>['group_msg_selection_delete_other'],
    );

    removeContactsCompleter.complete();
    await tester.pumpAndSettle();

    expect(state.debugSelectionModeEnabled(), isFalse);
    expect(find.text('Peer'), findsNothing);
    expect(find.text('Cancel (1)'), findsNothing);
    expect(find.text('Delete chats'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for selection-bar group-delete persistence before clearing the selection UI',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    const otherGroup = ChatGroup(
      id: 'group-2',
      name: 'Other Group',
      creatorId: _meId,
      memberCount: 2,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_mixed_delete_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      'peer-2',
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_mixed_delete_other',
          senderId: 'peer-2',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[_buildGroupMessage()],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      otherGroup.id,
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_delete',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 10, 0),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      otherGroup.id,
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugShowChatsList(
      me: _buildMe(),
      groups: <ChatGroup>[_buildGroup(), otherGroup],
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedGroupThread(
      group: otherGroup,
      messages: <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_delete',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 10, 0),
        ),
      ],
    );
    state.debugSeedUnread(<String, int>{
      'grp:$_groupId': 3,
      'grp:${otherGroup.id}': 4,
    });
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Security Group'), findsOneWidget);

    await tester.tap(find.text('Security Group'));
    await tester.pump();

    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Delete chats'), findsOneWidget);

    await tester.tap(find.text('Delete chats'));
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>['grp:$_groupId']);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{'grp:${otherGroup.id}': 4},
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{'grp:${otherGroup.id}': 4},
    );
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      isNull,
    );
    expect(
      await store.loadGroupKey(otherGroup.id, baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    final preservedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherMessages = await store.loadMessages(
      'peer-2',
      baseUrlOverride: _baseUrl,
    );
    expect(
      preservedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_mixed_delete_target'],
    );
    expect(
      preservedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_mixed_delete_other'],
    );
    final deletedGroupMessages = await store.loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    final preservedGroupMessages = await store.loadGroupMessages(
      otherGroup.id,
      baseUrlOverride: _baseUrl,
    );
    expect(deletedGroupMessages, isEmpty);
    expect(
      preservedGroupMessages.map((message) => message.id).toList(),
      <String>['group_msg_other_delete'],
    );
    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Cancel (1)'), findsOneWidget);
    expect(find.text('Delete chats'), findsOneWidget);

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();

    expect(state.debugSelectionModeEnabled(), isFalse);
    expect(find.text('Cancel (1)'), findsNothing);
    expect(find.text('Delete chats'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage waits for mixed selection-bar delete persistence before clearing the selection UI',
      (tester) async {
    final removeContactCalls = <List<String>>[];
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    const otherGroup = ChatGroup(
      id: 'group-2',
      name: 'Other Group',
      creatorId: _meId,
      memberCount: 2,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_mixed_delete_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      otherPeer.id,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_selection_mixed_delete_other',
          senderId: otherPeer.id,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[_buildGroupMessage()],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      otherGroup.id,
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_mixed_delete',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other mixed group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 12, 0),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      otherGroup.id,
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      removeContactsForPeersOverride: (peerIds) async {
        removeContactCalls.add(
          peerIds.toList(growable: false)..sort(),
        );
      },
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-mixed-peer',
          text: 'mixed peer',
        ),
      ],
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: otherPeer,
      messages: <ChatMessage>[
        _buildDirectMessage(
          id: 'msg-selection-mixed-other-peer',
          senderId: otherPeer.id,
          text: 'other peer',
          recipientId: _meId,
          createdAt: DateTime.utc(2026, 3, 20, 10, 11, 0),
        ),
      ],
    );
    state.debugShowChatsList(
      me: _buildMe(),
      contacts: <ChatContact>[_buildPeer(), otherPeer],
      groups: <ChatGroup>[_buildGroup(), otherGroup],
    );
    state.debugSeedGroupThread(
      group: _buildGroup(),
      messages: <ChatGroupMessage>[_buildGroupMessage()],
    );
    state.debugSeedGroupThread(
      group: otherGroup,
      messages: <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_mixed_delete',
          groupId: otherGroup.id,
          senderId: _meId,
          text: 'other mixed group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 12, 0),
        ),
      ],
    );
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      otherPeer.id: 5,
      'grp:$_groupId': 3,
      'grp:${otherGroup.id}': 4,
    });
    await tester.pump();

    final openSheetFuture = state.debugShowChatsMenu();
    await tester.pumpAndSettle();

    expect(find.text('Selection'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    await openSheetFuture;

    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('Security Group'), findsOneWidget);

    await tester.tap(find.text('Peer'));
    await tester.pump();
    await tester.tap(find.text('Security Group'));
    await tester.pump();

    expect(find.text('Cancel (2)'), findsOneWidget);
    expect(find.text('Delete chats'), findsOneWidget);

    await tester.tap(find.text('Delete chats'));
    await tester.pump();

    expect(removeContactCalls, <List<String>>[
      <String>[_peerId],
    ]);
    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'grp:$_groupId']..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        otherPeer.id: 5,
        'grp:${otherGroup.id}': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        otherPeer.id: 5,
        'grp:${otherGroup.id}': 4,
      },
    );
    final deletedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherMessages = await store.loadMessages(
      otherPeer.id,
      baseUrlOverride: _baseUrl,
    );
    expect(deletedTargetMessages, isEmpty);
    expect(
      preservedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_selection_mixed_delete_other'],
    );
    final deletedGroupMessages = await store.loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    final preservedGroupMessages = await store.loadGroupMessages(
      otherGroup.id,
      baseUrlOverride: _baseUrl,
    );
    expect(deletedGroupMessages, isEmpty);
    expect(
      preservedGroupMessages.map((message) => message.id).toList(),
      <String>['group_msg_other_mixed_delete'],
    );
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      isNull,
    );
    expect(
      await store.loadGroupKey(otherGroup.id, baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(state.debugSelectionModeEnabled(), isTrue);
    expect(find.text('Cancel (2)'), findsOneWidget);
    expect(find.text('Delete chats'), findsOneWidget);

    unreadBatchCompleter.complete();
    await tester.pumpAndSettle();

    expect(state.debugSelectionModeEnabled(), isFalse);
    expect(find.text('Cancel (2)'), findsNothing);
    expect(find.text('Delete chats'), findsNothing);
  });

  testWidgets(
      'ShamellChatPage starts mark-all-read unread batch saves through the dedicated detached seam',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
    });

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'peer-2', 'grp:$_groupId']..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
      },
    );

    unreadBatchCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage keeps negative group sentinels in the detached mark-all-read batch',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': -1,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'peer-2', 'grp:$_groupId', 'grp:group-2', 'grp:group-3']
        ..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      '2026-03-18T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );

    unreadBatchCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage clears mentions before the detached mark-all-read batch settles for negative group sentinels',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': -1,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2', 'group-3'},
      mentionAllUnread: <String>{_groupId, 'group-2'},
    );

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'peer-2', 'grp:$_groupId', 'grp:group-2', 'grp:group-3']
        ..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(state.debugGroupMentionUnreadSnapshot(), isEmpty);
    expect(state.debugGroupMentionAllUnreadSnapshot(), isEmpty);
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      '2026-03-18T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );

    unreadBatchCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage clears mentions after positive group-seen updates before the detached mark-all-read batch settles',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final unreadBatchCompleter = Completer<void>();
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      startMarkAllChatsReadUnreadBatchSaveOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
        await unreadBatchCompleter.future;
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2', 'group-3'},
      mentionAllUnread: <String>{'group-2', 'group-3'},
    );

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'peer-2', 'grp:$_groupId', 'grp:group-2', 'grp:group-3']
        ..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(state.debugGroupMentionUnreadSnapshot(), isEmpty);
    expect(state.debugGroupMentionAllUnreadSnapshot(), isEmpty);
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );

    unreadBatchCompleter.complete();
    await tester.pump();
  });

  testWidgets(
      'ShamellChatPage marks all chats read through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
    });

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'peer-2', 'grp:$_groupId']..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
      },
    );
  });

  testWidgets(
      'ShamellChatPage marks all unread groups seen while marking all chats read',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      isNot('2026-03-18T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );
  });

  testWidgets(
      'ShamellChatPage skips group-seen writes for negative unread sentinels during mark all read',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveGroupSeen(
      <String, String>{
        _groupId: '2026-03-18T00:00:00Z',
        'group-2': '2026-03-17T00:00:00Z',
        'group-3': '2026-03-16T00:00:00Z',
      },
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': -1,
      'grp:group-2': 4,
      'grp:group-3': 0,
    });

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
        'grp:group-3': 0,
      },
    );
    expect(
      await store.loadGroupSeenForGroup(_groupId, baseUrlOverride: _baseUrl),
      '2026-03-18T00:00:00Z',
    );
    expect(
      await store.loadGroupSeenForGroup('group-2', baseUrlOverride: _baseUrl),
      isNot('2026-03-17T00:00:00Z'),
    );
    expect(
      await store.loadGroupSeenForGroup('group-3', baseUrlOverride: _baseUrl),
      '2026-03-16T00:00:00Z',
    );
  });

  testWidgets(
      'ShamellChatPage clears all group mentions while marking all chats read',
      (tester) async {
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedGroupMentionState(
      mentionUnread: <String>{_groupId, 'group-2', 'group-3'},
      mentionAllUnread: <String>{'group-2', 'group-3'},
    );

    await state.debugMarkAllChatsRead();
    await tester.pump();

    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 0,
        'peer-2': 0,
        'grp:$_groupId': 0,
        'grp:group-2': 0,
      },
    );
    expect(state.debugGroupMentionUnreadSnapshot(), isEmpty);
    expect(state.debugGroupMentionAllUnreadSnapshot(), isEmpty);
  });

  testWidgets(
      'ShamellChatPage toggles group unread through the targeted group contract',
      (tester) async {
    final unreadCalls = <({String groupId, int unreadCount})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        unreadCalls.add((groupId: groupId, unreadCount: unreadCount));
      },
    );

    state.debugSeedUnread(<String, int>{
      'grp:$_groupId': 3,
      'grp:group-2': 4,
      _peerId: 7,
    });

    await state.debugToggleGroupReadUnread(_buildGroup());
    await tester.pump();

    expect(
      unreadCalls,
      <({String groupId, int unreadCount})>[
        (groupId: _groupId, unreadCount: 0),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        'grp:$_groupId': 0,
        'grp:group-2': 4,
        _peerId: 7,
      },
    );
  });

  testWidgets(
      'ShamellChatPage clears group unread through the targeted group contract',
      (tester) async {
    final unreadCalls = <({String groupId, int unreadCount})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        unreadCalls.add((groupId: groupId, unreadCount: unreadCount));
      },
    );

    state.debugSeedUnread(<String, int>{
      'grp:$_groupId': 3,
      'grp:group-2': 4,
      _peerId: 7,
    });

    await state.debugClearGroupConversation(_buildGroup());
    await tester.pump();

    expect(
      unreadCalls,
      <({String groupId, int unreadCount})>[
        (groupId: _groupId, unreadCount: 0),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        'grp:$_groupId': 0,
        'grp:group-2': 4,
        _peerId: 7,
      },
    );
  });

  testWidgets(
      'ShamellChatPage deletes selected chats through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final store = ChatLocalStore();
    final archivedPeer = _buildPeer().copyWith(archived: true);
    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[archivedPeer, otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_mixed_delete_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      'peer-2',
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_mixed_delete_other',
          senderId: 'peer-2',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[_buildGroupMessage()],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      'group-2',
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_other_mixed_delete',
          groupId: 'group-2',
          senderId: _meId,
          text: 'preserved group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 17, 0),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
      },
    );

    state.debugSeedDraftForChat(_peerId, 'draft target');
    state.debugSeedDraftForChat('peer-2', 'draft other');
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'peer-2': 5,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived('group-2', true);
    state.debugSeedSelectedChatIds(<String>[
      _peerId,
      'grp:$_groupId',
    ]);

    await state.debugDeleteSelectedChats();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(
      unreadBatchCalls.single.unreadKeys,
      <String>[_peerId, 'grp:$_groupId']..sort(),
    );
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        'peer-2': 5,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        'peer-2': 5,
        'grp:group-2': 4,
      },
    );
    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{'peer-2'},
    );
    final deletedMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedMessages = await store.loadMessages(
      'peer-2',
      baseUrlOverride: _baseUrl,
    );
    expect(deletedMessages, isEmpty);
    expect(
      preservedMessages.map((message) => message.id).toList(),
      <String>['direct_msg_mixed_delete_other'],
    );
    final deletedGroupMessages = await store.loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    final preservedGroupMessages = await store.loadGroupMessages(
      'group-2',
      baseUrlOverride: _baseUrl,
    );
    expect(deletedGroupMessages, isEmpty);
    expect(
      preservedGroupMessages.map((message) => message.id).toList(),
      <String>['group_msg_other_mixed_delete'],
    );
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      isNull,
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(
      await store.loadDrafts(baseUrlOverride: _baseUrl),
      <String, String>{'peer-2': 'draft other'},
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{_groupId, 'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage deletes selected contacts through the targeted peer and batch contracts',
      (tester) async {
    const otherPeerId = 'peer-2';
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_delete_guard_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      otherPeerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_delete_guard_other',
          senderId: otherPeerId,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[_buildGroupMessage()],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      'group-2',
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_contact_delete_guard_other',
          groupId: 'group-2',
          senderId: _meId,
          text: 'preserved group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 17, 0),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
      },
    );

    state.debugSeedDraftForChat(_peerId, 'draft target');
    state.debugSeedDraftForChat(otherPeerId, 'draft other');
    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      otherPeerId: 5,
      'grp:group-2': 4,
    });
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived('group-2', true);
    state.debugSeedSelectedChatIds(<String>[_peerId]);

    await state.debugDeleteSelectedChats();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>[_peerId]);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        otherPeerId: 5,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        otherPeerId: 5,
        'grp:group-2': 4,
      },
    );

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{otherPeerId},
    );

    final deletedMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedMessages = await store.loadMessages(
      otherPeerId,
      baseUrlOverride: _baseUrl,
    );
    expect(deletedMessages, isEmpty);
    expect(
      preservedMessages.map((message) => message.id).toList(),
      <String>['direct_msg_delete_guard_other'],
    );
    expect(
      await store.loadDrafts(baseUrlOverride: _baseUrl),
      <String, String>{otherPeerId: 'draft other'},
    );
    final preservedTargetGroupMessages = await store.loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherGroupMessages = await store.loadGroupMessages(
      'group-2',
      baseUrlOverride: _baseUrl,
    );
    expect(
      preservedTargetGroupMessages.map((message) => message.id).toList(),
      <String>['group_msg_1'],
    );
    expect(
      preservedOtherGroupMessages.map((message) => message.id).toList(),
      <String>['group_msg_contact_delete_guard_other'],
    );
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{_groupId, 'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage deletes selected groups through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    final store = ChatLocalStore();
    final archivedPeer = _buildPeer().copyWith(archived: true);
    final otherPeer = ChatContact(
      id: 'peer-2',
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[archivedPeer, otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_group_delete_guard_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      'peer-2',
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_group_delete_guard_other',
          senderId: 'peer-2',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[_buildGroupMessage()],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupMessages(
      'group-2',
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'group_msg_delete_guard_other',
          groupId: 'group-2',
          senderId: _meId,
          text: 'preserved group',
          createdAt: DateTime.utc(2026, 3, 20, 10, 17, 0),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false)..sort(),
        ));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:$_groupId': 3,
      'grp:group-2': 4,
    });
    state.debugSeedDraftForChat(_peerId, 'draft target');
    state.debugSeedDraftForChat('peer-2', 'draft other');
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived('group-2', true);
    state.debugSeedSelectedChatIds(<String>['grp:$_groupId']);

    await state.debugDeleteSelectedChats();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>['grp:$_groupId']);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{_peerId: 7, 'grp:group-2': 4},
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{_peerId: 7, 'grp:group-2': 4},
    );

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == 'peer-2');
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, 'peer-2'},
    );
    expect(updatedPeer.archived, isTrue);
    expect(preservedPeer.archived, isFalse);
    final preservedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherMessages = await store.loadMessages(
      'peer-2',
      baseUrlOverride: _baseUrl,
    );
    expect(
      preservedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_group_delete_guard_target'],
    );
    expect(
      preservedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_group_delete_guard_other'],
    );
    final deletedGroupMessages = await store.loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    final preservedGroupMessages = await store.loadGroupMessages(
      'group-2',
      baseUrlOverride: _baseUrl,
    );
    expect(deletedGroupMessages, isEmpty);
    expect(preservedGroupMessages, hasLength(1));
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      isNull,
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(
      await store.loadDrafts(baseUrlOverride: _baseUrl),
      <String, String>{
        _peerId: 'draft target',
        'peer-2': 'draft other',
      },
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{_groupId, 'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage unarchives selected groups through the targeted group contract',
      (tester) async {
    final archivedCalls = <({String groupId, bool archived})>[];
    final draftSaveCalls = <Map<String, String>>[];
    final store = ChatLocalStore();
    final archivedPeer = _buildPeer().copyWith(archived: true);
    const otherPeerId = 'peer-2';
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
      archived: true,
    );
    await store.saveContacts(
      <ChatContact>[archivedPeer, otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_group_unarchive_guard_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      otherPeerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_group_unarchive_guard_other',
          senderId: otherPeerId,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
      },
      saveDraftsOverride: (drafts) async {
        draftSaveCalls.add(Map<String, String>.from(drafts));
      },
    );

    state.debugSeedDraftForChat(_peerId, 'draft target');
    state.debugSeedDraftForChat(otherPeerId, 'draft other');
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived('group-2', true);
    archivedCalls.clear();

    state.debugSeedSelectedChatIds(<String>['grp:$_groupId']);

    await state.debugUnarchiveSelectedChats();
    await tester.pump();

    expect(
      archivedCalls,
      <({String groupId, bool archived})>[
        (groupId: _groupId, archived: false),
      ],
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{'group-2'},
    );
    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(updatedPeer.archived, isTrue);
    expect(preservedPeer.archived, isTrue);
    final preservedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherMessages = await store.loadMessages(
      otherPeerId,
      baseUrlOverride: _baseUrl,
    );
    expect(
      preservedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_group_unarchive_guard_target'],
    );
    expect(
      preservedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_group_unarchive_guard_other'],
    );
    expect(draftSaveCalls, isEmpty);
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
  });

  testWidgets(
      'ShamellChatPage unarchives selected contacts through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final archivedCalls = <({String groupId, bool archived})>[];
    final draftSaveCalls = <Map<String, String>>[];
    final store = ChatLocalStore();
    final archivedPeer = _buildPeer().copyWith(archived: true);
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
      archived: true,
    );
    await store.saveContacts(
      <ChatContact>[archivedPeer, otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_contact_unarchive_guard_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      otherPeerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_contact_unarchive_guard_other',
          senderId: otherPeerId,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
      },
      saveDraftsOverride: (drafts) async {
        draftSaveCalls.add(Map<String, String>.from(drafts));
      },
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: archivedPeer);
    state.debugSeedDraftForChat(_peerId, 'draft target');
    state.debugSeedDraftForChat(otherPeerId, 'draft other');
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived('group-2', true);
    archivedCalls.clear();
    state.debugSeedSelectedChatIds(<String>[_peerId]);

    await state.debugUnarchiveSelectedChats();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(updatedPeer.archived, isFalse);
    expect(preservedPeer.archived, isTrue);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    final preservedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherMessages = await store.loadMessages(
      otherPeerId,
      baseUrlOverride: _baseUrl,
    );
    expect(
      preservedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_contact_unarchive_guard_target'],
    );
    expect(
      preservedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_contact_unarchive_guard_other'],
    );
    expect(archivedCalls, isEmpty);
    expect(draftSaveCalls, isEmpty);
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{_groupId, 'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage unarchives mixed selected chats through the targeted peer and group contracts',
      (tester) async {
    const otherPeerId = 'peer-2';
    final archivedCalls = <({String groupId, bool archived})>[];
    final draftSaveCalls = <Map<String, String>>[];
    final store = ChatLocalStore();
    final archivedPeer = _buildPeer().copyWith(archived: true);
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
      archived: true,
    );
    await store.saveContacts(
      <ChatContact>[archivedPeer, otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      _peerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_mixed_unarchive_guard_target',
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveMessages(
      otherPeerId,
      <ChatMessage>[
        _buildDirectMessage(
          id: 'direct_msg_mixed_unarchive_guard_other',
          senderId: otherPeerId,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.saveGroupKey(_groupId, 'group-key-a',
        baseUrlOverride: _baseUrl);
    await store.saveGroupKey(
      'group-2',
      'group-key-b',
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
      },
      saveDraftsOverride: (drafts) async {
        draftSaveCalls.add(Map<String, String>.from(drafts));
      },
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: archivedPeer);
    state.debugSeedDraftForChat(_peerId, 'draft target');
    state.debugSeedDraftForChat(otherPeerId, 'draft other');
    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived('group-2', true);
    archivedCalls.clear();

    state.debugSeedSelectedChatIds(<String>[_peerId, 'grp:$_groupId']);

    await state.debugUnarchiveSelectedChats();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(updatedPeer.archived, isFalse);
    expect(preservedPeer.archived, isTrue);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(
      archivedCalls,
      <({String groupId, bool archived})>[
        (groupId: _groupId, archived: false),
      ],
    );
    final preservedTargetMessages = await store.loadMessages(
      _peerId,
      baseUrlOverride: _baseUrl,
    );
    final preservedOtherMessages = await store.loadMessages(
      otherPeerId,
      baseUrlOverride: _baseUrl,
    );
    expect(
      preservedTargetMessages.map((message) => message.id).toList(),
      <String>['direct_msg_mixed_unarchive_guard_target'],
    );
    expect(
      preservedOtherMessages.map((message) => message.id).toList(),
      <String>['direct_msg_mixed_unarchive_guard_other'],
    );
    expect(draftSaveCalls, isEmpty);
    expect(
      await store.loadGroupKey(_groupId, baseUrlOverride: _baseUrl),
      'group-key-a',
    );
    expect(
      await store.loadGroupKey('group-2', baseUrlOverride: _baseUrl),
      'group-key-b',
    );
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{'group-2'},
    );
  });

  testWidgets(
      'ShamellChatPage unarchives synced groups through the targeted group contract',
      (tester) async {
    final archivedCalls = <({String groupId, bool archived})>[];
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    Completer<void>? archivePersistCompleter;
    await ChatLocalStore().saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'msg-001',
          groupId: _groupId,
          senderId: _peerId,
          text: 'fresh group message',
          createdAt: DateTime.utc(2026, 3, 19, 10, 0, 1),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadGroupSeenForGroupsOverride: (_) async => <String, String>{},
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
        final completer = archivePersistCompleter;
        if (completer != null) {
          await completer.future;
        }
      },
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false),
        ));
      },
    );

    await state.debugSetGroupArchived(_groupId, true);
    await state.debugSetGroupArchived('group-2', true);
    archivedCalls.clear();
    archivePersistCompleter = Completer<void>();

    var completed = false;
    final syncFuture = state.debugSyncGroups();
    unawaited(syncFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(
      archivedCalls,
      <({String groupId, bool archived})>[
        (groupId: _groupId, archived: false),
      ],
    );
    expect(unreadBatchCalls, isEmpty);
    expect(
      state.debugArchivedGroupsSnapshot(),
      <String>{'group-2'},
    );

    archivePersistCompleter.complete();
    await syncFuture;
    await tester.pump();

    expect(completed, isTrue);
    expect(unreadBatchCalls, hasLength(1));
  });

  testWidgets(
      'ShamellChatPage persists synced group unread through the targeted batch contract',
      (tester) async {
    final unreadBatchCalls =
        <({Map<String, int> unread, List<String> unreadKeys})>[];
    await ChatLocalStore().saveGroupMessages(
      _groupId,
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'msg-001',
          groupId: _groupId,
          senderId: _peerId,
          text: 'fresh group message',
          createdAt: DateTime.utc(2026, 3, 19, 10, 0, 1),
        ),
      ],
      baseUrlOverride: _baseUrl,
    );

    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadGroupSeenForGroupsOverride: (_) async => <String, String>{},
      saveUnreadCountsForKeysOverride: (unread, unreadKeys) async {
        unreadBatchCalls.add((
          unread: Map<String, int>.from(unread),
          unreadKeys: unreadKeys.toList(growable: false),
        ));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:group-2': 4,
    });

    await state.debugSyncGroups();
    await tester.pump();

    expect(unreadBatchCalls, hasLength(1));
    expect(unreadBatchCalls.single.unreadKeys, <String>['grp:$_groupId']);
    expect(
      unreadBatchCalls.single.unread,
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 1,
        'grp:group-2': 4,
      },
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 1,
        'grp:group-2': 4,
      },
    );
  });

  testWidgets(
      'ShamellChatPage uses targeted group seen batch read during group sync',
      (tester) async {
    final seenBatchReadCalls = <List<String>>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadGroupSeenForGroupsOverride: (groupIds) async {
        seenBatchReadCalls.add(groupIds.toList(growable: false));
        return <String, String>{
          _groupId: '2026-03-19T10:00:00.000Z',
        };
      },
    );

    await state.debugSyncGroups();
    await tester.pump();

    expect(seenBatchReadCalls, <List<String>>[
      <String>[_groupId],
    ]);
  });

  testWidgets(
      'ShamellChatPage starts live group inbox merges through the dedicated detached seam',
      (tester) async {
    final updates = <ChatGroupInboxUpdate>[];
    final mergeCompleter = Completer<void>();
    final groupInboxController = StreamController<ChatGroupInboxUpdate>();
    addTearDown(groupInboxController.close);
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(
        streamGroupInboxHandler: ({required String deviceId}) {
          return groupInboxController.stream;
        },
      ),
      onCritical: () {},
      startLiveGroupInboxMergeOverride: (update) async {
        updates.add(update);
        await mergeCompleter.future;
      },
    );

    state.debugListenWs();
    await tester.pump();

    groupInboxController.add(
      ChatGroupInboxUpdate(
        groupId: _groupId,
        messages: <ChatGroupMessage>[
          ChatGroupMessage(
            id: 'msg-group-stream-001',
            groupId: _groupId,
            senderId: _peerId,
            text: 'streamed group message',
            createdAt: DateTime.utc(2026, 3, 19, 10, 0, 1),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(updates, hasLength(1));
    expect(updates.single.groupId, _groupId);
    expect(
        updates.single.messages.map((message) => message.id).toList(), <String>[
      'msg-group-stream-001',
    ]);

    mergeCompleter.complete();
  });

  testWidgets(
      'ShamellChatPage uses targeted group seen read for live group inbox updates',
      (tester) async {
    final seenReadCalls = <String>[];
    final unreadCalls = <({String groupId, int unreadCount})>[];
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadGroupSeenForGroupOverride: (groupId) async {
        seenReadCalls.add(groupId);
        return '2026-03-19T10:00:00.000Z';
      },
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        unreadCalls.add((groupId: groupId, unreadCount: unreadCount));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:group-2': 4,
    });

    state.debugMergeGroupInboxUpdate(
      ChatGroupInboxUpdate(
        groupId: _groupId,
        messages: <ChatGroupMessage>[
          ChatGroupMessage(
            id: 'msg-001',
            groupId: _groupId,
            senderId: _peerId,
            text: 'fresh',
            createdAt: DateTime.utc(2026, 3, 19, 10, 0, 1),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(seenReadCalls, <String>[_groupId]);
    expect(
      unreadCalls,
      <({String groupId, int unreadCount})>[
        (groupId: _groupId, unreadCount: 1),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 1,
        'grp:group-2': 4,
      },
    );
  });

  testWidgets(
      'ShamellChatPage waits for live group thread persistence before applying unread updates',
      (tester) async {
    final groupMessageCalls =
        <({String groupId, List<ChatGroupMessage> messages})>[];
    final unreadCalls = <({String groupId, int unreadCount})>[];
    final saveGroupMessagesCompleter = Completer<void>();
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadGroupSeenForGroupOverride: (groupId) async {
        return '2026-03-19T10:00:00.000Z';
      },
      saveGroupMessagesForGroupOverride: (groupId, messages) async {
        groupMessageCalls.add((
          groupId: groupId,
          messages: List<ChatGroupMessage>.from(messages),
        ));
        await saveGroupMessagesCompleter.future;
      },
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        unreadCalls.add((groupId: groupId, unreadCount: unreadCount));
      },
    );

    state.debugSeedUnread(<String, int>{
      _peerId: 7,
      'grp:group-2': 4,
    });

    var completed = false;
    final mergeFuture = state.debugMergeGroupInboxUpdate(
      ChatGroupInboxUpdate(
        groupId: _groupId,
        messages: <ChatGroupMessage>[
          ChatGroupMessage(
            id: 'msg-group-live-001',
            groupId: _groupId,
            senderId: _peerId,
            text: 'fresh group message',
            createdAt: DateTime.utc(2026, 3, 19, 10, 0, 1),
          ),
        ],
      ),
    );
    unawaited(mergeFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(groupMessageCalls, hasLength(1));
    expect(groupMessageCalls.single.groupId, _groupId);
    expect(
      groupMessageCalls.single.messages.map((message) => message.id).toList(),
      <String>['msg-group-live-001'],
    );
    expect(unreadCalls, isEmpty);
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        'grp:group-2': 4,
      },
    );
    final storedMessagesBeforeRelease =
        await ChatLocalStore().loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    expect(storedMessagesBeforeRelease, isEmpty);

    saveGroupMessagesCompleter.complete();
    await mergeFuture;

    expect(completed, isTrue);
    expect(
      unreadCalls,
      <({String groupId, int unreadCount})>[
        (groupId: _groupId, unreadCount: 1),
      ],
    );
    expect(
      state.debugUnreadSnapshot(),
      <String, int>{
        _peerId: 7,
        'grp:$_groupId': 1,
        'grp:group-2': 4,
      },
    );
    final storedMessages = await ChatLocalStore().loadGroupMessages(
      _groupId,
      baseUrlOverride: _baseUrl,
    );
    expect(storedMessages, isEmpty);
  });

  testWidgets(
      'ShamellChatPage waits for live group auto-unarchive persistence before continuing',
      (tester) async {
    final archivedCalls = <({String groupId, bool archived})>[];
    final groupMessageCalls =
        <({String groupId, List<ChatGroupMessage> messages})>[];
    final unreadCalls = <({String groupId, int unreadCount})>[];
    Completer<void>? archivePersistCompleter;
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      loadGroupSeenForGroupOverride: (groupId) async {
        return '2026-03-19T10:00:00.000Z';
      },
      saveArchivedGroupStateOverride: (groupId, archived) async {
        archivedCalls.add((groupId: groupId, archived: archived));
        final completer = archivePersistCompleter;
        if (completer != null) {
          await completer.future;
        }
      },
      saveGroupMessagesForGroupOverride: (groupId, messages) async {
        groupMessageCalls.add((
          groupId: groupId,
          messages: List<ChatGroupMessage>.from(messages),
        ));
      },
      saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
        unreadCalls.add((groupId: groupId, unreadCount: unreadCount));
      },
    );

    await state.debugSetGroupArchived(_groupId, true);
    archivedCalls.clear();

    archivePersistCompleter = Completer<void>();

    var completed = false;
    final mergeFuture = state.debugMergeGroupInboxUpdate(
      ChatGroupInboxUpdate(
        groupId: _groupId,
        messages: <ChatGroupMessage>[
          ChatGroupMessage(
            id: 'msg-group-live-archived-001',
            groupId: _groupId,
            senderId: _peerId,
            text: 'fresh group message',
            createdAt: DateTime.utc(2026, 3, 19, 10, 0, 1),
          ),
        ],
      ),
    );
    unawaited(mergeFuture.then((_) => completed = true));
    await tester.pump();

    expect(completed, isFalse);
    expect(
      archivedCalls,
      <({String groupId, bool archived})>[
        (groupId: _groupId, archived: false),
      ],
    );
    expect(state.debugArchivedGroupsSnapshot(), isEmpty);
    expect(groupMessageCalls, isEmpty);
    expect(unreadCalls, isEmpty);

    archivePersistCompleter.complete();
    await mergeFuture;

    expect(completed, isTrue);
    expect(groupMessageCalls, hasLength(1));
    expect(groupMessageCalls.single.groupId, _groupId);
    expect(
      groupMessageCalls.single.messages.map((message) => message.id).toList(),
      <String>['msg-group-live-archived-001'],
    );
    expect(
      unreadCalls,
      <({String groupId, int unreadCount})>[
        (groupId: _groupId, unreadCount: 1),
      ],
    );
  });

  testWidgets('ShamellChatPage reauths on critical direct prefs sync failure',
      (tester) async {
    final service =
        _FakeChatBootstrapService(fetchPrefsError: criticalChatError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSyncPrefsFromServer();
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage uses paged direct prefs sync', (tester) async {
    final service = _FakeChatBootstrapService(
      fetchPrefsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatContactPrefs>[
          ChatContactPrefs(
            peerId: _peerId,
            muted: true,
            starred: false,
            pinned: true,
          ),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncPrefsFromServer();
    await tester.pump();

    expect(service.fetchPrefsPagedCallCount, 1);
    expect(service.fetchPrefsCallCount, 0);
  });

  testWidgets(
      'ShamellChatPage direct prefs sync preserves unrelated stored peers',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      fetchPrefsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatContactPrefs>[
          ChatContactPrefs(
            peerId: _peerId,
            muted: true,
            starred: false,
            pinned: true,
          ),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncPrefsFromServer();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final syncedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(storedContacts.map((c) => c.id).toSet(),
        <String>{_peerId, otherPeerId});
    expect(syncedPeer.muted, isTrue);
    expect(syncedPeer.pinned, isTrue);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.muted, isFalse);
    expect(preservedPeer.pinned, isFalse);
  });

  testWidgets(
      'ShamellChatPage sets muted through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetPeerMuted(true);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final mutedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(storedContacts.map((c) => c.id).toSet(),
        <String>{_peerId, otherPeerId});
    expect(mutedPeer.muted, isTrue);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.muted, isFalse);
    expect(preservedPeer.pinned, isFalse);
  });

  testWidgets(
      'ShamellChatPage sets pinned through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetPeerPinned(true);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final pinnedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(pinnedPeer.pinned, isTrue);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.muted, isFalse);
    expect(preservedPeer.pinned, isFalse);
  });

  testWidgets(
      'ShamellChatPage sets hidden through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetPeerHidden(true);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final hiddenPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(hiddenPeer.hidden, isTrue);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.hidden, isFalse);
    expect(preservedPeer.pinned, isFalse);
  });

  testWidgets(
      'ShamellChatPage sets blocked through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetPeerBlocked(true);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final blockedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(blockedPeer.blocked, isTrue);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.blocked, isFalse);
    expect(preservedPeer.pinned, isFalse);
  });

  testWidgets(
      'ShamellChatPage toggles archived through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugTogglePeerArchived();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final archivedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(archivedPeer.archived, isTrue);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.archived, isFalse);
    expect(preservedPeer.pinned, isFalse);
  });

  testWidgets(
      'ShamellChatPage toggles disappearing through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugTogglePeerDisappearing();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(updatedPeer.disappearing, isTrue);
    expect(updatedPeer.disappearAfter, const Duration(minutes: 30));
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.disappearing, isFalse);
    expect(preservedPeer.disappearAfter, isNull);
  });

  testWidgets(
      'ShamellChatPage sets disappear-after through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetPeerDisappearAfter(const Duration(hours: 1));
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(updatedPeer.disappearAfter, const Duration(hours: 1));
    expect(updatedPeer.disappearing, isFalse);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.disappearAfter, isNull);
    expect(preservedPeer.disappearing, isFalse);
  });

  testWidgets(
      'ShamellChatPage resolves a peer through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      resolveDeviceHandler: (peerId) async {
        final publicKeyB64 = _curveKeyB64(77);
        return ChatContact(
          id: peerId,
          publicKeyB64: publicKeyB64,
          fingerprint: fingerprintForKey(publicKeyB64),
          name: 'Resolved Peer',
        );
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugResolvePeerId(_peerId);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final resolvedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(resolvedPeer.name, 'Resolved Peer');
    expect(resolvedPeer.publicKeyB64, _curveKeyB64(77));
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.publicKeyB64, _curveKeyB64(49));
  });

  testWidgets(
      'ShamellChatPage falls back to an existing local contact when peer discovery fails closed',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final originalPeer = ChatContact(
      id: _peerId,
      publicKeyB64: _curveKeyB64(33),
      fingerprint: 'fp-peer',
      name: 'Stored Peer',
    );
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[originalPeer, otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      resolveDeviceHandler: (peerId) async {
        throw const ChatHttpException(
          op: 'resolveDevice',
          statusCode: 404,
          body: '{"detail":"not found"}',
        );
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugResolvePeerId(_peerId);
    await tester.pump();

    final bootstrapState = state.debugBootstrapState() as Map<String, Object?>;
    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final resolvedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    expect(service.resolveDeviceCallCount, 1);
    expect(bootstrapState['peerId'], _peerId);
    expect(resolvedPeer.name, 'Stored Peer');
    expect(resolvedPeer.publicKeyB64, _curveKeyB64(33));
  });

  testWidgets(
      'ShamellChatPage reset session refreshes peer identity and clears stale verification',
      (tester) async {
    final store = ChatLocalStore();
    final verifiedPeer = ChatContact(
      id: _peerId,
      publicKeyB64: _curveKeyB64(33),
      fingerprint: fingerprintForKey(_curveKeyB64(33)),
      name: 'Peer',
      verified: true,
      verifiedAt: DateTime.utc(2026, 4, 6, 9, 0, 0),
    );
    await store.saveContacts(
      <ChatContact>[verifiedPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.savePeer(verifiedPeer, baseUrlOverride: _baseUrl);
    await store.markVerified(
      verifiedPeer.id,
      verifiedPeer.fingerprint,
      baseUrlOverride: _baseUrl,
    );
    const rotatedPeerSeed = 77;
    final rotatedPeerKey = _curveKeyB64(rotatedPeerSeed);
    final service = _FakeChatBootstrapService(
      resolveDeviceHandler: (peerId) async {
        return ChatContact(
          id: peerId,
          publicKeyB64: rotatedPeerKey,
          fingerprint: fingerprintForKey(rotatedPeerKey),
          name: 'Rotated Peer',
        );
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );
    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: verifiedPeer,
      messages: <ChatMessage>[_buildDirectMessage()],
    );
    await tester.pump();

    await state.debugResetCurrentPeerSession();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final refreshedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    expect(service.resolveDeviceCallCount, 1);
    expect(refreshedPeer.name, 'Rotated Peer');
    expect(refreshedPeer.publicKeyB64, rotatedPeerKey);
    expect(refreshedPeer.fingerprint, fingerprintForKey(rotatedPeerKey));
    expect(refreshedPeer.verified, isFalse);
    expect(refreshedPeer.verifiedAt, isNull);
    expect(
      state.debugBootstrapState(),
      containsPair('messageCount', 0),
    );
  });

  testWidgets(
      'ShamellChatPage marks verified through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugMarkVerified();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final verifiedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(verifiedPeer.verified, isTrue);
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.verified, isFalse);
  });

  testWidgets(
      'ShamellChatPage sets official notification mode through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    await state.debugSetPeerNotificationMode(OfficialNotificationMode.muted);
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(updatedPeer.muted, isTrue);
    expect(
      await state.debugLoadStoredOfficialNotificationMode(_peerId),
      'muted',
    );
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.muted, isFalse);
  });

  testWidgets(
      'ShamellChatPage bootstraps a changed peer key through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    final bundleIdentityKey = _curveKeyB64(77);
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      libsignalKeyApiEnabledOverride: true,
      fetchKeyBundleHandler: ({
        required String targetDeviceId,
        String? requesterDeviceId,
      }) async {
        return ChatKeyBundle(
          deviceId: targetDeviceId,
          identityKeyB64: bundleIdentityKey,
          identitySigningPubkeyB64: _curveKeyB64(78),
          signedPrekeyId: 1,
          signedPrekeyB64: _curveKeyB64(79),
          signedPrekeySigB64: 'sig',
        );
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugBootstrapCurrentPeerSession();
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedPeer = storedContacts.firstWhere((c) => c.id == _peerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId},
    );
    expect(updatedPeer.publicKeyB64, bundleIdentityKey);
    expect(updatedPeer.fingerprint, fingerprintForKey(bundleIdentityKey));
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.publicKeyB64, _curveKeyB64(49));
    expect(service.fetchKeyBundleCallCount, 1);
  });

  testWidgets(
      'ShamellChatPage reuses trusted local bootstrap state without fetching a new key bundle',
      (tester) async {
    final store = ChatLocalStore();
    final trustedPeerKey = _curveKeyB64(33);
    final trustedPeer = ChatContact(
      id: _peerId,
      publicKeyB64: trustedPeerKey,
      fingerprint: fingerprintForKey(trustedPeerKey),
      name: 'Peer',
    );
    await store.saveContacts(
      <ChatContact>[trustedPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.saveSessionBootstrapMeta(
      _peerId,
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 1,
      oneTimePrekeyId: 2,
      v2Only: true,
      identitySigningPubkeyB64: _curveKeyB64(78),
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      libsignalKeyApiEnabledOverride: true,
      fetchKeyBundleHandler: ({
        required String targetDeviceId,
        String? requesterDeviceId,
      }) async {
        throw StateError('fetchKeyBundle should not be called');
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );
    state.debugSeedDirectThread(me: _buildMe(), peer: trustedPeer);
    await tester.pump();

    await state.debugBootstrapCurrentPeerSession();
    await tester.pump();

    expect(service.fetchKeyBundleCallCount, 0);
  });

  testWidgets(
      'ShamellChatPage links official autochat through the targeted peer contact contract',
      (tester) async {
    const otherPeerId = 'peer-2';
    const officialId = 'official-1';
    const officialPeerId = 'peer-official';
    final store = ChatLocalStore();
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.markOfficialAutofollowed(
      officialId,
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      resolveDeviceHandler: (peerId) async {
        final publicKeyB64 = _curveKeyB64(91);
        return ChatContact(
          id: peerId,
          publicKeyB64: publicKeyB64,
          fingerprint: fingerprintForKey(publicKeyB64),
          name: 'Official Peer',
        );
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugEnsureServiceOfficialFollow(
      officialId: officialId,
      chatPeerId: officialPeerId,
    );
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final officialPeer =
        storedContacts.firstWhere((c) => c.id == officialPeerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, otherPeerId, officialPeerId},
    );
    expect(officialPeer.name, 'Official Peer');
    expect(
      await store.hasOfficialAutochat(
        officialPeerId,
        baseUrlOverride: _baseUrl,
      ),
      isTrue,
    );
    expect(preservedPeer.name, 'Other Peer');
    expect(preservedPeer.publicKeyB64, _curveKeyB64(49));
  });

  testWidgets(
      'ShamellChatPage official autochat reuses existing local contact without peer discovery',
      (tester) async {
    const officialId = 'official-1';
    const officialPeerId = 'peer-official';
    final store = ChatLocalStore();
    final officialPeer = ChatContact(
      id: officialPeerId,
      publicKeyB64: _curveKeyB64(91),
      fingerprint: fingerprintForKey(_curveKeyB64(91)),
      name: 'Official Peer',
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), officialPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.markOfficialAutofollowed(
      officialId,
      baseUrlOverride: _baseUrl,
    );
    final service = _FakeChatBootstrapService(
      resolveDeviceHandler: (peerId) async {
        throw const ChatHttpException(
          op: 'resolveDevice',
          statusCode: 404,
          body: '{"detail":"not found"}',
        );
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugEnsureServiceOfficialFollow(
      officialId: officialId,
      chatPeerId: officialPeerId,
    );
    await tester.pump();

    expect(service.resolveDeviceCallCount, 0);
    expect(
      await store.hasOfficialAutochat(
        officialPeerId,
        baseUrlOverride: _baseUrl,
      ),
      isTrue,
    );
  });

  testWidgets(
      'ShamellChatPage resets official local state after unfollow through the targeted peer contact contract',
      (tester) async {
    const officialId = 'official-1';
    const officialPeerId = 'peer-official';
    const otherPeerId = 'peer-2';
    final store = ChatLocalStore();
    final officialPeer = ChatContact(
      id: officialPeerId,
      publicKeyB64: _curveKeyB64(92),
      fingerprint: 'fp-official',
      name: 'Official Peer',
      muted: true,
    );
    final otherPeer = ChatContact(
      id: otherPeerId,
      publicKeyB64: _curveKeyB64(49),
      fingerprint: 'fp-peer-2',
      name: 'Other Peer',
      muted: true,
    );
    await store.saveContacts(
      <ChatContact>[_buildPeer(), officialPeer, otherPeer],
      baseUrlOverride: _baseUrl,
    );
    await store.markOfficialAutofollowed(
      officialId,
      baseUrlOverride: _baseUrl,
    );
    await store.markOfficialAutochat(
      officialPeerId,
      baseUrlOverride: _baseUrl,
    );
    await store.markOfficialAutoreplyShown(
      officialPeerId,
      baseUrlOverride: _baseUrl,
    );
    await store.setOfficialNotifMode(
      officialPeerId,
      OfficialNotificationMode.muted,
      baseUrlOverride: _baseUrl,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
      officialHttpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    state.debugSetCapabilities(
      const ShamellCapabilities(
        chat: true,
        payments: true,
        friends: false,
        moments: false,
        officialAccounts: true,
        channels: false,
        serviceNotifications: false,
        paymentsPhoneTargets: false,
      ),
    );
    await setSessionTokenForBaseUrl(
        _baseUrl, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

    await state.debugToggleOfficialFollowFromChat(
      officialId: officialId,
      kind: 'service',
      followed: true,
    );
    await tester.pump();

    final storedContacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    final updatedOfficialPeer =
        storedContacts.firstWhere((c) => c.id == officialPeerId);
    final preservedPeer = storedContacts.firstWhere((c) => c.id == otherPeerId);
    expect(updatedOfficialPeer.muted, isFalse);
    expect(preservedPeer.muted, isTrue);
    expect(
      storedContacts.map((c) => c.id).toSet(),
      <String>{_peerId, officialPeerId, otherPeerId},
    );
    expect(
      await store.hasOfficialAutochat(
        officialPeerId,
        baseUrlOverride: _baseUrl,
      ),
      isFalse,
    );
    expect(
      await store.hasOfficialAutofollowed(
        officialId,
        baseUrlOverride: _baseUrl,
      ),
      isFalse,
    );
    expect(
      await store.loadOfficialNotifMode(
        officialPeerId,
        baseUrlOverride: _baseUrl,
      ),
      OfficialNotificationMode.full,
    );
  });

  testWidgets('ShamellChatPage reauths on critical group prefs sync failure',
      (tester) async {
    final service = _FakeChatBootstrapService(
      fetchGroupPrefsError: criticalChatError,
    );
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSyncGroupPrefsFromServer();
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage uses paged group prefs sync', (tester) async {
    final service = _FakeChatBootstrapService(
      fetchGroupPrefsPagedHandler: ({
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatGroupPrefs>[
          ChatGroupPrefs(groupId: _groupId, muted: true, pinned: false),
        ];
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugSyncGroupPrefsFromServer();
    await tester.pump();

    expect(service.fetchGroupPrefsPagedCallCount, 1);
    expect(service.fetchGroupPrefsCallCount, 0);
  });

  testWidgets(
      'ShamellChatPage auto-recovers inbound ratchet window drift for unverified peers',
      (tester) async {
    var delivered = false;
    final service = _FakeChatBootstrapService(
      fetchInboxPagedHandler: ({
        required String deviceId,
        String? sinceIso,
        String? sinceId,
        int batchSize = 200,
        int maxPages = 25,
        int? retainLatestCount,
      }) async {
        if (delivered) return const <ChatMessage>[];
        delivered = true;
        return <ChatMessage>[
          ChatMessage(
            id: 'drift-msg-1',
            senderId: _peerId,
            recipientId: _meId,
            senderPubKeyB64: _curveKeyB64(33),
            nonceB64: base64Encode(Uint8List(24)),
            boxB64: base64Encode(utf8.encode('ciphertext')),
            createdAt: DateTime.utc(2026, 4, 6, 12, 0, 0),
            sealedSender: true,
            senderHint: 'fp-peer',
            keyId: 0,
            prevKeyId: 0,
            senderDhPubB64: _curveKeyB64(33),
          ),
        ];
      },
      resolveDeviceHandler: (peerId) async => _buildPeer(),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );
    await state.debugSeedRatchetForPeer(
      _peerId,
      RatchetState(
        rootKey: Uint8List.fromList(List<int>.filled(32, 1)),
        sendChainKey: Uint8List.fromList(List<int>.filled(32, 2)),
        recvChainKey: Uint8List.fromList(List<int>.filled(32, 3)),
        sendCount: 0,
        recvCount: 1,
        pn: 0,
        skipped: const <String, String>{},
        peerIdentity: 'fp-peer',
        dhPriv: Uint8List.fromList(List<int>.filled(32, 4)),
        dhPub: Uint8List.fromList(List<int>.filled(32, 5)),
        peerDhPub: base64Decode(_curveKeyB64(33)),
        peerDhPubB64: _curveKeyB64(33),
      ),
    );
    await tester.pump();

    await state.debugPullInbox();
    await tester.pump();
    await tester.pump();

    expect(service.resolveDeviceCallCount, 0);
    expect(state.debugCurrentRatchetWarning(), isNull);
  });

  testWidgets(
      'ShamellChatPage recovers inbound ratchet drift from the message sender key when peer refresh is unavailable',
      (tester) async {
    final me = _buildRealIdentity(id: _meId, seed: 11, name: 'Me');
    final stalePeerIdentity =
        _buildRealIdentity(id: _peerId, seed: 41, name: 'Peer old');
    final livePeerIdentity =
        _buildRealIdentity(id: _peerId, seed: 59, name: 'Peer live');
    final stalePeer = _contactForIdentity(stalePeerIdentity, name: 'Peer');
    var delivered = false;
    final service = _FakeChatBootstrapService(
      fetchInboxPagedHandler: ({
        required String deviceId,
        String? sinceIso,
        String? sinceId,
        int batchSize = 200,
        int maxPages = 25,
        int? retainLatestCount,
      }) async {
        if (delivered) return const <ChatMessage>[];
        delivered = true;
        return <ChatMessage>[
          _buildSealedRatchetMessage(
            sender: livePeerIdentity,
            recipient: me,
            text: 'hello recovered from sender key',
            id: 'sealed-inbound-recover-1',
            createdAt: DateTime.utc(2026, 4, 6, 13, 30, 0),
          ),
        ];
      },
      resolveDeviceHandler: (peerId) async {
        throw Exception('rate limited');
      },
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    state.debugSeedDirectThread(me: me, peer: stalePeer);
    await state.debugSeedRatchetForPeer(
      _peerId,
      RatchetState(
        rootKey: Uint8List.fromList(List<int>.filled(32, 1)),
        sendChainKey: Uint8List.fromList(List<int>.filled(32, 2)),
        recvChainKey: Uint8List.fromList(List<int>.filled(32, 3)),
        sendCount: 0,
        recvCount: 1,
        pn: 0,
        skipped: const <String, String>{},
        peerIdentity: stalePeerIdentity.fingerprint,
        dhPriv: Uint8List.fromList(List<int>.filled(32, 4)),
        dhPub: Uint8List.fromList(List<int>.filled(32, 5)),
        peerDhPub: base64Decode(stalePeerIdentity.publicKeyB64),
        peerDhPubB64: stalePeerIdentity.publicKeyB64,
      ),
    );
    await tester.pump();

    await state.debugPullInbox();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(service.resolveDeviceCallCount, 0);
    expect(state.debugCurrentRatchetWarning(), isNull);
    expect(find.text('hello recovered from sender key'), findsOneWidget);
  });

  testWidgets(
      'ShamellChatPage refreshes an unverified peer session before outbound send when a ratchet warning is active',
      (tester) async {
    final service = _FakeChatBootstrapService(
      resolveDeviceHandler: (peerId) async => _buildPeer(),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    state.debugSetRatchetWarning(
      'Message outside window; consider resetting session.',
    );
    await tester.pump();

    await state.debugSendDirectTextQuick('hello after warning');
    await tester.pump();

    expect(service.resolveDeviceCallCount, 1);
    expect(state.debugCurrentRatchetWarning(), isNull);
    expect(find.text('hello after warning'), findsOneWidget);
  });

  testWidgets(
      'ShamellChatPage decrypts an inbound sealed direct message from the initial identity-bound ratchet',
      (tester) async {
    final me = _buildRealIdentity(id: _meId, seed: 11, name: 'Me');
    final peerIdentity =
        _buildRealIdentity(id: _peerId, seed: 59, name: 'Peer');
    final peer = _contactForIdentity(peerIdentity, name: 'Peer');
    final inbound = _buildSealedRatchetMessage(
      sender: peerIdentity,
      recipient: me,
      text: 'hello secure inbound',
      id: 'sealed-inbound-1',
      createdAt: DateTime.utc(2026, 4, 6, 13, 0, 0),
    );
    final service = _FakeChatBootstrapService(
      fetchInboxPagedHandler: ({
        required String deviceId,
        String? sinceIso,
        String? sinceId,
        int batchSize = 200,
        int maxPages = 25,
        int? retainLatestCount,
      }) async {
        return <ChatMessage>[inbound];
      },
      resolveDeviceHandler: (peerId) async => peer,
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    state.debugSeedDirectThread(me: me, peer: peer);
    await tester.pump();
    await state.debugPullInbox();
    await tester.pump();
    await tester.pump();

    expect(find.text('hello secure inbound'), findsOneWidget);
    expect(state.debugCurrentRatchetWarning(), isNull);
  });

  testWidgets(
      'ShamellChatPage decrypts the same inbound sealed direct message idempotently across repeated UI reads',
      (tester) async {
    final me = _buildRealIdentity(id: _meId, seed: 19, name: 'Me');
    final peerIdentity =
        _buildRealIdentity(id: _peerId, seed: 83, name: 'Peer');
    final peer = _contactForIdentity(peerIdentity, name: 'Peer');
    final inbound = _buildSealedRatchetMessage(
      sender: peerIdentity,
      recipient: me,
      text: 'hello repeat inbound',
      id: 'sealed-inbound-repeat-1',
      createdAt: DateTime.utc(2026, 4, 6, 13, 2, 0),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedDirectThread(me: me, peer: peer);
    await tester.pump();

    expect(
      state.debugDecodeDirectMessageText(inbound),
      'hello repeat inbound',
    );
    expect(
      state.debugDecodeDirectMessageText(inbound),
      'hello repeat inbound',
    );
    expect(state.debugCurrentRatchetWarning(), isNull);
  });

  testWidgets(
      'ShamellChatPage decrypts its own sealed direct message using the active recipient session context',
      (tester) async {
    final me = _buildRealIdentity(id: _meId, seed: 13, name: 'Me');
    final peerIdentity =
        _buildRealIdentity(id: _peerId, seed: 73, name: 'Peer');
    final peer = _contactForIdentity(peerIdentity, name: 'Peer');
    final outbound = _buildSealedRatchetMessage(
      sender: me,
      recipient: peerIdentity,
      text: 'hello secure outbound',
      id: 'sealed-outbound-1',
      createdAt: DateTime.utc(2026, 4, 6, 13, 5, 0),
    );
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatBootstrapService(),
      onCritical: () {},
    );

    state.debugSeedDirectThread(
      me: me,
      peer: peer,
      messages: <ChatMessage>[outbound],
    );
    await tester.pump();

    expect(find.text('hello secure outbound'), findsOneWidget);
    expect(state.debugCurrentRatchetWarning(), isNull);
  });
}
