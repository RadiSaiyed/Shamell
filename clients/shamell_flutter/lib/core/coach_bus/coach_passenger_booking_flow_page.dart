// Cycle 220 — Coach Bus booking flow.
//
// Single-page funnel that takes the rider from a selected
// `CoachJourneyOption` to a confirmed `CoachBooking` with ticket
// coupons issued.
//
// Steps (collapsed into one screen with progress states):
//   1. Review summary (operator, time, price)
//   2. Optional contact email
//   3. "Confirm & pay" → POST /me/coach/bookings with the journey's
//      best_offer. We then POST /tickets to issue the coupons.
//   4. Show ticket details + a "Show my bookings" CTA.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../l10n.dart';
import 'coach_mobility_api.dart';
import 'coach_passenger_my_bookings_page.dart';

class CoachPassengerBookingFlowPage extends StatefulWidget {
  final String baseUrl;
  final CoachJourneyOption journey;
  final int passengers;

  const CoachPassengerBookingFlowPage({
    required this.baseUrl,
    required this.journey,
    required this.passengers,
    super.key,
  });

  @override
  State<CoachPassengerBookingFlowPage> createState() =>
      _CoachPassengerBookingFlowPageState();
}

enum _BookingStage { reviewing, processing, completed, failed }

class _CoachPassengerBookingFlowPageState
    extends State<CoachPassengerBookingFlowPage> {
  late final CoachMobilityApi _api;
  _BookingStage _stage = _BookingStage.reviewing;
  String? _error;
  String? _bookingId;
  String? _firstTicketId;
  final TextEditingController _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _stage = _BookingStage.processing;
      _error = null;
    });
    try {
      // Step 1 — create the booking from the journey's best offer.
      final draft = await _api.createBooking(
        offerId: widget.journey.bestOffer.offerId,
        passengers: widget.passengers,
        contactEmail: _emailCtrl.text.trim().isEmpty
            ? null
            : _emailCtrl.text.trim(),
      );
      // Step 2 — issue tickets on the booking.
      final tickets = await _api.issueTickets(
        bookingId: draft.booking.bookingId,
        offerId: draft.offer.offerId,
        passengerManifests: draft.passengerManifests,
      );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _bookingId = draft.booking.bookingId;
        _firstTicketId = tickets.tickets.isNotEmpty
            ? tickets.tickets.first.ticketId
            : null;
        _stage = _BookingStage.completed;
      });
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _stage = _BookingStage.failed;
        _error = err.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _BookingStage.failed;
        _error = isArabic
            ? 'تعذّر تأكيد الحجز'
            : 'Could not confirm the booking';
      });
    }
  }

  void _openMyBookings() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            CoachPassengerMyBookingsPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  String _fmtTime(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return iso;
    final local = p.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm  $hh:$mn';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'تأكيد الحجز' : 'Confirm booking'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          // Journey summary card.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.journey.operatorName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Icon(Icons.flight_takeoff_rounded,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(_fmtTime(widget.journey.departureAtIso)),
                      const Spacer(),
                      Icon(Icons.flight_land_rounded,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(_fmtTime(widget.journey.arrivalAtIso)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: <Widget>[
                      Text(isArabic ? 'الإجمالي' : 'Total',
                          style: const TextStyle(fontSize: 14)),
                      const Spacer(),
                      Text(
                        '${fmtCents(widget.journey.priceFromMinorUnits * widget.passengers)} ${widget.journey.currency}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    isArabic
                        ? '${widget.passengers} ركاب × ${fmtCents(widget.journey.priceFromMinorUnits)} ${widget.journey.currency}'
                        : '${widget.passengers} pax × ${fmtCents(widget.journey.priceFromMinorUnits)} ${widget.journey.currency}',
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_stage == _BookingStage.reviewing ||
              _stage == _BookingStage.failed) ...[
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: isArabic
                    ? 'البريد الإلكتروني (اختياري)'
                    : 'Contact email (optional)',
                helperText: isArabic
                    ? 'سنرسل تذكرتك إلى هذا البريد إن تم تقديمه.'
                    : 'We will send your ticket here if provided.',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed:
                  _stage == _BookingStage.processing ? null : _confirm,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.lock_rounded),
              label: Text(
                isArabic ? 'تأكيد ودفع' : 'Confirm & pay',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          if (_stage == _BookingStage.processing) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            ),
            Center(
              child: Text(
                isArabic
                    ? 'جاري تأكيد الحجز…'
                    : 'Confirming your booking…',
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ],
          if (_stage == _BookingStage.completed) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF388E3C).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF388E3C), size: 48),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                isArabic ? 'تم تأكيد الحجز' : 'Booking confirmed',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 20),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                isArabic
                    ? 'تذكرتك جاهزة في قسم "حجوزاتي".'
                    : 'Your ticket is ready in "My bookings".',
                style: const TextStyle(color: Colors.black54),
              ),
            ),
            if (_bookingId != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isArabic ? 'معرّف الحجز' : 'Booking ID',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),
                      SelectableText(
                        _bookingId!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_firstTicketId != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          isArabic ? 'معرّف التذكرة' : 'Ticket ID',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                        SelectableText(
                          _firstTicketId!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openMyBookings,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.confirmation_number_outlined),
              label: Text(
                isArabic ? 'عرض حجوزاتي' : 'View my bookings',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
