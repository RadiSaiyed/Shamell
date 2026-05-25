import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef ShamellClipboardWriter = Future<void> Function(String text);
typedef ShamellClipboardReader = Future<String?> Function();
typedef ShamellClipboardDelay = Future<void> Function(Duration duration);

const Duration _shamellSensitiveClipboardClearAfter = Duration(minutes: 2);

Future<void> _defaultClipboardWrite(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

Future<String?> _defaultClipboardRead() async {
  final data = await Clipboard.getData('text/plain');
  return data?.text;
}

Future<void> shamellCopyToClipboard(
  String text, {
  bool sensitive = false,
  Duration clearAfter = _shamellSensitiveClipboardClearAfter,
  ShamellClipboardWriter? writeText,
  ShamellClipboardReader? readText,
  ShamellClipboardDelay? delay,
}) async {
  final writer = writeText ?? _defaultClipboardWrite;
  await writer(text);
  if (!sensitive || text.trim().isEmpty || clearAfter <= Duration.zero) {
    return;
  }

  final reader = readText ?? _defaultClipboardRead;
  final pause = delay ?? Future<void>.delayed;
  unawaited(() async {
    try {
      await pause(clearAfter);
      final current = await reader();
      if (current == text) {
        await writer('');
      }
    } catch (_) {}
  }());
}

@visibleForTesting
Duration shamellSensitiveClipboardClearAfter() {
  return _shamellSensitiveClipboardClearAfter;
}
