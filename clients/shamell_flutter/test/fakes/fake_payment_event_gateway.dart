import 'dart:async';

import 'package:shamell_flutter/core/payment_event_bus.dart';
import 'package:shamell_flutter/core/payment_event_gateway.dart';

/// Test double for [PaymentEventGateway].
///
/// **What this replaces.** The production [DefaultPaymentEventGateway] calls
/// `PaymentEventStream.instance.start(...)` which opens a long-lived SSE
/// `HttpClient` and arms a 500ms reconnect `Timer` on failure. In widget
/// tests the mock binary messenger returns HTTP 400 for unbound channels, so
/// the reconnect Timer fires past test teardown and trips
/// `flutter_test`'s `!timersPending` assertion. The
/// `history_page_session_guard_test.dart` flakiness was a direct consequence.
///
/// **What this gives back.** Calls into [start] / [reconnectNow] / [stop] are
/// recorded but otherwise no-op. The event stream is fed by a
/// `StreamController` the test owns, so a test can:
///
///   final gateway = FakePaymentEventGateway();
///   // ... mount HistoryPage(paymentEventGateway: gateway) ...
///   gateway.emit(PaymentEvent(kind: PaymentEventKind.credit, ...));
///   await tester.pump();
///   // ... assert UI updated ...
///   await gateway.dispose();
///
/// The `dispose` call closes the controller so no listener leaks past the
/// test. Use `addTearDown(gateway.dispose)` to make that automatic.
class FakePaymentEventGateway implements PaymentEventGateway {
  final StreamController<PaymentEvent> _controller =
      StreamController<PaymentEvent>.broadcast();

  /// Record of `start` calls, in order. Each entry is `(baseUrl, walletId,
  /// deviceId)`. Tests can assert that HistoryPage's reconnect-on-resume
  /// logic invoked the gateway the expected number of times.
  final List<({String baseUrl, String walletId, String? deviceId})> startCalls =
      <({String baseUrl, String walletId, String? deviceId})>[];

  /// Count of `reconnectNow` calls.
  int reconnectCalls = 0;

  /// Count of `stop` calls.
  int stopCalls = 0;

  @override
  Stream<PaymentEvent> get stream => _controller.stream;

  @override
  Future<void> start({
    required String baseUrl,
    required String walletId,
    String? deviceId,
  }) async {
    startCalls.add((baseUrl: baseUrl, walletId: walletId, deviceId: deviceId));
  }

  @override
  void reconnectNow() {
    reconnectCalls += 1;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  /// Inject an event into the fake stream so subscribers can observe it.
  /// Drops silently if the controller has been closed (test teardown).
  void emit(PaymentEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  /// Close the underlying stream controller. Must be called in test teardown
  /// or via `addTearDown` so no subscription leaks.
  Future<void> dispose() async {
    if (_controller.isClosed) return;
    await _controller.close();
  }
}
