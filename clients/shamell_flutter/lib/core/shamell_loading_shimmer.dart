import 'package:flutter/material.dart';

/// Lightweight, dependency-free shimmer effect for loading placeholders.
///
/// A `CircularProgressIndicator` tells the user "something is loading"
/// but hides the shape of what's coming. A skeleton with shimmer hints
/// at the eventual layout (header row, bullet rows, card grid) which
/// reads as snappier even when the underlying request takes just as
/// long. This module ships three primitives:
///   * [ShamellShimmer] — wraps any child in a shimmering gradient
///   * [ShamellShimmerBox] — flat rounded rectangle suitable for text or
///     thumbnail placeholders
///   * [ShamellSkeletonList] — N stacked skeleton rows for list / card
///     loading states
///
/// All three respect the active theme: in dark mode the base + highlight
/// colours flip so the shimmer reads as a subtle pulse instead of an
/// over-bright streak.
class ShamellShimmer extends StatefulWidget {
  /// Child whose silhouette becomes the masked area. Usually a `Column`
  /// of [ShamellShimmerBox]es.
  final Widget child;

  /// Sweep duration. ~1500ms reads as "deliberately animated" without
  /// distracting the user.
  final Duration period;

  /// `false` (default) animates indefinitely until the widget unmounts
  /// — set to `true` to halt the sweep (useful when a parent already
  /// rebuilds quickly enough that the animation would never complete).
  final bool paused;

  const ShamellShimmer({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1500),
    this.paused = false,
  });

  @override
  State<ShamellShimmer> createState() => _ShamellShimmerState();
}

class _ShamellShimmerState extends State<ShamellShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    if (!widget.paused) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ShamellShimmer old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) {
      _controller.duration = widget.period;
    }
    if (old.paused != widget.paused) {
      if (widget.paused) {
        _controller.stop();
      } else if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Picking the base / highlight from the theme keeps the shimmer
    // legible on every surface; subtle in dark mode, gentle in light.
    final base = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45)
        : theme.colorScheme.onSurface.withValues(alpha: .08);
    final highlight = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .85)
        : theme.colorScheme.onSurface.withValues(alpha: .03);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // The sweep moves from outside the left edge to outside the
        // right edge, so the highlight enters and exits cleanly without
        // pop-flashing.
        final t = _controller.value * 2.0 - 1.0;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.25, 0.5, 0.75],
              begin: Alignment(-1.0 + t, -0.3),
              end: Alignment(1.0 + t, 0.3),
            ).createShader(bounds);
          },
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}

/// Solid rounded rectangle that "fills" with the shimmer applied by an
/// ancestor [ShamellShimmer]. Use width / height to match the silhouette
/// of what's about to render (e.g. avatar, headline line, paragraph).
class ShamellShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const ShamellShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      // The container is opaque white; the shimmer parent's ShaderMask
      // recolours the pixels into the base/highlight gradient. Using
      // a real colour avoids a transparent area that the gradient
      // can't tint.
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
      ),
    );
  }
}

/// Generates a vertical skeleton list of [itemCount] rows. Each row
/// renders a circle avatar placeholder and two stacked text lines —
/// the canonical "row + title + subtitle" layout used everywhere from
/// chats to favorites.
class ShamellSkeletonList extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const ShamellSkeletonList({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    return ShamellShimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) {
          return Row(
            children: const [
              ShamellShimmerBox(
                width: 44,
                height: 44,
                borderRadius:
                    BorderRadius.all(Radius.circular(22)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShamellShimmerBox(width: 160, height: 12),
                    SizedBox(height: 8),
                    ShamellShimmerBox(width: 220, height: 10),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Generic card skeleton: a 3-line block stacked under a wider header
/// box. Great for cards/tile placeholders where there's no avatar.
class ShamellSkeletonCard extends StatelessWidget {
  final double? width;
  final EdgeInsetsGeometry padding;

  const ShamellSkeletonCard({
    super.key,
    this.width,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ShamellShimmer(
      child: Container(
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: .5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            ShamellShimmerBox(width: 180, height: 14),
            SizedBox(height: 12),
            ShamellShimmerBox(width: double.infinity, height: 10),
            SizedBox(height: 8),
            ShamellShimmerBox(width: double.infinity, height: 10),
            SizedBox(height: 8),
            ShamellShimmerBox(width: 140, height: 10),
          ],
        ),
      ),
    );
  }
}
