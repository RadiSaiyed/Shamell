#!/usr/bin/env bash
set -euo pipefail

# Enforce "payments phone targets" are permanently disabled.
# Rationale: routing by phone leaks PII into URLs/logs/metrics and invites enumeration.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

errors=0

fail() {
  echo "[FAIL] $1" >&2
  errors=1
}

ok() {
  echo "[OK]   $1"
}

if ! command -v rg >/dev/null 2>&1; then
  fail "missing required command: rg"
fi

RG_FLAGS=(
  -n
  -S
  --no-heading
  --color=never
  --glob '!**/*.min.*'
  --glob '!**/*.lock'
  --glob '!**/Cargo.lock'
  --glob '!**/target/**'
  --glob '!**/.dart_tool/**'
  --glob '!**/build/**'
  --glob '!**/Pods/**'
)

check_absent() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches
  matches="$(rg "${RG_FLAGS[@]}" "$pattern" "$@" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    fail "$label"
    echo "$matches" >&2
  else
    ok "$label"
  fi
}

# Server/client artifacts that must not come back.
check_absent \
  "no payments phone-resolve endpoints (/resolve/phone) present" \
  "/resolve/phone|/payments/resolve/phone|payments_resolve_phone\\b|\\bresolve_phone\\b" \
  services_rs/bff_gateway/src \
  services_rs/payments_service/src \
  clients/shamell_flutter/lib/mini_apps/payments

# Deployment hardening: rate-limit knobs and docs should not advertise the removed endpoint.
check_absent \
  "no AUTH_RESOLVE_PHONE_* env vars present" \
  "AUTH_RESOLVE_PHONE_" \
  .env.example \
  ops \
  docs

if (( errors != 0 )); then
  exit 1
fi

echo "No-payments-phone-routing guard passed."

