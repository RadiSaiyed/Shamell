import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass.dart';
import 'l10n.dart';
import 'status_banner.dart';
import 'taxi/taxi_map_widget.dart';
import 'equipment_calendar.dart';
import 'equipment_ops_dashboard.dart';
import '../main.dart' show AppBG, WaterButton;

Future<Map<String, String>> _hdrEq({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final sp = await SharedPreferences.getInstance();
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) h['sa_cookie'] = cookie;
  return h;
}

class _SavedAddress {
  final String label;
  final String address;
  final double? lat;
  final double? lon;

  const _SavedAddress({required this.label, required this.address, this.lat, this.lon});

  factory _SavedAddress.fromJson(Map<String, dynamic> m) => _SavedAddress(
        label: m['label']?.toString() ?? '',
        address: m['address']?.toString() ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {'label': label, 'address': address, 'lat': lat, 'lon': lon};
}

double _kmBetween(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

class EquipmentCatalogPage extends StatefulWidget {
  final String baseUrl;
  final String? walletId;
  const EquipmentCatalogPage({super.key, required this.baseUrl, this.walletId});

  @override
  State<EquipmentCatalogPage> createState() => _EquipmentCatalogPageState();
}

class _EquipmentCatalogPageState extends State<EquipmentCatalogPage> {
  int _tab = 0; // 0 = Mieten, 1 = Dispo
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController cityCtrl = TextEditingController();
  final TextEditingController categoryCtrl = TextEditingController();
  final TextEditingController subcatCtrl = TextEditingController();
  final TextEditingController radiusCtrl = TextEditingController();
  final TextEditingController fromCtrl = TextEditingController();
  final TextEditingController toCtrl = TextEditingController();
  String? _assortment;
  String? _selectedSubcat;
  final Map<String, List<String>> _assortmentMap = const {
    'Aerial Work Platforms': [
      'Scissor lifts',
      'Articulated boom lifts',
      'Truck-mounted telescopic lifts',
    ],
    'Room Systems / Containers': [
      '20-ft base containers',
      'Sanitary containers',
      'Material containers',
    ],
    'Excavators': [
      'Mini excavators',
      'Crawler excavators',
      'Wheeled/mobile excavators',
    ],
    'Cranes': [
      'Auto/mobile/telescopic cranes',
      'Tower cranes',
      'Pick-and-carry cranes',
    ],
    'Forklifts & Warehouse Equipment': [
      'Forklifts/front loaders',
      'Four-way forklifts',
      'Pallet trucks',
    ],
    'Loaders': [
      'Wheel loaders',
      'Compact loaders',
      'Delta loaders',
    ],
    'Telescopic Machines': [
      'Rotating telehandlers',
      'Telehandlers',
      'Telehandler attachments',
    ],
    'Dumpers': [
      'Wheel dumpers',
      'Tracked dumpers',
    ],
    'Compaction Technology': [
      'Vibratory plates',
      'Tampers/rammers',
      'Compaction-equipment accessories',
    ],
    'Energy & Air': [
      'Site power & lighting',
      'Heating & climate control',
      'Compressed-air equipment',
    ],
    'Construction Site Equipment': [
      'Site monitoring',
      'Tanks',
      'Scaffolding & lifts',
    ],
    'Vehicles': [
      'Trailers',
      'Special vehicles',
      'Small transporters (up to 3.5 t)',
    ],
  };
  List<dynamic> _items = const [];
  String _err = '';
  bool _loading = false;
  bool _mapView = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
    });
    try {
      final params = {
        'q': searchCtrl.text.trim(),
        'city': cityCtrl.text.trim(),
        'category': (_assortment ?? categoryCtrl.text).trim(),
        'limit': '60'
      };
      if (subcatCtrl.text.isNotEmpty) params['subcategory'] = subcatCtrl.text.trim();
      if (radiusCtrl.text.isNotEmpty) params['max_distance_km'] = radiusCtrl.text.trim();
      if (fromCtrl.text.isNotEmpty) params['from_iso'] = fromCtrl.text.trim();
      if (toCtrl.text.isNotEmpty) params['to_iso'] = toCtrl.text.trim();
      final uri = Uri.parse('${widget.baseUrl}/equipment/assets').replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdrEq());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) _items = body;
      } else {
        _err = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _err = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDates() async {
    try {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
      );
      if (range != null) {
        final fmt = DateFormat("yyyy-MM-ddTHH:mm:ss'Z'");
        fromCtrl.text = fmt.format(range.start.toUtc());
        toCtrl.text = fmt.format(range.end.toUtc());
        _load();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: _tab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Equipment'),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          bottom: TabBar(
            indicatorColor: Colors.white,
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Mieten'),
              Tab(text: 'Dispo/Flotte'),
            ],
          ),
        ),
        body: AppBG(
          child: _tab == 0 ? _rentTab() : _opsTab(),
        ),
      ),
    );
  }

  Widget _opsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: WaterButton(
          label: 'Zur Dispo / Ops',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EquipmentOpsDashboardPage(baseUrl: widget.baseUrl))),
        ),
      ),
    );
  }

  Widget _rentTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(labelText: 'Suchen'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(labelText: 'Stadt'),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  value: _assortment,
                  decoration: const InputDecoration(labelText: 'Mietsortiment'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Alle')),
                    ..._assortmentMap.keys
                        .map((a) => DropdownMenuItem<String?>(value: a, child: Text(a)))
                        .toList(),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _assortment = v;
                      _selectedSubcat = null;
                      categoryCtrl.text = v ?? '';
                      subcatCtrl.text = '';
                    });
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  value: _selectedSubcat,
                  decoration: const InputDecoration(labelText: 'Unterkategorie'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Alle')),
                    ...(_assortment != null
                        ? (_assortmentMap[_assortment] ?? const [])
                        : _assortmentMap.values.expand((e) => e))
                        .map((s) => DropdownMenuItem<String?>(value: s, child: Text(s)))
                        .toList(),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedSubcat = v;
                      subcatCtrl.text = v ?? '';
                    });
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: radiusCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Radius km'),
                ),
              ),
              OutlinedButton.icon(
                  onPressed: _pickDates,
                  icon: const Icon(Icons.date_range),
                  label: const Text('Verfügbarkeit')),
              WaterButton(label: 'Filtern', onTap: _load),
              OutlinedButton.icon(
                  onPressed: () => setState(() => _mapView = !_mapView),
                  icon: Icon(_mapView ? Icons.grid_view : Icons.map_outlined),
                  label: Text(_mapView ? 'Liste' : 'Karte')),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_err.isNotEmpty) StatusBanner.error(_err),
        Expanded(
          child: _mapView ? _mapList() : _gridList(),
        )
      ],
    );
  }

  Widget _gridList() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.92),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final m = _items[i] as Map<String, dynamic>? ?? {};
        final dayPrice = m['daily_rate_cents'] ?? '-';
        final weekPrice = m['weekly_rate_cents'] ?? '-';
        final monthPrice = m['monthly_rate_cents'] ?? '-';
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EquipmentDetailPage(baseUrl: widget.baseUrl, asset: m, walletId: widget.walletId))),
          child: Glass(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                        image: m['image_url'] != null
                            ? DecorationImage(image: NetworkImage(m['image_url']), fit: BoxFit.cover)
                            : null,
                      ),
                    ),
                    Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .4),
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.place, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text('${m['city'] ?? ''}',
                                  style: const TextStyle(fontSize: 11, color: Colors.white)),
                            ],
                          ),
                        ))
                  ],
                ),
                const SizedBox(height: 8),
                Text(m['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${m['subcategory'] ?? m['category'] ?? ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 6),
                Text('Tag: $dayPrice ${m['currency'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Woche: $weekPrice ${m['currency'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                Text('Monat: $monthPrice ${m['currency'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${m['available_quantity'] ?? m['quantity'] ?? ''} verfügbar',
                        style: const TextStyle(fontSize: 12)),
                    WaterButton(
                      label: 'Jetzt anfragen',
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              EquipmentDetailPage(baseUrl: widget.baseUrl, asset: m, walletId: widget.walletId))),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mapList() {
    final markers = <Marker>{};
    for (final it in _items) {
      final m = it as Map<String, dynamic>? ?? {};
      final lat = (m['latitude'] as num?)?.toDouble();
      final lon = (m['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        markers.add(Marker(
            markerId: MarkerId('eq-${m['id']}'),
            position: LatLng(lat, lon),
            infoWindow: InfoWindow(
                title: m['title']?.toString() ?? '',
                snippet: m['city']?.toString() ?? '',
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EquipmentDetailPage(baseUrl: widget.baseUrl, asset: m, walletId: widget.walletId)));
                })));
      }
    }
    final center = markers.isNotEmpty ? markers.first.position : const LatLng(33.5138, 36.2765);
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TaxiMapWidget(center: center, initialZoom: 11, markers: markers),
    );
  }
}

