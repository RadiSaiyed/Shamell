import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;

class ChatIdentity {
  final String id;
  final String publicKeyB64;
  final String privateKeyB64;
  final String fingerprint;
  final String? displayName;

  const ChatIdentity({
    required this.id,
    required this.publicKeyB64,
    required this.privateKeyB64,
    required this.fingerprint,
    this.displayName,
  });

  Map<String, String?> toMap() => {
        'id': id,
        'publicKeyB64': publicKeyB64,
        'privateKeyB64': privateKeyB64,
        'fingerprint': fingerprint,
        'displayName': displayName,
      };

  static ChatIdentity? fromMap(Map<String, Object?>? map) {
    if (map == null) return null;
    final id = map['id'] as String?;
    final pk = map['publicKeyB64'] as String?;
    final sk = map['privateKeyB64'] as String?;
    final fp = map['fingerprint'] as String?;
    if (id == null || pk == null || sk == null || fp == null) return null;
    return ChatIdentity(
      id: id,
      publicKeyB64: pk,
      privateKeyB64: sk,
      fingerprint: fp,
      displayName: map['displayName'] as String?,
    );
  }
}

class ChatOneTimePrekey {
  final int keyId;
  final String keyB64;

  const ChatOneTimePrekey({
    required this.keyId,
    required this.keyB64,
  });

  Map<String, Object?> toJson() => {
        'key_id': keyId,
        'key_b64': keyB64,
      };
}

class ChatPrekeyStatus {
  final String deviceId;
  final int availablePrekeys;
  final int recommendedUpload;

  const ChatPrekeyStatus({
    required this.deviceId,
    required this.availablePrekeys,
    required this.recommendedUpload,
  });

  factory ChatPrekeyStatus.fromJson(Map<String, Object?> map) =>
      ChatPrekeyStatus(
        deviceId: (map['device_id'] ?? '').toString(),
        availablePrekeys: _parseInt(map['available_prekeys']) ?? 0,
        recommendedUpload: _parseInt(map['recommended_upload']) ?? 0,
      );
}

class ChatKeyBundle {
  final String deviceId;
  final String identityKeyB64;
  final String? identitySigningPubkeyB64;
  final int signedPrekeyId;
  final String signedPrekeyB64;
  final String signedPrekeySigB64;
  final int? oneTimePrekeyId;
  final String? oneTimePrekeyB64;
  final String protocolFloor;
  final bool supportsV2;
  final bool v2Only;

  const ChatKeyBundle({
    required this.deviceId,
    required this.identityKeyB64,
    this.identitySigningPubkeyB64,
    required this.signedPrekeyId,
    required this.signedPrekeyB64,
    required this.signedPrekeySigB64,
    this.oneTimePrekeyId,
    this.oneTimePrekeyB64,
    this.protocolFloor = 'v1_legacy',
    this.supportsV2 = false,
    this.v2Only = false,
  });

  factory ChatKeyBundle.fromJson(Map<String, Object?> map) => ChatKeyBundle(
        deviceId: (map['device_id'] ?? '') as String,
        identityKeyB64: (map['identity_key_b64'] ?? '') as String,
        identitySigningPubkeyB64:
            (map['identity_signing_pubkey_b64'] as String?)?.trim().isEmpty ??
                    true
                ? null
                : (map['identity_signing_pubkey_b64'] as String).trim(),
        signedPrekeyId: _parseInt(map['signed_prekey_id']) ?? 0,
        signedPrekeyB64: (map['signed_prekey_b64'] ?? '') as String,
        signedPrekeySigB64: (map['signed_prekey_sig_b64'] ?? '') as String,
        oneTimePrekeyId: _parseInt(map['one_time_prekey_id']),
        oneTimePrekeyB64: () {
          final raw = (map['one_time_prekey_b64'] ?? '').toString().trim();
          return raw.isEmpty ? null : raw;
        }(),
        protocolFloor: (map['protocol_floor'] ?? 'v1_legacy').toString(),
        supportsV2: (map['supports_v2'] as bool?) ?? false,
        v2Only: (map['v2_only'] as bool?) ?? false,
      );
}

