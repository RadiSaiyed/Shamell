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

class ChatContact {
  final String id;
  final String publicKeyB64;
  final String fingerprint;
  final String? name;
  final bool verified;
  final DateTime? verifiedAt;
  final bool disappearing;
  final Duration? disappearAfter;
  final bool hidden;
  final bool blocked;
  final DateTime? blockedAt;

  const ChatContact({
    required this.id,
    required this.publicKeyB64,
    required this.fingerprint,
    this.name,
    this.verified = false,
    this.verifiedAt,
    this.disappearing = false,
    this.disappearAfter,
    this.hidden = false,
    this.blocked = false,
    this.blockedAt,
  });

  ChatContact copyWith({bool? verified, DateTime? verifiedAt, bool? disappearing, Duration? disappearAfter, bool? hidden, bool? blocked, DateTime? blockedAt}) => ChatContact(
        id: id,
        publicKeyB64: publicKeyB64,
        fingerprint: fingerprint,
        name: name,
        verified: verified ?? this.verified,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        disappearing: disappearing ?? this.disappearing,
        disappearAfter: disappearAfter ?? this.disappearAfter,
        hidden: hidden ?? this.hidden,
        blocked: blocked ?? this.blocked,
        blockedAt: blockedAt ?? this.blockedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'publicKeyB64': publicKeyB64,
        'fingerprint': fingerprint,
        'name': name,
        'verified': verified,
        'verifiedAt': verifiedAt?.toIso8601String(),
        'disappearing': disappearing,
        'disappearAfterSeconds': disappearAfter?.inSeconds,
        'hidden': hidden,
        'blocked': blocked,
        'blockedAt': blockedAt?.toIso8601String(),
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
      disappearing: (map['disappearing'] as bool?) ?? false,
      disappearAfter: map['disappearAfterSeconds'] != null
          ? Duration(seconds: (map['disappearAfterSeconds'] as num).toInt())
          : null,
      hidden: (map['hidden'] as bool?) ?? false,
      blocked: (map['blocked'] as bool?) ?? false,
      blockedAt: _parseIso(map['blockedAt'] as String?),
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
      };
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

String generateShortId({int length = 8}) {
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
