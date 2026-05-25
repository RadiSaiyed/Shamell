import 'dart:async';

/// Composer-side typing-event debouncer (Cycle 5 wave 1 follow-up).
///
/// The chat composer fires text-change events on every keystroke; we
/// don't want to POST `/chat/messages/typing` on each one. This
/// helper enforces a debounced "typing_started" + a delayed
/// "typing_stopped" emission so the server sees at most ~one event
/// per [emitInterval] while the user is actively typing, plus one
/// "stopped" event after [idleTimeout] of no input.
///
/// **Wire-up shape** (for the chat page):
///
/// ```dart
/// final typing = ChatTypingDebouncer(
///   emitStarted: () => _service.postTypingSignal(
///     deviceId: me.id, peerId: peer.id, kind: 'started'),
///   emitStopped: () => _service.postTypingSignal(
///     deviceId: me.id, peerId: peer.id, kind: 'stopped'),
/// );
///
/// // In composer onChanged:
/// typing.onTextChanged();
///
/// // In composer dispose:
/// typing.dispose();
/// ```
///
/// **Semantics.** The first `onTextChanged()` after a quiet period
/// emits `started` immediately. Subsequent calls within
/// [emitInterval] are absorbed silently. After [idleTimeout] of
/// silence, a `stopped` event fires automatically. Manual
/// [emitStoppedNow] can short-circuit the idle timer (e.g. when the
/// user sends the message — we don't want a delayed "stopped" to
/// race past the new message into the recipient's stream).
class ChatTypingDebouncer {
  /// Called when the user transitions from idle → typing. The chat
  /// page wires this to `setMessageReaction(kind: "started")`.
  final Future<void> Function() emitStarted;

  /// Called when the user transitions from typing → idle. The chat
  /// page wires this to `setMessageReaction(kind: "stopped")`.
  final Future<void> Function() emitStopped;

  /// Minimum gap between two `started` emissions. Lower = more
  /// responsive on slow networks but spammier on the wire.
  final Duration emitInterval;

  /// How long after the last keystroke we declare the user "done
  /// typing" and emit `stopped`. WhatsApp uses ~3s; we match.
  final Duration idleTimeout;

  ChatTypingDebouncer({
    required this.emitStarted,
    required this.emitStopped,
    this.emitInterval = const Duration(seconds: 5),
    this.idleTimeout = const Duration(seconds: 3),
  });

  Timer? _idleTimer;
  /// Armed when a `started` was emitted recently. While this is
  /// non-null, subsequent `onTextChanged()` calls are absorbed —
  /// the rate-limit is "at most one `started` per [emitInterval]".
  /// The timer auto-clears itself after [emitInterval] so the next
  /// keystroke can re-arm a fresh emission.
  ///
  /// Timer-based rather than timestamp-based because `fake_async`
  /// faithfully fakes `Timer` but NOT `DateTime.now()` — using
  /// timestamps would make unit tests hostage to wall-clock timing.
  Timer? _cooldownTimer;
  bool _everEmittedStarted = false;
  bool _stoppedFiredSinceLastStarted = true;
  bool _disposed = false;

  /// Call from the composer `onChanged` handler on every keystroke
  /// (and any other text mutation: paste, dictation chunk, etc.).
  void onTextChanged() {
    if (_disposed) return;
    if (_cooldownTimer == null) {
      // Rate-limit window expired (or never armed) → fire a fresh
      // `started` and start the cooldown.
      _everEmittedStarted = true;
      _stoppedFiredSinceLastStarted = false;
      // Fire-and-forget — the chat page treats network failures as
      // soft (typing dots are eventual-consistency UX).
      // ignore: discarded_futures
      emitStarted();
      _cooldownTimer = Timer(emitInterval, () {
        _cooldownTimer = null;
      });
    }
    // Reset the idle timer either way — every keystroke pushes
    // "stopped" further into the future.
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _fireStopped);
  }

  /// Explicitly emit "stopped" right now and cancel any pending
  /// idle timer. The chat page calls this when the user actually
  /// hits send, when the composer loses focus, when the chat is
  /// closed, etc. — anywhere a deferred "stopped" might race past
  /// the next legitimate "started".
  Future<void> emitStoppedNow() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_stoppedFiredSinceLastStarted && _everEmittedStarted) {
      _stoppedFiredSinceLastStarted = true;
      await emitStopped();
    }
  }

  void _fireStopped() {
    _idleTimer = null;
    if (_disposed) return;
    if (!_stoppedFiredSinceLastStarted && _everEmittedStarted) {
      _stoppedFiredSinceLastStarted = true;
      // ignore: discarded_futures
      emitStopped();
    }
    // Tear down the cooldown so the NEXT typing session emits its
    // own "started" immediately rather than getting suppressed by
    // the previous session's rate-limit window. Without this, a
    // user who pauses for >idleTimeout then resumes inside the
    // emitInterval wouldn't see their typing dot reappear on the
    // peer's screen.
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }

  /// Cancel pending timers and stop emitting. Idempotent.
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }
}
