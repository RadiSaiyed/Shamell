import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_message_overview.dart';
import 'package:shamell_flutter/core/chat/chat_message_payload.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';

void main() {
  ChatMessage message({
    required String id,
    required String raw,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id,
      senderId: 'alice',
      recipientId: 'bob',
      senderPubKeyB64: 'sender-pub',
      nonceB64: 'nonce-$id',
      boxB64: raw,
      createdAt: createdAt ?? DateTime.utc(2026, 4, 22, 10),
      trustedLocalPlaintext: true,
    );
  }

  DecodedChatMessagePayload decode(ChatMessage message) {
    return decodeChatMessagePayload(
      utf8.decode(base64Decode(message.boxB64)),
    );
  }

  test('buildChatMessageOverviewIndex buckets messages once by type', () {
    final index = buildChatMessageOverviewIndex(
      <ChatMessage>[
        message(
          id: 'text',
          raw: base64Encode(
            utf8.encode('hello https://example.com'),
          ),
        ),
        message(
          id: 'media',
          raw: base64Encode(
            utf8.encode(
              jsonEncode({
                'text': 'photo',
                'attachment_b64':
                    base64Encode(Uint8List.fromList(<int>[1, 2, 3])),
                'attachment_mime': 'image/png',
              }),
            ),
          ),
        ),
        message(
          id: 'file',
          raw: base64Encode(
            utf8.encode(
              jsonEncode({
                'text': 'document',
                'attachment_b64':
                    base64Encode(Uint8List.fromList(<int>[4, 5, 6])),
                'attachment_mime': 'application/pdf',
              }),
            ),
          ),
        ),
        message(
          id: 'voice',
          raw: base64Encode(
            utf8.encode(
              jsonEncode({
                'text': 'voice note',
                'kind': 'voice',
                'voice_secs': 12,
                'attachment_b64':
                    base64Encode(Uint8List.fromList(<int>[7, 8, 9])),
                'attachment_mime': 'audio/aac',
              }),
            ),
          ),
        ),
      ],
      recalledMessageIds: const <String>{},
      decodeMessage: decode,
    );

    expect(index.entries.map((entry) => entry.message.id), <String>[
      'text',
      'media',
      'file',
      'voice',
    ]);
    expect(index.mediaEntries.map((entry) => entry.message.id), <String>[
      'media',
    ]);
    expect(index.fileEntries.map((entry) => entry.message.id), <String>[
      'file',
    ]);
    expect(index.linkEntries.map((entry) => entry.message.id), <String>[
      'text',
    ]);
    expect(index.voiceEntries.map((entry) => entry.message.id), <String>[
      'voice',
    ]);
  });

  test(
      'buildChatMessageOverviewIndex skips recalled messages and decode errors',
      () {
    final index = buildChatMessageOverviewIndex(
      <ChatMessage>[
        message(id: 'keep', raw: base64Encode(utf8.encode('keep me'))),
        message(id: 'drop', raw: base64Encode(utf8.encode('drop me'))),
        message(id: 'broken', raw: 'not-valid-base64'),
      ],
      recalledMessageIds: const <String>{'drop'},
      decodeMessage: (message) {
        if (message.id == 'broken') {
          throw StateError('broken');
        }
        return decode(message);
      },
    );

    expect(index.entries.map((entry) => entry.message.id), <String>['keep']);
  });

  test('filtered reuses prepared entries for query and filter combinations',
      () {
    final index = buildChatMessageOverviewIndex(
      <ChatMessage>[
        message(
            id: 'a', raw: base64Encode(utf8.encode('alpha link https://a'))),
        message(id: 'b', raw: base64Encode(utf8.encode('beta text'))),
        message(id: 'c', raw: base64Encode(utf8.encode('alpha voice'))),
      ],
      recalledMessageIds: const <String>{},
      decodeMessage: (message) {
        if (message.id == 'c') {
          return decodeChatMessagePayload(
            jsonEncode(
                {'text': 'alpha voice', 'kind': 'voice', 'voice_secs': 4}),
          );
        }
        return decode(message);
      },
    );

    expect(
      index
          .filtered(
            query: 'alpha',
            filter: ChatMessageOverviewFilter.all,
          )
          .map((entry) => entry.message.id),
      <String>['a', 'c'],
    );
    expect(
      index
          .filtered(
            query: 'alpha',
            filter: ChatMessageOverviewFilter.voice,
          )
          .map((entry) => entry.message.id),
      <String>['c'],
    );
    expect(
      index
          .filtered(
            query: '',
            filter: ChatMessageOverviewFilter.links,
          )
          .map((entry) => entry.message.id),
      <String>['a'],
    );
  });

  test('filtered can match metadata for attachments and contact cards', () {
    final index = buildChatMessageOverviewIndex(
      <ChatMessage>[
        message(
          id: 'pdf',
          raw: base64Encode(
            utf8.encode(
              jsonEncode({
                'text': '',
                'attachment_b64':
                    base64Encode(Uint8List.fromList(<int>[1, 2, 3])),
                'attachment_mime': 'application/pdf',
              }),
            ),
          ),
        ),
        message(
          id: 'contact',
          raw: base64Encode(
            utf8.encode(
              jsonEncode({
                'kind': 'contact',
                'contact_id': 'peer-42',
                'contact_name': 'Nadia',
              }),
            ),
          ),
        ),
      ],
      recalledMessageIds: const <String>{},
      decodeMessage: decode,
    );

    expect(
      index
          .filtered(query: 'pdf', filter: ChatMessageOverviewFilter.all)
          .map((entry) => entry.message.id),
      <String>['pdf'],
    );
    expect(
      index
          .filtered(query: 'nadia', filter: ChatMessageOverviewFilter.all)
          .map((entry) => entry.message.id),
      <String>['contact'],
    );
  });
}
