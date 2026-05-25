import 'package:shared_preferences/shared_preferences.dart';

import 'chat_outbox.dart';

/// SharedPreferences-backed persistence for the chat outbox.
///
/// Why SharedPreferences and not a "real" database (Hive / Isar /
/// sqflite): the outbox is intentionally tiny (a few dozen entries at
/// most — heavily-offline users still type a bounded volume before
/// reconnecting). Pulling in a DB just for this would add startup
/// cost, an init step, and a new code path that's only exercised on
/// the offline-flush edge case. SharedPreferences gives us:
///   * persistence across app restart and account switch
///   * synchronous-feeling load (`getInstance()` is cached after first
///     call)
///   * Android encrypted-storage backend on devices with secure HW
///     (when the platform plugin upgrades to EncryptedSharedPreferences)
/// All it costs us is a single round-trip JSON encode/decode per
/// mutation, which is < 1 ms for a list this small.
///
/// **Key scoping.** Stored at `chat_outbox/<baseUrl>/<deviceId>`. The
/// per-baseUrl scope means switching between production and staging
/// builds doesn't cross-contaminate; the per-deviceId scope means a
/// device sign-out / re-bind doesn't resurrect another account's
/// pending sends.
class ChatOutboxStore {
  ChatOutboxStore({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _resolvePrefs() async {
    final p = _prefs;
    if (p != null) return p;
    final created = await SharedPreferences.getInstance();
    _prefs = created;
    return created;
  }

  String _keyForScope({required String baseUrl, required String deviceId}) {
    final normBase = baseUrl.trim();
    final normDevice = deviceId.trim();
    return 'shamell.chat.outbox.v1::$normBase::$normDevice';
  }

  /// Loads all pending entries for this (baseUrl, deviceId) scope.
  /// Defensive: any corruption is treated as an empty queue (we'd
  /// rather lose the queue than crash the app on launch).
  Future<List<ChatOutboxEntry>> load({
    required String baseUrl,
    required String deviceId,
  }) async {
    final prefs = await _resolvePrefs();
    final raw = prefs.getString(_keyForScope(baseUrl: baseUrl, deviceId: deviceId));
    return deserializeChatOutbox(raw);
  }

  /// Replaces the entire queue. Callers do their own list-level
  /// computation (insert / update / remove) and call this once with
  /// the final list. This keeps the persistence layer trivially
  /// testable — no concurrent mutators within the store itself.
  Future<void> save({
    required String baseUrl,
    required String deviceId,
    required List<ChatOutboxEntry> entries,
  }) async {
    final prefs = await _resolvePrefs();
    final key = _keyForScope(baseUrl: baseUrl, deviceId: deviceId);
    if (entries.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, serializeChatOutbox(entries));
  }

  /// Append helper that loads → adds → saves. Use this for the most
  /// common case ("a send just failed, enqueue it"). Returns the new
  /// full list so the caller can update in-memory state without an
  /// extra round trip.
  Future<List<ChatOutboxEntry>> enqueue({
    required String baseUrl,
    required String deviceId,
    required ChatOutboxEntry entry,
  }) async {
    final cur = await load(baseUrl: baseUrl, deviceId: deviceId);
    // De-dup by localId — re-enqueueing the same localId replaces the
    // existing entry rather than duplicating it. This is what we want
    // when the user taps Retry: the same bubble's outbox entry gets a
    // fresh attempt counter, no new bubble appears.
    final next = <ChatOutboxEntry>[
      for (final e in cur)
        if (e.localId != entry.localId) e,
      entry,
    ];
    await save(baseUrl: baseUrl, deviceId: deviceId, entries: next);
    return next;
  }

  /// Drops the entry with the given localId. Returns the resulting
  /// list. No-op if the id isn't present.
  Future<List<ChatOutboxEntry>> remove({
    required String baseUrl,
    required String deviceId,
    required String localId,
  }) async {
    final cur = await load(baseUrl: baseUrl, deviceId: deviceId);
    final next = cur.where((e) => e.localId != localId).toList();
    if (next.length == cur.length) return cur;
    await save(baseUrl: baseUrl, deviceId: deviceId, entries: next);
    return next;
  }

  /// Updates the entry with the given localId via [mutator]. No-op if
  /// the id isn't present. Returns the resulting list.
  Future<List<ChatOutboxEntry>> update({
    required String baseUrl,
    required String deviceId,
    required String localId,
    required ChatOutboxEntry Function(ChatOutboxEntry) mutator,
  }) async {
    final cur = await load(baseUrl: baseUrl, deviceId: deviceId);
    var changed = false;
    final next = <ChatOutboxEntry>[
      for (final e in cur)
        if (e.localId == localId)
          () {
            changed = true;
            return mutator(e);
          }()
        else
          e,
    ];
    if (!changed) return cur;
    await save(baseUrl: baseUrl, deviceId: deviceId, entries: next);
    return next;
  }

  /// Drops every entry [chatOutboxShouldDrop] returns true for.
  /// Returns the resulting list. Use this on app foreground to
  /// silently expire ancient queued sends (24h+) instead of stamping
  /// confusing "old" bubbles into the live thread.
  Future<List<ChatOutboxEntry>> sweep({
    required String baseUrl,
    required String deviceId,
    required DateTime now,
    int maxAttempts = 8,
    int maxAgeHours = 24,
  }) async {
    final cur = await load(baseUrl: baseUrl, deviceId: deviceId);
    final next = cur
        .where((e) => !chatOutboxShouldDrop(
              e,
              now: now,
              maxAttempts: maxAttempts,
              maxAgeHours: maxAgeHours,
            ))
        .toList();
    if (next.length == cur.length) return cur;
    await save(baseUrl: baseUrl, deviceId: deviceId, entries: next);
    return next;
  }
}
