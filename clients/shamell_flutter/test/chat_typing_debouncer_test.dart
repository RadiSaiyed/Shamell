import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_typing_debouncer.dart';

class _Counter {
  int started = 0;
  int stopped = 0;
}

void main() {
  group('ChatTypingDebouncer', () {
    test('first onTextChanged emits started exactly once', () {
      fakeAsync((async) {
        final c = _Counter();
        final d = ChatTypingDebouncer(
          emitStarted: () async => c.started += 1,
          emitStopped: () async => c.stopped += 1,
          emitInterval: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 3),
        );
        d.onTextChanged();
        async.flushMicrotasks();
        expect(c.started, 1);
        expect(c.stopped, 0);
        d.dispose();
      });
    });

    test('rapid keystrokes within emitInterval do NOT re-emit started', () {
      fakeAsync((async) {
        final c = _Counter();
        final d = ChatTypingDebouncer(
          emitStarted: () async => c.started += 1,
          emitStopped: () async => c.stopped += 1,
          emitInterval: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 3),
        );
        d.onTextChanged();
        d.onTextChanged();
        d.onTextChanged();
        async.elapse(const Duration(seconds: 2));
        d.onTextChanged();
        async.flushMicrotasks();
        expect(c.started, 1, reason: 'all keystrokes within 5s → 1 emit');
        d.dispose();
      });
    });

    test('after emitInterval, next keystroke emits started again', () {
      fakeAsync((async) {
        final c = _Counter();
        final d = ChatTypingDebouncer(
          emitStarted: () async => c.started += 1,
          emitStopped: () async => c.stopped += 1,
          emitInterval: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 30),
        );
        d.onTextChanged();
        // Burst typing keeps the idle timer fresh but the started
        // emission is rate-limited.
        for (var i = 0; i < 10; i++) {
          async.elapse(const Duration(milliseconds: 500));
          d.onTextChanged();
        }
        // Total elapsed: 5s. Next keystroke after 5s should emit
        // started again.
        async.elapse(const Duration(milliseconds: 100));
        d.onTextChanged();
        async.flushMicrotasks();
        expect(c.started, 2);
        d.dispose();
      });
    });

    test('idle timeout fires stopped automatically', () {
      fakeAsync((async) {
        final c = _Counter();
        final d = ChatTypingDebouncer(
          emitStarted: () async => c.started += 1,
          emitStopped: () async => c.stopped += 1,
          emitInterval: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 3),
        );
        d.onTextChanged();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(c.started, 1);
        expect(c.stopped, 1, reason: 'after 3s of silence stopped fires');
        d.dispose();
      });
    });

    test('emitStoppedNow short-circuits the idle timer + only fires once', () async {
      final c = _Counter();
      final d = ChatTypingDebouncer(
        emitStarted: () async => c.started += 1,
        emitStopped: () async => c.stopped += 1,
        emitInterval: const Duration(seconds: 5),
        idleTimeout: const Duration(seconds: 30),
      );
      d.onTextChanged();
      // Pump the started microtask.
      await Future<void>.delayed(Duration.zero);
      expect(c.started, 1);

      await d.emitStoppedNow();
      expect(c.stopped, 1);

      // Calling again — already stopped, no double-fire.
      await d.emitStoppedNow();
      expect(c.stopped, 1);
      d.dispose();
    });

    test('stopped does NOT fire if started was never emitted', () {
      fakeAsync((async) {
        final c = _Counter();
        final d = ChatTypingDebouncer(
          emitStarted: () async => c.started += 1,
          emitStopped: () async => c.stopped += 1,
        );
        // Never call onTextChanged → never started → idle timer
        // wasn't even armed.
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(c.started, 0);
        expect(c.stopped, 0);
        d.dispose();
      });
    });

    test('after stopped fires, next keystroke restarts the cycle', () {
      fakeAsync((async) {
        final c = _Counter();
        final d = ChatTypingDebouncer(
          emitStarted: () async => c.started += 1,
          emitStopped: () async => c.stopped += 1,
          emitInterval: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 3),
        );
        d.onTextChanged();
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(c.stopped, 1);

        // New typing session — should emit started immediately (the
        // emitInterval rate-limit is per emission of started, so a
        // fresh session after stopped restarts the cooldown clock).
        d.onTextChanged();
        async.flushMicrotasks();
        expect(c.started, 2);
        d.dispose();
      });
    });

    test('dispose stops all future emissions', () {
      fakeAsync((async) {
        final c = _Counter();
        final d = ChatTypingDebouncer(
          emitStarted: () async => c.started += 1,
          emitStopped: () async => c.stopped += 1,
        );
        d.onTextChanged();
        async.flushMicrotasks();
        d.dispose();
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        // Started fired before dispose; stopped never fires because
        // the idle timer was canceled by dispose.
        expect(c.started, 1);
        expect(c.stopped, 0);

        // Further onTextChanged on a disposed debouncer is a no-op.
        d.onTextChanged();
        async.flushMicrotasks();
        expect(c.started, 1);
      });
    });
  });
}
