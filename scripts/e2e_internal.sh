#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_PORT="${BASE_PORT:-19480}"
E2E_PG_HOST="${E2E_PG_HOST:-127.0.0.1}"
E2E_PG_PORT="${E2E_PG_PORT:-5432}"
E2E_PG_USER="${E2E_PG_USER:-shamell}"
E2E_PG_PASSWORD="${E2E_PG_PASSWORD:-shamell}"
DB_CORE="${E2E_DB_CORE:-shamell_core}"
DB_CHAT="${E2E_DB_CHAT:-shamell_chat}"
DB_PAYMENTS="${E2E_DB_PAYMENTS:-shamell_payments}"
WITH_FRONTEND=0
SKIP_BUILD=0
KEEP_RUNNING=0
RESET_DB=1

usage() {
  cat <<'USAGE'
Usage: scripts/e2e_internal.sh [options]

Runs an internal end-to-end smoke across backend, database, and (optionally) Flutter frontend.

Options:
  --base-port <port>   Base port for local services (default: 19480)
  --with-frontend      Also run flutter analyze + flutter test
  --skip-build         Skip cargo build before starting services
  --no-reset-db        Keep existing DB contents (default: reset DBs)
  --keep-running       Do not stop started services on exit
  -h, --help           Show this help

Environment:
  E2E_PG_HOST          Postgres host (default: 127.0.0.1)
  E2E_PG_PORT          Postgres port (default: 5432)
  E2E_PG_USER          Postgres admin/user role (default: shamell)
  E2E_PG_PASSWORD      Postgres password (default: shamell)
  E2E_DB_CORE          Core DB name (default: shamell_core)
  E2E_DB_CHAT          Chat DB name (default: shamell_chat)
  E2E_DB_PAYMENTS      Payments DB name (default: shamell_payments)
USAGE
}

log() {
  printf '[e2e] %s\n' "$*"
}

fail() {
  printf '[e2e][error] %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-port)
      [[ $# -ge 2 ]] || fail "--base-port requires a value"
      BASE_PORT="$2"
      shift 2
      ;;
    --with-frontend)
      WITH_FRONTEND=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --no-reset-db)
      RESET_DB=0
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
PG_ISREADY="$(resolve_pg_bin pg_isready)" || fail "unable to locate pg_isready binary"

require_cmd curl
require_cmd jq
require_cmd openssl
export PGPASSWORD="$E2E_PG_PASSWORD"

PORT_BFF="$BASE_PORT"
PORT_CHAT="$((BASE_PORT + 1))"
PORT_PAY="$((BASE_PORT + 2))"
BASE_URL="http://127.0.0.1:${PORT_BFF}"

LOG_DIR="/tmp/shamell-e2e-run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

PID_CHAT=""
PID_PAY=""
PID_BFF=""

cleanup() {
  if [[ "$KEEP_RUNNING" == "1" ]]; then
    log "keeping services running (requested)"
    return 0
  fi
  local pid
  for pid in "$PID_CHAT" "$PID_PAY" "$PID_BFF"; do
    if [[ -n "${pid:-}" ]] && ps -p "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 0.2
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

start_service() {
  local log_file="$1"
  shift

  if [[ "$KEEP_RUNNING" == "1" ]]; then
    nohup "$@" >"$log_file" 2>&1 &
  else
    "$@" >"$log_file" 2>&1 &
  fi

  printf '%s\n' "$!"
}

wait_health() {
  local name="$1"
  local url="$2"
  local _ignored
  for _ignored in $(seq 1 60); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      log "health ${name}: ok"
      return 0
    fi
    sleep 0.5
  done
  log "health ${name}: failed"
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
  curl -sS -o "$out" -D "$headers_out" -w '%{http_code}' "$@" \
    -H 'Content-Type: application/json' -d "$body" "$url"
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

recreate_db() {
  local db="$1"
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db}' AND pid <> pg_backend_pid();" >/dev/null
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d postgres -c "DROP DATABASE IF EXISTS ${db};" >/dev/null
  "$CREATEDB" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -O shamell "$db"
  "$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$db" -c "GRANT ALL PRIVILEGES ON DATABASE ${db} TO shamell;" >/dev/null
}

if [[ "$SKIP_BUILD" == "0" ]]; then
  log "building backend binaries"
  (
    cd "$ROOT_DIR"
    cargo build -p shamell_chat_service -p shamell_payments_service -p shamell_bff_gateway
  )
fi

log "validating postgres availability"
ensure_pg_ready
ensure_role

if [[ "$RESET_DB" == "1" ]]; then
  log "resetting shamell databases"
  recreate_db "$DB_CORE"
  recreate_db "$DB_CHAT"
  recreate_db "$DB_PAYMENTS"
fi

log "starting services (logs: $LOG_DIR)"
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
    PAYMENTS_DB_URL="postgresql://shamell:${E2E_PG_PASSWORD}@${E2E_PG_HOST}:${E2E_PG_PORT}/${DB_PAYMENTS}" \
    PAYMENTS_REQUIRE_INTERNAL_SECRET=false PAYMENTS_ALLOW_DIRECT_TOPUP=true MERCHANT_FEE_BPS=0 \
    RUST_LOG=info \
    "$ROOT_DIR/target/debug/shamell_payments_service")"

PID_BFF="$(start_service "$LOG_DIR/bff.log" \
  env \
    ENV=dev APP_HOST=127.0.0.1 APP_PORT="$PORT_BFF" \
    DB_URL="postgresql://shamell:${E2E_PG_PASSWORD}@${E2E_PG_HOST}:${E2E_PG_PORT}/${DB_CORE}" \
    CHAT_BASE_URL="http://127.0.0.1:${PORT_CHAT}" \
    PAYMENTS_BASE_URL="http://127.0.0.1:${PORT_PAY}" \
    BFF_REQUIRE_INTERNAL_SECRET=false BFF_ENFORCE_ROUTE_AUTHZ=false \
    AUTH_ACCOUNT_CREATE_ENABLED=true AUTH_ACCOUNT_CREATE_POW_ENABLED=false \
    AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=false \
    AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=false \
    RUST_LOG=info \
    "$ROOT_DIR/target/debug/shamell_bff_gateway")"