class ChatContact {
  final String id;
  final String publicKeyB64;
  final String fingerprint;
  final String? name;
  final bool verified;
  final DateTime? verifiedAt;
  final bool starred;
  final bool pinned;
  final bool disappearing;
  final Duration? disappearAfter;
  final bool archived;
  final bool hidden;
  final bool blocked;
  final DateTime? blockedAt;
  final bool muted;

  const ChatContact({
    required this.id,
    required this.publicKeyB64,
    required this.fingerprint,
    this.name,
    this.verified = false,
    this.verifiedAt,
    this.starred = false,
    this.pinned = false,
    this.disappearing = false,
    this.disappearAfter,
    this.archived = false,
    this.hidden = false,
    this.blocked = false,
    this.blockedAt,
    this.muted = false,
  });

  ChatContact copyWith({
    bool? verified,
    DateTime? verifiedAt,
    bool? starred,
    bool? pinned,
    bool? disappearing,
    Duration? disappearAfter,
    bool? archived,
    bool? hidden,
    bool? blocked,
    DateTime? blockedAt,
    bool? muted,
  }) =>
      ChatContact(
        id: id,
        publicKeyB64: publicKeyB64,
        fingerprint: fingerprint,
        name: name,
        verified: verified ?? this.verified,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        starred: starred ?? this.starred,
        pinned: pinned ?? this.pinned,
        disappearing: disappearing ?? this.disappearing,
        disappearAfter: disappearAfter ?? this.disappearAfter,
        archived: archived ?? this.archived,
        hidden: hidden ?? this.hidden,
        blocked: blocked ?? this.blocked,
        blockedAt: blockedAt ?? this.blockedAt,
        muted: muted ?? this.muted,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'publicKeyB64': publicKeyB64,
        'fingerprint': fingerprint,
        'name': name,
        'verified': verified,
        'verifiedAt': verifiedAt?.toIso8601String(),
        'starred': starred,
        'pinned': pinned,
        'disappearing': disappearing,
        'disappearAfterSeconds': disappearAfter?.inSeconds,
        'archived': archived,
        'hidden': hidden,
        'blocked': blocked,
        'blockedAt': blockedAt?.toIso8601String(),
        'muted': muted,
      };

