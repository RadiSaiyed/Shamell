#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/ops.sh <env> <command> [args]

env:
  dev    local Rust microservices stack (docker-compose.yml)
  pi     Hetzner stack (alias of pipg)
  pipg   Hetzner stack with Postgres (ops/pi/docker-compose.postgres.yml)
  prod   alias of pipg

commands:
  up            build and start
  down          stop and remove
  restart       restart services
  logs          tail logs (pass service names or flags)
  ps            show status
  report        status + health + disk + backups
  smoke-api     run public-vs-internal auth boundary smoke (read-only)
  smoke-mailbox run mailbox transport smoke (non-dev; staging-safe by default)
  security-report  summarize recent BFF security events and alert on thresholds
  security-drill   send synthetic webhook drill payload
  build         build images
  pull          pull images
  health        call /health
  check         validate env file (non-dev)
  deploy        check + up + health (non-dev)
  migrate       no-op (kept for compatibility)
  backup        backup postgres databases
  restore       restore postgres databases
  shell         shell into primary app container

Environment variables:
  ENV_FILE      override env file for non-dev (default: ops/pi/.env)
  BACKUP_DIR    backup destination (default: backups/)
  BACKUP_KEEP   keep last N backups per type (0 disables pruning)
  CONFIRM_RESTORE=1  allow destructive restore
  RESTORE_DROP_SCHEMA=1  drop public schema before restore
  ALLOW_RUNNING_RESTORE=1 allow restore while services are running
  HEALTH_URL    override health URL
  HEALTH_HOST   optional Host header for health check
  HEALTH_RESOLVE optional curl --resolve (host:port:addr)
  HEALTH_INSECURE=1 allow insecure TLS for health check
  HEALTH_RETRIES  retry health check N times (default: 1)
  HEALTH_RETRY_DELAY  seconds between retries (default: 2)
  SMOKE_BASE_URL override smoke base URL (defaults to HEALTH_URL without /health)
  SMOKE_INSECURE=1 allow insecure TLS for smoke requests (defaults to HEALTH_INSECURE)
  SMOKE_HOST    optional Host header for smoke requests (defaults to HEALTH_HOST)
  SMOKE_RESOLVE optional curl --resolve for smoke requests (defaults to HEALTH_RESOLVE)
  SMOKE_CLIENT_IP optional X-Shamell-Client-IP header for auth-path smoke checks
  SKIP_HEALTH_CHECK=1 skip health check
  DEPLOY_FORCE_SEQUENTIAL_BUILD=1 skip fast compose up --build path for up/deploy
  DEPLOY_SEQUENTIAL_BUILD_SERVICES service list for fallback builds (default: bff chat payments bus)
  DEPLOY_BUILD_RETRIES retry count per sequential service build (default: 3)
  DEPLOY_BUILD_RETRY_DELAY_SECS seconds between sequential build retries (default: 8)
  SECURITY_ALERT_WINDOW_SECS  security-report lookback window (default: 300)
  SECURITY_ALERT_COOLDOWN_SECS security-report webhook cooldown (default: 600)
  SECURITY_ALERT_THRESHOLDS comma-separated threshold rules
  SECURITY_ALERT_WEBHOOK_URL optional webhook target for security-report alerts
  SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET optional X-Internal-Secret override for webhook posts
  SECURITY_ALERT_WEBHOOK_SERVICE_ID optional X-Internal-Service-Id for webhook posts
  SECURITY_ALERT_SERVICE docker service name to scan (default: bff)
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

ENV_NAME="${1:-}"
CMD="${2:-}"
if [[ -z "$ENV_NAME" || -z "$CMD" ]]; then
  usage
  exit 1
fi
shift 2

case "$ENV_NAME" in
  dev)
    COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
    DEFAULT_ENV_FILE=""
    HEALTH_URL_DEFAULT="http://localhost:8080/health"
    PRIMARY_SERVICE="bff"
    ;;
  pi|pipg|pi-pg|pi-postgres|prod)
    COMPOSE_FILE="${APP_DIR}/ops/pi/docker-compose.postgres.yml"
    DEFAULT_ENV_FILE="${APP_DIR}/ops/pi/.env"
    HEALTH_URL_DEFAULT="http://localhost:8080/health"
    PRIMARY_SERVICE="bff"
    ;;
  *)
    usage
    exit 1
    ;;
esac

ENV_FILE_PATH="${ENV_FILE:-$DEFAULT_ENV_FILE}"
if [[ -n "$ENV_FILE_PATH" && ! -f "$ENV_FILE_PATH" ]]; then
  echo "Env file not found: ${ENV_FILE_PATH}" >&2
  exit 1
fi

compose() {
  require_cmd docker
  if [[ -n "$ENV_FILE_PATH" ]]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE_PATH" "$@"
  else
    docker compose -f "$COMPOSE_FILE" "$@"
  fi
}

read_env() {
  local key="$1"
  if [[ -z "$ENV_FILE_PATH" || ! -f "$ENV_FILE_PATH" ]]; then
    return 0
  fi
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE_PATH" | tail -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf "%s" "$line"
}

env_file_has_pattern() {
  local pattern="$1"
  if [[ -z "$ENV_FILE_PATH" || ! -f "$ENV_FILE_PATH" ]]; then
    return 1
  fi
  grep -Eq "$pattern" "$ENV_FILE_PATH"
}

is_false_like() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "0" || "$v" == "false" || "$v" == "off" || "$v" == "no" ]]
}

is_true_like() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "on" || "$v" == "yes" ]]
}

is_placeholder_like() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  [[ -z "$v" || "$v" == change-me* || "$v" == *changeme* || "$v" == *replace-me* || "$v" == *replace_me* || "$v" == *please-rotate* || "$v" == *todo* || "$v" == "<set>" || "$v" == "set-me" || "$v" == "setme" ]]
}

