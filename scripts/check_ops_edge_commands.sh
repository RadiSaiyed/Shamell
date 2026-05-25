#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPS_SCRIPT="${ROOT}/scripts/ops.sh"
README_FILE="${ROOT}/README.md"
PI_README_FILE="${ROOT}/ops/pi/README.md"
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

require_contains "$OPS_SCRIPT" 'cloudflare-refresh refresh local Cloudflare trusted-proxy CIDRs for edge IaC' 'ops.sh usage documents cloudflare-refresh'
require_contains "$OPS_SCRIPT" 'cloudflare-status check local Cloudflare trusted-proxy CIDR freshness' 'ops.sh usage documents cloudflare-status'
require_contains "$OPS_SCRIPT" 'sync-nginx    sync Hetzner Nginx IaC (passes ops env file by default)' 'ops.sh usage documents sync-nginx'
require_contains "$OPS_SCRIPT" 'sync-ufw      sync Hetzner UFW allowlists / origin-lockdown policy' 'ops.sh usage documents sync-ufw'
require_contains "$OPS_SCRIPT" 'sync-edge     refresh Cloudflare CIDRs, then sync Nginx + UFW' 'ops.sh usage documents sync-edge'
require_contains "$OPS_SCRIPT" 'sync-ride-report-timer install/update Hetzner ride ops audit timer' 'ops.sh usage documents sync-ride-report-timer'
require_contains "$OPS_SCRIPT" 'ride-release-gate run the canonical ride release gate' 'ops.sh usage documents ride-release-gate'
require_contains "$OPS_SCRIPT" 'ride-repair-stale-presence repair stale online driver presence + cancel pending offers' 'ops.sh usage documents ride-repair-stale-presence'
require_contains "$OPS_SCRIPT" 'cloudflare_refresh() {' 'ops.sh exposes cloudflare_refresh helper'
require_contains "$OPS_SCRIPT" 'cloudflare_status() {' 'ops.sh exposes cloudflare_status helper'
require_contains "$OPS_SCRIPT" 'ride_release_gate() {' 'ops.sh exposes ride_release_gate helper'
require_contains "$OPS_SCRIPT" 'ride_repair_stale_presence() {' 'ops.sh exposes ride_repair_stale_presence helper'
require_contains "$OPS_SCRIPT" 'if ! cloudflare_status; then' 'ops.sh report surfaces Cloudflare freshness failures'
require_contains "$OPS_SCRIPT" 'echo "==> ride ops"' 'ops.sh report includes ride ops audit section'
require_contains "$OPS_SCRIPT" 'Ride ops report failed.' 'ops.sh report surfaces ride-report failures'
require_contains "$OPS_SCRIPT" 'Cloudflare real-ip snippet freshness must pass before non-dev check/deploy.' 'ops.sh check/deploy fail closed on stale Cloudflare snippet'
require_contains "$OPS_SCRIPT" 'require_non_dev_edge_preflight() {' 'ops.sh exposes shared edge preflight helper'
require_contains "$OPS_SCRIPT" 'check_env' 'ops.sh edge preflight reuses env validation'
require_contains "$OPS_SCRIPT" 'local failed=0' 'ops.sh report tracks failure state'
require_contains "$OPS_SCRIPT" 'if [[ "$failed" -ne 0 ]]; then' 'ops.sh report exits non-zero on reported failures'
require_contains "$OPS_SCRIPT" 'NGINX_SYNC_ENV_FILE="$ENV_FILE_PATH" "${APP_DIR}/scripts/sync_hetzner_nginx.sh" "$@"' 'sync-nginx forwards the selected ops env file into nginx sync'
require_contains "$OPS_SCRIPT" 'sync-edge: supported flags are --allow-livekit and --direct-web.' 'sync-edge rejects unsupported flags explicitly'
require_contains "$OPS_SCRIPT" 'cloudflare_refresh' 'ops.sh references cloudflare_refresh in dispatch/helper paths'
require_contains "$OPS_SCRIPT" 'cloudflare_status' 'ops.sh references cloudflare_status in dispatch/helper paths'
require_contains "$OPS_SCRIPT" 'sync_edge() {' 'ops.sh exposes sync_edge helper'
require_contains "$OPS_SCRIPT" 'sync_ride_report_timer() {' 'ops.sh exposes sync_ride_report_timer helper'
require_contains "$OPS_SCRIPT" 'sync_nginx "$host_alias"' 'sync-edge reuses sync-nginx with parsed host alias'
require_contains "$OPS_SCRIPT" 'sync_ufw "${ufw_args[@]}"' 'sync-edge reuses sync-ufw with parsed firewall flags'
require_contains "$OPS_SCRIPT" 'cloudflare-status|cloudflare_status|status-cloudflare)' 'ops.sh dispatches cloudflare-status aliases'
require_contains "$OPS_SCRIPT" 'cloudflare-refresh|cloudflare_refresh|refresh-cloudflare)' 'ops.sh dispatches cloudflare-refresh aliases'
require_contains "$OPS_SCRIPT" 'sync-nginx|sync_nginx|nginx-sync)' 'ops.sh dispatches sync-nginx aliases'
require_contains "$OPS_SCRIPT" 'sync-ufw|sync_ufw|ufw-sync)' 'ops.sh dispatches sync-ufw aliases'
require_contains "$OPS_SCRIPT" 'sync-edge|sync_edge|edge-sync)' 'ops.sh dispatches sync-edge aliases'
require_contains "$OPS_SCRIPT" 'sync-ride-report-timer|sync_ride_report_timer|ride-report-timer-sync)' 'ops.sh dispatches sync-ride-report-timer aliases'
require_contains "$OPS_SCRIPT" 'ride-release-gate|ride_release_gate|ride-gate)' 'ops.sh dispatches ride-release-gate aliases'
require_contains "$OPS_SCRIPT" 'ride-repair-stale-presence|ride_repair_stale_presence|ride-presence-repair)' 'ops.sh dispatches ride-repair-stale-presence aliases'

