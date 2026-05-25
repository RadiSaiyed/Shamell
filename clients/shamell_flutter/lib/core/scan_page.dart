import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'l10n.dart';
import 'media_access_policy.dart';
import 'shamell_ui.dart';

class ScanPage extends StatefulWidget {
  final bool? allowManualEntry;

  const ScanPage({super.key, this.allowManualEntry});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _torchOn = false;
  bool _popped = false;

  bool get _allowManualEntry => widget.allowManualEntry ?? !kReleaseMode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (!mounted) return;
      setState(() {
        _torchOn = !_torchOn;
      });
    } catch (_) {}
  }

  void _submitScanValue(String raw) {
    final normalized = raw.trim();
    if (_popped || normalized.isEmpty || !mounted) return;
    _popped = true;
    Navigator.pop(context, normalized);
  }

  Future<void> _openManualEntrySheet() async {
    if (!_allowManualEntry || _popped) return;
    try {
      await _controller.stop();
    } catch (_) {}
    final raw = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ScanManualEntrySheet(
          onSubmit: (value) => Navigator.pop(sheetContext, value),
        );
      },
    );
    try {
      await _controller.start();
    } catch (_) {}
    if (raw == null) return;
    _submitScanValue(raw);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final cameraAllowed = shamellAllowsCameraCapture();
    final manualEntryAction = _allowManualEntry
        ? IconButton(
            tooltip: l.isArabic ? 'إدخال الرمز يدويًا' : 'Enter code manually',
            icon: const Icon(Icons.keyboard_alt_outlined),
            onPressed: _openManualEntrySheet,
          )
        : null;
    if (!cameraAllowed) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(l.isArabic ? 'مسح رمز QR' : 'Scan QR'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (manualEntryAction != null) manualEntryAction,
          ],
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  if (_allowManualEntry) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openManualEntrySheet,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: Text(
                        l.isArabic
                            ? 'إدخال الرمز يدويًا'
                            : 'Enter code manually',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .24),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l.isArabic ? 'مسح رمز QR' : 'Scan QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'المصباح' : 'Torch',
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleTorch,
          ),
          if (manualEntryAction != null) manualEntryAction,
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_popped) return;
              final codes = capture.barcodes;
              if (codes.isEmpty) return;
              final raw = codes.first.rawValue;
              if (raw == null || raw.isEmpty) return;
              _submitScanValue(raw);
            },
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: _ScannerOverlay(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    l.isArabic
                        ? 'ضع رمز QR داخل الإطار للمسح'
                        : 'Align the QR code within the frame to scan',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .14),
                      ),
                    ),
                    child: Text(
                      l.isArabic ? 'يدعم QR وباركود' : 'Supports QR & barcodes',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (_allowManualEntry) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openManualEntrySheet,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: Text(
                        l.isArabic
                            ? 'إدخال الرمز يدويًا'
                            : 'Enter code manually',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .24),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanManualEntrySheet extends StatefulWidget {
  final ValueChanged<String> onSubmit;

  const ScanManualEntrySheet({super.key, required this.onSubmit});

  @override
  State<ScanManualEntrySheet> createState() => _ScanManualEntrySheetState();
}

class _ScanManualEntrySheetState extends State<ScanManualEntrySheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty || !mounted) return;
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    } catch (_) {}
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    widget.onSubmit(raw);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isArabic ? 'استيراد الرمز يدويًا' : 'Manual scan import',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  isArabic
                      ? 'ألصق حمولة QR أو الرابط أو رقم المحفظة أو @alias.'
                      : 'Paste a QR payload, link, wallet ID, or @alias.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'الرمز أو الرابط' : 'Code or link',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_go_outlined),
                      label: Text(isArabic ? 'لصق' : 'Paste'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(isArabic ? 'إلغاء' : 'Cancel'),
                    ),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(isArabic ? 'استخدام الرمز' : 'Use code'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cutOut = (w < h ? w : h) * 0.62;
        return CustomPaint(
          painter: _ScannerOverlayPainter(cutOutSize: cutOut),
          size: Size(w, h),
        );
      },
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double cutOutSize;
  _ScannerOverlayPainter({required this.cutOutSize});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: .55);
    final borderPaint = Paint()
      ..color = ShamellPalette.green.withValues(alpha: .95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 28),
      width: cutOutSize,
      height: cutOutSize,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Draw SyrChat-like corner brackets.
    const corner = 22.0;
    const inset = 8.0;
    final left = rect.left + inset;
    final right = rect.right - inset;
    final top = rect.top + inset;
    final bottom = rect.bottom - inset;

    void cornerLine(Offset a, Offset b) => canvas.drawLine(a, b, borderPaint);

    // Top-left
    cornerLine(Offset(left, top + corner), Offset(left, top));
    cornerLine(Offset(left, top), Offset(left + corner, top));
    // Top-right
    cornerLine(Offset(right - corner, top), Offset(right, top));
    cornerLine(Offset(right, top), Offset(right, top + corner));
    // Bottom-left
    cornerLine(Offset(left, bottom - corner), Offset(left, bottom));
    cornerLine(Offset(left, bottom), Offset(left + corner, bottom));
    // Bottom-right
    cornerLine(Offset(right - corner, bottom), Offset(right, bottom));
    cornerLine(Offset(right, bottom), Offset(right, bottom - corner));
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.cutOutSize != cutOutSize;
  }
}
