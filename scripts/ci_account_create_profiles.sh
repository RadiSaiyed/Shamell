#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_IMAGE="postgres:16-alpine@sha256:97ff59a4e30e08d1c11bdcd9455e7832368c0572b576c9092cde2df4ae5552a3"
PG_CONTAINER="shamell-ci-pg-${RANDOM}${RANDOM}"
PG_PORT="${CI_PG_PORT:-55432}"
BFF_PORT="${CI_BFF_PORT:-18080}"
TMP_DIR="$(mktemp -d)"
BFF_PID=""

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

b64_file() {
  local file="$1"
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w0 "$file"
  else
    base64 <"$file" | tr -d '\n'
  fi
}

random_secret() {
  openssl rand -hex 24
}

set_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -Eq "^${key}=" "$file"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

wait_for_postgres() {
  local attempts=60
  for ((i = 1; i <= attempts; i++)); do
    if docker exec "$PG_CONTAINER" pg_isready -U shamell -d shamell_core >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Postgres did not become ready in time." >&2
  docker logs "$PG_CONTAINER" || true
  return 1
}

stop_bff() {
  if [[ -n "$BFF_PID" ]] && kill -0 "$BFF_PID" >/dev/null 2>&1; then
    kill "$BFF_PID" >/dev/null 2>&1 || true
    wait "$BFF_PID" >/dev/null 2>&1 || true
  fi
  BFF_PID=""
}

start_bff() {
  local env_file="$1"
  local log_file="$2"
  stop_bff
  (
    set -a
    source "$env_file"
    set +a
    exec "${APP_DIR}/target/debug/shamell_bff_gateway"
  ) >"$log_file" 2>&1 &
  BFF_PID=$!

  local attempts=60
  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS "http://127.0.0.1:${BFF_PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$BFF_PID" >/dev/null 2>&1; then
      echo "BFF exited early while starting." >&2
      tail -n 200 "$log_file" || true
      return 1
    fi
    sleep 1
  done

  echo "BFF did not become healthy in time." >&2
  tail -n 200 "$log_file" || true
  return 1
}

build_env_file() {
  local mode="$1"
  local file="$2"
  local db_password="$3"

  cp "${APP_DIR}/ops/pi/env.prod.example" "$file"

  # Core runtime wiring for local CI smoke.
  set_env "$file" ENV "prod"
  set_env "$file" APP_HOST "127.0.0.1"
  set_env "$file" APP_PORT "${BFF_PORT}"
  set_env "$file" POSTGRES_USER "shamell"
  set_env "$file" POSTGRES_PASSWORD "${db_password}"
  set_env "$file" DB_URL "postgresql://shamell:${db_password}@127.0.0.1:${PG_PORT}/shamell_core"
  set_env "$file" CHAT_DB_URL "postgresql://shamell:${db_password}@127.0.0.1:${PG_PORT}/shamell_chat"
  set_env "$file" PAYMENTS_DB_URL "postgresql://shamell:${db_password}@127.0.0.1:${PG_PORT}/shamell_payments"
  set_env "$file" BUS_DB_URL "postgresql://shamell:${db_password}@127.0.0.1:${PG_PORT}/shamell_bus"
  set_env "$file" ALLOWED_HOSTS "localhost,127.0.0.1"
  set_env "$file" ALLOWED_ORIGINS "http://127.0.0.1:${BFF_PORT}"
  set_env "$file" CHAT_BASE_URL "http://127.0.0.1:19081"
  set_env "$file" PAYMENTS_BASE_URL "http://127.0.0.1:19082"
  set_env "$file" BUS_BASE_URL "http://127.0.0.1:19083"

  # Strong non-placeholder secrets expected by check_env.
  set_env "$file" INTERNAL_API_SECRET "$(random_secret)"
  set_env "$file" PAYMENTS_INTERNAL_SECRET "$(random_secret)"
  set_env "$file" BUS_PAYMENTS_INTERNAL_SECRET "$(random_secret)"
  set_env "$file" CHAT_INTERNAL_SECRET "$(random_secret)"
  set_env "$file" BUS_INTERNAL_SECRET "$(random_secret)"
  set_env "$file" BUS_TICKET_SECRET "$(random_secret)"
  set_env "$file" BFF_ROLE_HEADER_SECRET "$(random_secret)"
  set_env "$file" AUTH_ACCOUNT_CREATE_POW_SECRET "$(random_secret)"
  set_env "$file" LIVEKIT_API_KEY "lk_$(openssl rand -hex 12)"
  set_env "$file" LIVEKIT_API_SECRET "$(random_secret)"

  if [[ "$mode" == "strict" ]]; then
    local apple_p8_file apple_p8_b64 google_key_file google_json_file google_json_b64 google_private_key_escaped
    apple_p8_file="${TMP_DIR}/apple-${mode}.p8"
    google_key_file="${TMP_DIR}/google-${mode}.pem"
    google_json_file="${TMP_DIR}/google-${mode}.json"

    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$apple_p8_file" >/dev/null 2>&1
    apple_p8_b64="$(b64_file "$apple_p8_file")"

    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$google_key_file" >/dev/null 2>&1
    google_private_key_escaped="$(perl -0777 -pe 's/\n/\\n/g' "$google_key_file")"
    printf '{"type":"service_account","client_email":"ci-play-integrity@shamell-ci.iam.gserviceaccount.com","private_key":"%s","token_uri":"https://oauth2.googleapis.com/token"}' \
      "$google_private_key_escaped" >"$google_json_file"
    google_json_b64="$(b64_file "$google_json_file")"

    set_env "$file" AUTH_ACCOUNT_CREATE_ENABLED "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID "SHAMELLCI01"
    set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID "SHAMELLK01"
    set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 "$apple_p8_b64"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 "$google_json_b64"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES "online.shamell.app,online.shamell.app.operator,online.shamell.app.admin"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED "false"
  else
    set_env "$file" AUTH_ACCOUNT_CREATE_ENABLED "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID ""
    set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID ""
    set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 ""
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 ""
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES ""
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED "false"
  fi

  rm -f "${file}.bak"
}

