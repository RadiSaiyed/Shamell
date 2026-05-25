// Cycle 43 — animated "is typing" dots.
//
// A small three-dot widget where each dot pulses (scale + opacity)
// in sequence, mimicking the WhatsApp / iMessage typing indicator.
// Used in the chat-thread "X is typing…" bar (replacing the prior
// static `Icons.more_horiz`). Cheap — one AnimationController per
// instance, running 1.2 s loops; the dots are sized for a 12-14 px
// text body so they tuck inline with the existing label.

import 'package:flutter/material.dart';

class ChatTypingDots extends StatefulWidget {
  final Color color;
  final double size;

  const ChatTypingDots({
    super.key,
    required this.color,
    this.size = 5,
  });

  @override
  State<ChatTypingDots> createState() => _ChatTypingDotsState();
}

class _ChatTypingDotsState extends State<ChatTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Per-dot scale factor for a given phase. Each dot is offset by
  /// 1/3 of the cycle so the three pulse in a wave.
  double _dotScale(double t, int i) {
    final phase = (t - i / 3) % 1;
    final shifted = (phase < 0 ? phase + 1 : phase);
    // Triangular wave 0..1..0 over the cycle, then ease to feel
    // like a bounce rather than a sawtooth.
    final tri = shifted < 0.5 ? shifted * 2 : (1 - shifted) * 2;
    final eased = Curves.easeInOut.transform(tri.clamp(0.0, 1.0));
    return 0.6 + 0.6 * eased;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < 3; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 3),
              Transform.scale(
                scale: _dotScale(_ctrl.value, i),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
