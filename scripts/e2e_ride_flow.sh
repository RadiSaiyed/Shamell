#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_PORT="${BASE_PORT:-19580}"
E2E_PG_HOST="${E2E_PG_HOST:-127.0.0.1}"
E2E_PG_PORT="${E2E_PG_PORT:-5432}"
E2E_PG_USER="${E2E_PG_USER:-shamell}"
E2E_PG_PASSWORD="${E2E_PG_PASSWORD:-shamell}"
SKIP_BUILD=0
KEEP_RUNNING=0

usage() {
  cat <<'USAGE'
Usage: scripts/e2e_ride_flow.sh [options]

Runs a local ride-hailing end-to-end smoke across auth, rides, dispatch, tracking,
and the driver 10% reserve rule using isolated temporary databases.

Options:
  --base-port <port>   Base port for local services (default: 19580)
  --skip-build         Skip cargo build before starting services
  --keep-running       Do not stop started services or drop temp databases
  -h, --help           Show this help

Environment:
  E2E_PG_HOST          Postgres host (default: 127.0.0.1)
  E2E_PG_PORT          Postgres port (default: 5432)
  E2E_PG_USER          Postgres admin/user role (default: shamell)
  E2E_PG_PASSWORD      Postgres password (default: shamell)
USAGE
}

log() {
  printf '[ride-e2e] %s\n' "$*"
}

