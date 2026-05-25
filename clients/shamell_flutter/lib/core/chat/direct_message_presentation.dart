import 'package:flutter/foundation.dart';

import 'chat_message_payload.dart';
import 'chat_models.dart';

enum DirectMessageTextSegmentKind { text, highlight }

class DirectMessageTextSegment {
  final String text;
  final DirectMessageTextSegmentKind kind;

  const DirectMessageTextSegment({
    required this.text,
    this.kind = DirectMessageTextSegmentKind.text,
  });
}

class DirectMessageTextPresentation {
  final String plainText;
  final List<DirectMessageTextSegment> segments;

  const DirectMessageTextPresentation({
    required this.plainText,
    this.segments = const <DirectMessageTextSegment>[],
  });

  bool get hasHighlights => segments.any(
        (segment) => segment.kind == DirectMessageTextSegmentKind.highlight,
      );
}

class DirectMessagePresentation {
  final String kind;
  final String mime;
  final DirectMessageTextPresentation body;
  final String replyPreview;
  final bool hasAttachment;
  final bool showsInlineImage;
  final bool showsFileAttachment;
  final Uint8List? attachmentBytes;
  final int voiceSecs;
  final double? lat;
  final double? lon;
  final String contactId;
  final String contactName;

  const DirectMessagePresentation({
    required this.kind,
    required this.mime,
    required this.body,
    required this.replyPreview,
    required this.hasAttachment,
    required this.showsInlineImage,
    required this.showsFileAttachment,
    required this.attachmentBytes,
    required this.voiceSecs,
    required this.lat,
    required this.lon,
    required this.contactId,
    required this.contactName,
  });
}

enum DirectMessagePreviewKind {
  text,
  voice,
  image,
  attachment,
  location,
  contact,
  recalled,
}

class DirectMessagePreviewPresentation {
  final String text;
  final DirectMessagePreviewKind kind;

  const DirectMessagePreviewPresentation({
    required this.text,
    required this.kind,
  });
}

DirectMessageTextPresentation buildDirectMessageTextPresentation({
  required String text,
  required String searchTerm,
}) {
  final normalizedSearchTerm = searchTerm.trim();
  if (normalizedSearchTerm.isEmpty || text.isEmpty) {
    return DirectMessageTextPresentation(plainText: text);
  }
  final lowerText = text.toLowerCase();
  final lowerTerm = normalizedSearchTerm.toLowerCase();
  if (!lowerText.contains(lowerTerm)) {
    return DirectMessageTextPresentation(plainText: text);
  }

  final segments = <DirectMessageTextSegment>[];
  var start = 0;
  while (true) {
    final index = lowerText.indexOf(lowerTerm, start);
    if (index < 0) {
      if (start < text.length) {
        segments.add(DirectMessageTextSegment(text: text.substring(start)));
      }
      break;
    }
    if (index > start) {
      segments.add(
        DirectMessageTextSegment(text: text.substring(start, index)),
      );
    }
    segments.add(
      DirectMessageTextSegment(
        text: text.substring(index, index + normalizedSearchTerm.length),
        kind: DirectMessageTextSegmentKind.highlight,
      ),
    );
    start = index + normalizedSearchTerm.length;
  }

  return DirectMessageTextPresentation(
    plainText: text,
    segments: segments,
  );
}

