# Fastlane Packaging (iOS & Android)

This app includes minimal fastlane lanes to build and upload releases.

## iOS (TestFlight)
Requirements:
- Xcode + command line tools
- App Store Connect account
- Bundle ID set in iOS project (currently `online.shamell.app`)
- App Store Connect API key (recommended) or Apple ID session

Lanes (from `clients/shamell_flutter/ios`):
- `bundle exec fastlane build` → `flutter build ipa --release`
- `bundle exec fastlane beta` → Upload to TestFlight (configure API key or Apple ID)

## Android (Build and optional Play Console upload)
Requirements:
- App package configured as `online.shamell.app` (user flavor)
- Play Console access (optional; only if you want automated uploads)
- Release signing credentials via Gradle properties or env vars:
  `SHAMELL_RELEASE_STORE_FILE`, `SHAMELL_RELEASE_STORE_PASSWORD`,
  `SHAMELL_RELEASE_KEY_ALIAS`, `SHAMELL_RELEASE_KEY_PASSWORD`

Lanes (from `clients/shamell_flutter/android`):
- `bundle exec fastlane build` → `flutter build appbundle --release --flavor user`
- `bundle exec fastlane beta` → `supply` upload to Internal track for `online.shamell.app`

If/when Play access is available, set the JSON secret in GitHub Actions (optional):
- `gh secret set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON --repo RadiSaiyed/Shamell < /absolute/path/to/play-service-account.json`

## CI (optional)
- Current repo workflows build artifacts only; uploading to App Store Connect / Play Console is optional.
- If you enable uploads, add secrets for Apple/Play and run the above fastlane lanes in CI.
- Ensure to add NSCameraUsageDescription in iOS Info.plist for QR scanning.
