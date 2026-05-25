// Cycle 257 — Coach crew trip detail page.
//
// The driver/crew's working surface for a single trip. Shows the
// full passenger manifest with seat numbers, boarding state, and a
// big "Scan to board" CTA that opens the full-screen QR scanner
// (`CoachCrewScannerPage`). Also lists the most recent boarding
// events so the crew can see in-flight scans.
//
// We let the crew manually mark a passenger boarded/no-show without
// scanning (e.g. ticket displayed on torn paper, dead phone, etc.).
// Manual capture goes through the same `recordBoarding` API as the
// QR scan — the audit trail records `offline_captured=false` with a
// note such as "manual override".
//
// Refresh:
//   * 15 s background poll (the manifest can change fast right
//     before departure).
//   * Pull-to-refresh.
//   * Auto-refresh after every successful boarding capture (re-uses
//     the trip returned by the boarding response).

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'coach_crew_scanner_page.dart';
import 'coach_mobility_api.dart';
import 'coach_platform_contracts.dart';

class CoachCrewTripDetailPage extends StatefulWidget {
  final String baseUrl;
  final String tripId;

  const CoachCrewTripDetailPage({
    required this.baseUrl,
    required this.tripId,
    super.key,
  });

  @override
  State<CoachCrewTripDetailPage> createState() =>
      _CoachCrewTripDetailPageState();
}

