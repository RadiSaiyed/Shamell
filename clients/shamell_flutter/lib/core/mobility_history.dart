import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'http_error.dart';
import 'ui_kit.dart';
import 'skeleton.dart';
import 'l10n.dart';
import 'safe_set_state.dart';

const Duration _mobilityHistoryRequestTimeout = Duration(seconds: 15);

class MobilityHistoryPage extends StatefulWidget {
  final String baseUrl;
  // testMode avoids network calls in widget tests and shows the empty state immediately.
  final bool testMode;
  const MobilityHistoryPage(this.baseUrl, {super.key, this.testMode = false});

  @override
  State<MobilityHistoryPage> createState() => _MobilityHistoryPageState();
}

class _MobilityHistoryPageState extends State<MobilityHistoryPage>
    with SafeSetStateMixin<MobilityHistoryPage> {
  bool _loading = true;
  String _statusFilter = 'all';
  final List<String> _statuses = const ['all', 'completed', 'canceled'];
  List<Map<String, dynamic>> _bus = [];
  String _out = '';

  @override
  void initState() {
    super.initState();
    if (!widget.testMode) {
      _warmStart();
    } else {
      _loading = false;
    }
  }

  Future<void> _warmStart() async {
    await _loadFromCache();
    await _load(showSpinner: _bus.isEmpty);
  }

  Future<void> _loadFromCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('mobility_history_all');
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final bs = j['bus'];
      final bus = bs is List
          ? bs.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      bus.sort((a, b) => _extractTs(b).compareTo(_extractTs(a)));
      if (!mounted) return;
      setState(() {
        _bus = bus;
        _out = '';
        _loading = false;
      });
    } catch (_) {
      // Cache is best-effort; ignore errors here
    }
  }

  DateTime _extractTs(Map<String, dynamic> r) {
    final raw = (r['requested_at'] ?? r['created_at'] ?? '').toString();
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _fmtTs(Map<String, dynamic> r) {
    final dt = _extractTs(r);
    if (dt.millisecondsSinceEpoch == 0) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dday = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(dday).inDays;
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final l = L10n.of(context);
    if (diffDays == 0) return '${l.todayLabel} · $hm';
    if (diffDays == 1) return '${l.yesterdayLabel} · $hm';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} · $hm';
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _loading = true);
    }
    try {
      final qp = <String, String>{'limit': '100'};
      if (_statusFilter != 'all') qp['status'] = _statusFilter;
      final uri = Uri.parse('${widget.baseUrl}/me/mobility_history')
          .replace(queryParameters: qp);
      final sp = await SharedPreferences.getInstance();
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      final r = await http.get(uri, headers: {
        if (cookie.isNotEmpty) 'cookie': cookie,
      }).timeout(_mobilityHistoryRequestTimeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final bs = j['bus'];
        _bus = (bs is List
            ? bs.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[]);
        // Show newest entries first
        _bus.sort((a, b) => _extractTs(b).compareTo(_extractTs(a)));
        _out = '';
        // Cache only in "all" status; filtered results are transient.
        if (_statusFilter == 'all') {
          try {
            final snapshot = jsonEncode({'bus': _bus});
            await sp.setString('mobility_history_all', snapshot);
          } catch (_) {}
        }
      } else {
        _out = sanitizeHttpError(
          statusCode: r.statusCode,
          rawBody: r.body,
          isArabic: L10n.of(context).isArabic,
        );
      }
    } catch (e) {
      _out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    if (mounted && showSpinner) {
      setState(() => _loading = false);
    }
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
              FormSection(
                title: l.filterLabel,
                children: [
                  DropdownButton<String>(
                    value: _statusFilter,
                    items: _statuses
                        .map(
                          (s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(
                              s == 'all'
                                  ? l.statusAll
                                  : (s == 'completed'
                                      ? l.statusCompleted
                                      : l.statusCanceled),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _statusFilter = v);
                      _load();
                    },
                  ),
                ],
              ),
              if (_bus.isNotEmpty) ...[
                Text(L10n.of(context).homeBus,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ..._bus.map(_buildBusTile),
              ],
              if (_bus.isEmpty && _out.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l.noMobilityHistory,
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70)),
                  ),
                ),
              if (_out.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_out,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.mobilityHistoryTitle),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(color: Colors.white),
          SafeArea(child: body),
        ],
      ),
    );
  }

  Widget _buildBusTile(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    final created = _fmtTs(r);
    final tripId = (r['trip_id'] ?? '').toString();
    final seats = (r['seats'] ?? '').toString();
    final subtitle = StringBuffer();
    if (created.isNotEmpty) {
      subtitle.write(created);
    }
    if (tripId.isNotEmpty) {
      if (subtitle.isNotEmpty) subtitle.write('\n');
      subtitle.write('Trip: $tripId · Seats: $seats');
    }
    return StandardListTile(
      leading: const Icon(Icons.directions_bus_outlined),
      title: Text(status, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle.toString(), style: const TextStyle(fontSize: 12)),
    );
  }
}
