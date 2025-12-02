import 'dart:ui';

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
    final colorScheme = theme.colorScheme;
    final Color border = isDark
        ? Colors.white.withValues(alpha: borderOpacityDark)
        : Colors.black.withValues(alpha: borderOpacityLight);
    // Vibrant inner glow and soft outer glow, tuned for a liquid-glass look.
    final Color glow = colorScheme.primary.withValues(alpha: isDark ? 0.28 : 0.22);
    final Color highlight =
        Colors.white.withValues(alpha: isDark ? 0.22 : 0.32);
    final Color baseFill =
        Colors.white.withValues(alpha: isDark ? 0.08 : 0.18);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            // Subtle multi-stop gradient + glow for strong glassmorphism.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                highlight,
                baseFill,
                glow,
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border),
            boxShadow: [
              // Outer glow halo
              BoxShadow(
                color: glow.withValues(alpha: 0.55),
                blurRadius: 26,
                spreadRadius: 1,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.30),
                blurRadius: 32,
                spreadRadius: -4,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: child,
        ),
      ),
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
