#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/ops/pi/docker-compose.postgres.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/ops/pi/.env}"
DRIVER_PRESENCE_STALE_SECS="${RIDE_REPORT_DRIVER_PRESENCE_STALE_SECS:-45}"
TARGET_DRIVER_ACCOUNT_ID="${RIDE_REPAIR_DRIVER_ACCOUNT_ID:-}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: repair_ride_stale_presence.sh [--dry-run] [--driver-account-id <account_id>]

Repairs stale online ride-driver presence rows by:
- setting matching auth_ride_driver_presence rows to offline
- cancelling pending auth_ride_dispatch_offers for those drivers

Environment:
  COMPOSE_FILE                       docker compose file (default: ops/pi/docker-compose.postgres.yml)
  ENV_FILE                           env file with DB_URL/POSTGRES creds (default: ops/pi/.env)
  RIDE_REPORT_DRIVER_PRESENCE_STALE_SECS
                                     stale threshold in seconds (default: 45)
  RIDE_REPAIR_DRIVER_ACCOUNT_ID      optional account filter
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --driver-account-id)
      TARGET_DRIVER_ACCOUNT_ID="${2:-}"
      if [[ -z "$TARGET_DRIVER_ACCOUNT_ID" ]]; then
        echo "repair-ride-stale-presence: --driver-account-id requires a value." >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "repair-ride-stale-presence: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "repair-ride-stale-presence: missing required command: $1" >&2
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

psql_query() {
  local db_name="$1"
  local sql="$2"
  local pg_user="$3"
  local pg_password="$4"
  compose exec -T -e "PGPASSWORD=${pg_password}" db \
    psql -v ON_ERROR_STOP=1 -U "$pg_user" -d "$db_name" -AtF '|' -c "$sql"
}

require_cmd docker
require_cmd awk

if [[ ! -f "$ENV_FILE" ]]; then
  echo "repair-ride-stale-presence: env file not found: ${ENV_FILE}" >&2
  exit 1
fi
if ! [[ "$DRIVER_PRESENCE_STALE_SECS" =~ ^[0-9]+$ ]]; then
  echo "repair-ride-stale-presence: stale threshold must be numeric." >&2
  exit 1
fi

PG_USER="$(read_env POSTGRES_USER)"
PG_PASSWORD="$(read_env POSTGRES_PASSWORD)"
AUTH_DB_URL="$(read_env DB_URL)"
if [[ -z "$PG_USER" || -z "$PG_PASSWORD" || -z "$AUTH_DB_URL" ]]; then
  echo "repair-ride-stale-presence: expected POSTGRES_USER, POSTGRES_PASSWORD, and DB_URL in ${ENV_FILE}" >&2
  exit 1
fi
AUTH_DB_NAME="$(db_name_from_url "$AUTH_DB_URL")"

driver_filter_sql="TRUE"
if [[ -n "$TARGET_DRIVER_ACCOUNT_ID" ]]; then
  driver_filter_sql="driver_account_id = '${TARGET_DRIVER_ACCOUNT_ID}'"
fi

stale_rows_sql="$(cat <<SQL
select driver_account_id || '|' || extract(epoch from (now() - last_seen_at))::bigint
from auth_ride_driver_presence
where availability_status = 'online'
  and last_seen_at < now() - make_interval(secs => ${DRIVER_PRESENCE_STALE_SECS})
  and ${driver_filter_sql}
order by last_seen_at asc;
SQL
)"

stale_rows_file="$(mktemp)"
repair_rows_file="$(mktemp)"
cleanup_tmp() {
  rm -f "$stale_rows_file" "$repair_rows_file"
}
trap cleanup_tmp EXIT

psql_query "$AUTH_DB_NAME" "$stale_rows_sql" "$PG_USER" "$PG_PASSWORD" > "$stale_rows_file"
stale_count="$(grep -c '.' "$stale_rows_file" || true)"

printf 'repair-ride-stale-presence: auth_db=%s threshold=%ss dry_run=%s\n' \
  "$AUTH_DB_NAME" \
  "$DRIVER_PRESENCE_STALE_SECS" \
  "$DRY_RUN"
if [[ -n "$TARGET_DRIVER_ACCOUNT_ID" ]]; then
  printf 'repair-ride-stale-presence: target_driver_account_id=%s\n' "$TARGET_DRIVER_ACCOUNT_ID"
fi

if (( stale_count == 0 )); then
  echo "repair-ride-stale-presence: no stale online driver presence rows found."
  exit 0
fi

printf '\n[stale_presence_details driver_account_id|age_seconds]\n'
cat "$stale_rows_file"

if (( DRY_RUN == 1 )); then
  echo
  echo "repair-ride-stale-presence: dry run only; no rows mutated."
  exit 0
fi

repair_sql="$(cat <<SQL
WITH stale AS (
  SELECT driver_account_id
  FROM auth_ride_driver_presence
  WHERE availability_status = 'online'
    AND last_seen_at < now() - make_interval(secs => ${DRIVER_PRESENCE_STALE_SECS})
    AND ${driver_filter_sql}
),
presence_updated AS (
  UPDATE auth_ride_driver_presence presence
  SET
    availability_status = 'offline',
    updated_at = NOW()
  FROM stale
  WHERE presence.driver_account_id = stale.driver_account_id
  RETURNING presence.driver_account_id
),
offers_updated AS (
  UPDATE auth_ride_dispatch_offers offers
  SET
    status = 'cancelled',
    response_reason = COALESCE(offers.response_reason, 'driver_presence_stale'),
    responded_at = COALESCE(offers.responded_at, NOW()),
    updated_at = NOW()
  WHERE offers.status = 'pending'
    AND offers.driver_account_id IN (
      SELECT driver_account_id
      FROM stale
    )
  RETURNING offers.driver_account_id
)
SELECT 'presence_rows_repaired', count(*)::bigint FROM presence_updated
UNION ALL
SELECT 'pending_offers_cancelled', count(*)::bigint FROM offers_updated;
SQL
)"

psql_query "$AUTH_DB_NAME" "$repair_sql" "$PG_USER" "$PG_PASSWORD" > "$repair_rows_file"

printf '\n[repair_summary metric|count]\n'
cat "$repair_rows_file"

post_check_sql="$(cat <<SQL
select count(*)::bigint
from auth_ride_driver_presence
where availability_status = 'online'
  and last_seen_at < now() - make_interval(secs => ${DRIVER_PRESENCE_STALE_SECS})
  and ${driver_filter_sql};
SQL
)"
remaining="$(psql_query "$AUTH_DB_NAME" "$post_check_sql" "$PG_USER" "$PG_PASSWORD" | tr -d '[:space:]')"
printf '\nrepair-ride-stale-presence: remaining_stale_online_presence=%s\n' "$remaining"
