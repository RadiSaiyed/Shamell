/// One emoji's aggregated state on a chat message (Cycle 4).
///
/// Mirrors the server-side `ReactionSummary` shape returned inside the
/// inbox/thread JSON. Held as an immutable record so the chat page can
/// pass batches of them through `setState` without worrying about
/// callers mutating in place.
class ChatReactionSummary {
  /// The emoji as a raw Unicode sequence (server caps to 16 bytes).
  final String emoji;

  /// How many distinct reactors have placed this emoji on the message.
  final int count;

  /// Whether the local user has placed this emoji on the message.
  /// Used by the UI to render the chip in its "tapped" / outlined state
  /// so the user can see at a glance which reactions are theirs.
  final bool hasMe;

  const ChatReactionSummary({
    required this.emoji,
    required this.count,
    required this.hasMe,
  });

  /// Parses a JSON map from the chat_service inbox/thread response.
  /// Tolerates missing/odd fields so a forward-compat server adding a
  /// new key (e.g. `peak_reactor_id`) doesn't crash the client.
  static ChatReactionSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final emoji = raw['emoji'];
    if (emoji is! String || emoji.trim().isEmpty) return null;
    final countRaw = raw['count'];
    final count = countRaw is int
        ? countRaw
        : countRaw is num
            ? countRaw.toInt()
            : countRaw is String
                ? int.tryParse(countRaw) ?? 0
                : 0;
    final hasMe = raw['has_me'] == true;
    return ChatReactionSummary(emoji: emoji, count: count, hasMe: hasMe);
  }

  /// Parses an array of reaction summaries from a server response.
  /// Returns an empty list if the payload is missing/malformed — the
  /// no-reactions case is by far the common one, so the UI must be
  /// stable against it.
  static List<ChatReactionSummary> listFromJson(Object? raw) {
    if (raw is! List) return const <ChatReactionSummary>[];
    final out = <ChatReactionSummary>[];
    for (final item in raw) {
      final parsed = ChatReactionSummary.fromJson(item);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'emoji': emoji,
        'count': count,
        'has_me': hasMe,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatReactionSummary &&
        other.emoji == emoji &&
        other.count == count &&
        other.hasMe == hasMe;
  }

  @override
  int get hashCode => Object.hash(emoji, count, hasMe);

  @override
  String toString() =>
      'ChatReactionSummary(emoji: $emoji, count: $count, hasMe: $hasMe)';
}

/// Default emoji set offered by the picker. Hand-picked from the most
/// common chat reactions across WhatsApp/Telegram/Slack/Signal — picking
/// 6 keeps the picker compact and means the user can hit any of them
/// from a thumb without scrolling. The full Unicode keyboard is left
/// for a follow-up since the picker is most often used for these.
const List<String> defaultChatReactionEmojis = <String>[
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];
