import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'base_url_transport_policy.dart';

http.Client createShamellHttpClient({
  required bool releaseMode,
  required List<Uint8List> trustedTlsCertificatesDer,
}) {
  return http.Client();
}

WebSocketChannel connectShamellWebSocket(
  Uri wsUri, {
  required Map<String, String> headers,
  required bool failWithoutHeadersOnIo,
  required bool releaseMode,
  required List<Uint8List> trustedTlsCertificatesDer,
}) {
  final effectiveFailWithoutHeadersOnIo =
      shamellEffectiveFailWithoutHeadersOnIo(
    releaseMode: releaseMode,
    failWithoutHeadersOnIo: failWithoutHeadersOnIo,
  );
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
      if (!shamellShouldRetryWebSocketWithoutHeaders(
        headers: headers,
        failWithoutHeadersOnIo: effectiveFailWithoutHeadersOnIo,
      )) {
        rethrow;
      }
    }
  }
  return WebSocketChannel.connect(wsUri);
}
