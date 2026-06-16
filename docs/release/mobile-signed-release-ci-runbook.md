# Mobile Signed Release CI Runbook

## Goal
Run real signed release pipelines for Android and iOS in GitHub Actions and verify signing artifacts end-to-end.

## Preconditions
- Branch includes current workflow definitions:
  - `.github/workflows/flutter-android-beta.yml`
  - `.github/workflows/flutter-ios-beta.yml`
- Repo secrets configured:
  - Android:
    - `SHAMELL_RELEASE_STORE_BASE64`
    - `SHAMELL_RELEASE_STORE_PASSWORD`
    - `SHAMELL_RELEASE_KEY_ALIAS`
    - `SHAMELL_RELEASE_KEY_PASSWORD`
  - iOS:
    - `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`
    - `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
    - `IOS_PROVISIONING_PROFILE_BASE64`
    - `APP_STORE_CONNECT_API_KEY_JSON` (required only when upload is enabled)

## Dispatch commands
Run against the pushed branch containing the workflow updates.

```bash
gh workflow run "Flutter Android Beta (Build)" \
  --ref <branch> \
  -f require_production_signing=true \
  -f allow_debug_release_signing=false

gh workflow run "Flutter iOS Beta (TestFlight)" \
  --ref <branch> \
  -f require_production_signing=true \
  -f upload_testflight=true
```

## Verification criteria
- Android job passes these checkpoints:
  - `Verify Android signing environment`
  - `Build appbundle`
  - `Verify AAB signature`
  - Signed AAB artifact uploaded
- iOS job passes these checkpoints:
  - `Verify iOS signing environment`
  - `Install iOS signing assets`
  - `iOS build (signed IPA)`
  - `Verify IPA code signature`
  - Signed IPA artifact uploaded
  - `Fastlane beta (TestFlight)` when upload enabled and credentials present

## Fast triage
- Error: `Unexpected inputs provided`
  - Cause: remote branch still has old workflow schema.
  - Fix: push branch and dispatch again.
- Android signing env failure
  - Run local check with same env vars:
    - `./scripts/check_android_release_signing_env.sh`
- iOS signing env failure
  - Run local check with same env vars:
    - `./scripts/check_ios_release_signing_env.sh`

## Required evidence for release sign-off
- Links to successful Android and iOS workflow runs.
- Uploaded signed artifact IDs (AAB + IPA).
- iOS TestFlight upload log (if enabled).

