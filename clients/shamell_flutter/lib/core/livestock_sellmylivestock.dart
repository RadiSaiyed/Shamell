import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import 'design_tokens.dart';
import 'glass.dart';
import '../main.dart' show AppBG;

Future<Map<String, String>> _hdrLivestock({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class LivestockMarketplacePage extends StatefulWidget {
  final String baseUrl;
  const LivestockMarketplacePage({super.key, required this.baseUrl});

  @override
  State<LivestockMarketplacePage> createState() => _LivestockMarketplacePageState();
}

class _LivestockMarketplacePageState extends State<LivestockMarketplacePage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  String _error = '';
  List<dynamic> _listings = [];
  Set<int> _watchlist = {};
  Map<String, int> _speciesCounts = {};
  Map<String, int> _cityCounts = {};
  num _avgPrice = 0;
  int _offset = 0;
  final int _pageSize = 60;
  bool _hasMore = false;
  bool _appending = false;
  late final ScrollController _scroll;
  final Map<int, Map<String, dynamic>> _watchCache = {};
  bool _refreshingSaved = false;
  bool _showScrollTop = false;
  bool _negotiableOnly = false;

  // Filters
  final TextEditingController _search = TextEditingController();
  String _species = '';
  String _status = 'available';
  double _minPrice = 0;
  double _maxPrice = 0;
  bool _hasMax = false;
  double _minWeight = 0;
  double _maxWeight = 0;
  String _sort = 'newest'; // newest | price_asc | price_desc
  String _sex = ''; // male | female | mixed
  String _city = '';

  // Create listing
  final _createTitle = TextEditingController();
  final _createPrice = TextEditingController();
  final _createCity = TextEditingController();
  final _createSpecies = TextEditingController();
  final _createBreed = TextEditingController();
  final _createWeight = TextEditingController();
  final _createFarm = TextEditingController();
  final _createPhone = TextEditingController();
  String _createStatus = 'available';
  bool _createBusy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _scroll = ScrollController()..addListener(_onScroll);
    _loadWatchlist().then((_) => _loadListings());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tab.dispose();
    _search.dispose();
    _createTitle.dispose();
    _createPrice.dispose();
    _createCity.dispose();
    _createSpecies.dispose();
    _createBreed.dispose();
    _createWeight.dispose();
    _createFarm.dispose();
    _createPhone.dispose();
    super.dispose();
  }

  String get _base => widget.baseUrl.trim();

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
      if (_hasMore && !_appending && !_loading) {
        _loadListings(append: true);
      }
    }
    final show = _scroll.position.pixels > 400;
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }
  }
  Future<void> _loadWatchlist() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList('livestock_watchlist') ?? const [];
    final cacheRaw = sp.getString('livestock_watch_cache');
    if (cacheRaw != null && cacheRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(cacheRaw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final id = int.tryParse(k);
          if (id != null && v is Map<String, dynamic>) {
            _watchCache[id] = v;
          }
        });
      } catch (_) {}
    }
    setState(() {
      _watchlist = raw.map((e) => int.tryParse(e)).whereType<int>().toSet();
    });
  }

  Future<void> _persistWatchlist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('livestock_watchlist', _watchlist.map((e) => e.toString()).toList());
    final cacheJson = jsonEncode(_watchCache.map((k, v) => MapEntry(k.toString(), v)));
    await sp.setString('livestock_watch_cache', cacheJson);
  }

  void _toggleWatch(int id, [Map<String, dynamic>? snapshot]) {
    setState(() {
      if (_watchlist.contains(id)) {
        _watchlist.remove(id);
        _watchCache.remove(id);
      } else {
        _watchlist.add(id);
        if (snapshot != null) {
          _watchCache[id] = snapshot;
        }
      }
    });
    _persistWatchlist();
  }

  Future<void> _callSeller(dynamic phone) async {
    final p = (phone ?? '').toString().trim();
    if (p.isEmpty) return;
    final uri = Uri.parse('tel:$p');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _refreshSaved() async {
    if (_watchlist.isEmpty) return;
    setState(() => _refreshingSaved = true);
    try {
      for (final id in _watchlist) {
        try {
          final uri = Uri.parse('$_base/livestock/listings/$id');
          final r = await http.get(uri, headers: await _hdrLivestock());
          if (r.statusCode == 200) {
            final j = jsonDecode(r.body);
            if (j is Map<String, dynamic>) {
              _watchCache[id] = j;
            }
          }
        } catch (_) {
          // ignore per-item errors
        }
      }
      _persistWatchlist();
      setState(() {});
    } finally {
      if (mounted) setState(() => _refreshingSaved = false);
    }
  }

  Future<void> _exportSavedCsv(List<dynamic> savedListings) async {
    if (savedListings.isEmpty) return;
    final buf = StringBuffer();
    buf.writeln('id,title,price_cents,currency,city,status');
    for (final e in savedListings) {
      final id = e['id'] ?? '';
      final title = (e['title'] ?? '').toString().replaceAll(',', ' ');
      final price = e['price_cents'] ?? '';
      final cur = e['currency'] ?? '';
      final city = e['city'] ?? '';
      final st = e['status'] ?? '';
      buf.writeln('$id,$title,$price,$cur,$city,$st');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    // ignore errors silently; UI is best-effort
  }

  Future<void> _loadListings({bool append = false}) async {
    setState(() {
      _loading = !append;
      _appending = append;
      _error = '';
    });
    try {
      if (!append) {
        _offset = 0;
      }
      final params = {
        'limit': '$_pageSize',
        if (append) 'offset': '${_offset}',
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
        if (_species.isNotEmpty) 'species': _species,
        if (_status.isNotEmpty) 'status': _status,
        if (_minPrice > 0) 'min_price': _minPrice.round().toString(),
        if (_hasMax && _maxPrice > 0) 'max_price': _maxPrice.round().toString(),
        if (_minWeight > 0) 'min_weight': _minWeight,
        if (_maxWeight > 0) 'max_weight': _maxWeight,
        if (_negotiableOnly) 'negotiable': true,
        if (_sort == 'price_asc') 'order': 'asc',
        if (_sort == 'price_desc') 'order': 'desc',
        if (_sex.isNotEmpty) 'sex': _sex,
        if (_city.isNotEmpty) 'city': _city,
      };
      final uri = Uri.parse('$_base/livestock/listings').replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdrLivestock());
      if (r.statusCode != 200) {
        setState(() => _error = '${r.statusCode}: ${r.body}');
      } else {
        final j = jsonDecode(r.body);
        if (j is List) {
          final counts = <String, int>{};
          final cityCounts = <String, int>{};
          for (final e in j) {
            final sp = (e['species'] ?? '').toString();
            if (sp.isNotEmpty) counts[sp] = (counts[sp] ?? 0) + 1;
            final ct = (e['city'] ?? '').toString();
            if (ct.isNotEmpty) cityCounts[ct] = (cityCounts[ct] ?? 0) + 1;
          }
          setState(() {
            if (append) {
              _listings = [..._listings, ...j];
              _offset = _listings.length;
              for (final e in j) {
                final id = e['id'];
                if (id is int && _watchlist.contains(id)) {
                  _watchCache[id] = Map<String, dynamic>.from(e);
                }
              }
            } else {
              _listings = j;
              _offset = j.length;
              for (final e in j) {
                final id = e['id'];
                if (id is int && _watchlist.contains(id)) {
                  _watchCache[id] = Map<String, dynamic>.from(e);
                }
              }
            }
            _hasMore = j.length >= _pageSize;
            _speciesCounts = counts;
            _cityCounts = cityCounts;
            final combinedPrice = _listings.fold<num>(
                0, (sum, e) => sum + ((e['price_cents'] ?? 0) as num? ?? 0));
            _avgPrice =
                _listings.isEmpty ? 0 : (combinedPrice / _listings.length / 100);
          });
        }
      }
    } catch (e) {
      setState(() => _error = 'error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _appending = false;
        });
      }
    }
  }

  Future<void> _createListing() async {
    final title = _createTitle.text.trim();
    final price = int.tryParse(_createPrice.text.trim());
    if (title.isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and price are required')));
      return;
    }
    setState(() => _createBusy = true);
    try {
      final body = {
        'title': title,
        'price_cents': price,
        'city': _createCity.text.trim(),
        'species': _createSpecies.text.trim(),
        'breed': _createBreed.text.trim(),
        'weight_kg': double.tryParse(_createWeight.text.trim()),
        'farm_name': _createFarm.text.trim(),
        'seller_phone': _createPhone.text.trim(),
        'status': _createStatus,
      };
      final uri = Uri.parse('$_base/livestock/listings');
      final r = await http.post(uri, headers: await _hdrLivestock(json: true), body: jsonEncode(body));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _createTitle.clear();
        _createPrice.clear();
        _createCity.clear();
        _createSpecies.clear();
        _createBreed.clear();
        _createWeight.clear();
        _createFarm.clear();
        _createPhone.clear();
        await _loadListings();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listing created')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create failed: ${r.statusCode} ${r.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create failed: $e')));
    } finally {
      if (mounted) setState(() => _createBusy = false);
    }
  }

  Future<void> _updateListing(int id, Map<String, dynamic> patch) async {
    try {
      final uri = Uri.parse('$_base/livestock/listings/$id');
      final r = await http.patch(uri, headers: await _hdrLivestock(json: true), body: jsonEncode(patch));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _loadListings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: ${r.statusCode} ${r.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _createOffer(int id) async {
    final price = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OfferSheet(baseUrl: _base, listingId: id),
    );
    if (price != null) {
      await _loadListings();
    }
  }

  String _formatPrice(dynamic p, dynamic currency) {
    if (p == null) return '—';
    final num priceNum = p is num ? p : num.tryParse(p.toString()) ?? 0;
    final c = (currency ?? 'SYP').toString();
    return '${(priceNum / 100).toStringAsFixed(2)} $c';
  }

  Widget _buildFilters() {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Marketplace', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search breed, lot or city',
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadListings,
              ),
            ),
            onSubmitted: (_) => _loadListings(),
          ),
        const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sp in ['cattle', 'sheep', 'goat', 'poultry', 'camel'])
                ChoiceChip(
                  label: Text(sp.toUpperCase()),
                  selected: _species == sp,
                  onSelected: (_) {
                    setState(() => _species = _species == sp ? '' : sp);
                    _loadListings();
                  },
                ),
              for (final st in ['available', 'pending', 'sold'])
                ChoiceChip(
                  label: Text(st),
                  selected: _status == st,
                  onSelected: (_) {
                    setState(() => _status = st);
                    _loadListings();
                  },
                ),
              ChoiceChip(
                label: const Text('All statuses'),
                selected: _status.isEmpty,
                onSelected: (_) {
                  setState(() => _status = '');
                  _loadListings();
                },
              ),
              for (final sx in ['male', 'female', 'mixed'])
                ChoiceChip(
                  label: Text(sx[0].toUpperCase() + sx.substring(1)),
                  selected: _sex == sx,
                  onSelected: (_) {
                    setState(() => _sex = _sex == sx ? '' : sx);
                    _loadListings();
                  },
                ),
              ChoiceChip(
                label: const Text('Newest'),
                selected: _sort == 'newest',
                onSelected: (_) {
                  setState(() => _sort = 'newest');
                  _loadListings();
                },
              ),
              ChoiceChip(
                label: const Text('Price ↑'),
                selected: _sort == 'price_asc',
                onSelected: (_) {
                  setState(() => _sort = 'price_asc');
                  _loadListings();
                },
              ),
              ChoiceChip(
                label: const Text('Price ↓'),
                selected: _sort == 'price_desc',
                onSelected: (_) {
                  setState(() => _sort = 'price_desc');
                  _loadListings();
                },
              ),
              FilterChip(
                label: const Text('Negotiable only'),
                selected: _negotiableOnly,
                onSelected: (v) {
                  setState(() => _negotiableOnly = v);
                },
              ),
            ],
          ),
          if (_cityCounts.isNotEmpty) const SizedBox(height: 8),
          if (_cityCounts.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_cityCounts.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .take(6)
                  .map((e) => ChoiceChip(
                        label: Text('${e.key} (${e.value})'),
                        selected: _city == e.key,
                        onSelected: (_) {
                          setState(() => _city = _city == e.key ? '' : e.key);
                          _loadListings();
                        },
                      ))
                  .toList(),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Min price (cents)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = double.tryParse(v) ?? 0;
                    setState(() => _minPrice = n);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Max price (cents, optional)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = double.tryParse(v) ?? 0;
                    setState(() {
                      _maxPrice = n;
                      _hasMax = v.trim().isNotEmpty;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Min weight (kg)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _minWeight = double.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Max weight (kg)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _maxWeight = double.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _loadListings,
                icon: const Icon(Icons.tune),
                label: const Text('Apply'),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _search.clear();
                    _species = '';
            _status = 'available';
                    _minPrice = 0;
                    _maxPrice = 0;
                    _hasMax = false;
                    _minWeight = 0;
                    _maxWeight = 0;
                    _sort = 'newest';
                    _sex = '';
                    _city = '';
                  });
                  _loadListings();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard(dynamic item) {
    final photos = (item['photos'] is List) ? (item['photos'] as List).cast() : <dynamic>[];
    final cover = photos.isNotEmpty ? photos.first.toString() : '';
    final tags = (item['tags'] is List) ? (item['tags'] as List).cast<String>() : <String>[];
    final weight = item['weight_kg'];
    final lot = item['lot_size'];
    final negotiable = (item['negotiable'] == true);
    final grade = item['quality_grade'];
    final health = item['health_status'];
    final watched = _watchlist.contains(item['id']);
    final priceCents = (item['price_cents'] ?? 0) is num ? item['price_cents'] as num : num.tryParse(item['price_cents'].toString()) ?? 0;
    final fmt = NumberFormat.decimalPattern();
    String pricePerKg = '';
    if (weight != null && (weight is num) && weight > 0) {
      pricePerKg = '${(priceCents / weight / 100).toStringAsFixed(2)} per kg';
    }
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 88,
                  height: 72,
                  color: Colors.black12,
                  child: cover.isEmpty
                      ? const Icon(Icons.photo_outlined, size: 28)
                      : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(item['title'] ?? 'Listing', style: const TextStyle(fontWeight: FontWeight.w700))),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _toggleWatch(item['id'] as int, item is Map<String, dynamic> ? item : null),
                          icon: Icon(
                            watched ? Icons.bookmark : Icons.bookmark_border,
                            color: watched ? Tokens.colorAgricultureLivestock : null,
                          ),
                          tooltip: watched ? 'Saved' : 'Save',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (item['species'] != null)
                          _chip(item['species'].toString().toUpperCase(), Tokens.colorAgricultureLivestock),
                        if (item['breed'] != null) _chip(item['breed'], Colors.blueGrey),
                        _chip(item['status'] ?? 'available', item['status'] == 'sold' ? Colors.red : Colors.green),
                        if (grade != null) _chip('Grade ${grade.toString()}', Colors.deepPurple),
                        if (health != null) _chip(health.toString(), Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatPrice(item['price_cents'], item['currency'])} • ${(item['city'] ?? '').toString()}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7)),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      children: [
                        if (weight != null) Text('Weight: $weight kg'),
                        if (lot != null) Text('Lot: $lot head'),
                        if (lot != null && weight != null && weight is num && lot is num && lot > 0)
                          Text('Avg/head: ${fmt.format(weight / lot)} kg'),
                        Text(negotiable ? 'Negotiable' : 'Fixed price'),
                        if (pricePerKg.isNotEmpty) Text(pricePerKg),
                      ],
                    ),
                    if ((item['description'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          item['description'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ElevatedButton(
                          onPressed: () => _showListingDetail(item),
                          child: const Text('View listing'),
                        ),
                        OutlinedButton(
                          onPressed: () => _createOffer(item['id'] as int),
                          child: const Text('Make offer'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _callSeller(item['seller_phone']),
                          icon: const Icon(Icons.call),
                          label: const Text('Call seller'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _updateListing(item['id'] as int, {'negotiable': !negotiable}),
                          icon: Icon(negotiable ? Icons.lock_open : Icons.lock_outline),
                          label: Text(negotiable ? 'Mark fixed' : 'Mark negotiable'),
                        ),
                        if (tags.isNotEmpty)
                          Wrap(
                            spacing: 4,
                            children: tags.map((t) => Chip(label: Text(t))).toList(),
                          ),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onDelete) {
    return InputChip(
      label: Text(label),
      onDeleted: onDelete,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }

  Widget _chip(String text, Color c) {
    return Chip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      label: Text(text),
      backgroundColor:
          Theme.of(context).colorScheme.surface.withValues(alpha: .22),
      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
    );
  }

  Future<void> _showListingDetail(dynamic item) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (context, controller) {
          final photos = (item['photos'] is List) ? (item['photos'] as List).cast() : <dynamic>[];
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: controller,
              children: [
                Text(item['title'] ?? 'Listing', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(_formatPrice(item['price_cents'], item['currency']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (item['species'] != null) _chip(item['species'], Tokens.colorAgricultureLivestock),
                    if (item['breed'] != null) _chip(item['breed'], Colors.blueGrey),
                    if (item['city'] != null) _chip(item['city'], Colors.orange),
                    _chip(item['status'] ?? 'available', Colors.green),
                    _chip((item['negotiable'] == true) ? 'Negotiable' : 'Fixed', Colors.teal),
                    if (item['quality_grade'] != null) _chip('Grade ${item['quality_grade']}', Colors.deepPurple),
                    if (item['health_status'] != null) _chip(item['health_status'], Colors.teal),
                    if (item['sex'] != null) _chip(item['sex'], Colors.blue),
                  ],
                ),
                const SizedBox(height: 12),
                if (photos.isNotEmpty)
                  SizedBox(
                    height: 160,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          photos[i].toString(),
                          width: 200,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 200,
                            height: 160,
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if ((item['description'] ?? '').toString().isNotEmpty)
                  Text(item['description'], style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                Text('Contact: ${(item['seller_phone'] ?? '—').toString()} • Farm: ${(item['farm_name'] ?? '—').toString()}'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _createOffer(item['id'] as int),
                  icon: const Icon(Icons.local_offer_outlined),
                  label: const Text('Make offer'),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarketplace() {
    final visibleListings = _listings.where((e) {
      if (_negotiableOnly && e['negotiable'] != true) return false;
      return true;
    }).toList();
    final total = visibleListings.length;
    final saved = _watchlist.length;
    final statuses = <String, int>{};
    for (final e in visibleListings) {
      final st = (e['status'] ?? 'available').toString();
      statuses[st] = (statuses[st] ?? 0) + 1;
    }
    final active = <Widget>[];
    if (_search.text.trim().isNotEmpty) {
      active.add(_filterChip('Search: ${_search.text.trim()}', () {
        _search.clear();
        _loadListings();
      }));
    }
    if (_species.isNotEmpty) active.add(_filterChip('Species: ${_species.toUpperCase()}', () { setState(() => _species = ''); _loadListings(); }));
    if (_status.isNotEmpty) active.add(_filterChip('Status: $_status', () { setState(() => _status = ''); _loadListings(); }));
    if (_sex.isNotEmpty) active.add(_filterChip('Sex: $_sex', () { setState(() => _sex = ''); _loadListings(); }));
    if (_city.isNotEmpty) active.add(_filterChip('City: $_city', () { setState(() => _city = ''); _loadListings(); }));
    if (_minPrice > 0 || (_hasMax && _maxPrice > 0)) {
      active.add(_filterChip('Price ${_minPrice > 0 ? "≥ ${_minPrice.toInt()}" : ""} ${_hasMax && _maxPrice > 0 ? "≤ ${_maxPrice.toInt()}" : ""}', () {
        setState(() { _minPrice = 0; _maxPrice = 0; _hasMax = false; }); _loadListings();
      }));
    }
    if (_minWeight > 0 || _maxWeight > 0) {
      active.add(_filterChip('Weight ${_minWeight > 0 ? "≥ ${_minWeight.toInt()}kg" : ""} ${_maxWeight > 0 ? "≤ ${_maxWeight.toInt()}kg" : ""}', () {
        setState(() { _minWeight = 0; _maxWeight = 0; }); _loadListings();
      }));
    }

    final list = RefreshIndicator(
      onRefresh: () => _loadListings(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        controller: _scroll,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text('Listings: $total'),
                avatar: const Icon(Icons.list_alt, size: 18),
              ),
              Chip(
                label: Text('Avg price: ${_avgPrice.toStringAsFixed(2)}'),
                avatar: const Icon(Icons.bar_chart, size: 18),
              ),
              Chip(
                label: Text('Saved: $saved'),
                avatar: const Icon(Icons.bookmark, size: 18),
              ),
              if (_speciesCounts.isNotEmpty)
                Chip(
                  label: Text(
                    _speciesCounts.entries
                        .map((e) => '${e.key.toUpperCase()}:${e.value}')
                        .take(4)
                        .join('  '),
                  ),
                  avatar: const Icon(Icons.pie_chart_outline, size: 18),
                ),
              if (_speciesCounts.isNotEmpty)
                Chip(
                  label: Text(
                    'Top: ${(_speciesCounts.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .first.key.toUpperCase()}',
                  ),
                  avatar: const Icon(Icons.star, size: 18),
                ),
              if (_cityCounts.isNotEmpty)
                Chip(
                  label: Text(
                    (_cityCounts.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .take(3)
                        .map((e) => '${e.key}:${e.value}')
                        .join('  '),
                  ),
                  avatar: const Icon(Icons.location_on_outlined, size: 18),
                ),
              if (statuses.isNotEmpty)
                Chip(
                  label: Text(
                    statuses.entries
                        .map((e) => '${e.key}:${e.value}')
                        .take(3)
                        .join('  '),
                  ),
                  avatar: const Icon(Icons.layers_outlined, size: 18),
                ),
            ],
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: active),
          ],
          const SizedBox(height: 8),
          _buildFilters(),
          const SizedBox(height: 12),
          if (_error.isNotEmpty) Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
          if (!_loading && visibleListings.isEmpty)
            const Center(child: Text('No livestock listed yet')),
          ...visibleListings.map(_buildCard),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _appending
                    ? const CircularProgressIndicator()
                    : OutlinedButton.icon(
                        onPressed: () => _loadListings(append: true),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more'),
                      ),
              ),
            ),
        ],
      ),
    );

    return Stack(
      children: [
        list,
        if (_showScrollTop)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'livestock-top',
              onPressed: () => _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
              child: const Icon(Icons.arrow_upward),
            ),
          ),
      ],
    );
  }

  Widget _buildSaved() {
    final savedIds = _watchlist;
    final fromFeed = _listings.where((e) => savedIds.contains(e['id'])).toList();
    final cached = savedIds
        .where((id) => !fromFeed.any((e) => e['id'] == id))
        .map((id) {
          final snap = _watchCache[id];
          if (snap != null) {
            return {...snap, 'id': id};
          }
          return {'id': id, 'title': 'Saved listing #$id'};
        }).toList();
    final savedListings = [...fromFeed, ...cached];
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (savedListings.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text('No saved livestock yet. Tap the bookmark on any listing to save it.'),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshSaved,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text('Saved: ${savedListings.length}'),
                  avatar: const Icon(Icons.bookmark, size: 18),
                ),
                ActionChip(
                  avatar: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear saved'),
                  onPressed: () {
                    setState(() {
                      _watchlist.clear();
                      _watchCache.clear();
                    });
                    _persistWatchlist();
                  },
                ),
                ActionChip(
                  avatar: _refreshingSaved
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh saved'),
                  onPressed: _refreshingSaved ? null : _refreshSaved,
                ),
                ActionChip(
                  avatar: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy CSV'),
                  onPressed: () => _exportSavedCsv(savedListings),
                ),
                ActionChip(
                  avatar: const Icon(Icons.settings, size: 18),
                  label: Text(_negotiableOnly ? 'Negotiable on' : 'Negotiable off'),
                  onPressed: () {
                    setState(() {
                      _negotiableOnly = !_negotiableOnly;
                    });
                    _loadListings();
                  },
                ),
              ],
            ),
          const SizedBox(height: 12),
          ...savedListings.map(_buildCard),
        ],
      ),
    );
  }

  Widget _buildOperator() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create listing', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(controller: _createTitle, decoration: const InputDecoration(labelText: 'Title *')),
              TextField(controller: _createPrice, decoration: const InputDecoration(labelText: 'Price cents *'), keyboardType: TextInputType.number),
              TextField(controller: _createSpecies, decoration: const InputDecoration(labelText: 'Species (cattle/sheep/...)')),
              TextField(controller: _createBreed, decoration: const InputDecoration(labelText: 'Breed')),
              TextField(controller: _createWeight, decoration: const InputDecoration(labelText: 'Weight kg'), keyboardType: TextInputType.number),
              TextField(controller: _createCity, decoration: const InputDecoration(labelText: 'City')),
              TextField(controller: _createFarm, decoration: const InputDecoration(labelText: 'Farm name')),
              TextField(controller: _createPhone, decoration: const InputDecoration(labelText: 'Seller phone')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _createStatus,
                items: const [
                  DropdownMenuItem(value: 'available', child: Text('Available')),
                  DropdownMenuItem(value: 'pending', child: Text('Reserved')),
                  DropdownMenuItem(value: 'sold', child: Text('Sold')),
                ],
                onChanged: (v) => setState(() => _createStatus = v ?? 'available'),
                decoration: const InputDecoration(labelText: 'Status'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _createBusy ? null : _createListing,
                  icon: const Icon(Icons.add),
                  label: Text(_createBusy ? 'Saving...' : 'Publish listing'),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Manage listings', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._listings.map((item) => GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item['title'] ?? 'Listing', style: const TextStyle(fontWeight: FontWeight.w700))),
                      DropdownButton<String>(
                        value: item['status'] ?? 'available',
                        items: const [
                          DropdownMenuItem(value: 'available', child: Text('Available')),
                          DropdownMenuItem(value: 'pending', child: Text('Reserved')),
                          DropdownMenuItem(value: 'sold', child: Text('Sold')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _updateListing(item['id'] as int, {'status': v});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_formatPrice(item['price_cents'], item['currency'])),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(labelText: 'Update price (cents)'),
                          keyboardType: TextInputType.number,
                          onSubmitted: (v) {
                            final n = int.tryParse(v.trim());
                            if (n != null) _updateListing(item['id'] as int, {'price_cents': n});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _showOffers(item['id'] as int),
                        child: const Text('Offers'),
                      ),
                    ],
                  )
                ],
              ),
            )),
      ],
    );
  }

  Future<void> _showOffers(int listingId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OfferListSheet(baseUrl: _base, listingId: listingId),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Livestock Marketplace'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Marketplace'),
            Tab(text: 'Operator'),
            Tab(text: 'Saved'),
          ],
        ),
      ),
      body: Stack(
        children: [
          bg,
          TabBarView(
            controller: _tab,
            children: [
              _buildMarketplace(),
              _buildOperator(),
              _buildSaved(),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfferSheet extends StatefulWidget {
  final String baseUrl;
  final int listingId;
  const _OfferSheet({required this.baseUrl, required this.listingId});

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  final _price = TextEditingController();
  final _qty = TextEditingController();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _deliveryCity = TextEditingController();
  final _preferredDate = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _price.dispose();
    _qty.dispose();
    _phone.dispose();
    _name.dispose();
    _note.dispose();
    _deliveryCity.dispose();
    _preferredDate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = {
      'offer_price_cents': int.tryParse(_price.text.trim()),
      'quantity': int.tryParse(_qty.text.trim()),
      'buyer_phone': _phone.text.trim(),
      'buyer_name': _name.text.trim(),
      'note': _note.text.trim(),
      'delivery_city': _deliveryCity.text.trim(),
      'preferred_date': _preferredDate.text.trim(),
    };
    setState(() => _busy = true);
    try {
      final uri = Uri.parse('${widget.baseUrl}/livestock/listings/${widget.listingId}/offers');
      final r = await http.post(uri, headers: await _hdrLivestock(json: true), body: jsonEncode(body));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        if (mounted) Navigator.of(context).pop(1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Offer failed: ${r.statusCode} ${r.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Offer failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Make an offer', style: Theme.of(context).textTheme.titleMedium),
          TextField(controller: _price, decoration: const InputDecoration(labelText: 'Offer price (cents)'), keyboardType: TextInputType.number),
          TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Quantity / headcount'), keyboardType: TextInputType.number),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Your phone')),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name / company')),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 3),
          TextField(controller: _deliveryCity, decoration: const InputDecoration(labelText: 'Delivery city')),
          TextField(controller: _preferredDate, decoration: const InputDecoration(labelText: 'Preferred delivery date')),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.send),
            label: Text(_busy ? 'Sending...' : 'Submit offer'),
          ),
        ],
      ),
    );
  }
}

