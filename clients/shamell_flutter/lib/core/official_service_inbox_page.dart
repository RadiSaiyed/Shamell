import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show LoginPage;

import 'access_platform_contracts.dart';
import 'account_privilege_store.dart';
import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'l10n.dart';
import 'shamell_empty_state.dart';
import 'shamell_loading_shimmer.dart';
import 'chat/shamell_chat_page.dart';
import 'http_error.dart';
import 'payments/payments_idempotency.dart';
import 'safe_set_state.dart';

const Duration _officialServiceInboxRequestTimeout = Duration(seconds: 15);
const int _officialServiceInboxPageSize = 100;

String _officialInboxQueueLabel(String queue, bool isArabic) {
  switch (queue) {
    case 'unread':
      return isArabic ? 'غير مقروءة' : 'Unread';
    case 'open':
      return isArabic ? 'مفتوحة' : 'Open';
    case 'closed':
      return isArabic ? 'مغلقة' : 'Closed';
    default:
      return isArabic ? 'الكل' : 'All';
  }
}

class OfficialServiceInboxPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final http.Client? httpClient;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;

  const OfficialServiceInboxPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    this.httpClient,
    this.privilegeSnapshotOverride,
  });

  @override
  State<OfficialServiceInboxPage> createState() =>
      _OfficialServiceInboxPageState();
}

