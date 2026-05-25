import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_message_payload.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/direct_message_search.dart';

void main() {
  ChatMessage message({
    required String id,
  }) {
    return ChatMessage(
      id: id,
      senderId: 'alice',
      recipientId: 'bob',
      senderPubKeyB64: 'sender-pub',
      nonceB64: 'nonce-$id',
      boxB64: 'box-$id',
      createdAt: DateTime.utc(2026, 4, 22, 9, 30),
      trustedLocalPlaintext: true,
    );
  }

  test('buildDirectMessageSearchHaystack includes preview and metadata', () {
    final haystack = buildDirectMessageSearchHaystack(
      decoded: decodeChatMessagePayload(
        jsonEncode({
          'text': 'hello',
          'reply_preview': 'earlier reply',
          'contact_name': 'Alice Example',
          'contact_id': 'alice-1',
          'attachment_mime': 'application/pdf',
          'attachment_b64': base64Encode(Uint8List.fromList(<int>[1, 2, 3])),
        }),
      ),
      previewText: 'Attachment hello',
    );

    expect(haystack, contains('hello'));
    expect(haystack, contains('earlier reply'));
    expect(haystack, contains('alice example'));
    expect(haystack, contains('alice-1'));
    expect(haystack, contains('application/pdf'));
    expect(haystack, contains('attachment hello'));
  });

  test('buildDirectMessageSearchMatchIds returns stable ids and skips recalled',
      () {
    final decodedById = <String, DecodedChatMessagePayload>{
      'm1': decodeChatMessagePayload(
        jsonEncode({
          'text': 'Quarterly report attached',
          'attachment_b64': base64Encode(Uint8List.fromList(<int>[1, 2, 3])),
          'attachment_mime': 'application/pdf',
        }),
      ),
      'm2': decodeChatMessagePayload(
        jsonEncode({
          'text': 'voice note',
          'kind': 'voice',
          'voice_secs': 8,
        }),
      ),
      'm3': decodeChatMessagePayload(
        jsonEncode({
          'text': '',
          'contact_name': 'Support Team',
          'contact_id': 'support',
          'kind': 'contact',
        }),
      ),
    };

    final messages = <ChatMessage>[
      message(id: 'm1'),
      message(id: 'm2'),
      message(id: 'm3'),
      message(id: ' '),
    ];

    final reportMatches = buildDirectMessageSearchMatchIds(
      messages,
      searchTerm: 'report',
      recalledMessageIds: const <String>{},
      decodeMessage: (message) => decodedById[message.id]!,
      previewText: (_, decoded) => decoded.attachment != null
          ? 'Attachment ${decoded.text}'
          : decoded.text,
    );
    final contactMatches = buildDirectMessageSearchMatchIds(
      messages,
      searchTerm: 'support',
      recalledMessageIds: const <String>{'m2'},
      decodeMessage: (message) => decodedById[message.id]!,
      previewText: (_, decoded) => decoded.contactName ?? decoded.text,
    );

    expect(reportMatches, <String>['m1']);
    expect(contactMatches, <String>['m3']);
  });

  test('buildDirectMessageSearchIndex caches repeated query matches', () {
    var decodeCalls = 0;
    final index = buildDirectMessageSearchIndex(
      <ChatMessage>[
        message(id: 'm1'),
        message(id: 'm2'),
      ],
      recalledMessageIds: const <String>{},
      decodeMessage: (message) {
        decodeCalls++;
        if (message.id == 'm1') {
          return decodeChatMessagePayload(
            jsonEncode(<String, Object?>{'text': 'Quarterly report'}),
          );
        }
        return decodeChatMessagePayload(
          jsonEncode(<String, Object?>{'text': 'Follow up note'}),
        );
      },
      previewText: (_, decoded) => decoded.text,
    );

    final firstMatches = index.matchIds('report');
    final secondMatches = index.matchIds('report');

    expect(decodeCalls, 2);
    expect(firstMatches, <String>['m1']);
    expect(identical(firstMatches, secondMatches), isTrue);
  });
}
