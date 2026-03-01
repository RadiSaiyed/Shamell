#!/usr/bin/env bash
set -euo pipefail

require_prod="${REQUIRE_PRODUCTION_SIGNING:-false}"
allow_debug="${SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING:-false}"

have_keystore=false
if [[ -n "${SHAMELL_RELEASE_STORE_BASE64:-}" || -n "${SHAMELL_RELEASE_STORE_FILE:-}" ]]; then
  have_keystore=true
fi

if [[ "$require_prod" != "true" && "$have_keystore" != "true" ]]; then
  if [[ "$allow_debug" == "true" ]]; then
    echo "[OK]   production Android signing not required and debug-signing override is enabled"
    exit 0
  fi
  echo "[FAIL] no Android signing material found and debug-signing override is disabled" >&2
  exit 1
fi

if [[ "$have_keystore" != "true" ]]; then
  echo "[FAIL] production Android signing required but keystore is missing" >&2
  exit 1
fi

for name in SHAMELL_RELEASE_STORE_PASSWORD SHAMELL_RELEASE_KEY_ALIAS SHAMELL_RELEASE_KEY_PASSWORD; do
  if [[ -z "${!name:-}" ]]; then
    echo "[FAIL] missing required Android signing env: $name" >&2
    exit 1
  fi
done

keystore_path="${SHAMELL_RELEASE_STORE_FILE:-}"
if [[ -z "$keystore_path" ]]; then
  if [[ -z "${SHAMELL_RELEASE_STORE_BASE64:-}" ]]; then
    echo "[FAIL] no SHAMELL_RELEASE_STORE_FILE and SHAMELL_RELEASE_STORE_BASE64 is empty" >&2
    exit 1
  fi
  keystore_path="${RUNNER_TEMP:-/tmp}/shamell-release.keystore"
  printf '%s' "$SHAMELL_RELEASE_STORE_BASE64" | base64 --decode > "$keystore_path"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "SHAMELL_RELEASE_STORE_FILE=$keystore_path" >> "$GITHUB_ENV"
  fi
fi

if [[ ! -f "$keystore_path" ]]; then
  echo "[FAIL] Android keystore file not found: $keystore_path" >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "[FAIL] keytool is required to validate Android signing keystore" >&2
  exit 1
fi

if ! keytool -list \
  -keystore "$keystore_path" \
  -storepass "$SHAMELL_RELEASE_STORE_PASSWORD" \
  -alias "$SHAMELL_RELEASE_KEY_ALIAS" >/dev/null 2>&1; then
  echo "[FAIL] Android keystore validation failed for alias '$SHAMELL_RELEASE_KEY_ALIAS'" >&2
  exit 1
fi

echo "[OK]   Android signing environment is valid"
