// Cycle 214-215 — Driver + operator demand heatmap page.
//
// Self-contained surface that loads the BFF heatmap and renders
// a CustomPainter heat overlay on top of a simplified geographic
// canvas. We intentionally avoid wiring into the existing live
// map: the page is a quick "where is demand right now" glance,
// not a navigation tool. A follow-up cycle can layer this onto
// the live map widget once the integration cost is justified.
//
// The painter normalizes counts against `maxCount` so the hottest
// cell always renders at full intensity. Cells render as soft
// radial blobs (~500m radius) coloured from cool (low) to hot
// (high) for instant visual scanning.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'demand_heatmap_api.dart';
import 'l10n.dart';

class DemandHeatmapPage extends StatefulWidget {
  final String baseUrl;
  final bool isOperator;

  const DemandHeatmapPage({
    required this.baseUrl,
    this.isOperator = false,
    super.key,
  });

  @override
  State<DemandHeatmapPage> createState() => _DemandHeatmapPageState();
}

class _DemandHeatmapPageState extends State<DemandHeatmapPage> {
  late final DemandHeatmapApi _api;
  DemandHeatmap? _snapshot;
  bool _loading = true;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _api = DemandHeatmapApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final s = await _api.fetch();
    if (!mounted) return;
    setState(() {
      _snapshot = s;
      _loading = false;
    });
  }

  /// Bounding box across all cells. Empty snapshot → Damascus default.
  ({double minLat, double maxLat, double minLon, double maxLon}) _bbox() {
    final cells = _snapshot?.cells ?? const <DemandHeatmapCell>[];
    if (cells.isEmpty) {
      // Damascus default view.
      return (
        minLat: 33.45,
        maxLat: 33.60,
        minLon: 36.20,
        maxLon: 36.40,
      );
    }
    double minLat = cells.first.lat;
    double maxLat = cells.first.lat;
    double minLon = cells.first.lon;
    double maxLon = cells.first.lon;
    for (final c in cells) {
      if (c.lat < minLat) minLat = c.lat;
      if (c.lat > maxLat) maxLat = c.lat;
      if (c.lon < minLon) minLon = c.lon;
      if (c.lon > maxLon) maxLon = c.lon;
    }
    // Add 5% padding so blobs don't clip the edges.
    final padLat = math.max((maxLat - minLat) * .08, 0.01);
    final padLon = math.max((maxLon - minLon) * .08, 0.01);
    return (
      minLat: minLat - padLat,
      maxLat: maxLat + padLat,
      minLon: minLon - padLon,
      maxLon: maxLon + padLon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final s = _snapshot;
    final freshness = s == null
        ? '—'
        : 'updated ${_fmtAge(s.generatedAt)}';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'خريطة الطلب الحية' : 'Live demand heatmap',
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _refresh(),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Header strip with totals + window info.
          Container(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.local_fire_department_rounded,
                    color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isArabic
                            ? 'الطلب في آخر 30 دقيقة'
                            : 'Pickups in the last 30 min',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text(
                        s == null
                            ? (isArabic ? 'جاري التحميل…' : 'Loading…')
                            : (isArabic
                                ? '${s.cells.length} منطقة • أعلى كثافة ${s.maxCount} • $freshness'
                                : '${s.cells.length} cells • peak ${s.maxCount} • $freshness'),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && s == null
                ? const Center(child: CircularProgressIndicator())
                : (s == null || s.cells.isEmpty)
                    ? _emptyState(isArabic: isArabic)
                    : LayoutBuilder(builder: (ctx, constraints) {
                        final bbox = _bbox();
                        return Container(
                          color: const Color(0xFFEEEFF1),
                          child: CustomPaint(
                            size: Size(constraints.maxWidth,
                                constraints.maxHeight),
                            painter: _HeatmapPainter(
                              cells: s.cells,
                              maxCount: s.maxCount,
                              minLat: bbox.minLat,
                              maxLat: bbox.maxLat,
                              minLon: bbox.minLon,
                              maxLon: bbox.maxLon,
                            ),
                          ),
                        );
                      }),
          ),
          // Bottom legend.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                Text(isArabic ? 'منخفض' : 'Low',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[
                          Color(0xFF42A5F5),
                          Color(0xFFFFEB3B),
                          Color(0xFFFF7043),
                          Color(0xFFD32F2F),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(isArabic ? 'مرتفع' : 'High',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({required bool isArabic}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.search_rounded,
                size: 48, color: Colors.black38),
            const SizedBox(height: 12),
            Text(
              isArabic
                  ? 'لا توجد طلبات في آخر 30 دقيقة.'
                  : 'No pickups in the last 30 minutes.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtAge(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final delta = DateTime.now().toUtc().difference(parsed.toUtc());
    if (delta.inSeconds < 5) return 'just now';
    if (delta.inSeconds < 60) return '${delta.inSeconds}s ago';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    return '${delta.inHours}h ago';
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<DemandHeatmapCell> cells;
  final int maxCount;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  _HeatmapPainter({
    required this.cells,
    required this.maxCount,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  Offset _project(Size size, double lat, double lon) {
    final dx = (lon - minLon) / (maxLon - minLon);
    // Latitude axis is inverted in screen-space (north up).
    final dy = 1 - (lat - minLat) / (maxLat - minLat);
    return Offset(dx * size.width, dy * size.height);
  }

  Color _heatColor(double t) {
    // Smooth cool→hot interpolation across 4 control colors.
    const stops = <Color>[
      Color(0xFF42A5F5),
      Color(0xFFFFEB3B),
      Color(0xFFFF7043),
      Color(0xFFD32F2F),
    ];
    final clamped = t.clamp(0.0, 1.0);
    final segment = clamped * (stops.length - 1);
    final i = segment.floor().clamp(0, stops.length - 2);
    final f = segment - i;
    return Color.lerp(stops[i], stops[i + 1], f)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle grid background so the empty space doesn't feel like
    // a void.
    final gridPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: .05)
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      final x = size.width * (i / 10);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      final y = size.height * (i / 10);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (maxCount == 0) return;

    // Estimate cell radius in pixels: half a cell width.
    final cellWidthPx =
        size.width * (0.005 / math.max((maxLon - minLon), 0.001));
    final baseRadius = math.max(cellWidthPx * 0.8, 14.0);

    for (final c in cells) {
      final t = (c.count / maxCount).clamp(0.0, 1.0);
      final color = _heatColor(t);
      final center = _project(size, c.lat, c.lon);
      // Larger + more opaque for hotter cells.
      final radius = baseRadius * (0.7 + 0.6 * t);
      final shader = ui_radial(
        center: center,
        radius: radius,
        colors: <Color>[
          color.withValues(alpha: .85),
          color.withValues(alpha: 0),
        ],
      );
      final paint = Paint()..shader = shader;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      cells.length != old.cells.length ||
      maxCount != old.maxCount ||
      minLat != old.minLat ||
      maxLat != old.maxLat ||
      minLon != old.minLon ||
      maxLon != old.maxLon;
}

/// Wrap a radial gradient as a Shader. Kept in a helper so the
/// painter body stays readable.
Shader ui_radial({
  required Offset center,
  required double radius,
  required List<Color> colors,
}) {
  return RadialGradient(colors: colors).createShader(
    Rect.fromCircle(center: center, radius: radius),
  );
}
