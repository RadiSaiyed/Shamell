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

  if rg -n --quiet 'allow_credentials\(true\)' "$file"; then
    fail "$rel: uses allow_credentials(true)"
  else
    ok "$rel: credentials are not allowed in CORS"
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
check_service_main "services_rs/bus_service/src/main.rs"

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
  'AUTHORIZATION|x-chat-device-id|x-chat-device-token|x-device-id|idempotency-key|x-merchant|x-ref|x-internal-secret|x-internal-service-id|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|sec-fetch-site|COOKIE' \
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
  'AUTHORIZATION|idempotency-key|x-device-id|x-merchant|x-ref|x-internal-secret|x-internal-service-id|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|sec-fetch-site|COOKIE' \
  'auth/payment/internal/proxy/role headers'

check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_contacts_cors_allowed_headers" \
  'x-chat-device-id' \
  'x-chat-device-id'
check_forbidden_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_contacts_cors_allowed_headers" \
  'AUTHORIZATION|x-chat-device-token|idempotency-key|x-device-id|x-merchant|x-ref|x-internal-secret|x-internal-service-id|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|sec-fetch-site|COOKIE' \
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
  'AUTHORIZATION|x-chat-device-id|x-chat-device-token|x-internal-secret|x-internal-service-id|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|sec-fetch-site|COOKIE' \
  'auth/chat/internal/proxy/role headers'

check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_bus_cors_allowed_headers" \
  'idempotency-key' \
  'idempotency-key'
check_required_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_bus_cors_allowed_headers" \
  'x-device-id' \
  'x-device-id'
check_forbidden_in_whitelist \
  "services_rs/bff_gateway/src/main.rs" \
  "bff_bus_cors_allowed_headers" \
  'AUTHORIZATION|x-chat-device-id|x-chat-device-token|x-merchant|x-ref|x-internal-secret|x-internal-service-id|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|sec-fetch-site|COOKIE' \
  'auth/chat/payment/internal/proxy/role headers'

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
  'x-internal-secret|x-internal-service-id|x-role-auth|x-auth-roles|x-roles|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|COOKIE' \
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
  'x-internal-secret|x-internal-service-id|x-bus-payments-internal-secret|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|COOKIE' \
  'internal/proxy headers'

check_required_in_whitelist \
  "services_rs/bus_service/src/main.rs" \
  "bus_cors_allowed_headers" \
  'idempotency-key' \
  'idempotency-key'
check_forbidden_in_whitelist \
  "services_rs/bus_service/src/main.rs" \
  "bus_cors_allowed_headers" \
  'x-internal-secret|x-internal-service-id|x-bus-payments-internal-secret|x-forwarded-for|x-forwarded-host|x-real-ip|x-shamell-client-ip|COOKIE' \
  'internal/proxy headers'

if (( errors != 0 )); then
  exit 1
fi

echo "CORS hardening guard passed."
