// Cycle 247 — Coach boarding pass page.
//
// The full-screen, dark, ticket-shaped surface a passenger pulls
// up at the boarding gate. Designed to be the most visually
// premium thing in the Coach product. It carries everything the
// crew needs to scan + everything the passenger needs to know:
//
//   * Operator name + journey route
//   * Departure schedule with relative ETA
//   * Gate + Vehicle + Seat assignments per passenger
//   * Big scannable QR per passenger (one ticket coupon = one QR)
//   * Pass swipe-between-passengers for multi-passenger bookings
//   * Boarding-state pill (e.g. "BOARDING OPEN")
//
// We deliberately set system UI to dark + lock orientation to
// portrait while the pass is showing — it's a piece-of-paper
// equivalent and shouldn't reflow.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import 'coach_mobility_api.dart';
import 'coach_platform_contracts.dart';

class CoachBoardingPassPage extends StatefulWidget {
  final String baseUrl;
  final String bookingId;
  final String journeyId;
  // Optional API override — production builds construct one from baseUrl;
  // widget tests pass a fake so fetchTicketArtifactBytes can be stubbed.
  final CoachMobilityApi? api;

  const CoachBoardingPassPage({
    required this.baseUrl,
    required this.bookingId,
    required this.journeyId,
    this.api,
    super.key,
  });

  @override
  State<CoachBoardingPassPage> createState() => _CoachBoardingPassPageState();
}

