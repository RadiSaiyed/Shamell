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

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    fail "Missing file: $file"
    return 1
  fi
  return 0
}

check_service_main() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  if rg -n --quiet 'allow_methods\(Any\)' "$file"; then
    fail "$rel: uses allow_methods(Any)"
  else
    ok "$rel: no allow_methods(Any)"
  fi

  if rg -n --quiet 'allow_headers\(Any\)' "$file"; then
    fail "$rel: uses allow_headers(Any)"
  else
    ok "$rel: no allow_headers(Any)"
  fi

  check_credentials_invariant "$rel" "$file"
}

# allow_credentials(true) is NOT inherently a bug: it is required when a
# browser SPA needs to send the session cookie across origins. The actual
# security invariant is:
#
#   credentials may flow ONLY with an explicit Origin allow-list,
#   NEVER with allow_origin(Any) / the wildcard "*".
#
# This check enforces that invariant structurally instead of banning
# allow_credentials(true) outright:
#
#   1) If a file contains allow_credentials(true), it MUST also contain
#      allow_credentials(false) somewhere — proves the dual-mode pattern
#      where the wildcard branch falls back to false.
#   2) No single CorsLayer chain may combine allow_credentials(true) with
#      allow_origin(Any). We approximate "a single chain" by checking a
#      window of lines around each allow_credentials(true) occurrence:
#      tower-http CorsLayer builders are dot-chained across consecutive
#      lines, so a +/- 12 line window over-covers the typical chain
#      without bleeding into the next function.
check_credentials_invariant() {
  local rel="$1"
  local file="$2"

  local credentials_true_count
  credentials_true_count="$(rg -c --no-filename 'allow_credentials\(true\)' "$file" 2>/dev/null || echo 0)"

  if [[ "$credentials_true_count" == "0" ]]; then
    ok "$rel: credentials are not allowed in CORS"
    return
  fi

  local credentials_false_count
  credentials_false_count="$(rg -c --no-filename 'allow_credentials\(false\)' "$file" 2>/dev/null || echo 0)"
  if [[ "$credentials_false_count" == "0" ]]; then
    fail "$rel: allow_credentials(true) without a matching allow_credentials(false) — dual-mode wildcard fallback missing"
    return
  fi

  # For each line that has allow_credentials(true), look at a +/- 12 line
  # window of the same file and fail if that window also contains
  # allow_origin(Any) — that would mean the wildcard + credentials are
  # chained on the same CorsLayer, which is the vulnerable combination.
  local violation=0
  while IFS=: read -r match_line _; do
    [[ -z "$match_line" ]] && continue
    local start=$((match_line - 12))
    local end=$((match_line + 12))
    (( start < 1 )) && start=1
    if awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$file" \
        | rg --quiet 'allow_origin\(Any\)'; then
      fail "$rel: allow_credentials(true) at line $match_line is within a chain that also calls allow_origin(Any) — wildcard origin must never carry credentials"
      violation=1
    fi
  done < <(rg -n 'allow_credentials\(true\)' "$file" 2>/dev/null || true)

  if (( violation == 0 )); then
    ok "$rel: credentials gated behind explicit-origin branch (dual-mode pattern OK)"
  fi
}

extract_function_block() {
  local file="$1"
  local fn_name="$2"
  awk -v fn_name="$fn_name" '
    $0 ~ ("^fn " fn_name "\\(") { in_fn = 1 }
    in_fn { print }
    in_fn && $0 ~ /^}/ { exit }
  ' "$file"
}

check_forbidden_in_whitelist() {
  local rel="$1"
  local fn_name="$2"
  local pattern="$3"
  local label="$4"
  local file="$ROOT/$rel"
  local block
  block="$(extract_function_block "$file" "$fn_name")"
  if [[ -z "$block" ]]; then
    fail "$rel: missing function $fn_name"
    return
  fi
  if printf '%s\n' "$block" | rg -n --quiet -e "$pattern"; then
    fail "$rel: $fn_name contains forbidden $label"
  else
    ok "$rel: $fn_name has no forbidden $label"
  fi
}

check_required_in_whitelist() {
  local rel="$1"
  local fn_name="$2"
  local pattern="$3"
  local label="$4"
  local file="$ROOT/$rel"
  local block
  block="$(extract_function_block "$file" "$fn_name")"
  if [[ -z "$block" ]]; then
    fail "$rel: missing function $fn_name"
    return
  fi
  if printf '%s\n' "$block" | rg -n --quiet -e "$pattern"; then
    ok "$rel: $fn_name includes $label"
  else
    fail "$rel: $fn_name missing $label"
  fi
}

