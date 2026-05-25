import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final BorderRadiusGeometry? borderRadius;
  final double blurSigma;
  final double borderOpacityDark;
  final double borderOpacityLight;
  final bool showNoise;
  final Color? tint;
  final double? fillOpacity;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 26,
    this.borderRadius,
    this.blurSigma = 24,
    this.borderOpacityDark = 0.18,
    this.borderOpacityLight = 0.14,
    this.showNoise = false,
    this.tint,
    this.fillOpacity,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolvedRadius = borderRadius ?? BorderRadius.circular(radius);
    final baseTint = tint ?? theme.colorScheme.surface;
    final opacity = fillOpacity ?? (isDark ? .34 : .46);
    final cyan = isDark ? const Color(0xFF18B7FF) : const Color(0xFF08A8FF);
    final blue = isDark ? const Color(0xFF2478FF) : const Color(0xFF168BFF);
    final rose = isDark ? const Color(0xFFFF6FA8) : const Color(0xFFFF7BAE);
    final glassTint = Color.alphaBlend(
      cyan.withValues(alpha: isDark ? .16 : .20),
      baseTint,
    );
    final highlightOpacity =
        (opacity + (isDark ? .08 : .14)).clamp(0.0, 1.0).toDouble();
    final bodyOpacity = (opacity + .02).clamp(0.0, 1.0).toDouble();
    final borderOpacity = isDark ? borderOpacityDark : borderOpacityLight;
    final borderColor = Color.alphaBlend(
      cyan.withValues(alpha: isDark ? .30 : .36),
      Colors.white.withValues(alpha: isDark ? .24 : .54),
    ).withValues(alpha: (borderOpacity + .22).clamp(0.0, 1.0).toDouble());
    final innerBorderColor = Color.alphaBlend(
      rose.withValues(alpha: isDark ? .16 : .20),
      theme.dividerColor.withValues(alpha: borderOpacity),
    );
    final fillGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          Colors.white.withValues(alpha: isDark ? .18 : .46),
          cyan.withValues(alpha: isDark ? .24 : .28),
        ).withValues(alpha: highlightOpacity),
        Color.alphaBlend(
          glassTint.withValues(alpha: bodyOpacity),
          blue.withValues(alpha: isDark ? .20 : .24),
        ).withValues(alpha: bodyOpacity),
        Color.alphaBlend(
          rose.withValues(alpha: isDark ? .22 : .26),
          glassTint.withValues(alpha: opacity),
        ).withValues(alpha: opacity),
        Color.alphaBlend(
          theme.colorScheme.primary.withValues(alpha: isDark ? .18 : .14),
          glassTint.withValues(alpha: bodyOpacity),
        ).withValues(alpha: bodyOpacity),
      ],
      stops: const [0, .36, .72, 1],
    );
    final defaultShadow = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? .30 : .12),
        blurRadius: 34,
        spreadRadius: -8,
        offset: const Offset(0, 18),
      ),
      BoxShadow(
        color: cyan.withValues(alpha: isDark ? .22 : .18),
        blurRadius: 30,
        spreadRadius: -12,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: rose.withValues(alpha: isDark ? .11 : .10),
        blurRadius: 26,
        spreadRadius: -16,
        offset: const Offset(0, 2),
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: resolvedRadius,
        boxShadow: boxShadow ?? defaultShadow,
      ),
      child: ClipRRect(
        borderRadius: resolvedRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: fillGradient,
              borderRadius: resolvedRadius,
              border: Border.all(
                color: Color.alphaBlend(borderColor, innerBorderColor),
                width: 1.15,
              ),
            ),
            child: CustomPaint(
              foregroundPainter: _GlassSpecularPainter(
                color: Colors.white.withValues(alpha: isDark ? .18 : .46),
                cyan: cyan,
                rose: rose,
                radius: radius,
                showNoise: showNoise,
                noiseColor: Colors.white.withValues(alpha: isDark ? .05 : .18),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSpecularPainter extends CustomPainter {
  final Color color;
  final Color cyan;
  final Color rose;
  final double radius;
  final bool showNoise;
  final Color noiseColor;

  const _GlassSpecularPainter({
    required this.color,
    required this.cyan,
    required this.rose,
    required this.radius,
    required this.showNoise,
    required this.noiseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rimRadius = Radius.circular(
        math.min(radius, math.min(size.width, size.height) / 2));
    final rimRect = RRect.fromRectAndRadius(rect.deflate(.7), rimRadius);

    final cyanBloom = Paint()
      ..shader = RadialGradient(
        colors: [
          cyan.withValues(alpha: .28),
          cyan.withValues(alpha: .10),
          Colors.transparent,
        ],
        stops: const [0, .48, 1],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .18, size.height * .24),
          radius: math.max(size.width, size.height) * .58,
        ),
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .18, size.height * .25),
        width: size.width * .72,
        height: size.height * .92,
      ),
      cyanBloom,
    );

    final roseBloom = Paint()
      ..shader = RadialGradient(
        colors: [
          rose.withValues(alpha: .22),
          rose.withValues(alpha: .07),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .72, size.height * .18),
          radius: math.max(size.width, size.height) * .50,
        ),
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .73, size.height * .20),
        width: size.width * .70,
        height: size.height * .82,
      ),
      roseBloom,
    );

    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color,
          color.withValues(alpha: color.a * .34),
          color.withValues(alpha: 0),
        ],
        stops: const [0, .32, 1],
      ).createShader(rect);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * .70, 0)
      ..quadraticBezierTo(
          size.width * .42, size.height * .24, 0, size.height * .36)
      ..close();
    canvas.drawPath(path, sheen);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: color.a),
          cyan.withValues(alpha: .42),
          rose.withValues(alpha: .24),
          Colors.white.withValues(alpha: color.a * .36),
        ],
        stops: const [0, .34, .68, 1],
      ).createShader(rect);
    canvas.drawRRect(rimRect, rim);

    final innerRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.4
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: color.a * .18),
          cyan.withValues(alpha: .16),
          Colors.transparent,
          rose.withValues(alpha: .12),
        ],
        stops: const [0, .32, .68, 1],
      ).createShader(rect);
    canvas.drawRRect(rimRect.deflate(2.4), innerRim);

    final topLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: color.a * .78);
    canvas.drawLine(
      Offset(size.width * .10, 1.2),
      Offset(size.width * .90, 1.2),
      topLine,
    );

    if (!showNoise) return;
    final dot = Paint()..color = noiseColor;
    for (var y = 4; y < size.height; y += 9) {
      for (var x = 3; x < size.width; x += 11) {
        if (((x * 17 + y * 13) % 7) == 0) {
          canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), .45, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlassSpecularPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cyan != cyan ||
        oldDelegate.rose != rose ||
        oldDelegate.radius != radius ||
        oldDelegate.showNoise != showNoise ||
        oldDelegate.noiseColor != noiseColor;
  }
}

/// Lightweight convenience wrapper that mirrors [GlassPanel] but with a
/// shorter name, used in a few feature UIs.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: padding,
      radius: radius,
      child: child,
    );
  }
}
