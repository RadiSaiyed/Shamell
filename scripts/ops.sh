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

require_cmd docker

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
    if [[ -z "$val" || "$val" == change-me* ]]; then
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

    if [[ -n "$block_browser_header_session" ]] && is_false_like "$block_browser_header_session"; then
      echo "AUTH_BLOCK_BROWSER_HEADER_SESSION must be enabled in ${ENV_FILE_PATH} for prod/staging" >&2
      missing=1
    fi

    local livekit_key livekit_secret
    livekit_key="$(read_env LIVEKIT_API_KEY)"
    livekit_secret="$(read_env LIVEKIT_API_SECRET)"
    if [[ -z "$livekit_key" || -z "$livekit_secret" || "$livekit_key" == "devkey" || "$livekit_secret" == "devsecret" ]]; then
      echo "LIVEKIT_API_KEY/LIVEKIT_API_SECRET must be set to non-dev values in ${ENV_FILE_PATH}" >&2
      missing=1
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
  local -a up_args=("$@")
  local force_sequential
  force_sequential="${DEPLOY_FORCE_SEQUENTIAL_BUILD:-0}"
  local build_services
  build_services="$(infer_up_build_services "${up_args[@]}")"

  if is_true_like "$force_sequential"; then
    echo "${mode}: DEPLOY_FORCE_SEQUENTIAL_BUILD enabled; skipping fast build path."
    sequential_service_build "$build_services"
    compose up -d "${up_args[@]}"
    return 0
  fi

  if compose up -d --build "${up_args[@]}"; then
    echo "${mode}: fast compose up --build path succeeded."
    return 0
  fi

  echo "${mode}: fast compose up --build path failed; falling back to sequential service builds."
  sequential_service_build "$build_services"
  compose up -d "${up_args[@]}"
}

compose_build_with_fallback() {
  local mode="${1:-Build}"
  shift || true
  local -a build_args=("$@")
  local force_sequential
  force_sequential="${DEPLOY_FORCE_SEQUENTIAL_BUILD:-0}"
  local build_services
  build_services="$(infer_up_build_services "${build_args[@]}")"

  if is_true_like "$force_sequential"; then
    echo "${mode}: DEPLOY_FORCE_SEQUENTIAL_BUILD enabled; skipping fast compose build path."
    sequential_service_build "$build_services"
    return 0
  fi

  if compose build "${build_args[@]}"; then
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
