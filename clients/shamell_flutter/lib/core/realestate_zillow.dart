import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show AppBG;
import 'glass.dart';
import 'l10n.dart';

Future<Map<String, String>> _reHeaders({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class RealEstateEnduser extends StatefulWidget {
  final String baseUrl;
  const RealEstateEnduser({super.key, required this.baseUrl});

  @override
  State<RealEstateEnduser> createState() => _RealEstateEnduserState();
}

class _RealEstateEnduserState extends State<RealEstateEnduser> {
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final minpCtrl = TextEditingController();
  final maxpCtrl = TextEditingController();
  final minbCtrl = TextEditingController();
  final minBathCtrl = TextEditingController();
  final minAreaCtrl = TextEditingController();
  final inNameCtrl = TextEditingController();
  final inPhoneCtrl = TextEditingController();
  final inMsgCtrl = TextEditingController();
  final reserveWalletCtrl = TextEditingController();
  final reserveDepositCtrl = TextEditingController(text: '50000');
  final reservePropCtrl = TextEditingController();

  List<Map<String, dynamic>> _props = const [];
  bool _loading = false;
  String _status = '';
  String _actionOut = '';
  String _statusFilter = '';
  String _sort = 'newest'; // newest | price_desc | price_asc | area_desc | area_asc
  Set<int> _savedIds = {};
  String _viewMode = 'cards'; // cards | table
  bool _savedOnly = false;
  final List<int> _recentIds = [];

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'listed':
        return const Color(0xFF10B981);
      case 'reserved':
        return const Color(0xFFF59E0B);
      case 'sold':
        return const Color(0xFF6366F1);
      case 'rented':
        return const Color(0xFF0EA5E9);
      default:
        return Colors.grey;
    }
  }

  String _fmtNum(num v) {
    final s = v.round().toString();
    return s.replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'), (m) => ',');
  }

  @override
  void initState() {
    super.initState();
    _prefillWallet();
    _loadSaved();
    _load();
  }

  Future<void> _prefillWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        reserveWalletCtrl.text = w;
      }
    } catch (_) {}
  }

  Future<void> _loadSaved() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList('re_saved_ids') ?? [];
      _savedIds = raw.map((e) => int.tryParse(e) ?? -1).where((e) => e > 0).toSet();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveSaved() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('re_saved_ids', _savedIds.map((e) => e.toString()).toList());
    } catch (_) {}
  }

  List<Map<String, dynamic>> _applySortFilter(List<Map<String, dynamic>> list) {
    List<Map<String, dynamic>> out = List.of(list);
    if (_savedOnly && _savedIds.isNotEmpty) {
      out = out.where((e) {
        final id = e['id'] ?? '';
        final pid = (id is int) ? id : int.tryParse(id.toString()) ?? 0;
        return _savedIds.contains(pid);
      }).toList();
    }
    final minBaths = int.tryParse(minBathCtrl.text.trim()) ?? 0;
    final minArea = double.tryParse(minAreaCtrl.text.trim()) ?? 0;
    if (_statusFilter.isNotEmpty) {
      out = out.where((e) => (e['status'] ?? '').toString().toLowerCase() == _statusFilter).toList();
    }
    out = out.where((e) {
      final baths = (e['bathrooms'] is num) ? (e['bathrooms'] as num).toDouble() : double.tryParse((e['bathrooms'] ?? '').toString()) ?? 0;
      final area = (e['area_sqm'] is num) ? (e['area_sqm'] as num).toDouble() : double.tryParse((e['area_sqm'] ?? '').toString()) ?? 0;
      if (minBaths > 0 && baths < minBaths) return false;
      if (minArea > 0 && area < minArea) return false;
      return true;
    }).toList();
    int priceOf(Map<String, dynamic> m) => (m['price_cents'] is int) ? m['price_cents'] as int : int.tryParse((m['price_cents'] ?? '').toString()) ?? 0;
    int idOf(Map<String, dynamic> m) => (m['id'] is int) ? m['id'] as int : int.tryParse((m['id'] ?? '').toString()) ?? 0;
    double areaOf(Map<String, dynamic> m) => (m['area_sqm'] is num) ? (m['area_sqm'] as num).toDouble() : double.tryParse((m['area_sqm'] ?? '').toString()) ?? 0.0;
    switch (_sort) {
      case 'price_desc':
        out.sort((a, b) => priceOf(b).compareTo(priceOf(a)));
        break;
      case 'price_asc':
        out.sort((a, b) => priceOf(a).compareTo(priceOf(b)));
        break;
      case 'area_desc':
        out.sort((a, b) => areaOf(b).compareTo(areaOf(a)));
        break;
      case 'area_asc':
        out.sort((a, b) => areaOf(a).compareTo(areaOf(b)));
        break;
      default: // newest
        out.sort((a, b) => idOf(b).compareTo(idOf(a)));
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _status = '';
    });
    final u = Uri.parse(
        '${widget.baseUrl}/realestate/properties?q=${Uri.encodeComponent(qCtrl.text)}&city=${Uri.encodeComponent(cityCtrl.text)}&min_price=${Uri.encodeComponent(minpCtrl.text)}&max_price=${Uri.encodeComponent(maxpCtrl.text)}&min_bedrooms=${Uri.encodeComponent(minbCtrl.text)}');
    try {
      final r = await http.get(u, headers: await _reHeaders());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          _props = _applySortFilter(body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList());
          _status = '${_props.length} results';
        } else {
          _props = const [];
          _status = 'bad response';
        }
      } else {
        _props = const [];
        _status = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      if (!mounted) return;
      _props = const [];
      _status = 'error: $e';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _toggleSave(int pid) {
    setState(() {
      if (_savedIds.contains(pid)) {
        _savedIds.remove(pid);
      } else {
        _savedIds.add(pid);
      }
    });
    _saveSaved();
  }

  Future<void> _inquiry(int pid) async {
    setState(() => _actionOut = 'Sending inquiry...');
    try {
      final h = await _reHeaders(json: true);
      h['Idempotency-Key'] = 'inq-${DateTime.now().millisecondsSinceEpoch}';
      final r = await http.post(Uri.parse('${widget.baseUrl}/realestate/inquiries'),
          headers: h,
          body: jsonEncode({
            'property_id': pid,
            'name': inNameCtrl.text.trim().isEmpty ? 'Guest' : inNameCtrl.text.trim(),
            'phone': inPhoneCtrl.text.trim().isEmpty ? null : inPhoneCtrl.text.trim(),
            'message': inMsgCtrl.text.trim().isEmpty ? null : inMsgCtrl.text.trim(),
          }));
      setState(() => _actionOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _actionOut = 'error: $e');
    }
  }

  Future<void> _reserve(int pid) async {
    setState(() => _actionOut = 'Reserving...');
    try {
      final h = await _reHeaders(json: true);
      h['Idempotency-Key'] = 'res-${DateTime.now().millisecondsSinceEpoch}';
      final r = await http.post(Uri.parse('${widget.baseUrl}/realestate/reserve'),
          headers: h,
          body: jsonEncode({
            'property_id': pid,
            'buyer_wallet_id': reserveWalletCtrl.text.trim(),
            'deposit_cents': int.tryParse(reserveDepositCtrl.text.trim()) ?? 0
          }));
      setState(() => _actionOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _actionOut = 'error: $e');
    }
  }

  void _setFormPid(int pid) {
    reservePropCtrl.text = pid.toString();
  }

  void _openDetail(Map<String, dynamic> p) {
    final pid = (p['id'] is int) ? p['id'] as int : int.tryParse((p['id'] ?? '').toString()) ?? 0;
    if (pid > 0) {
      _recentIds.remove(pid);
      _recentIds.insert(0, pid);
      if (_recentIds.length > 10) {
        _recentIds.removeLast();
      }
    }
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (ctx, scroll) {
                return GlassPanel(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    controller: scroll,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(
                            (p['title'] ?? 'Property $pid').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                          )),
                          IconButton(
                              onPressed: () {
                                _toggleSave(pid);
                                Navigator.pop(ctx);
                              },
                              icon: Icon(_savedIds.contains(pid) ? Icons.bookmark : Icons.bookmark_border)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${p['price_cents'] ?? ''} SYP · ${(p['bedrooms'] ?? '-').toString()} bd · ${(p['bathrooms'] ?? '-').toString()} ba · ${(p['area_sqm'] ?? '-').toString()} m²',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if ((p['address'] ?? '').toString().isNotEmpty || (p['city'] ?? '').toString().isNotEmpty)
                        Text(
                          '${p['address'] ?? ''} ${(p['city'] ?? '').toString()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 10),
                      Text((p['description'] ?? '').toString()),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton(
                              onPressed: () {
                                _setFormPid(pid);
                                _inquiry(pid);
                              },
                              child: const Text('Contact')),
                          OutlinedButton(
                              onPressed: () {
                                _setFormPid(pid);
                                _reserve(pid);
                              },
                              child: const Text('Reserve')),
                        ],
                      ),
                    ],
                  ),
                );
              });
        });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final bg = const AppBG();

    Widget filterBar = GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.isArabic ? 'بحث عن عقار' : 'Find your home',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                  width: 180,
                  child: TextField(
                    controller: qCtrl,
                    decoration: InputDecoration(labelText: l.labelSearch),
                  )),
              SizedBox(
                  width: 150,
                  child: TextField(
                    controller: cityCtrl,
                    decoration: InputDecoration(labelText: l.labelCity),
                  )),
              SizedBox(
                  width: 140,
                  child: TextField(
                    controller: minpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min price'),
                  )),
              SizedBox(
                  width: 140,
                  child: TextField(
                    controller: maxpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max price'),
                  )),
              SizedBox(
                  width: 140,
                  child: TextField(
                    controller: minbCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min beds'),
                  )),
              SizedBox(
                  width: 140,
                  child: TextField(
                    controller: minBathCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min baths'),
                  )),
              SizedBox(
                  width: 140,
                  child: TextField(
                    controller: minAreaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min area m²'),
                  )),
              DropdownButton<String>(
                value: _statusFilter.isEmpty ? 'all' : _statusFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All status')),
                  DropdownMenuItem(value: 'listed', child: Text('Listed')),
                  DropdownMenuItem(value: 'reserved', child: Text('Reserved')),
                  DropdownMenuItem(value: 'sold', child: Text('Sold')),
                  DropdownMenuItem(value: 'rented', child: Text('Rented')),
                ],
                onChanged: (v) {
                  setState(() {
                    _statusFilter = (v == null || v == 'all') ? '' : v;
                    _props = _applySortFilter(_props);
                  });
                },
              ),
              SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _load,
                    child: Text(l.reSearch),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                  label: const Text('Newest'),
                  selected: _sort == 'newest',
                  onSelected: (_) {
                    setState(() {
                      _sort = 'newest';
                      _props = _applySortFilter(_props);
                    });
                  }),
              ChoiceChip(
                  label: const Text('Price ↓'),
                  selected: _sort == 'price_desc',
                  onSelected: (_) {
                    setState(() {
                      _sort = 'price_desc';
                      _props = _applySortFilter(_props);
                    });
                  }),
              ChoiceChip(
                  label: const Text('Price ↑'),
                  selected: _sort == 'price_asc',
                  onSelected: (_) {
                    setState(() {
                      _sort = 'price_asc';
                      _props = _applySortFilter(_props);
                    });
                  }),
              ChoiceChip(
                  label: const Text('Area ↓'),
                  selected: _sort == 'area_desc',
                  onSelected: (_) {
                    setState(() {
                      _sort = 'area_desc';
                      _props = _applySortFilter(_props);
                    });
                  }),
              ChoiceChip(
                  label: const Text('Area ↑'),
                  selected: _sort == 'area_asc',
                  onSelected: (_) {
                    setState(() {
                      _sort = 'area_asc';
                      _props = _applySortFilter(_props);
                    });
                  }),
              ChoiceChip(
                  label: const Text('Grid'),
                  selected: _viewMode == 'cards',
                  onSelected: (_) {
                    setState(() => _viewMode = 'cards');
                  }),
              ChoiceChip(
                  label: const Text('Table'),
                  selected: _viewMode == 'table',
                  onSelected: (_) {
                    setState(() => _viewMode = 'table');
                  }),
              ChoiceChip(
                  label: const Text('Saved only'),
                  selected: _savedOnly,
                  onSelected: (_) {
                    setState(() {
                      _savedOnly = !_savedOnly;
                      _props = _applySortFilter(_props);
                    });
                  }),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                  label: const Text('≤ 1,000,000'),
                  onPressed: () {
                    minpCtrl.text = '';
                    maxpCtrl.text = '1000000';
                    _load();
                  }),
              ActionChip(
                  label: const Text('≤ 5,000,000'),
                  onPressed: () {
                    minpCtrl.text = '';
                    maxpCtrl.text = '5000000';
                    _load();
                  }),
              ActionChip(
                  label: const Text('Beds ≥ 2'),
                  onPressed: () {
                    minbCtrl.text = '2';
                    _load();
                  }),
              ActionChip(
                  label: const Text('Beds ≥ 4'),
                  onPressed: () {
                    minbCtrl.text = '4';
                    _load();
                  }),
              ActionChip(
                  label: const Text('Baths ≥ 2'),
                  onPressed: () {
                    minBathCtrl.text = '2';
                    _props = _applySortFilter(_props);
                    setState(() {});
                  }),
              ActionChip(
                  label: const Text('Area ≥ 120 m²'),
                  onPressed: () {
                    minAreaCtrl.text = '120';
                    _props = _applySortFilter(_props);
                    setState(() {});
                  }),
              ActionChip(
                  label: const Text('Clear quick filters'),
                  onPressed: () {
                    minpCtrl.clear();
                    maxpCtrl.clear();
                    minbCtrl.clear();
                    minBathCtrl.clear();
                    minAreaCtrl.clear();
                    _load();
                  }),
            ],
          ),
          const SizedBox(height: 8),
          if (_status.isNotEmpty) Text(_status),
        ],
      ),
    );

    Widget mapStub = GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF0EA5E9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Center(
            child: Text(
          l.isArabic ? 'خريطة قادمة قريباً' : 'Map coming soon',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        )),
      ),
    );

    final savedList = _props.where((p) {
      final id = p['id'] ?? '';
      final pid = (id is int) ? id : int.tryParse(id.toString()) ?? 0;
      return _savedIds.contains(pid);
    }).toList();
    List<Map<String, dynamic>> _tableProps =
        _viewMode == 'table' ? _applySortFilter(_props) : _props;

    Widget cards = Column(
      children: _props.map((p) {
        final id = p['id'] ?? '';
        final pid = (id is int) ? id : int.tryParse(id.toString()) ?? 0;
        final title = (p['title'] ?? '').toString();
        final city = (p['city'] ?? '').toString();
        final address = (p['address'] ?? '').toString();
        final price = p['price_cents'] ?? 0;
        final beds = p['bedrooms'];
        final baths = p['bathrooms'];
        final area = p['area_sqm'];
        final status = (p['status'] ?? '').toString();
        final desc = (p['description'] ?? '').toString();
        final saved = _savedIds.contains(pid);
        final areaNum = (area is num) ? area.toDouble() : double.tryParse(area?.toString() ?? '');
        final pricePerSqm = (areaNum != null && areaNum > 0) ? (price / areaNum).round() : null;
        final priceStr = _fmtNum(price is num ? price : int.tryParse(price.toString()) ?? 0);
        final ppmStr = pricePerSqm != null ? _fmtNum(pricePerSqm) : null;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 160,
                    color: const Color(0xFF0EA5E9).withValues(alpha: .2),
                    child: const Center(child: Icon(Icons.image, size: 48, color: Colors.white70)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: Text(title.isEmpty ? 'Property $id' : title,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    IconButton(
                        onPressed: () => _toggleSave(pid),
                        icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border)),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(status, style: TextStyle(color: _statusColor(status))),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                    '$priceStr SYP · ${beds ?? '-'} bd · ${baths ?? '-'} ba · ${area ?? '-'} m²'
                    '${ppmStr != null ? ' · $ppmStr SYP/m²' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (address.isNotEmpty || city.isNotEmpty)
                  Text('$address ${city.isNotEmpty ? '· $city' : ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ElevatedButton(
                        onPressed: () {
                          _setFormPid(pid);
                          _openDetail(p);
                        },
                        child: Text(l.isArabic ? 'عرض التفاصيل' : 'View details')),
                    OutlinedButton(
                        onPressed: () {
                          _setFormPid(pid);
                          _inquiry(pid);
                        },
                        child: Text(l.isArabic ? 'استفسار' : 'Contact')),
                    OutlinedButton(
                        onPressed: () {
                          _setFormPid(pid);
                          _reserve(pid);
                        },
                        child: Text(l.isArabic ? 'حجز بدفعة' : 'Reserve')),
                  ],
                )
              ],
            ),
          ),
        );
      }).toList(),
    );

    Widget inquiryReserve = GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.isArabic ? 'تواصل / حجز' : 'Contact / Reserve',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                  width: 160,
                  child: TextField(
                    controller: reservePropCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Property ID'),
                  )),
              SizedBox(
                  width: 200,
                  child: TextField(
                    controller: inNameCtrl,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  )),
              SizedBox(
                  width: 180,
                  child: TextField(
                    controller: inPhoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  )),
              SizedBox(
                  width: 260,
                  child: TextField(
                    controller: inMsgCtrl,
                    decoration: const InputDecoration(labelText: 'Message'),
                  )),
              SizedBox(
                  width: 220,
                  child: TextField(
                    controller: reserveWalletCtrl,
                    decoration: const InputDecoration(labelText: 'Buyer wallet id'),
                  )),
              SizedBox(
                  width: 160,
                  child: TextField(
                    controller: reserveDepositCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Deposit (cents)'),
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                  onPressed: () {
                    final pid = int.tryParse(reservePropCtrl.text.trim()) ?? 0;
                    if (pid > 0) _inquiry(pid);
                  },
                  child: Text(l.isArabic ? 'إرسال استفسار' : 'Send inquiry')),
              OutlinedButton(
                  onPressed: () {
                    final pid = int.tryParse(reservePropCtrl.text.trim()) ?? 0;
                    if (pid > 0) _reserve(pid);
                  },
                  child: Text(l.isArabic ? 'حجز بدفعة' : 'Reserve')),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          if (_actionOut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_actionOut),
            ),
        ],
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Realestate'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          bg,
          Positioned.fill(
              child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                filterBar,
                const SizedBox(height: 12),
                mapStub,
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                inquiryReserve,
                const SizedBox(height: 12),
                if (_recentIds.isNotEmpty)
                  GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recently viewed (${_recentIds.length})',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recentIds.map((pid) {
                            return ActionChip(
                                label: Text('ID $pid'),
                                onPressed: () {
                                  final match = _props.firstWhere(
                                      (e) {
                                        final id = e['id'] ?? '';
                                        final eid = (id is int)
                                            ? id
                                            : int.tryParse(id.toString()) ?? 0;
                                        return eid == pid;
                                      },
                                      orElse: () => {});
                                  if (match.isNotEmpty) {
                                    _openDetail(match);
                                  } else {
                                    reservePropCtrl.text = pid.toString();
                                  }
                                });
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                if (savedList.isNotEmpty)
                  GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Saved (${savedList.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: savedList.map((p) {
                            final title = (p['title'] ?? 'Property').toString();
                            final id = p['id'];
                            return ActionChip(
                              label: Text('$title (#$id)'),
                              onPressed: () => _openDetail(p),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                _viewMode == 'cards'
                    ? cards
                    : _TableView(
                        props: _tableProps,
                        onDetail: _openDetail,
                        onContact: _inquiry,
                        onReserve: _reserve,
                        onSave: _toggleSave,
                        savedIds: _savedIds,
                        setPid: _setFormPid,
                      ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class RealEstateOperator extends StatefulWidget {
  final String baseUrl;
  const RealEstateOperator({super.key, required this.baseUrl});

  @override
  State<RealEstateOperator> createState() => _RealEstateOperatorState();
}

class _RealEstateOperatorState extends State<RealEstateOperator> {
  List<Map<String, dynamic>> _props = const [];
  bool _loading = false;
  String _out = '';
  String _statusFilter = 'all';
  final TextEditingController _opQueryCtrl = TextEditingController();
  final TextEditingController _opCityCtrl = TextEditingController();

  final titleCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final addrCtrl = TextEditingController();
  final bedsCtrl = TextEditingController();
  final bathsCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final ownerCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final editIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _opQueryCtrl.dispose();
    _opCityCtrl.dispose();
    titleCtrl.dispose();
    priceCtrl.dispose();
    cityCtrl.dispose();
    addrCtrl.dispose();
    bedsCtrl.dispose();
    bathsCtrl.dispose();
    areaCtrl.dispose();
    ownerCtrl.dispose();
    descCtrl.dispose();
    editIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _out = '';
    });
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/realestate/properties?limit=200'),
          headers: await _reHeaders());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          _props = body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList();
          _out = '${_props.length} listings';
        }
      } else {
        _out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      if (!mounted) return;
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredProps {
    return _props.where((p) {
      final st = (p['status'] ?? '').toString().toLowerCase();
      final city = (p['city'] ?? '').toString().toLowerCase();
      final title = (p['title'] ?? '').toString().toLowerCase();
      final q = _opQueryCtrl.text.toLowerCase();
      final c = _opCityCtrl.text.toLowerCase();
      if (_statusFilter != 'all' && st != _statusFilter) return false;
      if (q.isNotEmpty && !title.contains(q)) return false;
      if (c.isNotEmpty && !city.contains(c)) return false;
      return true;
    }).toList();
  }

  Future<void> _create() async {
    setState(() => _out = 'Creating...');
    try {
      final body = {
        'title': titleCtrl.text.trim(),
        'price_cents': int.tryParse(priceCtrl.text.trim()) ?? 0,
        'city': cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
        'address': addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim(),
        'bedrooms': bedsCtrl.text.trim().isEmpty ? null : int.tryParse(bedsCtrl.text.trim()),
        'bathrooms': bathsCtrl.text.trim().isEmpty ? null : int.tryParse(bathsCtrl.text.trim()),
        'area_sqm': areaCtrl.text.trim().isEmpty ? null : double.tryParse(areaCtrl.text.trim()),
        'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        'owner_wallet_id': ownerCtrl.text.trim().isEmpty ? null : ownerCtrl.text.trim(),
      };
      final r = await http.post(Uri.parse('${widget.baseUrl}/realestate/properties'),
          headers: await _reHeaders(json: true), body: jsonEncode(body));
      setState(() => _out = '${r.statusCode}: ${r.body}');
      await _load();
    } catch (e) {
      setState(() => _out = 'error: $e');
    }
  }

  Future<void> _updateStatus(int id, String status) async {
    setState(() => _out = 'Updating...');
    try {
      final r = await http.patch(
          Uri.parse('${widget.baseUrl}/realestate/properties/$id'),
          headers: await _reHeaders(json: true),
          body: jsonEncode({'status': status}));
      setState(() => _out = '${r.statusCode}: ${r.body}');
      await _load();
    } catch (e) {
      setState(() => _out = 'error: $e');
    }
  }

  Future<void> _updatePrice() async {
    final id = int.tryParse(editIdCtrl.text.trim()) ?? 0;
    if (id == 0) {
      setState(() => _out = 'Set property ID to edit');
      return;
    }
    final price = int.tryParse(priceCtrl.text.trim());
    final body = <String, dynamic>{};
    if (price != null) body['price_cents'] = price;
    if (descCtrl.text.trim().isNotEmpty) body['description'] = descCtrl.text.trim();
    setState(() => _out = 'Saving...');
    try {
      final r = await http.patch(
          Uri.parse('${widget.baseUrl}/realestate/properties/$id'),
          headers: await _reHeaders(json: true),
          body: jsonEncode(body));
      setState(() => _out = '${r.statusCode}: ${r.body}');
      await _load();
    } catch (e) {
      setState(() => _out = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = const AppBG();

    final stats = () {
      int listed = 0, reserved = 0, sold = 0, rented = 0;
      for (final p in _props) {
        final st = (p['status'] ?? '').toString().toLowerCase();
        switch (st) {
          case 'listed':
            listed++;
            break;
          case 'reserved':
            reserved++;
            break;
          case 'sold':
            sold++;
            break;
          case 'rented':
            rented++;
            break;
        }
      }
      return 'Listed $listed · Reserved $reserved · Sold $sold · Rented $rented';
    }();

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Realestate – Operator'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Create listing', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(width: 200, child: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title'))),
                            SizedBox(width: 140, child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (cents)'))),
                            SizedBox(width: 160, child: TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City'))),
                            SizedBox(width: 220, child: TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Address'))),
                            SizedBox(width: 100, child: TextField(controller: bedsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Beds'))),
                            SizedBox(width: 100, child: TextField(controller: bathsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Baths'))),
                            SizedBox(width: 120, child: TextField(controller: areaCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Area m²'))),
                            SizedBox(width: 200, child: TextField(controller: ownerCtrl, decoration: const InputDecoration(labelText: 'Owner wallet id'))),
                            SizedBox(width: 280, child: TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description'))),
                            ElevatedButton(onPressed: _create, child: const Text('Create')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Listings (${_props.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(stats, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            DropdownButton<String>(
                              value: _statusFilter,
                              items: const [
                                DropdownMenuItem(value: 'all', child: Text('All')),
                                DropdownMenuItem(value: 'listed', child: Text('Listed')),
                                DropdownMenuItem(value: 'reserved', child: Text('Reserved')),
                                DropdownMenuItem(value: 'sold', child: Text('Sold')),
                                DropdownMenuItem(value: 'rented', child: Text('Rented')),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _statusFilter = v ?? 'all';
                                });
                              },
                            ),
                            SizedBox(width: 180, child: TextField(controller: _opQueryCtrl, decoration: const InputDecoration(labelText: 'Search title'))),
                            SizedBox(width: 160, child: TextField(controller: _opCityCtrl, decoration: const InputDecoration(labelText: 'City filter'))),
                            SizedBox(width: 120, child: TextField(controller: editIdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ID to edit'))),
                            SizedBox(width: 140, child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New price (cents)'))),
                            SizedBox(width: 240, child: TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'New description (optional)'))),
                            ElevatedButton(onPressed: _updatePrice, child: const Text('Save changes')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._filteredProps.map((p) {
                          final id = p['id'] ?? '';
                          final pid = (id is int) ? id : int.tryParse(id.toString()) ?? 0;
                          final title = (p['title'] ?? '').toString();
                          final status = (p['status'] ?? '').toString();
                          final price = p['price_cents'] ?? 0;
                          final city = (p['city'] ?? '').toString();
                          final owner = (p['owner_wallet_id'] ?? '').toString();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: GlassPanel(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$title (#$id)', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text('$price SYP · $city', style: Theme.of(context).textTheme.bodySmall),
                                  if (owner.isNotEmpty) Text('Owner wallet: $owner', style: Theme.of(context).textTheme.bodySmall),
                                  Text('Status: $status', style: Theme.of(context).textTheme.bodySmall),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      OutlinedButton(onPressed: () => _updateStatus(pid, 'listed'), child: const Text('Listed')),
                                      OutlinedButton(onPressed: () => _updateStatus(pid, 'reserved'), child: const Text('Reserved')),
                                      OutlinedButton(onPressed: () => _updateStatus(pid, 'sold'), child: const Text('Sold')),
                                      OutlinedButton(onPressed: () => _updateStatus(pid, 'rented'), child: const Text('Rented')),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  if (_out.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_out),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableView extends StatelessWidget {
  final List<Map<String, dynamic>> props;
  final void Function(Map<String, dynamic>) onDetail;
  final void Function(int) onContact;
  final void Function(int) onReserve;
  final void Function(int) onSave;
  final Set<int> savedIds;
  final void Function(int) setPid;
  const _TableView({
    required this.props,
    required this.onDetail,
    required this.onContact,
    required this.onReserve,
    required this.onSave,
    required this.savedIds,
    required this.setPid,
  });

  String _fmtNumLocal(num v) {
    final s = v.round().toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  @override
  Widget build(BuildContext context) {
    if (props.isEmpty) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Title')),
          DataColumn(label: Text('City')),
          DataColumn(label: Text('Price')),
          DataColumn(label: Text('Beds')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: props.map((p) {
          final id = p['id'] ?? '';
          final pid = (id is int) ? id : int.tryParse(id.toString()) ?? 0;
          final title = (p['title'] ?? '').toString();
          final city = (p['city'] ?? '').toString();
          final price = p['price_cents'] ?? '';
          final beds = p['bedrooms'] ?? '';
          final status = (p['status'] ?? '').toString();
          final saved = savedIds.contains(pid);
          return DataRow(cells: [
            DataCell(Text(pid.toString())),
            DataCell(Text(title)),
            DataCell(Text(city)),
            DataCell(Text(_fmtNumLocal(price is num ? price : int.tryParse(price.toString()) ?? 0))),
            DataCell(Text(beds.toString())),
            DataCell(Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
              child: Text(status),
            )),
            DataCell(Wrap(
              spacing: 6,
              children: [
                IconButton(
                    tooltip: 'Detail',
                    onPressed: () => onDetail(p),
                    icon: const Icon(Icons.open_in_new)),
                IconButton(
                    tooltip: 'Contact',
                    onPressed: () {
                      setPid(pid);
                      onContact(pid);
                    },
                    icon: const Icon(Icons.message_outlined)),
                IconButton(
                    tooltip: 'Reserve',
                    onPressed: () {
                      setPid(pid);
                      onReserve(pid);
                    },
                    icon: const Icon(Icons.lock_outline)),
                IconButton(
                    tooltip: saved ? 'Unsave' : 'Save',
                    onPressed: () => onSave(pid),
                    icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border)),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }
}
