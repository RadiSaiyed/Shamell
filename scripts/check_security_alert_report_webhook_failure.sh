#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_SCRIPT="${ROOT}/scripts/security_events_report.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="${tmp_dir}/security-events.jsonl"
state_file="${tmp_dir}/security-alert-cooldowns.state"

cat >"$log_file" <<'EOF'
{"security_event":"chat_key_bootstrap_policy","outcome":"blocked","reason":"protocol_v2_disabled"}
EOF

set +e
output="$(
  ENV_FILE="${tmp_dir}/nonexistent.env" \
  SECURITY_ALERT_STATE_FILE="$state_file" \
  SECURITY_ALERT_COOLDOWN_SECS=600 \
  SECURITY_ALERT_SERVICE="replay" \
  SECURITY_ALERT_WEBHOOK_URL="http://127.0.0.1:1/internal/security/alerts" \
  SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET="test-secret" \
  "$REPORT_SCRIPT" --log-file "$log_file" 2>&1
)"
status=$?
set -e

if [[ "$status" == "0" || "$status" == "2" ]]; then
  echo "[FAIL] expected webhook delivery failure, got exit ${status}" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if [[ -s "$state_file" ]]; then
  echo "[FAIL] failed webhook delivery must not persist cooldown state" >&2
  cat "$state_file" >&2
  exit 1
else
  echo "[OK]   failed webhook delivery does not persist cooldown state"
fi

set +e
replay_output="$(
  ENV_FILE="${tmp_dir}/nonexistent.env" \
  SECURITY_ALERT_STATE_FILE="$state_file" \
  SECURITY_ALERT_COOLDOWN_SECS=600 \
  SECURITY_ALERT_SERVICE="replay" \
  "$REPORT_SCRIPT" --log-file "$log_file" 2>&1
)"
replay_status=$?
set -e

if [[ "$replay_status" != "2" ]]; then
  echo "[FAIL] expected second replay run to alert again after failed webhook, got exit ${replay_status}" >&2
  printf '%s\n' "$replay_output" >&2
  exit 1
fi

if grep -Fq "chat_key_bootstrap_policy.blocked:1/1" <<<"$replay_output"; then
  echo "[OK]   alert retriggers after failed webhook delivery"
else
  echo "[FAIL] expected alert to retrigger after failed webhook delivery" >&2
  printf '%s\n' "$replay_output" >&2
  exit 1
fi

echo "Security alert webhook failure check passed."
