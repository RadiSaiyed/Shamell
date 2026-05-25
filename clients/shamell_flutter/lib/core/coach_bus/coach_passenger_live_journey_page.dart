// Cycle 222 — Coach Bus live journey page.
//
// Polls /me/coach/journeys/:id/live every 30s while the rider has
// the page open. Renders:
//   * Journey summary (operator, route, scheduled vs delay)
//   * Feed-freshness chips (trip updates / vehicle positions /
//     service alerts) so the rider knows whether the data is fresh
//   * Ticket details (ticket id + barcode-style monospace)
//   * Recent boarding events (last few status transitions)

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'coach_disruption_broadcast_api.dart';
import 'coach_journey_rating_api.dart';
import 'coach_journey_rating_dialog.dart';
import 'coach_journey_timeline.dart';
import 'coach_mobility_api.dart';
import 'coach_safety_alerts_api.dart';
import 'coach_share_api.dart';
import 'coach_share_dialog.dart';
import 'coach_sos_dialog.dart';

class CoachPassengerLiveJourneyPage extends StatefulWidget {
  final String baseUrl;
  final String bookingId;
  final String journeyId;

  const CoachPassengerLiveJourneyPage({
    required this.baseUrl,
    required this.bookingId,
    required this.journeyId,
    super.key,
  });

  @override
  State<CoachPassengerLiveJourneyPage> createState() =>
      _CoachPassengerLiveJourneyPageState();
}

