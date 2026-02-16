import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'mini_program_runtime.dart';
import 'mini_programs_my_page_insights.dart';
import 'moments_page.dart';
import 'http_error.dart';

Future<Map<String, String>> _hdrMiniPrograms({required String baseUrl}) async {
  final headers = <String, String>{};
  try {
    final cookie = await getSessionCookieHeader(baseUrl) ?? '';
    if (cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
  } catch (_) {}
  return headers;
}

class MyMiniProgramsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final void Function(String modId) onOpenMod;

  const MyMiniProgramsPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.onOpenMod,
  });

  @override
  State<MyMiniProgramsPage> createState() => _MyMiniProgramsPageState();
}

class _MyMiniProgramsPageState extends State<MyMiniProgramsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  int _totalUsage = 0;
  double _avgRating = 0.0;
  int _totalMomentsShares = 0;
  List<Map<String, dynamic>> _topPrograms = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = const <Map<String, dynamic>>[];
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs/developer_json');
      final resp = await http.get(uri,
          headers: await _hdrMiniPrograms(baseUrl: widget.baseUrl));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = sanitizeHttpError(
            statusCode: resp.statusCode,
            rawBody: resp.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['programs'] is List) {
        raw = decoded['programs'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final list = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        list.add(e.cast<String, dynamic>());
      }
      list.sort((a, b) {
        final ua =
            (a['usage_score'] is num) ? (a['usage_score'] as num).toInt() : 0;
        final ub =
            (b['usage_score'] is num) ? (b['usage_score'] as num).toInt() : 0;
        final ra = (a['rating'] is num) ? (a['rating'] as num).toDouble() : 0.0;
        final rb = (b['rating'] is num) ? (b['rating'] as num).toDouble() : 0.0;
        final scoreA = ua + (ra * 10.0);
        final scoreB = ub + (rb * 10.0);
        return scoreB.compareTo(scoreA);
      });
      if (!mounted) return;
      int totalUsage = 0;
      double ratingSum = 0.0;
      int ratingCount = 0;
      int totalMoments = 0;
      final scoreList = <Map<String, dynamic>>[];
      for (final p in list) {
        final u = p['usage_score'];
        if (u is num && u > 0) {
          totalUsage += u.toInt();
        }
        final r = p['rating'];
        if (r is num && r > 0) {
          ratingSum += r.toDouble();
          ratingCount += 1;
        }
        final ms = p['moments_shares'];
        if (ms is num && ms > 0) {
          totalMoments += ms.toInt();
        }
        final usageScore = (u is num) ? u.toInt() : 0;
        final ratingScore = (r is num) ? r.toDouble() : 0.0;
        final momentsScore = (ms is num) ? ms.toInt() : 0;
        final combinedScore =
            (momentsScore * 2) + usageScore + (ratingScore * 10.0);
        final withScore = Map<String, dynamic>.from(p)
          ..['__score'] = combinedScore;
        scoreList.add(withScore);
      }
      scoreList.sort((a, b) {
        final sa =
            (a['__score'] is num) ? (a['__score'] as num).toDouble() : 0.0;
        final sb =
            (b['__score'] is num) ? (b['__score'] as num).toDouble() : 0.0;
        return sb.compareTo(sa);
      });
      final top =
          scoreList.length > 3 ? scoreList.sublist(0, 3) : List.of(scoreList);
      setState(() {
        _items = list;
        _loading = false;
        _totalUsage = totalUsage;
        _avgRating =
            ratingCount > 0 ? (ratingSum / ratingCount.toDouble()) : 0.0;
        _totalMomentsShares = totalMoments;
        _topPrograms = top;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = sanitizeExceptionForUi(error: e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'برامجي المصغّرة' : 'My mini‑programs',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          if (!_loading && _error == null && _items.isNotEmpty)
            _buildInsightsHeader(context),
          if (!_loading && _error == null && _topPrograms.isNotEmpty)
            _buildTopProgramsRow(context),
          Expanded(
            child: _items.isEmpty && !_loading
                ? _buildEmptyState(context)
                : ListView.builder(
                    itemCount: _items.length,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemBuilder: (ctx, i) {
                      final p = _items[i];
                      final appId = (p['app_id'] ?? '').toString();
                      final titleEn = (p['title_en'] ?? '').toString();
                      final titleAr = (p['title_ar'] ?? '').toString();
                      final descEn =
                          (p['description_en'] ?? '').toString().trim();
                      final descAr =
                          (p['description_ar'] ?? '').toString().trim();
                      final status =
                          (p['status'] ?? 'draft').toString().toLowerCase();
                      final reviewStatus =
                          (p['review_status'] ?? 'draft').toString();
                      final scopes = (p['scopes'] is List)
                          ? (p['scopes'] as List)
                              .map((e) => (e ?? '').toString())
                              .where((e) => e.isNotEmpty)
                              .toList()
                          : const <String>[];
                      final usage = (p['usage_score'] is num)
                          ? (p['usage_score'] as num).toInt()
                          : 0;
                      final rating = (p['rating'] is num)
                          ? (p['rating'] as num).toDouble()
                          : 0.0;
                      final lastVersion =
                          (p['last_version'] ?? '').toString().trim();
                      final isArabic = l.isArabic;
                      final title = isArabic && titleAr.isNotEmpty
                          ? titleAr
                          : (titleEn.isNotEmpty ? titleEn : appId);
                      final desc =
                          isArabic && descAr.isNotEmpty ? descAr : descEn;
                      final statusLabel = () {
                        switch (status) {
                          case 'active':
                            return isArabic ? 'نشط' : 'Active';
                          case 'draft':
                            return isArabic ? 'مسودة' : 'Draft';
                          default:
                            return status.isNotEmpty ? status : null;
                        }
                      }();
                      final reviewLower = reviewStatus.toLowerCase();
                      final bool canSubmit =
                          reviewLower == 'draft' || reviewLower == 'rejected';
                      final bool canWithdraw = reviewLower == 'submitted';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: appId.isEmpty
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => MiniProgramPage(
                                          id: appId,
                                          baseUrl: widget.baseUrl,
                                          walletId: widget.walletId,
                                          deviceId: widget.deviceId,
                                          onOpenMod: widget.onOpenMod,
                                        ),
                                      ),
                                    );
                                  },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.widgets_outlined,
                                          size: 24),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyLarge
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (appId.isNotEmpty)
                                              Text(
                                                appId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: .60),
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.insights_outlined,
                                            size: 20),
                                        tooltip: isArabic
                                            ? 'تفاصيل الأداء'
                                            : 'View performance',
                                        onPressed: () =>
                                            _showProgramInsights(p),
                                      ),
                                    ],
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      desc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (statusLabel != null)
                                        _MiniStatusChip(
                                          label: statusLabel,
                                          tone: status == 'active'
                                              ? _MiniStatusTone.success
                                              : _MiniStatusTone.neutral,
                                        ),
                                      _MiniStatusChip(
                                        label: () {
                                          if (isArabic) {
                                            switch (reviewLower) {
                                              case 'submitted':
                                                return 'قيد المراجعة';
                                              case 'approved':
                                                return 'مقبول للنشر';
                                              case 'rejected':
                                                return 'مرفوض';
                                              case 'draft':
                                              default:
                                                return 'غير مرسَل للمراجعة';
                                            }
                                          } else {
                                            switch (reviewLower) {
                                              case 'submitted':
                                                return 'In review';
                                              case 'approved':
                                                return 'Approved';
                                              case 'rejected':
                                                return 'Rejected';
                                              case 'draft':
                                              default:
                                                return 'Not submitted';
                                            }
                                          }
                                        }(),
                                        tone: reviewLower == 'submitted'
                                            ? _MiniStatusTone.info
                                            : (reviewLower == 'approved'
                                                ? _MiniStatusTone.success
                                                : (reviewLower == 'rejected'
                                                    ? _MiniStatusTone.danger
                                                    : _MiniStatusTone.neutral)),
                                      ),
                                      if (lastVersion.isNotEmpty)
                                        _MiniStatusChip(
                                          label: isArabic
                                              ? 'الإصدار $lastVersion'
                                              : 'Version $lastVersion',
                                          tone: _MiniStatusTone.neutral,
                                        ),
                                      if (usage > 0)
                                        _MiniStatusChip(
                                          label: isArabic
                                              ? 'الفتحات $usage'
                                              : 'Opens $usage',
                                          tone: _MiniStatusTone.neutral,
                                        ),
                                      if (rating > 0)
                                        _MiniStatusChip(
                                          label: isArabic
                                              ? '⭐ ${rating.toStringAsFixed(1)}'
                                              : '⭐ ${rating.toStringAsFixed(1)}',
                                          tone: _MiniStatusTone.neutral,
                                        ),
                                    ],
                                  ),
                                  if (scopes.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: scopes.map((s) {
                                        return _MiniStatusChip(
                                          label: s,
                                          tone: _MiniStatusTone.neutral,
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (canSubmit)
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.send_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            isArabic
                                                ? 'إرسال للمراجعة'
                                                : 'Submit for review',
                                          ),
                                          onPressed: appId.isEmpty
                                              ? null
                                              : () => _submitForReview(
                                                  context, appId),
                                        ),
                                      if (canWithdraw)
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.undo_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            isArabic
                                                ? 'سحب من المراجعة'
                                                : 'Withdraw review',
                                          ),
                                          onPressed: () =>
                                              _showWithdrawInfo(context),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsHeader(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final avgRatingText = _avgRating > 0 ? _avgRating.toStringAsFixed(1) : '–';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAr ? 'نظرة عامة على الأداء' : 'Performance insights',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              MiniProgramInsightChip(
                icon: Icons.play_circle_outline,
                label: isAr ? 'إجمالي الفتحات' : 'Total opens',
                value: _totalUsage > 0
                    ? _totalUsage.toString()
                    : (isAr ? 'لا بيانات' : 'No data'),
              ),
              MiniProgramInsightChip(
                icon: Icons.star_rate_rounded,
                label: isAr ? 'متوسط التقييم' : 'Avg rating',
                value: avgRatingText,
              ),
              MiniProgramInsightChip(
                icon: Icons.photo_outlined,
                label: isAr ? 'مشاركات في اللحظات' : 'Moments shares',
                value: _totalMomentsShares > 0
                    ? _totalMomentsShares.toString()
                    : (isAr ? 'لا بيانات' : 'No data'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.widgets_outlined,
              size: 40,
              color: theme.colorScheme.onSurface.withValues(alpha: .45),
            ),
            const SizedBox(height: 8),
            Text(
              l.isArabic
                  ? 'لم تقم بعد بتسجيل أي برنامج مصغّر.'
                  : 'You have not registered any mini‑programs yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .75),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.isArabic
                  ? 'استخدم خيار "تسجيل برنامج مصغر" في تبويب "أنا/Me" لبدء التسجيل، أو افتح صفحة المطور لمزيد من التفاصيل.'
                  : 'Use the "Register mini‑program" entry in the Me tab to get started, or open the developer page for more details.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProgramsRow(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAr ? 'أفضل برامجي المصغّرة' : 'Top mini‑programs',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _topPrograms.map((p) {
              final appId = (p['app_id'] ?? '').toString();
              final titleEn = (p['title_en'] ?? '').toString();
              final titleAr = (p['title_ar'] ?? '').toString();
              final usage = (p['usage_score'] is num)
                  ? (p['usage_score'] as num).toInt()
                  : 0;
              final rating =
                  (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
              final moments = (p['moments_shares'] is num)
                  ? (p['moments_shares'] as num).toInt()
                  : 0;
              final title = isAr && titleAr.isNotEmpty
                  ? titleAr
                  : (titleEn.isNotEmpty ? titleEn : appId);
              final buffer = StringBuffer();
              if (usage > 0) {
                buffer.write(
                  isAr ? 'فتح $usage' : 'Opens $usage',
                );
              }
              if (rating > 0) {
                if (buffer.isNotEmpty) buffer.write(' · ');
                buffer.write(isAr
                    ? 'تقييم ${rating.toStringAsFixed(1)}'
                    : 'Rating ${rating.toStringAsFixed(1)}');
              }
              if (moments > 0) {
                if (buffer.isNotEmpty) buffer.write(' · ');
                buffer.write(isAr ? 'لحظات $moments' : 'Moments $moments');
              }
              final meta = buffer.isNotEmpty ? buffer.toString() : null;
              return ActionChip(
                avatar: const Icon(Icons.widgets_outlined, size: 16),
                label: Text(
                  meta == null ? title : '$title · $meta',
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => _showProgramInsights(p),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _showProgramInsights(Map<String, dynamic> p) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final appId = (p['app_id'] ?? '').toString();
    final titleEn = (p['title_en'] ?? '').toString();
    final titleAr = (p['title_ar'] ?? '').toString();
    final descEn = (p['description_en'] ?? '').toString().trim();
    final descAr = (p['description_ar'] ?? '').toString().trim();
    final status = (p['status'] ?? 'draft').toString();
    final reviewStatus = (p['review_status'] ?? 'draft').toString();
    final usage =
        (p['usage_score'] is num) ? (p['usage_score'] as num).toInt() : 0;
    final rating = (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
    final momentsShares =
        (p['moments_shares'] is num) ? (p['moments_shares'] as num).toInt() : 0;
    final momentsShares30 = (p['moments_shares_30d'] is num)
        ? (p['moments_shares_30d'] as num).toInt()
        : 0;
    final lastVersion = (p['last_version'] ?? '').toString().trim();
    final createdAt = (p['created_at'] ?? '').toString();
    final updatedAt = (p['updated_at'] ?? '').toString();
    final title = isAr && titleAr.isNotEmpty
        ? titleAr
        : (titleEn.isNotEmpty ? titleEn : appId);
    final desc = isAr && descAr.isNotEmpty ? descAr : descEn;
    final avgRatingText = rating > 0
        ? rating.toStringAsFixed(1)
        : (isAr ? 'لا بيانات' : 'No data');
    var slug = appId.toLowerCase().trim();
    slug = slug.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final topicTag = slug.isNotEmpty ? '#mp_$slug' : '#ShamellMiniApp';
    int statsSharesTotal = 0;
    int statsShares30d = 0;
    int statsUniqueTotal = 0;
    int statsUnique30d = 0;
    int statsActiveDays30d = 0;
    int statsPeakSharesDay30d = 0;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(appId)}/moments_stats',
      );
      final resp = await http.get(
        uri,
        headers: await _hdrMiniPrograms(baseUrl: widget.baseUrl),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          final m = decoded.cast<String, dynamic>();
          final totalRaw = m['shares_total'];
          final total30Raw = m['shares_30d'];
          final uniqRaw = m['unique_sharers_total'];
          final uniq30Raw = m['unique_sharers_30d'];
          final seriesRaw = m['series_30d'];
          if (totalRaw is num) statsSharesTotal = totalRaw.toInt();
          if (total30Raw is num) statsShares30d = total30Raw.toInt();
          if (uniqRaw is num) statsUniqueTotal = uniqRaw.toInt();
          if (uniq30Raw is num) statsUnique30d = uniq30Raw.toInt();
          if (seriesRaw is List) {
            int activeDays = 0;
            int peak = 0;
            for (final e in seriesRaw) {
              if (e is! Map) continue;
              final mm = e.cast<String, dynamic>();
              final v = mm['shares'];
              final val = v is num ? v.toInt() : 0;
              if (val > 0) {
                activeDays += 1;
                if (val > peak) peak = val;
              }
            }
            statsActiveDays30d = activeDays;
            statsPeakSharesDay30d = peak;
          }
        }
      }
    } catch (_) {}
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            borderRadius: BorderRadius.circular(12),
            color: theme.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.widgets_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (appId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        appId,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    ),
                  if (desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        desc,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      MiniProgramInsightChip(
                        icon: Icons.play_circle_outline,
                        label: isAr ? 'إجمالي الفتحات' : 'Total opens',
                        value: usage > 0
                            ? usage.toString()
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.star_rate_rounded,
                        label: isAr ? 'التقييم' : 'Rating',
                        value: avgRatingText,
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.photo_outlined,
                        label: isAr ? 'مشاركات في اللحظات' : 'Moments shares',
                        value: momentsShares > 0
                            ? momentsShares.toString()
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.photo_library_outlined,
                        label: isAr
                            ? 'لحظات (آخر ٣٠ يوماً)'
                            : 'Moments (last 30 days)',
                        value: momentsShares30 > 0
                            ? momentsShares30.toString()
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                    ],
                  ),
                  if (statsSharesTotal > 0 ||
                      statsShares30d > 0 ||
                      statsUniqueTotal > 0 ||
                      statsUnique30d > 0) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (statsUniqueTotal > 0 || statsUnique30d > 0)
                          MiniProgramInsightChip(
                            icon: Icons.group_outlined,
                            label:
                                isAr ? 'المستخدمون الفريدون' : 'Unique sharers',
                            value: statsUniqueTotal > 0
                                ? (isAr
                                    ? '$statsUniqueTotal (٣٠ي: $statsUnique30d)'
                                    : '$statsUniqueTotal (30d: $statsUnique30d)')
                                : (isAr ? 'لا بيانات' : 'No data'),
                          ),
                        if (statsSharesTotal > 0 || statsShares30d > 0)
                          MiniProgramInsightChip(
                            icon: Icons.show_chart_outlined,
                            label: isAr
                                ? 'مشاركات اللحظات (إجمالي/٣٠ي)'
                                : 'Moments shares (total/30d)',
                            value: statsSharesTotal > 0
                                ? (isAr
                                    ? '$statsSharesTotal / $statsShares30d'
                                    : '$statsSharesTotal / $statsShares30d')
                                : (isAr ? 'لا بيانات' : 'No data'),
                          ),
                        if (statsActiveDays30d > 0)
                          MiniProgramInsightChip(
                            icon: Icons.calendar_today_outlined,
                            label: isAr
                                ? 'أيام نشطة (٣٠ يوماً)'
                                : 'Active days (30d)',
                            value: statsActiveDays30d.toString(),
                          ),
                        if (statsPeakSharesDay30d > 0)
                          MiniProgramInsightChip(
                            icon: Icons.trending_up_outlined,
                            label: isAr
                                ? 'أعلى مشاركات في يوم'
                                : 'Peak shares/day',
                            value: statsPeakSharesDay30d.toString(),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    isAr ? 'الحالة' : 'Status',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAr
                        ? 'الحالة: $status · المراجعة: $reviewStatus'
                        : 'Status: $status · Review: $reviewStatus',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  if (lastVersion.isNotEmpty ||
                      createdAt.isNotEmpty ||
                      updatedAt.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      isAr ? 'الإصدارات والتواريخ' : 'Versions & dates',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (lastVersion.isNotEmpty)
                      Text(
                        isAr
                            ? 'آخر إصدار: $lastVersion'
                            : 'Last version: $lastVersion',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (createdAt.isNotEmpty)
                      Text(
                        isAr ? 'أُنشئ: $createdAt' : 'Created: $createdAt',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    if (updatedAt.isNotEmpty)
                      Text(
                        isAr ? 'آخر تحديث: $updatedAt' : 'Updated: $updatedAt',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    isAr ? 'الإدارة' : 'Management',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.system_update_alt_outlined,
                            size: 18),
                        label: Text(
                          isAr
                              ? 'إرسال إصدار جديد للمراجعة'
                              : 'Submit new version for review',
                        ),
                        onPressed: appId.isEmpty
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                _openVersionSelfRegister(appId);
                              },
                      ),
                      TextButton.icon(
                        icon:
                            const Icon(Icons.photo_library_outlined, size: 18),
                        label: Text(
                          isAr
                              ? 'عرض اللحظات لهذا البرنامج'
                              : 'View Moments for this mini‑program',
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MomentsPage(
                                baseUrl: widget.baseUrl,
                                topicTag: topicTag,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isAr ? 'أدوات المطور' : 'Developer tools',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        icon:
                            const Icon(Icons.photo_library_outlined, size: 18),
                        label: Text(
                          isAr
                              ? 'عرض اللحظات لهذا البرنامج'
                              : 'View Moments for this mini‑program',
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MomentsPage(
                                baseUrl: widget.baseUrl,
                                topicTag: topicTag,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isAr
                        ? 'الأرقام تقريبية وتعكس الفتحات والتقييمات ومشاركات Mini‑Program في اللحظات، مع إبراز آخر ٣٠ يوماً كما في تحليلات Shamell. استخدم الوسوم مثل #ShamellMiniApp و #mp_<app_id> لبناء مواضيع خاصة ببرنامجك المصغّر.'
                        : 'Numbers are approximate and reflect opens, ratings and Mini‑Program links shared in Moments, with an emphasis on the last 30 days similar to Shamell analytics. Use hashtags like #ShamellMiniApp and #mp_<app_id> to build Mini‑program topic feeds for your app.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openVersionSelfRegister(String appId) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final versionCtrl = TextEditingController();
    final bundleCtrl = TextEditingController();
    final changelogEnCtrl = TextEditingController();
    final changelogArCtrl = TextEditingController();
    bool submitting = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: bottom + 12,
          ),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (ctx2, setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.system_update_alt_outlined,
                            size: 20,
                            color:
                                theme.colorScheme.primary.withValues(alpha: .9),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isAr
                                  ? 'إرسال إصدار جديد للبرنامج المصغّر'
                                  : 'Submit new Mini‑program version',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: versionCtrl,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'رقم الإصدار (مثال: 1.0.0)'
                              : 'Version (e.g. 1.0.0)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bundleCtrl,
                        decoration: InputDecoration(
                          labelText:
                              isAr ? 'رابط الحزمة (Bundle URL)' : 'Bundle URL',
                          helperText: isAr
                              ? 'رابط قابل للوصول لحزمة Mini‑Program (مثل ملف ZIP).'
                              : 'Publicly reachable URL for the Mini‑program bundle (e.g. ZIP file).',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: changelogEnCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'ملاحظات الإصدار (إنجليزي، اختياري)'
                              : 'Changelog (English, optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: changelogArCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'ملاحظات الإصدار (عربي، اختياري)'
                              : 'Changelog (Arabic, optional)',
                        ),
                      ),
                      if (error != null && error!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(ctx).pop(),
                            child: Text(isAr ? 'إلغاء' : 'Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: submitting
                                ? null
                                : () async {
                                    final version = versionCtrl.text.trim();
                                    final bundleUrl = bundleCtrl.text.trim();
                                    if (version.isEmpty || bundleUrl.isEmpty) {
                                      setModalState(() {
                                        error = isAr
                                            ? 'رقم الإصدار ورابط الحزمة مطلوبان.'
                                            : 'Version and bundle URL are required.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final uri = Uri.parse(
                                        '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(appId)}/versions/self_register',
                                      );
                                      final payload = <String, Object?>{
                                        'version': version,
                                        'bundle_url': bundleUrl,
                                        'changelog_en':
                                            changelogEnCtrl.text.trim().isEmpty
                                                ? null
                                                : changelogEnCtrl.text.trim(),
                                        'changelog_ar':
                                            changelogArCtrl.text.trim().isEmpty
                                                ? null
                                                : changelogArCtrl.text.trim(),
                                      };
                                      final resp = await http.post(
                                        uri,
                                        headers: await _hdrMiniPrograms(
                                          baseUrl: widget.baseUrl,
                                        ),
                                        body: jsonEncode(payload),
                                      );
                                      if (resp.statusCode < 200 ||
                                          resp.statusCode >= 300) {
                                        final msg = sanitizeHttpError(
                                          statusCode: resp.statusCode,
                                          rawBody: resp.body,
                                          isArabic: isAr,
                                        );
                                        setModalState(() {
                                          submitting = false;
                                          error = msg;
                                        });
                                        return;
                                      }
                                      if (!mounted) return;
                                      Navigator.of(ctx).pop();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            isAr
                                                ? 'تم تسجيل الإصدار الجديد للمراجعة.'
                                                : 'New version registered for review.',
                                          ),
                                        ),
                                      );
                                      // Refresh overall stats so last_version can update.
                                      // ignore: discarded_futures
                                      _load();
                                    } catch (e) {
                                      setModalState(() {
                                        submitting = false;
                                        error = sanitizeExceptionForUi(error: e);
                                      });
                                    }
                                  },
                            icon: submitting
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check),
                            label: Text(
                              isAr ? 'إرسال' : 'Submit',
                            ),
                          ),
                          if (appId.isNotEmpty)
                            TextButton.icon(
                              icon:
                                  const Icon(Icons.verified_outlined, size: 18),
                              label: Text(
                                isAr
                                    ? 'إرسال التطبيق نفسه للمراجعة'
                                    : 'Submit app for review',
                              ),
                              onPressed: () async {
                                try {
                                  final uri = Uri.parse(
                                    '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(appId)}/submit_review',
                                  );
                                  final resp = await http.post(
                                    uri,
                                    headers: await _hdrMiniPrograms(
                                      baseUrl: widget.baseUrl,
                                    ),
                                  );
                                  if (resp.statusCode < 200 ||
                                      resp.statusCode >= 300) {
                                    final msg = sanitizeHttpError(
                                      statusCode: resp.statusCode,
                                      rawBody: resp.body,
                                      isArabic: isAr,
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(msg),
                                      ),
                                    );
                                    return;
                                  }
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        isAr
                                            ? 'تم إرسال البرنامج للمراجعة. يمكن لفريق Shamell مراجعته وتفعيله.'
                                            : 'Mini‑program submitted for review. The Shamell team can now review and activate it.',
                                      ),
                                    ),
                                  );
                                  // Reload so we see updated review_status.
                                  // ignore: discarded_futures
                                  _load();
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        sanitizeExceptionForUi(
                                          error: e,
                                          isArabic: isAr,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitForReview(BuildContext context, String appId) async {
    final l = L10n.of(context);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(appId)}/submit_review',
      );
      final resp = await http.post(
        uri,
        headers: await _hdrMiniPrograms(baseUrl: widget.baseUrl),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final msg = sanitizeHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: l.isArabic,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تم إرسال التطبيق للمراجعة.'
                : 'Mini‑program submitted for review.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sanitizeExceptionForUi(error: e, isArabic: l.isArabic),
          ),
        ),
      );
    }
  }

  void _showWithdrawInfo(BuildContext context) {
    final l = L10n.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            l.isArabic ? 'سحب طلب المراجعة' : 'Withdraw review request',
          ),
          content: Text(
            l.isArabic
                ? 'لسحب طلب المراجعة، يرجى التواصل مع فريق Shamell أو تعديل حالة التطبيق من مركز المراجعة الإداري.'
                : 'To withdraw a review request, please contact the Shamell team or adjust the status from the admin review center.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.isArabic ? 'حسناً' : 'OK'),
            ),
          ],
        );
      },
    );
  }
}

enum _MiniStatusTone { neutral, success, info, danger }

class _MiniStatusChip extends StatelessWidget {
  final String label;
  final _MiniStatusTone tone;

  const _MiniStatusChip({
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    switch (tone) {
      case _MiniStatusTone.success:
        bg = Colors.green.withValues(alpha: .10);
        fg = Colors.green.shade700;
        break;
      case _MiniStatusTone.info:
        bg = theme.colorScheme.primary.withValues(alpha: .08);
        fg = theme.colorScheme.primary.withValues(alpha: .90);
        break;
      case _MiniStatusTone.danger:
        bg = Colors.red.withValues(alpha: .08);
        fg = Colors.red.shade700;
        break;
      case _MiniStatusTone.neutral:
      default:
        bg = theme.colorScheme.surface.withValues(alpha: .06);
        fg = theme.colorScheme.onSurface.withValues(alpha: .80);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
