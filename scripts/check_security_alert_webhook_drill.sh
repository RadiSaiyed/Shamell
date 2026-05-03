#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRILL_SCRIPT="${ROOT}/scripts/security_alert_webhook_drill.sh"

output="$(
  ENV_FILE="${ROOT}/ops/pi/.env.example" \
  SECURITY_ALERT_WEBHOOK_URL="http://127.0.0.1:8080/internal/security/alerts" \
  bash "$DRILL_SCRIPT" \
    --dry-run \
    --service chat \
    --severity warning \
    --note "Synthetic targeted drill. No incident." \
    --alert chat_prekey_inventory.low:3/3 \
    --alert chat_key_bootstrap_policy.blocked:1/1
)"

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

require_output '"service": "chat"' "custom drill service rendered"
require_output '"severity": "warning"' "custom drill severity rendered"
require_output '"chat_prekey_inventory.low:3/3"' "prekey alert rendered"
require_output '"chat_key_bootstrap_policy.blocked:1/1"' "bootstrap-policy alert rendered"
require_output '"Synthetic targeted drill. No incident."' "custom drill note rendered"
require_output 'Dry run enabled; not sending webhook.' "dry-run path stays non-destructive"

echo "Security alert webhook drill check passed."
