import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_push_deeplink.dart';

void main() {
  group('parseChatPushPayload', () {
    test('rejects non-chat_wakeup payloads', () {
      final p = parseChatPushPayload({'type': 'ride_event'});
      // A non-chat push must not look like a routable chat payload —
      // otherwise the deep-link handler would try to switch into a
      // chat for an unrelated event (e.g. ride status update).
      expect(p.kind, ChatPushKind.unknown);
      expect(p.hasThreadTarget, isFalse);
      expect(p.hasMessageTarget, isFalse);
    });

    test('parses a fully-populated direct payload', () {
      final p = parseChatPushPayload({
        'type': 'chat_wakeup',
        'chat_kind': 'direct',
        'peer_id': 'peer-abc',
        'message_id': 'msg-001',
        'sender_name': 'Alice',
        'preview': 'See you soon',
      });
      expect(p.kind, ChatPushKind.direct);
      expect(p.chatId, 'peer-abc');
      expect(p.messageId, 'msg-001');
      expect(p.senderName, 'Alice');
      expect(p.preview, 'See you soon');
      expect(p.hasThreadTarget, isTrue);
      expect(p.hasMessageTarget, isTrue);
    });

    test('parses a group payload by chat_kind', () {
      final p = parseChatPushPayload({
        'type': 'chat_wakeup',
        'chat_kind': 'group',
        'group_id': 'grp-xyz',
        'message_id': 'msg-007',
      });
      expect(p.kind, ChatPushKind.group);
      expect(p.chatId, 'grp-xyz');
      expect(p.messageId, 'msg-007');
    });

    test('infers direct when chat_kind missing but peer_id present', () {
      // Forward-compat: the server may ship `peer_id` before it ships
      // the `chat_kind` discriminator (one migration at a time). The
      // client must not refuse to route just because `chat_kind`
      // hasn't landed yet.
      final p = parseChatPushPayload({
        'type': 'chat_wakeup',
        'peer_id': 'peer-only',
        'message_id': 'm-1',
      });
      expect(p.kind, ChatPushKind.direct);
      expect(p.chatId, 'peer-only');
      expect(p.hasMessageTarget, isTrue);
    });

    test('infers group when chat_kind missing but group_id present', () {
      final p = parseChatPushPayload({
        'type': 'chat_wakeup',
        'group_id': 'grp-only',
        'message_id': 'm-1',
      });
      expect(p.kind, ChatPushKind.group);
      expect(p.chatId, 'grp-only');
    });

    test('trims whitespace and lower-cases the kind discriminator', () {
      final p = parseChatPushPayload({
        'type': '  Chat_Wakeup  ',
        'chat_kind': ' GROUP ',
        'group_id': '  grp-trim  ',
        'message_id': '  msg-trim  ',
      });
      expect(p.kind, ChatPushKind.group);
      expect(p.chatId, 'grp-trim');
      expect(p.messageId, 'msg-trim');
    });

    test('empty payload yields unknown kind, no thread target', () {
      // Important: an unknown push must not trip a navigation. The
      // existing "just pull inbox" fallback then runs.
      final p = parseChatPushPayload({'type': 'chat_wakeup'});
      expect(p.kind, ChatPushKind.unknown);
      expect(p.hasThreadTarget, isFalse);
      expect(p.hasMessageTarget, isFalse);
    });

    test('numeric ids are coerced to strings', () {
      // FCM sometimes ships ids as JSON numbers when the server sends
      // an int — Dart's `Map<String, Object?>` then contains an `int`,
      // not a `String`. The parser must coerce so the downstream
      // matcher (`_contacts.firstWhere((c) => c.id == chatId)`) sees a
      // plain string.
      final p = parseChatPushPayload({
        'type': 'chat_wakeup',
        'chat_kind': 'direct',
        'peer_id': 42,
        'message_id': 99,
      });
      expect(p.chatId, '42');
      expect(p.messageId, '99');
    });

    test('senderName is null when blank/whitespace, not empty string', () {
      // Callers do `payload.senderName ?? localFallback`, which only
      // fires when null. If we propagated `""` the fallback would never
      // run and the banner would render as a blank name.
      final p = parseChatPushPayload({
        'type': 'chat_wakeup',
        'peer_id': 'p',
        'sender_name': '   ',
      });
      expect(p.senderName, isNull);
    });

    test('alternative key names from_name and chat_kind=dm', () {
      // Backward-compat: an older server build emitted `from_name`
      // rather than `sender_name`. Keep that path working.
      final p = parseChatPushPayload({
        'type': 'chat_wakeup',
        'chat_kind': 'dm',
        'peer_id': 'p1',
        'from_name': 'Bob',
      });
      expect(p.kind, ChatPushKind.direct);
      expect(p.senderName, 'Bob');
    });
  });
}
