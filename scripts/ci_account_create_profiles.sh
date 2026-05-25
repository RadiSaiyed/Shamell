#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_IMAGE="postgres:16-alpine@sha256:97ff59a4e30e08d1c11bdcd9455e7832368c0572b576c9092cde2df4ae5552a3"
PG_CONTAINER="shamell-ci-pg-${RANDOM}${RANDOM}"
PG_PORT="${CI_PG_PORT:-}"
BFF_PORT="${CI_BFF_PORT:-}"
TMP_DIR="$(mktemp -d)"
BFF_PID=""

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

port_is_listening() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

claim_or_choose_tcp_port() {
  local requested_port="$1"
  local label="$2"
  local port=""
  if [[ -n "$requested_port" ]]; then
    if port_is_listening "$requested_port"; then
      echo "${label} port ${requested_port} is already in use." >&2
      return 1
    fi
    printf '%s\n' "$requested_port"
    return 0
  fi

  for ((i = 1; i <= 200; i++)); do
    port="$((20000 + RANDOM % 20000))"
    if [[ -n "$PG_PORT" && "$label" == "bff" && "$port" == "$PG_PORT" ]]; then
      continue
    fi
    if ! port_is_listening "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
  done

  echo "Could not find a free ${label} TCP port." >&2
  return 1
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

generate_internal_identity_pair() {
  local key_file text priv_hex pub_hex priv_b64 pub_b64
  key_file="${TMP_DIR}/internal-identity-${RANDOM}${RANDOM}.pem"
  openssl genpkey -algorithm ED25519 -out "$key_file" >/dev/null 2>&1
  text="$(openssl pkey -in "$key_file" -text -noout)"
  priv_hex="$(
    printf '%s\n' "$text" |
      awk '
        /^priv:$/ {capture=1; next}
        /^pub:$/ {capture=0}
        capture {print}
      ' |
      tr -d '[:space:]:'
  )"
  pub_hex="$(
    printf '%s\n' "$text" |
      awk '/^pub:$/ {capture=1; next} capture {print}' |
      tr -d '[:space:]:'
  )"
  priv_b64="$(printf '%s' "$priv_hex" | xxd -r -p | base64 | tr -d '\n')"
  pub_b64="$(printf '%s' "$pub_hex" | xxd -r -p | base64 | tr -d '\n')"
  printf '%s %s\n' "$priv_b64" "$pub_b64"
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

