import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'session_cookie_store.dart';
import 'shamell_empty_state.dart';
import 'shamell_loading_shimmer.dart';

class MiniProgramsReviewPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? httpClient;

  const MiniProgramsReviewPage({
    super.key,
    required this.baseUrl,
    this.httpClient,
  });

  @override
  State<MiniProgramsReviewPage> createState() => _MiniProgramsReviewPageState();
}

class _MiniProgramsReviewPageState extends State<MiniProgramsReviewPage> {
  static const Duration _requestTimeout = Duration(seconds: 12);

  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _programs = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? http.Client();
    _load();
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: jsonBody);
  }

  bool _isPendingReview(Map<String, dynamic> p) {
    final status = (p['status'] ?? '').toString().trim().toLowerCase();
    final review = (p['review_status'] ?? '').toString().trim().toLowerCase();
    return status == 'pending_review' ||
        review == 'pending' ||
        review == 'submitted' ||
        review == 'changes_requested';
  }

  bool _isPublishedStatus(String raw) {
    final status = raw.trim().toLowerCase();
    return status == 'active' || status == 'published';
  }

  String _statusLabel(String raw, L10n l) {
    final status = raw.trim().toLowerCase();
    if (_isPublishedStatus(status)) return l.isArabic ? 'منشور' : 'Published';
    if (status == 'pending_review') {
      return l.isArabic ? 'قيد المراجعة' : 'In review';
    }
    if (status == 'draft') return l.isArabic ? 'مسودة' : 'Draft';
    if (status == 'suspended') return l.isArabic ? 'موقوف' : 'Suspended';
    if (status == 'archived') return l.isArabic ? 'مؤرشف' : 'Archived';
    return l.isArabic ? 'الحالة: $raw' : 'Status: $raw';
  }

  String _reviewLabel(String raw, L10n l) {
    final review = raw.trim().toLowerCase();
    if (review == 'pending' || review == 'submitted') {
      return l.isArabic ? 'قيد المراجعة' : 'In review';
    }
    if (review == 'approved') return l.isArabic ? 'مقبول' : 'Approved';
    if (review == 'rejected') return l.isArabic ? 'مرفوض' : 'Rejected';
    if (review == 'changes_requested') {
      return l.isArabic ? 'تغييرات مطلوبة' : 'Changes requested';
    }
    if (review == 'draft') return l.isArabic ? 'مسودة' : 'Draft';
    return l.isArabic ? 'غير مرسَل للمراجعة' : 'Not submitted';
  }

  _MiniReviewTone _reviewTone(String raw) {
    final review = raw.trim().toLowerCase();
    if (review == 'pending' || review == 'submitted') {
      return _MiniReviewTone.info;
    }
    if (review == 'approved') return _MiniReviewTone.success;
    if (review == 'rejected' || review == 'changes_requested') {
      return _MiniReviewTone.danger;
    }
    return _MiniReviewTone.neutral;
  }

  String _manifestAuthorityLabel(String raw, L10n l) {
    final authority = raw.trim().toLowerCase();
    switch (authority) {
      case 'server_released_bundle':
        return l.isArabic ? 'حزمة منشورة من الخادم' : 'Server bundle';
      case 'server_native_manifest':
        return l.isArabic ? 'بيان خادم مدمج' : 'Server native';
      case 'server_review_pending':
        return l.isArabic ? 'ينتظر مراجعة الخادم' : 'Server review pending';
      case 'server_changes_requested':
        return l.isArabic ? 'تغييرات مطلوبة من الخادم' : 'Server changes';
      case 'server_rejected':
        return l.isArabic ? 'مرفوض من الخادم' : 'Server rejected';
      case 'server_restricted':
        return l.isArabic ? 'مقيّد من الخادم' : 'Server restricted';
      case 'server_draft':
        return l.isArabic ? 'مسودة على الخادم' : 'Server draft';
      case 'local_fallback':
        return l.isArabic ? 'احتياطي محلي' : 'Local fallback';
      default:
        return raw.trim().isEmpty ? (l.isArabic ? 'غير محدد' : 'Unknown') : raw;
    }
  }

  _MiniReviewTone _manifestAuthorityTone(String raw) {
    final authority = raw.trim().toLowerCase();
    if (authority == 'server_released_bundle' ||
        authority == 'server_native_manifest') {
      return _MiniReviewTone.success;
    }
    if (authority == 'server_review_pending') return _MiniReviewTone.info;
    if (authority == 'local_fallback' || authority == 'server_draft') {
      return _MiniReviewTone.neutral;
    }
    return _MiniReviewTone.danger;
  }

  String _text(dynamic raw) => (raw ?? '').toString().trim();

  String _localizedText(
    Map<String, dynamic> p,
    String enKey,
    String arKey,
    L10n l,
  ) {
    final en = _text(p[enKey]);
    final ar = _text(p[arKey]);
    if (l.isArabic && ar.isNotEmpty) return ar;
    return en.isNotEmpty ? en : ar;
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  String _actionLabel(Map<String, dynamic> action, L10n l) {
    final labelEn = _text(action['label_en'] ?? action['label']);
    final labelAr = _text(action['label_ar']);
    final id = _text(action['id'] ?? action['key']);
    if (l.isArabic && labelAr.isNotEmpty) return labelAr;
    if (labelEn.isNotEmpty) return labelEn;
    return id.isNotEmpty ? id : (l.isArabic ? 'إجراء' : 'Action');
  }

  String _actionDetail(Map<String, dynamic> action) {
    final kind = _text(action['kind'] ?? action['type']);
    final modId = _text(action['mod_id'] ?? action['modId']);
    final url = _text(action['url'] ?? action['href']);
    final target = modId.isNotEmpty ? modId : url;
    if (kind.isEmpty && target.isEmpty) return '';
    if (target.isEmpty) return kind;
    if (kind.isEmpty) return target;
    return '$kind · $target';
  }

  bool _isEnabled(Map<String, dynamic> p) {
    final raw = p['enabled'];
    return raw is bool ? raw : true;
  }

  bool _isOfficial(Map<String, dynamic> p) => p['official'] is bool
      ? p['official'] as bool
      : _text(p['official']).toLowerCase() == 'true';

  bool _isBeta(Map<String, dynamic> p) => p['beta'] is bool
      ? p['beta'] as bool
      : _text(p['beta']).toLowerCase() == 'true';

  bool _isPublishedProgram(Map<String, dynamic> p) {
    return _isPublishedStatus(_text(p['status'])) && _isEnabled(p);
  }

  int _intValue(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  double _doubleValue(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  Widget _summaryHeader(
    L10n l,
    ThemeData theme,
    List<Map<String, dynamic>> submitted,
  ) {
    final published = _programs.where(_isPublishedProgram).length;
    final disabled = _programs.where((p) => !_isEnabled(p)).length;
    final scopeCount = _programs.fold<int>(
      0,
      (total, p) => total + _stringList(p['scopes']).length,
    );
    final actionCount = _programs.fold<int>(
      0,
      (total, p) => total + _mapList(p['actions']).length,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _RegistryMetric(
            label: l.isArabic ? 'المجموع' : 'Total',
            value: _programs.length.toString(),
          ),
          _RegistryMetric(
            label: l.isArabic ? 'المراجعة' : 'Review',
            value: submitted.length.toString(),
          ),
          _RegistryMetric(
            label: l.isArabic ? 'منشور' : 'Published',
            value: published.toString(),
          ),
          _RegistryMetric(
            label: l.isArabic ? 'معطّل' : 'Disabled',
            value: disabled.toString(),
          ),
          _RegistryMetric(
            label: l.isArabic ? 'الصلاحيات' : 'Scopes',
            value: scopeCount.toString(),
          ),
          _RegistryMetric(
            label: l.isArabic ? 'الإجراءات' : 'Actions',
            value: actionCount.toString(),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs').replace(
        queryParameters: const <String, String>{
          'include_disabled': 'true',
          'limit': '200',
        },
      );
      final r =
          await _http.get(uri, headers: await _hdr()).timeout(_requestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() {
          _error = r.body.isNotEmpty ? r.body : 'HTTP ${r.statusCode}';
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
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateReviewStatus(
    String appId, {
    String? status,
    String? reviewStatus,
    bool? enabled,
  }) async {
    if (appId.isEmpty) return;
    final l = L10n.of(context);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/admin/mini_programs/${Uri.encodeComponent(appId)}',
      );
      final body = <String, dynamic>{};
      if (status != null) body['status'] = status;
      if (reviewStatus != null) body['review_status'] = reviewStatus;
      if (enabled != null) body['enabled'] = enabled;
      final r = await _http
          .patch(
            uri,
            headers: await _hdr(jsonBody: true),
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        String msg = 'HTTP ${r.statusCode}';
        try {
          final decoded = jsonDecode(r.body);
          if (decoded is Map && decoded['detail'] != null) {
            msg = decoded['detail'].toString();
          }
        } catch (_) {}
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
          content: Text(e.toString()),
        ),
      );
    }
  }

  Future<void> _openManifestDetails(Map<String, dynamic> p) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final appId = _text(p['app_id']);
    final runtimeId = _text(p['runtime_app_id']);
    final title = _localizedText(p, 'title_en', 'title_ar', l);
    final description =
        _localizedText(p, 'description_en', 'description_ar', l);
    final category = _localizedText(p, 'category_en', 'category_ar', l);
    final ownerName = _text(p['owner_name']);
    final ownerContact = _text(p['owner_contact']);
    final status = _text(p['status']);
    final reviewText = _text(p['review_status']);
    final review = reviewText.isNotEmpty ? reviewText : 'draft';
    final scopes = _stringList(p['scopes']);
    final actions = _mapList(p['actions']);
    final latestVersion = _text(p['latest_version'] ?? p['last_version']);
    final latestReview = _text(p['latest_version_review_status']);
    final releasedVersion = _text(p['released_version']);
    final bundleUrl = _text(p['released_bundle_url']);
    final manifestAuthority = _text(p['manifest_authority']);
    final changelog = _localizedText(
      p,
      'released_changelog_en',
      'released_changelog_ar',
      l,
    );
    final isInReview = _isPendingReview(p);
    final isApproved = review.toLowerCase() == 'approved';
    final isPublished = _isPublishedProgram(p);
    final canApprove = appId.isNotEmpty && (!isPublished || !isApproved);
    final canRequestChanges = appId.isNotEmpty && (isInReview || isApproved);
    final canReject = appId.isNotEmpty && (isInReview || isApproved);
    final canSuspend = appId.isNotEmpty && (isPublished || isApproved);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        void closeAndUpdate({
          String? status,
          String? reviewStatus,
          bool? enabled,
        }) {
          Navigator.of(sheetContext).pop();
          _updateReviewStatus(
            appId,
            status: status,
            reviewStatus: reviewStatus,
            enabled: enabled,
          );
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .86,
          minChildSize: .48,
          maxChildSize: .96,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.fact_check_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.isArabic
                                ? 'سجل البرنامج المصغّر'
                                : 'Registry manifest',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            title.isNotEmpty ? title : appId,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l.isArabic ? 'إغلاق' : 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .78),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (status.isNotEmpty)
                      _MiniReviewChip(
                        label: _statusLabel(status, l),
                        tone: isPublished
                            ? _MiniReviewTone.success
                            : _MiniReviewTone.neutral,
                      ),
                    _MiniReviewChip(
                      label: _reviewLabel(review, l),
                      tone: _reviewTone(review),
                    ),
                    if (manifestAuthority.isNotEmpty)
                      _MiniReviewChip(
                        label: _manifestAuthorityLabel(manifestAuthority, l),
                        tone: _manifestAuthorityTone(manifestAuthority),
                      ),
                    if (!_isEnabled(p))
                      _MiniReviewChip(
                        label: l.isArabic ? 'غير مفعّل' : 'Disabled',
                        tone: _MiniReviewTone.neutral,
                      ),
                    if (_isOfficial(p))
                      _MiniReviewChip(
                        label: l.isArabic ? 'رسمي' : 'Official',
                        tone: _MiniReviewTone.success,
                      ),
                    if (_isBeta(p))
                      _MiniReviewChip(
                        label: l.isArabic ? 'قيد المعاينة' : 'Preview',
                        tone: _MiniReviewTone.info,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _ManifestSection(
                  title: l.isArabic ? 'هوية التطبيق' : 'App identity',
                  children: [
                    _ManifestKeyValue(
                      label: 'app_id',
                      value: appId,
                    ),
                    _ManifestKeyValue(
                      label: 'runtime_app_id',
                      value: runtimeId.isNotEmpty ? runtimeId : appId,
                    ),
                    if (category.isNotEmpty)
                      _ManifestKeyValue(
                        label: l.isArabic ? 'الفئة' : 'Category',
                        value: category,
                      ),
                    if (ownerName.isNotEmpty || ownerContact.isNotEmpty)
                      _ManifestKeyValue(
                        label: l.isArabic ? 'المالك' : 'Owner',
                        value: ownerName.isNotEmpty ? ownerName : ownerContact,
                      ),
                    if (ownerName.isNotEmpty && ownerContact.isNotEmpty)
                      _ManifestKeyValue(
                        label: l.isArabic ? 'تواصل' : 'Contact',
                        value: ownerContact,
                      ),
                  ],
                ),
                _ManifestSection(
                  title: l.isArabic ? 'الإصدار' : 'Version',
                  children: [
                    _ManifestKeyValue(
                      label: l.isArabic ? 'مصدر البيان' : 'Manifest authority',
                      value: _manifestAuthorityLabel(manifestAuthority, l),
                    ),
                    _ManifestKeyValue(
                      label: l.isArabic ? 'الأحدث' : 'Latest',
                      value: latestVersion.isNotEmpty
                          ? latestVersion
                          : (l.isArabic ? 'غير متوفر' : 'Not submitted'),
                    ),
                    if (latestReview.isNotEmpty)
                      _ManifestKeyValue(
                        label: l.isArabic ? 'مراجعة الإصدار' : 'Version review',
                        value: _reviewLabel(latestReview, l),
                      ),
                    _ManifestKeyValue(
                      label: l.isArabic ? 'الإصدار المنشور' : 'Released',
                      value: releasedVersion.isNotEmpty
                          ? releasedVersion
                          : (l.isArabic ? 'لا يوجد' : 'None'),
                    ),
                    if (bundleUrl.isNotEmpty)
                      _ManifestKeyValue(
                        label: 'bundle_url',
                        value: bundleUrl,
                      ),
                    if (changelog.isNotEmpty)
                      _ManifestKeyValue(
                        label: l.isArabic ? 'سجل التغيير' : 'Changelog',
                        value: changelog,
                      ),
                  ],
                ),
                _ManifestSection(
                  title: l.isArabic ? 'الصلاحيات' : 'Scopes',
                  children: [
                    if (scopes.isEmpty)
                      Text(
                        l.isArabic
                            ? 'لا توجد صلاحيات مطلوبة.'
                            : 'No scopes requested.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .62),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final scope in scopes)
                            _MiniReviewChip(
                              label: scope,
                              tone: _MiniReviewTone.info,
                            ),
                        ],
                      ),
                  ],
                ),
                _ManifestSection(
                  title: l.isArabic ? 'الإجراءات' : 'Actions',
                  children: [
                    if (actions.isEmpty)
                      Text(
                        l.isArabic
                            ? 'لا توجد إجراءات معرفة.'
                            : 'No actions defined.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .62),
                        ),
                      )
                    else
                      for (final action in actions)
                        _ManifestActionRow(
                          id: _text(action['id'] ?? action['key']),
                          label: _actionLabel(action, l),
                          detail: _actionDetail(action),
                        ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(l.isArabic ? 'قبول' : 'Approve'),
                      onPressed: canApprove
                          ? () => closeAndUpdate(
                                status: 'published',
                                reviewStatus: 'approved',
                                enabled: true,
                              )
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.rule_outlined, size: 18),
                      label: Text(l.isArabic ? 'تغييرات' : 'Changes'),
                      onPressed: canRequestChanges
                          ? () => closeAndUpdate(
                                status: 'pending_review',
                                reviewStatus: 'changes_requested',
                                enabled: false,
                              )
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(l.isArabic ? 'رفض' : 'Reject'),
                      onPressed: canReject
                          ? () => closeAndUpdate(
                                status: 'pending_review',
                                reviewStatus: 'rejected',
                                enabled: false,
                              )
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.pause_circle_outline, size: 18),
                      label: Text(l.isArabic ? 'إيقاف' : 'Suspend'),
                      onPressed: canSuspend
                          ? () => closeAndUpdate(
                                status: 'suspended',
                                reviewStatus: 'approved',
                                enabled: false,
                              )
                          : null,
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    Widget body;
    if (_loading) {
      body = const ShamellSkeletonList(itemCount: 6);
    } else if (_error.isNotEmpty) {
      body = ShamellEmptyState.error(
        title: _error,
      );
    } else if (_programs.isEmpty) {
      body = ShamellEmptyState.empty(
        icon: Icons.widgets_outlined,
        title: l.isArabic
            ? 'لا توجد برامج مصغّرة مسجلة بعد.'
            : 'No mini‑programs registered yet.',
      );
    } else {
      final submitted = <Map<String, dynamic>>[];
      for (final p in _programs) {
        if (_isPendingReview(p)) {
          submitted.add(p);
        }
      }
      Widget buildList(List<Map<String, dynamic>> items) {
        if (items.isEmpty) {
          return ShamellEmptyState.empty(
            icon: Icons.inbox_outlined,
            title: l.isArabic ? 'لا توجد عناصر.' : 'No items.',
          );
        }
        return ListView.builder(
          itemCount: items.length,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          itemBuilder: (ctx, i) {
            final p = items[i];
            final appId = _text(p['app_id']);
            final runtimeId = _text(p['runtime_app_id']);
            final ownerName = _text(p['owner_name']);
            final ownerContact = _text(p['owner_contact']);
            final status = _text(p['status']);
            final reviewText = _text(p['review_status']);
            final review = reviewText.isNotEmpty ? reviewText : 'draft';
            final isEnabled = _isEnabled(p);
            final usage = _intValue(p['usage_score']);
            final rating = _doubleValue(p['rating']);
            final scopes = _stringList(p['scopes']);
            final actions = _mapList(p['actions']);
            final category = _localizedText(p, 'category_en', 'category_ar', l);
            final description =
                _localizedText(p, 'description_en', 'description_ar', l);
            final latestVersion =
                _text(p['latest_version'] ?? p['last_version']);
            final latestReview = _text(p['latest_version_review_status']);
            final releasedVersion = _text(p['released_version']);
            final manifestAuthority = _text(p['manifest_authority']);
            final title = _localizedText(p, 'title_en', 'title_ar', l);
            final displayTitle = title.isNotEmpty ? title : appId;
            final reviewLower = review.toLowerCase();
            final isInReview = _isPendingReview(p);
            final isApproved = reviewLower == 'approved';
            final isPublished = _isPublishedProgram(p);
            final canApprove =
                appId.isNotEmpty && (!isPublished || !isApproved);
            final canRequestChanges =
                appId.isNotEmpty && (isInReview || isApproved);
            final canReject = appId.isNotEmpty && (isInReview || isApproved);
            final canSuspend = appId.isNotEmpty && (isPublished || isApproved);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openManifestDetails(p),
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
                                    displayTitle,
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
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
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
                        if (description.isNotEmpty) ...[
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (ownerName.isNotEmpty ||
                            ownerContact.isNotEmpty) ...[
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
                            if (category.isNotEmpty)
                              _MiniReviewChip(
                                label: category,
                                tone: _MiniReviewTone.neutral,
                              ),
                            if (runtimeId.isNotEmpty && runtimeId != appId)
                              _MiniReviewChip(
                                label: 'runtime $runtimeId',
                                tone: _MiniReviewTone.neutral,
                              ),
                            if (_isOfficial(p))
                              _MiniReviewChip(
                                label: l.isArabic ? 'رسمي' : 'Official',
                                tone: _MiniReviewTone.success,
                              ),
                            if (_isBeta(p))
                              _MiniReviewChip(
                                label: l.isArabic ? 'قيد المعاينة' : 'Preview',
                                tone: _MiniReviewTone.info,
                              ),
                            if (latestVersion.isNotEmpty)
                              _MiniReviewChip(
                                label: latestReview.isNotEmpty
                                    ? 'latest $latestVersion · $latestReview'
                                    : 'latest $latestVersion',
                                tone: _MiniReviewTone.info,
                              ),
                            if (releasedVersion.isNotEmpty)
                              _MiniReviewChip(
                                label: 'released $releasedVersion',
                                tone: _MiniReviewTone.success,
                              ),
                            if (manifestAuthority.isNotEmpty)
                              _MiniReviewChip(
                                label: _manifestAuthorityLabel(
                                  manifestAuthority,
                                  l,
                                ),
                                tone: _manifestAuthorityTone(
                                  manifestAuthority,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (status.isNotEmpty)
                              _MiniReviewChip(
                                label: _statusLabel(status, l),
                                tone: isPublished
                                    ? _MiniReviewTone.success
                                    : _MiniReviewTone.neutral,
                              ),
                            if (!isEnabled)
                              _MiniReviewChip(
                                label: l.isArabic ? 'غير مفعّل' : 'Disabled',
                                tone: _MiniReviewTone.neutral,
                              ),
                            _MiniReviewChip(
                              label: _reviewLabel(review, l),
                              tone: _reviewTone(review),
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
                        if (scopes.isNotEmpty || actions.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (scopes.isNotEmpty)
                                _MiniReviewChip(
                                  label: l.isArabic
                                      ? '${scopes.length} صلاحيات'
                                      : '${scopes.length} scopes',
                                  tone: _MiniReviewTone.info,
                                ),
                              for (final scope in scopes.take(3))
                                _MiniReviewChip(
                                  label: scope,
                                  tone: _MiniReviewTone.info,
                                ),
                              if (actions.isNotEmpty)
                                _MiniReviewChip(
                                  label: l.isArabic
                                      ? '${actions.length} إجراءات'
                                      : '${actions.length} actions',
                                  tone: _MiniReviewTone.neutral,
                                ),
                              for (final action in actions.take(2))
                                _MiniReviewChip(
                                  label: _actionLabel(action, l),
                                  tone: _MiniReviewTone.neutral,
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.fact_check_outlined,
                                  size: 18),
                              label: Text(
                                l.isArabic ? 'البيان' : 'Manifest',
                              ),
                              onPressed: () => _openManifestDetails(p),
                            ),
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
                                        status: 'published',
                                        reviewStatus: 'approved',
                                        enabled: true,
                                      );
                                    }
                                  : null,
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.rule_outlined, size: 18),
                              label: Text(
                                l.isArabic ? 'تغييرات' : 'Changes',
                              ),
                              onPressed: canRequestChanges
                                  ? () {
                                      _updateReviewStatus(
                                        appId,
                                        status: 'pending_review',
                                        reviewStatus: 'changes_requested',
                                        enabled: false,
                                      );
                                    }
                                  : null,
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(
                                l.isArabic ? 'رفض' : 'Reject',
                              ),
                              onPressed: canReject
                                  ? () {
                                      _updateReviewStatus(
                                        appId,
                                        status: 'pending_review',
                                        reviewStatus: 'rejected',
                                        enabled: false,
                                      );
                                    }
                                  : null,
                            ),
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
                                        status: 'suspended',
                                        reviewStatus: 'approved',
                                        enabled: false,
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
              ),
            );
          },
        );
      }

      body = DefaultTabController(
        length: 2,
        child: Column(
          children: [
            _summaryHeader(l, theme, submitted),
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

class _RegistryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _RegistryMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 86),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .62),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManifestSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ManifestSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ManifestKeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _ManifestKeyValue({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .58),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isNotEmpty ? value : '-',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .86),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManifestActionRow extends StatelessWidget {
  final String id;
  final String label;
  final String detail;

  const _ManifestActionRow({
    required this.id,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .42),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome_motion_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (id.isNotEmpty)
                  Text(
                    id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .58),
                    ),
                  ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
