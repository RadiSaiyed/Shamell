import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Modern PMS slice: dashboard + calendar/reservations +
/// housekeeping and rate management, backed by /pms endpoints.
class PmsGlassPage extends StatefulWidget {
  final String baseUrl;
  const PmsGlassPage(this.baseUrl, {super.key});

  @override
  State<PmsGlassPage> createState() => _PmsGlassPageState();
}

class _PmsGlassPageState extends State<PmsGlassPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final DateFormat _ymd = DateFormat('yyyy-MM-dd');

  bool _loading = true;
  String _error = '';
  int? _propertyId;

  final List<Map<String, dynamic>> _properties = [];
  final List<Map<String, dynamic>> _roomTypes = [];
  final List<Map<String, dynamic>> _rooms = [];
  final List<Map<String, dynamic>> _bookings = [];
  final List<Map<String, dynamic>> _ratePlans = [];
  Map<int, int> _availability = {}; // room_type_id -> available count for range
  Map<String, dynamic> _stats = {
    'occupancy_pct': 0.0,
    'arrivals': 0,
    'departures': 0,
    'revenue_cents': 0,
    'active_bookings': 0,
  };
  final List<Map<String, String>> _channelMappings = [];
  final TextEditingController _channelExt = TextEditingController(text: 'OTA-12345');
  String _channel = 'airbnb';

  // Form state
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now().add(const Duration(days: 2));
  int? _bookingRoomTypeId;
  final TextEditingController _guestName = TextEditingController();
  final TextEditingController _guestPhone = TextEditingController();
  bool _confirmBooking = true;
  int? _rateRoomType;
  final TextEditingController _rateName = TextEditingController();
  final TextEditingController _ratePrice = TextEditingController(text: '120000');
  final TextEditingController _propName = TextEditingController(text: 'Hotel Shamell');
  final TextEditingController _propCity = TextEditingController(text: 'Damascus');
  final TextEditingController _rtName = TextEditingController(text: 'Standard Room');
  final TextEditingController _rtGuests = TextEditingController(text: '2');
  final TextEditingController _roomCode = TextEditingController(text: '101');
  int? _roomRoomType;

  String get _base => widget.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    _guestName.dispose();
    _guestPhone.dispose();
    _rateName.dispose();
    _ratePrice.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await _loadProperties();
      if (_propertyId == null && _properties.isNotEmpty) {
        _propertyId = _properties.first['id'] as int?;
      }
      await Future.wait([
        _loadRoomTypes(),
        _loadRooms(),
        _loadBookings(),
        _loadRatePlans(),
        _loadAvailability(),
        _loadStats(),
        _loadChannels(),
      ]);
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadProperties() async {
    final uri = Uri.parse('$_base/pms/properties');
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('properties ${r.statusCode}');
    final arr = jsonDecode(r.body) as List;
    _properties
      ..clear()
      ..addAll(arr.map((e) => {'id': e['id'], 'name': e['name'] ?? 'Property ${e['id']}', 'city': e['city'] ?? ''}));
  }

  Future<void> _loadRoomTypes() async {
    final qs = _propertyId != null ? '?property_id=$_propertyId' : '';
    final uri = Uri.parse('$_base/pms/room_types$qs');
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('room types ${r.statusCode}');
    final arr = jsonDecode(r.body) as List;
    _roomTypes
      ..clear()
      ..addAll(arr.map((e) => {
            'id': e['id'],
            'name': e['name'] ?? '',
            'max_guests': e['max_guests'] ?? 2,
          }));
    if (_bookingRoomTypeId == null && _roomTypes.isNotEmpty) {
      _bookingRoomTypeId = _roomTypes.first['id'] as int?;
    }
    if (_rateRoomType == null && _roomTypes.isNotEmpty) {
      _rateRoomType = _roomTypes.first['id'] as int?;
    }
  }

  Future<void> _loadRooms() async {
    final qs = _propertyId != null ? '?property_id=$_propertyId' : '';
    final uri = Uri.parse('$_base/pms/rooms$qs');
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('rooms ${r.statusCode}');
    final arr = jsonDecode(r.body) as List;
    _rooms
      ..clear()
      ..addAll(arr.map((e) => {
            'id': e['id'],
            'code': e['code'] ?? '',
            'housekeeping_status': e['housekeeping_status'] ?? 'clean',
            'room_type_id': e['room_type_id'],
          }));
  }

  Future<void> _loadBookings() async {
    final params = <String, String>{};
    if (_propertyId != null) params['property_id'] = '$_propertyId';
    final uri = Uri.parse('$_base/pms/bookings').replace(queryParameters: params.isEmpty ? null : params);
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('bookings ${r.statusCode}');
    final arr = jsonDecode(r.body) as List;
    _bookings
      ..clear()
      ..addAll(arr.map((b) {
        DateTime? from;
        DateTime? to;
        try {
          from = DateTime.parse(b['from_date']);
          to = DateTime.parse(b['to_date']);
        } catch (_) {}
        return {
          'id': b['id'],
          'property_id': b['property_id'],
          'room_type_id': b['room_type_id'],
          'room_id': b['room_id'],
          'guest': b['guest_name'] ?? '',
          'phone': b['guest_phone'] ?? '',
          'from': from,
          'to': to,
          'status': b['status'] ?? '',
          'total_cents': b['total_cents'] ?? 0,
        };
      }));
  }

  Future<void> _loadRatePlans() async {
    final params = <String, String>{};
    if (_propertyId != null) params['property_id'] = '$_propertyId';
    final uri = Uri.parse('$_base/pms/rate_plans').replace(queryParameters: params.isEmpty ? null : params);
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('rates ${r.statusCode}');
    final arr = jsonDecode(r.body) as List;
    _ratePlans
      ..clear()
      ..addAll(arr.map((rp) => {
            'id': rp['id'],
            'name': rp['name'] ?? '',
            'room_type_id': rp['room_type_id'],
            'price_per_night_cents': rp['price_per_night_cents'] ?? 0,
            'currency': rp['currency'] ?? 'SYP',
          }));
  }

  Future<void> _loadAvailability() async {
    if (_propertyId == null) {
      _availability = {};
      return;
    }
    final params = {
      'property_id': '$_propertyId',
      'from_iso': _ymd.format(_from),
      'to_iso': _ymd.format(_to),
    };
    final uri = Uri.parse('$_base/pms/availability').replace(queryParameters: params);
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('availability ${r.statusCode}');
    final arr = jsonDecode(r.body) as List;
    final map = <int, int>{};
    for (final a in arr) {
      map[a['room_type_id'] as int] = a['available'] ?? 0;
    }
    _availability = map;
  }

  Future<void> _loadStats() async {
    if (_propertyId == null) return;
    final uri = Uri.parse('$_base/pms/stats').replace(queryParameters: {
      'property_id': '$_propertyId',
      'from_iso': _ymd.format(_from),
      'to_iso': _ymd.format(_to),
    });
    final r = await http.get(uri);
    if (r.statusCode != 200) return;
    _stats = jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _loadChannels() async {
    final params = <String, String>{};
    if (_propertyId != null) params['property_id'] = '$_propertyId';
    final uri = Uri.parse('$_base/pms/channel/mappings').replace(queryParameters: params.isEmpty ? null : params);
    final r = await http.get(uri);
    if (r.statusCode != 200) return;
    final arr = jsonDecode(r.body) as List;
    _channelMappings
      ..clear()
      ..addAll(arr.map((m) => {
            'channel': m['channel']?.toString() ?? '',
            'external_id': m['external_id']?.toString() ?? '',
            'property_id': m['property_id']?.toString() ?? '',
          }));
  }

  Future<void> _createBooking() async {
    if (_propertyId == null || _bookingRoomTypeId == null) return;
    final body = {
      'property_id': _propertyId,
      'room_type_id': _bookingRoomTypeId,
      'room_id': null,
      'guest_name': _guestName.text.trim().isEmpty ? 'Walk-in guest' : _guestName.text.trim(),
      'guest_phone': _guestPhone.text.trim().isEmpty ? null : _guestPhone.text.trim(),
      'from_iso': _ymd.format(_from),
      'to_iso': _ymd.format(_to),
      'confirm': _confirmBooking,
    };
    final uri = Uri.parse('$_base/pms/bookings');
    final r = await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode(body));
    if (r.statusCode >= 300) {
      throw Exception('Booking failed ${r.statusCode}: ${r.body}');
    }
    await _loadBookings();
    await _loadAvailability();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking gespeichert')));
    }
  }

  Future<void> _updateBookingStatus(int bookingId, String status) async {
    final uri = Uri.parse('$_base/pms/bookings/$bookingId/status?status=$status');
    final r = await http.post(uri);
    if (r.statusCode >= 300) throw Exception('Status $status: ${r.statusCode}');
    await _loadBookings();
  }

  Future<void> _updateHousekeeping(int roomId, String status) async {
    final uri = Uri.parse('$_base/pms/rooms/$roomId/housekeeping?status=$status');
    final r = await http.post(uri);
    if (r.statusCode >= 300) throw Exception('HK $status: ${r.statusCode}');
    await _loadRooms();
  }

  Future<void> _createRatePlan() async {
    if (_propertyId == null || _rateRoomType == null) return;
    final parsed = int.tryParse(_ratePrice.text.trim());
    final price = parsed == null ? 0 : parsed.abs();
    final body = {
      'property_id': _propertyId,
      'room_type_id': _rateRoomType,
      'name': _rateName.text.trim().isEmpty ? 'Standard' : _rateName.text.trim(),
      'price_per_night_cents': price,
      'currency': 'SYP',
    };
    final uri = Uri.parse('$_base/pms/rate_plans');
    final r = await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode(body));
    if (r.statusCode >= 300) throw Exception('Rateplan ${r.statusCode}: ${r.body}');
    await _loadRatePlans();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('PMS · Cloudbeds style'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Calendar'),
            Tab(text: 'Reservations'),
            Tab(text: 'Housekeeping'),
            Tab(text: 'Rates'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : Column(
                  children: [
                    _propertyPicker(theme),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadAll,
                        child: TabBarView(
                          controller: _tab,
                          children: [
                            _buildDashboard(theme),
                            _buildCalendar(theme),
                            _buildReservations(theme),
                            _buildHousekeeping(theme),
                            _buildRates(theme),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _propertyPicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<int>(
              value: _propertyId,
              isExpanded: true,
              hint: const Text('Property auswählen'),
              items: _properties
                  .map((p) => DropdownMenuItem<int>(
                        value: p['id'] as int?,
                        child: Text('${p['name']} ${p['city'] != null ? "· ${p['city']}" : ""}'),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _propertyId = v;
                });
                _loadAll();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(ThemeData theme) {
    final occ = (_stats['occupancy_pct'] ?? 0.0) as double;
    final revenue = (_stats['revenue_cents'] ?? 0) as int;
    final arrivals = (_stats['arrivals'] ?? 0) as int;
    final departures = (_stats['departures'] ?? 0) as int;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _statCard('Occupancy', '${(occ * 100).round()}%', Icons.hotel, theme.colorScheme.primaryContainer),
            _statCard('Revenue (SYP)', revenue.toString(), Icons.payments_outlined, theme.colorScheme.secondaryContainer),
            _statCard('Arrivals', '$arrivals today', Icons.login, theme.colorScheme.surfaceContainerHighest),
            _statCard('Departures', '$departures today', Icons.logout, theme.colorScheme.surfaceContainerHighest),
            _statCard('Active bookings', '${_stats['active_bookings'] ?? 0}', Icons.receipt_long, theme.colorScheme.surfaceContainerHighest),
          ],
        ),
        const SizedBox(height: 16),
        _channelCard(theme),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Add inventory (property / room type / room)'),
          children: [
            _buildAddInventory(theme),
          ],
        ),
        const SizedBox(height: 12),
        Text('Quick booking', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _bookingForm(theme),
        const SizedBox(height: 16),
        Text('Latest reservations', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._bookings.take(6).map((b) => Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text(b['guest'] ?? ''),
                subtitle: Text('${_ymd.format(b['from'] ?? DateTime.now())} → ${_ymd.format(b['to'] ?? DateTime.now())}'),
                trailing: Text(b['status'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            )),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color bg) {
    return SizedBox(
      width: 170,
      child: Card(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingForm(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<int>(
              value: _bookingRoomTypeId,
              hint: const Text('Room type'),
              isExpanded: true,
              items: _roomTypes
                  .map((rt) => DropdownMenuItem<int>(
                        value: rt['id'] as int?,
                        child: Text(rt['name']),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _bookingRoomTypeId = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_ymd.format(_from)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: _from,
                      );
                      if (picked != null) {
                        setState(() => _from = picked);
                        _loadAvailability();
                      }
                    },
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_ymd.format(_to)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: _from,
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: _to,
                      );
                      if (picked != null) {
                        setState(() => _to = picked);
                        _loadAvailability();
                      }
                    },
                  ),
                ),
              ],
            ),
            TextField(
              controller: _guestName,
              decoration: const InputDecoration(labelText: 'Guest name'),
            ),
            TextField(
              controller: _guestPhone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
            SwitchListTile(
              value: _confirmBooking,
              onChanged: (v) => setState(() => _confirmBooking = v),
              title: const Text('Confirm immediately'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create booking'),
                onPressed: () async {
                  try {
                    await _createBooking();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Availability window: ${_ymd.format(_from)} → ${_ymd.format(_to)}'),
        const SizedBox(height: 8),
        ..._roomTypes.map((rt) {
          final avail = _availability[rt['id']] ?? 0;
          return Card(
            child: ListTile(
              title: Text(rt['name']),
              subtitle: Text('Max guests: ${rt['max_guests']}'),
              trailing: Chip(
                backgroundColor: avail > 0 ? Colors.green.shade100 : Colors.red.shade100,
                label: Text('Avail: $avail'),
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        Text('Upcoming stays', style: theme.textTheme.titleMedium),
        ..._bookings.take(10).map((b) => ListTile(
              leading: const Icon(Icons.event),
              title: Text('${b['guest']} · ${b['status']}'),
              subtitle: Text('${_ymd.format(b['from'] ?? DateTime.now())} → ${_ymd.format(b['to'] ?? DateTime.now())}'),
            )),
      ],
    );
  }

  Widget _buildReservations(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _bookings.length,
      itemBuilder: (_, idx) {
        final b = _bookings[idx];
        final rtName = _roomTypes.firstWhere(
          (rt) => rt['id'] == b['room_type_id'],
          orElse: () => {'name': 'Room ${b['room_type_id']}'},
        )['name'];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text('${b['guest']} · $rtName'),
            subtitle: Text('${_ymd.format(b['from'] ?? DateTime.now())} → ${_ymd.format(b['to'] ?? DateTime.now())}\nStatus: ${b['status']}'),
            trailing: PopupMenuButton<String>(
              onSelected: (st) async {
                try {
                  await _updateBookingStatus(b['id'] as int, st);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'confirmed', child: Text('Confirm')),
                PopupMenuItem(value: 'canceled', child: Text('Cancel')),
                PopupMenuItem(value: 'checked_in', child: Text('Check-in')),
                PopupMenuItem(value: 'checked_out', child: Text('Check-out')),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHousekeeping(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _rooms.map((r) {
        final rtName = _roomTypes.firstWhere(
          (rt) => rt['id'] == r['room_type_id'],
          orElse: () => {'name': ''},
        )['name'];
        final status = (r['housekeeping_status'] ?? 'clean') as String;
        final color = {
          'clean': Colors.green.shade100,
          'inspected': Colors.blue.shade100,
          'dirty': Colors.orange.shade100,
          'out_of_service': Colors.red.shade100,
        }[status] ??
            Colors.grey.shade200;
        return Card(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: color, child: Text(status.substring(0, 1).toUpperCase())),
            title: Text('Room ${r['code']} · $rtName'),
            subtitle: Text('HK: $status'),
            trailing: PopupMenuButton<String>(
              onSelected: (st) => _updateHousekeeping(r['id'] as int, st),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clean', child: Text('Mark clean')),
                PopupMenuItem(value: 'inspected', child: Text('Inspected')),
                PopupMenuItem(value: 'dirty', child: Text('Dirty')),
                PopupMenuItem(value: 'out_of_service', child: Text('Out of service')),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRates(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Rate plans', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._ratePlans.map((rp) {
          final rtName = _roomTypes.firstWhere(
            (rt) => rt['id'] == rp['room_type_id'],
            orElse: () => {'name': ''},
          )['name'];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: Text(rp['name']),
              subtitle: Text('$rtName · ${rp['price_per_night_cents']} ${rp['currency']} / night'),
            ),
          );
        }),
        const SizedBox(height: 12),
        Text('New rate', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButton<int>(
                  value: _rateRoomType,
                  isExpanded: true,
                  hint: const Text('Room type'),
                  items: _roomTypes
                      .map((rt) => DropdownMenuItem<int>(
                            value: rt['id'] as int?,
                            child: Text(rt['name']),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _rateRoomType = v),
                ),
                TextField(
                  controller: _rateName,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: _ratePrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price per night (cents)'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                    onPressed: () async {
                      try {
                        await _createRatePlan();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddInventory(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Property'),
          TextField(
            controller: _propName,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _propCity,
            decoration: const InputDecoration(labelText: 'City'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final body = {
                  'name': _propName.text.trim().isEmpty ? 'Property' : _propName.text.trim(),
                  'city': _propCity.text.trim().isEmpty ? null : _propCity.text.trim(),
                };
                final uri = Uri.parse('$_base/pms/properties');
                final r = await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode(body));
                if (r.statusCode >= 300) throw Exception('prop ${r.statusCode}');
                await _loadProperties();
                setState(() {
                  _propertyId = (_properties.isNotEmpty ? _properties.first['id'] as int? : null);
                });
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Save property'),
          ),
          const Divider(),
          const Text('Room type'),
          DropdownButton<int>(
            value: _propertyId,
            isExpanded: true,
            hint: const Text('Select property'),
            items: _properties
                .map((p) => DropdownMenuItem<int>(
                      value: p['id'] as int?,
                      child: Text(p['name']),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _propertyId = v),
          ),
          TextField(
            controller: _rtName,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _rtGuests,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Max guests'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_propertyId == null) return;
              try {
                final guests = int.tryParse(_rtGuests.text.trim()) ?? 2;
                final body = {'property_id': _propertyId, 'name': _rtName.text.trim(), 'max_guests': guests};
                final uri = Uri.parse('$_base/pms/room_types');
                final r = await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode(body));
                if (r.statusCode >= 300) throw Exception('room type ${r.statusCode}');
                await _loadRoomTypes();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Save room type'),
          ),
          const Divider(),
          const Text('Room'),
          DropdownButton<int>(
            value: _roomRoomType ?? _bookingRoomTypeId,
            isExpanded: true,
            hint: const Text('Room type'),
            items: _roomTypes
                .map((rt) => DropdownMenuItem<int>(
                      value: rt['id'] as int?,
                      child: Text(rt['name']),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _roomRoomType = v),
          ),
          TextField(
            controller: _roomCode,
            decoration: const InputDecoration(labelText: 'Room code'),
          ),
          ElevatedButton(
            onPressed: () async {
              final rtId = _roomRoomType ?? _bookingRoomTypeId;
              if (_propertyId == null || rtId == null) return;
              try {
                final body = {
                  'property_id': _propertyId,
                  'room_type_id': rtId,
                  'code': _roomCode.text.trim().isEmpty ? 'R-${DateTime.now().millisecondsSinceEpoch}' : _roomCode.text.trim(),
                  'housekeeping_status': 'clean',
                };
                final uri = Uri.parse('$_base/pms/rooms');
                final r = await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode(body));
                if (r.statusCode >= 300) throw Exception('room ${r.statusCode}');
                await _loadRooms();
                await _loadAvailability();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Save room'),
          ),
        ],
      ),
    );
  }

  Widget _channelCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Channel mappings (mock)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                DropdownButton<String>(
                  value: _channel,
                  items: const [
                    DropdownMenuItem(value: 'airbnb', child: Text('Airbnb')),
                    DropdownMenuItem(value: 'booking', child: Text('Booking.com')),
                    DropdownMenuItem(value: 'expedia', child: Text('Expedia')),
                  ],
                  onChanged: (v) => setState(() => _channel = v ?? 'airbnb'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _channelExt,
                    decoration: const InputDecoration(labelText: 'External property ID'),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_propertyId == null) return;
                    try {
                      final body = {
                        'property_id': _propertyId,
                        'channel': _channel,
                        'external_id': _channelExt.text.trim(),
                      };
                      final uri = Uri.parse('$_base/pms/channel/mappings');
                      final r = await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode(body));
                      if (r.statusCode >= 300) throw Exception('channel ${r.statusCode}');
                      await _loadChannels();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mapping saved')));
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _channelMappings
                  .map((m) => Chip(
                        avatar: const Icon(Icons.sync_alt, size: 16),
                        label: Text('${m['channel']} · ${m['external_id']}'),
                      ))
                  .toList(),
            ),
            if (_channelMappings.isEmpty) const Text('No mappings yet'),
          ],
        ),
      ),
    );
  }
}
