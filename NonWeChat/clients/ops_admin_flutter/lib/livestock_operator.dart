import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LivestockOperatorPage extends StatefulWidget {
  final String defaultBaseUrl;
  const LivestockOperatorPage({
    super.key,
    this.defaultBaseUrl = const String.fromEnvironment(
      'BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
  });

  @override
  State<LivestockOperatorPage> createState() => _LivestockOperatorPageState();
}

class _LivestockOperatorPageState extends State<LivestockOperatorPage> {
  final TextEditingController _baseCtrl = TextEditingController();
  final TextEditingController _tokenCtrl = TextEditingController();
  String _listOut = '';

  Future<SharedPreferences> get _sp async => SharedPreferences.getInstance();

  String get _baseUrl => _baseCtrl.text.trim();

  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final prefs = await _sp;
    final t = _tokenCtrl.text.trim().isNotEmpty
        ? _tokenCtrl.text.trim()
        : (prefs.getString('shamell_jwt') ??
            prefs.getString('jwt') ??
            prefs.getString('access_token') ??
            '');
    final h = <String, String>{};
    if (t.isNotEmpty) h['authorization'] = 'Bearer $t';
    if (json) h['content-type'] = 'application/json';
    return h;
  }

  Future<void> _saveBaseAndToken() async {
    final p = await _sp;
    await p.setString('ops_base_url', _baseUrl);
    await p.setString('shamell_jwt', _tokenCtrl.text.trim());
    if (mounted) setState(() {});
  }

  Future<void> _loadBaseAndToken() async {
    final p = await _sp;
    _baseCtrl.text = p.getString('ops_base_url') ?? widget.defaultBaseUrl;
    _tokenCtrl.text = p.getString('shamell_jwt') ?? '';
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _baseCtrl.text = widget.defaultBaseUrl;
    scheduleMicrotask(_loadBaseAndToken);
  }

  Future<void> _health() async {
    setState(() => _listOut = '...');
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/livestock/health'),
        headers: await _authHeaders(),
      );
      setState(() => _listOut = 'health: ${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _listOut = 'health error: $e');
    }
  }

  Future<void> _loadListings() async {
    setState(() => _listOut = 'Loading listings...');
    try {
      final uri = Uri.parse('$_baseUrl/livestock/listings_cached');
      final r = await http.get(uri, headers: await _authHeaders());
      if (r.statusCode == 200) {
        final body = r.body;
        try {
          final decoded = jsonDecode(body);
          if (decoded is List) {
            setState(() => _listOut = 'Listings: ${decoded.length}\n$body');
          } else {
            setState(() => _listOut = 'Listings loaded\n$body');
          }
        } catch (_) {
          setState(() => _listOut = 'Listings loaded\n$body');
        }
      } else {
        setState(() => _listOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Livestock – Operator'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _baseCtrl,
              decoration: const InputDecoration(
                labelText: 'BFF Base URL',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'JWT (optional)',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _saveBaseAndToken,
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _health,
                  child: const Text('Health'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loadListings,
                  child: const Text('Reload listings (cached)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _listOut,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
