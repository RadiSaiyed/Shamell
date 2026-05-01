import 'package:flutter/material.dart';

import '../tokens.dart';

class V2SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const V2SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(V2Tokens.spacingLg),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: V2Tokens.card,
        borderRadius: V2Tokens.radiusLg,
        border: Border.all(color: V2Tokens.divider),
      ),
      child: child,
    );
  }
}
