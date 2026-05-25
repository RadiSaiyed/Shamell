import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../wechat_ui.dart';

enum ShamellPaymentCardTone { section, hero, soft }

bool shamellPaymentIsCompact(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 430;
}

EdgeInsets shamellPaymentPagePadding(BuildContext context) {
  final compact = shamellPaymentIsCompact(context);
  final side = compact ? 12.0 : 16.0;
  return EdgeInsets.fromLTRB(side, side, side, compact ? 88 : 72);
}

EdgeInsets shamellPaymentCardPadding(
  BuildContext context, {
  ShamellPaymentCardTone tone = ShamellPaymentCardTone.section,
}) {
  final compact = shamellPaymentIsCompact(context);
  if (tone == ShamellPaymentCardTone.hero) {
    return EdgeInsets.all(compact ? 14 : 18);
  }
  return EdgeInsets.all(compact ? 14 : 18);
}

double shamellPaymentCardRadius(BuildContext context) {
  return shamellPaymentIsCompact(context) ? 10 : 12;
}

class ShamellPaymentCardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final ShamellPaymentCardTone tone;
  final Color? accent;

  const ShamellPaymentCardSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.radius = 24,
    this.tone = ShamellPaymentCardTone.section,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compact = shamellPaymentIsCompact(context);
    final effectivePadding = padding == const EdgeInsets.all(18)
        ? shamellPaymentCardPadding(context, tone: tone)
        : padding;
    final effectiveRadius =
        radius == 24 ? shamellPaymentCardRadius(context) : radius;
    final effectiveAccent = accent ?? Tokens.colorPayments;
    final fill = tone == ShamellPaymentCardTone.hero
        ? Color.lerp(
              theme.colorScheme.surface,
              effectiveAccent,
              isDark ? 0.10 : 0.035,
            ) ??
            theme.colorScheme.surface
        : tone == ShamellPaymentCardTone.soft
            ? (isDark
                ? theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: .32)
                : const Color(0xFFF7F8FA))
            : theme.colorScheme.surface;
    final borderColor = Color.lerp(
          theme.dividerColor.withValues(alpha: isDark ? 0.42 : 0.84),
          effectiveAccent.withValues(alpha: isDark ? 0.16 : 0.08),
          tone == ShamellPaymentCardTone.hero ? 0.40 : 0.16,
        ) ??
        theme.dividerColor;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.045);

    return Padding(
      padding: margin,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(effectiveRadius),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: compact ? 10 : 14,
              offset: Offset(0, compact ? 3 : 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(effectiveRadius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(effectiveRadius),
                border: Border.all(color: borderColor),
                color: fill,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  children: [
                    if (tone == ShamellPaymentCardTone.hero)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 3,
                          color: effectiveAccent.withValues(
                            alpha: isDark ? .74 : .62,
                          ),
                        ),
                      ),
                    Padding(
                      padding: effectivePadding,
                      child: SizedBox(width: double.infinity, child: child),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShamellPaymentMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;

  const ShamellPaymentMetricChip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    final effectiveAccent = accent ?? Tokens.colorPayments;
    final borderColor = effectiveAccent.withValues(alpha: isDark ? 0.26 : 0.16);
    final fill = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .24)
        : WeChatPalette.searchFill;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth < 220 ? 220 : maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
          color: fill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: effectiveAccent.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShamellPaymentListTileCard extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? accent;

  const ShamellPaymentListTileCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compact = shamellPaymentIsCompact(context);
    final effectivePadding =
        padding == const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
            ? EdgeInsets.symmetric(
                horizontal: compact ? 12 : 14,
                vertical: compact ? 10 : 12,
              )
            : padding;
    final effectiveRadius = compact ? 8.0 : 10.0;
    final effectiveAccent = accent ?? Tokens.colorPayments;
    final fill = theme.colorScheme.surface;
    final borderColor = Color.lerp(
          theme.dividerColor.withValues(alpha: isDark ? 0.26 : 0.10),
          effectiveAccent.withValues(alpha: isDark ? 0.20 : 0.12),
          0.72,
        ) ??
        theme.dividerColor;

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(effectiveRadius),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(effectiveRadius),
              border: Border.all(color: borderColor),
              color: fill,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.025),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: effectivePadding,
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        title,
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          subtitle!,
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShamellPaymentSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final ShamellPaymentCardTone tone;

  const ShamellPaymentSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.trailing,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.padding = const EdgeInsets.all(14),
    this.tone = ShamellPaymentCardTone.section,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ShamellPaymentCardSurface(
      tone: tone,
      margin: margin,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .68),
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class ShamellPaymentFilterField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?>? onChanged;
  final double? width;
  final Color? accent;

  const ShamellPaymentFilterField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveAccent = accent ?? Tokens.colorPayments;
    final field = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color.lerp(
                theme.dividerColor.withValues(alpha: isDark ? 0.30 : 0.12),
                effectiveAccent.withValues(alpha: isDark ? 0.22 : 0.12),
                0.75,
              ) ??
              theme.dividerColor,
        ),
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .24)
            : WeChatPalette.searchFill,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          icon: Icon(
            Icons.expand_more_rounded,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          items: options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );

    if (width == null) return content;
    return SizedBox(width: width, child: content);
  }
}

class ShamellPaymentPillButton extends StatelessWidget {
  final Widget label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? accent;
  final EdgeInsets padding;

  const ShamellPaymentPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.selected = false,
    this.accent,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveAccent = accent ?? Tokens.colorPayments;
    final enabled = onPressed != null;
    final fillA = selected
        ? (Color.lerp(
              theme.colorScheme.surface,
              effectiveAccent,
              isDark ? 0.34 : 0.18,
            ) ??
            effectiveAccent)
        : (Color.lerp(
              theme.colorScheme.surface,
              effectiveAccent,
              isDark ? 0.18 : 0.06,
            ) ??
            theme.colorScheme.surface);
    final fillB = selected
        ? (Color.lerp(
              theme.cardColor,
              effectiveAccent,
              isDark ? 0.26 : 0.12,
            ) ??
            theme.cardColor)
        : (Color.lerp(
              theme.cardColor,
              effectiveAccent,
              isDark ? 0.10 : 0.03,
            ) ??
            theme.cardColor);
    final borderColor = selected
        ? effectiveAccent.withValues(alpha: isDark ? 0.68 : 0.42)
        : (Color.lerp(
              theme.dividerColor.withValues(alpha: isDark ? 0.30 : 0.12),
              effectiveAccent.withValues(alpha: isDark ? 0.20 : 0.14),
              0.68,
            ) ??
            theme.dividerColor);

    final foreground = enabled
        ? (selected
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withValues(alpha: 0.82))
        : theme.colorScheme.onSurface.withValues(alpha: 0.42);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: enabled
                  ? [fillA, fillB]
                  : [
                      fillA.withValues(alpha: 0.55),
                      fillB.withValues(alpha: 0.55),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? effectiveAccent.withValues(alpha: isDark ? 0.22 : 0.12)
                    : Colors.black.withValues(alpha: isDark ? 0.12 : 0.03),
                blurRadius: selected ? 14 : 8,
                offset: Offset(0, selected ? 8 : 3),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: foreground,
                  ) ??
                  TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: foreground,
                  ),
              child: IconTheme.merge(
                data: IconThemeData(
                  size: 18,
                  color: foreground,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      icon!,
                      const SizedBox(width: 8),
                    ],
                    label,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentGlowBubble extends StatelessWidget {
  final Color color;
  final double size;

  const _PaymentGlowBubble({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
