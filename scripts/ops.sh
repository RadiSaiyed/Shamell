#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/ops.sh <env> <command> [args]

env:
  dev    local microservices compose
  devmono legacy local monolith compose
  prod   production compose (uses ops/production/.env)
  pi     raspberry pi compose (uses ops/pi/.env)

commands:
  up            build and start
  down          stop and remove
  restart       restart services
  logs          tail logs (pass service names or flags)
  ps            show status
  bootstrap-media-perms  chown volume perms (dev/devmono/prod/pi)
  proxy-cidrs   suggest reverse-proxy CIDRs (prod; Traefik)
  metrics-scrapers  show observed /metrics client IPs (prod; Traefik)
  report        status + health + disk + backups
  build         build images
  pull          pull images
  health        call /health
  check         validate env file (prod/pi)
  deploy        check + up + migrate + health (prod/pi; devmono supported)
  migrate       run core + payments migrations (prod/pi; optional in dev/devmono)
  migrate-core  run core migrations only (prod/pi; optional in dev/devmono)
  migrate-payments run payments migrations only (prod/pi; optional in dev/devmono)
  backup        backup database (prod/pi) or local service data (dev/devmono)
  restore       restore database (prod/pi) or local data (devmono)
  shell         shell into primary app container

Environment variables:
  ENV_FILE      override the default env file for prod/pi
  BACKUP_DIR    override the backup destination (default: platform/shamell-app/backups)
  BACKUP_MEDIA  set to 1 to include media volumes in prod/pi backups
  BACKUP_KEEP   keep last N backups per type (0 disables pruning)
  CONFIRM_RESTORE=1  allow destructive restore
  RESTORE_DROP_SCHEMA=1  drop public schema before restore (prod/pi)
  ALLOW_RUNNING_RESTORE=1 allow devmono restore while monolith is running
  HEALTH_URL    override health check URL
  HEALTH_HOST   optional Host header for health check
  HEALTH_RESOLVE optional curl --resolve (host:port:addr)
  HEALTH_INSECURE=1  allow insecure TLS for health check
  HEALTH_RETRIES  retry health check N times (default: 1)
  HEALTH_RETRY_DELAY  seconds between retries (default: 2)
  HEALTH_FALLBACK=1  allow local exec fallback for prod local.test
  SKIP_HEALTH_CHECK=1 skip health check (useful for local prod runs)

Examples:
  scripts/ops.sh dev up
  scripts/ops.sh dev logs
  scripts/ops.sh prod up
  ENV_FILE=ops/production/.env scripts/ops.sh prod backup
EOF
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
  devmono)
    COMPOSE_FILE="${APP_DIR}/docker-compose.monolith.yml"
    DEFAULT_ENV_FILE=""
    HEALTH_URL_DEFAULT="http://localhost:8088/health"
    PRIMARY_SERVICE="monolith"
    ;;
  prod)
    COMPOSE_FILE="${APP_DIR}/ops/production/docker-compose.yml"
    DEFAULT_ENV_FILE="${APP_DIR}/ops/production/.env"
    HEALTH_URL_DEFAULT=""
    PRIMARY_SERVICE="monolith"
    ;;
  pi)
    COMPOSE_FILE="${APP_DIR}/ops/pi/docker-compose.yml"
    DEFAULT_ENV_FILE="${APP_DIR}/ops/pi/.env"
    HEALTH_URL_DEFAULT="http://localhost:8080/health"
    PRIMARY_SERVICE="monolith"
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
  local line=""
  if [[ -z "$ENV_FILE_PATH" || ! -f "$ENV_FILE_PATH" ]]; then
    return 0
  fi
  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE_PATH" | tail -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf "%s" "$line"
}