DirectMessagePreviewPresentation buildDirectMessagePreviewPresentation({
  required DecodedChatMessagePayload decoded,
  required bool isIncoming,
  required bool isRecalled,
  required String recalledByOther,
  required String recalledByMe,
  required String previewVoice,
  required String previewImage,
  required String previewUnknown,
  required String previewLocation,
  required String attachmentLabel,
  required String contactCardLabel,
  required String contactCardPrefix,
}) {
  if (isRecalled) {
    return DirectMessagePreviewPresentation(
      text: isIncoming ? recalledByOther : recalledByMe,
      kind: DirectMessagePreviewKind.recalled,
    );
  }

  final kind = (decoded.kind ?? '').trim().toLowerCase();
  final text = decoded.text.trim();
  final hasAttachment =
      decoded.attachment != null && decoded.attachment!.isNotEmpty;
  final mime = (decoded.mime ?? '').trim().toLowerCase();
  final showsImagePreview = mime.isEmpty || mime.startsWith('image/');

  if (kind == 'contact') {
    final name =
        text.isNotEmpty ? text : (decoded.contactName ?? '').toString().trim();
    return DirectMessagePreviewPresentation(
      text: name.isNotEmpty ? '$contactCardPrefix$name' : contactCardLabel,
      kind: DirectMessagePreviewKind.contact,
    );
  }
  if (kind == 'voice') {
    return DirectMessagePreviewPresentation(
      text: previewVoice,
      kind: DirectMessagePreviewKind.voice,
    );
  }
  if (kind == 'location') {
    if (text.isNotEmpty) {
      return DirectMessagePreviewPresentation(
        text: text,
        kind: DirectMessagePreviewKind.location,
      );
    }
    if (decoded.lat != null && decoded.lon != null) {
      return DirectMessagePreviewPresentation(
        text: previewLocation,
        kind: DirectMessagePreviewKind.location,
      );
    }
  }
  if (hasAttachment) {
    final prefix = showsImagePreview ? previewImage : attachmentLabel;
    return DirectMessagePreviewPresentation(
      text: text.isNotEmpty ? '$prefix $text' : prefix,
      kind: showsImagePreview
          ? DirectMessagePreviewKind.image
          : DirectMessagePreviewKind.attachment,
    );
  }
  if (text.isNotEmpty) {
    return DirectMessagePreviewPresentation(
      text: text,
      kind: DirectMessagePreviewKind.text,
    );
  }
  return DirectMessagePreviewPresentation(
    text: previewUnknown,
    kind: DirectMessagePreviewKind.text,
  );
}

String buildDirectMessagePreviewText({
  required DecodedChatMessagePayload decoded,
  required bool isIncoming,
  required bool isRecalled,
  required String recalledByOther,
  required String recalledByMe,
  required String previewVoice,
  required String previewImage,
  required String previewUnknown,
  required String previewLocation,
  required String attachmentLabel,
  required String contactCardLabel,
  required String contactCardPrefix,
}) {
  return buildDirectMessagePreviewPresentation(
    decoded: decoded,
    isIncoming: isIncoming,
    isRecalled: isRecalled,
    recalledByOther: recalledByOther,
    recalledByMe: recalledByMe,
    previewVoice: previewVoice,
    previewImage: previewImage,
    previewUnknown: previewUnknown,
    previewLocation: previewLocation,
    attachmentLabel: attachmentLabel,
    contactCardLabel: contactCardLabel,
    contactCardPrefix: contactCardPrefix,
  ).text;
}

DirectMessagePresentation buildDirectMessagePresentation({
  required DecodedChatMessagePayload decoded,
  required String bodyText,
  required String searchTerm,
}) {
  final kind = (decoded.kind ?? '').trim().toLowerCase();
  final mime = (decoded.mime ?? '').trim().toLowerCase();
  final attachment = decoded.attachment;
  final hasAttachment = attachment != null && attachment.isNotEmpty;
  final showsInlineImage = hasAttachment &&
      kind != 'voice' &&
      (mime.isEmpty || mime.startsWith('image/'));
  final showsFileAttachment =
      hasAttachment && kind != 'voice' && !showsInlineImage;

  return DirectMessagePresentation(
    kind: kind,
    mime: mime,
    body: buildDirectMessageTextPresentation(
      text: bodyText,
      searchTerm: searchTerm,
    ),
    replyPreview: (decoded.replyPreview ?? '').trim(),
    hasAttachment: hasAttachment,
    showsInlineImage: showsInlineImage,
    showsFileAttachment: showsFileAttachment,
    attachmentBytes: attachment,
    voiceSecs: decoded.voiceSecs ?? 0,
    lat: decoded.lat,
    lon: decoded.lon,
    contactId: (decoded.contactId ?? '').trim(),
    contactName: (decoded.contactName ?? '').trim(),
  );
}

class DirectMessagePresentationCache {
  DirectMessagePresentationCache({
    this.maxEntries = 256,
  });

  final int maxEntries;
  final Map<String, _CachedDirectMessagePresentation> _entries =
      <String, _CachedDirectMessagePresentation>{};

