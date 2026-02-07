import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'shamell_map_widget.dart';
import 'glass.dart';
import 'l10n.dart';
import 'status_banner.dart';
import 'app_shell_widgets.dart' show WaterButton, AppBG;
import 'equipment_calendar.dart';
import 'board_badge.dart';
import 'equipment_catalog.dart' show EquipmentDetailPage;
import 'design_tokens.dart';
import 'driver_pod.dart';

class EquipmentOpsDashboardPage extends StatefulWidget {
  final String baseUrl;
  const EquipmentOpsDashboardPage({super.key, required this.baseUrl});

  @override
  State<EquipmentOpsDashboardPage> createState() =>
      _EquipmentOpsDashboardPageState();
}

class _EquipmentOpsDashboardPageState extends State<EquipmentOpsDashboardPage> {
  Map<String, dynamic>? _analytics;
  String _err = '';
  bool _loading = false;
  List<dynamic> _bookings = const [];
  List<dynamic> _holds = const [];
  String _assignOut = '';
  final Map<String, List<Map<String, dynamic>>> _board = {
    'pending': [],
    'en_route': [],
    'on_site': [],
    'completed': [],
  };
  List<dynamic> _calEvents = const [];
  DateTime _month = DateTime.now();
  bool _calLoading = false;
  String _calErr = '';

