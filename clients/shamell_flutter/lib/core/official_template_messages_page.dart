import 'dart:convert';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show LoginPage;

import 'base_url.dart';
import 'chat/chat_service.dart';
import 'design_tokens.dart';
import 'device_binding_reauth.dart';
import 'l10n.dart';
import 'unsupported_module_nav.dart';
import 'call_signaling.dart';
import 'payments/payments_shell.dart';
import 'shamell_loading_shimmer.dart';
import 'shamell_ui.dart';
import 'safe_set_state.dart';

const Duration _officialTemplateMessagesRequestTimeout = Duration(seconds: 15);
const int _officialTemplateMessagesPageSize = 50;

String _officialTemplateQueueLabel(String queue, bool isArabic) {
  switch (queue) {
    case 'unread':
      return isArabic ? 'غير مقروءة' : 'Unread';
    case 'actionable':
      return isArabic ? 'إجراء' : 'Actions';
    case 'service':
      return isArabic ? 'خدمة' : 'Service';
    case 'payments':
      return isArabic ? 'دفع' : 'Pay';
    case 'mobility':
      return isArabic ? 'تنقل' : 'Mobility';
    default:
      return isArabic ? 'الكل' : 'All';
  }
}

class OfficialTemplateMessagesPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? httpClient;

  const OfficialTemplateMessagesPage({
    super.key,
    required this.baseUrl,
    this.httpClient,
  });

  @override
  State<OfficialTemplateMessagesPage> createState() =>
      _OfficialTemplateMessagesPageState();
}

