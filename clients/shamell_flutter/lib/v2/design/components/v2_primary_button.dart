import 'package:flutter/material.dart';

import '../tokens.dart';

class V2PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const V2PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: V2Tokens.brand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          vertical: V2Tokens.spacingMd,
          horizontal: V2Tokens.spacingLg,
        ),
        shape: RoundedRectangleBorder(borderRadius: V2Tokens.radiusMd),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
