import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double blurSigma;
  final double borderOpacityDark;
  final double borderOpacityLight;
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 20, this.blurSigma = 20, this.borderOpacityDark = .22, this.borderOpacityLight = .10});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bg = isDark
        ? theme.colorScheme.surface.withValues(alpha: .98)
        : Colors.white;
    final Color border = isDark
        ? Colors.white.withValues(alpha: borderOpacityDark)
        : Colors.black.withValues(alpha: borderOpacityLight);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}
