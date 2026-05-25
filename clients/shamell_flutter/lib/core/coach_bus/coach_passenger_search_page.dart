// Cycle 218 — Coach Bus journey search page.
//
// The first step of the booking funnel. Lets the rider pick:
//   * origin city
//   * destination city
//   * departure date
//   * number of passengers
//
// Submitting routes to the offers page, which renders the
// returned `CoachJourneyOption` list and lets the rider pick one.
//
// City list is hard-coded to the Syria-only set returned by the
// BFF today (Damascus, Homs, Aleppo, Latakia). A follow-up cycle
// can pull the list from the bootstrap endpoint once the BFF
// surfaces it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import 'coach_mobility_api.dart';
import 'coach_passenger_offers_page.dart';

class CoachPassengerSearchPage extends StatefulWidget {
  final String baseUrl;

  const CoachPassengerSearchPage({required this.baseUrl, super.key});

  @override
  State<CoachPassengerSearchPage> createState() =>
      _CoachPassengerSearchPageState();
}

class _CoachPassengerSearchPageState extends State<CoachPassengerSearchPage> {
  late final CoachMobilityApi _api;
  String? _from;
  String? _to;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  int _passengers = 1;
  bool _submitting = false;
  String? _error;

  static const List<_City> _cities = <_City>[
    _City(code: 'damascus', en: 'Damascus', ar: 'دمشق'),
    _City(code: 'homs', en: 'Homs', ar: 'حمص'),
    _City(code: 'aleppo', en: 'Aleppo', ar: 'حلب'),
    _City(code: 'latakia', en: 'Latakia', ar: 'اللاذقية'),
  ];

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  void _swap() {
    if (_from == null || _to == null) return;
    setState(() {
      final tmp = _from;
      _from = _to;
      _to = tmp;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> _submit() async {
    final isArabic = L10n.of(context).isArabic;
    if (_from == null || _to == null) {
      setState(() => _error = isArabic
          ? 'اختر المدينة الأصلية والوجهة'
          : 'Pick origin and destination');
      return;
    }
    if (_from == _to) {
      setState(() => _error = isArabic
          ? 'الوجهتان متطابقتان'
          : 'Origin and destination cannot match');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final dateIso = _date.toIso8601String().substring(0, 10);
    try {
      final response = await _api.search(
        from: _from!,
        to: _to!,
        departureDate: dateIso,
        passengers: _passengers,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (ctx) => CoachPassengerOffersPage(
            baseUrl: widget.baseUrl,
            response: response,
          ),
        ),
      );
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = isArabic
            ? 'تعذّر الاتصال بالخادم'
            : 'Could not reach the server';
      });
    }
  }

  String _cityLabel(String code, {required bool isArabic}) {
    final c = _cities.firstWhere(
      (c) => c.code == code,
      orElse: () => _City(code: code, en: code, ar: code),
    );
    return isArabic ? c.ar : c.en;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'بحث رحلة' : 'Search journey'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  _cityDropdown(
                    label: isArabic ? 'من' : 'From',
                    icon: Icons.my_location_rounded,
                    value: _from,
                    onChanged: (v) => setState(() => _from = v),
                    isArabic: isArabic,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton.outlined(
                        onPressed: _from != null && _to != null ? _swap : null,
                        icon: const Icon(Icons.swap_vert_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _cityDropdown(
                    label: isArabic ? 'إلى' : 'To',
                    icon: Icons.location_on_outlined,
                    value: _to,
                    onChanged: (v) => setState(() => _to = v),
                    isArabic: isArabic,
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: theme.colorScheme.outline),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.event_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isArabic
                                  ? 'تاريخ السفر: ${_date.toIso8601String().substring(0, 10)}'
                                  : 'Travel date: ${_date.toIso8601String().substring(0, 10)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Icon(Icons.people_outline_rounded,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        isArabic ? 'عدد الركاب' : 'Passengers',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton.outlined(
                        onPressed: _passengers > 1
                            ? () => setState(() => _passengers--)
                            : null,
                        icon: const Icon(Icons.remove, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_passengers',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: _passengers < 6
                            ? () => setState(() => _passengers++)
                            : null,
                        icon: const Icon(Icons.add, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.search_rounded),
            label: Text(
              _submitting
                  ? (isArabic ? 'جارٍ البحث…' : 'Searching…')
                  : (isArabic ? 'ابحث' : 'Search'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cityDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required ValueChanged<String?> onChanged,
    required bool isArabic,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: _submitting ? null : onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      items: _cities
          .map((c) => DropdownMenuItem<String>(
                value: c.code,
                child: Text(isArabic ? c.ar : c.en),
              ))
          .toList(),
    );
  }
}

class _City {
  final String code;
  final String en;
  final String ar;
  const _City({required this.code, required this.en, required this.ar});
}
