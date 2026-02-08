#!/usr/bin/env bash
set -euo pipefail

CHECKS=0
FAILURES=0
MAX_FAILED_CHECKS="${DAST_MAX_FAILED_CHECKS:-0}"
MAX_RESPONSE_MS="${DAST_MAX_RESPONSE_MS:-2500}"

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

if ! is_uint "$MAX_FAILED_CHECKS"; then
  echo "Invalid DAST_MAX_FAILED_CHECKS: $MAX_FAILED_CHECKS (must be integer)" >&2
  exit 1
fi
if ! is_uint "$MAX_RESPONSE_MS"; then
  echo "Invalid DAST_MAX_RESPONSE_MS: $MAX_RESPONSE_MS (must be integer ms)" >&2
  exit 1
fi

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env: $name" >&2
    exit 1
  fi
}

trim_base() {
  local url="$1"
  url="${url%/}"
  printf '%s' "$url"
}

normalize_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    path="/$path"
  fi
  printf '%s' "$path"
}

expect_code() {
  local label="$1"
  local method="$2"
  local url="$3"
  local expected_csv="$4"
  local body="${5:-}"
  local ctype="${6:-}"
  local extra_header="${7:-}"

  local tmp
  tmp=$(mktemp)
  local code_and_time
  local code
  local time_s
  local latency_ms

  local -a args
  args=(
    -sS
    -o "$tmp"
    -w "%{http_code} %{time_total}"
    -X "$method"
    "$url"
    -H "User-Agent: ${DAST_USER_AGENT:-shamell-staging-dast-smoke/1.0}"
  )

  if [ -n "$ctype" ]; then
    args+=( -H "Content-Type: $ctype" )
  fi
  if [ -n "$extra_header" ]; then
    args+=( -H "$extra_header" )
  fi
  if [ -n "$body" ]; then
    args+=( --data "$body" )
  fi

  code_and_time=$(curl "${args[@]}")
  code="${code_and_time%% *}"
  time_s="${code_and_time##* }"
  latency_ms=$(awk -v t="$time_s" 'BEGIN {printf "%.0f", t * 1000}')

  CHECKS=$((CHECKS + 1))

  local code_ok=1
  IFS=',' read -r -a allowed <<< "$expected_csv"
  for x in "${allowed[@]}"; do
    if [ "$code" = "$x" ]; then
      code_ok=0
      break
    fi
  done

  local latency_ok=0
  if [ "$latency_ms" -le "$MAX_RESPONSE_MS" ]; then
    latency_ok=1
  fi

  if [ "$code_ok" -ne 0 ] || [ "$latency_ok" -ne 1 ]; then
    FAILURES=$((FAILURES + 1))
    echo "[FAIL] $label: code=$code expected={$expected_csv} latency_ms=${latency_ms} max_ms=${MAX_RESPONSE_MS} ($method $url)" >&2
    echo "Response body:" >&2
    sed -n '1,120p' "$tmp" >&2 || true
    rm -f "$tmp"
    return 0
  fi

  echo "[PASS] $label: code=$code latency_ms=${latency_ms}"
  rm -f "$tmp"
}

require_env STAGING_BFF_BASE_URL
require_env STAGING_PAYMENTS_BASE_URL
require_env STAGING_CHAT_BASE_URL

BFF_BASE_URL=$(trim_base "$STAGING_BFF_BASE_URL")
PAY_BASE_URL=$(trim_base "$STAGING_PAYMENTS_BASE_URL")
CHAT_BASE_URL=$(trim_base "$STAGING_CHAT_BASE_URL")

# Route checks differ between split-service and monolith/single-host staging layouts.
BFF_ADMIN_PATH="${DAST_BFF_ADMIN_PATH:-/admin/metrics}"
BFF_ADMIN_PATH="$(normalize_path "$BFF_ADMIN_PATH")"
PAYMENTS_ADMIN_PATH="${DAST_PAYMENTS_ADMIN_PATH:-/admin/debug/tables}"
PAYMENTS_SUMMARY_PATH="${DAST_PAYMENTS_SUMMARY_PATH:-/admin/fees/summary}"
PAYMENTS_WEBHOOK_PATH="${DAST_PAYMENTS_WEBHOOK_PATH:-}"
PAYMENTS_ADMIN_EXPECT="401"
PAYMENTS_SUMMARY_EXPECT="401,403"
if [ "$PAY_BASE_URL" = "$BFF_BASE_URL" ]; then
  PAYMENTS_ADMIN_PATH="${DAST_PAYMENTS_ADMIN_PATH:-/payments/admin/debug/tables}"
  PAYMENTS_SUMMARY_PATH="${DAST_PAYMENTS_SUMMARY_PATH:-/payments/admin/fees/summary}"
  # In single-host monolith layouts we may intentionally not expose the raw
  # Payments service router. In that case 404 is also acceptable.
  PAYMENTS_ADMIN_EXPECT="401,404"
  PAYMENTS_SUMMARY_EXPECT="401,403,404"
fi
PAYMENTS_ADMIN_PATH="$(normalize_path "$PAYMENTS_ADMIN_PATH")"
PAYMENTS_SUMMARY_PATH="$(normalize_path "$PAYMENTS_SUMMARY_PATH")"
if [ -n "$PAYMENTS_WEBHOOK_PATH" ]; then
  PAYMENTS_WEBHOOK_PATH="$(normalize_path "$PAYMENTS_WEBHOOK_PATH")"
fi

# Non-destructive availability checks
expect_code "BFF health" GET "$BFF_BASE_URL/health" "200"
expect_code "Payments health" GET "$PAY_BASE_URL/health" "200"
expect_code "Chat health" GET "$CHAT_BASE_URL/health" "200"

# AuthN/AuthZ guardrails (negative tests, no valid creds provided)
expect_code "BFF admin denied without token" GET "$BFF_BASE_URL$BFF_ADMIN_PATH" "401,403"
expect_code "Payments admin denied without token" GET "$PAY_BASE_URL$PAYMENTS_ADMIN_PATH" "$PAYMENTS_ADMIN_EXPECT"
expect_code "Chat inbox denied without token" GET "$CHAT_BASE_URL/chat/messages/inbox?device_id=dast-smoke" "401"
expect_code "BFF metrics denied without token" GET "$BFF_BASE_URL/metrics" "401,403"
if [ -n "$PAYMENTS_WEBHOOK_PATH" ]; then
  # Webhook endpoint should reject invalid signatures when configured in staging.
  expect_code "Payments webhook invalid signature rejected" \
    POST "$PAY_BASE_URL$PAYMENTS_WEBHOOK_PATH" "400,401,403,503" '{}' 'application/json' 'Stripe-Signature: t=0,v1=invalid'
else
  expect_code "Payments admin summary denied without token" GET "$PAY_BASE_URL$PAYMENTS_SUMMARY_PATH" "$PAYMENTS_SUMMARY_EXPECT"
fi

echo "DAST summary: checks=$CHECKS failures=$FAILURES max_failures=$MAX_FAILED_CHECKS max_response_ms=$MAX_RESPONSE_MS"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Staging DAST Summary"
    echo "- Checks: $CHECKS"
    echo "- Failures: $FAILURES"
    echo "- Allowed failures: $MAX_FAILED_CHECKS"
    echo "- Max response time (ms): $MAX_RESPONSE_MS"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$FAILURES" -gt "$MAX_FAILED_CHECKS" ]; then
  echo "Staging DAST smoke checks failed threshold (failures=$FAILURES > max=$MAX_FAILED_CHECKS)." >&2
  exit 1
fi

echo "Staging DAST smoke checks completed successfully."