fail() {
  printf '[ride-e2e][error] %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-port)
      [[ $# -ge 2 ]] || fail "--base-port requires a value"
      BASE_PORT="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --keep-running)
      KEEP_RUNNING=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

resolve_pg_bin() {
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then
    command -v "$bin"
    return 0
  fi
  local prefix
  for prefix in \
    /opt/homebrew/opt/postgresql@16/bin \
    /usr/local/opt/postgresql@16/bin \
    /opt/homebrew/bin \
    /usr/local/bin; do
    if [[ -x "$prefix/$bin" ]]; then
      printf '%s/%s\n' "$prefix" "$bin"
      return 0
    fi
  done
  return 1
}

PSQL="$(resolve_pg_bin psql)" || fail "unable to locate psql binary"
CREATEDB="$(resolve_pg_bin createdb)" || fail "unable to locate createdb binary"
DROPDB_BIN="$(resolve_pg_bin dropdb)" || fail "unable to locate dropdb binary"
PG_ISREADY="$(resolve_pg_bin pg_isready)" || fail "unable to locate pg_isready binary"

require_cmd curl
require_cmd jq
require_cmd openssl
require_cmd awk
require_cmd cargo
export PGPASSWORD="$E2E_PG_PASSWORD"

ensure_built_binary() {
  local path="$1"
  [[ -x "$path" ]] || fail "missing built binary: ${path} (rerun without --skip-build)"
}

RUN_SUFFIX="$(date +%Y%m%d%H%M%S)-$(openssl rand -hex 2)"
PORT_BFF="$BASE_PORT"
PORT_CHAT="$((BASE_PORT + 1))"
PORT_PAY="$((BASE_PORT + 2))"
BASE_URL="http://127.0.0.1:${PORT_BFF}"
LOG_DIR="/tmp/shamell-ride-e2e-${RUN_SUFFIX}"

DB_CORE="shamell_ride_smoke_core_${RUN_SUFFIX//-/_}"
DB_CHAT="shamell_ride_smoke_chat_${RUN_SUFFIX//-/_}"
DB_PAY="shamell_ride_smoke_pay_${RUN_SUFFIX//-/_}"
FEE_ACCOUNT_ID="$(openssl rand -hex 32)"

mkdir -p "$LOG_DIR"

PID_CHAT=""
PID_PAY=""
PID_BFF=""

cleanup() {
  if [[ "$KEEP_RUNNING" != "1" ]]; then
    local pid
    for pid in "$PID_CHAT" "$PID_PAY" "$PID_BFF"; do
      if [[ -n "${pid:-}" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        sleep 0.2
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    done
    for db in "$DB_CORE" "$DB_CHAT" "$DB_PAY"; do
      "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db}' AND pid <> pg_backend_pid();" \
        >/dev/null 2>&1 || true
      "$DROPDB_BIN" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" "$db" >/dev/null 2>&1 || true
    done
  else
    log "keeping services and temp databases running (requested)"
  fi
}
trap cleanup EXIT

start_service() {
  local log_file="$1"
  shift
  "$@" >"$log_file" 2>&1 &
  printf '%s\n' "$!"
}

wait_health() {
  local name="$1"
  local url="$2"
  local _ignored
  for _ignored in $(seq 1 90); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      log "health ${name}: ok"
      return 0
    fi
    sleep 0.5
  done
  if [[ -f "$LOG_DIR/${name}.log" ]]; then
    tail -n 120 "$LOG_DIR/${name}.log" >&2 || true
  fi
  fail "service ${name} did not become healthy"
}

http_post_json() {
  local url="$1"
  local out="$2"
  local headers_out="$3"
  local body="$4"
  shift 4
  curl -sS -o "$out" -D "$headers_out" -w '%{http_code}' \
    "$@" -H 'Content-Type: application/json' -d "$body" "$url"
}

http_get_json() {
  local url="$1"
  local out="$2"
  shift 2
  curl -sS -o "$out" -w '%{http_code}' "$@" "$url"
}

extract_session_cookie() {
  local headers_file="$1"
  grep -i '^set-cookie: __Host-sa_session=' "$headers_file" \
    | head -n1 \
    | sed -E 's/^[^=]+=([^;]+).*/\1/I' \
    | tr -d '\r'
}

assert_http_code() {
  local label="$1"
  local code="$2"
  shift 2
  local expected
  for expected in "$@"; do
    if [[ "$code" == "$expected" ]]; then
      return 0
    fi
  done
  fail "${label} failed (HTTP=${code}, expected=${*})"
}

ensure_pg_ready() {
  "$PG_ISREADY" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" >/dev/null \
    || fail "postgres is not accepting connections on ${E2E_PG_HOST}:${E2E_PG_PORT}"
}

ensure_role() {
  local exists
  exists="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='shamell'")"
  if [[ "$exists" != "1" ]]; then
    "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d postgres -c "CREATE ROLE shamell WITH LOGIN PASSWORD 'shamell';" >/dev/null
  else
    "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d postgres -c "ALTER ROLE shamell WITH LOGIN PASSWORD 'shamell';" >/dev/null
  fi
}

create_db() {
  local db="$1"
  "$CREATEDB" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -O shamell "$db"
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$db" -c "GRANT ALL PRIVILEGES ON DATABASE ${db} TO shamell;" >/dev/null
}

lookup_account_id_by_shamell_id() {
  local shamell_id="$1"
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_CORE" -At -c \
    "SELECT account_id FROM auth_accounts WHERE shamell_user_id='${shamell_id}' LIMIT 1;"
}

grant_payments_role() {
  local account_id="$1"
  local role="$2"
  local role_id
  role_id="$(openssl rand -hex 16)"
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_PAY" -c \
    "INSERT INTO roles (id, account_id, phone, role, created_at) SELECT '${role_id}', '${account_id}', NULL, '${role}', NOW() WHERE NOT EXISTS (SELECT 1 FROM roles WHERE account_id='${account_id}' AND role='${role}');" \
    >/dev/null
}

grant_auth_role() {
  local account_id="$1"
  local role_id="$2"
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_CORE" -c \
    "INSERT INTO auth_role_assignments (subject_account_id, subject_phone, role_id, created_by_account_id, created_at, revoked_by_account_id, revoked_at, revoke_reason, metadata) SELECT '${account_id}', NULL, '${role_id}', NULL, NOW(), NULL, NULL, NULL, '{\"source\":\"ride_e2e\"}'::jsonb WHERE NOT EXISTS (SELECT 1 FROM auth_role_assignments WHERE subject_account_id='${account_id}' AND role_id='${role_id}' AND revoked_at IS NULL);" \
    >/dev/null
}

upsert_driver_document() {
  local account_id="$1"
  local document_type="$2"
  local document_number="$3"
  local account_suffix="${account_id:0:8}"
  local document_id="doc-${RUN_SUFFIX}-${account_suffix}-${document_type}"
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_CORE" -c \
    "INSERT INTO auth_ride_driver_documents (document_id, driver_account_id, document_type, document_number, issuing_country, status, review_note, reviewer_account_id, submitted_at, reviewed_at, updated_at) VALUES ('${document_id}', '${account_id}', '${document_type}', '${document_number}', 'SY', 'approved', 'smoke approved', 'ride-smoke-reviewer', NOW(), NOW(), NOW()) ON CONFLICT (driver_account_id, document_type) DO UPDATE SET document_number=EXCLUDED.document_number, issuing_country=EXCLUDED.issuing_country, status='approved', review_note='smoke approved', reviewer_account_id='ride-smoke-reviewer', submitted_at=NOW(), reviewed_at=NOW(), updated_at=NOW();" \
    >/dev/null
}

json_field() {
  local file="$1"
  local expr="$2"
  jq -r "$expr" "$file"
}

create_and_match_ride() {
  local idempotency_suffix="$1"
  local fare_estimate_cents="$2"
  local pickup="$3"
  local destination="$4"
  local trip_create_body trip_create_headers trip_create_code
  local match_body match_headers match_code
  local ride_id

  trip_create_body="$(mktemp)"
  trip_create_headers="$(mktemp)"
  trip_create_code="$(http_post_json "${BASE_URL}/me/rides/trips" "$trip_create_body" "$trip_create_headers" \
    "{\"pickup\":\"${pickup}\",\"destination\":\"${destination}\",\"ride_class\":\"economy\",\"fare_estimate_cents\":${fare_estimate_cents},\"eta_seconds\":600}" \
    -H "Cookie: ${RIDER_COOKIE}" -H "Idempotency-Key: ride-smoke-create-${idempotency_suffix}")"
  assert_http_code "ride create ${idempotency_suffix}" "$trip_create_code" 200
  ride_id="$(json_field "$trip_create_body" '.ride_id // empty')"
  [[ -n "$ride_id" ]] || fail "ride create ${idempotency_suffix} response missing ride_id"

  match_body="$(mktemp)"
  match_headers="$(mktemp)"
  match_code="$(http_post_json "${BASE_URL}/me/rides/trips/${ride_id}/enter_matching" "$match_body" "$match_headers" '{}' \
    -H "Cookie: ${RIDER_COOKIE}" -H "Idempotency-Key: ride-smoke-match-${idempotency_suffix}")"
  assert_http_code "ride enter matching ${idempotency_suffix}" "$match_code" 200

  printf '%s\n' "$ride_id"
}

poll_until() {
  local label="$1"
  local attempts="$2"
  local sleep_secs="$3"
  shift 3
  local _ignored
  for _ignored in $(seq 1 "$attempts"); do
    if "$@"; then
      return 0
    fi
    sleep "$sleep_secs"
  done
  fail "${label} did not become true"
}

if [[ "$SKIP_BUILD" == "0" ]]; then
  log "building backend binaries"
  (
    cd "$ROOT_DIR"
    cargo build -p shamell_chat_service -p shamell_payments_service -p shamell_bff_gateway
  )
else
  ensure_built_binary "$ROOT_DIR/target/debug/shamell_chat_service"
  ensure_built_binary "$ROOT_DIR/target/debug/shamell_payments_service"
  ensure_built_binary "$ROOT_DIR/target/debug/shamell_bff_gateway"
fi

log "preparing isolated postgres databases"
ensure_pg_ready
ensure_role
create_db "$DB_CORE"
create_db "$DB_CHAT"
create_db "$DB_PAY"

log "starting local services (logs: $LOG_DIR)"
PID_CHAT="$(start_service "$LOG_DIR/chat.log" \
  env \
    ENV=dev APP_HOST=127.0.0.1 APP_PORT="$PORT_CHAT" \
    CHAT_DB_URL="postgresql://shamell:${E2E_PG_PASSWORD}@${E2E_PG_HOST}:${E2E_PG_PORT}/${DB_CHAT}" \
    CHAT_REQUIRE_INTERNAL_SECRET=false CHAT_ENFORCE_DEVICE_AUTH=false CHAT_MAILBOX_API_ENABLED=true \
    RUST_LOG=info \
    "$ROOT_DIR/target/debug/shamell_chat_service")"

PID_PAY="$(start_service "$LOG_DIR/payments.log" \
  env \
    ENV=dev APP_HOST=127.0.0.1 APP_PORT="$PORT_PAY" \
    PAYMENTS_DB_URL="postgresql://shamell:${E2E_PG_PASSWORD}@${E2E_PG_HOST}:${E2E_PG_PORT}/${DB_PAY}" \
    PAYMENTS_REQUIRE_INTERNAL_SECRET=false PAYMENTS_ALLOW_DIRECT_TOPUP=true MERCHANT_FEE_BPS=0 \
    PAYMENTS_AUTO_PROVISION_FEE_WALLET=true FEE_WALLET_ACCOUNT_ID="$FEE_ACCOUNT_ID" \
    RUST_LOG=info \
    "$ROOT_DIR/target/debug/shamell_payments_service")"

PID_BFF="$(start_service "$LOG_DIR/bff.log" \
  env \
    ENV=dev APP_HOST=127.0.0.1 APP_PORT="$PORT_BFF" \
    DB_URL="postgresql://shamell:${E2E_PG_PASSWORD}@${E2E_PG_HOST}:${E2E_PG_PORT}/${DB_CORE}" \
    CHAT_BASE_URL="http://127.0.0.1:${PORT_CHAT}" \
    PAYMENTS_BASE_URL="http://127.0.0.1:${PORT_PAY}" \
    FEE_WALLET_ACCOUNT_ID="$FEE_ACCOUNT_ID" \
    BFF_REQUIRE_INTERNAL_SECRET=false BFF_ENFORCE_ROUTE_AUTHZ=false \
    AUTH_ACCOUNT_CREATE_ENABLED=true AUTH_ACCOUNT_CREATE_POW_ENABLED=false \
    AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=false \
    AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=false \
    RUST_LOG=info \
    "$ROOT_DIR/target/debug/shamell_bff_gateway")"

wait_health chat "http://127.0.0.1:${PORT_CHAT}/health"
wait_health payments "http://127.0.0.1:${PORT_PAY}/health"
wait_health bff "${BASE_URL}/health"

suffix="$(openssl rand -hex 2)"
DEVICE_RIDER="ride${suffix}"
DEVICE_DRIVER="drv${suffix}"
DEVICE_DRIVER_2="drv2${suffix}"

create_account() {
  local label="$1"
  local device_id="$2"
  local username password body_out header_out code shamell_id session
  username="ride${label}${suffix}"
  password="RideSmoke-${suffix}-${label}-A1"
  body_out="$(mktemp)"
  header_out="$(mktemp)"
  code="$(http_post_json "${BASE_URL}/auth/signup" "$body_out" "$header_out" "{\"username\":\"${username}\",\"password\":\"${password}\",\"device_id\":\"${device_id}\"}")"
  assert_http_code "account create ${label}" "$code" 200
  shamell_id="$(json_field "$body_out" '.shamell_id // empty')"
  session="$(extract_session_cookie "$header_out")"
  [[ -n "$shamell_id" && -n "$session" ]] || fail "${label} missing shamell_id/session"
  printf '%s|%s\n' "$shamell_id" "$session"
}

log "creating rider and driver accounts"
IFS='|' read -r RIDER_SHAMELL_ID RIDER_SESSION <<<"$(create_account rider "$DEVICE_RIDER")"
IFS='|' read -r DRIVER_SHAMELL_ID DRIVER_SESSION <<<"$(create_account driver "$DEVICE_DRIVER")"
IFS='|' read -r DRIVER2_SHAMELL_ID DRIVER2_SESSION <<<"$(create_account driver2 "$DEVICE_DRIVER_2")"

RIDER_ACCOUNT_ID="$(lookup_account_id_by_shamell_id "$RIDER_SHAMELL_ID")"
DRIVER_ACCOUNT_ID="$(lookup_account_id_by_shamell_id "$DRIVER_SHAMELL_ID")"
DRIVER2_ACCOUNT_ID="$(lookup_account_id_by_shamell_id "$DRIVER2_SHAMELL_ID")"
[[ -n "$RIDER_ACCOUNT_ID" && -n "$DRIVER_ACCOUNT_ID" && -n "$DRIVER2_ACCOUNT_ID" ]] || fail "account lookup failed"

RIDER_COOKIE="__Host-sa_session=${RIDER_SESSION}"
DRIVER_COOKIE="__Host-sa_session=${DRIVER_SESSION}"
DRIVER2_COOKIE="__Host-sa_session=${DRIVER2_SESSION}"

create_payments_user() {
  local cookie="$1"
  local device_id="$2"
  local body_out header_out code wallet_id
  body_out="$(mktemp)"
  header_out="$(mktemp)"
  code="$(http_post_json "${BASE_URL}/payments/users" "$body_out" "$header_out" '{}' \
    -H "Cookie: ${cookie}" -H "x-device-id: ${device_id}")"
  assert_http_code "payments user create" "$code" 200
  wallet_id="$(json_field "$body_out" '.wallet_id // empty')"
  [[ -n "$wallet_id" ]] || fail "payments user response missing wallet_id"
  printf '%s\n' "$wallet_id"
}

log "creating rider and driver wallets"
RIDER_WALLET_ID="$(create_payments_user "$RIDER_COOKIE" "$DEVICE_RIDER")"
DRIVER_WALLET_ID="$(create_payments_user "$DRIVER_COOKIE" "$DEVICE_DRIVER")"
DRIVER2_WALLET_ID="$(create_payments_user "$DRIVER2_COOKIE" "$DEVICE_DRIVER_2")"

log "granting driver/operator roles and approving driver documents"
grant_payments_role "$DRIVER_ACCOUNT_ID" "driver"
grant_payments_role "$DRIVER_ACCOUNT_ID" "ops"
grant_payments_role "$DRIVER2_ACCOUNT_ID" "driver"
grant_auth_role "$DRIVER_ACCOUNT_ID" "rides.driver"
grant_auth_role "$DRIVER_ACCOUNT_ID" "rides.driver_ops"
grant_auth_role "$DRIVER2_ACCOUNT_ID" "rides.driver"
upsert_driver_document "$DRIVER_ACCOUNT_ID" "driver_license" "DRV-${suffix}-01"
upsert_driver_document "$DRIVER_ACCOUNT_ID" "vehicle_registration" "REG-${suffix}-02"
upsert_driver_document "$DRIVER_ACCOUNT_ID" "insurance" "INS-${suffix}-03"
upsert_driver_document "$DRIVER_ACCOUNT_ID" "identity_card" "ID-${suffix}-04"
upsert_driver_document "$DRIVER2_ACCOUNT_ID" "driver_license" "DRV2-${suffix}-01"
upsert_driver_document "$DRIVER2_ACCOUNT_ID" "vehicle_registration" "REG2-${suffix}-02"
upsert_driver_document "$DRIVER2_ACCOUNT_ID" "insurance" "INS2-${suffix}-03"
upsert_driver_document "$DRIVER2_ACCOUNT_ID" "identity_card" "ID2-${suffix}-04"

log "publishing initial driver presence"
PRESENCE_BODY="$(mktemp)"
PRESENCE_HEADERS="$(mktemp)"
PRESENCE_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/presence" "$PRESENCE_BODY" "$PRESENCE_HEADERS" \
  '{"online":true,"lat":33.5138,"lon":36.2765,"driver_name":"Smoke Driver","car_plate":"SMK-001"}' \
  -H "Cookie: ${DRIVER_COOKIE}")"
assert_http_code "driver presence online" "$PRESENCE_CODE" 200
PRESENCE2_BODY="$(mktemp)"
PRESENCE2_HEADERS="$(mktemp)"
PRESENCE2_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/presence" "$PRESENCE2_BODY" "$PRESENCE2_HEADERS" \
  '{"online":true,"lat":33.5212,"lon":36.3041,"driver_name":"Smoke Driver 2","car_plate":"SMK-002"}' \
  -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver2 presence online" "$PRESENCE2_CODE" 200

log "creating ride request"
RIDE_ID="$(create_and_match_ride "001" 2500 "Bab Touma Damascus" "Malki Damascus")"

QUEUE_BODY="$(mktemp)"
QUEUE2_BODY="$(mktemp)"
OFFER_ID=""
OFFER2_ID=""
poll_queue() {
  local ride_id="$1"
  local cookie="$2"
  local out_file="$3"
  local offer_var="$4"
  local code
  code="$(http_get_json "${BASE_URL}/me/rides/driver/dispatch_offers?limit=10" "$out_file" -H "Cookie: ${cookie}")"
  if [[ "$code" != "200" ]]; then
    return 1
  fi
  local offer_id
  offer_id="$(jq -r --arg ride_id "$ride_id" '.[] | select(.ride_id == $ride_id) | (.offer_id // "")' "$out_file" | head -n1)"
  printf -v "$offer_var" '%s' "$offer_id"
  [[ -n "$offer_id" ]]
}
poll_until "dispatch offer for driver1" 40 0.5 poll_queue "$RIDE_ID" "$DRIVER_COOKIE" "$QUEUE_BODY" OFFER_ID

log "verifying low-balance accept is blocked"
ACCEPT_FAIL_BODY="$(mktemp)"
ACCEPT_FAIL_HEADERS="$(mktemp)"
ACCEPT_FAIL_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/trips/${RIDE_ID}/accept" "$ACCEPT_FAIL_BODY" "$ACCEPT_FAIL_HEADERS" \
  '{"driver_name":"Smoke Driver","car_plate":"SMK-001","eta_seconds":420}' \
  -H "Cookie: ${DRIVER_COOKIE}" -H 'Idempotency-Key: ride-smoke-accept-low-balance-001')"
assert_http_code "low balance accept" "$ACCEPT_FAIL_CODE" 409
grep -q '10% platform fee' "$ACCEPT_FAIL_BODY" \
  || fail "low balance accept detail did not mention 10% platform fee"

log "topping up driver wallet and accepting ride"
TOPUP_BODY="$(mktemp)"
TOPUP_HEADERS="$(mktemp)"
TOPUP_CODE="$(http_post_json "${BASE_URL}/payments/wallets/${DRIVER_WALLET_ID}/topup" "$TOPUP_BODY" "$TOPUP_HEADERS" \
  '{"amount_cents":1000}' \
  -H "Cookie: ${DRIVER_COOKIE}" -H "x-device-id: ${DEVICE_DRIVER}" -H 'Idempotency-Key: ride-smoke-driver-topup-001')"
assert_http_code "driver topup" "$TOPUP_CODE" 200

ACCEPT_OK_BODY="$(mktemp)"
ACCEPT_OK_HEADERS="$(mktemp)"
ACCEPT_OK_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/trips/${RIDE_ID}/accept" "$ACCEPT_OK_BODY" "$ACCEPT_OK_HEADERS" \
  '{"driver_name":"Smoke Driver","car_plate":"SMK-001","eta_seconds":420}' \
  -H "Cookie: ${DRIVER_COOKIE}" -H 'Idempotency-Key: ride-smoke-accept-funded-001')"
assert_http_code "funded accept" "$ACCEPT_OK_CODE" 200

LEDGER_RESERVED_BODY="$(mktemp)"
LEDGER_RESERVED_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${DRIVER_WALLET_ID}/driver-ledger" "$LEDGER_RESERVED_BODY" \
  -H "Cookie: ${DRIVER_COOKIE}")"
assert_http_code "driver ledger reserved" "$LEDGER_RESERVED_CODE" 200
HELD_AFTER_ACCEPT="$(json_field "$LEDGER_RESERVED_BODY" '.held_reserve_cents // -1')"
[[ "$HELD_AFTER_ACCEPT" == "250" ]] || fail "expected held_reserve_cents=250 after accept, got ${HELD_AFTER_ACCEPT}"

log "verifying operator fleet sees active ride"
FLEET_BODY="$(mktemp)"
FLEET_CODE="$(http_get_json "${BASE_URL}/me/rides/operator/fleet/live?limit=10" "$FLEET_BODY" \
  -H "Cookie: ${DRIVER_COOKIE}")"
assert_http_code "operator fleet live" "$FLEET_CODE" 200
FLEET_ACTIVE_RIDE_ID="$(jq -r --arg driver_id "$DRIVER_ACCOUNT_ID" '.drivers[] | select(.driver_account_id == $driver_id) | (.active_ride_id // "")' "$FLEET_BODY" | head -n1)"
[[ "$FLEET_ACTIVE_RIDE_ID" == "$RIDE_ID" ]] || fail "operator fleet did not show active_ride_id=${RIDE_ID}"

log "reassigning active ride from driver1"
REASSIGN_BODY="$(mktemp)"
REASSIGN_HEADERS="$(mktemp)"
REASSIGN_CODE="$(http_post_json "${BASE_URL}/me/rides/operator/trips/${RIDE_ID}/commands" "$REASSIGN_BODY" "$REASSIGN_HEADERS" \
  '{"command":"reassign_trip","reason":"smoke reassign to second driver"}' \
  -H "Cookie: ${DRIVER_COOKIE}" -H 'Idempotency-Key: ride-smoke-reassign-001')"
assert_http_code "operator reassign trip" "$REASSIGN_CODE" 200

RIDER_MATCHING_BODY="$(mktemp)"
RIDER_MATCHING_CODE="$(http_get_json "${BASE_URL}/me/rides/trips/active" "$RIDER_MATCHING_BODY" -H "Cookie: ${RIDER_COOKIE}")"
assert_http_code "rider active after reassign" "$RIDER_MATCHING_CODE" 200
[[ "$(json_field "$RIDER_MATCHING_BODY" '.active.status // empty')" == "matching" ]] \
  || fail "expected rider active status matching after reassign"

DRIVER1_ACTIVE_AFTER_REASSIGN_BODY="$(mktemp)"
DRIVER1_ACTIVE_AFTER_REASSIGN_CODE="$(http_get_json "${BASE_URL}/me/rides/driver/trips/active" "$DRIVER1_ACTIVE_AFTER_REASSIGN_BODY" -H "Cookie: ${DRIVER_COOKIE}")"
assert_http_code "driver1 active after reassign" "$DRIVER1_ACTIVE_AFTER_REASSIGN_CODE" 200
[[ "$(json_field "$DRIVER1_ACTIVE_AFTER_REASSIGN_BODY" '.active')" == "null" ]] \
  || fail "expected driver1 active to be null after reassign"

LEDGER_DRIVER1_RELEASED_BODY="$(mktemp)"
LEDGER_DRIVER1_RELEASED_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${DRIVER_WALLET_ID}/driver-ledger" "$LEDGER_DRIVER1_RELEASED_BODY" \
  -H "Cookie: ${DRIVER_COOKIE}")"
assert_http_code "driver1 ledger released" "$LEDGER_DRIVER1_RELEASED_CODE" 200
HELD_AFTER_REASSIGN="$(json_field "$LEDGER_DRIVER1_RELEASED_BODY" '.held_reserve_cents // -1')"
[[ "$HELD_AFTER_REASSIGN" == "0" ]] || fail "expected driver1 held_reserve_cents=0 after reassign, got ${HELD_AFTER_REASSIGN}"

OFFER_ID=""
if poll_queue "$RIDE_ID" "$DRIVER_COOKIE" "$QUEUE_BODY" OFFER_ID; then
  fail "driver1 should not receive the reassigned offer again"
fi
poll_until "dispatch offer for driver2 after reassign" 40 0.5 poll_queue "$RIDE_ID" "$DRIVER2_COOKIE" "$QUEUE2_BODY" OFFER2_ID

log "topping up driver2 wallet and accepting reassigned ride"
TOPUP2_BODY="$(mktemp)"
TOPUP2_HEADERS="$(mktemp)"
TOPUP2_CODE="$(http_post_json "${BASE_URL}/payments/wallets/${DRIVER2_WALLET_ID}/topup" "$TOPUP2_BODY" "$TOPUP2_HEADERS" \
  '{"amount_cents":1000}' \
  -H "Cookie: ${DRIVER2_COOKIE}" -H "x-device-id: ${DEVICE_DRIVER_2}" -H 'Idempotency-Key: ride-smoke-driver2-topup-001')"
assert_http_code "driver2 topup" "$TOPUP2_CODE" 200

ACCEPT2_BODY="$(mktemp)"
ACCEPT2_HEADERS="$(mktemp)"
ACCEPT2_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/dispatch_offers/${OFFER2_ID}/accept" "$ACCEPT2_BODY" "$ACCEPT2_HEADERS" \
  '{"driver_name":"Smoke Driver 2","car_plate":"SMK-002","eta_seconds":360}' \
  -H "Cookie: ${DRIVER2_COOKIE}" -H 'Idempotency-Key: ride-smoke-accept-driver2-001')"
if [[ "$ACCEPT2_CODE" != "200" ]]; then
  log "driver2 accept response: $(cat "$ACCEPT2_BODY")"
  log "driver2 queue snapshot: $(cat "$QUEUE2_BODY")"
fi
assert_http_code "driver2 accept" "$ACCEPT2_CODE" 200

LEDGER_RESERVED_DRIVER2_BODY="$(mktemp)"
LEDGER_RESERVED_DRIVER2_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${DRIVER2_WALLET_ID}/driver-ledger" "$LEDGER_RESERVED_DRIVER2_BODY" \
  -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver2 ledger reserved" "$LEDGER_RESERVED_DRIVER2_CODE" 200
HELD_DRIVER2_AFTER_ACCEPT="$(json_field "$LEDGER_RESERVED_DRIVER2_BODY" '.held_reserve_cents // -1')"
[[ "$HELD_DRIVER2_AFTER_ACCEPT" == "250" ]] || fail "expected driver2 held_reserve_cents=250 after accept, got ${HELD_DRIVER2_AFTER_ACCEPT}"

driver_status_command() {
  local label="$1"
  local command="$2"
  local cookie="$3"
  local body_out headers_out code
  body_out="$(mktemp)"
  headers_out="$(mktemp)"
  code="$(http_post_json "${BASE_URL}/me/rides/driver/trips/${RIDE_ID}/status" "$body_out" "$headers_out" \
    "{\"status\":\"${command}\"}" \
    -H "Cookie: ${cookie}" -H "Idempotency-Key: ride-smoke-status-${command}-001")"
  assert_http_code "$label" "$code" 200
  printf '%s\n' "$body_out"
}

ARRIVING_BODY="$(driver_status_command 'driver2 head_to_pickup' 'head_to_pickup' "$DRIVER2_COOKIE")"

LOCATION_BODY="$(mktemp)"
LOCATION_HEADERS="$(mktemp)"
LOCATION_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/trips/${RIDE_ID}/location_ping" "$LOCATION_BODY" "$LOCATION_HEADERS" \
  '{"lat":33.5152,"lon":36.29637,"accuracy_meters":8,"speed_kmh":36,"heading_degrees":45}' \
  -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver location ping" "$LOCATION_CODE" 200

TRACKING_BODY="$(mktemp)"
TRACKING_CODE="$(http_get_json "${BASE_URL}/me/rides/trips/${RIDE_ID}/tracking" "$TRACKING_BODY" \
  -H "Cookie: ${RIDER_COOKIE}")"
assert_http_code "rider tracking snapshot" "$TRACKING_CODE" 200
LATEST_TRACKING_KIND="$(json_field "$TRACKING_BODY" '.latest_driver_location.event_kind // empty')"
[[ "$LATEST_TRACKING_KIND" == "driver_location" ]] || fail "expected latest driver tracking event"

LIVE_BODY="$(mktemp)"
LIVE_CODE="$(http_get_json "${BASE_URL}/me/rides/trips/${RIDE_ID}/live" "$LIVE_BODY" \
  -H "Cookie: ${RIDER_COOKIE}")"
assert_http_code "rider live snapshot" "$LIVE_CODE" 200
LIVE_STAGE="$(json_field "$LIVE_BODY" '.live_state.stage // empty')"
[[ -n "$LIVE_STAGE" ]] || fail "ride live_state.stage missing"

ARRIVED_BODY="$(driver_status_command 'driver2 arrived_pickup' 'arrived_pickup' "$DRIVER2_COOKIE")"
STARTED_BODY="$(driver_status_command 'driver2 start_trip' 'start_trip' "$DRIVER2_COOKIE")"
IN_PROGRESS_BODY="$(driver_status_command 'driver2 in_progress' 'in_progress' "$DRIVER2_COOKIE")"
COMPLETED_BODY="$(driver_status_command 'driver2 complete_trip' 'complete_trip' "$DRIVER2_COOKIE")"

LEDGER_SETTLED_BODY="$(mktemp)"
LEDGER_SETTLED_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${DRIVER2_WALLET_ID}/driver-ledger" "$LEDGER_SETTLED_BODY" \
  -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver2 ledger settled" "$LEDGER_SETTLED_CODE" 200
HELD_AFTER_COMPLETE="$(json_field "$LEDGER_SETTLED_BODY" '.held_reserve_cents // -1')"
[[ "$HELD_AFTER_COMPLETE" == "0" ]] || fail "expected driver2 held_reserve_cents=0 after complete, got ${HELD_AFTER_COMPLETE}"

FEE_WALLET_BALANCE="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_PAY" -At -c \
  "SELECT w.balance_cents FROM users u JOIN wallets w ON w.user_id = u.id WHERE u.account_id='${FEE_ACCOUNT_ID}' LIMIT 1;")"
