import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'base_url.dart' show isLocalhostHost, shamellHttpClient;

typedef ShamellPinnedRemoteImageClientFactory = http.Client Function();

final Map<String, Future<Uint8List?>> _shamellPinnedRemoteImageCache =
    <String, Future<Uint8List?>>{};
const int _shamellPinnedRemoteImageMaxBytes = 4 * 1024 * 1024;
const int _shamellPinnedRemoteImageMaxRedirects = 3;

@visibleForTesting
bool shamellPinnedRemoteImageAllowsUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return false;
  if (uri.host.trim().isEmpty) return false;
  if (uri.userInfo.isNotEmpty) return false;
  if (scheme == 'http' && !isLocalhostHost(uri.host)) {
    return false;
  }
  return true;
}

@visibleForTesting
bool shamellPinnedRemoteImageAllowsContentType(String? rawContentType) {
  final normalized = (rawContentType ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return true;
  final mediaType = normalized.split(';').first.trim();
  return mediaType.startsWith('image/');
}

@visibleForTesting
Future<Uint8List?> shamellPinnedRemoteImageBytes(
  String imageUrl, {
  Duration timeout = const Duration(seconds: 15),
  ShamellPinnedRemoteImageClientFactory? clientFactory,
}) {
  final normalized = imageUrl.trim();
  if (normalized.isEmpty) {
    return Future<Uint8List?>.value(null);
  }
  if (clientFactory != null) {
    return _fetchShamellPinnedRemoteImageBytes(
      normalized,
      timeout: timeout,
      clientFactory: clientFactory,
    );
  }
  return _shamellPinnedRemoteImageCache.putIfAbsent(
    normalized,
    () => _fetchShamellPinnedRemoteImageBytes(
      normalized,
      timeout: timeout,
    ),
  );
}

Future<Uint8List?> _fetchShamellPinnedRemoteImageBytes(
  String imageUrl, {
  required Duration timeout,
  ShamellPinnedRemoteImageClientFactory? clientFactory,
}) async {
  final uri = Uri.tryParse(imageUrl);
  if (uri == null) return null;
  if (!shamellPinnedRemoteImageAllowsUri(uri)) return null;
  final client = (clientFactory ?? shamellHttpClient)();
  try {
    final response = await _sendPinnedImageRequestWithValidatedRedirects(
      client: client,
      initialUri: uri,
      timeout: timeout,
    );
    if (response == null) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain();
      return null;
    }
    if (!shamellPinnedRemoteImageAllowsContentType(
      response.headers['content-type'],
    )) {
      await response.stream.drain();
      return null;
    }
    final advertisedLength = int.tryParse(
      (response.headers['content-length'] ?? '').trim(),
    );
    if (advertisedLength != null &&
        (advertisedLength <= 0 ||
            advertisedLength > _shamellPinnedRemoteImageMaxBytes)) {
      await response.stream.drain();
      return null;
    }
    final bodyBytes = await _readBoundedBytes(
      response.stream,
      maxBytes: _shamellPinnedRemoteImageMaxBytes,
    );
    if (bodyBytes == null || bodyBytes.isEmpty) return null;
    return bodyBytes;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<http.StreamedResponse?> _sendPinnedImageRequestWithValidatedRedirects({
  required http.Client client,
  required Uri initialUri,
  required Duration timeout,
}) async {
  var current = initialUri;
  for (var redirectCount = 0;
      redirectCount <= _shamellPinnedRemoteImageMaxRedirects;
      redirectCount++) {
    final request = http.Request('GET', current)
      ..followRedirects = false
      ..maxRedirects = 0;
    final response = await client.send(request).timeout(timeout);
    if (!_isRedirectStatus(response.statusCode)) {
      return response;
    }
    final location = (response.headers['location'] ?? '').trim();
    await response.stream.drain();
    if (location.isEmpty ||
        redirectCount == _shamellPinnedRemoteImageMaxRedirects) {
      return null;
    }
    final next = Uri.tryParse(location);
    if (next == null) {
      return null;
    }
    final resolved = current.resolveUri(next);
    if (!shamellPinnedRemoteImageAllowsUri(resolved)) {
      return null;
    }
    current = resolved;
  }
  return null;
}

bool _isRedirectStatus(int statusCode) =>
    statusCode == 301 ||
    statusCode == 302 ||
    statusCode == 303 ||
    statusCode == 307 ||
    statusCode == 308;

Future<Uint8List?> _readBoundedBytes(
  Stream<List<int>> stream, {
  required int maxBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in stream) {
    total += chunk.length;
    if (total > maxBytes) {
      return null;
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

class ShamellPinnedRemoteImage extends StatelessWidget {
  final String imageUrl;
  final Widget fallback;
  final BoxFit fit;
  final Duration timeout;
  final ShamellPinnedRemoteImageClientFactory? clientFactory;

  const ShamellPinnedRemoteImage({
    super.key,
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.timeout = const Duration(seconds: 15),
    this.clientFactory,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: shamellPinnedRemoteImageBytes(
        imageUrl,
        timeout: timeout,
        clientFactory: clientFactory,
      ),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return fallback;
        }
        return Image.memory(
          bytes,
          fit: fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}
