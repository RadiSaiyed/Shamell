import 'package:flutter/foundation.dart';

import 'chat_models.dart';

class DirectThreadListLayoutEntry {
  const DirectThreadListLayoutEntry({
    required this.message,
    required this.incoming,
    required this.showTimeHeader,
    required this.showAvatar,
    required this.showBubbleTail,
  });

  final ChatMessage message;
  final bool incoming;
  final bool showTimeHeader;
  final bool showAvatar;
  final bool showBubbleTail;
}

class DirectThreadListLayout {
  const DirectThreadListLayout._({
    required this.entries,
    required this.newMessagesIndex,
  });

  final List<DirectThreadListLayoutEntry> entries;
  final int newMessagesIndex;
}

@visibleForTesting
bool shouldShowDirectThreadTimeHeader(
  ChatMessage? previousMessage,
  ChatMessage currentMessage,
) {
  final currentTimestamp = currentMessage.createdAt;
  if (currentTimestamp == null) {
    return false;
  }
  if (previousMessage == null) {
    return true;
  }
  final previousTimestamp = previousMessage.createdAt;
  if (previousTimestamp == null) {
    return true;
  }
  final currentLocal = currentTimestamp.toLocal();
  final previousLocal = previousTimestamp.toLocal();
  final dayChanged = currentLocal.year != previousLocal.year ||
      currentLocal.month != previousLocal.month ||
      currentLocal.day != previousLocal.day;
  if (dayChanged) {
    return true;
  }
  final diff = currentLocal.difference(previousLocal).abs();
  return diff.inMinutes >= 10;
}

DirectThreadListLayout buildDirectThreadListLayout(
  Iterable<ChatMessage> messages, {
  String? newMessagesAnchorMessageId,
  String? currentUserId,
}) {
  final normalizedAnchorId = (newMessagesAnchorMessageId ?? '').trim();
  final normalizedCurrentUserId = (currentUserId ?? '').trim();
  final messageList = List<ChatMessage>.unmodifiable(messages);
  final entries = <DirectThreadListLayoutEntry>[];
  var newMessagesIndex = -1;
  for (var index = 0; index < messageList.length; index += 1) {
    final message = messageList[index];
    final previousMessage = index > 0 ? messageList[index - 1] : null;
    final nextMessage =
        index + 1 < messageList.length ? messageList[index + 1] : null;
    if (normalizedAnchorId.isNotEmpty &&
        message.id.trim() == normalizedAnchorId) {
      newMessagesIndex = index;
    }
    final incoming = normalizedCurrentUserId.isNotEmpty
        ? message.isIncomingFor(normalizedCurrentUserId)
        : false;
    final showTimeHeader =
        shouldShowDirectThreadTimeHeader(previousMessage, message);
    final nextBreaksCluster = normalizedCurrentUserId.isEmpty ||
        nextMessage == null ||
        shouldShowDirectThreadTimeHeader(message, nextMessage) ||
        nextMessage.isIncomingFor(normalizedCurrentUserId) != incoming;
    entries.add(
      DirectThreadListLayoutEntry(
        message: message,
        incoming: incoming,
        showTimeHeader: showTimeHeader,
        showAvatar: nextBreaksCluster,
        showBubbleTail: nextBreaksCluster,
      ),
    );
  }
  return DirectThreadListLayout._(
    entries: List<DirectThreadListLayoutEntry>.unmodifiable(entries),
    newMessagesIndex: newMessagesIndex,
  );
}