class _OfficialServiceInboxPageState extends State<OfficialServiceInboxPage>
    with SafeSetStateMixin<OfficialServiceInboxPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loading = true;
  bool _loadingPrivileges = true;
  bool _readAccessAllowed = false;
  bool _writeAccessAllowed = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  List<_ServiceSession> _items = const <_ServiceSession>[];
  final TextEditingController _searchController = TextEditingController();
  String _selectedQueue = 'all';
  final Map<int, String> _pendingMarkReadIdempotencyKeys = <int, String>{};
  final Map<int, String> _pendingCloseSessionIdempotencyKeys = <int, String>{};

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    _loadPrivilegesAndInbox();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _loadPrivilegesAndInbox() async {
    final snapshot = widget.privilegeSnapshotOverride ??
        await loadAccountPrivilegeSnapshotForBaseUrl(widget.baseUrl);
    if (!mounted) return;
    final readAccess = shamellHasOfficialDashboardReadSnapshotAccess(
      snapshot,
      widget.accountId,
    );
    final writeAccess = shamellHasOfficialDashboardWriteSnapshotAccess(
      snapshot,
      widget.accountId,
    );
    setState(() {
      _loadingPrivileges = false;
      _readAccessAllowed = readAccess;
      _writeAccessAllowed = writeAccess;
      _loading = readAccess;
    });
    if (!readAccess) {
      return;
    }
    await _load();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: jsonBody);
  }

  Uri? _serviceInboxUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>[
        'admin',
        'official_accounts',
        widget.accountId,
        ...pathSegments,
      ],
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage({bool? isArabic}) {
    final arabic = isArabic ?? L10n.of(context).isArabic;
    return arabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
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
        _error = null;
        _items = const <_ServiceSession>[];
      });
    }
    try {
      final queryParameters = <String, String>{
        'limit': '$_officialServiceInboxPageSize',
      };
      if (!reset && _items.isNotEmpty) {
        final last = _items.last;
        final beforeTs = last.cursorTs?.toUtc().toIso8601String();
        if (beforeTs != null && beforeTs.isNotEmpty && last.id > 0) {
          queryParameters['before_ts'] = beforeTs;
          queryParameters['before_id'] = '${last.id}';
        }
      }
      final uri = _serviceInboxUri(
        pathSegments: const <String>['service_inbox'],
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
          .timeout(_officialServiceInboxRequestTimeout);
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
      if (decoded is Map && decoded['sessions'] is List) {
        raw = decoded['sessions'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <_ServiceSession>[];
      for (final e in raw) {
        if (e is! Map) continue;
        items.add(_ServiceSession.fromJson(e.cast<String, dynamic>()));
      }
      if (!mounted) return;
      final merged = reset ? items : _mergeServiceSessions(_items, items);
      setState(() {
        _items = merged;
        _loading = false;
        _loadingMore = false;
        _hasMore = items.length >= _officialServiceInboxPageSize;
      });
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

  List<_ServiceSession> _mergeServiceSessions(
    List<_ServiceSession> current,
    List<_ServiceSession> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final merged = <_ServiceSession>[...current];
    final seen = current.map((session) => session.id).toSet();
    for (final session in incoming) {
      if (seen.add(session.id)) {
        merged.add(session);
      }
    }
    return merged;
  }

  bool _matchesQueue(_ServiceSession session, String queue) {
    final isClosed = session.status.trim().toLowerCase() == 'closed';
    switch (queue) {
      case 'unread':
        return session.unreadByOperator;
      case 'open':
        return !isClosed;
      case 'closed':
        return isClosed;
      default:
        return true;
    }
  }

  bool _matchesSearch(_ServiceSession session, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return session.customerPhone.toLowerCase().contains(normalized) ||
        session.status.toLowerCase().contains(normalized) ||
        (session.chatPeerId ?? '').toLowerCase().contains(normalized);
  }

  int _queueCount(String queue) {
    return _items.where((session) => _matchesQueue(session, queue)).length;
  }

  Future<void> _markRead(_ServiceSession s) async {
    if (!_writeAccessAllowed) return;
    if (!s.unreadByOperator) return;
    try {
      final uri = _serviceInboxUri(
        pathSegments: <String>['service_inbox', '${s.id}', 'mark_read'],
      );
      if (uri == null) {
        return;
      }
      final reqHeaders = await _hdr(jsonBody: true);
      final idempotencyKey = _pendingMarkReadIdempotencyKeys.putIfAbsent(
        s.id,
        () => newPaymentsIdempotencyKey('official-service-mark-read'),
      );
      reqHeaders['Idempotency-Key'] = idempotencyKey;
      final r = await _http
          .post(uri, headers: reqHeaders)
          .timeout(_officialServiceInboxRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _pendingMarkReadIdempotencyKeys.remove(s.id);
      }
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
      // Best-effort; UI is optimistic.
    }
  }

  Future<void> _closeSession(_ServiceSession s) async {
    if (!_writeAccessAllowed) return;
    final l = L10n.of(context);
    try {
      final uri = _serviceInboxUri(
        pathSegments: <String>['service_inbox', '${s.id}', 'close'],
      );
      if (uri == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_invalidServerUrlMessage(isArabic: l.isArabic))),
        );
        return;
      }
      final reqHeaders = await _hdr(jsonBody: true);
      final idempotencyKey = _pendingCloseSessionIdempotencyKeys.putIfAbsent(
        s.id,
        () => newPaymentsIdempotencyKey('official-service-close'),
      );
      reqHeaders['Idempotency-Key'] = idempotencyKey;
      final r = await _http
          .post(uri, headers: reqHeaders)
          .timeout(_officialServiceInboxRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر إغلاق الجلسة (HTTP ${r.statusCode}).'
                  : 'Failed to close session (HTTP ${r.statusCode}).',
            ),
          ),
        );
        return;
      }
      _pendingCloseSessionIdempotencyKeys.remove(s.id);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((it) => it.id == s.id
                ? it.copyWith(status: 'closed', unreadByOperator: false)
                : it)
            .toList();
      });
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      final detail = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر إغلاق الجلسة: $detail'
                : 'Failed to close session: $detail',
          ),
        ),
      );
    }
  }

  Future<void> _sendTemplateMessage(_ServiceSession s) async {
    if (!_writeAccessAllowed) return;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String? pendingIdempotencyKey;
    bool submitting = false;
    String? error;
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
              left: 12, right: 12, top: 12, bottom: bottom + 12),
          child: Material(
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (ctx2, setStateSB) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic
                            ? 'إرسال رسالة خدمة لمرة واحدة'
                            : 'Send one‑time service message',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'العنوان' : 'Title',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bodyCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'نص الرسالة' : 'Message body',
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final title = titleCtrl.text.trim();
                                  final body = bodyCtrl.text.trim();
                                  if (title.isEmpty || body.isEmpty) {
                                    setStateSB(() {
                                      error = l.isArabic
                                          ? 'الرجاء إدخال عنوان ونص للرسالة.'
                                          : 'Please provide both a title and message body.';
                                    });
                                    return;
                                  }
                                  setStateSB(() {
                                    submitting = true;
                                    error = null;
                                  });
                                  try {
                                    final idempotencyKey =
                                        pendingIdempotencyKey ??=
                                            newPaymentsIdempotencyKey(
                                                'official-service');
                                    final uri = _serviceInboxUri(
                                      pathSegments: <String>[
                                        'service_inbox',
                                        '${s.id}',
                                        'template_messages',
                                      ],
                                    );
                                    if (uri == null) {
                                      setStateSB(() {
                                        submitting = false;
                                        error = _invalidServerUrlMessage(
                                          isArabic: l.isArabic,
                                        );
                                      });
                                      return;
                                    }
                                    final reqHeaders =
                                        await _hdr(jsonBody: true);
                                    reqHeaders['Idempotency-Key'] =
                                        idempotencyKey;
                                    final r = await _http
                                        .post(
                                          uri,
                                          headers: reqHeaders,
                                          body: jsonEncode(<String, dynamic>{
                                            'title': title,
                                            'body': body,
                                          }),
                                        )
                                        .timeout(
                                            _officialServiceInboxRequestTimeout);
                                    if (r.statusCode < 200 ||
                                        r.statusCode >= 300) {
                                      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
                                        context,
                                        statusCode: r.statusCode,
                                        rawBody: r.body,
                                        loginPageBuilder: (_) =>
                                            const LoginPage(),
                                      )) {
                                        return;
                                      }
                                      setStateSB(() {
                                        submitting = false;
                                        error = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                      });
                                      return;
                                    }
                                    if (!mounted) return;
                                    Navigator.of(ctx2).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          l.isArabic
                                              ? 'تم إرسال رسالة الخدمة.'
                                              : 'Service message sent.',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (await shamellForceReauthIfCriticalDeviceBindingDrift(
                                      context,
                                      error: e,
                                      loginPageBuilder: (_) =>
                                          const LoginPage(),
                                    )) {
                                      return;
                                    }
                                    setStateSB(() {
                                      submitting = false;
                                      error = sanitizeExceptionForUi(error: e);
                                    });
                                  }
                                },
                          child: submitting
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(l.isArabic ? 'إرسال' : 'Send'),
                        ),
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
    } finally {
      titleCtrl.dispose();
      bodyCtrl.dispose();
    }
  }

  void _openChat(_ServiceSession s) {
    final peerId = (s.chatPeerId ?? '').trim();
    if (peerId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShamellChatPage(
          baseUrl: widget.baseUrl,
          initialPeerId: peerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final visibleItems = _items
        .where((session) => _matchesQueue(session, _selectedQueue))
        .where((session) => _matchesSearch(session, _searchController.text))
        .toList(growable: false);
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'صندوق خدمة العملاء' : 'Customer service inbox',
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_readAccessAllowed) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'صندوق خدمة العملاء' : 'Customer service inbox',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l.isArabic
                  ? 'هذا الحساب غير مخوّل للوصول إلى صندوق خدمة هذا الحساب الرسمي.'
                  : 'Your account is not allowed to access this official service inbox.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'صندوق خدمة العملاء' : 'Customer service inbox',
        ),
      ),
      body: _loading
          ? const ShamellSkeletonList(itemCount: 6)
          : _error != null
              ? ShamellEmptyState.error(
                  title: _error!,
                  actionLabel: l.isArabic ? 'إعادة المحاولة' : 'Retry',
                  onAction: () => _load(),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'ابحث في الجلسات'
                              : 'Search sessions',
                          hintText: l.isArabic
                              ? 'الهاتف أو الحالة أو المعرّف'
                              : 'Phone, status, or peer id',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchController.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              '${l.isArabic ? 'المحمّل' : 'Loaded'} ${_items.length}',
                            ),
                          ),
                          Chip(
                            label: Text(
                              '${l.isArabic ? 'المفتوحة' : 'Open'} ${_queueCount('open')}',
                            ),
                          ),
                          Chip(
                            label: Text(
                              '${l.isArabic ? 'غير المقروءة' : 'Unread'} ${_queueCount('unread')}',
                            ),
                          ),
                          Chip(
                            label: Text(
                              '${l.isArabic ? 'المغلقة' : 'Closed'} ${_queueCount('closed')}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.isArabic ? 'الطابور' : 'Queue',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final queue in const <String>[
                            'all',
                            'unread',
                            'open',
                            'closed',
                          ])
                            ChoiceChip(
                              label: Text(
                                '${_officialInboxQueueLabel(queue, l.isArabic)} (${queue == 'all' ? _items.length : _queueCount(queue)})',
                              ),
                              selected: _selectedQueue == queue,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() {
                                  _selectedQueue = queue;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.isArabic
                            ? 'عرض ${visibleItems.length} من ${_items.length} جلسة'
                            : 'Showing ${visibleItems.length} of ${_items.length} sessions',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_items.isEmpty)
                        Center(
                          child: Text(
                            l.isArabic
                                ? 'لا توجد جلسات خدمة عملاء حتى الآن.'
                                : 'No customer-service sessions yet.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                        )
                      else if (visibleItems.isEmpty)
                        Center(
                          child: Text(
                            l.isArabic
                                ? 'لا توجد جلسات تطابق البحث أو الطابور الحالي.'
                                : 'No sessions match the current search or queue.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < visibleItems.length; i++) ...[
                          Builder(builder: (_) {
                            final s = visibleItems[i];
                            final isOpen =
                                (s.status.trim().toLowerCase() != 'closed');
                            return ListTile(
                              onTap: () {
                                if (_writeAccessAllowed && s.unreadByOperator) {
                                  setState(() {
                                    _items = _items
                                        .map(
                                          (it) => it.id == s.id
                                              ? it.copyWith(
                                                  unreadByOperator: false)
                                              : it,
                                        )
                                        .toList();
                                  });
                                  // ignore: discarded_futures
                                  _markRead(s);
                                }
                                _openChat(s);
                              },
                              leading: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    child: Icon(
                                      Icons.support_agent_outlined,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                  if (s.unreadByOperator)
                                    Positioned(
                                      right: -2,
                                      top: -2,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                s.customerPhone.isNotEmpty
                                    ? s.customerPhone
                                    : (l.isArabic
                                        ? 'عميل غير معروف'
                                        : 'Unknown customer'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                () {
                                  final ts = s.lastMessageLabel;
                                  final base = isOpen
                                      ? (l.isArabic ? 'مفتوحة' : 'Open')
                                      : (l.isArabic ? 'مغلقة' : 'Closed');
                                  if (ts.isEmpty) return base;
                                  return '$base · $ts';
                                }(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .70),
                                ),
                              ),
                              trailing: isOpen
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.mark_email_read_outlined,
                                          ),
                                          tooltip: l.isArabic
                                              ? 'إرسال رسالة خدمة'
                                              : 'Send service message',
                                          onPressed: _writeAccessAllowed
                                              ? () {
                                                  // ignore: discarded_futures
                                                  _sendTemplateMessage(s);
                                                }
                                              : null,
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                          tooltip: l.isArabic
                                              ? 'إغلاق الجلسة'
                                              : 'Close session',
                                          onPressed: _writeAccessAllowed
                                              ? () {
                                                  // ignore: discarded_futures
                                                  _closeSession(s);
                                                }
                                              : null,
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          }),
                          if (i + 1 < visibleItems.length)
                            const Divider(height: 1),
                        ],
                      if (_loadingMore || _hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
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
                    ],
                  ),
                ),
    );
  }
}

