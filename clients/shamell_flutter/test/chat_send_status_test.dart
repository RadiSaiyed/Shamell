import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_send_status.dart';

ChatMessage _msg({
  String id = 'm1',
  DateTime? createdAt,
  DateTime? deliveredAt,
  DateTime? readAt,
}) {
  return ChatMessage(
    id: id,
    senderId: 'me',
    recipientId: 'peer',
    senderPubKeyB64: '',
    nonceB64: '',
    boxB64: '',
    createdAt: createdAt,
    deliveredAt: deliveredAt,
    readAt: readAt,
  );
}

void main() {
  group('isLocalChatMessageId', () {
    test('recognizes local- prefix', () {
      expect(isLocalChatMessageId('local-abc-def'), isTrue);
    });

    test('rejects server UUIDs and empty strings', () {
      // UUIDv4-shaped ids should never collide with the local prefix.
      expect(
        isLocalChatMessageId('550e8400-e29b-41d4-a716-446655440000'),
        isFalse,
      );
      expect(isLocalChatMessageId(''), isFalse);
      expect(isLocalChatMessageId('msg-001'), isFalse);
    });
  });

  group('makeLocalChatMessageId', () {
    test('emits the local- prefix and a lexicographically-orderable tail',
        () {
      final a = makeLocalChatMessageId();
      // Two ids on the same millisecond can collide on the leading ts
      // portion; the 6-char random tail must keep them distinct.
      final b = makeLocalChatMessageId();
      expect(isLocalChatMessageId(a), isTrue);
      expect(isLocalChatMessageId(b), isTrue);
      // Format invariants — `<prefix><ts-base36>-<6 chars>` — keep the
      // bubble's sort stable. We don't want to discover the dash got
      // dropped in a refactor and the merger started parsing wrong.
      final tail = a.substring(localChatMessageIdPrefix.length);
      final parts = tail.split('-');
      expect(parts.length, 2, reason: 'expected ts-rand split, got "$tail"');
      expect(parts[1].length, 6, reason: 'random tail must be 6 chars');
    });
  });

  group('chatMessageOutgoingStatus', () {
    test('LocalSendState overrides server-derived state', () {
      final m = _msg(readAt: DateTime.utc(2025, 1, 1));
      final local = LocalSendState(
        localId: 'local-x',
        peerId: 'peer',
        startedAt: DateTime.utc(2025),
        status: OutgoingSendStatus.failed,
      );
      // Even though the server fields say "read", the local stub's
      // failure status must win — otherwise a failed send would appear
      // delivered/read and the retry chip would never render.
      expect(
        chatMessageOutgoingStatus(message: m, localState: local),
        OutgoingSendStatus.failed,
      );
    });

    test('read beats delivered beats sent', () {
      final t = DateTime.utc(2025, 1, 1);
      expect(
        chatMessageOutgoingStatus(message: _msg(readAt: t, deliveredAt: t)),
        OutgoingSendStatus.read,
      );
      expect(
        chatMessageOutgoingStatus(message: _msg(deliveredAt: t)),
        OutgoingSendStatus.delivered,
      );
      expect(
        chatMessageOutgoingStatus(message: _msg()),
        OutgoingSendStatus.sent,
      );
    });
  });

  group('LocalSendState.withStatus', () {
    test('preserves identity fields and bumps status only', () {
      final base = LocalSendState(
        localId: 'local-1',
        peerId: 'peer-A',
        startedAt: DateTime.utc(2025),
        status: OutgoingSendStatus.sending,
      );
      final next = base.withStatus(
        OutgoingSendStatus.failed,
        errorReason: 'offline',
      );
      expect(next.localId, base.localId);
      expect(next.peerId, base.peerId);
      expect(next.startedAt, base.startedAt);
      expect(next.status, OutgoingSendStatus.failed);
      expect(next.errorReason, 'offline');
      expect(next.canRetry, isTrue);
      expect(base.canRetry, isFalse, reason: 'original must be unchanged');
    });
  });

  group('chatCalendarDaysBetween', () {
    test('Yesterday at 23:59 → Today at 00:01 is 1 calendar day', () {
      final yesterdayLate = DateTime(2026, 5, 12, 23, 59);
      final todayEarly = DateTime(2026, 5, 13, 0, 1);
      // 2 minutes apart on the wall clock but a full calendar boundary.
      // The day-separator must say "Yesterday" for the late message,
      // not "Today" just because <24 h elapsed.
      expect(chatCalendarDaysBetween(yesterdayLate, todayEarly), 1);
    });

    test('Same calendar day is 0 regardless of hour gap', () {
      final morning = DateTime(2026, 5, 13, 6);
      final evening = DateTime(2026, 5, 13, 23);
      expect(chatCalendarDaysBetween(morning, evening), 0);
    });
  });

  group('chatMessageDateHeaderLabel', () {
    String fakeShortDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    String fakeWeekday(DateTime d) {
      const names = [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ];
      return names[d.weekday - 1];
    }

    final now = DateTime(2026, 5, 13, 12); // Wednesday

    test('today → "Today" (en) / "اليوم" (ar)', () {
      expect(
        chatMessageDateHeaderLabel(
          DateTime(2026, 5, 13, 9),
          now: now,
          isArabic: false,
          shortDateFormatter: fakeShortDate,
          weekdayFormatter: fakeWeekday,
        ),
        'Today',
      );
      expect(
        chatMessageDateHeaderLabel(
          DateTime(2026, 5, 13, 9),
          now: now,
          isArabic: true,
          shortDateFormatter: fakeShortDate,
          weekdayFormatter: fakeWeekday,
        ),
        'اليوم',
      );
    });

    test('yesterday → "Yesterday" (en) / "أمس" (ar)', () {
      expect(
        chatMessageDateHeaderLabel(
          DateTime(2026, 5, 12, 22),
          now: now,
          isArabic: false,
          shortDateFormatter: fakeShortDate,
          weekdayFormatter: fakeWeekday,
        ),
        'Yesterday',
      );
      expect(
        chatMessageDateHeaderLabel(
          DateTime(2026, 5, 12, 22),
          now: now,
          isArabic: true,
          shortDateFormatter: fakeShortDate,
          weekdayFormatter: fakeWeekday,
        ),
        'أمس',
      );
    });

    test('2-6 days ago → weekday name', () {
      // 5 days ago: 2026-05-08 = Friday in our fake formatter.
      expect(
        chatMessageDateHeaderLabel(
          DateTime(2026, 5, 8, 14),
          now: now,
          isArabic: false,
          shortDateFormatter: fakeShortDate,
          weekdayFormatter: fakeWeekday,
        ),
        'Fri',
      );
    });

    test('7+ days ago falls back to short date', () {
      expect(
        chatMessageDateHeaderLabel(
          DateTime(2026, 5, 1, 10),
          now: now,
          isArabic: false,
          shortDateFormatter: fakeShortDate,
          weekdayFormatter: fakeWeekday,
        ),
        '2026-05-01',
      );
    });
  });
}
