#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/configure_account_create_attestation.sh \
    --env-file ops/pi/.env \
    --apple-team-id <TEAM_ID> \
    --apple-key-id <KEY_ID> \
    --apple-p8-file <path/to/AuthKey_XXXX.p8> \
    --google-sa-json-file <path/to/play-integrity-sa.json> \
    [--google-packages "online.shamell.app,online.shamell.app.operator,online.shamell.app.admin"]

Notes:
  - Writes/updates attestation vars in the env file.
  - Does not print secret values.
  - Enforces strict account-create attestation flags.
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

set_or_add() {
  local key="$1"
  local value="$2"
  local file="$3"
  if rg -q "^${key}=" "$file"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

ENV_FILE="ops/pi/.env"
APPLE_TEAM_ID=""
APPLE_KEY_ID=""
APPLE_P8_FILE=""
GOOGLE_SA_JSON_FILE=""
GOOGLE_PACKAGES="online.shamell.app,online.shamell.app.operator,online.shamell.app.admin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --apple-team-id)
      APPLE_TEAM_ID="${2:-}"
      shift 2
      ;;
    --apple-key-id)
      APPLE_KEY_ID="${2:-}"
      shift 2
      ;;
    --apple-p8-file)
      APPLE_P8_FILE="${2:-}"
      shift 2
      ;;
    --google-sa-json-file)
      GOOGLE_SA_JSON_FILE="${2:-}"
      shift 2
      ;;
    --google-packages)
      GOOGLE_PACKAGES="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ENV_FILE" || -z "$APPLE_TEAM_ID" || -z "$APPLE_KEY_ID" || -z "$APPLE_P8_FILE" || -z "$GOOGLE_SA_JSON_FILE" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi
if [[ ! -f "$APPLE_P8_FILE" ]]; then
  echo "Apple p8 file not found: $APPLE_P8_FILE" >&2
  exit 1
fi
if [[ ! -f "$GOOGLE_SA_JSON_FILE" ]]; then
  echo "Google service-account json file not found: $GOOGLE_SA_JSON_FILE" >&2
  exit 1
fi
if [[ -z "$GOOGLE_PACKAGES" ]]; then
  echo "--google-packages must not be empty" >&2
  exit 1
fi

require_cmd rg
require_cmd sed
require_cmd openssl

APPLE_P8_B64="$(openssl base64 -A <"$APPLE_P8_FILE")"
GOOGLE_SA_JSON_B64="$(openssl base64 -A <"$GOOGLE_SA_JSON_FILE")"

set_or_add AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED true "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION true "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_POW_ENABLED true "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID "$APPLE_TEAM_ID" "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID "$APPLE_KEY_ID" "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 "$APPLE_P8_B64" "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 "$GOOGLE_SA_JSON_B64" "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES "$GOOGLE_PACKAGES" "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY true "$ENV_FILE"
set_or_add AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED true "$ENV_FILE"

echo "Updated attestation settings in ${ENV_FILE}"
