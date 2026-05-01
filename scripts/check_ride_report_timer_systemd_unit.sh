#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_FILE="${ROOT}/ops/hetzner/systemd/shamell-ride-ops-report.service"
README_FILE="${ROOT}/ops/hetzner/systemd/README.md"

if rg -n --quiet --fixed-strings 'ExecStart=/usr/bin/flock -n -E 75 /run/shamell-ride-ops-report.lock' "$SERVICE_FILE"; then
  echo "[OK]   ride timer unit uses explicit benign lock-contention exit code"
else
  echo "[FAIL] ride timer unit missing flock -E 75 benign skip semantics" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'Environment=APP_DIR=/opt/shamell' "$SERVICE_FILE"; then
  echo "[FAIL] ride timer unit still hardcodes APP_DIR and overrides sync-time remote path detection" >&2
  exit 1
else
  echo "[OK]   ride timer unit does not override APP_DIR from EnvironmentFile"
fi

if rg -n --quiet --fixed-strings 'APP_DIR="$${APP_DIR:-/opt/shamell}"' "$SERVICE_FILE"; then
  echo "[OK]   ride timer unit keeps shell-level /opt/shamell fallback when APP_DIR is unset"
else
  echo "[FAIL] ride timer unit missing shell fallback for unset APP_DIR" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'RIDE_REPORT_FAIL_ON_FINDINGS="$${RIDE_REPORT_FAIL_ON_FINDINGS:-1}"' "$SERVICE_FILE"; then
  echo "[OK]   ride timer defaults to fail-on-findings monitoring semantics"
else
  echo "[FAIL] ride timer unit missing fail-on-findings default" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'SuccessExitStatus=75' "$SERVICE_FILE"; then
  echo "[OK]   ride timer unit treats lock-skip exit as healthy"
else
  echo "[FAIL] ride timer unit missing SuccessExitStatus=75" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'If a previous run still holds the lock, the ride timer exits with code `75`' "$README_FILE"; then
  echo "[OK]   README documents ride timer lock-contention behavior"
else
  echo "[FAIL] README missing ride timer lock-contention note" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'The ride timer defaults `RIDE_REPORT_FAIL_ON_FINDINGS=1`' "$README_FILE"; then
  echo "[OK]   README documents ride timer fail-on-findings default"
else
  echo "[FAIL] README missing ride timer fail-on-findings default" >&2
  exit 1
fi

echo "Ride timer systemd unit checks passed."
