import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shamell_flutter/core/shamell_photo_viewer_page.dart';

void main() {
  test('photo viewer source policy rejects non-local plaintext urls in release',
      () {
    expect(
      normalizeShamellPhotoViewerSourceForRuntime(
        'http://cdn.shamell.test/a.jpg',
        releaseMode: true,
      ),
      isNull,
    );
    expect(
      normalizeShamellPhotoViewerSourceForRuntime(
        'http://127.0.0.1:8080/a.jpg',
        releaseMode: true,
      ),
      'http://127.0.0.1:8080/a.jpg',
    );
    expect(
      normalizeShamellPhotoViewerSourceForRuntime(
        'https://cdn.shamell.test/a.jpg',
        releaseMode: true,
      ),
      'https://cdn.shamell.test/a.jpg',
    );
  });

  test('photo viewer source policy rejects credentialed and malformed urls',
      () {
    expect(
      normalizeShamellPhotoViewerSourceForRuntime(
        'https://user:pass@cdn.shamell.test/a.jpg',
        releaseMode: false,
      ),
      isNull,
    );
    expect(
      normalizeShamellPhotoViewerSourceForRuntime(
        'https://',
        releaseMode: false,
      ),
      isNull,
    );
  });

  test('photo viewer source policy preserves data uris and raw inline payloads',
      () {
    expect(
      normalizeShamellPhotoViewerSourceForRuntime(
        'data:image/png;base64,AAAA',
        releaseMode: true,
      ),
      'data:image/png;base64,AAAA',
    );
    expect(
      normalizeShamellPhotoViewerSourceForRuntime(
        'QUJDRA==',
        releaseMode: true,
      ),
      'QUJDRA==',
    );
  });

  test('photo viewer uses pinned transport only for same-origin remote media',
      () {
    expect(
      shamellPhotoViewerUsesPinnedTransport(
        source: 'https://api.shamell.online/media/a.jpg',
        baseUrl: 'https://api.shamell.online',
      ),
      isTrue,
    );
    expect(
      shamellPhotoViewerUsesPinnedTransport(
        source: 'https://cdn.shamell.online/media/a.jpg',
        baseUrl: 'https://api.shamell.online',
      ),
      isFalse,
    );
    expect(
      shamellPhotoViewerUsesPinnedTransport(
        source: 'data:image/png;base64,AAAA',
        baseUrl: 'https://api.shamell.online',
      ),
      isFalse,
    );
  });

  test('photo viewer fetch helper routes same-origin media through pinned path',
      () async {
    final calls = <String>[];
    final response = await shamellPhotoViewerFetchRemoteSourceResponse(
      source: 'https://api.shamell.online/media/a.jpg',
      baseUrl: 'https://api.shamell.online',
      releaseMode: true,
      pinnedGet: (uri) async {
        calls.add('pinned:${uri.toString()}');
        return http.Response.bytes(utf8.encode('a'), 200);
      },
      remoteGet: (uri) async {
        calls.add('remote:${uri.toString()}');
        return http.Response.bytes(utf8.encode('b'), 200);
      },
      timeout: const Duration(seconds: 1),
    );

    expect(response.bodyBytes, utf8.encode('a'));
    expect(
      calls,
      <String>['pinned:https://api.shamell.online/media/a.jpg'],
    );
  });

  test(
      'photo viewer fetch helper keeps non-first-party media off pinned path in debug',
      () async {
    final calls = <String>[];
    final response = await shamellPhotoViewerFetchRemoteSourceResponse(
      source: 'https://cdn.shamell.online/media/a.jpg',
      baseUrl: 'https://api.shamell.online',
      releaseMode: false,
      pinnedGet: (uri) async {
        calls.add('pinned:${uri.toString()}');
        return http.Response.bytes(utf8.encode('a'), 200);
      },
      remoteGet: (uri) async {
        calls.add('remote:${uri.toString()}');
        return http.Response.bytes(utf8.encode('b'), 200);
      },
      timeout: const Duration(seconds: 1),
    );

    expect(response.bodyBytes, utf8.encode('b'));
    expect(
      calls,
      <String>['remote:https://cdn.shamell.online/media/a.jpg'],
    );
  });

  test('photo viewer fetch helper blocks non-first-party media in release',
      () async {
    final calls = <String>[];

    await expectLater(
      () => shamellPhotoViewerFetchRemoteSourceResponse(
        source: 'https://cdn.shamell.online/media/a.jpg',
        baseUrl: 'https://api.shamell.online',
        releaseMode: true,
        pinnedGet: (uri) async {
          calls.add('pinned:${uri.toString()}');
          return http.Response.bytes(utf8.encode('a'), 200);
        },
        remoteGet: (uri) async {
          calls.add('remote:${uri.toString()}');
          return http.Response.bytes(utf8.encode('b'), 200);
        },
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<StateError>()),
    );

    expect(calls, isEmpty);
  });

  test('photo viewer direct save is disabled on Android 9 and lower', () {
    expect(
      shamellPhotoViewerSupportsDirectSaveToGallery(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        androidSdkInt: 28,
      ),
      isFalse,
    );
    expect(
      shamellPhotoViewerSupportsDirectSaveToGallery(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        androidSdkInt: null,
      ),
      isFalse,
    );
  });

  test('photo viewer direct save stays enabled on Android 10+ and non-android',
      () {
    expect(
      shamellPhotoViewerSupportsDirectSaveToGallery(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        androidSdkInt: 29,
      ),
      isTrue,
    );
    expect(
      shamellPhotoViewerSupportsDirectSaveToGallery(
        isWeb: false,
        targetPlatform: TargetPlatform.iOS,
        androidSdkInt: null,
      ),
      isTrue,
    );
    expect(
      shamellPhotoViewerSupportsDirectSaveToGallery(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
        androidSdkInt: 34,
      ),
      isFalse,
    );
  });
}
