#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${APP_DIR}/scripts/lib_internal_identity.sh"
ENV_FILE="${ENV_FILE:-${APP_DIR}/ops/pi/.env}"
WEBHOOK_URL="${SECURITY_ALERT_WEBHOOK_URL:-}"
WEBHOOK_INTERNAL_SECRET="${SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET:-}"
WEBHOOK_SERVICE_ID="${SECURITY_ALERT_WEBHOOK_SERVICE_ID:-security-reporter}"
WEBHOOK_SIGNING_SEED_B64="${SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64:-}"
WEBHOOK_AUDIENCE="${SECURITY_ALERT_WEBHOOK_AUDIENCE:-bff}"
SERVICE="${SECURITY_ALERT_DRILL_SERVICE:-${SECURITY_ALERT_SERVICE:-bff}}"
SEVERITY="${SECURITY_ALERT_DRILL_SEVERITY:-info}"
NOTE="${SECURITY_ALERT_DRILL_NOTE:-Synthetic drill event. No incident.}"
DRY_RUN=0
declare -a ALERTS=()

if [[ -n "${SECURITY_ALERT_DRILL_ALERTS:-}" ]]; then
  IFS=',' read -ra raw_alerts <<<"${SECURITY_ALERT_DRILL_ALERTS}"
  for raw in "${raw_alerts[@]}"; do
    alert="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$alert" ]] && continue
    ALERTS+=("$alert")
  done
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --alert)
      if [[ $# -lt 2 ]]; then
        echo "--alert requires a value" >&2
        exit 1
      fi
      ALERTS+=("$2")
      shift 2
      ;;
    --severity)
      if [[ $# -lt 2 ]]; then
        echo "--severity requires a value" >&2
        exit 1
      fi
      SEVERITY="$2"
      shift 2
      ;;
    --service)
      if [[ $# -lt 2 ]]; then
        echo "--service requires a value" >&2
        exit 1
      fi
      SERVICE="$2"
      shift 2
      ;;
    --note)
      if [[ $# -lt 2 ]]; then
        echo "--note requires a value" >&2
        exit 1
      fi
      NOTE="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: scripts/security_alert_webhook_drill.sh [--dry-run] [--alert <event:count/threshold>]... [--severity <info|warning|high|critical>] [--service <name>] [--note <text>]

Sends a synthetic security alert payload to SECURITY_ALERT_WEBHOOK_URL.
Reads URL from env var or ENV_FILE (default: ops/pi/.env).
If no --alert values are provided, defaults to webhook_drill.synthetic:1/1.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
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
  local severity="$4"
  local note="$5"
  shift 5
  local alerts=("$@")
  if have_cmd jq; then
    local alerts_json
    if ((${#alerts[@]} > 0)); then
      alerts_json="$(printf '%s\n' "${alerts[@]}" | jq -R . | jq -s .)"
    else
      alerts_json='[]'
    fi
    jq -n \
      --arg service "$service" \
      --arg timestamp "$timestamp" \
      --arg host "$host" \
      --arg severity "$severity" \
      --arg note "$note" \
      --argjson alerts "$alerts_json" \
      '{
        source: "shamell-security-webhook-drill",
        service: $service,
        timestamp: $timestamp,
        host: $host,
        severity: $severity,
        alerts: $alerts,
        note: $note
      }'
    return 0
  fi

  if have_cmd python3; then
    python3 - "$service" "$timestamp" "$host" "$severity" "$note" "${alerts[@]}" <<'PY'
import json
import sys

payload = {
    "source": "shamell-security-webhook-drill",
    "service": sys.argv[1],
    "timestamp": sys.argv[2],
    "host": sys.argv[3],
    "severity": sys.argv[4],
    "note": sys.argv[5],
    "alerts": sys.argv[6:],
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

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf "%s" "$s"
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
if [[ -z "$WEBHOOK_SIGNING_SEED_B64" ]]; then
  WEBHOOK_SIGNING_SEED_B64="$(read_env_file_var SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64)"
fi
if [[ -z "$WEBHOOK_AUDIENCE" ]]; then
  WEBHOOK_AUDIENCE="$(read_env_file_var SECURITY_ALERT_WEBHOOK_AUDIENCE)"
fi
if [[ -z "$WEBHOOK_INTERNAL_SECRET" && -z "$WEBHOOK_SIGNING_SEED_B64" ]]; then
  WEBHOOK_INTERNAL_SECRET="$(read_env_file_var INTERNAL_API_SECRET)"
fi
if [[ -n "$WEBHOOK_SERVICE_ID" ]]; then
  WEBHOOK_SERVICE_ID="$(internal_identity_normalize_service_id "$WEBHOOK_SERVICE_ID")"
fi
if [[ -n "$WEBHOOK_AUDIENCE" ]]; then
  WEBHOOK_AUDIENCE="$(internal_identity_normalize_audience "$WEBHOOK_AUDIENCE")"
fi

if [[ -z "$WEBHOOK_URL" ]]; then
  echo "SECURITY_ALERT_WEBHOOK_URL is empty (env var or ${ENV_FILE})." >&2
  exit 1
fi

if ! [[ "$SEVERITY" =~ ^(info|warning|high|critical)$ ]]; then
  echo "Invalid severity: ${SEVERITY}" >&2
  exit 1
fi

if [[ "${#ALERTS[@]}" -eq 0 ]]; then
  ALERTS=("webhook_drill.synthetic:1/1")
fi

for idx in "${!ALERTS[@]}"; do
  ALERTS[$idx]="$(trim "${ALERTS[$idx]}")"
  if [[ -z "${ALERTS[$idx]}" ]]; then
    echo "Alert values must be non-empty." >&2
    exit 1
  fi
done

payload="$(build_payload "$SERVICE" "$(date -u +%FT%TZ)" "$(hostname -f 2>/dev/null || hostname)" "$SEVERITY" "$NOTE" "${ALERTS[@]}")"

echo "Prepared webhook drill payload:"
pretty_print_payload "$payload"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run enabled; not sending webhook."
  exit 0
fi

require_cmd curl
curl_args=(-fsS -X POST -H "Content-Type: application/json")
payload_file="$(mktemp)"
trap 'rm -f "$payload_file"' EXIT
printf '%s' "$payload" > "$payload_file"
if [[ -n "$WEBHOOK_SIGNING_SEED_B64" ]]; then
  while IFS= read -r header; do
    curl_args+=(-H "$header")
  done < <(
    internal_identity_build_curl_headers \
      "$WEBHOOK_SIGNING_SEED_B64" \
      "$WEBHOOK_SERVICE_ID" \
      "$WEBHOOK_AUDIENCE" \
      "POST" \
      "$WEBHOOK_URL" \
      "$payload_file"
  )
elif [[ -n "$WEBHOOK_INTERNAL_SECRET" ]]; then
  curl_args+=(-H "X-Internal-Secret: ${WEBHOOK_INTERNAL_SECRET}")
fi
if [[ -n "$WEBHOOK_SERVICE_ID" && -z "$WEBHOOK_SIGNING_SEED_B64" ]]; then
  curl_args+=(-H "X-Internal-Service-Id: ${WEBHOOK_SERVICE_ID}")
fi
curl "${curl_args[@]}" --data "$payload" "$WEBHOOK_URL" >/dev/null
echo "Webhook drill sent successfully."