class EquipmentDetailPage extends StatefulWidget {
  final String baseUrl;
  final Map<String, dynamic> asset;
  final String? walletId;
  const EquipmentDetailPage({super.key, required this.baseUrl, required this.asset, this.walletId});

  @override
  State<EquipmentDetailPage> createState() => _EquipmentDetailPageState();
}

class _EquipmentDetailPageState extends State<EquipmentDetailPage> {
  late final TextEditingController deliveryCtrl;
  final ValueNotifier<String> _distanceOut = ValueNotifier<String>('');
  final ValueNotifier<String> _costOut = ValueNotifier<String>('');
  double? _destLat;
  double? _destLon;

  Map<String, dynamic> get asset => widget.asset;

  @override
  void initState() {
    super.initState();
    deliveryCtrl = TextEditingController(text: asset['city']?.toString() ?? '');
  }

  @override
  void dispose() {
    deliveryCtrl.dispose();
    _distanceOut.dispose();
    _costOut.dispose();
    super.dispose();
  }

  Future<void> _calcDelivery() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/osm/geocode').replace(queryParameters: {'q': deliveryCtrl.text.trim()});
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List && body.isNotEmpty) {
          final first = body.first as Map<String, dynamic>? ?? {};
          _destLat = (first['lat'] as num?)?.toDouble();
          _destLon = (first['lon'] as num?)?.toDouble();
        }
      }
      final originLat = (asset['latitude'] as num?)?.toDouble();
      final originLon = (asset['longitude'] as num?)?.toDouble();
      if (originLat != null && originLon != null && _destLat != null && _destLon != null) {
        final km = _kmBetween(originLat, originLon, _destLat!, _destLon!).toStringAsFixed(1);
        _distanceOut.value = '$km km (ca.)';
      }
      // full quote for delivery cost
      final payload = {
        'equipment_id': asset['id'],
        'from_iso': DateFormat("yyyy-MM-ddTHH:mm:ss'Z'").format(DateTime.now().toUtc()),
        'to_iso': DateFormat("yyyy-MM-ddTHH:mm:ss'Z'").format(DateTime.now().add(const Duration(days: 1)).toUtc()),
        'quantity': 1,
        'delivery_required': true,
        'delivery_lat': _destLat,
        'delivery_lon': _destLon,
      };
      final rq = await http.post(Uri.parse('${widget.baseUrl}/equipment/quote'),
          headers: await _hdrEq(json: true), body: jsonEncode(payload));
      if (rq.statusCode == 200) {
        final q = jsonDecode(rq.body);
        _costOut.value =
            'Lieferung: ${q['delivery_cents'] ?? 0} / Gesamt: ${q['total_cents'] ?? 0} ${q['currency'] ?? ''}';
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final specs = <Widget>[];
    void add(String label, Object? v) {
      if (v == null || (v is String && v.isEmpty)) return;
      specs.add(Row(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(width: 6),
        Text(v.toString(), style: const TextStyle(fontWeight: FontWeight.w600))
      ]));
    }

    add('Gewicht', asset['weight_kg']);
    add('Leistung', asset['power_kw']);
    add('Tags', asset['tags']);
    add('Kategorie', asset['category']);

    final imgs = <String>[];
    if (asset['image_url'] != null) imgs.add(asset['image_url']);
    if (asset['gallery'] is List) {
      imgs.addAll((asset['gallery'] as List).whereType<String>());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(asset['title']?.toString() ?? 'Equipment'),
        actions: [
          IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EquipmentCalendarPage(
                        baseUrl: widget.baseUrl,
                        equipmentId: asset['id'] as int,
                        title: asset['title']?.toString() ?? 'Equipment')));
              },
              icon: const Icon(Icons.calendar_today_outlined)),
        ],
      ),
      body: AppBG(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: 220,
              child: PageView(
                children: imgs.isNotEmpty
                    ? imgs
                        .map((u) => Container(
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.black12,
                                image: DecorationImage(image: NetworkImage(u), fit: BoxFit.cover),
                              ),
                            ))
                        .toList()
                    : [
                        Container(
                          decoration:
                              BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.black12),
                          child: const Center(child: Icon(Icons.construction, size: 48)),
                        )
                      ],
              ),
            ),
            const SizedBox(height: 12),
            Text(asset['title']?.toString() ?? '', style: Theme.of(context).textTheme.titleLarge),
            Text('${asset['city'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            if (specs.isNotEmpty) ...[
              const Text('Spezifikationen', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...specs,
            ],
            const SizedBox(height: 12),
            Text('Preis', style: Theme.of(context).textTheme.titleMedium),
            Text('Tag: ${asset['daily_rate_cents'] ?? '-'} ${asset['currency'] ?? ''}'),
            Text('Woche: ${asset['weekly_rate_cents'] ?? '-'} ${asset['currency'] ?? ''}'),
            Text('Monat: ${asset['monthly_rate_cents'] ?? '-'} ${asset['currency'] ?? ''}'),
            const SizedBox(height: 12),
            const Text('Add-ons', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('• Schadenverzicht / Versicherung', style: TextStyle(fontSize: 12)),
            const Text('• Zubehör / Attachments auf Anfrage', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Lieferkosten kalkulieren', style: TextStyle(fontWeight: FontWeight.w700)),
            TextField(controller: deliveryCtrl, decoration: const InputDecoration(labelText: 'Lieferadresse')),
            const SizedBox(height: 6),
            Row(
              children: [
                WaterButton(label: 'Lieferpreis', onTap: _calcDelivery),
                const SizedBox(width: 8),
                ValueListenableBuilder<String>(
                    valueListenable: _distanceOut,
                    builder: (_, v, __) => Text(v, style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 8),
                ValueListenableBuilder<String>(
                    valueListenable: _costOut,
                    builder: (_, v, __) => Text(v, style: const TextStyle(fontSize: 12))),
              ],
            ),
            const SizedBox(height: 16),
            WaterButton(
                label: 'Anfrage / Buchen',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EquipmentBookingWizard(baseUrl: widget.baseUrl, asset: asset, walletId: widget.walletId)))),
          ],
        ),
      ),
    );
  }
}

