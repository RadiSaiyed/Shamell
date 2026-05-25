import 'dart:typed_data';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'base_url_transport_policy.dart';

http.Client createShamellHttpClient({
  required bool releaseMode,
  required List<Uint8List> trustedTlsCertificatesDer,
}) {
  final client = BrowserClient()..withCredentials = true;
  return client;
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
  if (headers.isNotEmpty &&
      !shamellShouldRetryWebSocketWithoutHeaders(
        headers: headers,
        failWithoutHeadersOnIo: effectiveFailWithoutHeadersOnIo,
      )) {
    throw UnsupportedError(
      'Browser websocket connections cannot attach custom headers.',
    );
  }
  return WebSocketChannel.connect(wsUri);
}
