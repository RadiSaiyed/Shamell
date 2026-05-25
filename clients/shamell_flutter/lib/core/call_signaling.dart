import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'base_url.dart';
import 'chat/chat_service.dart';
import 'device_binding_guard.dart';
import 'session_cookie_store.dart';

bool _isCallSignalingLocalhostHost(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1';
}

@visibleForTesting
Uri? shamellTrustedCallSignalingBaseUri(String baseUrl) {
  final uri = parseApiBaseUrl(baseUrl.trim());
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return uri;
  if (scheme == 'http' && _isCallSignalingLocalhostHost(uri.host)) {
    return uri;
  }
  return null;
}

@visibleForTesting
Uri shamellCallSignalingWsUri({
  required Uri trustedBaseUri,
  required String deviceId,
}) {
  final scheme = trustedBaseUri.scheme.toLowerCase() == 'https' ? 'wss' : 'ws';
  final normalizedDeviceId = deviceId.trim();
  final shouldIncludePort = trustedBaseUri.hasPort && trustedBaseUri.port > 0;
  if (shouldIncludePort) {
    return Uri(
      scheme: scheme,
      host: trustedBaseUri.host,
      port: trustedBaseUri.port,
      path: '/ws/call/signaling',
      queryParameters: <String, String>{'device_id': normalizedDeviceId},
    );
  }
  return Uri(
    scheme: scheme,
    host: trustedBaseUri.host,
    path: '/ws/call/signaling',
    queryParameters: <String, String>{'device_id': normalizedDeviceId},
  );
}

/// Lightweight WebSocket-based signaling client for future VoIP calls.
///
/// This is a stub that defines the on-wire JSON format and connection
/// lifecycle, so that the backend and other clients can implement
/// compatible signaling. Media (WebRTC, native VoIP, etc.) is intentionally
/// out of scope here and can be integrated later.
class CallSignalingClient {
  CallSignalingClient(String baseUrl)
      : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  final String _base;
  WebSocketChannel? _ws;
  StreamController<Map<String, dynamic>>? _eventsCtrl;
  int _connectGeneration = 0;

  /// Completer that resolves the moment the underlying WebSocket is
  /// either successfully attached (`true`) or the connect attempt
  /// terminally failed (`false`). Callers use `awaitReady()` to gate
  /// any outbound send on a real socket — sending before this
  /// resolves is the race that produced "Invite failed" toasts on
  /// the call-page when the user tapped Call faster than the WS
  /// handshake completed.
  ///
  /// Re-created on every `connect()` so a reconnect generation
  /// starts with a fresh pending future.
  Completer<bool>? _readyCompleter;

  /// Connects to the signaling WebSocket for the given deviceId.
  ///
  /// The backend is expected to expose `/ws/call/signaling` and route
  /// events between participants based on `device_id`.
  Stream<Map<String, dynamic>> connect({required String deviceId}) {
    _connectGeneration += 1;
    final generation = _connectGeneration;
    _ws?.sink.close();
    _ws = null;
    // Settle any prior pending completer as `false` so a stale
    // `awaitReady()` from a previous `connect()` call doesn't hang
    // forever after a re-attach.
    final prior = _readyCompleter;
    if (prior != null && !prior.isCompleted) {
      prior.complete(false);
    }
    _readyCompleter = Completer<bool>();
    unawaited(_eventsCtrl?.close());
    _eventsCtrl = StreamController<Map<String, dynamic>>.broadcast();
    unawaited(_connectInternal(
      deviceId: deviceId.trim(),
      generation: generation,
    ));
    return _eventsCtrl!.stream;
  }