echo "$PID_CHAT" >"$LOG_DIR/chat.pid"
echo "$PID_PAY" >"$LOG_DIR/payments.pid"
echo "$PID_BFF" >"$LOG_DIR/bff.pid"

PID_CHAT="$(cat "$LOG_DIR/chat.pid")"
PID_PAY="$(cat "$LOG_DIR/payments.pid")"
PID_BFF="$(cat "$LOG_DIR/bff.pid")"

wait_health chat "http://127.0.0.1:${PORT_CHAT}/health"
wait_health payments "http://127.0.0.1:${PORT_PAY}/health"
wait_health bff "${BASE_URL}/health"

suffix="$(openssl rand -hex 2)"
DEVICE_A="deva${suffix}"
DEVICE_B="devb${suffix}"
USERNAME_A="e2ea${suffix}"
USERNAME_B="e2eb${suffix}"
PASSWORD_A="SmokePass-${suffix}-A1"
PASSWORD_B="SmokePass-${suffix}-B1"

log "creating account A"
BODY_A="$(mktemp)"
HEAD_A="$(mktemp)"
CODE_A="$(http_post_json "${BASE_URL}/auth/signup" "$BODY_A" "$HEAD_A" "{\"username\":\"${USERNAME_A}\",\"password\":\"${PASSWORD_A}\",\"device_id\":\"${DEVICE_A}\"}")"
[[ "$CODE_A" == "200" ]] || fail "account A create failed (code=$CODE_A): $(cat "$BODY_A")"
SHID_A="$(jq -r '.shamell_id // empty' "$BODY_A")"
SID_A="$(extract_session_cookie "$HEAD_A")"
[[ -n "$SHID_A" && -n "$SID_A" ]] || fail "account A missing shamell_id/session"
COOKIE_A="__Host-sa_session=${SID_A}"

log "creating account B"
BODY_B="$(mktemp)"
HEAD_B="$(mktemp)"
CODE_B="$(http_post_json "${BASE_URL}/auth/signup" "$BODY_B" "$HEAD_B" "{\"username\":\"${USERNAME_B}\",\"password\":\"${PASSWORD_B}\",\"device_id\":\"${DEVICE_B}\"}")"
[[ "$CODE_B" == "200" ]] || fail "account B create failed (code=$CODE_B): $(cat "$BODY_B")"
SHID_B="$(jq -r '.shamell_id // empty' "$BODY_B")"
SID_B="$(extract_session_cookie "$HEAD_B")"
[[ -n "$SHID_B" && -n "$SID_B" ]] || fail "account B missing shamell_id/session"
COOKIE_B="__Host-sa_session=${SID_B}"

log "registering chat devices"
REG_A_OUT="$(mktemp)"
REG_A_H="$(mktemp)"
REG_A_CODE="$(http_post_json "${BASE_URL}/chat/devices/register" "$REG_A_OUT" "$REG_A_H" \
  "{\"device_id\":\"${DEVICE_A}\",\"public_key_b64\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"name\":\"Account A Device\"}" \
  -H "Cookie: ${COOKIE_A}")"
[[ "$REG_A_CODE" == "200" ]] || fail "chat register A failed (code=$REG_A_CODE): $(cat "$REG_A_OUT")"

