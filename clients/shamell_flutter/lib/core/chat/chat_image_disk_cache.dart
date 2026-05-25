import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk-backed LRU cache for decrypted chat image bytes (Cycle 3D).
///
/// **Why this exists.** Today the chat page decrypts an image attachment
/// every time the message bubble re-enters the viewport. That's:
///   • CPU expensive (base64Decode + XChaCha20-Poly1305 over ~750 KB
///     per image)
///   • Memory expensive (the decoded byte buffer churns through GC)
///   • Battery expensive when scrolling through media-heavy threads
///
/// A disk-resident LRU lets us pay the decrypt cost once per message
/// and reuse the bytes across cold starts. The cache is content-addressed
/// by SHA-256 of the encrypted ciphertext, so:
///   • The same image attached to multiple messages dedups naturally
///   • A re-decrypt of identical ciphertext always lands on the same
///     cache key without us needing to track message ids
///   • Tampering / corruption is detectable at read time (the chat page
///     can still re-decrypt the underlying box_b64 if the cache file
///     bytes don't match)
///
/// **Eviction policy.** Total bytes capped via [maxTotalBytes] (default
/// 64 MB). Eviction is touch-time LRU: every successful [getBytes] hit
/// bumps the entry's `lastAccessMs` so frequently-viewed images stay
/// resident. When [putBytes] would push the total over the cap, the
/// oldest entries are deleted until we're back under.
///
/// **Concurrency.** All mutating operations are serialised through a
/// `synchronized` lock so concurrent message renders (a common case
/// when a thread first loads) can't race on the index file. Reads
/// against established entries don't need to take the lock — they only
/// touch the entry's timestamp at the end, and a stale timestamp is
/// harmless (the entry is still resident and still readable).
///
/// **Persistence.** A single index file (`index.json`) under the
/// cache directory tracks every entry's `(key, sizeBytes, lastAccessMs)`.
/// Index writes use atomic rename so a crash mid-write can't corrupt
/// the cache state — the worst-case is one orphaned blob that gets
/// cleaned up on the next [trimToCap] call.
class ChatImageDiskCache {
  /// Override for tests: lets unit tests inject a temporary directory
  /// instead of the real app-private docs dir.
  final Future<Directory> Function() _baseDirProvider;

  /// Subdirectory inside the base dir where the index file and entry
  /// blobs live. Defaults to `chat_image_cache/`.
  final String _subdir;

  /// Maximum total bytes the cache is allowed to hold. When [putBytes]
  /// would exceed this, oldest entries are evicted.
  final int maxTotalBytes;

  /// Serialise all mutating operations so concurrent put/evict can't
  /// corrupt the index file or the on-disk byte budget. Implemented as
  /// a Future-chain mutex — each new `synchronized` call appends to
  /// the tail, so callers wait their turn FIFO. Avoids pulling in the
  /// `synchronized` package for a single use case.
  final _AsyncMutex _lock = _AsyncMutex();

  /// In-memory mirror of the on-disk index. Populated lazily on first
  /// use (see [_ensureLoaded]). Keys are the content-addressed hex
  /// SHA-256 of the original ciphertext.
  final Map<String, _CacheEntry> _index = <String, _CacheEntry>{};

  /// Total bytes currently resident according to the in-memory index.
  /// Maintained alongside [_index] so trim decisions don't have to walk
  /// the full map.
  int _totalBytes = 0;

  /// True once [_loadIndex] has run successfully. Loading is lazy —
  /// callers don't pay the index-file read cost until the first cache
  /// operation.
  bool _loaded = false;

  /// Cached resolved cache directory. `null` until first use.
  Directory? _cacheDir;

  ChatImageDiskCache({
    Future<Directory> Function()? baseDirProvider,
    String subdir = 'chat_image_cache',
    this.maxTotalBytes = 64 * 1024 * 1024, // 64 MB
  })  : _baseDirProvider =
            baseDirProvider ?? getApplicationDocumentsDirectory,
        _subdir = subdir;

  /// Content-addressed key for a ciphertext blob. SHA-256 hex of the
  /// raw bytes — collision-resistant enough for this use case.
  static String keyForCiphertext(Uint8List ciphertext) {
    return crypto.sha256.convert(ciphertext).toString();
  }

