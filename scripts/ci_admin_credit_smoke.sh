#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_IMAGE="postgres:16-alpine@sha256:97ff59a4e30e08d1c11bdcd9455e7832368c0572b576c9092cde2df4ae5552a3"
TMP_DIR="$(mktemp -d)"
PG_CONTAINER=""
PAYMENTS_PID=""
BFF_PID=""
PAYMENTS_PORT="${CI_PAYMENTS_PORT:-}"
BFF_PORT="${CI_BFF_PORT:-}"
PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-shamell}"
PGPASSWORD="${PGPASSWORD:-shamell}"
BFF_DB=""
PAYMENTS_DB=""
PSQL_MODE=host
LAST_STATUS=""
LAST_BODY_FILE=""
LAST_HEADERS_FILE=""
export PGPASSWORD

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ci-admin-credit-smoke: missing required command: $1" >&2
    exit 1
  }
}

choose_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

psql_admin() {
  if [[ "$PSQL_MODE" == "docker" ]]; then
    docker exec -e "PGPASSWORD=${PGPASSWORD}" "$PG_CONTAINER" \
      psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d postgres "$@"
  else
    psql -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres "$@"
  fi
}

psql_db() {
  local db="$1"
  shift
  if [[ "$PSQL_MODE" == "docker" ]]; then
    docker exec -e "PGPASSWORD=${PGPASSWORD}" "$PG_CONTAINER" \
      psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$db" "$@"
  else
    psql -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" "$@"
  fi
}

psql_scalar() {
  local db="$1"
  local sql="$2"
  psql_db "$db" -Atc "$sql"
}

sql_literal() {
  printf '%s' "$1" | sed "s/'/''/g"
}

host_postgres_tools_available() {
  command -v pg_isready >/dev/null 2>&1 && command -v psql >/dev/null 2>&1
}

