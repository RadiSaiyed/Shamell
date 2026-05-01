import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  /// Connects to the signaling WebSocket for the given deviceId.
  ///
  /// The backend is expected to expose `/ws/call/signaling` and route
  /// events between participants based on `device_id`.
  Stream<Map<String, dynamic>> connect({required String deviceId}) {
    _eventsCtrl?.close();
    _eventsCtrl = StreamController<Map<String, dynamic>>.broadcast();
    final u = Uri.parse(_base);
    final wsUri = Uri(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: '/ws/call/signaling',
      queryParameters: {'device_id': deviceId},
    );
    _ws = WebSocketChannel.connect(wsUri);
    _ws!.stream.listen((payload) {
      try {
        final j = jsonDecode(payload);
        if (j is Map<String, dynamic>) {
          _eventsCtrl?.add(j);
        }
      } catch (_) {}
    }, onError: (_) {
      _eventsCtrl?.add({'type': 'error'});
    }, onDone: () {
      _eventsCtrl?.add({'type': 'closed'});
    });
    return _eventsCtrl!.stream;
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
  }) async {
    await send({
      'type': 'answer',
      'call_id': callId,
      'from': fromDeviceId,
    });
  }

  /// Convenience: send a hangup to end a call.
  Future<void> sendHangup({
    required String callId,
    required String fromDeviceId,
  }) async {
    await send({
      'type': 'hangup',
      'call_id': callId,
      'from': fromDeviceId,
    });
  }

  /// Reads the current deviceId from chat local storage.
  ///
  /// This is a helper so that the VoIP UI can easily bootstrap the
  /// signaling context without duplicating storage logic.
  static Future<String?> loadDeviceId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('chat.identity');
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is Map && j['id'] is String) {
        return j['id'] as String;
      }
    } catch (_) {}
    return null;
  }

  void close() {
    _ws?.sink.close();
    _ws = null;
    _eventsCtrl?.close();
    _eventsCtrl = null;
  }
}
