// Cycle 256 — Coach crew full-screen QR scanner.
//
// Pure scanning surface that runs continuously (unlike the
// generic ScanPage which pops on first hit). The crew can scan a
// queue of passengers without re-opening the camera.
//
// QR resolution priority:
//   1. raw == ticket.qrPayloadRef   → match by stable server ref
//   2. raw matches  `shamell-coach:<ticketId>:<couponId>` (the
//      fallback format the boarding pass renders when the server
//      hasn't issued a payload ref yet)
//   3. raw matches a ticket's `ticketId` outright
//   4. otherwise: unrecognised — show a "ticket not on this trip"
//      flash and keep scanning.
//
// Debouncer: a given ticket can only be re-scanned every 4s. This
// prevents the camera firing 30 boardings for the same code while
// the passenger fumbles past the gate.
//
// Returns the most recent `CoachCrewBoardingResult` on pop, so the
// detail page can refresh.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n.dart';
import '../media_access_policy.dart';
import 'coach_mobility_api.dart';
import 'coach_platform_contracts.dart';

class CoachCrewScannerPage extends StatefulWidget {
  final String baseUrl;
  final String tripId;
  final CoachCrewManifestResponse manifest;

  const CoachCrewScannerPage({
    required this.baseUrl,
    required this.tripId,
    required this.manifest,
    super.key,
  });

  @override
  State<CoachCrewScannerPage> createState() => _CoachCrewScannerPageState();
}

