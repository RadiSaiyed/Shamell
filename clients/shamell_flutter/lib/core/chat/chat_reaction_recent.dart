// Cycle 27 — track which emoji reactions a user actually uses, so
// the quick-react row surfaces their personal top-6 instead of the
// hardcoded WhatsApp-style default. Backing store is
// SharedPreferences (a single JSON map: emoji → count).
//
// Design choices:
// * `Map<String,int>` of emoji → use-count, capped at ~32 entries
//   so the prefs blob doesn't grow unbounded over years of use.
// * Decay isn't strictly necessary at this scale — most users
//   converge on 4–6 favourites within a week. A future cycle could
//   add half-life decay if users complain about stale picks.
// * `defaultEmojiSlate` is the WhatsApp/iMessage-style fallback
//   used until the user has a history. Same order Cycle-7 picked.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> defaultEmojiSlate = <String>[
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '😡',
];

const String _kPrefsKey = 'shamell.chat.reaction_recent.v1';
const int _kMaxStoredEmojis = 32;

/// Pure helper: blend the user's `counts` history with the
/// `defaultEmojiSlate` to produce a stable top-`limit` row of
/// emojis. Highest-count wins, ties broken by the order they
/// appeared in defaults (stable iteration).
List<String> topReactionEmojis({
  required Map<String, int> counts,
  int limit = 6,
}) {
  if (counts.isEmpty) return defaultEmojiSlate.take(limit).toList();
  // Build a ranked list of (emoji, count) pairs.
  final entries = <MapEntry<String, int>>[];
  // Seed defaults with count 0 so any used emoji outranks them but
  // unused defaults still fill the row.
  for (final e in defaultEmojiSlate) {
    entries.add(MapEntry<String, int>(e, counts[e] ?? 0));
  }
  // Add user-history emojis not in defaults.
  for (final entry in counts.entries) {
    if (defaultEmojiSlate.contains(entry.key)) continue;
    entries.add(entry);
  }
  // Sort stable: count desc, original index ascending.
  entries.sort((a, b) {
    final byCount = b.value - a.value;
    if (byCount != 0) return byCount;
    return 0; // Dart's sort is stable; insertion order tie-breaks.
  });
  final out = <String>[];
  for (final e in entries) {
    if (!out.contains(e.key)) out.add(e.key);
    if (out.length >= limit) break;
  }
  return out;
}

/// Apply a `+1` to `emoji` in `counts`, capping the stored map at
/// [_kMaxStoredEmojis] entries (evicting the lowest-count emoji
/// when over the cap). Pure — caller writes the result back to
/// prefs.
Map<String, int> bumpReactionCount({
  required Map<String, int> counts,
  required String emoji,
}) {
  final next = Map<String, int>.from(counts);
  next[emoji] = (next[emoji] ?? 0) + 1;
  if (next.length > _kMaxStoredEmojis) {
    // Drop the lowest-count entry; ties keep the first.
    String? toRemove;
    int minCount = 1 << 30;
    for (final e in next.entries) {
      if (e.value < minCount) {
        minCount = e.value;
        toRemove = e.key;
      }
    }
    if (toRemove != null) next.remove(toRemove);
  }
  return next;
}

/// SharedPreferences-backed singleton — the chat page reads on
/// startup and re-reads after a bump so the next quick-react row
/// reflects the new count.
class ChatReactionRecent {
  static final ChatReactionRecent instance = ChatReactionRecent._();
  ChatReactionRecent._();

  Map<String, int> _cache = const <String, int>{};
  bool _hydrated = false;

  Future<void> hydrate() async {
    if (_hydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _cache = <String, int>{};
          decoded.forEach((k, v) {
            if (k is String && v is int) _cache[k] = v;
            if (k is String && v is double) _cache[k] = v.toInt();
          });
        }
      }
    } catch (_) {
      // Best-effort hydrate.
    }
    _hydrated = true;
  }

  Map<String, int> get counts => _cache;

  Future<void> bump(String emoji) async {
    if (!_hydrated) await hydrate();
    _cache = bumpReactionCount(counts: _cache, emoji: emoji);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, jsonEncode(_cache));
    } catch (_) {
      // Persist failure is non-fatal; we keep the in-memory cache.
    }
  }

  /// Convenience: current top-N row.
  List<String> currentTop({int limit = 6}) =>
      topReactionEmojis(counts: _cache, limit: limit);
}
