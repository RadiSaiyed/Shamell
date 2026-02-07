import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_shell_widgets.dart' show AppBG;
import 'design_tokens.dart';
import 'glass.dart';

class DoctorsDoctolibPage extends StatefulWidget {
  final String baseUrl;
  const DoctorsDoctolibPage({super.key, required this.baseUrl});

  @override
  State<DoctorsDoctolibPage> createState() => _DoctorsDoctolibPageState();
}

class _DoctorsDoctolibPageState extends State<DoctorsDoctolibPage> {
  final _searchCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _loading = false;
  List<_DoctorResult> _results = const [];
  String _error = '';
  String _insuranceFilter = '';
  final _languageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<Map<String, String>> _hdr({bool json = false}) async {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    try {
      final sp = await SharedPreferences.getInstance();
      final cookie = sp.getString('sa_cookie');
      if (cookie != null && cookie.isNotEmpty) h['sa_cookie'] = cookie;
    } catch (_) {}
    return h;
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/doctors/search')
          .replace(queryParameters: {
        'q': _searchCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'from_iso': DateTime.now().toIso8601String(),
        'to_iso': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
        'insurance': _insuranceFilter,
        'language': _languageCtrl.text.trim(),
      });
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) {
        setState(() {
          _error = 'Search failed: ${r.statusCode}';
          _results = const [];
          _loading = false;
        });
        return;
      }
      final j = jsonDecode(r.body) as List;
      final list = j
          .map((e) => _DoctorResult(
                id: e['id'] as int,
                name: e['name'] ?? '',
                speciality: e['speciality'] ?? '',
                city: e['city'] ?? '',
                insurance: e['insurance']?.toString(),
                languages: e['languages']?.toString(),
                nextSlots: (e['next_slots'] as List?)
                        ?.map((s) => s.toString())
                        .toList() ??
                    const [],
              ))
          .toList();
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Search error: $e';
        _loading = false;
      });
    }
  }

  Future<List<_Slot>> _fetchSlots(int doctorId) async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/doctors/$doctorId/slots')
          .replace(queryParameters: {
        'from_iso': DateTime.now().toIso8601String(),
        'to_iso': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
      });
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) return const [];
      final j = jsonDecode(r.body) as List;
      return j
          .map((e) => _Slot(
                iso: e['ts_iso'] ?? '',
                duration: e['duration_minutes'] ?? 20,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _book(int doctorId, String slotIso) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Book appointment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full name')),
              TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone/email')),
              TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Reason')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  final payload = {
                    'slot_iso': slotIso,
                    'patient_name': nameCtrl.text.trim(),
                    'patient_phone': phoneCtrl.text.trim(),
                    'reason': reasonCtrl.text.trim(),
                  };
                  final r = await http.post(
                    Uri.parse('${widget.baseUrl}/doctors/$doctorId/book'),
                    headers: await _hdr(json: true),
                    body: jsonEncode(payload),
                  );
                  if (r.statusCode == 200) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Booked successfully')));
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Booking failed: ${r.statusCode}')));
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _openSlots(_DoctorResult doc) async {
    final slots = await _fetchSlots(doc.id);
    if (!mounted) return;
    // group by day
    final grouped = <String, List<_Slot>>{};
    for (final s in slots) {
      final day = _fmtDay(s.iso);
      grouped.putIfAbsent(day, () => []).add(s);
    }
    await showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (slots.isEmpty)
                    const Text('No slots available')
                  else
                    ...grouped.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: e.value
                                    .take(12)
                                    .map((s) => ElevatedButton(
                                          onPressed: () => _book(doc.id, s.iso),
                                          child: Text(_fmtSlot(s.iso)),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          );
        });
  }

  String _fmtSlot(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Doctors'),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _HeroSearch(
                    searchCtrl: _searchCtrl,
                    cityCtrl: _cityCtrl,
                    onSearch: _fetch,
                    onInsuranceChanged: (v) {
                      setState(() => _insuranceFilter = v);
                      _fetch();
                    },
                    languageCtrl: _languageCtrl,
                  ),
                  const SizedBox(height: 16),
                  const _SpecialtyGrid(),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                  if (_error.isNotEmpty) Text(_error),
                  if (!_loading && _error.isEmpty)
                    _DoctorList(
                      results: _results,
                      onViewSlots: _openSlots,
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

class _DoctorResult {
  final int id;
  final String name;
  final String speciality;
  final String city;
  final String? insurance;
  final String? languages;
  final List<String> nextSlots;
  const _DoctorResult({
    required this.id,
    required this.name,
    required this.speciality,
    required this.city,
    this.insurance,
    this.languages,
    required this.nextSlots,
  });
}

class _Slot {
  final String iso;
  final int duration;
  const _Slot({required this.iso, required this.duration});
}

class _HeroSearch extends StatelessWidget {
  final TextEditingController searchCtrl;
  final TextEditingController cityCtrl;
  final VoidCallback onSearch;
  final void Function(String) onInsuranceChanged;
  final TextEditingController languageCtrl;
  const _HeroSearch({
    required this.searchCtrl,
    required this.cityCtrl,
    required this.onSearch,
    required this.onInsuranceChanged,
    required this.languageCtrl,
  });
  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Book a doctor in minutes',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Find doctors, dentists, and specialists near you.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SearchField(
                icon: Icons.search,
                hint: 'Search doctor or specialty',
                controller: searchCtrl,
              ),
              _SearchField(
                icon: Icons.place_outlined,
                hint: 'Location',
                controller: cityCtrl,
              ),
              _SearchField(
                icon: Icons.translate,
                hint: 'Language',
                controller: languageCtrl,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.tune),
                  label: const Text('Filters'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('See results'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Any insurance'),
                selected: false,
                onSelected: (_) => onInsuranceChanged(''),
              ),
              ChoiceChip(
                label: const Text('Public'),
                selected: false,
                onSelected: (_) => onInsuranceChanged('public'),
              ),
              ChoiceChip(
                label: const Text('Private'),
                selected: false,
                onSelected: (_) => onInsuranceChanged('private'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final IconData icon;
  final String hint;
  final TextEditingController? controller;
  const _SearchField({required this.icon, required this.hint, this.controller});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          hintText: hint,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Tokens.border),
          ),
        ),
      ),
    );
  }
}

