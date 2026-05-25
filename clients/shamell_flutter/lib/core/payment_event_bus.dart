import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_sounds.dart';

/// Discriminator for payment-related realtime events flowing through the bus.
enum PaymentEventKind {
  credit,
  debit,
  request,
  topup,
  refundCredit,
  unknown,
}

/// Origin of a [PaymentEvent], used for deduplication and side-effect policy.
enum PaymentEventSource {
  /// Originated locally from an action the current client just executed.
  /// The local handler is responsible for its own UX; bus skips side-effects.
  local,

  /// Delivered via Firebase Cloud Messaging push.
  fcm,

  /// Delivered via the realtime SSE stream.
  sse,

  /// Synthetic / unknown origin.
  unknown,
}

@immutable
class PaymentEvent {
  const PaymentEvent({
    required this.kind,
    this.walletId,
    this.amountCents,
    this.currency,
    this.peerWalletId,
    this.txnId,
    this.requestId,
    this.source = PaymentEventSource.unknown,
  });

  final PaymentEventKind kind;
  final String? walletId;
  final int? amountCents;
  final String? currency;
  final String? peerWalletId;
  final String? txnId;
  final String? requestId;
  final PaymentEventSource source;

  bool get isInbound =>
      kind == PaymentEventKind.credit ||
      kind == PaymentEventKind.refundCredit ||
      kind == PaymentEventKind.topup;

  bool get isOutbound => kind == PaymentEventKind.debit;

  static PaymentEventKind kindFromWire(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'payment_credit':
      case 'transfer.credit':
      case 'wallet.credit':
        return PaymentEventKind.credit;
      case 'transfer.debit':
      case 'wallet.debit':
        return PaymentEventKind.debit;
      case 'payment_request':
      case 'request.created':
        return PaymentEventKind.request;
      case 'wallet.topup':
        return PaymentEventKind.topup;
      case 'refund.credit':
      case 'refund.applied':
        return PaymentEventKind.refundCredit;
      default:
        return PaymentEventKind.unknown;
    }
  }

  static int? _intOrNull(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _trimmedOrNull(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Parse an FCM RemoteMessage data map into an event, if recognized.
  ///
  /// Returns `null` for unknown push types; callers can pass through to other
  /// handlers (e.g. chat, ride) without false matches.
  static PaymentEvent? fromFcmData(Map<Object?, Object?> data) {
    final kind = kindFromWire(data['type']?.toString());
    if (kind == PaymentEventKind.unknown) return null;
    return PaymentEvent(
      kind: kind,
      walletId: _trimmedOrNull(data['wallet_id']),
      amountCents: _intOrNull(data['amount_cents']),
      currency: _trimmedOrNull(data['currency']),
      peerWalletId: _trimmedOrNull(data['peer_wallet_id']),
      txnId: _trimmedOrNull(data['txn_id']),
      requestId: _trimmedOrNull(data['request_id']),
      source: PaymentEventSource.fcm,
    );
  }
}

/// Process-wide singleton that fans out payment events to UI subscribers and
/// drives global side-effects (sound + haptic feedback).
///
/// Wiring:
/// - FCM foreground messages → [emit] with [PaymentEventSource.fcm]
/// - SSE stream entries (Stage 2)  → [emit] with [PaymentEventSource.sse]
/// - Local optimistic UI flows → [emit] with [PaymentEventSource.local]
///   (or skip the bus entirely; bus suppresses sound/haptic for local).
class PaymentEventBus {
  PaymentEventBus._() {
    _selfSubscription = stream.listen(_dispatchSideEffects);
  }

  static final PaymentEventBus instance = PaymentEventBus._();

  final StreamController<PaymentEvent> _controller =
      StreamController<PaymentEvent>.broadcast();

  late final StreamSubscription<PaymentEvent> _selfSubscription;

  /// Recently-seen txn ids, used to suppress duplicate side-effects when a
  /// local action and a remote echo arrive close together. Bounded LRU.
  final Queue<String> _recentTxnIds = Queue<String>();
  static const int _recentTxnIdsMax = 64;

  Stream<PaymentEvent> get stream => _controller.stream;

  /// Emit an event onto the bus. Safe to call from any isolate hop, but
  /// listeners are notified on the calling zone.
  void emit(PaymentEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  /// Mark a transaction id as locally observed so subsequent remote echoes
  /// don't trigger another sound/haptic. Call this immediately before the
  /// local optimistic UX fires.
  void markTxnAsLocal(String? txnId) {
    if (txnId == null || txnId.isEmpty) return;
    _recentTxnIds.add(txnId);
    while (_recentTxnIds.length > _recentTxnIdsMax) {
      _recentTxnIds.removeFirst();
    }
  }

  bool _isRecentLocalTxn(String? txnId) {
    if (txnId == null || txnId.isEmpty) return false;
    return _recentTxnIds.contains(txnId);
  }

  Future<void> _dispatchSideEffects(PaymentEvent event) async {
    if (event.source == PaymentEventSource.local) return;
    if (_isRecentLocalTxn(event.txnId)) return;
    // Whichever remote source delivers first wins; record the txn so any
    // follow-up echo (e.g. FCM after SSE for the same operation) is muted.
    _recordTxnId(event.txnId);
    switch (event.kind) {
      case PaymentEventKind.credit:
      case PaymentEventKind.refundCredit:
      case PaymentEventKind.topup:
        unawaited(HapticFeedback.heavyImpact());
        await ShamellSoundEffects.play(ShamellSoundEffect.moneyReceived);
        break;
      case PaymentEventKind.debit:
        unawaited(HapticFeedback.mediumImpact());
        await ShamellSoundEffects.play(ShamellSoundEffect.paymentSent);
        break;
      case PaymentEventKind.request:
        unawaited(HapticFeedback.selectionClick());
        await ShamellSoundEffects.play(ShamellSoundEffect.paymentRequest);
        break;
      case PaymentEventKind.unknown:
        break;
    }
  }

  void _recordTxnId(String? txnId) {
    if (txnId == null || txnId.isEmpty) return;
    if (_recentTxnIds.contains(txnId)) return;
    _recentTxnIds.add(txnId);
    while (_recentTxnIds.length > _recentTxnIdsMax) {
      _recentTxnIds.removeFirst();
    }
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    await _selfSubscription.cancel();
    await _controller.close();
  }
}
