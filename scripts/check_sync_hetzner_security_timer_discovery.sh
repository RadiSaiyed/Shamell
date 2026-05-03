#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="${ROOT}/scripts/sync_hetzner_security_timer.sh"
README_FILE="${ROOT}/ops/hetzner/systemd/README.md"

require_literal() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if rg -n --quiet --fixed-strings -e "$needle" "$file"; then
    echo "[OK]   $label"
  else
    echo "[FAIL] $label" >&2
    exit 1
  fi
}

require_literal "$SYNC_SCRIPT" '.env.prod' "remote app discovery considers .env.prod"
require_literal "$SYNC_SCRIPT" '.env.staging' "remote app discovery considers .env.staging"
require_literal "$README_FILE" 'Remote app-dir auto-detection also treats any of those three env-file names as a valid deployed repo.' "README documents env-file-aware remote app discovery"

echo "Hetzner security timer discovery checks passed."
