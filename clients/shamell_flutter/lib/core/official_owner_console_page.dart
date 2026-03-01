import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'official_accounts_page.dart'
    show OfficialAccountHandle, OfficialAccountFeedPage;
import 'mini_programs_my_page_insights.dart' show MiniProgramInsightChip;
import 'moments_page.dart' show MomentsPage;
import 'channels_page.dart' show ChannelsPage;
import 'official_moments_comments_page.dart';
import 'official_service_inbox_page.dart';
import 'app_shell_widgets.dart' show AppBG;
import 'safe_set_state.dart';

class OfficialOwnerConsolePage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final String accountName;

  const OfficialOwnerConsolePage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    required this.accountName,
  });

  @override
  State<OfficialOwnerConsolePage> createState() =>
      _OfficialOwnerConsolePageState();
}

class _OfficialOwnerConsolePageState extends State<OfficialOwnerConsolePage>
    with SafeSetStateMixin<OfficialOwnerConsolePage> {
  static const Duration _officialOwnerRequestTimeout = Duration(seconds: 15);
  bool _loading = true;
  String _error = '';
  OfficialAccountHandle? _account;
  Map<String, dynamic>? _momentsStats;
  List<Map<String, dynamic>> _autoReplies = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    final headers = <String, String>{};
    if (jsonBody) {
      headers['content-type'] = 'application/json';
    }
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
      OfficialAccountHandle? acc;
      try {
        final uri = Uri.parse('${widget.baseUrl}/official_accounts')
            .replace(queryParameters: const {'followed_only': 'false'});
        final r = await http
            .get(uri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          final list = <OfficialAccountHandle>[];
          if (decoded is Map && decoded['accounts'] is List) {
            for (final e in decoded['accounts'] as List) {
              if (e is Map) {
                list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()),
                );
              }
            }
          } else if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) {
                list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()),
                );
              }
            }
          }
          for (final a in list) {
            if (a.id == widget.accountId) {
              acc = a;
              break;
            }
          }
        }
      } catch (_) {}
      Map<String, dynamic>? moments;
      List<Map<String, dynamic>> autoReplies = const <Map<String, dynamic>>[];
      try {
        final uri = Uri.parse(
          '${widget.baseUrl}/official_accounts/${Uri.encodeComponent(widget.accountId)}/moments_stats',
        );
        final r = await http
            .get(uri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          if (decoded is Map) {
            moments = decoded.cast<String, dynamic>();
          }
        }
      } catch (_) {}
      // Load existing auto‑reply rules for this Official account via admin API.
      try {
        final uri = Uri.parse(
          '${widget.baseUrl}/admin/official_accounts/${Uri.encodeComponent(widget.accountId)}/auto_replies',
        );
        final r = await http
            .get(uri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          if (decoded is Map && decoded['rules'] is List) {
            final list = <Map<String, dynamic>>[];
            for (final e in decoded['rules'] as List) {
              if (e is Map) {
                list.add(e.cast<String, dynamic>());
              }
            }
            autoReplies = list;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _account = acc;
        _momentsStats = moments;
        _autoReplies = autoReplies;
        _loading = false;
        if (acc == null) {
          _error = 'Official account not found';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final acc = _account;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'مركز الحساب الرسمي' : 'Official account console',
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (acc == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'مركز الحساب الرسمي' : 'Official account console',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error.isNotEmpty
                  ? _error
                  : (l.isArabic
                      ? 'تعذّر العثور على هذا الحساب الرسمي.'
                      : 'Could not find this official account.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      );
    }

    final stats = _momentsStats ?? const <String, dynamic>{};
    final totalShares = (stats['total_shares'] is num)
        ? (stats['total_shares'] as num).toInt()
        : 0;
    final shares30 =
        (stats['shares_30d'] is num) ? (stats['shares_30d'] as num).toInt() : 0;
    final uniqueSharersTotal = (stats['unique_sharers_total'] is num)
        ? (stats['unique_sharers_total'] as num).toInt()
        : 0;
    final comments30 = (stats['comments_30d'] is num)
        ? (stats['comments_30d'] as num).toInt()
        : 0;
    final followers =
        (stats['followers'] is num) ? (stats['followers'] as num).toInt() : 0;
    final sharesPer1k = (stats['shares_per_1k_followers'] is num)
        ? (stats['shares_per_1k_followers'] as num).toDouble()
        : 0.0;

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: acc.avatarUrl != null
                      ? NetworkImage(acc.avatarUrl!)
                      : null,
                  child: acc.avatarUrl == null
                      ? Text(
                          acc.name.isNotEmpty
                              ? acc.name.characters.first.toUpperCase()
                              : '?',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              acc.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (acc.verified)
                            Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.verified,
                                size: 18,
                                color: Tokens.colorPayments,
                              ),
                            ),
                        ],
                      ),
                      if ((acc.category ?? '').isNotEmpty ||
                          (acc.city ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if ((acc.category ?? '').isNotEmpty)
                                acc.category!,
                              if ((acc.city ?? '').isNotEmpty) acc.city!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                        ),
                      if (acc.openingHours != null &&
                          acc.openingHours!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            acc.openingHours!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'خدمة العملاء' : 'Customer service',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.support_agent_outlined),
                  title: Text(
                    l.isArabic
                        ? 'صندوق خدمة العملاء'
                        : 'Customer service inbox',
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'عرض جلسات خدمة العملاء المفتوحة والرد عبر Shamell.'
                        : 'View open customer-service sessions and reply via Shamell chats.',
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OfficialServiceInboxPage(
                          baseUrl: widget.baseUrl,
                          accountId: widget.accountId,
                          accountName: widget.accountName,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (acc.qrPayload != null && acc.qrPayload!.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.isArabic ? 'رمز QR للحساب' : 'Official QR code',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: QrImageView(
                      data: acc.qrPayload!,
                      size: 160,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.isArabic
                        ? 'يمكن للعملاء مسح هذا الرمز لمتابعة الحساب وفتح الدردشة أو الخدمات، مثل Shamell Official Accounts.'
                        : 'Customers can scan this code to follow, chat and open services, similar to Shamell Official Accounts.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (totalShares > 0 || shares30 > 0 || followers > 0 || comments30 > 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isArabic ? 'الأثر في اللحظات' : 'Moments impact',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      MiniProgramInsightChip(
                        icon: Icons.share_outlined,
                        label: l.isArabic ? 'إجمالي المشاركات' : 'Total shares',
                        value: totalShares > 0
                            ? totalShares.toString()
                            : (l.isArabic ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.timeline_outlined,
                        label:
                            l.isArabic ? 'مشاركات (٣٠ يوماً)' : 'Shares (30d)',
                        value: shares30 > 0
                            ? shares30.toString()
                            : (l.isArabic ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.people_outline,
                        label: l.isArabic ? 'المتابعون' : 'Followers',
                        value: followers > 0
                            ? followers.toString()
                            : (l.isArabic ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.group_outlined,
                        label:
                            l.isArabic ? 'مستخدمون فريدون' : 'Unique sharers',
                        value: uniqueSharersTotal > 0
                            ? uniqueSharersTotal.toString()
                            : (l.isArabic ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.insights_outlined,
                        label: l.isArabic
                            ? 'مشاركات لكل ١٠٠٠ متابع'
                            : 'Shares / 1K followers',
                        value: sharesPer1k > 0
                            ? sharesPer1k.toStringAsFixed(1)
                            : (l.isArabic ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.comment_outlined,
                        label: l.isArabic
                            ? 'تعليقات (٣٠ يوماً)'
                            : 'Comments (30d)',
                        value: comments30 > 0
                            ? comments30.toString()
                            : (l.isArabic ? 'لا بيانات' : 'No data'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'قنوات الحساب' : 'Account channels',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openFeedComposer(acc),
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: Text(
                        l.isArabic ? 'منشور جديد في الخلاصة' : 'New feed item',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OfficialAccountFeedPage(
                              baseUrl: widget.baseUrl,
                              account: acc,
                              onOpenChat: null,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: Text(
                        l.isArabic ? 'خلاصة الحساب الرسمي' : 'Official feed',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChannelsPage(
                              baseUrl: widget.baseUrl,
                              officialAccountId: widget.accountId,
                              officialName: acc.name,
                              initialHotOnly: false,
                              forOwnerConsole: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.live_tv_outlined, size: 18),
                      label: Text(
                        l.isArabic ? 'لوحة القنوات' : 'Channels dashboard',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChannelsPage(
                              baseUrl: widget.baseUrl,
                              officialAccountId: widget.accountId,
                              officialName: acc.name,
                              forOwnerConsole: true,
                              openLiveComposerOnStart: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.radio_button_checked, size: 18),
                      label: Text(
                        l.isArabic ? 'بدء بث مباشر' : 'Go live',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MomentsPage(
                              baseUrl: widget.baseUrl,
                              originOfficialAccountId: widget.accountId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(
                        l.isArabic
                            ? 'منشورات هذا الحساب في اللحظات'
                            : 'Moments posts from this account',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OfficialMomentsCommentsPage(
                              baseUrl: widget.baseUrl,
                              accountId: widget.accountId,
                              accountName: acc.name,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.comment_outlined, size: 18),
                      label: Text(
                        l.isArabic
                            ? 'تعليقات اللحظات (إدارة)'
                            : 'Moments comments (admin)',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'الردود التلقائية' : 'Auto replies',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.isArabic
                      ? 'يمكنك إعداد رسالة ترحيب يتم عرضها تلقائياً عند فتح الدردشة مع الحساب الرسمي (أسلوب شبيه بـ Shamell).'
                      : 'Configure a welcome message that is shown automatically when a chat with this Official account is opened (Shamell‑style).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (ctx) {
                    Map<String, dynamic>? welcome;
                    for (final r in _autoReplies) {
                      final kind =
                          (r['kind'] ?? 'welcome').toString().toLowerCase();
                      if (kind == 'welcome') {
                        welcome = r;
                        break;
                      }
                    }
                    final enabled = (welcome?['enabled'] as bool?) ?? false;
                    final text = (welcome?['text'] ?? '').toString().trim();
                    final hasText = text.isNotEmpty && enabled;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasText
                              ? (l.isArabic
                                  ? 'رسالة ترحيب مفعّلة:'
                                  : 'Active welcome message:')
                              : (l.isArabic
                                  ? 'لا توجد رسالة ترحيب مفعّلة بعد.'
                                  : 'No active welcome message yet.'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasText) ...[
                          const SizedBox(height: 4),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _openAutoReplyEditor(welcome),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(
                              l.isArabic
                                  ? 'تعديل رسالة الترحيب'
                                  : 'Edit welcome message',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (ctx) {
                    final keywordRules = _autoReplies
                        .where((r) =>
                            (r['kind'] ?? 'keyword').toString().toLowerCase() ==
                            'keyword')
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.isArabic
                              ? 'قواعد الكلمات المفتاحية (تجريبية)'
                              : 'Keyword auto‑replies (experimental)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (keywordRules.isEmpty)
                          Text(
                            l.isArabic
                                ? 'يمكنك إضافة ردود تلقائية بناءً على كلمات معينة يرسلها المستخدم.'
                                : 'You can add automatic replies that trigger when users send specific keywords.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final r in keywordRules.take(3))
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '"${(r['keyword'] ?? '').toString()}"',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        ((r['enabled'] as bool?) ?? true)
                                            ? Icons.toggle_on
                                            : Icons.toggle_off,
                                        size: 18,
                                        color: ((r['enabled'] as bool?) ?? true)
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurface
                                                .withValues(alpha: .40),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 16,
                                        ),
                                        onPressed: () =>
                                            _openKeywordAutoReplyEditor(r),
                                      ),
                                    ],
                                  ),
                                ),
                              if (keywordRules.length > 3)
                                Text(
                                  l.isArabic
                                      ? '+ ${keywordRules.length - 3} قواعد أخرى'
                                      : '+ ${keywordRules.length - 3} more rules',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _openKeywordAutoReplyEditor(null),
                            icon:
                                const Icon(Icons.add_circle_outline, size: 18),
                            label: Text(
                              l.isArabic
                                  ? 'إضافة قاعدة كلمة مفتاحية'
                                  : 'Add keyword rule',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if ((acc.address ?? '').isNotEmpty || (acc.websiteUrl ?? '').isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isArabic ? 'بيانات المتجر' : 'Merchant profile',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if ((acc.address ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        acc.address!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if ((acc.websiteUrl ?? '').isNotEmpty)
                    Text(
                      acc.websiteUrl!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'مركز الحساب الرسمي' : 'Official account console',
        ),
      ),
      body: AppBG(
        child: body,
      ),
    );
  }

  Future<void> _openFeedComposer(OfficialAccountHandle acc) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final idCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final snippetCtrl = TextEditingController();
    final thumbCtrl = TextEditingController();
    String? error;
    bool submitting = false;
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
                            Icons.article_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'منشور جديد في الحساب الرسمي'
                                  : 'Create new official feed item',
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
                        controller: idCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'معرّف فريد (مثل campaign_2025)'
                              : 'Unique ID (e.g. campaign_2025)',
                          helperText: l.isArabic
                              ? 'يُستخدم كمفتاح داخلي ويمكن تضمينه في روابط أو الحملات.'
                              : 'Used as internal key; can be referenced from campaigns or links.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText:
                              l.isArabic ? 'العنوان' : 'Title (headline)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: snippetCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'نص مختصر / وصف'
                              : 'Short text / snippet',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: thumbCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'رابط صورة (اختياري)'
                              : 'Thumbnail URL (optional)',
                          helperText: l.isArabic
                              ? 'استخدم رابط صورة موجودة لعرض بطاقة غنية في الخلاصة.'
                              : 'Use an existing image URL for a rich feed card.',
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
                            child: Text(
                              l.isArabic ? 'إلغاء' : 'Cancel',
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: submitting
                                ? null
                                : () async {
                                    final slug = idCtrl.text.trim();
                                    final title = titleCtrl.text.trim();
                                    final snippet = snippetCtrl.text.trim();
                                    if (slug.isEmpty || snippet.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'المعرّف والنص مطلوبان.'
                                            : 'ID and snippet are required.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final uri = Uri.parse(
                                          '${widget.baseUrl}/admin/official_feeds');
                                      final payload = <String, Object?>{
                                        'account_id': widget.accountId,
                                        'id': slug,
                                        'type': 'promo',
                                        'title':
                                            title.isNotEmpty ? title : null,
                                        'snippet':
                                            snippet.isNotEmpty ? snippet : null,
                                        'thumb_url':
                                            thumbCtrl.text.trim().isNotEmpty
                                                ? thumbCtrl.text.trim()
                                                : null,
                                      };
                                      final r = await http
                                          .post(
                                            uri,
                                            headers: await _hdr(jsonBody: true),
                                            body: jsonEncode(payload),
                                          )
                                          .timeout(
                                              _officialOwnerRequestTimeout);
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        final msg = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                        if (!mounted) return;
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
                                            l.isArabic
                                                ? 'تم نشر منشور الخلاصة.'
                                                : 'Feed item created.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      setModalState(() {
                                        submitting = false;
                                        error =
                                            sanitizeExceptionForUi(error: e);
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
                              l.isArabic ? 'نشر' : 'Publish',
                            ),
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

  Future<void> _openAutoReplyEditor(Map<String, dynamic>? existing) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final initialText = (existing?['text'] ?? '').toString();
    final textCtrl = TextEditingController(text: initialText);
    bool enabled = (existing?['enabled'] as bool?) ?? true;
    bool submitting = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                            Icons.message_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'رسالة ترحيب تلقائية'
                                  : 'Automatic welcome message',
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
                      Text(
                        l.isArabic
                            ? 'سيتم عرض هذه الرسالة تلقائياً في الدردشة عندما يفتح المستخدم محادثة مع الحساب الرسمي.'
                            : 'This message will be shown automatically in chat when a user opens a conversation with your Official account.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: textCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'نص رسالة الترحيب'
                              : 'Welcome message text',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'تفعيل هذه الرسالة'
                                  : 'Enable this welcome message',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: (v) {
                              setModalState(() {
                                enabled = v;
                              });
                            },
                          ),
                        ],
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
                            child: Text(
                              l.isArabic ? 'إلغاء' : 'Cancel',
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: submitting
                                ? null
                                : () async {
                                    final text = textCtrl.text.trim();
                                    if (text.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'النص مطلوب.'
                                            : 'Text is required.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final headers =
                                          await _hdr(jsonBody: true);
                                      http.Response r;
                                      if (existing != null &&
                                          (existing['id'] != null)) {
                                        final id = existing['id'].toString();
                                        final uri = Uri.parse(
                                          '${widget.baseUrl}/admin/official_auto_replies/$id',
                                        );
                                        r = await http
                                            .patch(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'text': text,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      } else {
                                        final uri = Uri.parse(
                                          '${widget.baseUrl}/admin/official_accounts/${Uri.encodeComponent(widget.accountId)}/auto_replies',
                                        );
                                        r = await http
                                            .post(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'kind': 'welcome',
                                                'text': text,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      }
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        final msg = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                        if (!mounted) return;
                                        setModalState(() {
                                          submitting = false;
                                          error = msg;
                                        });
                                        return;
                                      }
                                      if (!mounted) return;
                                      Navigator.of(ctx).pop();
                                      await _load();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l.isArabic
                                                ? 'تم حفظ رسالة الترحيب.'
                                                : 'Welcome message saved.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      setModalState(() {
                                        submitting = false;
                                        error =
                                            sanitizeExceptionForUi(error: e);
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
                              l.isArabic ? 'حفظ' : 'Save',
                            ),
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

  Future<void> _openKeywordAutoReplyEditor(
      Map<String, dynamic>? existing) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final initialKeyword = (existing?['keyword'] ?? '').toString();
    final initialText = (existing?['text'] ?? '').toString();
    final kwCtrl = TextEditingController(text: initialKeyword);
    final textCtrl = TextEditingController(text: initialText);
    bool enabled = (existing?['enabled'] as bool?) ?? true;
    bool submitting = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                            Icons.rule_folder_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'قاعدة رد تلقائي لكلمة مفتاحية'
                                  : 'Keyword auto‑reply rule',
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
                        controller: kwCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'الكلمة أو العبارة'
                              : 'Keyword or phrase',
                          helperText: l.isArabic
                              ? 'سيتم مطابقة الكلمة داخل النص (مطابقة جزئية، بدون حساسية لحالة الأحرف).'
                              : 'Matched anywhere in the message text (case‑insensitive substring).',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: textCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'نص الرد التلقائي'
                              : 'Auto‑reply text',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'تفعيل هذه القاعدة'
                                  : 'Enable this rule',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: (v) {
                              setModalState(() {
                                enabled = v;
                              });
                            },
                          ),
                        ],
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
                            child: Text(
                              l.isArabic ? 'إلغاء' : 'Cancel',
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: submitting
                                ? null
                                : () async {
                                    final kw = kwCtrl.text.trim();
                                    final txt = textCtrl.text.trim();
                                    if (kw.isEmpty || txt.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'الكلمة والنص مطلوبان.'
                                            : 'Keyword and text are required.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final headers =
                                          await _hdr(jsonBody: true);
                                      http.Response r;
                                      if (existing != null &&
                                          (existing['id'] != null)) {
                                        final id = existing['id'].toString();
                                        final uri = Uri.parse(
                                          '${widget.baseUrl}/admin/official_auto_replies/$id',
                                        );
                                        r = await http
                                            .patch(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'kind': 'keyword',
                                                'keyword': kw,
                                                'text': txt,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      } else {
                                        final uri = Uri.parse(
                                          '${widget.baseUrl}/admin/official_accounts/${Uri.encodeComponent(widget.accountId)}/auto_replies',
                                        );
                                        r = await http
                                            .post(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'kind': 'keyword',
                                                'keyword': kw,
                                                'text': txt,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      }
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        final msg = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                        if (!mounted) return;
                                        setModalState(() {
                                          submitting = false;
                                          error = msg;
                                        });
                                        return;
                                      }
                                      if (!mounted) return;
                                      Navigator.of(ctx).pop();
                                      await _load();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l.isArabic
                                                ? 'تم حفظ قاعدة الكلمة المفتاحية.'
                                                : 'Keyword rule saved.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      setModalState(() {
                                        submitting = false;
                                        error =
                                            sanitizeExceptionForUi(error: e);
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
                              l.isArabic ? 'حفظ' : 'Save',
                            ),
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
}
