// Cycle 217 — Coach Bus passenger hub.
//
// First passenger-facing surface for the Coach (intercity bus)
// product. Lives inside the main user app as a separate page
// reached from a menu entry; we don't ship a dedicated rider
// flavor yet — the intercity audience overlaps with the taxi
// rider audience enough that a single shell + page makes sense.
//
// The hub has two primary entry points:
//   * "Search journeys" — large CTA that opens the search page
//   * "My bookings" — recent bookings preview + link to the full
//     bookings page when there are any
//
// Both surfaces are powered by the existing `CoachMobilityApi`
// in coach_mobility_api.dart. No new BFF wiring needed.

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'coach_crew_cockpit_page.dart';
import 'coach_mobility_api.dart';
import 'coach_passenger_my_bookings_page.dart';
import 'coach_passenger_search_page.dart';
import 'coach_platform_contracts.dart';

class CoachPassengerHubPage extends StatefulWidget {
  final String baseUrl;

  const CoachPassengerHubPage({required this.baseUrl, super.key});

  @override
  State<CoachPassengerHubPage> createState() => _CoachPassengerHubPageState();
}

class _CoachPassengerHubPageState extends State<CoachPassengerHubPage> {
  late final CoachMobilityApi _api;
  CoachBookingShelfResponse? _shelf;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final shelf = await _api.listBookings();
      if (!mounted) return;
      setState(() {
        _shelf = shelf;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openSearch() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) =>
            CoachPassengerSearchPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  void _openMyBookings() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) =>
            CoachPassengerMyBookingsPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  /// Cycle 258 — discovery entry into the Crew Cockpit. Any user
  /// can open it; if they aren't assigned to any trips the cockpit
  /// shows its own "no trips" empty state. Riders who double up as
  /// drivers see their next shift here.
  void _openCrewCockpit() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) =>
            CoachCrewCockpitPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    final upcoming = _shelf?.bookings
            .where((e) =>
                e.booking.state == CoachBookingLifecycleState.ticketed ||
                e.booking.state == CoachBookingLifecycleState.bookingPending ||
                e.booking.state == CoachBookingLifecycleState.paymentAuthorized ||
                e.booking.state == CoachBookingLifecycleState.partiallyTicketed)
            .toList(growable: false) ??
        const <CoachBookingShelfEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'الباصات بين المدن' : 'Intercity coaches'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            // Hero search CTA — the dominant action on this page.
            Material(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _openSearch,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Icon(Icons.directions_bus_filled_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              isArabic
                                  ? 'ابحث عن رحلة'
                                  : 'Search a journey',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isArabic
                                  ? 'بين دمشق وحمص وحلب واللاذقية'
                                  : 'Between Damascus, Homs, Aleppo, Latakia',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .85),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // My bookings section.
            Row(
              children: <Widget>[
                Text(
                  isArabic ? 'حجوزاتي' : 'My bookings',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (!_loading && (_shelf?.bookings.isNotEmpty ?? false))
                  TextButton.icon(
                    onPressed: _openMyBookings,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: Text(isArabic ? 'الكل' : 'See all'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (upcoming.isEmpty)
              _emptyState(isArabic: isArabic, theme: theme)
            else
              ...upcoming.take(3).map((e) => _bookingCard(
                    entry: e,
                    isArabic: isArabic,
                    theme: theme,
                  )),
            const SizedBox(height: 24),
            _crewCockpitTile(theme: theme, isArabic: isArabic),
          ],
        ),
      ),
    );
  }

  /// Cycle 258 — tile that opens the Crew Cockpit. Lives at the
  /// bottom of the hub so passengers don't trip over it but crew
  /// always know where to go for "what's my next trip?".
  Widget _crewCockpitTile({
    required ThemeData theme,
    required bool isArabic,
  }) {
    return Material(
      color: const Color(0xFF1A1D23),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openCrewCockpit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Icon(Icons.badge_outlined,
                    color: Color(0xFFFFC107), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isArabic ? 'قمرة الطاقم' : 'Crew cockpit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? 'للسائقين: رحلتك التالية ومسح الصعود'
                          : 'Driver/crew: next trip + boarding scanner',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState({required bool isArabic, required ThemeData theme}) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(Icons.confirmation_number_outlined,
                size: 36,
                color: theme.colorScheme.onSurface.withValues(alpha: .35)),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'لا توجد حجوزات حالية. ابدأ بالبحث عن رحلة.'
                  : 'No bookings yet. Start with a journey search.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookingCard({
    required CoachBookingShelfEntry entry,
    required bool isArabic,
    required ThemeData theme,
  }) {
    final summary = entry.journey;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              theme.colorScheme.primary.withValues(alpha: .12),
          child: Icon(Icons.directions_bus_rounded,
              color: theme.colorScheme.primary),
        ),
        title: Text(
          '${summary.from} → ${summary.to}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${summary.operatorName} · ${_fmtIso(summary.departureAtIso)}',
        ),
        trailing: _statusChip(entry.booking.state, isArabic: isArabic),
        onTap: _openMyBookings,
      ),
    );
  }

  Widget _statusChip(CoachBookingLifecycleState state,
      {required bool isArabic}) {
    Color bg;
    Color fg;
    String label;
    switch (state) {
      case CoachBookingLifecycleState.ticketed:
      case CoachBookingLifecycleState.partiallyTicketed:
        bg = const Color(0xFF388E3C).withValues(alpha: .14);
        fg = const Color(0xFF1B5E20);
        label = isArabic ? 'مُذكَّر' : 'Ticketed';
        break;
      case CoachBookingLifecycleState.paymentAuthorized:
      case CoachBookingLifecycleState.bookingPending:
        bg = const Color(0xFFFFA000).withValues(alpha: .14);
        fg = const Color(0xFFE65100);
        label = isArabic ? 'معلق' : 'Pending';
        break;
      case CoachBookingLifecycleState.cancelled:
      case CoachBookingLifecycleState.refunded:
        bg = Colors.grey.withValues(alpha: .14);
        fg = Colors.black54;
        label = isArabic ? 'ملغى' : 'Cancelled';
        break;
      case CoachBookingLifecycleState.boarded:
        bg = const Color(0xFF1976D2).withValues(alpha: .14);
        fg = const Color(0xFF0D47A1);
        label = isArabic ? 'تم الصعود' : 'Boarded';
        break;
      default:
        bg = Colors.grey.withValues(alpha: .14);
        fg = Colors.black54;
        label = state.toString().split('.').last;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: fg,
          letterSpacing: .4,
        ),
      ),
    );
  }

  String _fmtIso(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm $hh:$mn';
  }
}
