// Cycle 49 — pulsing "online" status dot.
//
// Drop-in replacement for the prior `Container(...green...)` dot we
// used in the chat-list avatar overlay and the chat-thread AppBar
// subtitle. The pulse is subtle (1.0 → 0.5 alpha + 1.0 → 0.85 scale
// over 1.4 s); the goal is "alive without being noisy".

import 'package:flutter/material.dart';

class ChatPulseDot extends StatefulWidget {
  /// Dot diameter at the centre of the pulse, in pixels.
  final double size;

  /// Solid dot colour.
  final Color color;

  /// Optional ring around the dot — usually the surface colour, so
  /// the dot reads cleanly against textured backgrounds (e.g. the
  /// avatar tile).
  final Color? borderColor;
  final double borderWidth;

  const ChatPulseDot({
    super.key,
    this.size = 12,
    this.color = const Color(0xFF4CAF50),
    this.borderColor,
    this.borderWidth = 2,
  });

  @override
  State<ChatPulseDot> createState() => _ChatPulseDotState();
}

class _ChatPulseDotState extends State<ChatPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final t = _pulse.value;
        final scale = 0.85 + 0.15 * t;
        final alpha = 0.55 + 0.45 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: alpha),
              shape: BoxShape.circle,
              border: widget.borderColor == null
                  ? null
                  : Border.all(
                      color: widget.borderColor!,
                      width: widget.borderWidth,
                    ),
            ),
          ),
        );
      },
    );
  }
}
