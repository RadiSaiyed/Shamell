import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_message_position_index.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';

void main() {
  ChatMessage message(String id) {
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

  test('buildChatMessagePositionIndex resolves message ids to list positions',
      () {
    final index = buildChatMessagePositionIndex(
      <ChatMessage>[
        message('m1'),
        message('m2'),
        message('m3'),
      ],
    );

    expect(index.indexOf('m1'), 0);
    expect(index.indexOf('m2'), 1);
    expect(index.indexOf('m3'), 2);
    expect(index.indexOf('missing'), -1);
  });

  test('buildChatMessagePositionIndex skips blank ids and keeps latest index',
      () {
    final index = buildChatMessagePositionIndex(
      <ChatMessage>[
        message('m1'),
        message(' '),
        message('m1'),
        message('m2'),
      ],
    );

    expect(index.indexOf(''), -1);
    expect(index.indexOf('m1'), 2);
    expect(index.indexOf('m2'), 3);
  });
}
