import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;
  const SkeletonBox(
      {super.key,
      required this.height,
      this.width,
      this.borderRadius = const BorderRadius.all(Radius.circular(12))});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final base = onSurface.withValues(alpha: .04);
    final highlight = onSurface.withValues(alpha: .07);
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _ac.value, 0),
              end: Alignment(1 + 2 * _ac.value, 0),
              colors: [base, highlight, base],
              stops: const [0.1, 0.3, 0.6],
            ),
          ),
        );
      },
    );
  }
}

class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const SkeletonBox(
            height: 40,
            width: 40,
            borderRadius: BorderRadius.all(Radius.circular(20))),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
              SkeletonBox(height: 12, width: 160),
              SizedBox(height: 8),
              SkeletonBox(height: 10, width: 220),
            ])),
      ]),
    );
  }
}
