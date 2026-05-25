import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';

void main() {
  test('ChatTypingSignal parses direct payloads', () {
    final signal = ChatTypingSignal.fromJson(<String, Object?>{
      'type': 'typing',
      'scope': 'direct',
      'from_device_id': 'dev_sender',
      'peer_id': 'dev_peer',
      'is_typing': true,
      'sent_at': '2026-03-08T02:30:00Z',
    });

    expect(signal, isNotNull);
    expect(signal!.scope, ChatTypingScope.direct);
    expect(signal.fromDeviceId, 'dev_sender');
    expect(signal.peerId, 'dev_peer');
    expect(signal.groupId, isNull);
    expect(signal.isTyping, isTrue);
    expect(signal.sentAt, isNotNull);
  });

  test('ChatTypingSignal parses group payloads and string booleans', () {
    final signal = ChatTypingSignal.fromJson(<String, Object?>{
      'scope': 'group',
      'from_device_id': 'dev_sender',
      'group_id': 'grp_demo',
      'is_typing': '1',
    });

    expect(signal, isNotNull);
    expect(signal!.scope, ChatTypingScope.group);
    expect(signal.fromDeviceId, 'dev_sender');
    expect(signal.peerId, isNull);
    expect(signal.groupId, 'grp_demo');
    expect(signal.isTyping, isTrue);
  });

  test('ChatTypingSignal rejects malformed payloads', () {
    expect(
      ChatTypingSignal.fromJson(<String, Object?>{
        'type': 'call_signal',
        'scope': 'direct',
        'from_device_id': 'dev_sender',
        'peer_id': 'dev_peer',
      }),
      isNull,
    );
    expect(
      ChatTypingSignal.fromJson(<String, Object?>{
        'scope': 'direct',
        'from_device_id': '',
        'peer_id': 'dev_peer',
      }),
      isNull,
    );
    expect(
      ChatTypingSignal.fromJson(<String, Object?>{
        'scope': 'group',
        'from_device_id': 'dev_sender',
        'group_id': '',
      }),
      isNull,
    );
  });
}
