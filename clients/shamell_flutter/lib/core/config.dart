const String kMapProvider = String.fromEnvironment('MAP_PROVIDER', defaultValue: 'osm');
const String kRoutingProvider = String.fromEnvironment('ROUTING_PROVIDER', defaultValue: 'google');
const String kPushProvider = String.fromEnvironment('PUSH_PROVIDER', defaultValue: 'fcm');

const String kOsmTileUrl = String.fromEnvironment(
  'OSM_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const String kOsmStyleUrl = String.fromEnvironment(
  'OSM_STYLE_URL',
  defaultValue: '',
);

const String kOsmAttribution = String.fromEnvironment(
  'OSM_ATTRIBUTION',
  defaultValue: '© OpenStreetMap contributors',
);

const String kOsmTrafficTileUrl = String.fromEnvironment(
  'OSM_TRAFFIC_TILE_URL',
  defaultValue: '',
);

/// Optional TomTom Map Display API key for client-side tiles (web/mobile).
/// Passed at build time via:
///   --dart-define=TOMTOM_MAP_KEY=...
const String kTomTomMapKey = String.fromEnvironment(
  'TOMTOM_MAP_KEY',
  defaultValue: '',
);

bool get useOsmMaps => kMapProvider.toLowerCase() == 'osm';

const String kGotifyBaseUrl = String.fromEnvironment('GOTIFY_BASE_URL', defaultValue: '');
const String kGotifyClientToken = String.fromEnvironment('GOTIFY_CLIENT_TOKEN', defaultValue: '');