  String get _base => widget.baseUrl.trim();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _err = '';
    });
    try {
      final a = await http.get(Uri.parse('$_base/equipment/analytics/summary'));
      if (a.statusCode == 200) {
        _analytics = jsonDecode(a.body) as Map<String, dynamic>?;
      }
      final b = await http
          .get(Uri.parse('$_base/equipment/bookings?status=active&limit=100'));
      if (b.statusCode == 200) {
        final body = jsonDecode(b.body);
        if (body is List) _bookings = body;
      }
      _holds = const [];
      _board.forEach((k, v) => v.clear());
      for (final x in _bookings) {
        final m = x as Map<String, dynamic>? ?? {};
        final tasks = (m['tasks'] as List?) ?? const [];
        String st = m['status']?.toString() ?? 'pending';
        if (tasks.isNotEmpty) {
          final deliveryTask = tasks.firstWhere(
              (t) => (t as Map?)?['kind'] == 'delivery',
              orElse: () => tasks.first);
          if (deliveryTask is Map && deliveryTask['status'] != null) {
            st = deliveryTask['status'].toString();
          }
        }
        if (_board.containsKey(st)) {
          _board[st]!.add(m);
        } else {
          _board['pending']!.add(m);
        }
      }
      await _loadCalendar();
    } catch (e) {
      _err = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCalendar() async {
    setState(() {
      _calLoading = true;
      _calErr = '';
    });
    try {
      final monthStr =
          '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';
      final uri = Uri.parse('$_base/equipment/ops/calendar')
          .replace(queryParameters: {'month': monthStr});
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map && body['events'] is List) {
          _calEvents = body['events'] as List<dynamic>;
          _holds =
              _calEvents.where((e) => e is Map && e['type'] == 'hold').toList();
        }
      } else {
        _calErr = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _calErr = e.toString();
    } finally {
      if (mounted) setState(() => _calLoading = false);
    }
  }

  Widget _cards() {
    final a = _analytics ?? {};
    final items = <Widget>[];
    void add(String label, Object? value) {
      items.add(GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .70),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              value?.toString() ?? '-',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ));
    }

    add('Assets', a['assets_total']);
    add('Available', a['assets_available']);
    add('Active jobs', a['bookings_active']);
    add('Pending', a['bookings_pending']);
    add('Booked wk', a['bookings_week']);
    add('Blocks wk', a['blocks_week']);
    add('Deliveries open', a['logistics_open']);
    add('Revenue 30d (cents)', a['revenue_30d_cents']);

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1.5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: items,
    );
  }

  Widget _map() {
    final markers = <Marker>{};
    final polylines = <Polyline>{};
    // plot holds as translucent markers if available
    for (final h in _holds) {
      final m = h as Map<String, dynamic>? ?? {};
      final lat = (m['lat'] as num?)?.toDouble();
      final lon = (m['lon'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        markers.add(
          Marker(
            markerId: MarkerId('hold-${m['id'] ?? ''}'),
            position: LatLng(lat, lon),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueYellow,
            ),
            infoWindow: InfoWindow(
              title: 'Hold',
              snippet: m['reason']?.toString() ?? '',
            ),
          ),
        );
      }
    }
    for (final b in _bookings) {
      final m = b as Map<String, dynamic>? ?? {};
      final eqId = m['equipment_id'];
      final tasks = (m['tasks'] as List?) ?? const [];
      Map<String, dynamic>? deliveryTask;
      if (tasks.isNotEmpty) {
        deliveryTask = tasks.cast<Map<String, dynamic>>().firstWhere(
            (t) => t['kind'] == 'delivery',
            orElse: () => tasks.first as Map<String, dynamic>);
      }
      final drop = deliveryTask?['address'] ?? m['delivery_address'] ?? '';
      final latVal = deliveryTask?['lat'] ?? m['delivery_lat'];
      final lonVal = deliveryTask?['lon'] ?? m['delivery_lon'];
      final lat = (latVal as num?)?.toDouble();
      final lon = (lonVal as num?)?.toDouble();
      if (lat != null && lon != null) {
        markers.add(Marker(
            markerId: MarkerId('drop-$eqId'),
            position: LatLng(lat, lon),
            infoWindow: InfoWindow(title: 'Eq $eqId', snippet: drop)));
      }
      final route = deliveryTask?['route'];
      if (route is List && route.isNotEmpty) {
        polylines.add(Polyline(
          polylineId: PolylineId('route-$eqId'),
          color: Colors.blueAccent,
          width: 4,
          points: route
              .map((p) =>
                  LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
              .toList(),
        ));
      }
    }
    final center = markers.isNotEmpty
        ? markers.first.position
        : const LatLng(33.5138, 36.2765);
    return SizedBox(
      height: 260,
      child: ShamellMapWidget(
          center: center,
          initialZoom: 10,
          markers: markers,
          polylines: polylines),
    );
  }

  Widget _calendarPanel() {
    final monthLabel = DateFormat('MMMM yyyy').format(_month);
    final events = _calEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Kalender (Bookings + Holds) · $monthLabel',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
                onPressed: () {
                  setState(() {
                    _month = DateTime(_month.year, _month.month - 1, 1);
                  });
                  _loadCalendar();
                },
                icon: const Icon(Icons.chevron_left)),
            IconButton(
                onPressed: () {
                  setState(() {
                    _month = DateTime(_month.year, _month.month + 1, 1);
                  });
                  _loadCalendar();
                },
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
        if (_calLoading) const LinearProgressIndicator(),
        if (_calErr.isNotEmpty) StatusBanner.error(_calErr),
        ...events.map((e) {
          final m = e as Map<String, dynamic>? ?? {};
          final isHold = m['type'] == 'hold';
          final header = isHold
              ? 'Hold / ${m['reason'] ?? ''}'
              : 'Booking ${m['status'] ?? ''}';
          return Glass(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Eq ${m['equipment_id'] ?? ''} • $header',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${m['from_iso'] ?? ''} → ${m['to_iso'] ?? ''}',
                    style: const TextStyle(fontSize: 12)),
                if (!isHold && m['project'] != null)
                  Text('Projekt: ${m['project']}',
                      style: const TextStyle(fontSize: 12)),
                if (!isHold && m['po'] != null)
                  Text('PO: ${m['po']}', style: const TextStyle(fontSize: 12)),
                if (!isHold &&
                    m['attachments'] is List &&
                    (m['attachments'] as List).isNotEmpty)
                  Text('Attachments: ${(m['attachments'] as List).join(", ")}',
                      style: const TextStyle(fontSize: 12)),
                if (!isHold && m['signature_name'] != null)
                  Text('POD: ${m['signature_name']}',
                      style: const TextStyle(fontSize: 12)),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _boardView() {
    final cols = [
      ('pending', Colors.orange),
      ('en_route', Colors.blue),
      ('on_site', Colors.amber),
      ('completed', Tokens.colorPayments),
    ];
    final theme = Theme.of(context);
    return SizedBox(
      height: 320,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: cols.map((c) {
          final items = _board[c.$1] ?? [];
          return Container(
            width: 220,
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BoardBadge(label: c.$1, color: c.$2),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final m = items[i];
                      return Glass(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Eq ${m['equipment_id']}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              m['delivery_address']?.toString() ?? '',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              m['from_iso']?.toString() ?? '',
                              style: theme.textTheme.bodySmall,
                            ),
                            Row(
                              children: [
                                TextButton(
                                    onPressed: () => _openAssignSheet(m),
                                    child: const Text('Assign')),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _openTaskStatus(
      Map<String, dynamic> booking, String status) async {
    try {
      final body = [
        {'kind': 'delivery', 'status': status}
      ];
      final r = await http.post(
          Uri.parse('$_base/equipment/bookings/${booking['id']}/logistics'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body));
      setState(() => _assignOut = '${r.statusCode}: ${r.body}');
      _loadAll();
    } catch (e) {
      setState(() => _assignOut = 'error: $e');
    }
  }

  Future<void> _openAssignSheet(Map<String, dynamic> booking) async {
    final driver =
        TextEditingController(text: booking['driver_name']?.toString() ?? '');
    final phone =
        TextEditingController(text: booking['driver_phone']?.toString() ?? '');
    final eta =
        TextEditingController(text: booking['eta_minutes']?.toString() ?? '');
    final wStart = TextEditingController();
    final wEnd = TextEditingController();
    final proofUrl = TextEditingController();
    final proofNote = TextEditingController();
    final signature = TextEditingController();
    String status = booking['status']?.toString() ?? 'pending';
    String out = '';
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16),
            child: StatefulBuilder(builder: (context, setSheet) {
              Future<void> submit() async {
                setSheet(() => out = 'saving...');
                try {
                  final body = [
                    {
                      'kind': 'delivery',
                      'status': status,
                      'driver_name': driver.text.trim(),
                      'driver_phone': phone.text.trim(),
                      'eta_minutes': int.tryParse(eta.text.trim()),
                      'window_start_iso': wStart.text.trim().isEmpty
                          ? null
                          : wStart.text.trim(),
                      'window_end_iso':
                          wEnd.text.trim().isEmpty ? null : wEnd.text.trim(),
                      'proof_photo_url': proofUrl.text.trim().isEmpty
                          ? null
                          : proofUrl.text.trim(),
                      'proof_note': proofNote.text.trim().isEmpty
                          ? null
                          : proofNote.text.trim(),
                      'signature_name': signature.text.trim().isEmpty
                          ? null
                          : signature.text.trim(),
                    }
                  ];
                  final r = await http.post(
                      Uri.parse(
                          '$_base/equipment/bookings/${booking['id']}/logistics'),
                      headers: {'content-type': 'application/json'},
                      body: jsonEncode(body));
                  out = '${r.statusCode}: ${r.body}';
                  if (r.statusCode == 200) {
                    _assignOut = 'Updated booking ${booking['id']}';
                    Navigator.of(context).pop();
                    _loadAll();
                  }
                } catch (e) {
                  out = 'error: $e';
                }
                setSheet(() {});
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Assign delivery',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text('Booking ${booking['id']}'),
                    const SizedBox(height: 8),
                    TextField(
                        controller: driver,
                        decoration:
                            const InputDecoration(labelText: 'Driver name')),
                    TextField(
                        controller: phone,
                        decoration:
                            const InputDecoration(labelText: 'Driver phone')),
                    TextField(
                        controller: eta,
                        decoration:
                            const InputDecoration(labelText: 'ETA minutes')),
                    TextField(
                        controller: wStart,
                        decoration: const InputDecoration(
                            labelText: 'Window start (ISO)')),
                    TextField(
                        controller: wEnd,
                        decoration: const InputDecoration(
                            labelText: 'Window end (ISO)')),
                    TextField(
                        controller: proofUrl,
                        decoration: const InputDecoration(
                            labelText: 'Proof photo URL (optional)')),
                    TextField(
                        controller: proofNote,
                        decoration:
                            const InputDecoration(labelText: 'Proof note')),
                    TextField(
                        controller: signature,
                        decoration:
                            const InputDecoration(labelText: 'Signature name')),
                    DropdownButton<String>(
                      value: status,
                      items: const [
                        DropdownMenuItem(
                            value: 'pending', child: Text('pending')),
                        DropdownMenuItem(
                            value: 'en_route', child: Text('en_route')),
                        DropdownMenuItem(
                            value: 'completed', child: Text('completed')),
                      ],
                      onChanged: (v) => setSheet(() => status = v ?? status),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: WaterButton(label: 'Save', onTap: submit)),
                      ],
                    ),
                    if (out.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(out)),
                  ],
                ),
              );
            }),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${l.equipmentTitle} Ops'),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Stack(
        children: [
          const AppBG(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_err.isNotEmpty) StatusBanner.error(_err),
                if (_assignOut.isNotEmpty) StatusBanner.info(_assignOut),
                _cards(),
                const SizedBox(height: 16),
                Text(
                  'Active deliveries',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                _boardView(),
                const SizedBox(height: 8),
                _map(),
                const SizedBox(height: 12),
                _calendarPanel(),
                const SizedBox(height: 12),
                ..._bookings.map((b) {
                  final m = b as Map<String, dynamic>? ?? {};
                  return GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Eq ${m['equipment_id']} • ${m['status']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text('From: ${m['from_iso'] ?? ''}'),
                        Text('To: ${m['to_iso'] ?? ''}'),
                        if (m['delivery_address'] != null)
                          Text('Delivery: ${m['delivery_address']}'),
                        if (m['pickup_address'] != null)
                          Text('Pickup: ${m['pickup_address']}'),
                        if (m['project'] != null)
                          Text('Projekt: ${m['project']}',
                              style: const TextStyle(fontSize: 12)),
                        if (m['po'] != null)
                          Text('PO: ${m['po']}',
                              style: const TextStyle(fontSize: 12)),
                        if (m['attachments'] is List &&
                            (m['attachments'] as List).isNotEmpty)
                          Text(
                              'Attachments: ${(m['attachments'] as List).join(", ")}',
                              style: const TextStyle(fontSize: 12)),
                        if (m['insurance'] == true)
                          const Text('Versicherung aktiv',
                              style: TextStyle(fontSize: 12)),
                        if (m['damage_waiver'] == true)
                          const Text('Schadenverzicht aktiv',
                              style: TextStyle(fontSize: 12)),
                        if (m['delivery_distance_km'] != null)
                          Text('Route: ${m['delivery_distance_km']} km'),
                        if (m['tasks'] is List)
                          ...m['tasks'].map<Widget>((t) {
                            if (t is! Map) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${t['kind']} • ${t['status']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  if (t['eta_minutes'] != null)
                                    Text('ETA: ${t['eta_minutes']} min',
                                        style: const TextStyle(fontSize: 12)),
                                  if (t['driver_name'] != null)
                                    Text(
                                        'Driver: ${t['driver_name']} (${t['driver_phone'] ?? ''})',
                                        style: const TextStyle(fontSize: 12)),
                                  if (t['window_start_iso'] != null)
                                    Text(
                                        'Window: ${t['window_start_iso']} - ${t['window_end_iso'] ?? ''}',
                                        style: const TextStyle(fontSize: 12)),
                                  if (t['arrived_iso'] != null)
                                    Text('Arrived: ${t['arrived_iso']}',
                                        style: const TextStyle(fontSize: 12)),
                                  if (t['completed_iso'] != null)
                                    Text('Completed: ${t['completed_iso']}',
                                        style: const TextStyle(fontSize: 12)),
                                  if (t['proof_photo_url'] != null)
                                    Text('Proof: ${t['proof_photo_url']}',
                                        style: const TextStyle(fontSize: 12)),
                                  if (t['proof_note'] != null)
                                    Text('Notiz: ${t['proof_note']}',
                                        style: const TextStyle(fontSize: 12)),
                                  if (t['signature_name'] != null)
                                    Text('Signature: ${t['signature_name']}',
                                        style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            );
                          }).toList(),
                        if (m['invoice'] is Map &&
                            (m['invoice'] as Map)['pdf_url'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                'Rechnung: ${(m['invoice'] as Map)['status']} • ${(m['invoice'] as Map)['pdf_url']}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        Row(
                          children: [
                            TextButton(
                                onPressed: () => _openAssignSheet(m),
                                child: const Text('Assign/ETA')),
                            const SizedBox(width: 8),
                            TextButton(
                                onPressed: () =>
                                    _openTaskStatus(m, 'completed'),
                                child: const Text('Mark delivered')),
                            const SizedBox(width: 8),
                            TextButton(
                                onPressed: () => Navigator.of(context)
                                        .push(MaterialPageRoute(
                                      builder: (_) => EquipmentCalendarPage(
                                          baseUrl: _base,
                                          equipmentId: m['equipment_id'] is int
                                              ? m['equipment_id'] as int
                                              : int.tryParse(
                                                      '${m['equipment_id']}') ??
                                                  0,
                                          title: 'Eq ${m['equipment_id']}'),
                                    )),
                                child: const Text('Calendar')),
                            TextButton(
                                onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => DriverPodPage(
                                                baseUrl: _base,
                                                bookingId:
                                                    m['id']?.toString() ?? '',
                                              )),
                                    ),
                                child: const Text('POD')),
                            IconButton(
                                icon: const Icon(Icons.open_in_new),
                                onPressed: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => EquipmentDetailPage(
                                            baseUrl: _base,
                                            asset: m,
                                            walletId: null,
                                          )));
                                })
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
