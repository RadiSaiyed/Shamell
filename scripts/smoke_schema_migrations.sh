#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_IMAGE="${SCHEMA_MIGRATION_PG_IMAGE:-postgres:16-alpine@sha256:97ff59a4e30e08d1c11bdcd9455e7832368c0572b576c9092cde2df4ae5552a3}"
DOCKER_CONTAINER_NAME="shamell-schema-smoke-${RANDOM}-${RANDOM}"

CHAT_DB_NAME="${CHAT_MIGRATION_SMOKE_DB:-shamell_chat_smoke}"
PAYMENTS_DB_NAME="${PAYMENTS_MIGRATION_SMOKE_DB:-shamell_payments_smoke}"
BFF_DB_NAME="${BFF_MIGRATION_SMOKE_DB:-shamell_core_smoke}"
BFF_EMPTY_DB_NAME="${BFF_MIGRATION_EMPTY_DB:-shamell_core_empty_smoke}"
CHAT_SCHEMA_NAME="${CHAT_MIGRATION_SMOKE_SCHEMA:-chat_smoke}"
PAYMENTS_SCHEMA_NAME="${PAYMENTS_MIGRATION_SMOKE_SCHEMA:-payments_smoke}"
CHAT_EMPTY_SCHEMA_NAME="${CHAT_MIGRATION_EMPTY_SCHEMA:-chat_empty_control}"
PAYMENTS_EMPTY_SCHEMA_NAME="${PAYMENTS_MIGRATION_EMPTY_SCHEMA:-payments_empty_control}"

BACKEND=""
PG_PORT=""
PG_HOST="127.0.0.1"
PG_USER="shamell"
PG_PASSWORD="shamell"
PG_TMP_DIR=""
RUNTIME_LOG_DIR=""
BFF_SERVICE_PID=""
CHAT_SERVICE_PID=""
PAYMENTS_SERVICE_PID=""

INITDB_BIN=""
PG_CTL_BIN=""
PSQL_BIN=""
CREATEDB_BIN=""
PG_ISREADY_BIN=""

log() {
  printf '[schema-smoke] %s\n' "$*"
}

fail() {
  printf '[schema-smoke][error] %s\n' "$*" >&2
  exit 1
}

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

cleanup() {
  if [[ -n "$BFF_SERVICE_PID" ]] && kill -0 "$BFF_SERVICE_PID" >/dev/null 2>&1; then
    kill "$BFF_SERVICE_PID" >/dev/null 2>&1 || true
    wait "$BFF_SERVICE_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$CHAT_SERVICE_PID" ]] && kill -0 "$CHAT_SERVICE_PID" >/dev/null 2>&1; then
    kill "$CHAT_SERVICE_PID" >/dev/null 2>&1 || true
    wait "$CHAT_SERVICE_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$PAYMENTS_SERVICE_PID" ]] && kill -0 "$PAYMENTS_SERVICE_PID" >/dev/null 2>&1; then
    kill "$PAYMENTS_SERVICE_PID" >/dev/null 2>&1 || true
    wait "$PAYMENTS_SERVICE_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$BACKEND" == "docker" ]]; then
    docker rm -f "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  if [[ "$BACKEND" == "local" && -n "$PG_TMP_DIR" ]]; then
    "$PG_CTL_BIN" -D "$PG_TMP_DIR" stop -m immediate >/dev/null 2>&1 || true
    rm -rf "$PG_TMP_DIR"
  fi
  if [[ -n "$RUNTIME_LOG_DIR" ]]; then
    rm -rf "$RUNTIME_LOG_DIR"
  fi
}
trap cleanup EXIT

