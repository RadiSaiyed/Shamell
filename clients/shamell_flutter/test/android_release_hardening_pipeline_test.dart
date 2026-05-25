import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android release pipeline keeps reverse-engineering hardening enabled',
      () async {
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    final fastlane = await File('android/fastlane/Fastfile').readAsString();
    final signingGuard =
        await File('../../scripts/check_android_release_signing_env.sh')
            .readAsString();
    final exportedSurfaceGuard =
        await File('../../scripts/check_android_exported_components.sh')
            .readAsString();
    final ciWorkflow =
        await File('../../.github/workflows/ci.yml').readAsString();
    final androidBetaWorkflow =
        await File('../../.github/workflows/flutter-android-beta.yml')
            .readAsString();
    final mainActivity = await File(
      'android/app/src/main/kotlin/online/shamell/app/MainActivity.kt',
    ).readAsString();

    expect(gradle.contains('isMinifyEnabled = true'), isTrue);
    expect(gradle.contains('isShrinkResources = true'), isTrue);
    expect(
      gradle.contains('isDebuggable = false'),
      isTrue,
      reason: 'release builds must fail closed with debuggable=false',
    );
    expect(
      gradle.contains('isJniDebuggable = false'),
      isTrue,
      reason: 'release builds must fail closed with jniDebuggable=false',
    );
    expect(
      gradle.contains('"EXPECTED_SIGNING_CERT_SHA256"'),
      isTrue,
      reason: 'release signing cert pin check must stay wired into BuildConfig',
    );
    expect(
      gradle.contains(
          'Android release builds require SHAMELL_ANDROID_SIGNING_CERT_SHA256'),
      isTrue,
      reason:
          'all Android release builds must fail closed without signing cert pinning',
    );
    expect(
      gradle.contains('"PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER"'),
      isTrue,
      reason: 'Play Integrity cloud project wiring must stay in release config',
    );
    expect(
      gradle.contains(
          'Android release builds require TRUSTED_TLS_CERTIFICATES_DER_BASE64'),
      isTrue,
      reason:
          'release builds must fail before shipping if the mobile TLS pin bundle is missing',
    );
    expect(
      gradle.contains('"ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS"'),
      isTrue,
      reason:
          'release config should wire an explicit emulator-QA bypass flag instead of weakening the default release path',
    );
    expect(
      gradle.contains(
          'SHAMELL_ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS must be false'),
      isTrue,
      reason:
          'production signing must reject emulator-QA runtime-integrity bypass builds',
    );

    expect(fastlane.contains('flutter build appbundle --release'), isTrue);
    expect(
      fastlane.contains('--obfuscate'),
      isTrue,
      reason: 'release builds must keep Dart symbol obfuscation enabled',
    );
    expect(
      fastlane.contains('--split-debug-info=build/app/outputs/symbols/android'),
      isTrue,
      reason:
          'release builds must keep split debug symbols for safe crash decoding',
    );

    expect(mainActivity.contains('WindowManager.LayoutParams.FLAG_SECURE'),
        isTrue);
    expect(mainActivity.contains('setRecentsScreenshotEnabled(false)'), isTrue);
    expect(mainActivity.contains('enforceReleaseRuntimeIntegrity()'), isTrue);
    expect(
      mainActivity.contains(
          'playIntegrityNonceB64Re = Regex("^[A-Za-z0-9_-]{16,256}\$")'),
      isTrue,
      reason:
          'Play Integrity nonce handling should enforce strict base64url length/charset bounds',
    );
    expect(
      mainActivity.contains('isValidPlayIntegrityNonceB64'),
      isTrue,
      reason:
          'Play Integrity nonce verification helper should remain wired for fail-closed input validation',
    );
    expect(
      mainActivity.contains('nonce_b64 invalid'),
      isTrue,
      reason:
          'method channel should reject malformed Play Integrity nonces before requesting tokens',
    );
    expect(mainActivity.contains('hook_framework_class'), isTrue);
    expect(
      mainActivity.contains('signals += "emulator"'),
      isTrue,
      reason:
          'release runtime integrity should fail closed on emulator-analysis environments',
    );
    expect(
      mainActivity.contains('signals += "non_user_build"'),
      isTrue,
      reason:
          'release runtime integrity should fail closed on userdebug/eng Android builds',
    );
    expect(
      mainActivity.contains('isQaEmulatorSignalSet'),
      isTrue,
      reason:
          'emulator-QA bypass should be scoped to the expected emulator-only signal set',
    );
    expect(
      mainActivity.contains('ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS'),
      isTrue,
      reason:
          'runtime integrity should only bypass on explicit emulator-QA builds',
    );
    expect(
      mainActivity.contains('"compromised" to false'),
      isTrue,
      reason:
          'emulator-QA bypass should suppress the compromised runtime page for expected emulator-only signal sets',
    );
    expect(
      mainActivity.contains('signals += "writable_system_mount"'),
      isTrue,
      reason:
          'release runtime integrity should fail closed when system partitions are mounted writable',
    );
    expect(
      mainActivity.contains('signals += "magisk_overlay_mount"'),
      isTrue,
      reason:
          'release runtime integrity should fail closed when magisk-like overlay mounts are detected',
    );
    expect(
      mainActivity.contains('signals += "frida_port_listener"'),
      isTrue,
      reason:
          'release runtime integrity should fail closed when local Frida listener ports are present',
    );
    expect(
      mainActivity.contains('if (expected.isEmpty()) return true'),
      isTrue,
      reason:
          'runtime integrity must fail closed when signing-cert pin fingerprint is missing',
    );
    expect(mainActivity.contains('signing_cert_mismatch'), isTrue);
    expect(
      signingGuard.contains('SHAMELL_ANDROID_SIGNING_CERT_SHA256'),
      isTrue,
      reason:
          'release signing guard must export signing certificate fingerprint',
    );
    expect(
      signingGuard.contains('mktemp'),
      isTrue,
      reason:
          'decoded release keystore material should use randomized temp file names',
    );
    expect(
      signingGuard.contains('chmod 600 "\$keystore_path"'),
      isTrue,
      reason: 'decoded release keystore material should be private on disk',
    );
    expect(
      signingGuard.contains('trap cleanup_temp_keystore EXIT'),
      isTrue,
      reason:
          'decoded release keystore material should be cleaned up when guard script exits',
    );
    expect(
      exportedSurfaceGuard.contains('online.shamell.app.MainActivity'),
      isTrue,
      reason:
          'exported-component guard must keep a strict allowlist anchored to MainActivity',
    );
    expect(
      exportedSurfaceGuard.contains(
          'io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver'),
      isTrue,
      reason:
          'exported-component guard should allow the FCM receiver that is required for push delivery',
    );
    expect(
      exportedSurfaceGuard
          .contains('com.google.firebase.iid.FirebaseInstanceIdReceiver'),
      isTrue,
      reason:
          'exported-component guard should allow the Play services IID receiver required by firebase_messaging',
    );
    expect(
      exportedSurfaceGuard
          .contains('androidx.work.impl.background.systemjob.SystemJobService'),
      isTrue,
      reason:
          'exported-component guard should allow the JobScheduler bridge exported only to the system',
    );
    expect(
      exportedSurfaceGuard.contains('unexpected exported Android components'),
      isTrue,
      reason:
          'exported-component guard must fail closed on unexpected exported components',
    );
    expect(
      ciWorkflow.contains('./scripts/check_android_exported_components.sh'),
      isTrue,
      reason: 'CI must enforce Android exported-component surface checks',
    );
    expect(
      androidBetaWorkflow
          .contains('../../scripts/check_android_exported_components.sh'),
      isTrue,
      reason:
          'release artifact workflow must audit merged manifest exported components',
    );
    expect(
      androidBetaWorkflow.contains('SHAMELL_ANDROID_MANIFEST_PATH'),
      isTrue,
      reason: 'merged-manifest guard should read explicit manifest path',
    );
    expect(
      androidBetaWorkflow.contains('mktemp'),
      isTrue,
      reason:
          'release keystore decode in Android beta workflow should use randomized temp files',
    );
  });
}
