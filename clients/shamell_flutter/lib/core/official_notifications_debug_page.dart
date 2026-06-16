import 'dart:convert';
import 'http_error.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'safe_set_state.dart';

const Duration _officialNotificationsDebugRequestTimeout =
    Duration(seconds: 15);

class OfficialNotificationsDebugPage extends StatefulWidget {
  final String baseUrl;

  const OfficialNotificationsDebugPage({super.key, required this.baseUrl});

  @override
  State<OfficialNotificationsDebugPage> createState() =>
      _OfficialNotificationsDebugPageState();
}

class _OfficialNotificationsDebugPageState
    extends State<OfficialNotificationsDebugPage>
    with SafeSetStateMixin<OfficialNotificationsDebugPage> {
  bool _loading = true;
  String _error = '';
  List<_NotifRow> _rows = const <_NotifRow>[];

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
      _rows = const <_NotifRow>[];
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts');
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialNotificationsDebugRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() {
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
      if (decoded is Map && decoded['accounts'] is List) {
        raw = decoded['accounts'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final rows = <_NotifRow>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final id = (m['id'] ?? '').toString();
        final name = (m['name'] ?? '').toString();
        final kind = (m['kind'] ?? 'service').toString();
        final notif = (m['notif_mode'] ?? '').toString();
        if (id.isEmpty) continue;
        rows.add(
          _NotifRow(
            id: id,
            name: name,
            kind: kind,
            notifMode: notif.isEmpty ? 'full (default)' : notif,
          ),
        );
      }
      rows.sort((a, b) => a.id.compareTo(b.id));
      setState(() {
        _rows = rows;
      });
    } catch (e) {
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic
              ? 'تصحيح إشعارات الحسابات الرسمية'
              : 'Official notifications – debug',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      return ListTile(
                        title: Text(
                          r.name.isNotEmpty ? r.name : r.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${r.id} • ${r.kind} • ${r.notifMode}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: _rows.length,
                  ),
                ),
    );
  }
}

class _NotifRow {
  final String id;
  final String name;
  final String kind;
  final String notifMode;

  const _NotifRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.notifMode,
  });
}
