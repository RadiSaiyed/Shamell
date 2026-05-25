import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'base_url.dart';
import 'payment_event_bus.dart';
import 'session_cookie_store.dart';

/// Long-lived SSE consumer for payment events.
///
/// Connects to `${baseUrl}/payments/events/stream` (the BFF endpoint), parses
/// the SSE wire format, decodes each event payload, and re-publishes it to
/// [PaymentEventBus]. The bus then drives sound + haptic feedback and any
/// subscribed UI.
///
/// Lifecycle:
/// - [start] is idempotent. Calling it after auth ensures the singleton holds
///   exactly one upstream connection at a time.
/// - On network failure or upstream close, reconnect with capped exponential
///   backoff (500ms → 32s).
/// - [stop] tears down the active connection and pauses retries (e.g. on
///   logout); subsequent [start] resumes cleanly.
class PaymentEventStream {
  PaymentEventStream._();

  static final PaymentEventStream instance = PaymentEventStream._();

  static const Duration _initialBackoff = Duration(milliseconds: 500);
  static const Duration _maxBackoff = Duration(seconds: 32);

  String? _baseUrl;
  String? _walletId;
  String? _deviceId;

  bool _running = false;
  bool _connecting = false;
  HttpClient? _activeHttpClient;
  StreamSubscription<List<int>>? _activeSubscription;
  Timer? _retryTimer;
  int _consecutiveFailures = 0;

  /// Last event id observed from either the live SSE stream or a backfill
  /// fetch. Used as a cursor against `/payments/events?since_id=...` so
  /// events emitted during a reconnect gap are replayed before we resume
  /// listening.
  String? _lastEventId;

  /// Ensure the SSE consumer is connected for [walletId] against [baseUrl].
  ///
  /// Safe to call repeatedly (e.g. on every screen mount). If already running
  /// against the same wallet/base, this is a no-op. If parameters changed
  /// since the last call, the previous connection is torn down and a new one
  /// established.
  Future<void> start({
    required String baseUrl,
    required String walletId,
    String? deviceId,
  }) async {
    if (walletId.trim().isEmpty || baseUrl.trim().isEmpty) {
      return;
    }
    if (_running &&
        _baseUrl == baseUrl &&
        _walletId == walletId &&
        _deviceId == deviceId) {
      return;
    }
    await stop();
    _baseUrl = baseUrl;
    _walletId = walletId;
    _deviceId = deviceId;
    _running = true;
    _consecutiveFailures = 0;
    unawaited(_connect());
  }

  /// Force an immediate reconnect attempt, bypassing any backoff.
  /// Use after the app returns to the foreground or after a known network
  /// transition (Wi-Fi ↔ cellular) so users don't wait for the next retry.
  void reconnectNow() {
    if (!_running) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _consecutiveFailures = 0;
    if (_connecting) return;
    final sub = _activeSubscription;
    _activeSubscription = null;
    if (sub != null) {
      try {
        unawaited(sub.cancel());
      } catch (_) {}
    }
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    unawaited(_connect());
  }

