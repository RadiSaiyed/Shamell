#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${APP_DIR}/ops/pi/docker-compose.postgres.yml}"
ENV_FILE="${ENV_FILE:-${APP_DIR}/ops/pi/.env}"

WINDOW_SECS="${SECURITY_ALERT_WINDOW_SECS:-300}"
COOLDOWN_SECS="${SECURITY_ALERT_COOLDOWN_SECS:-600}"
SERVICE="${SECURITY_ALERT_SERVICE:-bff,chat}"
THRESHOLDS="${SECURITY_ALERT_THRESHOLDS:-device_login_approve.blocked:5,device_login_redeem.blocked:5,biometric_login.blocked:10,biometric_token_rotate.failed:1,auth_rate_limit_exceeded.blocked:30,chat_protocol_downgrade.blocked:1,chat_key_bundle_policy.blocked:1,chat_key_register_policy.blocked:1}"
WEBHOOK_URL="${SECURITY_ALERT_WEBHOOK_URL:-}"
WEBHOOK_INTERNAL_SECRET="${SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET:-}"
WEBHOOK_SERVICE_ID="${SECURITY_ALERT_WEBHOOK_SERVICE_ID:-security-reporter}"
STATE_FILE="${SECURITY_ALERT_STATE_FILE:-${APP_DIR}/.cache/security-alert-cooldowns.state}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf "%s" "$s"
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

value_or_env_file() {
  local key="$1"
  local current="$2"
  if [[ -n "$current" ]]; then
    printf "%s" "$current"
    return 0
  fi
  read_env_file_var "$key"
}

count_lookup() {
  local file="$1"
  local key="$2"
  awk -F'\t' -v k="$key" '$1 == k { print $2; found=1; exit } END { if (!found) print 0 }' "$file"
}

read_last_sent() {
  local key="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    printf "0"
    return 0
  fi
  awk -F'\t' -v k="$key" '$1 == k { print $2; found=1 } END { if (!found) print 0 }' "$file" | tail -n1
}

WINDOW_SECS="$(value_or_env_file SECURITY_ALERT_WINDOW_SECS "$WINDOW_SECS")"
COOLDOWN_SECS="$(value_or_env_file SECURITY_ALERT_COOLDOWN_SECS "$COOLDOWN_SECS")"
SERVICE="$(value_or_env_file SECURITY_ALERT_SERVICE "$SERVICE")"
THRESHOLDS="$(value_or_env_file SECURITY_ALERT_THRESHOLDS "$THRESHOLDS")"
WEBHOOK_URL="$(value_or_env_file SECURITY_ALERT_WEBHOOK_URL "$WEBHOOK_URL")"
WEBHOOK_INTERNAL_SECRET="$(value_or_env_file SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET "$WEBHOOK_INTERNAL_SECRET")"
WEBHOOK_SERVICE_ID="$(value_or_env_file SECURITY_ALERT_WEBHOOK_SERVICE_ID "$WEBHOOK_SERVICE_ID")"
if [[ -z "$WEBHOOK_INTERNAL_SECRET" ]]; then
  WEBHOOK_INTERNAL_SECRET="$(value_or_env_file INTERNAL_API_SECRET "")"
fi

IFS=',' read -ra raw_services <<< "$SERVICE"
declare -a compose_services=()
for raw in "${raw_services[@]}"; do
  svc="$(trim "$raw")"
  [[ -z "$svc" ]] && continue
  compose_services+=("$svc")
done
if [[ "${#compose_services[@]}" -eq 0 ]]; then
  compose_services=(bff chat)
fi
SERVICE_LABEL="$(IFS=,; echo "${compose_services[*]}")"

require_cmd docker

if ! [[ "$WINDOW_SECS" =~ ^[0-9]+$ ]]; then
  echo "SECURITY_ALERT_WINDOW_SECS must be an integer" >&2
  exit 1
fi
if ! [[ "$COOLDOWN_SECS" =~ ^[0-9]+$ ]]; then
  echo "SECURITY_ALERT_COOLDOWN_SECS must be an integer" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

events_file="${tmp_dir}/events.tsv"
combo_counts_file="${tmp_dir}/combo_counts.tsv"
event_counts_file="${tmp_dir}/event_counts.tsv"
alerts_file="${tmp_dir}/alerts.txt"
unsuppressed_file="${tmp_dir}/unsuppressed.txt"
state_work_file="${tmp_dir}/state_work.tsv"