wait_for_host_postgres() {
  local attempts=60
  for ((i = 1; i <= attempts; i++)); do
    if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_container_postgres() {
  local attempts=60
  for ((i = 1; i <= attempts; i++)); do
    if docker exec "$PG_CONTAINER" pg_isready -U "$PGUSER" -d postgres >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

ensure_postgres() {
  if host_postgres_tools_available && wait_for_host_postgres; then
    PSQL_MODE=host
    return 0
  fi

  if [[ "${CI_ADMIN_CREDIT_START_POSTGRES:-auto}" == "0" ]]; then
    echo "ci-admin-credit-smoke: postgres unavailable at ${PGHOST}:${PGPORT}" >&2
    exit 1
  fi

  require_cmd docker
  PGPORT="$(choose_port)"
  PG_CONTAINER="shamell-admin-credit-pg-$(openssl rand -hex 4)"
  PSQL_MODE=docker
  echo "ci-admin-credit-smoke: starting temporary postgres on 127.0.0.1:${PGPORT}"
  docker run -d --rm \
    --name "$PG_CONTAINER" \
    -e "POSTGRES_USER=${PGUSER}" \
    -e "POSTGRES_PASSWORD=${PGPASSWORD}" \
    -e POSTGRES_DB=postgres \
    -p "127.0.0.1:${PGPORT}:5432" \
    "$PG_IMAGE" >/dev/null

  if ! wait_for_container_postgres; then
    echo "ci-admin-credit-smoke: temporary postgres did not become ready" >&2
    docker logs "$PG_CONTAINER" >&2 || true
    exit 1
  fi
}

postgres_url() {
  local db="$1"
  printf 'postgresql://%s:%s@%s:%s/%s' "$PGUSER" "$PGPASSWORD" "$PGHOST" "$PGPORT" "$db"
}

create_db() {
  local db="$1"
  psql_admin -c "CREATE DATABASE ${db}" >/dev/null
}

drop_db() {
  local db="$1"
  [[ -n "$db" ]] || return 0
  psql_admin -c "DROP DATABASE IF EXISTS ${db} WITH (FORCE)" >/dev/null 2>&1 || true
}

stop_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local status=$?
  if ((status != 0)); then
    for log_file in "$TMP_DIR"/*.log; do
      [[ -f "$log_file" ]] || continue
      echo "---- ${log_file} (tail) ----" >&2
      tail -n 160 "$log_file" >&2 || true
    done
  fi
  stop_pid "$BFF_PID"
  stop_pid "$PAYMENTS_PID"
  drop_db "$BFF_DB"
  drop_db "$PAYMENTS_DB"
  if [[ -n "$PG_CONTAINER" ]]; then
    docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
  fi
  if [[ "${CI_ADMIN_CREDIT_KEEP_TMP:-0}" == "1" && "$status" != "0" ]]; then
    echo "ci-admin-credit-smoke: kept temp dir ${TMP_DIR}" >&2
  else
    rm -rf "$TMP_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT

wait_for_http() {
  local url="$1"
  local pid="$2"
  local log_file="$3"
  local label="$4"
  local attempts=60
  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS --connect-timeout 2 --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "ci-admin-credit-smoke: ${label} exited while starting" >&2
      tail -n 200 "$log_file" >&2 || true
      exit 1
    fi
    sleep 1
  done
  echo "ci-admin-credit-smoke: ${label} did not become healthy" >&2
  tail -n 200 "$log_file" >&2 || true
  exit 1
}

run_bff_schema_migrate() {
  local log_file="${TMP_DIR}/bff-schema.log"
  (
    export ENV=dev
    DB_URL="$(postgres_url "$BFF_DB")"
    export DB_URL
    exec "${APP_DIR}/target/debug/shamell_bff_auth_schema_migrate"
  ) >"$log_file" 2>&1 || {
    echo "ci-admin-credit-smoke: BFF auth schema migration failed" >&2
    tail -n 200 "$log_file" >&2 || true
    exit 1
  }
}

start_payments() {
  local log_file="${TMP_DIR}/payments.log"
  PAYMENTS_PORT="${PAYMENTS_PORT:-$(choose_port)}"
  (
    export ENV=dev
    export APP_HOST=127.0.0.1
    export APP_PORT="$PAYMENTS_PORT"
    PAYMENTS_DB_URL="$(postgres_url "$PAYMENTS_DB")"
    export PAYMENTS_DB_URL
    export PAYMENTS_AUTO_APPLY_SCHEMA=true
    export PAYMENTS_REQUIRE_INTERNAL_SECRET=false
    export PAYMENTS_REQUIRE_IDEMPOTENCY_KEY=true
    export PAYMENTS_ADMIN_CREDIT_MAX_AMOUNT_CENTS=10000
    export PAYMENTS_ADMIN_CREDIT_OPERATOR_DAILY_LIMIT_CENTS=20000
    export PAYMENTS_ADMIN_CREDIT_APPROVAL_THRESHOLD_CENTS=1000
    export ALLOWED_HOSTS=localhost,127.0.0.1
    export ALLOWED_ORIGINS="http://127.0.0.1:${BFF_PORT:-5173}"
    export RUST_LOG="${RUST_LOG:-warn}"
    exec "${APP_DIR}/target/debug/shamell_payments_service"
  ) >"$log_file" 2>&1 &
  PAYMENTS_PID=$!
  wait_for_http "http://127.0.0.1:${PAYMENTS_PORT}/health" "$PAYMENTS_PID" "$log_file" "payments"
}

start_bff() {
  local log_file="${TMP_DIR}/bff.log"
  BFF_PORT="${BFF_PORT:-$(choose_port)}"
  (
    export ENV=dev
    export APP_HOST=127.0.0.1
    export APP_PORT="$BFF_PORT"
    DB_URL="$(postgres_url "$BFF_DB")"
    export DB_URL
    export PAYMENTS_BASE_URL="http://127.0.0.1:${PAYMENTS_PORT}"
    export CHAT_BASE_URL=http://127.0.0.1:9
    export ALLOWED_HOSTS=localhost,127.0.0.1
    export ALLOWED_ORIGINS="http://127.0.0.1:${BFF_PORT}"
    export AUTH_ACCOUNT_CREATE_POW_ENABLED=false
    export AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=false
    export AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=false
    export AUTH_PAYMENT_MUTATION_HARDWARE_ATTESTATION_ENABLED=false
    export AUTH_BIOMETRIC_ENROLL_HARDWARE_ATTESTATION_ENABLED=false
    export BFF_EXPOSE_UPSTREAM_ERRORS=true
    export RUST_LOG="${RUST_LOG:-warn}"
    exec "${APP_DIR}/target/debug/shamell_bff_gateway"
  ) >"$log_file" 2>&1 &
  BFF_PID=$!
  wait_for_http "http://127.0.0.1:${BFF_PORT}/health" "$BFF_PID" "$log_file" "bff"
}

api_call() {
  local method="$1"
  local path="$2"
  local cookie="${3:-}"
  local body="${4:-}"
  local idempotency_key="${5:-}"
  LAST_BODY_FILE="${TMP_DIR}/body-$(openssl rand -hex 4).json"
  LAST_HEADERS_FILE="${TMP_DIR}/headers-$(openssl rand -hex 4).txt"
  local -a args=(
    -sS
    --connect-timeout 5
    --max-time 20
    -D "$LAST_HEADERS_FILE"
    -o "$LAST_BODY_FILE"
    -w "%{http_code}"
    -X "$method"
    -H "accept: application/json"
    -H "user-agent: shamell-admin-credit-ci"
  )
  if [[ -n "$cookie" ]]; then
    args+=(-H "Cookie: ${cookie}")
  fi
  if [[ -n "$idempotency_key" ]]; then
    args+=(-H "Idempotency-Key: ${idempotency_key}")
  fi
  if [[ -n "$body" ]]; then
    args+=(-H "content-type: application/json" --data-binary "$body")
  fi
  LAST_STATUS="$(curl "${args[@]}" "http://127.0.0.1:${BFF_PORT}${path}")"
}

assert_status() {
  local label="$1"
  shift
  local expected
  for expected in "$@"; do
    if [[ "$LAST_STATUS" == "$expected" ]]; then
      return 0
    fi
  done
  echo "ci-admin-credit-smoke: ${label} failed (HTTP=${LAST_STATUS}, expected=$*)" >&2
  cat "$LAST_BODY_FILE" >&2 || true
  exit 1
}

extract_session_cookie() {
  local headers_file="$1"
  awk '
    BEGIN { IGNORECASE = 1 }
    /^set-cookie:/ {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /__Host-sa_session=/) {
        sub(/^set-cookie:[[:space:]]*/, "", line)
        sub(/;.*/, "", line)
        print line
        exit
      }
    }
  ' "$headers_file"
}