REG_B_OUT="$(mktemp)"
REG_B_H="$(mktemp)"
REG_B_CODE="$(http_post_json "${BASE_URL}/chat/devices/register" "$REG_B_OUT" "$REG_B_H" \
  "{\"device_id\":\"${DEVICE_B}\",\"public_key_b64\":\"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\",\"name\":\"Account B Device\"}" \
  -H "Cookie: ${COOKIE_B}")"
[[ "$REG_B_CODE" == "200" ]] || fail "chat register B failed (code=$REG_B_CODE): $(cat "$REG_B_OUT")"

log "creating + redeeming contact invite"
INV_OUT="$(mktemp)"
INV_H="$(mktemp)"
INV_CODE="$(http_post_json "${BASE_URL}/contacts/invites" "$INV_OUT" "$INV_H" '{"max_uses":1}' -H "Cookie: ${COOKIE_A}")"
[[ "$INV_CODE" == "200" ]] || fail "invite create failed (code=$INV_CODE): $(cat "$INV_OUT")"
INV_TOKEN="$(jq -r '.token // empty' "$INV_OUT")"
[[ -n "$INV_TOKEN" ]] || fail "invite token missing"

RED_OUT="$(mktemp)"
RED_H="$(mktemp)"
RED_CODE="$(http_post_json "${BASE_URL}/contacts/invites/redeem" "$RED_OUT" "$RED_H" \
  "{\"token\":\"${INV_TOKEN}\"}" \
  -H "Cookie: ${COOKIE_B}" -H "x-chat-device-id: ${DEVICE_B}")"
[[ "$RED_CODE" == "200" ]] || fail "invite redeem failed (code=$RED_CODE): $(cat "$RED_OUT")"

log "sending direct chat message A -> B"
SEND_OUT="$(mktemp)"
SEND_H="$(mktemp)"
SEND_PAYLOAD="{\"sender_id\":\"${DEVICE_A}\",\"recipient_id\":\"${DEVICE_B}\",\"protocol_version\":\"2\",\"sender_pubkey_b64\":\"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC\",\"nonce_b64\":\"DDDDDDDDDDDDDDDD\",\"box_b64\":\"EEEEEEEEEEEEEEEE\",\"sealed_sender\":true,\"sender_hint\":\"hintA123\"}"
SEND_CODE="$(http_post_json "${BASE_URL}/chat/messages/send" "$SEND_OUT" "$SEND_H" "$SEND_PAYLOAD" -H "Cookie: ${COOKIE_A}")"
[[ "$SEND_CODE" == "200" ]] || fail "chat send failed (code=$SEND_CODE): $(cat "$SEND_OUT")"

INBOX_OUT="$(mktemp)"
INBOX_CODE="$(http_get_json "${BASE_URL}/chat/messages/inbox?device_id=${DEVICE_B}&limit=20" "$INBOX_OUT" -H "Cookie: ${COOKIE_B}")"
[[ "$INBOX_CODE" == "200" ]] || fail "chat inbox failed (code=$INBOX_CODE): $(cat "$INBOX_OUT")"
INBOX_COUNT="$(jq 'length' "$INBOX_OUT")"
[[ "$INBOX_COUNT" -ge 1 ]] || fail "chat inbox is empty"

log "creating payments users + topup + transfer"
PAY_A_OUT="$(mktemp)"
PAY_A_H="$(mktemp)"
PAY_A_CODE="$(http_post_json "${BASE_URL}/payments/users" "$PAY_A_OUT" "$PAY_A_H" '{}' \
  -H "Cookie: ${COOKIE_A}" -H "x-device-id: ${DEVICE_A}")"
[[ "$PAY_A_CODE" == "200" ]] || fail "payments user A failed (code=$PAY_A_CODE): $(cat "$PAY_A_OUT")"
WALLET_A="$(jq -r '.wallet_id // empty' "$PAY_A_OUT")"
[[ -n "$WALLET_A" ]] || fail "wallet A missing"

PAY_B_OUT="$(mktemp)"
PAY_B_H="$(mktemp)"
PAY_B_CODE="$(http_post_json "${BASE_URL}/payments/users" "$PAY_B_OUT" "$PAY_B_H" '{}' \
  -H "Cookie: ${COOKIE_B}" -H "x-device-id: ${DEVICE_B}")"
[[ "$PAY_B_CODE" == "200" ]] || fail "payments user B failed (code=$PAY_B_CODE): $(cat "$PAY_B_OUT")"
WALLET_B="$(jq -r '.wallet_id // empty' "$PAY_B_OUT")"
[[ -n "$WALLET_B" ]] || fail "wallet B missing"

