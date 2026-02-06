#!/usr/bin/env bash
set -euo pipefail

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
  local code

  local -a args
  args=(
    -sS
    -o "$tmp"
    -w "%{http_code}"
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

  code=$(curl "${args[@]}")

  local ok=1
  IFS=',' read -r -a allowed <<< "$expected_csv"
  for x in "${allowed[@]}"; do
    if [ "$code" = "$x" ]; then
      ok=0
      break
    fi
  done

  if [ "$ok" -ne 0 ]; then
    echo "[FAIL] $label: expected one of {$expected_csv}, got $code ($method $url)" >&2
    echo "Response body:" >&2
    sed -n '1,120p' "$tmp" >&2 || true
    rm -f "$tmp"
    exit 1
  fi

  echo "[PASS] $label: $code"
  rm -f "$tmp"
}

require_env STAGING_BFF_BASE_URL
require_env STAGING_PAYMENTS_BASE_URL
require_env STAGING_CHAT_BASE_URL

BFF_BASE_URL=$(trim_base "$STAGING_BFF_BASE_URL")
PAY_BASE_URL=$(trim_base "$STAGING_PAYMENTS_BASE_URL")
CHAT_BASE_URL=$(trim_base "$STAGING_CHAT_BASE_URL")

# Non-destructive availability checks
expect_code "BFF health" GET "$BFF_BASE_URL/health" "200"
expect_code "Payments health" GET "$PAY_BASE_URL/health" "200"
expect_code "Chat health" GET "$CHAT_BASE_URL/health" "200"

# AuthN/AuthZ guardrails (negative tests, no valid creds provided)
expect_code "BFF admin denied without token" GET "$BFF_BASE_URL/admin" "401,403"
expect_code "Payments admin denied without token" GET "$PAY_BASE_URL/admin/debug/tables" "401"
expect_code "Chat inbox denied without token" GET "$CHAT_BASE_URL/chat/messages/inbox?device_id=dast-smoke" "401"

# Upload should reject anonymous calls
UPLOAD_TMP=$(mktemp)
printf 'dast-smoke' > "$UPLOAD_TMP"
UPLOAD_CODE=$(curl -sS -o /tmp/dast_upload_resp.txt -w "%{http_code}" \
  -X POST "$BFF_BASE_URL/chat/media/upload" \
  -H "User-Agent: ${DAST_USER_AGENT:-shamell-staging-dast-smoke/1.0}" \
  -F "file=@${UPLOAD_TMP};type=text/plain" \
  -F "kind=attachment" \
  -F "mime=text/plain")
rm -f "$UPLOAD_TMP"
if [ "$UPLOAD_CODE" != "401" ]; then
  echo "[FAIL] BFF upload unauthenticated expected 401, got $UPLOAD_CODE" >&2
  sed -n '1,120p' /tmp/dast_upload_resp.txt >&2 || true
  exit 1
fi
echo "[PASS] BFF upload denied without auth: $UPLOAD_CODE"

# Webhook endpoint should reject invalid signature, or be explicitly disabled in staging.
expect_code "Payments webhook invalid signature rejected" \
  POST "$PAY_BASE_URL/webhooks/psp" "400,401,503" '{}' 'application/json' 'Stripe-Signature: t=0,v1=invalid'

echo "Staging DAST smoke checks completed."
