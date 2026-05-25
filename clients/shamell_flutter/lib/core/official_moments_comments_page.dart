import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show LoginPage;

import 'access_platform_contracts.dart';
import 'account_privilege_store.dart';
import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'l10n.dart';
import 'safe_set_state.dart';
import 'shamell_loading_shimmer.dart';
import 'shamell_moments_page.dart';

const Duration _officialMomentsCommentsRequestTimeout = Duration(seconds: 15);
const int _officialMomentsCommentsPageSize = 200;

String _officialCommentQueueLabel(String queue, bool isArabic) {
  switch (queue) {
    case 'customer':
      return isArabic ? 'العملاء' : 'Customer';
    case 'official':
      return isArabic ? 'الحساب الرسمي' : 'Official';
    case 'replies':
      return isArabic ? 'الردود' : 'Replies';
    default:
      return isArabic ? 'الكل' : 'All';
  }
}

class OfficialMomentsCommentsPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final http.Client? httpClient;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;

  const OfficialMomentsCommentsPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    this.httpClient,
    this.privilegeSnapshotOverride,
  });

  @override
  State<OfficialMomentsCommentsPage> createState() =>
      _OfficialMomentsCommentsPageState();
}

class _OfficialMomentsCommentsPageState
    extends State<OfficialMomentsCommentsPage>
    with SafeSetStateMixin<OfficialMomentsCommentsPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loading = true;
  bool _loadingPrivileges = true;
  bool _readAccessAllowed = false;
  bool _writeAccessAllowed = false;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  bool _resultsMayBeTruncated = false;
  final TextEditingController _searchController = TextEditingController();
  String _selectedQueue = 'all';

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    _loadPrivilegesAndComments();
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    _searchController.dispose();
    super.dispose();
  }

  bool _isOfficialComment(Map<String, dynamic> comment) {
    final userKey = (comment['user_key'] ?? '').toString().trim().toLowerCase();
    return userKey.startsWith('official:');
  }

  bool _isReplyComment(Map<String, dynamic> comment) {
    final rawReplyToId = comment['reply_to_id'];
    if (rawReplyToId is num) {
      return rawReplyToId.toInt() > 0;
    }
    final parsed = int.tryParse(rawReplyToId?.toString() ?? '');
    return (parsed ?? 0) > 0;
  }

  bool _matchesQueue(Map<String, dynamic> comment, String queue) {
    switch (queue) {
      case 'customer':
        return !_isOfficialComment(comment);
      case 'official':
        return _isOfficialComment(comment);
      case 'replies':
        return _isReplyComment(comment);
      default:
        return true;
    }
  }

  bool _matchesSearch(Map<String, dynamic> comment, String query) {
    if (query.isEmpty) return true;
    final commentId = (comment['id'] ?? '').toString().toLowerCase();
    final postId = (comment['post_id'] ?? '').toString().toLowerCase();
    final replyToId = (comment['reply_to_id'] ?? '').toString().toLowerCase();
    final text = (comment['text'] ?? '').toString().toLowerCase();
    final userKey = (comment['user_key'] ?? '').toString().toLowerCase();
    final createdAt = (comment['created_at'] ?? '').toString().toLowerCase();
    return commentId.contains(query) ||
        postId.contains(query) ||
        replyToId.contains(query) ||
        text.contains(query) ||
        userKey.contains(query) ||
        createdAt.contains(query);
  }

  int _queueCount(String queue) {
    return _items.where((comment) => _matchesQueue(comment, queue)).length;
  }

  Future<void> _loadPrivilegesAndComments() async {
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

  Uri? _commentsUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: pathSegments,
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage() {
    return L10n.of(context).isArabic
        ? 'عنوان الخادم غير صالح.'
        : 'Invalid server URL.';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = const <Map<String, dynamic>>[];
      _resultsMayBeTruncated = false;
    });
    try {
      final uri = _commentsUri(
        pathSegments: const <String>['moments', 'admin', 'comments'],
        queryParameters: <String, String>{
          'official_account_id': widget.accountId,
          'limit': '$_officialMomentsCommentsPageSize',
        },
      );
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = _invalidServerUrlMessage();
        });
        return;
      }
      final r = await _http
          .get(uri, headers: await _hdr())
          .timeout(_officialMomentsCommentsRequestTimeout);
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
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        items.add(e.cast<String, dynamic>());
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _resultsMayBeTruncated =
            items.length >= _officialMomentsCommentsPageSize;
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
      setState(() {
        _loading = false;
        _error = sanitizeExceptionForUi(error: e);
      });
    }
  }

  Future<void> _deleteComment(int commentId) async {
    if (!_writeAccessAllowed) return;
    final l = L10n.of(context);
    try {
      final uri = _commentsUri(
        pathSegments: <String>[
          'moments',
          'admin',
          'comments',
          '$commentId',
        ],
      );
      if (uri == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_invalidServerUrlMessage())),
        );
        return;
      }
      final r = await _http
          .delete(uri, headers: await _hdr(jsonBody: true))
          .timeout(_officialMomentsCommentsRequestTimeout);
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
                  ? 'تعذّر حذف التعليق (HTTP ${r.statusCode}).'
                  : 'Failed to delete comment (HTTP ${r.statusCode}).',
            ),
          ),
        );
        return;
      }
      setState(() {
        _items = _items.where((c) => (c['id'] ?? 0) != commentId).toList();
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
                ? 'تعذّر حذف التعليق: $detail'
                : 'Failed to delete comment: $detail',
          ),
        ),
      );
    }
  }

  Future<void> _replyAsOfficial(
    int postId, {
    int? replyToId,
  }) async {
    if (!_writeAccessAllowed) return;
    final l = L10n.of(context);
    final ctrl = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
              top: 12,
            ),
            child: Material(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isArabic ? 'رد كحساب رسمي' : 'Reply as official account',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: l.isArabic ? 'نص الرد' : 'Reply text',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final text = ctrl.text.trim();
                          if (text.isEmpty) return;
                          Navigator.of(ctx).pop();
                          await _sendOfficialReply(
                            postId: postId,
                            text: text,
                            replyToId: replyToId,
                          );
                        },
                        child: Text(
                          l.isArabic ? 'إرسال' : 'Send',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _sendOfficialReply({
    required int postId,
    required String text,
    int? replyToId,
  }) async {
    if (!_writeAccessAllowed) return;
    final l = L10n.of(context);
    try {
      final uri = _commentsUri(
        pathSegments: <String>[
          'moments',
          'admin',
          'posts',
          '$postId',
          'comment',
        ],
      );
      if (uri == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_invalidServerUrlMessage())),
        );
        return;
      }
      final body = <String, dynamic>{
        'text': text,
        'official_account_id': widget.accountId,
      };
      if (replyToId != null) {
        body['reply_to_id'] = replyToId;
      }
      final r = await _http
          .post(
            uri,
            headers: await _hdr(jsonBody: true),
            body: jsonEncode(body),
          )
          .timeout(_officialMomentsCommentsRequestTimeout);
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
                  ? 'تعذّر إرسال الرد (HTTP ${r.statusCode}).'
                  : 'Failed to send reply (HTTP ${r.statusCode}).',
            ),
          ),
        );
        return;
      }
      await _load();
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
                ? 'تعذّر إرسال الرد: $detail'
                : 'Failed to send reply: $detail',
          ),
        ),
      );
    }
  }

  void _openInMoments(int _) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShamellMomentsPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  @visibleForTesting
  void debugShowRemovedMomentsEntry() {
    _openInMoments(0);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final title =
        l.isArabic ? 'تعليقات المنشورات (إدارة)' : 'Feed comments (admin)';
    final searchQuery = _searchController.text.trim().toLowerCase();
    final visibleItems = _items
        .where((comment) => _matchesQueue(comment, _selectedQueue))
        .where((comment) => _matchesSearch(comment, searchQuery))
        .toList(growable: false);
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const ShamellSkeletonList(itemCount: 6),
      );
    }
    if (!_readAccessAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l.isArabic
                  ? 'هذا الحساب غير مخوّل للوصول إلى تعليقات هذا الحساب الرسمي.'
                  : 'Your account is not allowed to access these official feed comments.',
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
        title: Text(title),
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText:
                          l.isArabic ? 'ابحث في التعليقات' : 'Search comments',
                      hintText: l.isArabic
                          ? 'النص أو الكاتب أو رقم المنشور أو التعليق'
                          : 'Text, author, post, or comment id',
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
                          '${l.isArabic ? 'العملاء' : 'Customer'} ${_queueCount('customer')}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${l.isArabic ? 'الحساب الرسمي' : 'Official'} ${_queueCount('official')}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${l.isArabic ? 'الردود' : 'Replies'} ${_queueCount('replies')}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.isArabic ? 'الطابور' : 'Queue',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final queue in const <String>[
                        'all',
                        'customer',
                        'official',
                        'replies',
                      ])
                        ChoiceChip(
                          label: Text(
                            '${_officialCommentQueueLabel(queue, l.isArabic)} (${queue == 'all' ? _items.length : _queueCount(queue)})',
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
                        ? 'عرض ${visibleItems.length} من ${_items.length} تعليق'
                        : 'Showing ${visibleItems.length} of ${_items.length} comments',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  if (!_loading &&
                      _resultsMayBeTruncated &&
                      _error == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.isArabic
                          ? 'يتم عرض أحدث 200 تعليق فقط في هذا العرض.'
                          : 'Showing only the latest 200 comments in this view.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .72),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (!_loading && _items.isEmpty && _error == null)
                    Text(
                      l.isArabic
                          ? 'لا توجد تعليقات حديثة على منشورات هذا الحساب الرسمي.'
                          : 'There are no recent feed comments for this official account.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    )
                  else if (!_loading && visibleItems.isEmpty && _error == null)
                    Text(
                      l.isArabic
                          ? 'لا توجد تعليقات تطابق البحث أو الطابور الحالي.'
                          : 'No comments match the current search or queue.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    )
                  else ...[
                    for (var i = 0; i < visibleItems.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(
                        builder: (ctx) {
                          final c = visibleItems[i];
                          final cid = (c['id'] as num?)?.toInt() ??
                              int.tryParse((c['id'] ?? '').toString()) ??
                              0;
                          final pid = (c['post_id'] as num?)?.toInt() ??
                              int.tryParse((c['post_id'] ?? '').toString()) ??
                              0;
                          final text = (c['text'] ?? '').toString();
                          final ts = (c['created_at'] ?? '').toString();
                          final userKey =
                              (c['user_key'] ?? '').toString().trim();
                          String authorLabel = userKey;
                          if (userKey.startsWith('official:')) {
                            final idx = userKey.indexOf(':');
                            final suffix = idx >= 0 && idx + 1 < userKey.length
                                ? userKey.substring(idx + 1)
                                : userKey;
                            authorLabel = 'Official · $suffix';
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text.isEmpty ? '(empty)' : text,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l.isArabic
                                      ? 'المنشور #$pid · التعليق #$cid'
                                      : 'Post #$pid · Comment #$cid',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                                if (authorLabel.isNotEmpty)
                                  Text(
                                    authorLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: .75),
                                    ),
                                  ),
                                if (ts.isNotEmpty)
                                  Text(
                                    ts,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: .60),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    TextButton(
                                      onPressed: () => _openInMoments(pid),
                                      child: Text(
                                        l.isArabic ? 'فتح' : 'Open',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _writeAccessAllowed
                                          ? () => _replyAsOfficial(
                                                pid,
                                                replyToId: cid,
                                              )
                                          : null,
                                      child: Text(
                                        l.isArabic
                                            ? 'رد كحساب رسمي'
                                            : 'Reply as service',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _writeAccessAllowed
                                          ? () => _deleteComment(cid)
                                          : null,
                                      child: Text(
                                        l.isArabic ? 'حذف' : 'Delete',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
