import 'chat_message_payload.dart';
import 'chat_models.dart';
import 'direct_message_search.dart';

/// One match result from a cross-chat search (Cycle 3D). Unlike
/// [DirectMessageSearchEntry] (which is scoped to a single conversation
/// and therefore doesn't need to remember WHERE the message lives), this
/// entry carries both the conversation id and a flag distinguishing 1:1
/// peers from groups so the result-list UI can:
///
///   • group results by conversation
///   • show the right title (peer alias vs. group name)
///   • jump back to the correct page on tap
class CrossChatSearchEntry {
  /// The chat message's wire id. Stable across reloads, suitable for
  /// passing to `_jumpToMessageById` on the chat page.
  final String messageId;

  /// The conversation id: a peer device id for direct chats, or a group
  /// id for group chats. Inspect [isGroup] to know which.
  final String conversationId;

  /// True if [conversationId] is a group id; false for a 1:1 peer id.
  final bool isGroup;

  /// Pre-normalized lowercase haystack — same shape as
  /// [DirectMessageSearchEntry.haystack]. Allows reusing the existing
  /// substring-match path.
  final String haystack;

  /// Optional snippet to show under the conversation name in the result
  /// list. Typically the message text or a short preview. Already
  /// truncated to a reasonable length by the builder.
  final String previewSnippet;

  /// Optional millisecond timestamp for ordering results. Most recent
  /// first feels more useful than relevance-ranked for "find the latest
  /// thing X said about Y".
  final int sortMs;

  const CrossChatSearchEntry({
    required this.messageId,
    required this.conversationId,
    required this.isGroup,
    required this.haystack,
    this.previewSnippet = '',
    this.sortMs = 0,
  });
}

/// Cross-conversation message search index. Pure-data structure — pass it
/// the entry list at construction time and call [matches] with the search
/// term. Reuses [DirectMessageSearchIndex]'s LRU cache pattern so repeat
/// queries hit cheaply.
class CrossChatSearchIndex {
  CrossChatSearchIndex({
    Iterable<CrossChatSearchEntry> entries =
        const <CrossChatSearchEntry>[],
    this.maxCachedQueries = 8,
  }) : entries = List<CrossChatSearchEntry>.unmodifiable(entries);

  final List<CrossChatSearchEntry> entries;
  final int maxCachedQueries;
  final Map<String, List<CrossChatSearchEntry>> _matchCache =
      <String, List<CrossChatSearchEntry>>{};

  /// Returns matching entries, most-recent-first (by [sortMs]). Empty
  /// search term returns an empty list — there is no "show everything"
  /// affordance because that would dump every message in every chat.
  List<CrossChatSearchEntry> matches(String searchTerm) {
    final normalized = searchTerm.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <CrossChatSearchEntry>[];
    }
    final cached = _matchCache.remove(normalized);
    if (cached != null) {
      _matchCache[normalized] = cached;
      return cached;
    }

    final hits = <CrossChatSearchEntry>[
      for (final entry in entries)
        if (entry.haystack.contains(normalized)) entry,
    ];
    // Most recent first. Stable for equal sortMs.
    hits.sort((a, b) => b.sortMs.compareTo(a.sortMs));
    final result = List<CrossChatSearchEntry>.unmodifiable(hits);

    if (_matchCache.length >= maxCachedQueries) {
      _matchCache.remove(_matchCache.keys.first);
    }
    _matchCache[normalized] = result;
    return result;
  }
}