require_contains "$README_FILE" './scripts/ops.sh pipg cloudflare-status' 'root README documents canonical cloudflare-status workflow'
require_contains "$README_FILE" './scripts/ops.sh pipg ride-release-gate' 'root README documents canonical ride release gate workflow'
require_contains "$README_FILE" '`pipg check` and `pipg deploy` now fail closed on stale Cloudflare trusted-proxy' 'root README documents check/deploy Cloudflare preflight'
require_contains "$README_FILE" '`pipg report` now exits non-zero when health or edge freshness checks fail.' 'root README documents report failure semantics'
require_contains "$README_FILE" '`pipg report` also runs `ride-report` on non-dev stacks' 'root README documents report ride-report integration'
require_contains "$README_FILE" '`pipg ride-release-gate` is the canonical non-dev ride close-out' 'root README documents ride-release-gate semantics'
require_contains "$README_FILE" '`pipg sync-nginx` and `pipg sync-edge` now run the same non-dev env preflight' 'root README documents edge sync preflight'
require_contains "$README_FILE" './scripts/ops.sh pipg sync-edge shamell' 'root README documents canonical sync-edge workflow'
require_contains "$README_FILE" './scripts/ops.sh pipg sync-ride-report-timer shamell --run-now' 'root README documents canonical ride timer sync workflow'
require_contains "$PI_README_FILE" './scripts/ops.sh pipg cloudflare-status' 'pi README documents ops.sh Cloudflare status'
require_contains "$PI_README_FILE" './scripts/ops.sh pipg ride-release-gate' 'pi README documents ops.sh ride-release-gate'
require_contains "$PI_README_FILE" '`check` and `deploy` now also fail closed if the local Cloudflare CIDR source' 'pi README documents check/deploy Cloudflare preflight'
require_contains "$PI_README_FILE" '`report` now exits non-zero if health or Cloudflare freshness fails.' 'pi README documents report failure semantics'
require_contains "$PI_README_FILE" '`report` also runs `ride-report` on non-dev stacks' 'pi README documents report ride-report integration'
require_contains "$PI_README_FILE" '`ride-release-gate` is the canonical ride close-out' 'pi README documents ride-release-gate semantics'
require_contains "$PI_README_FILE" '`sync-nginx` and `sync-edge` now run the same non-dev env preflight before' 'pi README documents edge sync preflight'
require_contains "$PI_README_FILE" './scripts/ops.sh pipg cloudflare-refresh' 'pi README documents ops.sh Cloudflare refresh'
require_contains "$PI_README_FILE" './scripts/ops.sh pipg sync-nginx shamell' 'pi README documents ops.sh nginx sync'
require_contains "$PI_README_FILE" './scripts/ops.sh pipg sync-ufw shamell' 'pi README documents ops.sh ufw sync'
require_contains "$PI_README_FILE" './scripts/ops.sh pipg sync-ride-report-timer shamell --run-now' 'pi README documents ops.sh ride timer sync'

if [[ "$errors" -ne 0 ]]; then
  exit 1
fi

echo "ops.sh edge command guard passed."