class EquipmentBookingWizard extends StatefulWidget {
  final String baseUrl;
  final Map<String, dynamic> asset;
  final String? walletId;
  const EquipmentBookingWizard({super.key, required this.baseUrl, required this.asset, this.walletId});

  @override
  State<EquipmentBookingWizard> createState() => _EquipmentBookingWizardState();
}

class _EquipmentBookingWizardState extends State<EquipmentBookingWizard> {
  int _step = 0;
  final TextEditingController fromCtrl = TextEditingController();
  final TextEditingController toCtrl = TextEditingController();
  final TextEditingController qtyCtrl = TextEditingController(text: '1');
  final TextEditingController projectCtrl = TextEditingController();
  final TextEditingController windowCtrl = TextEditingController();
  bool _delivery = true;
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController contactCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();
  final TextEditingController poCtrl = TextEditingController();
  bool _insurance = false;
  bool _damageWaiver = false;
  final TextEditingController windowStartCtrl = TextEditingController();
  final TextEditingController windowEndCtrl = TextEditingController();
  List<_SavedAddress> _addressBook = const [];
  double? _deliveryLat;
  double? _deliveryLon;
  final TextEditingController pickupCtrl = TextEditingController();
  double? _pickupLat;
  double? _pickupLon;
  final List<String> _attachments = const ['Hydraulikhammer', 'Schaufel', 'Gabel', 'Besen'];
  final Set<String> _selectedAttachments = {};
  Map<String, dynamic>? _quote;
  String _out = '';

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _pickDates() async {
    try {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
      );
      if (range != null) {
        final fmt = DateFormat("yyyy-MM-ddTHH:mm:ss'Z'");
        fromCtrl.text = fmt.format(range.start.toUtc());
        toCtrl.text = fmt.format(range.end.toUtc());
      }
    } catch (_) {}
  }

  Future<void> _quoteNow() async {
    setState(() => _out = 'quoting...');
    try {
      await _ensureDeliveryCoords();
      double? deliveryKm;
      final originLat = (widget.asset['latitude'] as num?)?.toDouble();
      final originLon = (widget.asset['longitude'] as num?)?.toDouble();
      if (originLat != null && originLon != null && _deliveryLat != null && _deliveryLon != null) {
        deliveryKm = _kmBetween(originLat, originLon, _deliveryLat!, _deliveryLon!);
      }
      final body = {
        'equipment_id': widget.asset['id'],
        'from_iso': fromCtrl.text.trim(),
        'to_iso': toCtrl.text.trim(),
        'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 1,
        'delivery_required': _delivery,
        'delivery_lat': _deliveryLat,
        'delivery_lon': _deliveryLon,
        'delivery_km': deliveryKm,
      };
      final r = await http.post(Uri.parse('${widget.baseUrl}/equipment/quote'),
          headers: await _hdrEq(json: true), body: jsonEncode(body));
      _out = '${r.statusCode}: ${r.body}';
      if (r.statusCode == 200) {
        _quote = jsonDecode(r.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      _out = 'error: $e';
    }
    setState(() {});
  }

  Future<void> _bookNow() async {
    setState(() => _out = 'booking...');
    try {
      await _ensureDeliveryCoords();
      double? deliveryKm;
      final originLat = (widget.asset['latitude'] as num?)?.toDouble();
      final originLon = (widget.asset['longitude'] as num?)?.toDouble();
      if (originLat != null && originLon != null && _deliveryLat != null && _deliveryLon != null) {
        deliveryKm = _kmBetween(originLat, originLon, _deliveryLat!, _deliveryLon!);
      }
      final body = {
        'equipment_id': widget.asset['id'],
        'from_iso': fromCtrl.text.trim(),
        'to_iso': toCtrl.text.trim(),
        'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 1,
        'delivery_required': _delivery,
        'renter_name': contactCtrl.text.trim(),
        'renter_wallet_id': widget.walletId,
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'delivery_address': addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
        'pickup_address': pickupCtrl.text.trim().isEmpty ? null : pickupCtrl.text.trim(),
        'confirm': true,
        'project': projectCtrl.text.trim().isEmpty ? null : projectCtrl.text.trim(),
        'po': poCtrl.text.trim().isEmpty ? null : poCtrl.text.trim(),
        'insurance': _insurance,
        'damage_waiver': _damageWaiver,
        'delivery_scheduled_iso': windowStartCtrl.text.trim().isEmpty ? null : windowStartCtrl.text.trim(),
        'pickup_scheduled_iso': windowEndCtrl.text.trim().isEmpty ? null : windowEndCtrl.text.trim(),
        'delivery_window_start_iso': windowStartCtrl.text.trim().isEmpty ? null : windowStartCtrl.text.trim(),
        'delivery_window_end_iso': windowEndCtrl.text.trim().isEmpty ? null : windowEndCtrl.text.trim(),
        'attachments': _selectedAttachments.toList(),
        'delivery_lat': _deliveryLat,
        'delivery_lon': _deliveryLon,
        'delivery_km': deliveryKm,
      };
      final r = await http.post(Uri.parse('${widget.baseUrl}/equipment/book'),
          headers: await _hdrEq(json: true), body: jsonEncode(body));
      _out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      _out = 'error: $e';
    }
    setState(() {});
  }

  Future<void> _loadAddresses() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final List<_SavedAddress> parsed = [];
      final raw = sp.getStringList('equipment_saved_addresses_v2') ?? const [];
      for (final r in raw) {
        try {
          parsed.add(_SavedAddress.fromJson(jsonDecode(r)));
        } catch (_) {}
      }
      // migrate legacy simple list if present
      final legacy = sp.getStringList('equipment_saved_addresses') ?? const [];
      for (final l in legacy) {
        parsed.add(_SavedAddress(label: l, address: l));
      }
      setState(() => _addressBook = parsed);
    } catch (_) {}
  }

  Future<void> _saveAddress(_SavedAddress addr) async {
    if (addr.address.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList('equipment_saved_addresses_v2') ?? [];
    final List<_SavedAddress> items = [];
    for (final r in raw) {
      try {
        items.add(_SavedAddress.fromJson(jsonDecode(r)));
      } catch (_) {}
    }
    items.removeWhere((a) => a.address == addr.address);
    items.insert(0, addr);
    while (items.length > 12) {
      items.removeLast();
    }
    await sp.setStringList('equipment_saved_addresses_v2', items.map((e) => jsonEncode(e.toJson())).toList());
    setState(() => _addressBook = items);
  }

  Future<void> _geocodeAddress(String addr) async {
    if (addr.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/osm/geocode').replace(queryParameters: {'q': addr});
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List && body.isNotEmpty) {
          final first = body.first as Map<String, dynamic>? ?? {};
          setState(() {
            _deliveryLat = (first['lat'] as num?)?.toDouble();
            _deliveryLon = (first['lon'] as num?)?.toDouble();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _pickOnMap() async {
    LatLng? sel = _deliveryLat != null && _deliveryLon != null
        ? LatLng(_deliveryLat!, _deliveryLon!)
        : const LatLng(33.5138, 36.2765);
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return Padding(
            padding: EdgeInsets.only(
                left: 12, right: 12, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 12),
            child: StatefulBuilder(builder: (context, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 320,
                    child: TaxiMapWidget(
                      center: sel ?? const LatLng(33.5138, 36.2765),
                      initialZoom: 12,
                      markers: sel != null
                          ? {
                              Marker(markerId: const MarkerId('drop'), position: sel!),
                            }
                          : {},
                      onTap: (ll) => setSheet(() => sel = ll),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: WaterButton(
                              label: 'Pin übernehmen',
                              onTap: () {
                                if (sel != null) {
                                  setState(() {
                                    _deliveryLat = sel!.latitude;
                                    _deliveryLon = sel!.longitude;
                                    if (addressCtrl.text.trim().isEmpty) {
                                      addressCtrl.text =
                                          '${sel!.latitude.toStringAsFixed(4)}, ${sel!.longitude.toStringAsFixed(4)}';
                                    }
                                  });
                                }
                                Navigator.of(context).pop();
                              })),
                    ],
                  )
                ],
              );
            }),
          );
        });
  }

  Future<void> _ensureDeliveryCoords() async {
    if (!_delivery) return;
    if (_deliveryLat != null && _deliveryLon != null) return;
    await _geocodeAddress(addressCtrl.text.trim());
  }

  Widget _step1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('1. Daten', style: TextStyle(fontWeight: FontWeight.w700)),
        Row(
          children: [
            Expanded(child: TextField(controller: fromCtrl, decoration: const InputDecoration(labelText: 'Von (ISO)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: toCtrl, decoration: const InputDecoration(labelText: 'Bis (ISO)'))),
            IconButton(onPressed: _pickDates, icon: const Icon(Icons.date_range)),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Menge'),
              ),
            ),
            const SizedBox(width: 12),
            SwitchListTile(
              value: _delivery,
              onChanged: (v) => setState(() => _delivery = v),
              title: const Text('Lieferung'),
            )
          ],
        ),
        const SizedBox(height: 12),
        WaterButton(label: 'Weiter', onTap: () => setState(() => _step = 1)),
      ],
    );
  }

  Widget _step2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('2. Adresse & Kontakt', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Adresse / Baustelle')),
        const SizedBox(height: 6),
        Row(
          children: [
            WaterButton(label: 'Pin setzen', padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), onTap: _pickOnMap),
            const SizedBox(width: 8),
            WaterButton(
                label: 'Als Favorit',
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: () => _saveAddress(_SavedAddress(
                    label: projectCtrl.text.trim().isNotEmpty ? projectCtrl.text.trim() : addressCtrl.text.trim(),
                    address: addressCtrl.text.trim(),
                    lat: _deliveryLat,
                    lon: _deliveryLon))),
          ],
        ),
        if (_deliveryLat != null && _deliveryLon != null)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text('Pin: ${_deliveryLat?.toStringAsFixed(4)}, ${_deliveryLon?.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        if (_addressBook.isNotEmpty)
          Wrap(
            spacing: 6,
            children: _addressBook
                .map((a) => ActionChip(
                      avatar: const Icon(Icons.place, size: 16),
                      label: Text(a.label.isNotEmpty ? a.label : a.address, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() {
                        addressCtrl.text = a.address;
                        _deliveryLat = a.lat;
                        _deliveryLon = a.lon;
                      }),
                    ))
                .toList(),
          ),
        TextField(controller: pickupCtrl, decoration: const InputDecoration(labelText: 'Abholadresse (optional)')),
        TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Kontakt / Firma')),
        TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Hinweise')),
        TextField(controller: projectCtrl, decoration: const InputDecoration(labelText: 'Projekt / Kunde')),
        TextField(controller: poCtrl, decoration: const InputDecoration(labelText: 'PO / Referenz')),
        TextField(controller: windowStartCtrl, decoration: const InputDecoration(labelText: 'Lieferzeitfenster Start (ISO)')),
        TextField(controller: windowEndCtrl, decoration: const InputDecoration(labelText: 'Lieferzeitfenster Ende (ISO)')),
        CheckboxListTile(
          value: _insurance,
          onChanged: (v) => setState(() => _insurance = v ?? false),
          title: const Text('Versicherung hinzufügen'),
        ),
        CheckboxListTile(
          value: _damageWaiver,
          onChanged: (v) => setState(() => _damageWaiver = v ?? false),
          title: const Text('Schadenverzicht'),
        ),
        const SizedBox(height: 8),
        const Text('Attachments / Zubehör', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(
          spacing: 6,
          children: _attachments
              .map((a) => FilterChip(
                    label: Text(a),
                    selected: _selectedAttachments.contains(a),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedAttachments.add(a);
                        } else {
                          _selectedAttachments.remove(a);
                        }
                      });
                    },
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            WaterButton(label: 'Zurück', onTap: () => setState(() => _step = 0)),
            const SizedBox(width: 12),
            WaterButton(
                label: 'Weiter',
                onTap: () async {
                  await _quoteNow();
                  await _saveAddress(_SavedAddress(
                      label: projectCtrl.text.trim().isNotEmpty ? projectCtrl.text.trim() : addressCtrl.text.trim(),
                      address: addressCtrl.text.trim(),
                      lat: _deliveryLat,
                      lon: _deliveryLon));
                  setState(() => _step = 2);
                }),
          ],
        ),
      ],
    );
  }

  Widget _step3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('3. Zusammenfassung', style: TextStyle(fontWeight: FontWeight.w700)),
        if (_quote != null) ...[
          Text('Miete: ${_quote?['rental_cents']}'),
          Text('Lieferung: ${_quote?['delivery_cents']}'),
          Text('Kaution: ${_quote?['deposit_cents']}'),
          Text('Gesamt: ${_quote?['total_cents']} ${_quote?['currency'] ?? ''}'),
          if (projectCtrl.text.trim().isNotEmpty) Text('Projekt: ${projectCtrl.text}'),
          if (poCtrl.text.trim().isNotEmpty) Text('PO: ${poCtrl.text}'),
          if (_insurance) const Text('✓ Versicherung'),
          if (_damageWaiver) const Text('✓ Schadenverzicht'),
          if (_selectedAttachments.isNotEmpty)
            Text('Attachments: ${_selectedAttachments.join(", ")}', style: const TextStyle(fontSize: 12)),
          if (_deliveryLat != null && _deliveryLon != null)
            Text('Liefer-Pin: ${_deliveryLat?.toStringAsFixed(4)}, ${_deliveryLon?.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            WaterButton(label: 'Zurück', onTap: () => setState(() => _step = 1)),
            const SizedBox(width: 12),
            WaterButton(label: 'Jetzt buchen', onTap: _bookNow),
          ],
        ),
        if (_out.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_out)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buchung')),
      body: AppBG(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              if (_step == 0) _step1(),
              if (_step == 1) _step2(),
              if (_step == 2) _step3(),
            ],
          ),
        ),
      ),
    );
  }
}
