import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'chat/chat_service.dart';
import 'session_cookie_store.dart';

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

  bool _isLocalhostHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  /// Connects to the signaling WebSocket for the given deviceId.
  ///
  /// The backend is expected to expose `/ws/call/signaling` and route
  /// events between participants based on `device_id`.
  Stream<Map<String, dynamic>> connect({required String deviceId}) {
    _connectGeneration += 1;
    final generation = _connectGeneration;
    _ws?.sink.close();
    _ws = null;
    unawaited(_eventsCtrl?.close());
    _eventsCtrl = StreamController<Map<String, dynamic>>.broadcast();
    unawaited(_connectInternal(
      deviceId: deviceId.trim(),
      generation: generation,
    ));
    return _eventsCtrl!.stream;
  }

  Future<void> _connectInternal({
    required String deviceId,
    required int generation,
  }) async {
    if (deviceId.isEmpty) {
      _emit({'type': 'error', 'reason': 'missing_device_id'});
      return;
    }
    try {
      final u = Uri.parse(_base);
      final scheme = u.scheme.toLowerCase();
      final host = u.host.toLowerCase();
      // Best practice: do not connect over plaintext transports to non-local hosts.
      if (scheme != 'https' && !(scheme == 'http' && _isLocalhostHost(host))) {
        _emit({'type': 'error', 'reason': 'insecure_transport'});
        return;
      }
      final wsUri = Uri(
        scheme: scheme == 'https' ? 'wss' : 'ws',
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: '/ws/call/signaling',
        queryParameters: {'device_id': deviceId},
      );

      final headers = await _wsHeaders(deviceId);
      if (generation != _connectGeneration) return;

      final ws = _connectWebSocket(wsUri, headers: headers);
      if (generation != _connectGeneration) {
        try {
          ws.sink.close();
        } catch (_) {}
        return;
      }
      _ws = ws;
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
        },
        onDone: () {
          if (generation != _connectGeneration) return;
          _emit({'type': 'closed'});
        },
      );
    } catch (_) {
      _emit({'type': 'error'});
    }
  }

  Future<Map<String, String>> _wsHeaders(String deviceId) async {
    final headers = <String, String>{};
    final cookie = await getSessionCookieHeader(_base);
    if (cookie != null && cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
    final token = (await ChatLocalStore().loadDeviceAuthToken(deviceId)) ?? '';
    if (token.trim().isNotEmpty) {
      headers['X-Chat-Device-Id'] = deviceId;
      headers['X-Chat-Device-Token'] = token.trim();
    }
    return headers;
  }

  WebSocketChannel _connectWebSocket(
    Uri wsUri, {
    required Map<String, String> headers,
  }) {
    if (headers.isNotEmpty) {
      try {
        final dynamic connector = WebSocketChannel.connect;
        final dynamic ch = Function.apply(
          connector,
          <Object?>[wsUri],
          <Symbol, Object?>{#headers: headers},
        );
        if (ch is WebSocketChannel) {
          return ch;
        }
      } catch (_) {
        // On non-web platforms we expect explicit header support; fail closed
        // instead of silently retrying without auth/session headers.
        if (!kIsWeb) rethrow;
      }
    }
    return WebSocketChannel.connect(wsUri);
  }

  void _emit(Map<String, dynamic> event) {
    final ctrl = _eventsCtrl;
    if (ctrl == null || ctrl.isClosed) return;
    try {
      ctrl.add(event);
    } catch (_) {}
  }

  /// Sends a raw signaling message (e.g. invite, answer, hangup, webrtc_offer).
  Future<void> send(Map<String, Object?> msg) async {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  /// Convenience: send an invite to start a call.
  Future<void> sendInvite({
    required String callId,
    required String fromDeviceId,
    required String toDeviceId,
    String mode = 'audio',
  }) async {
    await send({
      'type': 'invite',
      'call_id': callId,
      'from': fromDeviceId,
      'to': toDeviceId,
      'mode': mode,
    });
  }

  /// Convenience: send an answer (accept call).
  Future<void> sendAnswer({
    required String callId,
    required String fromDeviceId,
    String? toDeviceId,
  }) async {
    await send({
      'type': 'answer',
      'call_id': callId,
      'from': fromDeviceId,
      if (toDeviceId != null && toDeviceId.isNotEmpty) 'to': toDeviceId,
    });
  }

  /// Convenience: send a hangup to end a call.
  Future<void> sendHangup({
    required String callId,
    required String fromDeviceId,
    String? toDeviceId,
  }) async {
    await send({
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
  static Future<String?> loadDeviceId() async {
    try {
      final id = await ChatLocalStore().loadIdentity();
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
