import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show AppBG;
import 'glass.dart';

Future<Map<String, String>> _hdrInv({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) h['sa_cookie'] = cookie;
  return h;
}

class InventoryGlassPage extends StatefulWidget {
  final String baseUrl;
  const InventoryGlassPage(this.baseUrl, {super.key});
  @override
  State<InventoryGlassPage> createState() => _InventoryGlassPageState();
}

class _InventoryGlassPageState extends State<InventoryGlassPage> with SingleTickerProviderStateMixin {
  bool _busy = false;
  String _out = '';
  List<dynamic> _items = [];
  List<dynamic> _low = [];
  double _totalCost = 0;

  final _name = TextEditingController();
  final _qty = TextEditingController(text: '0');
  final _unit = TextEditingController(text: 'unit');
  final _price = TextEditingController(text: '0'); // purchase price per unit (cents)
  final _mhd = TextEditingController();
  final _batch = TextEditingController();
  final _lowThreshold = TextEditingController(text: '0');

  String get _base => widget.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _unit.dispose();
    _price.dispose();
    _mhd.dispose();
    _batch.dispose();
    _lowThreshold.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('$_base/pos/inventory/items'));
      if (r.statusCode == 200) {
        final arr = jsonDecode(r.body) as List;
        double total = 0;
        final low = <dynamic>[];
        for (final i in arr) {
          final qty = (i['stock_qty'] as num?)?.toDouble() ?? 0.0;
          final price = (i['purchase_price_cents'] as num?)?.toDouble() ?? 0.0;
          total += qty * price / 100.0;
          if (i['low_stock_threshold'] != null && qty <= (i['low_stock_threshold'] ?? 0)) {
            low.add(i);
          }
        }
        setState(() {
          _items = arr;
          _low = low;
          _totalCost = total;
        });
      }
    } catch (_) {}
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final body = jsonEncode({
        "name": name,
        "stock_qty": double.tryParse(_qty.text.trim()) ?? 0,
        "unit": _unit.text.trim(),
        "low_stock_threshold": double.tryParse(_lowThreshold.text.trim()),
        "batch_control": _batch.text.trim().isNotEmpty,
        "purchase_price_cents": int.tryParse(_price.text.trim()) ?? 0,
        "mhd": _mhd.text.trim().isEmpty ? null : _mhd.text.trim(),
      });
      final r = await http.post(Uri.parse('$_base/pos/inventory/items'), headers: await _hdrInv(json: true), body: body);
      _out = '${r.statusCode}: ${r.body}';
      await _load();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjust(int id, double delta) async {
    try {
      final body = jsonEncode({"inventory_item_id": id, "qty": delta, "reason": "adjustment"});
      await http.post(Uri.parse('$_base/pos/inventory/movements'), headers: await _hdrInv(json: true), body: body);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory & COGS'),
      ),
      body: Stack(
        children: [
          bg,
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Add inventory item', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(width: 180, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'))),
                        SizedBox(width: 100, child: TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Qty'), keyboardType: TextInputType.number)),
                        SizedBox(width: 100, child: TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Unit'))),
                        SizedBox(width: 140, child: TextField(controller: _price, decoration: const InputDecoration(labelText: 'Purchase price (cents)'), keyboardType: TextInputType.number)),
                        SizedBox(width: 140, child: TextField(controller: _lowThreshold, decoration: const InputDecoration(labelText: 'Low stock threshold'), keyboardType: TextInputType.number)),
                        SizedBox(width: 140, child: TextField(controller: _batch, decoration: const InputDecoration(labelText: 'Batch code (optional)'))),
                        SizedBox(width: 160, child: TextField(controller: _mhd, decoration: const InputDecoration(labelText: 'MHD (optional)'))),
                        ElevatedButton(onPressed: _busy ? null : _create, child: const Text('Save')),
                      ],
                    ),
                    if (_out.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_out)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Items: ${_items.length}')),
                    Chip(label: Text('Total stock value: ${_totalCost.toStringAsFixed(2)}')),
                    Chip(label: Text('Low stock: ${_low.length}')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ..._items.map((i) {
                final low = i['low_stock_threshold'] != null && (i['stock_qty'] as num) <= (i['low_stock_threshold'] ?? 0);
                return GlassPanel(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('Stock: ${i['stock_qty']} ${i['unit']}'),
                          Text('Cost: ${(i['purchase_price_cents'] ?? 0) / 100} per ${i['unit']}'),
                          if (i['mhd'] != null) Text('MHD: ${i['mhd']}'),
                        ],
                      )),
                      if (low) const Icon(Icons.warning, color: Colors.orange),
                      IconButton(onPressed: () => _adjust(i['id'] as int, 1), icon: const Icon(Icons.add)),
                      IconButton(onPressed: () => _adjust(i['id'] as int, -1), icon: const Icon(Icons.remove)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}
