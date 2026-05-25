import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'base_url_transport_policy.dart';

const String _missingReleaseTlsPinsMessage =
    'TRUSTED_TLS_CERTIFICATES_DER_BASE64 must be set for release mobile builds';

SecurityContext _buildPinnedSecurityContext(
  List<Uint8List> trustedTlsCertificatesDer,
) {
  final context = SecurityContext(withTrustedRoots: false);
  context.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
  for (final certificateDer in trustedTlsCertificatesDer) {
    context.setTrustedCertificatesBytes(_certificateBytesAsPem(certificateDer));
  }
  return context;
}

bool _looksLikePem(Uint8List certificateBytes) {
  if (certificateBytes.isEmpty) return false;
  final prefixLength =
      certificateBytes.length > 48 ? 48 : certificateBytes.length;
  final prefix = utf8.decode(
    certificateBytes.sublist(0, prefixLength),
    allowMalformed: true,
  );
  return prefix.contains('-----BEGIN CERTIFICATE-----');
}

Uint8List _certificateBytesAsPem(Uint8List certificateBytes) {
  if (_looksLikePem(certificateBytes)) {
    return certificateBytes;
  }
  final encoded = base64Encode(certificateBytes);
  final buffer = StringBuffer('-----BEGIN CERTIFICATE-----\n');
  for (var i = 0; i < encoded.length; i += 64) {
    final end = (i + 64 < encoded.length) ? i + 64 : encoded.length;
    buffer.writeln(encoded.substring(i, end));
  }
  buffer.write('-----END CERTIFICATE-----\n');
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

HttpClient _buildHttpClient({
  required bool releaseMode,
  required List<Uint8List> trustedTlsCertificatesDer,
}) {
  if (releaseMode && trustedTlsCertificatesDer.isEmpty) {
    throw StateError(_missingReleaseTlsPinsMessage);
  }
  final httpClient = releaseMode
      ? HttpClient(
          context: _buildPinnedSecurityContext(trustedTlsCertificatesDer),
        )
      : HttpClient();
  httpClient.connectionTimeout = const Duration(seconds: 15);
  httpClient.idleTimeout = const Duration(seconds: 15);
  httpClient.maxConnectionsPerHost = 8;
  httpClient.badCertificateCallback = (_, __, ___) => false;
  return httpClient;
}

http.Client createShamellHttpClient({
  required bool releaseMode,
  required List<Uint8List> trustedTlsCertificatesDer,
}) {
  return IOClient(
    _buildHttpClient(
      releaseMode: releaseMode,
      trustedTlsCertificatesDer: trustedTlsCertificatesDer,
    ),
  );
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
  final client = _buildHttpClient(
    releaseMode: releaseMode,
    trustedTlsCertificatesDer: trustedTlsCertificatesDer,
  );
  try {
    return IOWebSocketChannel.connect(
      wsUri,
      headers: headers.isEmpty ? null : headers,
      connectTimeout: const Duration(seconds: 15),
      customClient: client,
    );
  } catch (_) {
    client.close(force: true);
    if (shamellShouldRetryWebSocketWithoutHeaders(
      headers: headers,
      failWithoutHeadersOnIo: effectiveFailWithoutHeadersOnIo,
    )) {
      return IOWebSocketChannel.connect(
        wsUri,
        connectTimeout: const Duration(seconds: 15),
        customClient: _buildHttpClient(
          releaseMode: releaseMode,
          trustedTlsCertificatesDer: trustedTlsCertificatesDer,
        ),
      );
    }
    rethrow;
  }
}