  /// Tear down the active connection and cancel any pending retry. The bus
  /// itself is not affected.
  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    final sub = _activeSubscription;
    _activeSubscription = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
  }

  Duration _backoffFor(int attempt) {
    if (attempt <= 0) return Duration.zero;
    final clamped = attempt.clamp(1, 6);
    final ms = _initialBackoff.inMilliseconds * (1 << (clamped - 1));
    final capped = ms.clamp(0, _maxBackoff.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  Future<void> _connect() async {
    if (!_running || _connecting) return;
    _connecting = true;

    final baseUrl = _baseUrl ?? '';
    final walletId = _walletId ?? '';
    final deviceId = (_deviceId ?? '').trim();

    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const ['payments', 'events', 'stream'],
    );
    if (uri == null) {
      _connecting = false;
      return;
    }

    // Use dart:io HttpClient directly: package:http's IOClient wraps the
    // response stream in a way that defers chunk delivery for long-lived
    // chunked transfers, breaking SSE on Android.
    //
    // Disable autoUncompress: the SSE keep-alive frames are tiny comments
    // (`:keepalive\n\n`) and any decompression stage tends to buffer until
    // the deflate window is full, masking liveness.
    // Bump idleTimeout well past the server's 8s keep-alive cadence so the
    // dart:io HttpClient does not silently tear down a live SSE socket.
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(minutes: 5);
    _activeHttpClient = client;

    String? cookieHeader;
    try {
      cookieHeader = await getSessionCookieHeader(baseUrl);
    } catch (_) {
      cookieHeader = null;
    }

    assert(() {
      // ignore: avoid_print
      print('PaymentEventStream connecting cookie=${cookieHeader != null}');
      return true;
    }());
    HttpClientResponse response;
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        req.headers.set('Cookie', cookieHeader);
      }
      if (deviceId.isNotEmpty) {
        req.headers.set('x-device-id', deviceId);
      }
      response = await req.close();
    } catch (error) {
      assert(() {
        // ignore: avoid_print
        print('PaymentEventStream connect threw $error');
        return true;
      }());
      _connecting = false;
      client.close(force: true);
      _activeHttpClient = null;
      _scheduleReconnect();
      return;
    }

    assert(() {
      // ignore: avoid_print
      print('PaymentEventStream connect status=${response.statusCode}');
      return true;
    }());
    if (response.statusCode != 200) {
      try {
        await response.drain<void>(null);
      } catch (_) {}
      _connecting = false;
      client.close(force: true);
      _activeHttpClient = null;
      // 401/403 mean the session is invalid; don't burn battery retrying
      // until the caller restarts the stream after re-auth.
      if (response.statusCode == 401 || response.statusCode == 403) {
        _running = false;
        return;
      }
      _scheduleReconnect();
      return;
    }

    _consecutiveFailures = 0;
    final decoder = utf8.decoder;
    final stringBuffer = StringBuffer();
    String? eventType;
    final dataLines = <String>[];

    void emitCurrent() {
      if (dataLines.isEmpty && eventType == null) return;
      final dataRaw = dataLines.join('\n');
      _handleSseEvent(eventType, dataRaw, walletFilter: walletId);
      eventType = null;
      dataLines.clear();
    }

    void processLine(String line) {
      if (line.isEmpty) {
        emitCurrent();
        return;
      }
      if (line.startsWith(':')) {
        // SSE comment / keepalive — ignore.
        return;
      }
      final colon = line.indexOf(':');
      if (colon <= 0) return;
      final field = line.substring(0, colon);
      var value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          eventType = value;
          break;
        case 'data':
          dataLines.add(value);
          break;
        // 'id' / 'retry' currently unused.
      }
    }

    void onChunk(List<int> chunk) {
      stringBuffer.write(decoder.convert(chunk));
      while (true) {
        final s = stringBuffer.toString();
        final newlineIdx = s.indexOf('\n');
        if (newlineIdx < 0) break;
        final raw = s.substring(0, newlineIdx);
        final line = raw.endsWith('\r')
            ? raw.substring(0, raw.length - 1)
            : raw;
        stringBuffer.clear();
        stringBuffer.write(s.substring(newlineIdx + 1));
        processLine(line);
      }
    }

    final subscription = response.listen(
      onChunk,
      onError: (Object _, StackTrace __) {
        _connecting = false;
        _activeHttpClient?.close(force: true);
        _activeHttpClient = null;
        _scheduleReconnect();
      },
      onDone: () {
        _connecting = false;
        _activeHttpClient?.close(force: true);
        _activeHttpClient = null;
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
    _activeSubscription = subscription;
    _connecting = false;

    // Backfill any events emitted while we were disconnected. The bus dedups
    // by txn_id so replays don't double-fire sound/haptic.
    unawaited(_backfillSinceLast(baseUrl: baseUrl, walletFilter: walletId));
  }

  Future<void> _backfillSinceLast({
    required String baseUrl,
    required String walletFilter,
  }) async {
    final cursor = _lastEventId;
    if (cursor == null || cursor.isEmpty) return;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const ['payments', 'events'],
      queryParameters: {'since_id': cursor},
    );
    if (uri == null) return;
    String? cookieHeader;
    try {
      cookieHeader = await getSessionCookieHeader(baseUrl);
    } catch (_) {}
    final client = HttpClient()..autoUncompress = true;
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        req.headers.set('Cookie', cookieHeader);
      }
      final resp = await req
          .close()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        throw TimeoutException('backfill timeout');
      });
      if (resp.statusCode != 200) {
        await resp.drain<void>(null);
        return;
      }
      final body = await resp.transform(utf8.decoder).join();
      final decoded = json.decode(body);
      if (decoded is! List) return;
      var replayed = 0;
      for (final event in decoded) {
        if (event is! Map) continue;
        _handleSseEvent(
          event['event_type']?.toString(),
          json.encode(event),
          walletFilter: walletFilter,
        );
        replayed += 1;
      }
      if (replayed > 0) {
        assert(() {
          // ignore: avoid_print
          print('PaymentEventStream backfill replayed $replayed event(s)');
          return true;
        }());
      }
    } catch (error) {
      assert(() {
        // ignore: avoid_print
        print('PaymentEventStream backfill error $error');
        return true;
      }());
    } finally {
      client.close(force: true);
    }
  }

  void _handleSseEvent(
    String? eventTypeFromFrame,
    String dataRaw, {
    required String walletFilter,
  }) {
    if (dataRaw.isEmpty) return;
    Map<String, dynamic>? parsed;
    try {
      final decoded = json.decode(dataRaw);
      if (decoded is Map<String, dynamic>) {
        parsed = decoded;
      }
    } catch (_) {
      return;
    }
    if (parsed == null) return;

    final walletId = parsed['wallet_id']?.toString();
    if (walletId == null || walletId != walletFilter) {
      // Server already filters; this is a defensive fallback.
      return;
    }
    final eventId = parsed['id']?.toString();
    if (eventId != null && eventId.isNotEmpty) {
      _lastEventId = eventId;
    }
    final wireType =
        eventTypeFromFrame ?? parsed['event_type']?.toString();
    final kind = PaymentEvent.kindFromWire(wireType);
    if (kind == PaymentEventKind.unknown) return;

    final payload = parsed['payload'];
    int? amountCents;
    String? currency;
    String? peerWalletId;
    String? txnId;
    if (payload is Map) {
      final ac = payload['amount_cents'];
      if (ac is int) {
        amountCents = ac;
      } else if (ac is num) {
        amountCents = ac.toInt();
      } else if (ac is String) {
        amountCents = int.tryParse(ac);
      }
      currency = payload['currency']?.toString();
      peerWalletId = payload['peer_wallet_id']?.toString();
      txnId = payload['txn_id']?.toString();
    }

    PaymentEventBus.instance.emit(PaymentEvent(
      kind: kind,
      walletId: walletId,
      amountCents: amountCents,
      currency: currency,
      peerWalletId: peerWalletId,
      txnId: txnId,
      source: PaymentEventSource.sse,
    ));
  }

  void _scheduleReconnect() {
    if (!_running) return;
    final sub = _activeSubscription;
    _activeSubscription = null;
    if (sub != null) {
      try {
        unawaited(sub.cancel());
      } catch (_) {}
    }
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    _consecutiveFailures += 1;
    final delay = _backoffFor(_consecutiveFailures);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }
}
