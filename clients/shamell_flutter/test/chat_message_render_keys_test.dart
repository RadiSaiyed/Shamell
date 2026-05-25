import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_message_render_keys.dart';

void main() {
  test('retainMessageIds prunes keys outside the active thread', () {
    final registry = ChatMessageRenderKeys();
    final retainedMessageKey = registry.messageKeyFor('m2');

    registry.messageKeyFor('m1');
    registry.messageKeyFor('m3');

    registry.retainMessageIds(const <String>['m2', 'm4']);

    expect(registry.messageKeyCount, 1);
    expect(registry.existingMessageKey('m1'), isNull);
    expect(registry.existingMessageKey('m2'), same(retainedMessageKey));
  });

  test('retainMessageIds clears all keys when the thread becomes empty', () {
    final registry = ChatMessageRenderKeys()..messageKeyFor('m1');

    registry.retainMessageIds(const <String>[]);

    expect(registry.messageKeyCount, 0);
  });

  test('messageKeyFor normalizes blank ids', () {
    final registry = ChatMessageRenderKeys();

    expect(registry.messageKeyFor('   '), isNull);
    expect(registry.messageKeyCount, 0);
  });

  test('existing key lookups do not allocate new keys', () {
    final registry = ChatMessageRenderKeys();

    expect(registry.existingMessageKey('m1'), isNull);
    expect(registry.messageKeyCount, 0);

    final messageKey = registry.messageKeyFor('m1');

    expect(registry.existingMessageKey('m1'), same(messageKey));
    expect(messageKey, isA<GlobalKey>());
  });
}
