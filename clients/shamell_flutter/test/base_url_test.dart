import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/base_url_transport_policy.dart';

void main() {
  test('isSecureApiBaseUrl allows https and local-network http in dev', () {
    expect(isSecureApiBaseUrl('https://api.shamell.online'), isTrue);
    expect(isSecureApiBaseUrl('http://localhost:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://127.0.0.1:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://192.168.1.10:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://10.0.0.10:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://172.20.1.7:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://devbox.local:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://api.shamell.online'), isFalse);
    expect(isSecureApiBaseUrl('api.shamell.online'), isFalse);
    expect(isSecureApiBaseUrl(''), isFalse);
  });

  test(
      'normalizeSecureApiBaseUrl rejects credentials, paths, query, and fragment',
      () {
    expect(
      normalizeSecureApiBaseUrl('https://user:pass@api.shamell.online'),
      isNull,
    );
    expect(
      normalizeSecureApiBaseUrl('https://api.shamell.online/v1'),
      isNull,
    );
    expect(
      normalizeSecureApiBaseUrl('https://api.shamell.online?env=dev'),
      isNull,
    );
    expect(
      normalizeSecureApiBaseUrl('https://api.shamell.online#frag'),
      isNull,
    );
  });

  test('normalizeSecureApiBaseUrl canonicalizes root origins', () {
    expect(
      normalizeSecureApiBaseUrl('https://api.shamell.online/'),
      'https://api.shamell.online',
    );
    expect(
      normalizeSecureApiBaseUrl('http://localhost:8080/'),
      'http://localhost:8080',
    );
  });

  test('normalizeSecureApiBaseUrl rejects invalid explicit ports', () {
    expect(
      normalizeSecureApiBaseUrl('https://api.shamell.online:0'),
      isNull,
    );
    expect(
      normalizeSecureApiBaseUrl('https://api.shamell.online:65536'),
      isNull,
    );
  });

  test('release mode rejects untrusted https origins', () {
    expect(
      normalizeSecureApiBaseUrlForRuntime(
        'https://api.shamell.online',
        releaseMode: true,
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      'https://api.shamell.online',
    );
    expect(
      normalizeSecureApiBaseUrlForRuntime(
        'https://evil.example',
        releaseMode: true,
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      isNull,
    );
  });

  test('release mode accepts explicitly trusted https origins', () {
    expect(
      normalizeSecureApiBaseUrlForRuntime(
        'https://api.two.example',
        releaseMode: true,
        trustedOriginsRaw: 'https://api.one.example, https://api.two.example',
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      'https://api.two.example',
    );
  });

  test('release mode rejects localhost http by default', () {
    expect(
      normalizeSecureApiBaseUrlForRuntime(
        'http://127.0.0.1:8080',
        releaseMode: true,
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      isNull,
    );
  });

  test('release mode allows localhost http only with explicit opt-in', () {
    expect(
      normalizeSecureApiBaseUrlForRuntime(
        'http://127.0.0.1:8080',
        releaseMode: true,
        fallbackBaseUrl: 'https://api.shamell.online',
        allowLocalhostHttpInRelease: true,
      ),
      'http://127.0.0.1:8080',
    );
  });

  test('trusted release origin list falls back to secure BASE_URL origin', () {
    final origins = shamellTrustedApiOriginsForRelease(
      trustedOriginsRaw: 'http://127.0.0.1:8080, https://api.one.example',
      fallbackBaseUrl: 'https://api.shamell.online',
    );
    expect(origins, contains('https://api.one.example'));
    expect(origins, contains('https://api.shamell.online'));
    expect(origins.any((origin) => origin.startsWith('http://')), isFalse);
  });

  test('release TLS certificate bundle parser decodes semicolon-separated DER',
      () {
    final certs = shamellTrustedTlsCertificatesDerForRuntime(
      trustedTlsCertificatesDerBase64: '${base64Encode(const <int>[
            1,
            2,
            3
          ])};${base64Encode(const <int>[4, 5])}',
    );
    expect(certs, hasLength(2));
    expect(certs[0], orderedEquals(const <int>[1, 2, 3]));
    expect(certs[1], orderedEquals(const <int>[4, 5]));
  });

  test('release TLS certificate bundle parser rejects invalid base64', () {
    expect(
      () => shamellTrustedTlsCertificatesDerForRuntime(
        trustedTlsCertificatesDerBase64: '!!!not-base64!!!',
      ),
      throwsFormatException,
    );
  });

  test('release mobile http client fails closed without pinned TLS bundle', () {
    expect(
      () => shamellHttpClient(
        releaseModeOverride: true,
        trustedTlsCertificatesDerBase64: '',
      ),
      throwsStateError,
    );
  });

  test('release mobile websocket client fails closed without pinned TLS bundle',
      () {
    expect(
      () => shamellConnectWebSocket(
        Uri.parse('wss://api.shamell.online/ws'),
        releaseModeOverride: true,
        trustedTlsCertificatesDerBase64: '',
      ),
      throwsStateError,
    );
  });

  test('websocket header retry policy defaults to fail-closed', () {
    expect(
      shamellShouldRetryWebSocketWithoutHeaders(
        headers: const <String, String>{'cookie': '__Host-sa_session=deadbeef'},
        failWithoutHeadersOnIo: true,
      ),
      isFalse,
    );
    expect(
      shamellShouldRetryWebSocketWithoutHeaders(
        headers: const <String, String>{'cookie': '__Host-sa_session=deadbeef'},
        failWithoutHeadersOnIo: false,
      ),
      isTrue,
    );
    expect(
      shamellShouldRetryWebSocketWithoutHeaders(
        headers: const <String, String>{},
        failWithoutHeadersOnIo: false,
      ),
      isFalse,
    );
  });

  test(
      'release mode forces websocket header retry policy to fail-closed even when opted out',
      () {
    final effectiveFailWithoutHeadersOnIo =
        shamellEffectiveFailWithoutHeadersOnIo(
      releaseMode: true,
      failWithoutHeadersOnIo: false,
    );
    expect(effectiveFailWithoutHeadersOnIo, isTrue);
    expect(
      shamellShouldRetryWebSocketWithoutHeaders(
        headers: const <String, String>{'cookie': '__Host-sa_session=deadbeef'},
        failWithoutHeadersOnIo: effectiveFailWithoutHeadersOnIo,
      ),
      isFalse,
    );
  });

  test('non-release mode preserves explicit websocket header fallback opt-in',
      () {
    final effectiveFailWithoutHeadersOnIo =
        shamellEffectiveFailWithoutHeadersOnIo(
      releaseMode: false,
      failWithoutHeadersOnIo: false,
    );
    expect(effectiveFailWithoutHeadersOnIo, isFalse);
    expect(
      shamellShouldRetryWebSocketWithoutHeaders(
        headers: const <String, String>{'cookie': '__Host-sa_session=deadbeef'},
        failWithoutHeadersOnIo: effectiveFailWithoutHeadersOnIo,
      ),
      isTrue,
    );
  });

  test('secureApiChildUri builds canonical child endpoints', () {
    expect(
      secureApiChildUri(
        baseUrl: 'https://api.shamell.online/',
        pathSegments: const ['auth', 'devices', 'device/1'],
      ).toString(),
      'https://api.shamell.online/auth/devices/device%2F1',
    );
    expect(
      secureApiChildUri(
        baseUrl: 'http://127.0.0.1:8080',
        pathSegments: const ['auth', 'logout'],
      ).toString(),
      'http://127.0.0.1:8080/auth/logout',
    );
  });

  test('secureApiChildUri rejects malformed bases and empty segments', () {
    expect(
      secureApiChildUri(
        baseUrl: 'https://user:pass@api.shamell.online',
        pathSegments: const ['auth', 'devices'],
      ),
      isNull,
    );
    expect(
      secureApiChildUri(
        baseUrl: 'https://api.shamell.online/app',
        pathSegments: const ['auth', 'devices'],
      ),
      isNull,
    );
    expect(
      secureApiChildUri(
        baseUrl: 'https://api.shamell.online',
        pathSegments: const ['auth', ' '],
      ),
      isNull,
    );
  });

  test('preferredConfiguredApiBaseUrl preserves canonical stored origins', () {
    expect(
      preferredConfiguredApiBaseUrl(
        storedBaseUrl: 'https://api.example.com',
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      'https://api.example.com',
    );
  });

  test(
      'preferredConfiguredApiBaseUrl preserves localhost in non-release builds',
      () {
    expect(
      preferredConfiguredApiBaseUrl(
        storedBaseUrl: 'http://127.0.0.1:8080',
        fallbackBaseUrl: 'https://api.shamell.online',
        releaseMode: false,
      ),
      'http://127.0.0.1:8080',
    );
  });

  test(
      'preferredConfiguredApiBaseUrl prefers fallback over localhost in release builds',
      () {
    expect(
      preferredConfiguredApiBaseUrl(
        storedBaseUrl: 'http://127.0.0.1:8080',
        fallbackBaseUrl: 'https://api.shamell.online',
        releaseMode: true,
      ),
      'https://api.shamell.online',
    );
  });

  test('preferredConfiguredApiBaseUrl uses fallback for invalid stored values',
      () {
    expect(
      preferredConfiguredApiBaseUrl(
        storedBaseUrl: 'https://user:pass@api.example.com/root',
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      'https://api.shamell.online',
    );
  });

  test('configuredApiBaseUrlOrFallbackIfUnset falls back only when unset', () {
    expect(
      configuredApiBaseUrlOrFallbackIfUnset(
        storedBaseUrl: '',
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      'https://api.shamell.online',
    );
    expect(
      configuredApiBaseUrlOrFallbackIfUnset(
        storedBaseUrl: 'https://api.example.com',
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      'https://api.example.com',
    );
    expect(
      configuredApiBaseUrlOrFallbackIfUnset(
        storedBaseUrl: 'https://user:pass@api.example.com/root',
        fallbackBaseUrl: 'https://api.shamell.online',
      ),
      isNull,
    );
  });
}