signup_user() {
  local prefix="$1"
  local suffix username password device_id shamell_id cookie account_id shamell_sql
  suffix="$(openssl rand -hex 5)"
  username="ci${prefix}${suffix}"
  password="Ci-${prefix}-${suffix}-A1"
  device_id="ci-${prefix}-${suffix}"
  api_call POST /auth/signup "" "{\"username\":\"${username}\",\"password\":\"${password}\",\"device_id\":\"${device_id}\"}"
  assert_status "signup_${prefix}" 200
  shamell_id="$(jq -r '.shamell_id // empty' "$LAST_BODY_FILE")"
  cookie="$(extract_session_cookie "$LAST_HEADERS_FILE")"
  if [[ -z "$shamell_id" || -z "$cookie" ]]; then
    echo "ci-admin-credit-smoke: signup_${prefix} missing shamell_id or session cookie" >&2
    cat "$LAST_BODY_FILE" >&2 || true
    exit 1
  fi
  shamell_sql="$(sql_literal "$shamell_id")"
  account_id="$(psql_scalar "$BFF_DB" "SELECT account_id FROM auth_accounts WHERE shamell_user_id='${shamell_sql}' LIMIT 1")"
  if [[ -z "$account_id" ]]; then
    echo "ci-admin-credit-smoke: signup_${prefix} missing account row" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\n' "$account_id" "$shamell_id" "$cookie"
}

grant_finance_role() {
  local account_id="$1"
  local account_sql
  account_sql="$(sql_literal "$account_id")"
  psql_db "$BFF_DB" -c "
WITH inserted AS (
  INSERT INTO auth_role_assignments (subject_account_id, role_id, created_by_account_id, metadata)
  VALUES ('${account_sql}', 'platform.finance_admin', '${account_sql}', '{\"source\":\"ci_admin_credit_smoke\"}'::jsonb)
  RETURNING id
)
INSERT INTO auth_scope_assignments (role_assignment_id, scope_kind, scope_value)
SELECT id, 'platform', NULL FROM inserted;
" >/dev/null
}

assert_json_value() {
  local label="$1"
  local jq_filter="$2"
  local expected="$3"
  local actual
  actual="$(jq -r "$jq_filter" "$LAST_BODY_FILE")"
  if [[ "$actual" != "$expected" ]]; then
    echo "ci-admin-credit-smoke: ${label} expected ${expected}, got ${actual}" >&2
    cat "$LAST_BODY_FILE" >&2 || true
    exit 1
  fi
}

require_cmd cargo
require_cmd curl
require_cmd jq
require_cmd openssl
require_cmd python3

ensure_postgres

RUN_SUFFIX="$(openssl rand -hex 5)"
BFF_DB="shamell_admin_credit_bff_${RUN_SUFFIX}"
PAYMENTS_DB="shamell_admin_credit_pay_${RUN_SUFFIX}"
create_db "$BFF_DB"
create_db "$PAYMENTS_DB"

BFF_PORT="${BFF_PORT:-$(choose_port)}"
PAYMENTS_PORT="${PAYMENTS_PORT:-$(choose_port)}"

echo "ci-admin-credit-smoke: building payments and bff binaries"
cargo build --manifest-path "${APP_DIR}/services_rs/payments_service/Cargo.toml" --bins
cargo build --manifest-path "${APP_DIR}/services_rs/bff_gateway/Cargo.toml" --bins

run_bff_schema_migrate
start_payments
start_bff

