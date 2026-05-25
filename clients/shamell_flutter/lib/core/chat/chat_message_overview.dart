import 'dart:typed_data';

import 'chat_message_payload.dart';
import 'chat_models.dart';

enum ChatMessageOverviewFilter { all, media, files, links, voice }

class ChatMessageOverviewEntry {
  final ChatMessage message;
  final String text;
  final String searchText;
  final Uint8List? attachment;
  final String? mime;
  final String? kind;
  final int? voiceSecs;
  final DateTime? timestamp;

  const ChatMessageOverviewEntry({
    required this.message,
    required this.text,
    required this.searchText,
    required this.attachment,
    required this.mime,
    required this.kind,
    required this.voiceSecs,
    required this.timestamp,
  });

  bool get hasAttachment => attachment != null && attachment!.isNotEmpty;

  bool get hasLink =>
      searchText.contains('http://') ||
      searchText.contains('https://') ||
      searchText.contains('www.');

  bool get isVoice => kind == 'voice' || voiceSecs != null;

  bool get isMedia {
    if (!hasAttachment || isVoice) return false;
    final mimeType = (mime ?? '').toLowerCase();
    return mimeType.startsWith('image/') || mimeType.startsWith('video/');
  }

  bool get isFile => hasAttachment && !isVoice && !isMedia;
}

class ChatMessageOverviewIndex {
  final List<ChatMessageOverviewEntry> entries;
  final List<ChatMessageOverviewEntry> mediaEntries;
  final List<ChatMessageOverviewEntry> fileEntries;
  final List<ChatMessageOverviewEntry> linkEntries;
  final List<ChatMessageOverviewEntry> voiceEntries;

  const ChatMessageOverviewIndex({
    this.entries = const <ChatMessageOverviewEntry>[],
    this.mediaEntries = const <ChatMessageOverviewEntry>[],
    this.fileEntries = const <ChatMessageOverviewEntry>[],
    this.linkEntries = const <ChatMessageOverviewEntry>[],
    this.voiceEntries = const <ChatMessageOverviewEntry>[],
  });

  List<ChatMessageOverviewEntry> filtered({
    String query = '',
    required ChatMessageOverviewFilter filter,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final source = switch (filter) {
      ChatMessageOverviewFilter.all => entries,
      ChatMessageOverviewFilter.media => mediaEntries,
      ChatMessageOverviewFilter.files => fileEntries,
      ChatMessageOverviewFilter.links => linkEntries,
      ChatMessageOverviewFilter.voice => voiceEntries,
    };
    if (normalizedQuery.isEmpty) {
      return source;
    }
    return <ChatMessageOverviewEntry>[
      for (final entry in source)
        if (entry.searchText.contains(normalizedQuery)) entry,
    ];
  }
}

ChatMessageOverviewIndex buildChatMessageOverviewIndex(
  Iterable<ChatMessage> messages, {
  required Set<String> recalledMessageIds,
  required DecodedChatMessagePayload Function(ChatMessage message)
      decodeMessage,
}) {
  final entries = <ChatMessageOverviewEntry>[];
  final mediaEntries = <ChatMessageOverviewEntry>[];
  final fileEntries = <ChatMessageOverviewEntry>[];
  final linkEntries = <ChatMessageOverviewEntry>[];
  final voiceEntries = <ChatMessageOverviewEntry>[];

  for (final message in messages) {
    if (recalledMessageIds.contains(message.id)) {
      continue;
    }
    try {
      final decoded = decodeMessage(message);
      final searchText = <String>[
        decoded.text,
        decoded.replyPreview ?? '',
        decoded.contactName ?? '',
        decoded.contactId ?? '',
        decoded.mime ?? '',
        decoded.kind ?? '',
      ].join('\n').toLowerCase();
      final entry = ChatMessageOverviewEntry(
        message: message,
        text: decoded.text,
        searchText: searchText,
        attachment: decoded.attachment,
        mime: decoded.mime,
        kind: decoded.kind,
        voiceSecs: decoded.voiceSecs,
        timestamp: message.createdAt ?? message.deliveredAt,
      );
      entries.add(entry);
      if (entry.isMedia) {
        mediaEntries.add(entry);
      } else if (entry.isFile) {
        fileEntries.add(entry);
      }
      if (entry.hasLink) {
        linkEntries.add(entry);
      }
      if (entry.isVoice) {
        voiceEntries.add(entry);
      }
    } catch (_) {}
  }

  return ChatMessageOverviewIndex(
    entries: List<ChatMessageOverviewEntry>.unmodifiable(entries),
    mediaEntries: List<ChatMessageOverviewEntry>.unmodifiable(mediaEntries),
    fileEntries: List<ChatMessageOverviewEntry>.unmodifiable(fileEntries),
    linkEntries: List<ChatMessageOverviewEntry>.unmodifiable(linkEntries),
    voiceEntries: List<ChatMessageOverviewEntry>.unmodifiable(voiceEntries),
  );
}