TOPUP_OUT="$(mktemp)"
TOPUP_H="$(mktemp)"
TOPUP_CODE="$(http_post_json "${BASE_URL}/payments/wallets/${WALLET_A}/topup" "$TOPUP_OUT" "$TOPUP_H" \
  '{"amount_cents":5000}' \
  -H "Cookie: ${COOKIE_A}" -H "x-device-id: ${DEVICE_A}" -H 'Idempotency-Key: topup-a-001')"
[[ "$TOPUP_CODE" == "200" ]] || fail "topup failed (code=$TOPUP_CODE): $(cat "$TOPUP_OUT")"

XFER_OUT="$(mktemp)"
XFER_H="$(mktemp)"
XFER_PAYLOAD="{\"to_wallet_id\":\"${WALLET_B}\",\"amount_cents\":1200}"
XFER_CODE="$(http_post_json "${BASE_URL}/payments/transfer" "$XFER_OUT" "$XFER_H" "$XFER_PAYLOAD" \
  -H "Cookie: ${COOKIE_A}" -H "x-device-id: ${DEVICE_A}" -H 'Idempotency-Key: xfer-a-to-b-001')"
[[ "$XFER_CODE" == "200" ]] || fail "transfer failed (code=$XFER_CODE): $(cat "$XFER_OUT")"

WSNAP_A="$(mktemp)"
WSNAP_B="$(mktemp)"
WSNAP_A_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${WALLET_A}/snapshot?limit=20" "$WSNAP_A" \
  -H "Cookie: ${COOKIE_A}" -H "x-device-id: ${DEVICE_A}")"
WSNAP_B_CODE="$(http_get_json "${BASE_URL}/payments/wallets/${WALLET_B}/snapshot?limit=20" "$WSNAP_B" \
  -H "Cookie: ${COOKIE_B}" -H "x-device-id: ${DEVICE_B}")"
[[ "$WSNAP_A_CODE" == "200" ]] || fail "wallet A snapshot failed"
[[ "$WSNAP_B_CODE" == "200" ]] || fail "wallet B snapshot failed"

log "collecting database summaries"
CORE_SUM="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_CORE" -At -F '|' -c \
  "SELECT (SELECT COUNT(*) FROM auth_accounts), (SELECT COUNT(*) FROM auth_sessions), (SELECT COUNT(*) FROM auth_chat_devices), (SELECT COUNT(*) FROM auth_contact_invites), (SELECT COUNT(*) FROM auth_chat_contacts);")"
CHAT_SUM="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_CHAT" -At -F '|' -c \
  "SELECT (SELECT COUNT(*) FROM devices), (SELECT COUNT(*) FROM messages);")"
CHAT_LAST="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_CHAT" -At -F '|' -c \
  "SELECT sender_id, recipient_id, COALESCE(sealed_sender::text,'') FROM messages ORDER BY created_at DESC LIMIT 1;")"
PAY_SUM="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_PAYMENTS" -At -F '|' -c \
  "SELECT (SELECT COUNT(*) FROM users), (SELECT COUNT(*) FROM wallets), (SELECT COUNT(*) FROM txns), (SELECT COUNT(*) FROM idempotency);")"
PAY_WALLETS="$("$PSQL" -h "$E2E_PG_HOST" -p "$E2E_PG_PORT" -U "$E2E_PG_USER" -d "$DB_PAYMENTS" -At -F '|' -c \
  "SELECT id || ':' || balance_cents FROM wallets ORDER BY id;")"

if [[ "$WITH_FRONTEND" == "1" ]]; then
  log "running frontend checks (flutter analyze + flutter test)"
  (
    cd "$ROOT_DIR/clients/shamell_flutter"
    flutter pub get
    flutter analyze
    flutter test
  )
fi

cat <<REPORT
=== Shamell Internal E2E Report ===
Base URL: $BASE_URL
Logs: $LOG_DIR

Accounts:
  A shamell_id: $SHID_A
  B shamell_id: $SHID_B

Wallets:
  A wallet_id: $WALLET_A
  B wallet_id: $WALLET_B

API checks:
  auth_signup(A/B): 200/200
  chat_inbox_count(B): $INBOX_COUNT
  payments_topup(A): 200
  payments_transfer(A->B): 200

DB summaries:
  core (accounts|sessions|chat_devices|invites|contacts): $CORE_SUM
  chat (devices|messages): $CHAT_SUM
  chat last (sender|recipient|sealed): $CHAT_LAST
  payments (users|wallets|txns|idempotency): $PAY_SUM
  payments wallet balances:
$PAY_WALLETS

Sample payloads:
  account A create: $(cat "$BODY_A")
  account B create: $(cat "$BODY_B")
  chat send: $(cat "$SEND_OUT")
  transfer: $(cat "$XFER_OUT")
=== End Report ===
REPORT