class _CoachCrewTripDetailPageState extends State<CoachCrewTripDetailPage> {
  late final CoachMobilityApi _api;
  CoachCrewManifestResponse? _manifest;
  bool _loading = true;
  String? _error;
  Timer? _poller;
  String? _capturingTicketId;

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 15), (_) {
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
      final manifest = await _api.getCrewManifest(widget.tripId);
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
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
            ? 'تعذّر تحميل قائمة الركاب'
            : 'Could not load the manifest';
      });
    }
  }

  Future<void> _openScanner() async {
    final manifest = _manifest;
    if (manifest == null) return;
    final result = await Navigator.of(context).push<CoachCrewBoardingResult>(
      MaterialPageRoute<CoachCrewBoardingResult>(
        builder: (_) => CoachCrewScannerPage(
          baseUrl: widget.baseUrl,
          tripId: widget.tripId,
          manifest: manifest,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      // Refresh to incorporate any sequence of scans the scanner
      // performed in-place.
      unawaited(_refresh(silent: true));
    }
  }

  Future<void> _quickCapture(
    CoachCrewManifestEntry entry,
    CoachBoardingScanStatus scanStatus, {
    String? note,
  }) async {
    if (_capturingTicketId != null) return;
    setState(() {
      _capturingTicketId = entry.ticket.ticketId;
    });
    try {
      final result = await _api.recordBoarding(
        tripId: widget.tripId,
        ticketId: entry.ticket.ticketId,
        scanStatus: scanStatus,
        offlineCaptured: false,
        note: note,
      );
      if (!mounted) return;
      // We don't have a way to splice a single entry into the
      // manifest list; re-fetch.
      setState(() {
        _capturingTicketId = null;
      });
      unawaited(_refresh(silent: true));
      _showSnack(_friendlyStatusLabel(result.boardingEvent.scanStatus),
          ok: scanStatus == CoachBoardingScanStatus.scanned);
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() => _capturingTicketId = null);
      _showSnack(err.toString(), ok: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _capturingTicketId = null);
      _showSnack(
        L10n.of(context).isArabic ? 'فشل التسجيل' : 'Capture failed',
        ok: false,
      );
    }
  }

  void _showSnack(String message, {required bool ok}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.removeCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _friendlyStatusLabel(CoachBoardingScanStatus status) {
    final isArabic = L10n.of(context).isArabic;
    switch (status) {
      case CoachBoardingScanStatus.scanned:
        return isArabic ? 'تم الصعود' : 'Boarded';
      case CoachBoardingScanStatus.denied:
        return isArabic ? 'تم الرفض' : 'Denied';
      case CoachBoardingScanStatus.duplicate:
        return isArabic ? 'مسح مكرر' : 'Duplicate scan';
      case CoachBoardingScanStatus.revoked:
        return isArabic ? 'تذكرة مُلغاة' : 'Ticket revoked';
      case CoachBoardingScanStatus.noShow:
        return isArabic ? 'لم يحضر' : 'No-show';
    }
  }

  String _shortTime(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return '';
    final l = p.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mn = l.minute.toString().padLeft(2, '0');
    return '$hh:$mn';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    final manifest = _manifest;
    final trip = manifest?.trip;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'تفاصيل الرحلة' : 'Trip detail'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      floatingActionButton: manifest == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(
                isArabic ? 'امسح للصعود' : 'Scan to board',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: _loading && _manifest == null
            ? const Center(child: CircularProgressIndicator())
            : (_error != null && _manifest == null)
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
                    padding:
                        const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: <Widget>[
                      if (trip != null)
                        _tripSummaryCard(
                          trip: trip,
                          theme: theme,
                          isArabic: isArabic,
                        ),
                      const SizedBox(height: 16),
                      _sectionHeader(
                        isArabic ? 'قائمة الركاب' : 'Passenger manifest',
                        trailing:
                            '${manifest!.manifest.length} ${isArabic ? "ركاب" : "pax"}',
                      ),
                      const SizedBox(height: 8),
                      ...manifest.manifest.map(
                        (e) => _passengerCard(
                          entry: e,
                          theme: theme,
                          isArabic: isArabic,
                        ),
                      ),
                      if (manifest.recentEvents.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _sectionHeader(
                            isArabic ? 'آخر العمليات' : 'Recent activity'),
                        const SizedBox(height: 8),
                        ...manifest.recentEvents.take(8).map(
                              (e) => _eventRow(
                                event: e,
                                manifest: manifest,
                                isArabic: isArabic,
                              ),
                            ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _sectionHeader(String label, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: .8,
                color: Colors.black87,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _tripSummaryCard({
    required CoachCrewTripSummary trip,
    required ThemeData theme,
    required bool isArabic,
  }) {
    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                    trip.operatorName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                Text(
                  _shortTime(trip.departureAtIso),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${trip.from} → ${trip.to}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'البوابة: ${trip.gateLabel} · المركبة: ${trip.vehicleLabel}'
                  : 'Gate: ${trip.gateLabel} · Vehicle: ${trip.vehicleLabel}',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _stat(
                  label: isArabic ? 'صعدوا' : 'Boarded',
                  value: trip.boardedCount,
                  total: trip.manifestCount,
                  color: const Color(0xFF388E3C),
                ),
                const SizedBox(width: 8),
                _stat(
                  label: isArabic ? 'انتظار' : 'Pending',
                  value: trip.pendingCount,
                  total: trip.manifestCount,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _stat(
                  label: isArabic ? 'لم يحضروا' : 'No-show',
                  value: trip.noShowCount,
                  total: trip.manifestCount,
                  color: const Color(0xFFE65100),
                ),
                const SizedBox(width: 8),
                _stat(
                  label: isArabic ? 'مرفوض' : 'Denied',
                  value: trip.deniedCount,
                  total: trip.manifestCount,
                  color: const Color(0xFFB71C1C),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat({
    required String label,
    required int value,
    required int total,
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
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: .4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passengerCard({
    required CoachCrewManifestEntry entry,
    required ThemeData theme,
    required bool isArabic,
  }) {
    final p = entry.passenger;
    final stateInfo = _stateChip(entry.boardingState, isArabic: isArabic);
    final isBusy = _capturingTicketId == entry.ticket.ticketId;
    final isBoarded =
        entry.boardingState == CoachManifestBoardingState.boarded;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.seatNumber,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        p.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ticketShortLabel(entry.ticket,
                            isArabic: isArabic),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                stateInfo,
              ],
            ),
            if (entry.needsAttention) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: Color(0xFFE65100)),
                    const SizedBox(width: 4),
                    Text(
                      isArabic ? 'يحتاج مراجعة' : 'Needs attention',
                      style: const TextStyle(
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!isBoarded) ...[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _quickCapture(
                                entry,
                                CoachBoardingScanStatus.scanned,
                                note: 'manual board',
                              ),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 18),
                      label: Text(
                        isArabic ? 'صعود يدوي' : 'Manual board',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _quickCapture(
                                entry,
                                CoachBoardingScanStatus.noShow,
                                note: 'manual no-show',
                              ),
                      icon: const Icon(Icons.do_not_disturb_alt_rounded,
                          size: 18),
                      label: Text(
                        isArabic ? 'لم يحضر' : 'No-show',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (isBusy)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  String _ticketShortLabel(CoachTicketCoupon ticket, {required bool isArabic}) {
    final ref = ticket.operatorTicketReference;
    if (ref != null && ref.isNotEmpty) {
      return isArabic ? 'مرجع: $ref' : 'Ref: $ref';
    }
    final id = ticket.ticketId;
    final short = id.length >= 8 ? id.substring(id.length - 8) : id;
    return isArabic ? 'تذكرة …$short' : 'Ticket …$short';
  }

  Widget _stateChip(CoachManifestBoardingState state,
      {required bool isArabic}) {
    Color bg;
    Color fg;
    String label;
    switch (state) {
      case CoachManifestBoardingState.boarded:
        bg = const Color(0xFF388E3C).withValues(alpha: .14);
        fg = const Color(0xFF1B5E20);
        label = isArabic ? 'صَعِد' : 'Boarded';
        break;
      case CoachManifestBoardingState.notBoarded:
        bg = Colors.grey.withValues(alpha: .14);
        fg = Colors.black54;
        label = isArabic ? 'انتظار' : 'Pending';
        break;
      case CoachManifestBoardingState.denied:
        bg = const Color(0xFFB71C1C).withValues(alpha: .14);
        fg = const Color(0xFFB71C1C);
        label = isArabic ? 'مرفوض' : 'Denied';
        break;
      case CoachManifestBoardingState.duplicateAttempt:
        bg = const Color(0xFFFFA000).withValues(alpha: .14);
        fg = const Color(0xFFE65100);
        label = isArabic ? 'مكرر' : 'Duplicate';
        break;
      case CoachManifestBoardingState.revoked:
        bg = Colors.black.withValues(alpha: .14);
        fg = Colors.black;
        label = isArabic ? 'ملغى' : 'Revoked';
        break;
      case CoachManifestBoardingState.noShow:
        bg = const Color(0xFFE65100).withValues(alpha: .14);
        fg = const Color(0xFFE65100);
        label = isArabic ? 'لم يحضر' : 'No-show';
        break;
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

  Widget _eventRow({
    required CoachBoardingEvent event,
    required CoachCrewManifestResponse manifest,
    required bool isArabic,
  }) {
    // Resolve the passenger row this event belongs to so we can show
    // a human name instead of a ticket ID.
    String displayName = '';
    String seat = '';
    for (final entry in manifest.manifest) {
      if (entry.ticket.ticketId == event.ticketId) {
        displayName = entry.passenger.displayName;
        seat = entry.seatNumber;
        break;
      }
    }
    final label = _friendlyStatusLabel(event.scanStatus);
    final t = _shortTime(event.capturedAtIso);
    Color color;
    IconData icon;
    switch (event.scanStatus) {
      case CoachBoardingScanStatus.scanned:
        color = const Color(0xFF388E3C);
        icon = Icons.check_circle_rounded;
        break;
      case CoachBoardingScanStatus.denied:
        color = const Color(0xFFB71C1C);
        icon = Icons.cancel_rounded;
        break;
      case CoachBoardingScanStatus.duplicate:
        color = const Color(0xFFE65100);
        icon = Icons.error_rounded;
        break;
      case CoachBoardingScanStatus.revoked:
        color = Colors.black;
        icon = Icons.block_rounded;
        break;
      case CoachBoardingScanStatus.noShow:
        color = const Color(0xFFE65100);
        icon = Icons.do_not_disturb_on_rounded;
        break;
    }
    final detailParts = <String>[
      if (seat.isNotEmpty) (isArabic ? 'مقعد $seat' : 'Seat $seat'),
      if (displayName.isNotEmpty) displayName,
    ];
    final detail = detailParts.isEmpty
        ? (isArabic ? 'تذكرة …${_shortTicketId(event.ticketId)}' : 'Ticket …${_shortTicketId(event.ticketId)}')
        : detailParts.join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$label · $detail',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            t,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _shortTicketId(String id) =>
      id.length >= 6 ? id.substring(id.length - 6) : id;
}