check_env() {
  if [[ "$ENV_NAME" == "dev" || "$ENV_NAME" == "devmono" ]]; then
    echo "${ENV_NAME} env: no env file checks."
    return 0
  fi

  local missing=0
  local required=(
    INTERNAL_API_SECRET
    PAYMENTS_INTERNAL_SECRET
    SONIC_SECRET
    TOPUP_SECRET
    ALIAS_CODE_PEPPER
    CASH_SECRET_PEPPER
  )
  local key
  for key in "${required[@]}"; do
    local val
    val="$(read_env "$key")"
    if [[ -z "$val" || "$val" == change-me* ]]; then
      echo "Missing or invalid ${key} in ${ENV_FILE_PATH}" >&2
      missing=1
      continue
    fi
  done

  # Optional: validate sha256 digests if configured
  for key in ADMIN_TOKEN_SHA256 METRICS_BEARER_TOKEN_SHA256; do
    local val
    val="$(read_env "$key")"
    if [[ -n "$val" && ! "$val" =~ ^[0-9a-fA-F]{64}$ ]]; then
      echo "${key} must be a sha256 hex digest in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
  done

  local origins
  origins="$(read_env ALLOWED_ORIGINS)"
  if [[ -z "$origins" ]]; then
    echo "Missing ALLOWED_ORIGINS in ${ENV_FILE_PATH}" >&2
    missing=1
  elif [[ "$origins" == *"*"* ]]; then
    echo "ALLOWED_ORIGINS must not include '*' in ${ENV_FILE_PATH}" >&2
    missing=1
  fi

  local hosts
  hosts="$(read_env ALLOWED_HOSTS)"
  if [[ -z "$hosts" ]]; then
    echo "Missing ALLOWED_HOSTS in ${ENV_FILE_PATH}" >&2
    missing=1
  elif [[ "$hosts" == *"*"* ]]; then
    echo "ALLOWED_HOSTS must not include '*' in ${ENV_FILE_PATH}" >&2
    missing=1
  fi

  local core_auto
  core_auto="$(read_env AUTO_CREATE_SCHEMA)"
  if [[ -z "$core_auto" ]]; then
    echo "Missing AUTO_CREATE_SCHEMA in ${ENV_FILE_PATH}" >&2
    missing=1
  else
    local core_auto_norm
    core_auto_norm="$(printf '%s' "$core_auto" | tr '[:upper:]' '[:lower:]')"
    case "$core_auto_norm" in
      false|0|off|no)
        ;;
      *)
        echo "AUTO_CREATE_SCHEMA must be false in ${ENV_FILE_PATH}" >&2
        missing=1
        ;;
    esac
  fi

  if [[ "$ENV_NAME" == "prod" ]]; then
    local trusted_proxies
    trusted_proxies="$(read_env TRUSTED_PROXY_CIDRS)"
    if [[ -z "$trusted_proxies" || "$trusted_proxies" == change-me* ]]; then
      echo "Warning: TRUSTED_PROXY_CIDRS is unset in ${ENV_FILE_PATH}. Rate limits may see only proxy IPs." >&2
    fi

    # Traefik/uvicorn forwarded-allow setting (only relevant if you rely on uvicorn's proxy headers).
    local forwarded_allow
    forwarded_allow="$(read_env FORWARDED_ALLOW_IPS)"
    if [[ -n "$forwarded_allow" ]]; then
      local forwarded_norm
      forwarded_norm="$(printf '%s' "$forwarded_allow" | tr '[:upper:]' '[:lower:]')"
      if [[ "$forwarded_norm" == "*" ]]; then
        echo "FORWARDED_ALLOW_IPS must not be '*' in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
    fi

    local alembic_startup
    alembic_startup="$(read_env RUN_ALEMBIC_ON_STARTUP)"
    if [[ -n "$alembic_startup" ]]; then
      local alembic_norm
      alembic_norm="$(printf '%s' "$alembic_startup" | tr '[:upper:]' '[:lower:]')"
      case "$alembic_norm" in
        true|1|yes|on)
          echo "RUN_ALEMBIC_ON_STARTUP must be false in ${ENV_FILE_PATH}" >&2
          missing=1
          ;;
      esac
    fi

    local expose_codes
    expose_codes="$(read_env AUTH_EXPOSE_CODES)"
    if [[ -n "$expose_codes" ]]; then
      local expose_norm
      expose_norm="$(printf '%s' "$expose_codes" | tr '[:upper:]' '[:lower:]')"
      case "$expose_norm" in
        true|1|yes|on)
          echo "AUTH_EXPOSE_CODES must be false in ${ENV_FILE_PATH}" >&2
          missing=1
          ;;
      esac
    fi

    local base_domain
    base_domain="$(read_env BASE_DOMAIN)"
    if [[ -z "$base_domain" || "$base_domain" == "example.com" ]]; then
      echo "BASE_DOMAIN is unset or still example.com in ${ENV_FILE_PATH}" >&2
    fi

    if [[ -n "$trusted_proxies" ]]; then
      case "$trusted_proxies" in
        *"10.0.0.0/8"*|*"172.16.0.0/12"*|*"192.168.0.0/16"*)
          echo "Warning: TRUSTED_PROXY_CIDRS uses broad private ranges. Prefer narrow Docker network CIDR(s)." >&2
          echo "  Helper: ./scripts/ops.sh prod proxy-cidrs" >&2
          ;;
      esac
    fi

    if docker network inspect shamell_edge >/dev/null 2>&1; then
      local edge_subnets
      edge_subnets="$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' shamell_edge 2>/dev/null || true)"
      edge_subnets="$(printf '%s' "$edge_subnets" | tr ' ' '\n' | sed '/^$/d')"
      if [[ -n "$edge_subnets" ]]; then
        while IFS= read -r subnet; do
          subnet="$(printf '%s' "$subnet" | tr -d '[:space:]')"
          if [[ -z "$subnet" ]]; then
            continue
          fi
          if [[ -n "$trusted_proxies" && "$trusted_proxies" != *"$subnet"* ]]; then
            echo "Warning: TRUSTED_PROXY_CIDRS does not include shamell_edge subnet ${subnet}" >&2
          fi
          if [[ -n "$forwarded_allow" && "$forwarded_allow" != *"$subnet"* ]]; then
            echo "Warning: FORWARDED_ALLOW_IPS does not include shamell_edge subnet ${subnet}" >&2
          fi
        done <<<"$edge_subnets"
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
  local local_domain=0
  if [[ "$ENV_NAME" == "prod" ]]; then
    local base_domain="${BASE_DOMAIN:-$(read_env BASE_DOMAIN)}"
    if [[ -n "$base_domain" ]]; then
      if [[ "$base_domain" == "local.test" || "$base_domain" == *.local.test ]]; then
        url="https://api.${base_domain}/health"
        if [[ -z "${HEALTH_RESOLVE:-}" ]]; then
          curl_args+=(--resolve "api.${base_domain}:443:127.0.0.1")
        fi
        if [[ -z "${HEALTH_INSECURE:-}" ]]; then
          curl_args+=(-k)
        fi
        local_domain=1
      else
        url="https://api.${base_domain}/health"
      fi
    else
      url="http://localhost:8080/health"
    fi
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

  if [[ "$local_domain" == "1" && "${HEALTH_FALLBACK:-1}" == "1" ]]; then
    echo "Health check via Traefik failed; falling back to monolith exec." >&2
    local host_header="api.${base_domain}"
    compose exec -T monolith python -c \
      "import urllib.request; req=urllib.request.Request('http://127.0.0.1:8080/health', headers={'Host': '${host_header}'}); print(urllib.request.urlopen(req, timeout=3).read().decode())"
    return $?
  fi
  return 1
}

