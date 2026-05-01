# Shamell Ride Media Access Evidence

This document defines the regulator-facing evidence bundle for proving that the
released Android `Shamell Ride` customer app does not request camera or
microphone access.

Source code alone is not sufficient. The evidence must be tied to the final
release artifact.

## What counts as proof

The minimum acceptable proof set is:

1. the exact signed `Shamell Ride` APK that was released
2. its SHA-256 digest
3. a machine-generated inspection report from the final APK
4. the reconstructed final `AndroidManifest.xml` from that APK
5. the regression-test log that protects the ride flavor policy in source

Optional but useful supplementary evidence:

1. Android Settings screenshots showing the installed app has no Camera or
   Microphone permission entries
2. the CI workflow URL and artifact IDs for the release build
3. a short release-manager attestation that the attached hash matches the
   deployed APK

## Current technical controls

The rider surface is fail-closed at two layers:

1. Runtime gating in Flutter:
   - `clients/shamell_flutter/lib/core/media_access_policy.dart`
   - rider flows block camera capture, microphone capture, and realtime calls
2. Android flavor merge removal:
   - `clients/shamell_flutter/android/app/src/ride/AndroidManifest.xml`
   - explicitly removes:
     - `android.permission.CAMERA`
     - `android.permission.RECORD_AUDIO`
     - `android.permission.MODIFY_AUDIO_SETTINGS`
     - `android.hardware.camera`
     - `android.hardware.microphone`

## How to generate the evidence bundle

First build the signed Android APK bundle:

```bash
./scripts/build_android_release_apks.sh --output-dir .artifacts/android-apk-release
```

Then inspect the final `Shamell Ride` APK:

```bash
bash scripts/check_ride_android_media_access_absent.sh \
  --apk .artifacts/android-apk-release/shamell-ride-<version>.apk \
  --out-dir .artifacts/regulator-evidence
```

This produces:

1. `ride-media-access-report.txt`
2. `ride-media-access-report.json`
3. `ride-media-access-manifest.xml`

The check fails if any of these appear in the final APK:

1. `android.permission.CAMERA`
2. `android.permission.RECORD_AUDIO`
3. `android.permission.MODIFY_AUDIO_SETTINGS`
4. `android.hardware.camera`
5. `android.hardware.microphone`

It also fails if the APK application id is not `online.shamell.ride` or if the
APK is debuggable.

## Regression tests to attach

Run and archive these tests:

```bash
cd clients/shamell_flutter
flutter test \
  test/ride_media_policy_test.dart \
  test/android_ride_manifest_media_restrictions_test.dart
```

These tests prove:

1. the rider surface blocks camera, microphone, and call entry points
2. the Android `ride` flavor keeps the permission-removal manifest overlay in
   place

## Recommended regulator package

For each release, provide a zip or signed archive containing:

1. the released `Shamell Ride` APK
2. `ride-media-access-report.txt`
3. `ride-media-access-report.json`
4. `ride-media-access-manifest.xml`
5. the SHA-256 value in a release note or attestation file
6. the `flutter test` output for the two ride media tests
7. the CI workflow link and build timestamp

## Why this is stronger than a code screenshot

Android library manifests are merged during the build. The final APK can differ
from a source manifest because dependencies may add permissions or features.
The artifact inspection step closes that gap by proving what is actually inside
the released package.