expected_versions() {
  local dir="$1"
  local path
  local -a versions=()
  shopt -s nullglob
  for path in "$dir"/*.sql; do
    versions+=("$(basename "${path%.sql}")")
  done
  shopt -u nullglob
  (( ${#versions[@]} > 0 )) || fail "no migrations found in ${dir#$ROOT_DIR/}"
  printf '%s\n' "${versions[@]}" | sort
}

docker_daemon_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

pick_free_port() {
  require_cmd lsof
  local candidate
  local attempt
  for attempt in $(seq 1 50); do
    candidate="$((20000 + RANDOM % 20000))"
    if ! lsof -iTCP:"$candidate" -sTCP:LISTEN >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  fail "unable to find free local TCP port for temporary postgres"
}

wait_for_http_ok() {
  local name="$1"
  local url="$2"
  local pid="$3"
  local log_file="$4"
  local attempt
  for attempt in $(seq 1 60); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      log "${name} health ok"
      return 0
    fi
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      printf '[schema-smoke][error] %s exited before health check succeeded\n' "$name" >&2
      if [[ -f "$log_file" ]]; then
        tail -n 120 "$log_file" >&2 || true
      fi
      exit 1
    fi
    sleep 0.5
  done
  printf '[schema-smoke][error] %s health check timed out\n' "$name" >&2
  if [[ -f "$log_file" ]]; then
    tail -n 120 "$log_file" >&2 || true
  fi
  exit 1
}

wait_for_process_failure() {
  local name="$1"
  local pid="$2"
  local log_file="$3"
  local attempt
  local status
  for attempt in $(seq 1 40); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      set +e
      wait "$pid"
      status=$?
      set -e
      if [[ "$status" -eq 0 ]]; then
        printf '[schema-smoke][error] %s exited successfully but failure was expected\n' "$name" >&2
        if [[ -f "$log_file" ]]; then
          tail -n 120 "$log_file" >&2 || true
        fi
        exit 1
      fi
      log "${name} failed closed as expected"
      return 0
    fi
    sleep 0.5
  done

  printf '[schema-smoke][error] %s kept running against an uninitialized schema\n' "$name" >&2
  if [[ -f "$log_file" ]]; then
    tail -n 120 "$log_file" >&2 || true
  fi
  exit 1
}

wait_for_postgres_local() {
  local attempt
  for attempt in $(seq 1 60); do
    if "$PG_ISREADY_BIN" -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d postgres >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "local postgres cluster did not become ready"
}

wait_for_postgres_docker() {
  local attempt
  for attempt in $(seq 1 60); do
    if docker exec "$DOCKER_CONTAINER_NAME" pg_isready -U "$PG_USER" -d postgres >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "docker postgres did not become ready"
}

start_docker_postgres() {
  require_cmd docker
  BACKEND="docker"
  log "starting postgres smoke container"
  docker run \
    --name "$DOCKER_CONTAINER_NAME" \
    -e POSTGRES_USER="$PG_USER" \
    -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRES_DB=postgres \
    -p 127.0.0.1::5432 \
    -d \
    "$PG_IMAGE" >/dev/null
  wait_for_postgres_docker
  PG_PORT="$(docker port "$DOCKER_CONTAINER_NAME" 5432/tcp | awk -F: 'END {print $NF}')"
  [[ -n "$PG_PORT" ]] || fail "failed to resolve docker postgres port"
  log "postgres ready via docker on ${PG_HOST}:${PG_PORT}"
}

start_local_postgres() {
  INITDB_BIN="$(resolve_pg_bin initdb)" || fail "initdb not found for local postgres fallback"
  PG_CTL_BIN="$(resolve_pg_bin pg_ctl)" || fail "pg_ctl not found for local postgres fallback"
  PSQL_BIN="$(resolve_pg_bin psql)" || fail "psql not found for local postgres fallback"
  CREATEDB_BIN="$(resolve_pg_bin createdb)" || fail "createdb not found for local postgres fallback"
  PG_ISREADY_BIN="$(resolve_pg_bin pg_isready)" || fail "pg_isready not found for local postgres fallback"

  BACKEND="local"
  PG_PORT="$(pick_free_port)"
  PG_TMP_DIR="$(mktemp -d /tmp/shamell-schema-smoke-pg-XXXXXX)"
  log "starting temporary local postgres cluster on ${PG_HOST}:${PG_PORT}"

  "$INITDB_BIN" -D "$PG_TMP_DIR" -U "$PG_USER" --auth=trust >/dev/null
  "$PG_CTL_BIN" \
    -D "$PG_TMP_DIR" \
    -l "$PG_TMP_DIR/postgres.log" \
    -o "-c listen_addresses=${PG_HOST} -p ${PG_PORT}" \
    start >/dev/null
  wait_for_postgres_local
}

psql_exec() {
  local db="$1"
  local sql="$2"
  if [[ "$BACKEND" == "docker" ]]; then
    docker exec "$DOCKER_CONTAINER_NAME" \
      psql -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$db" -At -c "$sql"
    return 0
  fi

  PGPASSWORD="$PG_PASSWORD" \
    "$PSQL_BIN" \
    -v ON_ERROR_STOP=1 \
    -h "$PG_HOST" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    -d "$db" \
    -At \
    -c "$sql"
}

create_db() {
  local db="$1"
  if [[ "$BACKEND" == "docker" ]]; then
    psql_exec postgres "CREATE DATABASE ${db};" >/dev/null
    return 0
  fi

  PGPASSWORD="$PG_PASSWORD" \
    "$CREATEDB_BIN" \
    -h "$PG_HOST" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    "$db"
}

drop_schema_if_exists() {
  local db="$1"
  local schema="$2"
  psql_exec "$db" "DROP SCHEMA IF EXISTS ${schema} CASCADE;" >/dev/null
}

assert_ledger_matches() {
  local db="$1"
  local schema="$2"
  local ledger="$3"
  local expected="$4"
  local actual
  actual="$(psql_exec "$db" "SELECT version FROM ${schema}.${ledger} ORDER BY version;")"
  if [[ "$actual" != "$expected" ]]; then
    printf '[schema-smoke][error] migration ledger mismatch for %s.%s.%s\n' "$db" "$schema" "$ledger" >&2
    printf '[schema-smoke][error] expected:\n%s\n' "$expected" >&2
    printf '[schema-smoke][error] actual:\n%s\n' "$actual" >&2
    exit 1
  fi

  local invalid_checksums
  invalid_checksums="$(
    psql_exec \
      "$db" \
      "SELECT COUNT(*) FROM ${schema}.${ledger} WHERE checksum !~ '^[0-9a-f]{64}$';"
  )"
  [[ "$invalid_checksums" == "0" ]] || fail "invalid checksums in ${db}.${schema}.${ledger}"

  local row_count
  row_count="$(psql_exec "$db" "SELECT COUNT(*) FROM ${schema}.${ledger};")"
  local expected_count
  expected_count="$(printf '%s\n' "$expected" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$row_count" == "$expected_count" ]] || fail "unexpected migration row count for ${db}.${schema}"
}

run_bff_migrator() {
  (
    cd "$ROOT_DIR"
    ENV=dev \
    DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${BFF_DB_NAME}" \
    cargo run --quiet -p shamell_bff_gateway --bin shamell_bff_auth_schema_migrate
  )
}

run_chat_migrator() {
  (
    cd "$ROOT_DIR"
    ENV=dev \
    APP_HOST=127.0.0.1 \
    APP_PORT=18081 \
    CHAT_DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${CHAT_DB_NAME}" \
    DB_SCHEMA="$CHAT_SCHEMA_NAME" \
    cargo run --quiet -p shamell_chat_service --bin shamell_chat_schema_migrate
  )
}

run_payments_migrator() {
  (
    cd "$ROOT_DIR"
    ENV=dev \
    APP_HOST=127.0.0.1 \
    APP_PORT=18082 \
    PAYMENTS_DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PAYMENTS_DB_NAME}" \
    DB_SCHEMA="$PAYMENTS_SCHEMA_NAME" \
    cargo run --quiet -p shamell_payments_service --bin shamell_payments_schema_migrate
  )
}

build_runtime_binaries() {
  log "building bff, chat and payments service binaries"
  (
    cd "$ROOT_DIR"
    cargo build --quiet \
      -p shamell_bff_gateway \
      -p shamell_chat_service \
      -p shamell_payments_service \
      --bin shamell_bff_gateway \
      --bin shamell_chat_service \
      --bin shamell_payments_service
  )
}

start_bff_runtime() {
  local port="$1"
  local log_file="$RUNTIME_LOG_DIR/bff-runtime.log"
  log "starting bff service with AUTH_AUTO_APPLY_SCHEMA=false"
  (
    cd "$ROOT_DIR"
    ENV=dev \
    SHAMELL_DEPLOYMENT_PROFILE=root-dev \
    APP_HOST=127.0.0.1 \
    APP_PORT="$port" \
    DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${BFF_DB_NAME}" \
    AUTH_AUTO_APPLY_SCHEMA=false \
    BFF_REQUIRE_INTERNAL_SECRET=false \
    BFF_ENFORCE_ROUTE_AUTHZ=false \
    AUTH_DEVICE_LOGIN_WEB_ENABLED=false \
    RUST_LOG=info \
    exec target/debug/shamell_bff_gateway >"$log_file" 2>&1
  ) &
  BFF_SERVICE_PID="$!"
  wait_for_http_ok "bff" "http://127.0.0.1:${port}/health" "$BFF_SERVICE_PID" "$log_file"
  kill "$BFF_SERVICE_PID" >/dev/null 2>&1 || true
  wait "$BFF_SERVICE_PID" >/dev/null 2>&1 || true
  BFF_SERVICE_PID=""
}

start_chat_runtime() {
  local port="$1"
  local log_file="$RUNTIME_LOG_DIR/chat-runtime.log"
  log "starting chat service with CHAT_AUTO_APPLY_SCHEMA=false"
  (
    cd "$ROOT_DIR"
    ENV=dev \
    APP_HOST=127.0.0.1 \
    APP_PORT="$port" \
    CHAT_DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${CHAT_DB_NAME}" \
    DB_SCHEMA="$CHAT_SCHEMA_NAME" \
    CHAT_AUTO_APPLY_SCHEMA=false \
    CHAT_REQUIRE_INTERNAL_SECRET=false \
    RUST_LOG=info \
    exec target/debug/shamell_chat_service >"$log_file" 2>&1
  ) &
  CHAT_SERVICE_PID="$!"
  wait_for_http_ok "chat" "http://127.0.0.1:${port}/health" "$CHAT_SERVICE_PID" "$log_file"
  kill "$CHAT_SERVICE_PID" >/dev/null 2>&1 || true
  wait "$CHAT_SERVICE_PID" >/dev/null 2>&1 || true
  CHAT_SERVICE_PID=""
}

start_payments_runtime() {
  local port="$1"
  local log_file="$RUNTIME_LOG_DIR/payments-runtime.log"
  log "starting payments service with PAYMENTS_AUTO_APPLY_SCHEMA=false"
  (
    cd "$ROOT_DIR"
    ENV=dev \
    APP_HOST=127.0.0.1 \
    APP_PORT="$port" \
    PAYMENTS_DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PAYMENTS_DB_NAME}" \
    DB_SCHEMA="$PAYMENTS_SCHEMA_NAME" \
    PAYMENTS_AUTO_APPLY_SCHEMA=false \
    PAYMENTS_AUTO_PROVISION_FEE_WALLET=false \
    PAYMENTS_REQUIRE_INTERNAL_SECRET=false \
    PAYMENTS_ALLOW_DIRECT_TOPUP=true \
    MERCHANT_FEE_BPS=0 \
    RUST_LOG=info \
    exec target/debug/shamell_payments_service >"$log_file" 2>&1
  ) &
  PAYMENTS_SERVICE_PID="$!"
  wait_for_http_ok "payments" "http://127.0.0.1:${port}/health" "$PAYMENTS_SERVICE_PID" "$log_file"
  kill "$PAYMENTS_SERVICE_PID" >/dev/null 2>&1 || true
  wait "$PAYMENTS_SERVICE_PID" >/dev/null 2>&1 || true
  PAYMENTS_SERVICE_PID=""
}

start_bff_runtime_expect_failure() {
  local port="$1"
  local log_file="$RUNTIME_LOG_DIR/bff-runtime-fail.log"
  log "starting bff service on empty control database with AUTH_AUTO_APPLY_SCHEMA=false"
  (
    cd "$ROOT_DIR"
    ENV=dev \
    SHAMELL_DEPLOYMENT_PROFILE=root-dev \
    APP_HOST=127.0.0.1 \
    APP_PORT="$port" \
    DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${BFF_EMPTY_DB_NAME}" \
    AUTH_AUTO_APPLY_SCHEMA=false \
    BFF_REQUIRE_INTERNAL_SECRET=false \
    BFF_ENFORCE_ROUTE_AUTHZ=false \
    AUTH_DEVICE_LOGIN_WEB_ENABLED=false \
    RUST_LOG=info \
    exec target/debug/shamell_bff_gateway >"$log_file" 2>&1
  ) &
  BFF_SERVICE_PID="$!"
  wait_for_process_failure "bff empty-db startup" "$BFF_SERVICE_PID" "$log_file"
  BFF_SERVICE_PID=""
}

start_chat_runtime_expect_failure() {
  local port="$1"
  local log_file="$RUNTIME_LOG_DIR/chat-runtime-fail.log"
  log "starting chat service on empty control schema with CHAT_AUTO_APPLY_SCHEMA=false"
  (
    cd "$ROOT_DIR"
    ENV=dev \
    APP_HOST=127.0.0.1 \
    APP_PORT="$port" \
    CHAT_DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${CHAT_DB_NAME}" \
    DB_SCHEMA="$CHAT_EMPTY_SCHEMA_NAME" \
    CHAT_AUTO_APPLY_SCHEMA=false \
    CHAT_REQUIRE_INTERNAL_SECRET=false \
    RUST_LOG=info \
    exec target/debug/shamell_chat_service >"$log_file" 2>&1
  ) &
  CHAT_SERVICE_PID="$!"
  wait_for_process_failure "chat empty-schema startup" "$CHAT_SERVICE_PID" "$log_file"
  CHAT_SERVICE_PID=""
}

start_payments_runtime_expect_failure() {
  local port="$1"
  local log_file="$RUNTIME_LOG_DIR/payments-runtime-fail.log"
  log "starting payments service on empty control schema with PAYMENTS_AUTO_APPLY_SCHEMA=false"
  (
    cd "$ROOT_DIR"
    ENV=dev \
    APP_HOST=127.0.0.1 \
    APP_PORT="$port" \
    PAYMENTS_DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PAYMENTS_DB_NAME}" \
    DB_SCHEMA="$PAYMENTS_EMPTY_SCHEMA_NAME" \
    PAYMENTS_AUTO_APPLY_SCHEMA=false \
    PAYMENTS_AUTO_PROVISION_FEE_WALLET=false \
    PAYMENTS_REQUIRE_INTERNAL_SECRET=false \
    PAYMENTS_ALLOW_DIRECT_TOPUP=true \
    MERCHANT_FEE_BPS=0 \
    RUST_LOG=info \
    exec target/debug/shamell_payments_service >"$log_file" 2>&1
  ) &
  PAYMENTS_SERVICE_PID="$!"
  wait_for_process_failure "payments empty-schema startup" "$PAYMENTS_SERVICE_PID" "$log_file"
  PAYMENTS_SERVICE_PID=""
}

require_cmd cargo
require_cmd curl
require_cmd sed
require_cmd sort
require_cmd wc

if docker_daemon_available; then
  start_docker_postgres
else
  log "docker daemon unavailable, falling back to temporary local postgres cluster"
  start_local_postgres
fi

log "creating smoke databases"
create_db "$BFF_DB_NAME"
create_db "$BFF_EMPTY_DB_NAME"
create_db "$CHAT_DB_NAME"
create_db "$PAYMENTS_DB_NAME"

BFF_EXPECTED="$(expected_versions "$ROOT_DIR/services_rs/bff_gateway/migrations")"
CHAT_EXPECTED="$(expected_versions "$ROOT_DIR/services_rs/chat_service/migrations")"
PAYMENTS_EXPECTED="$(expected_versions "$ROOT_DIR/services_rs/payments_service/migrations")"
RUNTIME_LOG_DIR="$(mktemp -d /tmp/shamell-schema-runtime-XXXXXX)"

log "running bff auth schema migrator on empty database"
run_bff_migrator
log "rerunning bff auth schema migrator to verify idempotence"
run_bff_migrator
assert_ledger_matches "$BFF_DB_NAME" "public" "__auth_schema_migrations" "$BFF_EXPECTED"

log "running chat schema migrator on empty database"
run_chat_migrator
log "rerunning chat schema migrator to verify idempotence"
run_chat_migrator
assert_ledger_matches "$CHAT_DB_NAME" "$CHAT_SCHEMA_NAME" "__schema_migrations" "$CHAT_EXPECTED"

log "running payments schema migrator on empty database"
run_payments_migrator
log "rerunning payments schema migrator to verify idempotence"
run_payments_migrator
assert_ledger_matches "$PAYMENTS_DB_NAME" "$PAYMENTS_SCHEMA_NAME" "__schema_migrations" "$PAYMENTS_EXPECTED"

build_runtime_binaries
start_bff_runtime "$(pick_free_port)"
start_chat_runtime "$(pick_free_port)"
start_payments_runtime "$(pick_free_port)"
drop_schema_if_exists "$CHAT_DB_NAME" "$CHAT_EMPTY_SCHEMA_NAME"
drop_schema_if_exists "$PAYMENTS_DB_NAME" "$PAYMENTS_EMPTY_SCHEMA_NAME"
start_bff_runtime_expect_failure "$(pick_free_port)"
start_chat_runtime_expect_failure "$(pick_free_port)"
start_payments_runtime_expect_failure "$(pick_free_port)"

log "schema migration smoke passed"
