import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'ui_kit.dart';
import 'skeleton.dart';
import 'app_shell_widgets.dart' show AppBG;
import 'wechat_webview_page.dart';

class OrderCenterPage extends StatefulWidget {
  final String baseUrl;
  const OrderCenterPage(this.baseUrl, {super.key});

  @override
  State<OrderCenterPage> createState() => _OrderCenterPageState();
}

class _OrderCenterPageState extends State<OrderCenterPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _taxi = [];
  List<Map<String, dynamic>> _bus = [];
  List<Map<String, dynamic>> _food = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _hdr({bool json = false}) async {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    final sp = await SharedPreferences.getInstance();
    final cookie = sp.getString('sa_cookie') ?? '';
    if (cookie.isNotEmpty) {
      h['Cookie'] = cookie;
    }
    return h;
  }

  Future<Map<String, String>> _hdrFood({bool json = false}) async {
    final headers = <String, String>{};
    if (json) headers['content-type'] = 'application/json';
    try {
      final sp = await SharedPreferences.getInstance();
      final cookie = sp.getString('sa_cookie') ?? '';
      if (cookie.isNotEmpty) {
        headers['sa_cookie'] = cookie;
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
      await Future.wait([
        _loadMobility(),
        _loadFood(),
      ]);
    } catch (e) {
      _error = 'Error: $e';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _loadMobility() async {
    try {
      final qp = <String, String>{'taxi_limit': '20', 'bus_limit': '20'};
      final uri = Uri.parse('${widget.baseUrl}/me/mobility_history')
          .replace(queryParameters: qp);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final tx = j['taxi'];
        final bs = j['bus'];
        final taxi = tx is List
            ? tx.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[];
        final bus = bs is List
            ? bs.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[];
        taxi.sort((a, b) => _extractTs(b).compareTo(_extractTs(a)));
        bus.sort((a, b) => _extractTs(b).compareTo(_extractTs(a)));
        _taxi = taxi.take(5).toList();
        _bus = bus.take(5).toList();
      }
    } catch (_) {}
  }

  Future<void> _loadFood() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final phone = sp.getString('last_login_phone') ?? '';
      if (phone.isEmpty) return;
      final qp = <String, String>{'phone': phone, 'limit': '20'};
      final uri = Uri.parse('${widget.baseUrl}/food/orders')
          .replace(queryParameters: qp);
      final r = await http.get(uri, headers: await _hdrFood());
      if (r.statusCode == 200) {
        final arr = jsonDecode(r.body);
        final orders = arr is List
            ? arr.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[];
        orders.sort((a, b) => _extractTs(b).compareTo(_extractTs(a)));
        _food = orders.take(5).toList();
      }
    } catch (_) {}
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
                subtitle: l.isArabic
                    ? 'أحدث رحلات التاكسي والحافلات'
                    : 'Recent taxi and bus trips',
                children: [
                  if (_taxi.isEmpty && _bus.isEmpty)
                    Text(
                      l.noMobilityHistory,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                    ),
                  ..._taxi.map((r) => _buildTaxiTile(r, l)),
                  ..._bus.map((r) => _buildBusTile(r, l)),
                  if (_taxi.isNotEmpty || _bus.isNotEmpty)
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
              FormSection(
                title: l.isArabic ? 'طلبات الطعام' : 'Food orders',
                subtitle: l.isArabic
                    ? 'أحدث طلبات الطعام المرتبطة بحسابك'
                    : 'Recent food orders for your account',
                children: [
                  if (_food.isEmpty)
                    Text(
                      l.isArabic
                          ? 'لا توجد طلبات طعام بعد'
                          : 'No food orders yet',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                    ),
                  ..._food.map((r) => _buildFoodTile(r, l)),
                  if (_food.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          final base = widget.baseUrl
                              .trim()
                              .replaceAll(RegExp(r'/+$'), '');
                          final baseUri = Uri.tryParse(base);
                          if (baseUri == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WeChatWebViewPage(
                                initialUri: Uri(path: '/food'),
                                baseUri: baseUri,
                                initialTitle: l.isArabic ? 'الطعام' : 'Food',
                              ),
                            ),
                          );
                        },
                        child: Text(
                          l.isArabic ? 'عرض كل الطلبات' : 'View all orders',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
    return DomainPageScaffold(
      background: const AppBG(),
      title: l.isArabic ? 'طلباتي' : 'My orders',
      child: body,
      scrollable: false,
    );
  }

  Widget _buildTaxiTile(Map<String, dynamic> r, L10n l) {
    final status = (r['status'] ?? '').toString();
    final subtitle = _fmtTs(r, l);
    return StandardListTile(
      leading: const Icon(Icons.local_taxi_outlined),
      title: Text(
        status.isEmpty ? (l.isArabic ? 'رحلة تاكسي' : 'Taxi ride') : status,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
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

  Widget _buildFoodTile(Map<String, dynamic> r, L10n l) {
    final status = (r['status'] ?? '').toString();
    final restaurant =
        (r['restaurant_name'] ?? r['restaurant_id'] ?? '').toString();
    final subtitle = StringBuffer();
    subtitle.write(_fmtTs(r, l));
    if (restaurant.isNotEmpty) {
      if (subtitle.isNotEmpty) subtitle.write('\n');
      subtitle.write(restaurant);
    }
    return StandardListTile(
      leading: const Icon(Icons.restaurant_outlined),
      title: Text(
        status.isEmpty ? (l.isArabic ? 'طلب طعام' : 'Food order') : status,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle.toString(), style: const TextStyle(fontSize: 12)),
    );
  }
}
