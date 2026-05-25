// Cycle 202 — Operator cancellation-reason analytics page.
//
// Polls /me/rides/operator/cancellation-reasons and renders a
// horizontal bar chart of reason buckets over the last 30 days.
// Designed for quick scan: total count up top, then sorted bars
// largest → smallest with both count and percentage labels.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'l10n.dart';
import 'session_cookie_store.dart';

class _CancellationBucket {
  final String reasonCode;
  final int count;
  const _CancellationBucket({required this.reasonCode, required this.count});
}

class _AnalyticsSnapshot {
  final String generatedAt;
  final int windowDays;
  final int totalCancellations;
  final List<_CancellationBucket> buckets;
  const _AnalyticsSnapshot({
    required this.generatedAt,
    required this.windowDays,
    required this.totalCancellations,
    required this.buckets,
  });
}

Future<_AnalyticsSnapshot?> _fetchAnalytics(String baseUrl) async {
  final uri = secureApiChildUri(
    baseUrl: baseUrl,
    pathSegments: const <String>[
      'me',
      'rides',
      'operator',
      'cancellation-reasons',
    ],
  );
  if (uri == null) return null;
  final client = http.Client();
  try {
    final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
    final resp =
        await client.get(uri, headers: headers).timeout(const Duration(seconds: 12));
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = decoded['buckets'];
    final buckets = (raw is List)
        ? raw.whereType<Map<String, dynamic>>().map((m) {
            return _CancellationBucket(
              reasonCode: (m['reason_code'] as String?) ?? '',
              count: (m['count'] is int)
                  ? m['count'] as int
                  : int.tryParse('${m['count'] ?? 0}') ?? 0,
            );
          }).toList()
        : <_CancellationBucket>[];
    return _AnalyticsSnapshot(
      generatedAt: (decoded['generated_at'] as String?) ?? '',
      windowDays: (decoded['window_days'] is int)
          ? decoded['window_days'] as int
          : int.tryParse('${decoded['window_days'] ?? 30}') ?? 30,
      totalCancellations: (decoded['total_cancellations'] is int)
          ? decoded['total_cancellations'] as int
          : int.tryParse('${decoded['total_cancellations'] ?? 0}') ?? 0,
      buckets: buckets,
    );
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

class OperatorCancellationAnalyticsPage extends StatefulWidget {
  final String baseUrl;

  const OperatorCancellationAnalyticsPage({
    required this.baseUrl,
    super.key,
  });

  @override
  State<OperatorCancellationAnalyticsPage> createState() =>
      _OperatorCancellationAnalyticsPageState();
}

class _OperatorCancellationAnalyticsPageState
    extends State<OperatorCancellationAnalyticsPage> {
  _AnalyticsSnapshot? _snapshot;
  bool _loading = true;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 60), (_) {
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
    final s = await _fetchAnalytics(widget.baseUrl);
    if (!mounted) return;
    setState(() {
      _snapshot = s;
      _loading = false;
    });
  }

  String _humanLabel(String code, {required bool isArabic}) {
    switch (code) {
      case 'changed_mind':
        return isArabic ? 'غيّر رأيه' : 'Changed mind';
      case 'driver_taking_too_long':
        return isArabic ? 'السائق متأخر' : 'Driver too slow';
      case 'wrong_pickup':
        return isArabic ? 'موقع التقاط خاطئ' : 'Wrong pickup';
      case 'driver_unprofessional':
        return isArabic ? 'السائق غير مهني' : 'Driver unprofessional';
      case 'price_too_high':
        return isArabic ? 'السعر مرتفع' : 'Price too high';
      case 'rider_no_show':
        return isArabic ? 'الراكب لم يحضر' : 'Rider no-show';
      case 'wrong_address':
        return isArabic ? 'عنوان خاطئ' : 'Wrong address';
      case 'traffic_blocked':
        return isArabic ? 'الطريق مغلق' : 'Traffic blocked';
      case 'rider_uncooperative':
        return isArabic ? 'سلوك الراكب' : 'Rider behavior';
      case 'vehicle_issue':
        return isArabic ? 'مشكلة المركبة' : 'Vehicle issue';
      case 'other':
        return isArabic ? 'سبب آخر' : 'Other';
      case 'unspecified':
        return isArabic ? 'بدون سبب' : 'Unspecified';
      default:
        return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    final s = _snapshot;
    final maxCount =
        s == null || s.buckets.isEmpty ? 1 : s.buckets.first.count.clamp(1, 1 << 30);
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'أسباب الإلغاء' : 'Cancellation reasons'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _refresh(),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: _loading && s == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: <Widget>[
                  Card(
                    color: theme.colorScheme.primary.withValues(alpha: .08),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.bar_chart_rounded,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  isArabic
                                      ? 'إجمالي الإلغاءات (${s?.windowDays ?? 30} يوم)'
                                      : 'Total cancellations (${s?.windowDays ?? 30}d)',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${s?.totalCancellations ?? 0}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (s == null || s.buckets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          isArabic
                              ? 'لا توجد إلغاءات في النافذة الزمنية الحالية.'
                              : 'No cancellations in the current window.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  else
                    ...s.buckets.map((b) {
                      final fraction =
                          (b.count / maxCount).clamp(0.0, 1.0).toDouble();
                      final pct = s.totalCancellations == 0
                          ? 0
                          : (100 * b.count / s.totalCancellations).round();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    _humanLabel(b.reasonCode,
                                        isArabic: isArabic),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  '${b.count} · $pct%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 8,
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}
