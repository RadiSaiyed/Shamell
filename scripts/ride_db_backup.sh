#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/ops/pi/docker-compose.postgres.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/ops/pi/.env}"
OUTPUT_DIR="${RIDE_DB_BACKUP_OUTPUT_DIR:-${ROOT_DIR}/.backups/ride-db}"
RETENTION_DAYS="${RIDE_DB_BACKUP_RETENTION_DAYS:-30}"
ENCRYPTION_MODE="${RIDE_DB_BACKUP_ENCRYPTION_MODE:-age}"
AGE_RECIPIENT="${RIDE_DB_BACKUP_AGE_RECIPIENT:-}"
GPG_RECIPIENT="${RIDE_DB_BACKUP_GPG_RECIPIENT:-}"
PG_DUMP_FORMAT="${RIDE_DB_BACKUP_PG_DUMP_FORMAT:-custom}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ride-db-backup: missing required command: $1" >&2
    exit 1
  }
}

read_env() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi
  local value
  value="$(awk -F= -v k="$key" '$1==k{v=substr($0, index($0,$2))} END{print v}' "$ENV_FILE")"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

db_name_from_url() {
  local url="$1"
  local db_name="${url##*/}"
  db_name="${db_name%%\?*}"
  printf '%s' "$db_name"
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$path" | awk '{print $1}'
}

encrypt_backup() {
  local input="$1"
  local output="$2"
  case "$ENCRYPTION_MODE" in
    age)
      require_cmd age
      if [[ -z "$AGE_RECIPIENT" ]]; then
        echo "ride-db-backup: RIDE_DB_BACKUP_AGE_RECIPIENT must be set when encryption mode is age" >&2
        exit 1
      fi
      age -r "$AGE_RECIPIENT" -o "$output" "$input"
      ;;
    gpg)
      require_cmd gpg
      if [[ -z "$GPG_RECIPIENT" ]]; then
        echo "ride-db-backup: RIDE_DB_BACKUP_GPG_RECIPIENT must be set when encryption mode is gpg" >&2
        exit 1
      fi
      gpg --batch --yes --trust-model always --recipient "$GPG_RECIPIENT" --output "$output" --encrypt "$input"
      ;;
    *)
      echo "ride-db-backup: unsupported encryption mode: ${ENCRYPTION_MODE}" >&2
      echo "ride-db-backup: supported modes are: age, gpg" >&2
      exit 1
      ;;
  esac
}

rotate_backups() {
  local retention_expr
  retention_expr="+$((RETENTION_DAYS - 1))"
  find "$OUTPUT_DIR" -type f \( -name '*.manifest.json' -o -name '*.age' -o -name '*.gpg' -o -name '*.dump' \) -mtime "$retention_expr" -delete
}

require_cmd docker
require_cmd awk
require_cmd date
require_cmd find
require_cmd mktemp
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "ride-db-backup: missing required command: sha256sum or shasum" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ride-db-backup: env file not found: ${ENV_FILE}" >&2
  exit 1
fi
if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || (( RETENTION_DAYS < 1 )); then
  echo "ride-db-backup: RIDE_DB_BACKUP_RETENTION_DAYS must be a positive integer" >&2
  exit 1
fi
if [[ "$PG_DUMP_FORMAT" != "custom" && "$PG_DUMP_FORMAT" != "plain" ]]; then
  echo "ride-db-backup: RIDE_DB_BACKUP_PG_DUMP_FORMAT must be custom or plain" >&2
  exit 1
fi

PG_USER="$(read_env POSTGRES_USER)"
PG_PASSWORD="$(read_env POSTGRES_PASSWORD)"
DB_URL="$(read_env DB_URL)"

if [[ -z "$PG_USER" || -z "$PG_PASSWORD" || -z "$DB_URL" ]]; then
  echo "ride-db-backup: expected POSTGRES_USER, POSTGRES_PASSWORD, and DB_URL in ${ENV_FILE}" >&2
  exit 1
fi

DB_NAME="$(db_name_from_url "$DB_URL")"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EXTENSION=".dump"
if [[ "$ENCRYPTION_MODE" == "age" ]]; then
  EXTENSION=".dump.age"
elif [[ "$ENCRYPTION_MODE" == "gpg" ]]; then
  EXTENSION=".dump.gpg"
fi

mkdir -p "$OUTPUT_DIR"
umask 077
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

raw_dump="${tmp_dir}/ride-db-${TIMESTAMP}.dump"
encrypted_dump="${OUTPUT_DIR}/ride-db-${TIMESTAMP}${EXTENSION}"
manifest="${OUTPUT_DIR}/ride-db-${TIMESTAMP}.manifest.json"

pg_dump_args=(pg_dump -U "$PG_USER" -d "$DB_NAME" --no-owner --no-privileges)
if [[ "$PG_DUMP_FORMAT" == "custom" ]]; then
  pg_dump_args+=(--format=custom)
fi

compose exec -T -e "PGPASSWORD=${PG_PASSWORD}" db "${pg_dump_args[@]}" >"$raw_dump"
encrypt_backup "$raw_dump" "$encrypted_dump"

archive_sha256="$(sha256_file "$encrypted_dump")"
cat >"$manifest" <<EOF
{
  "database": "${DB_NAME}",
  "created_at_utc": "${TIMESTAMP}",
  "encryption_mode": "${ENCRYPTION_MODE}",
  "retention_days": ${RETENTION_DAYS},
  "artifact_file": "$(basename "$encrypted_dump")",
  "artifact_sha256": "${archive_sha256}"
}
EOF

rotate_backups

echo "ride-db-backup: ok database=${DB_NAME} artifact=$(basename "$encrypted_dump") retention_days=${RETENTION_DAYS} encryption=${ENCRYPTION_MODE}"
