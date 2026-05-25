#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="${ROOT}/scripts/sync_hetzner_security_timer.sh"
README_FILE="${ROOT}/ops/hetzner/systemd/README.md"

if rg -n --quiet --fixed-strings 'ENV_FILE='"'"'${REMOTE_ENV_FILE}'"'"' ./scripts/security_alert_webhook_drill.sh' "$SYNC_SCRIPT"; then
  echo "[OK]   sync script passes REMOTE_ENV_FILE into webhook drill"
else
  echo "[FAIL] sync script does not pass REMOTE_ENV_FILE into webhook drill" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'SECURITY_ALERT_DRILL_ALERTS=$(quote_for_remote "$SECURITY_ALERT_DRILL_ALERTS")' "$SYNC_SCRIPT"; then
  echo "[OK]   sync script forwards targeted drill alerts to remote host"
else
  echo "[FAIL] sync script does not forward targeted drill alerts" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'SECURITY_ALERT_DRILL_SEVERITY=$(quote_for_remote "$SECURITY_ALERT_DRILL_SEVERITY")' "$SYNC_SCRIPT"; then
  echo "[OK]   sync script forwards targeted drill severity to remote host"
else
  echo "[FAIL] sync script does not forward targeted drill severity" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'using the same resolved `REMOTE_ENV_FILE` as the timer service' "$README_FILE"; then
  echo "[OK]   README documents drill env-file parity"
else
  echo "[FAIL] README missing drill env-file parity note" >&2
  exit 1
fi

echo "Hetzner security timer sync checks passed."