[[ "$FEE_WALLET_BALANCE" == "250" ]] || fail "expected fee wallet balance 250 after complete, got ${FEE_WALLET_BALANCE:-<empty>}"

RIDER_ACTIVE_BODY="$(mktemp)"
RIDER_ACTIVE_CODE="$(http_get_json "${BASE_URL}/me/rides/trips/active" "$RIDER_ACTIVE_BODY" -H "Cookie: ${RIDER_COOKIE}")"
assert_http_code "rider active after complete" "$RIDER_ACTIVE_CODE" 200
[[ "$(json_field "$RIDER_ACTIVE_BODY" '.active')" == "null" ]] || fail "expected rider active to be null after complete"

DRIVER_ACTIVE_BODY="$(mktemp)"
DRIVER_ACTIVE_CODE="$(http_get_json "${BASE_URL}/me/rides/driver/trips/active" "$DRIVER_ACTIVE_BODY" -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver2 active after complete" "$DRIVER_ACTIVE_CODE" 200
[[ "$(json_field "$DRIVER_ACTIVE_BODY" '.active')" == "null" ]] || fail "expected driver2 active to be null after complete"

log "taking driver1 offline so cancel scenario targets driver2 deterministically"
DRIVER1_OFFLINE_BODY="$(mktemp)"
DRIVER1_OFFLINE_HEADERS="$(mktemp)"
DRIVER1_OFFLINE_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/presence" "$DRIVER1_OFFLINE_BODY" "$DRIVER1_OFFLINE_HEADERS" \
  '{"online":false}' \
  -H "Cookie: ${DRIVER_COOKIE}")"
