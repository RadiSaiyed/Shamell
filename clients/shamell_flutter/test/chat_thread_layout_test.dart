import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_thread_layout.dart';

void main() {
  ChatMessage message(
    String id,
    DateTime? createdAt, {
    String senderId = 'alice',
    String recipientId = 'bob',
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      senderPubKeyB64: 'sender-pub',
      nonceB64: 'nonce-$id',
      boxB64: 'box-$id',
      createdAt: createdAt,
      trustedLocalPlaintext: true,
    );
  }

  test(
      'shouldShowDirectThreadTimeHeader shows header for first timestamped item',
      () {
    expect(
      shouldShowDirectThreadTimeHeader(
        null,
        message('m1', DateTime.utc(2026, 4, 22, 9, 30)),
      ),
      isTrue,
    );
    expect(
      shouldShowDirectThreadTimeHeader(
        null,
        message('m2', null),
      ),
      isFalse,
    );
  });

  test('shouldShowDirectThreadTimeHeader groups nearby messages on same day',
      () {
    final previous = message('m1', DateTime.utc(2026, 4, 22, 9, 30));
    final current = message('m2', DateTime.utc(2026, 4, 22, 9, 37));

    expect(shouldShowDirectThreadTimeHeader(previous, current), isFalse);
  });

  test('shouldShowDirectThreadTimeHeader splits by gap and day boundary', () {
    final previous = message('m1', DateTime.utc(2026, 4, 22, 9, 30));
    final gapMessage = message('m2', DateTime.utc(2026, 4, 22, 9, 45));
    final nextDayMessage = message('m3', DateTime.utc(2026, 4, 23, 9, 35));

    expect(shouldShowDirectThreadTimeHeader(previous, gapMessage), isTrue);
    expect(
        shouldShowDirectThreadTimeHeader(gapMessage, nextDayMessage), isTrue);
  });

  test('buildDirectThreadListLayout prepares time headers and anchor index',
      () {
    final layout = buildDirectThreadListLayout(
      <ChatMessage>[
        message('m1', DateTime.utc(2026, 4, 22, 9, 30)),
        message('m2', DateTime.utc(2026, 4, 22, 9, 36)),
        message('m3', DateTime.utc(2026, 4, 22, 9, 49)),
        message('m4', DateTime.utc(2026, 4, 23, 10, 0)),
      ],
      newMessagesAnchorMessageId: ' m3 ',
      currentUserId: 'bob',
    );

    expect(layout.newMessagesIndex, 2);
    expect(
      layout.entries.map((entry) => entry.showTimeHeader).toList(),
      <bool>[true, false, true, true],
    );
    expect(layout.entries[2].message.id, 'm3');
  });

  test('buildDirectThreadListLayout groups consecutive messages by direction',
      () {
    final layout = buildDirectThreadListLayout(
      <ChatMessage>[
        message('m1', DateTime.utc(2026, 4, 22, 9, 30)),
        message('m2', DateTime.utc(2026, 4, 22, 9, 31)),
        message(
          'm3',
          DateTime.utc(2026, 4, 22, 9, 32),
          senderId: 'bob',
          recipientId: 'alice',
        ),
        message(
          'm4',
          DateTime.utc(2026, 4, 22, 9, 33),
          senderId: 'bob',
          recipientId: 'alice',
        ),
      ],
      currentUserId: 'bob',
    );

    expect(
      layout.entries.map((entry) => entry.incoming).toList(),
      <bool>[true, true, false, false],
    );
    expect(
      layout.entries.map((entry) => entry.showAvatar).toList(),
      <bool>[false, true, false, true],
    );
    expect(
      layout.entries.map((entry) => entry.showBubbleTail).toList(),
      <bool>[false, true, false, true],
    );
  });

  test('buildDirectThreadListLayout breaks clusters on time headers', () {
    final layout = buildDirectThreadListLayout(
      <ChatMessage>[
        message('m1', DateTime.utc(2026, 4, 22, 9, 30)),
        message('m2', DateTime.utc(2026, 4, 22, 9, 45)),
      ],
      currentUserId: 'bob',
    );

    expect(
      layout.entries.map((entry) => entry.showTimeHeader).toList(),
      <bool>[true, true],
    );
    expect(
      layout.entries.map((entry) => entry.showAvatar).toList(),
      <bool>[true, true],
    );
    expect(
      layout.entries.map((entry) => entry.showBubbleTail).toList(),
      <bool>[true, true],
    );
  });
}
