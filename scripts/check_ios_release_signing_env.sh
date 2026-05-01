#!/usr/bin/env bash
set -euo pipefail

require_prod="${REQUIRE_PRODUCTION_SIGNING:-false}"
require_upload="${REQUIRE_TESTFLIGHT_UPLOAD:-false}"

if [[ "$require_prod" != "true" ]]; then
  echo "[OK]   production iOS signing not required for this run"
  exit 0
fi

required=(
  IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64
  IOS_DISTRIBUTION_CERTIFICATE_PASSWORD
  IOS_PROVISIONING_PROFILE_BASE64
)

if [[ "$require_upload" == "true" ]]; then
  required+=(APP_STORE_CONNECT_API_KEY_JSON)
fi

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "[FAIL] missing required iOS signing env: $name" >&2
    exit 1
  fi
done

cert_path="${RUNNER_TEMP:-/tmp}/shamell-dist.p12"
profile_path="${RUNNER_TEMP:-/tmp}/shamell.mobileprovision"

printf '%s' "$IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64" | base64 --decode > "$cert_path"
printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$profile_path"

if [[ ! -s "$cert_path" || ! -s "$profile_path" ]]; then
  echo "[FAIL] decoded iOS signing files are empty" >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "IOS_CERT_PATH=$cert_path" >> "$GITHUB_ENV"
  echo "IOS_PROFILE_PATH=$profile_path" >> "$GITHUB_ENV"
fi

echo "[OK]   iOS signing environment is valid"
