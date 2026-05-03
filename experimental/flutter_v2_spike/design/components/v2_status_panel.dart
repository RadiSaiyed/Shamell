import 'package:flutter/material.dart';

import '../tokens.dart';

class V2StatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Color color;

  const V2StatusPanel({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.color = V2Tokens.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(V2Tokens.spacingMd),
      decoration: BoxDecoration(
        color: V2Tokens.card,
        borderRadius: V2Tokens.radiusMd,
        border: Border.all(
          color: color == V2Tokens.textPrimary
              ? V2Tokens.divider
              : color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: V2Tokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                ),
                if ((message ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    message!.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: V2Tokens.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
