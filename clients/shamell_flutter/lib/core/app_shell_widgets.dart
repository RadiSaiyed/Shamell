import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Unified homescreen-like background for all pages.
///
/// Extracted from `main.dart` so Mini‑Apps can depend on core only.
class AppBG extends StatelessWidget {
  final Widget? child;

  const AppBG({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark ? Tokens.darkScaffold : Tokens.lightScaffold;

    return ColoredBox(
      color: background,
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _LiquidBackdropPainter extends CustomPainter {
  final bool isDark;

  const _LiquidBackdropPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    void band({
      required Alignment begin,
      required Alignment end,
      required List<Color> colors,
      List<double>? stops,
    }) {
      final paint = Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
          stops: stops,
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }

    band(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              const Color(0xFF19C8FF).withValues(alpha: .24),
              Colors.transparent,
              const Color(0xFFFF6EA6).withValues(alpha: .14),
            ]
          : [
              const Color(0xFFFFFFFF).withValues(alpha: .60),
              const Color(0xFF0EB9FF).withValues(alpha: .30),
              const Color(0xFFFF75A9).withValues(alpha: .18),
            ],
      stops: const [0, .48, 1],
    );
    band(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: isDark
          ? [
              const Color(0xFF0B7DFF).withValues(alpha: .14),
              const Color(0xFFFFC7A8).withValues(alpha: .08),
              Colors.transparent,
            ]
          : [
              Colors.transparent,
              const Color(0xFFFFFFFF).withValues(alpha: .36),
              Colors.transparent,
            ],
      stops: const [0, .52, 1],
    );

    void ribbon({
      required Path path,
      required List<Color> colors,
      required Alignment begin,
      required Alignment end,
      double blur = 34,
    }) {
      final paint = Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawPath(path, paint);
    }

    ribbon(
      path: Path()
        ..moveTo(-size.width * .18, size.height * .14)
        ..cubicTo(
          size.width * .22,
          size.height * .02,
          size.width * .46,
          size.height * .24,
          size.width * .90,
          size.height * .08,
        )
        ..lineTo(size.width * 1.20, size.height * .26)
        ..cubicTo(
          size.width * .72,
          size.height * .42,
          size.width * .35,
          size.height * .22,
          -size.width * .12,
          size.height * .34,
        )
        ..close(),
      colors: isDark
          ? [
              const Color(0xFF1FCBFF).withValues(alpha: .24),
              const Color(0xFF1A7DFF).withValues(alpha: .20),
              const Color(0xFFFF5D9D).withValues(alpha: .12),
            ]
          : [
              const Color(0xFF27C9FF).withValues(alpha: .44),
              const Color(0xFF168BFF).withValues(alpha: .34),
              const Color(0xFFFF78AB).withValues(alpha: .20),
            ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      blur: 42,
    );

    ribbon(
      path: Path()
        ..moveTo(size.width * .04, size.height * .64)
        ..cubicTo(
          size.width * .34,
          size.height * .48,
          size.width * .58,
          size.height * .78,
          size.width * 1.06,
          size.height * .58,
        )
        ..lineTo(size.width * 1.18, size.height * .84)
        ..cubicTo(
          size.width * .70,
          size.height * .98,
          size.width * .34,
          size.height * .78,
          -size.width * .10,
          size.height * .94,
        )
        ..close(),
      colors: isDark
          ? [
              const Color(0xFFFF6EA6).withValues(alpha: .16),
              const Color(0xFF1BBFFF).withValues(alpha: .16),
              const Color(0xFFFFFFFF).withValues(alpha: .04),
            ]
          : [
              const Color(0xFFFF8AB8).withValues(alpha: .26),
              const Color(0xFF16BBFF).withValues(alpha: .30),
              const Color(0xFFFFFFFF).withValues(alpha: .22),
            ],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      blur: 48,
    );

    final glassLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: isDark ? .10 : .36);
    final path = Path()
      ..moveTo(-size.width * .10, size.height * .28)
      ..cubicTo(
        size.width * .25,
        size.height * .20,
        size.width * .54,
        size.height * .44,
        size.width * 1.08,
        size.height * .30,
      );
    canvas.drawPath(path, glassLine);

    final secondLine = Path()
      ..moveTo(size.width * .18, size.height * .72)
      ..cubicTo(
        size.width * .38,
        size.height * .62,
        size.width * .62,
        size.height * .86,
        size.width * 1.08,
        size.height * .70,
      );
    canvas.drawPath(
      secondLine,
      glassLine..color = Colors.white.withValues(alpha: isDark ? .08 : .24),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidBackdropPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}

/// Simple filled CTA button reused across verticals.
///
/// Extracted from `main.dart` as part of the Superapp Shell.
class WaterButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;

  const WaterButton({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    this.radius = 12,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color base = tint ?? theme.colorScheme.primary;
    final style = FilledButton.styleFrom(
      backgroundColor: base,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return icon == null
        ? FilledButton(style: style, onPressed: onTap, child: Text(label))
        : FilledButton.icon(
            style: style,
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
          );
  }
}