assert_http_code "driver1 presence offline" "$DRIVER1_OFFLINE_CODE" 200

log "creating second ride for explicit cancel-release verification"
RIDE_CANCEL_ID="$(create_and_match_ride "002" 1800 "Abu Rummaneh Damascus" "Qassa Damascus")"
QUEUE_CANCEL_BODY="$(mktemp)"
OFFER_CANCEL_ID=""
poll_until "dispatch offer for driver2 cancel scenario" 40 0.5 poll_queue "$RIDE_CANCEL_ID" "$DRIVER2_COOKIE" "$QUEUE_CANCEL_BODY" OFFER_CANCEL_ID

ACCEPT_CANCEL_BODY="$(mktemp)"
ACCEPT_CANCEL_HEADERS="$(mktemp)"
ACCEPT_CANCEL_CODE="$(http_post_json "${BASE_URL}/me/rides/driver/dispatch_offers/${OFFER_CANCEL_ID}/accept" "$ACCEPT_CANCEL_BODY" "$ACCEPT_CANCEL_HEADERS" \
  '{"driver_name":"Smoke Driver 2","car_plate":"SMK-002","eta_seconds":300}' \
  -H "Cookie: ${DRIVER2_COOKIE}" -H 'Idempotency-Key: ride-smoke-accept-driver2-cancel-001')"
