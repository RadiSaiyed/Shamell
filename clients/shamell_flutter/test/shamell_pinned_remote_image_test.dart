import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shamell_flutter/core/shamell_pinned_remote_image.dart';

void main() {
  test('pinned remote image helper fetches bytes through provided client',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      expect(
          request.url.toString(), 'https://api.example.com/media/avatar.png');
      return http.Response.bytes(utf8.encode('image-bytes'), 200);
    });

    final bytes = await shamellPinnedRemoteImageBytes(
      'https://api.example.com/media/avatar.png',
      clientFactory: () => client,
    );

    expect(calls, 1);
    expect(bytes, isNotNull);
    expect(utf8.decode(bytes!), 'image-bytes');
  });

  test('pinned remote image helper fails closed on non-success status',
      () async {
    final client = MockClient((request) async {
      return http.Response('nope', 404);
    });

    final bytes = await shamellPinnedRemoteImageBytes(
      'https://api.example.com/media/avatar.png',
      clientFactory: () => client,
    );

    expect(bytes, isNull);
  });

  test('pinned remote image helper rejects insecure remote plaintext http URLs',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response.bytes(utf8.encode('image-bytes'), 200);
    });

    final bytes = await shamellPinnedRemoteImageBytes(
      'http://evil.example/media/avatar.png',
      clientFactory: () => client,
    );

    expect(bytes, isNull);
    expect(calls, 0);
  });

  test('pinned remote image helper rejects oversized payloads early', () async {
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode('x'),
        200,
        headers: const {
          'content-length': '5000000',
          'content-type': 'image/png',
        },
      );
    });

    final bytes = await shamellPinnedRemoteImageBytes(
      'https://api.example.com/media/avatar.png',
      clientFactory: () => client,
    );

    expect(bytes, isNull);
  });

  test('pinned remote image helper rejects non-image content types', () async {
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode('<html>not an image</html>'),
        200,
        headers: const {'content-type': 'text/html; charset=utf-8'},
      );
    });

    final bytes = await shamellPinnedRemoteImageBytes(
      'https://api.example.com/media/avatar.png',
      clientFactory: () => client,
    );

    expect(bytes, isNull);
  });
}
