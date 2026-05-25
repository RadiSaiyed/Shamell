import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/base64_bytes_cache.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/group_message_presentation.dart';

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

  ChatGroupMessage message({
    required String id,
    required String text,
    String senderId = 'alice',
    String? kind,
    String? attachmentB64,
    String? attachmentMime,
    int? voiceSecs,
  }) {
    return ChatGroupMessage(
      id: id,
      groupId: 'group-1',
      senderId: senderId,
      text: text,
      kind: kind,
      attachmentB64: attachmentB64,
      attachmentMime: attachmentMime,
      voiceSecs: voiceSecs,
      createdAt: DateTime(2026, 4, 22, 9, 7),
    );
  }

  test('buildGroupMessageTextPresentation resolves and highlights mentions',
      () {
    final presentation = buildGroupMessageTextPresentation(
      text: 'hello @me-1 and @bob',
      displayName: displayName,
      currentUserId: 'me-1',
      isArabic: false,
    );

    expect(presentation.plainText, 'hello @Me and @Bob');
    expect(presentation.mentionsCurrentUser, isTrue);
    expect(presentation.mentionsAll, isFalse);
    expect(
      presentation.segments
          .where((segment) =>
              segment.kind == GroupMessageTextSegmentKind.mentionHighlight)
          .map((segment) => segment.text),
      <String>['@Me'],
    );
    expect(
      presentation.segments
          .where(
              (segment) => segment.kind == GroupMessageTextSegmentKind.mention)
          .map((segment) => segment.text),
      <String>['@Bob'],
    );
  });

  test('buildGroupMessagePresentation formats system events once', () {
    final presentation = buildGroupMessagePresentation(
      message: message(
        id: 'm1',
        senderId: 'alice',
        kind: 'system',
        text: jsonEncode({
          'event': 'invite',
          'actor_id': 'alice',
          'member_ids': <String>['bob'],
        }),
      ),
      isArabic: false,
      currentUserId: 'me-1',
      displayName: displayName,
      previewVoice: 'Voice message',
      previewImage: 'Image',
      previewUnknown: 'Unknown',
      encryptedMessageLabel: 'Encrypted message',
    );

    expect(presentation.isSystem, isTrue);
    expect(presentation.body.plainText, 'Alice invited Bob');
    expect(presentation.timestampLabel, '09:07');
  });

  test('buildGroupMessagePresentation decodes image attachments through cache',
      () {
    final attachmentBytesCache = Base64BytesCache(maxEntries: 4);
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    final presentation = buildGroupMessagePresentation(
      message: message(
        id: 'm2',
        senderId: 'alice',
        kind: 'image',
        text: '@bob',
        attachmentB64: base64Encode(bytes),
        attachmentMime: 'image/png',
      ),
      isArabic: false,
      currentUserId: 'me-1',
      displayName: displayName,
      previewVoice: 'Voice message',
      previewImage: 'Image',
      previewUnknown: 'Unknown',
      encryptedMessageLabel: 'Encrypted message',
      attachmentBytesCache: attachmentBytesCache,
    );

    expect(presentation.isImage, isTrue);
    expect(presentation.attachmentBytes, bytes);
    expect(presentation.body.plainText, '@Bob');
    expect(presentation.mentionPreview.plainText, 'Image @Bob');
    expect(presentation.rawText.mentionsAll, isFalse);
    expect(attachmentBytesCache.size, 1);
  });

  test('GroupMessagePresentationCache reuses stable entries', () {
    final cache = GroupMessagePresentationCache(
      maxEntries: 4,
      attachmentBytesCache: Base64BytesCache(maxEntries: 4),
    );
    final msg = message(id: 'm3', text: 'hello @bob');

    final first = cache.build(
      msg,
      isArabic: false,
      currentUserId: 'me-1',
      displayNamesRevision: 1,
      displayName: displayName,
      previewVoice: 'Voice message',
      previewImage: 'Image',
      previewUnknown: 'Unknown',
      encryptedMessageLabel: 'Encrypted message',
    );
    final second = cache.build(
      msg,
      isArabic: false,
      currentUserId: 'me-1',
      displayNamesRevision: 1,
      displayName: displayName,
      previewVoice: 'Voice message',
      previewImage: 'Image',
      previewUnknown: 'Unknown',
      encryptedMessageLabel: 'Encrypted message',
    );

    expect(identical(first, second), isTrue);
    expect(cache.size, 1);
  });

  test('GroupMessagePresentationCache invalidates on display-name revision',
      () {
    final cache = GroupMessagePresentationCache(maxEntries: 4);
    final msg = message(id: 'm4', text: 'hello @bob');

    final first = cache.build(
      msg,
      isArabic: false,
      currentUserId: 'me-1',
      displayNamesRevision: 1,
      displayName: displayName,
      previewVoice: 'Voice message',
      previewImage: 'Image',
      previewUnknown: 'Unknown',
      encryptedMessageLabel: 'Encrypted message',
    );
    final second = cache.build(
      msg,
      isArabic: false,
      currentUserId: 'me-1',
      displayNamesRevision: 2,
      displayName: (id, {fallback}) =>
          id == 'bob' ? 'Robert' : displayName(id, fallback: fallback),
      previewVoice: 'Voice message',
      previewImage: 'Image',
      previewUnknown: 'Unknown',
      encryptedMessageLabel: 'Encrypted message',
    );

    expect(first.body.plainText, 'hello @Bob');
    expect(second.body.plainText, 'hello @Robert');
    expect(identical(first, second), isFalse);
    expect(cache.size, 1);
  });
}