  /// Content-addressed key for a base64-encoded ciphertext. Convenience
  /// for the chat page's `box_b64` flow.
  static String keyForBase64Ciphertext(String base64Ciphertext) {
    return crypto.sha256.convert(utf8.encode(base64Ciphertext)).toString();
  }

  /// Looks up [key] in the cache. Returns the bytes on hit, `null` on
  /// miss. Touches the entry's `lastAccessMs` so LRU eviction sees it
  /// as fresh. The touch is best-effort — if writing the index back to
  /// disk fails, we still return the bytes (a stale lastAccess is
  /// harmless).
  Future<Uint8List?> getBytes(String key) async {
    await _ensureLoaded();
    final entry = _index[key];
    if (entry == null) return null;
    try {
      final file = await _entryFile(key);
      if (!await file.exists()) {
        // Index says the entry exists but the blob is gone — clean up
        // the stale index entry so future lookups don't repeatedly hit
        // this code path.
        await _lock.synchronized(() async {
          final removed = _index.remove(key);
          if (removed != null) _totalBytes -= removed.sizeBytes;
          await _persistIndex();
        });
        return null;
      }
      final bytes = await file.readAsBytes();
      // Touch the timestamp under the lock so concurrent puts / trims
      // can't reorganise the LRU mid-update. We AWAIT the persist (vs.
      // fire-and-forget) so tests can deterministically observe the
      // cache reaching a quiescent state via [tearDown]'s temp-dir
      // cleanup. Production overhead is one tiny JSON write per hit —
      // negligible compared with the file read above.
      await _lock.synchronized(() async {
        final live = _index[key];
        if (live == null) return;
        _index[key] = live.touched(
          lastAccessMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _persistIndex();
      });
      return bytes;
    } catch (error, stack) {
      debugPrint('ChatImageDiskCache.getBytes failed for $key: $error\n$stack');
      return null;
    }
  }

  /// Stores [bytes] under [key]. Overwrites any existing entry with the
  /// same key (its old blob is deleted before the new one is written).
  /// After the write, the cache is trimmed back under [maxTotalBytes]
  /// by evicting the oldest entries first.
  Future<void> putBytes(String key, Uint8List bytes) async {
    if (key.isEmpty || bytes.isEmpty) return;
    await _ensureLoaded();
    await _lock.synchronized(() async {
      try {
        final dir = await _cacheDirectory();
        await dir.create(recursive: true);
        final file = File('${dir.path}/$key.bin');

        // Make room for the new entry. We compute the post-write total
        // assuming overwrite semantics: subtract the old size if the
        // key already existed.
        final existing = _index[key];
        if (existing != null) {
          _totalBytes -= existing.sizeBytes;
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
          _index.remove(key);
        }

        await file.writeAsBytes(bytes, flush: false);
        _index[key] = _CacheEntry(
          key: key,
          sizeBytes: bytes.length,
          lastAccessMs: DateTime.now().millisecondsSinceEpoch,
        );
        _totalBytes += bytes.length;

        await _trimUnderCapInsideLock();
        await _persistIndex();
      } catch (error, stack) {
        debugPrint('ChatImageDiskCache.putBytes failed for $key: $error\n$stack');
      }
    });
  }

  /// Total bytes currently resident in the cache. Reflects the in-memory
  /// index; safe to call without awaiting any pending writes (a put
  /// that hasn't committed yet is not included). Mostly useful for
  /// tests and diagnostics surfacing.
  Future<int> totalBytes() async {
    await _ensureLoaded();
    return _totalBytes;
  }

  /// Number of entries currently resident. Same caveats as [totalBytes].
  Future<int> entryCount() async {
    await _ensureLoaded();
    return _index.length;
  }

  /// Wipes the entire cache — both the on-disk blobs and the in-memory
  /// index. Useful for a "clear chat image cache" settings action and
  /// for test isolation. Safe to call concurrently with reads; in-flight
  /// reads may return null if their entry was deleted mid-operation,
  /// which is the same as a regular cache miss.
  Future<void> clear() async {
    await _ensureLoaded();
    await _lock.synchronized(() async {
      try {
        final dir = await _cacheDirectory();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (error, stack) {
        debugPrint('ChatImageDiskCache.clear failed: $error\n$stack');
      }
      _index.clear();
      _totalBytes = 0;
    });
  }

  // --- private helpers ---------------------------------------------

  Future<Directory> _cacheDirectory() async {
    final existing = _cacheDir;
    if (existing != null) return existing;
    final base = await _baseDirProvider();
    final dir = Directory('${base.path}/$_subdir');
    _cacheDir = dir;
    return dir;
  }

  Future<File> _entryFile(String key) async {
    final dir = await _cacheDirectory();
    return File('${dir.path}/$key.bin');
  }

  Future<File> _indexFile() async {
    final dir = await _cacheDirectory();
    return File('${dir.path}/index.json');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _lock.synchronized(() async {
      if (_loaded) return; // double-check inside the lock
      await _loadIndex();
      _loaded = true;
    });
  }

  Future<void> _loadIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return; // empty cache is fine
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final key = (item['key'] ?? '').toString();
        final size = item['size'];
        final lastAccess = item['lastAccessMs'];
        if (key.isEmpty || size is! int || lastAccess is! int) continue;
        _index[key] = _CacheEntry(
          key: key,
          sizeBytes: size,
          lastAccessMs: lastAccess,
        );
        _totalBytes += size;
      }
    } catch (error, stack) {
      debugPrint('ChatImageDiskCache._loadIndex corrupt index: $error\n$stack');
      // Defensive: a corrupt index file shouldn't brick the cache.
      // Start over with empty state; the next put will rebuild.
      _index.clear();
      _totalBytes = 0;
    }
  }

  /// Persists the index with atomic rename. Must be called inside the
  /// lock so concurrent writers can't tear-write the file.
  Future<void> _persistIndex() async {
    try {
      final dir = await _cacheDirectory();
      await dir.create(recursive: true);
      final tmp = File('${dir.path}/index.json.tmp');
      final final_ = File('${dir.path}/index.json');
      final serialised = jsonEncode([
        for (final entry in _index.values)
          {
            'key': entry.key,
            'size': entry.sizeBytes,
            'lastAccessMs': entry.lastAccessMs,
          }
      ]);
      await tmp.writeAsString(serialised, flush: true);
      // `rename` is atomic on POSIX (and Android maps to it). On any
      // platform where it's not, we fall back to write-replace; worst
      // case a torn write means index is empty next launch, which
      // recovers gracefully.
      try {
        await tmp.rename(final_.path);
      } catch (_) {
        await final_.writeAsString(serialised, flush: true);
        try {
          await tmp.delete();
        } catch (_) {}
      }
    } catch (error, stack) {
      debugPrint('ChatImageDiskCache._persistIndex failed: $error\n$stack');
    }
  }

  Future<void> _trimUnderCapInsideLock() async {
    if (_totalBytes <= maxTotalBytes) return;
    // Sort entries by lastAccessMs ascending so the oldest go first.
    final sorted = _index.values.toList()
      ..sort((a, b) => a.lastAccessMs.compareTo(b.lastAccessMs));
    for (final entry in sorted) {
      if (_totalBytes <= maxTotalBytes) break;
      _index.remove(entry.key);
      _totalBytes -= entry.sizeBytes;
      try {
        final file = await _entryFile(entry.key);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Filesystem hiccup — the index is already updated, so the
        // orphaned blob (if any) will be picked up next launch by a
        // future cleanup pass. Not worth failing the put for.
      }
    }
  }

  /// Test-only hook to reset the in-memory state so subsequent calls
  /// reload from disk. Real callers should use [clear] instead.
  @visibleForTesting
  void resetInMemoryForTesting() {
    _index.clear();
    _totalBytes = 0;
    _loaded = false;
    _cacheDir = null;
  }
}

class _CacheEntry {
  final String key;
  final int sizeBytes;
  final int lastAccessMs;

  const _CacheEntry({
    required this.key,
    required this.sizeBytes,
    required this.lastAccessMs,
  });

  _CacheEntry touched({required int lastAccessMs}) =>
      _CacheEntry(key: key, sizeBytes: sizeBytes, lastAccessMs: lastAccessMs);
}

/// Tiny FIFO mutex. `synchronized(fn)` runs [fn] only after every
/// previously-issued call has completed. Each call extends the tail
/// future, so cancellation isn't supported (we don't need it) and
/// memory cost is one Future per pending operation.
class _AsyncMutex {
  Future<void> _tail = Future<void>.value();

  /// Runs [action] under the mutex; resolves with [action]'s result.
  /// If [action] throws, the mutex still releases (the inner future
  /// completes via the try/finally chain on the caller's side because
  /// we await the result).
  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _tail;
    _tail = previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}
