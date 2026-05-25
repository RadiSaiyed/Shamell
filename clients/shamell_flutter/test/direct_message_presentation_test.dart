import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_message_payload.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/direct_message_presentation.dart';

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

  test('buildDirectMessageTextPresentation highlights repeated matches', () {
    final presentation = buildDirectMessageTextPresentation(
      text: 'alpha beta alpha',
      searchTerm: 'alpha',
    );

    expect(presentation.plainText, 'alpha beta alpha');
    expect(
      presentation.segments.map((segment) => (segment.text, segment.kind)),
      <(String, DirectMessageTextSegmentKind)>[
        ('alpha', DirectMessageTextSegmentKind.highlight),
        (' beta ', DirectMessageTextSegmentKind.text),
        ('alpha', DirectMessageTextSegmentKind.highlight),
      ],
    );
  });

  test('buildDirectMessagePreviewText distinguishes image and file attachments',
      () {
    final imagePreview = buildDirectMessagePreviewText(
      decoded: decodeChatMessagePayload(
        jsonEncode({
          'text': 'caption',
          'attachment_b64': base64Encode(Uint8List.fromList(<int>[1, 2, 3])),
          'attachment_mime': 'image/png',
        }),
      ),
      isIncoming: true,
      isRecalled: false,
      recalledByOther: 'recalled-other',
      recalledByMe: 'recalled-me',
      previewVoice: '[Voice]',
      previewImage: '[Image]',
      previewUnknown: '<message>',
      previewLocation: 'Location',
      attachmentLabel: 'Attachment',
      contactCardLabel: 'Contact card',
      contactCardPrefix: 'Contact card: ',
    );
    final filePreview = buildDirectMessagePreviewText(
      decoded: decodeChatMessagePayload(
        jsonEncode({
          'attachment_b64': base64Encode(Uint8List.fromList(<int>[4, 5, 6])),
          'attachment_mime': 'application/pdf',
        }),
      ),
      isIncoming: true,
      isRecalled: false,
      recalledByOther: 'recalled-other',
      recalledByMe: 'recalled-me',
      previewVoice: '[Voice]',
      previewImage: '[Image]',
      previewUnknown: '<message>',
      previewLocation: 'Location',
      attachmentLabel: 'Attachment',
      contactCardLabel: 'Contact card',
      contactCardPrefix: 'Contact card: ',
    );

    expect(imagePreview, '[Image] caption');
    expect(filePreview, 'Attachment');
  });

  test(
      'buildDirectMessagePreviewPresentation classifies recalled, contact, and file previews',
      () {
    final recalled = buildDirectMessagePreviewPresentation(
      decoded: decodeChatMessagePayload(jsonEncode({'text': 'ignored'})),
      isIncoming: true,
      isRecalled: true,
      recalledByOther: 'recalled-other',
      recalledByMe: 'recalled-me',
      previewVoice: '[Voice]',
      previewImage: '[Image]',
      previewUnknown: '<message>',
      previewLocation: 'Location',
      attachmentLabel: 'Attachment',
      contactCardLabel: 'Contact card',
      contactCardPrefix: 'Contact card: ',
    );
    final contact = buildDirectMessagePreviewPresentation(
      decoded: decodeChatMessagePayload(
        jsonEncode({
          'kind': 'contact',
          'contact_name': 'Alice',
        }),
      ),
      isIncoming: true,
      isRecalled: false,
      recalledByOther: 'recalled-other',
      recalledByMe: 'recalled-me',
      previewVoice: '[Voice]',
      previewImage: '[Image]',
      previewUnknown: '<message>',
      previewLocation: 'Location',
      attachmentLabel: 'Attachment',
      contactCardLabel: 'Contact card',
      contactCardPrefix: 'Contact card: ',
    );
    final file = buildDirectMessagePreviewPresentation(
      decoded: decodeChatMessagePayload(
        jsonEncode({
          'attachment_b64': base64Encode(Uint8List.fromList(<int>[4, 5, 6])),
          'attachment_mime': 'application/pdf',
        }),
      ),
      isIncoming: true,
      isRecalled: false,
      recalledByOther: 'recalled-other',
      recalledByMe: 'recalled-me',
      previewVoice: '[Voice]',
      previewImage: '[Image]',
      previewUnknown: '<message>',
      previewLocation: 'Location',
      attachmentLabel: 'Attachment',
      contactCardLabel: 'Contact card',
      contactCardPrefix: 'Contact card: ',
    );

    expect(recalled.text, 'recalled-other');
    expect(recalled.kind, DirectMessagePreviewKind.recalled);
    expect(contact.text, 'Contact card: Alice');
    expect(contact.kind, DirectMessagePreviewKind.contact);
    expect(file.text, 'Attachment');
    expect(file.kind, DirectMessagePreviewKind.attachment);
  });

  test(
      'DirectMessagePresentationCache classifies file attachments and reuses cached entries',
      () {
    final cache = DirectMessagePresentationCache(maxEntries: 4);
    final decoded = decodeChatMessagePayload(
      jsonEncode({
        'text': 'Quarterly report',
        'attachment_b64': base64Encode(Uint8List.fromList(<int>[7, 8, 9])),
        'attachment_mime': 'application/pdf',
      }),
    );
    final msg = message(id: 'm1');

    final first = cache.build(
      msg,
      decoded: decoded,
      bodyText: decoded.text,
      searchTerm: 'report',
    );
    final second = cache.build(
      msg,
      decoded: decoded,
      bodyText: decoded.text,
      searchTerm: 'report',
    );

    expect(first.showsInlineImage, isFalse);
    expect(first.showsFileAttachment, isTrue);
    expect(first.body.hasHighlights, isTrue);
    expect(identical(first, second), isTrue);
    expect(cache.size, 1);
  });

  test(
      'buildDirectMessagePresentation keeps empty mime attachments inline-safe',
      () {
    final presentation = buildDirectMessagePresentation(
      decoded: decodeChatMessagePayload(
        jsonEncode({
          'attachment_b64': base64Encode(Uint8List.fromList(<int>[1, 3, 5])),
        }),
      ),
      bodyText: '',
      searchTerm: '',
    );

    expect(presentation.showsInlineImage, isTrue);
    expect(presentation.showsFileAttachment, isFalse);
  });
}