  static ChatContact? fromMap(Map<String, Object?>? map) {
    if (map == null) return null;
    final id = map['id'] as String?;
    final pk = map['publicKeyB64'] as String?;
    final fp = map['fingerprint'] as String?;
    if (id == null || pk == null || fp == null) return null;
    return ChatContact(
      id: id,
      publicKeyB64: pk,
      fingerprint: fp,
      name: map['name'] as String?,
      verified: (map['verified'] as bool?) ?? false,
      verifiedAt: _parseIso(map['verifiedAt'] as String?),
      starred: (map['starred'] as bool?) ?? false,
      pinned: (map['pinned'] as bool?) ?? false,
      disappearing: (map['disappearing'] as bool?) ?? false,
      disappearAfter: map['disappearAfterSeconds'] != null
          ? Duration(seconds: (map['disappearAfterSeconds'] as num).toInt())
          : null,
      archived: (map['archived'] as bool?) ?? false,
      hidden: (map['hidden'] as bool?) ?? false,
      blocked: (map['blocked'] as bool?) ?? false,
      blockedAt: _parseIso(map['blockedAt'] as String?),
      muted: (map['muted'] as bool?) ?? false,
    );
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String senderPubKeyB64;
  final String nonceB64;
  final String boxB64;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? expireAt;
  final bool sealedSender;
  final String? senderHint;
  final int? keyId;
  final int? prevKeyId;
  final String? senderDhPubB64;
  final bool trustedLocalPlaintext;
  /// Inline "edited" marker — mirrors `messages.was_edited` server-side
  /// (P0-10). True when the message has been edited at least once;
  /// the bubble renders an "(edited)" tag next to the timestamp.
  /// Falls back to `false` for older payloads that don't carry the
  /// field — the user just won't see the marker, no crash.
  final bool wasEdited;
  /// Most recent edit timestamp. Null when never edited. Surfaced
  /// alongside the "(edited)" tag so users can see *when* the edit
  /// happened on long-press / accessibility tooltips.
  final DateTime? lastEditedAt;
  /// Monotonic per-conversation sequence number assigned by the
  /// server (P0-11, migration 0035). Strictly increasing within a
  /// 1:1 conversation; the counter is shared by both directions, so
  /// A→B and B→A messages interleave deterministically.
  ///
  /// `0` means "not yet known" — either the message is a local
  /// optimistic stub (still in flight) or the row predates migration
  /// 0035 (pre-migration legacy). Clients should:
  ///   * Use `seq` for ordering when both compared messages have
  ///     `seq > 0` (cleaner than `(createdAt, id)`).
  ///   * Fall back to `createdAt` when either has `seq == 0`.
  /// Catch-up replay will request `inbox since seq=N` (next cycle),
  /// where the BFF can stream all messages strictly greater than N
  /// without the timestamp tie-break ambiguity.
  final int seq;
  /// Cycle 4 reactions summary as returned by chat_service. Empty list
  /// when no reactions exist on the message. Each entry is `{emoji,
  /// count, has_me}` — the chat page parses this through
  /// `ChatReactionSummary.fromJson` for rendering.
  ///
  /// Kept as the raw `List<Map<String, Object?>>` shape so we don't
  /// drag the `ChatReactionSummary` type into the model layer (which
  /// is shared with non-chat-page code that doesn't need the widget
  /// dependency). The chat page does the typed conversion at render
  /// time via `ChatReactionSummary.listFromJson(message.reactions)`.
  final List<Map<String, Object?>> reactions;
  /// Cycle 13: `true` when this message was originally scheduled and
  /// drained by the server-side worker (Cycle 10), `false` for live
  /// sends. The bubble renders a small "scheduled" badge so the
  /// recipient knows the timing was deliberate. Falls back to
  /// `false` for legacy payloads that don't carry the field.
  final bool wasScheduled;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.senderPubKeyB64,
    required this.nonceB64,
    required this.boxB64,
    this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.expireAt,
    this.sealedSender = false,
    this.senderHint,
    this.keyId,
    this.prevKeyId,
    this.senderDhPubB64,
    this.trustedLocalPlaintext = false,
    this.wasEdited = false,
    this.lastEditedAt,
    this.seq = 0,
    this.reactions = const <Map<String, Object?>>[],
    this.wasScheduled = false,
  });

  static ChatMessage fromJson(Map<String, Object?> map) => ChatMessage(
        id: (map['id'] ?? '') as String,
        senderId: (map['sender_id'] ?? '') as String,
        recipientId: (map['recipient_id'] ?? '') as String,
        senderPubKeyB64: (map['sender_pubkey_b64'] ?? '') as String,
        nonceB64: (map['nonce_b64'] ?? '') as String,
        boxB64: (map['box_b64'] ?? '') as String,
        createdAt: _parseIso(map['created_at'] as String?),
        deliveredAt: _parseIso(map['delivered_at'] as String?),
        readAt: _parseIso(map['read_at'] as String?),
        expireAt: _parseIso(map['expire_at'] as String?),
        sealedSender: (map['sealed_sender'] as bool?) ?? false,
        senderHint: map['sender_hint'] as String?,
        keyId: _parseInt(map['key_id']),
        prevKeyId: _parseInt(map['prev_key_id']),
        senderDhPubB64: map['sender_dh_pub_b64'] as String?,
        trustedLocalPlaintext: false,
        wasEdited: (map['was_edited'] as bool?) ?? false,
        lastEditedAt: _parseIso(map['last_edited_at'] as String?),
        seq: _parseInt(map['seq']) ?? 0,
        reactions: _parseReactions(map['reactions']),
        wasScheduled: (map['was_scheduled'] as bool?) ?? false,
      );

  static ChatMessage fromMap(Map<String, Object?> map) => ChatMessage(
        id: (map['id'] ?? '') as String,
        senderId: (map['senderId'] ?? '') as String,
        recipientId: (map['recipientId'] ?? '') as String,
        senderPubKeyB64: (map['senderPubKeyB64'] ?? '') as String,
        nonceB64: (map['nonceB64'] ?? '') as String,
        boxB64: (map['boxB64'] ?? '') as String,
        createdAt: _parseIso(map['createdAt'] as String?),
        deliveredAt: _parseIso(map['deliveredAt'] as String?),
        readAt: _parseIso(map['readAt'] as String?),
        expireAt: _parseIso(map['expireAt'] as String?),
        sealedSender: (map['sealedSender'] as bool?) ?? false,
        senderHint: map['senderHint'] as String?,
        keyId: _parseInt(map['keyId']),
        prevKeyId: _parseInt(map['prevKeyId']),
        senderDhPubB64: map['senderDhPubB64'] as String?,
        trustedLocalPlaintext: (map['trustedLocalPlaintext'] as bool?) ?? false,
        wasEdited: (map['wasEdited'] as bool?) ?? false,
        lastEditedAt: _parseIso(map['lastEditedAt'] as String?),
        seq: _parseInt(map['seq']) ?? 0,
        wasScheduled: (map['wasScheduled'] as bool?) ?? false,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'senderId': senderId,
        'recipientId': recipientId,
        'senderPubKeyB64': senderPubKeyB64,
        'nonceB64': nonceB64,
        'boxB64': boxB64,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'deliveredAt': deliveredAt?.toUtc().toIso8601String(),
        'readAt': readAt?.toUtc().toIso8601String(),
        'expireAt': expireAt?.toUtc().toIso8601String(),
        'sealedSender': sealedSender,
        'senderHint': senderHint,
        'keyId': keyId,
        'prevKeyId': prevKeyId,
        'senderDhPubB64': senderDhPubB64,
        'trustedLocalPlaintext': trustedLocalPlaintext,
        'wasEdited': wasEdited,
        'lastEditedAt': lastEditedAt?.toUtc().toIso8601String(),
        'seq': seq,
        'wasScheduled': wasScheduled,
      };

  bool isOwnFor(String myId) {
    final normalizedMyId = myId.trim();
    if (normalizedMyId.isEmpty) return false;
    final normalizedSenderId = senderId.trim();
    if (normalizedSenderId.isNotEmpty) {
      return normalizedSenderId == normalizedMyId;
    }
    final normalizedRecipientId = recipientId.trim();
    if (normalizedRecipientId.isNotEmpty) {
      return normalizedRecipientId != normalizedMyId;
    }
    return false;
  }

  bool isIncomingFor(String myId) {
    final normalizedMyId = myId.trim();
    if (normalizedMyId.isEmpty) return false;
    final normalizedSenderId = senderId.trim();
    if (normalizedSenderId.isNotEmpty) {
      return normalizedSenderId != normalizedMyId;
    }
    final normalizedRecipientId = recipientId.trim();
    if (normalizedRecipientId.isNotEmpty) {
      return normalizedRecipientId == normalizedMyId;
    }
    return false;
  }

  String peerIdFor(String myId) {
    final normalizedMyId = myId.trim();
    final normalizedSenderId = senderId.trim();
    if (normalizedSenderId.isNotEmpty) {
      return normalizedSenderId == normalizedMyId
          ? recipientId
          : normalizedSenderId;
    }
    final normalizedRecipientId = recipientId.trim();
    if (normalizedRecipientId.isNotEmpty &&
        normalizedRecipientId != normalizedMyId) {
      return normalizedRecipientId;
    }
    return '';
  }
}

