#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_SCRIPT="${ROOT}/scripts/ci_account_create_profiles.sh"

require_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "$needle" "$file"; then
    echo "[OK]   $label"
  else
    echo "[FAIL] $label" >&2
    exit 1
  fi
}

require_absent() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "$needle" "$file"; then
    echo "[FAIL] $label" >&2
    exit 1
  else
    echo "[OK]   $label"
  fi
}

require_contains "$CI_SCRIPT" 'set_env "$file" BFF_TRUSTED_PROXY_CIDRS "127.0.0.1/32,::1/128"' 'ci account-create profile explicitly trusts loopback proxy hop'
require_contains "$CI_SCRIPT" 'SMOKE_CLIENT_IP="203.0.113.10"' 'ci smoke uses non-loopback forwarded client ip'
require_absent "$CI_SCRIPT" 'SMOKE_CLIENT_IP="127.0.0.1"' 'ci smoke no longer hides trusted-proxy regressions behind loopback client ip'

echo "CI trusted proxy smoke check passed."
