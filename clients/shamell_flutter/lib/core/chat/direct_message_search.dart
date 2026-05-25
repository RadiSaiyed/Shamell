import 'chat_message_payload.dart';
import 'chat_models.dart';

typedef DirectMessageSearchPreviewBuilder = String Function(
  ChatMessage message,
  DecodedChatMessagePayload decoded,
);

class DirectMessageSearchEntry {
  final String messageId;
  final String haystack;

  const DirectMessageSearchEntry({
    required this.messageId,
    required this.haystack,
  });
}

class DirectMessageSearchIndex {
  DirectMessageSearchIndex({
    Iterable<DirectMessageSearchEntry> entries =
        const <DirectMessageSearchEntry>[],
    this.maxCachedQueries = 8,
  }) : entries = List<DirectMessageSearchEntry>.unmodifiable(entries);

  final List<DirectMessageSearchEntry> entries;
  final int maxCachedQueries;
  final Map<String, List<String>> _matchCache = <String, List<String>>{};

  List<String> matchIds(String searchTerm) {
    final normalizedSearchTerm = searchTerm.trim().toLowerCase();
    if (normalizedSearchTerm.isEmpty) {
      return const <String>[];
    }
    final cached = _matchCache.remove(normalizedSearchTerm);
    if (cached != null) {
      _matchCache[normalizedSearchTerm] = cached;
      return cached;
    }

    final matches = List<String>.unmodifiable(<String>[
      for (final entry in entries)
        if (entry.haystack.contains(normalizedSearchTerm)) entry.messageId,
    ]);
    if (_matchCache.length >= maxCachedQueries) {
      _matchCache.remove(_matchCache.keys.first);
    }
    _matchCache[normalizedSearchTerm] = matches;
    return matches;
  }
}

String buildDirectMessageSearchHaystack({
  required DecodedChatMessagePayload decoded,
  required String previewText,
}) {
  return <String>[
    decoded.text,
    previewText,
    decoded.replyPreview ?? '',
    decoded.contactName ?? '',
    decoded.contactId ?? '',
    decoded.mime ?? '',
  ].join('\n').toLowerCase();
}

DirectMessageSearchIndex buildDirectMessageSearchIndex(
  Iterable<ChatMessage> messages, {
  required Set<String> recalledMessageIds,
  required DecodedChatMessagePayload Function(ChatMessage message)
      decodeMessage,
  required DirectMessageSearchPreviewBuilder previewText,
}) {
  final entries = <DirectMessageSearchEntry>[];
  for (final message in messages) {
    final messageId = message.id.trim();
    if (messageId.isEmpty || recalledMessageIds.contains(messageId)) {
      continue;
    }
    try {
      final decoded = decodeMessage(message);
      final haystack = buildDirectMessageSearchHaystack(
        decoded: decoded,
        previewText: previewText(message, decoded),
      );
      entries.add(
        DirectMessageSearchEntry(
          messageId: messageId,
          haystack: haystack,
        ),
      );
    } catch (_) {}
  }
  return DirectMessageSearchIndex(entries: entries);
}

List<String> buildDirectMessageSearchMatchIds(
  Iterable<ChatMessage> messages, {
  required String searchTerm,
  required Set<String> recalledMessageIds,
  required DecodedChatMessagePayload Function(ChatMessage message)
      decodeMessage,
  required DirectMessageSearchPreviewBuilder previewText,
}) {
  return buildDirectMessageSearchIndex(
    messages,
    recalledMessageIds: recalledMessageIds,
    decodeMessage: decodeMessage,
    previewText: previewText,
  ).matchIds(searchTerm);
}
