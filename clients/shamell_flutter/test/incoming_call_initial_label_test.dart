import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/incoming_call_page.dart';

void main() {
  group('pickInitialCallerLabel', () {
    const peer = 'dev_caller_001';

    test('null hint → falls back to deviceId', () {
      expect(
        pickInitialCallerLabel(hint: null, fromDeviceId: peer),
        peer,
      );
    });

    test('empty hint → falls back to deviceId', () {
      expect(
        pickInitialCallerLabel(hint: '', fromDeviceId: peer),
        peer,
      );
    });

    test('whitespace hint → falls back to deviceId', () {
      expect(
        pickInitialCallerLabel(hint: '   \t  ', fromDeviceId: peer),
        peer,
      );
    });

    test('non-blank hint → used verbatim (preserves caller-provided name)', () {
      expect(
        pickInitialCallerLabel(hint: 'Anna Müller', fromDeviceId: peer),
        'Anna Müller',
      );
    });

    test('hint with surrounding whitespace is trimmed', () {
      expect(
        pickInitialCallerLabel(
          hint: '  Anna Müller  ',
          fromDeviceId: peer,
        ),
        'Anna Müller',
      );
    });

    test('does not touch device id even when empty (caller-side guarded)', () {
      // The widget rejects empty fromDeviceId upstream, so the helper's
      // contract is: return whatever fromDeviceId is when no hint applies.
      expect(
        pickInitialCallerLabel(hint: null, fromDeviceId: ''),
        '',
      );
    });
  });
}