class ChatContactPrefs {
  final String peerId;
  final bool muted;
  final bool starred;
  final bool pinned;

  const ChatContactPrefs({
    required this.peerId,
    required this.muted,
    required this.starred,
    required this.pinned,
  });

  factory ChatContactPrefs.fromJson(Map<String, Object?> map) {
    final peerId = (map['peer_id'] ?? '') as String;
    return ChatContactPrefs(
      peerId: peerId,
      muted: (map['muted'] as bool?) ?? false,
      starred: (map['starred'] as bool?) ?? false,
      pinned: (map['pinned'] as bool?) ?? false,
    );
  }
}

class ChatGroupPrefs {
  final String groupId;
  final bool muted;
  final bool pinned;

  const ChatGroupPrefs({
    required this.groupId,
    required this.muted,
    required this.pinned,
  });

  factory ChatGroupPrefs.fromJson(Map<String, Object?> map) {
    final groupId = (map['group_id'] ?? '') as String;
    return ChatGroupPrefs(
      groupId: groupId,
      muted: (map['muted'] as bool?) ?? false,
      pinned: (map['pinned'] as bool?) ?? false,
    );
  }
}

class ChatCallLogEntry {
  final String id;
  final String peerId;
  final DateTime ts;
  final String direction; // 'out' or 'in'
  final String kind; // 'video' or 'voice'
  final bool accepted;
  final Duration duration;

