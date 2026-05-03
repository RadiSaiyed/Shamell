#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="${ROOT}/scripts/sync_hetzner_ride_report_timer.sh"
README_FILE="${ROOT}/ops/hetzner/systemd/README.md"

if rg -n --quiet --fixed-strings "RIDE_REPORT_RESERVED_FEE_HOLD_STALE_SECS" "$SYNC_SCRIPT"; then
  echo "[OK]   ride timer sync forwards ride-report threshold overrides"
else
  echo "[FAIL] ride timer sync does not forward threshold overrides" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings "ride_ops_report.sh" "$SYNC_SCRIPT"; then
  echo "[OK]   ride timer sync installs latest ride_ops_report.sh on host"
else
  echo "[FAIL] ride timer sync does not install ride_ops_report.sh" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'using the same resolved `REMOTE_ENV_FILE` as the timer service' "$README_FILE"; then
  echo "[OK]   README documents ride timer env-file parity"
else
  echo "[FAIL] README missing ride timer env-file parity note" >&2
  exit 1
fi

echo "Hetzner ride timer sync checks passed."
