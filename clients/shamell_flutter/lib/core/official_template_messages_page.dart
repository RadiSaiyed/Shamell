import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'mini_apps_config.dart';
import 'call_signaling.dart';
import '../mini_apps/payments/payments_shell.dart';
import 'shamell_ui.dart';

class OfficialTemplateMessagesPage extends StatefulWidget {
  final String baseUrl;

  const OfficialTemplateMessagesPage({super.key, required this.baseUrl});

  @override
  State<OfficialTemplateMessagesPage> createState() =>
      _OfficialTemplateMessagesPageState();
}

class _OfficialTemplateMessagesPageState
    extends State<OfficialTemplateMessagesPage> {
  bool _loading = true;
  String _error = '';
  List<_TemplateMessage> _items = const <_TemplateMessage>[];
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      _items = const <_TemplateMessage>[];
    });
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/me/official_template_messages',
      ).replace(queryParameters: const <String, String>{
        'unread_only': 'false',
      });
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['messages'] is List) {
        raw = decoded['messages'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <_TemplateMessage>[];
      for (final e in raw) {
        if (e is! Map) continue;
        items.add(
          _TemplateMessage.fromJson(e.cast<String, dynamic>()),
        );
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      await _persistUnreadFlag(items.any((m) => m.isUnread));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = sanitizeExceptionForUi(error: e);
      });
    }
  }

  Future<void> _persistUnreadFlag(bool hasUnread) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('official_template_messages.has_unread', hasUnread);
    } catch (_) {}
  }

  Future<void> _markRead(_TemplateMessage msg) async {
    if (!msg.isUnread) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/me/official_template_messages/${msg.id}/read',
      );
      await http.post(uri, headers: await _hdr());
    } catch (_) {
      // Best-effort; UI is updated optimistically.
    }
  }

  Future<void> _openDeeplink(_TemplateMessage msg) async {
    final dl = msg.deeplink;
    if (dl == null || dl.isEmpty) return;
    final miniAppId = (dl['mini_app_id'] ?? '').toString().trim();
    if (miniAppId.isEmpty) return;
    final payloadRaw = dl['payload'];
    final payload =
        payloadRaw is Map ? payloadRaw.cast<String, dynamic>() : null;
    await _openMiniAppById(miniAppId, payload: payload);
  }

  Future<void> _openMiniAppById(
    String dl, {
    Map<String, dynamic>? payload,
  }) async {
    if (dl == 'payments' || dl == 'alias' || dl == 'merchant') {
      try {
        final sp = await SharedPreferences.getInstance();
        final walletId = sp.getString('wallet_id') ?? '';
        final devId = await CallSignalingClient.loadDeviceId();
        String? initialSection;
        String? contextLabel;
        final p = payload;
        if (p != null) {
          final rawSection = p['section'];
          final rawLabel = p['label'];
          if (rawSection is String && rawSection.trim().isNotEmpty) {
            initialSection = rawSection.trim();
          }
          if (rawLabel is String && rawLabel.trim().isNotEmpty) {
            contextLabel = rawLabel.trim();
          }
        }
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentsPage(
              widget.baseUrl,
              walletId,
              devId ?? 'device',
              initialSection: initialSection,
              contextLabel: contextLabel,
            ),
          ),
        );
      } catch (_) {}
      return;
    }
    final app = miniAppById(dl);
    if (app == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Open mini‑app: ${app.title(isArabic: L10n.of(context).isArabic)}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final hasUnread = _items.any((m) => m.isUnread);
    final q = _search.trim().toLowerCase();
    final items = q.isEmpty
        ? _items
        : _items
            .where((m) =>
                m.title.toLowerCase().contains(q) ||
                m.body.toLowerCase().contains(q) ||
                m.accountId.toLowerCase().contains(q))
            .toList(growable: false);

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'إشعارات الخدمات' : 'Service notifications',
        ),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          if (hasUnread)
            IconButton(
              tooltip: l.isArabic ? 'تحديد الكل كمقروء' : 'Mark all as read',
              icon: const Icon(Icons.done_all_outlined),
              onPressed: () async {
                final unread =
                    _items.where((m) => m.isUnread).toList(growable: false);
                if (unread.isEmpty) return;
                setState(() {
                  _items = _items
                      .map((m) => m.isUnread ? m.markReadLocally() : m)
                      .toList(growable: false);
                });
                await _persistUnreadFlag(false);
                for (final msg in unread) {
                  // Best-effort; ignore failures.
                  // ignore: discarded_futures
                  _markRead(msg);
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 8),
                      ShamellSearchBar(
                        hintText: l.isArabic ? 'بحث' : 'Search',
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _search = v),
                      ),
                      if (_items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              l.isArabic
                                  ? 'لا توجد رسائل من الحسابات الرسمية حتى الآن.'
                                  : 'No messages from official accounts yet.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            ),
                          ),
                        )
                      else if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l.isArabic ? 'لا توجد نتائج.' : 'No results found.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                        )
                      else
                        ShamellSection(
                          dividerIndent: 72,
                          dividerEndIndent: 16,
                          children: [
                            for (final m in items)
                              Builder(
                                builder: (ctx) {
                                  final isUnread = m.isUnread;
                                  final hasDeeplink = m.deeplink != null &&
                                      m.deeplink!.isNotEmpty;
                                  final ts = m.createdAtLabel;
                                  final leadIcon = hasDeeplink
                                      ? Icons.campaign_outlined
                                      : Icons.mail_outline;
                                  final leadColor = hasDeeplink
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFF8B5CF6);
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    onTap: () async {
                                      if (isUnread) {
                                        setState(() {
                                          _items = _items
                                              .map((x) => x.id == m.id
                                                  ? m.markReadLocally()
                                                  : x)
                                              .toList(growable: false);
                                        });
                                        await _persistUnreadFlag(
                                          _items.any((m) => m.isUnread),
                                        );
                                        // ignore: discarded_futures
                                        _markRead(m);
                                      }
                                      if (hasDeeplink) {
                                        // ignore: discarded_futures
                                        _openDeeplink(m);
                                      }
                                    },
                                    leading: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ShamellLeadingIcon(
                                          icon: leadIcon,
                                          background: leadColor,
                                        ),
                                        if (isUnread)
                                          Positioned(
                                            right: -2,
                                            top: -2,
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFA5151),
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    title: Text(
                                      m.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isUnread
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (m.body.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              m.body,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            m.accountId,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              fontSize: 11,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: .70),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: ts.isEmpty
                                        ? chevron()
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                ts,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  fontSize: 11,
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: .55),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              chevron(),
                                            ],
                                          ),
                                  );
                                },
                              ),
                          ],
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}

class _TemplateMessage {
  final int id;
  final String accountId;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, dynamic>? deeplink;

  const _TemplateMessage({
    required this.id,
    required this.accountId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
    required this.deeplink,
  });

  factory _TemplateMessage.fromJson(Map<String, dynamic> j) {
    DateTime? _parseTs(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }

    Map<String, dynamic>? dl;
    final rawDl = j['deeplink_json'];
    if (rawDl is Map) {
      dl = rawDl.cast<String, dynamic>();
    }
    return _TemplateMessage(
      id: (j['id'] as num?)?.toInt() ?? 0,
      accountId: (j['account_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      createdAt: _parseTs((j['created_at'] ?? '').toString()),
      readAt: _parseTs((j['read_at'] ?? '').toString()),
      deeplink: dl,
    );
  }

  bool get isUnread => readAt == null;

  String get createdAtLabel {
    final t = createdAt;
    if (t == null) return '';
    final dt = t.toLocal();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  _TemplateMessage markReadLocally() {
    if (!isUnread) return this;
    return _TemplateMessage(
      id: id,
      accountId: accountId,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: DateTime.now(),
      deeplink: deeplink,
    );
  }
}
