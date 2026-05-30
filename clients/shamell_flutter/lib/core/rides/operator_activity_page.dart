// Operator activity log. Mirrors the carrier-flavor `_OrgActivityPage`
// pattern (carrier_console_page.dart#L1395) but reads the
// platform-wide `/admin/user-activity` feed because ride operations
// span every flavor's user session — there isn't a carrier-org-style
// scope to filter on.
//
// Reached via the IconButton on RideOperatorConsolePage's AppBar.
//
// Auth: the endpoint gates on superadmin (see
// `bff_gateway/src/auth.rs::admin_user_activity`). `demo_all_ops`
// holds owner.daily_admin, so existing operator-console users see
// it. A scoped per-flavor activity endpoint is the follow-up; this
// page closes the module-8 gap from the operator-console-inventory
// memory ("Audit log / activity protocol").
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';
import '../session_cookie_store.dart';

class OperatorActivityPage extends StatefulWidget {
  final String baseUrl;

  const OperatorActivityPage({super.key, required this.baseUrl});

  @override
  State<OperatorActivityPage> createState() => _OperatorActivityPageState();
}

class _OperatorActivityPageState extends State<OperatorActivityPage> {
  bool _loading = true;
  String? _loadError;
  List<_ActivityEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<Map<String, String>> _authHeaders() async {
    final base = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
    return {...base, 'Accept': 'application/json'};
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final headers = await _authHeaders();
      final resp = await http
          .get(
            Uri.parse('${widget.baseUrl}/admin/user-activity?limit=100'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 401) {
        setState(() {
          _loading = false;
          _loadError = 'Sitzung abgelaufen — bitte erneut anmelden.\n'
              '(Session expired — please sign in again.)';
        });
        return;
      }
      if (resp.statusCode == 403) {
        setState(() {
          _loading = false;
          _loadError = 'Diese Ansicht erfordert eine Superadmin-Rolle.\n'
              '(This view requires the superadmin role.)';
        });
        return;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() {
          _loading = false;
          _loadError = 'HTTP ${resp.statusCode}\n${resp.body}';
        });
        return;
      }
      final parsed = json.decode(resp.body) as Map<String, dynamic>;
      final items = parsed['items'];
      if (items is! List) {
        setState(() {
          _loading = false;
          _loadError = 'Unexpected response shape (no `items` array).';
        });
        return;
      }
      setState(() {
        _loading = false;
        _events = items
            .whereType<Map<String, dynamic>>()
            .map(_ActivityEvent.fromJson)
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'سجل النشاط' : 'Activity log'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(l)),
    );
  }

  Widget _buildBody(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(l.isArabic ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                l.isArabic ? 'لا توجد أحداث بعد' : 'No activity yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _ActivityRow(event: _events[i]),
      ),
    );
  }
}

class _ActivityEvent {
  final int id;
  final String? accountId;
  final String? username;
  final String? shamellUserId;
  final String eventType; // 'module_open' | 'signup' | 'platform_feature' | …
  final String action;
  final String? moduleId;
  final String? route;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  _ActivityEvent({
    required this.id,
    required this.accountId,
    required this.username,
    required this.shamellUserId,
    required this.eventType,
    required this.action,
    required this.moduleId,
    required this.route,
    required this.metadata,
    required this.createdAt,
  });

  static _ActivityEvent fromJson(Map<String, dynamic> json) => _ActivityEvent(
        id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
        accountId: json['account_id']?.toString(),
        username: json['username']?.toString(),
        shamellUserId: json['shamell_user_id']?.toString(),
        eventType: (json['event_type'] ?? '').toString(),
        action: (json['action'] ?? '').toString(),
        moduleId: json['module_id']?.toString(),
        route: json['route']?.toString(),
        metadata: (json['metadata'] is Map<String, dynamic>)
            ? (json['metadata'] as Map<String, dynamic>)
            : <String, dynamic>{},
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())
                ?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class _ActivityRow extends StatelessWidget {
  final _ActivityEvent event;

  const _ActivityRow({required this.event});

  IconData _icon() {
    switch (event.eventType) {
      case 'signup':
        return Icons.person_add_outlined;
      case 'module_open':
        return Icons.open_in_new_rounded;
      case 'platform_feature':
        return Icons.toggle_on_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }

  Color _accent() {
    switch (event.eventType) {
      case 'signup':
        return const Color(0xFF16A34A);
      case 'module_open':
        return const Color(0xFF2563EB);
      case 'platform_feature':
        return const Color(0xFFEAB308);
      default:
        return Colors.grey.shade600;
    }
  }

  String _humanWho(L10n l) {
    final u = event.username?.trim();
    if (u != null && u.isNotEmpty) return u;
    final sid = event.shamellUserId?.trim();
    if (sid != null && sid.isNotEmpty) return sid;
    final acc = event.accountId;
    if (acc != null && acc.length >= 12) return '${acc.substring(0, 12)}…';
    return l.isArabic ? '(مجهول)' : '(unknown)';
  }

  String _humanWhat(L10n l) {
    final mod = event.moduleId?.trim();
    if (event.eventType == 'module_open' && mod != null && mod.isNotEmpty) {
      return l.isArabic ? 'فتح وحدة $mod' : 'Opened module: $mod';
    }
    if (event.eventType == 'signup') {
      return l.isArabic ? 'تسجيل جديد · ${event.action}' : 'Signup · ${event.action}';
    }
    if (event.action.isNotEmpty) {
      return '${event.eventType} · ${event.action}';
    }
    return event.eventType;
  }

  String _humanWhen() {
    final dt = event.createdAt;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final accent = _accent();
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: .12),
          foregroundColor: accent,
          child: Icon(_icon(), size: 20),
        ),
        title: Text(_humanWhat(l), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_humanWho(l)),
        trailing: Text(_humanWhen(), style: Theme.of(context).textTheme.bodySmall),
        dense: true,
      ),
    );
  }
}
