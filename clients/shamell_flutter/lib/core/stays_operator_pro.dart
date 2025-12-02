import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modern Stays operator UI inspired by booking.com style dashboards.
/// Uses local sample data; wire real API calls later.
class StaysOperatorProPage extends StatefulWidget {
  final String baseUrl;
  const StaysOperatorProPage(this.baseUrl, {super.key});

  @override
  State<StaysOperatorProPage> createState() => _StaysOperatorProPageState();
}

class _StaysOperatorProPageState extends State<StaysOperatorProPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final DateFormat _df = DateFormat('EEE d MMM');
  final DateFormat _ymd = DateFormat('yyyy-MM-dd');

  int? _opId;
  String? _token;
  bool _loading = true;
  String _error = '';
  String _statusFilter = '';
  List<Map<String, dynamic>> _properties = [];
  int? _propertyFilter;

  // Room types loaded from backend
  final List<Map<String, dynamic>> _roomTypes = [];
  final List<DateTime> _dates = List<DateTime>.generate(
    14,
    (i) => DateTime.now().add(Duration(days: i)),
  );
  final Map<String, Map<String, Map<String, dynamic>>> _rates = {};

  // Live bookings and housekeeping/ledger
  final List<Map<String, dynamic>> _bookings = [];
  final Map<String, List<String>> _hk = {};
  final List<Map<String, dynamic>> _ledger = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final sp = await SharedPreferences.getInstance();
      final opId = sp.getInt('stays_op_id');
      final tok = sp.getString('stays_op_token');
      if (opId == null || tok == null || tok.isEmpty) {
        setState(() {
          _error = 'Keine Operator-Anmeldung gefunden. Bitte zuerst im Operator-Login anmelden.';
          _loading = false;
        });
        return;
      }
      _opId = opId;
      _token = tok;
      await _loadProperties();
      await _loadRoomTypesAndRates();
      await _loadBookings();
      await _loadHousekeeping();
      await _loadFinanceFromBookings();
    } catch (e) {
      setState(() {
        _error = 'Fehler: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String get _base => widget.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Map<String, String> _authHeaders({bool json = false}) {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    if (_token != null) h['authorization'] = 'Bearer $_token';
    return h;
  }

  Future<void> _loadRoomTypesAndRates() async {
    if (_opId == null) return;
    // room types
    final rtUri = Uri.parse('$_base/stays/operators/${_opId}/room_types');
    final r = await http.get(rtUri, headers: _authHeaders());
    if (r.statusCode != 200) {
      throw Exception('Room types: ${r.statusCode}: ${r.body}');
    }
    final list = jsonDecode(r.body) as List;
    _roomTypes
      ..clear()
      ..addAll(list.map((e) => {
            'id': e['id'],
            'title': e['title'] ?? '',
            'base_price_cents': e['base_price_cents'] ?? 0,
          }));
    // rates per room type
    _rates.clear();
    for (int idx = 0; idx < _roomTypes.length; idx++) {
      final rt = _roomTypes[idx];
      final rtId = rt['id'];
      final roomTitle = rt['title'] ?? 'Room $idx';
      _rates[roomTitle] = {};
      final frm = _ymd.format(_dates.first);
      final to = _ymd.format(_dates.last);
      final rateUri = Uri.parse('$_base/stays/operators/${_opId}/room_types/$rtId/rates?frm=$frm&to=$to');
      final rr = await http.get(rateUri, headers: _authHeaders());
      if (rr.statusCode != 200) {
        throw Exception('Rates: ${rr.statusCode}: ${rr.body}');
      }
      final items = (jsonDecode(rr.body)['items'] as List?) ?? [];
      for (final it in items) {
        final date = ((it['date'] ?? '') as String).substring(0, 10);
        _rates[roomTitle]![date] = {
          'price': it['price_cents'] ?? 0,
          'allot': it['allotment'] ?? 0,
          'closed': (it['closed'] ?? false) == true,
        };
      }
      // fill missing with defaults
      for (final d in _dates) {
        final key = _ymd.format(d);
        _rates[roomTitle]![key] ??= {'price': rt['base_price_cents'] ?? 0, 'allot': 0, 'closed': false};
      }
    }
  }

  Future<void> _loadBookings() async {
    if (_opId == null) return;
    final qs = <String, String>{
      'limit': '50',
      'offset': '0',
      'order': 'desc',
      'sort_by': 'from',
    };
    if (_statusFilter.isNotEmpty) qs['status'] = _statusFilter;
    if (_propertyFilter != null) qs['property_id'] = _propertyFilter.toString();
    final uri = Uri.parse('$_base/stays/operators/${_opId}/bookings/search').replace(queryParameters: qs);
    final r = await http.get(uri, headers: _authHeaders());
    if (r.statusCode != 200) {
      throw Exception('Bookings: ${r.statusCode}: ${r.body}');
    }
    final j = jsonDecode(r.body);
    final items = (j['items'] as List?) ?? [];
    _bookings
      ..clear()
      ..addAll(items.map((b) {
        return {
          'id': b['id'] ?? '',
          'guest': b['guest_name'] ?? '',
          'room': b['listing_id']?.toString() ?? '',
          'from': DateTime.tryParse(b['from_iso'] ?? '') ?? DateTime.now(),
          'to': DateTime.tryParse(b['to_iso'] ?? '') ?? DateTime.now().add(const Duration(days: 1)),
          'price': b['amount_cents'] ?? 0,
          'status': b['status'] ?? '',
        };
      }));
  }

  Future<void> _loadProperties() async {
    if (_opId == null) return;
    final uri = Uri.parse('$_base/stays/operators/${_opId}/properties');
    final r = await http.get(uri, headers: _authHeaders());
    if (r.statusCode != 200) return;
    final list = (jsonDecode(r.body) as List?) ?? [];
    _properties = list
        .map((p) => {
              'id': p['id'],
              'name': p['name'] ?? 'Property ${p['id']}',
            })
        .toList();
  }

  Future<void> _loadHousekeeping() async {
    if (_opId == null) return;
    final uri = Uri.parse('$_base/stays/operators/${_opId}/rooms');
    final r = await http.get(uri, headers: _authHeaders());
    if (r.statusCode != 200) {
      throw Exception('Rooms: ${r.statusCode}: ${r.body}');
    }
    final items = (jsonDecode(r.body) as List?) ?? [];
    final hk = <String, List<String>>{'dirty': [], 'cleaning': [], 'inspected': [], 'clean': []};
    for (final it in items) {
      final status = (it['status'] ?? 'clean').toString();
      final code = it['code']?.toString() ?? '-';
      hk.putIfAbsent(status, () => []).add(code);
    }
    _hk
      ..clear()
      ..addAll(hk);
  }

  Future<void> _loadFinanceFromBookings() async {
    _ledger.clear();
    if (_bookings.isEmpty) return;
    _ledger.addAll(_bookings.take(5).map((b) {
      return {
        'label': 'Booking ${b['guest']}',
        'amount': b['price'],
        'date': b['from'] as DateTime,
      };
    }));
  }

  void _editCell(String room, DateTime day) async {
    final key = _ymd.format(day);
    final data = _rates[room]![key]!;
    final priceCtrl = TextEditingController(text: data['price'].toString());
    final allotCtrl = TextEditingController(text: data['allot'].toString());
    bool closed = data['closed'] as bool;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$room · ${_df.format(day)}',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Preis (SYP)',
                  prefixIcon: Icon(Icons.price_change_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: allotCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kontingent',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Geschlossen'),
                value: closed,
                onChanged: (v) => setState(() => closed = v),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  await _saveRate(room, day,
                      price: int.tryParse(priceCtrl.text),
                      allot: int.tryParse(allotCtrl.text),
                      closed: closed);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _openBulk() {
    final from = TextEditingController(text: _df.format(_dates.first));
    final to = TextEditingController(text: _df.format(_dates.last));
    final price = TextEditingController();
    final allot = TextEditingController();
    bool closed = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bulk bearbeiten', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: from,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Von'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: to,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Bis'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                decoration: const InputDecoration(labelText: 'Preis setzen (optional)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: allot,
                decoration: const InputDecoration(labelText: 'Kontingent setzen (optional)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Schließen'),
                value: closed,
                onChanged: (v) => setState(() => closed = v),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  await _applyBulk(
                    price: price.text.isNotEmpty ? int.tryParse(price.text) : null,
                    allot: allot.text.isNotEmpty ? int.tryParse(allot.text) : null,
                    closed: closed,
                  );
                  if (mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Übernehmen'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hotel Operator'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Kalender'),
            Tab(text: 'Bookings'),
            Tab(text: 'Housekeeping'),
            Tab(text: 'Finance'),
          ],
          isScrollable: true,
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildDashboard(context),
          _buildCalendar(context),
          _buildBookings(context),
          _buildHousekeeping(context),
          _buildFinance(context),
        ],
      ),
    );
  }

  Widget _buildDashboard(BuildContext ctx) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi('Auslastung heute', '82%', Icons.hotel_class),
              _kpi('ADR', '240,000 SYP', Icons.attach_money),
              _kpi('RevPAR', '196,800 SYP', Icons.trending_up),
              _kpi('Stornorate', '4%', Icons.cancel_schedule_send),
            ],
          ),
          const SizedBox(height: 16),
          Text('Nächste Check-ins/Outs', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          _card(
            child: Column(
              children: _bookings.map((b) {
                final checkIn = DateFormat('EEE, d MMM').format(b['from'] as DateTime);
                final checkOut = DateFormat('EEE, d MMM').format(b['to'] as DateTime);
                return ListTile(
                  leading: const Icon(Icons.login),
                  title: Text(b['guest'] as String),
                  subtitle: Text('${b['room']} · $checkIn → $checkOut'),
                  trailing: Chip(label: Text(b['status'] as String)),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Aktionen', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _openBulk,
                icon: const Icon(Icons.calendar_month),
                label: const Text('Bulk Kalender bearbeiten'),
              ),
              OutlinedButton.icon(
                onPressed: () => _tab.animateTo(2),
                icon: const Icon(Icons.view_list_outlined),
                label: const Text('Bookings öffnen'),
              ),
              OutlinedButton.icon(
                onPressed: () => _tab.animateTo(3),
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Housekeeping'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext ctx) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error));
    }
    if (_roomTypes.isEmpty) {
      return const Center(child: Text('Keine Zimmerkategorien vorhanden.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('Kalender', style: Theme.of(ctx).textTheme.titleMedium),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _openBulk,
                icon: const Icon(Icons.tune),
                label: const Text('Bulk'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 220 + (_dates.length * 120),
              child: ListView(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 220),
                      ..._dates.map((d) {
                        return Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade300),
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(DateFormat('EEE').format(d), style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(DateFormat('d MMM').format(d)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                  ..._roomTypes.map((rt) {
                    final room = rt['title'] as String;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 220,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade300),
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                            color: Colors.grey.shade50,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(room, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              const Text('2 Gäste · Frühstück inkl.'),
                            ],
                        ),
                      ),
                      ..._dates.map((d) {
                        final key = _ymd.format(d);
                        final data = _rates[room]![key]!;
                          final closed = data['closed'] as bool;
                          final price = data['price'] as int;
                          final allot = data['allot'] as int;
                          return InkWell(
                            onTap: () => _editCell(room, d),
                            child: Container(
                              width: 120,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(color: Colors.grey.shade300),
                                  bottom: BorderSide(color: Colors.grey.shade300),
                                ),
                                color: closed ? Colors.red.shade50 : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('${(price / 1000).round()}k'),
                                      const Spacer(),
                                      Icon(
                                        closed ? Icons.block : Icons.check_circle_outline,
                                        size: 16,
                                        color: closed ? Colors.red : Colors.green,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Allot: $allot', style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookings(BuildContext ctx) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('Bookings', style: Theme.of(ctx).textTheme.titleMedium),
              const Spacer(),
              Text('${_bookings.length} Einträge'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _propertyFilter,
                  decoration: const InputDecoration(labelText: 'Property', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Alle')),
                    ..._properties.map((p) => DropdownMenuItem<int?>(
                          value: p['id'] as int?,
                          child: Text(p['name'] as String),
                        )),
                  ],
                  onChanged: (v) async {
                    setState(() => _propertyFilter = v);
                    await _loadBookings();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _statusFilter.isEmpty ? null : _statusFilter,
                  decoration: const InputDecoration(labelText: 'Status', isDense: true),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('Alle')),
                    DropdownMenuItem<String?>(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem<String?>(value: 'confirmed', child: Text('Confirmed')),
                    DropdownMenuItem<String?>(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem<String?>(value: 'canceled', child: Text('Canceled')),
                    DropdownMenuItem<String?>(value: 'checked-in', child: Text('Checked-in')),
                  ],
                  onChanged: (v) async {
                    setState(() => _statusFilter = v ?? '');
                    await _loadBookings();
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _bookings.length,
            itemBuilder: (ctx, i) {
              final b = _bookings[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(b['guest'] as String),
                  subtitle: Text(
                      '${b['room']} · ${_df.format(b['from'] as DateTime)} → ${_df.format(b['to'] as DateTime)}'),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${b['price']} SYP'),
                      const SizedBox(height: 4),
                      Chip(label: Text((b['status'] ?? '').toString())),
                    ],
                  ),
                  onTap: () => _openBookingDrawer(b),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openBookingDrawer(Map<String, dynamic> b) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b['guest'] as String, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${b['room']} · ${_df.format(b['from'] as DateTime)} → ${_df.format(b['to'] as DateTime)}'),
              const SizedBox(height: 8),
              Chip(label: Text(b['status'] as String)),
              const SizedBox(height: 8),
              Text('Preis: ${b['price']} SYP'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _updateBookingStatus(b, 'confirmed'),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('Bestätigen'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _updateBookingStatus(b, 'canceled'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Stornieren'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _updateBookingStatus(b, 'completed'),
                    icon: const Icon(Icons.swap_horiz_outlined),
                    label: const Text('Abschließen'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHousekeeping(BuildContext ctx) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error));
    }
    if (_hk.isEmpty) {
      return const Center(child: Text('Keine Zimmer geladen.'));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _hk.entries.map((e) {
          return Expanded(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key.toUpperCase(), style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: e.value
                          .map((room) => Chip(
                                label: Text(room),
                                backgroundColor: e.key == 'dirty'
                                    ? Colors.red.shade50
                                    : e.key == 'cleaning'
                                        ? Colors.amber.shade50
                                        : Colors.green.shade50,
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFinance(BuildContext ctx) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Finance & Payouts', style: Theme.of(ctx).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._ledger.map((l) {
          return ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(l['label'] as String),
            subtitle: Text(DateFormat('d MMM y').format(l['date'] as DateTime)),
            trailing: Text('${l['amount']} SYP'),
          );
        }),
      ],
    );
  }

  Widget _kpi(String label, String value, IconData icon) {
    return SizedBox(
      width: 200,
      child: _card(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: Icon(icon, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Card _card({required Widget child}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }

  Future<void> _saveRate(String room, DateTime day, {int? price, int? allot, bool? closed}) async {
    if (_opId == null || _token == null) return;
    final rt = _roomTypes.firstWhere((rt) => rt['title'] == room, orElse: () => {});
    final rtId = rt['id'];
    if (rtId == null) return;
    final body = {
      'days': [
        {
          'date': _ymd.format(day),
          if (price != null) 'price_cents': price,
          if (allot != null) 'allotment': allot,
          if (closed != null) 'closed': closed,
        }
      ]
    };
    final uri = Uri.parse('$_base/stays/operators/${_opId}/room_types/$rtId/rates');
    final r = await http.post(uri, headers: _authHeaders(json: true), body: jsonEncode(body));
    if (r.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: ${r.statusCode}')));
      return;
    }
    setState(() {
      final key = _ymd.format(day);
      _rates[room]![key]!['price'] = price ?? _rates[room]![key]!['price'];
      _rates[room]![key]!['allot'] = allot ?? _rates[room]![key]!['allot'];
      if (closed != null) _rates[room]![key]!['closed'] = closed;
    });
  }

  Future<void> _applyBulk({int? price, int? allot, bool? closed}) async {
    if (_opId == null || _token == null) return;
    for (final rt in _roomTypes) {
      final rtId = rt['id'];
      if (rtId == null) continue;
      final body = {
        'days': _dates
            .map((d) => {
                  'date': _ymd.format(d),
                  if (price != null) 'price_cents': price,
                  if (allot != null) 'allotment': allot,
                  if (closed != null) 'closed': closed,
                })
            .toList()
      };
      final uri = Uri.parse('$_base/stays/operators/${_opId}/room_types/$rtId/rates');
      final r = await http.post(uri, headers: _authHeaders(json: true), body: jsonEncode(body));
      if (r.statusCode != 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bulk fehlgeschlagen: ${r.statusCode}')));
        return;
      }
    }
    await _loadRoomTypesAndRates();
    if (mounted) setState(() {});
  }

  Future<void> _updateBookingStatus(Map<String, dynamic> b, String status) async {
    if (_opId == null || _token == null) return;
    final bid = b['id']?.toString() ?? '';
    if (bid.isEmpty) return;
    final uri = Uri.parse('$_base/stays/operators/${_opId}/bookings/$bid/status');
    try {
      final r = await http.post(uri, headers: _authHeaders(json: true), body: jsonEncode({'status': status}));
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _loadBookings();
        if (mounted) setState(() {});
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status aktualisiert: $status')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: ${r.statusCode}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }
}
