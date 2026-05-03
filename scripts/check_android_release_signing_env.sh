#!/usr/bin/env bash
set -euo pipefail

require_prod="${REQUIRE_PRODUCTION_SIGNING:-false}"
allow_debug="${SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING:-false}"
play_integrity_project_number="${ORG_GRADLE_PROJECT_playIntegrityCloudProjectNumber:-${playIntegrityCloudProjectNumber:-${SHAMELL_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER:-}}}"
temporary_keystore_path=""
signing_env_out="${SHAMELL_ANDROID_SIGNING_ENV_OUT:-}"

append_persisted_env() {
  local name="$1"
  local value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_ENV"
  fi
  if [[ -n "${signing_env_out:-}" ]]; then
    printf '%s=%q\n' "$name" "$value" >> "$signing_env_out"
  fi
}

cleanup_temp_keystore() {
  if [[ -n "${temporary_keystore_path:-}" && -f "$temporary_keystore_path" ]]; then
    rm -f "$temporary_keystore_path"
  fi
}

trap cleanup_temp_keystore EXIT

if ! command -v keytool >/dev/null 2>&1; then
  echo "[FAIL] keytool is required to validate Android signing keystore" >&2
  exit 1
fi

if ! keytool -help >/dev/null 2>&1; then
  echo "[FAIL] keytool is present but no usable Java runtime is configured; install a JDK or set JAVA_HOME to a valid JDK before building Android release artifacts" >&2
  exit 1
fi

if [[ "$require_prod" == "true" && "$allow_debug" == "true" ]]; then
  echo "[FAIL] SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING must be false when REQUIRE_PRODUCTION_SIGNING=true" >&2
  exit 1
fi

have_release_keystore=false
if [[ -n "${SHAMELL_RELEASE_STORE_BASE64:-}" || -n "${SHAMELL_RELEASE_STORE_FILE:-}" ]]; then
  have_release_keystore=true
fi

if [[ "$have_release_keystore" != "true" && "$allow_debug" != "true" ]]; then
  echo "[FAIL] no Android signing material found and debug-signing override is disabled" >&2
  exit 1
fi

if [[ "$require_prod" == "true" && "$have_release_keystore" != "true" ]]; then
  echo "[FAIL] production Android signing required but release keystore is missing" >&2
  exit 1
fi

if [[ "$require_prod" == "true" ]]; then
  if [[ -z "${play_integrity_project_number:-}" ]]; then
    echo "[FAIL] production Android signing requires Play Integrity cloud project number via ORG_GRADLE_PROJECT_playIntegrityCloudProjectNumber or SHAMELL_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER" >&2
    exit 1
  fi
  if ! [[ "$play_integrity_project_number" =~ ^[0-9]+$ ]] || [[ "$play_integrity_project_number" == "0" ]]; then
    echo "[FAIL] Play Integrity cloud project number must be a positive integer, got: $play_integrity_project_number" >&2
    exit 1
  fi
fi

keystore_path=""
keystore_storepass=""
keystore_key_alias=""
keystore_keypass=""
signing_source=""

if [[ "$have_release_keystore" == "true" ]]; then
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
    keystore_path="$(mktemp "${RUNNER_TEMP:-/tmp}/shamell-release.keystore.XXXXXX")"
    temporary_keystore_path="$keystore_path"
    chmod 600 "$keystore_path"
    printf '%s' "$SHAMELL_RELEASE_STORE_BASE64" | base64 --decode > "$keystore_path"
    chmod 600 "$keystore_path"
    append_persisted_env "SHAMELL_RELEASE_STORE_FILE" "$keystore_path"
  fi

  keystore_storepass="${SHAMELL_RELEASE_STORE_PASSWORD}"
  keystore_key_alias="${SHAMELL_RELEASE_KEY_ALIAS}"
  keystore_keypass="${SHAMELL_RELEASE_KEY_PASSWORD}"
  signing_source="release-keystore"
