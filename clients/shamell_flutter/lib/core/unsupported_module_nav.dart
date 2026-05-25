import 'package:flutter/material.dart';

import 'l10n.dart';

String unsupportedModuleShortcutMessage({required bool isArabic}) {
  return isArabic
      ? 'اختصار هذه الوحدة لم يعد مدعوماً.'
      : 'This module shortcut is no longer supported.';
}

void showUnsupportedModuleShortcutSnackBar(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final isArabic = L10n.of(context).isArabic;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(unsupportedModuleShortcutMessage(isArabic: isArabic)),
      ),
    );
}
