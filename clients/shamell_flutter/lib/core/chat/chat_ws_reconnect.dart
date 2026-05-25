/// Exponential-backoff schedule for the chat WebSocket reconnect
/// machinery in `_ShamellChatPageState._listenWs`.
///
/// **Why a separate helper.** The reconnect logic on the page was
/// inlined as a `Future.delayed(Duration(seconds: 2))` band-aid that
/// hammered the server every 2 s after a disconnect. Once a clean
/// schedule is here, the page's `_scheduleInboxWsReconnect` is a
/// 3-line consumer and the schedule itself is unit-testable without a
/// `BuildContext` or a real socket.
///
/// **Schedule.** First reconnect after a disconnect is immediate
/// (0 ms). The second is 1 s. Each subsequent attempt doubles up to a
/// `maxDelayMs` ceiling. This matches the WhatsApp /
/// Signal / Telegram practice of "try once fast, then back off so we
/// don't DDoS the server during an outage." The very first attempt
/// (i.e. step 0) returns 0 so the first reconnect after a clean
/// disconnect is instant — same as iMessage's behaviour when a network
/// blip hands the socket back without a roundtrip.
///
/// **Reset semantics.** When the socket successfully delivers a
/// payload, the caller resets the schedule to step 0. The next
/// disconnect therefore tries immediately again — without that reset,
/// a long-lived connection that flaps every 30 minutes would slowly
/// drift into 30 s reconnect delays forever.

/// Computes the next reconnect delay (in milliseconds) given the
/// current backoff step. `step == 0` produces 0 ms (immediate).
/// `step == 1` produces 1000 ms. Each subsequent step doubles up to
/// `maxDelayMs`.
int chatWsReconnectDelayMs({
  required int step,
  int maxDelayMs = 30000,
}) {
  if (step <= 0) return 0;
  if (maxDelayMs <= 0) return 0;
  // Cap step to prevent overflow on `1 << step` for absurd inputs.
  final capped = step > 20 ? 20 : step;
  final base = 1000 << (capped - 1); // 1s, 2s, 4s, 8s, ...
  if (base >= maxDelayMs) return maxDelayMs;
  return base;
}

/// Advances the step monotonically. Once the step's delay reaches the
/// ceiling, further increments are no-ops (we stay at the ceiling, we
/// don't keep marching the counter forever).
int chatWsReconnectNextStep({
  required int currentStep,
  int maxDelayMs = 30000,
}) {
  final cur = currentStep < 0 ? 0 : currentStep;
  final nextDelay = chatWsReconnectDelayMs(
    step: cur + 1,
    maxDelayMs: maxDelayMs,
  );
  final currentDelay = chatWsReconnectDelayMs(
    step: cur,
    maxDelayMs: maxDelayMs,
  );
  if (nextDelay <= currentDelay && cur > 0) {
    // We're already at the ceiling — don't keep counting.
    return cur;
  }
  return cur + 1;
}
