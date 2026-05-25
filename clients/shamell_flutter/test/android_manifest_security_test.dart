import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'android release manifest keeps hardened defaults and no unused contact/media reads',
      () async {
    final manifest =
        await File('android/app/src/main/AndroidManifest.xml').readAsString();

    expect(
      manifest.contains('android.permission.READ_CONTACTS'),
      isFalse,
    );
    expect(
      manifest.contains('android.permission.READ_MEDIA_IMAGES'),
      isFalse,
    );
    expect(
      manifest.contains('android.permission.READ_EXTERNAL_STORAGE'),
      isFalse,
    );
    expect(
      manifest.contains('android.permission.WRITE_EXTERNAL_STORAGE'),
      isFalse,
    );
    expect(
      manifest.contains('android.permission.ACCESS_FINE_LOCATION'),
      isTrue,
    );
    expect(
      manifest.contains('android.permission.ACCESS_COARSE_LOCATION'),
      isTrue,
    );
    expect(
      manifest.contains('android.permission.ACCESS_BACKGROUND_LOCATION'),
      isFalse,
    );
    expect(
      manifest.contains('android.permission.CAMERA'),
      isTrue,
    );
    expect(
      manifest.contains('android.permission.POST_NOTIFICATIONS'),
      isTrue,
    );
    expect(
      manifest.contains('androidx.work.impl.diagnostics.DiagnosticsReceiver'),
      isTrue,
      reason:
          'main manifest should explicitly remove WorkManager diagnostics receiver from release merge',
    );
    expect(
      manifest.contains('androidx.profileinstaller.ProfileInstallReceiver'),
      isTrue,
      reason:
          'main manifest should explicitly remove profile installer receiver from release merge',
    );
    expect(
      manifest.contains('tools:node="remove"'),
      isTrue,
      reason:
          'release manifest should actively prune non-functional exported library receivers',
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="device_login"'),
      isFalse,
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="invite"'),
      isFalse,
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="friend"'),
      isFalse,
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="chat"'),
      isFalse,
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="moduleapp"'),
      isFalse,
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="moduleapps"'),
      isFalse,
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="official"'),
      isFalse,
    );
    expect(
      manifest.contains('android:scheme="shamell" android:host="moments"'),
      isFalse,
    );
    expect(
      manifest.contains(
          'android:scheme="https" android:host="online.shamell.online" android:pathPrefix="/app/device_login"'),
      isTrue,
    );
    expect(
      manifest.contains(
          'android:scheme="https" android:host="online.shamell.online" android:pathPrefix="/app/invite"'),
      isTrue,
    );
    expect(
      manifest.contains(
          'android:scheme="https" android:host="online.shamell.online" android:pathPrefix="/app/friend"'),
      isTrue,
    );
    expect(
      manifest.contains('android:allowBackup="false"'),
      isTrue,
    );
    expect(
      manifest.contains('android:usesCleartextTraffic="false"'),
      isTrue,
    );
    expect(
      manifest.contains('android:extractNativeLibs="false"'),
      isTrue,
    );
    expect(
      manifest
          .contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      isTrue,
    );
    expect(
      manifest.contains('android:fullBackupContent="@xml/backup_rules"'),
      isTrue,
    );
  });
}
