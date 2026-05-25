import 'dart:async';

import 'package:flutter/widgets.dart';

/// Mixin that serialises money-mutating actions inside a single State
/// object. Drop-in for any screen that lets the user fire off a Send /
/// Pay / Accept-Request / Redeem-Voucher etc.
///
/// **The problem this exists to fix.** Every money-moving entry point in
/// the app (`_sendManual`, `_pay`, `_acceptReq`, `_redeemCashCode`)
/// regenerates an Idempotency-Key on each invocation. The Idempotency-Key
/// machinery on the server only deduplicates *the same key replayed*.
/// Two distinct invocations from a double-tap (or a rage-tap, or a
/// re-entrant rebuild during the in-flight HTTP) produce *two different
/// keys* and therefore *two distinct transfers*.
///
/// This mixin gives every flow a single "I am currently moving money"
/// gate so the UI's "Send" button truly becomes a single action even on
/// fast double-tap, mid-flight rotation, or rebuild-driven re-entry.
///
/// **Usage**:
/// ```
/// class _MyTabState extends State<MyTab> with MoneyMutationGuardMixin {
///   Future<void> _onSendTap() async {
///     await guardMoneyMutation(() async {
///       // ... do the transfer
///     });
///   }
///
///   Widget build(BuildContext context) {
///     return FilledButton(
///       onPressed: isMoneyMutationInFlight ? null : _onSendTap,
///       child: const Text('Send'),
///     );
///   }
/// }
/// ```
///
/// **Why a mixin and not a global lock**: a global lock would block the
/// Receive tab while the Send tab is in flight; we only need
/// serialisation *per surface*. Two different screens minting two
/// independent transfers (e.g. a backgrounded payment request accept
/// while the user is composing a P2P send) is correct behavior — they
/// each have their own idempotency key and their own user intent.
///
/// **Reset on critical error**: if `action()` throws, the guard is
/// released so the user can retry. Successful completion also releases
/// it. The guard does NOT survive across `dispose()` — by definition,
/// if the State is gone, no follow-up mutation can race.
mixin MoneyMutationGuardMixin<T extends StatefulWidget> on State<T> {
  bool _moneyMutationInFlight = false;

  /// Whether a money mutation is currently in flight on this surface.
  /// Use this to disable the action button in `build`.
  bool get isMoneyMutationInFlight => _moneyMutationInFlight;

  /// Run [action] under the money-mutation guard.
  ///
  /// - Returns the result of [action] on success.
  /// - Returns `null` (without running [action]) if a mutation is
  ///   already in flight — the caller can show a SnackBar / haptic to
  ///   tell the user we're already on it, but most call-sites simply
  ///   discard the return.
  /// - Re-throws any exception [action] throws, after releasing the
  ///   guard so the user can retry.
  /// - Calls `setState` on entry + exit so build-time-gated widgets
  ///   (e.g. `onPressed: isMoneyMutationInFlight ? null : …`) update
  ///   immediately.
  Future<R?> guardMoneyMutation<R>(Future<R> Function() action) async {
    if (_moneyMutationInFlight) return null;
    if (mounted) {
      setState(() {
        _moneyMutationInFlight = true;
      });
    } else {
      _moneyMutationInFlight = true;
    }
    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          _moneyMutationInFlight = false;
        });
      } else {
        _moneyMutationInFlight = false;
      }
    }
  }
}
