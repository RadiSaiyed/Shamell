import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/core/media_access_policy.dart';

void main() {
  test('ride rider surface blocks camera, microphone, and calls', () {
    expect(shamellAllowsCameraCapture(ShamellAppSurface.ride), isFalse);
    expect(shamellAllowsMicrophoneCapture(ShamellAppSurface.ride), isFalse);
    expect(shamellAllowsRealtimeCalls(ShamellAppSurface.ride), isFalse);
  });

  test('non-rider surfaces keep media access enabled', () {
    for (final surface in <ShamellAppSurface>[
      ShamellAppSurface.superapp,
      ShamellAppSurface.driver,
      ShamellAppSurface.operator,
    ]) {
      expect(shamellAllowsCameraCapture(surface), isTrue);
      expect(shamellAllowsMicrophoneCapture(surface), isTrue);
      expect(shamellAllowsRealtimeCalls(surface), isTrue);
    }
  });
}