IFS=$'\t' read -r operator_account_id _operator_shamell_id operator_cookie < <(signup_user operator)
grant_finance_role "$operator_account_id"
IFS=$'\t' read -r approver_account_id _approver_shamell_id approver_cookie < <(signup_user approver)
grant_finance_role "$approver_account_id"
IFS=$'\t' read -r _target_account_id target_shamell_id target_cookie < <(signup_user target)

low_body="$(jq -cn --arg shamell_id "$target_shamell_id" '{shamell_id:$shamell_id,amount_cents:500,reason:"ci_smoke_low"}')"
low_idem="ci-low-$(openssl rand -hex 6)"
api_call POST /payments/admin/credits "$operator_cookie" "$low_body" "$low_idem"
assert_status "low_credit" 200
assert_json_value "low_credit_status" '.status' credited
assert_json_value "low_credit_balance" '.balance_cents|tostring' 500
wallet_id="$(jq -r '.wallet_id // empty' "$LAST_BODY_FILE")"
low_txn_id="$(jq -r '.txn_id // empty' "$LAST_BODY_FILE")"
if [[ -z "$wallet_id" || -z "$low_txn_id" ]]; then
  echo "ci-admin-credit-smoke: low_credit missing wallet_id or txn_id" >&2
  cat "$LAST_BODY_FILE" >&2 || true
  exit 1
fi

api_call POST /payments/admin/credits "$operator_cookie" "$low_body" "$low_idem"
assert_status "low_credit_replay" 200
assert_json_value "low_credit_replay_status" '.status' credited
assert_json_value "low_credit_replay_txn" '.txn_id' "$low_txn_id"
assert_json_value "low_credit_replay_balance" '.balance_cents|tostring' 500

high_body="$(jq -cn --arg wallet_id "$wallet_id" '{wallet_id:$wallet_id,amount_cents:1500,reason:"ci_smoke_high_requires_approval",note:"approval path"}')"
high_idem="ci-high-$(openssl rand -hex 6)"
api_call POST /payments/admin/credits "$operator_cookie" "$high_body" "$high_idem"
assert_status "high_credit_pending" 200
assert_json_value "high_credit_pending_status" '.status' pending_approval
approval_request_id="$(jq -r '.approval_request_id // empty' "$LAST_BODY_FILE")"
if [[ -z "$approval_request_id" ]]; then
  echo "ci-admin-credit-smoke: high_credit_pending missing approval_request_id" >&2
  cat "$LAST_BODY_FILE" >&2 || true
  exit 1
fi

api_call POST "/payments/admin/credits/${approval_request_id}/approve" "$operator_cookie" "{}" "ci-approve-self-$(openssl rand -hex 6)"
assert_status "self_approval_forbidden" 409

approve_idem="ci-approve-$(openssl rand -hex 6)"
api_call POST "/payments/admin/credits/${approval_request_id}/approve" "$approver_cookie" "{}" "$approve_idem"
assert_status "approval" 200
assert_json_value "approval_status" '.status' credited
assert_json_value "approval_balance" '.balance_cents|tostring' 2000
assert_json_value "approval_approver" '.approved_by_account_id' "$approver_account_id"
approval_txn_id="$(jq -r '.txn_id // empty' "$LAST_BODY_FILE")"
if [[ -z "$approval_txn_id" ]]; then
  echo "ci-admin-credit-smoke: approval missing txn_id" >&2
  cat "$LAST_BODY_FILE" >&2 || true
  exit 1
fi

api_call POST "/payments/admin/credits/${approval_request_id}/approve" "$approver_cookie" "{}" "$approve_idem"
assert_status "approval_replay" 200
assert_json_value "approval_replay_status" '.status' credited
assert_json_value "approval_replay_txn" '.txn_id' "$approval_txn_id"

api_call GET "/payments/admin/credits?limit=5" "$operator_cookie"
assert_status "admin_credit_history" 200
history_count="$(jq -r '.items | length' "$LAST_BODY_FILE")"
if ((history_count < 2)); then
  echo "ci-admin-credit-smoke: history expected at least 2 items, got ${history_count}" >&2
  cat "$LAST_BODY_FILE" >&2 || true
  exit 1
fi
assert_json_value "history_credited_count" '.metrics.credited_count|tostring' 2

api_call GET /payments/admin/credits/metrics "$operator_cookie"
assert_status "admin_credit_metrics" 200
assert_json_value "metrics_credited_count" '.credited_count|tostring' 2
assert_json_value "metrics_pending_count" '.pending_approval_count|tostring' 0

api_call GET /payments/admin/credits/reconciliation "$operator_cookie"
assert_status "admin_credit_reconciliation" 200
assert_json_value "reconciliation_status" '.status' balanced

api_call POST /payments/admin/credits "$target_cookie" "$low_body" "ci-forbidden-$(openssl rand -hex 6)"
assert_status "unprivileged_admin_credit_forbidden" 403

echo "ci-admin-credit-smoke: ok"
