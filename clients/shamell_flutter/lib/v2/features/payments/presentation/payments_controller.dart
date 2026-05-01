import 'package:flutter/foundation.dart';

import '../../../../core/payments/payments_idempotency.dart';
import '../../../core/analytics/analytics_event.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/analytics/v2_event_catalog.dart';
import '../../../core/metrics/kpi_tracker.dart';
import '../application/transfer_use_case.dart';
import '../domain/payment_transfer.dart';

@visibleForTesting
bool shamellIsCriticalV2PaymentsUiFailure(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('no longer valid on this device') ||
      text.contains('auth session required') ||
      text.contains('authentication required') ||
      text.contains('unauthorized') ||
      text.contains('forbidden') ||
      text.contains('sign in again');
}

class PaymentsController extends ChangeNotifier {
  final TransferUseCase transferUseCase;
  final AnalyticsService analytics;
  final KpiTracker kpi;

  PaymentsController({
    required this.transferUseCase,
    required this.analytics,
    required this.kpi,
  });

  bool busy = false;
  bool isLoadingBalance = false;
  String error = '';
  String success = '';
  int balanceCents = 2000000;
  String _activeWalletId = '';
  bool sessionResetRequired = false;
  String _pendingTransferFingerprint = '';
  String _pendingTransferIdempotencyKey = '';

  Future<void> bindWallet(String walletId) async {
    final normalized = walletId.trim();
    if (normalized.isEmpty || normalized == _activeWalletId) {
      return;
    }
    _activeWalletId = normalized;
    await refreshBalance(walletId: normalized);
  }

  Future<void> refreshBalance({required String walletId}) async {
    final normalized = walletId.trim();
    if (normalized.isEmpty || isLoadingBalance) {
      return;
    }
    isLoadingBalance = true;
    sessionResetRequired = false;
    notifyListeners();
    try {
      balanceCents =
          await transferUseCase.loadBalanceCents(walletId: normalized);
    } catch (e) {
      if (shamellIsCriticalV2PaymentsUiFailure(e)) {
        sessionResetRequired = true;
        error = 'Session reset. Sign in again.';
      } else if (error.isEmpty) {
        error = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      isLoadingBalance = false;
      notifyListeners();
    }
  }

  Future<void> transfer({
    required String fromWalletId,
    required String toWalletId,
    required int amountCents,
  }) async {
    if (busy) {
      return;
    }
    final normalizedFromWalletId = fromWalletId.trim();
    final normalizedToWalletId = toWalletId.trim();
    final idempotencyKey = _reuseOrCreateTransferIdempotencyKey(
      fromWalletId: normalizedFromWalletId,
      toWalletId: normalizedToWalletId,
      amountCents: amountCents,
    );
    _activeWalletId = normalizedFromWalletId.isNotEmpty
        ? normalizedFromWalletId
        : _activeWalletId;
    busy = true;
    error = '';
    success = '';
    sessionResetRequired = false;
    notifyListeners();
    final startedAt = DateTime.now();
    try {
      final result = await transferUseCase.run(
        PaymentTransfer(
          fromWalletId: normalizedFromWalletId,
          toWalletId: normalizedToWalletId,
          amountCents: amountCents,
          idempotencyKey: idempotencyKey,
        ),
      );
      _clearPendingTransferIdempotencyKey();
      balanceCents = result.newBalanceCents;
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      await analytics.track(
        AnalyticsEvent(
          name: V2EventCatalog.paymentsTransferSucceeded,
          timestamp: DateTime.now(),
          properties: <String, Object?>{
            'amount_cents': amountCents,
            'elapsed_ms': elapsedMs,
          },
        ),
      );
      success = 'Transfer completed.';
      await kpi.markFirstSuccess(flow: 'payments');
    } catch (e) {
      if (shamellIsCriticalV2PaymentsUiFailure(e)) {
        sessionResetRequired = true;
        error = 'Session reset. Sign in again.';
      } else {
        error = e.toString().replaceFirst('Exception: ', '');
      }
      await analytics.track(
        AnalyticsEvent(
          name: V2EventCatalog.errorShown,
          timestamp: DateTime.now(),
          properties: const <String, Object?>{
            'code': 'payments.transfer_failed',
            'surface': 'payments',
          },
        ),
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _reuseOrCreateTransferIdempotencyKey({
    required String fromWalletId,
    required String toWalletId,
    required int amountCents,
  }) {
    final fingerprint =
        '${fromWalletId.trim()}|${toWalletId.trim()}|$amountCents';
    if (_pendingTransferFingerprint == fingerprint &&
        _pendingTransferIdempotencyKey.isNotEmpty) {
      return _pendingTransferIdempotencyKey;
    }
    _pendingTransferFingerprint = fingerprint;
    _pendingTransferIdempotencyKey = newPaymentsIdempotencyKey('v2tw');
    return _pendingTransferIdempotencyKey;
  }

  void _clearPendingTransferIdempotencyKey() {
    _pendingTransferFingerprint = '';
    _pendingTransferIdempotencyKey = '';
  }
}
