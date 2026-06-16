import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_error.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import 'skeleton.dart';
import 'app_shell_widgets.dart' show AppBG;
import 'safe_set_state.dart';

const Duration _orderCenterRequestTimeout = Duration(seconds: 15);

class OrderCenterPage extends StatefulWidget {
  final String baseUrl;
  const OrderCenterPage(this.baseUrl, {super.key});

  @override
  State<OrderCenterPage> createState() => _OrderCenterPageState();
}

class _OrderCenterPageState extends State<OrderCenterPage>
    with SafeSetStateMixin<OrderCenterPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _bus = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _hdr({bool json = false}) async {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
    if (cookie.isNotEmpty) {
      h['cookie'] = cookie;
    }
    return h;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    await _loadMobility();
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _loadMobility() async {
    try {
      final qp = <String, String>{'limit': '20'};
      final uri = Uri.parse('${widget.baseUrl}/me/mobility_history')
          .replace(queryParameters: qp);
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_orderCenterRequestTimeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final bs = j['bus'];
        final bus = bs is List
            ? bs.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[];
        bus.sort((a, b) => _extractTs(b).compareTo(_extractTs(a)));
        _bus = bus.take(5).toList();
      } else {
        _error = sanitizeHttpError(
          statusCode: r.statusCode,
          rawBody: r.body,
          isArabic: L10n.of(context).isArabic,
        );
      }
    } catch (e) {
      _error = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
  }

  DateTime _extractTs(Map<String, dynamic> r) {
    final raw = (r['requested_at'] ?? r['created_at'] ?? r['updated_at'] ?? '')
        .toString();
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _fmtTs(Map<String, dynamic> r, L10n l) {
    final dt = _extractTs(r);
    if (dt.millisecondsSinceEpoch == 0) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dday = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(dday).inDays;
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diffDays == 0) return '${l.todayLabel} · $hm';
    if (diffDays == 1) return '${l.yesterdayLabel} · $hm';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} · $hm';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final body = _loading
        ? ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 6,
            itemBuilder: (_, __) => const SkeletonListTile(),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FormSection(
                title: l.isArabic ? 'التنقل' : 'Mobility',
                subtitle:
                    l.isArabic ? 'أحدث رحلات الحافلات' : 'Recent bus trips',
                children: [
                  if (_bus.isEmpty)
                    Text(
                      l.noMobilityHistory,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                    ),
                  ..._bus.map((r) => _buildBusTile(r, l)),
                  if (_bus.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pushNamed('/mobility_history');
                        },
                        child: Text(
                          l.isArabic ? 'عرض كل الرحلات' : 'View all trips',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
    return DomainPageScaffold(
      background: const AppBG(),
      title: l.isArabic ? 'رحلاتي' : 'My trips',
      child: body,
      scrollable: false,
    );
  }

  Widget _buildBusTile(Map<String, dynamic> r, L10n l) {
    final status = (r['status'] ?? '').toString();
    final subtitle = _fmtTs(r, l);
    return StandardListTile(
      leading: const Icon(Icons.directions_bus_outlined),
      title: Text(
        status.isEmpty ? (l.isArabic ? 'رحلة باص' : 'Bus trip') : status,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }
}
