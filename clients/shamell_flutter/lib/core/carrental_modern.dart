import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'glass.dart';
import 'l10n.dart';
import 'status_banner.dart';
import '../main.dart' show AppBG, WaterButton;

Future<Map<String, String>> _hdrCarrental({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final sp = await SharedPreferences.getInstance();
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class CarrentalModernPage extends StatefulWidget {
  final String baseUrl;
  const CarrentalModernPage(this.baseUrl, {super.key});

  @override
  State<CarrentalModernPage> createState() => _CarrentalModernPageState();
}

class _CarrentalModernPageState extends State<CarrentalModernPage> {
  final TextEditingController cityCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController fromCtrl = TextEditingController();
  final TextEditingController toCtrl = TextEditingController();
  final TextEditingController dropoffCtrl = TextEditingController();
  List<dynamic> _cars = const [];
  String _carsOut = '';
  bool _loading = false;
  String _transmissionFilter = '';
  String _fuelFilter = '';
  double _maxPrice = 0;
  int _minSeats = 0;
  bool _freeCancelOnly = false;
  bool _unlimitedOnly = false;
  String _sort = 'price_asc'; // price_asc, price_desc, newest
  bool _showScrollTop = false;
  late final ScrollController _scroll;
  String _classFilter = ''; // economy, suv, premium, van
  Set<int> _saved = {};
  bool _savedOnly = false;
  bool _oneWayOnly = false;
  int get _durationDays {
    final f = DateTime.tryParse(fromCtrl.text.trim());
    final t = DateTime.tryParse(toCtrl.text.trim());
    if (f == null || t == null) return 0;
    final d = t.difference(f).inDays;
    return d <= 0 ? 1 : d;
  }

  // Operator bookings
  List<dynamic> _bookings = const [];
  bool _bookingsLoading = false;
  String _bookingsOut = '';
  String _bookingStatusFilter = '';

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    cityCtrl.dispose();
    searchCtrl.dispose();
    fromCtrl.dispose();
    toCtrl.dispose();
    dropoffCtrl.dispose();
    super.dispose();
  }

  String get _base => widget.baseUrl.trim();

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_onScroll);
    _loadSaved();
    _loadCars();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
      // placeholder for lazy load if backend supports paging later
    }
    final show = _scroll.position.pixels > 400;
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }
  }

  Future<void> _loadSaved() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList('carrental_saved') ?? const [];
    setState(() {
      _saved = raw.map((e) => int.tryParse(e)).whereType<int>().toSet();
    });
  }

  Future<void> _persistSaved() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('carrental_saved', _saved.map((e) => e.toString()).toList());
  }

  void _toggleSaved(int id) {
    setState(() {
      if (_saved.contains(id)) {
        _saved.remove(id);
      } else {
        _saved.add(id);
      }
    });
    _persistSaved();
  }

  Future<void> _loadCars() async {
    setState(() {
      _loading = true;
      _carsOut = '';
    });
    try {
      final uri = Uri.parse('$_base/carrental/cars').replace(queryParameters: {
        'q': searchCtrl.text.trim(),
        'city': cityCtrl.text.trim(),
        'dropoff_city': dropoffCtrl.text.trim(),
        'from': fromCtrl.text.trim(),
        'to': toCtrl.text.trim(),
      });
      final r = await http.get(uri, headers: await _hdrCarrental());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() => _cars = body);
        } else {
          setState(() {
            _carsOut = '${r.statusCode}: ${r.body}';
            _cars = const [];
          });
        }
      } else {
        setState(() => _carsOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) setState(() => _carsOut = 'error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bookCar(Map<String, dynamic> car) async {
    final nameCtrl = TextEditingController(text: car['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController();
    final from = TextEditingController(text: fromCtrl.text);
    final to = TextEditingController(text: toCtrl.text);
    String insurance = 'standard'; // standard / plus
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
                setSheet(() => out = 'booking...');
                try {
                  final resp = await http.post(Uri.parse('$_base/carrental/book'),
                      headers: await _hdrCarrental(json: true),
                      body: jsonEncode({
                        'car_id': car['id'],
                        'renter_name': nameCtrl.text.trim(),
                        'renter_phone':
                            phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                        'from_iso': from.text.trim(),
                        'to_iso': to.text.trim(),
                        'confirm': true,
                        'insurance': insurance,
                      }));
                  setSheet(() => out = '${resp.statusCode}: ${resp.body}');
                } catch (e) {
                  setSheet(() => out = 'error: $e');
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Book ${car['name'] ?? 'car'}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Name')),
                  TextField(
                      controller: phoneCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Phone (optional)')),
                  TextField(
                      controller: from,
                      decoration: const InputDecoration(labelText: 'From (yyyy-mm-dd)')),
                  TextField(
                      controller: to,
                      decoration: const InputDecoration(labelText: 'To (yyyy-mm-dd)')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Protection'),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: insurance,
                        items: const [
                          DropdownMenuItem(value: 'standard', child: Text('Standard (included)')),
                          DropdownMenuItem(value: 'plus', child: Text('Plus (+15%)')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setSheet(() => insurance = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  WaterButton(label: 'Confirm booking', onTap: submit),
                  if (out.isNotEmpty) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: StatusBanner.info(out, dense: true),
                  )
                ],
              );
            }),
          );
        });
  }

  Future<void> _quoteCar(String carId) async {
    if (carId.isEmpty) return;
    try {
      final r = await http.post(Uri.parse('$_base/carrental/quote'),
          headers: await _hdrCarrental(json: true),
          body: jsonEncode({
            'car_id': int.tryParse(carId) ?? 0,
            'from_iso': fromCtrl.text.trim(),
            'to_iso': toCtrl.text.trim(),
          }));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quote ${r.statusCode}: ${r.body}')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Quote error: $e')));
    }
  }

  Future<void> _loadBookings() async {
    setState(() {
      _bookingsLoading = true;
      _bookingsOut = '';
    });
    try {
      final params = <String, String>{'limit': '100'};
      if (_bookingStatusFilter.isNotEmpty) params['status'] = _bookingStatusFilter;
      final uri =
          Uri.parse('$_base/carrental/bookings').replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdrCarrental());
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
      if (mounted) setState(() => _bookingsLoading = false);
    }
  }

  Future<void> _opConfirm(String id) async {
    try {
      await http.post(Uri.parse('$_base/carrental/bookings/$id/confirm'),
          headers: await _hdrCarrental(json: true), body: jsonEncode({'confirm': true}));
      await _loadBookings();
    } catch (e) {
      if (mounted) setState(() => _bookingsOut = 'error: $e');
    }
  }

  Future<void> _opCancel(String id) async {
    try {
      await http.post(Uri.parse('$_base/carrental/bookings/$id/cancel'));
      await _loadBookings();
    } catch (e) {
      if (mounted) setState(() => _bookingsOut = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);

    final hero = GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.carrentalTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
              'Compare cars, filter by pickup city, and book instantly.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7))),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: cityCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pickup city',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: dropoffCtrl,
                decoration: const InputDecoration(
                  labelText: 'Drop-off city (optional)',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                controller: fromCtrl,
                decoration: const InputDecoration(
                  labelText: 'From (yyyy-mm-dd)',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                controller: toCtrl,
                decoration: const InputDecoration(
                  labelText: 'To (yyyy-mm-dd)',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Search model or make',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            WaterButton(
              label: _loading ? 'Searching...' : 'Search cars',
              icon: Icons.directions_car,
              onTap: () {
                if (!_loading) {
                  _loadCars();
                }
              },
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            TextButton(
              onPressed: () {
                final now = DateTime.now();
                fromCtrl.text = now.toIso8601String().split('T').first;
                toCtrl.text =
                    now.add(const Duration(days: 2)).toIso8601String().split('T').first;
                setState(() {});
              },
              child: const Text('Pick tomorrow for 2 days'),
            ),
            TextButton(
              onPressed: () {
                cityCtrl.clear();
                dropoffCtrl.clear();
                searchCtrl.clear();
                fromCtrl.clear();
                toCtrl.clear();
                setState(() {});
              },
              child: const Text('Clear fields'),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('Auto'),
              selected: _transmissionFilter == 'auto',
              onSelected: (_) => setState(() => _transmissionFilter = _transmissionFilter == 'auto' ? '' : 'auto'),
            ),
            ChoiceChip(
              label: const Text('Manual'),
              selected: _transmissionFilter == 'manual',
              onSelected: (_) => setState(() => _transmissionFilter = _transmissionFilter == 'manual' ? '' : 'manual'),
            ),
            ChoiceChip(
              label: const Text('Electric'),
              selected: _fuelFilter == 'electric',
              onSelected: (_) => setState(() => _fuelFilter = _fuelFilter == 'electric' ? '' : 'electric'),
            ),
            ChoiceChip(
              label: const Text('Hybrid'),
              selected: _fuelFilter == 'hybrid',
              onSelected: (_) => setState(() => _fuelFilter = _fuelFilter == 'hybrid' ? '' : 'hybrid'),
            ),
            ChoiceChip(
              label: const Text('Price ↑'),
              selected: _sort == 'price_asc',
              onSelected: (_) => setState(() => _sort = 'price_asc'),
            ),
            ChoiceChip(
              label: const Text('Price ↓'),
              selected: _sort == 'price_desc',
              onSelected: (_) => setState(() => _sort = 'price_desc'),
            ),
            ChoiceChip(
              label: const Text('Newest'),
              selected: _sort == 'newest',
              onSelected: (_) => setState(() => _sort = 'newest'),
            ),
            ChoiceChip(
              label: const Text('Top rated'),
              selected: _sort == 'rating',
              onSelected: (_) => setState(() => _sort = 'rating'),
            ),
            ChoiceChip(
              label: const Text('Economy'),
              selected: _classFilter == 'economy',
              onSelected: (_) => setState(() => _classFilter = _classFilter == 'economy' ? '' : 'economy'),
            ),
            ChoiceChip(
              label: const Text('SUV'),
              selected: _classFilter == 'suv',
              onSelected: (_) => setState(() => _classFilter = _classFilter == 'suv' ? '' : 'suv'),
            ),
            ChoiceChip(
              label: const Text('Premium'),
              selected: _classFilter == 'premium',
              onSelected: (_) => setState(() => _classFilter = _classFilter == 'premium' ? '' : 'premium'),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                decoration: const InputDecoration(labelText: 'Max price/day'),
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => _maxPrice = double.tryParse(v) ?? 0),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                decoration: const InputDecoration(labelText: 'Min seats'),
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => _minSeats = int.tryParse(v) ?? 0),
              ),
            ),
            FilterChip(
              label: const Text('Free cancel'),
              selected: _freeCancelOnly,
              onSelected: (v) => setState(() => _freeCancelOnly = v),
            ),
            FilterChip(
              label: const Text('Unlimited mileage'),
              selected: _unlimitedOnly,
              onSelected: (v) => setState(() => _unlimitedOnly = v),
            ),
            FilterChip(
              label: const Text('Saved only'),
              selected: _savedOnly,
              onSelected: (v) => setState(() => _savedOnly = v),
            ),
            FilterChip(
              label: const Text('One-way only'),
              selected: _oneWayOnly,
              onSelected: (v) => setState(() => _oneWayOnly = v),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _transmissionFilter = '';
                  _fuelFilter = '';
                  _maxPrice = 0;
                  _minSeats = 0;
                  _freeCancelOnly = false;
                  _unlimitedOnly = false;
                  _savedOnly = false;
                  _oneWayOnly = false;
                  _classFilter = '';
                  _sort = 'price_asc';
                });
              },
              child: const Text('Reset filters'),
            )
          ]),
          if (_carsOut.isNotEmpty) ...[
            const SizedBox(height: 8),
            StatusBanner.error(_carsOut, dense: true),
          ],
        ],
      ),
    );

    List<Map<String, dynamic>> _filteredCars() {
      final list = _cars.cast<Map<String, dynamic>>();
      final filtered = list.where((c) {
        final cls = (c['class'] ?? c['category'] ?? '').toString().toLowerCase();
        final cid = c['id'] is int ? c['id'] as int : int.tryParse((c['id'] ?? '').toString()) ?? -1;
        if (_transmissionFilter.isNotEmpty &&
            (c['transmission'] ?? '').toString().toLowerCase() != _transmissionFilter) {
          return false;
        }
        if (_fuelFilter.isNotEmpty &&
            (c['fuel'] ?? '').toString().toLowerCase() != _fuelFilter) {
          return false;
        }
        if (_classFilter.isNotEmpty && cls != _classFilter) return false;
        if (_savedOnly && (cid == -1 || !_saved.contains(cid))) return false;
        final price = (c['price_per_day_cents'] ?? 0) is num ? (c['price_per_day_cents'] as num) / 100 : 0;
        if (_maxPrice > 0 && price > _maxPrice) return false;
        if (_minSeats > 0) {
          final s = (c['seats'] ?? 0);
          final seats = s is num ? s.toInt() : int.tryParse(s.toString()) ?? 0;
          if (seats < _minSeats) return false;
        }
        if (_freeCancelOnly && (c['free_cancel'] ?? false) != true) return false;
        if (_unlimitedOnly && (c['unlimited_mileage'] ?? false) != true) return false;
        final pickup = (c['city'] ?? '').toString();
        final drop = (c['dropoff_city'] ?? '').toString();
        if (_oneWayOnly) {
          if (drop.isEmpty || drop.toLowerCase() == pickup.toLowerCase()) return false;
        }
        return true;
      }).toList();
      filtered.sort((a, b) {
        final pa = (a['price_per_day_cents'] ?? 0) as num? ?? 0;
        final pb = (b['price_per_day_cents'] ?? 0) as num? ?? 0;
        if (_sort == 'price_desc') return pb.compareTo(pa);
        if (_sort == 'newest') {
          final ia = (a['id'] ?? 0) as int? ?? 0;
          final ib = (b['id'] ?? 0) as int? ?? 0;
          return ib.compareTo(ia);
        }
        if (_sort == 'rating') {
          final ra = (a['rating'] ?? 0) as num? ?? 0;
          final rb = (b['rating'] ?? 0) as num? ?? 0;
          return rb.compareTo(ra);
        }
        return pa.compareTo(pb);
      });
      return filtered;
    }

    Widget carCard(Map<String, dynamic> car) {
      final name = (car['name'] ?? car['model'] ?? 'Car').toString();
      final city = (car['city'] ?? '').toString();
      final drop = (car['dropoff_city'] ?? '').toString();
      final price = ((car['price_per_day_cents'] ?? 0) as num) / 100;
      final currency = (car['currency'] ?? '').toString();
      final seats = (car['seats'] ?? '').toString();
      final trans = (car['transmission'] ?? '').toString();
      final fuel = (car['fuel'] ?? '').toString();
      final rating = (car['rating'] ?? 0).toString();
      final trips = (car['trips'] ?? '').toString();
      final img = (car['image_url'] ?? '').toString();
      final id = (car['id'] ?? '').toString();
      final cid = int.tryParse(id) ?? -1;
      final saved = cid != -1 && _saved.contains(cid);
      final unlimited = (car['unlimited_mileage'] ?? false) == true;
      final cls = (car['car_class'] ?? '').toString();
      final isOneWay = drop.isNotEmpty && drop.toLowerCase() != city.toLowerCase();
      return GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 140,
                width: double.infinity,
                color: Colors.black12,
                child: img.isEmpty
                    ? const Icon(Icons.directions_car, size: 48)
                    : Image.network(img, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
              ),
            ),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(city, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7))),
            if (drop.isNotEmpty && drop.toLowerCase() != city.toLowerCase())
              Text('Drop-off: $drop',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (rating != '0') Chip(label: Text('★ $rating'), visualDensity: VisualDensity.compact),
                if (trips.isNotEmpty) Chip(label: Text('$trips trips'), visualDensity: VisualDensity.compact),
                if (cls.isNotEmpty) Chip(label: Text(cls), visualDensity: VisualDensity.compact),
                if (isOneWay) Chip(label: const Text('One-way'), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (seats.isNotEmpty) Chip(label: Text('$seats seats'), visualDensity: VisualDensity.compact),
              if (trans.isNotEmpty) Chip(label: Text(trans), visualDensity: VisualDensity.compact),
              if (fuel.isNotEmpty) Chip(label: Text(fuel), visualDensity: VisualDensity.compact),
              if ((car['free_cancel'] ?? false) == true)
                Chip(
                  label: const Text('Free cancel'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Tokens.colorAgricultureLivestock.withValues(alpha: .1),
                ),
              if (unlimited)
                Chip(
                  label: const Text('Unlimited mileage'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Tokens.colorCourierTransport.withValues(alpha: .12),
                ),
            ]),
            const Spacer(),
              Text('$price $currency / day', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_durationDays > 0)
                Text('Est. total ${(_durationDays * price).toStringAsFixed(2)} $currency',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7))),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: cid == -1 ? null : () => _toggleSaved(cid),
                  icon: Icon(saved ? Icons.favorite : Icons.favorite_border,
                      color: saved ? Colors.red : Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)),
                  tooltip: saved ? 'Saved' : 'Save',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: WaterButton(
                    label: 'Quote',
                    onTap: () {
                      _quoteCar(id);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WaterButton(
                    label: 'Book',
                    tint: const Color(0xFFDAA520),
                    onTap: () {
                      _bookCar(car);
                    },
                  ),
                ),
              ],
            )
          ],
        ),
      );
    }

    final filtered = _filteredCars();
    num avgPrice = 0;
    num best = 0;
    num worst = 0;
    if (filtered.isNotEmpty) {
      final totals = filtered.map((c) => ((c['price_per_day_cents'] ?? 0) as num? ?? 0)).toList();
      avgPrice = totals.reduce((a, b) => a + b) / filtered.length / 100;
      totals.sort();
      worst = totals.last / 100;
      best = totals.first / 100;
    }

    final results = filtered.isEmpty
        ? GlassPanel(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.search_off),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'No cars match your filters. Try broadening pickup/drop-off, dates, or price.')),
                ],
              ),
            ),
          )
        : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.9,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (_, idx) {
              final car = filtered[idx];
              return carCard(car);
            },
          );

    final bookingsSection = GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text('Found: ${filtered.length}'),
                  avatar: const Icon(Icons.directions_car, size: 18),
                ),
                Chip(
                  label: Text('Avg: ${avgPrice.toStringAsFixed(2)}'),
                  avatar: const Icon(Icons.attach_money, size: 18),
                ),
                if (filtered.isNotEmpty)
                  Chip(
                    label: Text('Best: ${best.toStringAsFixed(2)}'),
                    avatar: const Icon(Icons.trending_down, size: 18),
                  ),
                if (filtered.isNotEmpty)
                  Chip(
                    label: Text('Highest: ${worst.toStringAsFixed(2)}'),
                    avatar: const Icon(Icons.trending_up, size: 18),
                  ),
                if (filtered.isNotEmpty)
                  ...filtered
                      .map((c) => (c['car_class'] ?? '').toString())
                      .where((c) => c.isNotEmpty)
                      .fold<Map<String, int>>({}, (map, cls) {
                        map[cls] = (map[cls] ?? 0) + 1;
                        return map;
                      })
                      .entries
                      .take(3)
                      .map((e) => Chip(
                            label: Text('${e.key}: ${e.value}'),
                            avatar: const Icon(Icons.category, size: 16),
                          )),
              ],
            ),
          const SizedBox(height: 8),
         Row(
            children: [
              Text('Bookings', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(onPressed: _loadBookings, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(
                label: Text('Total: ${_bookings.length}'),
                avatar: const Icon(Icons.list_alt, size: 18),
              ),
              Chip(
                label: Text('Pending: ${_bookings.where((b) => (b['status'] ?? '') == 'pending').length}'),
                avatar: const Icon(Icons.timer, size: 18),
              ),
              Chip(
                label: Text('Confirmed: ${_bookings.where((b) => (b['status'] ?? '') == 'confirmed').length}'),
                avatar: const Icon(Icons.check_circle, size: 18),
              ),
            ],
          ),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _bookingStatusFilter.isEmpty,
              onSelected: (_) {
                setState(() => _bookingStatusFilter = '');
                _loadBookings();
              },
            ),
            ChoiceChip(
              label: const Text('Pending'),
              selected: _bookingStatusFilter == 'pending',
              onSelected: (_) {
                setState(() => _bookingStatusFilter = 'pending');
                _loadBookings();
              },
            ),
            ChoiceChip(
              label: const Text('Confirmed'),
              selected: _bookingStatusFilter == 'confirmed',
              onSelected: (_) {
                setState(() => _bookingStatusFilter = 'confirmed');
                _loadBookings();
              },
            ),
          ]),
          if (_bookingsLoading) const LinearProgressIndicator(minHeight: 2),
          if (_bookingsOut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_bookingsOut,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _bookings.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, idx) {
              final b = _bookings[idx] as Map<String, dynamic>? ?? {};
              final id = (b['id'] ?? '').toString();
              final status = (b['status'] ?? '').toString();
              final fromIso = (b['from_iso'] ?? '').toString();
              final toIso = (b['to_iso'] ?? '').toString();
              int days = 0;
              try {
                final f = DateTime.tryParse(fromIso);
                final t = DateTime.tryParse(toIso);
                if (f != null && t != null) {
                  days = t.difference(f).inDays;
                  if (days <= 0) days = 1;
                }
              } catch (_) {}
              return ListTile(
                title: Text('Booking #$id — ${(b['car_name'] ?? '').toString()}'),
                subtitle: Text(
                    '${(b['renter_name'] ?? '').toString()} • ${(b['renter_phone'] ?? '').toString()}\n$fromIso → $toIso (${days > 0 ? "$days d" : ""})\n$status'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                        onPressed: () => _opConfirm(id),
                        icon: const Icon(Icons.check_circle, color: Colors.green)),
                    IconButton(
                        onPressed: () => _opCancel(id),
                        icon: const Icon(Icons.cancel, color: Colors.red)),
                  ],
                ),
              );
            },
          )
        ],
      ),
    );

    final content = ListView(
      padding: const EdgeInsets.all(16),
      controller: _scroll,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Chip(
              label: Text('Saved: ${_saved.length}'),
              avatar: const Icon(Icons.favorite, size: 16),
            ),
            if (_savedOnly)
              Chip(
                label: const Text('Saved filter on'),
                avatar: const Icon(Icons.filter_alt, size: 16),
              ),
            if (_saved.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear saved'),
                onPressed: () {
                  setState(() => _saved.clear());
                  _persistSaved();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (cityCtrl.text.isNotEmpty)
              Chip(
                label: Text('Pickup: ${cityCtrl.text}'),
                avatar: const Icon(Icons.location_on, size: 16),
              ),
            if (dropoffCtrl.text.isNotEmpty)
              Chip(
                label: Text('Drop-off: ${dropoffCtrl.text}'),
                avatar: const Icon(Icons.flag_outlined, size: 16),
              ),
            if (fromCtrl.text.isNotEmpty && toCtrl.text.isNotEmpty)
              Chip(
                label: Text('Dates: ${fromCtrl.text} → ${toCtrl.text} (${_durationDays}d)'),
                avatar: const Icon(Icons.calendar_month, size: 16),
              ),
          ],
        ),
        const SizedBox(height: 12),
        hero,
        const SizedBox(height: 16),
        results,
        const SizedBox(height: 16),
        bookingsSection,
        if (_saved.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Saved cars', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.9,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (_, idx) {
              final car = filtered[idx];
              final cid = car['id'] is int
                  ? car['id'] as int
                  : int.tryParse((car['id'] ?? '').toString()) ?? -1;
              if (!_saved.contains(cid)) return const SizedBox.shrink();
              return carCard(car);
            },
          ),
        ],
      ],
    );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l.carrentalTitle),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(onPressed: _loadCars, icon: const Icon(Icons.search)),
        ],
      ),
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(child: SafeArea(child: content)),
          if (_showScrollTop)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'cr-top',
                onPressed: () => _scroll.animateTo(0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut),
                child: const Icon(Icons.arrow_upward),
              ),
            ),
        ],
      ),
    );
  }
}
