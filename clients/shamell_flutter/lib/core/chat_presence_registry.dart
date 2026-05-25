import 'package:flutter/services.dart';

/// Tracks whether any chat surface is currently visible in the foreground
/// process. Chat root widgets call [enter] in `initState` and [leave] in
/// `dispose`, and the foreground FCM handler queries [hasActiveChat] before
/// surfacing a full notification banner.
///
/// Rationale: when the user is already inside a chat surface and a new
/// `chat_wakeup` push arrives, a system banner that says "you have new
/// messages" is redundant and noisy. The foreground handler instead emits a
/// short haptic + click — same signal a flagship messenger would give for an
/// in-app arrival — while still pulling the inbox so the new message appears
/// inline.
///
/// Why a process-local counter instead of a per-peer map: the server-side
/// `chat_wakeup` push is intentionally peer-agnostic (it just signals "go
/// pull"), so the foreground handler cannot match against a specific peer.
/// "Any chat root visible" is the best signal we have client-side, and matches
/// what WhatsApp/Telegram do when a generic wakeup hits.
class ShamellChatPresenceRegistry {
  ShamellChatPresenceRegistry._();

  static int _activeCount = 0;

  /// Increment the active-chat counter. Safe to call from `initState`.
  static void enter() {
    _activeCount += 1;
  }

  /// Decrement the active-chat counter. Safe to call from `dispose`. Clamped
  /// at zero so an out-of-pair call (e.g. hot reload state churn) cannot
  /// produce a negative count and permanently suppress notifications.
  static void leave() {
    final next = _activeCount - 1;
    _activeCount = next < 0 ? 0 : next;
  }

  static bool get hasActiveChat => _activeCount > 0;

  /// Emit the in-chat arrival signal — a short haptic tick plus a soft system
  /// click. Both calls are best-effort and silently absorb platform failures
  /// (e.g. when haptics are globally disabled by the OS).
  static Future<void> emitInChatArrivalFeedback() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }
}
