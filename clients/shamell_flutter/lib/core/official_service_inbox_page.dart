import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'chat/shamell_chat_page.dart';
import 'http_error.dart';

class OfficialServiceInboxPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final String accountName;

  const OfficialServiceInboxPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    required this.accountName,
  });

  @override
  State<OfficialServiceInboxPage> createState() =>
      _OfficialServiceInboxPageState();
}

class _OfficialServiceInboxPageState extends State<OfficialServiceInboxPage> {
  bool _loading = true;
  String? _error;
  List<_ServiceSession> _items = const <_ServiceSession>[];

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
      final cookie = await getSessionCookie() ?? '';
      if (cookie.isNotEmpty) {
        headers['sa_cookie'] = cookie;
      }
    } catch (_) {}
    return headers;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = const <_ServiceSession>[];
    });
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/admin/official_accounts/${Uri.encodeComponent(widget.accountId)}/service_inbox',
      ).replace(queryParameters: const <String, String>{
        'limit': '100',
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

  Future<void> _markRead(_ServiceSession s) async {
    if (!s.unreadByOperator) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/admin/official_accounts/${Uri.encodeComponent(widget.accountId)}/service_inbox/${s.id}/mark_read',
      );
      await http.post(uri, headers: await _hdr(jsonBody: true));
    } catch (_) {
      // Best-effort; UI is optimistic.
    }
  }

  Future<void> _closeSession(_ServiceSession s) async {
    final l = L10n.of(context);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/admin/official_accounts/${Uri.encodeComponent(widget.accountId)}/service_inbox/${s.id}/close',
      );
      final r = await http.post(uri, headers: await _hdr(jsonBody: true));
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
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((it) => it.id == s.id
                ? it.copyWith(status: 'closed', unreadByOperator: false)
                : it)
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر إغلاق الجلسة: $e'
                : 'Failed to close session: $e',
          ),
        ),
      );
    }
  }

  Future<void> _sendTemplateMessage(_ServiceSession s) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
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
                                    final uri = Uri.parse(
                                      '${widget.baseUrl}/admin/official_accounts/${Uri.encodeComponent(widget.accountId)}/service_inbox/${s.id}/template_messages',
                                    );
                                    final r = await http.post(
                                      uri,
                                      headers: await _hdr(jsonBody: true),
                                      body: jsonEncode(<String, dynamic>{
                                        'title': title,
                                        'body': body,
                                      }),
                                    );
                                    if (r.statusCode < 200 ||
                                        r.statusCode >= 300) {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'صندوق خدمة العملاء' : 'Customer service inbox',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
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
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (_, i) {
                            final s = _items[i];
                            final isOpen =
                                (s.status.trim().toLowerCase() != 'closed');
                            return ListTile(
                              onTap: () {
                                if (s.unreadByOperator) {
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
                                          onPressed: () {
                                            // ignore: discarded_futures
                                            _sendTemplateMessage(s);
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                          tooltip: l.isArabic
                                              ? 'إغلاق الجلسة'
                                              : 'Close session',
                                          onPressed: () {
                                            // ignore: discarded_futures
                                            _closeSession(s);
                                          },
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemCount: _items.length,
                        ),
                ),
    );
  }
}

class _ServiceSession {
  final int id;
  final String accountId;
  final String customerPhone;
  final String? chatPeerId;
  final String status;
  final DateTime? lastMessageTs;
  final bool unreadByOperator;

  const _ServiceSession({
    required this.id,
    required this.accountId,
    required this.customerPhone,
    required this.chatPeerId,
    required this.status,
    required this.lastMessageTs,
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
      accountId: (j['account_id'] ?? '').toString(),
      customerPhone: (j['customer_phone'] ?? '').toString(),
      chatPeerId: (j['chat_peer_id'] ?? '').toString().isEmpty
          ? null
          : (j['chat_peer_id'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      lastMessageTs: _parseTs((j['last_message_ts'] ?? '').toString()),
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
      accountId: accountId,
      customerPhone: customerPhone,
      chatPeerId: chatPeerId,
      status: status ?? this.status,
      lastMessageTs: lastMessageTs,
      unreadByOperator: unreadByOperator ?? this.unreadByOperator,
    );
  }
}
