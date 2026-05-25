import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_outbox.dart';
import 'package:shamell_flutter/core/chat/chat_outbox_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatOutboxEntry _entry(String id, {String peerId = 'peer-A', String text = 'hi'}) {
  return ChatOutboxEntry(
    localId: id,
    peerId: peerId,
    text: text,
    createdAt: DateTime.utc(2026, 5, 13, 12),
  );
}

void main() {
  setUp(() {
    // Each test runs against a fresh in-memory prefs to keep them
    // independent of disk state and of each other.
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatOutboxStore.enqueue / load / save', () {
    test('round-trips a single entry across baseUrl scopes', () async {
      final store = ChatOutboxStore();
      await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: _entry('l1'),
      );
      final loaded = await store.load(baseUrl: 'https://api.prod', deviceId: 'dev-1');
      expect(loaded, hasLength(1));
      expect(loaded.first.localId, 'l1');
      // Different baseUrl scope sees an empty queue (no cross-pollution).
      final other = await store.load(baseUrl: 'https://api.stg', deviceId: 'dev-1');
      expect(other, isEmpty);
      // Different deviceId scope sees an empty queue too.
      final otherDev =
          await store.load(baseUrl: 'https://api.prod', deviceId: 'dev-2');
      expect(otherDev, isEmpty);
    });

    test('enqueue with the same localId replaces, not duplicates', () async {
      final store = ChatOutboxStore();
      final base = _entry('l1', text: 'hello');
      await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: base,
      );
      // Re-enqueue same localId with bumped attempt — this is the
      // "user taps Retry" path. Must not double the bubble.
      final retried = base.withAttempt(attempt: 1, lastError: 'first failure');
      final list = await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: retried,
      );
      expect(list, hasLength(1));
      expect(list.single.attempt, 1);
      expect(list.single.lastError, 'first failure');
    });

    test('save with empty list removes the key entirely', () async {
      SharedPreferences.setMockInitialValues({
        // Pre-populate so we can verify the remove path.
        'shamell.chat.outbox.v1::https://api.prod::dev-1':
            '{"version":1,"entries":['
                '{"local_id":"l1","peer_id":"p","text":"x",'
                '"created_at":"2026-05-13T12:00:00Z","attempt":0}]}'
      });
      final store = ChatOutboxStore();
      // Verify it loaded the seeded entry.
      expect(
        await store.load(baseUrl: 'https://api.prod', deviceId: 'dev-1'),
        hasLength(1),
      );
      await store.save(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entries: const <ChatOutboxEntry>[],
      );
      // Re-load is empty.
      expect(
        await store.load(baseUrl: 'https://api.prod', deviceId: 'dev-1'),
        isEmpty,
      );
    });
  });

  group('ChatOutboxStore.update', () {
    test('mutates only the matching entry', () async {
      final store = ChatOutboxStore();
      await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: _entry('l1'),
      );
      await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: _entry('l2'),
      );
      final after = await store.update(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        localId: 'l1',
        mutator: (e) => e.withAttempt(attempt: 3, lastError: 'oops'),
      );
      expect(after, hasLength(2));
      final l1 = after.firstWhere((e) => e.localId == 'l1');
      expect(l1.attempt, 3);
      expect(l1.lastError, 'oops');
      final l2 = after.firstWhere((e) => e.localId == 'l2');
      expect(l2.attempt, 0);
      expect(l2.lastError, isNull);
    });

    test('update is a no-op when the id is absent', () async {
      final store = ChatOutboxStore();
      await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: _entry('l1'),
      );
      final after = await store.update(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        localId: 'l-missing',
        mutator: (e) => e.withAttempt(attempt: 7),
      );
      // Original is unchanged.
      expect(after.single.attempt, 0);
    });
  });

  group('ChatOutboxStore.remove', () {
    test('drops the entry and persists the new list', () async {
      final store = ChatOutboxStore();
      await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: _entry('l1'),
      );
      await store.enqueue(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entry: _entry('l2'),
      );
      final after = await store.remove(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        localId: 'l1',
      );
      expect(after, hasLength(1));
      expect(after.single.localId, 'l2');
      // Persistence check — a fresh load sees the new list.
      final reloaded =
          await store.load(baseUrl: 'https://api.prod', deviceId: 'dev-1');
      expect(reloaded, hasLength(1));
      expect(reloaded.single.localId, 'l2');
    });
  });

  group('ChatOutboxStore.sweep', () {
    test('drops entries past max age', () async {
      final store = ChatOutboxStore();
      final fresh = _entry('fresh').withAttempt(attempt: 0);
      // Old entry: createdAt one week ago.
      final old = ChatOutboxEntry(
        localId: 'old',
        peerId: 'peer-A',
        text: 'old',
        createdAt: DateTime.utc(2026, 5, 6, 12),
        attempt: 1,
      );
      await store.save(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entries: <ChatOutboxEntry>[fresh, old],
      );
      final after = await store.sweep(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        now: DateTime.utc(2026, 5, 13, 12),
      );
      expect(after, hasLength(1));
      expect(after.single.localId, 'fresh');
    });

    test('keeps everything when no entries are stale', () async {
      final store = ChatOutboxStore();
      final e1 = _entry('l1');
      final e2 = _entry('l2');
      await store.save(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        entries: <ChatOutboxEntry>[e1, e2],
      );
      final after = await store.sweep(
        baseUrl: 'https://api.prod',
        deviceId: 'dev-1',
        now: DateTime.utc(2026, 5, 13, 12, 10),
      );
      expect(after, hasLength(2));
    });
  });
}