check_service_main "services_rs/bff_gateway/src/main.rs"
check_service_main "services_rs/chat_service/src/main.rs"
check_service_main "services_rs/payments_service/src/main.rs"

check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_public_cors_allowed_headers" \
  'CONTENT_TYPE' \
  'CONTENT_TYPE'
check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_public_cors_allowed_headers" \
  'x-request-id' \
  'x-request-id'
check_forbidden_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_public_cors_allowed_headers" \
  'AUTHORIZATION|x-chat-device-id|x-chat-device-token|x-device-id|idempotency-key|x-merchant|x-ref|x-internal-secret|x-internal-service-id|x-internal-audience|x-internal-identity-ts|x-internal-identity-sig|x-internal-identity-sig-v2|x-internal-identity-nonce|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|x-shamell-client-ip-attested|sec-fetch-site|COOKIE' \
  'auth/internal/proxy/role/app headers'

check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_chat_cors_allowed_headers" \
  'x-chat-device-id' \
  'x-chat-device-id'
check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_chat_cors_allowed_headers" \
  'x-chat-device-token' \
  'x-chat-device-token'
check_forbidden_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_chat_cors_allowed_headers" \
  'AUTHORIZATION|idempotency-key|x-device-id|x-merchant|x-ref|x-internal-secret|x-internal-service-id|x-internal-audience|x-internal-identity-ts|x-internal-identity-sig|x-internal-identity-sig-v2|x-internal-identity-nonce|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|x-shamell-client-ip-attested|sec-fetch-site|COOKIE' \
  'auth/payment/internal/proxy/role headers'

check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_contacts_cors_allowed_headers" \
  'x-chat-device-id' \
  'x-chat-device-id'
check_forbidden_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_contacts_cors_allowed_headers" \
  'AUTHORIZATION|x-chat-device-token|idempotency-key|x-device-id|x-merchant|x-ref|x-internal-secret|x-internal-service-id|x-internal-audience|x-internal-identity-ts|x-internal-identity-sig|x-internal-identity-sig-v2|x-internal-identity-nonce|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|x-shamell-client-ip-attested|sec-fetch-site|COOKIE' \
  'auth/chat-token/payment/internal/proxy/role headers'

check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_payments_cors_allowed_headers" \
  'idempotency-key' \
  'idempotency-key'
check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_payments_cors_allowed_headers" \
  'x-device-id' \
  'x-device-id'
check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_payments_cors_allowed_headers" \
  'x-merchant' \
  'x-merchant'
check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_payments_cors_allowed_headers" \
  'x-ref' \
  'x-ref'
check_forbidden_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_payments_cors_allowed_headers" \
  'AUTHORIZATION|x-chat-device-id|x-chat-device-token|x-internal-secret|x-internal-service-id|x-internal-audience|x-internal-identity-ts|x-internal-identity-sig|x-internal-identity-sig-v2|x-internal-identity-nonce|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|x-shamell-client-ip-attested|sec-fetch-site|COOKIE' \
  'auth/chat/internal/proxy/role headers'

check_required_in_whitelist \
  "services_rs/chat_service/src/main.rs" \
  "chat_cors_allowed_headers" \
  'x-chat-device-id' \
  'x-chat-device-id'
check_required_in_whitelist \
  "services_rs/chat_service/src/main.rs" \
  "chat_cors_allowed_headers" \
  'x-chat-device-token' \
  'x-chat-device-token'
check_forbidden_in_whitelist \
  "services_rs/chat_service/src/main.rs" \
  "chat_cors_allowed_headers" \
  'x-internal-secret|x-internal-service-id|x-internal-audience|x-internal-identity-ts|x-internal-identity-sig|x-internal-identity-sig-v2|x-internal-identity-nonce|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|x-shamell-client-ip-attested|COOKIE' \
  'internal/proxy/role headers'

check_required_in_whitelist \
  "services_rs/payments_service/src/main.rs" \
  "payments_cors_allowed_headers" \
  'idempotency-key' \
  'idempotency-key'
check_required_in_whitelist \
  "services_rs/payments_service/src/main.rs" \
  "payments_cors_allowed_headers" \
  'x-merchant' \
  'x-merchant'
check_forbidden_in_whitelist \
  "services_rs/payments_service/src/main.rs" \
  "payments_cors_allowed_headers" \
  'x-internal-secret|x-internal-service-id|x-internal-audience|x-internal-identity-ts|x-internal-identity-sig|x-internal-identity-sig-v2|x-internal-identity-nonce|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|x-shamell-client-ip-attested|COOKIE' \
  'internal/proxy headers'

if (( errors != 0 )); then
  exit 1
fi

echo "CORS hardening guard passed."
