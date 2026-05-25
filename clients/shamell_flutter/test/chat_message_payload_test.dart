import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/base64_bytes_cache.dart';
import 'package:shamell_flutter/core/chat/chat_message_payload.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';

void main() {
  ChatMessage message({
    required String id,
    String nonceB64 = 'nonce-1',
    String boxB64 = 'box-1',
  }) {
    return ChatMessage(
      id: id,
      senderId: 'alice',
      recipientId: 'bob',
      senderPubKeyB64: 'sender-pub',
      nonceB64: nonceB64,
      boxB64: boxB64,
      createdAt: DateTime.utc(2026, 4, 22, 9, 30),
      sealedSender: true,
    );
  }

  test('decodeChatMessagePayload parses structured payload fields', () {
    final raw = jsonEncode({
      'text': 'hello',
      'attachment_b64': base64Encode(Uint8List.fromList(<int>[1, 2, 3])),
      'attachment_mime': 'image/png',
      'kind': 'image',
      'voice_secs': 7,
      'reply_to_id': 'm0',
      'reply_preview': 'Earlier message',
      'client_ts': '2026-04-22T09:15:00.000Z',
      'lat': '40.123',
      'lon': 29.456,
      'contact_id': 'peer-7',
      'contact_name': 'Peer Seven',
      'sender_fp': 'fp-1',
      'session_hash': 'hash-1',
    });

    final payload = decodeChatMessagePayload(raw);

    expect(payload.text, 'hello');
    expect(payload.attachment, Uint8List.fromList(<int>[1, 2, 3]));
    expect(payload.mime, 'image/png');
    expect(payload.kind, 'image');
    expect(payload.voiceSecs, 7);
    expect(payload.replyToId, 'm0');
    expect(payload.replyPreview, 'Earlier message');
    expect(payload.clientTs, DateTime.parse('2026-04-22T09:15:00.000Z'));
    expect(payload.lat, 40.123);
    expect(payload.lon, 29.456);
    expect(payload.contactId, 'peer-7');
    expect(payload.contactName, 'Peer Seven');
    expect(payload.senderFingerprint, 'fp-1');
    expect(payload.sessionHash, 'hash-1');
  });

  test('decodeChatMessagePayload falls back to raw text for non-json payloads',
      () {
    final payload = decodeChatMessagePayload('plain text message');

    expect(payload.text, 'plain text message');
    expect(payload.attachment, isNull);
    expect(payload.kind, isNull);
    expect(payload.replyPreview, isNull);
  });

  test('ChatMessagePayloadCache reuses cached payloads for stable messages',
      () {
    final attachmentBytesCache = Base64BytesCache(maxEntries: 4);
    final payloadCache = ChatMessagePayloadCache(
      maxEntries: 4,
      attachmentBytesCache: attachmentBytesCache,
    );
    final raw = jsonEncode({
      'text': 'cached',
      'attachment_b64': base64Encode(Uint8List.fromList(<int>[4, 5, 6])),
      'attachment_mime': 'image/jpeg',
    });

    final first = payloadCache.decode(message(id: 'm1'), raw: raw);
    final second = payloadCache.decode(message(id: 'm1'), raw: raw);

    expect(identical(first, second), isTrue);
    expect(payloadCache.size, 1);
    expect(attachmentBytesCache.size, 1);
  });

  test('ChatMessagePayloadCache refreshes when raw changes for the same id',
      () {
    final payloadCache = ChatMessagePayloadCache(maxEntries: 4);
    final msg = message(id: 'm1');

    final first = payloadCache.decode(
      msg,
      raw: jsonEncode({'text': 'before'}),
    );
    final second = payloadCache.decode(
      msg,
      raw: jsonEncode({'text': 'after'}),
    );

    expect(first.text, 'before');
    expect(second.text, 'after');
    expect(identical(first, second), isFalse);
    expect(payloadCache.size, 1);
  });
}