check_env() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "dev env: no env-file checks."
    return 0
  fi

  local missing=0
  local required=(
    POSTGRES_USER
    POSTGRES_PASSWORD
    DB_URL
    CHAT_DB_URL
    PAYMENTS_DB_URL
    BUS_DB_URL
    INTERNAL_API_SECRET
    PAYMENTS_INTERNAL_SECRET
    BUS_PAYMENTS_INTERNAL_SECRET
    BUS_INTERNAL_SECRET
    BUS_TICKET_SECRET
    BFF_ROLE_HEADER_SECRET
    ALLOWED_HOSTS
    ALLOWED_ORIGINS
  )

  local key val
  for key in "${required[@]}"; do
    val="$(read_env "$key")"
    if is_placeholder_like "$val"; then
      echo "Missing or invalid ${key} in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
  done

  for key in DB_URL CHAT_DB_URL PAYMENTS_DB_URL BUS_DB_URL; do
    val="$(read_env "$key")"
    local norm
    norm="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$norm" || ( "$norm" != postgres* && "$norm" != postgresql* ) ]]; then
      echo "${key} must be a postgres URL in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
  done

  local origins hosts
  origins="$(read_env ALLOWED_ORIGINS)"
  hosts="$(read_env ALLOWED_HOSTS)"
  if [[ "$origins" == *"*"* ]]; then
    echo "ALLOWED_ORIGINS must not include '*' in ${ENV_FILE_PATH}" >&2
    missing=1
  fi
  if [[ "$hosts" == *"*"* ]]; then
    echo "ALLOWED_HOSTS must not include '*' in ${ENV_FILE_PATH}" >&2
    missing=1
  fi

  local runtime_env
  runtime_env="$(printf '%s' "$(read_env ENV)" | tr '[:upper:]' '[:lower:]')"
  local route_authz
  route_authz="$(read_env BFF_ENFORCE_ROUTE_AUTHZ)"
  local accept_legacy_cookie
  accept_legacy_cookie="$(read_env AUTH_ACCEPT_LEGACY_SESSION_COOKIE)"
  local allow_header_session_auth
  allow_header_session_auth="$(read_env AUTH_ALLOW_HEADER_SESSION_AUTH)"
  local block_browser_header_session
  block_browser_header_session="$(read_env AUTH_BLOCK_BROWSER_HEADER_SESSION)"
  if [[ "$runtime_env" == "prod" || "$runtime_env" == "production" || "$runtime_env" == "staging" || -z "$runtime_env" ]]; then
    if [[ -z "$route_authz" ]]; then
      echo "BFF_ENFORCE_ROUTE_AUTHZ must be enabled in ${ENV_FILE_PATH} for prod/staging" >&2
      missing=1
    elif is_false_like "$route_authz"; then
      echo "BFF_ENFORCE_ROUTE_AUTHZ must be enabled in ${ENV_FILE_PATH} for prod/staging" >&2
      missing=1
    fi

    if is_true_like "$accept_legacy_cookie"; then
      echo "AUTH_ACCEPT_LEGACY_SESSION_COOKIE must be false in ${ENV_FILE_PATH} for prod/staging" >&2
      missing=1
    fi

    if [[ -n "$allow_header_session_auth" ]]; then
      echo "AUTH_ALLOW_HEADER_SESSION_AUTH has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if [[ -n "$block_browser_header_session" ]]; then
      echo "AUTH_BLOCK_BROWSER_HEADER_SESSION has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_EXPOSE_CODES='; then
      echo "AUTH_EXPOSE_CODES has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_REQUEST_CODE_'; then
      echo "AUTH_REQUEST_CODE_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_VERIFY_'; then
      echo "AUTH_VERIFY_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_OTP_'; then
      echo "AUTH_OTP_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_RESOLVE_PHONE_'; then
      echo "AUTH_RESOLVE_PHONE_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP='; then
      echo "CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi

    local livekit_key livekit_secret
    livekit_key="$(read_env LIVEKIT_API_KEY)"
    livekit_secret="$(read_env LIVEKIT_API_SECRET)"
    if [[ -z "$livekit_key" || -z "$livekit_secret" || "$livekit_key" == "devkey" || "$livekit_secret" == "devsecret" ]]; then
      echo "LIVEKIT_API_KEY/LIVEKIT_API_SECRET must be set to non-dev values in ${ENV_FILE_PATH}" >&2
      missing=1
    fi

    local account_create_pow_enabled
    account_create_pow_enabled="$(read_env AUTH_ACCOUNT_CREATE_POW_ENABLED)"
    if [[ -z "$account_create_pow_enabled" ]]; then
      account_create_pow_enabled="true"
    fi

    if ! is_false_like "$account_create_pow_enabled"; then
      local account_create_pow_secret
      account_create_pow_secret="$(read_env AUTH_ACCOUNT_CREATE_POW_SECRET)"
      if is_placeholder_like "$account_create_pow_secret"; then
        echo "AUTH_ACCOUNT_CREATE_POW_SECRET must be set to a strong non-placeholder value in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
    fi

    local hw_attestation_enabled
    hw_attestation_enabled="$(read_env AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED)"
    if [[ -z "$hw_attestation_enabled" ]]; then
      hw_attestation_enabled="true"
    fi
    local account_create_enabled
    account_create_enabled="$(read_env AUTH_ACCOUNT_CREATE_ENABLED)"
    local hw_attestation_required
    hw_attestation_required="$(read_env AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION)"
    if [[ -z "$hw_attestation_required" ]]; then
      hw_attestation_required="$hw_attestation_enabled"
    fi

    if is_false_like "$hw_attestation_enabled"; then
      if [[ -n "$hw_attestation_required" ]] && ! is_false_like "$hw_attestation_required"; then
        echo "AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION must be false in ${ENV_FILE_PATH} when hardware attestation is disabled" >&2
        missing=1
      fi
      if [[ -z "$account_create_enabled" ]] || ! is_false_like "$account_create_enabled"; then
        echo "AUTH_ACCOUNT_CREATE_ENABLED must be explicitly false in ${ENV_FILE_PATH} when hardware attestation is disabled (secure interim mode)" >&2
        missing=1
      fi

      local apple_team_id apple_key_id apple_p8_b64
      apple_team_id="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID)"
      apple_key_id="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID)"
      apple_p8_b64="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64)"
      if [[ -n "$apple_team_id" || -n "$apple_key_id" || -n "$apple_p8_b64" ]]; then
        echo "Apple DeviceCheck vars must be empty in ${ENV_FILE_PATH} when hardware attestation is disabled" >&2
        missing=1
      fi

      local play_svc_b64 play_pkgs play_require_strong play_require_recognized play_require_licensed
      play_svc_b64="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64)"
      play_pkgs="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES)"
      play_require_strong="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY)"
      play_require_recognized="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED)"
      play_require_licensed="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED)"

      if [[ -n "$play_svc_b64" || -n "$play_pkgs" ]]; then
        echo "Play Integrity provider vars must be empty in ${ENV_FILE_PATH} when hardware attestation is disabled" >&2
        missing=1
      fi
      if [[ -n "$play_require_strong" ]] && ! is_false_like "$play_require_strong"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY must be false in ${ENV_FILE_PATH} when hardware attestation is disabled" >&2
        missing=1
      fi
      if [[ -n "$play_require_recognized" ]] && ! is_false_like "$play_require_recognized"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED must be false in ${ENV_FILE_PATH} when hardware attestation is disabled" >&2
        missing=1
      fi
      if [[ -n "$play_require_licensed" ]] && ! is_false_like "$play_require_licensed"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED must be false in ${ENV_FILE_PATH} when hardware attestation is disabled" >&2
        missing=1
      fi
    fi

    if ! is_false_like "$hw_attestation_enabled"; then
      if is_false_like "$hw_attestation_required"; then
        echo "AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION must be true in ${ENV_FILE_PATH} for prod/staging strict mode" >&2
        missing=1
      fi

      local apple_team_id apple_key_id apple_p8_b64
      apple_team_id="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID)"
      apple_key_id="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID)"
      apple_p8_b64="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64)"

      if is_placeholder_like "$apple_team_id"; then
        echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID must be set in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
      if is_placeholder_like "$apple_key_id"; then
        echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID must be set in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
      if is_placeholder_like "$apple_p8_b64"; then
        echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 must be set in ${ENV_FILE_PATH}" >&2
        missing=1
      elif command -v openssl >/dev/null 2>&1; then
        if ! printf '%s' "$apple_p8_b64" | openssl base64 -d -A >/dev/null 2>&1; then
          echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 must be valid base64 PEM in ${ENV_FILE_PATH}" >&2
          missing=1
        else
          local apple_decoded
          apple_decoded="$(printf '%s' "$apple_p8_b64" | openssl base64 -d -A 2>/dev/null || true)"
          if [[ "$apple_decoded" != *"BEGIN PRIVATE KEY"* ]]; then
            echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 must decode to a PEM private key in ${ENV_FILE_PATH}" >&2
            missing=1
          fi
        fi
      fi

      local play_svc_b64 play_pkgs play_require_strong play_require_recognized
      play_svc_b64="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64)"
      play_pkgs="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES)"
      play_require_strong="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY)"
      play_require_recognized="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED)"

      if is_placeholder_like "$play_svc_b64"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must be set in ${ENV_FILE_PATH}" >&2
        missing=1
      elif command -v openssl >/dev/null 2>&1; then
        if ! printf '%s' "$play_svc_b64" | openssl base64 -d -A >/dev/null 2>&1; then
          echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must be valid base64(JSON) in ${ENV_FILE_PATH}" >&2
          missing=1
        else
          local play_decoded
          play_decoded="$(printf '%s' "$play_svc_b64" | openssl base64 -d -A 2>/dev/null || true)"
          if [[ "$play_decoded" != *"\"client_email\""* || "$play_decoded" != *"\"private_key\""* ]]; then
            echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must include client_email/private_key in ${ENV_FILE_PATH}" >&2
            missing=1
          fi
        fi
      fi

      if is_placeholder_like "$play_pkgs"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES must be set in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
      if [[ -z "$play_require_strong" ]] || is_false_like "$play_require_strong"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY must be true in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
      if [[ -z "$play_require_recognized" ]] || is_false_like "$play_require_recognized"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED must be true in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
    fi
  fi

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
  echo "Env check OK: ${ENV_FILE_PATH}"
}

