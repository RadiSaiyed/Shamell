# Build Instructions – Android APK for Regulator

## Prerequisites

- Flutter SDK installed (version compatible with the `environment` in `pubspec.yaml`).  
- Android SDK / Android Studio installed.  
- Repository checked out, working directory: `clients/shamell_flutter`.

## Debug build (for internal testing)

```bash
cd clients/shamell_flutter
flutter pub get
flutter build apk --debug
```

The debug APK will be created at:

- `build/app/outputs/flutter-apk/app-debug.apk`

## Release build (for regulator submission)

1. **Optional: configure your own signing key**  
   - Place a keystore under `android/app` and reference it from `android/app/build.gradle.kts`.  
   - For non‑production review, debug signing can be used if agreed with the regulator.

2. **Build the release APK**

```bash
cd clients/shamell_flutter
flutter pub get
flutter build apk --release
```

The release APK will be created at:

- `build/app/outputs/flutter-apk/app-release.apk`

## Integrity check (optional)

On macOS/Linux:

```bash
cd clients/shamell_flutter
shasum -a 256 build/app/outputs/flutter-apk/app-release.apk
```

Record the resulting SHA256 hash in a small README and provide it alongside the APK so the regulator can verify integrity.

