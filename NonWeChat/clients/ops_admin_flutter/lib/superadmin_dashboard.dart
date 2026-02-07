import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SuperadminDashboardPage extends StatefulWidget {
  const SuperadminDashboardPage({super.key});

  @override
  State<SuperadminDashboardPage> createState() => _SuperadminDashboardPageState();
}

class _SuperadminDashboardPageState extends State<SuperadminDashboardPage> {
  final TextEditingController _baseCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';

  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _upstreams;
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    _baseCtrl.text = sp.getString('ops_base_url') ??
        const String.fromEnvironment(
          'BASE_URL',
          defaultValue: 'http://localhost:8080',
        );
    if (mounted) {
      setState(() {});
    }
    await _loadAll();
  }

  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final sp = await SharedPreferences.getInstance();
    final h = <String, String>{};
    final cookie = sp.getString('sa_cookie');
    if (cookie != null && cookie.isNotEmpty) {
      h['Cookie'] = cookie;
    }
    final token = sp.getString('shamell_jwt') ?? sp.getString('jwt') ?? sp.getString('access_token') ?? '';
    if (token.isNotEmpty) {
      h['authorization'] = 'Bearer $token';
    }
    if (json) {
      h['content-type'] = 'application/json';
    }
    return h;
  }

  String get _baseUrl => _baseCtrl.text.trim();

  Future<void> _loadAll() async {
    if (_baseUrl.isEmpty) {
      setState(() {
        _error = 'Base URL is empty.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final headers = await _authHeaders(json: false);
      final statsUri = Uri.parse('$_baseUrl/admin/stats?limit=200');
      final upsUri = Uri.parse('$_baseUrl/upstreams/health');
      final infoUri = Uri.parse('$_baseUrl/admin/info');

      final results = await Future.wait<http.Response>([
        http.get(statsUri, headers: headers),
        http.get(upsUri, headers: headers),
        http.get(infoUri, headers: headers),
      ]);

      final statsResp = results[0];
      final upsResp = results[1];
      final infoResp = results[2];

      Map<String, dynamic>? parseJson(http.Response r) {
        if (r.statusCode < 200 || r.statusCode >= 300) return null;
        try {
          final body = jsonDecode(r.body);
          return body is Map<String, dynamic> ? body : null;
        } catch (_) {
          return null;
        }
      }

      final stats = parseJson(statsResp);
      final ups = parseJson(upsResp);
      final info = parseJson(infoResp);

      String err = '';
      if (stats == null) {
        err = 'Failed to load /admin/stats (${statsResp.statusCode}).';
      } else if (ups == null) {
        err = 'Failed to load /upstreams/health (${upsResp.statusCode}).';
      } else if (info == null) {
        err = 'Failed to load /admin/info (${infoResp.statusCode}).';
      }

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _upstreams = ups;
        _info = info;
        _error = err;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error loading dashboard: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildEnvCard() {
    final info = _info ?? const {};
    final env = (info['env'] ?? '').toString();
    final monolith = info['monolith'] == true;
    final security = info['security_headers'] == true;
    final domains = (info['domains'] as Map?) ?? const {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Environment',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('ENV: ${env.isEmpty ? '(unknown)' : env}'),
            Text('Monolith: ${monolith ? 'on' : 'off'}'),
            Text('Security headers: ${security ? 'enabled' : 'disabled'}'),
            const SizedBox(height: 8),
            const Text(
              'Domains',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            if (domains.isEmpty)
              const Text('No domain info.')
            else
              ...domains.entries.map((e) {
                final name = e.key;
                final v = (e.value as Map).cast<String, dynamic>();
                final internal = v['internal'] == true;
                final base = (v['base_url'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '$name: ${internal ? 'internal' : 'remote'} · ${base.isEmpty ? '(no base)' : base}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildUpstreamsCard() {
    final ups = _upstreams ?? const {};
    final entries = ups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    int total = 0;
    int ok = 0;
    for (final e in entries) {
      total++;
      final v = (e.value as Map).cast<String, dynamic>();
      final sc = v['status_code'];
      if (sc is int && sc >= 200 && sc < 300) ok++;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upstreams health',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Healthy: $ok / $total'),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text('No upstreams configured.')
            else
              ...entries.map((e) {
                final name = e.key;
                final v = (e.value as Map).cast<String, dynamic>();
                final sc = v['status_code'];
                final err = v['error'];
                String status;
                if (err != null) {
                  status = 'ERROR: $err';
                } else if (sc is int) {
                  if (sc >= 200 && sc < 300) {
                    status = 'OK ($sc)';
                  } else if (sc >= 500) {
                    status = 'DOWN ($sc)';
                  } else {
                    status = 'WARN ($sc)';
                  }
                } else {
                  status = 'UNKNOWN';
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '$name · $status',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildGuardrailsCard() {
    final stats = _stats ?? const {};
    final guardrails = (stats['guardrails'] as Map?)?.cast<String, dynamic>() ?? const {};
    final freight = (stats['freight_guardrails'] as Map?)?.cast<String, dynamic>() ?? const {};

    List<MapEntry<String, int>> _toSorted(Map<String, dynamic> src) {
      final list = src.entries
          .map((e) => MapEntry(e.key, (e.value is int) ? (e.value as int) : int.tryParse(e.value.toString()) ?? 0))
          .toList();
      list.sort((a, b) => b.value.compareTo(a.value));
      return list;
    }

    final all = _toSorted(guardrails);
    final top = all.take(10).toList();
    final freightTop = _toSorted(freight).take(10).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Guardrails (recent)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (top.isEmpty)
              const Text('No guardrail events in recent window.')
            else
              ...top.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
                  )),
            if (freightTop.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Freight / Courier guardrails',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              ...freightTop.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyCard() {
    final stats = _stats ?? const {};
    final samples = (stats['samples'] as Map?)?.cast<String, dynamic>() ?? const {};

    String lineFor(String metric, String label) {
      final m = samples[metric];
      if (m is Map) {
        final cnt = m['count'] ?? 0;
        final avg = m['avg_ms'] ?? 0.0;
        return '$label: avg ${avg.toStringAsFixed(0)} ms · count ${cnt.toString()}';
      }
      return '';
    }

    final lines = <String>[
      lineFor('pay_send_ms', 'Payments send'),
      lineFor('taxi_book_ms', 'Taxi booking'),
      lineFor('bus_book_ms', 'Bus booking'),
      lineFor('stays_book_ms', 'Stays booking'),
      lineFor('food_order_ms', 'Food order'),
    ].where((s) => s.isNotEmpty).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Key latency metrics',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (lines.isEmpty)
              const Text(
                'No detailed latency metrics yet.',
                style: TextStyle(fontSize: 12),
              )
            else
              ...lines.map(
                (s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    s,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _baseCtrl,
          decoration: InputDecoration(
            labelText: 'BFF Base URL',
            suffixIcon: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _loadAll,
            ),
          ),
          onSubmitted: (_) => _loadAll(),
        ),
        const SizedBox(height: 12),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (_info != null) _buildEnvCard(),
        if (_upstreams != null) _buildUpstreamsCard(),
        if (_stats != null) _buildGuardrailsCard(),
        if (_stats != null) _buildLatencyCard(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Superadmin Dashboard'),
      ),
      body: body,
    );
  }
}