health() {
  if [[ "${SKIP_HEALTH_CHECK:-0}" == "1" ]]; then
    echo "Health check skipped."
    return 0
  fi

  require_cmd curl

  local url="${HEALTH_URL:-$HEALTH_URL_DEFAULT}"
  local curl_args=(-fsS)
  if [[ "${HEALTH_INSECURE:-0}" == "1" ]]; then
    curl_args+=(-k)
  fi
  if [[ -n "${HEALTH_HOST:-}" ]]; then
    curl_args+=(-H "Host: ${HEALTH_HOST}")
  fi
  if [[ -n "${HEALTH_RESOLVE:-}" ]]; then
    curl_args+=(--resolve "${HEALTH_RESOLVE}")
  fi

  local retries="${HEALTH_RETRIES:-1}"
  local delay="${HEALTH_RETRY_DELAY:-2}"
  local attempt=1

  while true; do
    if curl "${curl_args[@]}" "$url"; then
      echo
      return 0
    fi
    if (( attempt >= retries )); then
      break
    fi
    sleep "$delay"
    attempt=$((attempt + 1))
  done

  return 1
}

prune_backups() {
  local backup_dir="$1"
  local pattern="$2"
  local keep="${BACKUP_KEEP:-0}"
  if [[ -z "$keep" || "$keep" == "0" ]]; then
    return 0
  fi
  if ! [[ "$keep" =~ ^[0-9]+$ ]]; then
    echo "BACKUP_KEEP must be an integer." >&2
    exit 1
  fi

  local files=()
  local f
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$backup_dir" -maxdepth 1 -type f -name "$pattern" -print | sort -r)

  if (( ${#files[@]} <= keep )); then
    return 0
  fi

  local idx
  for ((idx=keep; idx<${#files[@]}; idx++)); do
    rm -f "${files[idx]}"
    echo "Pruned: ${files[idx]}"
  done
}

_pg_read_or() {
  local key="$1"
  local default="$2"
  local v
  v="$(read_env "$key")"
  if [[ -z "$v" ]]; then
    v="$default"
  fi
  printf "%s" "$v"
}

backup_postgres_bundle() {
  local backup_dir="$1"
  local ts="$2"

  local user password
  user="$(read_env POSTGRES_USER)"
  password="$(read_env POSTGRES_PASSWORD)"
  if [[ -z "$user" || -z "$password" ]]; then
    echo "Missing POSTGRES_USER/POSTGRES_PASSWORD in ${ENV_FILE_PATH}" >&2
    exit 1
  fi

  local core_db chat_db payments_db bus_db
  core_db="$(_pg_read_or POSTGRES_DB_CORE shamell_core)"
  chat_db="$(_pg_read_or POSTGRES_DB_CHAT shamell_chat)"
  payments_db="$(_pg_read_or POSTGRES_DB_PAYMENTS shamell_payments)"
  bus_db="$(_pg_read_or POSTGRES_DB_BUS shamell_bus)"

  local out="${backup_dir}/${ENV_NAME}-postgres-${ts}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"

  compose up -d db >/dev/null

  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$core_db" --no-owner --no-privileges > "${tmp}/core.sql"
  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$chat_db" --no-owner --no-privileges > "${tmp}/chat.sql"
  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$payments_db" --no-owner --no-privileges > "${tmp}/payments.sql"
  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$bus_db" --no-owner --no-privileges > "${tmp}/bus.sql"

  tar -czf "$out" -C "$tmp" core.sql chat.sql payments.sql bus.sql
  rm -rf "$tmp" || true

  echo "Backup written: ${out}"
  prune_backups "$backup_dir" "${ENV_NAME}-postgres-*.tar.gz"
}

restore_postgres_bundle() {
  local backup_file="$1"

  local user password
  user="$(read_env POSTGRES_USER)"
  password="$(read_env POSTGRES_PASSWORD)"
  if [[ -z "$user" || -z "$password" ]]; then
    echo "Missing POSTGRES_USER/POSTGRES_PASSWORD in ${ENV_FILE_PATH}" >&2
    exit 1
  fi

  local core_db chat_db payments_db bus_db
  core_db="$(_pg_read_or POSTGRES_DB_CORE shamell_core)"
  chat_db="$(_pg_read_or POSTGRES_DB_CHAT shamell_chat)"
  payments_db="$(_pg_read_or POSTGRES_DB_PAYMENTS shamell_payments)"
  bus_db="$(_pg_read_or POSTGRES_DB_BUS shamell_bus)"

  local tmp
  tmp="$(mktemp -d)"
  tar -xzf "$backup_file" -C "$tmp"

  for f in core.sql chat.sql payments.sql bus.sql; do
    if [[ ! -f "${tmp}/${f}" ]]; then
      echo "Invalid postgres backup bundle (missing ${f}): ${backup_file}" >&2
      exit 1
    fi
  done

  compose up -d db >/dev/null

  if [[ "${RESTORE_DROP_SCHEMA:-0}" == "1" ]]; then
    for db in "$core_db" "$chat_db" "$payments_db" "$bus_db"; do
      compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$db" -v ON_ERROR_STOP=1 -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
    done
  fi

  cat "${tmp}/core.sql" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$core_db" -v ON_ERROR_STOP=1
  cat "${tmp}/chat.sql" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$chat_db" -v ON_ERROR_STOP=1
  cat "${tmp}/payments.sql" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$payments_db" -v ON_ERROR_STOP=1
  cat "${tmp}/bus.sql" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$bus_db" -v ON_ERROR_STOP=1

  rm -rf "$tmp" || true
  echo "Restore complete: ${backup_file}"
}

backup() {
  local backup_dir="${BACKUP_DIR:-${APP_DIR}/backups}"
  mkdir -p "$backup_dir"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_postgres_bundle "$backup_dir" "$ts"
}

restore() {
  local backup_file="${1:-}"
  if [[ -z "$backup_file" ]]; then
    echo "Usage: scripts/ops.sh ${ENV_NAME} restore <backup-file>" >&2
    exit 1
  fi
  if [[ ! -f "$backup_file" ]]; then
    echo "Backup not found: ${backup_file}" >&2
    exit 1
  fi
  if [[ "${CONFIRM_RESTORE:-0}" != "1" ]]; then
    echo "Refusing to restore without CONFIRM_RESTORE=1" >&2
    exit 1
  fi

  local running
  running="$(compose ps -q bff || true)"
  if [[ -n "$running" && "${ALLOW_RUNNING_RESTORE:-0}" != "1" ]]; then
    echo "Services are running. Stop them or set ALLOW_RUNNING_RESTORE=1 to proceed." >&2
    exit 1
  fi

  restore_postgres_bundle "$backup_file"
}

report() {
  local backup_dir="${BACKUP_DIR:-${APP_DIR}/backups}"

  echo "==> status"
  compose ps
  echo

  echo "==> health"
  if ! health; then
    echo "Health check failed." >&2
  fi
  echo

  echo "==> disk"
  if command -v df >/dev/null 2>&1; then
    df -h "$backup_dir" 2>/dev/null || df -h .
  else
    echo "df not available"
  fi
  echo

  echo "==> backups"
  if [[ -d "$backup_dir" ]]; then
    ls -lt "$backup_dir" | head -n 20
  else
    echo "No backups directory at ${backup_dir}"
  fi
}

security_report() {
  "${APP_DIR}/scripts/security_events_report.sh"
}

security_drill() {
  "${APP_DIR}/scripts/security_alert_webhook_drill.sh" "$@"
}

migrate() {
  echo "migrate: no-op (schema is managed by Rust services on startup)."
}

compose_build_service() {
  local service="$1"
  if compose build --help 2>/dev/null | grep -q -- '--no-deps'; then
    compose build --no-deps "$service"
  else
    compose build "$service"
  fi
}

sequential_service_build() {
  local services_raw retries delay
  services_raw="${1:-${DEPLOY_SEQUENTIAL_BUILD_SERVICES:-bff chat payments bus}}"
  retries="${DEPLOY_BUILD_RETRIES:-3}"
  delay="${DEPLOY_BUILD_RETRY_DELAY_SECS:-8}"

  if ! [[ "$retries" =~ ^[0-9]+$ ]] || [[ "$retries" == "0" ]]; then
    echo "DEPLOY_BUILD_RETRIES must be a positive integer." >&2
    return 1
  fi
  if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
    echo "DEPLOY_BUILD_RETRY_DELAY_SECS must be a non-negative integer." >&2
    return 1
  fi

  services_raw="${services_raw//,/ }"
  local build_services=()
  read -r -a build_services <<<"$services_raw"
  if [[ "${#build_services[@]}" -eq 0 ]]; then
    echo "DEPLOY_SEQUENTIAL_BUILD_SERVICES resolved to an empty service list." >&2
    return 1
  fi

  local service attempt
  for service in "${build_services[@]}"; do
    attempt=1
    while true; do
      echo "Sequential build: ${service} (attempt ${attempt}/${retries})"
      if compose_build_service "$service"; then
        break
      fi
      if (( attempt >= retries )); then
        echo "Sequential build failed for ${service} after ${retries} attempts." >&2
        return 1
      fi
      if (( delay > 0 )); then
        echo "Retrying ${service} in ${delay}s..."
        sleep "$delay"
      fi
      attempt=$((attempt + 1))
    done
  done
}

infer_up_build_services() {
  if [[ -n "${DEPLOY_SEQUENTIAL_BUILD_SERVICES:-}" ]]; then
    printf "%s" "${DEPLOY_SEQUENTIAL_BUILD_SERVICES}"
    return 0
  fi

  local -a buildable=(bff chat payments bus)
  local -a selected=()
  local arg service existing seen
  for arg in "$@"; do
    if [[ "$arg" == -* ]]; then
      continue
    fi
    for service in "${buildable[@]}"; do
      if [[ "$arg" != "$service" ]]; then
        continue
      fi
      seen=0
      if (( ${#selected[@]} > 0 )); then
        for existing in "${selected[@]}"; do
          if [[ "$existing" == "$service" ]]; then
            seen=1
            break
          fi
        done
      fi
      if (( seen == 0 )); then
        selected+=("$service")
      fi
      break
    done
  done

  if [[ "${#selected[@]}" -eq 0 ]]; then
    printf "%s" "${buildable[*]}"
  else
    printf "%s" "${selected[*]}"
  fi
}

compose_up_with_build_fallback() {
  local mode="${1:-Deploy}"
  shift || true
  local -a up_args=()
  local has_up_args=0
  if (( $# > 0 )); then
    up_args=("$@")
    has_up_args=1
  fi
  local force_sequential
  force_sequential="${DEPLOY_FORCE_SEQUENTIAL_BUILD:-0}"
  local build_services
  if (( has_up_args == 1 )); then
    build_services="$(infer_up_build_services "${up_args[@]}")"
  else
    build_services="$(infer_up_build_services)"
  fi

  if is_true_like "$force_sequential"; then
    echo "${mode}: DEPLOY_FORCE_SEQUENTIAL_BUILD enabled; skipping fast build path."
    sequential_service_build "$build_services"
    if (( has_up_args == 1 )); then
      compose up -d "${up_args[@]}"
    else
      compose up -d
    fi
    return 0
  fi

  if (( has_up_args == 1 )); then
    if compose up -d --build "${up_args[@]}"; then
      echo "${mode}: fast compose up --build path succeeded."
      return 0
    fi
  elif compose up -d --build; then
    echo "${mode}: fast compose up --build path succeeded."
    return 0
  fi

  echo "${mode}: fast compose up --build path failed; falling back to sequential service builds."
  sequential_service_build "$build_services"
  if (( has_up_args == 1 )); then
    compose up -d "${up_args[@]}"
  else
    compose up -d
  fi
}

compose_build_with_fallback() {
  local mode="${1:-Build}"
  shift || true
  local -a build_args=()
  local has_build_args=0
  if (( $# > 0 )); then
    build_args=("$@")
    has_build_args=1
  fi
  local force_sequential
  force_sequential="${DEPLOY_FORCE_SEQUENTIAL_BUILD:-0}"
  local build_services
  if (( has_build_args == 1 )); then
    build_services="$(infer_up_build_services "${build_args[@]}")"
  else
    build_services="$(infer_up_build_services)"
  fi

  if is_true_like "$force_sequential"; then
    echo "${mode}: DEPLOY_FORCE_SEQUENTIAL_BUILD enabled; skipping fast compose build path."
    sequential_service_build "$build_services"
    return 0
  fi

  if (( has_build_args == 1 )); then
    if compose build "${build_args[@]}"; then
      echo "${mode}: fast compose build path succeeded."
      return 0
    fi
  elif compose build; then
    echo "${mode}: fast compose build path succeeded."
    return 0
  fi

  echo "${mode}: fast compose build path failed; falling back to sequential service builds."
  sequential_service_build "$build_services"
}

deploy() {
  if [[ "$ENV_NAME" != "dev" ]]; then
    check_env
  fi

  compose_up_with_build_fallback "Deploy"

  if [[ -z "${HEALTH_RETRIES:-}" ]]; then
    HEALTH_RETRIES=10
  fi
  if [[ -z "${HEALTH_RETRY_DELAY:-}" ]]; then
    HEALTH_RETRY_DELAY=2
  fi
  health
}

smoke_mailbox() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "smoke-mailbox: run against pipg/prod env (needs Postgres-backed auth + internal headers)." >&2
    exit 1
  fi

  require_cmd curl
  require_cmd jq
  require_cmd shasum
  require_cmd openssl

  local env_lower
  env_lower="$(read_env ENV | tr '[:upper:]' '[:lower:]')"
  if [[ "$env_lower" == "prod" || "$env_lower" == "production" ]]; then
    if ! is_true_like "${SMOKE_ALLOW_PROD:-0}"; then
      echo "smoke-mailbox: refusing to write test sessions in prod. Set SMOKE_ALLOW_PROD=1 to override." >&2
      exit 1
    fi
  fi

  local bff_port caller internal_secret client_ip phone device_id sid sid_hash pub envelope
  bff_port="$(read_env BFF_PUBLISH_PORT)"
  bff_port="${bff_port:-8080}"
  internal_secret="$(read_env INTERNAL_API_SECRET)"
  caller="${SMOKE_INTERNAL_CALLER:-edge}"
  caller="$(printf '%s' "$caller" | tr -d '[:space:]')"
  if [[ -z "$caller" ]]; then
    caller="edge"
  fi

  client_ip="${SMOKE_CLIENT_IP:-203.0.113.10}"
  phone="${SMOKE_PHONE:-+15555550100}"
  device_id="${SMOKE_DEVICE_ID:-smk$(date +%s | tail -c 6)}"

  sid="$(openssl rand -hex 16)"
  sid_hash="$(printf '%s' "$sid" | shasum -a 256 | awk '{print $1}')"

  # 32+ chars; chat service only checks length here.
  pub="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789AB"
  # Must pass normalize_key_material min_len=16 and allowed chars.
  envelope="QUJDREVGR0hJSktMTU5PUFFSU1RVVldY"

  local pg_user pg_pass pg_db
  pg_user="$(read_env POSTGRES_USER)"
  pg_pass="$(read_env POSTGRES_PASSWORD)"
  pg_db="$(read_env POSTGRES_DB_CORE)"
  pg_user="${pg_user:-shamell}"
  pg_db="${pg_db:-shamell_core}"
  if [[ -z "$pg_pass" ]]; then
    echo "smoke-mailbox: missing POSTGRES_PASSWORD in env file." >&2
    exit 1
  fi
  if [[ -z "$internal_secret" ]]; then
    echo "smoke-mailbox: missing INTERNAL_API_SECRET in env file." >&2
    exit 1
  fi

  cleanup_smoke_mailbox() {
    # best-effort cleanup
    local pg_user="${SMOKE_MB_PG_USER:-}"
    local pg_pass="${SMOKE_MB_PG_PASS:-}"
    local pg_db="${SMOKE_MB_PG_DB:-}"
    local sid_hash="${SMOKE_MB_SID_HASH:-}"
    local phone="${SMOKE_MB_PHONE:-}"
    local device_id="${SMOKE_MB_DEVICE_ID:-}"
    if [[ -z "$pg_user" || -z "$pg_pass" || -z "$pg_db" || -z "$sid_hash" ]]; then
      return 0
    fi
    compose exec -T db sh -lc "PGPASSWORD='${pg_pass}' psql -U '${pg_user}' -d '${pg_db}' -v ON_ERROR_STOP=1 -q \
      -c \"DELETE FROM auth_sessions WHERE sid_hash='${sid_hash}';\" \
      -c \"DELETE FROM device_sessions WHERE phone='${phone}' AND device_id='${device_id}';\"" >/dev/null 2>&1 || true
  }
  SMOKE_MB_PG_USER="$pg_user"
  SMOKE_MB_PG_PASS="$pg_pass"
  SMOKE_MB_PG_DB="$pg_db"
  SMOKE_MB_SID_HASH="$sid_hash"
  SMOKE_MB_PHONE="$phone"
  SMOKE_MB_DEVICE_ID="$device_id"
  trap cleanup_smoke_mailbox EXIT

  # Seed session + owned device for BFF guardrails.
  compose exec -T db sh -lc "PGPASSWORD='${pg_pass}' psql -U '${pg_user}' -d '${pg_db}' -v ON_ERROR_STOP=1 -q" >/dev/null <<SQL
INSERT INTO auth_sessions (sid_hash, phone, device_id, expires_at, created_at, last_seen_at, revoked_at)
VALUES ('${sid_hash}', '${phone}', '${device_id}', NOW() + INTERVAL '1 day', NOW(), NOW(), NULL)
ON CONFLICT (sid_hash) DO UPDATE SET phone=EXCLUDED.phone, device_id=EXCLUDED.device_id, expires_at=EXCLUDED.expires_at, last_seen_at=NOW(), revoked_at=NULL;

INSERT INTO device_sessions (phone, device_id, device_type, device_name, platform, app_version, last_ip, user_agent, created_at, last_seen_at)
VALUES ('${phone}', '${device_id}', 'mobile', 'smoke', 'ios', '1.0', '${client_ip}', 'smoke-mailbox', NOW(), NOW())
ON CONFLICT (phone, device_id) DO UPDATE SET last_seen_at=NOW(), last_ip=EXCLUDED.last_ip, user_agent=EXCLUDED.user_agent;
SQL

  local bff_url
  bff_url="${SMOKE_BFF_URL:-http://127.0.0.1:${bff_port}}"

  local -a common_headers=(
    -H "x-internal-secret: ${internal_secret}"
    -H "x-internal-service-id: ${caller}"
    -H "x-shamell-client-ip: ${client_ip}"
    -H "content-type: application/json"
    -H "cookie: __Host-sa_session=${sid}"
  )

  local reg_raw reg_http reg_json auth_token
  reg_raw="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -d "{\"device_id\":\"${device_id}\",\"public_key_b64\":\"${pub}\",\"name\":\"smoke\"}" \
    "${bff_url}/chat/devices/register")"
  reg_http="$(printf '%s' "$reg_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  reg_json="$(printf '%s' "$reg_raw" | sed '/^HTTP:/d')"
  auth_token="$(printf '%s' "$reg_json" | jq -r '.auth_token // empty')"
  if [[ "$reg_http" != "200" || -z "$auth_token" ]]; then
    echo "smoke-mailbox: register failed (HTTP=$reg_http)" >&2
    echo "$reg_raw" >&2
    exit 1
  fi

  local issue_raw issue_http mailbox_token
  issue_raw="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"device_id\":\"${device_id}\"}" \
    "${bff_url}/chat/mailboxes/issue")"
  issue_http="$(printf '%s' "$issue_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  mailbox_token="$(printf '%s' "$issue_raw" | sed '/^HTTP:/d' | jq -r '.mailbox_token // empty')"
  if [[ "$issue_http" != "200" || -z "$mailbox_token" ]]; then
    echo "smoke-mailbox: issue failed (HTTP=$issue_http)" >&2
    echo "$issue_raw" >&2
    exit 1
  fi

  local write_http poll_http rotate_http rotate_json new_mailbox_token old_write_http
  write_http="$(curl -sS -o /dev/null -w '%{http_code}' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"mailbox_token\":\"${mailbox_token}\",\"envelope_b64\":\"${envelope}\",\"sender_hint\":\"smoke\"}" \
    "${bff_url}/chat/mailboxes/write")"
  if [[ "$write_http" != "200" ]]; then
    echo "smoke-mailbox: write failed (HTTP=$write_http)" >&2
    exit 1
  fi

  poll_http="$(curl -sS -o /dev/null -w '%{http_code}' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"device_id\":\"${device_id}\",\"mailbox_token\":\"${mailbox_token}\",\"limit\":10}" \
    "${bff_url}/chat/mailboxes/poll")"
  if [[ "$poll_http" != "200" ]]; then
    echo "smoke-mailbox: poll failed (HTTP=$poll_http)" >&2
    exit 1
  fi

  rotate_json="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"device_id\":\"${device_id}\",\"mailbox_token\":\"${mailbox_token}\"}" \
    "${bff_url}/chat/mailboxes/rotate")"
  rotate_http="$(printf '%s' "$rotate_json" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  new_mailbox_token="$(printf '%s' "$rotate_json" | sed '/^HTTP:/d' | jq -r '.mailbox_token // empty')"
  if [[ "$rotate_http" != "200" || -z "$new_mailbox_token" ]]; then
    echo "smoke-mailbox: rotate failed (HTTP=$rotate_http)" >&2
    echo "$rotate_json" >&2
    exit 1
  fi
  if [[ "$new_mailbox_token" == "$mailbox_token" ]]; then
    echo "smoke-mailbox: rotate returned same token (unexpected)." >&2
    exit 1
  fi

  old_write_http="$(curl -sS -o /dev/null -w '%{http_code}' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"mailbox_token\":\"${mailbox_token}\",\"envelope_b64\":\"${envelope}\"}" \
    "${bff_url}/chat/mailboxes/write")"
  if [[ "$old_write_http" != "404" ]]; then
    echo "smoke-mailbox: old token write not rejected as 404 (HTTP=$old_write_http)" >&2
    exit 1
  fi

  echo "smoke-mailbox: ok (register=200 issue=200 write=200 poll=200 rotate=200 old_write=404)"
}

smoke_api() {
  require_cmd curl

  # Keep this read-only and low-noise: it should be safe to run in prod.
  local health_url base_url
  health_url="${HEALTH_URL:-$HEALTH_URL_DEFAULT}"
  base_url="${SMOKE_BASE_URL:-}"
  if [[ -z "$base_url" ]]; then
    # Derive from health URL. If the health URL ends with /health, strip it.
    if [[ "$health_url" == */health ]]; then
      base_url="${health_url%/health}"
    else
      base_url="$health_url"
    fi
  fi
  base_url="${base_url%/}"
  if [[ -z "$base_url" ]]; then
    echo "smoke-api: could not derive SMOKE_BASE_URL." >&2
    exit 1
  fi

  local curl_args=(-sS)
  if [[ "${SMOKE_INSECURE:-${HEALTH_INSECURE:-0}}" == "1" ]]; then
    curl_args+=(-k)
  fi
  if [[ -n "${SMOKE_HOST:-${HEALTH_HOST:-}}" ]]; then
    curl_args+=(-H "Host: ${SMOKE_HOST:-$HEALTH_HOST}")
  fi
  if [[ -n "${SMOKE_RESOLVE:-${HEALTH_RESOLVE:-}}" ]]; then
    curl_args+=(--resolve "${SMOKE_RESOLVE:-$HEALTH_RESOLVE}")
  fi
  if [[ -n "${SMOKE_CLIENT_IP:-}" ]]; then
    curl_args+=(-H "X-Shamell-Client-IP: ${SMOKE_CLIENT_IP}")
  fi

  local tmp status body url
  tmp="$(mktemp)"
  local health_status me_roles_status chat_inbox_status internal_alerts_status
  local account_create_challenge_status expect_account_create_disabled account_create_enabled

  request() {
    local method="$1"
    url="$2"
    shift 2
    status="$(
      curl "${curl_args[@]}" \
        --connect-timeout 5 \
        --max-time 12 \
        -X "$method" \
        "$@" \
        -o "$tmp" \
        -w "%{http_code}" \
        "$url"
    )"
    body="$(cat "$tmp" || true)"
  }

  fail_if_internal_auth_error() {
    local name="$1"
    local status="$2"
    local body="$3"
    if echo "$body" | grep -qi "internal auth required"; then
      echo "smoke-api: FAIL ($name) returned internal auth required (HTTP=$status)." >&2
      exit 1
    fi
    if echo "$body" | grep -qi "internal auth not configured"; then
      echo "smoke-api: FAIL ($name) internal auth not configured (HTTP=$status)." >&2
      exit 1
    fi
  }

  # 1) Health must be OK (fast fail).
  request GET "${base_url}/health"
  health_status="$status"
  if [[ "$status" != "200" ]]; then
    echo "smoke-api: FAIL health check (${base_url}/health) (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 2) Public authed routes must NOT require X-Internal-Secret.
  request GET "${base_url}/me/roles"
  me_roles_status="$status"
  fail_if_internal_auth_error "me/roles" "$status" "$body"
  if [[ "$status" != "401" && "$status" != "403" ]]; then
    echo "smoke-api: FAIL me/roles expected 401/403 without session (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 3) Chat routes must also fail with normal auth errors (not internal-auth),
  # and must not reach upstream without a session.
  request GET "${base_url}/chat/messages/inbox?device_id=smoke_device"
  chat_inbox_status="$status"
  fail_if_internal_auth_error "chat/messages/inbox" "$status" "$body"
  if [[ "$status" != "401" && "$status" != "403" ]]; then
    echo "smoke-api: FAIL chat inbox expected 401/403 without session (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 4) Internal-only route must remain non-public (Nginx blocks /internal/*),
  # or (direct BFF) must require X-Internal-Secret.
  request POST "${base_url}/internal/security/alerts" -H "content-type: application/json" -d "{}"
  internal_alerts_status="$status"
  if [[ "$status" == "200" || "$status" == "201" || "$status" == "202" ]]; then
    echo "smoke-api: FAIL internal/security/alerts unexpectedly accepted request (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi
  # Accept 401 (internal-auth), 403/404 (edge block), 405 (method mismatch).
  if [[ "$status" != "401" && "$status" != "403" && "$status" != "404" && "$status" != "405" ]]; then
    echo "smoke-api: FAIL internal/security/alerts unexpected status (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 5) Account-create challenge must match rollout policy:
  # - secure interim mode (disabled): 503
  # - enabled mode: 200 (or 429 under repeated runs/rate-limit)
  expect_account_create_disabled="${SMOKE_EXPECT_ACCOUNT_CREATE_DISABLED:-}"
  if [[ -z "$expect_account_create_disabled" ]]; then
    account_create_enabled="$(read_env AUTH_ACCOUNT_CREATE_ENABLED)"
    if [[ -z "$account_create_enabled" ]]; then
      account_create_enabled="true"
    fi
    if is_false_like "$account_create_enabled"; then
      expect_account_create_disabled="1"
    else
      expect_account_create_disabled="0"
    fi
  fi

  request POST "${base_url}/auth/account/create/challenge" \
    -H "content-type: application/json" \
    -d '{"device_id":"smoke_device"}'
  account_create_challenge_status="$status"
  fail_if_internal_auth_error "auth/account/create/challenge" "$status" "$body"
  if is_true_like "$expect_account_create_disabled"; then
    if [[ "$status" != "503" ]]; then
      echo "smoke-api: FAIL account-create challenge expected 503 in secure interim mode (HTTP=$status)." >&2
      rm -f "$tmp"
      exit 1
    fi
  else
    if [[ "$status" != "200" && "$status" != "429" ]]; then
      echo "smoke-api: FAIL account-create challenge expected 200/429 in enabled mode (HTTP=$status)." >&2
      rm -f "$tmp"
      exit 1
    fi
  fi

  rm -f "$tmp"
  echo "smoke-api: ok (base=${base_url} health=${health_status} me_roles=${me_roles_status} chat_inbox=${chat_inbox_status} internal_alerts=${internal_alerts_status} account_create_challenge=${account_create_challenge_status})"
}

case "$CMD" in
  up)
    compose_up_with_build_fallback "Up" "$@"
    ;;
  down)
    compose down "$@"
    ;;
  restart)
    compose restart "$@"
    ;;
  logs)
    if [[ "$#" -eq 0 ]]; then
      compose logs -f --tail=200
    else
      compose logs "$@"
    fi
    ;;
  ps|status)
    compose ps
    ;;
  report)
    report
    ;;
  smoke-api|smoke_api|api-smoke)
    smoke_api
    ;;
  smoke-mailbox|smoke_mailbox|mailbox-smoke)
    smoke_mailbox
    ;;
  security-report|security_alerts)
    security_report
    ;;
  security-drill|security_webhook_drill)
    security_drill "$@"
    ;;
  build)
    compose_build_with_fallback "Build" "$@"
    ;;
  pull)
    compose pull "$@"
    ;;
  health)
    health
    ;;
  check)
    check_env
    ;;
  deploy)
    deploy
    ;;
  migrate)
    migrate
    ;;
  backup)
    backup
    ;;
  restore)
    restore "$@"
    ;;
  shell)
    compose exec "$PRIMARY_SERVICE" sh
    ;;
  *)
    usage
    exit 1
    ;;
esac