assert_http_code "driver2 accept cancel scenario" "$ACCEPT_CANCEL_CODE" 200

LEDGER_CANCEL_RESERVED_BODY="$(mktemp)"
LEDGER_CANCEL_RESERVED_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${DRIVER2_WALLET_ID}/driver-ledger" "$LEDGER_CANCEL_RESERVED_BODY" \
  -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver2 ledger cancel reserved" "$LEDGER_CANCEL_RESERVED_CODE" 200
HELD_AFTER_CANCEL_ACCEPT="$(json_field "$LEDGER_CANCEL_RESERVED_BODY" '.held_reserve_cents // -1')"
[[ "$HELD_AFTER_CANCEL_ACCEPT" == "180" ]] || fail "expected driver2 held_reserve_cents=180 after cancel-scenario accept, got ${HELD_AFTER_CANCEL_ACCEPT}"

CANCEL_BODY="$(mktemp)"
CANCEL_HEADERS="$(mktemp)"
CANCEL_CODE="$(http_post_json "${BASE_URL}/me/rides/trips/${RIDE_CANCEL_ID}/commands" "$CANCEL_BODY" "$CANCEL_HEADERS" \
  '{"command":"cancel_trip","reason":"smoke rider cancel"}' \
  -H "Cookie: ${RIDER_COOKIE}" -H 'Idempotency-Key: ride-smoke-cancel-002')"
