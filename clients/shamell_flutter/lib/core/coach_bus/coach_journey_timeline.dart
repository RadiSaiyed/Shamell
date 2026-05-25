// Cycle 252 — Coach journey timeline widget.
//
// Visual breakdown of the four key moments of an intercity bus
// trip: boarding window open → departure → in transit → arrival.
// Computes a "you are here" progress marker from the live status
// label + current wall-clock vs the schedule, no BFF round-trip.
//
// Designed to look at home both on the dark boarding pass and the
// regular live-journey card — `darkMode` parameter toggles the
// color palette.

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'coach_mobility_api.dart';

class CoachJourneyTimeline extends StatelessWidget {
  final CoachJourneyLiveResponse live;
  final bool darkMode;

  const CoachJourneyTimeline({
    required this.live,
    this.darkMode = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final events = _buildEvents(isArabic: isArabic);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            isArabic ? 'مسار الرحلة' : 'Journey timeline',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: darkMode ? Colors.white : null,
              fontSize: 15,
            ),
          ),
        ),
        for (var i = 0; i < events.length; i++)
          _row(
            event: events[i],
            isLast: i == events.length - 1,
            isArabic: isArabic,
          ),
      ],
    );
  }

  Widget _row({
    required _TimelineEvent event,
    required bool isLast,
    required bool isArabic,
  }) {
    final dotColor = event.state == _TimelineState.passed
        ? const Color(0xFF34D399)
        : event.state == _TimelineState.current
            ? const Color(0xFFFFC107)
            : (darkMode
                ? Colors.white.withValues(alpha: .25)
                : Colors.black26);
    final connectorColor = event.state == _TimelineState.passed
        ? const Color(0xFF34D399)
        : (darkMode
            ? Colors.white.withValues(alpha: .12)
            : Colors.black12);
    final titleColor = darkMode ? Colors.white : Colors.black87;
    final subColor = darkMode
        ? Colors.white.withValues(alpha: .55)
        : Colors.black54;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              // Dot
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: event.state == _TimelineState.current
                      ? dotColor
                      : (darkMode
                          ? const Color(0xFF1A1D23)
                          : Colors.white),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: dotColor,
                    width: event.state == _TimelineState.current
                        ? 4
                        : 2.5,
                  ),
                ),
              ),
              // Connector
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: connectorColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            fontWeight: event.state == _TimelineState.current
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: titleColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (event.timeLabel.isNotEmpty)
                        Text(
                          event.timeLabel,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  if (event.detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        event.detail,
                        style: TextStyle(
                          color: subColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (event.state == _TimelineState.current)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107)
                              .withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isArabic ? 'الحالة الحالية' : 'Current step',
                          style: const TextStyle(
                            color: Color(0xFFE65100),
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: .6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_TimelineEvent> _buildEvents({required bool isArabic}) {
    final j = live.journey;
    final trip = live.trip;
    final now = DateTime.now();
    final boardingOpenIso = trip.boardingOpensAtIso;
    final boardingCloseIso = trip.boardingClosesAtIso;
    final boardingOpen = DateTime.tryParse(boardingOpenIso);
    final boardingClose = DateTime.tryParse(boardingCloseIso);
    final departure = DateTime.tryParse(j.departureAtIso);
    final arrival = DateTime.tryParse(j.arrivalAtIso);
    final statusLower = j.statusLabel.toLowerCase();

    // Compute states per event.
    _TimelineState boardingState;
    _TimelineState departureState;
    _TimelineState transitState;
    _TimelineState arrivalState;

    if (statusLower.contains('arriv') ||
        statusLower.contains('completed')) {
      boardingState = _TimelineState.passed;
      departureState = _TimelineState.passed;
      transitState = _TimelineState.passed;
      arrivalState = _TimelineState.current;
    } else if (statusLower.contains('depart') ||
        statusLower.contains('en route') ||
        statusLower.contains('transit')) {
      boardingState = _TimelineState.passed;
      departureState = _TimelineState.passed;
      transitState = _TimelineState.current;
      arrivalState = _TimelineState.upcoming;
    } else if (statusLower.contains('board')) {
      boardingState = _TimelineState.current;
      departureState = _TimelineState.upcoming;
      transitState = _TimelineState.upcoming;
      arrivalState = _TimelineState.upcoming;
    } else if (departure != null && now.isAfter(departure)) {
      boardingState = _TimelineState.passed;
      departureState = _TimelineState.passed;
      transitState = _TimelineState.current;
      arrivalState = _TimelineState.upcoming;
    } else if (boardingOpen != null && now.isAfter(boardingOpen)) {
      boardingState = _TimelineState.current;
      departureState = _TimelineState.upcoming;
      transitState = _TimelineState.upcoming;
      arrivalState = _TimelineState.upcoming;
    } else {
      boardingState = _TimelineState.upcoming;
      departureState = _TimelineState.upcoming;
      transitState = _TimelineState.upcoming;
      arrivalState = _TimelineState.upcoming;
    }

    return <_TimelineEvent>[
      _TimelineEvent(
        title: isArabic ? 'نافذة الصعود' : 'Boarding window',
        timeLabel: _shortTime(boardingOpenIso),
        detail: boardingClose != null
            ? (isArabic
                ? 'تُغلق في ${_shortTime(boardingCloseIso)}'
                : 'closes at ${_shortTime(boardingCloseIso)}')
            : (isArabic
                ? 'سيُعلن قبل المغادرة بـ 20 د'
                : 'announced ~20 min before departure'),
        state: boardingState,
      ),
      _TimelineEvent(
        title: isArabic ? 'المغادرة' : 'Departure',
        timeLabel: _shortTime(j.departureAtIso),
        detail: '${j.from}${trip.gateLabel.isNotEmpty ? " · ${trip.gateLabel}" : ""}',
        state: departureState,
      ),
      _TimelineEvent(
        title: isArabic ? 'في الطريق' : 'In transit',
        timeLabel: _durationLabel(departure, arrival, isArabic: isArabic),
        detail: trip.vehicleLabel.isNotEmpty
            ? (isArabic
                ? 'المركبة ${trip.vehicleLabel}'
                : 'Vehicle ${trip.vehicleLabel}')
            : '',
        state: transitState,
      ),
      _TimelineEvent(
        title: isArabic ? 'الوصول' : 'Arrival',
        timeLabel: _shortTime(j.arrivalAtIso),
        detail: j.to,
        state: arrivalState,
      ),
    ];
  }

  String _shortTime(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return '';
    final l = p.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mn = l.minute.toString().padLeft(2, '0');
    return '$hh:$mn';
  }

  String _durationLabel(DateTime? dep, DateTime? arr,
      {required bool isArabic}) {
    if (dep == null || arr == null) return '';
    final diff = arr.difference(dep);
    final h = diff.inMinutes ~/ 60;
    final m = diff.inMinutes % 60;
    if (isArabic) {
      return h > 0
          ? '${h}س ${m.toString().padLeft(2, '0')}د'
          : '${m}د';
    }
    return h > 0
        ? '${h}h ${m.toString().padLeft(2, '0')}m'
        : '${m}m';
  }
}

enum _TimelineState { upcoming, current, passed }

class _TimelineEvent {
  final String title;
  final String timeLabel;
  final String detail;
  final _TimelineState state;

  const _TimelineEvent({
    required this.title,
    required this.timeLabel,
    required this.detail,
    required this.state,
  });
}