class _ServiceSession {
  final int id;
  final String customerPhone;
  final String? chatPeerId;
  final String status;
  final DateTime? lastMessageTs;
  final DateTime? cursorTs;
  final bool unreadByOperator;

  const _ServiceSession({
    required this.id,
    required this.customerPhone,
    required this.chatPeerId,
    required this.status,
    required this.lastMessageTs,
    required this.cursorTs,
    required this.unreadByOperator,
  });

  factory _ServiceSession.fromJson(Map<String, dynamic> j) {
    DateTime? _parseTs(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }

    return _ServiceSession(
      id: (j['id'] as num?)?.toInt() ?? 0,
      customerPhone: (j['customer_phone'] ?? '').toString(),
      chatPeerId: (j['chat_peer_id'] ?? '').toString().isEmpty
          ? null
          : (j['chat_peer_id'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      lastMessageTs: _parseTs((j['last_message_ts'] ?? '').toString()),
      cursorTs: _parseTs((j['cursor_ts'] ?? '').toString()),
      unreadByOperator: (j['unread_by_operator'] as bool?) ?? false,
    );
  }

  String get lastMessageLabel {
    final t = lastMessageTs;
    if (t == null) return '';
    final dt = t.toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  _ServiceSession copyWith({
    String? status,
    bool? unreadByOperator,
  }) {
    return _ServiceSession(
      id: id,
      customerPhone: customerPhone,
      chatPeerId: chatPeerId,
      status: status ?? this.status,
      lastMessageTs: lastMessageTs,
      cursorTs: cursorTs,
      unreadByOperator: unreadByOperator ?? this.unreadByOperator,
    );
  }
}
