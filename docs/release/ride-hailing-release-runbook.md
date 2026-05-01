# Ride-Hailing Release Runbook

This is the canonical close-out and day-2 operations runbook for the Shamell
ride-hailing surfaces: `Shamell Ride`, `Shamell Driver`, and `Shamell Control`.

## 1. Pre-release backend gates

Production-safe read-only checks:

```bash
./scripts/ops.sh pipg ride-release-gate
./scripts/ops.sh pipg health
./scripts/ops.sh pipg smoke-api
./scripts/ops.sh pipg ride-report
./scripts/ops.sh pipg ride-repair-stale-presence --dry-run
bash scripts/check_mobile_firebase_flavors.sh
```

`ride-release-gate` is the canonical non-dev ride close-out. It runs
`schema-migrate bff`, `schema-migrate payments`, `health`, `smoke-api`, and
`ride-report` with `RIDE_REPORT_FAIL_ON_FINDINGS=1`.

`ride-report` is read-only and audits the main operational failure modes:

- stale `matching` rides
- `matching` rides with no pending dispatch offer
- stale pending dispatch offers
- stale online driver presence
- active rides with missing or stale live-state
- active rides missing an assigned driver
- stale reserved 10% driver fee holds

If stale online driver presence is already present in prod, use the explicit
repair command instead of waiting for opportunistic BFF reads:

```bash
./scripts/ops.sh pipg ride-repair-stale-presence --dry-run
./scripts/ops.sh pipg ride-repair-stale-presence
```

`check_mobile_firebase_flavors.sh` is the required mobile push preflight for the
ride surfaces. It fails when the per-flavor Android Firebase files are missing
or mismatched:

- `android/app/src/user/google-services.json`
- `android/app/src/ride/google-services.json`
- `android/app/src/driver/google-services.json`
- `android/app/src/operator/google-services.json`

If it fails, remote Rider/Driver/Control push will stay unavailable on-device
even if the backend push fanout and `FCM_SERVER_KEY` are otherwise configured.
The full setup and `--dart-define` fallback are documented in
`clients/shamell_flutter/FIREBASE_SETUP.md`.

Useful environment overrides:

```bash
RIDE_REPORT_FAIL_ON_FINDINGS=1
RIDE_REPORT_DETAIL_LIMIT=10
RIDE_REPORT_MATCHING_STALE_SECS=180
RIDE_REPORT_PENDING_OFFER_STALE_SECS=90
RIDE_REPORT_DRIVER_PRESENCE_STALE_SECS=45
RIDE_REPORT_LIVE_STATE_STALE_SECS=45
RIDE_REPORT_RESERVED_FEE_HOLD_STALE_SECS=900
```

Install the recurring Hetzner host timer after deploy:

```bash
./scripts/ops.sh pipg sync-ride-report-timer shamell --run-now
```

The repository CI also runs a dedicated `ride-gate` job on every push/PR and a
scheduled `Ride Gate Nightly` workflow. Both publish a markdown run summary and
artifact bundle; the nightly workflow keeps a single persistent GitHub issue
open while the gate is failing and closes it automatically after recovery.

## 2. Local end-to-end regression

Run the isolated local ride regression before merging or releasing backend ride
changes:

```bash
./scripts/ops.sh dev smoke-ride-flow
```

This covers:

- rider request creation
- `enter_matching`
- low-balance accept block
- driver top-up and accept
- rider/control live tracking
- `arrived -> started -> in_progress -> completed`
- driver reassign
- 10% hold reserve / release / settlement path

## 3. Device sanity checks

Minimum device matrix before release:

- `Shamell Ride`
  - submit ride request
  - receive rider notification on `driver_assigned` and `driver_arriving`
  - verify active-trip summary semantics remain visible in UI dump
- `Shamell Driver`
  - go online
  - receive audible dispatch notification
  - verify low-balance dispatch blocks `Accept`
  - verify `Need funds` opens wallet flow
- `Shamell Control`
  - verify live board loads even when one queue endpoint is degraded
  - verify `Reassign driver`
  - verify audible/visible operator alert on focus-trip transition

Before relying on any of the notification checks above, confirm that the build
does not show the in-app `Push unavailable in this build` warning card. If the
warning is visible, fix the Firebase flavor files first.

## 4. Regulator evidence for Shamell Ride

If you need black-and-white proof that the released Android rider app does not
request camera or microphone access, do not rely on source code alone. Produce
the evidence from the final signed APK:

```bash
./scripts/build_android_release_apks.sh --output-dir .artifacts/android-apk-release

bash scripts/check_ride_android_media_access_absent.sh \
  --apk .artifacts/android-apk-release/shamell-ride-<version>.apk \
  --out-dir .artifacts/regulator-evidence

(
  cd clients/shamell_flutter
  flutter test \
    test/ride_media_policy_test.dart \
    test/android_ride_manifest_media_restrictions_test.dart
)
```

Archive and hand over:

- the exact signed `Shamell Ride` APK
- the generated `ride-media-access-report.txt`
- the generated `ride-media-access-report.json`
- the generated `ride-media-access-manifest.xml`
- the APK SHA-256 digest
- the two ride media test logs

The detailed rationale and packaging checklist live in
`docs/security/ride-media-access-evidence.md`.

## 5. Required prod invariants

These must hold before sign-off:

- `https://api.shamell.online/health` returns `ok`
- no stale `matching` rides older than the agreed threshold
- no stale pending offers older than the agreed threshold
- no online drivers with stale presence beyond the agreed threshold
- no active trips missing a fresh live-state
- no stale reserved driver fee holds

## 6. Known operational boundaries

- Driver tracking currently uses Android foreground location and automatic
  stream rebind on app lifecycle resume/relaunch. This is robust for normal
  backgrounding and app restarts, but it is not a fully kill-proof native
  daemon.
- Rider/Driver/Control alerting is verified through local Android notifications.
  Full remote push additionally requires valid per-flavor Firebase mobile
  config and a configured `FCM_SERVER_KEY`.
- `ride-report` is intended for read-only audits and monitoring integration.
  It does not mutate data.
- The Hetzner `ride ops` timer runs `ride-report` with
  `RIDE_REPORT_FAIL_ON_FINDINGS=1` by default, so stuck ride state shows up as
  a failed `systemd` service instead of a silent warning.
