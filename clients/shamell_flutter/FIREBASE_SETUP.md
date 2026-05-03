Firebase in this repo is not fully configured out of the box. The checked-in
`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, and
`lib/firebase_options.dart` values are placeholders.

Android flavors

- `user` -> `online.shamell.app`
- `ride` -> `online.shamell.ride`
- `driver` -> `online.shamell.driver`
- `operator` -> `online.shamell.operator`

Recommended Android setup

1. Create a Firebase Android app for each package name above.
2. Download each matching `google-services.json`.
3. Either place them manually at:
   - `android/app/src/user/google-services.json`
   - `android/app/src/ride/google-services.json`
   - `android/app/src/driver/google-services.json`
   - `android/app/src/operator/google-services.json`
4. Or install them from a secure local directory with:

```sh
bash scripts/install_mobile_firebase_flavors.sh /absolute/path/to/firebase-config-dir
```

Expected source filenames for the install script:

- `user.google-services.json`
- `ride.google-services.json`
- `driver.google-services.json`
- `operator.google-services.json`

The Android Gradle module enables the `com.google.gms.google-services` plugin
only when the currently requested flavor has a non-placeholder config file that
contains the matching package name.

You can validate the local flavor wiring at any time with:

```sh
bash scripts/check_mobile_firebase_flavors.sh
```

You can also derive Flutter-side `--dart-define` flags directly from those
installed Android configs:

```sh
bash scripts/print_mobile_firebase_dart_defines.sh
```

This emits shell-quoted flags such as:

```sh
--dart-define=SHAMELL_FIREBASE_API_KEY=...
--dart-define=SHAMELL_FIREBASE_MESSAGING_SENDER_ID=...
--dart-define=SHAMELL_FIREBASE_PROJECT_ID=...
--dart-define=SHAMELL_FIREBASE_ANDROID_APP_ID_OPERATOR=...
```

Optional Dart-define fallback

If you need Flutter-side Firebase options before native files are in place, the
app can also initialize Firebase from `--dart-define` values:

- `SHAMELL_FIREBASE_API_KEY`
- `SHAMELL_FIREBASE_MESSAGING_SENDER_ID`
- `SHAMELL_FIREBASE_PROJECT_ID`
- `SHAMELL_FIREBASE_STORAGE_BUCKET`
- `SHAMELL_FIREBASE_AUTH_DOMAIN`
- `SHAMELL_FIREBASE_MEASUREMENT_ID`
- `SHAMELL_FIREBASE_ANDROID_APP_ID_SUPERAPP`
- `SHAMELL_FIREBASE_ANDROID_APP_ID_RIDE`
- `SHAMELL_FIREBASE_ANDROID_APP_ID_DRIVER`
- `SHAMELL_FIREBASE_ANDROID_APP_ID_OPERATOR`
- `SHAMELL_FIREBASE_IOS_APP_ID_SUPERAPP`
- `SHAMELL_FIREBASE_IOS_APP_ID_RIDE`
- `SHAMELL_FIREBASE_IOS_APP_ID_DRIVER`
- `SHAMELL_FIREBASE_IOS_APP_ID_OPERATOR`
- `SHAMELL_FIREBASE_IOS_BUNDLE_ID_SUPERAPP`
- `SHAMELL_FIREBASE_IOS_BUNDLE_ID_RIDE`
- `SHAMELL_FIREBASE_IOS_BUNDLE_ID_DRIVER`
- `SHAMELL_FIREBASE_IOS_BUNDLE_ID_OPERATOR`
- `SHAMELL_FIREBASE_WEB_APP_ID`
- `SHAMELL_FIREBASE_MACOS_APP_ID`

Example

```sh
flutter build apk --debug \
  --flavor operator \
  -t lib/main_operator.dart \
  --dart-define=BASE_URL=http://127.0.0.1:8080 \
  --dart-define=SHAMELL_FIREBASE_API_KEY=... \
  --dart-define=SHAMELL_FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=SHAMELL_FIREBASE_PROJECT_ID=... \
  --dart-define=SHAMELL_FIREBASE_ANDROID_APP_ID_OPERATOR=...
```

iOS

The iOS project is still a single target in this repo, not a full flavor/scheme
matrix. To enable Firebase there, replace the placeholder
`ios/Runner/GoogleService-Info.plist` with a real file for the active bundle id,
or extend the Xcode project to use per-scheme plist files.
