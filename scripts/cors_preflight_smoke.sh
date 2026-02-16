#!/usr/bin/env bash
set -euo pipefail

CHECKS=0
FAILURES=0

SMOKE_MAX_FAILED_CHECKS="${SMOKE_MAX_FAILED_CHECKS:-0}"
SMOKE_TIMEOUT_SECS="${SMOKE_TIMEOUT_SECS:-15}"
SMOKE_CONNECT_TIMEOUT_SECS="${SMOKE_CONNECT_TIMEOUT_SECS:-5}"
SMOKE_ORIGIN="${SMOKE_ORIGIN:-https://online.shamell.online}"
SMOKE_USER_AGENT="${SMOKE_USER_AGENT:-shamell-cors-preflight-smoke/1.0}"

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
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

trim_token() {
  local token="$1"
  token="${token#"${token%%[![:space:]]*}"}"
  token="${token%"${token##*[![:space:]]}"}"
  printf '%s' "$token"
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

to_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

lower_tokens_csv() {
  local csv="$1"
  while IFS= read -r token; do
    token="$(trim_token "$token")"
    if [[ -n "$token" ]]; then
      printf '%s\n' "$(to_lower "$token")"
    fi
  done < <(printf '%s' "$csv" | tr ',' '\n')
}

upper_tokens_csv() {
  local csv="$1"
  while IFS= read -r token; do
    token="$(trim_token "$token")"
    if [[ -n "$token" ]]; then
      printf '%s\n' "$(to_upper "$token")"
    fi
  done < <(printf '%s' "$csv" | tr ',' '\n')
}

contains_token() {
  local haystack_lines="$1"
  local needle="$2"
  while IFS= read -r line; do
    if [[ "$line" == "$needle" ]]; then
      return 0
    fi
  done <<< "$haystack_lines"
  return 1
}

header_first_value() {
  local headers_file="$1"
  local name="$2"
  local name_lc
  name_lc="$(to_lower "$name")"
  awk -v wanted="$name_lc" '
    BEGIN { IGNORECASE = 1 }
    {
      gsub(/\r$/, "", $0)
      if ($0 == "") next
      split($0, parts, ":")
      key = tolower(parts[1])
      if (key == wanted) {
        sub(/^[^:]+:[[:space:]]*/, "", $0)
        print $0
        exit
      }
    }
  ' "$headers_file"
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env: $name" >&2
    exit 1
  fi
}

run_preflight() {
  local path="$1"
  local requested_method="$2"
  local requested_headers="$3"
  local headers_file="$4"

  local url="${BASE_URL}$(normalize_path "$path")"
  local -a args
  args=(
    -sS
    -o /dev/null
    -D "$headers_file"
    -w "%{http_code}"
    -X OPTIONS
    "$url"
    -H "Origin: $SMOKE_ORIGIN"
    -H "Access-Control-Request-Method: $requested_method"
    -H "Access-Control-Request-Headers: $requested_headers"
    -H "User-Agent: $SMOKE_USER_AGENT"
    --max-time "$SMOKE_TIMEOUT_SECS"
    --connect-timeout "$SMOKE_CONNECT_TIMEOUT_SECS"
  )

  if [[ -n "${SMOKE_HOST:-}" ]]; then
    args+=( -H "Host: ${SMOKE_HOST}" )
  fi
  if [[ -n "${SMOKE_RESOLVE:-}" ]]; then
    args+=( --resolve "${SMOKE_RESOLVE}" )
  fi
  if [[ "${SMOKE_INSECURE:-0}" == "1" ]]; then
    args+=( -k )
  fi

  curl "${args[@]}"
}

expect_cors_preflight() {
  local label="$1"
  local path="$2"
  local requested_method="$3"
  local requested_headers="$4"
  local required_allow_headers="$5"
  local forbidden_allow_headers="$6"
  local expected_codes="${7:-200,204}"

  local headers_file
  headers_file="$(mktemp)"
  local code
  code="$(run_preflight "$path" "$requested_method" "$requested_headers" "$headers_file")"

  CHECKS=$((CHECKS + 1))

  local expected_code_lines
  expected_code_lines="$(lower_tokens_csv "$expected_codes")"
  if ! contains_token "$expected_code_lines" "$(to_lower "$code")"; then
    FAILURES=$((FAILURES + 1))
    echo "[FAIL] $label: status=$code expected={$expected_codes}" >&2
    sed -n '1,120p' "$headers_file" >&2 || true
    rm -f "$headers_file"
    return 0
  fi

  local allow_origin
  allow_origin="$(header_first_value "$headers_file" "access-control-allow-origin")"
  if [[ -z "$allow_origin" || "$allow_origin" != "$SMOKE_ORIGIN" ]]; then
    FAILURES=$((FAILURES + 1))
    echo "[FAIL] $label: unexpected Access-Control-Allow-Origin='$allow_origin' expected '$SMOKE_ORIGIN'" >&2
    sed -n '1,120p' "$headers_file" >&2 || true
    rm -f "$headers_file"
    return 0
  fi

  local allow_methods_raw
  allow_methods_raw="$(header_first_value "$headers_file" "access-control-allow-methods")"
  local allow_methods
  allow_methods="$(upper_tokens_csv "$allow_methods_raw")"
  if ! contains_token "$allow_methods" "$(to_upper "$requested_method")"; then
    FAILURES=$((FAILURES + 1))
    echo "[FAIL] $label: Access-Control-Allow-Methods missing $(to_upper "$requested_method")" >&2
    sed -n '1,120p' "$headers_file" >&2 || true
    rm -f "$headers_file"
    return 0
  fi

  local allow_headers_raw
  allow_headers_raw="$(header_first_value "$headers_file" "access-control-allow-headers")"
  local allow_headers
  allow_headers="$(lower_tokens_csv "$allow_headers_raw")"

  while IFS= read -r need; do
    if ! contains_token "$allow_headers" "$need"; then
      FAILURES=$((FAILURES + 1))
      echo "[FAIL] $label: Access-Control-Allow-Headers missing '$need'" >&2
      sed -n '1,120p' "$headers_file" >&2 || true
      rm -f "$headers_file"
      return 0
    fi
  done < <(lower_tokens_csv "$required_allow_headers")

  while IFS= read -r bad; do
    if contains_token "$allow_headers" "$bad"; then
      FAILURES=$((FAILURES + 1))
      echo "[FAIL] $label: Access-Control-Allow-Headers must not contain '$bad'" >&2
      sed -n '1,120p' "$headers_file" >&2 || true
      rm -f "$headers_file"
      return 0
    fi
  done < <(lower_tokens_csv "$forbidden_allow_headers")

  echo "[PASS] $label: status=$code"
  rm -f "$headers_file"
}

expect_no_cors_preflight() {
  local label="$1"
  local path="$2"
  local requested_method="$3"
  local requested_headers="$4"
  local expected_codes="${5:-401,403,404,405}"

  local headers_file
  headers_file="$(mktemp)"
  local code
  code="$(run_preflight "$path" "$requested_method" "$requested_headers" "$headers_file")"

  CHECKS=$((CHECKS + 1))

  local expected_code_lines
  expected_code_lines="$(lower_tokens_csv "$expected_codes")"
  if ! contains_token "$expected_code_lines" "$(to_lower "$code")"; then
    FAILURES=$((FAILURES + 1))
    echo "[FAIL] $label: status=$code expected={$expected_codes}" >&2
    sed -n '1,120p' "$headers_file" >&2 || true
    rm -f "$headers_file"
    return 0
  fi

  local allow_origin
  allow_origin="$(header_first_value "$headers_file" "access-control-allow-origin")"
  if [[ -n "$allow_origin" ]]; then
    FAILURES=$((FAILURES + 1))
    echo "[FAIL] $label: internal/no-cors route leaked Access-Control-Allow-Origin='$allow_origin'" >&2
    sed -n '1,120p' "$headers_file" >&2 || true
    rm -f "$headers_file"
    return 0
  fi

  echo "[PASS] $label: status=$code no CORS headers"
  rm -f "$headers_file"
}

if ! is_uint "$SMOKE_MAX_FAILED_CHECKS"; then
  echo "Invalid SMOKE_MAX_FAILED_CHECKS: $SMOKE_MAX_FAILED_CHECKS (must be integer)" >&2
  exit 1
fi
if ! is_uint "$SMOKE_TIMEOUT_SECS"; then
  echo "Invalid SMOKE_TIMEOUT_SECS: $SMOKE_TIMEOUT_SECS (must be integer)" >&2
  exit 1
fi
if ! is_uint "$SMOKE_CONNECT_TIMEOUT_SECS"; then
  echo "Invalid SMOKE_CONNECT_TIMEOUT_SECS: $SMOKE_CONNECT_TIMEOUT_SECS (must be integer)" >&2
  exit 1
fi

require_env SMOKE_BASE_URL
BASE_URL="$(trim_base "$SMOKE_BASE_URL")"

expect_cors_preflight \
  "public auth preflight" \
  "/auth/biometric/login" \
  "POST" \
  "content-type,x-request-id" \
  "content-type,x-request-id" \
  "authorization,x-chat-device-id,x-chat-device-token,idempotency-key,x-device-id,x-merchant,x-ref,x-internal-secret,x-internal-service-id,cookie"

expect_cors_preflight \
  "chat preflight" \
  "/chat/messages/send" \
  "POST" \
  "content-type,x-chat-device-id,x-chat-device-token" \
  "content-type,x-request-id,x-chat-device-id,x-chat-device-token" \
  "authorization,idempotency-key,x-device-id,x-merchant,x-ref,x-internal-secret,x-internal-service-id,cookie"

expect_cors_preflight \
  "contacts preflight" \
  "/contacts/invites/redeem" \
  "POST" \
  "content-type,x-chat-device-id" \
  "content-type,x-request-id,x-chat-device-id" \
  "authorization,x-chat-device-token,idempotency-key,x-device-id,x-merchant,x-ref,x-internal-secret,x-internal-service-id,cookie"

expect_cors_preflight \
  "payments preflight" \
  "/payments/transfer" \
  "POST" \
  "content-type,idempotency-key,x-device-id,x-merchant,x-ref" \
  "content-type,x-request-id,idempotency-key,x-device-id,x-merchant,x-ref" \
  "authorization,x-chat-device-id,x-chat-device-token,x-internal-secret,x-internal-service-id,cookie"

expect_cors_preflight \
  "bus preflight" \
  "/bus/trips/cors-smoke/book" \
  "POST" \
  "content-type,idempotency-key,x-device-id" \
  "content-type,x-request-id,idempotency-key,x-device-id" \
  "authorization,x-chat-device-id,x-chat-device-token,x-merchant,x-ref,x-internal-secret,x-internal-service-id,cookie"

expect_no_cors_preflight \
  "internal security alerts preflight blocked/no-cors" \
  "/internal/security/alerts" \
  "POST" \
  "content-type,x-request-id"

echo "CORS preflight smoke summary: checks=$CHECKS failures=$FAILURES max_failures=$SMOKE_MAX_FAILED_CHECKS"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## CORS Preflight Smoke Summary"
    echo "- Base URL: $BASE_URL"
    echo "- Origin: $SMOKE_ORIGIN"
    echo "- Checks: $CHECKS"
    echo "- Failures: $FAILURES"
    echo "- Allowed failures: $SMOKE_MAX_FAILED_CHECKS"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$FAILURES" -gt "$SMOKE_MAX_FAILED_CHECKS" ]]; then
  echo "CORS preflight smoke failed threshold (failures=$FAILURES > max=$SMOKE_MAX_FAILED_CHECKS)." >&2
  exit 1
fi

echo "CORS preflight smoke checks completed successfully."