  const ChatCallLogEntry({
    required this.id,
    required this.peerId,
    required this.ts,
    required this.direction,
    required this.kind,
    required this.accepted,
    required this.duration,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'peerId': peerId,
        'ts': ts.toUtc().toIso8601String(),
        'direction': direction,
        'kind': kind,
        'accepted': accepted,
        'durationSeconds': duration.inSeconds,
      };

  static ChatCallLogEntry fromMap(Map<String, Object?> map) => ChatCallLogEntry(
        id: (map['id'] ?? map['call_id'] ?? '').toString(),
        peerId: (map['peerId'] ?? map['peer_id'] ?? '').toString(),
        ts: _parseIso(
              (map['ts'] ?? map['started_at'] ?? map['created_at'])?.toString(),
            ) ??
            DateTime.now(),
        direction: (map['direction'] ?? 'out').toString(),
        kind: (map['kind'] ?? 'video').toString(),
        accepted: (map['accepted'] as bool?) ?? false,
        duration: Duration(
          seconds: _parseInt(
                map['durationSeconds'] ?? map['duration_seconds'],
              ) ??
              0,
        ),
      );
}

class ChatConversationEvent {
  final int eventId;
  final String deviceId;
  final String? peerId;
  final String eventType;
  final String resourceId;
  final Map<String, Object?> payload;
  final DateTime? createdAt;

  const ChatConversationEvent({
    required this.eventId,
    required this.deviceId,
    this.peerId,
    required this.eventType,
    required this.resourceId,
    this.payload = const <String, Object?>{},
    this.createdAt,
  });

  factory ChatConversationEvent.fromJson(Map<String, Object?> map) {
    final rawPayload = map['payload'];
    return ChatConversationEvent(
      eventId: _parseInt(map['event_id']) ?? 0,
      deviceId: (map['device_id'] ?? '').toString(),
      peerId: (map['peer_id'] ?? '').toString().trim().isEmpty
          ? null
          : (map['peer_id'] ?? '').toString(),
      eventType: (map['event_type'] ?? '').toString(),
      resourceId: (map['resource_id'] ?? '').toString(),
      payload: rawPayload is Map
          ? rawPayload.cast<String, Object?>()
          : const <String, Object?>{},
      createdAt: _parseIso(map['created_at']?.toString()),
    );
  }
}

class ChatVoiceTranscriptJob {
  final String id;
  final String messageId;
  final String deviceId;
  final String status;
  final String? language;
  final String? error;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ChatVoiceTranscriptJob({
    required this.id,
    required this.messageId,
    required this.deviceId,
    required this.status,
    this.language,
    this.error,
    this.createdAt,
    this.updatedAt,
  });

