#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${APP_DIR}/ops/pi/.env}"
WEBHOOK_URL="${SECURITY_ALERT_WEBHOOK_URL:-}"
WEBHOOK_INTERNAL_SECRET="${SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET:-}"
WEBHOOK_SERVICE_ID="${SECURITY_ALERT_WEBHOOK_SERVICE_ID:-security-reporter}"
SERVICE="${SECURITY_ALERT_SERVICE:-bff}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: scripts/security_alert_webhook_drill.sh [--dry-run]

Sends a synthetic security alert payload to SECURITY_ALERT_WEBHOOK_URL.
Reads URL from env var or ENV_FILE (default: ops/pi/.env).
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

read_env_file_var() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf "%s" "$line"
}

build_payload() {
  local service="$1"
  local timestamp="$2"
  local host="$3"
  if have_cmd jq; then
    jq -n \
      --arg service "$service" \
      --arg timestamp "$timestamp" \
      --arg host "$host" \
      '{
        source: "shamell-security-webhook-drill",
        service: $service,
        timestamp: $timestamp,
        host: $host,
        severity: "info",
        alerts: [
          "webhook_drill.synthetic:1/1"
        ],
        note: "Synthetic drill event. No incident."
      }'
    return 0
  fi

  if have_cmd python3; then
    python3 - "$service" "$timestamp" "$host" <<'PY'
import json
import sys

payload = {
    "source": "shamell-security-webhook-drill",
    "service": sys.argv[1],
    "timestamp": sys.argv[2],
    "host": sys.argv[3],
    "severity": "info",
    "alerts": ["webhook_drill.synthetic:1/1"],
    "note": "Synthetic drill event. No incident.",
}
print(json.dumps(payload, separators=(",", ":")))
PY
    return 0
  fi

  echo "Missing required command: jq or python3" >&2
  return 1
}

pretty_print_payload() {
  local json="$1"
  if have_cmd jq; then
    printf "%s\n" "$json" | jq .
    return 0
  fi
  if have_cmd python3; then
    printf "%s\n" "$json" | python3 -m json.tool
    return 0
  fi
  printf "%s\n" "$json"
}

if [[ -z "$WEBHOOK_URL" ]]; then
  WEBHOOK_URL="$(read_env_file_var SECURITY_ALERT_WEBHOOK_URL)"
fi
if [[ -z "$WEBHOOK_INTERNAL_SECRET" ]]; then
  WEBHOOK_INTERNAL_SECRET="$(read_env_file_var SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET)"
fi
if [[ -z "$WEBHOOK_SERVICE_ID" ]]; then
  WEBHOOK_SERVICE_ID="$(read_env_file_var SECURITY_ALERT_WEBHOOK_SERVICE_ID)"
fi
if [[ -z "$WEBHOOK_INTERNAL_SECRET" ]]; then
  WEBHOOK_INTERNAL_SECRET="$(read_env_file_var INTERNAL_API_SECRET)"
fi

if [[ -z "$WEBHOOK_URL" ]]; then
  echo "SECURITY_ALERT_WEBHOOK_URL is empty (env var or ${ENV_FILE})." >&2
  exit 1
fi

payload="$(build_payload "$SERVICE" "$(date -u +%FT%TZ)" "$(hostname -f 2>/dev/null || hostname)")"

echo "Prepared webhook drill payload:"
pretty_print_payload "$payload"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run enabled; not sending webhook."
  exit 0
fi

require_cmd curl
curl_args=(-fsS -X POST -H "Content-Type: application/json")
if [[ -n "$WEBHOOK_INTERNAL_SECRET" ]]; then
  curl_args+=(-H "X-Internal-Secret: ${WEBHOOK_INTERNAL_SECRET}")
fi
if [[ -n "$WEBHOOK_SERVICE_ID" ]]; then
  curl_args+=(-H "X-Internal-Service-Id: ${WEBHOOK_SERVICE_ID}")
fi
curl "${curl_args[@]}" --data "$payload" "$WEBHOOK_URL" >/dev/null
echo "Webhook drill sent successfully."
