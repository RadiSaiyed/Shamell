import 'dart:convert';

import 'base_url.dart';

const String kMapProvider =
    String.fromEnvironment('MAP_PROVIDER', defaultValue: 'maplibre');
const String kRoutingProvider =
    String.fromEnvironment('ROUTING_PROVIDER', defaultValue: 'tomtom');
const String kMapDisplayProvider =
    String.fromEnvironment('MAP_DISPLAY_PROVIDER', defaultValue: 'tomtom');

const String kOsmTileUrl = String.fromEnvironment(
  'OSM_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const String kOsmStyleUrl = String.fromEnvironment(
  'OSM_STYLE_URL',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);

const String kOsmAttribution = String.fromEnvironment(
  'OSM_ATTRIBUTION',
  defaultValue: '© OpenStreetMap contributors',
);

const String kOsmTrafficTileUrl = String.fromEnvironment(
  'OSM_TRAFFIC_TILE_URL',
  defaultValue: '',
);

const String kTomTomMapLayer = String.fromEnvironment(
  'TOMTOM_MAP_LAYER',
  defaultValue: 'basic',
);
const String kTomTomMapStyle = String.fromEnvironment(
  'TOMTOM_MAP_STYLE',
  defaultValue: 'main',
);
const String kTomTomMapView = String.fromEnvironment(
  'TOMTOM_MAP_VIEW',
  defaultValue: 'Unified',
);
const String kTomTomMapLanguage = String.fromEnvironment(
  'TOMTOM_MAP_LANGUAGE',
  defaultValue: 'en-US',
);
const String kTomTomMapTileSize = String.fromEnvironment(
  'TOMTOM_MAP_TILE_SIZE',
  defaultValue: '256',
);

bool get useOsmMaps => kMapProvider.toLowerCase() == 'osm';
bool get useMapLibreMaps => kMapProvider.toLowerCase() == 'maplibre';
bool get useTomTomRouting => kRoutingProvider.toLowerCase() == 'tomtom';
bool get useTomTomMapDisplayPrimary =>
    kMapDisplayProvider.toLowerCase() == 'tomtom';

String? _normalizedApiOrigin(String baseUrl) {
  final normalized = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (normalized == null || normalized.isEmpty) return null;
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

Uri? buildTomTomMapProbeTileUri(String baseUrl) {
  final origin = _normalizedApiOrigin(baseUrl);
  if (origin == null) return null;
  final layer = _normalizedTomTomMapLayer();
  final style = _normalizedTomTomMapStyle();
  final tileSize = _normalizedTomTomMapTileSize();
  return Uri.parse(
    '$origin/me/rides/map_tiles/0/0/0'
    '?layer=${Uri.encodeQueryComponent(layer)}'
    '&style=${Uri.encodeQueryComponent(style)}'
    '&tileSize=$tileSize'
    '&view=${Uri.encodeQueryComponent(_normalizedTomTomMapView())}'
    '&language=${Uri.encodeQueryComponent(_normalizedTomTomMapLanguage())}',
  );
}

String buildTomTomMapLibreRasterStyleJson(String baseUrl) {
  final uri = buildTomTomMapProbeTileUri(baseUrl);
  if (uri == null) {
    throw StateError('API base URL is invalid.');
  }
  return jsonEncode(<String, Object>{
    'version': 8,
    'name': 'shamell_tomtom_raster',
    'sources': <String, Object>{
      'tomtom_raster': <String, Object>{
        'type': 'raster',
        'tiles': <String>[
          uri.toString().replaceFirst('/0/0/0', '/{z}/{x}/{y}')
        ],
        'tileSize': _normalizedTomTomMapTileSize(),
      },
    },
    'layers': <Object>[
      <String, Object>{
        'id': 'background',
        'type': 'background',
        'paint': <String, Object>{'background-color': '#eef3f8'},
      },
      <String, Object>{
        'id': 'tomtom_raster',
        'type': 'raster',
        'source': 'tomtom_raster',
        'minzoom': 0,
        'maxzoom': 22,
      },
    ],
  });
}

String _normalizedTomTomMapLayer() {
  final trimmed = kTomTomMapLayer.trim().toLowerCase();
  return trimmed.isEmpty ? 'basic' : trimmed;
}

String _normalizedTomTomMapStyle() {
  final trimmed = kTomTomMapStyle.trim().toLowerCase();
  return trimmed.isEmpty ? 'main' : trimmed;
}

String _normalizedTomTomMapView() {
  final trimmed = kTomTomMapView.trim();
  return trimmed.isEmpty ? 'Unified' : trimmed;
}

String _normalizedTomTomMapLanguage() {
  final trimmed = kTomTomMapLanguage.trim();
  return trimmed.isEmpty ? 'en-US' : trimmed;
}

int _normalizedTomTomMapTileSize() {
  final parsed = int.tryParse(kTomTomMapTileSize.trim()) ?? 256;
  return parsed == 512 ? 512 : 256;
}