class _CoachBoardingPassPageState extends State<CoachBoardingPassPage> {
  late final CoachMobilityApi _api;
  CoachJourneyLiveResponse? _live;
  bool _loading = true;
  String? _error;
  Timer? _poller;
  final PageController _pageCtrl = PageController();
  int _currentIndex = 0;
  // Artifact id currently being downloaded → spinner on the button.
  String? _busyArtifactId;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
    // Lock to portrait while the pass is visible — gate scanners
    // love a bright vertical screen and the pass shouldn't reflow.
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _pageCtrl.dispose();
    // Restore orientation freedom on exit.
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitDown,
    ]);
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
            ? 'تعذّر تحميل بطاقة الصعود'
            : 'Could not load the boarding pass';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final live = _live;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(isArabic ? 'بطاقة الصعود' : 'Boarding pass'),
        actions: <Widget>[
          IconButton(
            tooltip: isArabic ? 'تحديث' : 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      body: _loading && live == null
          ? const Center(child: CircularProgressIndicator())
          : live == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _error ?? (isArabic ? 'لا توجد بيانات' : 'No data'),
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _renderPass(live, isArabic: isArabic),
    );
  }

  Widget _renderPass(CoachJourneyLiveResponse live,
      {required bool isArabic}) {
    final tickets = live.tickets;
    if (tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isArabic
                ? 'لم يتم إصدار التذاكر بعد. يرجى التحقق من حالة الحجز.'
                : 'Tickets have not been issued yet. Check your booking status.',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // The manifest list tells us the passenger names; tickets are
    // keyed by passenger_id. Map by passenger_id so the right name
    // shows on the right coupon.
    final manifestByPassengerId = <String, CoachPassengerManifest>{
      for (final m in live.passengerManifests) m.passengerId: m,
    };
    return Column(
      children: <Widget>[
        // Journey hero
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.directions_bus_filled_rounded,
                      color: Colors.amber.shade400, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      live.journey.operatorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  _statusPill(live.journey.statusLabel,
                      isArabic: isArabic),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${live.journey.from} → ${live.journey.to}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _fmtSchedule(live.journey.departureAtIso,
                    live.journey.arrivalAtIso),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .65),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: tickets.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (ctx, i) {
              final t = tickets[i];
              final m = manifestByPassengerId[t.passengerId];
              return _passCoupon(
                ticket: t,
                manifest: m,
                trip: live.trip,
                isArabic: isArabic,
              );
            },
          ),
        ),
        if (tickets.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < tickets.length; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: _currentIndex == i
                          ? Colors.white
                          : Colors.white.withValues(alpha: .25),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statusPill(String label, {required bool isArabic}) {
    final lowered = label.toLowerCase();
    Color bg;
    Color fg;
    if (lowered.contains('cancel')) {
      bg = const Color(0xFFD32F2F);
      fg = Colors.white;
    } else if (lowered.contains('board')) {
      bg = const Color(0xFFFFA000);
      fg = Colors.white;
    } else {
      bg = const Color(0xFF34D399);
      fg = const Color(0xFF064E3B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          color: fg,
          letterSpacing: .6,
        ),
      ),
    );
  }

  Widget _passCoupon({
    required CoachTicketCoupon ticket,
    CoachPassengerManifest? manifest,
    required CoachCrewTripSummary trip,
    required bool isArabic,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF1A1D23),
              Color(0xFF111419),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: Colors.white.withValues(alpha: .08)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: .35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: <Widget>[
            // Passenger header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          isArabic ? 'الراكب' : 'Passenger',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .55),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          manifest?.displayName ??
                              (isArabic ? 'راكب' : 'Passenger'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: .35)),
                    ),
                    child: Text(
                      ticket.status.toString().split('.').last.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFFFC107),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Detail grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: <Widget>[
                  Expanded(child: _fact(isArabic ? 'البوابة' : 'Gate', trip.gateLabel)),
                  Expanded(
                      child: _fact(isArabic ? 'المركبة' : 'Vehicle',
                          trip.vehicleLabel)),
                  Expanded(
                      child:
                          _fact(isArabic ? 'القسيمة' : 'Coupon',
                              '#${ticket.couponId.length > 6 ? ticket.couponId.substring(ticket.couponId.length - 6) : ticket.couponId}')),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: _DashedDivider(),
            ),
            // QR area
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: QrImageView(
                          data: _qrPayload(ticket),
                          version: QrVersions.auto,
                          size: 220,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF111419),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF111419),
                          ),
                          gapless: false,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isArabic
                            ? 'اعرض رمز QR لطاقم الصعود'
                            : 'Show this code to the boarding crew',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .55),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ticketArtifactActions(ticket, isArabic),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isArabic ? 'معرّف التذكرة' : 'Ticket ID',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .55),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    ticket.ticketId,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .50),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '—' : value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  String _qrPayload(CoachTicketCoupon t) {
    // Prefer the server-issued QR payload reference. If absent
    // (older issuance), fall back to a self-describing payload so
    // the gate scanner still gets a valid handle.
    final ref = (t.qrPayloadRef ?? '').trim();
    if (ref.isNotEmpty) return ref;
    return 'shamell-coach:${t.ticketId}:${t.couponId}';
  }

  Widget _ticketArtifactActions(CoachTicketCoupon ticket, bool isArabic) {
    final wallet = ticket.artifactByKind('wallet_pass');
    final pdf = ticket.artifactByKind('pdf');
    if (wallet == null && pdf == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (wallet != null)
          _artifactButton(
            artifact: wallet,
            icon: Icons.account_balance_wallet_outlined,
            label: isArabic ? 'إضافة إلى المحفظة' : 'Add to Wallet',
          ),
        if (wallet != null && pdf != null) const SizedBox(width: 14),
        if (pdf != null)
          _artifactButton(
            artifact: pdf,
            icon: Icons.picture_as_pdf_outlined,
            label: isArabic ? 'تحميل PDF' : 'Download PDF',
          ),
      ],
    );
  }

  Widget _artifactButton({
    required CoachTicketArtifact artifact,
    required IconData icon,
    required String label,
  }) {
    final isBusy = _busyArtifactId == artifact.artifactId;
    return TextButton.icon(
      onPressed: isBusy ? null : () => unawaited(_shareArtifact(artifact)),
      icon: isBusy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(icon, size: 18, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  Future<void> _shareArtifact(CoachTicketArtifact artifact) async {
    setState(() => _busyArtifactId = artifact.artifactId);
    try {
      final bytes = await _api.fetchTicketArtifactBytes(artifact);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${artifact.fileName}');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: artifact.mimeType)],
        subject: artifact.fileName,
      );
    } on CoachApiException catch (err) {
      if (!mounted) return;
      final isArabic = L10n.of(context).isArabic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تعذّر تنزيل البطاقة: ${err.detail}'
                : 'Could not download the ticket: ${err.detail}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final isArabic = L10n.of(context).isArabic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic ? 'حدث خطأ غير متوقّع' : 'Something went wrong',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyArtifactId = null);
      }
    }
  }

  String _fmtSchedule(String depIso, String arrIso) {
    final dep = DateTime.tryParse(depIso);
    final arr = DateTime.tryParse(arrIso);
    if (dep == null || arr == null) {
      return '$depIso → $arrIso';
    }
    final l = dep.toLocal();
    final a = arr.toLocal();
    String fmt(DateTime t) =>
        '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${fmt(l)} → ${fmt(a)}';
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      const dash = 6.0;
      const gap = 4.0;
      final count = (constraints.maxWidth / (dash + gap)).floor();
      return Row(
        children: List<Widget>.generate(count, (_) {
          return Padding(
            padding: const EdgeInsets.only(right: gap),
            child: Container(
              width: dash,
              height: 1.2,
              color: Colors.white.withValues(alpha: .18),
            ),
          );
        }),
      );
    });
  }
}
