import 'package:flutter/material.dart';

/// Shared "empty" and "error" placeholders used when a list/page has
/// nothing to show or a fetch failed. The two surfaces are visually
/// kin: large icon, short title, calmer description, optional action(s).
/// Splitting them into separate constructors keeps call sites declarative
/// (`ShamellEmptyState.notFound(...)` vs `ShamellEmptyState.error(...)`)
/// and lets us tune the accent colour and default icons per kind.
///
/// The widget is designed for two scenarios:
///   * **Full surface**: hand it back from `Center` or as the lone child
///     of a `ListView` so it occupies the available space.
///   * **Card-tight**: drop it inside a sized container — the padding
///     defaults already work for cells around 200–320 dp wide.
///
/// All copy is passed in by the caller so each page handles its own
/// localisation (English + Arabic). The widget never hard-codes strings.
class ShamellEmptyState extends StatelessWidget {
  /// Icon shown above the title. Pick something that hints at the
  /// missing content (e.g. `Icons.inbox_outlined` for an empty list,
  /// `Icons.search_off_rounded` for "no matches", `Icons.error_outline`
  /// for errors).
  final IconData icon;

  /// One-line label, bold. Optional but recommended for clarity.
  final String? title;

  /// Multi-line description that explains *why* the surface is empty
  /// or errored. Optional.
  final String? description;

  /// Primary call-to-action — for example "Retry" on an error or
  /// "Add favorite" on an empty favorites list. Both `actionLabel` and
  /// `onAction` must be supplied for the button to render.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional second action, rendered as a `TextButton` next to the
  /// primary. Use it for "Open settings" / "Learn more" links.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Accent colour for the icon and primary action. Defaults to the
  /// surface primary so each Mini-Program inherits its theme.
  final Color? accent;

  /// `false` (default) treats this as a generic "nothing here" state —
  /// neutral icon tint. `true` switches to an error palette using the
  /// theme's error colour so failures are unmistakable.
  final bool isError;

  /// Outer padding around the column. Overrides the default
  /// `EdgeInsets.all(24)` if a call site needs tighter chrome.
  final EdgeInsetsGeometry padding;

  const ShamellEmptyState({
    super.key,
    required this.icon,
    this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.accent,
    this.isError = false,
    this.padding = const EdgeInsets.all(24),
  });

  /// Shortcut for "fetch failed" surfaces. Mirrors the primary
  /// constructor but pins `isError: true` so accent / icon defaults
  /// pick the theme error palette.
  const ShamellEmptyState.error({
    super.key,
    this.icon = Icons.error_outline_rounded,
    this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.accent,
    this.padding = const EdgeInsets.all(24),
  }) : isError = true;

  /// Shortcut for "no results matching this filter" — same as the
  /// default constructor but defaults the icon to `search_off`.
  const ShamellEmptyState.noResults({
    super.key,
    this.icon = Icons.search_off_rounded,
    this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.accent,
    this.padding = const EdgeInsets.all(24),
  }) : isError = false;

  /// Shortcut for "empty inbox / list" — defaults to the inbox icon.
  const ShamellEmptyState.empty({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.accent,
    this.padding = const EdgeInsets.all(24),
  }) : isError = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultAccent = isError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final activeAccent = accent ?? defaultAccent;
    final neutralIconTint = isError
        ? theme.colorScheme.error.withValues(alpha: .55)
        : theme.colorScheme.onSurface.withValues(alpha: .45);
    final descriptionStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: .65),
      height: 1.35,
    );

    final hasPrimary = actionLabel != null && onAction != null;
    final hasSecondary =
        secondaryActionLabel != null && onSecondaryAction != null;

    return Semantics(
      container: true,
      label: title ?? description,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 44,
              color: neutralIconTint,
            ),
            if (title != null) ...[
              const SizedBox(height: 12),
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: descriptionStyle,
              ),
            ],
            if (hasPrimary || hasSecondary) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (hasPrimary)
                    FilledButton(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: activeAccent,
                        foregroundColor:
                            ThemeData.estimateBrightnessForColor(activeAccent) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                      ),
                      child: Text(actionLabel!),
                    ),
                  if (hasSecondary)
                    TextButton(
                      onPressed: onSecondaryAction,
                      child: Text(secondaryActionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
