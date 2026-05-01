#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPS_SCRIPT="${ROOT}/scripts/ops.sh"
MATRIX_SCRIPT="${ROOT}/scripts/pipg_api_matrix.sh"
ACCESS_ASSIGN_SCRIPT="${ROOT}/scripts/access_assignment_admin.sh"

require_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$file"; then
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
  if grep -Fq "$needle" "$file"; then
    echo "[FAIL] $label" >&2
    exit 1
  else
    echo "[OK]   $label"
  fi
}

require_contains "$OPS_SCRIPT" 'source "${APP_DIR}/scripts/lib_internal_identity.sh"' 'ops.sh loads shared internal identity shell helpers'
require_contains "$OPS_SCRIPT" 'caller="$(internal_identity_normalize_service_id "$caller")"' 'ops.sh normalizes smoke caller with canonical helper'
require_absent "$OPS_SCRIPT" "caller=\"\$(printf '%s' \"\$caller\" | tr -d '[:space:]')\"" 'ops.sh no longer strips interior caller whitespace into a different id'

require_contains "$MATRIX_SCRIPT" 'source "${ROOT_DIR}/scripts/lib_internal_identity.sh"' 'pipg_api_matrix.sh loads shared internal identity shell helpers'
require_contains "$MATRIX_SCRIPT" 'CALLER="$(internal_identity_normalize_service_id "$CALLER")"' 'pipg_api_matrix.sh normalizes matrix caller with canonical helper'
require_absent "$MATRIX_SCRIPT" "CALLER=\"\$(printf '%s' \"\$CALLER\" | tr -d '[:space:]')\"" 'pipg_api_matrix.sh no longer strips interior caller whitespace into a different id'

require_contains "$ACCESS_ASSIGN_SCRIPT" 'source "${APP_DIR}/scripts/lib_internal_identity.sh"' 'access_assignment_admin.sh loads shared internal identity shell helpers'
require_contains "$ACCESS_ASSIGN_SCRIPT" 'SERVICE_ID="$(internal_identity_normalize_service_id "${SERVICE_ID:-control-automation}")"' 'access_assignment_admin.sh normalizes service ids with canonical helper'
require_contains "$ACCESS_ASSIGN_SCRIPT" 'internal_identity_build_curl_headers' 'access_assignment_admin.sh signs requests with shared helper'

echo "Internal caller shell usage check passed."