run_profile() {
  local profile="$1"
  local env_file="$2"
  local expect_disabled="$3"
  local log_file="${TMP_DIR}/bff-${profile}.log"

  echo "==> ${profile}: pipg check"
  ENV_FILE="$env_file" "${APP_DIR}/scripts/ops.sh" pipg check

  echo "==> ${profile}: start bff"
  start_bff "$env_file" "$log_file"

  echo "==> ${profile}: smoke-api"
  if ! ENV_FILE="$env_file" \
    SMOKE_BASE_URL="http://127.0.0.1:${BFF_PORT}" \
    SMOKE_CLIENT_IP="127.0.0.1" \
    SMOKE_EXPECT_ACCOUNT_CREATE_DISABLED="$expect_disabled" \
    "${APP_DIR}/scripts/ops.sh" pipg smoke-api; then
    echo "==> ${profile}: smoke-api failed; bff log tail" >&2
    tail -n 200 "$log_file" >&2 || true
    return 1
  fi

  stop_bff
}

cleanup() {
  stop_bff
  docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR" || true
}
trap cleanup EXIT

main() {
  require_cmd cargo
  require_cmd curl
  require_cmd docker
  require_cmd openssl
  require_cmd perl
  require_cmd sed
  require_cmd base64

  echo "==> build bff binary"
  (
    cd "$APP_DIR"
    cargo build -p shamell_bff_gateway
  )

  local db_password strict_env interim_env
  db_password="$(random_secret)"
  strict_env="${TMP_DIR}/env.strict"
  interim_env="${TMP_DIR}/env.interim"

  build_env_file strict "$strict_env" "$db_password"
  build_env_file interim "$interim_env" "$db_password"

  echo "==> start postgres"
  docker run -d --rm \
    --name "$PG_CONTAINER" \
    -e POSTGRES_USER="shamell" \
    -e POSTGRES_PASSWORD="$db_password" \
    -e POSTGRES_DB="shamell_core" \
    -p "127.0.0.1:${PG_PORT}:5432" \
    "$PG_IMAGE" >/dev/null
  wait_for_postgres

  run_profile strict "$strict_env" 0
  run_profile interim "$interim_env" 1

  echo "Account-create profile checks passed (strict + interim)."
}

main "$@"
