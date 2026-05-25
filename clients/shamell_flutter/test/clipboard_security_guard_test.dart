import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clipboard writes are routed via safe_clipboard wrapper', () async {
    final offenders = <String>[];
    await for (final entity in Directory('lib').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll('\\', '/');
      if (normalizedPath.endsWith('/core/safe_clipboard.dart')) {
        continue;
      }
      final source = await entity.readAsString();
      if (source.contains('Clipboard.setData(')) {
        offenders.add(normalizedPath);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Direct Clipboard.setData calls bypass auto-clear for sensitive data: '
          '${offenders.join(', ')}',
    );
  });
}