/// Build cross-chat search entries from a map of direct-message
/// conversations (peer device id → that peer's encrypted [ChatMessage]
/// list). Each message is decoded through [decodeMessage] so we get the
/// plaintext text, mime, contact name, etc., and combined into a
/// lowercase haystack via [buildDirectMessageSearchHaystack].
///
/// [recalledMessageIdsByPeer] is a per-peer set of recalled ids that
/// should be excluded from the index (matches the per-conversation
/// search path's recalled-message handling). Pass an empty map for "no
/// recalls".
List<CrossChatSearchEntry> buildCrossChatSearchEntriesFromDirects({
  required Map<String, List<ChatMessage>> directMessagesByPeer,
  required Map<String, Set<String>> recalledMessageIdsByPeer,
  required DecodedChatMessagePayload Function(ChatMessage message)
      decodeMessage,
  required DirectMessageSearchPreviewBuilder previewText,
  int previewMaxLength = 120,
}) {
  final out = <CrossChatSearchEntry>[];
  for (final convo in directMessagesByPeer.entries) {
    final peerId = convo.key;
    final recalled =
        recalledMessageIdsByPeer[peerId] ?? const <String>{};
    for (final message in convo.value) {
      final messageId = message.id.trim();
      if (messageId.isEmpty || recalled.contains(messageId)) continue;
      try {
        final decoded = decodeMessage(message);
        final preview = previewText(message, decoded);
        final haystack = buildDirectMessageSearchHaystack(
          decoded: decoded,
          previewText: preview,
        );
        if (haystack.trim().isEmpty) continue;
        out.add(
          CrossChatSearchEntry(
            messageId: messageId,
            conversationId: peerId,
            isGroup: false,
            haystack: haystack,
            previewSnippet: _truncate(
              preview.isNotEmpty ? preview : decoded.text,
              previewMaxLength,
            ),
            sortMs: message.createdAt?.millisecondsSinceEpoch ?? 0,
          ),
        );
      } catch (_) {
        // Best-effort: a single decode failure must not poison the
        // entire index build.
      }
    }
  }
  return out;
}

/// Group-message variant. [extractText] yields the plaintext body of a
/// group message (the chat page typically already decrypts group
/// payloads, so this is a `(msg) => msg.text` style mapping). The
/// returned haystack combines the text with the contact name + mime hint
/// if [extractContactName] and [extractMime] are provided.
List<CrossChatSearchEntry> buildCrossChatSearchEntriesFromGroups<T>({
  required Map<String, List<T>> groupMessagesByGroup,
  required Map<String, Set<String>> recalledMessageIdsByGroup,
  required String Function(T message) extractId,
  required String Function(T message) extractText,
  required DateTime? Function(T message) extractCreatedAt,
  String? Function(T message)? extractContactName,
  String? Function(T message)? extractMime,
  int previewMaxLength = 120,
}) {
  final out = <CrossChatSearchEntry>[];
  for (final convo in groupMessagesByGroup.entries) {
    final groupId = convo.key;
    final recalled =
        recalledMessageIdsByGroup[groupId] ?? const <String>{};
    for (final message in convo.value) {
      final messageId = extractId(message).trim();
      if (messageId.isEmpty || recalled.contains(messageId)) continue;
      try {
        final text = extractText(message);
        final contactName = extractContactName?.call(message) ?? '';
        final mime = extractMime?.call(message) ?? '';
        final haystack = <String>[
          text,
          contactName,
          mime,
        ].join('\n').toLowerCase();
        if (haystack.trim().isEmpty) continue;
        out.add(
          CrossChatSearchEntry(
            messageId: messageId,
            conversationId: groupId,
            isGroup: true,
            haystack: haystack,
            previewSnippet: _truncate(text, previewMaxLength),
            sortMs: extractCreatedAt(message)?.millisecondsSinceEpoch ?? 0,
          ),
        );
      } catch (_) {
        // Same best-effort skip as the direct path.
      }
    }
  }
  return out;
}

/// Composes a [CrossChatSearchIndex] from already-built entry lists.
/// Callers typically obtain one list from
/// [buildCrossChatSearchEntriesFromDirects] and one from
/// [buildCrossChatSearchEntriesFromGroups] and pass both here.
CrossChatSearchIndex buildCrossChatSearchIndex({
  required Iterable<CrossChatSearchEntry> directEntries,
  required Iterable<CrossChatSearchEntry> groupEntries,
}) {
  return CrossChatSearchIndex(entries: <CrossChatSearchEntry>[
    ...directEntries,
    ...groupEntries,
  ]);
}

/// Single-line truncate that adds an ellipsis and trims ragged whitespace.
String _truncate(String value, int maxLength) {
  final flattened = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flattened.length <= maxLength) return flattened;
  return '${flattened.substring(0, maxLength - 1).trimRight()}…';
}
