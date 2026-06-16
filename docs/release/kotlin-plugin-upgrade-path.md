# Android Kotlin/Plugin Upgrade Path (flutter_webrtc)

## Baseline (2026-03-01)
- Kotlin Gradle Plugin (KGP): `2.2.21` in `clients/shamell_flutter/android/settings.gradle.kts`
- `flutter_webrtc`: `^1.3.1` in `clients/shamell_flutter/pubspec.yaml`
- iOS Pod lock guard: `scripts/check_ios_webrtc_pod_lock_sync.sh`
- Android KGP/WebRTC guard: `scripts/check_kotlin_webrtc_compat.sh`

## Why this path is fixed
- `flutter_webrtc` Android build internals are sensitive to KGP/AGP jumps.
- Moving KGP first can break Android plugin builds before Dart code compiles.
- CI now blocks unsafe combinations with `check_kotlin_webrtc_compat.sh`.

## Upgrade order (must keep this sequence)
1. Upgrade `flutter_webrtc` first on current KGP baseline (`2.2.21`).
2. Run:
   - `flutter pub upgrade`
   - `./scripts/check_kotlin_webrtc_compat.sh`
   - `./scripts/check_ios_webrtc_pod_lock_sync.sh`
   - `flutter analyze`
   - `flutter test`
   - `flutter build ios --release --no-codesign`
3. If step 2 is green, then bump KGP (`android/settings.gradle.kts`) and validate Android build in CI.
4. Keep guard script thresholds aligned with the proven version pair from CI.

## CI gates that must stay enabled
- `.github/workflows/ci.yml`:
  - `Guard Kotlin/flutter_webrtc compatibility`
  - `Guard iOS flutter_webrtc Pod lock sync`
- Block merges if either gate fails.

## Known failure signatures
- `Unexpected inputs provided` when dispatching workflow:
  - Remote branch has old workflow file; push branch first.
- iOS CocoaPods mismatch for WebRTC-SDK version:
  - run `./scripts/check_ios_webrtc_pod_lock_sync.sh`
  - then refresh Pod lock and commit.
