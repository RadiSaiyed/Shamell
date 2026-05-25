import 'package:flutter/material.dart';

/// Animated three-dot "typing…" indicator for the conversation header
/// (Cycle 5 wave 1 follow-up). Renders three small bouncing circles
/// next to an optional label like "Alice is typing…".
///
/// **When to render.** The chat page parent shows this only while the
/// peer's typing-state Redis pubsub event is `typing_started` AND no
/// `typing_stopped` (or 10s timeout — whichever comes first) has
/// arrived since. The chat page owns that state machine; this widget
/// is purely visual.
///
/// **Animation.** Continuous loop, ~1.2s per cycle. Each dot peaks
/// 0.15s after the previous one for a subtle wave effect (rather than
/// all three pulsing in unison, which feels rigid). The CPU cost is
/// one `AnimationController` per visible chat header — negligible
/// because the indicator hides itself when no typing is active.
class ChatTypingDot extends StatefulWidget {
  /// Optional caption like "Alice is typing…". Pass `null` to render
  /// just the three dots (useful when the parent has its own label).
  final String? label;

  /// Override the dot color. Defaults to the theme's
  /// `colorScheme.primary` with a subtle alpha.
  final Color? color;

  /// Override the dot diameter. Defaults to 6 px.
  final double size;

  const ChatTypingDot({
    super.key,
    this.label,
    this.color,
    this.size = 6,
  });

  @override
  State<ChatTypingDot> createState() => _ChatTypingDotState();
}

class _ChatTypingDotState extends State<ChatTypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.color ??
        theme.colorScheme.primary.withValues(alpha: .85);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .68),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 6),
        ],
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          _Dot(controller: _ac, phase: i / 3.0, color: color, size: widget.size),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final AnimationController controller;

  /// 0.0 / 0.33 / 0.66 — staggered phase so the three dots peak in
  /// sequence rather than in unison.
  final double phase;
  final Color color;
  final double size;

  const _Dot({
    required this.controller,
    required this.phase,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Map (0..1) → sine wave 0→1→0, offset by phase.
        final t = (controller.value + phase) % 1.0;
        // Sin curve, normalised so the dip is the dimmer "rest" state.
        final amp = (1 - ((t - 0.5).abs() * 2)).clamp(0.0, 1.0);
        final opacity = 0.35 + 0.65 * amp;
        final yOffset = -3.0 * amp;
        return Transform.translate(
          offset: Offset(0, yOffset),
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
