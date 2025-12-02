import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'glass.dart';
import 'status_banner.dart';
import 'l10n.dart';
import '../main.dart' show AppBG, WaterButton;

class EquipmentCalendarPage extends StatefulWidget {
  final String baseUrl;
  final int equipmentId;
  final String title;
  const EquipmentCalendarPage({super.key, required this.baseUrl, required this.equipmentId, required this.title});

  @override
  State<EquipmentCalendarPage> createState() => _EquipmentCalendarPageState();
}

class _EquipmentCalendarPageState extends State<EquipmentCalendarPage> {
  DateTime _month = DateTime.now();
  List<dynamic> _days = const [];
  List<dynamic> _blocks = const [];
  bool _loading = false;
  String _err = '';

  String get _base => widget.baseUrl.trim();

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
      final m = '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';
      final uri = Uri.parse('$_base/equipment/calendar/${widget.equipmentId}').replace(queryParameters: {'month': m});
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map && body['days'] is List) {
          _days = body['days'] as List<dynamic>;
          _blocks = body['blocks'] is List ? body['blocks'] as List<dynamic> : const [];
        }
      } else {
        _err = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _err = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addHold() async {
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
                      Uri.parse('$_base/equipment/availability/${widget.equipmentId}'),
                      headers: {'content-type': 'application/json'},
                      body: jsonEncode(payload));
                  out = '${r.statusCode}: ${r.body}';
                  if (r.statusCode == 200) {
                    Navigator.of(context).pop();
                    _load();
                  }
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
                    const Text('Add hold / maintenance', style: TextStyle(fontWeight: FontWeight.w700)),
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
                ),
              );
            }),
          );
        });
  }

  Future<void> _addHoldPrefilled(String isoDay) async {
    final from = TextEditingController(text: '${isoDay}T08:00:00Z');
    final to = TextEditingController(text: '${isoDay}T18:00:00Z');
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
                      Uri.parse('$_base/equipment/availability/${widget.equipmentId}'),
                      headers: {'content-type': 'application/json'},
                      body: jsonEncode(payload));
                  out = '${r.statusCode}: ${r.body}';
                  if (r.statusCode == 200) {
                    Navigator.of(context).pop();
                    _load();
                  }
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
                    Text('Add hold for $isoDay', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                ),
              );
            }),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final firstDay = DateTime(_month.year, _month.month, 1);
    final weekdayOffset = firstDay.weekday % 7;
    final totalDays = DateUtils.getDaysInMonth(_month.year, _month.month);
    final items = List.generate(weekdayOffset + totalDays, (i) {
      if (i < weekdayOffset) return null;
      final day = i - weekdayOffset + 1;
      final iso = DateTime(_month.year, _month.month, day).toIso8601String().split('T').first;
      final data = _days.cast<Map?>().firstWhere((d) => d?['date'] == iso, orElse: () => null) ?? {};
      final available = data['available'] == true;
      final blocked = data['blocked'] == true;
      final booked = data['booked'] == true;
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
      return {'day': day, 'color': c, 'blocked': blocked, 'booked': booked, 'iso': iso};
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} · Calendar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
              onPressed: () {
                setState(() {
                  _month = DateTime(_month.year, _month.month - 1, 1);
                });
                _load();
              },
              icon: const Icon(Icons.chevron_left)),
          IconButton(
              onPressed: () {
                setState(() {
                  _month = DateTime(_month.year, _month.month + 1, 1);
                });
                _load();
              },
              icon: const Icon(Icons.chevron_right)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AppBG(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_err.isNotEmpty) const SizedBox(height: 8),
                if (_err.isNotEmpty) StatusBanner.error(_err),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 1),
                  itemBuilder: (_, i) {
                    final itm = items[i];
                    if (itm == null) return const SizedBox.shrink();
                    final color = itm['color'] is Color ? itm['color'] as Color : Colors.transparent;
                    return GestureDetector(
                      onTap: () {
                        final iso = itm['iso'] as String?;
                        if (iso != null) _addHoldPrefilled(iso);
                      },
                      child: Container(
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                        child: Center(child: Text(itm['day'].toString())),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (_blocks.isNotEmpty) ...[
                  const Text('Holds', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ..._blocks.map((b) {
                    final m = b as Map<String, dynamic>? ?? {};
                    return GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${m['from_iso'] ?? ''} → ${m['to_iso'] ?? ''} • ${m['reason'] ?? ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                WaterButton(label: 'Add hold', onTap: _addHold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
