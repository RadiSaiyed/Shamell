// Cycle 255 — Coach crew cockpit.
//
// The bus driver/crew's home page. Focused, single-purpose
// surface: "what trip am I working right now / next" with a giant
// "Open boarding scanner" CTA. Separate from the operator
// dispatch console (which shows the whole fleet) — this is
// driver-first.
//
// Pulls from the existing `crewDepartures()` BFF endpoint (no
// new wiring needed). The "Next trip" hero is the first
// departure whose status is upcoming/boarding; everything else is
// the upcoming queue.

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'coach_crew_trip_detail_page.dart';
import 'coach_mobility_api.dart';

class CoachCrewCockpitPage extends StatefulWidget {
  final String baseUrl;

  const CoachCrewCockpitPage({required this.baseUrl, super.key});

  @override
  State<CoachCrewCockpitPage> createState() => _CoachCrewCockpitPageState();
}

class _CoachCrewCockpitPageState extends State<CoachCrewCockpitPage> {
  late final CoachMobilityApi _api;
  CoachCrewDepartureBoardResponse? _board;
  bool _loading = true;
  String? _error;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final board = await _api.crewDepartures();
      if (!mounted) return;
      setState(() {
        _board = board;
        _loading = false;
      });
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = L10n.of(context).isArabic
            ? 'تعذّر تحميل قائمة المغادرات'
            : 'Could not load the departures';
      });
    }
  }

  void _openTrip(CoachCrewTripSummary trip) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachCrewTripDetailPage(
          baseUrl: widget.baseUrl,
          tripId: trip.tripId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    final departures = _board?.departures ?? const <CoachCrewTripSummary>[];
    final nextTrip = departures.isNotEmpty ? departures.first : null;
    final queue = departures.length > 1
        ? departures.sublist(1)
        : const <CoachCrewTripSummary>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'قمرة الطاقم' : 'Crew cockpit'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: _loading && _board == null
            ? const Center(child: CircularProgressIndicator())
            : (_error != null && _board == null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: <Widget>[
                      if (nextTrip == null)
                        _noTripsCard(theme: theme, isArabic: isArabic)
                      else
                        _nextTripHero(
                          trip: nextTrip,
                          theme: theme,
                          isArabic: isArabic,
                        ),
                      if (queue.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            isArabic ? 'في الطابور' : 'Upcoming queue',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: .4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...queue.map((t) => _queueRow(
                              trip: t,
                              theme: theme,
                              isArabic: isArabic,
                            )),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _noTripsCard({required ThemeData theme, required bool isArabic}) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: <Widget>[
            Icon(Icons.directions_bus_outlined,
                size: 48, color: theme.colorScheme.onSurface
                    .withValues(alpha: .35)),
            const SizedBox(height: 12),
            Text(
              isArabic
                  ? 'لا توجد رحلات مسندة الآن.'
                  : 'No trips assigned right now.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextTripHero({
    required CoachCrewTripSummary trip,
    required ThemeData theme,
    required bool isArabic,
  }) {
    final boardingOpen = DateTime.tryParse(trip.boardingOpensAtIso);
    final boardingClose = DateTime.tryParse(trip.boardingClosesAtIso);
    final now = DateTime.now();
    final boardingActive = boardingOpen != null &&
        boardingClose != null &&
        now.isAfter(boardingOpen) &&
        now.isBefore(boardingClose.add(const Duration(minutes: 30)));
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Container(
            color: theme.colorScheme.primary,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.flight_takeoff_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isArabic ? 'الرحلة التالية' : 'Next trip',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (boardingActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          isArabic ? 'الصعود مفتوح' : 'BOARDING NOW',
                          style: const TextStyle(
                            color: Color(0xFF7A4F00),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: .6,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${trip.from} → ${trip.to}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_shortDateTime(trip.departureAtIso)} → ${_shortDateTime(trip.arrivalAtIso)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .82),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                    child: _fact(
                        isArabic ? 'البوابة' : 'Gate', trip.gateLabel)),
                Expanded(
                    child: _fact(isArabic ? 'المركبة' : 'Vehicle',
                        trip.vehicleLabel)),
                Expanded(
                    child: _fact(isArabic ? 'الركاب' : 'Pax',
                        trip.manifestCount.toString())),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Row(
              children: <Widget>[
                _miniStat(
                    label: isArabic ? 'صعدوا' : 'Boarded',
                    value: trip.boardedCount,
                    color: const Color(0xFF388E3C)),
                const SizedBox(width: 8),
                _miniStat(
                    label: isArabic ? 'لم يحضروا' : 'No-show',
                    value: trip.noShowCount,
                    color: const Color(0xFFE65100)),
                const SizedBox(width: 8),
                _miniStat(
                    label: isArabic ? 'انتظار' : 'Pending',
                    value: trip.pendingCount,
                    color: theme.colorScheme.primary),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openTrip(trip),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                    label: Text(
                      isArabic
                          ? 'افتح الصعود والمسح'
                          : 'Open boarding scanner',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueRow({
    required CoachCrewTripSummary trip,
    required ThemeData theme,
    required bool isArabic,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openTrip(trip),
        leading: CircleAvatar(
          backgroundColor:
              theme.colorScheme.primary.withValues(alpha: .12),
          child: Icon(Icons.directions_bus_filled_rounded,
              color: theme.colorScheme.primary, size: 22),
        ),
        title: Text(
          '${trip.from} → ${trip.to}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_shortDateTime(trip.departureAtIso)} · ${trip.manifestCount} ${isArabic ? "ركاب" : "pax"}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '—' : value,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _miniStat({
    required String label,
    required int value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: <Widget>[
            Text(
              '$value',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDateTime(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return iso;
    final l = p.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mn = l.minute.toString().padLeft(2, '0');
    return '$dd.$mm $hh:$mn';
  }
}