metrics_scrapers() {
  if [[ "$ENV_NAME" != "prod" ]]; then
    echo "metrics-scrapers is only available for prod (Traefik) env." >&2
    exit 1
  fi
  local traefik_id
  traefik_id="$(compose ps -q traefik 2>/dev/null || true)"
  if [[ -z "$traefik_id" ]]; then
    echo "Traefik container not found. Run: scripts/ops.sh ${ENV_NAME} up" >&2
    exit 1
  fi
  local enabled="${TRAEFIK_ACCESSLOG:-$(read_env TRAEFIK_ACCESSLOG)}"
  enabled="$(echo "${enabled:-}" | tr '[:upper:]' '[:lower:]')"
  if [[ "$enabled" != "true" && "$enabled" != "1" ]]; then
    echo "TRAEFIK_ACCESSLOG is disabled. To discover scrapers:" >&2
    echo "  1) Set TRAEFIK_ACCESSLOG=true in ${ENV_FILE_PATH}" >&2
    echo "  2) Restart: docker compose -f ${COMPOSE_FILE} --env-file ${ENV_FILE_PATH} up -d traefik" >&2
    echo "  3) Wait for a scrape, then re-run this command." >&2
  fi
  echo "Observed /metrics client IPs (Traefik access log):"
  local ips
  ips="$(
    docker logs "$traefik_id" 2>/dev/null \
      | grep -F '"RequestPath":"/metrics"' \
      | sed -n 's/.*"ClientAddr":"\([^"]*\)".*/\1/p' \
      | awk '
          {
            addr=$0
            if (addr ~ /^\[/) {
              sub(/^\[/, "", addr)
              sub(/\].*$/, "", addr)
              print addr
              next
            }
            if (addr ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:/) {
              sub(/:.*/, "", addr)
              print addr
              next
            }
            print addr
          }
        ' \
      | sort -u
  )"
  if [[ -z "$ips" ]]; then
    echo "  (no /metrics access log entries found yet)" >&2
    echo >&2
    echo "If you run the recommended local Prometheus scrape (Docker internal)," >&2
    echo "there is no public /metrics route and this command will stay empty." >&2
    echo "To enable `metrics.<BASE_DOMAIN>`, use:" >&2
    echo "  docker compose -f ${COMPOSE_FILE} -f ${APP_DIR}/ops/production/docker-compose.metrics-public.yml --env-file ${ENV_FILE_PATH} up -d" >&2
    exit 1
  fi
  echo "$ips"
  echo
  echo "Suggested PROMETHEUS_ALLOWED_CIDRS:"
  echo "$ips" | while IFS= read -r ip; do
    ip="$(echo "$ip" | tr -d '[:space:]')"
    if [[ -z "$ip" ]]; then
      continue
    fi
    if [[ "$ip" == *:* ]]; then
      echo "  ${ip}/128"
    else
      echo "  ${ip}/32"
    fi
  done
}

