// Cycle 219 — Coach Bus offers/journey selection page.
//
// Renders the list of `CoachJourneyOption`s returned by the
// search endpoint. Each card shows operator + departure/arrival
// time + duration + price + amenities + change/refund flags. The
// rider taps one to enter the booking flow.

import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import 'coach_mobility_api.dart';
import 'coach_passenger_booking_flow_page.dart';

class CoachPassengerOffersPage extends StatelessWidget {
  final String baseUrl;
  final CoachJourneySearchResponse response;

  const CoachPassengerOffersPage({
    required this.baseUrl,
    required this.response,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${response.from} → ${response.to}',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${response.departureDate}  ·  ${response.passengers} ${isArabic ? "ركاب" : "pax"}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .85),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: response.journeys.length,
        itemBuilder: (ctx, i) {
          final j = response.journeys[i];
          return _OfferCard(
            journey: j,
            isArabic: isArabic,
            theme: theme,
            onTap: () {
              Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => CoachPassengerBookingFlowPage(
                    baseUrl: baseUrl,
                    journey: j,
                    passengers: response.passengers,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final CoachJourneyOption journey;
  final bool isArabic;
  final ThemeData theme;
  final VoidCallback onTap;

  const _OfferCard({
    required this.journey,
    required this.isArabic,
    required this.theme,
    required this.onTap,
  });

  String _fmtTime(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return iso;
    final local = p.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(int minutes, {required bool isArabic}) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (isArabic) {
      return '${h}س ${m.toString().padLeft(2, '0')}د';
    }
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.directions_bus_filled_rounded,
                      color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      journey.operatorName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  Text(
                    '${fmtCents(journey.priceFromMinorUnits)} ${journey.currency}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Text(
                    _fmtTime(journey.departureAtIso),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: <Widget>[
                          Text(
                            _fmtDuration(journey.durationMinutes,
                                isArabic: isArabic),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            height: 1.4,
                            color: Colors.black26,
                          ),
                          Text(
                            journey.transferCount == 0
                                ? (isArabic ? 'مباشر' : 'Direct')
                                : '${journey.transferCount} ${isArabic ? "تحويلات" : "transfers"}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    _fmtTime(journey.arrivalAtIso),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  if (journey.lowAvailability)
                    _flagChip(
                      label: isArabic
                          ? 'مقاعد محدودة'
                          : 'Few seats left',
                      color: const Color(0xFFE65100),
                    )
                  else
                    _flagChip(
                      label: isArabic
                          ? '${journey.seatsAvailable} مقعد متاح'
                          : '${journey.seatsAvailable} seats',
                      color: const Color(0xFF388E3C),
                    ),
                  const SizedBox(width: 6),
                  if (journey.changeable)
                    _flagChip(
                      label: isArabic ? 'قابل للتعديل' : 'Changeable',
                      color: const Color(0xFF1976D2),
                    ),
                  const SizedBox(width: 6),
                  if (journey.refundable)
                    _flagChip(
                      label: isArabic ? 'قابل للاسترداد' : 'Refundable',
                      color: const Color(0xFF7B1FA2),
                    ),
                ],
              ),
              if (journey.amenities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: journey.amenities
                      .take(5)
                      .map((a) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              a,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _flagChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
