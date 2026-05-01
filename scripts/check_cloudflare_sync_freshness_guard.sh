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
  require_contains "$path" 'CLOUDFLARE_REALIP_SNIPPET' "$rel supports explicit Cloudflare snippet path override"
  require_contains "$path" 'ensure_fresh_cloudflare_realip_snippet()' "$rel defines Cloudflare snippet freshness guard"
  require_contains "$path" 'bash "${REPO_ROOT}/scripts/check_cloudflare_realip_freshness.sh"' "$rel invokes shared Cloudflare freshness checker"
}

check_script "scripts/sync_hetzner_nginx.sh"
check_script "scripts/sync_hetzner_ufw.sh"

if (( errors != 0 )); then
  exit 1
fi

echo "Cloudflare sync freshness guard check passed."