bootstrap_media_perms() {
  if [[ "$ENV_NAME" != "prod" && "$ENV_NAME" != "pi" && "$ENV_NAME" != "dev" && "$ENV_NAME" != "devmono" ]]; then
    echo "bootstrap-media-perms is only available for dev/devmono/prod/pi env." >&2
    exit 1
  fi

  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "Ensuring dev service volumes have safe ownership ..."
    compose run --rm --no-deps bootstrap-perms
    return 0
  fi

  local svc="monolith"
  local uid gid
  uid="${MONOLITH_UID:-$(read_env MONOLITH_UID)}"
  gid="${MONOLITH_GID:-$(read_env MONOLITH_GID)}"
  uid="${uid:-10001}"
  gid="${gid:-10001}"
  local targets=("/data/chat_media" "/data/moments_media")
  if [[ "$ENV_NAME" == "devmono" ]]; then
    targets=("/data" "/data/chat_media" "/data/moments_media")
  fi
  echo "Ensuring media volumes are owned by ${uid}:${gid} ..."
  compose run --rm --no-deps --build --user 0:0 \
    --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
    "$svc" sh -ceu "
    uid='${uid}'; gid='${gid}';
    for d in ${targets[*]}; do
      if [ ! -d \"\$d\" ]; then
        echo \"Missing directory: \$d\" >&2
        exit 1
      fi
      owner=\$(stat -c '%u:%g' \"\$d\" 2>/dev/null || true)
      if [ \"\$owner\" = \"\${uid}:\${gid}\" ]; then
        continue
      fi
      echo \"Fixing ownership: \$d -> \${uid}:\${gid} (was \$owner)\" >&2
      chown -R \"\${uid}:\${gid}\" \"\$d\"
    done
  "
}

proxy_cidrs() {
  if [[ "$ENV_NAME" != "prod" ]]; then
    echo "proxy-cidrs is only available for prod (Traefik) env." >&2
    exit 1
  fi
  local traefik_id
  traefik_id="$(compose ps -q traefik 2>/dev/null || true)"
  local monolith_id
  monolith_id="$(compose ps -q monolith 2>/dev/null || true)"
  if [[ -z "$traefik_id" || -z "$monolith_id" ]]; then
    echo "Required containers not found. Run: scripts/ops.sh ${ENV_NAME} up" >&2
    exit 1
  fi
  python3 - <<'PY' "$traefik_id" "$monolith_id"
import json
import subprocess
import sys

traefik_id = sys.argv[1]
monolith_id = sys.argv[2]

def _inspect(cid: str) -> dict:
    out = subprocess.check_output(["docker", "inspect", cid], text=True)
    rows = json.loads(out)
    return rows[0] if rows else {}

def _nets(obj: dict) -> set[str]:
    ns = (obj.get("NetworkSettings") or {}).get("Networks") or {}
    if isinstance(ns, dict):
        return set(ns.keys())
    return set()

t = _inspect(traefik_id)
m = _inspect(monolith_id)
shared = sorted(_nets(t) & _nets(m))
if not shared:
    print("No shared Docker networks found between traefik and monolith.")
    sys.exit(2)

cidrs: list[str] = []
details: list[tuple[str, str]] = []
for net in shared:
    out = subprocess.check_output(["docker", "network", "inspect", net], text=True)
    rows = json.loads(out)
    obj = rows[0] if rows else {}
    configs = ((obj.get("IPAM") or {}).get("Config") or [])
    subnets: list[str] = []
    for cfg in configs:
        if isinstance(cfg, dict):
            s = (cfg.get("Subnet") or "").strip()
            if s:
                subnets.append(s)
                cidrs.append(s)
    details.append((net, ", ".join(subnets) if subnets else "(no subnet)"))

cidrs = sorted({c for c in cidrs if c})
print("Shared Docker networks (traefik <-> monolith):")
for net, subnet in details:
    print(f"  - {net}: {subnet}")
print()
if not cidrs:
    print("No CIDRs detected for the shared network(s).")
    sys.exit(3)
joined = ",".join(cidrs)
print("Suggested values (narrower than private-range defaults):")
print(f"  TRUSTED_PROXY_CIDRS={joined}")
print(f"  FORWARDED_ALLOW_IPS=127.0.0.1,{joined}")
print()
print("Note: this trusts forwarded headers from any container on the shared network(s).")
PY
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
  shopt -s nullglob
  files=("${backup_dir}"/${pattern})
  shopt -u nullglob
  if (( ${#files[@]} <= keep )); then
    return 0
  fi
  local sorted=()
  IFS=$'\n' sorted=($(printf '%s\n' "${files[@]}" | sort -r))
  local idx
  for ((idx=keep; idx<${#sorted[@]}; idx++)); do
    rm -f "${sorted[idx]}"
    echo "Pruned: ${sorted[idx]}"
  done
}

backup() {
  local backup_dir="${BACKUP_DIR:-${APP_DIR}/backups}"
  mkdir -p "$backup_dir"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  if [[ "$ENV_NAME" == "dev" ]]; then
    local core_out="${backup_dir}/dev-core-data-${ts}.tar.gz"
    local chat_out="${backup_dir}/dev-chat-data-${ts}.tar.gz"
    local payments_out="${backup_dir}/dev-payments-data-${ts}.tar.gz"
    local media_out="${backup_dir}/dev-media-data-${ts}.tar.gz"
    compose run --rm --no-deps bff sh -c "tar -czf - -C /data ." >"$core_out"
    compose run --rm --no-deps chat sh -c "tar -czf - -C /data ." >"$chat_out"
    compose run --rm --no-deps payments sh -c "tar -czf - -C /data ." >"$payments_out"
    compose run --rm --no-deps bff sh -c "tar -czf - -C /data chat_media moments_media" >"$media_out"
    echo "Backups written:"
    echo "  ${core_out}"
    echo "  ${chat_out}"
    echo "  ${payments_out}"
    echo "  ${media_out}"
    prune_backups "$backup_dir" "dev-core-data-*.tar.gz"
    prune_backups "$backup_dir" "dev-chat-data-*.tar.gz"
    prune_backups "$backup_dir" "dev-payments-data-*.tar.gz"
    prune_backups "$backup_dir" "dev-media-data-*.tar.gz"
    return 0
  fi
  if [[ "$ENV_NAME" == "devmono" ]]; then
    local out="${backup_dir}/devmono-monolith-data-${ts}.tar.gz"
    compose run --rm --no-deps monolith sh -c "tar -czf - -C /data ." >"$out"
    echo "Backup written: ${out}"
    prune_backups "$backup_dir" "devmono-monolith-data-*.tar.gz"
    return 0
  fi

  local user="${POSTGRES_USER:-$(read_env POSTGRES_USER)}"
  local password="${POSTGRES_PASSWORD:-$(read_env POSTGRES_PASSWORD)}"
  local db="${POSTGRES_DB:-$(read_env POSTGRES_DB)}"
  if [[ -z "$user" || -z "$password" || -z "$db" ]]; then
    echo "Missing POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_DB for backup." >&2
    exit 1
  fi
  local out="${backup_dir}/${ENV_NAME}-db-${ts}.sql.gz"
  require_cmd gzip
  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$db" | gzip >"$out"
  echo "Backup written: ${out}"
  prune_backups "$backup_dir" "${ENV_NAME}-db-*.sql.gz"

  if [[ "${BACKUP_MEDIA:-0}" == "1" ]]; then
    local media_out="${backup_dir}/${ENV_NAME}-media-${ts}.tar.gz"
    compose exec -T monolith sh -c "tar -czf - -C /data chat_media moments_media" >"$media_out"
    echo "Media backup written: ${media_out}"
    prune_backups "$backup_dir" "${ENV_NAME}-media-*.tar.gz"
  fi
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

  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "Dev microservices restore is intentionally disabled to avoid partial-data corruption." >&2
    echo "Use devmono restore or restore service backups manually (core/chat/payments/media)." >&2
    exit 1
  fi

  if [[ "$ENV_NAME" == "devmono" ]]; then
    case "$backup_file" in
      *.tar.gz|*.tgz)
        ;;
      *)
        echo "Dev monolith restore expects a .tar.gz backup from ./scripts/ops.sh devmono backup" >&2
        exit 1
        ;;
    esac
    local running
    running="$(compose ps -q monolith || true)"
    if [[ -n "$running" && "${ALLOW_RUNNING_RESTORE:-0}" != "1" ]]; then
      echo "Monolith is running. Stop it or set ALLOW_RUNNING_RESTORE=1 to proceed." >&2
      exit 1
    fi
    compose run --rm --no-deps monolith sh -c "rm -rf /data/* && tar -xzf - -C /data" <"$backup_file"
    echo "Restore complete: ${backup_file}"
    return 0
  fi

  local user="${POSTGRES_USER:-$(read_env POSTGRES_USER)}"
  local password="${POSTGRES_PASSWORD:-$(read_env POSTGRES_PASSWORD)}"
  local db="${POSTGRES_DB:-$(read_env POSTGRES_DB)}"
  if [[ -z "$user" || -z "$password" || -z "$db" ]]; then
    echo "Missing POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_DB for restore." >&2
    exit 1
  fi

  if [[ "${RESTORE_DROP_SCHEMA:-0}" == "1" ]]; then
    compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$db" -v ON_ERROR_STOP=1 \
      -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
  fi

  if [[ "$backup_file" == *.gz ]]; then
    require_cmd gzip
    gzip -dc "$backup_file" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$db" -v ON_ERROR_STOP=1
  else
    cat "$backup_file" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$db" -v ON_ERROR_STOP=1
  fi
  echo "Restore complete: ${backup_file}"
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
    echo "df not available."
  fi
  echo
  echo "==> backups"
  if [[ -d "$backup_dir" ]]; then
    ls -lt "$backup_dir" | head -n 20
  else
    echo "No backups directory at ${backup_dir}"
  fi
}

migrate_core() {
  if [[ "$ENV_NAME" == "dev" || "$ENV_NAME" == "devmono" ]]; then
    echo "${ENV_NAME} uses sqlite auto-create; migrations are optional."
    return 0
  fi
  # This repo layout does not ship a separate "core" Alembic config.
  # Payments migrations are handled in migrate_payments().
  echo "core migrations: no-op (not configured in this repository layout)"
}

migrate_payments() {
  if [[ "$ENV_NAME" == "dev" || "$ENV_NAME" == "devmono" ]]; then
    echo "${ENV_NAME} uses sqlite auto-create; migrations are optional."
    return 0
  fi
  compose run --rm monolith alembic -c /app/apps/payments/alembic.ini upgrade head
}

migrate() {
  if [[ "$ENV_NAME" == "dev" || "$ENV_NAME" == "devmono" ]]; then
    echo "${ENV_NAME} uses sqlite auto-create; migrations are optional."
    return 0
  fi
  migrate_core
  migrate_payments
}

deploy() {
  if [[ "$ENV_NAME" != "dev" && "$ENV_NAME" != "devmono" ]]; then
    check_env
  fi
  if [[ "$ENV_NAME" == "prod" || "$ENV_NAME" == "pi" || "$ENV_NAME" == "devmono" ]]; then
    bootstrap_media_perms
  fi
  compose up -d --build
  if [[ "$ENV_NAME" != "dev" ]]; then
    migrate
  fi
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
    if [[ "$ENV_NAME" == "dev" || "$ENV_NAME" == "devmono" ]]; then
      bootstrap_media_perms
    fi
    compose up -d --build "$@"
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
  proxy-cidrs)
    proxy_cidrs
    ;;
  metrics-scrapers)
    metrics_scrapers
    ;;
  bootstrap-media-perms)
    bootstrap_media_perms
    ;;
  report)
    report
    ;;
  build)
    compose build "$@"
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
  migrate-core)
    migrate_core
    ;;
  migrate-payments)
    migrate_payments
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
