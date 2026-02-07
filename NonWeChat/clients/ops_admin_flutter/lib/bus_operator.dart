import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BusOperatorPage extends StatefulWidget {
  final String defaultBaseUrl;
  const BusOperatorPage({
    super.key,
    this.defaultBaseUrl = const String.fromEnvironment(
      'BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
  });
  @override
  State<BusOperatorPage> createState() => _BusOperatorPageState();
}

class _BusOperatorPageState extends State<BusOperatorPage> {
  final TextEditingController _baseCtrl = TextEditingController();
  final TextEditingController _tokenCtrl = TextEditingController();

  // Cities
  final TextEditingController _cityNameCtrl = TextEditingController(text: 'Damascus');
  final TextEditingController _cityCountryCtrl = TextEditingController(text: 'Syria');
  String _citiesOut = '';

  // Operators
  final TextEditingController _opNameCtrl = TextEditingController(text: 'ShamBus');
  final TextEditingController _opWalletCtrl = TextEditingController();
  String _opsOut = '';

  // Routes
  final TextEditingController _rtOriginCtrl = TextEditingController();
  final TextEditingController _rtDestCtrl = TextEditingController();
  final TextEditingController _rtOpCtrl = TextEditingController();
  String _routesOut = '';

  // Trips
  final TextEditingController _tripRouteCtrl = TextEditingController();
  final TextEditingController _tripDepCtrl = TextEditingController(text: '2025-11-20T08:00:00+00:00');
  final TextEditingController _tripArrCtrl = TextEditingController(text: '2025-11-20T12:00:00+00:00');
  final TextEditingController _tripPriceCtrl = TextEditingController(text: '12000');
  final TextEditingController _tripSeatsCtrl = TextEditingController(text: '40');
  String _tripsOut = '';

  // Search
  final TextEditingController _sOriginCtrl = TextEditingController();
  final TextEditingController _sDestCtrl = TextEditingController();
  final TextEditingController _sDateCtrl = TextEditingController(text: '2025-11-20');

  // Booking
  final TextEditingController _bTripCtrl = TextEditingController();
  final TextEditingController _bSeatsCtrl = TextEditingController(text: '1');
  final TextEditingController _bWalletCtrl = TextEditingController();
  final TextEditingController _bPhoneCtrl = TextEditingController();
  String _bookOut = '';

  // Tickets + boarding
  final TextEditingController _tBookingCtrl = TextEditingController();
  final TextEditingController _tPayloadCtrl = TextEditingController();
  String _ticketsOut = '';

  Future<SharedPreferences> get _sp async => SharedPreferences.getInstance();
  String get _baseUrl => _baseCtrl.text.trim();

  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final prefs = await _sp;
    final t = _tokenCtrl.text.trim().isNotEmpty
        ? _tokenCtrl.text.trim()
        : (prefs.getString('shamell_jwt') ?? prefs.getString('jwt') ?? prefs.getString('access_token') ?? '');
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
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _baseCtrl.text = widget.defaultBaseUrl;
    scheduleMicrotask(_loadBaseAndToken);
  }

  // Actions
  Future<void> _health() async {
    setState(() => _citiesOut = '...');
    try {
      final r = await http.get(Uri.parse('$_baseUrl/bus/health'), headers: await _authHeaders());
      setState(() => _citiesOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _citiesOut = 'error: $e');
    }
  }

  Future<void> _addCity() async {
    setState(() => _citiesOut = '...');
    try {
      final r = await http.post(Uri.parse('$_baseUrl/bus/cities'), headers: await _authHeaders(json: true), body: jsonEncode({'name': _cityNameCtrl.text.trim(), 'country': _cityCountryCtrl.text.trim()}));
      setState(() => _citiesOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _citiesOut = 'error: $e');
    }
  }

  Future<void> _listCities() async {
    setState(() => _citiesOut = '...');
    try {
      final r = await http.get(Uri.parse('$_baseUrl/bus/cities_cached'), headers: await _authHeaders());
      setState(() => _citiesOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _citiesOut = 'error: $e');
    }
  }

  Future<void> _addOperator() async {
    setState(() => _opsOut = '...');
    try {
      final body = {'name': _opNameCtrl.text.trim(), 'wallet_id': _opWalletCtrl.text.trim().isEmpty ? null : _opWalletCtrl.text.trim()};
      final r = await http.post(Uri.parse('$_baseUrl/bus/operators'), headers: await _authHeaders(json: true), body: jsonEncode(body));
      setState(() => _opsOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _opsOut = 'error: $e');
    }
  }

  Future<void> _listOperators() async {
    setState(() => _opsOut = '...');
    try {
      final r = await http.get(Uri.parse('$_baseUrl/bus/operators'), headers: await _authHeaders());
      setState(() => _opsOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _opsOut = 'error: $e');
    }
  }

  Future<void> _addRoute() async {
    setState(() => _routesOut = '...');
    try {
      final body = {'origin_city_id': _rtOriginCtrl.text.trim(), 'dest_city_id': _rtDestCtrl.text.trim(), 'operator_id': _rtOpCtrl.text.trim()};
      final r = await http.post(Uri.parse('$_baseUrl/bus/routes'), headers: await _authHeaders(json: true), body: jsonEncode(body));
      setState(() => _routesOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _routesOut = 'error: $e');
    }
  }

  Future<void> _listRoutes() async {
    setState(() => _routesOut = '...');
    try {
      final oc = _rtOriginCtrl.text.trim();
      final dc = _rtDestCtrl.text.trim();
      final uri = Uri.parse('$_baseUrl/bus/routes').replace(queryParameters: {
        if (oc.isNotEmpty) 'origin_city_id': oc,
        if (dc.isNotEmpty) 'dest_city_id': dc,
      });
      final r = await http.get(uri, headers: await _authHeaders());
      setState(() => _routesOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _routesOut = 'error: $e');
    }
  }

  Future<void> _addTrip() async {
    setState(() => _tripsOut = '...');
    try {
      final body = {
        'route_id': _tripRouteCtrl.text.trim(),
        'depart_at_iso': _tripDepCtrl.text.trim(),
        'arrive_at_iso': _tripArrCtrl.text.trim(),
        'price_cents': int.tryParse(_tripPriceCtrl.text.trim()) ?? 0,
        'currency': 'SYP',
        'seats_total': int.tryParse(_tripSeatsCtrl.text.trim()) ?? 40,
      };
      final r = await http.post(Uri.parse('$_baseUrl/bus/trips'), headers: await _authHeaders(json: true), body: jsonEncode(body));
      setState(() => _tripsOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _tripsOut = 'error: $e');
    }
  }

  Future<void> _searchTrips() async {
    setState(() => _tripsOut = '...');
    try {
      final uri = Uri.parse('$_baseUrl/bus/trips/search').replace(queryParameters: {
        'origin_city_id': _sOriginCtrl.text.trim(),
        'dest_city_id': _sDestCtrl.text.trim(),
        'date': _sDateCtrl.text.trim(),
      });
      final r = await http.get(uri, headers: await _authHeaders());
      final t = r.body;
      setState(() => _tripsOut = '${r.statusCode}: $t');
      try {
        final arr = jsonDecode(t) as List;
        if (arr.isNotEmpty) {
          final tripId = (arr[0]['trip'] ?? const {})['id']?.toString() ?? '';
          if (tripId.isNotEmpty) _bTripCtrl.text = tripId;
        }
      } catch (_) {}
    } catch (e) {
      setState(() => _tripsOut = 'error: $e');
    }
  }

  Future<void> _bookTrip() async {
    setState(() => _bookOut = '...');
    try {
      final body = {
        'seats': int.tryParse(_bSeatsCtrl.text.trim()) ?? 1,
        'wallet_id': _bWalletCtrl.text.trim().isEmpty ? null : _bWalletCtrl.text.trim(),
        'customer_phone': _bPhoneCtrl.text.trim().isEmpty ? null : _bPhoneCtrl.text.trim(),
      };
      final r = await http.post(Uri.parse('$_baseUrl/bus/trips/${Uri.encodeComponent(_bTripCtrl.text.trim())}/book'), headers: (await _authHeaders(json: true))..['Idempotency-Key'] = 'ui-${DateTime.now().millisecondsSinceEpoch}', body: jsonEncode(body));
      setState(() => _bookOut = '${r.statusCode}: ${r.body}');
      try {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if ((j['id'] ?? '').toString().isNotEmpty) _tBookingCtrl.text = j['id'].toString();
      } catch (_) {}
    } catch (e) {
      setState(() => _bookOut = 'error: $e');
    }
  }

  Future<void> _loadTickets() async {
    setState(() => _ticketsOut = '...');
    try {
      final r = await http.get(Uri.parse('$_baseUrl/bus/bookings/${Uri.encodeComponent(_tBookingCtrl.text.trim())}/tickets'), headers: await _authHeaders());
      setState(() => _ticketsOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _ticketsOut = 'error: $e');
    }
  }

  Future<void> _boardTicket() async {
    setState(() => _ticketsOut = '...');
    try {
      final r = await http.post(Uri.parse('$_baseUrl/bus/tickets/board'), headers: await _authHeaders(json: true), body: jsonEncode({'payload': _tPayloadCtrl.text.trim()}));
      setState(() => _ticketsOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _ticketsOut = 'error: $e');
    }
  }

  Future<void> _scanQR() async {
    final payload = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _QRScanPage()));
    if (!mounted) return;
    if (payload != null && payload.isNotEmpty) {
      setState(() => _tPayloadCtrl.text = payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bus Operator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _baseCtrl, decoration: const InputDecoration(labelText: 'BFF Base URL')),
          const SizedBox(height: 8),
          TextField(controller: _tokenCtrl, decoration: const InputDecoration(labelText: 'Bearer Token (optional)')),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: _saveBaseAndToken, child: const Text('Save')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _loadBaseAndToken, child: const Text('Load')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _health, child: const Text('Health')),
          ]),

          const Divider(height: 28),
          Text('Cities', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            Expanded(child: TextField(controller: _cityNameCtrl, decoration: const InputDecoration(labelText: 'Name'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _cityCountryCtrl, decoration: const InputDecoration(labelText: 'Land'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _addCity, child: const Text('Add')), const SizedBox(width: 8),
            OutlinedButton(onPressed: _listCities, child: const Text('List')),
          ]),
          if (_citiesOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_citiesOut)),

          const Divider(height: 28),
          Text('Operators', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            Expanded(child: TextField(controller: _opNameCtrl, decoration: const InputDecoration(labelText: 'Name'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _opWalletCtrl, decoration: const InputDecoration(labelText: 'Wallet ID'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _addOperator, child: const Text('Add')), const SizedBox(width: 8),
            OutlinedButton(onPressed: _listOperators, child: const Text('List')),
          ]),
          if (_opsOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_opsOut)),

          const Divider(height: 28),
          Text('Routes', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            Expanded(child: TextField(controller: _rtOriginCtrl, decoration: const InputDecoration(labelText: 'Origin City ID'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _rtDestCtrl, decoration: const InputDecoration(labelText: 'Dest City ID'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _rtOpCtrl, decoration: const InputDecoration(labelText: 'Operator ID'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: _addRoute, child: const Text('Create Route')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _listRoutes, child: const Text('List Routes')),
          ]),
          if (_routesOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_routesOut)),

          const Divider(height: 28),
          Text('Trips', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            Expanded(child: TextField(controller: _tripRouteCtrl, decoration: const InputDecoration(labelText: 'Route ID'))),
            const SizedBox(width: 8),
            SizedBox(width: 130, child: TextField(controller: _tripPriceCtrl, decoration: const InputDecoration(labelText: 'Price (cents)'))),
            const SizedBox(width: 8),
            SizedBox(width: 100, child: TextField(controller: _tripSeatsCtrl, decoration: const InputDecoration(labelText: 'Seats'))),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: _tripDepCtrl, decoration: const InputDecoration(labelText: 'Depart ISO'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _tripArrCtrl, decoration: const InputDecoration(labelText: 'Arrive ISO'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: _addTrip, child: const Text('Create Trip')),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _sOriginCtrl, decoration: const InputDecoration(labelText: 'Search: Origin City'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _sDestCtrl, decoration: const InputDecoration(labelText: 'Search: Dest City'))),
            const SizedBox(width: 8),
            SizedBox(width: 140, child: TextField(controller: _sDateCtrl, decoration: const InputDecoration(labelText: 'YYYY-MM-DD'))),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _searchTrips, child: const Text('Search')),
          ]),
          if (_tripsOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_tripsOut)),

          const Divider(height: 28),
          Text('Booking', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            Expanded(child: TextField(controller: _bTripCtrl, decoration: const InputDecoration(labelText: 'Trip ID'))),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: _bSeatsCtrl, decoration: const InputDecoration(labelText: 'Seats'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _bWalletCtrl, decoration: const InputDecoration(labelText: 'Wallet ID (optional)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _bPhoneCtrl, decoration: const InputDecoration(labelText: 'Phone (optional)'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _bookTrip, child: const Text('Book')),
          ]),
          if (_bookOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_bookOut)),

          const Divider(height: 28),
          Text('Tickets & Boarding', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            Expanded(child: TextField(controller: _tBookingCtrl, decoration: const InputDecoration(labelText: 'Booking ID'))),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _loadTickets, child: const Text('Load Tickets')),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _tPayloadCtrl, decoration: const InputDecoration(labelText: 'Ticket Payload (QR Text)')),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: _boardTicket, child: const Text('Board')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _scanQR, child: const Text('Scan QR')),
          ]),
          if (_ticketsOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_ticketsOut)),
        ],
      ),
    );
  }
}

// --- Simple QR Scan Page using mobile_scanner ---

class _QRScanPage extends StatefulWidget {
  const _QRScanPage();
  @override
  State<_QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<_QRScanPage> {
  bool _done = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Ticket QR')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            final barcodes = capture.barcodes;
            for (final b in barcodes) {
              final v = b.rawValue?.trim();
              if (v != null && v.isNotEmpty) {
                _done = true;
                Navigator.pop(context, v);
                break;
              }
            }
          },
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(12.0),
            child: Text('Richte die Kamera auf den Ticket‑QR', textAlign: TextAlign.center),
          ),
        ),
      ]),
    );
  }
}