run_bff_schema_migrate() {
  local env_file="$1"
  local log_file="$2"
  (
    set -a
    source "$env_file"
    set +a
    exec "${APP_DIR}/target/debug/shamell_bff_auth_schema_migrate"
  ) >"$log_file" 2>&1
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

smoke_signup_policy() {
  local profile="$1"
  local expected_status="$2"
  local body_file username password device_id status
  body_file="${TMP_DIR}/signup-${profile}.json"
  username="ci${profile}$(openssl rand -hex 6)"
  password="CiProfile-${profile}-A1-$(openssl rand -hex 6)"
  device_id="ci-${profile}-device-$(openssl rand -hex 6)"
  status="$(
    curl -sS \
      --connect-timeout 5 \
      --max-time 12 \
      -X POST \
      -H "content-type: application/json" \
      -d "{\"username\":\"${username}\",\"password\":\"${password}\",\"device_id\":\"${device_id}\"}" \
      -o "$body_file" \
      -w "%{http_code}" \
      "http://127.0.0.1:${BFF_PORT}/auth/signup"
  )"
  if [[ "$status" != "$expected_status" ]]; then
    echo "==> ${profile}: signup policy failed (HTTP=${status}, expected=${expected_status})" >&2
    cat "$body_file" >&2 || true
    return 1
  fi
  echo "==> ${profile}: signup policy HTTP=${status}"
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
  set_env "$file" BFF_TRUSTED_PROXY_CIDRS "127.0.0.1/32,::1/128"
  set_env "$file" ALLOWED_HOSTS "localhost,127.0.0.1"
  set_env "$file" ALLOWED_ORIGINS "https://127.0.0.1:${BFF_PORT}"
  set_env "$file" CHAT_BASE_URL "http://127.0.0.1:19081"
  set_env "$file" PAYMENTS_BASE_URL "http://127.0.0.1:19082"

  # Strong non-placeholder secrets expected by check_env.
  local internal_identity_seed_b64 internal_identity_pub_b64
  local security_alert_seed_b64 security_alert_pub_b64
  local access_assignment_admin_seed_b64 access_assignment_admin_pub_b64
  local access_assignment_sync_seed_b64 access_assignment_sync_pub_b64
  local apple_p8_file apple_p8_b64
  local google_key_file google_json_file google_json_b64 google_private_key_escaped
  read -r internal_identity_seed_b64 internal_identity_pub_b64 < <(generate_internal_identity_pair)
  read -r security_alert_seed_b64 security_alert_pub_b64 < <(generate_internal_identity_pair)
  read -r access_assignment_admin_seed_b64 access_assignment_admin_pub_b64 < <(generate_internal_identity_pair)
  read -r access_assignment_sync_seed_b64 access_assignment_sync_pub_b64 < <(generate_internal_identity_pair)
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

  set_env "$file" INTERNAL_API_SECRET "$(random_secret)"
  set_env "$file" BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS "security-reporter=${security_alert_pub_b64}"
  set_env "$file" BFF_SECURITY_ALERT_INTERNAL_IDENTITY_MAX_SKEW_SECS "30"
  set_env "$file" BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2 "true"
  set_env "$file" BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK "false"
  set_env "$file" BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS "control-automation,iam-sync"
  set_env "$file" BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS "control-automation=${access_assignment_admin_pub_b64},iam-sync=${access_assignment_sync_pub_b64}"
  set_env "$file" BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_MAX_SKEW_SECS "30"
  set_env "$file" BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2 "true"
  set_env "$file" BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK "false"
  set_env "$file" BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64 "$internal_identity_seed_b64"
  set_env "$file" ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID "control-automation"
  set_env "$file" ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64 "$access_assignment_admin_seed_b64"
  set_env "$file" ACCESS_ASSIGNMENT_ADMIN_AUDIENCE "bff"
  set_env "$file" PAYMENTS_INTERNAL_SECRET ""
  set_env "$file" CHAT_INTERNAL_SECRET ""
  set_env "$file" PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS "bff=${internal_identity_pub_b64}"
  set_env "$file" PAYMENTS_INTERNAL_IDENTITY_MAX_SKEW_SECS "30"
  set_env "$file" PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2 "true"
  set_env "$file" PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK "false"
  set_env "$file" CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS "bff=${internal_identity_pub_b64}"
  set_env "$file" CHAT_INTERNAL_IDENTITY_MAX_SKEW_SECS "30"
  set_env "$file" CHAT_REQUIRE_INTERNAL_IDENTITY_V2 "true"
  set_env "$file" CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK "false"
  set_env "$file" BFF_ROLE_HEADER_SECRET "$(random_secret)"
  set_env "$file" AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET "$(random_secret)"
  set_env "$file" AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS "https://127.0.0.1:${BFF_PORT}"
  set_env "$file" SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64 "$security_alert_seed_b64"
  set_env "$file" AUTH_ACCOUNT_CREATE_POW_SECRET "$(random_secret)"
  set_env "$file" AUTH_PAYMENT_MUTATION_HARDWARE_ATTESTATION_ENABLED "true"
  set_env "$file" LIVEKIT_API_KEY "lk_$(openssl rand -hex 12)"
  set_env "$file" LIVEKIT_API_SECRET "$(random_secret)"
  set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID "AB12CD34EF"
  set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID "ZX98YX76WV"
  set_env "$file" AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 "$apple_p8_b64"
  set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 "$google_json_b64"
  set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES "online.shamell.app,online.shamell.app.operator,online.shamell.app.admin"

  if [[ "$mode" == "strict" ]]; then
    set_env "$file" AUTH_ACCOUNT_CREATE_ENABLED "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED "false"
  else
    set_env "$file" AUTH_ACCOUNT_CREATE_ENABLED "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION "false"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED "true"
    set_env "$file" AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED "false"
  fi

  rm -f "${file}.bak"
}

run_profile() {
  local profile="$1"
  local env_file="$2"
  local expect_disabled="$3"
  local log_file="${TMP_DIR}/bff-${profile}.log"
  local migrate_log_file="${TMP_DIR}/bff-schema-migrate-${profile}.log"

  echo "==> ${profile}: pipg check"
  ENV_FILE="$env_file" "${APP_DIR}/scripts/ops.sh" pipg check

  echo "==> ${profile}: schema-migrate bff"
  if ! run_bff_schema_migrate "$env_file" "$migrate_log_file"; then
    echo "==> ${profile}: schema-migrate failed; migrator log tail" >&2
    tail -n 200 "$migrate_log_file" >&2 || true
    return 1
  fi

  echo "==> ${profile}: start bff"
  start_bff "$env_file" "$log_file"

  echo "==> ${profile}: smoke-api"
  if ! ENV_FILE="$env_file" \
    SMOKE_BASE_URL="http://127.0.0.1:${BFF_PORT}" \
    SMOKE_CLIENT_IP="203.0.113.10" \
    "${APP_DIR}/scripts/ops.sh" pipg smoke-api; then
    echo "==> ${profile}: smoke-api failed; bff log tail" >&2
    tail -n 200 "$log_file" >&2 || true
    return 1
  fi

  local expected_signup_status
  expected_signup_status="200"
  if [[ "$expect_disabled" == "1" ]]; then
    expected_signup_status="503"
  fi
  smoke_signup_policy "$profile" "$expected_signup_status"

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
  require_cmd lsof
  require_cmd openssl
  require_cmd perl
  require_cmd sed
  require_cmd base64
  require_cmd xxd

  PG_PORT="$(claim_or_choose_tcp_port "${CI_PG_PORT:-}" "postgres")"
  BFF_PORT="$(claim_or_choose_tcp_port "${CI_BFF_PORT:-}" "bff")"

  echo "==> build bff binary"
  (
    cd "$APP_DIR"
    cargo build \
      -p shamell_bff_gateway \
      --bin shamell_bff_gateway \
      --bin shamell_bff_auth_schema_migrate
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