class _OfferListSheet extends StatefulWidget {
  final String baseUrl;
  final int listingId;
  const _OfferListSheet({required this.baseUrl, required this.listingId});

  @override
  State<_OfferListSheet> createState() => _OfferListSheetState();
}

class _OfferListSheetState extends State<_OfferListSheet> {
  bool _loading = true;
  String _error = '';
  List<dynamic> _offers = [];
  String _statusFilter = '';
  final TextEditingController _offerSearch = TextEditingController();
  String _offerSort = 'newest'; // newest, price_desc, price_asc

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/livestock/listings/${widget.listingId}/offers');
      final r = await http.get(uri, headers: await _hdrLivestock());
      if (r.statusCode != 200) {
        setState(() => _error = '${r.statusCode}: ${r.body}');
      } else {
        final j = jsonDecode(r.body);
        if (j is List) _offers = j;
      }
    } catch (e) {
      _error = 'error: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(int id, String status) async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/livestock/offers/$id');
      final r = await http.patch(uri, headers: await _hdrLivestock(json: true), body: jsonEncode({'status': status}));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: ${r.statusCode} ${r.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _copyOffersCsv(List<dynamic> items) async {
    if (items.isEmpty) return;
    final buf = StringBuffer();
    buf.writeln('id,buyer_name,buyer_phone,offer_price_cents,currency,quantity,status,delivery_city,preferred_date,note');
    for (final o in items) {
      buf.writeln('${o['id'] ?? ""},'
          '${(o['buyer_name'] ?? "").toString().replaceAll(",", " ")},'
          '${o['buyer_phone'] ?? ""},'
          '${o['offer_price_cents'] ?? ""},'
          '${o['currency'] ?? ""},'
          '${o['quantity'] ?? ""},'
          '${o['status'] ?? ""},'
          '${o['delivery_city'] ?? ""},'
          '${o['preferred_date'] ?? ""},'
          '${(o['note'] ?? "").toString().replaceAll(",", " ")}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
  }

  @override
  void dispose() {
    _offerSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusCounts = <String, int>{};
    for (final o in _offers) {
      final st = (o['status'] ?? 'open').toString();
      statusCounts[st] = (statusCounts[st] ?? 0) + 1;
    }
    Iterable<dynamic> visible = _statusFilter.isEmpty
        ? _offers
        : _offers.where((o) => (o['status'] ?? '').toString() == _statusFilter);
    final q = _offerSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      visible = visible.where((o) {
        final name = (o['buyer_name'] ?? '').toString().toLowerCase();
        final phone = (o['buyer_phone'] ?? '').toString().toLowerCase();
        final note = (o['note'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || note.contains(q);
      });
    }
    final visibleList = visible.toList();
    visibleList.sort((a, b) {
      if (_offerSort == 'price_desc') {
        final pa = (a['offer_price_cents'] ?? 0) as num? ?? 0;
        final pb = (b['offer_price_cents'] ?? 0) as num? ?? 0;
        return pb.compareTo(pa);
      }
      if (_offerSort == 'price_asc') {
        final pa = (a['offer_price_cents'] ?? 0) as num? ?? 0;
        final pb = (b['offer_price_cents'] ?? 0) as num? ?? 0;
        return pa.compareTo(pb);
      }
      final ia = (a['id'] ?? 0) as int? ?? 0;
      final ib = (b['id'] ?? 0) as int? ?? 0;
      return ib.compareTo(ia);
    });
    num totalValue = 0;
    num maxValue = 0;
    num minValue = visibleList.isEmpty ? 0 : double.maxFinite;
    for (final o in visibleList) {
      final v = o['offer_price_cents'];
      if (v is num) {
        totalValue += v;
        if (v > maxValue) maxValue = v;
        if (v < minValue) minValue = v;
      }
    }
    final avgValue = visibleList.isEmpty ? 0 : (totalValue / visibleList.length);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Offers', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _offerSearch,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search buyer / phone / note',
              suffixIcon: _offerSearch.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _offerSearch.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Newest'),
                selected: _offerSort == 'newest',
                onSelected: (_) => setState(() => _offerSort = 'newest'),
              ),
              ChoiceChip(
                label: const Text('Price ↓'),
                selected: _offerSort == 'price_desc',
                onSelected: (_) => setState(() => _offerSort = 'price_desc'),
              ),
              ChoiceChip(
                label: const Text('Price ↑'),
                selected: _offerSort == 'price_asc',
                onSelected: (_) => setState(() => _offerSort = 'price_asc'),
              ),
            ],
          ),
          if (_offers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text('Offers: ${visibleList.length}/${_offers.length}'),
                  avatar: const Icon(Icons.list_alt, size: 18),
                ),
                Chip(
                  label: Text('Sum: ${(totalValue / 100).toStringAsFixed(2)}'),
                  avatar: const Icon(Icons.attach_money, size: 18),
                ),
                if (visibleList.isNotEmpty)
                  Chip(
                    label: Text('Avg: ${(avgValue / 100).toStringAsFixed(2)}'),
                    avatar: const Icon(Icons.bar_chart, size: 18),
                  ),
                if (visibleList.isNotEmpty)
                  Chip(
                    label: Text('Best: ${(maxValue / 100).toStringAsFixed(2)}'),
                    avatar: const Icon(Icons.trending_up, size: 18),
                  ),
                if (visibleList.isNotEmpty)
                  Chip(
                    label: Text('Lowest: ${(minValue / 100).toStringAsFixed(2)}'),
                    avatar: const Icon(Icons.trending_down, size: 18),
                  ),
                ...statusCounts.entries.map(
                  (e) => Chip(
                    label: Text('${e.key}: ${e.value}'),
                    avatar: const Icon(Icons.layers, size: 16),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy CSV'),
                  onPressed: () => _copyOffersCsv(visibleList),
                ),
                ActionChip(
                  avatar: const Icon(Icons.filter_alt, size: 18),
                  label: Text(_statusFilter.isEmpty ? 'All statuses' : 'Filter: $_statusFilter'),
                  onPressed: () {
                    setState(() {
                      if (_statusFilter.isEmpty) {
                        _statusFilter = 'open';
                      } else if (_statusFilter == 'open') {
                        _statusFilter = 'accepted';
                      } else if (_statusFilter == 'accepted') {
                        _statusFilter = 'declined';
                      } else {
                        _statusFilter = '';
                      }
                    });
                  },
                ),
              ],
            ),
          ],
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error.isNotEmpty) Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!_loading)
            ...visibleList.map((o) => ListTile(
                  title: Row(
                    children: [
                      Expanded(child: Text('${o['buyer_name'] ?? 'Buyer'} • ${o['buyer_phone'] ?? ''}')),
                      Chip(
                        label: Text((o['status'] ?? 'open').toString()),
                        backgroundColor: _statusColor((o['status'] ?? '').toString()),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Offer: ${(o['offer_price_cents'] ?? 0) / 100} ${o['currency'] ?? ''} • qty: ${o['quantity'] ?? '—'}'),
                      if ((o['delivery_city'] ?? '').toString().isNotEmpty)
                        Text('Delivery: ${o['delivery_city']}'),
                      if ((o['preferred_date'] ?? '').toString().isNotEmpty)
                        Text('Preferred date: ${o['preferred_date']}'),
                      if ((o['note'] ?? '').toString().isNotEmpty) Text(o['note']),
                    ],
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Accept',
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _update(o['id'] as int, 'accepted'),
                      ),
                      IconButton(
                        tooltip: 'Decline',
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _update(o['id'] as int, 'declined'),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Colors.green.withValues(alpha: 0.15);
      case 'declined':
        return Colors.red.withValues(alpha: 0.15);
      default:
        return Colors.blue.withValues(alpha: 0.12);
    }
  }
}
