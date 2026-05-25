import 'dart:convert';
import 'dart:io';

import 'base_url.dart';
import 'chat/chat_service.dart';
import 'session_cookie_store.dart';

class LiveKitCallToken {
  final String token;
  final String url;
  final String room;
  final String identity;
  final int expiresAtUnix;

  const LiveKitCallToken({
    required this.token,
    required this.url,
    required this.room,
    required this.identity,
    required this.expiresAtUnix,
  });

  Duration get remaining {
    final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final delta = expiresAtUnix - nowSecs;
    if (delta <= 0) return Duration.zero;
    return Duration(seconds: delta);
  }
}

class LiveKitCallException implements Exception {
  final int statusCode;
  final String message;
  const LiveKitCallException(this.statusCode, this.message);

  @override
  String toString() => 'LiveKitCallException($statusCode): $message';
}

/// Thin client for the BFF endpoint `POST /calls/livekit/token`.
///
/// Returns a short-lived HS256 JWT plus the LiveKit server URL clients pass
/// to `Room.connect(...)`. The token is per-room: caller and callee both
/// call this with the same `callId` to join the same LiveKit room.
class LiveKitCallService {
  LiveKitCallService(String baseUrl)
      : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  final String _base;

  /// Request a LiveKit access token for [callId]. `mode` is informational
  /// (audio/video) — actual track publication is decided by the client.
  Future<LiveKitCallToken> requestToken({
    required String callId,
    String mode = 'video',
    String? chatDeviceId,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: _base,
      pathSegments: const ['calls', 'livekit', 'token'],
    );
    if (uri == null) {
      throw const LiveKitCallException(0, 'invalid base url');
    }
    final body = jsonEncode(<String, Object?>{
      'call_id': callId,
      'mode': mode,
    });
    final cookie = await getSessionCookieHeader(_base);
    final chatToken = (chatDeviceId == null || chatDeviceId.isEmpty)
        ? null
        : await ChatLocalStore().loadDeviceAuthToken(
            chatDeviceId,
            baseUrlOverride: _base,
          );

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (cookie != null && cookie.isNotEmpty) {
        req.headers.set('Cookie', cookie);
      }
      if (chatDeviceId != null && chatDeviceId.isNotEmpty) {
        req.headers.set('x-chat-device-id', chatDeviceId);
        if (chatToken != null && chatToken.isNotEmpty) {
          req.headers.set('x-chat-device-token', chatToken);
        }
      }
      req.add(utf8.encode(body));
      final response = await req.close();
      final bodyBytes = <int>[];
      await for (final chunk in response) {
        bodyBytes.addAll(chunk);
      }
      final responseBody = utf8.decode(bodyBytes, allowMalformed: true);
      if (response.statusCode != 200) {
        throw LiveKitCallException(response.statusCode, responseBody);
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        throw const LiveKitCallException(200, 'malformed token response');
      }
      final token = (decoded['token'] ?? '').toString();
      final url = (decoded['url'] ?? '').toString();
      final room = (decoded['room'] ?? '').toString();
      final identity = (decoded['identity'] ?? '').toString();
      final expiresAtUnix =
          (decoded['expires_at_unix'] as num?)?.toInt() ?? 0;
      if (token.isEmpty || url.isEmpty || room.isEmpty || identity.isEmpty) {
        throw const LiveKitCallException(200, 'missing token field');
      }
      return LiveKitCallToken(
        token: token,
        url: url,
        room: room,
        identity: identity,
        expiresAtUnix: expiresAtUnix,
      );
    } finally {
      client.close(force: true);
    }
  }
}
