import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat_presence_registry.dart';

void main() {
  setUp(() {
    // Drain any leftover counter from earlier tests so each case starts at
    // zero. Using a bounded loop with a safety cap so a runaway state never
    // produces an infinite loop here.
    for (var i = 0; i < 1024 && ShamellChatPresenceRegistry.hasActiveChat; i++) {
      ShamellChatPresenceRegistry.leave();
    }
  });

  test('hasActiveChat starts false', () {
    expect(ShamellChatPresenceRegistry.hasActiveChat, isFalse);
  });

  test('single enter flips hasActiveChat true; leave flips back', () {
    ShamellChatPresenceRegistry.enter();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isTrue);
    ShamellChatPresenceRegistry.leave();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isFalse);
  });

  test('nested enters require matching leaves before hasActiveChat clears', () {
    ShamellChatPresenceRegistry.enter();
    ShamellChatPresenceRegistry.enter();
    ShamellChatPresenceRegistry.enter();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isTrue);
    ShamellChatPresenceRegistry.leave();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isTrue);
    ShamellChatPresenceRegistry.leave();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isTrue);
    ShamellChatPresenceRegistry.leave();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isFalse);
  });

  test('extra leave is clamped at zero (does not go negative)', () {
    ShamellChatPresenceRegistry.leave();
    ShamellChatPresenceRegistry.leave();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isFalse);
    // A subsequent matched enter+leave still toggles cleanly.
    ShamellChatPresenceRegistry.enter();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isTrue);
    ShamellChatPresenceRegistry.leave();
    expect(ShamellChatPresenceRegistry.hasActiveChat, isFalse);
  });
}
