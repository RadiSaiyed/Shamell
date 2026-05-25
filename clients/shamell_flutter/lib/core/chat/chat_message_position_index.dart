import 'chat_models.dart';

class ChatMessagePositionIndex {
  const ChatMessagePositionIndex._(this._positions);

  final Map<String, int> _positions;

  int indexOf(String messageId) {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return -1;
    }
    return _positions[normalizedMessageId] ?? -1;
  }
}

ChatMessagePositionIndex buildChatMessagePositionIndex(
  Iterable<ChatMessage> messages,
) {
  final positions = <String, int>{};
  var index = 0;
  for (final message in messages) {
    final messageId = message.id.trim();
    if (messageId.isNotEmpty) {
      positions[messageId] = index;
    }
    index++;
  }
  return ChatMessagePositionIndex._(
    Map<String, int>.unmodifiable(positions),
  );
}
