import 'package:flutter/material.dart';

import 'glass.dart';

/// Standard container for grouped form content.
///
/// Renders a title, optional subtitle and wraps children in a GlassPanel so
/// all screens share the same basic section layout.
class FormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsets margin;
  final EdgeInsets padding;

  const FormSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 16),
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Padding(
      padding: margin,
      child: GlassPanel(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: onSurface,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withValues(alpha: 0.70),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Standardised list tile used across history, recent lists and domain
/// summaries. Wraps a ListTile in a GlassPanel for consistent spacing and
/// borders.
class StandardListTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final EdgeInsets padding;

  const StandardListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: GlassPanel(
        padding: padding,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Shared scaffold that applies the unified Shamell layout shell:
/// gradient background + full-screen GlassPanel card, as used in
/// Taxi Rider and other modernised flows.
class DomainPageScaffold extends StatelessWidget {
  final Widget background;
  final String title;
  final Widget child;
  final bool scrollable;

  const DomainPageScaffold({
    super.key,
    required this.background,
    required this.title,
    required this.child,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final inner = scrollable
        ? SingleChildScrollView(
            child: child,
          )
        : child;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          background,
          Positioned.fill(
            child: SafeArea(
              child: GlassPanel(
                padding: const EdgeInsets.all(12),
                radius: 12,
                child: inner,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard primary action button used across the app.
///
/// This wraps a FilledButton so that primary calls-to-action share the
/// same look and feel on all screens.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final btn = icon == null
        ? FilledButton(
            onPressed: onPressed,
            child: Text(label),
          )
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
    if (expanded) {
      return SizedBox(width: double.infinity, child: btn);
    }
    return btn;
  }
}