  /// Wait (up to [timeout]) for the underlying WebSocket to be
  /// attached after [connect]. Resolves to `true` if the socket is
  /// ready (subsequent `send()` calls will succeed), `false` if the
  /// connection attempt failed terminally, or `false` if the
  /// timeout fires first.
  ///
  /// **Why this exists.** Real-device QA flagged that tapping the
  /// Voice / Video call icon immediately after entering a chat would
  /// reliably show "Failed: Invite failed". Cause: `connect()`
  /// returns the event stream synchronously but kicks the WS
  /// handshake on a microtask — `_ws` is still `null` for the first
  /// ~30-200 ms while DNS + TCP + TLS + WS upgrade complete. The
  /// caller's immediate `sendInvite()` then sees `_ws == null` and
  /// returns `false`. Waiting on this completer makes the caller
  /// patient enough to outlast the handshake without blocking
  /// indefinitely.
  Future<bool> awaitReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_ws != null) return true;
    final c = _readyCompleter;
    if (c == null) return false;
    try {
      return await c.future.timeout(timeout, onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<void> _connectInternal({
    required String deviceId,
    required int generation,
  }) async {
    // Helper to settle the ready-completer exactly once. Generation
    // check guards against settling a future when a newer `connect()`
    // has already replaced the completer.
    void settleReady(bool ok) {
      if (generation != _connectGeneration) return;
      final c = _readyCompleter;
      if (c != null && !c.isCompleted) {
        c.complete(ok);
      }
    }

    if (deviceId.isEmpty) {
      _emit({'type': 'error', 'reason': 'missing_device_id'});
      settleReady(false);
      return;
    }
    try {
      final u = shamellTrustedCallSignalingBaseUri(_base);
      if (u == null) {
        _emit({'type': 'error', 'reason': 'insecure_transport'});
        settleReady(false);
        return;
      }
      final wsUri = shamellCallSignalingWsUri(
        trustedBaseUri: u,
        deviceId: deviceId,
      );

      final headers = await _wsHeaders(deviceId);
      if (shamellCallSignalingRequiresBoundSessionCookie(_base) &&
          (headers['cookie'] ?? '').trim().isEmpty) {
        _emit({'type': 'error', 'detail': 'auth session required'});
        settleReady(false);
        return;
      }
      if (generation != _connectGeneration) return;

      final ws = _connectWebSocket(wsUri, headers: headers);
      if (generation != _connectGeneration) {
        try {
          ws.sink.close();
        } catch (_) {}
        return;
      }
      _ws = ws;
      // Socket handle is attached — `send()` will now succeed.
      // Resolve the ready future so any waiting `awaitReady()` (in
      // `VoipCallPage._bootstrap`) can proceed to send the invite.
      settleReady(true);
      ws.stream.listen(
        (payload) {
          if (generation != _connectGeneration) return;
          try {
            final j = jsonDecode(payload.toString());
            if (j is Map<String, dynamic>) {
              _emit(j);
            }
          } catch (_) {}
        },
        onError: (_) {
          if (generation != _connectGeneration) return;
          _emit({'type': 'error'});
          // If the WS errors before any send completed, also fail
          // any in-flight awaitReady — otherwise the caller waits
          // for the full timeout on a socket that's already dead.
          settleReady(false);
        },
        onDone: () {
          if (generation != _connectGeneration) return;
          _emit({'type': 'closed'});
          settleReady(false);
        },
      );
    } catch (_) {
      _emit({'type': 'error'});
      settleReady(false);
    }
  }

  Future<Map<String, String>> _wsHeaders(String deviceId) async {
    return shamellCallSignalingHeadersForBaseUrl(
      _base,
      deviceId: deviceId,
    );
  }

  WebSocketChannel _connectWebSocket(
    Uri wsUri, {
    required Map<String, String> headers,
  }) {
    return shamellConnectWebSocket(
      wsUri,
      headers: headers,
      failWithoutHeadersOnIo: true,
    );
  }

  void _emit(Map<String, dynamic> event) {
    final ctrl = _eventsCtrl;
    if (ctrl == null || ctrl.isClosed) return;
    try {
      ctrl.add(event);
    } catch (_) {}
  }

  /// Sends a raw signaling message (e.g. invite, answer, hangup, webrtc_offer).
  Future<bool> send(Map<String, Object?> msg) async {
    final ws = _ws;
    if (ws == null) return false;
    try {
      ws.sink.add(jsonEncode(msg));
      return true;
    } catch (_) {}
    return false;
  }

  /// Convenience: send an invite to start a call.
  ///
  /// [fromName] is the caller's display name; the BFF forwards it into the
  /// `from_name` field of the chat-service push payload so the receiver's
  /// ringer banner shows the human-readable label instead of the
  /// chat-device-id fallback. Pass null on legacy paths; receivers fall
  /// back to local contact lookup when absent.
  Future<bool> sendInvite({
    required String callId,
    required String fromDeviceId,
    required String toDeviceId,
    String mode = 'audio',
    String? fromName,
  }) async {
    final trimmedName = fromName?.trim();
    return send({
      'type': 'invite',
      'call_id': callId,
      'from': fromDeviceId,
      'to': toDeviceId,
      'mode': mode,
      if (trimmedName != null && trimmedName.isNotEmpty)
        'from_name': trimmedName,
    });
  }

  /// Convenience: send an answer (accept call).
  Future<bool> sendAnswer({
    required String callId,
    required String fromDeviceId,
    String? toDeviceId,
  }) async {
    return send({
      'type': 'answer',
      'call_id': callId,
      'from': fromDeviceId,
      if (toDeviceId != null && toDeviceId.isNotEmpty) 'to': toDeviceId,
    });
  }

  /// Convenience: send a hangup to end a call.
  Future<bool> sendHangup({
    required String callId,
    required String fromDeviceId,
    String? toDeviceId,
  }) async {
    return send({
      'type': 'hangup',
      'call_id': callId,
      'from': fromDeviceId,
      if (toDeviceId != null && toDeviceId.isNotEmpty) 'to': toDeviceId,
    });
  }

  /// Reads the current deviceId from chat local storage.
  ///
  /// This is a helper so that the VoIP UI can easily bootstrap the
  /// signaling context without duplicating storage logic.
  static Future<String?> loadDeviceId({String? baseUrlOverride}) async {
    try {
      final id = await ChatLocalStore().loadIdentity(
        baseUrlOverride: baseUrlOverride,
      );
      return id?.id;
    } catch (_) {}
    return null;
  }

  void close() {
    _connectGeneration += 1;
    _ws?.sink.close();
    _ws = null;
    unawaited(_eventsCtrl?.close());
    _eventsCtrl = null;
  }
}

@visibleForTesting
bool shamellCallSignalingRequiresBoundSessionCookie(String baseUrl) {
  final uri = shamellTrustedCallSignalingBaseUri(baseUrl);
  if (uri == null) return true;
  return kReleaseMode || !_isCallSignalingLocalhostHost(uri.host);
}

bool shamellCallSignalingEventRequiresReauth(Map<String, dynamic> event) {
  final type = (event['type'] ?? '').toString().trim().toLowerCase();
  if (type != 'error') return false;
  final detail = (event['detail'] ?? event['reason'] ?? '').toString();
  return shamellContainsCriticalAccountSessionDetail(detail);
}

@visibleForTesting
Future<Map<String, String>> shamellCallSignalingHeadersForBaseUrl(
  String baseUrl, {
  required String deviceId,
}) async {
  final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
  final token = (await ChatLocalStore().loadDeviceAuthToken(
        deviceId,
        baseUrlOverride: baseUrl,
      )) ??
      '';
  if (token.trim().isNotEmpty) {
    headers['X-Chat-Device-Id'] = deviceId;
    headers['X-Chat-Device-Token'] = token.trim();
  }
  return headers;
}
