import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_thread_index.dart';

void main() {
  test('buildPinnedChatOrderIndex keeps first occurrence and skips blanks', () {
    final index = buildPinnedChatOrderIndex(<String>[
      'peer-b',
      ' ',
      'peer-a',
      'peer-b',
      'group:1',
    ]);

    expect(index, <String, int>{
      'peer-b': 0,
      'peer-a': 2,
      'group:1': 4,
    });
  });

  test('buildLatestChatCallsByPeer keeps newest call per peer', () {
    final latest = buildLatestChatCallsByPeer(<ChatCallLogEntry>[
      ChatCallLogEntry(
        id: 'old-a',
        peerId: 'peer-a',
        ts: DateTime.utc(2026, 4, 20, 10),
        direction: 'in',
        kind: 'voice',
        accepted: true,
        duration: const Duration(minutes: 1),
      ),
      ChatCallLogEntry(
        id: 'new-a',
        peerId: 'peer-a',
        ts: DateTime.utc(2026, 4, 21, 12),
        direction: 'out',
        kind: 'video',
        accepted: false,
        duration: Duration.zero,
      ),
      ChatCallLogEntry(
        id: 'blank-peer',
        peerId: ' ',
        ts: DateTime.utc(2026, 4, 21, 13),
        direction: 'in',
        kind: 'voice',
        accepted: true,
        duration: const Duration(seconds: 10),
      ),
      ChatCallLogEntry(
        id: 'peer-b',
        peerId: 'peer-b',
        ts: DateTime.utc(2026, 4, 19, 9),
        direction: 'in',
        kind: 'voice',
        accepted: true,
        duration: const Duration(seconds: 5),
      ),
    ]);

    expect(latest.keys.toSet(), <String>{'peer-a', 'peer-b'});
    expect(latest['peer-a']?.id, 'new-a');
    expect(latest['peer-b']?.id, 'peer-b');
  });
}
