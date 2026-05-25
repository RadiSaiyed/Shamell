import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../base64_bytes_cache.dart';
import 'chat_models.dart';

class DecodedChatMessagePayload {
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
  final String? senderFingerprint;
  final String? sessionHash;

  const DecodedChatMessagePayload({
    required this.text,
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
    this.lon,
    this.senderFingerprint,
    this.sessionHash,
  });
}

DecodedChatMessagePayload decodeChatMessagePayload(
  String raw, {
  Base64BytesCache? attachmentBytesCache,
}) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final text = (decoded['text'] ?? '').toString();
      final attachmentRaw = (decoded['attachment_b64'] ?? '').toString().trim();
      Uint8List? attachment;
      String? mime;
      if (attachmentRaw.isNotEmpty) {
        try {
          attachment = attachmentBytesCache != null
              ? attachmentBytesCache.decode(attachmentRaw)
              : base64Decode(attachmentRaw);
          if (attachment != null) {
            mime = (decoded['attachment_mime'] ?? 'image/jpeg').toString();
          }
        } catch (_) {
          attachment = null;
          mime = null;
        }
      }

      final kind = (decoded['kind'] ?? '').toString().trim();
      final voiceSecsRaw = decoded['voice_secs'];
      final voiceSecs = voiceSecsRaw is num ? voiceSecsRaw.toInt() : null;
      final contactIdRaw = decoded['contact_id'] ?? decoded['contactId'];
      final contactId = (contactIdRaw ?? '').toString().trim();
      final contactNameRaw = decoded['contact_name'] ?? decoded['contactName'];
      final contactName = (contactNameRaw ?? '').toString().trim();
      final replyToIdRaw = (decoded['reply_to_id'] ?? '').toString().trim();
      final replyPreviewRaw = (decoded['reply_preview'] ?? '').toString();
      final senderFingerprintRaw =
          (decoded['sender_fp'] ?? '').toString().trim();
      final sessionHashRaw = (decoded['session_hash'] ?? '').toString().trim();

      final lat = _decodePayloadCoordinate(decoded['lat']);
      final lon = _decodePayloadCoordinate(decoded['lon']);

      final clientTsRaw = (decoded['client_ts'] ?? '').toString().trim();
      DateTime? clientTs;
      if (clientTsRaw.isNotEmpty) {
        try {
          clientTs = DateTime.parse(clientTsRaw);
        } catch (_) {
          clientTs = null;
        }
      }

      return DecodedChatMessagePayload(
        text: text,
        attachment: attachment,
        mime: mime,
        clientTs: clientTs,
        kind: kind.isEmpty ? null : kind,
        contactId: contactId.isEmpty ? null : contactId,
        contactName: contactName.isEmpty ? null : contactName,
        voiceSecs: voiceSecs,
        replyToId: replyToIdRaw.isEmpty ? null : replyToIdRaw,
        replyPreview: replyPreviewRaw.trim().isEmpty ? null : replyPreviewRaw,
        lat: lat,
        lon: lon,
        senderFingerprint:
            senderFingerprintRaw.isEmpty ? null : senderFingerprintRaw,
        sessionHash: sessionHashRaw.isEmpty ? null : sessionHashRaw,
      );
    }
  } catch (_) {}

  return DecodedChatMessagePayload(
    text: raw,
    attachment: null,
    mime: null,
    clientTs: null,
    kind: null,
    contactId: null,
    contactName: null,
    voiceSecs: null,
    replyToId: null,
    replyPreview: null,
    lat: null,
    lon: null,
    senderFingerprint: null,
    sessionHash: null,
  );
}

class ChatMessagePayloadCache {
  ChatMessagePayloadCache({
    this.maxEntries = 256,
    Base64BytesCache? attachmentBytesCache,
  }) : _attachmentBytesCache =
            attachmentBytesCache ?? Base64BytesCache(maxEntries: 256);

  final int maxEntries;
  final Base64BytesCache _attachmentBytesCache;
  final Map<String, _CachedChatMessagePayload> _entries =
      <String, _CachedChatMessagePayload>{};

  DecodedChatMessagePayload decode(
    ChatMessage message, {
    required String raw,
  }) {
    final key = _cacheKeyForMessage(message);
    final cached = _entries.remove(key);
    if (cached != null && cached.matches(message, raw)) {
      _entries[key] = cached;
      return cached.payload;
    }

    final payload = decodeChatMessagePayload(
      raw,
      attachmentBytesCache: _attachmentBytesCache,
    );
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _CachedChatMessagePayload.from(
      message: message,
      raw: raw,
      payload: payload,
    );
    return payload;
  }

  void clear() => _entries.clear();

  @visibleForTesting
  int get size => _entries.length;

  static String _cacheKeyForMessage(ChatMessage message) {
    final id = message.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    final createdAtMicros =
        message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0;
    return [
      message.senderId,
      message.recipientId,
      '$createdAtMicros',
      message.nonceB64,
    ].join('|');
  }
}

class _CachedChatMessagePayload {
  final String nonceB64;
  final String boxB64;
  final bool sealedSender;
  final bool trustedLocalPlaintext;
  final int createdAtMicros;
  final int rawHash;
  final int rawLength;
  final DecodedChatMessagePayload payload;

  const _CachedChatMessagePayload({
    required this.nonceB64,
    required this.boxB64,
    required this.sealedSender,
    required this.trustedLocalPlaintext,
    required this.createdAtMicros,
    required this.rawHash,
    required this.rawLength,
    required this.payload,
  });

  factory _CachedChatMessagePayload.from({
    required ChatMessage message,
    required String raw,
    required DecodedChatMessagePayload payload,
  }) {
    return _CachedChatMessagePayload(
      nonceB64: message.nonceB64,
      boxB64: message.boxB64,
      sealedSender: message.sealedSender,
      trustedLocalPlaintext: message.trustedLocalPlaintext,
      createdAtMicros: message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0,
      rawHash: raw.hashCode,
      rawLength: raw.length,
      payload: payload,
    );
  }

  bool matches(ChatMessage message, String raw) {
    return nonceB64 == message.nonceB64 &&
        boxB64 == message.boxB64 &&
        sealedSender == message.sealedSender &&
        trustedLocalPlaintext == message.trustedLocalPlaintext &&
        createdAtMicros ==
            (message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0) &&
        rawHash == raw.hashCode &&
        rawLength == raw.length;
  }
}

double? _decodePayloadCoordinate(Object? raw) {
  if (raw is num) {
    return raw.toDouble();
  }
  if (raw is String && raw.isNotEmpty) {
    return double.tryParse(raw);
  }
  return null;
}