assert_http_code "rider cancel trip" "$CANCEL_CODE" 200

LEDGER_CANCEL_RELEASED_BODY="$(mktemp)"
LEDGER_CANCEL_RELEASED_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${DRIVER2_WALLET_ID}/driver-ledger" "$LEDGER_CANCEL_RELEASED_BODY" \
  -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver2 ledger cancel released" "$LEDGER_CANCEL_RELEASED_CODE" 200
HELD_AFTER_CANCEL_RELEASE="$(json_field "$LEDGER_CANCEL_RELEASED_BODY" '.held_reserve_cents // -1')"
[[ "$HELD_AFTER_CANCEL_RELEASE" == "0" ]] || fail "expected driver2 held_reserve_cents=0 after rider cancel, got ${HELD_AFTER_CANCEL_RELEASE}"

RIDER_ACTIVE_AFTER_CANCEL_BODY="$(mktemp)"
RIDER_ACTIVE_AFTER_CANCEL_CODE="$(http_get_json "${BASE_URL}/me/rides/trips/active" "$RIDER_ACTIVE_AFTER_CANCEL_BODY" -H "Cookie: ${RIDER_COOKIE}")"
assert_http_code "rider active after cancel" "$RIDER_ACTIVE_AFTER_CANCEL_CODE" 200
[[ "$(json_field "$RIDER_ACTIVE_AFTER_CANCEL_BODY" '.active')" == "null" ]] || fail "expected rider active to be null after cancel"

