import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/call_signaling.dart';

void main() {
  group('CallSignalingClient.awaitReady', () {
    test('returns false within timeout when never connect()ed', () async {
      final client = CallSignalingClient('https://api.example');
      // Without a prior `connect()` call, awaitReady has nothing to
      // wait on. It must NOT hang forever — it should observe the
      // null completer state and resolve to `false` immediately so
      // the caller can fail-fast.
      final result = await client.awaitReady(
        timeout: const Duration(milliseconds: 200),
      );
      expect(result, isFalse);
    });

    test('returns false on timeout when WS handshake never completes',
        () async {
      // Point at a URL the WS connect can't actually reach. The
      // shamellTrustedCallSignalingBaseUri guard will reject the
      // base URL (no real backend), so `_connectInternal` will
      // settle the ready future as `false` quickly. This exercises
      // the failure-resolution path of the completer.
      final client = CallSignalingClient('http://insecure.invalid');
      final stream = client.connect(deviceId: 'dev-test');
      // Listen so the stream-controller isn't paused.
      final sub = stream.listen((_) {});
      try {
        final result = await client.awaitReady(
          timeout: const Duration(seconds: 2),
        );
        // The TLS-pin guard rejects insecure transport synchronously
        // → completer resolves false fast (well under 2 s).
        expect(result, isFalse);
      } finally {
        await sub.cancel();
        client.close();
      }
    });

    test(
        'subsequent connect() resets the completer so a fresh awaitReady can resolve',
        () async {
      final client = CallSignalingClient('http://insecure.invalid');
      // First attempt: will settle false (insecure transport).
      final stream1 = client.connect(deviceId: 'dev-1');
      final sub1 = stream1.listen((_) {});
      final first = await client.awaitReady(
        timeout: const Duration(seconds: 2),
      );
      expect(first, isFalse);
      await sub1.cancel();

      // Second connect() creates a fresh completer. Even though the
      // base URL is still invalid, the future MUST settle (not hang
      // on the prior completer). This pins the lifecycle contract
      // that the audit-fix relies on.
      final stream2 = client.connect(deviceId: 'dev-2');
      final sub2 = stream2.listen((_) {});
      final second = await client.awaitReady(
        timeout: const Duration(seconds: 2),
      );
      expect(second, isFalse);
      await sub2.cancel();
      client.close();
    });
  });
}
