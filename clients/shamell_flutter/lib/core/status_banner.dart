import 'package:flutter/material.dart';

enum StatusKind { info, success, warning, error }

class StatusBanner extends StatelessWidget {
  final StatusKind kind;
  final String message;
  final bool dense;

  const StatusBanner({
    super.key,
    required this.kind,
    required this.message,
    this.dense = false,
  });

  const StatusBanner.info(this.message, {super.key, this.dense = false})
      : kind = StatusKind.info;

  const StatusBanner.error(this.message, {super.key, this.dense = false})
      : kind = StatusKind.error;

  const StatusBanner.success(this.message, {super.key, this.dense = false})
      : kind = StatusKind.success;

  const StatusBanner.warning(this.message, {super.key, this.dense = false})
      : kind = StatusKind.warning;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    Color stripe;
    IconData icon;
    switch (kind) {
      case StatusKind.success:
        stripe = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case StatusKind.warning:
        stripe = Colors.orange;
        icon = Icons.warning_amber_outlined;
        break;
      case StatusKind.error:
        stripe = theme.colorScheme.error;
        icon = Icons.error_outline;
        break;
      case StatusKind.info:
      default:
        stripe = Colors.blueGrey;
        icon = Icons.info_outline;
        break;
    }

    final bg = onSurface.withValues(alpha: 0.04);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: dense ? 16 : 18, color: stripe),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: dense ? 12 : 13,
              color: onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: stripe, width: 3),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: dense ? 6 : 8,
      ),
      child: content,
    );
  }
}

