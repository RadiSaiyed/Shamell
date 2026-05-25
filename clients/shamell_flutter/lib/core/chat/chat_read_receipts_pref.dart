import 'package:shared_preferences/shared_preferences.dart';

/// Global "send read receipts" preference (audit P1-17).
///
/// **Default**: enabled (matches the existing app behaviour — every
/// `_startLiveDirectReadAck` call goes through). When the user turns
/// this OFF, the call site short-circuits BEFORE the network ack so
/// the recipient never sees a `read_at` timestamp on our messages.
///
/// **Scope**: process-wide. Mirrors WhatsApp's global setting and
/// Signal's global setting — per-chat overrides aren't part of the
/// MVP because the trust model is bidirectional (if you disable
/// sending, you also lose visibility into others' read state for
/// symmetry).
///
/// **Storage**: SharedPreferences. Survives app restart. NOT scoped
/// per baseUrl / per account because read-receipt behaviour is a
/// user-level privacy preference, not server-side state — the user
/// expects "I turned off read receipts" to apply across their
/// accounts on this device.
class ChatReadReceiptsPref {
  ChatReadReceiptsPref._();

  /// Key under SharedPreferences. Versioned so a future migration
  /// (e.g. switching to per-chat overrides) can read old values
  /// and migrate them in place rather than dropping them silently.
  static const String _prefKey = 'shamell.chat.read_receipts.v1';

  /// In-memory cache so the hot-path check (every incoming message
  /// triggers an ack) doesn't pay an async hop. Synced from
  /// SharedPreferences once at startup via [hydrate] and updated on
  /// every [setEnabled] call.
  static bool _cached = true;
  static bool _hydrated = false;

  /// Fast synchronous check used by the message-ack hot path. Always
  /// safe — defaults to `true` until [hydrate] returns. The brief
  /// window before hydrate completes might cause one or two extra
  /// acks to fire for a user who has the setting off; that's
  /// acceptable given the simplicity gain.
  static bool get enabled => _cached;

  /// Reads the persisted value into the in-memory cache. Idempotent
  /// — repeat calls during reauth cycles are a no-op. Errors are
  /// swallowed so a SharedPreferences failure never blocks the chat
  /// page from booting.
  static Future<void> hydrate() async {
    if (_hydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_prefKey);
      if (stored != null) {
        _cached = stored;
      }
      _hydrated = true;
    } catch (_) {
      // Defensive — leave _cached at its default (true).
    }
  }

  /// Sets the global preference, updates the in-memory cache, and
  /// persists to disk. The cache is updated FIRST so callers don't
  /// race against the disk write.
  static Future<void> setEnabled(bool value) async {
    _cached = value;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {
      // Disk failure: in-memory state still reflects the intent. The
      // next process restart may resurrect the old value — accept that
      // over crashing the toggle interaction.
    }
  }

  /// Test-only reset hook. Wiped to the default-on state so unit
  /// tests don't bleed state into each other.
  static void resetForTesting() {
    _cached = true;
    _hydrated = false;
  }
}
