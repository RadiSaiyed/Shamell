#!/usr/bin/env bash
set -euo pipefail

# Dev guard: approves a pending device-login challenge without requiring a mobile client.
# Intended for local PI test environments only.
#
# Flow:
# 1) Open https://127.0.0.1:8443/auth/device_login and click "Start new login QR".
# 2) Copy the token from the "shamell://device_login?token=..." line.
# 3) Run this script with that token; the browser page should sign in within a few seconds.
#
# This does NOT belong in a real production runbook.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${PI_ENV_FILE:-${ROOT}/ops/pi/.env}"
DB_CONTAINER="${PI_DB_CONTAINER:-pi-db-1}"

usage() {
  cat <<'EOF' >&2
Usage:
  ops/pi/dev_guard_approve_device_login.sh --token <32-hex> [--phone <e164>]

Options:
  --token   Required. The device-login token from the browser page.
  --phone   Optional. Phone to bind the browser session to. Default: +12025550123
  --yes     Required safety switch.

Env overrides:
  PI_ENV_FILE        Path to ops/pi/.env (default: ops/pi/.env)
  PI_DB_CONTAINER    Postgres container name (default: pi-db-1)
  DEV_GUARD_ALLOW_PROD=1  Allow running against ENV=prod|staging (not recommended)
EOF
}

read_env_file() {
  local key="$1"
  local file="$2"
  if [[ -z "$file" || ! -f "$file" ]]; then
    return 0
  fi
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf "%s" "$line"
}

YES="false"
TOKEN=""
PHONE="+12025550123"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)
      TOKEN="${2:-}"; shift 2;;
    --phone)
      PHONE="${2:-}"; shift 2;;
    --yes)
      YES="true"; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2;;
  esac
done

TOKEN="$(echo "${TOKEN}" | tr '[:upper:]' '[:lower:]' | xargs)"
PHONE="$(echo "${PHONE}" | xargs)"

if [[ "${YES}" != "true" ]]; then
  echo "Refusing to run without --yes (dev guard safety switch)." >&2
  exit 2
fi
if [[ -z "${TOKEN}" || ! "${TOKEN}" =~ ^[0-9a-f]{32}$ ]]; then
  echo "Invalid --token: expected 32 lowercase hex chars." >&2
  exit 2
fi
if [[ -z "${PHONE}" || ! "${PHONE}" =~ ^\+[0-9]{7,20}$ ]]; then
  echo "Invalid --phone: expected E.164 like +12025550123." >&2
  exit 2
fi

ENV_NAME="$(read_env_file ENV "${ENV_FILE}")"
ENV_LOWER="$(echo "${ENV_NAME:-}" | tr '[:upper:]' '[:lower:]' | xargs)"
if [[ "${ENV_LOWER}" =~ ^(prod|production|staging)$ ]] && [[ "${DEV_GUARD_ALLOW_PROD:-}" != "1" ]]; then
  echo "Refusing to run dev-guard against ENV=${ENV_NAME}. Set DEV_GUARD_ALLOW_PROD=1 to override (not recommended)." >&2
  exit 2
fi

if command -v rg >/dev/null 2>&1; then
  if ! docker ps --format '{{.Names}}' | rg -qx "${DB_CONTAINER}"; then
    echo "Postgres container not running: ${DB_CONTAINER}" >&2
    exit 1
  fi
else
  if ! docker ps --format '{{.Names}}' | grep -qx "${DB_CONTAINER}"; then
    echo "Postgres container not running: ${DB_CONTAINER}" >&2
    exit 1
  fi
fi

DB_URL="$(read_env_file DB_URL "${ENV_FILE}")"
DB_NAME="$(DB_URL="${DB_URL}" python3 - <<PY
import os, sys, urllib.parse
url = os.environ.get("DB_URL", "").strip()
if not url:
  sys.exit(0)
try:
  p = urllib.parse.urlparse(url)
  name = (p.path or "").lstrip("/")
  if name:
    print(name)
except Exception:
  pass
PY
)"

if [[ -z "${DB_NAME}" ]]; then
  DB_NAME="$(read_env_file POSTGRES_DB_CORE "${ENV_FILE}")"
fi
DB_NAME="${DB_NAME:-shamell_core}"

DB_USER="$(DB_URL="${DB_URL}" python3 - <<PY
import os, sys, urllib.parse
url = os.environ.get("DB_URL", "").strip()
if not url:
  sys.exit(0)
try:
  p = urllib.parse.urlparse(url)
  if p.username:
    print(p.username)
except Exception:
  pass
PY
)"
DB_USER="${DB_USER:-$(read_env_file POSTGRES_USER "${ENV_FILE}")}"
DB_USER="${DB_USER:-shamell}"

DB_PASS="$(DB_URL="${DB_URL}" python3 - <<PY
import os, sys, urllib.parse
url = os.environ.get("DB_URL", "").strip()
if not url:
  sys.exit(0)
try:
  p = urllib.parse.urlparse(url)
  if p.password:
    print(p.password)
except Exception:
  pass
PY
)"
DB_PASS="${DB_PASS:-$(read_env_file POSTGRES_PASSWORD "${ENV_FILE}")}"

TOKEN_HASH="$(TOKEN="${TOKEN}" python3 - <<PY
import hashlib, os
token = os.environ["TOKEN"].encode("utf-8")
print(hashlib.sha256(token).hexdigest())
PY
)"

SQL="UPDATE device_login_challenges SET status='approved', phone='${PHONE}', approved_at=NOW() WHERE token_hash='${TOKEN_HASH}' AND expires_at > NOW() RETURNING status || '|' || phone;"

OUT="$(docker exec -i \
  -e PGPASSWORD="${DB_PASS}" \
  "${DB_CONTAINER}" \
  psql -v ON_ERROR_STOP=1 -q -t -A -U "${DB_USER}" -d "${DB_NAME}" \
  -c "${SQL}" | tr -d '\r' | xargs || true)"

if [[ "${OUT}" == approved\|* ]]; then
  echo "Approved. The browser should sign in within a few seconds."
  exit 0
fi

echo "No pending challenge found (expired or already redeemed). Generate a new QR/token and retry." >&2
exit 1