class _CoachPassengerLiveJourneyPageState
    extends State<CoachPassengerLiveJourneyPage> {
  late final CoachMobilityApi _api;
  late final CoachDisruptionBroadcastApi _noticeApi;
  CoachJourneyLiveResponse? _live;
  // Cycle 262 — operator-published notices for this journey.
  List<CoachDisruptionBroadcast> _notices = const <CoachDisruptionBroadcast>[];
  bool _loading = true;
  String? _error;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
    _noticeApi = CoachDisruptionBroadcastApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
    unawaited(_refreshNotices());
    _poller = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refresh(silent: true));
      unawaited(_refreshNotices());
    });
  }

  /// Cycle 262 — pull active operator notices for the journey. The
  /// API quietly returns an empty list on failure so a stale BFF
  /// route doesn't break the live page.
  Future<void> _refreshNotices() async {
    if (!mounted) return;
    try {
      final list = await _noticeApi.listJourneyNotices(widget.journeyId);
      if (!mounted) return;
      setState(() => _notices = list.broadcasts);
    } catch (_) {
      // Soft-fail: the live page still renders without notices.
    }
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
      final live = await _api.getJourneyLive(widget.journeyId);
      if (!mounted) return;
      setState(() {
        _live = live;
        _loading = false;
        _error = null;
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
            ? 'تعذّر تحميل الرحلة'
            : 'Could not load live journey';
      });
    }
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

  /// Cycle 245 — open the coach share dialog. Mints a fresh
  /// 12 h token on open and hands it to native-share / copy.
  Future<void> _openShareDialog(CoachJourneyLiveResponse live) async {
    if (!mounted) return;
    final api = CoachShareApi(baseUrl: widget.baseUrl);
    await showCoachShareDialog(
      context: context,
      api: api,
      journeyId: widget.journeyId,
      bookingId: widget.bookingId,
      operatorId: live.offer.operatorId,
      isArabic: L10n.of(context).isArabic,
    );
  }

  /// Cycle 237 — open the coach SOS confirmation dialog. The
  /// rider holds for 3s to dispatch; the alert lands in the
  /// operator queue with the rider's last-known coords.
  Future<void> _openSosDialog(CoachJourneyLiveResponse live) async {
    if (!mounted) return;
    final api = CoachSafetyAlertsApi(baseUrl: widget.baseUrl);
    final alert = await showCoachSosConfirmDialog(
      context: context,
      api: api,
      journeyId: widget.journeyId,
      bookingId: widget.bookingId,
      operatorId: live.offer.operatorId,
      isArabic: L10n.of(context).isArabic,
    );
    if (alert != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 6),
          content: Text(
            L10n.of(context).isArabic
                ? 'تم إرسال الإنذار. ستتلقى مكالمة قريباً.'
                : 'SOS dispatched — operations will contact you shortly.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  /// Cycle 230 — open the post-journey rating dialog. The rider
  /// can rate at any time once they have a journey context (the
  /// AppBar action stays visible). The BFF upserts on (journey,
  /// rider) so a re-tap edits the existing rating.
  Future<void> _openRatingDialog(CoachJourneyLiveResponse live) async {
    if (!mounted) return;
    final api = CoachJourneyRatingApi(baseUrl: widget.baseUrl);
    final saved = await showCoachJourneyRatingDialog(
      context: context,
      api: api,
      journeyId: widget.journeyId,
      bookingId: widget.bookingId,
      operatorId: live.offer.operatorId,
      operatorDisplayName: live.journey.operatorName,
      isArabic: L10n.of(context).isArabic,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF388E3C),
          content: Text(
            L10n.of(context).isArabic
                ? 'شكراً على تقييمك!'
                : 'Thanks for rating your journey!',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    final live = _live;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'تتبع الرحلة' : 'Live journey'),
        actions: <Widget>[
          if (live != null)
            IconButton(
              tooltip: isArabic ? 'SOS' : 'SOS',
              icon: Icon(Icons.shield_rounded,
                  color: theme.colorScheme.error),
              onPressed: () => _openSosDialog(live),
            ),
          if (live != null)
            IconButton(
              tooltip: isArabic ? 'مشاركة الرحلة' : 'Share journey',
              icon: const Icon(Icons.share_location_rounded),
              onPressed: () => _openShareDialog(live),
            ),
          if (live != null)
            IconButton(
              tooltip: isArabic ? 'قيّم الرحلة' : 'Rate journey',
              icon: const Icon(Icons.star_rate_rounded),
              onPressed: () => _openRatingDialog(live),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: _loading && live == null
            ? const Center(child: CircularProgressIndicator())
            : (live == null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error ?? (isArabic ? 'لا توجد بيانات' : 'No data'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: <Widget>[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                live.journey.operatorName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${live.journey.from} → ${live.journey.to}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: <Widget>[
                                  Icon(Icons.event_outlined,
                                      size: 16, color: Colors.black54),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_fmtIso(live.journey.departureAtIso)} → ${_fmtIso(live.journey.arrivalAtIso)}',
                                    style: const TextStyle(
                                        color: Colors.black54),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _statusBanner(live, isArabic: isArabic,
                                  theme: theme),
                            ],
                          ),
                        ),
                      ),
                      // Cycle 262 — operator notices (delays, route
                      // changes). Shown immediately under the status
                      // banner so riders see them before everything
                      // else. Hidden when there are no active notices.
                      if (_notices.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _noticesPanel(isArabic: isArabic),
                      ],
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CoachJourneyTimeline(live: live),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _feedFreshness(live, isArabic: isArabic),
                      const SizedBox(height: 12),
                      _ticketsCard(live, isArabic: isArabic),
                      const SizedBox(height: 12),
                      _eventsCard(live, isArabic: isArabic),
                    ],
                  ),
      ),
    );
  }

  /// Cycle 262 — render operator notices stacked, severity-coloured.
  /// Most-recent first (the API already sorts that way).
  Widget _noticesPanel({required bool isArabic}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            isArabic ? 'بلاغات المشغّل' : 'Operator notices',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              letterSpacing: .6,
              color: Colors.black54,
            ),
          ),
        ),
        for (final notice in _notices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _noticeBanner(notice, isArabic: isArabic),
          ),
      ],
    );
  }

  Widget _noticeBanner(CoachDisruptionBroadcast notice,
      {required bool isArabic}) {
    Color bg;
    Color fg;
    IconData icon;
    switch (notice.severity) {
      case CoachDisruptionSeverity.info:
        bg = const Color(0xFF1976D2).withValues(alpha: .10);
        fg = const Color(0xFF0D47A1);
        icon = Icons.info_outline_rounded;
        break;
      case CoachDisruptionSeverity.warning:
        bg = const Color(0xFFE65100).withValues(alpha: .12);
        fg = const Color(0xFFBF360C);
        icon = Icons.warning_amber_rounded;
        break;
      case CoachDisruptionSeverity.critical:
        bg = const Color(0xFFB71C1C).withValues(alpha: .14);
        fg = const Color(0xFFB71C1C);
        icon = Icons.report_problem_rounded;
        break;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: .35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  notice.headline,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                if (notice.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      notice.body,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
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

  Widget _statusBanner(CoachJourneyLiveResponse live,
      {required bool isArabic, required ThemeData theme}) {
    // The journey summary carries the human-readable status
    // ("On schedule", "Boarding", "Departed", …); the trip summary
    // is operator-side counters (boarded/denied/no-show) which we
    // skip on the rider surface.
    final raw = live.journey.statusLabel;
    Color bg;
    Color fg;
    final lowered = raw.toLowerCase();
    if (lowered.contains('cancel') || lowered.contains('canceled')) {
      bg = Theme.of(context).colorScheme.error.withValues(alpha: .12);
      fg = Theme.of(context).colorScheme.error;
    } else {
      bg = const Color(0xFF388E3C).withValues(alpha: .12);
      fg = const Color(0xFF1B5E20);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        raw,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _feedFreshness(CoachJourneyLiveResponse live,
      {required bool isArabic}) {
    // Operator feed health is reported per (operator, feed_kind)
    // tuple — group by feed_kind so the rider sees one chip per
    // data category instead of one per operator.
    final feeds = live.operatorFeedHealth;
    if (feeds.isEmpty) {
      return const SizedBox.shrink();
    }
    bool _allFresh(String kind) {
      final relevant = feeds.where((f) => f.feedKind == kind);
      if (relevant.isEmpty) return false;
      return relevant.every((f) => f.isFresh);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isArabic ? 'صحة بيانات النقل' : 'Live data freshness',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _freshChip(
                  label: isArabic ? 'تحديثات الرحلة' : 'Trip updates',
                  fresh: _allFresh('trip_updates'),
                ),
                _freshChip(
                  label: isArabic ? 'مواقع المركبة' : 'Vehicle positions',
                  fresh: _allFresh('vehicle_positions'),
                ),
                _freshChip(
                  label: isArabic ? 'إشعارات الخدمة' : 'Service alerts',
                  fresh: _allFresh('service_alerts'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _freshChip({required String label, required bool fresh}) {
    final color = fresh ? const Color(0xFF388E3C) : const Color(0xFFE65100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            fresh ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticketsCard(CoachJourneyLiveResponse live,
      {required bool isArabic}) {
    if (live.tickets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isArabic ? 'التذاكر' : 'Tickets',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...live.tickets.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SelectableText(
                          t.ticketId,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.status.toString().split('.').last,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _eventsCard(CoachJourneyLiveResponse live,
      {required bool isArabic}) {
    if (live.recentEvents.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isArabic ? 'أحداث حديثة' : 'Recent events',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...live.recentEvents.take(8).map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.circle, size: 8, color: Colors.black38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              e.scanStatus.toString().split('.').last,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              _fmtIso(e.capturedAtIso),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
