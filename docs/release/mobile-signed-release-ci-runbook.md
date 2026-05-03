# Mobile Signed Release CI Runbook

## Goal
Run real signed release pipelines for Android and iOS in GitHub Actions and verify signing artifacts end-to-end.

Android release output now has two channels:
- signed `user` AAB for store-style archive/signoff use
- signed APK bundle for direct sideload distribution of:
  - `Shamell`
  - `Shamell Ride`
  - `Shamell Driver`
  - `Shamell Control`

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
    - `SHAMELL_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER`
    - `TRUSTED_TLS_CERTIFICATES_DER_BASE64`
  - iOS:
    - `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`
    - `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
    - `IOS_PROVISIONING_PROFILE_BASE64`
    - `APP_STORE_CONNECT_API_KEY_JSON` (required only when upload is enabled)
    - `TRUSTED_TLS_CERTIFICATES_DER_BASE64`

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
  - `Guard mobile release security env`
  - `Build appbundle`
  - `Verify AAB signature`
  - Signed AAB artifact uploaded
  - `Build signed APK bundle`
  - Signed APK bundle artifact uploaded
  - APK split-debug-info artifact uploaded and retained securely
  - Split-debug-info artifact uploaded and retained securely
- iOS job passes these checkpoints:
  - `Verify iOS signing environment`
  - `Guard mobile release security env`
  - `Install iOS signing assets`
  - `iOS build (signed IPA)`
  - `Verify IPA code signature`
  - Signed IPA artifact uploaded
  - Split-debug-info artifact uploaded and retained securely
  - `Fastlane beta (TestFlight)` when upload enabled and credentials present

## Release security guardrails
- Production-signed runs must not set `SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING=true`.
- Production-signed Android runs must set a positive Play Integrity cloud project number:
  - CI secret: `SHAMELL_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER`
  - Gradle property: `playIntegrityCloudProjectNumber`
- Flutter release builds must keep Dart obfuscation enabled:
  - `--obfuscate`
  - `--split-debug-info=<secure-path>`
- Release builds must not inject insecure Flutter defines such as:
  - `ALLOW_LEGACY_SESSION_FALLBACK_ON_MOBILE_IN_RELEASE=true`
  - `ALLOW_LEGACY_SESSION_FALLBACK_IN_RELEASE=true`
  - `ENABLE_MOBILE_SECURE_STORAGE=false`
  - `ENABLE_DESKTOP_SECURE_STORAGE=false`
- Production-signed runs must keep API origin trust fail-closed:
  - `BASE_URL` must remain an approved public `https://` API origin
  - if `TRUSTED_API_ORIGINS` is set, it must list only approved public `https://` origins
- Production-signed mobile runs must pin TLS trust explicitly:
  - `TRUSTED_TLS_CERTIFICATES_DER_BASE64` is required
  - format: semicolon-separated base64 DER certificates
  - release Flutter builds must pass `--dart-define=TRUSTED_TLS_CERTIFICATES_DER_BASE64=...`

### Generating `TRUSTED_TLS_CERTIFICATES_DER_BASE64`
Use the real release API origin and include the certificate(s) you want the app to trust, typically the active intermediate or explicit leaf + backup.

```bash
host="api.shamell.online"
tmpdir="$(mktemp -d)"
openssl s_client -showcerts -servername "$host" -connect "${host}:443" </dev/null 2>/dev/null \
  | awk -v dir="$tmpdir" '
      /BEGIN CERTIFICATE/ { n += 1; file = sprintf("%s/cert-%02d.pem", dir, n) }
      file { print >> file }
      /END CERTIFICATE/ { close(file); file = "" }
    '

bundle=""
for pem in "$tmpdir"/cert-*.pem; do
  der_b64="$(openssl x509 -in "$pem" -outform der | base64 | tr -d '\n')"
  if [ -n "$bundle" ]; then
    bundle="${bundle};${der_b64}"
  else
    bundle="${der_b64}"
  fi
done
printf '%s\n' "$bundle"
```

Store the printed value as the GitHub secret `TRUSTED_TLS_CERTIFICATES_DER_BASE64`.

Keep split-debug-info outputs out of public artifact channels. They are required for post-release symbolication and materially reduce the reverse-engineering value of shipped Flutter binaries.

## Direct APK distribution
After the Android workflow succeeds, download the artifact:
- `shamell-android-release-apks`

It contains:
- `index.html`
- `release-manifest.json`
- four signed production APKs

You can also build the same bundle locally:

```bash
./scripts/build_android_release_apks.sh --output-dir .artifacts/android-apk-release
```

Publish the bundle to the Hetzner static site after syncing Nginx:

```bash
./scripts/sync_hetzner_nginx.sh shamell
./scripts/publish_android_apk_downloads.sh \
  --source-dir .artifacts/android-apk-release \
  --host shamell
```

The production download URL is:

```text
https://shamell.online/downloads/android/
```

That page is the canonical non-Play-Store install path for all four Android apps.

For a one-button signed build + production publish path, dispatch:

```bash
gh workflow run "Android APK Publish"
```

That workflow expects these additional GitHub secrets:
- `SHAMELL_HETZNER_HOST`
- `SHAMELL_HETZNER_USER`
- `SHAMELL_HETZNER_SSH_PRIVATE_KEY`
- `SHAMELL_HETZNER_SUDO_PASSWORD` if the deploy user is not passwordless sudo
- `INTERNAL_API_SECRET` so `sync_hetzner_nginx.sh` can render the host-local
  internal-auth snippet non-interactively

## Shamell Control web release
Build the dedicated Flutter web console for `Shamell Control` locally:

```bash
./scripts/build_control_web_release.sh --output-dir .artifacts/control-web-release
```

That bundle targets:

```text
https://shamell.online/control/
```

Publish it after syncing Nginx:

```bash
./scripts/sync_hetzner_nginx.sh shamell
./scripts/publish_control_web_release.sh \
  --source-dir .artifacts/control-web-release \
  --host shamell
```

For a one-button CI path, dispatch:

```bash
gh workflow run "Shamell Control Web Publish"
```

That workflow expects the Hetzner secrets above plus these web Firebase secrets
when production web push/init should be enabled at build time:
- `SHAMELL_FIREBASE_API_KEY`
- `SHAMELL_FIREBASE_MESSAGING_SENDER_ID`
- `SHAMELL_FIREBASE_PROJECT_ID`
- `SHAMELL_FIREBASE_STORAGE_BUCKET`
- `SHAMELL_FIREBASE_AUTH_DOMAIN`
- `SHAMELL_FIREBASE_MEASUREMENT_ID`
- `SHAMELL_FIREBASE_WEB_APP_ID`

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
- Uploaded signed artifact IDs (AAB + APK bundle + IPA).
- Uploaded split-debug-info artifact IDs (Android AAB + Android APKs + iOS) and the secure retention location.
- Download URL verification for `https://shamell.online/downloads/android/` when shipping outside Play Store.
- Web URL verification for `https://shamell.online/control/` when shipping Shamell Control outside mobile-only flows.
- iOS TestFlight upload log (if enabled).
