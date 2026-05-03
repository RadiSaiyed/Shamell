#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_SCRIPT="${ROOT}/scripts/security_events_report.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="${tmp_dir}/security-events.jsonl"
state_file="${tmp_dir}/security-alert-cooldowns.state"

cat >"$log_file" <<'EOF'
{"security_event":"chat_prekey_inventory","outcome":"low","inventory_source":"status_check","device_id_hash":"111111111111"}
{"security_event":"chat_prekey_inventory","outcome":"low","inventory_source":"bundle_fetch","device_id_hash":"222222222222"}
{"security_event":"chat_prekey_inventory","outcome":"low","inventory_source":"bundle_fetch","device_id_hash":"333333333333"}
{"security_event":"chat_key_bootstrap_policy","outcome":"blocked","reason":"protocol_v2_disabled"}
{"security_event":"device_login_approve","outcome":"blocked"}
not-json
EOF

set +e
output="$(
  ENV_FILE="${tmp_dir}/nonexistent.env" \
  SECURITY_ALERT_STATE_FILE="$state_file" \
  SECURITY_ALERT_COOLDOWN_SECS=0 \
  SECURITY_ALERT_SERVICE="replay" \
  "$REPORT_SCRIPT" --log-file "$log_file" 2>&1
)"
status=$?
set -e

if [[ "$status" != "2" ]]; then
  echo "[FAIL] security_events_report replay exited with ${status}, expected 2" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

require_output() {
  local needle="$1"
  local label="$2"
  if grep -Fq "$needle" <<<"$output"; then
    echo "[OK]   $label"
  else
    echo "[FAIL] $label" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

require_absent() {
  local needle="$1"
  local label="$2"
  if grep -Fq "$needle" <<<"$output"; then
    echo "[FAIL] $label" >&2
    printf '%s\n' "$output" >&2
    exit 1
  else
    echo "[OK]   $label"
  fi
}

require_output "chat_prekey_inventory.low = 3" "counted chat_prekey_inventory.low from replay log"
require_output "chat_key_bootstrap_policy.blocked = 1" "counted chat_key_bootstrap_policy.blocked from replay log"
require_output "chat_prekey_inventory.low:3/3" "threshold fired for chat_prekey_inventory.low"
require_output "chat_key_bootstrap_policy.blocked:1/1" "threshold fired for chat_key_bootstrap_policy.blocked"
require_output "Replay mode active; webhook delivery disabled unless SECURITY_ALERT_WEBHOOK_URL is explicitly set." "replay mode stays fail-closed on webhook delivery"
require_absent "device_login_approve.blocked:1/5" "sub-threshold events do not alert"

echo "Security alert report replay check passed."
