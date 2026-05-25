import 'package:flutter/foundation.dart';

import 'chat_models.dart';

Map<String, int> buildPinnedChatOrderIndex(Iterable<String> order) {
  final indexByKey = <String, int>{};
  var index = 0;
  for (final raw in order) {
    final key = raw.trim();
    if (key.isEmpty || indexByKey.containsKey(key)) {
      index += 1;
      continue;
    }
    indexByKey[key] = index;
    index += 1;
  }
  return indexByKey;
}

Map<String, ChatCallLogEntry> buildLatestChatCallsByPeer(
  Iterable<ChatCallLogEntry> calls,
) {
  final latestByPeer = <String, ChatCallLogEntry>{};
  for (final entry in calls) {
    final peerId = entry.peerId.trim();
    if (peerId.isEmpty) continue;
    final current = latestByPeer[peerId];
    if (current == null || entry.ts.isAfter(current.ts)) {
      latestByPeer[peerId] = entry;
    }
  }
  return latestByPeer;
}

@visibleForTesting
Map<String, Object?> debugLatestChatCallsByPeer(
  Iterable<ChatCallLogEntry> calls,
) {
  final latest = buildLatestChatCallsByPeer(calls);
  return <String, Object?>{
    for (final entry in latest.entries)
      entry.key: <String, Object?>{
        'id': entry.value.id,
        'ts': entry.value.ts.toUtc().toIso8601String(),
      },
  };
}
