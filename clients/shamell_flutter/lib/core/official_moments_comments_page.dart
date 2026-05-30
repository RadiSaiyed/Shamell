import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'moments_page.dart';

class OfficialMomentsCommentsPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final String accountName;

  const OfficialMomentsCommentsPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    required this.accountName,
  });

  @override
  State<OfficialMomentsCommentsPage> createState() =>
      _OfficialMomentsCommentsPageState();
}

class _OfficialMomentsCommentsPageState
    extends State<OfficialMomentsCommentsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

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
      _error = null;
      _items = const <Map<String, dynamic>>[];
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/admin/comments')
          .replace(queryParameters: <String, String>{
        'official_account_id': widget.accountId,
        'limit': '200',
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = sanitizeExceptionForUi(error: e);
      });
    }
  }

  Future<void> _deleteComment(int commentId) async {
    final l = L10n.of(context);
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/moments/admin/comments/$commentId');
      final r = await http.delete(uri, headers: await _hdr(jsonBody: true));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر حذف التعليق: $e'
                : 'Failed to delete comment: $e',
          ),
        ),
      );
    }
  }

  Future<void> _replyAsOfficial(
    int postId, {
    int? replyToId,
  }) async {
    final l = L10n.of(context);
    final ctrl = TextEditingController();
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
  }

  Future<void> _sendOfficialReply({
    required int postId,
    required String text,
    int? replyToId,
  }) async {
    final l = L10n.of(context);
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/moments/admin/posts/$postId/comment');
      final body = <String, dynamic>{
        'text': text,
        'official_account_id': widget.accountId,
      };
      if (replyToId != null) {
        body['reply_to_id'] = replyToId;
      }
      final r = await http.post(
        uri,
        headers: await _hdr(jsonBody: true),
        body: jsonEncode(body),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تعذّر إرسال الرد: $e' : 'Failed to send reply: $e',
          ),
        ),
      );
    }
  }

  void _openInMoments(int postId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MomentsPage(
          baseUrl: widget.baseUrl,
          initialPostId: postId.toString(),
          focusComments: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final title =
        l.isArabic ? 'تعليقات اللحظات (إدارة)' : 'Moments comments (admin)';
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          if (!_loading && _items.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.isArabic
                    ? 'لا توجد تعليقات حديثة على اللحظات المرتبطة بهذا الحساب الرسمي.'
                    : 'There are no recent Moments comments for this official account.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = _items[i];
                      final cid = (c['id'] ?? 0) as int;
                      final pid = (c['post_id'] ?? 0) as int;
                      final text = (c['text'] ?? '').toString();
                      final ts = (c['created_at'] ?? '').toString();
                      final userKey = (c['user_key'] ?? '').toString().trim();
                      String authorLabel = userKey;
                      if (userKey.startsWith('official:')) {
                        final idx = userKey.indexOf(':');
                        final suffix = idx >= 0 && idx + 1 < userKey.length
                            ? userKey.substring(idx + 1)
                            : userKey;
                        authorLabel = 'Official · $suffix';
                      }
                      return ListTile(
                        title: Text(
                          text.isEmpty ? '(empty)' : text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
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
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _openInMoments(pid),
                              child: Text(
                                l.isArabic ? 'فتح' : 'Open',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _replyAsOfficial(
                                pid,
                                replyToId: cid,
                              ),
                              child: Text(
                                l.isArabic
                                    ? 'رد كحساب رسمي'
                                    : 'Reply as service',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _deleteComment(cid),
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
