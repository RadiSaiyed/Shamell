import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ride manifest removes camera and microphone access from final merge',
      () async {
    final manifest =
        await File('android/app/src/ride/AndroidManifest.xml').readAsString();

    expect(
      manifest.contains('android.permission.CAMERA'),
      isTrue,
      reason:
          'ride flavor must explicitly remove the app/plugin camera permission',
    );
    expect(
      manifest.contains('android.permission.RECORD_AUDIO'),
      isTrue,
      reason:
          'ride flavor must explicitly remove plugin-added microphone permission',
    );
    expect(
      manifest.contains('android.permission.MODIFY_AUDIO_SETTINGS'),
      isTrue,
      reason:
          'ride flavor should also strip auxiliary audio-routing permission if merged later',
    );
    expect(
      manifest.contains('android.hardware.camera'),
      isTrue,
      reason: 'ride flavor must remove plugin-added camera hardware feature',
    );
    expect(
      manifest.contains('android.hardware.microphone'),
      isTrue,
      reason:
          'ride flavor should strip any microphone hardware feature declarations',
    );
    expect(
      RegExp('tools:node="remove"').allMatches(manifest).length,
      greaterThanOrEqualTo(5),
    );
  });
}