DRIVER2_ACTIVE_AFTER_CANCEL_BODY="$(mktemp)"
DRIVER2_ACTIVE_AFTER_CANCEL_CODE="$(http_get_json "${BASE_URL}/me/rides/driver/trips/active" "$DRIVER2_ACTIVE_AFTER_CANCEL_BODY" -H "Cookie: ${DRIVER2_COOKIE}")"
assert_http_code "driver2 active after cancel" "$DRIVER2_ACTIVE_AFTER_CANCEL_CODE" 200
[[ "$(json_field "$DRIVER2_ACTIVE_AFTER_CANCEL_BODY" '.active')" == "null" ]] || fail "expected driver2 active to be null after cancel"

FEE_WALLET_BALANCE_AFTER_CANCEL="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_PAY" -At -c \
  "SELECT w.balance_cents FROM users u JOIN wallets w ON w.user_id = u.id WHERE u.account_id='${FEE_ACCOUNT_ID}' LIMIT 1;")"
[[ "$FEE_WALLET_BALANCE_AFTER_CANCEL" == "$FEE_WALLET_BALANCE" ]] \
  || fail "expected fee wallet balance to stay ${FEE_WALLET_BALANCE} after cancel, got ${FEE_WALLET_BALANCE_AFTER_CANCEL:-<empty>}"

