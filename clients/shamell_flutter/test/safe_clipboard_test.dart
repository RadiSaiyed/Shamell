import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/safe_clipboard.dart';

void main() {
  test('sensitive clipboard copy clears unchanged text after ttl', () async {
    String clipboard = '';
    final delayed = Completer<void>();

    await shamellCopyToClipboard(
      'invite://token-123',
      sensitive: true,
      writeText: (text) async {
        clipboard = text;
      },
      readText: () async => clipboard,
      delay: (_) => delayed.future,
    );

    expect(clipboard, 'invite://token-123');

    delayed.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(clipboard, isEmpty);
  });

  test('sensitive clipboard copy does not clear if user changed clipboard',
      () async {
    String clipboard = '';
    final delayed = Completer<void>();

    await shamellCopyToClipboard(
      'pay://wallet_me?amount=100',
      sensitive: true,
      writeText: (text) async {
        clipboard = text;
      },
      readText: () async => clipboard,
      delay: (_) => delayed.future,
    );

    clipboard = 'user-overrode-clipboard';
    delayed.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(clipboard, 'user-overrode-clipboard');
  });

  test('non-sensitive clipboard copy does not schedule auto-clear', () async {
    String clipboard = '';
    var delayCalled = false;

    await shamellCopyToClipboard(
      'https://safe.example.com/docs',
      sensitive: false,
      writeText: (text) async {
        clipboard = text;
      },
      readText: () async => clipboard,
      delay: (_) {
        delayCalled = true;
        return Future<void>.value();
      },
    );

    expect(clipboard, 'https://safe.example.com/docs');
    expect(delayCalled, isFalse);
  });
}
