import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'l10n.dart';
import 'wechat_ui.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _torchOn = false;
  bool _popped = false;

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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
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
              _popped = true;
              Navigator.pop(context, raw);
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
                ],
              ),
            ),
          ),
        ],
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
      ..color = WeChatPalette.green.withValues(alpha: .95)
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

    // Draw WeChat-like corner brackets.
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