compose_logs() {
  if [[ -f "$ENV_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
      logs --no-color --no-log-prefix --since "${WINDOW_SECS}s" "${compose_services[@]}" 2>/dev/null || true
  else
    docker compose -f "$COMPOSE_FILE" \
      logs --no-color --no-log-prefix --since "${WINDOW_SECS}s" "${compose_services[@]}" 2>/dev/null || true
  fi
}

parse_security_events_tsv() {
  if command -v jq >/dev/null 2>&1; then
    jq -Rr 'fromjson? | select(type=="object" and .security_event != null) | [.security_event, (.outcome // "na")] | @tsv'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import json
import sys

for raw in sys.stdin:
    line = raw.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if not isinstance(obj, dict):
        continue
    event = obj.get("security_event")
    if event is None:
        continue
    outcome = obj.get("outcome", "na")
    print(f"{event}\t{outcome}")
PY
    return 0
  fi
  echo "Missing required command: jq or python3" >&2
  return 1
}

build_webhook_payload() {
  local service="$1"
  local window_secs="$2"
  local alerts_file="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg service "$service" \
      --arg timestamp "$(date -u +%FT%TZ)" \
      --argjson window_secs "$window_secs" \
      --argjson alerts "$(jq -R . < "$alerts_file" | jq -s .)" \
      '{
        source: "shamell-security-events-report",
        service: $service,
        timestamp: $timestamp,
        window_secs: $window_secs,
        alerts: $alerts
      }'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$service" "$window_secs" "$alerts_file" <<'PY'
import datetime
import json
import sys

service = sys.argv[1]
window_secs = int(sys.argv[2])
alerts_path = sys.argv[3]
with open(alerts_path, "r", encoding="utf-8") as fh:
    alerts = [line.strip() for line in fh if line.strip()]
payload = {
    "source": "shamell-security-events-report",
    "service": service,
    "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "window_secs": window_secs,
    "alerts": alerts,
}
print(json.dumps(payload, separators=(",", ":")))
PY
    return 0
  fi
  echo "Missing required command for webhook payload: jq or python3" >&2
  return 1
}

compose_logs | parse_security_events_tsv > "$events_file"

if [[ -s "$events_file" ]]; then
  awk -F'\t' '{ print $1 "." $2 }' "$events_file" \
    | sort \
    | uniq -c \
    | awk '{ c=$1; $1=""; sub(/^ /, ""); print $0 "\t" c }' \
    > "$combo_counts_file"

  cut -f1 "$events_file" \
    | sort \
    | uniq -c \
    | awk '{ c=$1; $1=""; sub(/^ /, ""); print $0 "\t" c }' \
    > "$event_counts_file"
else
  : > "$combo_counts_file"
  : > "$event_counts_file"
fi

echo "Security event counts (last ${WINDOW_SECS}s, services=${SERVICE_LABEL}):"
if [[ ! -s "$combo_counts_file" ]]; then
  echo "  (no events)"
else
  awk -F'\t' '{ printf "  %s = %s\n", $1, $2 }' "$combo_counts_file"
fi

: > "$alerts_file"
IFS=',' read -ra rules <<< "$THRESHOLDS"
for raw_rule in "${rules[@]}"; do
  rule="$(trim "$raw_rule")"
  [[ -z "$rule" ]] && continue
  if [[ "$rule" != *:* ]]; then
    echo "Skipping invalid threshold rule (missing ':'): ${rule}" >&2
    continue
  fi
  key="$(trim "${rule%%:*}")"
  threshold="$(trim "${rule##*:}")"
  if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
    echo "Skipping invalid threshold (non-integer): ${rule}" >&2
    continue
  fi
  if [[ "$key" == *.* ]]; then
    count="$(count_lookup "$combo_counts_file" "$key")"
  else
    count="$(count_lookup "$event_counts_file" "$key")"
  fi
  if (( count >= threshold )); then
    printf "%s:%s/%s\n" "$key" "$count" "$threshold" >> "$alerts_file"
  fi
done

if [[ -f "$STATE_FILE" ]]; then
  cp "$STATE_FILE" "$state_work_file"
else
  : > "$state_work_file"
fi

: > "$unsuppressed_file"
now_epoch="$(date +%s)"
if [[ -s "$alerts_file" ]]; then
  while IFS= read -r alert; do
    key="${alert%%:*}"
    prev="$(read_last_sent "$key" "$state_work_file")"
    if ! [[ "$prev" =~ ^[0-9]+$ ]]; then
      prev=0
    fi
    age=$(( now_epoch - prev ))
    if (( prev > 0 && age < COOLDOWN_SECS )); then
      continue
    fi
    printf "%s\n" "$alert" >> "$unsuppressed_file"
    awk -F'\t' -v k="$key" '$1 != k' "$state_work_file" > "${state_work_file}.tmp"
    mv "${state_work_file}.tmp" "$state_work_file"
    printf "%s\t%s\n" "$key" "$now_epoch" >> "$state_work_file"
  done < "$alerts_file"
fi

if [[ -s "$alerts_file" ]]; then
  echo
  echo "ALERT thresholds crossed:"
  while IFS= read -r alert; do
    echo "  - ${alert}"
  done < "$alerts_file"
fi

mkdir -p "$(dirname "$STATE_FILE")"
sort -u "$state_work_file" > "$STATE_FILE"

if [[ -n "$WEBHOOK_URL" && -s "$unsuppressed_file" ]]; then
  require_cmd curl
  payload="$(build_webhook_payload "$SERVICE_LABEL" "$WINDOW_SECS" "$unsuppressed_file")"
  curl_args=(-fsS -X POST -H "Content-Type: application/json")
  if [[ -n "$WEBHOOK_INTERNAL_SECRET" ]]; then
    curl_args+=(-H "X-Internal-Secret: ${WEBHOOK_INTERNAL_SECRET}")
  fi
  if [[ -n "$WEBHOOK_SERVICE_ID" ]]; then
    curl_args+=(-H "X-Internal-Service-Id: ${WEBHOOK_SERVICE_ID}")
  fi
  curl "${curl_args[@]}" --data "$payload" "$WEBHOOK_URL" >/dev/null
fi

if [[ -s "$alerts_file" ]]; then
  exit 2
fi
exit 0