class _OfficialTemplateMessagesPageState
    extends State<OfficialTemplateMessagesPage>
    with SafeSetStateMixin<OfficialTemplateMessagesPage> {
  final ChatLocalStore _store = ChatLocalStore();
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String _error = '';
  List<_TemplateMessage> _items = const <_TemplateMessage>[];
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _selectedQueue = 'all';

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    _load();
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: jsonBody);
  }

  Uri? _templateMessagesUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>[
        'me',
        'official_template_messages',
        ...pathSegments,
      ],
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage() {
    return L10n.of(context).isArabic
        ? 'عنوان الخادم غير صالح.'
        : 'Invalid server URL.';
  }

  Future<void> _load() => _loadPage(reset: true);

  Future<void> _loadMore() => _loadPage(reset: false);

  Future<void> _loadPage({required bool reset}) async {
    if (!reset) {
      if (_loading || _loadingMore || !_hasMore || _items.isEmpty) {
        return;
      }
      setState(() {
        _loadingMore = true;
      });
    } else {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _hasMore = false;
        _error = '';
        _items = const <_TemplateMessage>[];
      });
    }
    try {
      final queryParameters = <String, String>{
        'unread_only': 'false',
        'limit': '$_officialTemplateMessagesPageSize',
      };
      if (!reset && _items.isNotEmpty) {
        final last = _items.last;
        final beforeCreatedAt = last.createdAt?.toUtc().toIso8601String();
        if (beforeCreatedAt != null &&
            beforeCreatedAt.isNotEmpty &&
            last.id > 0) {
          queryParameters['before_created_at'] = beforeCreatedAt;
          queryParameters['before_id'] = '${last.id}';
        }
      }
      final uri = _templateMessagesUri(
        pathSegments: const <String>[],
        queryParameters: queryParameters,
      );
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = _invalidServerUrlMessage();
        });
        return;
      }
      final r = await _http
          .get(uri, headers: await _hdr())
          .timeout(_officialTemplateMessagesRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
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
      final merged = reset ? items : _mergeTemplateMessages(_items, items);
      setState(() {
        _items = merged;
        _loading = false;
        _loadingMore = false;
        _hasMore = items.length >= _officialTemplateMessagesPageSize;
      });
      await _persistUnreadFlag(merged.any((m) => m.isUnread));
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      final detail = sanitizeExceptionForUi(error: e);
      if (reset) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = detail;
        });
      } else {
        setState(() {
          _loadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(detail)),
        );
      }
    }
  }

  List<_TemplateMessage> _mergeTemplateMessages(
    List<_TemplateMessage> current,
    List<_TemplateMessage> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final merged = <_TemplateMessage>[...current];
    final seen = current.map((m) => m.id).toSet();
    for (final message in incoming) {
      if (seen.add(message.id)) {
        merged.add(message);
      }
    }
    return merged;
  }

  Future<void> _persistUnreadFlag(bool hasUnread) async {
    try {
      await _store.saveServiceNotificationsHasUnread(
        hasUnread,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
  }

  Future<void> _markRead(_TemplateMessage msg) async {
    if (!msg.isUnread) return;
    try {
      final uri = _templateMessagesUri(
        pathSegments: <String>['${msg.id}', 'read'],
      );
      if (uri == null) {
        return;
      }
      final r = await _http
          .post(uri, headers: await _hdr())
          .timeout(_officialTemplateMessagesRequestTimeout);
      await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      );
    } catch (e) {
      await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      );
      // Best-effort; UI is updated optimistically.
    }
  }

  Future<void> _openDeeplink(_TemplateMessage msg) async {
    final dl = msg.deeplink;
    if (dl == null || dl.isEmpty) return;
    final miniProgramId = _templateMessageMiniProgramId(dl);
    if (miniProgramId.isEmpty) return;
    final payloadRaw = dl['payload'];
    final payload =
        payloadRaw is Map ? payloadRaw.cast<String, dynamic>() : null;
    await _openModuleAppById(miniProgramId, payload: payload);
  }

  Future<void> _openModuleAppById(
    String dl, {
    Map<String, dynamic>? payload,
  }) async {
    if (dl == 'payments' || dl == 'alias' || dl == 'merchant') {
      try {
        final walletId =
            await loadStoredWalletId(baseUrlOverride: widget.baseUrl) ?? '';
        final devId = await CallSignalingClient.loadDeviceId(
          baseUrlOverride: widget.baseUrl,
        );
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
    if (!mounted) return;
    showUnsupportedModuleShortcutSnackBar(context);
  }

  bool _matchesQueue(_TemplateMessage message, String queue) {
    switch (queue) {
      case 'unread':
        return message.isUnread;
      case 'actionable':
        return message.hasActionableDeeplink;
      case 'service':
        return message.kind.toLowerCase() == 'service';
      case 'payments':
        return message.category == _TemplateMessageCategory.payments;
      case 'mobility':
        return message.category == _TemplateMessageCategory.mobility;
      default:
        return true;
    }
  }

  int _queueCount(String queue) {
    return _items.where((message) => _matchesQueue(message, queue)).length;
  }

  IconData _queueIcon(String queue) {
    switch (queue) {
      case 'unread':
        return Icons.mark_email_unread_outlined;
      case 'actionable':
        return Icons.open_in_new_outlined;
      case 'service':
        return Icons.notifications_none_outlined;
      case 'payments':
        return Icons.account_balance_wallet_outlined;
      case 'mobility':
        return Icons.route_outlined;
      default:
        return Icons.all_inbox_outlined;
    }
  }

  IconData _messageIcon(_TemplateMessage message) {
    switch (message.category) {
      case _TemplateMessageCategory.payments:
        return Icons.account_balance_wallet_outlined;
      case _TemplateMessageCategory.mobility:
        return Icons.route_outlined;
      case _TemplateMessageCategory.miniProgram:
        return Icons.widgets_outlined;
      case _TemplateMessageCategory.official:
        return Icons.verified_outlined;
      case _TemplateMessageCategory.service:
        return Icons.mail_outline;
    }
  }

  Color _messageColor(_TemplateMessage message) {
    switch (message.category) {
      case _TemplateMessageCategory.payments:
        return Tokens.colorPayments;
      case _TemplateMessageCategory.mobility:
        return const Color(0xFF0EA5E9);
      case _TemplateMessageCategory.miniProgram:
        return const Color(0xFF7C3AED);
      case _TemplateMessageCategory.official:
        return const Color(0xFF2563EB);
      case _TemplateMessageCategory.service:
        return const Color(0xFF8B5CF6);
    }
  }

  Widget _queuePill({
    required ThemeData theme,
    required L10n l,
    required String queue,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final selected = _selectedQueue == queue;
    final count = queue == 'all' ? _items.length : _queueCount(queue);
    final bg = selected
        ? ShamellPalette.green
        : (isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .32)
            : Colors.white);
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _selectedQueue = queue),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? ShamellPalette.green
                : theme.dividerColor.withValues(alpha: isDark ? .45 : .80),
            width: .7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _queueIcon(queue),
              size: 16,
              color: selected
                  ? Colors.white
                  : theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
            const SizedBox(width: 6),
            Text(
              _officialTemplateQueueLabel(queue, l.isArabic),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              count > 99 ? '99+' : '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: selected
                    ? Colors.white.withValues(alpha: .86)
                    : theme.colorScheme.onSurface.withValues(alpha: .54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryPanel({
    required ThemeData theme,
    required L10n l,
    required bool hasUnread,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final unreadCount = _queueCount('unread');
    final actionableCount = _queueCount('actionable');
    final serviceCount = _queueCount('service');
    final detail = l.isArabic
        ? '$unreadCount غير مقروءة · $actionableCount إجراءات · $serviceCount خدمة'
        : '$unreadCount unread · $actionableCount actions · $serviceCount service';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .46 : .82),
          width: .7,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Tokens.colorPayments.withValues(alpha: isDark ? .20 : .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: Tokens.colorPayments,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'إشعارات الخدمات' : 'Service inbox',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text(l.isArabic ? 'قراءة الكل' : 'Read all'),
            )
          else
            Text(
              l.isArabic ? '${_items.length} عنصر' : '${_items.length} items',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: Tokens.colorPayments,
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyPanel({
    required ThemeData theme,
    required L10n l,
    required bool filtered,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 28),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .46 : .82),
          width: .7,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.notifications_none_outlined,
              color: theme.colorScheme.onSurface.withValues(alpha: .42),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            filtered
                ? (l.isArabic
                    ? 'لا توجد إشعارات تطابق البحث أو الطابور الحالي.'
                    : 'No notifications match the current search or queue.')
                : (l.isArabic
                    ? 'لا توجد رسائل من الحسابات الرسمية حتى الآن.'
                    : 'No service notifications yet.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .72),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllRead() async {
    final unread = _items.where((m) => m.isUnread).toList(growable: false);
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
    final items = _items
        .where((m) => _matchesQueue(m, _selectedQueue))
        .where((m) =>
            q.isEmpty ||
            m.title.toLowerCase().contains(q) ||
            m.body.toLowerCase().contains(q))
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
              onPressed: _markAllRead,
            ),
        ],
      ),
      body: _loading
          ? const ShamellSkeletonList(itemCount: 6)
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
                        hintText: l.isArabic
                            ? 'بحث في إشعارات الخدمات'
                            : 'Search service notifications',
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _search = v),
                      ),
                      _summaryPanel(theme: theme, l: l, hasUnread: hasUnread),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 38,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (_, i) {
                            final queue = const <String>[
                              'all',
                              'unread',
                              'actionable',
                              'payments',
                              'mobility',
                              'service',
                            ][i];
                            return _queuePill(
                              theme: theme,
                              l: l,
                              queue: queue,
                            );
                          },
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemCount: 6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          l.isArabic
                              ? 'عرض ${items.length} من ${_items.length} إشعار'
                              : 'Showing ${items.length} of ${_items.length} notifications',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        _emptyPanel(theme: theme, l: l, filtered: false)
                      else if (items.isEmpty)
                        _emptyPanel(theme: theme, l: l, filtered: true)
                      else
                        ShamellSection(
                          dividerIndent: 72,
                          dividerEndIndent: 16,
                          children: [
                            for (final m in items)
                              Builder(
                                builder: (ctx) {
                                  final isUnread = m.isUnread;
                                  final hasDeeplink = m.hasActionableDeeplink;
                                  final ts = m.createdAtLabel;
                                  final leadIcon = _messageIcon(m);
                                  final leadColor = _messageColor(m);
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
                                        if (m.kindLabel(l).isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  m.kindLabel(l),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    fontSize: 11,
                                                    color: theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: .70),
                                                  ),
                                                ),
                                                if (hasDeeplink)
                                                  Text(
                                                    l.isArabic
                                                        ? 'إجراء'
                                                        : 'Action',
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color:
                                                          Tokens.colorPayments,
                                                    ),
                                                  ),
                                              ],
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
                      if (_loadingMore || _hasMore)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _loadMore,
                                    child: Text(
                                      l.isArabic ? 'تحميل المزيد' : 'Load more',
                                    ),
                                  ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}

enum _TemplateMessageCategory {
  service,
  payments,
  mobility,
  miniProgram,
  official,
}

class _TemplateMessage {
  final int id;
  final String kind;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, dynamic>? deeplink;

  const _TemplateMessage({
    required this.id,
    required this.kind,
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
      kind: (j['kind'] ?? '').toString().trim(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      createdAt: _parseTs((j['created_at'] ?? '').toString()),
      readAt: _parseTs((j['read_at'] ?? '').toString()),
      deeplink: dl,
    );
  }

  bool get isUnread => readAt == null;

  bool get hasActionableDeeplink {
    final dl = deeplink;
    if (dl == null || dl.isEmpty) return false;
    return _templateMessageMiniProgramId(dl).isNotEmpty;
  }

  String get moduleAppId {
    final dl = deeplink;
    if (dl == null || dl.isEmpty) return '';
    return _templateMessageMiniProgramId(dl).toLowerCase();
  }

  _TemplateMessageCategory get category {
    final module = moduleAppId;
    if (module == 'payments' ||
        module == 'pay' ||
        module == 'wallet' ||
        module == 'alias' ||
        module == 'merchant') {
      return _TemplateMessageCategory.payments;
    }
    if (module == 'ride' ||
        module == 'taxi' ||
        module == 'coach' ||
        module == 'bus' ||
        module == 'mobility') {
      return _TemplateMessageCategory.mobility;
    }
    if (module == 'mini_programs' ||
        module == 'miniapps' ||
        module == 'green_paket') {
      return _TemplateMessageCategory.miniProgram;
    }
    if (module == 'official' || module == 'official_accounts') {
      return _TemplateMessageCategory.official;
    }
    return _TemplateMessageCategory.service;
  }

  String kindLabel(L10n l) {
    switch (category) {
      case _TemplateMessageCategory.payments:
        return l.isArabic ? 'سرتشات باي' : 'SyrChat Pay';
      case _TemplateMessageCategory.mobility:
        return l.isArabic ? 'تنقل' : 'Mobility';
      case _TemplateMessageCategory.miniProgram:
        return l.isArabic ? 'برنامج مصغّر' : 'Mini Program';
      case _TemplateMessageCategory.official:
        return l.isArabic ? 'حساب رسمي' : 'Official account';
      case _TemplateMessageCategory.service:
        return l.isArabic ? 'إشعار خدمة' : 'Service notification';
    }
  }

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
      kind: kind,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: DateTime.now(),
      deeplink: deeplink,
    );
  }
}

String _templateMessageMiniProgramId(Map<String, dynamic> dl) {
  for (final key in const <String>[
    'mini_program_id',
    'module_app_id',
    'mini_app_id',
    'app_id',
  ]) {
    final value = (dl[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}
