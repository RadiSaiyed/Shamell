// Cycle 213 — Driver demand heatmap client.
//
// Pairs with the BFF endpoint:
//   GET /me/rides/demand-heatmap
//
// Returns aggregated pickup density for the last 30 minutes,
// snapped to ~500 m grid cells (0.005° on each side). The driver
// + operator surfaces overlay this onto their map.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class DemandHeatmapCell {
  final double lat;
  final double lon;
  final int count;

  const DemandHeatmapCell({
    required this.lat,
    required this.lon,
    required this.count,
  });

  factory DemandHeatmapCell.fromJson(Map<String, dynamic> json) {
    return DemandHeatmapCell(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      count: (json['count'] is int)
          ? json['count'] as int
          : int.tryParse('${json['count'] ?? 0}') ?? 0,
    );
  }
}

class DemandHeatmap {
  final String generatedAt;
  final int windowSeconds;
  final double cellSizeDegrees;
  final int maxCount;
  final List<DemandHeatmapCell> cells;

  const DemandHeatmap({
    required this.generatedAt,
    required this.windowSeconds,
    required this.cellSizeDegrees,
    required this.maxCount,
    required this.cells,
  });

  bool get isEmpty => cells.isEmpty;

  factory DemandHeatmap.fromJson(Map<String, dynamic> json) {
    final raw = json['cells'];
    final cells = (raw is List)
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(DemandHeatmapCell.fromJson)
            .toList(growable: false)
        : const <DemandHeatmapCell>[];
    return DemandHeatmap(
      generatedAt: (json['generated_at'] as String?) ?? '',
      windowSeconds: (json['window_seconds'] is int)
          ? json['window_seconds'] as int
          : int.tryParse('${json['window_seconds'] ?? 0}') ?? 0,
      cellSizeDegrees: (json['cell_size_degrees'] as num?)?.toDouble() ?? 0.005,
      maxCount: (json['max_count'] is int)
          ? json['max_count'] as int
          : int.tryParse('${json['max_count'] ?? 0}') ?? 0,
      cells: cells,
    );
  }
}

class DemandHeatmapApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client? _httpClient;

  const DemandHeatmapApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Fetch the heatmap. Returns null on auth / network failure;
  /// caller treats null as "no overlay this tick".
  Future<DemandHeatmap?> fetch() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'demand-heatmap'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return DemandHeatmap.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }
}
