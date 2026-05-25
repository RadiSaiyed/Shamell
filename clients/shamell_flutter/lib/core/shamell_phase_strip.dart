import 'package:flutter/material.dart';

/// One step in a [ShamellPhaseStrip] — the user-facing phases that pages
/// like the ride hailing / driver / coach bus surfaces walk through.
///
/// Pages provide a list of steps in order. The strip styles each one
/// according to its position relative to the active index:
///  * completed (index < activeIndex): dimmed accent + check icon
///  * active   (index == activeIndex): bright accent + bold label
///  * pending  (index > activeIndex):  surface colour + dim label
class ShamellPhaseStep {
  /// Icon shown when the step is **active or pending**. Completed steps
  /// always show a checkmark to match the standard stepper convention.
  final IconData icon;

  /// Short label shown on every state. Localise this at the call site.
  final String label;

  /// Per-step accent override. Most pages use the surface primary, but
  /// the driver "In trip" step uses green so the earning state stands
  /// out at a glance. `null` falls back to `theme.colorScheme.primary`.
  final Color? accent;

  const ShamellPhaseStep({
    required this.icon,
    required this.label,
    this.accent,
  });
}

/// Persistent multi-step progress strip used across SyrChat's mobility
/// surfaces (Bus end-user, Taxi rider, Taxi driver).
///
/// The strip renders [steps] as equal-width pills connected by short
/// progress lines. Each step's visual state derives from its position
/// relative to [activeIndex]. Pages can pass [subStatusText] to surface
/// a fine-grained label under the active step (e.g. "Driver arriving"
/// in the taxi rider's Active phase) without inflating the strip's
/// height when no detail is available.
///
/// The widget implements [PreferredSizeWidget] so it can be dropped
/// straight into `AppBar.bottom`. Pages that want to inline it inside
/// a body `ListView` simply use it as a regular `Widget`.
class ShamellPhaseStrip extends StatelessWidget
    implements PreferredSizeWidget {
  final List<ShamellPhaseStep> steps;
  final int activeIndex;

  /// Optional sub-status shown as a second line under the active step.
  /// Passing null hides the sub-status row entirely so the strip stays
  /// compact when there is no detail to show.
  final String? subStatusText;

  /// Accessible "Step X of N: <label>" announcement. Localise at call
  /// site so each page can pick the right RTL forms.
  final String? semanticsLabel;

  /// Custom outer padding. Defaults are tuned for the AppBar.bottom slot.
  final EdgeInsetsGeometry padding;

  /// Background container is opt-out: ListView callers (e.g. inline in
  /// a body) often pair the strip with their own card styling and want
  /// transparent here, while AppBar.bottom callers leave it `true` so
  /// the strip reads as a distinct chrome region.
  final bool showBackgroundCard;

  const ShamellPhaseStrip({
    super.key,
    required this.steps,
    required this.activeIndex,
    this.subStatusText,
    this.semanticsLabel,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
    this.showBackgroundCard = false,
  })  : assert(steps.length > 0, 'ShamellPhaseStrip needs at least one step'),
        assert(
          activeIndex >= 0 && activeIndex < steps.length,
          'activeIndex must point at a step in the list',
        );

  // Height tuned to fit toolbar-like chrome. Two-line variants (with
  // sub-status) stay within the same envelope by tightening the icon
  // size; we don't grow the strip when sub-status appears so AppBar
  // layout doesn't reflow between phases.
  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultAccent = theme.colorScheme.primary;
    final content = Padding(
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: _ShamellPhaseChip(
                step: steps[i],
                index: i,
                activeIndex: activeIndex,
                defaultAccent: defaultAccent,
                subStatusText: i == activeIndex ? subStatusText : null,
              ),
            ),
            if (i < steps.length - 1)
              Container(
                width: 8,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                color: i < activeIndex
                    ? defaultAccent.withValues(alpha: .85)
                    : theme.dividerColor.withValues(alpha: .55),
              ),
          ],
        ],
      ),
    );
    final wrapped = showBackgroundCard
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: theme.brightness == Brightness.dark ? .35 : .55,
              ),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: theme.dividerColor.withValues(alpha: .7)),
            ),
            child: content,
          )
        : content;
    if (semanticsLabel == null) {
      return wrapped;
    }
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: wrapped,
    );
  }
}

class _ShamellPhaseChip extends StatelessWidget {
  final ShamellPhaseStep step;
  final int index;
  final int activeIndex;
  final Color defaultAccent;
  final String? subStatusText;

  const _ShamellPhaseChip({
    required this.step,
    required this.index,
    required this.activeIndex,
    required this.defaultAccent,
    required this.subStatusText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = index < activeIndex;
    final active = index == activeIndex;
    final accent = step.accent ?? defaultAccent;
    final Color bg;
    final Color fg;
    final Color border;
    if (active) {
      bg = accent.withValues(alpha: .14);
      fg = accent;
      border = accent.withValues(alpha: .55);
    } else if (completed) {
      bg = accent.withValues(alpha: .08);
      fg = accent.withValues(alpha: .82);
      border = accent.withValues(alpha: .32);
    } else {
      bg = theme.colorScheme.surface;
      fg = theme.colorScheme.onSurface.withValues(alpha: .52);
      border = theme.dividerColor.withValues(alpha: .65);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            completed ? Icons.check_rounded : step.icon,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: fg,
                  ),
                ),
                if (subStatusText != null)
                  Text(
                    subStatusText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg.withValues(alpha: .82),
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
