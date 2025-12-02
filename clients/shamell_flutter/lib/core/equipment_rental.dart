import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'glass.dart';
import 'l10n.dart';
import 'status_banner.dart';
import '../main.dart' show AppScaffold, WaterButton;
import 'taxi/taxi_map_widget.dart';
import 'config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'equipment_calendar.dart';

Future<Map<String, String>> _hdrEquipment({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final sp = await SharedPreferences.getInstance();
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class EquipmentRentalPage extends StatefulWidget {
  final String baseUrl;
  final String? walletId;
  final List<String>? operatorDomains;
  const EquipmentRentalPage(this.baseUrl, {super.key, this.walletId, this.operatorDomains});

  @override
  State<EquipmentRentalPage> createState() => _EquipmentRentalPageState();
}

class _EquipmentRentalPageState extends State<EquipmentRentalPage> with SingleTickerProviderStateMixin {
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController cityCtrl = TextEditingController();
  final TextEditingController categoryCtrl = TextEditingController();
  final TextEditingController nearLatCtrl = TextEditingController();
  final TextEditingController nearLonCtrl = TextEditingController();
  final TextEditingController radiusCtrl = TextEditingController();
  final TextEditingController minPriceCtrl = TextEditingController();
  final TextEditingController maxPriceCtrl = TextEditingController();
  final TextEditingController minWeightCtrl = TextEditingController();
  final TextEditingController maxWeightCtrl = TextEditingController();
  final TextEditingController minPowerCtrl = TextEditingController();
  final TextEditingController maxPowerCtrl = TextEditingController();
  final TextEditingController tagsCtrl = TextEditingController();
  final TextEditingController fromCtrl = TextEditingController();
  final TextEditingController toCtrl = TextEditingController();
  final TextEditingController deliveryKmCtrl = TextEditingController();
  bool _availableOnly = true;
  int _qty = 1;
  String _order = 'newest';
  double? _deliveryLat;
  double? _deliveryLon;
  double? _pickupLat;
  double? _pickupLon;
  List<String> _recentAddresses = const [];
  List<String> _addressSuggestions = const [];
  List<dynamic> _assets = const [];
  List<dynamic> _bookings = const [];
  Map<String, dynamic>? _analytics;
  Map<int, dynamic> _calendarCache = {};
  bool _loadingAssets = false;
  bool _loadingBookings = false;
  String _assetsOut = '';
  String _bookingsOut = '';
  late final TabController _tabs;

  String get _base => widget.baseUrl.trim();
  String? get _wallet => widget.walletId;
  bool get _isOperator => (widget.operatorDomains ?? const []).contains('equipment');

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _tabs = TabController(length: _isOperator ? 3 : 2, vsync: this);
    _loadAssets();
    _loadBookings();
    if (_isOperator) {
      _loadAnalytics();
    }
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    cityCtrl.dispose();
    categoryCtrl.dispose();
    nearLatCtrl.dispose();
    nearLonCtrl.dispose();
    radiusCtrl.dispose();
    minPriceCtrl.dispose();
    maxPriceCtrl.dispose();
    minWeightCtrl.dispose();
    maxWeightCtrl.dispose();
    minPowerCtrl.dispose();
    maxPowerCtrl.dispose();
    tagsCtrl.dispose();
    fromCtrl.dispose();
    toCtrl.dispose();
    deliveryKmCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _recentAddresses = sp.getStringList('equipment_addr_recent') ?? const [];
    });
  }

  Future<void> _saveRecent(String addr) async {
    if (addr.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final current = sp.getStringList('equipment_addr_recent') ?? [];
    if (!current.contains(addr)) {
      current.insert(0, addr);
    }
    while (current.length > 8) {
      current.removeLast();
    }
    await sp.setStringList('equipment_addr_recent', current);
    setState(() => _recentAddresses = current);
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loadingAssets = true;
      _assetsOut = '';
    });
    try {
      final params = {
        'q': searchCtrl.text.trim(),
        'city': cityCtrl.text.trim(),
        'category': categoryCtrl.text.trim(),
        'limit': '40',
        'order': _order,
      };
      if (_availableOnly) params['available_only'] = 'true';
      if (fromCtrl.text.isNotEmpty) params['from_iso'] = fromCtrl.text.trim();
      if (toCtrl.text.isNotEmpty) params['to_iso'] = toCtrl.text.trim();
      if (minPriceCtrl.text.trim().isNotEmpty) params['min_price'] = minPriceCtrl.text.trim();
      if (maxPriceCtrl.text.trim().isNotEmpty) params['max_price'] = maxPriceCtrl.text.trim();
      if (nearLatCtrl.text.trim().isNotEmpty) params['near_lat'] = nearLatCtrl.text.trim();
      if (nearLonCtrl.text.trim().isNotEmpty) params['near_lon'] = nearLonCtrl.text.trim();
      if (radiusCtrl.text.trim().isNotEmpty) params['max_distance_km'] = radiusCtrl.text.trim();
      if (minWeightCtrl.text.trim().isNotEmpty) params['min_weight'] = minWeightCtrl.text.trim();
      if (maxWeightCtrl.text.trim().isNotEmpty) params['max_weight'] = maxWeightCtrl.text.trim();
      if (minPowerCtrl.text.trim().isNotEmpty) params['min_power'] = minPowerCtrl.text.trim();
      if (maxPowerCtrl.text.trim().isNotEmpty) params['max_power'] = maxPowerCtrl.text.trim();
      if (tagsCtrl.text.trim().isNotEmpty) params['tag'] = tagsCtrl.text.trim();
      final uri = Uri.parse('$_base/equipment/assets').replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdrEquipment());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() => _assets = body);
        } else {
          setState(() => _assetsOut = '${r.statusCode}: ${r.body}');
        }
      } else {
        setState(() => _assetsOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) setState(() => _assetsOut = 'error: $e');
    } finally {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  Future<void> _loadBookings() async {
    setState(() {
      _loadingBookings = true;
      _bookingsOut = '';
    });
    try {
      final params = {'limit': '50'};
      if (!_isOperator && (_wallet ?? '').isNotEmpty) {
        params['renter_wallet_id'] = _wallet!;
      }
      final uri = Uri.parse('$_base/equipment/bookings').replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdrEquipment());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() => _bookings = body);
        } else {
          setState(() => _bookingsOut = '${r.statusCode}: ${r.body}');
        }
      } else {
        setState(() => _bookingsOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) setState(() => _bookingsOut = 'error: $e');
    } finally {
      if (mounted) setState(() => _loadingBookings = false);
    }
  }

  Future<void> _pickDates() async {
    try {
      final now = DateTime.now();
      final initialStart = DateTime.tryParse(fromCtrl.text) ?? now;
      final initialEnd = DateTime.tryParse(toCtrl.text) ?? now.add(const Duration(days: 1));
      final range = await showDateRangePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 1)),
        lastDate: now.add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      );
      if (range != null) {
        final fmt = DateFormat("yyyy-MM-ddTHH:mm:ss'Z'");
        fromCtrl.text = fmt.format(range.start.toUtc());
        toCtrl.text = fmt.format(range.end.toUtc());
        _loadAssets();
      }
    } catch (_) {}
  }

  Future<void> _pickLocation() async {
    double lat = double.tryParse(nearLatCtrl.text) ?? 33.5138;
    double lon = double.tryParse(nearLonCtrl.text) ?? 36.2765;
    LatLng marker = LatLng(lat, lon);
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return StatefulBuilder(builder: (context, setSheet) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pick search center', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('${marker.latitude.toStringAsFixed(4)}, ${marker.longitude.toStringAsFixed(4)}'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: TaxiMapWidget(
                        center: marker,
                        initialZoom: 11,
                        markers: {
                          Marker(
                              markerId: const MarkerId('center'),
                              position: marker,
                              draggable: true,
                              onDragEnd: (p) {
                                marker = p;
                                lat = p.latitude;
                                lon = p.longitude;
                                setSheet(() {});
                              })
                        },
                        onTap: (p) {
                          marker = p;
                          lat = p.latitude;
                          lon = p.longitude;
                          setSheet(() {});
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                            child: WaterButton(
                          label: 'Use location',
                          onTap: () {
                            try{ HapticFeedback.lightImpact(); }catch(_){}
                            nearLatCtrl.text = lat.toStringAsFixed(5);
                            nearLonCtrl.text = lon.toStringAsFixed(5);
                            Navigator.of(context).pop();
                            _loadAssets();
                          },
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            );
          });
        });
  }

  Future<void> _pickPoint(String title, double? lat0, double? lon0, void Function(LatLng) onSelect) async {
    double lat = lat0 ?? 33.5138;
    double lon = lon0 ?? 36.2765;
    LatLng marker = LatLng(lat, lon);
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return StatefulBuilder(builder: (context, setSheet) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${marker.latitude.toStringAsFixed(4)}, ${marker.longitude.toStringAsFixed(4)}'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: TaxiMapWidget(
                        center: marker,
                        initialZoom: 12,
                        markers: {
                          Marker(
                              markerId: const MarkerId('center2'),
                              position: marker,
                              draggable: true,
                              onDragEnd: (p) {
                                marker = p;
                                lat = p.latitude;
                                lon = p.longitude;
                                setSheet(() {});
                              })
                        },
                        onTap: (p) {
                          marker = p;
                          lat = p.latitude;
                          lon = p.longitude;
                          setSheet(() {});
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                            child: WaterButton(
                          label: 'Use location',
                          onTap: () {
                            try {
                              HapticFeedback.lightImpact();
                            } catch (_) {}
                            onSelect(LatLng(lat, lon));
                            Navigator.of(context).pop();
                          },
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            );
          });
        });
  }

  Future<List<dynamic>> _loadCalendar(int equipmentId) async {
    if (_calendarCache.containsKey(equipmentId)) {
      final cached = _calendarCache[equipmentId];
      if (cached is List) return cached;
    }
    try {
      final now = DateTime.now();
      final month = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
      final uri = Uri.parse('$_base/equipment/calendar/$equipmentId').replace(queryParameters: {'month': month});
      final r = await http.get(uri, headers: await _hdrEquipment());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map && body['days'] is List) {
          final days = body['days'] as List<dynamic>;
          // also store blocks for reuse
          _calendarCache[equipmentId] = {
            'days': days,
            'blocks': body['blocks'] ?? const [],
          };
          return days;
        } else if (body is List) {
          _calendarCache[equipmentId] = {'days': body, 'blocks': const []};
          return body;
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _showAvailability(Map<String, dynamic> asset) async {
    final id = asset['id'] as int;
    final eqLat = (asset['latitude'] as num?)?.toDouble();
    final eqLon = (asset['longitude'] as num?)?.toDouble();
    List<dynamic> blocks = const [];
    await showModalBottomSheet(
        context: context,
        builder: (_) {
          return FutureBuilder<List<dynamic>>(
              future: _loadCalendar(id),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
                }
                final days = snap.data ?? const [];
                final cached = _calendarCache[id];
                if (cached is Map && cached['blocks'] is List) {
                  blocks = cached['blocks'] as List<dynamic>;
                }
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Availability', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (days.isEmpty) const Text('No calendar data'),
                      if (days.isNotEmpty)
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: days.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final d = days[i] as Map<String, dynamic>? ?? {};
                              final available = d['available'] == true;
                              final blocked = d['blocked'] == true;
                              final booked = d['booked'] == true;
                              Color c = available ? Colors.green : (blocked ? Colors.orange : Colors.red);
                              return Container(
                                width: 72,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: c.withValues(alpha: .6)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text((d['date'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
                                    const SizedBox(height: 4),
                                    Text(available ? 'Free' : (blocked ? 'Hold' : 'Booked'),
                                        style: TextStyle(fontSize: 11, color: c)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      if (days.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Month heatmap', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: days.map((e) {
                            final m = e as Map<String, dynamic>? ?? {};
                            final available = m['available'] == true;
                            final blocked = m['blocked'] == true;
                            final booked = m['booked'] == true;
                            Color c;
                            if (available) {
                              c = Colors.green.withValues(alpha: .8);
                            } else if (blocked) {
                              c = Colors.orange.withValues(alpha: .8);
                            } else if (booked) {
                              c = Colors.red.withValues(alpha: .8);
                            } else {
                              c = Colors.grey.withValues(alpha: .4);
                            }
                            return Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                            );
                          }).toList(),
                        ),
                      ],
                      if (eqLat != null && eqLon != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Row(
                            children: [
                              const Icon(Icons.location_pin, size: 16),
                              const SizedBox(width: 4),
                              Text('Depot: ${eqLat.toStringAsFixed(4)}, ${eqLon.toStringAsFixed(4)}', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      if (blocks.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Holds/maintenance', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        ...blocks.map((b) {
                          final m = b as Map<String, dynamic>? ?? {};
                          return Text('${m['from_iso'] ?? ''} → ${m['to_iso'] ?? ''} • ${m['reason'] ?? ''}', style: const TextStyle(fontSize: 12));
                        }),
                      ],
                      if (_isOperator)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: WaterButton(
                              label: 'Add hold',
                              onTap: () {
                                Navigator.of(context).pop();
                                _addHold(asset);
                              }),
                        ),
                    ],
                  ),
                );
              });
        });
  }

  Future<void> _loadAnalytics() async {
    try {
      final r = await http.get(Uri.parse('$_base/equipment/analytics/summary'), headers: await _hdrEquipment());
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => _analytics = jsonDecode(r.body) as Map<String, dynamic>?);
      }
    } catch (_) {}
  }

  Future<void> _addHold(Map<String, dynamic> asset) async {
    final from = TextEditingController();
    final to = TextEditingController();
    final reason = TextEditingController(text: 'maintenance');
    String out = '';
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return Padding(
            padding: EdgeInsets.only(
                left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
            child: StatefulBuilder(builder: (context, setSheet) {
              Future<void> submit() async {
                setSheet(() => out = 'saving...');
                try {
                  final payload = {
                    'from_iso': from.text.trim(),
                    'to_iso': to.text.trim(),
                    'reason': reason.text.trim(),
                  };
                  final r = await http.post(
                      Uri.parse('$_base/equipment/availability/${asset['id']}'),
                      headers: await _hdrEquipment(json: true),
                      body: jsonEncode(payload));
                  out = '${r.statusCode}: ${r.body}';
                  if (r.statusCode == 200) {
                    _calendarCache.remove(asset['id']);
                  }
                } catch (e) {
                  out = 'error: $e';
                }
                setSheet(() {});
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hold / maintenance', style: Theme.of(context).textTheme.titleLarge),
                  Text(asset['title']?.toString() ?? ''),
                  const SizedBox(height: 8),
                  TextField(controller: from, decoration: const InputDecoration(labelText: 'From ISO')),
                  TextField(controller: to, decoration: const InputDecoration(labelText: 'To ISO')),
                  TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: WaterButton(label: 'Save', onTap: submit)),
                    ],
                  ),
                  if (out.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(out)),
                ],
              );
            }),
          );
        });
  }

  Future<void> _editAsset(Map<String, dynamic> asset) async {
    final title = TextEditingController(text: asset['title']?.toString() ?? '');
    final city = TextEditingController(text: asset['city']?.toString() ?? '');
    final cat = TextEditingController(text: asset['category']?.toString() ?? '');
    final subcat = TextEditingController(text: asset['subcategory']?.toString() ?? '');
    final daily = TextEditingController(text: asset['daily_rate_cents']?.toString() ?? '');
    final weekly = TextEditingController(text: asset['weekly_rate_cents']?.toString() ?? '');
    final monthly = TextEditingController(text: asset['monthly_rate_cents']?.toString() ?? '');
    final qtyCtrl = TextEditingController(text: asset['quantity']?.toString() ?? '1');
    final minDays = TextEditingController(text: asset['min_rental_days']?.toString() ?? '');
    final maxDays = TextEditingController(text: asset['max_rental_days']?.toString() ?? '');
    final weekendPct = TextEditingController(text: asset['weekend_surcharge_pct']?.toString() ?? '');
    final longtermPct = TextEditingController(text: asset['longterm_discount_pct']?.toString() ?? '');
    final minNotice = TextEditingController(text: asset['min_notice_hours']?.toString() ?? '');
    final specs = TextEditingController(text: asset['specs']?.toString() ?? '');
    final weight = TextEditingController(text: asset['weight_kg']?.toString() ?? '');
    final power = TextEditingController(text: asset['power_kw']?.toString() ?? '');
    final deposit = TextEditingController(text: asset['deposit_cents']?.toString() ?? '');
    final deliveryFee = TextEditingController(text: asset['delivery_fee_cents']?.toString() ?? '');
    final deliveryPerKm = TextEditingController(text: asset['delivery_per_km_cents']?.toString() ?? '');
    final imageUrl = TextEditingController(text: asset['image_url']?.toString() ?? '');
    final tags = TextEditingController(text: asset['tags']?.toString() ?? '');
    final lat = TextEditingController(text: asset['latitude']?.toString() ?? '');
    final lon = TextEditingController(text: asset['longitude']?.toString() ?? '');
    String out = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: StatefulBuilder(builder: (context, setSheet) {
          Future<void> submit() async {
            setSheet(() => out = 'saving...');
            try {
              final body = {
                'title': title.text.trim(),
                'city': city.text.trim(),
                'category': cat.text.trim(),
                'subcategory': subcat.text.trim(),
                'daily_rate_cents': int.tryParse(daily.text.trim()),
                'weekly_rate_cents': int.tryParse(weekly.text.trim()),
                'monthly_rate_cents': int.tryParse(monthly.text.trim()),
                'quantity': int.tryParse(qtyCtrl.text.trim()),
                'min_rental_days': int.tryParse(minDays.text.trim()),
                'max_rental_days': int.tryParse(maxDays.text.trim()),
                'weekend_surcharge_pct': double.tryParse(weekendPct.text.trim()),
                'longterm_discount_pct': double.tryParse(longtermPct.text.trim()),
                'min_notice_hours': int.tryParse(minNotice.text.trim()),
                'specs': specs.text.trim(),
                'weight_kg': double.tryParse(weight.text.trim()),
                'power_kw': double.tryParse(power.text.trim()),
                'deposit_cents': int.tryParse(deposit.text.trim()),
                'delivery_fee_cents': int.tryParse(deliveryFee.text.trim()),
                'delivery_per_km_cents': double.tryParse(deliveryPerKm.text.trim()),
                'image_url': imageUrl.text.trim(),
                'tags': tags.text.trim(),
                'latitude': double.tryParse(lat.text.trim()),
                'longitude': double.tryParse(lon.text.trim()),
              };
              final r = await http.patch(
                  Uri.parse('$_base/equipment/assets/${asset['id']}'),
                  headers: await _hdrEquipment(json: true),
                  body: jsonEncode(body));
              out = '${r.statusCode}: ${r.body}';
              if (r.statusCode == 200) {
                _calendarCache.remove(asset['id']);
                _loadAssets();
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
                Text('Edit equipment', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: city, decoration: const InputDecoration(labelText: 'City')),
                TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude')),
                TextField(controller: lon, decoration: const InputDecoration(labelText: 'Longitude')),
                TextField(controller: cat, decoration: const InputDecoration(labelText: 'Category')),
                TextField(controller: subcat, decoration: const InputDecoration(labelText: 'Subcategory')),
                TextField(
                    controller: daily,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Daily rate (cents)')),
                TextField(
                    controller: weekly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Weekly rate (cents)')),
                TextField(
                    controller: monthly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Monthly rate (cents)')),
                TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity')),
                TextField(controller: specs, decoration: const InputDecoration(labelText: 'Specs (brief)')),
                TextField(
                    controller: weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Weight kg')),
                TextField(
                    controller: power,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Power kW')),
                TextField(
                    controller: minDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min rental days')),
                TextField(
                    controller: maxDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max rental days')),
                TextField(
                    controller: weekendPct,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Weekend surcharge %')),
                TextField(
                    controller: longtermPct,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Long-term discount %')),
                TextField(
                    controller: minNotice,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min notice hours')),
                TextField(
                    controller: deposit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Deposit (cents)')),
                TextField(
                    controller: deliveryFee,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Delivery base fee (cents)')),
                TextField(
                    controller: deliveryPerKm,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Delivery per km (cents)')),
                TextField(controller: imageUrl, decoration: const InputDecoration(labelText: 'Image URL')),
                TextField(controller: tags, decoration: const InputDecoration(labelText: 'Tags')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: WaterButton(
                      label: 'Save',
                      onTap: submit,
                    )),
                  ],
                ),
                if (out.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(out, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Future<void> _createAssetDialog() async {
    final title = TextEditingController();
    final city = TextEditingController();
    final cat = TextEditingController();
    final subcat = TextEditingController();
    final daily = TextEditingController();
    final weekly = TextEditingController();
    final monthly = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final minDays = TextEditingController();
    final maxDays = TextEditingController();
    final weekendPct = TextEditingController();
    final longtermPct = TextEditingController();
    final minNotice = TextEditingController();
    final specs = TextEditingController();
    final weight = TextEditingController();
    final power = TextEditingController();
    final deposit = TextEditingController();
    final deliveryFee = TextEditingController();
    final deliveryPerKm = TextEditingController();
    final imageUrl = TextEditingController();
    final tags = TextEditingController();
    final lat = TextEditingController();
    final lon = TextEditingController();
    String out = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: StatefulBuilder(builder: (context, setSheet) {
          Future<void> submit() async {
            setSheet(() => out = 'saving...');
            try {
              final body = {
                'title': title.text.trim(),
                'city': city.text.trim(),
                'category': cat.text.trim().isNotEmpty ? cat.text.trim() : categoryCtrl.text.trim(),
                'subcategory': subcat.text.trim(),
                'daily_rate_cents': int.tryParse(daily.text.trim()),
                'weekly_rate_cents': int.tryParse(weekly.text.trim()),
                'monthly_rate_cents': int.tryParse(monthly.text.trim()),
                'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 1,
                'min_rental_days': int.tryParse(minDays.text.trim()),
                'max_rental_days': int.tryParse(maxDays.text.trim()),
                'weekend_surcharge_pct': double.tryParse(weekendPct.text.trim()),
                'longterm_discount_pct': double.tryParse(longtermPct.text.trim()),
                'min_notice_hours': int.tryParse(minNotice.text.trim()),
                'specs': specs.text.trim(),
                'weight_kg': double.tryParse(weight.text.trim()),
                'power_kw': double.tryParse(power.text.trim()),
                'deposit_cents': int.tryParse(deposit.text.trim()),
                'delivery_fee_cents': int.tryParse(deliveryFee.text.trim()),
                'delivery_per_km_cents': double.tryParse(deliveryPerKm.text.trim()),
                'image_url': imageUrl.text.trim(),
                'tags': tags.text.trim(),
                'latitude': double.tryParse(lat.text.trim()),
                'longitude': double.tryParse(lon.text.trim()),
              };
              final r = await http.post(Uri.parse('$_base/equipment/assets'),
                  headers: await _hdrEquipment(json: true), body: jsonEncode(body));
              setSheet(() => out = '${r.statusCode}: ${r.body}');
              if (r.statusCode == 200) {
                _loadAssets();
              }
            } catch (e) {
              setSheet(() => out = 'error: $e');
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add equipment', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: city, decoration: const InputDecoration(labelText: 'City')),
              TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude')),
              TextField(controller: lon, decoration: const InputDecoration(labelText: 'Longitude')),
              TextField(controller: cat, decoration: const InputDecoration(labelText: 'Category')),
              TextField(controller: subcat, decoration: const InputDecoration(labelText: 'Subcategory')),
              TextField(
                  controller: daily,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Daily rate (cents)')),
              TextField(
                  controller: weekly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weekly rate (cents)')),
              TextField(
                  controller: monthly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Monthly rate (cents)')),
              TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity')),
              TextField(controller: specs, decoration: const InputDecoration(labelText: 'Specs (brief)')),
              TextField(
                  controller: weight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weight kg')),
              TextField(
                  controller: power,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Power kW')),
              TextField(
                  controller: minDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min rental days')),
              TextField(
                  controller: maxDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max rental days')),
              TextField(
                  controller: weekendPct,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weekend surcharge %')),
              TextField(
                  controller: longtermPct,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Long-term discount %')),
              TextField(
                  controller: minNotice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min notice hours')),
              TextField(
                  controller: deposit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Deposit (cents)')),
              TextField(
                  controller: deliveryFee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Delivery base fee (cents)')),
              TextField(
                  controller: deliveryPerKm,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Delivery per km (cents)')),
              TextField(controller: imageUrl, decoration: const InputDecoration(labelText: 'Image URL')),
              TextField(controller: tags, decoration: const InputDecoration(labelText: 'Tags')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: WaterButton(
                    label: 'Save',
                    onTap: submit,
                  )),
                ],
              ),
              if (out.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(out, style: const TextStyle(fontSize: 12)),
                ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _quoteAndBook(Map<String, dynamic> asset) async {
    final from = TextEditingController(text: fromCtrl.text);
    final to = TextEditingController(text: toCtrl.text);
    final notes = TextEditingController();
    final deliveryAddress = TextEditingController();
    final pickupAddress = TextEditingController();
    bool delivery = false;
    String out = '';
    List<dynamic> calendar = await _loadCalendar(asset['id'] as int);
    Map<String, dynamic>? quotePayload;
    final eqLat = (asset['latitude'] as num?)?.toDouble();
    final eqLon = (asset['longitude'] as num?)?.toDouble();

    Future<void> submit() async {
      try {
        final qty = _qty;
        final payload = {
          'equipment_id': asset['id'],
          'from_iso': from.text.trim(),
          'to_iso': to.text.trim(),
          'quantity': qty,
          'delivery_required': delivery,
          'delivery_km': double.tryParse(deliveryKmCtrl.text.trim()),
          'delivery_lat': _deliveryLat,
          'delivery_lon': _deliveryLon,
          'delivery_address': deliveryAddress.text.trim().isEmpty ? null : deliveryAddress.text.trim(),
          'pickup_address': pickupAddress.text.trim().isEmpty ? null : pickupAddress.text.trim(),
          'renter_wallet_id': _wallet,
          'confirm': true,
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        };
        final r = await http.post(Uri.parse('$_base/equipment/book'),
            headers: await _hdrEquipment(json: true), body: jsonEncode(payload));
        out = '${r.statusCode}: ${r.body}';
        if (r.statusCode == 200) {
          _loadBookings();
        }
      } catch (e) {
        out = 'error: $e';
      }
      if (mounted) setState(() {});
    }

    Future<void> geocodeAddress(TextEditingController ctrl, bool isDelivery) async {
      try {
        final q = ctrl.text.trim();
        if (q.isEmpty) return;
        final uri = Uri.parse('$_base/osm/geocode').replace(queryParameters: {'q': q});
        final r = await http.get(uri);
        if (r.statusCode == 200) {
          final body = jsonDecode(r.body);
          if (body is List && body.isNotEmpty) {
            final first = body.first as Map<String, dynamic>? ?? {};
            final lat = (first['lat'] as num?)?.toDouble();
            final lon = (first['lon'] as num?)?.toDouble();
            if (lat != null && lon != null) {
              setState(() {
                if (isDelivery) {
                  _deliveryLat = lat;
                  _deliveryLon = lon;
                } else {
                  _pickupLat = lat;
                  _pickupLon = lon;
                }
              });
            }
            if (q.isNotEmpty) _saveRecent(q);
            setState(() {
              _addressSuggestions = (body as List)
                  .take(5)
                  .map((e) => (e as Map)['display_name']?.toString() ?? (e as Map)['name']?.toString() ?? '')
                  .where((s) => s.isNotEmpty)
                  .cast<String>()
                  .toList();
            });
          }
        }
      } catch (_) {}
    }

    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return Padding(
            padding: EdgeInsets.only(
                left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
            child: StatefulBuilder(builder: (context, setSheet) {
              Future<void> quote() async {
                setSheet(() => out = 'quoting...');
                try {
          final payload = {
            'equipment_id': asset['id'],
            'from_iso': from.text.trim(),
            'to_iso': to.text.trim(),
            'quantity': _qty,
            'delivery_required': delivery,
            'delivery_km': double.tryParse(deliveryKmCtrl.text.trim()),
            'delivery_lat': _deliveryLat,
            'delivery_lon': _deliveryLon,
            'delivery_address': deliveryAddress.text.trim().isEmpty ? null : deliveryAddress.text.trim(),
            'pickup_address': pickupAddress.text.trim().isEmpty ? null : pickupAddress.text.trim(),
          };
                  final r = await http.post(Uri.parse('$_base/equipment/quote'),
                      headers: await _hdrEquipment(json: true), body: jsonEncode(payload));
                  out = '${r.statusCode}: ${r.body}';
                  try{
                    quotePayload = jsonDecode(r.body) as Map<String, dynamic>?;
                  }catch(_){}
                } catch (e) {
                  out = 'error: $e';
                }
                setSheet(() {});
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asset['title']?.toString() ?? '',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                          controller: from,
                          decoration: const InputDecoration(labelText: 'From (ISO)'),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                          controller: to,
                          decoration: const InputDecoration(labelText: 'To (ISO)'),
                        )),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: Text('Qty: $_qty',
                                style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            if (_qty > 1) setSheet(() => _qty -= 1);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setSheet(() => _qty += 1),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Delivery & pickup'),
                      value: delivery,
                      onChanged: (v) => setSheet(() => delivery = v),
                    ),
                    if (delivery) ...[
                      Row(
                        children: [
                          Expanded(
                              child: TextField(
                            controller: deliveryAddress,
                            decoration: const InputDecoration(labelText: 'Delivery address (optional)'),
                          )),
                          IconButton(
                              onPressed: () => geocodeAddress(deliveryAddress, true),
                              icon: const Icon(Icons.search))
                        ],
                      ),
                      if (_addressSuggestions.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: _addressSuggestions
                              .map((s) => ActionChip(
                                    label: Text(s, style: const TextStyle(fontSize: 12)),
                                    onPressed: () {
                                      deliveryAddress.text = s;
                                      geocodeAddress(deliveryAddress, true);
                                    },
                                  ))
                              .toList(),
                        ),
                      if (_recentAddresses.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: _recentAddresses
                              .map((s) => ActionChip(
                                    label: Text(s, style: const TextStyle(fontSize: 12)),
                                    onPressed: () {
                                      deliveryAddress.text = s;
                                      geocodeAddress(deliveryAddress, true);
                                    },
                                  ))
                              .toList(),
                        ),
                      Row(
                        children: [
                          Expanded(
                              child: TextField(
                            controller: pickupAddress,
                            decoration: const InputDecoration(labelText: 'Pickup address (optional)'),
                          )),
                          IconButton(
                              onPressed: () => geocodeAddress(pickupAddress, false),
                              icon: const Icon(Icons.search))
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                              child: Text(
                            _deliveryLat != null ? 'Dropoff: ${_deliveryLat?.toStringAsFixed(5)}, ${_deliveryLon?.toStringAsFixed(5)}' : 'Dropoff pin not set',
                            style: const TextStyle(fontSize: 12),
                          )),
                          TextButton(
                      onPressed: () => _pickPoint('Set delivery location', _deliveryLat, _deliveryLon,
                                  (p) => setSheet(() {
                                        _deliveryLat = p.latitude;
                                        _deliveryLon = p.longitude;
                                      })),
                          child: const Text('Set delivery pin')),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                              child: Text(
                            _pickupLat != null ? 'Pickup: ${_pickupLat?.toStringAsFixed(5)}, ${_pickupLon?.toStringAsFixed(5)}' : 'Pickup pin not set',
                            style: const TextStyle(fontSize: 12),
                          )),
                          TextButton(
                              onPressed: () => _pickPoint('Set pickup location', _pickupLat, _pickupLon,
                                  (p) => setSheet(() {
                                        _pickupLat = p.latitude;
                                        _pickupLon = p.longitude;
                                      })),
                              child: const Text('Set pickup pin')),
                        ],
                      ),
                    ],
                    if (calendar.isNotEmpty)
                      SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: calendar.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, i) {
                            final d = calendar[i] as Map<String, dynamic>? ?? {};
                            final available = d['available'] == true;
                            final blocked = d['blocked'] == true;
                            final booked = d['booked'] == true;
                            Color c = available ? Colors.green : (blocked ? Colors.orange : Colors.red);
                            return InkWell(
                              onTap: available
                                  ? () {
                                      final day = DateTime.tryParse((d['date'] ?? '').toString());
                                      if (day != null) {
                                        final fmt = DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
                                        from.text = fmt.format(DateTime(day.year, day.month, day.day, 8).toUtc());
                                        to.text = fmt.format(DateTime(day.year, day.month, day.day, 18).toUtc());
                                        setSheet(() {});
                                      }
                                    }
                                  : null,
                              child: Container(
                                width: 68,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: c.withValues(alpha: .6)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text((d['date'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
                                    Text(available ? 'Free' : (blocked ? 'Hold' : 'Booked'),
                                        style: TextStyle(fontSize: 11, color: c)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (delivery)
                      TextField(
                        controller: deliveryKmCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Delivery distance (km, optional)'),
                      ),
                    TextField(
                      controller: notes,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    ),
                    const SizedBox(height: 12),
                    if (quotePayload != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Quote breakdown', style: TextStyle(fontWeight: FontWeight.w700)),
                            Text('Rental: ${quotePayload?['rental_cents'] ?? ''}'),
                            Text('Delivery: ${quotePayload?['delivery_cents'] ?? ''}'),
                            Text('Deposit: ${quotePayload?['deposit_cents'] ?? ''}'),
                            if (quotePayload?['weekend_days'] != null) Text('Weekend days: ${quotePayload?['weekend_days']}'),
                            if (quotePayload?['min_days_applied'] != null) Text('Min days: ${quotePayload?['min_days_applied']}'),
                            if (quotePayload?['longterm_discount_pct'] != null) Text('Long-term discount: ${quotePayload?['longterm_discount_pct']}%'),
                            if (quotePayload?['delivery_distance_km'] != null) Text('Route: ${quotePayload?['delivery_distance_km']} km'),
                            Text('Total: ${quotePayload?['total_cents'] ?? ''} ${quotePayload?['currency'] ?? ''}'),
                          ],
                        ),
                      ),
                    if (quotePayload?['delivery_route'] is List && eqLat != null && eqLon != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          height: 180,
                          child: TaxiMapWidget(
                            center: LatLng(_deliveryLat ?? eqLat, _deliveryLon ?? eqLon),
                            initialZoom: 11,
                            markers: {
                              Marker(markerId: const MarkerId('eq'), position: LatLng(eqLat, eqLon)),
                              if (_deliveryLat != null && _deliveryLon != null)
                                Marker(markerId: const MarkerId('drop'), position: LatLng(_deliveryLat!, _deliveryLon!)),
                              if (_pickupLat != null && _pickupLon != null)
                                Marker(markerId: const MarkerId('pick'), position: LatLng(_pickupLat!, _pickupLon!)),
                            },
                            polylines: {
                              Polyline(
                                polylineId: const PolylineId('delivery'),
                                color: Colors.blueAccent,
                                width: 4,
                                points: (quotePayload!['delivery_route'] as List)
                                    .map((p) => LatLng(
                                          (p[0] as num).toDouble(),
                                          (p[1] as num).toDouble(),
                                        ))
                                    .toList(),
                              ),
                            },
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                            child: WaterButton(
                          label: 'Quote',
                          onTap: quote,
                        )),
                        const SizedBox(width: 12),
                        Expanded(
                            child: WaterButton(
                          label: 'Book',
                          onTap: submit,
                        )),
                      ],
                    ),
                    if (out.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(out, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              );
            }),
          );
        });
  }

  Widget _buildAnalytics() {
    if (_analytics == null) return const SizedBox.shrink();
    final cards = <Widget>[];
    void add(String label, Object? value) {
      cards.add(Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(value?.toString() ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ));
    }

    add('Assets', _analytics!['assets_total']);
    add('Available', _analytics!['assets_available']);
    add('Active jobs', _analytics!['bookings_active']);
    add('Pending', _analytics!['bookings_pending']);
    add('Booked wk', _analytics!['bookings_week']);
    add('Blocks wk', _analytics!['blocks_week']);
    add('Deliveries open', _analytics!['logistics_open']);
    add('Revenue 30d (cents)', _analytics!['revenue_30d_cents']);

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1.6,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  Widget _catalogTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(labelText: 'Search'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: tagsCtrl,
                  decoration: const InputDecoration(labelText: 'Tags'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: nearLatCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Near lat'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: nearLonCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Near lon'),
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
              SizedBox(
                width: 120,
                child: TextField(
                  controller: minPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min price'),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: maxPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max price'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: minWeightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min weight kg'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: maxWeightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max weight kg'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: minPowerCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min power kW'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: maxPowerCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max power kW'),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: fromCtrl,
                  decoration: const InputDecoration(labelText: 'From (ISO)'),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: toCtrl,
                  decoration: const InputDecoration(labelText: 'To (ISO)'),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: const Text('Pick dates'),
                onPressed: _pickDates,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.pin_drop_outlined),
                label: const Text('Choose center'),
                onPressed: _pickLocation,
              ),
              FilterChip(
                label: const Text('Available only'),
                selected: _availableOnly,
                onSelected: (v) => setState(() => _availableOnly = v),
              ),
              DropdownButton<String>(
                value: _order,
                items: const [
                  DropdownMenuItem(value: 'newest', child: Text('Newest')),
                  DropdownMenuItem(value: 'price_asc', child: Text('Price ↑')),
                  DropdownMenuItem(value: 'price_desc', child: Text('Price ↓')),
                ],
                onChanged: (v) => setState(() => _order = v ?? 'newest'),
              ),
              WaterButton(label: 'Search', onTap: _loadAssets),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingAssets) const LinearProgressIndicator(),
          if (_assetsOut.isNotEmpty) StatusBanner.info(_assetsOut),
          Expanded(
            child: ListView.builder(
              itemCount: _assets.length,
              itemBuilder: (_, i) {
                final a = _assets[i] as Map<String, dynamic>;
                final price = (a['daily_rate_cents'] ?? '').toString();
                final available = a['available_quantity'];
                final dist = a['distance_km'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a['title']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('${a['city'] ?? ''} • ${a['category'] ?? ''}${a['subcategory'] != null ? ' / ${a['subcategory']}' : ''}',
                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        if (dist != null)
                          Text('~${dist.toString()} km away', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        if ((a['weight_kg'] ?? '') != '')
                          Text('Weight: ${a['weight_kg']} kg', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        if ((a['power_kw'] ?? '') != '')
                          Text('Power: ${a['power_kw']} kW', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        if ((a['tags'] ?? '') != '')
                          Text('Tags: ${a['tags']}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text('Daily: $price ${a['currency'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (available != null)
                          Text('Available: $available / ${a['quantity'] ?? ''}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        if ((a['weekend_surcharge_pct'] ?? 0) != 0)
                          Text('Weekend +${a['weekend_surcharge_pct']}%',
                              style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        if ((a['longterm_discount_pct'] ?? 0) != 0)
                          Text('Long-term -${a['longterm_discount_pct']}%',
                              style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            TextButton(onPressed: () => _showAvailability(a), child: const Text('Availability')),
                            if (_isOperator)
                              TextButton(
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => EquipmentCalendarPage(
                                            baseUrl: _base,
                                            equipmentId: a['id'] as int,
                                            title: a['title']?.toString() ?? 'Equipment',
                                          ))),
                                  child: const Text('Calendar')),
                            if (_isOperator)
                              TextButton(
                                  onPressed: () => _addHold(a), child: const Text('Hold/maintenance')),
                            Expanded(
                                child: WaterButton(
                              label: 'Book',
                              onTap: () => _quoteAndBook(a),
                            )),
                            if (_isOperator)
                              IconButton(
                                icon: const Icon(Icons.edit_note),
                                onPressed: () => _editAsset(a),
                              )
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookingsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              WaterButton(label: 'Refresh', onTap: _loadBookings),
              const SizedBox(width: 12),
              if (_loadingBookings) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (_bookingsOut.isNotEmpty) StatusBanner.info(_bookingsOut),
          Expanded(
            child: ListView.separated(
              itemCount: _bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final b = _bookings[i] as Map<String, dynamic>;
                final status = b['status']?.toString() ?? '';
                final amount = b['amount_cents'] ?? '';
                return GlassPanel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${b['equipment_id'] ?? ''} · $status',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('From: ${b['from_iso'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      Text('To: ${b['to_iso'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      Text('Qty: ${b['quantity'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      Text('Amount: $amount ${b['currency'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      if (_isOperator)
                        Row(
                          children: [
                            TextButton(
                                onPressed: () => _updateStatus(b['id']?.toString() ?? '', 'confirmed'),
                                child: const Text('Confirm')),
                            TextButton(
                                onPressed: () => _updateStatus(b['id']?.toString() ?? '', 'active'),
                                child: const Text('Start')),
                            TextButton(
                                onPressed: () => _updateStatus(b['id']?.toString() ?? '', 'completed'),
                                child: const Text('Complete')),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await http.post(Uri.parse('$_base/equipment/bookings/$id/status'),
          headers: await _hdrEquipment(json: true), body: jsonEncode({'status': status}));
      _loadBookings();
      _loadAnalytics();
    } catch (_) {}
  }

  Widget _opsTab() {
    // Build a simple tasks list from bookings
    final tasks = <Map<String, dynamic>>[];
    for (final b in _bookings) {
      final m = b as Map<String, dynamic>;
      final bid = m['id'];
      final eqId = m['equipment_id'];
      final tlist = m['tasks'];
      if (tlist is List) {
        for (final t in tlist) {
          if (t is Map<String, dynamic>) {
            tasks.add({
              'id': t['id'],
              'kind': t['kind'],
              'status': t['status'],
              'scheduled': t['scheduled_iso'],
              'address': t['address'],
              'assignee': t['assignee'],
              'booking_id': bid,
              'equipment_id': eqId,
            });
          }
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(child: WaterButton(label: 'New asset', onTap: _createAssetDialog)),
              const SizedBox(width: 12),
              IconButton(onPressed: _loadAnalytics, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 12),
          _buildAnalytics(),
          const SizedBox(height: 12),
          if (tasks.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Open logistics', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...tasks.map(
                  (t) => GlassPanel(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${t['kind']} • ${t['status']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Booking ${t['booking_id']} • Eq ${t['equipment_id']}', style: const TextStyle(fontSize: 12)),
                        if (t['address'] != null) Text(t['address'].toString(), style: const TextStyle(fontSize: 12)),
                        if (t['scheduled'] != null) Text('At: ${t['scheduled']}', style: const TextStyle(fontSize: 12)),
                        if (t['assignee'] != null) Text('Assigned: ${t['assignee']}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                )
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final tabs = [
      Tab(text: l.equipmentTitle),
      Tab(text: l.historyTitle),
      if (_isOperator) const Tab(text: 'Ops'),
    ];

    return AppScaffold(
      appBar: AppBar(
        title: Text(l.equipmentTitle),
        bottom: TabBar(controller: _tabs, tabs: tabs),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _catalogTab(),
          _bookingsTab(),
          if (_isOperator) _opsTab(),
        ],
      ),
    );
  }
}
