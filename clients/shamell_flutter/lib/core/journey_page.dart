import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'status_banner.dart';
import 'ui_kit.dart';
import 'skeleton.dart';
import 'mobility_history.dart' show MobilityHistoryPage;

class JourneyPage extends StatefulWidget {
  final String baseUrl;
  // testMode avoids network calls in widget tests and keeps the UI static.
  final bool testMode;
  const JourneyPage(this.baseUrl, {super.key, this.testMode = false});

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic> _home = {};
  List<Map<String, dynamic>> _bus = [];

  @override
  void initState() {
    super.initState();
    if (!widget.testMode) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/journey_snapshot');
      final sp = await SharedPreferences.getInstance();
      final cookie = sp.getString('sa_cookie') ?? '';
      final r = await http.get(uri, headers: {'Cookie': cookie});
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final home = j['home'];
        final mob = j['mobility_history'] ?? {};
        _home = home is Map<String, dynamic> ? home : <String, dynamic>{};
        final bs = (mob is Map<String, dynamic>) ? mob['bus'] : null;
        _bus = (bs is List
            ? bs.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[]);
      } else {
        _error = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _error = 'Error: $e';
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
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
                  child: StatusBanner.error(_error),
                ),
              _buildProfileSection(l),
              _buildRolesSection(l),
              _buildMobilitySection(l),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.route_outlined,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(l.journeyTitle),
          ],
        ),
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

  Widget _buildProfileSection(L10n l) {
    final phone = (_home['phone'] ?? '').toString();
    final walletId = (_home['wallet_id'] ?? '').toString();
    return FormSection(
      title: l.profileTitle,
      children: [
        StandardListTile(
          leading: const Icon(Icons.phone_iphone_outlined),
          title: Text(phone.isEmpty ? l.notSet : phone),
          subtitle: Text(l.labelPhone),
        ),
        StandardListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(walletId.isEmpty ? l.notSet : walletId),
          subtitle: Text(l.labelWalletId),
        ),
      ],
    );
  }

  Widget _buildRolesSection(L10n l) {
    final roles =
        (_home['roles'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final opDomains = (_home['operator_domains'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final isAdmin = _home['is_admin'] == true;
    final isSuper = _home['is_superadmin'] == true;

    final chips = <Widget>[];
    for (final r in roles) {
      chips.add(Chip(label: Text(r)));
    }
    if (isAdmin) {
      chips.add(Chip(label: Text('admin')));
    }
    if (isSuper) {
      chips.add(Chip(label: Text('superadmin')));
    }

    final opsText = opDomains.isEmpty
        ? (l.isArabic ? 'لا توجد مجالات مشغّل' : 'No operator domains')
        : opDomains.join(', ');

    return FormSection(
      title: l.rolesOverviewTitle,
      children: [
        if (chips.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: chips,
          ),
        const SizedBox(height: 8),
        StandardListTile(
          leading: const Icon(Icons.support_agent_outlined),
          title: Text(opsText),
        ),
      ],
    );
  }

  Widget _buildMobilitySection(L10n l) {
    final hasAny = _bus.isNotEmpty;
    return FormSection(
      title: l.mobilityTitle,
      children: [
        if (!hasAny)
          Text(
            l.isArabic ? 'لا توجد رحلات بعد' : 'No mobility history yet',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70)),
          ),
        if (_bus.isNotEmpty) ...[
          Text(l.homeBus, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ..._bus.take(3).map(_buildBusTile),
        ],
        const SizedBox(height: 12),
        PrimaryButton(
          label: l.isArabic ? 'عرض كل الرحلات' : 'View all trips',
          expanded: true,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MobilityHistoryPage(widget.baseUrl)),
            );
          },
        ),
      ],
    );
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
    if (diffDays == 0) return 'Today · $hm';
    if (diffDays == 1) return 'Yesterday · $hm';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} · $hm';
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
