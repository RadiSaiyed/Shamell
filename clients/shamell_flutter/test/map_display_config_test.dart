import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/config.dart';

void main() {
  test('buildTomTomMapProbeTileUri builds BFF tile proxy URL without secrets',
      () {
    final uri = buildTomTomMapProbeTileUri('https://api.shamell.online');
    expect(uri, isNotNull);
    expect(uri!.scheme, 'https');
    expect(uri.host, 'api.shamell.online');
    expect(uri.path, '/me/rides/map_tiles/0/0/0');
    expect(uri.queryParameters['layer'], 'basic');
    expect(uri.queryParameters['style'], 'main');
    expect(uri.queryParameters['tileSize'], '256');
    expect(uri.queryParameters['view'], 'Unified');
    expect(uri.queryParameters['language'], 'en-US');
    expect(uri.queryParameters.containsKey('key'), isFalse);
  });

  test('buildTomTomMapLibreRasterStyleJson emits maplibre raster style payload',
      () {
    final styleJson =
        buildTomTomMapLibreRasterStyleJson('https://api.shamell.online');
    final decoded = jsonDecode(styleJson);
    expect(decoded, isA<Map<String, Object?>>());

    final style = decoded as Map<String, Object?>;
    expect(style['version'], 8);

    final sources = style['sources'] as Map<String, Object?>;
    final source = sources['tomtom_raster'] as Map<String, Object?>;
    expect(source['type'], 'raster');
    expect(source['tileSize'], 256);

    final tiles = source['tiles'] as List<Object?>;
    expect(tiles, hasLength(1));
    final tileTemplate = tiles.first! as String;
    expect(tileTemplate, contains('/me/rides/map_tiles/{z}/{x}/{y}'));
    final tileUri = Uri.parse(tileTemplate);
    expect(tileUri.queryParameters['layer'], 'basic');
    expect(tileUri.queryParameters['style'], 'main');
    expect(tileUri.queryParameters.containsKey('key'), isFalse);
  });
}
