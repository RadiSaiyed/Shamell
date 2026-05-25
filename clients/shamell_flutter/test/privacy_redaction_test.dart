import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/privacy_redaction.dart';

void main() {
  group('privacy redaction helpers', () {
    test('masks phone numbers without exposing full values', () {
      expect(shamellMaskPhone('+963996428955'), '+963•••55');
      expect(shamellMaskPhone('0996428955'), '09•••55');
    });

    test('masks identifiers while keeping short edge cases safe', () {
      expect(
        shamellMaskIdentifier(
          '7aee4fc035fc939edced1e07677ba54abbc4b69312c49648b6f59ee9bae5ff5e',
          prefix: 6,
          suffix: 4,
        ),
        '7aee4f…ff5e',
      );
      expect(shamellMaskIdentifier('ab', prefix: 2, suffix: 2), '…');
    });

    test('masks vehicle plates and rounds coordinates', () {
      expect(shamellMaskVehiclePlate('SH001'), 'S…01');
      expect(
        shamellApproximateCoordinatePair(lat: 33.51405, lon: 36.3124),
        '33.51, 36.31',
      );
    });

    test('summarizes payloads without logging contents', () {
      expect(
        shamellPrivacySafePayloadSummary('{"ride_id":"abc","pickup":"secret"}'),
        'present(35 chars)',
      );
      expect(shamellPrivacySafePayloadSummary('   '), 'empty');
    });

    test('redacts phone numbers inside free-text previews', () {
      final preview = shamellPrivacySafeTextPreview(
        'Call me on +963996428955 after pickup at the gate.',
      );
      expect(preview, contains('+963•••55'));
      expect(preview, isNot(contains('+963996428955')));
    });

    test('shortens ride identifiers for lightweight surfaces', () {
      expect(shamellShortRideId('L17XG2SBRMIEQTBPPRF7284UUM'), 'L17XG2…');
      expect(shamellShortRideId('ride_1'), 'ride_1');
    });
  });
}
