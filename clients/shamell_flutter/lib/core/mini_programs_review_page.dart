import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'safe_set_state.dart';

class MiniProgramsReviewPage extends StatefulWidget {
  final String baseUrl;

  const MiniProgramsReviewPage({super.key, required this.baseUrl});

  @override
  State<MiniProgramsReviewPage> createState() => _MiniProgramsReviewPageState();
}

class _MiniProgramsReviewPageState extends State<MiniProgramsReviewPage>
    with SafeSetStateMixin<MiniProgramsReviewPage> {
  static const Duration _miniProgramsReviewRequestTimeout =
      Duration(seconds: 15);
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _programs = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _hdr() async {
    final headers = <String, String>{};
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) {
        headers['cookie'] = cookie;
      }
    } catch (_) {}
    return headers;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs');
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_miniProgramsReviewRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() {
          _error = 'HTTP ${r.statusCode}';
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      final list = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['programs'] is List) {
        for (final e in decoded['programs'] as List) {
          if (e is Map) {
            list.add(e.cast<String, dynamic>());
          }
        }
      }
      setState(() {
        _programs = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
        _loading = false;
      });
    }
  }

  Future<void> _updateReviewStatus(
    String appId, {
    String? status,
    String? reviewStatus,
  }) async {
    if (appId.isEmpty) return;
    final l = L10n.of(context);
    try {
      final uri = Uri.parse('${widget.baseUrl}/admin/mini_programs/$appId');
      final body = <String, dynamic>{};
      if (status != null) body['status'] = status;
      if (reviewStatus != null) body['review_status'] = reviewStatus;
      final r = await http
          .patch(
            uri,
            headers: {
              ...(await _hdr()),
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_miniProgramsReviewRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        final msg = sanitizeHttpError(
          statusCode: r.statusCode,
          rawBody: r.body,
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
            l.isArabic ? 'تم تحديث حالة المراجعة.' : 'Review status updated.',
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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      );
    } else if (_programs.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l.isArabic
                ? 'لا توجد برامج مصغّرة مسجلة بعد.'
                : 'No mini‑programs registered yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
        ),
      );
    } else {
      final submitted = <Map<String, dynamic>>[];
      final others = <Map<String, dynamic>>[];
      for (final p in _programs) {
        final review = (p['review_status'] ?? 'draft').toString().toLowerCase();
        if (review == 'submitted') {
          submitted.add(p);
        } else {
          others.add(p);
        }
      }
      Widget buildList(List<Map<String, dynamic>> items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.isArabic ? 'لا توجد عناصر.' : 'No items.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: items.length,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          itemBuilder: (ctx, i) {
            final p = items[i];
            final appId = (p['app_id'] ?? '').toString();
            final titleEn = (p['title_en'] ?? '').toString();
            final titleAr = (p['title_ar'] ?? '').toString();
            final ownerName = (p['owner_name'] ?? '').toString();
            final ownerContact = (p['owner_contact'] ?? '').toString();
            final status = (p['status'] ?? '').toString();
            final review = (p['review_status'] ?? 'draft').toString();
            final usageRaw = p['usage_score'];
            final usage = usageRaw is num ? usageRaw.toInt() : 0;
            final ratingRaw = p['rating'];
            final rating = ratingRaw is num ? ratingRaw.toDouble() : 0.0;
            final title = l.isArabic && titleAr.isNotEmpty
                ? titleAr
                : (titleEn.isNotEmpty ? titleEn : appId);
            final reviewLower = review.toLowerCase();
            final isSubmitted = reviewLower == 'submitted';
            final isApproved = reviewLower == 'approved';
            final canApprove = isSubmitted;
            final canReject = isSubmitted || isApproved;
            final canSuspend = isSubmitted || isApproved;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.widgets_outlined, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (appId.isNotEmpty)
                                  Text(
                                    appId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: .60),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (ownerName.isNotEmpty || ownerContact.isNotEmpty) ...[
                        Text(
                          ownerName.isNotEmpty
                              ? (l.isArabic
                                  ? 'المالك: $ownerName'
                                  : 'Owner: $ownerName')
                              : ownerContact,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .75),
                          ),
                        ),
                        if (ownerContact.isNotEmpty && ownerName.isNotEmpty)
                          Text(
                            ownerContact,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .65),
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(height: 4),
                      ],
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (status.isNotEmpty)
                            _MiniReviewChip(
                              label: () {
                                final s = status.toLowerCase();
                                if (l.isArabic) {
                                  if (s == 'active') return 'نشط';
                                  if (s == 'disabled') return 'متوقف';
                                  return 'الحالة: $status';
                                } else {
                                  if (s == 'active') return 'Active';
                                  if (s == 'disabled') return 'Disabled';
                                  return 'Status: $status';
                                }
                              }(),
                              tone: status.toLowerCase() == 'active'
                                  ? _MiniReviewTone.success
                                  : _MiniReviewTone.neutral,
                            ),
                          _MiniReviewChip(
                            label: () {
                              if (l.isArabic) {
                                switch (reviewLower) {
                                  case 'submitted':
                                    return 'قيد المراجعة';
                                  case 'approved':
                                    return 'مقبول';
                                  case 'rejected':
                                    return 'مرفوض';
                                  case 'suspended':
                                    return 'موقوف';
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
                                  case 'suspended':
                                    return 'Suspended';
                                  default:
                                    return 'Not submitted';
                                }
                              }
                            }(),
                            tone: () {
                              if (reviewLower == 'submitted') {
                                return _MiniReviewTone.info;
                              }
                              if (reviewLower == 'approved') {
                                return _MiniReviewTone.success;
                              }
                              if (reviewLower == 'rejected' ||
                                  reviewLower == 'suspended') {
                                return _MiniReviewTone.danger;
                              }
                              return _MiniReviewTone.neutral;
                            }(),
                          ),
                          if (usage > 0)
                            _MiniReviewChip(
                              label: l.isArabic
                                  ? 'الفتحات $usage'
                                  : 'Opens $usage',
                              tone: _MiniReviewTone.neutral,
                            ),
                          if (rating > 0)
                            _MiniReviewChip(
                              label: '⭐ ${rating.toStringAsFixed(1)}',
                              tone: _MiniReviewTone.neutral,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.check_circle_outline,
                                size: 18),
                            label: Text(
                              l.isArabic ? 'قبول' : 'Approve',
                            ),
                            onPressed: canApprove
                                ? () {
                                    _updateReviewStatus(
                                      appId,
                                      status: 'active',
                                      reviewStatus: 'approved',
                                    );
                                  }
                                : null,
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: Text(
                              l.isArabic ? 'رفض' : 'Reject',
                            ),
                            onPressed: canReject
                                ? () {
                                    _updateReviewStatus(
                                      appId,
                                      status: 'disabled',
                                      reviewStatus: 'rejected',
                                    );
                                  }
                                : null,
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(Icons.pause_circle_outline,
                                size: 18),
                            label: Text(
                              l.isArabic ? 'إيقاف' : 'Suspend',
                            ),
                            onPressed: canSuspend
                                ? () {
                                    _updateReviewStatus(
                                      appId,
                                      status: 'disabled',
                                      reviewStatus: 'suspended',
                                    );
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }

      body = DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              labelColor: theme.colorScheme.primary,
              tabs: [
                Tab(
                  text: l.isArabic ? 'قيد المراجعة' : 'Review queue',
                ),
                Tab(
                  text: l.isArabic ? 'الكل' : 'All',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  buildList(submitted),
                  buildList(_programs),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic
              ? 'مركز مراجعة البرامج المصغّرة'
              : 'Mini‑program review center',
        ),
      ),
      body: body,
    );
  }
}

enum _MiniReviewTone { neutral, success, info, danger }

class _MiniReviewChip extends StatelessWidget {
  final String label;
  final _MiniReviewTone tone;

  const _MiniReviewChip({
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    switch (tone) {
      case _MiniReviewTone.success:
        bg = Colors.green.withValues(alpha: .10);
        fg = Colors.green.shade700;
        break;
      case _MiniReviewTone.info:
        bg = theme.colorScheme.primary.withValues(alpha: .08);
        fg = theme.colorScheme.primary.withValues(alpha: .90);
        break;
      case _MiniReviewTone.danger:
        bg = Colors.red.withValues(alpha: .10);
        fg = Colors.red.shade700;
        break;
      case _MiniReviewTone.neutral:
      default:
        bg = theme.colorScheme.surface.withValues(alpha: .06);
        fg = theme.colorScheme.onSurface.withValues(alpha: .85);
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