class _CoachCrewScannerPageState extends State<CoachCrewScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  late final CoachMobilityApi _api;

  bool _torchOn = false;
  bool _busy = false;
  String? _lastTicketId;
  DateTime? _lastTicketAt;

  // Last result overlay state.
  _ScanFlash? _flash;
  Timer? _flashTimer;

  // Live counter so the user can see throughput at a glance.
  int _successCount = 0;
  int _denyCount = 0;

  CoachCrewBoardingResult? _lastSuccess;

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  CoachCrewManifestEntry? _resolveScan(String raw) {
    final normalised = raw.trim();
    if (normalised.isEmpty) return null;
    // 1. Match by qrPayloadRef.
    for (final entry in widget.manifest.manifest) {
      final ref = entry.ticket.qrPayloadRef;
      if (ref != null && ref.isNotEmpty && ref == normalised) {
        return entry;
      }
    }
    // 2. Parse `shamell-coach:<ticketId>:<couponId>`.
    if (normalised.startsWith('shamell-coach:')) {
      final parts = normalised.split(':');
      if (parts.length >= 2) {
        final ticketId = parts[1].trim();
        if (ticketId.isNotEmpty) {
          for (final entry in widget.manifest.manifest) {
            if (entry.ticket.ticketId == ticketId) {
              return entry;
            }
          }
        }
      }
    }
    // 3. Match by raw ticket id.
    for (final entry in widget.manifest.manifest) {
      if (entry.ticket.ticketId == normalised) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    await _handleRawCode(code);
  }

  Future<void> _handleRawCode(String code) async {
    if (_busy) return;
    if (code.trim().isEmpty) return;
    // De-bounce by ticket id: if the camera fires the same code
    // multiple times within 4 seconds, ignore subsequent reads.
    final entry = _resolveScan(code);
    if (entry == null) {
      _showFlash(
        _ScanFlash(
          color: const Color(0xFFB71C1C),
          icon: Icons.help_outline_rounded,
          title: L10n.of(context).isArabic
              ? 'تذكرة غير معروفة'
              : 'Ticket not on this trip',
          subtitle: _shortCode(code),
        ),
      );
      return;
    }
    final ticketId = entry.ticket.ticketId;
    final now = DateTime.now();
    if (_lastTicketId == ticketId &&
        _lastTicketAt != null &&
        now.difference(_lastTicketAt!) < const Duration(seconds: 4)) {
      // Same ticket within debounce window — ignore.
      return;
    }
    _lastTicketId = ticketId;
    _lastTicketAt = now;

    // Decide which scan_status to send. If the manifest says the
    // ticket is already boarded → send "duplicate" so the server can
    // record the second tap without flipping the state.
    final CoachBoardingScanStatus scanStatus =
        entry.boardingState == CoachManifestBoardingState.boarded
            ? CoachBoardingScanStatus.duplicate
            : CoachBoardingScanStatus.scanned;

    setState(() => _busy = true);
    try {
      final result = await _api.recordBoarding(
        tripId: widget.tripId,
        ticketId: ticketId,
        scanStatus: scanStatus,
        offlineCaptured: false,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastSuccess = result;
      });
      final isArabic = L10n.of(context).isArabic;
      final eventStatus = result.boardingEvent.scanStatus;
      final passengerName =
          result.manifestEntry.passenger.displayName;
      final seat = result.manifestEntry.seatNumber;
      switch (eventStatus) {
        case CoachBoardingScanStatus.scanned:
          _successCount++;
          _showFlash(
            _ScanFlash(
              color: const Color(0xFF1B5E20),
              icon: Icons.check_circle_rounded,
              title: isArabic ? 'تم الصعود' : 'Boarded',
              subtitle: isArabic
                  ? 'مقعد $seat · $passengerName'
                  : 'Seat $seat · $passengerName',
            ),
          );
          break;
        case CoachBoardingScanStatus.duplicate:
          _denyCount++;
          _showFlash(
            _ScanFlash(
              color: const Color(0xFFE65100),
              icon: Icons.error_rounded,
              title: isArabic ? 'مسح مكرر' : 'Already boarded',
              subtitle: isArabic
                  ? 'مقعد $seat · $passengerName'
                  : 'Seat $seat · $passengerName',
            ),
          );
          break;
        case CoachBoardingScanStatus.denied:
          _denyCount++;
          _showFlash(
            _ScanFlash(
              color: const Color(0xFFB71C1C),
              icon: Icons.cancel_rounded,
              title: isArabic ? 'مرفوض' : 'Denied',
              subtitle: passengerName,
            ),
          );
          break;
        case CoachBoardingScanStatus.revoked:
          _denyCount++;
          _showFlash(
            _ScanFlash(
              color: Colors.black87,
              icon: Icons.block_rounded,
              title: isArabic ? 'تذكرة مُلغاة' : 'Ticket revoked',
              subtitle: passengerName,
            ),
          );
          break;
        case CoachBoardingScanStatus.noShow:
          _denyCount++;
          _showFlash(
            _ScanFlash(
              color: const Color(0xFFE65100),
              icon: Icons.do_not_disturb_rounded,
              title: isArabic ? 'لم يحضر' : 'No-show',
              subtitle: passengerName,
            ),
          );
          break;
      }
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFlash(
        _ScanFlash(
          color: const Color(0xFFB71C1C),
          icon: Icons.error_outline_rounded,
          title: L10n.of(context).isArabic ? 'خطأ' : 'Error',
          subtitle: err.toString(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFlash(
        _ScanFlash(
          color: const Color(0xFFB71C1C),
          icon: Icons.error_outline_rounded,
          title: L10n.of(context).isArabic ? 'فشل' : 'Failed',
          subtitle: '',
        ),
      );
    }
  }

  void _showFlash(_ScanFlash flash) {
    setState(() => _flash = flash);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _flash = null);
    });
  }

  String _shortCode(String raw) {
    if (raw.length <= 28) return raw;
    return '${raw.substring(0, 12)}…${raw.substring(raw.length - 12)}';
  }

  Future<void> _manualEntry() async {
    final isArabic = L10n.of(context).isArabic;
    try {
      await _controller.stop();
    } catch (_) {}
    final controller = TextEditingController();
    final entered = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1D23),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isArabic ? 'إدخال يدوي' : 'Manual entry',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: isArabic
                      ? 'الصق محتوى رمز QR أو معرّف التذكرة'
                      : 'Paste QR payload or ticket id',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: .5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                      sheetContext, controller.text.trim()),
                  child: Text(isArabic ? 'بحث' : 'Look up'),
                ),
              ),
            ],
          ),
        );
      },
    );
    try {
      await _controller.start();
    } catch (_) {}
    final code = (entered ?? '').trim();
    if (code.isEmpty) return;
    await _handleRawCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final cameraAllowed = shamellAllowsCameraCapture();
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_lastSuccess);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            isArabic ? 'مسح الصعود' : 'Board scanner',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: <Widget>[
            if (cameraAllowed)
              IconButton(
                tooltip: isArabic ? 'المصباح' : 'Torch',
                icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                onPressed: _toggleTorch,
              ),
            IconButton(
              tooltip: isArabic ? 'إدخال يدوي' : 'Manual entry',
              icon: const Icon(Icons.keyboard_alt_outlined),
              onPressed: _manualEntry,
            ),
          ],
        ),
        body: cameraAllowed
            ? _buildCameraSurface(isArabic: isArabic)
            : _buildCameraDeniedSurface(isArabic: isArabic),
      ),
    );
  }

  Widget _buildCameraDeniedSurface({required bool isArabic}) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 42,
              ),
              const SizedBox(height: 16),
              Text(
                shamellRestrictedMediaMessage(
                  context,
                  camera: true,
                  microphone: false,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.keyboard_alt_outlined),
                label: Text(
                  isArabic ? 'إدخال يدوي' : 'Manual entry',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: .24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraSurface({required bool isArabic}) {
    return Stack(
      children: <Widget>[
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),
        // Reticle.
        const Positioned.fill(
          child: IgnorePointer(
            child: _CrewScannerReticle(),
          ),
        ),
        // Top counter strip.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  _counterChip(
                    icon: Icons.check_circle_rounded,
                    label: isArabic ? 'صَعِد' : 'Boarded',
                    value: _successCount,
                    color: const Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 8),
                  _counterChip(
                    icon: Icons.error_rounded,
                    label: isArabic ? 'تحفظ' : 'Held',
                    value: _denyCount,
                    color: const Color(0xFFE65100),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Flash banner.
        if (_flash != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 28,
            child: _FlashBanner(flash: _flash!),
          ),
        // Hint text only while no banner is showing.
        if (_flash == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                isArabic
                    ? 'وجّه الكاميرا إلى رمز QR على بطاقة الصعود'
                    : 'Point the camera at the QR on the boarding pass',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x55000000),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _counterChip({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .6), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFlash {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;

  const _ScanFlash({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _FlashBanner extends StatelessWidget {
  final _ScanFlash flash;
  const _FlashBanner({required this.flash});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: flash.color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: .35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Icon(flash.icon, color: Colors.white, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    flash.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: .2,
                    ),
                  ),
                  if (flash.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        flash.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .9),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
}

class _CrewScannerReticle extends StatelessWidget {
  const _CrewScannerReticle();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final size = box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight;
        final side = (size * 0.62).clamp(180.0, 320.0);
        return Center(
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: .7),
                width: 2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: .45),
                  blurRadius: 24,
                  spreadRadius: 800,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
