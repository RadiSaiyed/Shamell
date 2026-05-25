import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/device_login_label.dart';

void main() {
  test('sanitizeDeviceLoginLabel keeps regular labels', () {
    expect(sanitizeDeviceLoginLabel('Pixel 8 Pro'), 'Pixel 8 Pro');
    expect(sanitizeDeviceLoginLabel('  Demo-Phone  '), 'Demo-Phone');
  });

  test('sanitizeDeviceLoginLabel strips control and bidi spoofing chars', () {
    const raw = 'Demo\u202EDevice\u0007';
    expect(sanitizeDeviceLoginLabel(raw), 'DemoDevice');
  });

  test('sanitizeDeviceLoginLabel normalizes whitespace and truncates', () {
    expect(
      sanitizeDeviceLoginLabel('  Demo \n\t Phone   2026  '),
      'Demo Phone 2026',
    );
    expect(
      sanitizeDeviceLoginLabel(
        'abcdefghijklmnopqrstuvwxyz',
        maxChars: 8,
      ),
      'abcdefgh',
    );
  });

  test('sanitizeDeviceLoginLabel returns null for empty/blocked labels', () {
    expect(sanitizeDeviceLoginLabel(' \n\t '), isNull);
    expect(sanitizeDeviceLoginLabel('\u202E\u2066\u2069\u0000'), isNull);
  });
}
