import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double blurSigma;
  final double borderOpacityDark;
  final double borderOpacityLight;
  final bool showNoise;
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 26,
    this.blurSigma = 14, // deeper blur for frosted glassmorphism
    this.borderOpacityDark = 0.18,
    this.borderOpacityLight = 0.14,
    this.showNoise = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color border =
        theme.dividerColor.withValues(alpha: isDark ? 0.22 : 0.28);
    final Color fill = theme.cardColor;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: const [],
      ),
      child: child,
    );
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