  DirectMessagePresentation build(
    ChatMessage message, {
    required DecodedChatMessagePayload decoded,
    required String bodyText,
    required String searchTerm,
  }) {
    final key = _cacheKeyForMessage(message);
    final cached = _entries.remove(key);
    if (cached != null &&
        cached.matches(
          message,
          decoded: decoded,
          bodyText: bodyText,
          searchTerm: searchTerm,
        )) {
      _entries[key] = cached;
      return cached.presentation;
    }

    final presentation = buildDirectMessagePresentation(
      decoded: decoded,
      bodyText: bodyText,
      searchTerm: searchTerm,
    );
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _CachedDirectMessagePresentation.from(
      message: message,
      decoded: decoded,
      bodyText: bodyText,
      searchTerm: searchTerm,
      presentation: presentation,
    );
    return presentation;
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

class _CachedDirectMessagePresentation {
  final String nonceB64;
  final String boxB64;
  final bool sealedSender;
  final bool trustedLocalPlaintext;
  final int createdAtMicros;
  final String text;
  final String kind;
  final String mime;
  final bool hasAttachment;
  final int voiceSecs;
  final double? lat;
  final double? lon;
  final String contactId;
  final String contactName;
  final String replyPreview;
  final String bodyText;
  final String searchTerm;
  final DirectMessagePresentation presentation;

  const _CachedDirectMessagePresentation({
    required this.nonceB64,
    required this.boxB64,
    required this.sealedSender,
    required this.trustedLocalPlaintext,
    required this.createdAtMicros,
    required this.text,
    required this.kind,
    required this.mime,
    required this.hasAttachment,
    required this.voiceSecs,
    required this.lat,
    required this.lon,
    required this.contactId,
    required this.contactName,
    required this.replyPreview,
    required this.bodyText,
    required this.searchTerm,
    required this.presentation,
  });

  factory _CachedDirectMessagePresentation.from({
    required ChatMessage message,
    required DecodedChatMessagePayload decoded,
    required String bodyText,
    required String searchTerm,
    required DirectMessagePresentation presentation,
  }) {
    final attachment = decoded.attachment;
    return _CachedDirectMessagePresentation(
      nonceB64: message.nonceB64,
      boxB64: message.boxB64,
      sealedSender: message.sealedSender,
      trustedLocalPlaintext: message.trustedLocalPlaintext,
      createdAtMicros: message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0,
      text: decoded.text,
      kind: (decoded.kind ?? '').trim().toLowerCase(),
      mime: (decoded.mime ?? '').trim().toLowerCase(),
      hasAttachment: attachment != null && attachment.isNotEmpty,
      voiceSecs: decoded.voiceSecs ?? 0,
      lat: decoded.lat,
      lon: decoded.lon,
      contactId: (decoded.contactId ?? '').trim(),
      contactName: (decoded.contactName ?? '').trim(),
      replyPreview: (decoded.replyPreview ?? '').trim(),
      bodyText: bodyText,
      searchTerm: searchTerm.trim(),
      presentation: presentation,
    );
  }

  bool matches(
    ChatMessage message, {
    required DecodedChatMessagePayload decoded,
    required String bodyText,
    required String searchTerm,
  }) {
    final attachment = decoded.attachment;
    return nonceB64 == message.nonceB64 &&
        boxB64 == message.boxB64 &&
        sealedSender == message.sealedSender &&
        trustedLocalPlaintext == message.trustedLocalPlaintext &&
        createdAtMicros ==
            (message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0) &&
        text == decoded.text &&
        kind == (decoded.kind ?? '').trim().toLowerCase() &&
        mime == (decoded.mime ?? '').trim().toLowerCase() &&
        hasAttachment == (attachment != null && attachment.isNotEmpty) &&
        voiceSecs == (decoded.voiceSecs ?? 0) &&
        lat == decoded.lat &&
        lon == decoded.lon &&
        contactId == (decoded.contactId ?? '').trim() &&
        contactName == (decoded.contactName ?? '').trim() &&
        replyPreview == (decoded.replyPreview ?? '').trim() &&
        this.bodyText == bodyText &&
        this.searchTerm == searchTerm.trim();
  }
}
