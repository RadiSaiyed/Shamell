#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPS_SCRIPT="${ROOT}/scripts/ops.sh"
MATRIX_SCRIPT="${ROOT}/scripts/pipg_api_matrix.sh"
README_FILE="${ROOT}/ops/pi/README.md"

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

require_contains "$OPS_SCRIPT" 'SMOKE_CLIENT_IP optional X-Forwarded-For client IP override' 'ops.sh documents trusted-proxy smoke client IP behavior'
require_contains "$OPS_SCRIPT" 'curl_args+=(-H "X-Forwarded-For: ${SMOKE_CLIENT_IP}")' 'ops.sh uses X-Forwarded-For for direct smoke overrides'
require_contains "$OPS_SCRIPT" '-H "x-forwarded-for: ${client_ip}"' 'smoke-mailbox uses X-Forwarded-For in common headers'
require_absent "$OPS_SCRIPT" 'X-Shamell-Client-IP' 'ops.sh no longer claims a spoofable trusted client IP override header'

require_contains "$MATRIX_SCRIPT" '-H "x-forwarded-for: ${CLIENT_IP}"' 'pipg_api_matrix.sh uses X-Forwarded-For for matrix requests'
require_absent "$MATRIX_SCRIPT" 'x-shamell-client-ip' 'pipg_api_matrix.sh no longer sends stripped trusted client IP headers directly'

require_contains "$README_FILE" 'BFF_TRUSTED_PROXY_CIDRS' 'README explains trusted proxy prerequisite for smoke client IP overrides'
require_contains "$README_FILE" 'X-Forwarded-For: <ip>' 'README documents X-Forwarded-For smoke behavior'

echo "Trusted proxy smoke header usage check passed."