  factory ChatVoiceTranscriptJob.fromJson(Map<String, Object?> map) =>
      ChatVoiceTranscriptJob(
        id: (map['id'] ?? '').toString(),
        messageId: (map['message_id'] ?? '').toString(),
        deviceId: (map['device_id'] ?? '').toString(),
        status: (map['status'] ?? '').toString(),
        language: (map['language'] ?? '').toString().trim().isEmpty
            ? null
            : (map['language'] ?? '').toString(),
        error: (map['error'] ?? '').toString().trim().isEmpty
            ? null
            : (map['error'] ?? '').toString(),
        createdAt: _parseIso(map['created_at']?.toString()),
        updatedAt: _parseIso(map['updated_at']?.toString()),
      );
}

class ChatGroup {
  final String id;
  final String name;
  final String creatorId;
  final DateTime? createdAt;
  final int memberCount;
  final int keyVersion;
  final String? avatarB64;
  final String? avatarMime;

  const ChatGroup({
    required this.id,
    required this.name,
    required this.creatorId,
    this.createdAt,
    this.memberCount = 0,
    this.keyVersion = 0,
    this.avatarB64,
    this.avatarMime,
  });

  static ChatGroup fromJson(Map<String, Object?> map) => ChatGroup(
        id: (map['group_id'] ?? map['id'] ?? '') as String,
        name: (map['name'] ?? '') as String,
        creatorId: (map['creator_id'] ?? '') as String,
        createdAt: _parseIso(map['created_at'] as String?),
        memberCount: (map['member_count'] as num?)?.toInt() ?? 0,
        keyVersion: (map['key_version'] as num?)?.toInt() ??
            int.tryParse((map['key_version'] ?? '').toString()) ??
            0,
        avatarB64: map['avatar_b64'] as String?,
        avatarMime: map['avatar_mime'] as String?,
      );
}

class ChatGroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String text;
  final String? kind;
  final String? nonceB64;
  final String? boxB64;
  final String? attachmentB64;
  final String? attachmentMime;
  final int? voiceSecs;
  final double? lat;
  final double? lon;
  final String? contactId;
  final String? contactName;
  final DateTime? createdAt;
  final DateTime? expireAt;

  const ChatGroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.text,
    this.kind,
    this.nonceB64,
    this.boxB64,
    this.attachmentB64,
    this.attachmentMime,
    this.voiceSecs,
    this.lat,
    this.lon,
    this.contactId,
    this.contactName,
    this.createdAt,
    this.expireAt,
  });

  static ChatGroupMessage fromJson(Map<String, Object?> map) =>
      ChatGroupMessage(
        id: (map['id'] ?? '') as String,
        groupId: (map['group_id'] ?? '') as String,
        senderId: (map['sender_id'] ?? '') as String,
        text: (map['text'] ?? '') as String,
        kind: () {
          final raw = (map['kind'] ?? '').toString().trim();
          return raw.isEmpty ? null : raw;
        }(),
        nonceB64: map['nonce_b64'] as String?,
        boxB64: map['box_b64'] as String?,
        attachmentB64: map['attachment_b64'] as String?,
        attachmentMime: map['attachment_mime'] as String?,
        voiceSecs: _parseInt(map['voice_secs']),
        lat: _parseDouble(map['lat']),
        lon: _parseDouble(map['lon']),
        contactId: () {
          final raw = (map['contact_id'] ?? map['contactId']);
          final s = (raw ?? '').toString().trim();
          return s.isEmpty ? null : s;
        }(),
        contactName: () {
          final raw = (map['contact_name'] ?? map['contactName']);
          final s = (raw ?? '').toString().trim();
          return s.isEmpty ? null : s;
        }(),
        createdAt: _parseIso(map['created_at'] as String?),
        expireAt: _parseIso(map['expire_at'] as String?),
      );
}

class ChatGroupKeyEvent {
  final String groupId;
  final int version;
  final String actorId;
  final String? keyFp;
  final DateTime? createdAt;

  const ChatGroupKeyEvent({
    required this.groupId,
    required this.version,
    required this.actorId,
    this.keyFp,
    this.createdAt,
  });

