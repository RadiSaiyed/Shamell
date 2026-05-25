import 'package:flutter/material.dart';

import '../skeleton.dart';

/// Single-row chat-bubble placeholder used while a paginated history load
/// is in flight (Cycle 3C). The widget mimics the shape of a real message
/// bubble — narrow body for incoming, slightly wider for outgoing, the
/// timestamp slot blocked out below — so the loading state reads as
/// "more messages incoming" rather than a generic spinner.
///
/// Sizes are deliberately small (height 14 / 10) so the row stays compact
/// in dense threads. Width varies pseudo-randomly per [seed] so a column of
/// 3 stacked skeletons doesn't look like 3 identical rectangles.
class ChatBubbleSkeleton extends StatelessWidget {
  /// Whether the bubble should hug the leading edge (incoming peer message,
  /// `false`) or the trailing edge (my outgoing message, `true`). Defaults
  /// to incoming because the user's first paginated batch is almost always
  /// older history skewing toward the peer's side.
  final bool isMine;

  /// Deterministic seed for width jitter. Pass the row index from a
  /// `ListView.builder` so the skeleton row keeps a stable shape across
  /// rebuilds (otherwise every `AnimatedBuilder` tick re-rolls the width
  /// and the bubble appears to grow/shrink, which looks broken).
  final int seed;

  const ChatBubbleSkeleton({
    super.key,
    this.isMine = false,
    this.seed = 0,
  });

  /// Pseudo-random body width in the [120, 240] px band, derived from
  /// [seed]. Real messages cluster around 140–220 px, so this band looks
  /// natural without ever being suspiciously uniform.
  double _bodyWidth() {
    final spread = ((seed * 37) % 121).toDouble(); // 0..120
    return 120 + spread;
  }

  @override
  Widget build(BuildContext context) {
    final width = _bodyWidth();
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final radius = isMine
        ? const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: alignment,
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SkeletonBox(
              height: 14,
              width: width,
              borderRadius: radius,
            ),
            const SizedBox(height: 4),
            // Timestamp placeholder — narrow box, ~48 px wide.
            const SkeletonBox(
              height: 8,
              width: 48,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Column of [ChatBubbleSkeleton]s used in the "load older messages"
/// in-flight state. Three rows is a good visual cue without dominating
/// the viewport, and the seeded width jitter makes them look like
/// distinct messages.
///
/// Alternates incoming / outgoing so the column reads as a snippet of
/// conversation rather than a one-sided wall.
class ChatBubbleSkeletonGroup extends StatelessWidget {
  /// How many skeleton bubbles to render. Defaults to 3, which matches
  /// the typical page-size feel without crowding the viewport.
  final int count;

  const ChatBubbleSkeletonGroup({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            ChatBubbleSkeleton(seed: i, isMine: i.isOdd),
        ],
      ),
    );
  }
}