cat <<REPORT
=== Shamell Ride E2E Smoke ===
Base URL: ${BASE_URL}
Logs: ${LOG_DIR}

Accounts:
  rider_shamell_id: ${RIDER_SHAMELL_ID}
  rider_account_id: ${RIDER_ACCOUNT_ID}
  driver_shamell_id: ${DRIVER_SHAMELL_ID}
  driver_account_id: ${DRIVER_ACCOUNT_ID}
  driver2_shamell_id: ${DRIVER2_SHAMELL_ID}
  driver2_account_id: ${DRIVER2_ACCOUNT_ID}

Wallets:
  rider_wallet_id: ${RIDER_WALLET_ID}
  driver_wallet_id: ${DRIVER_WALLET_ID}
  driver2_wallet_id: ${DRIVER2_WALLET_ID}
  fee_wallet_account_id: ${FEE_ACCOUNT_ID}
  fee_wallet_balance_cents: ${FEE_WALLET_BALANCE}

Ride:
  ride_id_main: ${RIDE_ID}
  ride_id_cancel: ${RIDE_CANCEL_ID}
  offer_id_driver1: ${OFFER_ID}
  offer_id_driver2: ${OFFER2_ID}
  offer_id_cancel_driver2: ${OFFER_CANCEL_ID}
  low_balance_accept_http: ${ACCEPT_FAIL_CODE}
  reserve_after_accept_driver1_cents: ${HELD_AFTER_ACCEPT}
  reserve_after_reassign_driver1_cents: ${HELD_AFTER_REASSIGN}
  reserve_after_accept_driver2_cents: ${HELD_DRIVER2_AFTER_ACCEPT}
  reserve_after_complete_cents: ${HELD_AFTER_COMPLETE}
  reserve_after_cancel_accept_cents: ${HELD_AFTER_CANCEL_ACCEPT}
  reserve_after_cancel_release_cents: ${HELD_AFTER_CANCEL_RELEASE}
  live_stage_after_location_ping: ${LIVE_STAGE}
  tracking_kind_after_location_ping: ${LATEST_TRACKING_KIND}
  reassign_response: $(cat "$REASSIGN_BODY")
  cancel_response: $(cat "$CANCEL_BODY")
  fee_wallet_balance_after_cancel_cents: ${FEE_WALLET_BALANCE_AFTER_CANCEL}

Status payloads:
  arriving: $(cat "$ARRIVING_BODY")
  arrived: $(cat "$ARRIVED_BODY")
  started: $(cat "$STARTED_BODY")
  in_progress: $(cat "$IN_PROGRESS_BODY")
  completed: $(cat "$COMPLETED_BODY")
=== End Ride E2E Smoke ===
REPORT
