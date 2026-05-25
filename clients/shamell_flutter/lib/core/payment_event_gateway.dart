import 'dart:async';

import 'payment_event_bus.dart';
import 'payment_event_stream.dart';

/// Injectable seam over [PaymentEventStream] + [PaymentEventBus] so widgets
/// like `HistoryPage` and `PaymentsOverview` can be unit-tested without the
/// real SSE / singleton machinery (Cycle 3C).
///
/// **Why this exists.** The production `PaymentEventStream` is a process-wide
/// singleton that, when [start]ed, immediately opens an `HttpClient` against
/// `${baseUrl}/payments/events/stream` and — on failure — schedules a 500ms
/// reconnect `Timer`. In Flutter widget tests the mock binary messenger
/// returns HTTP 400 for unbound channels, so the timer keeps re-arming past
/// the test's teardown and trips `flutter_test`'s `!timersPending` assertion.
/// The flaky-test marker in `history_page_session_guard_test.dart` (search
/// `TODO(chat-stab)`) traces back to exactly that race.
///
/// By routing every widget consumer through a [PaymentEventGateway] handle,
/// tests can inject a no-op fake whose [start] returns immediately and whose
/// [stream] is driven by a `StreamController` they fully control. Production
/// code wires up [DefaultPaymentEventGateway] which forwards all four methods
/// to the existing singletons — so behaviour is identical to the pre-Cycle
/// 3C path. **Adding the seam is API-additive only**; no existing call site
/// changes its observable behaviour.
abstract class PaymentEventGateway {
  /// Broadcast stream that subscribers (e.g. HistoryPage) listen to. In
  /// production this is [PaymentEventBus.instance.stream].
  Stream<PaymentEvent> get stream;

  /// Ensures the underlying realtime source is connected for [walletId]
  /// against [baseUrl]. Idempotent — calling twice with the same args is a
  /// no-op. Matches [PaymentEventStream.start].
  Future<void> start({
    required String baseUrl,
    required String walletId,
    String? deviceId,
  });

  /// Force an immediate reconnect attempt. Matches
  /// [PaymentEventStream.reconnectNow]. No-op if not running.
  void reconnectNow();

  /// Tear down the active connection. Matches [PaymentEventStream.stop].
  Future<void> stop();
}

/// Production [PaymentEventGateway] — a thin pass-through to the global
/// [PaymentEventStream] singleton + [PaymentEventBus] singleton.
///
/// Holds no per-instance state, so every instance is interchangeable. Widgets
/// can `const DefaultPaymentEventGateway()` cheaply at every build if
/// desired, but we deliberately don't make it `const` for one reason: it
/// guards against accidentally comparing two gateway references for identity
/// in tests where the production gateway should be considered distinct from
/// a test fake.
class DefaultPaymentEventGateway implements PaymentEventGateway {
  /// Public constructor so widgets can default-construct one inline. Sharing
  /// instances across widgets is fine because all state lives on the
  /// singletons this delegates to.
  DefaultPaymentEventGateway();

  @override
  Stream<PaymentEvent> get stream => PaymentEventBus.instance.stream;

  @override
  Future<void> start({
    required String baseUrl,
    required String walletId,
    String? deviceId,
  }) {
    return PaymentEventStream.instance.start(
      baseUrl: baseUrl,
      walletId: walletId,
      deviceId: deviceId,
    );
  }

  @override
  void reconnectNow() {
    PaymentEventStream.instance.reconnectNow();
  }

  @override
  Future<void> stop() {
    return PaymentEventStream.instance.stop();
  }
}
