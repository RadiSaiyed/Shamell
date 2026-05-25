bool shamellEffectiveFailWithoutHeadersOnIo({
  required bool releaseMode,
  required bool failWithoutHeadersOnIo,
}) {
  // Security hardening: release builds must always fail closed and never retry
  // authenticated websocket upgrades without headers.
  return releaseMode || failWithoutHeadersOnIo;
}

bool shamellShouldRetryWebSocketWithoutHeaders({
  required Map<String, String> headers,
  required bool failWithoutHeadersOnIo,
}) {
  return headers.isNotEmpty && !failWithoutHeadersOnIo;
}
