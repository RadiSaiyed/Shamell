import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_thread_presentation.dart';

void main() {
  String displayName(
    String id, {
    String? fallback,
  }) {
    return switch (id) {
      'alice' => 'Alice',
      'bob' => 'Bob',
      'me-1' => 'Me',
      _ => fallback ?? id,
    };
  }

  test('formatChatThreadTimestamp formats same-day timestamps as HH:mm', () {
    final value = formatChatThreadTimestamp(
      DateTime(2026, 4, 22, 9, 7),
      now: DateTime(2026, 4, 22, 18, 30),
    );

    expect(value, '09:07');
  });

  test('formatChatThreadTimestamp formats older timestamps as MM-dd', () {
    final value = formatChatThreadTimestamp(
      DateTime(2026, 4, 21, 9, 7),
      now: DateTime(2026, 4, 22, 18, 30),
    );

    expect(value, '04-21');
  });

  test('buildLatestChatCallPreview only overrides when call is newer', () {
    final call = ChatCallLogEntry(
      id: 'call-1',
      peerId: 'peer-1',
      ts: DateTime.utc(2026, 4, 22, 10),
      direction: 'out',
      kind: 'voice',
      accepted: true,
      duration: const Duration(seconds: 35),
    );

    expect(
      buildLatestChatCallPreview(
        latestCall: call,
        latestMessageAt: DateTime.utc(2026, 4, 22, 9),
        isArabic: false,
      ),
      'Outgoing Voice • 35s',
    );
    expect(
      buildLatestChatCallPreview(
        latestCall: call,
        latestMessageAt: DateTime.utc(2026, 4, 22, 11),
        isArabic: false,
      ),
      isNull,
    );
  });

  test('buildChatGroupThreadPreviewData formats system invite events', () {
    final preview = buildChatGroupThreadPreviewData(
      message: ChatGroupMessage(
        id: 'm1',
        groupId: 'g1',
        senderId: 'alice',
        text: '{"event":"invite","actor_id":"alice","member_ids":["bob"]}',
        kind: 'system',
        createdAt: DateTime.utc(2026, 4, 22, 10),
      ),
      displayName: displayName,
      isArabic: false,
      currentUserId: 'me-1',
      noMessagesYet: 'No messages yet',
      previewVoice: 'Voice message',
      previewImage: 'Image',
      encryptedMessageLabel: 'Encrypted message',
    );

    expect(preview.plainText, 'Alice invited Bob');
    expect(preview.hasStyledSegments, isFalse);
  });

  test('buildChatGroupThreadPreviewData builds rich segments for mentions', () {
    final preview = buildChatGroupThreadPreviewData(
      message: ChatGroupMessage(
        id: 'm2',
        groupId: 'g1',
        senderId: 'alice',
        text: 'hello @me-1 and @bob',
        kind: 'text',
        createdAt: DateTime.utc(2026, 4, 22, 10),
      ),
      displayName: displayName,
      isArabic: false,
      currentUserId: 'me-1',
      noMessagesYet: 'No messages yet',
      previewVoice: 'Voice message',
      previewImage: 'Image',
      encryptedMessageLabel: 'Encrypted message',
    );

    expect(preview.plainText, 'Alice: hello @Me and @Bob');
    expect(preview.hasStyledSegments, isTrue);
    expect(
      preview.segments
          .where((segment) =>
              segment.kind ==
              ChatGroupThreadPreviewSegmentKind.mentionHighlight)
          .map((segment) => segment.text),
      <String>['@Me'],
    );
  });
}
