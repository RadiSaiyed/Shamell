#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

ok() {
  echo "[OK]   $1"
}

fail() {
  echo "[FAIL] $1" >&2
  errors=1
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if rg -n --fixed-strings --quiet "$pattern" "$path"; then
    ok "$label"
  else
    fail "$label"
  fi
}

check_script() {
  local rel="$1"
  local path="$ROOT/$rel"
  if [[ ! -f "$path" ]]; then
    fail "missing script: $rel"
    return
  fi
  require_contains "$path" 'ALLOW_UNTRUSTED_CLIENT_IP="${DASHBOARD_PROXY_ALLOW_UNTRUSTED_CLIENT_IP:-}"' "$rel exposes explicit untrusted-client-ip override"
  require_contains "$path" 'TRUSTED_PROXY_CIDRS="${BFF_TRUSTED_PROXY_CIDRS:-}"' "$rel reads BFF_TRUSTED_PROXY_CIDRS"
  require_contains "$path" 'enforce_trusted_proxy_config_for_dashboard_proxy "$TRUSTED_PROXY_CIDRS"' "$rel enforces trusted-proxy config before startup"
  require_contains "$path" 'Add the Docker bridge/gateway CIDR used by the' "$rel explains docker bridge/gateway requirement"
}

check_script "scripts/start_dashboard_dev_proxy.sh"
check_script "scripts/start_all_dashboard_proxies.sh"

if [[ "$errors" -ne 0 ]]; then
  exit 1
fi

echo "Dashboard proxy trusted-proxy guard check passed."
