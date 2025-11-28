import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TaxiOperatorPage extends StatefulWidget {
  final String defaultBaseUrl;
  const TaxiOperatorPage({
    super.key,
    this.defaultBaseUrl = const String.fromEnvironment(
      'BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
  });
  @override
  State<TaxiOperatorPage> createState() => _TaxiOperatorPageState();
}

class _TaxiOperatorPageState extends State<TaxiOperatorPage> {
  // Base + token
  final TextEditingController _baseCtrl = TextEditingController();
  final TextEditingController _tokenCtrl = TextEditingController();

  // Driver creation
  final TextEditingController _dNameCtrl = TextEditingController(text: 'test_driver');
  final TextEditingController _dPhoneCtrl = TextEditingController(text: '+963006000002');
  final TextEditingController _dMakeCtrl = TextEditingController(text: 'Toyota');
  final TextEditingController _dPlateCtrl = TextEditingController(text: 'XYZ-123');
  final TextEditingController _dColorCtrl = TextEditingController(text: 'Gelb');
  String _dClass = 'classic';
  String _dOut = '';

  // Driver list/search
  final TextEditingController _statusCtrl = TextEditingController();
  List<Map<String, dynamic>> _drivers = [];
  String _listOut = '';

  // Driver balance by identity
  final TextEditingController _balPhoneCtrl = TextEditingController();
  final TextEditingController _balPlateCtrl = TextEditingController();
  final TextEditingController _balCentsCtrl = TextEditingController(text: '0');

  // Taxi driver QR topup
  final TextEditingController _topupPhoneCtrl = TextEditingController();
  final TextEditingController _topupAmountCtrl = TextEditingController(text: '10000');
  String _topupPayload = '';
  List<Map<String, dynamic>> _qrLogs = [];

  // Rides list (no manual creation)
  List<Map<String, dynamic>> _rides = [];

  // Complaints
  final TextEditingController _cSearchCtrl = TextEditingController();
  final TextEditingController _cResolutionCtrl = TextEditingController();
  String _cStatusFilter = 'open';
  List<Map<String, dynamic>> _complaints = [];
  String _cOut = '';
  static const String _complaintsEmail = 'radisaiyed@icloud.com';
  static const String _supportPhone = '+96996428955';

  // Helpers
  Future<SharedPreferences> get _sp async => SharedPreferences.getInstance();

  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final prefs = await _sp;
    final t = _tokenCtrl.text.trim().isNotEmpty
        ? _tokenCtrl.text.trim()
        : (prefs.getString('shamell_jwt') ?? prefs.getString('jwt') ?? prefs.getString('access_token') ?? '');
    final h = <String, String>{};
    if (t.isNotEmpty) h['authorization'] = 'Bearer $t';
     final cookie = prefs.getString('sa_cookie');
     if (cookie != null && cookie.isNotEmpty) {
       h['Cookie'] = cookie;
     }
    if (json) h['content-type'] = 'application/json';
    return h;
  }

  String get _baseUrl => _baseCtrl.text.trim();

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
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _baseCtrl.text = widget.defaultBaseUrl;
    // async load stored values
    scheduleMicrotask(_loadBaseAndToken);
  }

  // --- Actions ---
  Future<void> _createDriver() async {
    setState(() => _dOut = '...');
    try {
      final uri = Uri.parse('$_baseUrl/taxi/drivers');
      final r = await http.post(
        uri,
        headers: await _authHeaders(json: true),
        body: jsonEncode({
          'name': _dNameCtrl.text.trim(),
          'phone': _dPhoneCtrl.text.trim(),
          'vehicle_make': _dMakeCtrl.text.trim(),
          'vehicle_plate': _dPlateCtrl.text.trim(),
          'vehicle_class': _dClass,
          'vehicle_color': _dColorCtrl.text.trim(),
        }),
      );
      setState(() => _dOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _dOut = 'error: $e');
    }
  }

  Future<void> _blockPhone(bool block) async {
    setState(() => _listOut = '...');
    try {
      final phone = _balPhoneCtrl.text.trim();
      if (phone.isEmpty) {
        setState(() => _listOut = 'Please enter phone');
        return;
      }
      final ep = block ? '/admin/block_driver' : '/admin/unblock_driver';
      final r = await http.post(Uri.parse('$_baseUrl$ep'), headers: await _authHeaders(json: true), body: jsonEncode({'phone': phone}));
      setState(() => _listOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  Future<void> _setBalanceByIdentity() async {
    setState(() => _listOut = '...');
    try {
      final cents = int.tryParse(_balCentsCtrl.text.trim()) ?? 0;
      final body = {
        'phone': _balPhoneCtrl.text.trim().isEmpty ? null : _balPhoneCtrl.text.trim(),
        'vehicle_plate': _balPlateCtrl.text.trim().isEmpty ? null : _balPlateCtrl.text.trim(),
        'set_cents': cents,
      };
      final r = await http.post(Uri.parse('$_baseUrl/taxi/drivers/balance_by_identity'), headers: await _authHeaders(json: true), body: jsonEncode(body));
      setState(() => _listOut = '${r.statusCode}: ${r.body}');
      await _listDrivers();
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  Future<void> _createTaxiTopupQr() async {
    setState(() => _listOut = '...');
    try {
      final phone = _topupPhoneCtrl.text.trim();
      final amt = int.tryParse(_topupAmountCtrl.text.trim()) ?? 0;
      if (phone.isEmpty || amt <= 0) {
        setState(() => _listOut = 'Phone and amount required');
        return;
      }
      final uri = Uri.parse('$_baseUrl/taxi/topup_qr/create');
      // amt is entered in SYP (major units); backend converts to cents.
      final r = await http.post(
        uri,
        headers: await _authHeaders(json: true),
        body: jsonEncode({'driver_phone': phone, 'amount_syp': amt}),
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        _topupPayload = (j['payload'] ?? '').toString();
        setState(() => _listOut = 'Topup-QR erstellt');
      } else {
        setState(() => _listOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  Future<void> _blockTaxiDriver(String driverId, bool block) async {
    setState(() => _listOut = '...');
    try {
      if (driverId.trim().isEmpty) {
        setState(() => _listOut = 'driver_id required');
        return;
      }
      final ep = block ? '/taxi/drivers/$driverId/block' : '/taxi/drivers/$driverId/unblock';
      final r = await http.post(Uri.parse('$_baseUrl$ep'), headers: await _authHeaders(json: true));
      setState(() => _listOut = '${r.statusCode}: ${r.body}');
      await _listDrivers();
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  Future<void> _deleteTaxiDriver(String driverId) async {
    setState(() => _listOut = '...');
    try {
      if (driverId.trim().isEmpty) {
        setState(() => _listOut = 'driver_id required');
        return;
      }
      final r = await http.delete(Uri.parse('$_baseUrl/taxi/drivers/$driverId'), headers: await _authHeaders());
      setState(() => _listOut = '${r.statusCode}: ${r.body}');
      await _listDrivers();
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  Future<void> _listDrivers() async {
    setState(() => _listOut = '...');
    try {
      final params = <String, String>{};
      if (_statusCtrl.text.trim().isNotEmpty) params['status'] = _statusCtrl.text.trim();
      final uri = Uri.parse('$_baseUrl/taxi/drivers').replace(queryParameters: params.isEmpty ? null : params);
      final r = await http.get(uri, headers: await _authHeaders());
      if (r.statusCode == 200) {
        final arr = jsonDecode(r.body) as List;
        _drivers = arr.cast<Map<String, dynamic>>();
        setState(() => _listOut = 'drivers: ${_drivers.length}');
      } else {
        setState(() => _listOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  Future<void> _listRides() async {
    setState(() => _listOut = '...');
    try {
      final params = <String, String>{};
      if (_statusCtrl.text.trim().isNotEmpty) params['status'] = _statusCtrl.text.trim();
      final uri = Uri.parse('$_baseUrl/taxi/rides').replace(queryParameters: params.isEmpty ? null : params);
      final r = await http.get(uri, headers: await _authHeaders());
      if (r.statusCode == 200) {
        final arr = jsonDecode(r.body) as List;
        _rides = arr.cast<Map<String, dynamic>>();
        setState(() => _listOut = 'rides: ${_rides.length}');
      } else {
        setState(() => _listOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  // Manual ride creation removed from Operator UI

  Future<void> _loadQrLogs() async {
    setState(() => _listOut = '...');
    try {
      final uri = Uri.parse('$_baseUrl/taxi/topup_qr/logs').replace(queryParameters: {'limit': '200'});
      final r = await http.get(uri, headers: await _authHeaders());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final items = (j['items'] as List?) ?? const [];
        _qrLogs = items.cast<Map<String, dynamic>>();
        setState(() => _listOut = 'qr logs: ${_qrLogs.length}');
      } else {
        setState(() => _listOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => _listOut = 'error: $e');
    }
  }

  Future<void> _listComplaints() async {
    setState(() => _cOut = '...');
    try {
      final params = <String, String>{};
      if (_cSearchCtrl.text.trim().isNotEmpty) params['q'] = _cSearchCtrl.text.trim();
      if (_cStatusFilter.isNotEmpty) params['status'] = _cStatusFilter;
      final uri = Uri.parse('$_baseUrl/support/complaints').replace(queryParameters: params.isEmpty ? null : params);
      final r = await http.get(uri, headers: await _authHeaders());
      if (r.statusCode == 200) {
        final arr = jsonDecode(r.body) as List;
        _complaints = arr.cast<Map<String, dynamic>>();
        setState(() => _cOut = 'complaints: ${_complaints.length}');
      } else {
        setState(() => _cOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => _cOut = 'error: $e');
    }
  }

  Future<void> _setComplaintStatus(String id, String status) async {
    setState(() => _cOut = '...');
    try {
      final body = {'status': status};
      if (_cResolutionCtrl.text.trim().isNotEmpty) body['resolution_notes'] = _cResolutionCtrl.text.trim();
      final r = await http.patch(Uri.parse('$_baseUrl/support/complaints/$id'), headers: await _authHeaders(json: true), body: jsonEncode(body));
      setState(() => _cOut = '${r.statusCode}: ${r.body}');
      await _listComplaints();
    } catch (e) {
      setState(() => _cOut = 'error: $e');
    }
  }

  String _fmtSYP(dynamic cents) {
    try {
      final c = (cents is num) ? cents.toInt() : int.parse((cents ?? '0').toString());
      final syp = (c / 100.0).round();
      return '$syp SYP';
    } catch (_) {
      return '0 SYP';
    }
  }

  Widget _buildBaseHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: _baseCtrl, decoration: const InputDecoration(labelText: 'BFF Base URL')),
        const SizedBox(height: 8),
        TextField(controller: _tokenCtrl, decoration: const InputDecoration(labelText: 'Bearer Token (optional)')),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(onPressed: _saveBaseAndToken, child: const Text('Save')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _loadBaseAndToken, child: const Text('Load')),
        ]),
      ],
    );
  }

  Widget _buildDriversTab(List<String> classes, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBaseHeader(),
        const Divider(height: 32),

        // QR topup for taxi drivers
        Text('Taxi topup via QR', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _topupPhoneCtrl, decoration: const InputDecoration(labelText: 'Driver phone (E.164)'))),
          const SizedBox(width: 8),
          SizedBox(width: 140, child: TextField(controller: _topupAmountCtrl, decoration: const InputDecoration(labelText: 'Amount (SYP)'), keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _createTaxiTopupQr, icon: const Icon(Icons.qr_code_2), label: const Text('Generate QR')),
        if (_topupPayload.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                Text('Amount: ${_topupAmountCtrl.text.trim()} SYP'),
                const SizedBox(height: 4),
                const Text('Scan with the Taxi Driver app (topup valid for taxi drivers only)'),
                const SizedBox(height: 8),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Image.network('$_baseUrl/qr.png?data=${Uri.encodeComponent(_topupPayload)}'),
                ),
              ],
            ),
          ),
        ],

        const Divider(height: 32),

        // Driver creation
        Text('Create driver', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _dNameCtrl, decoration: const InputDecoration(labelText: 'Driver name'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _dPhoneCtrl, decoration: const InputDecoration(labelText: 'Phone (E.164)'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _dMakeCtrl, decoration: const InputDecoration(labelText: 'Vehicle make'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _dPlateCtrl, decoration: const InputDecoration(labelText: 'License plate'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            value: _dClass,
            items: classes.map((c) => DropdownMenuItem(value: c, child: Text(c.toUpperCase()))).toList(),
            onChanged: (v) => setState(() => _dClass = v ?? 'classic'),
            decoration: const InputDecoration(labelText: 'Vehicle class'),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _dColorCtrl, decoration: const InputDecoration(labelText: 'Color'))),
        ]),
        const SizedBox(height: 8),
        FilledButton(onPressed: _createDriver, child: const Text('Create driver')),
        if (_dOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_dOut)),

        const Divider(height: 32),
        Text('Drivers', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _statusCtrl, decoration: const InputDecoration(labelText: 'Status filter (optional)'))),
          const SizedBox(width: 8),
          FilledButton(onPressed: _listDrivers, child: const Text('Load drivers')),
        ]),
        const SizedBox(height: 8),
        // Balance by identity + block/unblock
        Row(children: [
          Expanded(child: TextField(controller: _balPhoneCtrl, decoration: const InputDecoration(labelText: 'Phone (for block/balance)'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _balPlateCtrl, decoration: const InputDecoration(labelText: 'License plate (for balance)'))),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: TextField(controller: _balCentsCtrl, decoration: const InputDecoration(labelText: 'Set Cents'))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _setBalanceByIdentity, child: const Text('Set balance')),
          OutlinedButton(onPressed: () => _blockPhone(true), child: const Text('Block')),
          OutlinedButton(onPressed: () => _blockPhone(false), child: const Text('Unblock')),
        ]),
        if (_listOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_listOut)),

        const Divider(height: 24),
        if (_drivers.isNotEmpty) ...[
          Text('Drivers (${_drivers.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final d in _drivers.take(50))
            ListTile(
              dense: true,
              title: Text('${d['name'] ?? ''} · ${d['phone'] ?? ''} · ${d['vehicle_plate'] ?? ''}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Class: ${d['vehicle_class'] ?? ''} · Balance: ${_fmtSYP(d['balance_cents'] ?? 0)} · Status: ${d['status'] ?? ''}'),
                  if ((d['wallet_id'] ?? '').toString().isNotEmpty)
                    Text('Wallet ID: ${d['wallet_id']}', style: const TextStyle(fontSize: 11)),
                ],
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Temporarily block',
                    icon: const Icon(Icons.block, size: 18),
                    onPressed: () => _blockTaxiDriver((d['id'] ?? '').toString(), true),
                  ),
                  IconButton(
                    tooltip: 'Unblock',
                    icon: const Icon(Icons.lock_open, size: 18),
                    onPressed: () => _blockTaxiDriver((d['id'] ?? '').toString(), false),
                  ),
                  IconButton(
                    tooltip: 'Delete permanently',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteTaxiDriver((d['id'] ?? '').toString()),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildRidesTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBaseHeader(),
        const Divider(height: 32),
        Text('Fahrten', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _statusCtrl, decoration: const InputDecoration(labelText: 'Status-Filter (optional)'))),
          const SizedBox(width: 8),
          FilledButton(onPressed: _listRides, child: const Text('Fahrten laden')),
        ]),
        if (_listOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_listOut)),
        const SizedBox(height: 12),
        if (_rides.isNotEmpty) ...[
          Text('Fahrten (${_rides.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final r in _rides.take(50))
            Builder(builder: (_) {
              final fareC = (r['fare_cents'] ?? 0) as int;
              final feeC = (r['broker_fee_cents'] ?? 0) as int;
              final payoutC = (r['driver_payout_cents'] ?? (fareC - feeC)) as int;
              final fare = _fmtSYP(fareC);
              final fee = _fmtSYP(feeC);
              final payout = _fmtSYP(payoutC);
              return ListTile(
                dense: true,
                title: Text('Ride ${r['id'] ?? ''} · ${r['status'] ?? ''} · $fare'),
                subtitle: Text(
                  'Rider: ${r['rider_phone'] ?? ''} · Driver: ${r['driver_id'] ?? ''}\n'
                  'Platform fee (SuperAdmin): $fee · Driver payout: $payout',
                ),
              );
            }),
        ],
        const Divider(height: 32),
        Text('Taxi-Topup-QRs (Audit)', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(onPressed: _loadQrLogs, icon: const Icon(Icons.refresh), label: const Text('QR-Logs laden')),
        ]),
        const SizedBox(height: 8),
        if (_qrLogs.isNotEmpty) ...[
          Text('QRs (${_qrLogs.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final it in _qrLogs.take(50))
            Builder(builder: (_) {
              final amtC = (it['amount_cents'] ?? 0) as int;
              final amt = _fmtSYP(amtC);
              final createdMs = it['created_at'] ?? 0;
              final redeemed = it['redeemed'] == true;
              final redeemedAt = it['redeemed_at'];
              DateTime? created;
              DateTime? redeemedDt;
              try {
                final ms = createdMs is int ? createdMs : int.tryParse('$createdMs') ?? 0;
                if (ms > 0) created = DateTime.fromMillisecondsSinceEpoch(ms);
              } catch (_) {}
              try {
                if (redeemedAt != null) {
                  final ms = redeemedAt is int ? redeemedAt : int.tryParse('$redeemedAt') ?? 0;
                  if (ms > 0) redeemedDt = DateTime.fromMillisecondsSinceEpoch(ms);
                }
              } catch (_) {}
              return ListTile(
                dense: true,
                leading: Icon(
                  redeemed ? Icons.check_circle_outline : Icons.hourglass_empty,
                  color: redeemed ? Colors.green : Colors.orange,
                ),
                title: Text('Driver: ${it['driver_phone'] ?? ''} · $amt'),
                subtitle: Text(
                  'Erstellt von: ${it['created_by'] ?? ''}'
                  '${created != null ? '\nErstellt: $created' : ''}'
                  '\nStatus: ${redeemed ? 'entwertet' : 'offen'}'
                  '${redeemedDt != null ? '\nEntwertet: $redeemedDt' : ''}',
                ),
              );
            }),
        ],
      ],
    );
  }

  Widget _buildComplaintsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBaseHeader(),
        const Divider(height: 32),
        Text('Complaints', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.mail_outline, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Complaints contact: $_complaintsEmail', style: Theme.of(context).textTheme.bodySmall)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.call_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Call us: $_supportPhone', style: Theme.of(context).textTheme.bodySmall)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _cSearchCtrl, decoration: const InputDecoration(labelText: 'Search (text/id/phone)'))),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _cStatusFilter,
            items: const [
              DropdownMenuItem(value: 'open', child: Text('Open')),
              DropdownMenuItem(value: 'in_review', child: Text('In review')),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
            ],
            onChanged: (v) => setState(() => _cStatusFilter = v ?? 'open'),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _listComplaints, child: const Text('Refresh')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _cResolutionCtrl, decoration: const InputDecoration(labelText: 'Note/solution (optional for status change)')),
        if (_cOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_cOut)),
        const SizedBox(height: 8),
        for (final c in _complaints) Card(
          child: ListTile(
            title: Text('#${c['id'] ?? ''} · ${(c['category'] ?? '').toString().toUpperCase()} · ${(c['status'] ?? 'open').toString().toUpperCase()}'),
            subtitle: Text(((c['description'] ?? '') as String) + '\nRide: ' + ((c['ride_id'] ?? '').toString()) + ' · Rider: ' + ((c['rider_phone'] ?? '').toString())),
            trailing: Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => _setComplaintStatus((c['id'] ?? '').toString(), 'in_review'), child: const Text('In review')),
              OutlinedButton(onPressed: () => _setComplaintStatus((c['id'] ?? '').toString(), 'resolved'), child: const Text('Resolved')),
            ]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const classes = ['classic', 'comfort', 'yellow', 'vip', 'van'];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Taxi Operator'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Drivers'),
              Tab(text: 'Rides'),
              Tab(text: 'Complaints'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDriversTab(classes, context),
            _buildRidesTab(context),
            _buildComplaintsTab(context),
          ],
        ),
      ),
    );
  }
}
