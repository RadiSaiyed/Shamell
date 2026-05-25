// Cycle 221 — Coach Bus "My bookings" page.
//
// Lists every booking attached to the caller's account (via the
// existing `/me/coach/bookings` shelf endpoint). Each tile shows
// the journey summary + state and lets the rider drill into:
//   * Live tracking (current journey position) — Cycle 222
//   * Refund / rebook actions — Cycle 223 (separate page)

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'coach_boarding_pass_page.dart';
import 'coach_mobility_api.dart';
import 'coach_passenger_live_journey_page.dart';
import 'coach_passenger_refund_page.dart';
import 'coach_platform_contracts.dart';

class CoachPassengerMyBookingsPage extends StatefulWidget {
  final String baseUrl;

  const CoachPassengerMyBookingsPage({required this.baseUrl, super.key});

  @override
  State<CoachPassengerMyBookingsPage> createState() =>
      _CoachPassengerMyBookingsPageState();
}

class _CoachPassengerMyBookingsPageState
    extends State<CoachPassengerMyBookingsPage> {
  late final CoachMobilityApi _api;
  CoachBookingShelfResponse? _shelf;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shelf = await _api.listBookings();
      if (!mounted) return;
      setState(() {
        _shelf = shelf;
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
            ? 'تعذّر تحميل الحجوزات'
            : 'Could not load bookings';
      });
    }
  }

  void _openLive(CoachBookingShelfEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachPassengerLiveJourneyPage(
          baseUrl: widget.baseUrl,
          bookingId: entry.booking.bookingId,
          journeyId: entry.journey.journeyId,
        ),
      ),
    );
  }

  void _openRefund(CoachBookingShelfEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachPassengerRefundPage(
          baseUrl: widget.baseUrl,
          bookingId: entry.booking.bookingId,
        ),
      ),
    );
  }

  /// Cycle 250 — open the premium full-screen boarding pass.
  void _openBoardingPass(CoachBookingShelfEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachBoardingPassPage(
          baseUrl: widget.baseUrl,
          bookingId: entry.booking.bookingId,
          journeyId: entry.journey.journeyId,
        ),
      ),
    );
  }

  String _fmtIso(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return iso;
    final local = p.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm $hh:$mn';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final entries = _shelf?.bookings ?? const <CoachBookingShelfEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'حجوزاتي' : 'My bookings'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refresh,
            tooltip: isArabic ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null && entries.isEmpty)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(Icons.cloud_off_rounded,
                              size: 48, color: Colors.black38),
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  )
                : entries.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: <Widget>[
                          const SizedBox(height: 80),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                isArabic
                                    ? 'لا توجد حجوزات بعد.'
                                    : 'No bookings yet.',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: entries.length,
                        itemBuilder: (ctx, i) {
                          final e = entries[i];
                          return _bookingTile(e, isArabic: isArabic);
                        },
                      ),
      ),
    );
  }

  Widget _bookingTile(CoachBookingShelfEntry entry,
      {required bool isArabic}) {
    final summary = entry.journey;
    final state = entry.booking.state;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.directions_bus_filled_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.operatorName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                _statusChip(state, isArabic: isArabic),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${summary.from} → ${summary.to}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${_fmtIso(summary.departureAtIso)} → ${_fmtIso(summary.arrivalAtIso)}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 10),
            // Cycle 250 — Boarding Pass primary CTA for ticketed
            // bookings. Premium full-screen surface with QR.
            if (entry.tickets.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openBoardingPass(entry),
                  icon: const Icon(
                      Icons.confirmation_number_rounded,
                      size: 18),
                  label: Text(
                    isArabic ? 'بطاقة الصعود' : 'Boarding pass',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            if (entry.tickets.isNotEmpty) const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openLive(entry),
                    icon: const Icon(Icons.travel_explore_rounded, size: 18),
                    label: Text(isArabic ? 'تتبع مباشر' : 'Live tracking'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openRefund(entry),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: Text(
                      isArabic ? 'تغيير/استرداد' : 'Change/refund',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
      case CoachBookingLifecycleState.refundApproved:
      case CoachBookingLifecycleState.refundRequested:
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
}
