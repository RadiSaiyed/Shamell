import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_image_disk_cache.dart';

void main() {
  late Directory tempBase;

  setUp(() async {
    tempBase = await Directory.systemTemp.createTemp('chat_img_cache_');
  });

  tearDown(() async {
    if (await tempBase.exists()) {
      await tempBase.delete(recursive: true);
    }
  });

  ChatImageDiskCache makeCache({int? maxBytes}) {
    return ChatImageDiskCache(
      baseDirProvider: () async => tempBase,
      maxTotalBytes: maxBytes ?? (64 * 1024 * 1024),
    );
  }

  group('keyForCiphertext / keyForBase64Ciphertext', () {
    test('identical bytes hash to identical keys (content-addressed)', () {
      final a = ChatImageDiskCache.keyForCiphertext(
          Uint8List.fromList(<int>[1, 2, 3, 4, 5]));
      final b = ChatImageDiskCache.keyForCiphertext(
          Uint8List.fromList(<int>[1, 2, 3, 4, 5]));
      expect(a, b);
      expect(a.length, 64, reason: 'SHA-256 hex is 64 chars');
    });

    test('different bytes hash to different keys', () {
      final a = ChatImageDiskCache.keyForCiphertext(
          Uint8List.fromList(<int>[1, 2, 3]));
      final b = ChatImageDiskCache.keyForCiphertext(
          Uint8List.fromList(<int>[1, 2, 4]));
      expect(a, isNot(b));
    });

    test('base64 helper is stable across identical inputs', () {
      final a = ChatImageDiskCache.keyForBase64Ciphertext('SGVsbG8gd29ybGQ=');
      final b = ChatImageDiskCache.keyForBase64Ciphertext('SGVsbG8gd29ybGQ=');
      expect(a, b);
    });
  });

  group('putBytes / getBytes', () {
    test('round-trips bytes through disk', () async {
      final cache = makeCache();
      final bytes = Uint8List.fromList(<int>[10, 20, 30, 40, 50]);
      await cache.putBytes('key1', bytes);
      final got = await cache.getBytes('key1');
      expect(got, isNotNull);
      expect(got!, bytes);
    });

    test('returns null for unknown keys', () async {
      final cache = makeCache();
      expect(await cache.getBytes('never_stored'), isNull);
    });

    test('overwriting an existing key replaces the bytes', () async {
      final cache = makeCache();
      await cache.putBytes('key1', Uint8List.fromList(<int>[1, 1]));
      await cache.putBytes('key1', Uint8List.fromList(<int>[2, 2, 2]));
      final got = await cache.getBytes('key1');
      expect(got!, <int>[2, 2, 2]);
      expect(await cache.totalBytes(), 3);
      expect(await cache.entryCount(), 1);
    });

    test('handles empty key / empty bytes as no-ops', () async {
      final cache = makeCache();
      await cache.putBytes('', Uint8List.fromList(<int>[1, 2]));
      await cache.putBytes('k', Uint8List(0));
      expect(await cache.entryCount(), 0);
    });
  });

  group('LRU eviction', () {
    test('evicts oldest entries when over maxTotalBytes', () async {
      // Cache capacity = 30 bytes. Inserting 3 x 10 byte entries should
      // sit exactly at the cap; a 4th 10-byte put should evict the
      // oldest.
      final cache = makeCache(maxBytes: 30);
      await cache.putBytes('a', Uint8List(10));
      await cache.putBytes('b', Uint8List(10));
      await cache.putBytes('c', Uint8List(10));
      expect(await cache.totalBytes(), 30);
      // Forth entry pushes over the cap; oldest (a) must be evicted.
      await cache.putBytes('d', Uint8List(10));
      expect(await cache.totalBytes(), 30);
      expect(await cache.getBytes('a'), isNull,
          reason: 'a was the oldest and must be evicted');
      expect(await cache.getBytes('b'), isNotNull);
      expect(await cache.getBytes('d'), isNotNull);
    });

    test('touch on read keeps frequently-accessed entries resident', () async {
      final cache = makeCache(maxBytes: 30);
      await cache.putBytes('a', Uint8List(10));
      // Tiny sleeps to make sure each entry has a strictly-later
      // lastAccessMs — millisecond precision can collide on fast
      // machines.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await cache.putBytes('b', Uint8List(10));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await cache.putBytes('c', Uint8List(10));
      // Touch 'a' so it's no longer the oldest.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await cache.getBytes('a');
      // Give the touch's persist future a chance to run.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      // Now insert a fourth — 'b' should evict because it's the oldest
      // by lastAccessMs after the touch.
      await cache.putBytes('d', Uint8List(10));
      expect(await cache.getBytes('a'), isNotNull,
          reason: 'a was touched and should survive');
      expect(await cache.getBytes('b'), isNull,
          reason: 'b is now the oldest after a was touched');
    });

    test('evicts multiple entries in one put when needed', () async {
      // 10-byte cap. Storing a 6-byte entry then a 6-byte entry forces
      // the first eviction; storing a 10-byte entry forces wiping
      // everything else.
      final cache = makeCache(maxBytes: 10);
      await cache.putBytes('a', Uint8List(6));
      await cache.putBytes('b', Uint8List(6));
      expect(await cache.entryCount(), 1,
          reason: 'a should have been evicted to fit b');
      await cache.putBytes('big', Uint8List(10));
      expect(await cache.entryCount(), 1);
      expect(await cache.getBytes('big'), isNotNull);
      expect(await cache.getBytes('b'), isNull);
    });
  });

  group('persistence', () {
    test('index survives a new cache instance pointed at the same dir',
        () async {
      final c1 = makeCache();
      await c1.putBytes('persist_me', Uint8List.fromList(<int>[9, 8, 7]));
      expect(await c1.totalBytes(), 3);

      // Brand-new instance reads the on-disk index and surfaces the
      // same entry.
      final c2 = makeCache();
      expect(await c2.totalBytes(), 3);
      expect(await c2.entryCount(), 1);
      final got = await c2.getBytes('persist_me');
      expect(got!, <int>[9, 8, 7]);
    });

    test('stale index entry (blob deleted out of band) self-heals on read',
        () async {
      final c1 = makeCache();
      await c1.putBytes('a', Uint8List.fromList(<int>[1, 2, 3]));
      // Externally delete the blob file to simulate corruption / user
      // wipe / OS reclaim.
      final blob = File('${tempBase.path}/chat_image_cache/a.bin');
      expect(await blob.exists(), isTrue);
      await blob.delete();

      // Same instance reads back: index says it exists, but read finds
      // no blob — the cache must self-heal and return null.
      final got = await c1.getBytes('a');
      expect(got, isNull);
      expect(await c1.entryCount(), 0,
          reason: 'stale index entry must be cleaned up');
    });
  });

  group('clear', () {
    test('wipes index + on-disk blobs', () async {
      final cache = makeCache();
      await cache.putBytes('a', Uint8List(10));
      await cache.putBytes('b', Uint8List(10));
      expect(await cache.entryCount(), 2);
      await cache.clear();
      expect(await cache.entryCount(), 0);
      expect(await cache.totalBytes(), 0);
      expect(await cache.getBytes('a'), isNull);
      // The on-disk dir was also removed.
      final dir = Directory('${tempBase.path}/chat_image_cache');
      expect(await dir.exists(), isFalse);
    });
  });

  group('concurrency safety', () {
    test('parallel puts to different keys all succeed', () async {
      final cache = makeCache();
      await Future.wait<void>([
        for (var i = 0; i < 20; i++)
          cache.putBytes('key_$i', Uint8List.fromList(<int>[i, i, i])),
      ]);
      expect(await cache.entryCount(), 20);
      // Every entry is readable.
      for (var i = 0; i < 20; i++) {
        expect(await cache.getBytes('key_$i'), <int>[i, i, i]);
      }
    });
  });
}
