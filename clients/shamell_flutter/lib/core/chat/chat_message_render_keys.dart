import 'package:flutter/material.dart';

class ChatMessageRenderKeys {
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  void retainMessageIds(Iterable<String> messageIds) {
    final retainedIds = <String>{
      for (final messageId in messageIds)
        if (messageId.trim().isNotEmpty) messageId.trim(),
    };
    if (retainedIds.isEmpty) {
      clear();
      return;
    }
    _messageKeys
        .removeWhere((messageId, _) => !retainedIds.contains(messageId));
  }

  GlobalKey? messageKeyFor(String messageId) {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return null;
    }
    return _messageKeys.putIfAbsent(normalizedMessageId, () => GlobalKey());
  }

  GlobalKey? existingMessageKey(String messageId) {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return null;
    }
    return _messageKeys[normalizedMessageId];
  }

  void clear() {
    _messageKeys.clear();
  }

  int get messageKeyCount => _messageKeys.length;
}