else
  debug_keystore_path="${SHAMELL_DEBUG_RELEASE_STORE_FILE:-${HOME:-/tmp}/.android/debug.keystore}"
  debug_storepass="${SHAMELL_DEBUG_RELEASE_STORE_PASSWORD:-android}"
  debug_key_alias="${SHAMELL_DEBUG_RELEASE_KEY_ALIAS:-androiddebugkey}"
  debug_keypass="${SHAMELL_DEBUG_RELEASE_KEY_PASSWORD:-android}"

  if [[ ! -f "$debug_keystore_path" ]]; then
    mkdir -p "$(dirname "$debug_keystore_path")"
    keytool -genkeypair \
      -alias "$debug_key_alias" \
      -keyalg RSA \
      -keysize 2048 \
      -validity 36500 \
      -keystore "$debug_keystore_path" \
      -storepass "$debug_storepass" \
      -keypass "$debug_keypass" \
      -dname "CN=Android Debug,O=Android,C=US" \
      -noprompt >/dev/null 2>&1
  fi

  keystore_path="$debug_keystore_path"
  keystore_storepass="$debug_storepass"
  keystore_key_alias="$debug_key_alias"
  keystore_keypass="$debug_keypass"
  signing_source="debug-keystore"
fi

if [[ ! -f "$keystore_path" ]]; then
  echo "[FAIL] Android keystore file not found: $keystore_path" >&2
  exit 1
fi

if ! keytool -list \
  -keystore "$keystore_path" \
  -storepass "$keystore_storepass" \
  -keypass "$keystore_keypass" \
  -alias "$keystore_key_alias" >/dev/null 2>&1; then
  echo "[FAIL] Android keystore validation failed for alias '$keystore_key_alias'" >&2
  exit 1
fi

fingerprint_raw="$(keytool -list -v \
  -keystore "$keystore_path" \
  -storepass "$keystore_storepass" \
  -keypass "$keystore_keypass" \
  -alias "$keystore_key_alias" 2>/dev/null \
  | awk -F': ' '/SHA256:/{print $2; exit}')"
fingerprint="$(printf '%s' "${fingerprint_raw:-}" | tr -d '[:space:]:' | tr '[:upper:]' '[:lower:]')"
if ! [[ "$fingerprint" =~ ^[a-f0-9]{64}$ ]]; then
  echo "[FAIL] unable to derive valid SHA-256 signing fingerprint from keystore alias '$keystore_key_alias'" >&2
  exit 1
fi

owner_dn="$(keytool -list -v \
  -keystore "$keystore_path" \
  -storepass "$keystore_storepass" \
  -keypass "$keystore_keypass" \
  -alias "$keystore_key_alias" 2>/dev/null \
  | awk -F': ' '/Owner:/{print $2; exit}')"
alias_lower="$(printf '%s' "$keystore_key_alias" | tr '[:upper:]' '[:lower:]')"
owner_lower="$(printf '%s' "${owner_dn:-}" | tr '[:upper:]' '[:lower:]')"
if [[ "$signing_source" == "release-keystore" && "$allow_debug" != "true" ]]; then
  if [[ "$alias_lower" == "androiddebugkey" ]] || [[ "$owner_lower" == *"cn=android debug"* ]]; then
    echo "[FAIL] release keystore must not use the Android debug signing identity" >&2
    exit 1
  fi
fi

provided_fingerprint="$(printf '%s' "${SHAMELL_ANDROID_SIGNING_CERT_SHA256:-}" | tr -d '[:space:]:' | tr '[:upper:]' '[:lower:]')"
if [[ -n "$provided_fingerprint" && "$provided_fingerprint" != "$fingerprint" ]]; then
  echo "[FAIL] SHAMELL_ANDROID_SIGNING_CERT_SHA256 does not match keystore fingerprint" >&2
  exit 1
fi

export SHAMELL_ANDROID_SIGNING_CERT_SHA256="$fingerprint"
append_persisted_env "SHAMELL_ANDROID_SIGNING_CERT_SHA256" "$fingerprint"

if [[ -z "${SHAMELL_ANDROID_SIGNING_CERT_SHA256:-}" ]]; then
  echo "[FAIL] Android release signing checks require SHAMELL_ANDROID_SIGNING_CERT_SHA256" >&2
  exit 1
fi

echo "[OK]   Android signing environment is valid (${signing_source})"