class _SpecialtyGrid extends StatelessWidget {
  const _SpecialtyGrid();

  @override
  Widget build(BuildContext context) {
    final specs = [
      ('General practitioner', Icons.health_and_safety_outlined, Tokens.accent),
      ('Dentist', Icons.medical_services_outlined, Tokens.colorHotelsStays),
      ('Pediatrician', Icons.child_care_outlined, Tokens.colorFood),
      ('Dermatologist', Icons.spa_outlined, Tokens.colorAgricultureLivestock),
      ('Cardiologist', Icons.favorite_border, Tokens.colorTaxi),
      ('Gynecologist', Icons.family_restroom, Tokens.colorHotelsStays),
    ];
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Popular specialties',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
            ),
            itemCount: specs.length,
            itemBuilder: (context, i) {
              final s = specs[i];
              return _SpecialtyCard(
                label: s.$1,
                icon: s.$2,
                tint: s.$3,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SpecialtyCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  const _SpecialtyCard(
      {required this.label, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            backgroundColor: tint.withValues(alpha: 0.16),
            child: Icon(icon, color: tint),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DoctorList extends StatelessWidget {
  final List<_DoctorResult> results;
  final void Function(_DoctorResult) onViewSlots;
  const _DoctorList({required this.results, required this.onViewSlots});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Doctors',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (results.isEmpty)
            const Text('No doctors found')
          else
            ...results.map((d) => _DoctorCard(
                  result: d,
                  onViewSlots: () => onViewSlots(d),
                )),
        ],
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final _DoctorResult result;
  final VoidCallback onViewSlots;
  const _DoctorCard({required this.result, required this.onViewSlots});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        radius: 14,
        child: Row(
          children: [
            const CircleAvatar(
              radius: 22,
              child: Icon(Icons.person_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('${result.speciality} • ${result.city}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.event_available, size: 16),
                      const SizedBox(width: 4),
                      Text(
                          [
                            if (result.nextSlots.isNotEmpty)
                              'Next: ${_fmt(result.nextSlots.first)}',
                            if (result.insurance != null &&
                                result.insurance!.isNotEmpty)
                              'Insurance: ${result.insurance}',
                            if (result.languages != null &&
                                result.languages!.isNotEmpty)
                              'Languages: ${result.languages}',
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                ElevatedButton(
                  onPressed: onViewSlots,
                  child: const Text('View slots'),
                ),
                const SizedBox(height: 6),
                if (result.nextSlots.isNotEmpty)
                  TextButton(
                    onPressed: onViewSlots,
                    child: const Text('Quick book'),
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

String _fmt(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

String _fmtDay(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}
