import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_outbox.dart';

ChatOutboxEntry _entry({
  String localId = 'local-1',
  String peerId = 'peer-A',
  String text = 'hi',
  String? attachmentB64,
  String? attachmentMime,
  String? replyToMessageId,
  DateTime? createdAt,
  int attempt = 0,
  String? lastError,
}) {
  return ChatOutboxEntry(
    localId: localId,
    peerId: peerId,
    text: text,
    attachmentB64: attachmentB64,
    attachmentMime: attachmentMime,
    replyToMessageId: replyToMessageId,
    createdAt: createdAt ?? DateTime.utc(2026, 5, 13, 12, 0, 0),
    attempt: attempt,
    lastError: lastError,
  );
}

void main() {
  group('ChatOutboxEntry.toJson / fromJson round-trip', () {
    test('minimal entry preserves all fields', () {
      final e = _entry();
      final round = ChatOutboxEntry.fromJson(e.toJson());
      expect(round, isNotNull);
      expect(round!.localId, e.localId);
      expect(round.peerId, e.peerId);
      expect(round.text, e.text);
      expect(round.createdAt.toUtc(), e.createdAt.toUtc());
      expect(round.attempt, e.attempt);
      expect(round.attachmentB64, isNull);
      expect(round.replyToMessageId, isNull);
      expect(round.lastError, isNull);
    });

    test('full entry preserves attachment + reply + error fields', () {
      final e = _entry(
        attachmentB64: 'YWJj',
        attachmentMime: 'image/jpeg',
        replyToMessageId: 'srv-msg-7',
        attempt: 3,
        lastError: 'offline',
      );
      final round = ChatOutboxEntry.fromJson(e.toJson());
      expect(round!.attachmentB64, 'YWJj');
      expect(round.attachmentMime, 'image/jpeg');
      expect(round.replyToMessageId, 'srv-msg-7');
      expect(round.attempt, 3);
      expect(round.lastError, 'offline');
    });

    test('missing required fields yield null entry', () {
      // An entry without local_id is meaningless — the merger would
      // never be able to swap it for a server message. Drop it.
      expect(
        ChatOutboxEntry.fromJson({'peer_id': 'p', 'text': 't'}),
        isNull,
      );
      expect(
        ChatOutboxEntry.fromJson({'local_id': 'l', 'text': 't'}),
        isNull,
      );
    });

    test('blank attachment / reply fields normalise to null', () {
      final round = ChatOutboxEntry.fromJson({
        'local_id': 'l',
        'peer_id': 'p',
        'text': 'hi',
        'attachment_b64': '   ',
        'reply_to_message_id': '',
        'last_error': '',
      });
      expect(round, isNotNull);
      expect(round!.attachmentB64, isNull);
      expect(round.replyToMessageId, isNull);
      expect(round.lastError, isNull);
    });
  });

  group('serialize / deserialize list', () {
    test('round-trips a non-empty list', () {
      final entries = <ChatOutboxEntry>[
        _entry(localId: 'l1', text: 'first'),
        _entry(localId: 'l2', text: 'second', attempt: 2),
      ];
      final json = serializeChatOutbox(entries);
      final round = deserializeChatOutbox(json);
      expect(round, hasLength(2));
      expect(round[0].localId, 'l1');
      expect(round[1].localId, 'l2');
      expect(round[1].attempt, 2);
    });

    test('empty list serialises to a parseable wrapper', () {
      final json = serializeChatOutbox(const <ChatOutboxEntry>[]);
      final round = deserializeChatOutbox(json);
      expect(round, isEmpty);
    });

    test('null / empty input → empty list (no exception)', () {
      expect(deserializeChatOutbox(null), isEmpty);
      expect(deserializeChatOutbox(''), isEmpty);
      expect(deserializeChatOutbox('   '), isEmpty);
    });

    test('non-JSON garbage → empty list (defensive)', () {
      // Disk corruption or a half-written file must not crash the app
      // on launch. Worst-case behaviour is "queue is empty after this
      // launch" — the user re-types, losing nothing visible.
      expect(deserializeChatOutbox('not json'), isEmpty);
      expect(deserializeChatOutbox('{"unrelated":true}'), isEmpty);
    });

    test('future version → empty list (forward-compat)', () {
      // When v2 lands, we'd rather drop v1 reads than pretend v2 is v1
      // and stamp wrong field values onto the stub.
      final v2 = '{"version":99,"entries":[]}';
      expect(deserializeChatOutbox(v2), isEmpty);
    });

    test('partially-malformed entries are skipped, valid ones kept', () {
      const raw =
          '{"version":1,"entries":[{"local_id":"good","peer_id":"p","text":"ok",'
          '"created_at":"2026-05-13T12:00:00Z","attempt":0},'
          '{"peer_id":"no-localid"},'
          '{"local_id":"empty","peer_id":"p","text":""}]}';
      final round = deserializeChatOutbox(raw);
      // The "no-localid" one is dropped (no local_id), the "empty" one
      // is also dropped (vacuous: no text and no attachment).
      expect(round, hasLength(1));
      expect(round.single.localId, 'good');
    });
  });

  group('withAttempt', () {
    test('bumps attempt and lastError without mutating other fields', () {
      final base = _entry();
      final next = base.withAttempt(attempt: 1, lastError: 'timeout');
      expect(next.localId, base.localId);
      expect(next.peerId, base.peerId);
      expect(next.text, base.text);
      expect(next.createdAt, base.createdAt);
      expect(next.attempt, 1);
      expect(next.lastError, 'timeout');
      // Base is unchanged — record semantics.
      expect(base.attempt, 0);
      expect(base.lastError, isNull);
    });
  });

  group('chatOutboxBackoffSeconds', () {
    test('schedule grows monotonically and caps at 600s', () {
      expect(chatOutboxBackoffSeconds(0), 0);
      expect(chatOutboxBackoffSeconds(1), 5);
      expect(chatOutboxBackoffSeconds(2), 15);
      expect(chatOutboxBackoffSeconds(3), 30);
      expect(chatOutboxBackoffSeconds(4), 60);
      expect(chatOutboxBackoffSeconds(5), 120);
      expect(chatOutboxBackoffSeconds(6), 300);
      expect(chatOutboxBackoffSeconds(7), 600);
      expect(chatOutboxBackoffSeconds(8), 600);
      expect(chatOutboxBackoffSeconds(99), 600);
    });

    test('negative attempt treated as zero (no crash)', () {
      expect(chatOutboxBackoffSeconds(-1), 0);
    });
  });

  group('chatOutboxShouldDrop', () {
    test('drops after max attempts', () {
      final e = _entry(attempt: 8);
      expect(
        chatOutboxShouldDrop(e, now: DateTime.utc(2026, 5, 13, 13)),
        isTrue,
      );
    });

    test('drops after max age even if attempts low', () {
      final e = _entry(
        createdAt: DateTime.utc(2026, 5, 12, 12),
        attempt: 1,
      );
      // 25 h later — past the 24h default ceiling.
      final now = DateTime.utc(2026, 5, 13, 13);
      expect(chatOutboxShouldDrop(e, now: now), isTrue);
    });

    test('keeps fresh, low-attempt entries', () {
      final e = _entry(
        createdAt: DateTime.utc(2026, 5, 13, 11, 50),
        attempt: 0,
      );
      // 10 min old, attempt 0 → definitely keep.
      final now = DateTime.utc(2026, 5, 13, 12);
      expect(chatOutboxShouldDrop(e, now: now), isFalse);
    });

    test('custom thresholds honoured', () {
      final e = _entry(attempt: 4);
      // Lower the ceiling to 3 attempts → drop.
      expect(
        chatOutboxShouldDrop(
          e,
          now: DateTime.utc(2026, 5, 13, 13),
          maxAttempts: 3,
        ),
        isTrue,
      );
    });
  });
}