  static ChatGroupKeyEvent fromJson(Map<String, Object?> map) {
    final rawVersion = map['version'];
    final version = rawVersion is num
        ? rawVersion.toInt()
        : int.tryParse((rawVersion ?? '').toString()) ?? 0;
    return ChatGroupKeyEvent(
      groupId: (map['group_id'] ?? '') as String,
      version: version,
      actorId: (map['actor_id'] ?? '') as String,
      keyFp: map['key_fp'] as String?,
      createdAt: _parseIso(map['created_at'] as String?),
    );
  }
}

class ChatGroupMember {
  final String deviceId;
  final String role;
  final DateTime? joinedAt;

  const ChatGroupMember({
    required this.deviceId,
    required this.role,
    this.joinedAt,
  });

  static ChatGroupMember fromJson(Map<String, Object?> map) => ChatGroupMember(
        deviceId: (map['device_id'] ?? '') as String,
        role: (map['role'] ?? 'member') as String,
        joinedAt: _parseIso(map['joined_at'] as String?),
      );
}

class ChatGroupInboxUpdate {
  final String groupId;
  final List<ChatGroupMessage> messages;

  const ChatGroupInboxUpdate({
    required this.groupId,
    required this.messages,
  });
}

enum ChatTypingScope { direct, group }

class ChatTypingSignal {
  final ChatTypingScope scope;
  final String fromDeviceId;
  final String? peerId;
  final String? groupId;
  final bool isTyping;
  final DateTime? sentAt;

  const ChatTypingSignal({
    required this.scope,
    required this.fromDeviceId,
    required this.isTyping,
    this.peerId,
    this.groupId,
    this.sentAt,
  });

  static ChatTypingSignal? fromJson(Map<String, Object?> map) {
    final rawType = (map['type'] ?? 'typing').toString().trim().toLowerCase();
    if (rawType != 'typing') return null;
    final fromDeviceId = (map['from_device_id'] ?? '').toString().trim();
    if (fromDeviceId.isEmpty) return null;
    final scopeRaw = (map['scope'] ?? '').toString().trim().toLowerCase();
    final isTyping = _parseTypingBool(map['is_typing']);
    final sentAt = _parseIso(map['sent_at'] as String?);
    switch (scopeRaw) {
      case 'direct':
        final peerId = (map['peer_id'] ?? '').toString().trim();
        if (peerId.isEmpty) return null;
        return ChatTypingSignal(
          scope: ChatTypingScope.direct,
          fromDeviceId: fromDeviceId,
          peerId: peerId,
          isTyping: isTyping,
          sentAt: sentAt,
        );
      case 'group':
        final groupId = (map['group_id'] ?? '').toString().trim();
        if (groupId.isEmpty) return null;
        return ChatTypingSignal(
          scope: ChatTypingScope.group,
          fromDeviceId: fromDeviceId,
          groupId: groupId,
          isTyping: isTyping,
          sentAt: sentAt,
        );
      default:
        return null;
    }
  }
}

DateTime? _parseIso(String? v) {
  if (v == null || v.isEmpty) return null;
  try {
    return DateTime.parse(v).toLocal();
  } catch (_) {
    return null;
  }
}

String fingerprintForKey(String publicKeyB64) {
  try {
    final bytes = base64Decode(publicKeyB64);
    final h = crypto.sha256.convert(bytes).bytes;
    final hex = h.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return hex.substring(0, 16);
  } catch (_) {
    return '';
  }
}

String generateShortId({int length = 24}) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(length, (_) => alphabet[rnd.nextInt(alphabet.length)])
      .join();
}

int? _parseInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

double? _parseDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Cycle 4: tolerantly parse the `reactions` array on a chat message
/// response. Returns an empty list when the field is missing or
/// malformed — the renderer treats "no reactions" as the most common
/// case so a parse failure must never crash the inbox load.
List<Map<String, Object?>> _parseReactions(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map((m) => Map<String, Object?>.from(m))
      .toList(growable: false);
}

bool _parseTypingBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = (value ?? '').toString().trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}
