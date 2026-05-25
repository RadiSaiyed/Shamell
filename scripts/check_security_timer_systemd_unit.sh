#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_FILE="${ROOT}/ops/hetzner/systemd/shamell-security-events-report.service"
README_FILE="${ROOT}/ops/hetzner/systemd/README.md"

if rg -n --quiet --fixed-strings 'ExecStart=/usr/bin/flock -n -E 75 /run/shamell-security-events-report.lock' "$SERVICE_FILE"; then
  echo "[OK]   systemd unit uses explicit benign lock-contention exit code"
else
  echo "[FAIL] systemd unit missing flock -E 75 benign skip semantics" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'Environment=APP_DIR=/opt/shamell' "$SERVICE_FILE"; then
  echo "[FAIL] systemd unit still hardcodes APP_DIR and overrides sync-time remote path detection" >&2
  exit 1
else
  echo "[OK]   systemd unit does not override APP_DIR from EnvironmentFile"
fi

if rg -n --quiet --fixed-strings 'APP_DIR="$${APP_DIR:-/opt/shamell}"' "$SERVICE_FILE"; then
  echo "[OK]   systemd unit keeps shell-level /opt/shamell fallback when APP_DIR is unset"
else
  echo "[FAIL] systemd unit missing shell fallback for unset APP_DIR" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'SuccessExitStatus=2 75' "$SERVICE_FILE"; then
  echo "[OK]   systemd unit treats alert and lock-skip exit codes as healthy"
else
  echo "[FAIL] systemd unit missing SuccessExitStatus=2 75" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'If a previous run still holds the lock, the service now exits with code `75`' "$README_FILE"; then
  echo "[OK]   README documents benign lock-contention behavior"
else
  echo "[FAIL] README missing lock-contention note" >&2
  exit 1
fi

if rg -n --quiet --fixed-strings 'the unit itself no' "$README_FILE" && \
   rg -n --quiet --fixed-strings 'longer hardcodes `APP_DIR`' "$README_FILE"; then
  echo "[OK]   README documents APP_DIR override semantics"
else
  echo "[FAIL] README missing APP_DIR override semantics" >&2
  exit 1
fi

echo "Security timer systemd unit checks passed."
