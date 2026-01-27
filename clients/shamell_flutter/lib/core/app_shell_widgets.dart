import 'package:flutter/material.dart';

/// Unified homescreen-like background for all pages.
///
/// Extracted from `main.dart` so Mini‑Apps can depend on core only.
class AppBG extends StatelessWidget {
  final Widget? child;

  const AppBG({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;
    if (child == null) {
      return ColoredBox(color: bg);
    }
    return ColoredBox(
      color: bg,
      child: child,
    );
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
        ? FilledButton(
            style: style,
            onPressed: onTap,
            child: Text(label),
          )
        : FilledButton.icon(
            style: style,
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
          );
  }
}
