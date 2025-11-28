# Fastlane Packaging (iOS & Android)

This app includes minimal fastlane lanes to build and upload releases.

## iOS (TestFlight)
Requirements:
- Xcode + command line tools
- App Store Connect account
- Bundle ID set in ios/Runner (Appfile placeholder currently com.example.shamell)
- App Store Connect API key (recommended) or Apple ID session

Lanes (from `clients/shamell_flutter/ios`):
- `bundle exec fastlane build` → `flutter build ipa --release`
- `bundle exec fastlane beta` → Upload to TestFlight (configure API key or Apple ID)

## Android (Play Console)
Requirements:
- Service account JSON with access to your Play Console app
- `applicationId` set in `android/app/build.gradle`

Lanes (from `clients/shamell_flutter/android`):
- `bundle exec fastlane build` → `flutter build appbundle --release`
- `bundle exec fastlane beta` → `supply` upload to Internal track

## CI (optional)
- Add GitHub Actions that set up Flutter and run the above lanes, with secrets for Apple/Play.
- Ensure to add NSCameraUsageDescription in iOS Info.plist for QR scanning.
